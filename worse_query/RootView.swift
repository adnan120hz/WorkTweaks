import SwiftUI

struct RootView: View {
    @StateObject private var console = Console()
    @StateObject private var gestalt = GestaltManager.shared

    var body: some View {
        TabView {
            TweaksView(console: console, manager: gestalt)
                .tabItem { Label("Tweaks", systemImage: "slider.horizontal.3") }

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
    }
}
