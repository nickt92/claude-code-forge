import Foundation

/// Runs `forge update`: fetches origin into the source repo, fast-forward merges,
/// and reinstalls forge to ~/.claude. Non-interactive with clear exit codes —
/// the UI must get explicit user confirmation before calling this.
public final class UpdateService: Sendable {
    private let executor: CLIExecutor
    private let pathResolver: ForgePathResolver

    public init(executor: CLIExecutor = ProcessExecutor(), forgePath: String? = nil) {
        self.executor = executor
        self.pathResolver = ForgePathResolver(executor: executor, forgePath: forgePath)
    }

    /// Returns the CLI's output for display in the update log disclosure.
    public func update() async throws -> String {
        let forgePath = try await pathResolver.resolve()
        do {
            let data = try await executor.run(executable: forgePath, arguments: ["update"])
            return String(decoding: data, as: UTF8.self)
        } catch let error as ForgeError {
            if case .cliExitCode(_, let stderr) = error {
                throw ForgeError.unexpected(Self.friendlyMessage(for: stderr))
            }
            throw error
        }
    }

    /// Maps the update command's known failure modes to actionable messages.
    /// The raw stderr is preserved as a suffix so nothing is hidden.
    static func friendlyMessage(for stderr: String) -> String {
        let lowered = stderr.lowercased()
        if lowered.contains("uncommitted changes") {
            return "Your forge source repo has uncommitted changes. Commit or stash them, then try again. (\(stderr.trimmedForDisplay))"
        }
        if lowered.contains("not a git repository") {
            return "The forge source directory is not a git repository, so it can't be updated in place. (\(stderr.trimmedForDisplay))"
        }
        if lowered.contains("failed to fetch") {
            return "Couldn't reach origin to fetch updates. Check your network connection. (\(stderr.trimmedForDisplay))"
        }
        if lowered.contains("fast-forward merge failed") {
            return "The source repo has diverged from origin and can't be fast-forwarded. Resolve it manually in the source directory. (\(stderr.trimmedForDisplay))"
        }
        return "Update failed: \(stderr.trimmedForDisplay)"
    }
}

extension String {
    fileprivate var trimmedForDisplay: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    }
}
