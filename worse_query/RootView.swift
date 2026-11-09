import SwiftUI

struct RootView: View {
    @StateObject private var console = Console()
    @StateObject private var gestalt = GestaltManager.shared
    @StateObject private var respringCenter = RespringCenter.shared
    /// Persists across launches: the intro is shown only until the
    /// user taps "Get Started" once (and again only after a reinstall,
    /// which wipes the app's defaults).
    @AppStorage("wt.introSeen") private var introSeen = false

    var body: some View {
        TabView {
            TweaksView(console: console, manager: gestalt)
                .tabItem { Label("Tweaks", systemImage: "slider.horizontal.3") }

            CacheExtraView(manager: gestalt)
                .tabItem { Label("Extra", systemImage: "key") }

            ResolutionView(manager: gestalt)
                .tabItem { Label("Resolution", systemImage: "aspectratio") }

            BackupView(manager: gestalt)
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.timemachine") }

            SandboxView(console: console)
                .tabItem { Label("Sandbox", systemImage: "shippingbox") }

            LogView(console: console)
                .tabItem { Label("Log", systemImage: "terminal") }
        }
        .tint(Color("AccentColor"))
        .onAppear {
            console.start()
            gestalt.load()
        }
        // First-launch intro (developer + credits + compatibility):
        // presented only while `introSeen` is false; tapping
        // "Get Started" sets it once and for all on this install.
        .fullScreenCover(isPresented: Binding(
            get: { !introSeen },
            set: { presented in if !presented { introSeen = true } }
        )) {
            IntroView { introSeen = true }
        }
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
}
