import Foundation

public final class ConfigService: Sendable {
    private let executor: CLIExecutor
    private let pathResolver: ForgePathResolver

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.pathResolver = ForgePathResolver(executor: executor, forgePath: forgePath)
    }

    public init(executor: CLIExecutor = ProcessExecutor(), pathResolver: ForgePathResolver) {
        self.executor = executor
        self.pathResolver = pathResolver
    }

    public func setScanPath(_ path: String) async throws {
        let forgePath = try await pathResolver.resolve()
        _ = try await executor.run(executable: forgePath, arguments: ["config", "set", "dashboard.scan_path", path])
    }

    public func getScanPath() async throws -> String? {
        let forgePath = try await pathResolver.resolve()
        let data = try await executor.run(executable: forgePath, arguments: ["config", "get", "dashboard.scan_path"])
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == true ? nil : value
    }
}
