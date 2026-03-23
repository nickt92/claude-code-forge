import Foundation

public final class ForgeService: Sendable {
    private let executor: CLIExecutor
    private let forgePathOverride: String?

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.forgePathOverride = forgePath
    }

    public func loadDashboard() async throws -> DashboardData {
        let forgePath = try await discoverForgePath()
        let data = try await executor.run(executable: forgePath, arguments: ["dashboard"])

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(DashboardData.self, from: data)
        } catch let error as DecodingError {
            throw ForgeError.jsonDecodingFailed(error)
        }
    }

    public func discoverForgePath() async throws -> String {
        if let override = forgePathOverride, !override.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: override) else {
                throw ForgeError.cliNotFound
            }
            return override
        }

        if let whichPath = try? await resolveViaWhich() {
            return whichPath
        }

        let knownPaths = [
            "\(NSHomeDirectory())/.claude/bin/forge",
            "\(NSHomeDirectory())/.local/bin/forge",
            "/usr/local/bin/forge",
            "/opt/homebrew/bin/forge",
        ]

        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        throw ForgeError.cliNotFound
    }

    private func resolveViaWhich() async throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["forge"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

                guard let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: path)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
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
            return "Claude analysis timed out after 90 seconds."
        case .fixInProgress:
            return "A fix is already running for this repository."
        }
    }
}
