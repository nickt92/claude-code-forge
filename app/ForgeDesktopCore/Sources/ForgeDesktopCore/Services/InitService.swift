import Foundation

public final class InitService: Sendable {
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

    public func initProject(at repoPath: String) async throws {
        let forgePath = try await pathResolver.resolve()
        _ = try await executor.run(executable: forgePath, arguments: ["init", "--skip-docs", "--dir", repoPath])
    }
}
