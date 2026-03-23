import Foundation

public final class ConfigService: Sendable {
    private let executor: CLIExecutor
    private let forgePathOverride: String?

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.forgePathOverride = forgePath
    }

    public func setScanPath(_ path: String) async throws {
        let forgePath = try await resolvePath()
        _ = try await executor.run(executable: forgePath, arguments: ["config", "set", "dashboard.scan_path", path])
    }

    public func getScanPath() async throws -> String? {
        let forgePath = try await resolvePath()
        let data = try await executor.run(executable: forgePath, arguments: ["config", "get", "dashboard.scan_path"])
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == true ? nil : value
    }

    private func resolvePath() async throws -> String {
        if let override = forgePathOverride, !override.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: override) else {
                throw ForgeError.cliNotFound
            }
            return override
        }
        let service = ForgeService(executor: executor)
        return try await service.discoverForgePath()
    }
}
