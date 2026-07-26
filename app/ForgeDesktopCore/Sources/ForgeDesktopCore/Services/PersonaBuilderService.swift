import Foundation

/// Creates custom personas via `forge build`'s non-interactive flags.
public final class PersonaBuilderService: Sendable {
    private let executor: CLIExecutor
    private let pathResolver: ForgePathResolver

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.pathResolver = ForgePathResolver(executor: executor, forgePath: forgePath)
    }

    /// Returns the CLI output on success. CLI validation errors (the authority)
    /// surface as `ForgeError.cliExitCode` with the CLI's own message.
    public func build(_ draft: PersonaDraft) async throws -> String {
        let forgePath = try await pathResolver.resolve()
        let data = try await executor.run(executable: forgePath, arguments: draft.cliArguments)
        return String(decoding: data, as: UTF8.self)
    }
}
