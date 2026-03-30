import Foundation
import CryptoKit
import os

// MARK: - FileSystem Protocol

public protocol FileSystemProtocol: Sendable {
    func readString(at path: String) throws -> String
    func writeString(_ content: String, to path: String) throws
    func fileExists(at path: String) -> Bool
}

public struct RealFileSystem: FileSystemProtocol {
    public init() {}

    public func readString(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    public func writeString(_ content: String, to path: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

public final class MockFileSystem: FileSystemProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _files: [String: String]

    public var files: [String: String] {
        lock.withLock { _files }
    }

    public init(files: [String: String] = [:]) {
        self._files = files
    }

    public func readString(at path: String) throws -> String {
        try lock.withLock {
            guard let content = _files[path] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return content
        }
    }

    public func writeString(_ content: String, to path: String) throws {
        lock.withLock {
            _files[path] = content
        }
    }

    public func fileExists(at path: String) -> Bool {
        lock.withLock {
            _files[path] != nil
        }
    }
}

// MARK: - Fix Service

public final class FixService: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.forge.desktop", category: "FixService")

    private let initService: InitService
    private let claudeService: ClaudeService?
    private let fileSystem: FileSystemProtocol
    private let lock = NSLock()
    private var fixesInProgress: Set<String> = []

    public init(
        initService: InitService,
        claudeService: ClaudeService? = nil,
        fileSystem: FileSystemProtocol = RealFileSystem()
    ) {
        self.initService = initService
        self.claudeService = claudeService
        self.fileSystem = fileSystem
    }

    public var claudeAvailable: Bool {
        claudeService?.isAvailable ?? false
    }

    public enum FixResult: Sendable, Equatable {
        case success
        case pendingReview(before: String, after: String)
        case claudeDidNotModify(response: String, costUsd: Double)
        case notFixable(String)
        case staleContent
        case fileNotFound
        case claudeNotAvailable
        case claudeFailed(String)
        case claudeTimeout
        case fixInProgress
    }

    public func fix(
        finding: Finding,
        repoPath: String,
        claudeMdPath: String?,
        contentHashAtLoad: String?,
        onEvent: (@MainActor @Sendable (ClaudeStreamEvent) -> Void)? = nil
    ) async throws -> FixResult {
        switch finding.code {
        case "no_claude_md":
            try await initService.initProject(at: repoPath)
            return .success

        case "missing_section":
            guard let section = finding.section else {
                return .notFixable("Finding has no section name")
            }
            guard let mdPath = claudeMdPath, fileSystem.fileExists(at: mdPath) else {
                return .fileNotFound
            }
            return try await fixWithClaude(repoPath: repoPath, mdPath: mdPath, expectedHash: contentHashAtLoad, onEvent: onEvent) {
                Self.missingSectionPrompt(section: section, claudeMdPath: mdPath)
            }

        case "tech_gap":
            guard let mdPath = claudeMdPath, fileSystem.fileExists(at: mdPath) else {
                return .fileNotFound
            }
            let tech = extractTechName(from: finding.detail)
            return try await fixWithClaude(repoPath: repoPath, mdPath: mdPath, expectedHash: contentHashAtLoad, onEvent: onEvent) {
                Self.techGapPrompt(tech: tech, claudeMdPath: mdPath)
            }

        case "low_coverage":
            guard let mdPath = claudeMdPath, fileSystem.fileExists(at: mdPath) else {
                return .fileNotFound
            }
            guard let section = finding.section else {
                return .notFixable("No specific section to add — run individual missing_section fixes instead")
            }
            return try await fixWithClaude(repoPath: repoPath, mdPath: mdPath, expectedHash: contentHashAtLoad, onEvent: onEvent) {
                Self.missingSectionPrompt(section: section, claudeMdPath: mdPath)
            }

        default:
            return .notFixable("Finding code '\(finding.code)' is not auto-fixable")
        }
    }

    // MARK: - Serialization

    public func isFixRunning(for repoPath: String) -> Bool {
        lock.withLock { fixesInProgress.contains(repoPath) }
    }

    private func acquireLock(for repoPath: String) -> Bool {
        lock.withLock {
            guard !fixesInProgress.contains(repoPath) else { return false }
            fixesInProgress.insert(repoPath)
            return true
        }
    }

    private func releaseLock(for repoPath: String) {
        lock.withLock { _ = fixesInProgress.remove(repoPath) }
    }

    // MARK: - Claude-Powered Fix

    private func fixWithClaude(
        repoPath: String,
        mdPath: String,
        expectedHash: String?,
        onEvent: (@MainActor @Sendable (ClaudeStreamEvent) -> Void)? = nil,
        prompt: () -> String
    ) async throws -> FixResult {
        guard let claude = claudeService, claude.isAvailable else {
            return .claudeNotAvailable
        }

        // Stale content check
        if let expected = expectedHash {
            let currentHash = try contentHash(for: mdPath)
            if currentHash != expected {
                Self.logger.debug("Stale content detected for \(mdPath, privacy: .public)")
                return .staleContent
            }
        }

        // Serialization: one fix at a time per repo
        guard acquireLock(for: repoPath) else {
            Self.logger.info("Fix already in progress for \(repoPath, privacy: .public)")
            return .fixInProgress
        }
        defer { releaseLock(for: repoPath) }

        Self.logger.info("Starting fix for \(mdPath, privacy: .public)")

        // Backup CLAUDE.md before Claude invocation
        let backup = try fileSystem.readString(at: mdPath)
        let promptText = prompt()

        // Use streaming path when onEvent callback is provided
        if let onEvent {
            return try await fixWithClaudeStreaming(
                claude: claude, repoPath: repoPath, mdPath: mdPath,
                backup: backup, prompt: promptText, onEvent: onEvent
            )
        }

        // Non-streaming path (backwards compatible for tests / callers without UI)
        do {
            let result = try await claude.runInRepo(
                prompt: promptText,
                repoPath: repoPath
            )

            if result.isError {
                Self.logger.error("Claude returned error: \(result.result ?? "nil", privacy: .public)")
                try? fileSystem.writeString(backup, to: mdPath)
                return .claudeFailed(result.result ?? "Unknown error")
            }

            return try evaluateFixResult(mdPath: mdPath, backup: backup, claudeResult: result)
        } catch let error as ForgeError {
            return handleFixError(error, mdPath: mdPath, backup: backup)
        }
    }

    private func fixWithClaudeStreaming(
        claude: ClaudeService,
        repoPath: String,
        mdPath: String,
        backup: String,
        prompt: String,
        onEvent: @MainActor @Sendable (ClaudeStreamEvent) -> Void
    ) async throws -> FixResult {
        let stream = claude.streamInRepo(
            prompt: prompt,
            repoPath: repoPath,
            allowedTools: ["Read", "Edit", "Glob", "Grep"],
            maxBudget: ClaudeService.maxBudget,
            timeout: ClaudeService.timeout
        )

        var claudeResult: ClaudeResult?
        var streamError: String?

        do {
            for try await event in stream {
                await onEvent(event)
                switch event {
                case .result(let result):
                    claudeResult = result
                case .error(let message):
                    streamError = message
                default:
                    break
                }
            }
        } catch let error as ForgeError {
            return handleFixError(error, mdPath: mdPath, backup: backup)
        } catch {
            restoreIfChanged(mdPath: mdPath, backup: backup)
            throw error
        }

        if let error = streamError {
            restoreIfChanged(mdPath: mdPath, backup: backup)
            return .claudeFailed(error)
        }

        if let result = claudeResult, result.isError {
            Self.logger.error("Claude returned error: \(result.result ?? "nil", privacy: .public)")
            try? fileSystem.writeString(backup, to: mdPath)
            return .claudeFailed(result.result ?? "Unknown error")
        }

        return try evaluateFixResult(
            mdPath: mdPath,
            backup: backup,
            claudeResult: claudeResult ?? ClaudeResult(result: nil, isError: false)
        )
    }

    private func evaluateFixResult(mdPath: String, backup: String, claudeResult: ClaudeResult) throws -> FixResult {
        let updated = try fileSystem.readString(at: mdPath)
        if hashString(updated) == hashString(backup) {
            let response = claudeResult.result ?? ""
            let cost = claudeResult.costUsd ?? 0
            Self.logger.warning("Claude did not modify file. cost=$\(cost) Response: \(response, privacy: .public)")
            return .claudeDidNotModify(response: response, costUsd: cost)
        }

        Self.logger.info("Fix complete — pending review for \(mdPath, privacy: .public)")
        return .pendingReview(before: backup, after: updated)
    }

    private func handleFixError(_ error: ForgeError, mdPath: String, backup: String) -> FixResult {
        restoreIfChanged(mdPath: mdPath, backup: backup)
        Self.logger.error("Fix failed: \(error.errorDescription ?? "Unknown", privacy: .public)")

        switch error {
        case .claudeTimeout:
            return .claudeTimeout
        case .claudeNotAvailable:
            return .claudeNotAvailable
        case .claudeFailed(let msg):
            return .claudeFailed(msg)
        default:
            return .claudeFailed(error.errorDescription ?? "Unknown error")
        }
    }

    private func restoreIfChanged(mdPath: String, backup: String) {
        let current = try? fileSystem.readString(at: mdPath)
        if let current, hashString(current) != hashString(backup) {
            try? fileSystem.writeString(backup, to: mdPath)
        }
    }

    // MARK: - Approve / Reject

    /// Confirms the Claude-generated change should persist on disk.
    /// Returns `true` if the file still matches `expectedAfterContent` (safe to keep).
    /// Returns `false` if the file was externally modified during review.
    public func approveChange(mdPath: String, expectedAfterContent: String) throws -> Bool {
        let current = try fileSystem.readString(at: mdPath)
        return hashString(current) == hashString(expectedAfterContent)
    }

    /// Restores the original content, discarding Claude's changes.
    public func rejectChange(mdPath: String, originalContent: String) throws {
        try fileSystem.writeString(originalContent, to: mdPath)
    }

    // MARK: - Content Hash

    public func contentHash(for path: String) throws -> String {
        let content = try fileSystem.readString(at: path)
        return hashString(content)
    }

    // MARK: - Prompts

    static func missingSectionPrompt(section: String, claudeMdPath: String) -> String {
        let sectionTitle = section
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        return """
        You MUST use the Edit tool to modify the file at \(claudeMdPath). Do not describe what \
        you would do — actually call the Edit tool to make the change.

        Steps:
        1. Use the Read tool to read \(claudeMdPath)
        2. Use Glob and Read to scan the codebase and understand its actual patterns
        3. Use the Edit tool to append a new ## \(sectionTitle) section at the end of \(claudeMdPath)

        Requirements for the new section:
        - Document ACTUAL patterns, frameworks, tools, and conventions found in this codebase
        - Reference real file paths, tool names, and patterns you observe
        - Keep it concise: 8-20 lines of actionable, project-specific guidance
        - Only ADD the new section — do not modify or remove existing content
        - Do NOT read or reference any .env files, secrets, credentials, or API keys
        - Do NOT include any secrets, tokens, or passwords in the content you write
        """
    }

    static func techGapPrompt(tech: String, claudeMdPath: String) -> String {
        """
        You MUST use the Edit tool to modify the file at \(claudeMdPath). Do not describe what \
        you would do — actually call the Edit tool to make the change.

        Steps:
        1. Use the Read tool to read \(claudeMdPath)
        2. Use Glob and Read to scan how \(tech) is used in this codebase
        3. Use the Edit tool to update \(claudeMdPath):
           - If a ## Tech Stack section exists, add \(tech) documentation to it
           - If no Tech Stack section exists, create one at the end of the file

        Requirements for the addition:
        - Document the version, key packages/config, and usage patterns you observe
        - Keep additions concise: 3-10 lines
        - Only ADD content — do not modify or remove existing content
        - Do NOT read or reference any .env files, secrets, credentials, or API keys
        """
    }

    // MARK: - Private

    private func extractTechName(from detail: String) -> String {
        guard let spaceIndex = detail.firstIndex(of: " ") else { return detail }
        let candidate = String(detail[detail.startIndex..<spaceIndex])
        return detail.hasPrefix("\(candidate) detected") ? candidate : detail
    }

    private func hashString(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
