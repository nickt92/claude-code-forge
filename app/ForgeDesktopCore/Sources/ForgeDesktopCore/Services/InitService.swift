import Foundation

public final class InitService: Sendable {
    private let executor: CLIExecutor
    private let forgePathOverride: String?

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.forgePathOverride = forgePath
    }

    public func initProject(at repoPath: String) async throws {
        let forgePath = try await resolvePath()
        _ = try await executor.run(executable: forgePath, arguments: ["init", "--skip-docs", "--dir", repoPath])
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
