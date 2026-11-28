import SwiftUI

// MARK: - Tweaky's friends
//
// The four friends from the user's mascot photo, drawn entirely
// in SwiftUI shapes — no image asset — in the same style as
// TweakyMascot (GeometryReader, size-parameterized, fixed colors
// so every character looks identical in light/dark mode and
// under every language theme, accessibilityHidden(true)):
//
// - Star: a 5-pointed yellow star, orange outline, dot eyes
//   and a small smile.
// - Cloud: a white cloud of overlapping circles, light-blue
//   outline, dot eyes and a small smile.
// - Cat: a pink round face, triangular ears, darker-pink
//   outline, three whiskers each side, dot eyes and a smile.
// - Rocket: a light-blue body with a blue outline, a round
//   window, pink fins and an orange flame.
//
// MascotFriendView picks one by kind. WTCardCornerFriends
// decorates a card's empty corners with the characters —
// Tweaky plus the four friends, a different character in
// each corner, the lineup rotating with `variant` so no two
// cards show the same arrangement (never the old uniform
// 4x-Tweaky frame). The mascots peek from the corners, mostly
// outside the card, so they sit in the gap between cards
// instead of covering the card's content. Decoration only:
// they never intercept taps.
//
// Cards only — never on menu-row icons or tab-bar icons
// (that is exactly what the v8.0 fix removed).

/// The five mascot characters: Tweaky and his four friends.
enum MascotFriendKind: CaseIterable {
    case tweaky, star, cloud, cat, rocket
}

/// One mascot character, drawn at the given body size.
struct MascotFriendView: View {
    var kind: MascotFriendKind
    var size: CGFloat = 24

    var body: some View {
        switch kind {
        case .tweaky:
            TweakyMascot(size: size)
        case .star:
            StarFriend(size: size)
        case .cloud:
            CloudFriend(size: size)
        case .cat:
            CatFriend(size: size)
        case .rocket:
            RocketFriend(size: size)
        }
    }
}

/// A smile curve, as in TweakyMascot: a quadratic Bezier
/// dipping below the middle.
private struct FriendSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

// MARK: - Star friend

