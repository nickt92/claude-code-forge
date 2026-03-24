import SwiftUI

public struct SettingsView: View {
    @AppStorage("forgeBinaryPath") private var forgePath: String = ""
    @AppStorage("claudeBinaryPath") private var claudePath: String = ""
    @AppStorage("scanDepth") private var scanDepth: Int = 3
    @State private var resolvedPath: String = ""
    @State private var resolvedClaudePath: String = ""
    @State private var isResolving = false
    @State private var scanPath: String = ""
    @State private var scanPathLoaded = false
    @State private var isRescanning = false
    @Environment(\.configService) private var configService

    var onRescan: (() -> Void)?

    public init(onRescan: (() -> Void)? = nil) {
        self.onRescan = onRescan
    }

    public var body: some View {
        Form {
            Section("Forge Binary") {
                HStack {
                    TextField("Path to forge binary", text: $forgePath, prompt: Text("Auto-detect"))
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        browseForFile { forgePath = $0 }
                    }
                }

                if forgePath.isEmpty {
                    autoDetectStatus(isResolving: isResolving, resolvedPath: resolvedPath, label: "Forge CLI")
                        .task { await resolveAutoPath() }
                }
            }

            Section("Claude Code Binary") {
                HStack {
                    TextField("Path to claude binary", text: $claudePath, prompt: Text("Auto-detect"))
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        browseForFile { claudePath = $0 }
                    }
                }

                if claudePath.isEmpty {
                    autoDetectStatus(isResolving: isResolving, resolvedPath: resolvedClaudePath, label: "Claude Code CLI")
                        .task { await resolveClaudePath() }
                }
            }

            Section("Repository Scanning") {
                HStack {
                    TextField("Scan path", text: $scanPath, prompt: Text("~/code"))
                        .textFieldStyle(.roundedBorder)

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

                Stepper("Scan depth: \(scanDepth)", value: $scanDepth, in: 1...5)
                    .font(.system(size: 12))

                Button {
                    if !scanPath.isEmpty {
                        Task { try? await configService.setScanPath(scanPath) }
                    }
                    isRescanning = true
                    onRescan?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { isRescanning = false }
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
        .frame(width: 500, height: 380)
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
        isResolving = true
        defer { isResolving = false }

        let service = ForgeService()
        if let path = try? await service.discoverForgePath() {
            resolvedPath = path
        }
    }

    private func resolveClaudePath() async {
        let service = ClaudeService()
        if service.isAvailable {
            resolvedClaudePath = "claude"
        }
    }
}
