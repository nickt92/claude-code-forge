import SwiftUI

/// Branded empty/error state: forge-tinted icon mark, title, message, optional actions.
/// Replaces the previous mix of `ContentUnavailableView` and ad-hoc VStacks.
struct ForgeEmptyState<Actions: View>: View {
    let icon: String
    let title: String
    let message: String?
    @ViewBuilder let actions: Actions

    init(
        icon: String,
        title: String,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: ForgeTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(ForgeTheme.Colors.forgeOrange.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(ForgeTheme.Gradients.forge)
            }
            .accessibilityHidden(true)

            VStack(spacing: ForgeTheme.Spacing.xs) {
                Text(title)
                    .font(ForgeTheme.Typography.rowTitle)
                if let message {
                    Text(message)
                        .font(ForgeTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actions
        }
        .padding(ForgeTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ForgeEmptyState where Actions == EmptyView {
    init(icon: String, title: String, message: String? = nil) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

#Preview("Empty state") {
    ForgeEmptyState(
        icon: "folder.badge.questionmark",
        title: "No Repositories Found",
        message: "Set a scan path in Settings to discover repositories."
    ) {
        Button("Open Settings") {}
            .buttonStyle(.forgeSecondary)
    }
    .frame(width: 320, height: 280)
}
