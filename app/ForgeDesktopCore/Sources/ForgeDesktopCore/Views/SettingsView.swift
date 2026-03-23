import SwiftUI

public struct SettingsView: View {
    @AppStorage("forgeBinaryPath") private var forgePath: String = ""
    @State private var resolvedPath: String = ""
    @State private var isResolving = false

    public init() {}

    public var body: some View {
        Form {
            Section("Forge Binary") {
                HStack {
                    TextField("Path to forge binary", text: $forgePath, prompt: Text("Auto-detect"))
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.treatsFilePackagesAsDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            forgePath = url.path
                        }
                    }
                }

                if forgePath.isEmpty {
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
                            Text("Forge CLI not found — install forge or set the path above")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .task {
                        await resolveAutoPath()
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 220)
    }

    private func resolveAutoPath() async {
        isResolving = true
        defer { isResolving = false }

        let service = ForgeService()
        if let path = try? await service.discoverForgePath() {
            resolvedPath = path
        }
    }
}
