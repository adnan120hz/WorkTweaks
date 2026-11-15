import SwiftUI

/// The five main tabs, Sandbox first: it is the app's front door
/// (it holds the "Start Tweaks Feature" master switch). RootView
/// owns the selection so other views (e.g. the locked Tweaks tab)
/// can ask to jump to a specific tab.
enum AppTab: Hashable {
    case sandbox, tweaks, extra, backup, log
}

struct RootView: View {
    @StateObject private var console = Console()
    @StateObject private var gestalt = GestaltManager.shared
    @StateObject private var respringCenter = RespringCenter.shared
    /// Persists across launches: the v2.0 Welcome is shown only
    /// until the user taps "Get Started" once (and again only after
    /// a reinstall, which wipes the app's defaults). A new key for
    /// v2.0, so everyone sees the new Welcome once after updating.
    @AppStorage("wt.welcomeV2Seen") private var welcomeSeen = false
    /// Sileo UI (the whole-app restyle) is read here too, so the
    /// root can swap the TabView for the Sileo shell. Same key
    /// the Sandbox picker writes.
    @AppStorage("wt.tweaksUIVersion") private var uiVersionRaw = "sileo"
    @State private var selectedTab: AppTab = .sandbox

    private var useSileoUI: Bool { uiVersionRaw == "sileo" }

    var body: some View {
        Group {
            if !welcomeSeen {
                // 1. Welcome gate (first launch of v2.0).
                WelcomeView { welcomeSeen = true }
            } else if SupportInfo.isSupported {
                // 2. Supported build → the app itself. Sileo UI
                // restyles the whole app (floating pill tab bar
                // + dark menus); New/Old UI keep the standard
                // TabView with the Tweaks tab in that layout.
                Group {
                    if useSileoUI {
                        SileoShell(console: console, manager: gestalt)
                    } else {
                        tabView
                    }
                }
                .onAppear {
                    console.start()
                    gestalt.load()
                }
            } else {
                // 3. Unsupported build → no tab UI, ever.
                UnsupportedView()
            }
        }
        .tint(Color("AccentColor"))
        // mond: root overlay presenting the respring web view.
        .overlay {
            if respringCenter.show {
                ZStack {
                    RespringView()
                        .brightness(-1.0)
                        .ignoresSafeArea()

                    if respringCenter.canDismiss {
                        VStack {
                            Spacer()
                            Text("Respring did not trigger on this device.")
                                .font(.footnote)
                                .foregroundStyle(.white)
                            Button("Close — reboot manually instead") {
                                respringCenter.dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
        }
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            SandboxView(console: console)
                .tabItem { Label("Sandbox", systemImage: "shippingbox") }
                .tag(AppTab.sandbox)

            TweaksView(console: console, manager: gestalt,
                       onOpenSandbox: { selectedTab = .sandbox },
                       onOpenExtra: { selectedTab = .extra },
                       onOpenBackup: { selectedTab = .backup })
                .tabItem { Label("Tweaks", systemImage: "slider.horizontal.3") }
                .tag(AppTab.tweaks)

            CacheExtraView(manager: gestalt)
                .tabItem { Label("Extra", systemImage: "key") }
                .tag(AppTab.extra)

            BackupView(manager: gestalt)
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.timemachine") }
                .tag(AppTab.backup)

            LogView(console: console)
                .tabItem { Label("Log", systemImage: "terminal") }
                .tag(AppTab.log)
        }
        .onChange(of: selectedTab) { _, _ in
            SoundEffects.playSwipe()
        }
    }
}
