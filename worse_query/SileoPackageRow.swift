import SwiftUI

// MARK: - Sileo package rows
//
// A faithful SwiftUI copy of Sileo's FeaturedPackageView
// (repo adnan120hz/ui3-Ui): a square package icon in the
// package's own color, a three-line title stack (name 17
// semibold / author 13 medium gray / version 11 gray), and
// the action where Sileo puts its GET pill — here a Liquid
// Glass toggle switch, because a tweak's action is its on/off
// state. The whole row is tappable (opens the package's info,
// like Sileo opening a depiction); the toggle handles its own
// taps. A 1pt separator runs full width under every row.
// Titles wrap to two lines so long tweak names never truncate
// mid-word ("Enable Dynami…").

extension TweakTint {
    /// The tweak's own color, used as its package icon square
    /// (Sileo packages each carry their own icon color).
    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .brown: .brown
        case .gray: .gray
        }
    }
}

/// A tweak's toggle, as a Liquid Glass switch: a glass
/// capsule track (blue-tinted glass when on, plain glass when
/// off) with a white knob that slides. Same size as the
/// system switch (51 x 31), same tap behavior as the old
/// ON/OFF pill — only the look changed, and every tweak row
/// now has a real toggle instead of an ON/OFF label.
struct SileoGlassToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            SoundEffects.playTap()
            action()
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .frame(width: 51, height: 31)
                    .glassEffect(isOn ? .regular.tint(.blue) : .regular, in: Capsule())
                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(2)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// One package row: icon + title stack + trailing action +
/// full-width separator. The row tap and the trailing button
/// are separate targets (the button wins inside its own area).
struct SileoPackageRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let author: String
    let version: String
    let onTap: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            SileoIcon(systemImage: icon, color: iconColor, size: 60)
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
        SileoPackageRow(
            icon: tweak.icon,
            iconColor: tweak.tint.color,
            title: tweak.title,
            author: TweakCategory.section(of: tweak).title,
            version: stateLine,
            onTap: {
                if tweak.infoMessage != nil {
                    onInfo(tweak)
                }
            }
        ) {
            SileoGlassToggle(isOn: tweak.isOn(in: manager.dictNow)) {
                let binding = manager.toggleBinding(for: tweak)
                binding.wrappedValue.toggle()
            }
            .disabled(pillDisabled)
            .opacity(pillDisabled ? 0.4 : 1)
        }
        .disabled(tweak.id == "enable_ipados_mode" && ipadOSModeLocked)
    }
}
