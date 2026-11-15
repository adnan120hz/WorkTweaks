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

/// Sileo's four tabs, in Sileo's order: Featured (our tweaks),
/// News (version updates), Sources (our GitHub link),
/// Packages (all tweaks).
enum SileoTab: String, CaseIterable {
    case featured, news, sources, packages

    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .featured: "star.fill"
        case .news: "newspaper"
        case .sources: "globe"
        case .packages: "doc.text.fill"
        }
    }
}

/// The whole app in Sileo UI: Sileo's four tabs inside a dark
/// shell with Sileo's floating pill tab bar + blue search
/// circle at the bottom. This replaces the standard TabView
/// while wt.tweaksUIVersion == "sileo". The avatar (top right
/// of the Featured tab) opens the settings sheet, which holds
/// the Sandbox controls and tools. The system (engine, backup,
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
                case .news:
                    SileoNewsView()
                case .sources:
                    SileoSourcesView()
                case .packages:
                    SileoPackagesView(manager: manager)
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

    /// Sileo's floating pill tab bar: the four tabs as
    /// icon-over-label items (like Sileo's pill), the selected
    /// one in blue, and the blue search circle beside it —
    /// the circle opens the tweaks search.
    private var tabBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
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
                        }
                        .foregroundStyle(shell.selectedTab == tab ? Sileo.accent : .white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())

            Button {
                SoundEffects.playTap()
                shell.selectedTab = .featured
                shell.searchActive = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Sileo.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search tweaks")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
