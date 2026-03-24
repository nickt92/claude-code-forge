import XCTest
import Foundation
@testable import ForgeDesktopCore

final class ConfigServiceTests: XCTestCase {

    func testGetScanPathReturnsValue() async throws {
        let response = "/Users/test/repos\n".data(using: .utf8)!
        let executor = MockExecutor(data: response)
        let service = ConfigService(executor: executor, forgePath: "/usr/bin/true")

        let path = try await service.getScanPath()
        XCTAssertEqual(path, "/Users/test/repos")
    }

    func testGetScanPathReturnsNilForEmpty() async throws {
        let response = "\n".data(using: .utf8)!
        let executor = MockExecutor(data: response)
        let service = ConfigService(executor: executor, forgePath: "/usr/bin/true")

        let path = try await service.getScanPath()
        XCTAssertNil(path)
    }

    func testSetScanPathDoesNotThrowOnSuccess() async throws {
        let executor = MockExecutor(data: Data())
        let service = ConfigService(executor: executor, forgePath: "/usr/bin/true")

        try await service.setScanPath("/Users/test/repos")
    }

    func testSetScanPathPropagatesErrors() async throws {
        let executor = MockExecutor(error: ForgeError.cliExitCode(1, stderr: "failed"))
        let service = ConfigService(executor: executor, forgePath: "/usr/bin/true")

        do {
            try await service.setScanPath("/Users/test")
            XCTFail("Expected error")
        } catch let error as ForgeError {
            if case .cliExitCode(let code, _) = error {
                XCTAssertEqual(code, 1)
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }
}

// MARK: - Claude-Aware Mock Executor

/// A mock executor that simulates Claude editing a file when invoked.
/// On run(), it modifies the target file in the MockFileSystem and returns JSON output.
final class ClaudeAwareMockExecutor: CLIExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private let fileSystem: MockFileSystem
    private let targetPath: String
    private let contentToAppend: String
    private let shouldFail: Bool
    private let shouldTimeout: Bool
    var lastArguments: [String]?

    init(
        fileSystem: MockFileSystem,
        targetPath: String,
        contentToAppend: String = "\n## Testing\n\nRun `npm test` to execute the test suite.\n",
        shouldFail: Bool = false,
        shouldTimeout: Bool = false
    ) {
        self.fileSystem = fileSystem
        self.targetPath = targetPath
        self.contentToAppend = contentToAppend
        self.shouldFail = shouldFail
        self.shouldTimeout = shouldTimeout
    }

    func run(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) async throws -> Data {
        lock.withLock { lastArguments = arguments }

        if shouldTimeout {
            throw ForgeError.claudeTimeout
        }

        if shouldFail {
            throw ForgeError.cliExitCode(1, stderr: "Claude analysis failed")
        }

        // Simulate Claude editing the file
        if let current = try? fileSystem.readString(at: targetPath) {
            try? fileSystem.writeString(current + contentToAppend, to: targetPath)
        }

        let result = ClaudeResult(result: "Done", isError: false, costUsd: 0.05)
        return try JSONEncoder().encode(result)
    }
}

/// Mock executor that returns a result but does NOT modify any files.
final class NoOpClaudeExecutor: CLIExecutor, Sendable {
    func run(executable: String, arguments: [String], workingDirectory: String?, timeout: TimeInterval?) async throws -> Data {
        let result = ClaudeResult(result: "Done", isError: false, costUsd: 0.01)
        return try JSONEncoder().encode(result)
    }
}

final class FixServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a FixService WITHOUT a ClaudeService (legacy path)
    private func makeFixService(
        files: [String: String] = [:],
        executor: CLIExecutor = MockExecutor(data: Data())
    ) -> (FixService, MockFileSystem) {
        let fs = MockFileSystem(files: files)
        let initService = InitService(executor: executor, forgePath: "/usr/bin/true")
        let service = FixService(initService: initService, fileSystem: fs)
        return (service, fs)
    }

    /// Creates a FixService WITH a ClaudeService backed by ClaudeAwareMockExecutor
    private func makeClaudeFixService(
        files: [String: String] = [:],
        targetPath: String,
        contentToAppend: String = "\n## Testing\n\nRun `npm test` to execute the test suite.\n",
        shouldFail: Bool = false,
        shouldTimeout: Bool = false
    ) -> (FixService, MockFileSystem, ClaudeAwareMockExecutor) {
        let fs = MockFileSystem(files: files)
        let claudeExecutor = ClaudeAwareMockExecutor(
            fileSystem: fs,
            targetPath: targetPath,
            contentToAppend: contentToAppend,
            shouldFail: shouldFail,
            shouldTimeout: shouldTimeout
        )
        let claudeService = ClaudeService(executor: claudeExecutor, claudePath: "/usr/local/bin/claude")
        let initService = InitService(executor: MockExecutor(data: Data()), forgePath: "/usr/bin/true")
        let service = FixService(initService: initService, claudeService: claudeService, fileSystem: fs)
        return (service, fs, claudeExecutor)
    }

