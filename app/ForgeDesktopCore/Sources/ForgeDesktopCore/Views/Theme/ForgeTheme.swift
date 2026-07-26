import AppKit
import SwiftUI

public enum ForgeTheme {
    // MARK: - Colors

    public enum Colors {
        // Brand
        public static let forgeOrange = Color(red: 0.902, green: 0.494, blue: 0.133)
        public static let forgeAmber = Color(red: 0.937, green: 0.604, blue: 0.157)
        public static let forgeDark = Color(red: 0.169, green: 0.122, blue: 0.075)
        public static let forgeGlow = Color(red: 1.0, green: 0.647, blue: 0.0)

        /// Text-grade brand orange. `forgeOrange` is ~2.5:1 on white and fails WCAG AA,
        /// so any orange text or badge foreground on a light surface must use this instead.
        public static let forgeText = dynamic(
            light: NSColor(srgbRed: 0.580, green: 0.310, blue: 0.0, alpha: 1.0),
            dark: NSColor(srgbRed: 1.0, green: 0.690, blue: 0.290, alpha: 1.0)
        )

        /// Deep ember fills for the hero gradient button — dark enough that white
        /// body-size text clears 4.5:1 (emberLight ≈ 4.7:1, emberDeep ≈ 5.6:1).
        public static let emberLight = Color(red: 0.82, green: 0.26, blue: 0.059)
        public static let emberDeep = Color(red: 0.737, green: 0.231, blue: 0.043)

        /// Foreground for text rendered ON a tint fill (filled badges, active pills).
        /// Dark-mode tints are light (e.g. forgeText's dark variant), so white-on-tint
        /// fails there — this flips to near-black where the tint is light.
        public static let onTint = dynamic(
            light: NSColor.white,
            dark: NSColor.black.withAlphaComponent(0.85)
        )

        // Semantic
        public static let success = Color.green
        public static let warning = Color.orange
        public static let danger = Color.red
        public static let info = Color.blue

        // Surfaces
        public static let surface = Color(nsColor: .controlBackgroundColor)
        public static let surfaceRaised = Color(nsColor: .windowBackgroundColor)

        /// Washes derive from system colors so they track appearance and the
        /// user's accent preference instead of fighting them.
        public static let hoverWash = Color.primary.opacity(0.06)
        public static let selectedWash = Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)

        static func dynamic(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        }
    }

    // MARK: - Gradients

    public enum Gradients {
        public static let forge = LinearGradient(
            colors: [Colors.forgeOrange, Colors.forgeAmber],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        public static let subtleBg = LinearGradient(
            colors: [Colors.forgeOrange.opacity(0.06), Color.clear],
            startPoint: .top, endPoint: .bottom
        )
        /// Hero CTA fill — ember tones, AA-safe under white text.
        public static let hero = LinearGradient(
            colors: [Colors.emberLight, Colors.emberDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Spacing (4pt scale)

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    // MARK: - Typography

    public enum Typography {
        public static let screenTitle = Font.system(size: 20, weight: .bold)
        public static let sheetTitle = Font.system(size: 15, weight: .semibold)
        public static let cardTitle = Font.system(size: 12, weight: .bold)
        public static let rowTitle = Font.system(size: 13, weight: .semibold)
        public static let body = Font.system(size: 12)
        public static let caption = Font.system(size: 11)
        public static let micro = Font.system(size: 10, weight: .medium)
        public static let mono = Font.system(size: 11, design: .monospaced)
        public static let score = Font.system(size: 13, weight: .bold, design: .rounded)
    }

    // MARK: - Elevation

    public struct ShadowToken: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let y: CGFloat

        public init(color: Color, radius: CGFloat, y: CGFloat) {
            self.color = color
            self.radius = radius
            self.y = y
        }
    }

    /// Shadow colors are appearance-dynamic: subtle in light mode, much stronger in
    /// dark mode where low-opacity black disappears against dark surfaces. Cards pair
    /// these with a stroke so elevation reads in both appearances.
    public enum Elevation {
        public static let flat = ShadowToken(color: .clear, radius: 0, y: 0)
        public static let card = ShadowToken(color: shadowColor(light: 0.08, dark: 0.45), radius: 5, y: 2)
        public static let raised = ShadowToken(color: shadowColor(light: 0.13, dark: 0.6), radius: 10, y: 4)
        public static let overlay = ShadowToken(color: shadowColor(light: 0.2, dark: 0.7), radius: 24, y: 8)

        private static func shadowColor(light: CGFloat, dark: CGFloat) -> Color {
            Colors.dynamic(
                light: NSColor.black.withAlphaComponent(light),
                dark: NSColor.black.withAlphaComponent(dark)
            )
        }
    }

    // MARK: - Animations

    public enum Animations {
        public static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.7)
        public static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.6)
        public static let easeReveal = Animation.easeOut(duration: 0.4)
        public static let staggerDelay: Double = 0.05
        /// Hard cap for staggered entrances — restrained beats theatrical.
        public static let staggerBudget: Double = 0.2
    }

    // MARK: - Metrics

    public enum Metrics {
        public static let cardRadius: CGFloat = 12
        public static let chipRadius: CGFloat = 6
        public static let rowRadius: CGFloat = 8
        public static let spacing: CGFloat = 8
        public static let sheetWidth: CGFloat = 540
        public static let iconButtonSize: CGFloat = 28
    }
}

// MARK: - View Helpers

extension View {
    public func forgeShadow(_ token: ForgeTheme.ShadowToken) -> some View {
        shadow(color: token.color, radius: token.radius, y: token.y)
    }

    /// Value-driven animation that honors Reduce Motion.
    public func forgeAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(ForgeAnimationModifier(animation: animation, value: value))
    }

    /// Hover wash for interactive elements OUTSIDE List contexts (menu bar rows,
    /// icon buttons, cards). List rows get system hover/selection — never both.
    public func forgeHoverHighlight(radius: CGFloat = ForgeTheme.Metrics.rowRadius) -> some View {
        modifier(ForgeHoverHighlightModifier(radius: radius))
    }
}

/// Imperative counterpart to `.forgeAnimation` for `withAnimation` call sites.
@MainActor
public func forgeWithAnimation<Result>(
    _ animation: Animation = ForgeTheme.Animations.springSnappy,
    _ body: () throws -> Result
) rethrows -> Result {
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    return try withAnimation(reduceMotion ? nil : animation, body)
}

private struct ForgeAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct ForgeHoverHighlightModifier: ViewModifier {
    @State private var isHovered = false
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(isHovered ? ForgeTheme.Colors.hoverWash : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .onDisappear {
                isHovered = false
            }
    }
}
