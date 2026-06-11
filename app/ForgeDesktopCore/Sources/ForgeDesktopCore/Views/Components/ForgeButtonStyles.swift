import SwiftUI

// ButtonStyle cannot hold @State, so each style returns a wrapper view that owns
// hover tracking. Hover is reset in onDisappear because macOS does not reliably
// deliver onHover(false) when a view scrolls away or the window resigns key.

// MARK: - Primary (hero CTAs only)

/// Gradient hero button. HIG note: this intentionally bypasses the system default-button
/// treatment, so it is reserved for at most 1–2 hero CTAs per flow. Sheet confirm/dismiss
/// buttons stay `.borderedProminent`/`.bordered` and pick up the brand AccentColor.
struct ForgePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration)
    }

    private struct PrimaryBody: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, ForgeTheme.Spacing.lg)
                .padding(.vertical, ForgeTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                        .fill(ForgeTheme.Gradients.hero)
                        .overlay(
                            RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                                .fill(.white.opacity(isHovered ? 0.12 : 0))
                        )
                )
                .forgeShadow(isHovered ? ForgeTheme.Elevation.raised : ForgeTheme.Elevation.card)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .forgeAnimation(.easeOut(duration: 0.12), value: isHovered)
                .forgeAnimation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { isHovered = $0 }
                .onDisappear { isHovered = false }
        }
    }
}

// MARK: - Secondary

struct ForgeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration)
    }

    private struct SecondaryBody: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, ForgeTheme.Spacing.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                        .fill(isHovered ? ForgeTheme.Colors.hoverWash : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                        .stroke(.quaternary)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .forgeAnimation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
                .onDisappear { isHovered = false }
        }
    }
}

// MARK: - Icon

/// 28×28 icon-only button. Callers MUST set `.help(...)` and `accessibilityLabel`
/// — `.help` alone is not announced by VoiceOver.
struct ForgeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(
                    width: ForgeTheme.Metrics.iconButtonSize,
                    height: ForgeTheme.Metrics.iconButtonSize
                )
                .background(
                    RoundedRectangle(cornerRadius: ForgeTheme.Metrics.chipRadius)
                        .fill(isHovered ? ForgeTheme.Colors.hoverWash : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: ForgeTheme.Metrics.chipRadius))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .forgeAnimation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
                .onDisappear { isHovered = false }
        }
    }
}

// MARK: - Pill

/// Capsule action button for inline contexts (filter chips, finding fix actions).
struct ForgePillButtonStyle: ButtonStyle {
    var tint: Color = ForgeTheme.Colors.forgeText
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, tint: tint, isActive: isActive)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let tint: Color
        let isActive: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(ForgeTheme.Typography.micro)
                .foregroundStyle(isActive ? ForgeTheme.Colors.onTint : tint)
                .padding(.horizontal, ForgeTheme.Spacing.sm + 2)
                .padding(.vertical, ForgeTheme.Spacing.xs)
                .background(
                    Capsule().fill(
                        isActive
                            ? AnyShapeStyle(tint)
                            : AnyShapeStyle(tint.opacity(isHovered ? 0.2 : 0.12))
                    )
                )
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .forgeAnimation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
                .onDisappear { isHovered = false }
        }
    }
}

// MARK: - Static accessors

extension ButtonStyle where Self == ForgePrimaryButtonStyle {
    static var forgePrimary: ForgePrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == ForgeSecondaryButtonStyle {
    static var forgeSecondary: ForgeSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == ForgeIconButtonStyle {
    static var forgeIcon: ForgeIconButtonStyle { .init() }
}

extension ButtonStyle where Self == ForgePillButtonStyle {
    static var forgePill: ForgePillButtonStyle { .init() }

    static func forgePill(tint: Color, isActive: Bool = false) -> ForgePillButtonStyle {
        .init(tint: tint, isActive: isActive)
    }
}

#Preview("Button styles") {
    VStack(spacing: ForgeTheme.Spacing.lg) {
        Button("Generate with Claude") {}
            .buttonStyle(.forgePrimary)
        Button("Secondary Action") {}
            .buttonStyle(.forgeSecondary)
        HStack {
            Button {} label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.forgeIcon)
            Button {} label: { Image(systemName: "stethoscope") }
                .buttonStyle(.forgeIcon)
        }
        HStack {
            Button("Fix") {}
                .buttonStyle(.forgePill)
            Button("Errors") {}
                .buttonStyle(.forgePill(tint: .red, isActive: true))
        }
    }
    .padding(ForgeTheme.Spacing.xl)
}
