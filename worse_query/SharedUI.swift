import SwiftUI

// MARK: - Shared v2.0 UI pieces
//
// One visual language across every screen: soft cards with rounded
// corners and a hairline border, colored rounded-square icon chips
// (iOS Settings style), and section headers with small SF Symbols.

extension View {
    /// One consistent card surface for every v2.0 screen: same
    /// padding, corner radius, fill, and hairline border.
    func wtCard() -> some View {
        self
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

/// A colored rounded-square icon chip, iOS Settings style.
struct IconChip: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

extension TweakTint {
    /// SwiftUI color for a tweak's icon chip.
    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .brown: return .brown
        case .gray: return .gray
        }
    }
}

// MARK: - Supported releases table
//
// Renders SupportInfo.supportedReleases with the four columns
// (Version / Build / Notes / Release Date). Used as plain rows in
// License & Credits and as a card on the unsupported screen.

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

struct SupportedReleasesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Supported iOS Versions", systemImage: "checkmark.shield")
                .font(.headline)
                .padding(.bottom, 6)

            ForEach(Array(SupportInfo.supportedReleases.enumerated()), id: \.element.id) { index, release in
                if index > 0 { Divider() }
                SupportedReleaseRow(release: release)
                    .padding(.vertical, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wtCard()
    }
}
