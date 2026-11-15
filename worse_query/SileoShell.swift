import SwiftUI
import Combine

/// Shared state of the Sileo shell: which tab the floating pill
/// shows, and whether the tweaks search cover is open. Owned by
/// SileoShell and passed down through the environment — the pill
/// (at the root) and the search cover (in the Tweaks tab) both
/// read it, so there is exactly one pill and one search button
/// for the whole app.
final class SileoShellState: ObservableObject {
    @Published var selectedTab: AppTab = .sandbox
    @Published var searchActive = false
}

/// The whole app in Sileo UI: the five tabs inside a dark shell
/// with Sileo's floating pill tab bar + blue search circle at the
/// bottom. This replaces the standard TabView while
/// wt.tweaksUIVersion == "sileo" — the menu buttons and the
/// layout of every menu change, not just the Tweaks tab. The
/// system (engine, backup, resolver, respring) is untouched.
struct SileoShell: View {
    @ObservedObject var console: Console
    @ObservedObject var manager: GestaltManager
    @StateObject private var shell = SileoShellState()

    /// The five menus, in the same order as the standard tab bar.
    private let tabs: [(AppTab, String, String)] = [
        (.sandbox, "Sandbox", "shippingbox"),
        (.tweaks, "Tweaks", "slider.horizontal.3"),
        (.extra, "Extra", "key"),
        (.backup, "Backup", "externaldrive.badge.timemachine"),
        (.log, "Log", "terminal"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Sileo.background.ignoresSafeArea()

            Group {
                switch shell.selectedTab {
                case .sandbox:
                    SandboxView(console: console, sileo: true)
                case .tweaks:
                    TweaksView(console: console, manager: manager,
                               onOpenSandbox: { shell.selectedTab = .sandbox },
                               onOpenExtra: { shell.selectedTab = .extra },
                               onOpenBackup: { shell.selectedTab = .backup })
                case .extra:
                    CacheExtraView(manager: manager, sileo: true)
                case .backup:
                    BackupView(manager: manager, sileo: true)
                case .log:
                    LogView(console: console, sileo: true)
                }
            }
            .environmentObject(shell)

            tabBar
        }
        .preferredColorScheme(.dark)
    }

    /// Sileo's floating pill tab bar, adapted: the pill switches
    /// the five menus, and the blue circle opens the tweaks
    /// search (tweaks are this app's packages).
    private var tabBar: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs, id: \.0) { tab in
                        Button {
                            SoundEffects.playSwipe()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                shell.selectedTab = tab.0
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.2)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(tab.1)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(shell.selectedTab == tab.0 ? .white : .white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                shell.selectedTab == tab.0 ? Sileo.accent : Color.clear,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .background(.ultraThinMaterial, in: Capsule())

            Button {
                SoundEffects.playTap()
                shell.selectedTab = .tweaks
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
