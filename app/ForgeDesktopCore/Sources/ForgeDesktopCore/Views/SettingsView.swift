import SwiftUI

public struct SettingsView: View {
    @AppStorage("forgeBinaryPath") private var forgePath: String = ""
    @AppStorage("claudeBinaryPath") private var claudePath: String = ""
    @State private var resolvedPath: String = ""
    @State private var resolvedClaudePath: String = ""
    @State private var isResolvingForge = false
    @State private var isResolvingClaude = false
    @State private var scanPath: String = ""
    @State private var scanPathLoaded = false
    @State private var isRescanning = false
    @State private var currentPresetName: String?
    @State private var permissionsLoaded = false
    @State private var showPermissionPicker = false
    @State private var applyingPreset = false
    @State private var presetError: String?
    @State private var loadedPresets: [PermissionPreset] = []
    @State private var showStatuslineLegend = false
    @State private var forgeStatus: ForgeStatus?
    @State private var statusLoadFailed = false
    @State private var showUpdateConfirm = false
    @State private var isUpdating = false
    @State private var updateError: String?
    @State private var updateLog = ""
    @Environment(\.configService) private var configService
    @Environment(\.permissionsService) private var permissionsService
    @Environment(\.statusService) private var statusService
    @Environment(\.updateService) private var updateService
    @Environment(\.forgeState) private var forgeState

    var onRescan: (() async -> Void)?

    public init(onRescan: (() async -> Void)? = nil) {
        self.onRescan = onRescan
    }