/// A 5-pointed star: outer points and inner vertices
/// alternating around the center, top point straight up.
private struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        var path = Path()
        for i in 0..<10 {
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
            let r = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: cx + CGFloat(cos(angle)) * r,
                y: cy + CGFloat(sin(angle)) * r
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct StarFriend: View {
    /// Body width in points. The face sits inside the star,
    /// so the eyes and smile stay near the center.
    var size: CGFloat = 24

    private static let fillYellow = Color(red: 1.0, green: 0.80, blue: 0.10)
    private static let outlineOrange = Color(red: 0.80, green: 0.42, blue: 0.05)
    private static let dark = Color(red: 0.10, green: 0.11, blue: 0.13)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            StarShape()
                .fill(Self.fillYellow)
                .frame(width: s, height: s)
                .overlay(
                    StarShape()
                        .stroke(Self.outlineOrange, lineWidth: s * 0.03)
                )
                .position(x: s * 0.5, y: s * 0.5)
            // Two black dot eyes.
            Circle()
                .fill(Self.dark)
                .frame(width: s * 0.085, height: s * 0.085)
                .position(x: s * 0.40, y: s * 0.50)
            Circle()
                .fill(Self.dark)
                .frame(width: s * 0.085, height: s * 0.085)
                .position(x: s * 0.60, y: s * 0.50)
            // Small smile, kept high so its dip stays inside
            // the star (the bottom notch sits at y 0.725).
            FriendSmileShape()
                .stroke(Self.dark, style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                .frame(width: s * 0.28, height: s * 0.09)
                .position(x: s * 0.5, y: s * 0.60)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Cloud friend

struct CloudFriend: View {
    /// Body width in points. The cloud is a row of overlapping
    /// circles with aligned bottoms, so the top is bumpy and
    /// the bottom nearly flat.
    var size: CGFloat = 24

    private static let fillWhite = Color.white
    private static let outlineBlue = Color(red: 0.55, green: 0.75, blue: 0.95)
    private static let dark = Color(red: 0.10, green: 0.11, blue: 0.13)

    /// The puffs: (center x, center y, radius), in units of size.
    private static let puffs: [(CGFloat, CGFloat, CGFloat)] = [
        (0.24, 0.60, 0.18),
        (0.50, 0.52, 0.26),
        (0.76, 0.60, 0.18),
    ]

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            // Outline first: every puff stroked, then the same
            // puffs filled white on top — each white fill covers
            // the inner half of its own stroke and the strokes
            // of its neighbours where they overlap, so only the
            // outer silhouette keeps its outline.
            ForEach(0..<Self.puffs.count, id: \.self) { i in
                let puff = Self.puffs[i]
                Circle()
                    .stroke(Self.outlineBlue, lineWidth: s * 0.035)
                    .frame(width: s * puff.2 * 2, height: s * puff.2 * 2)
                    .position(x: s * puff.0, y: s * puff.1)
            }
            ForEach(0..<Self.puffs.count, id: \.self) { i in
                let puff = Self.puffs[i]
                Circle()
                    .fill(Self.fillWhite)
                    .frame(width: s * puff.2 * 2, height: s * puff.2 * 2)
                    .position(x: s * puff.0, y: s * puff.1)
            }
            // Two black dot eyes, on the big middle puff.
            Circle()
                .fill(Self.dark)
                .frame(width: s * 0.08, height: s * 0.08)
                .position(x: s * 0.40, y: s * 0.58)
            Circle()
                .fill(Self.dark)
                .frame(width: s * 0.08, height: s * 0.08)
                .position(x: s * 0.60, y: s * 0.58)
            // Small smile, inside the middle puff.
            FriendSmileShape()
                .stroke(Self.dark, style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                .frame(width: s * 0.26, height: s * 0.09)
                .position(x: s * 0.5, y: s * 0.68)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Cat friend

/// A triangle: (left base, top, right base), in units of size.
private struct TriangleShape: Shape {
    var left: CGPoint
    var top: CGPoint
    var right: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: left.x * rect.width, y: left.y * rect.height))
        path.addLine(to: CGPoint(x: top.x * rect.width, y: top.y * rect.height))
        path.addLine(to: CGPoint(x: right.x * rect.width, y: right.y * rect.height))
        path.closeSubpath()
        return path
    }
}

struct CatFriend: View {
    /// Body width in points. The ears stick up above the round
    /// face; the face center sits at y 0.58.
    var size: CGFloat = 24

    private static let fillPink = Color(red: 0.99, green: 0.65, blue: 0.75)
    private static let outlinePink = Color(red: 0.90, green: 0.35, blue: 0.52)
    private static let innerEarPink = Color(red: 0.93, green: 0.42, blue: 0.55)
    private static let dark = Color(red: 0.10, green: 0.11, blue: 0.13)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            // Ears first — the face circle draws over their bases.
            TriangleShape(
                left: CGPoint(x: 0.20, y: 0.40),
                top: CGPoint(x: 0.28, y: 0.10),
                right: CGPoint(x: 0.42, y: 0.38)
            )
            .fill(Self.fillPink)
            .overlay(
                TriangleShape(
                    left: CGPoint(x: 0.20, y: 0.40),
                    top: CGPoint(x: 0.28, y: 0.10),
                    right: CGPoint(x: 0.42, y: 0.38)
                )
                .stroke(Self.outlinePink, lineWidth: s * 0.025)
            )
            TriangleShape(
                left: CGPoint(x: 0.58, y: 0.38),
                top: CGPoint(x: 0.72, y: 0.10),
                right: CGPoint(x: 0.80, y: 0.40)
            )
            .fill(Self.fillPink)
            .overlay(
                TriangleShape(
                    left: CGPoint(x: 0.58, y: 0.38),
                    top: CGPoint(x: 0.72, y: 0.10),
                    right: CGPoint(x: 0.80, y: 0.40)
                )
                .stroke(Self.outlinePink, lineWidth: s * 0.025)
            )
            // Inner ears.
            TriangleShape(
                left: CGPoint(x: 0.26, y: 0.36),
                top: CGPoint(x: 0.29, y: 0.20),
                right: CGPoint(x: 0.36, y: 0.35)
            )
            .fill(Self.innerEarPink)
            TriangleShape(
                left: CGPoint(x: 0.64, y: 0.35),
                top: CGPoint(x: 0.71, y: 0.20),
                right: CGPoint(x: 0.74, y: 0.36)
            )
            .fill(Self.innerEarPink)
            // Round face with the darker-pink outline.
            Circle()
                .fill(Self.fillPink)
                .frame(width: s * 0.72, height: s * 0.72)
                .overlay(
                    Circle()
                        .stroke(Self.outlinePink, lineWidth: s * 0.03)
                )
                .position(x: s * 0.5, y: s * 0.58)
            // Three whiskers each side, fanning out from the
            // face edge.
            ForEach(0..<3, id: \.self) { i in
                let y = s * (0.50 + CGFloat(i) * 0.08)
                let dy = s * (CGFloat(i) - 1) * 0.06
                Path { path in
                    path.move(to: CGPoint(x: s * 0.16, y: y))
                    path.addLine(to: CGPoint(x: s * 0.01, y: y + dy))
                }
                .stroke(Self.outlinePink, style: StrokeStyle(lineWidth: s * 0.018, lineCap: .round))
                Path { path in
                    path.move(to: CGPoint(x: s * 0.84, y: y))
                    path.addLine(to: CGPoint(x: s * 0.99, y: y + dy))
                }
                .stroke(Self.outlinePink, style: StrokeStyle(lineWidth: s * 0.018, lineCap: .round))
            }
            // Two black dot eyes.
            Circle()
                .fill(Self.dark)
                .frame(width: s * 0.09, height: s * 0.09)
                .position(x: s * 0.36, y: s * 0.55)
            Circle()
                .fill(Self.dark)
                .frame(width: s * 0.09, height: s * 0.09)
                .position(x: s * 0.64, y: s * 0.55)
            // Small smile.
            FriendSmileShape()
                .stroke(Self.dark, style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                .frame(width: s * 0.26, height: s * 0.09)
                .position(x: s * 0.5, y: s * 0.70)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Rocket friend

struct RocketFriend: View {
    /// Body width in points. Total height is 1.3x: the body
    /// on top, the flame below it.
    var size: CGFloat = 24

    private static let bodyBlue = Color(red: 0.55, green: 0.82, blue: 0.98)
    private static let outlineBlue = Color(red: 0.05, green: 0.48, blue: 0.85)
    private static let windowBlue = Color(red: 0.75, green: 0.90, blue: 1.0)
    private static let finPink = Color(red: 0.98, green: 0.55, blue: 0.70)
    private static let finOutline = Color(red: 0.90, green: 0.30, blue: 0.50)
    private static let flameOrange = Color(red: 1.0, green: 0.55, blue: 0.10)
    private static let flameYellow = Color(red: 1.0, green: 0.80, blue: 0.10)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            // Flame first — the body draws over its top.
            Path { path in
                path.move(to: CGPoint(x: s * 0.38, y: s * 0.74))
                path.addQuadCurve(
                    to: CGPoint(x: s * 0.50, y: s * 1.08),
                    control: CGPoint(x: s * 0.34, y: s * 0.92)
                )
                path.addQuadCurve(
                    to: CGPoint(x: s * 0.62, y: s * 0.74),
                    control: CGPoint(x: s * 0.66, y: s * 0.92)
                )
                path.closeSubpath()
            }
            .fill(Self.flameOrange)
            Path { path in
                path.move(to: CGPoint(x: s * 0.44, y: s * 0.74))
                path.addQuadCurve(
                    to: CGPoint(x: s * 0.50, y: s * 0.95),
                    control: CGPoint(x: s * 0.42, y: s * 0.86)
                )
                path.addQuadCurve(
                    to: CGPoint(x: s * 0.56, y: s * 0.74),
                    control: CGPoint(x: s * 0.58, y: s * 0.86)
                )
                path.closeSubpath()
            }
            .fill(Self.flameYellow)
            // Pink fins at the body's lower sides.
            TriangleShape(
                left: CGPoint(x: 0.28, y: 0.55),
                top: CGPoint(x: 0.10, y: 0.78),
                right: CGPoint(x: 0.28, y: 0.74)
            )
            .fill(Self.finPink)
            .overlay(
                TriangleShape(
                    left: CGPoint(x: 0.28, y: 0.55),
                    top: CGPoint(x: 0.10, y: 0.78),
                    right: CGPoint(x: 0.28, y: 0.74)
                )
                .stroke(Self.finOutline, lineWidth: s * 0.02)
            )
            TriangleShape(
                left: CGPoint(x: 0.72, y: 0.55),
                top: CGPoint(x: 0.90, y: 0.78),
                right: CGPoint(x: 0.72, y: 0.74)
            )
            .fill(Self.finPink)
            .overlay(
                TriangleShape(
                    left: CGPoint(x: 0.72, y: 0.55),
                    top: CGPoint(x: 0.90, y: 0.78),
                    right: CGPoint(x: 0.72, y: 0.74)
                )
                .stroke(Self.finOutline, lineWidth: s * 0.02)
            )
            // Light-blue body: pointed nose, straight sides,
            // flat bottom — with the blue outline.
            Path { path in
                path.move(to: CGPoint(x: s * 0.50, y: s * 0.02))
                path.addQuadCurve(
                    to: CGPoint(x: s * 0.72, y: s * 0.30),
                    control: CGPoint(x: s * 0.68, y: s * 0.10)
                )
                path.addLine(to: CGPoint(x: s * 0.72, y: s * 0.72))
                path.addLine(to: CGPoint(x: s * 0.28, y: s * 0.72))
                path.addLine(to: CGPoint(x: s * 0.28, y: s * 0.30))
                path.addQuadCurve(
                    to: CGPoint(x: s * 0.50, y: s * 0.02),
                    control: CGPoint(x: s * 0.32, y: s * 0.10)
                )
                path.closeSubpath()
            }
            .fill(Self.bodyBlue)
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: s * 0.50, y: s * 0.02))
                    path.addQuadCurve(
                        to: CGPoint(x: s * 0.72, y: s * 0.30),
                        control: CGPoint(x: s * 0.68, y: s * 0.10)
                    )
                    path.addLine(to: CGPoint(x: s * 0.72, y: s * 0.72))
                    path.addLine(to: CGPoint(x: s * 0.28, y: s * 0.72))
                    path.addLine(to: CGPoint(x: s * 0.28, y: s * 0.30))
                    path.addQuadCurve(
                        to: CGPoint(x: s * 0.50, y: s * 0.02),
                        control: CGPoint(x: s * 0.32, y: s * 0.10)
                    )
                    path.closeSubpath()
                }
                .stroke(Self.outlineBlue, lineWidth: s * 0.03)
            )
            // Round window: light-blue circle, darker ring.
            Circle()
                .fill(Self.windowBlue)
                .frame(width: s * 0.28, height: s * 0.28)
                .overlay(
                    Circle()
                        .stroke(Self.outlineBlue, lineWidth: s * 0.025)
                )
                .position(x: s * 0.5, y: s * 0.42)
        }
        .frame(width: size, height: size * 1.3)
        .accessibilityHidden(true)
    }
}

