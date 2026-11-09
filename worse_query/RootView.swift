import SwiftUI

struct RootView: View {
    @StateObject private var console = Console()
    @StateObject private var gestalt = GestaltManager.shared
    @StateObject private var respringCenter = RespringCenter.shared
    @State private var showIntro = true

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
        // Perkenalan: intro with developer + license credits, shown
        // when the app opens (once per process launch).
        .fullScreenCover(isPresented: $showIntro) {
            IntroView()
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
