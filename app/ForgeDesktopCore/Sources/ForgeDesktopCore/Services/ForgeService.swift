import Foundation

public final class ForgeService: Sendable {
    private let executor: CLIExecutor
    private let forgePathOverride: String?
    private let cache: DashboardCache?

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public init(
        executor: CLIExecutor = ProcessExecutor(),
        forgePath: String? = nil,
        cache: DashboardCache? = nil
    ) {
        self.executor = executor
        self.forgePathOverride = forgePath
        self.cache = cache
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw ForgeError.jsonDecodingFailed(error)
        }
    }

    public func loadDashboard() async throws -> DashboardData {
        let forgePath = try await discoverForgePath()
        let data = try await executor.run(executable: forgePath, arguments: ["dashboard"])
        let dashboard = try decode(DashboardData.self, from: data)
        // Only valid payloads are cached — decode succeeded above.
        cache?.save(data)
        return dashboard
    }

    /// Last successful dashboard payload, decoded from the on-disk cache.
    /// Returns nil for any miss or decode failure — callers fall back to a live load.
    public func cachedDashboard() -> DashboardData? {
        guard let data = cache?.load() else { return nil }
        return try? Self.decoder.decode(DashboardData.self, from: data)
    }

    public func auditRepo(path: String) async throws -> AuditData {
        let forgePath = try await discoverForgePath()
        let data = try await executor.run(executable: forgePath, arguments: ["audit", path, "--json"])
        return try decode(AuditData.self, from: data)
    }

    public func loadHookTelemetry() async throws -> HookTelemetryData {
        let forgePath = try await discoverForgePath()
        let data = try await executor.run(executable: forgePath, arguments: ["stats", "--hooks", "--json"])
        return try decode(HookTelemetryData.self, from: data)
    }

    public func loadSessionScorecard() async throws -> SessionScorecard {
        let forgePath = try await discoverForgePath()
        let data = try await executor.run(executable: forgePath, arguments: ["stats", "--session", "--json"])
        return try decode(SessionScorecard.self, from: data)
    }

    public func fixRepo(path: String) async throws {
        let forgePath = try await discoverForgePath()
        _ = try await executor.run(executable: forgePath, arguments: ["audit", path, "--fix"])
    }

    public func discoverForgePath() async throws -> String {
        if let override = forgePathOverride, !override.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: override) else {
                throw ForgeError.cliNotFound
            }
            return override
        }

        if let cached = await ForgePathCache.shared.value() {
            return cached
        }

        // Filesystem checks first. This used to spawn `which` on every call,
        // ahead of four `isExecutableFile` checks that answer the question
        // without a process — and every service resolves the path before every
        // command, so the app was forking a subprocess per CLI invocation.
        for path in Self.knownPaths where FileManager.default.isExecutableFile(atPath: path) {
            await ForgePathCache.shared.store(path)
            return path
        }

        if let whichPath = await resolveViaWhich() {
            await ForgePathCache.shared.store(whichPath)
            return whichPath
        }

        throw ForgeError.cliNotFound
    }

    static let knownPaths = [
        "\(NSHomeDirectory())/.claude/bin/forge",
        "\(NSHomeDirectory())/.local/bin/forge",
        "/usr/local/bin/forge",
        "/opt/homebrew/bin/forge",
    ]

    /// Falls back to `which` only when none of the known locations hold a
    /// binary. Routed through the executor so it inherits the concurrent pipe
    /// drain and, more importantly, a timeout — the hand-rolled Process here
    /// had neither, so a `which` that never exited wedged the caller forever.
    private func resolveViaWhich() async -> String? {
        guard let data = try? await executor.run(
            executable: "/usr/bin/which",
            arguments: ["forge"],
            workingDirectory: nil,
            timeout: 5
        ) else { return nil }

        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}

/// Process-lifetime cache for the discovered forge path.
///
/// Resolution is stable for a session and was previously repeated — including a
/// subprocess spawn — before every single CLI call.
actor ForgePathCache {
    static let shared = ForgePathCache()

    private var cached: String?

    func value() -> String? {
        // A binary can be moved or uninstalled mid-session; re-resolve if the
        // cached path stopped being executable rather than failing every call.
        if let cached, !FileManager.default.isExecutableFile(atPath: cached) {
            self.cached = nil
        }
        return cached
    }

    func store(_ path: String) { cached = path }

    /// Test hook — resolution is global state, so suites must be able to reset it.
    func reset() { cached = nil }
}

public enum ForgeError: LocalizedError, Sendable {
    case cliNotFound
    case cliExitCode(Int, stderr: String)
    case jsonDecodingFailed(DecodingError)
    case unexpected(String)
    case claudeNotAvailable
    case claudeFailed(String)
    case claudeTimeout
    case fixInProgress

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Forge CLI not found. Install forge or set the path in Settings."
        case .cliExitCode(let code, let stderr):
            let detail = stderr.isEmpty ? "" : ": \(stderr.prefix(200))"
            return "Forge exited with code \(code)\(detail)"
        case .jsonDecodingFailed(let error):
            return "Failed to parse forge output: \(error.localizedDescription)"
        case .unexpected(let message):
            return "Unexpected error: \(message)"
        case .claudeNotAvailable:
            return "Claude Code CLI not found. Install Claude Code to use intelligent fixes."
        case .claudeFailed(let message):
            return "Claude analysis failed: \(message)"
        case .claudeTimeout:
            return "Claude analysis timed out."
        case .fixInProgress:
            return "A fix is already running for this repository."
        }
    }
}
