import SwiftUI

// MARK: - Sileo look, shared by every tab
//
// The Sileo UI (wt.tweaksUIVersion == "sileo") restyles the
// WHOLE app, not just the Tweaks tab: dark page (#1C1C1E),
// white text, blue accent, WorkTweaks icon — the same language
// as the Sileo Featured page (repo adnan120hz/ui3-Ui), with
// Sileo's green/teal accent changed to blue. The components
// here are the Sileo-mode replacements for WTGlassPage /
// WTSectionCard / RowIcon; the system behind them (engine,
// backup, resolver, respring) is untouched.

enum Sileo {
    /// Sileo's dark page background (#1C1C1E).
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    /// Dark card fill (white at 7% over the page background).
    static let card = Color.white.opacity(0.07)
    /// Hairline between rows.
    static let separator = Color.white.opacity(0.15)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.6)
    static let accent = Color.blue
}

/// Sileo page container: dark background + scrolling content
/// with room at the bottom for the floating pill tab bar.
struct SileoPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Sileo.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// A dark card — the Sileo-mode replacement for WTSectionCard.
struct SileoCard<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Sileo.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .background(Sileo.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Sileo.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The blue rounded-square icon Sileo puts on every package row.
struct SileoIcon: View {
    let systemImage: String
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.43, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Sileo.accent, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

/// The big section title Sileo puts above a package list
/// ("Hot Right Now" on the Featured page).
struct SileoSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(Sileo.primary)
    }
}
