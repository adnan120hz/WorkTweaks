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

    /// Short labels — SHOWN on the tab bar, like Sileo.
    /// (v6.0.7 hid them by going icon-only; the user
    /// corrected that — the text stays.)
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

/// The whole app in Sileo UI: four tabs, following the
/// system appearance (Light or Dark Mode). The bottom bar is
/// built to match the real Sileo picture the user sent:
/// a glass pill with the four tabs (icon + label) on the
/// left, and a LARGE glass search circle beside it on the
/// right — the same height as the pill, level with it
/// (sejajar), with a clear gap between them. That is the
/// "shrink the menu" the user ordered: the MENU (the pill)
/// is shrunk, not the search.
///
/// Why a custom bottom bar instead of the native TabView
/// tab bar: the native pill cannot be narrowed. Measured
/// on the user's screenshots, it stays ~88% of the screen
/// wide whether the tabs have labels or are icon-only
/// (v6.0.6 with labels: 878 units; v6.0.7 icon-only: 876),
/// so there is never room for a search circle beside it —
/// any circle overlaps the Cleaner tab. Sileo's pill is
/// ~66% wide. The native TabView still drives the pages
/// (its own tab bar is hidden); only the visible bottom
/// bar is custom. The glass is `.glassEffect(.regular)`
/// with no tint and no background — the same glass the
/// user already approved on the search field — not the
/// frosted manual glass of the old pill builds. The system
/// (engine, backup, resolver, respring) is untouched.
///
/// One rule for glass in this shell: nothing manual. The
/// system renders the toggles and the buttons; the only
/// glassEffect left in the Sileo UI is on non-interactive
/// surfaces (the search field, the Welcome cards) and on
/// this bottom bar, and those stay because the user
/// confirmed they already look right.
struct SileoShell: View {
    @ObservedObject var console: Console
    @ObservedObject var manager: GestaltManager
    @StateObject private var shell = SileoShellState()

    var body: some View {
        ZStack {
            Sileo.background.ignoresSafeArea()

            // The pages, switched by the bottom bar. This is
            // NOT a TabView: a TabView always draws its own
            // native tab bar, and `.toolbar(.hidden, for:
            // .tabBar)` did not hide it in v6.0.8 — the user
            // saw it doubled behind the custom pill. So the
            // pages live in a ZStack and only the selected
            // one is visible; the others stay in the
            // hierarchy (opacity 0) so their NavigationStack
            // state is kept when switching back. The custom
            // bottom bar below drives `shell.selectedTab`.
            ZStack {
                TweaksView(console: console, manager: manager,
                           onOpenSandbox: { shell.settingsActive = true },
                           onOpenExtra: { shell.settingsActive = true },
                           onOpenBackup: { shell.settingsActive = true })
                    .opacity(shell.selectedTab == .featured ? 1 : 0)
                    .disabled(shell.selectedTab != .featured)

                NavigationStack { AppDataView() }
                    .opacity(shell.selectedTab == .appData ? 1 : 0)
                    .disabled(shell.selectedTab != .appData)

                NavigationStack { PosterBoardView() }
                    .opacity(shell.selectedTab == .posterBoard ? 1 : 0)
                    .disabled(shell.selectedTab != .posterBoard)

                NavigationStack { CacheCleanerView() }
                    .opacity(shell.selectedTab == .cacheCleaner ? 1 : 0)
                    .disabled(shell.selectedTab != .cacheCleaner)
            }
            .environmentObject(shell)
            .onChange(of: shell.selectedTab) { _, _ in
                SoundEffects.playSwipe()
            }

            // The bottom bar, built to match the real Sileo
            // picture: a glass pill with the four tabs
            // (icon + label) and a LARGE glass search circle
            // beside it — same height as the pill, level
            // with it, with a clear gap. The pill is the
            // menu that was shrunk (not the search); the
            // search stays large, like Sileo's. It is an
            // overlay, so it only takes the size of its
            // content and never blocks taps to the pages.
            .overlay(alignment: .bottom) {
                bottomBar
            }
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

    /// The bottom bar: the menu pill + the search circle,
    /// level, with a gap — like the real Sileo picture.
    private var bottomBar: some View {
        HStack(spacing: 12) {
            // The menu pill: the four tabs, icon + label.
            // It takes the flexible width (the menu that
            // was shrunk), so the search circle fits beside
            // it. The selected tab reads blue, like Sileo.
            HStack(spacing: 0) {
                ForEach(SileoTab.allCases, id: \.self) { tab in
                    Button {
                        SoundEffects.playTap()
                        shell.selectedTab = tab
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(shell.selectedTab == tab ? Sileo.accent : Sileo.primary)
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(.horizontal, 4)
            .glassEffect(.regular, in: Capsule())
            .frame(maxWidth: .infinity)

            // The search circle: LARGE, the same height as
            // the pill (64pt), level with it — not the small
            // 48pt circle of v6.0.7. It opens the tweaks
            // search (the same cover the nav bar magnifier
            // opened in v5.9.2 — that magnifier is gone, the
            // circle is the only search button).
            Button {
                SoundEffects.playTap()
                shell.selectedTab = .featured
                shell.searchActive = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Search tweaks")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
