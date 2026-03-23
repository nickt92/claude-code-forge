import SwiftUI

public struct SetupWizardView: View {
    @Bindable var state: ForgeState
    @Environment(\.configService) private var configService
    @State private var detectedPath: String?
    @State private var detectError: String?
    @State private var scanPath: String = ""
    @State private var loadError: String?

    let forgeService: ForgeService
    let onComplete: () -> Void

    public init(state: ForgeState, forgeService: ForgeService, onComplete: @escaping () -> Void) {
        self.state = state
        self.forgeService = forgeService
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                }

                Text("Welcome to Forge")
                    .font(.system(size: 20, weight: .bold))
                Text("Let's get your environment set up.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            stepIndicator
                .padding(.bottom, 24)

            Divider()

            // Step content
            Group {
                switch state.setupPhase {
                case .detectCLI:
                    detectCLIStep
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
            stepDot(step: 2, label: "Scan Path", active: state.setupPhase == .setScanPath, done: stepNumber > 2)
            stepLine(done: stepNumber > 2)
            stepDot(step: 3, label: "Load Data", active: state.setupPhase == .initialLoad, done: state.setupPhase == .complete)
        }
        .padding(.horizontal, 60)
    }

    private var stepNumber: Int {
        switch state.setupPhase {
        case .detectCLI: return 1
        case .setScanPath: return 2
        case .initialLoad: return 3
        case .complete: return 4
        }
    }

    private func stepDot(step: Int, label: String, active: Bool, done: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : active ? Color.accentColor : Color.secondary.opacity(0.15))
                    .frame(width: 28, height: 28)
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
                    state.setupPhase = .setScanPath
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

    // MARK: - Step 2: Scan Path

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

    // MARK: - Step 3: Initial Load

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
