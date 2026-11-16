import SwiftUI

// MARK: - Sileo look, shared by the whole app
//
// The Sileo UI (wt.tweaksUIVersion == "sileo") restyles the app
// after Sileo 2.5.1 (repo adnan120hz/ui3-Ui): flat package rows
// with 1pt separators (no cards), Sileo's separator gray, and
// the green/teal accent changed to blue. The page follows the
// system appearance — truly black in Dark Mode, light in Light
// Mode. The components here are the Sileo-mode replacements for
// WTGlassPage / WTSectionCard / RowIcon; the system behind them
// (engine, backup, resolver, respring) is untouched.
//
// Since v5.8 the whole Sileo UI was Liquid Glass; v6.0.11
// removes the manual glass (user order) — the package
// icons are solid color tiles (the tweak's color, white
// symbol), the toggles are the native switches, the search
// field and its close button are plain, and the banners
// are colorful info cards. The toolchain builds with
// Xcode 26+, so the system renders Liquid Glass on its
// own native components. And the page follows the system
// appearance — dark background in Dark Mode, light
// background in Light Mode — instead of forcing dark.
//
// Measurements come from the repo's own code:
// - FeaturedPackageView: icon square, 16pt row spacing/margins,
//   title 17 semibold, author 13 medium, version 11, both gray
//   RGB(143,142,148); separator 1pt, full width.
// - FeaturedHeaderView: section title 22 bold, 16pt margins.
// - PackageIconView: corner radius = width / 4.
// - SileoThemeManager (dark): separator RGB(71,71,73); the
//   page background here is truly black instead.

enum Sileo {
    /// The page background: truly black in Dark Mode (not the
    /// old dark gray #1C1C1E), the system background in Light
    /// Mode.
    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black
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

/// The package icon Sileo puts on every row: a solid tile in
/// the package's own color (here the tweak's tint) and a symbol
/// in the matching color, corner radius width / 4
/// (PackageIconView). The tile used to be a tinted Liquid
/// Glass tile (`.glassEffect` with a color tint); the manual
/// glass is removed (v6.0.11, user order) and the tile is a
/// plain solid color now — the colors stay (blocks of 4), and
/// the system renders Liquid Glass on its own components from
/// the Xcode 26+ build.
struct SileoIcon: View {
    let systemImage: String
    var color: Color = .blue
    var size: CGFloat = 60
    /// The symbol's color — white, except on a light tile,
    /// where it is dark so it stays readable.
    var symbolColor: Color = .white

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(symbolColor)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
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
