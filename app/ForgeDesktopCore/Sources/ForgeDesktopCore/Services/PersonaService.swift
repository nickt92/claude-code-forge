import Foundation

public final class PersonaService: Sendable {
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

    public func listPersonas() async throws -> [PersonaProfile] {
        let forgePath = try await pathResolver.resolve()
        let data = try await executor.run(executable: forgePath, arguments: ["switch", "--list", "--json"])

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode([PersonaProfile].self, from: data)
        } catch let error as DecodingError {
            throw ForgeError.jsonDecodingFailed(error)
        }
    }

    public func switchPersona(name: String) async throws {
        let forgePath = try await pathResolver.resolve()
        _ = try await executor.run(executable: forgePath, arguments: ["switch", name])
    }
}
