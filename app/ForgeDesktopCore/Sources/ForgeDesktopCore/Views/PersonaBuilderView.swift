import SwiftUI

/// Three-step wizard for creating a custom persona via `forge build`:
/// Name → Behavior (axes, quality, plugins) → Review & Create.
public struct PersonaBuilderView: View {
    /// Existing personas, used for fast-path name validation (CLI stays the authority).
    let builtinIds: [String]
    let customIds: [String]
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.personaBuilderService) private var builderService

    @State private var draft = PersonaDraft()
    @State private var step = 0
    @State private var isCreating = false
    @State private var createError: String?

    public init(
        builtinIds: [String],
        customIds: [String],
        onCreated: @escaping (String) -> Void
    ) {
        self.builtinIds = builtinIds
        self.customIds = customIds
        self.onCreated = onCreated
    }

    private var nameValidation: PersonaDraft.NameValidation {
        draft.validateName(builtinIds: builtinIds, customIds: customIds)
    }

    private var nameExists: Bool {
        customIds.contains(draft.personaKey)
    }

    public var body: some View {
        ForgeSheet(
            icon: "person.crop.circle.badge.plus",
            title: "Create Custom Persona",
            subtitle: "Step \(step + 1) of 3",
            content: {
                Group {
                    switch step {
                    case 0: nameStep
                    case 1: behaviorStep
                    default: reviewStep
                    }
                }
                .frame(minHeight: 320, alignment: .top)
                .padding(ForgeTheme.Spacing.xl)
                .forgeAnimation(ForgeTheme.Animations.springSnappy, value: step)
            },
            footer: { footerBar }
        )
    }

    // MARK: - Step 1: Name

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
                Text("What should this persona be called?")
                    .font(ForgeTheme.Typography.rowTitle)
                Text("Letters, numbers, and hyphens. The persona is saved as custom-<name>.")
                    .font(ForgeTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("e.g. backend-lead", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .font(ForgeTheme.Typography.mono)
                .accessibilityLabel("Persona name")

            switch nameValidation {
            case .valid:
                if !draft.name.isEmpty {
                    HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ForgeTheme.Colors.success)
                            .accessibilityHidden(true)
                        Text("Will be created as \(draft.personaKey)")
                            .font(ForgeTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .empty:
                EmptyView()
            case .invalidFormat:
                validationNote("Use letters, numbers, and hyphens — must start with a letter.", isError: true)
            case .builtinCollision:
                validationNote("A built-in persona named \"\(draft.name)\" already exists. Pick another name.", isError: true)
            case .customExists:
                VStack(alignment: .leading, spacing: ForgeTheme.Spacing.sm) {
                    validationNote("Custom persona \"\(draft.personaKey)\" already exists.", isError: false)
                    Toggle("Overwrite the existing persona", isOn: $draft.force)
                        .font(ForgeTheme.Typography.caption)
                }
            }

            Spacer()
        }
    }

    private func validationNote(_ text: String, isError: Bool) -> some View {
        HStack(spacing: ForgeTheme.Spacing.xs + 2) {
            Image(systemName: isError ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isError ? ForgeTheme.Colors.danger : ForgeTheme.Colors.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(ForgeTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 2: Behavior

    private var behaviorStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.lg) {
                axisPicker(.communication, selection: $draft.communication)
                axisPicker(.autonomy, selection: $draft.autonomy)
                axisPicker(.workflow, selection: $draft.workflow)
                axisPicker(.depth, selection: $draft.depth)

                Divider()

                Toggle(isOn: $draft.engineeringQuality) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Engineering quality standards")
                            .font(.system(size: 12, weight: .medium))
                        Text("Testing, performance, and accessibility requirements")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
                    Text("Plugin Group")
                        .font(.system(size: 12, weight: .medium))
                    Picker("Plugin Group", selection: $draft.pluginGroup) {
                        ForEach(PersonaDraft.pluginGroups, id: \.value) { group in
                            Text(group.value.capitalized).tag(group.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(PersonaDraft.pluginGroups.first { $0.value == draft.pluginGroup }?.description ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func axisPicker(_ axis: PersonaDraft.Axis, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
            Text(axis.label)
                .font(.system(size: 12, weight: .medium))
            Picker(axis.label, selection: selection) {
                ForEach(axis.options, id: \.value) { option in
                    Text(option.value.capitalized).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("\(axis.label) level")
            Text(axis.options.first { $0.value == selection.wrappedValue }?.description ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 3: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
                Text(draft.personaKey)
                    .font(ForgeTheme.Typography.rowTitle)
                Text("Review the configuration, then create the persona.")
                    .font(ForgeTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: ForgeTheme.Spacing.xs) {
                StatusBadge("comm: \(draft.communication)", tint: ForgeTheme.Colors.info)
                StatusBadge("auto: \(draft.autonomy)", tint: ForgeTheme.Colors.info)
                StatusBadge("flow: \(draft.workflow)", tint: ForgeTheme.Colors.info)
                StatusBadge("depth: \(draft.depth)", tint: ForgeTheme.Colors.info)
                StatusBadge(
                    draft.engineeringQuality ? "quality: engineering" : "quality: core",
                    tint: ForgeTheme.Colors.success
                )
                StatusBadge("plugins: \(draft.pluginGroup)", tint: ForgeTheme.Colors.forgeText)
                if draft.force {
                    StatusBadge("overwrites existing", icon: "exclamationmark.triangle", tint: ForgeTheme.Colors.warning)
                }
            }

            Toggle(isOn: $draft.switchAfterCreate) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Switch to this persona after creating")
                        .font(.system(size: 12, weight: .medium))
                    Text("Reassembles your CLAUDE.md with the new persona")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let createError {
                HStack(alignment: .top, spacing: ForgeTheme.Spacing.xs + 2) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ForgeTheme.Colors.danger)
                        .accessibilityHidden(true)
                    Text(createError)
                        .font(ForgeTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ForgeTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ForgeTheme.Colors.danger.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                )
            }

            Spacer()
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)

            Spacer()

            if step > 0 {
                Button("Back") {
                    forgeWithAnimation { step -= 1 }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCreating)
            }

            if step < 2 {
                Button("Continue") {
                    forgeWithAnimation { step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(nameValidation != .valid)
            } else {
                Button {
                    create()
                } label: {
                    HStack(spacing: ForgeTheme.Spacing.xs) {
                        if isCreating {
                            ProgressView().controlSize(.mini)
                        }
                        Text(isCreating ? "Creating…" : "Create Persona")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isCreating || nameValidation != .valid)
            }
        }
    }

    private func create() {
        isCreating = true
        createError = nil
        Task {
            do {
                _ = try await builderService.build(draft)
                onCreated(draft.personaKey)
                dismiss()
            } catch {
                createError = error.localizedDescription
            }
            isCreating = false
        }
    }
}
