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

/// The four pill tabs: Featured (our tweaks) and the three
/// tools the user opens most — App Data, PosterBoard and the
/// Cache Cleaner. News (changelog) and Sources (GitHub) live
/// in the avatar's settings sheet instead.
enum SileoTab: String, CaseIterable {
    case featured, appData, posterBoard, cacheCleaner

    var title: String {
        switch self {
        case .featured: "Featured"
        case .appData: "App Data"
        case .posterBoard: "PosterBoard"
        case .cacheCleaner: "Cache Cleaner"
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

/// The whole app in Sileo UI: the four tabs inside a dark
/// shell with Sileo's floating pill tab bar + search circle at
/// the bottom. This replaces the standard TabView while
/// wt.tweaksUIVersion == "sileo". The pill and the search
/// circle are real Liquid Glass (glassEffect, iOS 26): the
/// scrolling content shows through them, refracted at the
/// edges, like Sileo 2.5.1's pill — not a solid color and not
/// the old frosted material. The avatar (top right of the
/// Featured tab) opens the settings sheet, which holds the
/// Sandbox controls and tools. The system (engine, backup,
/// resolver, respring) is untouched.
struct SileoShell: View {
    @ObservedObject var console: Console
    @ObservedObject var manager: GestaltManager
    @StateObject private var shell = SileoShellState()

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
                }
            }
            .environmentObject(shell)

            tabBar
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $shell.settingsActive) {
            SileoSettingsSheet(console: console, manager: manager)
        }
    }

    /// Sileo's floating pill tab bar in Liquid Glass: the four
    /// tabs as icon-over-label items (the selected one in
    /// blue, the rest white), and the glass search circle
    /// beside it — the circle opens the tweaks search. The
    /// pill scrolls horizontally if the labels ever need more
    /// room, so a label can never wrap to two lines (the
    /// "Featu / red" mess in v5.6).
    private var tabBar: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(SileoTab.allCases, id: \.self) { tab in
                        Button {
                            SoundEffects.playSwipe()
                            withAnimation(.easeInOut(duration: 0.25)) {
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
                            .foregroundStyle(shell.selectedTab == tab ? Sileo.accent : .white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .glassEffect(.regular, in: Capsule())

            Button {
                SoundEffects.playTap()
                shell.selectedTab = .featured
                shell.searchActive = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: Circle())
            .accessibilityLabel("Search tweaks")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
