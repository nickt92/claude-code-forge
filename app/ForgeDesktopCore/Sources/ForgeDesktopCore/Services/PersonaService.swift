import Foundation

public final class PersonaService: Sendable {
    private let executor: CLIExecutor
    private let forgePathOverride: String?

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.forgePathOverride = forgePath
    }

    public func listPersonas() async throws -> [PersonaProfile] {
        let forgePath = try await resolvePath()
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
        let forgePath = try await resolvePath()
        _ = try await executor.run(executable: forgePath, arguments: ["switch", name])
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
