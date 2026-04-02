import Foundation

public final class PermissionsService: Sendable {
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

    public func listPresets() async throws -> [PermissionPreset] {
        let forgePath = try await pathResolver.resolve()
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
        let forgePath = try await pathResolver.resolve()
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
        let forgePath = try await pathResolver.resolve()
        _ = try await executor.run(
            executable: forgePath,
            arguments: ["permissions", "--preset", name]
        )
    }
}
