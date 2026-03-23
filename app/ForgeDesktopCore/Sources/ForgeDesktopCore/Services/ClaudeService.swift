import Foundation

public struct ClaudeResult: Codable, Sendable {
    public let result: String?
    public let isError: Bool
    public let costUsd: Double?

    enum CodingKeys: String, CodingKey {
        case result
        case isError = "is_error"
        case costUsd = "cost_usd"
    }

    public init(result: String?, isError: Bool, costUsd: Double? = nil) {
        self.result = result
        self.isError = isError
        self.costUsd = costUsd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        isError = (try? container.decode(Bool.self, forKey: .isError)) ?? false
        costUsd = try? container.decode(Double.self, forKey: .costUsd)
    }
}

public final class ClaudeService: Sendable {
    private let executor: CLIExecutor
    private let claudePath: String?

    static let timeout: TimeInterval = 90
    static let model = "sonnet"
    static let maxBudget = "0.25"

    static let knownPaths = [
        "\(NSHomeDirectory())/.local/bin/claude",
        "\(NSHomeDirectory())/.claude/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
    ]

    public init(executor: CLIExecutor = ProcessExecutor(), claudePath: String? = nil) {
        self.executor = executor
        self.claudePath = claudePath ?? Self.discoverClaudePath()
    }

    public var isAvailable: Bool {
        claudePath != nil
    }

    public func runInRepo(prompt: String, repoPath: String, allowedTools: [String] = ["Read", "Edit", "Glob", "Grep"]) async throws -> ClaudeResult {
        guard let path = claudePath else {
            throw ForgeError.claudeNotAvailable
        }

        let arguments = [
            "-p", prompt,
            "--output-format", "json",
            "--model", Self.model,
            "--permission-mode", "bypassPermissions",
            "--no-session-persistence",
            "--allowedTools", allowedTools.joined(separator: ","),
            "--max-budget-usd", Self.maxBudget,
        ]

        let data: Data
        do {
            data = try await executor.run(
                executable: path,
                arguments: arguments,
                workingDirectory: repoPath,
                timeout: Self.timeout
            )
        } catch let error as ForgeError where error.isCLIExit {
            throw ForgeError.claudeFailed(error.errorDescription ?? "Unknown error")
        } catch let error as ForgeError where error.isTimeout {
            throw ForgeError.claudeTimeout
        }

        return try parseResult(data)
    }

    private func parseResult(_ data: Data) throws -> ClaudeResult {
        do {
            return try JSONDecoder().decode(ClaudeResult.self, from: data)
        } catch {
            // Claude may return plain text on success
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return ClaudeResult(result: text.trimmingCharacters(in: .whitespacesAndNewlines), isError: false)
            }
            throw ForgeError.claudeFailed("Could not parse Claude output")
        }
    }

    public static func discoverClaudePath() -> String? {
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to `which claude`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }
            return path
        } catch {
            return nil
        }
    }
}

// MARK: - ForgeError Helpers

extension ForgeError {
    var isCLIExit: Bool {
        if case .cliExitCode = self { return true }
        return false
    }

    var isTimeout: Bool {
        if case .claudeTimeout = self { return true }
        return false
    }
}
