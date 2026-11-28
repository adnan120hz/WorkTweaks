import SwiftUI

/// The five main tabs, Sandbox first: it is the app's front door
/// (it holds the "Start Tweaks Feature" master switch). RootView
/// owns the selection so other views (e.g. the locked Tweaks tab)
/// can ask to jump to a specific tab. Exactly five tabs, so iOS
/// never builds a "More" tab.
enum AppTab: Hashable {
    case sandbox, tweaks, extra, backup, log
}

struct RootView: View {
    @StateObject private var console = Console()
    @StateObject private var gestalt = GestaltManager.shared
    @StateObject private var respringCenter = RespringCenter.shared
    /// Language store (v7.0): drives the flag theme and every
    /// translated string. Shared singleton, also injected into
    /// the environment by WorkTweaksApp.
    @StateObject private var langStore = WTLangStore.shared
    /// Persists across launches: the v2.0 Welcome is shown only
    /// until the user taps "Get Started" once (and again only after
    /// a reinstall, which wipes the app's defaults). A new key for
    /// v2.0, so everyone sees the new Welcome once after updating.
    @AppStorage("wt.welcomeV2Seen") private var welcomeSeen = false
    @State private var selectedTab: AppTab = .sandbox

    var body: some View {
        Group {
            if !welcomeSeen {
                // 1. Welcome gate (first launch of v2.0).
                WelcomeView { welcomeSeen = true }
            } else if SupportInfo.isSupported {
                // 2. Supported build → the app itself.
                tabView
            } else {
                // 3. Unsupported build → no tab UI, ever.
                UnsupportedView()
            }
        }
        // The tint follows the selected language's theme
        // color (blue for English, red for Indonesian/
        // Chinese/Vietnamese, dark blue for Russian) — it
        // drives toggles, the selected tab, the segmented
        // picker and links app-wide.
        .tint(langStore.theme.accent)
        .environmentObject(langStore)
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
                            Text(langStore.tr("Respring did not trigger on this device."))
                                .font(.footnote)
                                .foregroundStyle(.white)
                            Button(langStore.tr("Close — reboot manually instead")) {
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
                .tabItem {
                    Label {
                        Text("Sandbox")
                    } icon: {
                        Image(systemName: "shippingbox")
                            .wtIconCornerMascots(size: 10)
                    }
                }
                .tag(AppTab.sandbox)

            TweaksView(console: console, manager: gestalt,
                       onOpenSandbox: { selectedTab = .sandbox },
                       onOpenExtra: { selectedTab = .extra },
                       onOpenBackup: { selectedTab = .backup })
                .tabItem {
                    Label {
                        Text("Tweaks")
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                            .wtIconCornerMascots(size: 10)
                    }
                }
                .tag(AppTab.tweaks)

            CacheExtraView(manager: gestalt)
                .tabItem {
                    Label {
                        Text(langStore.tr("Extra"))
                    } icon: {
                        Image(systemName: "key")
                            .wtIconCornerMascots(size: 10)
                    }
                }
                .tag(AppTab.extra)

            BackupView(manager: gestalt)
                .tabItem {
                    Label {
                        Text(langStore.tr("Backup"))
                    } icon: {
                        Image(systemName: "externaldrive.badge.timemachine")
                            .wtIconCornerMascots(size: 10)
                    }
                }
                .tag(AppTab.backup)

            LogView(console: console)
                .tabItem {
                    Label {
                        Text("Log")
                    } icon: {
                        Image(systemName: "terminal")
                            .wtIconCornerMascots(size: 10)
                    }
                }
                .tag(AppTab.log)
        }
        .onChange(of: selectedTab) { _, _ in
            SoundEffects.playSwipe()
        }
        // Tab switches animate (v8.0 menu motion).
        .animation(.wtMenu, value: selectedTab)
        .onAppear {
            console.start()
            gestalt.load()
        }
    }
}
