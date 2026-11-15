import SwiftUI

// MARK: - Sources tab (our GitHub link)
//
// Sileo's Sources tab, for WorkTweaks: an "All Tweaks" row
// (like Sileo's "All Packages", it switches to the Packages
// tab) and a Repositories section with one repo — ours.
// Tapping the repo opens it in Safari. There is nothing to
// edit or add here, so Sileo's Edit and + buttons are gone.

struct SileoSourcesView: View {
    @EnvironmentObject private var shell: SileoShellState

    var body: some View {
        NavigationStack {
            SileoPage {
                Button {
                    SoundEffects.playTap()
                    shell.selectedTab = .packages
                } label: {
                    HStack(spacing: 16) {
                        SileoIcon(systemImage: "cube.fill", color: .gray, size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Tweaks")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Sileo.primary)
                                .lineLimit(1)
                            Text("See all tweaks")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Sileo.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(TweakCatalog.all.count)")
                            .font(.system(size: 15))
                            .foregroundStyle(Sileo.secondary)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Sileo.separator).frame(height: 1)
                }

                SileoSectionTitle(text: "Repositories")

                Link(destination: URL(string: "https://github.com/adnan120hz/WorkTweaks")!) {
                    HStack(spacing: 16) {
                        Image("AppIconDisplay")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WorkTweaks")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Sileo.primary)
                                .lineLimit(1)
                            Text("github.com/adnan120hz/WorkTweaks")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Sileo.secondary)
                                .lineLimit(1)
                            Text("MobileGestalt Tweak App for iOS")
                                .font(.system(size: 11))
                                .foregroundStyle(Sileo.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Sileo.separator).frame(height: 1)
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
