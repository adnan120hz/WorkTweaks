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
// MARK: - Liquid Glass card surface
//
// Every card in the app renders on the iOS 26 Liquid Glass
// surface — the same material as the floating tab bar — via
// this one modifier, so the look stays identical everywhere.
// The REGULAR glass variant only: no added transparency and
// no tint, so cards stay essentially solid and text keeps its
// full contrast. (The Log tab is excluded on purpose: it
// keeps its plain console appearance.)

struct WTGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content.glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

extension View {
    /// Applies the shared Liquid Glass card surface with the
    /// given corner radius (the app's cards use 14 or 16; a
    /// radius of 999 renders a capsule).
    func wtGlassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(WTGlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass page scaffolding
//
// Since v3.8 every page shares the Tweaks page's construction:
// a ScrollView holding a vertical stack of free-standing glass
// cards over the grouped background, instead of List/Form
// section containers. A former List/Form section maps to one
// WTSectionCard: the section header becomes a small caption
// above the card (the "Sections" / "Menus" label style), the
// rows live inside the card, and the section footer becomes a
// caption below it.

/// The scrolling page shell: a stack of section cards over the
/// system grouped background, with the Tweaks page's margins.
struct WTGlassPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// One page section as a glass card, with the section's header
/// as a caption above it and its footer as a caption below it.
/// Rows are padded inside the card; multi-row cards separate
/// their rows with Divider(), like the lists they replace.
struct WTSectionCard<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wtGlassCard(cornerRadius: 16)

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Manual restart guide
//
// Choosing "Restart Device" anywhere in the app (after Apply,
// after a Revert or Backup restore, after a footnote write)
// presents this guide: the app never restarts the device
// itself — iOS gives apps no way to do that — so the user
// restarts by hand. One shared copy, so every flow shows
// identical text.

enum ManualRestartGuide {
    static let title = "Restart Manually"
    static let message = "Restart manually: press Volume Up, then Volume Down, then hold the Side button until the Apple logo appears — or go to Settings > General > Shut Down, slide to power off, then turn the device back on."
}

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
