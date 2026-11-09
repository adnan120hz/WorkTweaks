import SwiftUI

// MARK: - Shared UI pieces
//
// One visual language across every screen — "quiet pro tool":
// native inset-grouped lists with real separators, plain SF Symbol
// row icons in a single accent color at a single size and weight,
// native section headers, and no decorative gradients, floating
// cards, or colored icon chips anywhere.

/// A plain SF Symbol row icon. Every row icon in the app renders
/// through this view, so they all share one size, one weight, and
/// one color. Tweaks keep their own unique symbol (see
/// TweakCatalog.presentation) — only the rendering is uniform.
struct RowIcon: View {
    let systemImage: String
    var color: Color = .accentColor

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 30)
    }
}

// MARK: - Supported releases table
//
// Renders SupportInfo.supportedReleases with the four columns
// (Version / Build / Notes / Release Date) as plain list rows.
// Used in License & Credits and on the unsupported screen.

struct SupportedReleaseRow: View {
    let release: SupportedRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(release.version)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(release.build)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text("\(release.notes) • \(release.releaseDate)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
