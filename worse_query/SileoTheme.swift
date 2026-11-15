import SwiftUI

// MARK: - Sileo look, shared by the whole app
//
// The Sileo UI (wt.tweaksUIVersion == "sileo") restyles the app
// after Sileo 2.5.1 (repo adnan120hz/ui3-Ui): a dark page, flat
// package rows with 1pt separators (no cards), Sileo's exact
// dark-theme colors, and the green/teal accent changed to blue.
// The components here are the Sileo-mode replacements for
// WTGlassPage / WTSectionCard / RowIcon; the system behind them
// (engine, backup, resolver, respring) is untouched.
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
    /// Sileo's dark page background (#1C1C1E).
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    /// Sileo's dark separator (RGB 71,71,73), 1pt, full width.
    static let separator = Color(red: 71 / 255, green: 71 / 255, blue: 73 / 255)
    static let primary = Color.white
    /// Sileo's author/version gray (RGB 143,142,148).
    static let secondary = Color(red: 143 / 255, green: 142 / 255, blue: 148 / 255)
    static let accent = Color.blue
}

/// Sileo page container: dark background + scrolling content.
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

/// The package icon Sileo puts on every row: a square with the
/// package's own color (here the tweak's tint) and a white
/// symbol, corner radius width / 4 (PackageIconView). The
/// symbol is large and semibold so the icon reads clearly at
/// a glance — the v5.6 symbols were too small and faint.
struct SileoIcon: View {
    let systemImage: String
    var color: Color = .blue
    var size: CGFloat = 60

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
    }
}

/// The section title Sileo puts above a package list
/// ("Hot Right Now" on the Featured page): 22 bold.
struct SileoSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Sileo.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }
}
