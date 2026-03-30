import Foundation

public final class PermissionsService: Sendable {
    private let executor: CLIExecutor
    private let forgePathOverride: String?

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.forgePathOverride = forgePath
    }

    public func listPresets() async throws -> [PermissionPreset] {
        let forgePath = try await resolvePath()
        let data = try await executor.run(
            executable: forgePath,
            arguments: ["permissions", "--list", "--json"]
        )

        let decoder = JSONDecoder()
        do {
            return try decoder.decode([PermissionPreset].self, from: data)
        } catch let error as DecodingError {
            throw ForgeError.jsonDecodingFailed(error)
        }
    }

    public func currentState() async throws -> PermissionsState {
        let forgePath = try await resolvePath()
        let data = try await executor.run(
            executable: forgePath,
            arguments: ["permissions", "--json"]
        )

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PermissionsState.self, from: data)
        } catch let error as DecodingError {
            throw ForgeError.jsonDecodingFailed(error)
        }
    }

    public func applyPreset(name: String) async throws {
        let forgePath = try await resolvePath()
        _ = try await executor.run(
            executable: forgePath,
            arguments: ["permissions", "--preset", name]
        )
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
