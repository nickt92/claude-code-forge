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
    @Environment(\.configService) private var configService
    @Environment(\.permissionsService) private var permissionsService

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
                        withAnimation { showPermissionPicker.toggle() }
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
                    permissionPickerRows
                }

                if let presetError {
                    Text(presetError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
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
                            .foregroundStyle(.orange)
                            .font(.system(size: 11))
                        Text("Scanning a broad directory may be slow and trigger macOS permission prompts. Consider a specific directory like ~/code.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .frame(minHeight: 400, idealHeight: 520)
    }

    private func autoDetectStatus(isResolving: Bool, resolvedPath: String, label: String) -> some View {
        HStack(spacing: 6) {
            if isResolving {
                ProgressView()
                    .controlSize(.mini)
            } else if !resolvedPath.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
                Text("Found: \(resolvedPath)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
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

    private var currentPresetLabel: String {
        switch currentPresetName {
        case "ask-before-changes": return "Ask Before Changes"
        case "auto-edit": return "Auto-Edit"
        case "full-autonomy": return "Full Autonomy (Recommended)"
        case nil: return "None"
        default: return currentPresetName ?? "None"
        }
    }

    private func presetDescription(for name: String) -> String {
        switch name {
        case "ask-before-changes":
            return "Claude browses your code without asking, but asks before making changes."
        case "auto-edit":
            return "Claude browses and edits files without asking. Still asks before running commands."
        case "full-autonomy":
            return "Claude runs dev commands without asking. Still asks before destructive operations."
        default:
            return ""
        }
    }

    private var permissionPickerRows: some View {
        VStack(spacing: 6) {
            ForEach(
                [("ask-before-changes", "Ask Before Changes", false),
                 ("auto-edit", "Auto-Edit", false),
                 ("full-autonomy", "Full Autonomy", true)],
                id: \.0
            ) { id, label, recommended in
                HStack {
                    Image(systemName: currentPresetName == id ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(currentPresetName == id ? Color.accentColor : .secondary)
                        .font(.system(size: 13))

                    Text(label)
                        .font(.system(size: 11, weight: .medium))

                    if recommended {
                        Text("Recommended")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }

                    Spacer()

                    if applyingPreset && currentPresetName != id {
                        ProgressView().controlSize(.mini)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !applyingPreset, currentPresetName != id else { return }
                    applyPreset(id)
                }
                .padding(.vertical, 4)
            }
        }
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
