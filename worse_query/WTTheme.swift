import SwiftUI

// MARK: - Flag theme (v7.0)
//
// The accent color, gradients and backgrounds follow the
// selected language's flag. The five palettes are deliberately
// VISIBLY DISTINCT even where the flags look similar:
//   en-US — blue accent (#0A84FF) + navy, red/white secondary
//   id    — red accent (#E7000B) + white, top-to-bottom gradient
//   zh    — deep red (#DE2910) + gold (#FFDE00), diagonal
//           gradient, 1 large + 4 small gold stars
//   vi    — bright red (#DA251D) + yellow (#FFFF00), horizontal
//           gradient red → warm orange-red, 1 large yellow star
//   ru    — flag blue (#0039A6) + white/red tricolour;
//           the blue is visibly darker than the US accent
//           (#0A84FF), so the two never read as the same.
// zh vs vi differ in red, in second color (gold vs pure
// yellow), in gradient direction and stops, and in the star
// motif — so the two themes never read as the same.
//
// Flags are drawn with SwiftUI shapes only — no flag emoji,
// no image assets. Per user order, NO logo or flag artwork
// appears in any page background: the flag theme lives only
// in accent colors/gradients and in the small foreground
// flag indicators (header-card language row, language
// picker sheet). The Apple logo watermark and the faint
// flag background were removed.

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

// MARK: - Five-point star shape (flag stars)

struct WTStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.382
        var angle = -Double.pi / 2
        let step = Double.pi / 5
        var first = true
        for i in 0..<10 {
            let r = i % 2 == 0 ? outer : inner
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r
            )
            if first {
                path.move(to: point)
                first = false
            } else {
                path.addLine(to: point)
            }
            angle += step
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Drawn flag (no emoji, no assets)

/// The selected language's flag, drawn with SwiftUI shapes.
/// id: red over white bands. zh: red field, 1 large + 4 small
/// gold stars. vi: red field, 1 large yellow star. ru: white
/// over blue over red horizontal tricolour. en-US:
/// 13 stripes + blue canton with a simplified star grid.
/// Used ONLY as small foreground indicators (header-card
/// language row, language picker sheet) — never in any
/// page background.
struct WTFlagView: View {
    let language: WTLanguage

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                switch language {
                case .id:
                    VStack(spacing: 0) {
                        Color(red: 0xE7 / 255, green: 0x00 / 255, blue: 0x0B / 255)
                        Color.white
                    }
                case .zhHans:
                    Color(red: 0xDE / 255, green: 0x29 / 255, blue: 0x10 / 255)
                    // 1 large + 4 small gold stars, upper-left.
                    WTStarShape()
                        .fill(Color(red: 0xFF / 255, green: 0xDE / 255, blue: 0x00 / 255))
                        .frame(width: h * 0.34, height: h * 0.34)
                        .position(x: w * 0.16, y: h * 0.26)
                    ForEach(0..<4) { i in
                        let spots: [(CGFloat, CGFloat)] = [
                            (0.33, 0.10), (0.40, 0.22), (0.37, 0.38), (0.27, 0.44),
                        ]
                        WTStarShape()
                            .fill(Color(red: 0xFF / 255, green: 0xDE / 255, blue: 0x00 / 255))
                            .frame(width: h * 0.11, height: h * 0.11)
                            .position(x: w * spots[i].0, y: h * spots[i].1)
                    }
                case .vi:
                    Color(red: 0xDA / 255, green: 0x25 / 255, blue: 0x1D / 255)
                    // 1 large yellow star, centered.
                    WTStarShape()
                        .fill(Color(red: 1, green: 1, blue: 0))
                        .frame(width: h * 0.62, height: h * 0.62)
                        .position(x: w * 0.5, y: h * 0.5)
                case .ru:
                    // White over blue over red tricolour.
                    VStack(spacing: 0) {
                        Color.white
                        Color(red: 0x00 / 255, green: 0x39 / 255, blue: 0xA6 / 255)
                        Color(red: 0xD5 / 255, green: 0x2B / 255, blue: 0x1E / 255)
                    }
                case .enUS:
                    VStack(spacing: 0) {
                        ForEach(0..<13) { i in
                            (i % 2 == 0
                                ? Color(red: 0xB2 / 255, green: 0x22 / 255, blue: 0x34 / 255)
                                : Color.white)
                        }
                    }
                    VStack {
                        HStack {
                            ZStack {
                                Color(red: 0x3C / 255, green: 0x3B / 255, blue: 0x6E / 255)
                                // Simplified star grid: 9 rows x 6 cols.
                                VStack(spacing: h * 0.012) {
                                    ForEach(0..<9) { _ in
                                        HStack(spacing: w * 0.018) {
                                            ForEach(0..<6) { _ in
                                                WTStarShape()
                                                    .fill(Color.white)
                                                    .frame(width: h * 0.045, height: h * 0.045)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(width: w * 0.4, height: h * 7 / 13)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}
