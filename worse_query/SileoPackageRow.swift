import SwiftUI

// MARK: - Sileo package rows
//
// A faithful SwiftUI copy of Sileo's FeaturedPackageView
// (repo adnan120hz/ui3-Ui): a square package icon in the
// package's own color, a three-line title stack (name 17
// semibold / author 13 medium gray / version 11 gray), and
// the action where Sileo puts its GET pill — here the native
// Toggle switch, because a tweak's action is its on/off
// state. The native switch is the system's own Liquid Glass
// switch (the same one the New and Old UIs use) — a custom
// glass toggle was tried in v5.8 and rendered as a flat blue
// capsule, not glass, so it is gone. The whole row is
// tappable (opens the package's info, like Sileo opening a
// depiction); the toggle handles its own taps. A 1pt
// separator runs full width under every row. Titles wrap to
// two lines so long tweak names never truncate mid-word
// ("Enable Dynami…").

extension TweakTint {
    /// The tweak's Sileo icon colors: the glass tile tint +
    /// the symbol color, from the five-color palette only —
    /// blue, cyan, gray (abu), dark, light. The catalog's 13
    /// tints are folded into those five by hue family: cool
    /// blues to blue, teals/greens to cyan, browns/grays to
    /// gray, reds/oranges to dark, pinks/yellows to light. A
    /// light tile gets a dark symbol so it stays readable.
    var sileoIcon: (tile: Color, symbol: Color) {
        switch self {
        case .blue, .indigo, .purple:
            (.blue, .white)
        case .green, .mint, .teal, .cyan:
            (.cyan, .white)
        case .brown, .gray:
            (.gray, .white)
        case .red, .orange:
            (Color(red: 0.16, green: 0.16, blue: 0.18), .white)
        case .pink, .yellow:
            (.white, Color(red: 0.16, green: 0.16, blue: 0.18))
        }
    }
}

/// One package row: icon + title stack + trailing action +
/// full-width separator. The row tap and the trailing button
/// are separate targets (the button wins inside its own area).
struct SileoPackageRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    /// The icon's symbol color — white, except on a light
    /// tile, where it is dark so it stays readable.
    var iconSymbolColor: Color = .white
    let title: String
    let author: String
    let version: String
    let onTap: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            SileoIcon(systemImage: icon, color: iconColor, size: 60, symbolColor: iconSymbolColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Sileo.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(author)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Sileo.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(version)
                    .font(.system(size: 11))
                    .foregroundStyle(Sileo.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sileo.separator).frame(height: 1)
        }
    }
}

/// One catalog tweak as a Sileo package row: the tweak's own
/// tint as the glass icon tile, the section name as the author
/// line, the state as the version line ("On · WorkTweaks").
/// Shared by the Featured and Packages tabs so the two lists
/// can never drift. The info alert only opens for tweaks that
/// actually have info text.
struct SileoTweakRow: View {
    @ObservedObject var manager: GestaltManager
    let tweak: GestaltTweak
    let onInfo: (GestaltTweak) -> Void
    /// The icon colors, when the page groups them (blocks of
    /// four down the page) instead of the tweak's own catalog
    /// tint. Nil = the tweak's own tint.
    let iconColor: (tile: Color, symbol: Color)? = nil

    /// Enable iPadOS Mode stays locked unless the device class in
    /// CacheExtra still reads "iPhone" (unchanged from v2.0).
    private var ipadOSModeLocked: Bool {
        let extra = manager.dictNow["CacheExtra"] as? [String: Any]
        return extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone"
    }

    private var pillDisabled: Bool {
        !manager.isValid || !tweak.supported()
            || (tweak.id == "enable_ipados_mode" && ipadOSModeLocked)
    }

    private var stateLine: String {
        if !tweak.supported(), let minv = tweak.minv {
            return String(format: "Requires iOS %.1f+ · WorkTweaks", minv)
        }
        return (tweak.isOn(in: manager.dictNow) ? "On" : "Off") + " · WorkTweaks"
    }

    var body: some View {
        let icon = iconColor ?? tweak.tint.sileoIcon
        SileoPackageRow(
            icon: tweak.icon,
            iconColor: icon.tile,
            iconSymbolColor: icon.symbol,
            title: tweak.title,
            author: TweakCategory.section(of: tweak).title,
            version: stateLine,
            onTap: {
                if tweak.infoMessage != nil {
                    onInfo(tweak)
                }
            }
        ) {
            // The native Toggle: the system's own Liquid Glass
            // switch, the same one the New and Old UIs use.
            Toggle(isOn: manager.toggleBinding(for: tweak)) {
                Text(tweak.title)
            }
            .labelsHidden()
            .disabled(pillDisabled)
            .opacity(pillDisabled ? 0.4 : 1)
        }
        .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)
    }
}
