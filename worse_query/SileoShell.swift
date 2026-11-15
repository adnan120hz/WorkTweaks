import SwiftUI
import Combine

/// Shared state of the Sileo shell: which tab the floating pill
/// shows, whether the tweaks search cover is open, and whether
/// the avatar's settings sheet is open. Owned by SileoShell
/// and passed down through the environment — the pill (at the
/// root), the search cover and the avatar (on the Featured tab)
/// all read it, so there is exactly one pill, one search
/// button and one settings sheet for the whole app.
final class SileoShellState: ObservableObject {
    @Published var selectedTab: SileoTab = .featured
    @Published var searchActive = false
    @Published var settingsActive = false
}

/// The pill tabs: Featured (our tweaks) and the tools the user
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

/// The whole app in Sileo UI: the five tabs inside a shell
/// that follows the system appearance (Light or Dark Mode),
/// with Sileo's floating pill tab bar + search circle at
/// the bottom. This replaces the standard TabView while
/// wt.tweaksUIVersion == "sileo".
///
/// The pill is real Liquid Glass (glassEffect, iOS 26): the
/// scrolling content shows through it, refracted at the
/// edges, like Sileo 2.5.1's pill. The glass is a milky
/// translucent material — a white tint over .regular — so it
/// reads as a liquid bubble even on the black page, the way
/// the real Sileo pill does over its dark lists. The selected
/// tab carries a soft blue highlight that glides between tabs
/// on a spring (matchedGeometryEffect), so the pill morphs
/// instead of snapping — the liquid feel. The avatar (top
/// right of the Featured tab) opens the settings sheet, which
/// holds the Sandbox controls and tools. The system (engine,
/// backup, resolver, respring) is untouched.
///
/// One rule for glass in this shell, learned in v5.9:
/// glassEffect goes on non-interactive surfaces only (the
/// pill container, the search field). Buttons use the native
/// .glass / .glassProminent button styles, and toggles use
/// the native Toggle — glassEffect on a button's label broke
/// the Welcome screen's Get Started button in v5.8.
struct SileoShell: View {
    @ObservedObject var console: Console
    @ObservedObject var manager: GestaltManager
    @StateObject private var shell = SileoShellState()
    /// The sliding tab highlight's geometry namespace.
    @Namespace private var tabHighlight

    var body: some View {
        ZStack(alignment: .bottom) {
            Sileo.background.ignoresSafeArea()

            Group {
                switch shell.selectedTab {
                case .featured:
                    TweaksView(console: console, manager: manager,
                               onOpenSandbox: { shell.settingsActive = true },
                               onOpenExtra: { shell.settingsActive = true },
                               onOpenBackup: { shell.settingsActive = true })
                case .appData:
                    NavigationStack { AppDataView() }
                case .posterBoard:
                    NavigationStack { PosterBoardView() }
                case .cacheCleaner:
                    NavigationStack { CacheCleanerView() }
                case .backup:
                    // BackupView brings its own NavigationStack.
                    BackupView(manager: manager, sileo: true)
                }
            }
            .environmentObject(shell)

            tabBar
        }
        .sheet(isPresented: $shell.settingsActive) {
            SileoSettingsSheet(console: console, manager: manager)
        }
    }

    /// Sileo's floating pill tab bar in Liquid Glass: the five
    /// tabs as icon-over-label items, with a soft blue
    /// highlight that glides to the selected tab, and the big
    /// glass search bubble beside it — the circle opens the
    /// tweaks search. The pill scrolls horizontally if the
    /// labels ever need more room, so a label can never wrap
    /// to two lines, and it auto-scrolls to the selected tab.
    private var tabBar: some View {
        HStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(SileoTab.allCases, id: \.self) { tab in
                            Button {
                                SoundEffects.playSwipe()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    shell.selectedTab = tab
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 17, weight: .semibold))
                                    Text(tab.title)
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                .foregroundStyle(shell.selectedTab == tab ? Sileo.accent : Color.primary.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background {
                                    if shell.selectedTab == tab {
                                        Capsule()
                                            .fill(Color.blue.opacity(0.16))
                                            .matchedGeometryEffect(id: "tabHighlight", in: tabHighlight)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(tab)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .glassEffect(.regular.tint(.white.opacity(0.2)), in: Capsule())
                .onChange(of: shell.selectedTab) { _, tab in
                    withAnimation { proxy.scrollTo(tab, anchor: .center) }
                }
            }

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
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
