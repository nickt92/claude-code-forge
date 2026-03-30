import Foundation
import os

public enum ClaudeStreamEvent: Sendable {
    case assistantText(String)
    case toolUse(name: String, input: String)
    case toolResult(name: String, output: String)
    case result(ClaudeResult)
    case error(String)
}

public struct ClaudeResult: Codable, Sendable {
    public let result: String?
    public let isError: Bool
    public let costUsd: Double?

    enum CodingKeys: String, CodingKey {
        case result
        case isError = "is_error"
        // Claude CLI v2+ emits "total_cost_usd" in --output-format json responses.
        // The legacy "cost_usd" key is no longer present.
        case costUsd = "total_cost_usd"
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

public final class ClaudeService: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.forge.desktop", category: "ClaudeService")

    private let executor: CLIExecutor
    private let explicitPath: String?
    private let lock = NSLock()
    private var _resolvedPath: String??  // nil = not yet resolved, .some(nil) = resolved to not found

    static let timeout: TimeInterval = 180
    static let model = "sonnet"
    static let maxBudget = "0.50"

    static let knownPaths = [
        "\(NSHomeDirectory())/.local/bin/claude",
        "\(NSHomeDirectory())/.claude/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
    ]

    public init(executor: CLIExecutor = ProcessExecutor(), claudePath: String? = nil) {
        self.executor = executor
        self.explicitPath = claudePath
    }

    /// Resolved path to the Claude CLI binary. Discovered lazily on first access.
    /// Resolution happens outside the lock to avoid blocking UI thread during `which` calls.
    private var claudePath: String? {
        let cached: String?? = lock.withLock { _resolvedPath }
        if let cached { return cached }

        let resolved = explicitPath ?? Self.discoverClaudePath()
        lock.withLock { _resolvedPath = .some(resolved) }
        return resolved
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

        Self.logger.info("Invoking Claude: model=\(Self.model) tools=\(allowedTools.joined(separator: ","), privacy: .public) prompt_length=\(prompt.count) repo=\(repoPath, privacy: .public)")

        let data: Data
        do {
            data = try await executor.run(
                executable: path,
                arguments: arguments,
                workingDirectory: repoPath,
                timeout: Self.timeout
            )
        } catch let error as ForgeError where error.isCLIExit {
            Self.logger.error("Claude CLI failed: \(error.errorDescription ?? "Unknown", privacy: .public)")
            throw ForgeError.claudeFailed(error.errorDescription ?? "Unknown error")
        } catch let error as ForgeError where error.isTimeout {
            Self.logger.error("Claude timed out after \(Self.timeout)s")
            throw ForgeError.claudeTimeout
        }

        let result = try parseResult(data)
        let cost = result.costUsd.map { String(format: "$%.4f", $0) } ?? "unknown"
        Self.logger.info("Claude response: isError=\(result.isError) cost=\(cost, privacy: .public) result_length=\(result.result?.count ?? 0)")
        if result.costUsd == nil {
            Self.logger.warning("Claude response missing cost field — raw output may indicate an unexpected response format")
        }
        return result
    }

    // MARK: - Streaming

    public func streamInRepo(
        prompt: String,
        repoPath: String,
        systemPrompt: String? = nil,
        allowedTools: [String] = ["Read", "Edit", "Glob", "Grep"],
        maxBudget: String = "1.00",
        timeout: TimeInterval = 300
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        guard let path = claudePath else {
            return AsyncThrowingStream { $0.finish(throwing: ForgeError.claudeNotAvailable) }
        }

        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--model", Self.model,
            "--permission-mode", "bypassPermissions",
            "--no-session-persistence",
            "--allowedTools", allowedTools.joined(separator: ","),
            "--max-budget-usd", maxBudget,
        ]

        if let systemPrompt {
            arguments += ["--append-system-prompt", systemPrompt]
        }

        Self.logger.info("Streaming Claude: model=\(Self.model) tools=\(allowedTools.joined(separator: ","), privacy: .public) prompt_length=\(prompt.count) repo=\(repoPath, privacy: .public)")

        let rawStream = executor.stream(
            executable: path,
            arguments: arguments,
            workingDirectory: repoPath,
            timeout: timeout
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await lineData in rawStream {
                        guard let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                              !line.isEmpty else { continue }

                        if let event = Self.parseStreamLine(line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    Self.logger.error("Stream error: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    static func parseStreamLine(_ line: String) -> ClaudeStreamEvent? {
        guard let data = line.data(using: .utf8) else { return nil }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json else { return nil }

            let type = json["type"] as? String ?? ""

            switch type {
            case "assistant":
                // Text content block
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    var text = ""
                    for block in content {
                        if let blockText = block["text"] as? String {
                            text += blockText
                        }
                    }
                    if !text.isEmpty {
                        return .assistantText(text)
                    }
                }
                return nil

            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    return .assistantText(text)
                }
                return nil

            case "tool_use":
                let name = json["name"] as? String ?? "unknown"
                let input: String
                if let inputObj = json["input"] {
                    if let inputData = try? JSONSerialization.data(withJSONObject: inputObj),
                       let inputStr = String(data: inputData, encoding: .utf8) {
                        input = inputStr
                    } else {
                        input = ""
                    }
                } else {
                    input = ""
                }
                return .toolUse(name: name, input: input)

            case "tool_result":
                let name = json["name"] as? String ?? "unknown"
                let output = json["output"] as? String ?? ""
                return .toolResult(name: name, output: output)

            case "result":
                if let resultStr = json["result"] as? String {
                    let isError = json["is_error"] as? Bool ?? false
                    let costUsd = json["cost_usd"] as? Double
                    let result = ClaudeResult(result: resultStr, isError: isError, costUsd: costUsd)
                    return .result(result)
                }
                return nil

            case "error":
                let message = json["error"] as? String
                    ?? (json["message"] as? String)
                    ?? "Unknown error"
                return .error(message)

            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func parseResult(_ data: Data) throws -> ClaudeResult {
        do {
            let result = try JSONDecoder().decode(ClaudeResult.self, from: data)
            if !result.isError && (result.result == nil || result.result?.isEmpty == true) && (result.costUsd ?? 0) == 0 {
                Self.logger.warning("Claude returned empty result with zero cost — likely a no-op invocation")
            }
            return result
        } catch {
            // Claude with --output-format json should always return JSON.
            // Non-JSON output is anomalous — log it as a warning.
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                Self.logger.warning("Claude returned non-JSON output: \(text.prefix(200), privacy: .public)")
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

        // Fall back to `which claude` with a 5-second timeout to prevent hangs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            let completed = try process.runWithTimeout(seconds: 5)
            guard completed, process.terminationStatus == 0 else {
                if !completed && process.isRunning { process.terminate() }
                return nil
            }

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

// MARK: - Process Timeout Helper

extension Process {
    /// Launches the process and waits for exit with a timeout. Returns `true` if it exited in time.
    /// The `terminationHandler` is set before `run()` to avoid races with fast-exiting processes.
    func runWithTimeout(seconds: TimeInterval) throws -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        terminationHandler = { _ in semaphore.signal() }
        try run()
        return semaphore.wait(timeout: .now() + seconds) == .success
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
