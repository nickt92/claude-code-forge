import SwiftUI

public struct SettingsView: View {
    @AppStorage("forgeBinaryPath") private var forgePath: String = ""
    @AppStorage("claudeBinaryPath") private var claudePath: String = ""
    @State private var resolvedPath: String = ""
    @State private var resolvedClaudePath: String = ""
    @State private var isResolving = false
    @State private var scanPath: String = ""
    @State private var scanPathLoaded = false
    @State private var isRescanning = false
    @Environment(\.configService) private var configService

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
                    autoDetectStatus(isResolving: isResolving, resolvedPath: resolvedPath, label: "Forge CLI")
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
                    autoDetectStatus(isResolving: isResolving, resolvedPath: resolvedClaudePath, label: "Claude Code CLI")
                        .task { await resolveClaudePath() }
                }
            } header: {
                Text("Claude Code Binary")
            } footer: {
                Text("Changes take effect after restarting Forge.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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

    static func isBroadScanPath(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        let home = NSHomeDirectory()
        return expanded == home || expanded == "/" || expanded == "/Users"
    }
}
