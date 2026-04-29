import Foundation

public final class DoctorService: Sendable {
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

    public func runDoctor() async throws -> DoctorResult {
        let forgePath = try await pathResolver.resolve()
        let data = try await executor.run(executable: forgePath, arguments: ["doctor", "--json"])

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(DoctorResult.self, from: data)
        } catch let error as DecodingError {
            throw ForgeError.jsonDecodingFailed(error)
        }
    }
}
