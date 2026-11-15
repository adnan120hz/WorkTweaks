import SwiftUI
import Combine

/// Shared state of the Sileo shell: which tab is selected,
/// whether the tweaks search cover is open, and whether the
/// avatar's settings sheet is open. Owned by SileoShell and
/// passed down through the environment — the search cover and
/// the avatar (on the Featured tab) read it, so there is
/// exactly one search cover and one settings sheet for the
/// whole app.
final class SileoShellState: ObservableObject {
    @Published var selectedTab: SileoTab = .featured
    @Published var searchActive = false
    @Published var settingsActive = false
}

/// The tabs: Featured (our tweaks) and the tools the user
/// opens most — App Data, PosterBoard, the Cache Cleaner, and
/// Backup. News (changelog) and Sources (GitHub) live in the
/// avatar's settings sheet instead.
enum SileoTab: String, CaseIterable {
    case featured, appData, posterBoard, cacheCleaner, backup

    var title: String {
        switch self {
        case .featured: "Featured"
        case .appData: "App Data"
        case .posterBoard: "PosterBoard"
        case .cacheCleaner: "Cache Cleaner"
        case .backup: "Backup"
        }
    }

    var icon: String {
        switch self {
        case .featured: "star.fill"
        case .appData: "folder.fill"
        case .posterBoard: "photo.fill"
        case .cacheCleaner: "trash.fill"
        case .backup: "externaldrive.fill"
        }
    }
}

/// The whole app in Sileo UI: the five tabs in a native
/// TabView, following the system appearance (Light or Dark
/// Mode). The tab bar is the system's own Liquid Glass — it
/// renders automatically on iOS 26+, the same way v1.0's tab
/// bar did, with no manual glassEffect anywhere on it. That
/// is the lesson of v5.6–v5.9.1: a custom pill built from
/// glassEffect never looked like the system's glass (flat in
/// v5.7, stiff in v5.8, frosted gray with a white tint in
/// v5.9), so the pill is gone — the real Sileo app uses a
/// native tab bar too. The avatar (top right of the Featured
/// tab) opens the settings sheet, which holds the Sandbox
/// controls and tools. The system (engine, backup, resolver,
/// respring) is untouched.
///
/// One rule for glass in this shell: nothing manual. The
/// system renders the tab bar, the toggles and the buttons;
/// the only glassEffect left in the Sileo UI is on
/// non-interactive surfaces (the search field, the Welcome
/// cards), and those stay because the user confirmed they
/// already look right.
struct SileoShell: View {
    @ObservedObject var console: Console
    @ObservedObject var manager: GestaltManager
    @StateObject private var shell = SileoShellState()

    var body: some View {
        ZStack {
            Sileo.background.ignoresSafeArea()

            TabView(selection: $shell.selectedTab) {
                TweaksView(console: console, manager: manager,
                           onOpenSandbox: { shell.settingsActive = true },
                           onOpenExtra: { shell.settingsActive = true },
                           onOpenBackup: { shell.settingsActive = true })
                    .tabItem { Label(SileoTab.featured.title, systemImage: SileoTab.featured.icon) }
                    .tag(SileoTab.featured)

                NavigationStack { AppDataView() }
                    .tabItem { Label(SileoTab.appData.title, systemImage: SileoTab.appData.icon) }
                    .tag(SileoTab.appData)

                NavigationStack { PosterBoardView() }
                    .tabItem { Label(SileoTab.posterBoard.title, systemImage: SileoTab.posterBoard.icon) }
                    .tag(SileoTab.posterBoard)

                NavigationStack { CacheCleanerView() }
                    .tabItem { Label(SileoTab.cacheCleaner.title, systemImage: SileoTab.cacheCleaner.icon) }
                    .tag(SileoTab.cacheCleaner)

                // BackupView brings its own NavigationStack.
                BackupView(manager: manager, sileo: true)
                    .tabItem { Label(SileoTab.backup.title, systemImage: SileoTab.backup.icon) }
                    .tag(SileoTab.backup)
            }
            .tint(Sileo.accent)
            .environmentObject(shell)
            .onChange(of: shell.selectedTab) { _, _ in
                SoundEffects.playSwipe()
            }
        }
        .sheet(isPresented: $shell.settingsActive) {
            SileoSettingsSheet(console: console, manager: manager)
        }
    }
}
