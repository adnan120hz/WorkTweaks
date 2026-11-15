import SwiftUI

// MARK: - Sileo look, shared by the whole app
//
// The Sileo UI (wt.tweaksUIVersion == "sileo") restyles the app
// after Sileo 2.5.1 (repo adnan120hz/ui3-Ui): flat package rows
// with 1pt separators (no cards), Sileo's exact dark-theme
// colors, and the green/teal accent changed to blue. The
// components here are the Sileo-mode replacements for
// WTGlassPage / WTSectionCard / RowIcon; the system behind them
// (engine, backup, resolver, respring) is untouched.
//
// Since v5.8 the whole Sileo UI is Liquid Glass, not just the
// pill: the package icons are tinted glass tiles (the tweak's
// color as a glass tint, white symbol — no more flat neon
// squares), the toggles are glass switches, the search field
// and its close button are glass, and the banners are colorful
// info cards. And the page follows the system appearance —
// dark background in Dark Mode, light background in Light
// Mode — instead of forcing dark.
//
// Measurements come from the repo's own code:
// - FeaturedPackageView: icon square, 16pt row spacing/margins,
//   title 17 semibold, author 13 medium, version 11, both gray
//   RGB(143,142,148); separator 1pt, full width.
// - FeaturedHeaderView: section title 22 bold, 16pt margins.
// - PackageIconView: corner radius = width / 4.
// - SileoThemeManager (dark): background RGB(28,28,30),
//   separator RGB(71,71,73).

enum Sileo {
    /// The page background: Sileo's dark #1C1C1E in Dark Mode,
    /// the system background in Light Mode.
    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : UIColor.systemBackground
    })
    /// The 1pt separator, full width: RGB(71,71,73) in Dark
    /// Mode, a light gray in Light Mode.
    static let separator = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 71 / 255, green: 71 / 255, blue: 73 / 255, alpha: 1)
            : UIColor(red: 198 / 255, green: 198 / 255, blue: 200 / 255, alpha: 1)
    })
    /// The main text color — follows the system appearance.
    static let primary = Color.primary
    /// Sileo's author/version gray (RGB 143,142,148) — reads
    /// in both appearances.
    static let secondary = Color(red: 143 / 255, green: 142 / 255, blue: 148 / 255)
    static let accent = Color.blue
}

/// Sileo page container: background + scrolling content.
/// Rows are full width (they carry their own 16pt margins, so
/// separators run edge to edge like Sileo's). `bottomPadding`
/// is 120 under the shell's floating pill tab bar, 24 when a
/// page is pushed inside the settings sheet (no pill there).
struct SileoPage<Content: View>: View {
    var bottomPadding: CGFloat = 120
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Sileo.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.top, 8)
                .padding(.bottom, bottomPadding)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// The package icon Sileo puts on every row: a Liquid Glass
/// tile tinted with the package's own color (here the tweak's
/// tint) and a white symbol, corner radius width / 4
/// (PackageIconView). The glass tint replaces the flat neon
/// squares of v5.6/v5.7 — the colors stay, but as translucent
/// glass, so the whole app reads as Liquid Glass.
struct SileoIcon: View {
    let systemImage: String
    var color: Color = .blue
    var size: CGFloat = 60

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(color.opacity(0.55)), in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
    }
}

/// The section title Sileo puts above a package list
/// ("Hot Right Now" on the Featured page): 22 bold. The top
/// padding gives each section its own breathing room — every
/// tweak group sits apart from the one above it.
struct SileoSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Sileo.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 10)
    }
}
