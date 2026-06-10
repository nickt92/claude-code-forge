import SwiftUI

public struct SetupWizardView: View {
    @Bindable var state: ForgeState
    @Environment(\.configService) private var configService
    @State private var detectedPath: String?
    @State private var detectError: String?
    @State private var claudeDetectedPath: String?
    @State private var claudeDetectError: String?
    @State private var claudeVersion: String?
    @State private var scanPath: String = ""
    @State private var loadError: String?
    @State private var selectedPreset: String = "full-autonomy"
    @State private var applyingPreset: Bool = false
    @State private var presetError: String?
    @State private var expandedPreset: String?
    @AppStorage("claudeBinaryPath") private var claudeBinaryPath: String = ""

    @Environment(\.permissionsService) private var permissionsService

    let forgeService: ForgeService
    let onComplete: () -> Void

    @Environment(\.claudeService) private var claudeService

    public init(state: ForgeState, forgeService: ForgeService, onComplete: @escaping () -> Void) {
        self.state = state
        self.forgeService = forgeService
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: ForgeTheme.Spacing.sm + 2) {
                ZStack {
                    Circle()
                        .fill(ForgeTheme.Colors.forgeOrange.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(ForgeTheme.Gradients.forge)
                }
                .accessibilityHidden(true)

                Text("Welcome to Forge")
                    .font(ForgeTheme.Typography.screenTitle)
                Text("Let's get your environment set up.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, ForgeTheme.Spacing.xl)

            stepIndicator
                .padding(.bottom, ForgeTheme.Spacing.xl)
                .forgeAnimation(ForgeTheme.Animations.springSnappy, value: stepNumber)

            Divider()

            // Step content
            Group {
                switch state.setupPhase {
                case .detectCLI:
                    detectCLIStep
                case .detectClaude:
                    detectClaudeStep
                case .configurePermissions:
                    permissionsStep
                case .setScanPath:
                    scanPathStep
                case .initialLoad:
                    initialLoadStep
                case .complete:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(width: 460)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            stepDot(step: 1, label: "Find CLI", active: state.setupPhase == .detectCLI, done: stepNumber > 1)
            stepLine(done: stepNumber > 1)
            stepDot(step: 2, label: "Claude", active: state.setupPhase == .detectClaude, done: stepNumber > 2)
            stepLine(done: stepNumber > 2)
            stepDot(step: 3, label: "Permissions", active: state.setupPhase == .configurePermissions, done: stepNumber > 3)
            stepLine(done: stepNumber > 3)
            stepDot(step: 4, label: "Scan Path", active: state.setupPhase == .setScanPath, done: stepNumber > 4)
            stepLine(done: stepNumber > 4)
            stepDot(step: 5, label: "Load Data", active: state.setupPhase == .initialLoad, done: state.setupPhase == .complete)
        }
        .padding(.horizontal, 28)
    }

    private var stepNumber: Int {
        switch state.setupPhase {
        case .detectCLI: return 1
        case .detectClaude: return 2
        case .configurePermissions: return 3
        case .setScanPath: return 4
        case .initialLoad: return 5
        case .complete: return 6
        }
    }

    private func stepDot(step: Int, label: String, active: Bool, done: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? ForgeTheme.Colors.success : active ? Color.accentColor : Color.secondary.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .scaleEffect(active ? 1.1 : 1.0)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? .white : .secondary)
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(active ? .primary : .secondary)
        }
    }

    private func stepLine(done: Bool) -> some View {
        Rectangle()
            .fill(done ? Color.green.opacity(0.6) : Color.secondary.opacity(0.15))
            .frame(height: 2)
            .frame(maxWidth: 50)
            .padding(.bottom, 18) // align with dot centers
    }

    // MARK: - Step 1: Detect CLI

    private var detectCLIStep: some View {
        VStack(spacing: 18) {
            if let path = detectedPath {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    Text("Forge CLI found")
                        .font(.system(size: 14, weight: .semibold))
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }

                Button {
                    state.forgePath = path
                    state.setupPhase = .detectClaude
                } label: {
                    Text("Continue")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if let error = detectError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button("Browse...") { browseForCLI() }
                        .buttonStyle(.bordered)
                    Button("Retry") { detectCLI() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Searching for forge CLI...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { detectCLI() }
    }

    private func detectCLI() {
        detectedPath = nil
        detectError = nil
        Task {
            do {
                let path = try await forgeService.discoverForgePath()
                detectedPath = path
            } catch {
                detectError = "Forge CLI not found.\nInstall forge or browse to select it."
            }
        }
    }

    private func browseForCLI() {
        let panel = NSOpenPanel()
        panel.title = "Select Forge Binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            detectedPath = url.path
        }
    }

    // MARK: - Step 2: Detect Claude

    private var detectClaudeStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Check Claude Code CLI")
                    .font(.system(size: 14, weight: .semibold))
                Text("Claude Code powers intelligent CLAUDE.md fixes.\nIt's optional but recommended.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let path = claudeDetectedPath {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("Claude Code found")
                        .font(.system(size: 13, weight: .medium))
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                    if let version = claudeVersion {
                        Text("Version: \(version)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Button {
                    claudeBinaryPath = path
                    state.claudeAvailable = true
                    state.setupPhase = .configurePermissions
                } label: {
                    Text("Continue")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if claudeDetectError != nil {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text("Claude Code CLI not found")
                        .font(.system(size: 13, weight: .medium))
                    Text("Install it to enable intelligent fixes:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text("npm install -g @anthropic-ai/claude-code")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("npm install -g @anthropic-ai/claude-code", forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Copy command")
                    }
                }

                HStack(spacing: 12) {
                    Button("Skip for Now") {
                        state.claudeAvailable = false
                        state.setupPhase = .setScanPath
                    }
                    .buttonStyle(.bordered)

                    Button("Retry") { detectClaude() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Searching for Claude Code CLI...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { detectClaude() }
    }

    private func detectClaude() {
        claudeDetectedPath = nil
        claudeDetectError = nil
        claudeVersion = nil

        Task {
            if let path = ClaudeService.discoverClaudePath() {
                // Verify it's functional with --version
                let versionStr = await getClaudeVersion(at: path)
                claudeDetectedPath = path
                claudeVersion = versionStr
            } else {
                claudeDetectError = "Not found"
            }
        }
    }

    private func getClaudeVersion(at path: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                guard proc.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: version)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Step 3: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("How much autonomy should Claude have?")
                    .font(.system(size: 14, weight: .semibold))
                Text("Controls what Claude can do without asking permission.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                permissionPresetRow(
                    id: "ask-before-changes",
                    label: "Ask Before Changes",
                    description: "Claude browses your code without asking, but asks permission before making any changes.",
                    detail: "Auto-approves: reading files, searching code, listing directories.\nYou approve: file edits, running commands.",
                    recommended: false
                )
                permissionPresetRow(
                    id: "auto-edit",
                    label: "Auto-Edit",
                    description: "Claude browses and edits files without asking. Still asks before running commands.",
                    detail: "Auto-approves: everything above, plus creating and editing files, viewing git status.\nYou approve: running build/test commands, git operations.",
                    recommended: false
                )
                permissionPresetRow(
                    id: "full-autonomy",
                    label: "Full Autonomy",
                    description: "Claude runs development commands without asking. Still asks before destructive operations.",
                    detail: "Auto-approves: everything above, plus git operations, package managers, build tools.\nYou approve: force pushes, deletions, arbitrary scripts.",
                    recommended: true
                )
            }
            .padding(.horizontal, 8)

            if let error = presetError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 10))
                Text("You can change this anytime in Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Skip") {
                    state.setupPhase = .setScanPath
                }
                .buttonStyle(.bordered)

                Button {
                    applyPermissionPreset()
                } label: {
                    HStack(spacing: 4) {
                        if applyingPreset {
                            ProgressView().controlSize(.mini)
                        }
                        Text("Apply & Continue")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(applyingPreset)
            }
        }
    }

    private func permissionPresetRow(
        id: String,
        label: String,
        description: String,
        detail: String,
        recommended: Bool
    ) -> some View {
        Button {
            selectedPreset = id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: selectedPreset == id ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selectedPreset == id ? Color.accentColor : .secondary)
                        .font(.system(size: 14))

                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    if recommended {
                        StatusBadge("Recommended", tint: ForgeTheme.Colors.forgeText, style: .filled)
                    }
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)

                if expandedPreset == id {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 20)
                        .padding(.top, 2)
                }

                Button {
                    forgeWithAnimation(.easeInOut(duration: 0.2)) {
                        expandedPreset = expandedPreset == id ? nil : id
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: expandedPreset == id ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                        Text("Details")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedPreset == id ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selectedPreset == id ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func applyPermissionPreset() {
        applyingPreset = true
        presetError = nil
        Task {
            do {
                try await permissionsService.applyPreset(name: selectedPreset)
                state.setupPhase = .setScanPath
            } catch {
                presetError = "Failed to apply preset: \(error.localizedDescription)"
            }
            applyingPreset = false
        }
    }

    // MARK: - Step 4: Scan Path

    private var scanPathStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Where are your repositories?")
                    .font(.system(size: 14, weight: .semibold))
                Text("Forge will scan this directory for projects.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("~/projects", text: $scanPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button("Browse...") { browseForScanPath() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)

            if SettingsView.isBroadScanPath(scanPath) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text("This will scan your entire home directory, which may be slow and trigger macOS permission prompts.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
            }

            Button {
                setScanPath()
            } label: {
                Text("Continue")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(scanPath.isEmpty)
        }
    }

    private func browseForScanPath() {
        let panel = NSOpenPanel()
        panel.title = "Select Repository Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            scanPath = url.path
        }
    }

    private func setScanPath() {
        Task {
            try? await configService.setScanPath(scanPath)
            state.setupPhase = .initialLoad
        }
    }

    // MARK: - Step 5: Initial Load

    private var initialLoadStep: some View {
        VStack(spacing: 18) {
            if let error = loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                Button("Retry") { runInitialLoad() }
                    .buttonStyle(.borderedProminent)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading your dashboard...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { runInitialLoad() }
    }

    private func runInitialLoad() {
        loadError = nil
        state.loadState = .loading

        Task {
            do {
                let data = try await forgeService.loadDashboard()
                state.loadState = .loaded(data)
                state.setupPhase = .complete
                onComplete()
            } catch {
                loadError = error.localizedDescription
                state.loadState = .failed(
                    (error as? ForgeError) ?? .unexpected(error.localizedDescription)
                )
            }
        }
    }
}