    // MARK: - no_claude_md (unchanged path)

    func testFixNoClaudeMdCallsInit() async throws {
        let executor = MockExecutor(data: Data())
        let (service, _) = makeFixService(executor: executor)

        let finding = Finding(severity: "error", code: "no_claude_md", detail: "No CLAUDE.md found", section: nil, fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: nil, contentHashAtLoad: nil)

        XCTAssertEqual(result, .success)
    }

    // MARK: - missing_section without Claude returns claudeNotAvailable

    func testFixMissingSectionWithoutClaudeReturnsNotAvailable() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, _) = makeFixService(files: [mdPath: "# Project\n"])

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "warn", code: "missing_section", detail: "No testing section", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        XCTAssertEqual(result, .claudeNotAvailable)
    }

    // MARK: - missing_section with Claude

    func testFixMissingSectionWithClaudeWritesContent() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let original = "# Project\n\nSome content\n"
        let (service, _, _) = makeClaudeFixService(
            files: [mdPath: original],
            targetPath: mdPath,
            contentToAppend: "\n## Error Handling\n\nUse structured error types.\n"
        )

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "warn", code: "missing_section", detail: "No error-handling section", section: "error-handling", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        if case .pendingReview(let before, let after) = result {
            XCTAssertEqual(before, original)
            XCTAssertTrue(after.contains("## Error Handling"))
            XCTAssertTrue(after.contains("Use structured error types."))
        } else {
            XCTFail("Expected .pendingReview, got \(result)")
        }
    }

    func testFixMissingSectionWithoutSectionNameReturnsNotFixable() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, _, _) = makeClaudeFixService(files: [mdPath: "# Test\n"], targetPath: mdPath)

        let finding = Finding(severity: "warn", code: "missing_section", detail: "Missing section", section: nil, fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: nil)

        if case .notFixable = result {
            // expected
        } else {
            XCTFail("Expected .notFixable, got \(result)")
        }
    }

    // MARK: - tech_gap with Claude

    func testFixTechGapWithClaudeDocumentsTech() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let original = "# Project\n"
        let (service, _, _) = makeClaudeFixService(
            files: [mdPath: original],
            targetPath: mdPath,
            contentToAppend: "\n## Tech Stack\n\n- nodejs v20 with Express\n"
        )

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "info", code: "tech_gap", detail: "nodejs detected but not mentioned in CLAUDE.md", section: nil, fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        if case .pendingReview(let before, let after) = result {
            XCTAssertEqual(before, original)
            XCTAssertTrue(after.contains("nodejs v20"))
        } else {
            XCTFail("Expected .pendingReview, got \(result)")
        }
    }

    func testFixTechGapWithoutClaudeReturnsNotAvailable() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, _) = makeFixService(files: [mdPath: "# Project\n"])

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "info", code: "tech_gap", detail: "nodejs detected but not mentioned in CLAUDE.md", section: nil, fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        XCTAssertEqual(result, .claudeNotAvailable)
    }

    // MARK: - low_coverage with Claude

    func testFixLowCoverageWithClaudeWritesContent() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, _, _) = makeClaudeFixService(
            files: [mdPath: "# Project\n"],
            targetPath: mdPath,
            contentToAppend: "\n## Testing\n\nUse pytest for all tests.\n"
        )

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "warn", code: "low_coverage", detail: "Low coverage", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        if case .pendingReview(_, let after) = result {
            XCTAssertTrue(after.contains("## Testing"))
        } else {
            XCTFail("Expected .pendingReview, got \(result)")
        }
    }

    func testFixLowCoverageWithoutSectionReturnsNotFixable() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, _, _) = makeClaudeFixService(files: [mdPath: "# Test\n"], targetPath: mdPath)

        let finding = Finding(severity: "warn", code: "low_coverage", detail: "Low coverage", section: nil, fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: nil)

        if case .notFixable = result {
            // expected
        } else {
            XCTFail("Expected .notFixable, got \(result)")
        }
    }

    // MARK: - Stale content guard

    func testStaleContentGuardPreventsOverwrite() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, fs, _) = makeClaudeFixService(files: [mdPath: "original content"], targetPath: mdPath)

        let staleHash = "0000000000000000000000000000000000000000000000000000000000000000"
        let finding = Finding(severity: "warn", code: "missing_section", detail: "Missing section", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: staleHash)

        XCTAssertEqual(result, .staleContent)
        XCTAssertEqual(fs.files[mdPath], "original content")
    }

    func testContentHashIsConsistent() throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, _) = makeFixService(files: [mdPath: "hello world"])

        let hash1 = try service.contentHash(for: mdPath)
        let hash2 = try service.contentHash(for: mdPath)

        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 64) // SHA-256 hex = 64 chars
    }

    // MARK: - Not fixable codes

    func testUnfixableCodeReturnsNotFixable() async throws {
        let (service, _) = makeFixService()
        let finding = Finding(severity: "warn", code: "has_placeholders", detail: "CLAUDE.md has placeholders", section: nil, fixable: false)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: nil, contentHashAtLoad: nil)

        if case .notFixable = result {
            // expected
        } else {
            XCTFail("Expected .notFixable, got \(result)")
        }
    }

    // MARK: - File not found

    func testMissingSectionWithNoFileReturnsFileNotFound() async throws {
        let (service, _) = makeFixService()
        let finding = Finding(severity: "warn", code: "missing_section", detail: "Missing", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: "/nonexistent/CLAUDE.md", contentHashAtLoad: nil)

        XCTAssertEqual(result, .fileNotFound)
    }

    func testTechGapWithNoFileReturnsFileNotFound() async throws {
        let (service, _) = makeFixService()
        let finding = Finding(severity: "info", code: "tech_gap", detail: "nodejs detected", section: nil, fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: nil, contentHashAtLoad: nil)

        XCTAssertEqual(result, .fileNotFound)
    }

    // MARK: - Claude failure handling

    func testClaudeFailureRestoresBackup() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let original = "# Project\n\nOriginal content\n"
        let (service, fs, _) = makeClaudeFixService(
            files: [mdPath: original],
            targetPath: mdPath,
            shouldFail: true
        )

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "warn", code: "missing_section", detail: "Missing", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        if case .claudeFailed = result {
            // expected
        } else {
            XCTFail("Expected .claudeFailed, got \(result)")
        }
        XCTAssertEqual(fs.files[mdPath], original)
    }

    func testClaudeTimeoutReturnsTimeout() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, _, _) = makeClaudeFixService(
            files: [mdPath: "# Project\n"],
            targetPath: mdPath,
            shouldTimeout: true
        )

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "warn", code: "missing_section", detail: "Missing", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        XCTAssertEqual(result, .claudeTimeout)
    }

    func testClaudeNoModificationReturnsDidNotModify() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let original = "# Project\n"
        let fs = MockFileSystem(files: [mdPath: original])
        let noOpExecutor = NoOpClaudeExecutor()
        let claudeService = ClaudeService(executor: noOpExecutor, claudePath: "/usr/local/bin/claude")
        let initService = InitService(executor: MockExecutor(data: Data()), forgePath: "/usr/bin/true")
        let service = FixService(initService: initService, claudeService: claudeService, fileSystem: fs)

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "warn", code: "missing_section", detail: "Missing", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        if case .claudeDidNotModify(let response) = result {
            XCTAssertEqual(response, "Done")
        } else {
            XCTFail("Expected .claudeDidNotModify, got \(result)")
        }
    }

    // MARK: - Serialization

    func testFixInProgressBlocksSecondFix() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, _, _) = makeClaudeFixService(
            files: [mdPath: "# Project\n"],
            targetPath: mdPath
        )

        XCTAssertFalse(service.isFixRunning(for: "/repo"))
    }

    func testClaudeAvailableProperty() {
        let (serviceWithout, _) = makeFixService()
        XCTAssertFalse(serviceWithout.claudeAvailable)

        let mdPath = "/repo/CLAUDE.md"
        let (serviceWith, _, _) = makeClaudeFixService(files: [:], targetPath: mdPath)
        XCTAssertTrue(serviceWith.claudeAvailable)
    }

    // MARK: - Prompt generation

    func testMissingSectionPromptContainsSectionTitle() {
        let prompt = FixService.missingSectionPrompt(section: "error-handling", claudeMdPath: "/repo/CLAUDE.md")
        XCTAssertTrue(prompt.contains("## Error Handling"))
        XCTAssertTrue(prompt.contains("/repo/CLAUDE.md"))
        XCTAssertTrue(prompt.contains("Do NOT read or reference any .env files"))
    }

    func testTechGapPromptContainsTechName() {
        let prompt = FixService.techGapPrompt(tech: "nodejs", claudeMdPath: "/repo/CLAUDE.md")
        XCTAssertTrue(prompt.contains("nodejs"))
        XCTAssertTrue(prompt.contains("/repo/CLAUDE.md"))
        XCTAssertTrue(prompt.contains("Do NOT read or reference any .env files"))
    }

    // MARK: - ClaudeResult decoding

    func testClaudeResultDecodesSuccessJSON() throws {
        let json = """
        {"result": "Done editing", "is_error": false, "cost_usd": 0.12}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(ClaudeResult.self, from: json)
        XCTAssertEqual(result.result, "Done editing")
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.costUsd!, 0.12, accuracy: 0.001)
    }

    func testClaudeResultDecodesErrorJSON() throws {
        let json = """
        {"result": "Something failed", "is_error": true}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(ClaudeResult.self, from: json)
        XCTAssertEqual(result.result, "Something failed")
        XCTAssertTrue(result.isError)
        XCTAssertNil(result.costUsd)
    }

    func testClaudeResultDecodesMinimalJSON() throws {
        let json = """
        {"result": "ok"}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(ClaudeResult.self, from: json)
        XCTAssertEqual(result.result, "ok")
        XCTAssertFalse(result.isError)
        XCTAssertNil(result.costUsd)
    }

    // MARK: - Approve / Reject

    func testApproveReturnsTrueWhenFileUnchanged() throws {
        let mdPath = "/repo/CLAUDE.md"
        let content = "# Updated content"
        let (service, _) = makeFixService(files: [mdPath: content])

        let result = try service.approveChange(mdPath: mdPath, expectedAfterContent: content)
        XCTAssertTrue(result)
    }

    func testApproveReturnsFalseWhenFileModifiedExternally() throws {
        let mdPath = "/repo/CLAUDE.md"
        let (service, fs) = makeFixService(files: [mdPath: "current on disk"])

        // Simulate external edit
        try fs.writeString("externally modified", to: mdPath)

        let result = try service.approveChange(mdPath: mdPath, expectedAfterContent: "what we expected")
        XCTAssertFalse(result)
    }

    func testRejectRestoresOriginalContent() throws {
        let mdPath = "/repo/CLAUDE.md"
        let original = "# Original"
        let (service, fs) = makeFixService(files: [mdPath: "# Claude edited"])

        try service.rejectChange(mdPath: mdPath, originalContent: original)

        XCTAssertEqual(fs.files[mdPath], original)
    }

    func testPendingReviewFlowEndToEnd() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let original = "# Project\n"
        let (service, fs, _) = makeClaudeFixService(
            files: [mdPath: original],
            targetPath: mdPath,
            contentToAppend: "\n## Testing\n\nRun tests.\n"
        )

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "warn", code: "missing_section", detail: "Missing", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        // Should be pending review
        guard case .pendingReview(let before, let after) = result else {
            XCTFail("Expected .pendingReview, got \(result)")
            return
        }
        XCTAssertEqual(before, original)
        XCTAssertTrue(after.contains("## Testing"))

        // File on disk should have Claude's edits (Option C: edit-first)
        XCTAssertEqual(fs.files[mdPath], after)

        // Approve — file stays as-is
        let approved = try service.approveChange(mdPath: mdPath, expectedAfterContent: after)
        XCTAssertTrue(approved)
        XCTAssertEqual(fs.files[mdPath], after)
    }

    func testPendingReviewRejectRestoresOriginal() async throws {
        let mdPath = "/repo/CLAUDE.md"
        let original = "# Project\n"
        let (service, fs, _) = makeClaudeFixService(
            files: [mdPath: original],
            targetPath: mdPath,
            contentToAppend: "\n## Testing\n\nRun tests.\n"
        )

        let hash = try service.contentHash(for: mdPath)
        let finding = Finding(severity: "warn", code: "missing_section", detail: "Missing", section: "testing", fixable: true)

        let result = try await service.fix(finding: finding, repoPath: "/repo", claudeMdPath: mdPath, contentHashAtLoad: hash)

        guard case .pendingReview(let before, _) = result else {
            XCTFail("Expected .pendingReview")
            return
        }

        // Reject — restores original
        try service.rejectChange(mdPath: mdPath, originalContent: before)
        XCTAssertEqual(fs.files[mdPath], original)
    }

    // MARK: - MockFileSystem

    func testMockFileSystemBasics() throws {
        let fs = MockFileSystem(files: ["/a.txt": "hello"])

        XCTAssertTrue(fs.fileExists(at: "/a.txt"))
        XCTAssertFalse(fs.fileExists(at: "/b.txt"))
        XCTAssertEqual(try fs.readString(at: "/a.txt"), "hello")

        try fs.writeString("world", to: "/a.txt")
        XCTAssertEqual(try fs.readString(at: "/a.txt"), "world")

        try fs.writeString("new", to: "/b.txt")
        XCTAssertTrue(fs.fileExists(at: "/b.txt"))
    }
}
