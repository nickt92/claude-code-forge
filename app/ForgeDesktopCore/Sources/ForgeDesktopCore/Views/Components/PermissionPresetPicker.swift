import SwiftUI

/// Data-driven permission preset picker, backed by `forge permissions --list --json`.
/// Replaces the preset lists that were previously hardcoded (and duplicated) in
/// SettingsView and SetupWizardView — the CLI is the single source of truth.
///
/// The component owns loading and selection; the host owns apply semantics
/// (Settings applies on selection change, the setup wizard applies on continue).
struct PermissionPresetPicker: View {
    @Binding var selection: String?
    var recommendedId: String? = "full-autonomy"
    var isDisabled: Bool = false
    var onPresetsLoaded: (([PermissionPreset]) -> Void)?

    @Environment(\.permissionsService) private var permissionsService
    @State private var presets: [PermissionPreset] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var expandedId: String?

    var body: some View {
        Group {
            if isLoading {
                SkeletonGroup {
                    VStack(spacing: ForgeTheme.Spacing.xs + 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonBox(width: nil, height: 52, radius: ForgeTheme.Metrics.rowRadius)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading permission presets")
            } else if let loadError {
                HStack(spacing: ForgeTheme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ForgeTheme.Colors.warning)
                        .accessibilityHidden(true)
                    Text(loadError)
                        .font(ForgeTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await load() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(ForgeTheme.Spacing.sm)
                .background(
                    ForgeTheme.Colors.warning.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                )
            } else {
                VStack(spacing: ForgeTheme.Spacing.xs + 2) {
                    ForEach(presets.sorted { $0.tier < $1.tier }) { preset in
                        presetRow(preset)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func presetRow(_ preset: PermissionPreset) -> some View {
        let isSelected = selection == preset.id
        let isExpanded = expandedId == preset.id

        return Button {
            guard !isDisabled, !isSelected else { return }
            selection = preset.id
        } label: {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
                HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .font(.system(size: 14))
                        .accessibilityHidden(true)

                    Text(preset.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    if preset.id == recommendedId {
                        StatusBadge("Recommended", tint: ForgeTheme.Colors.forgeText, style: .filled)
                    }

                    Spacer()

                    StatusBadge("Tier \(preset.tier)", tint: .secondary, style: .outline)
                }

                Text(preset.description)
                    .font(ForgeTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)

                if isExpanded {
                    VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
                        Text(preset.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: ForgeTheme.Spacing.xs) {
                            StatusBadge(
                                "\(preset.permissions.count) rules",
                                icon: "checkmark.shield",
                                tint: ForgeTheme.Colors.success
                            )
                            if let inherits = preset.inherits, !inherits.isEmpty {
                                StatusBadge(
                                    "Includes \(label(forPresetId: inherits))",
                                    icon: "arrow.turn.down.right",
                                    tint: ForgeTheme.Colors.info
                                )
                            }
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.top, ForgeTheme.Spacing.xxs)
                    .transition(.opacity)
                }

                Button {
                    forgeWithAnimation(.easeInOut(duration: 0.2)) {
                        expandedId = isExpanded ? nil : preset.id
                    }
                } label: {
                    HStack(spacing: ForgeTheme.Spacing.xxs) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                            .accessibilityHidden(true)
                        Text("Details")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide \(preset.label) details" : "Show \(preset.label) details")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ForgeTheme.Spacing.md)
            .padding(.vertical, ForgeTheme.Spacing.sm + 2)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .accessibilityLabel(
            isSelected
                ? "\(preset.label), selected"
                : "Select \(preset.label) preset"
        )
    }

    private func label(forPresetId id: String) -> String {
        presets.first { $0.id == id }?.label ?? id.formattedAsTitle
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let loaded = try await permissionsService.listPresets()
            presets = loaded
            onPresetsLoaded?(loaded)
        } catch {
            loadError = "Couldn't load presets: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
