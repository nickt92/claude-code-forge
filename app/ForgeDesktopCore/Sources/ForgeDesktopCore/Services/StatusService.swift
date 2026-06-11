import Foundation

/// Reads installation status via `forge status --json`.
public final class StatusService: Sendable {
    private let executor: CLIExecutor
    private let pathResolver: ForgePathResolver

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.pathResolver = ForgePathResolver(executor: executor, forgePath: forgePath)
    }

    public func status() async throws -> ForgeStatus {
        let forgePath = try await pathResolver.resolve()
        let data = try await executor.run(executable: forgePath, arguments: ["status", "--json"])
        do {
            return try Self.decoder.decode(ForgeStatus.self, from: data)
        } catch let error as DecodingError {
            throw ForgeError.jsonDecodingFailed(error)
        }
    }
}
