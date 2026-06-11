import SwiftUI

/// The one capsule badge. Consolidates the hand-rolled capsules that previously lived
/// in CountBadge, SectionTag, FindingRow fix states, persona axis chips, and the
/// setup wizard's "Recommended" pill.
///
/// Foreground contrast: pass text-grade tints (`ForgeTheme.Colors.forgeText`, semantic
/// colors) for `.subtle`/`.outline`; `.filled` uses white on the tint.
struct StatusBadge: View {
    enum Style {
        /// Tinted text on a soft tint wash — the default.
        case subtle
        /// White text on a solid tint fill.
        case filled
        /// Tinted text with a tint stroke, transparent fill.
        case outline
    }

    let text: String
    var icon: String?
    var tint: Color = .secondary
    var style: Style = .subtle

    init(_ text: String, icon: String? = nil, tint: Color = .secondary, style: Style = .subtle) {
        self.text = text
        self.icon = icon
        self.tint = tint
        self.style = style
    }

    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(ForgeTheme.Typography.micro)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, ForgeTheme.Spacing.sm)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
        .overlay {
            if case .outline = style {
                Capsule().stroke(tint.opacity(0.4))
            }
        }
    }

    private var foreground: Color {
        switch style {
        case .filled: ForgeTheme.Colors.onTint
        case .subtle, .outline: tint
        }
    }

    private var background: Color {
        switch style {
        case .filled: tint
        case .subtle: tint.opacity(0.12)
        case .outline: .clear
        }
    }
}

#Preview("Badges") {
    VStack(alignment: .leading, spacing: ForgeTheme.Spacing.md) {
        HStack {
            StatusBadge("3", tint: ForgeTheme.Colors.danger)
            StatusBadge("Fixed", icon: "checkmark", tint: ForgeTheme.Colors.success)
            StatusBadge("Recommended", tint: ForgeTheme.Colors.forgeText, style: .filled)
        }
        HStack {
            StatusBadge("technical", style: .outline)
            StatusBadge("Testing", tint: ForgeTheme.Colors.success)
            StatusBadge("Missing", tint: ForgeTheme.Colors.danger)
        }
    }
    .padding(ForgeTheme.Spacing.xl)
}