    public var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Path to forge binary", text: $forgePath, prompt: Text("Auto-detect"))
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        browseForFile { forgePath = $0 }
                    }
                }

                if forgePath.isEmpty {
                    autoDetectStatus(isResolving: isResolvingForge, resolvedPath: resolvedPath, label: "Forge CLI")
                        .task { await resolveAutoPath() }
                }
            } header: {
                Text("Forge Binary")
            } footer: {
                Text("Changes take effect after restarting Forge.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section {
                HStack {
                    TextField("Path to claude binary", text: $claudePath, prompt: Text("Auto-detect"))
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        browseForFile { claudePath = $0 }
                    }
                }

                if claudePath.isEmpty {
                    autoDetectStatus(isResolving: isResolvingClaude, resolvedPath: resolvedClaudePath, label: "Claude Code CLI")
                        .task { await resolveClaudePath() }
                }
            } header: {
                Text("Claude Code Binary")
            } footer: {
                Text("Changes take effect after restarting Forge.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current: \(currentPresetLabel)")
                            .font(.system(size: 12))
                        if let name = currentPresetName {
                            Text(presetDescription(for: name))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(showPermissionPicker ? "Done" : "Change...") {
                        forgeWithAnimation { showPermissionPicker.toggle() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .task {
                    guard !permissionsLoaded else { return }
                    permissionsLoaded = true
                    await loadCurrentPreset()
                }

                if showPermissionPicker {
                    HStack(spacing: ForgeTheme.Spacing.sm) {
                        PermissionPresetPicker(
                            selection: Binding(
                                get: { currentPresetName },
                                set: { newValue in
                                    if let newValue { applyPreset(newValue) }
                                }
                            ),
                            isDisabled: applyingPreset,
                            onPresetsLoaded: { loadedPresets = $0 }
                        )
                        if applyingPreset {
                            ProgressView().controlSize(.small)
                        }
                    }
                }

                if let presetError {
                    Text(presetError)
                        .font(.system(size: 11))
                        .foregroundStyle(ForgeTheme.Colors.danger)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Controls what Claude Code can do without asking permission.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section("Repository Scanning") {
                HStack {
                    TextField("Scan path", text: $scanPath, prompt: Text("~/code"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !scanPath.isEmpty {
                                Task { try? await configService.setScanPath(scanPath) }
                            }
                        }

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            scanPath = url.path
                            Task { try? await configService.setScanPath(scanPath) }
                        }
                    }
                }
                .task {
                    guard !scanPathLoaded else { return }
                    scanPathLoaded = true
                    if let path = try? await configService.getScanPath() {
                        scanPath = path
                    }
                }

                if Self.isBroadScanPath(scanPath) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(ForgeTheme.Colors.warning)
                            .font(.system(size: 11))
                        Text("Scanning a broad directory may be slow and trigger macOS permission prompts. Consider a specific directory like ~/code.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(ForgeTheme.Colors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.chipRadius))
                }

                Button {
                    if !scanPath.isEmpty {
                        Task { try? await configService.setScanPath(scanPath) }
                    }
                    isRescanning = true
                    Task {
                        await onRescan?()
                        isRescanning = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRescanning {
                            ProgressView().controlSize(.mini)
                        }
                        Text("Rescan Now")
                    }
                }
                .disabled(isRescanning)
            }

            Section {
                aboutContent
            } header: {
                Text("About")
            } footer: {
                if forgeStatus?.reinstallPending == true {
                    Text("Updating fetches the latest changes into your forge source repo (fast-forward only) and reinstalls to ~/.claude.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .sheet(isPresented: $showStatuslineLegend) {
                StatuslineLegendView()
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .frame(minHeight: 400, idealHeight: 560)
        .task { await loadStatus() }
        .confirmationDialog(
            "Update Forge?",
            isPresented: $showUpdateConfirm,
            titleVisibility: .visible
        ) {
            Button("Update and Reinstall") { runUpdate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This fetches the latest changes from origin into your forge source repo (fast-forward only) and reinstalls forge to ~/.claude. The app itself is not modified.")
        }
    }

    // MARK: - About / Status

    @ViewBuilder
    private var aboutContent: some View {
        LabeledContent("App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")

        if let status = forgeStatus {
            LabeledContent("Forge CLI") {
                HStack(spacing: ForgeTheme.Spacing.sm) {
                    Text("v\(status.version.installed)")
                    if status.reinstallPending {
                        StatusBadge(
                            "v\(status.version.source) ready to install",
                            icon: "arrow.down.circle",
                            tint: ForgeTheme.Colors.info
                        )
                    } else {
                        StatusBadge("Up to date", icon: "checkmark", tint: ForgeTheme.Colors.success)
                    }
                }
            }
            LabeledContent("Persona", value: status.persona.label)
            LabeledContent("Plugins", value: "\(status.plugins.count) (\(status.plugins.group) group)")
            LabeledContent("Hooks", value: "\(status.hooks.count)")
            if let date = status.installedAtDate {
                LabeledContent("Installed", value: date.formatted(date: .abbreviated, time: .shortened))
            }

            if status.reinstallPending {
                HStack(spacing: ForgeTheme.Spacing.sm) {
                    Button {
                        showUpdateConfirm = true
                    } label: {
                        HStack(spacing: ForgeTheme.Spacing.xs) {
                            if isUpdating {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .accessibilityHidden(true)
                            }
                            Text(isUpdating ? "Updating…" : "Install Update")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isUpdating)
                    .accessibilityLabel("Install forge update")
                }
            }

            if let updateError {
                Text(updateError)
                    .font(ForgeTheme.Typography.caption)
                    .foregroundStyle(ForgeTheme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !updateLog.isEmpty {
                DisclosureGroup("Update Log") {
                    Text(updateLog)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(ForgeTheme.Typography.caption)
            }
        } else if statusLoadFailed {
            HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ForgeTheme.Colors.warning)
                    .font(.system(size: 11))
                    .accessibilityHidden(true)
                Text("Couldn't read forge status — is the CLI installed?")
                    .font(ForgeTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: ForgeTheme.Spacing.sm) {
                ProgressView().controlSize(.mini)
                Text("Reading installation status…")
                    .font(ForgeTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Button("Statusline Guide...") {
            showStatuslineLegend = true
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func loadStatus() async {
        statusLoadFailed = false
        do {
            forgeStatus = try await statusService.status()
            // Keep the shared state in sync so the menu bar and dashboard badges
            // clear immediately after an in-app update instead of lagging until
            // the next dashboard refresh.
            forgeState.forgeStatus = forgeStatus
        } catch {
            statusLoadFailed = true
        }
    }

    private func runUpdate() {
        isUpdating = true
        updateError = nil
        updateLog = ""
        Task {
            do {
                updateLog = try await updateService.update()
                await loadStatus()
            } catch {
                updateError = error.localizedDescription
            }
            isUpdating = false
        }
    }

    private func autoDetectStatus(isResolving: Bool, resolvedPath: String, label: String) -> some View {
        HStack(spacing: 6) {
            if isResolving {
                ProgressView()
                    .controlSize(.mini)
            } else if !resolvedPath.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ForgeTheme.Colors.success)
                    .font(.system(size: 12))
                Text("Found: \(resolvedPath)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ForgeTheme.Colors.warning)
                    .font(.system(size: 12))
                Text("\(label) not found — set the path above")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func browseForFile(_ setter: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            setter(url.path)
        }
    }

    private func resolveAutoPath() async {
        isResolvingForge = true
        defer { isResolvingForge = false }

        let service = ForgeService()
        if let path = try? await service.discoverForgePath() {
            resolvedPath = path
        }
    }

    private func resolveClaudePath() async {
        isResolvingClaude = true
        defer { isResolvingClaude = false }
        let service = ClaudeService()
        if service.isAvailable {
            resolvedClaudePath = "claude"
        }
    }

    static func isBroadScanPath(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        let home = NSHomeDirectory()
        return expanded == home || expanded == "/" || expanded == "/Users"
    }

    // MARK: - Permissions Helpers

    /// Resolved from the CLI's preset list when loaded; falls back to a formatted id
    /// so the summary row never shows a stale hardcoded label.
    private var currentPresetLabel: String {
        guard let currentPresetName else { return "None" }
        return loadedPresets.first { $0.id == currentPresetName }?.label
            ?? currentPresetName.formattedAsTitle
    }

    private func presetDescription(for name: String) -> String {
        loadedPresets.first { $0.id == name }?.description ?? ""
    }

    private func loadCurrentPreset() async {
        do {
            let state = try await permissionsService.currentState()
            currentPresetName = state.currentPreset == "none" ? nil : state.currentPreset
        } catch {
            currentPresetName = nil
        }
    }

    private func applyPreset(_ name: String) {
        applyingPreset = true
        presetError = nil
        Task {
            do {
                try await permissionsService.applyPreset(name: name)
                currentPresetName = name
            } catch {
                presetError = "Failed to apply preset: \(error.localizedDescription)"
            }
            applyingPreset = false
        }
    }
}
