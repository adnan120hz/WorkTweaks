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
    /// Backup opens as a sheet from the top-left button — it
    /// is not a tab anymore, so the tab bar has four tabs.
    @Published var backupActive = false
}

/// The tabs: Featured (our tweaks) and the tools the user
/// opens most — App Data, PosterBoard and the Cache Cleaner.
/// Backup is NOT a tab: it lives at the top left (the Backup
/// button on Featured) and opens as a sheet. News (changelog)
/// and Sources (GitHub) live in the avatar's settings sheet
/// instead.
enum SileoTab: String, CaseIterable {
    case featured, appData, posterBoard, cacheCleaner

    /// Short labels, used only for accessibility — the tab
    /// bar shows ICONS ONLY. The native pill sizes to its
    /// content, so text labels made it almost full-width and
    /// the search circle sat on top of the Cleaner tab. With
    /// icons only the pill shrinks to about two-thirds of the
    /// screen, leaving a clear gap at the right for the
    /// search circle beside it, level — like Sileo. (That is
    /// the "shrink the menu" the user ordered.)
    var title: String {
        switch self {
        case .featured: "Featured"
        case .appData: "Data"
        case .posterBoard: "Poster"
        case .cacheCleaner: "Cleaner"
        }
    }

    var icon: String {
        switch self {
        case .featured: "star.fill"
        case .appData: "folder.fill"
        case .posterBoard: "photo.fill"
        case .cacheCleaner: "trash.fill"
        }
    }
}

/// The whole app in Sileo UI: four tabs in a native
/// TabView, following the system appearance (Light or Dark
/// Mode). The tab bar is the system's own Liquid Glass — it
/// renders automatically on iOS 26+, the same way v1.0's tab
/// bar did, with no manual glassEffect anywhere on it. That
/// is the lesson of v5.6–v5.9.1: a custom pill built from
/// glassEffect never looked like the system's glass (flat in
/// v5.7, stiff in v5.8, frosted gray with a white tint in
/// v5.9), so the pill is gone for good — never restore it.
/// The floating glass search circle sits at the bottom right,
/// LEVEL with the tab bar (its centre on the tab bar's
/// centre), like the search circle beside Sileo's pill. The
/// avatar (top right of the Featured tab) opens the settings
/// sheet, which holds the Sandbox controls and tools; Backup
/// lives only at the top left of the Featured page, on the
/// same row as the avatar, and opens as a sheet. The system
/// (engine, backup, resolver, respring) is untouched.
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
                    .tabItem {
                        Image(systemName: SileoTab.featured.icon)
                            .accessibilityLabel(SileoTab.featured.title)
                    }
                    .tag(SileoTab.featured)

                NavigationStack { AppDataView() }
                    .tabItem {
                        Image(systemName: SileoTab.appData.icon)
                            .accessibilityLabel(SileoTab.appData.title)
                    }
                    .tag(SileoTab.appData)

                NavigationStack { PosterBoardView() }
                    .tabItem {
                        Image(systemName: SileoTab.posterBoard.icon)
                            .accessibilityLabel(SileoTab.posterBoard.title)
                    }
                    .tag(SileoTab.posterBoard)

                NavigationStack { CacheCleanerView() }
                    .tabItem {
                        Image(systemName: SileoTab.cacheCleaner.icon)
                            .accessibilityLabel(SileoTab.cacheCleaner.title)
                    }
                    .tag(SileoTab.cacheCleaner)
            }
            .tint(Sileo.accent)
            .environmentObject(shell)
            .onChange(of: shell.selectedTab) { _, _ in
                SoundEffects.playSwipe()
            }

            // The search button sits at the bottom right,
            // LEVEL with the native tab bar — its centre on
            // the tab bar pill's centre, like the search
            // circle beside Sileo's pill. Measured on the
            // user's v6.0.6 screenshot: the pill's centre is
            // 67pt above the screen bottom, so a 48pt circle
            // needs its bottom 43pt above the screen bottom.
            // The frame ignores the safe area, so that 43pt
            // is measured from the screen bottom, not from
            // the safe-area edge — that is why v6.0.6's
            // padding bottom 34 (safe-area-relative) left
            // the circle ~50pt too high. The 48pt frame is
            // on the Button itself, not the image: in v6.0.6
            // the frame was on the image and the glass style
            // inflated the button to ~81pt, which is why it
            // covered the Cleaner tab. It opens the tweaks
            // search (the same cover the nav bar magnifier
            // opened in v5.9.2 — that magnifier is gone, the
            // circle is the only search button).
            Button {
                SoundEffects.playTap()
                shell.selectedTab = .featured
                shell.searchActive = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .frame(width: 48, height: 48)
            .accessibilityLabel("Search tweaks")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 10)
            .padding(.bottom, 43)
            .ignoresSafeArea()
        }
        .sheet(isPresented: $shell.settingsActive) {
            SileoSettingsSheet(console: console, manager: manager)
        }
        .sheet(isPresented: $shell.backupActive) {
            // Backup lives only at the top left now, not in
            // the tab bar — it opens as a sheet, with Done
            // to go back (same pattern as the settings sheet).
            BackupView(manager: manager, sileo: true)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { shell.backupActive = false }
                    }
                }
        }
    }
}
