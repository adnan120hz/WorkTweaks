import SwiftUI

// MARK: - Flag theme (v7.0)
//
// The accent color, gradients and backgrounds follow the
// selected language's flag. The five palettes are deliberately
// VISIBLY DISTINCT even where the flags look similar:
//   en-US — blue accent (#0A84FF) + navy, red/white secondary
//   id    — red accent (#E7000B) + white, top-to-bottom gradient
//   zh    — deep red (#DE2910) + gold (#FFDE00), diagonal
//           gradient
//   vi    — bright red (#DA251D) + yellow (#FFFF00), horizontal
//           gradient red → warm orange-red
//   ru    — flag blue (#0039A6) + white/red tricolour;
//           the blue is visibly darker than the US accent
//           (#0A84FF), so the two never read as the same.
// zh vs vi differ in red, in second color (gold vs pure
// yellow), and in gradient direction and stops — so the
// two themes never read as the same.
//
// Per user order, NO flag graphics anywhere in the UI:
// no drawn flags, no flag emoji, no image assets. The
// flag theme lives ONLY in accent colors/gradients, and
// the language is shown by name text only. The Apple
// logo watermark and the faint flag background were
// removed in the same fix.

struct WTTheme {
    let language: WTLanguage
    let accent: Color
    let accentDeep: Color
    let secondary: Color
    let gradientColors: [Color]
    let gradientStart: UnitPoint
    let gradientEnd: UnitPoint

    static func forLanguage(_ language: WTLanguage) -> WTTheme {
        switch language {
        case .enUS:
            return WTTheme(
                language: .enUS,
                accent: Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255),
                accentDeep: Color(red: 0x0A / 255, green: 0x2A / 255, blue: 0x6B / 255),
                secondary: Color(red: 0xB2 / 255, green: 0x22 / 255, blue: 0x34 / 255),
                gradientColors: [
                    Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255),
                    Color(red: 0x0A / 255, green: 0x2A / 255, blue: 0x6B / 255),
                ],
                gradientStart: .topLeading,
                gradientEnd: .bottomTrailing
            )
        case .id:
            return WTTheme(
                language: .id,
                accent: Color(red: 0xE7 / 255, green: 0x00 / 255, blue: 0x0B / 255),
                accentDeep: Color(red: 0xA8 / 255, green: 0x00 / 255, blue: 0x08 / 255),
                secondary: .white,
                gradientColors: [
                    Color(red: 0xE7 / 255, green: 0x00 / 255, blue: 0x0B / 255),
                    Color(red: 0xA8 / 255, green: 0x00 / 255, blue: 0x08 / 255),
                ],
                gradientStart: .top,
                gradientEnd: .bottom
            )
        case .zhHans:
            return WTTheme(
                language: .zhHans,
                accent: Color(red: 0xDE / 255, green: 0x29 / 255, blue: 0x10 / 255),
                accentDeep: Color(red: 0x7A / 255, green: 0x13 / 255, blue: 0x0A / 255),
                secondary: Color(red: 0xFF / 255, green: 0xDE / 255, blue: 0x00 / 255),
                gradientColors: [
                    Color(red: 0xDE / 255, green: 0x29 / 255, blue: 0x10 / 255),
                    Color(red: 0x7A / 255, green: 0x13 / 255, blue: 0x0A / 255),
                ],
                gradientStart: .topLeading,
                gradientEnd: .bottomTrailing
            )
        case .vi:
            return WTTheme(
                language: .vi,
                accent: Color(red: 0xDA / 255, green: 0x25 / 255, blue: 0x1D / 255),
                accentDeep: Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x2A / 255),
                secondary: Color(red: 1, green: 1, blue: 0),
                gradientColors: [
                    Color(red: 0xDA / 255, green: 0x25 / 255, blue: 0x1D / 255),
                    Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x2A / 255),
                ],
                gradientStart: .leading,
                gradientEnd: .trailing
            )
        case .ru:
            return WTTheme(
                language: .ru,
                accent: Color(red: 0x00 / 255, green: 0x39 / 255, blue: 0xA6 / 255),
                accentDeep: Color(red: 0x00 / 255, green: 0x22 / 255, blue: 0x6E / 255),
                secondary: Color(red: 0xD5 / 255, green: 0x2B / 255, blue: 0x1E / 255),
                gradientColors: [
                    Color(red: 0x00 / 255, green: 0x39 / 255, blue: 0xA6 / 255),
                    Color(red: 0x00 / 255, green: 0x22 / 255, blue: 0x6E / 255),
                ],
                gradientStart: .top,
                gradientEnd: .bottom
            )
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: gradientStart, endPoint: gradientEnd)
    }
}