// MARK: - Card-corner friends

/// Decorates a card's four corners with the mascots: Tweaky
/// plus the four friends, a different character in each
/// corner. `variant` rotates the lineup through the five
/// characters, so each card shows a different arrangement:
///
/// - variant 0: star, tweaky, cloud, cat
/// - variant 1: tweaky, cloud, cat, rocket
/// - variant 2: cloud, cat, rocket, star
/// - variant 3: cat, rocket, star, tweaky
/// - variant 4: rocket, star, tweaky, cloud
///
/// (corners in top-leading / top-trailing / bottom-leading /
/// bottom-trailing order). The mascots peek from the corners,
/// about half outside the card, and never intercept taps.
struct WTCardCornerFriends: ViewModifier {
    var variant: Int = 0
    var size: CGFloat = 24

    /// The four characters for a variant, in corner order
    /// (top-leading, top-trailing, bottom-leading,
    /// bottom-trailing) — a rotating window over the five
    /// mascots, so every corner shows a different character.
    static func kinds(for variant: Int) -> [MascotFriendKind] {
        let all = MascotFriendKind.allCases
        let start = ((variant % all.count) + all.count) % all.count
        return (0..<4).map { all[(start + $0) % all.count] }
    }

    func body(content: Content) -> some View {
        let kinds = Self.kinds(for: variant)
        content
            .overlay(alignment: .topLeading) {
                MascotFriendView(kind: kinds[0], size: size)
                    .offset(x: -10, y: -12)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                MascotFriendView(kind: kinds[1], size: size)
                    .offset(x: 10, y: -12)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                MascotFriendView(kind: kinds[2], size: size)
                    .offset(x: -10, y: 12)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                MascotFriendView(kind: kinds[3], size: size)
                    .offset(x: 10, y: 12)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Fills a card's empty corners with Tweaky and his
    /// friends — a different character in each corner, the
    /// lineup rotating with `variant`. Cards only: never on
    /// menu-row icons or tab-bar icons.
    func wtCardCornerFriends(variant: Int = 0, size: CGFloat = 24) -> some View {
        modifier(WTCardCornerFriends(variant: variant, size: size))
    }
}
