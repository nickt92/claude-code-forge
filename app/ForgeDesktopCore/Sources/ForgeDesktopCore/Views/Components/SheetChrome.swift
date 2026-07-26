import SwiftUI

// MARK: - Sheet Header

/// Unified header for every modal sheet: brand-tinted icon mark, title, optional
/// subtitle, optional trailing accessory.
struct ForgeSheetHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                    .fill(ForgeTheme.Colors.forgeOrange.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ForgeTheme.Colors.forgeText)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xxs) {
                Text(title)
                    .font(ForgeTheme.Typography.sheetTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(ForgeTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            trailing
        }
    }
}

extension ForgeSheetHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Sheet Container

/// Unified sheet shell: header, divider, content, optional footer bar.
/// Fixed width by default; pass `isResizable: true` for variable-height content
/// (e.g. Telemetry) to get `minWidth` instead of a fixed frame.
struct ForgeSheet<Content: View, HeaderTrailing: View, Footer: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    let width: CGFloat
    let isResizable: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let headerTrailing: HeaderTrailing
    @ViewBuilder let footer: Footer

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        width: CGFloat = ForgeTheme.Metrics.sheetWidth,
        isResizable: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder footer: () -> Footer
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.isResizable = isResizable
        self.content = content()
        self.headerTrailing = headerTrailing()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            ForgeSheetHeader(icon: icon, title: title, subtitle: subtitle) {
                headerTrailing
            }
            .padding(.horizontal, ForgeTheme.Spacing.xl)
            .padding(.vertical, ForgeTheme.Spacing.lg)

            Divider()

            content

            if Footer.self != EmptyView.self {
                Divider()
                footer
                    .padding(.horizontal, ForgeTheme.Spacing.xl)
                    .padding(.vertical, ForgeTheme.Spacing.md)
            }
        }
        .frame(minWidth: isResizable ? width : nil)
        .frame(width: isResizable ? nil : width)
    }
}

extension ForgeSheet where HeaderTrailing == EmptyView, Footer == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        width: CGFloat = ForgeTheme.Metrics.sheetWidth,
        isResizable: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            icon: icon, title: title, subtitle: subtitle, width: width,
            isResizable: isResizable, content: content,
            headerTrailing: { EmptyView() }, footer: { EmptyView() }
        )
    }
}

extension ForgeSheet where HeaderTrailing == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        width: CGFloat = ForgeTheme.Metrics.sheetWidth,
        isResizable: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(
            icon: icon, title: title, subtitle: subtitle, width: width,
            isResizable: isResizable, content: content,
            headerTrailing: { EmptyView() }, footer: footer
        )
    }
}

#Preview("ForgeSheet") {
    ForgeSheet(
        icon: "stethoscope",
        title: "System Doctor",
        subtitle: "Health checks for your forge installation"
    ) {
        Text("Sheet body")
            .frame(maxWidth: .infinity)
            .padding(ForgeTheme.Spacing.xl)
    } footer: {
        HStack {
            Spacer()
            Button("Done") {}
                .buttonStyle(.borderedProminent)
        }
    }
}
