import SwiftUI

/// The standard content card: uppercase title, optional SF Symbol, optional trailing
/// accessory (per-card actions), elevation that reads in light and dark mode, and an
/// optional hover lift for cards that act as targets.
struct ForgeCard<Content: View, Trailing: View>: View {
    let title: String?
    let icon: String?
    let accent: Color?
    let isHoverable: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    @State private var isHovered = false

    init(
        _ title: String? = nil,
        icon: String? = nil,
        accent: Color? = nil,
        isHoverable: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.isHoverable = isHoverable
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.md) {
            if title != nil {
                header
            }
            content
        }
        .padding(ForgeTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ForgeTheme.Colors.surface,
            in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
                .stroke(.quaternary)
        )
        .forgeShadow(isHoverable && isHovered ? ForgeTheme.Elevation.raised : ForgeTheme.Elevation.card)
        .forgeAnimation(ForgeTheme.Animations.springSnappy, value: isHovered)
        .onHover { hovering in
            guard isHoverable else { return }
            isHovered = hovering
        }
        .onDisappear {
            isHovered = false
        }
    }

    private var header: some View {
        HStack(spacing: ForgeTheme.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent ?? ForgeTheme.Colors.forgeText)
                    .accessibilityHidden(true)
            }
            if let title {
                Text(title)
                    .font(ForgeTheme.Typography.cardTitle)
                    .foregroundStyle(accent ?? .secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension ForgeCard where Trailing == EmptyView {
    init(
        _ title: String? = nil,
        icon: String? = nil,
        accent: Color? = nil,
        isHoverable: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, icon: icon, accent: accent, isHoverable: isHoverable, content: content) {
            EmptyView()
        }
    }
}

#Preview("ForgeCard variants") {
    VStack(spacing: ForgeTheme.Spacing.lg) {
        ForgeCard("Score Breakdown", icon: "chart.bar.fill") {
            Text("Card body content")
        }
        ForgeCard("Findings", icon: "exclamationmark.bubble", content: {
            Text("Card with trailing action")
        }, trailing: {
            Button("Fix All") {}
                .controlSize(.small)
        })
        ForgeCard("Hoverable", icon: "cursorarrow.rays", isHoverable: true) {
            Text("Lifts on hover")
        }
    }
    .padding(ForgeTheme.Spacing.xl)
    .frame(width: 420)
}
