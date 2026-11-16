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
/// bar is custom. The system (engine, backup, resolver,
/// respring) is untouched.
///
/// No manual Liquid Glass anywhere in this shell (v6.0.11,
/// user order): the pill and the search circle used to
/// carry `.glassEffect(.regular)`; that hand-applied glass
/// is removed and both use a plain system background now.
/// The toolchain builds with Xcode 26+, so the system
/// renders Liquid Glass on its own native components
/// (toggles, buttons); nothing here adds glass by hand.
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
    ///
    /// Sizes, measured off the real Sileo bar the user sent
    /// (v6.0.9's circle was too big and taller than the
    /// pill): the pill is ~66% of the screen wide, the
    /// search circle ~20% wide, the gap ~8pt, and the two
    /// are the SAME height. On a 390pt screen that is a
    /// 76pt circle, a 76pt-tall pill, 24pt side margins,
    /// and an 8pt gap. The circle is a plain button on a
    /// fixed 76pt circle — v6.0.9's `.buttonStyle(.glass)`
    /// inflated the 64pt frame to ~97pt, which is what
    /// made the circle too big and taller than the pill;
    /// v6.0.10 fixed that with glass on the fixed circle,
    /// and v6.0.11 removes the glass entirely (plain
    /// system background). The pill's height is forced to
    /// 76pt (not left to content + padding) so it can
    /// never drift from the circle's height.
    private var bottomBar: some View {
        HStack(spacing: 8) {
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
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 26, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(shell.selectedTab == tab ? Sileo.accent : Sileo.primary)
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(Color(.secondarySystemBackground), in: Capsule())

            // The search circle: the SAME height as the
            // pill (76pt), level with it. It opens the
            // tweaks search (the same cover the nav bar
            // magnifier opened in v5.9.2 — that magnifier
            // is gone, the circle is the only search
            // button). Plain button on a fixed 76pt circle
            // with a plain system background, so it renders
            // at exactly 76pt.
            Button {
                SoundEffects.playTap()
                shell.selectedTab = .featured
                shell.searchActive = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Sileo.accent)
                    .frame(width: 76, height: 76)
                    .background(Color(.secondarySystemBackground), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search tweaks")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}
