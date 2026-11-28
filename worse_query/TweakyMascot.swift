import SwiftUI

// MARK: - Tweaky, the WorkTweaks mascot
//
// Drawn entirely in SwiftUI shapes — no image asset. Tweaky is
// a blue round character: a light-blue circle with a darker blue
// outline, an antenna topped by a yellow dot, two white eyes
// with black pupils, pink cheeks, and a smile.
//
// The view is sized by `size` (the body diameter); the total
// height is 1.24x to leave room for the antenna. All features
// are positioned in units of `size`, so the mascot scales
// cleanly from the 30pt corner decorations on the onboarding
// pages to any larger use. Decoration only: hidden from
// VoiceOver.

struct TweakyMascot: View {
    /// Body diameter in points. The onboarding corners use 30.
    var size: CGFloat = 30

    // Character colors, fixed so Tweaky looks the same in
    // light and dark mode and under every language theme.
    private static let bodyBlue = Color(red: 0.49, green: 0.78, blue: 0.96)
    private static let outlineBlue = Color(red: 0.05, green: 0.48, blue: 0.85)
    private static let dotYellow = Color(red: 1.0, green: 0.76, blue: 0.03)
    private static let cheekPink = Color(red: 0.96, green: 0.66, blue: 0.75)
    private static let dark = Color(red: 0.10, green: 0.11, blue: 0.13)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            // Antenna stem: from the top of the head upward,
            // ending just under the yellow dot.
            RoundedRectangle(cornerRadius: s * 0.02, style: .continuous)
                .fill(Self.outlineBlue)
                .frame(width: s * 0.04, height: s * 0.17)
                .position(x: s * 0.5, y: s * 0.175)
            // Antenna dot.
            Circle()
                .fill(Self.dotYellow)
                .frame(width: s * 0.15, height: s * 0.15)
                .overlay(
                    Circle()
                        .stroke(Self.outlineBlue, lineWidth: s * 0.012)
                )
                .position(x: s * 0.5, y: s * 0.08)
            // Round body with the darker blue outline.
            Circle()
                .fill(Self.bodyBlue)
                .frame(width: s, height: s)
                .overlay(
                    Circle()
                        .stroke(Self.outlineBlue, lineWidth: s * 0.03)
                )
                .position(x: s * 0.5, y: s * 0.74)
            // Eyes: white circles with black pupils.
            Circle()
                .fill(.white)
                .frame(width: s * 0.20, height: s * 0.20)
                .position(x: s * 0.32, y: s * 0.66)
            Circle()
                .fill(.white)
                .frame(width: s * 0.20, height: s * 0.20)
                .position(x: s * 0.68, y: s * 0.66)
            Circle()
                .fill(Self.dark)
                .frame(width: s * 0.105, height: s * 0.105)
                .position(x: s * 0.32, y: s * 0.675)
            Circle()
                .fill(Self.dark)
                .frame(width: s * 0.105, height: s * 0.105)
                .position(x: s * 0.68, y: s * 0.675)
            // Pink cheeks, outside and below the eyes.
            Circle()
                .fill(Self.cheekPink)
                .frame(width: s * 0.13, height: s * 0.13)
                .position(x: s * 0.18, y: s * 0.86)
            Circle()
                .fill(Self.cheekPink)
                .frame(width: s * 0.13, height: s * 0.13)
                .position(x: s * 0.82, y: s * 0.86)
            // Smile: a shallow curve dipping below the eyes.
            SmileShape()
                .stroke(Self.dark, style: StrokeStyle(lineWidth: s * 0.032, lineCap: .round))
                .frame(width: s * 0.32, height: s * 0.14)
                .position(x: s * 0.5, y: s * 0.86)
        }
        .frame(width: size, height: size * 1.24)
        .accessibilityHidden(true)
    }
}

/// A smile curve: a quadratic Bezier from the left end to the
/// right end, dipping through a control point below the middle.
private struct SmileShape: Shape {
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

// MARK: - Animated Tweaky (Apply-success popup)
//
// The same mascot with a happy motion — a gentle vertical
// bounce, a subtle scale pulse, and a slight side-to-side
// wiggle (antenna included). Real SwiftUI animation: one
// @State boolean drives offset + scale + rotation through a
// single .easeInOut animation repeating forever with
// autoreverses, so the three motions stay in sync.
// Lightweight and non-blocking; the animation stops with the
// view when the popup is dismissed. Used by the Apply-success
// popup in the Tweaks tab.
struct AnimatedTweakyMascot: View {
    /// Body diameter in points. The Apply-success popup uses 90.
    var size: CGFloat = 90

    @State private var bouncing = false

    var body: some View {
        TweakyMascot(size: size)
            .offset(y: bouncing ? -size * 0.08 : size * 0.04)
            .scaleEffect(bouncing ? 1.05 : 0.97)
            .rotationEffect(.degrees(bouncing ? 3 : -3))
            .animation(
                .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                value: bouncing
            )
            .onAppear { bouncing = true }
    }
}
