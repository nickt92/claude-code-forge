import XCTest
import Foundation
@testable import ForgeDesktopCore

// MARK: - CodebaseContext Decoding Tests

final class CodebaseContextTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testDecodesAnalyzeFixture() throws {
        let data = try fixtureData("analyze")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: data)

        XCTAssertEqual(context.name, "my-project")
        XCTAssertEqual(context.path, "/Users/test/my-project")
        XCTAssertFalse(context.directoryStructure.isEmpty)
    }

    func testDecodesDependencies() throws {
        let data = try fixtureData("analyze")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: data)

        XCTAssertEqual(context.dependencies.count, 1)
        XCTAssertEqual(context.dependencies.first?.file, "package.json")
        XCTAssertTrue(context.dependencies.first!.content.contains("react"))
    }

    func testDecodesGitContext() throws {
        let data = try fixtureData("analyze")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: data)

        XCTAssertTrue(context.git.isRepo)
        XCTAssertEqual(context.git.branch, "main")
        XCTAssertEqual(context.git.defaultBranch, "main")
        XCTAssertEqual(context.git.recentCommits.count, 3)
        XCTAssertEqual(context.git.contributors.count, 2)
    }

    func testDecodesTestFiles() throws {
        let data = try fixtureData("analyze")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: data)

        XCTAssertEqual(context.testFiles.count, 2)
        XCTAssertTrue(context.testFiles.contains("tests/auth.test.ts"))
    }

    func testDecodesNullExistingClaudeMd() throws {
        let data = try fixtureData("analyze")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: data)

        XCTAssertNil(context.existingClaudeMd)
    }

    func testDecodesConfigs() throws {
        let data = try fixtureData("analyze")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: data)

        XCTAssertEqual(context.configs.count, 1)
        XCTAssertEqual(context.configs.first?.file, "tsconfig.json")
    }

    func testDecodesCiConfigs() throws {
        let data = try fixtureData("analyze")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: data)

        XCTAssertEqual(context.ciConfigs.count, 1)
        XCTAssertEqual(context.ciConfigs.first?.file, ".github/workflows/ci.yml")
    }

    func testDecodesScripts() throws {
        let data = try fixtureData("analyze")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: data)

        XCTAssertEqual(context.scripts.count, 2)
        XCTAssertTrue(context.scripts.contains("scripts/deploy.sh"))
    }

    func testDecodesWithExistingClaudeMd() throws {
        let json = """
        {
          "path": "/test",
          "name": "test",
          "directory_structure": ".",
          "dependencies": [],
          "configs": [],
          "documentation": [],
          "git": {"is_repo": false, "branch": null, "default_branch": null, "recent_commits": [], "contributors": []},
          "test_files": [],
          "scripts": [],
          "existing_claude_md": "# CLAUDE.md\\nExisting content",
          "ci_configs": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let context = try decoder.decode(CodebaseContext.self, from: json)

        XCTAssertNotNil(context.existingClaudeMd)
        XCTAssertTrue(context.existingClaudeMd!.contains("CLAUDE.md"))
    }
}

// MARK: - OnboardingService Tests

final class OnboardingServiceTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testAnalyzeRepoDecodesSuccessfully() async throws {
        let data = try fixtureData("analyze")
        let executor = MockExecutor(data: data)
        let claudeService = ClaudeService(executor: executor, claudePath: "/usr/local/bin/claude")
        let service = OnboardingService(
            executor: executor,
            claudeService: claudeService,
            forgePath: "/usr/bin/true"
        )

        let context = try await service.analyzeRepo(path: "/test/repo")

        XCTAssertEqual(context.name, "my-project")
        XCTAssertEqual(context.dependencies.count, 1)
        XCTAssertTrue(context.git.isRepo)
    }

    func testAnalyzeRepoThrowsOnBadJSON() async throws {
        let badData = "not json".data(using: .utf8)!
        let executor = MockExecutor(data: badData)
        let claudeService = ClaudeService(executor: executor, claudePath: "/usr/local/bin/claude")
        let service = OnboardingService(
            executor: executor,
            claudeService: claudeService,
            forgePath: "/usr/bin/true"
        )

        do {
            _ = try await service.analyzeRepo(path: "/test")
            XCTFail("Expected decoding error")
        } catch let error as ForgeError {
            guard case .jsonDecodingFailed = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
        }
    }

    func testSaveClaudeMdCreatesFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let claudeService = ClaudeService(executor: MockExecutor(data: Data()), claudePath: nil)
        let service = OnboardingService(
            executor: MockExecutor(data: Data()),
            claudeService: claudeService
        )

        try service.saveClaudeMd(content: "# Test CLAUDE.md", repoPath: tmpDir.path)

        let mdPath = tmpDir.appendingPathComponent(".claude/CLAUDE.md").path
        let written = try String(contentsOfFile: mdPath, encoding: .utf8)
        XCTAssertEqual(written, "# Test CLAUDE.md")
    }
}

// MARK: - ClaudeStreamEvent Parsing Tests

final class ClaudeStreamParsingTests: XCTestCase {

    func testParsesAssistantTextDelta() {
        let line = """
        {"type":"content_block_delta","delta":{"text":"Hello world"}}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .assistantText(let text) = event {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .assistantText, got \(String(describing: event))")
        }
    }

    func testParsesToolUse() {
        let line = """
        {"type":"tool_use","name":"Read","input":{"file_path":"/test/file.txt"}}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .toolUse(let name, let input) = event {
            XCTAssertEqual(name, "Read")
            XCTAssertTrue(input.contains("file_path"))
        } else {
            XCTFail("Expected .toolUse, got \(String(describing: event))")
        }
    }

    func testParsesToolResult() {
        let line = """
        {"type":"tool_result","name":"Read","output":"file contents here"}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .toolResult(let name, let output) = event {
            XCTAssertEqual(name, "Read")
            XCTAssertEqual(output, "file contents here")
        } else {
            XCTFail("Expected .toolResult, got \(String(describing: event))")
        }
    }

    func testParsesResultEvent() {
        let line = """
        {"type":"result","result":"Done generating","is_error":false,"total_cost_usd":0.15}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .result(let result) = event {
            XCTAssertEqual(result.result, "Done generating")
            XCTAssertFalse(result.isError)
            XCTAssertEqual(result.costUsd!, 0.15, accuracy: 0.001)
        } else {
            XCTFail("Expected .result, got \(String(describing: event))")
        }
    }

    func testParsesResultEventWithLegacyCostKey() {
        let line = """
        {"type":"result","result":"Done","is_error":false,"cost_usd":0.10}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .result(let result) = event {
            XCTAssertEqual(result.costUsd!, 0.10, accuracy: 0.001)
        } else {
            XCTFail("Expected .result, got \(String(describing: event))")
        }
    }

    func testParsesErrorEvent() {
        let line = """
        {"type":"error","error":"Rate limit exceeded"}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .error(let message) = event {
            XCTAssertEqual(message, "Rate limit exceeded")
        } else {
            XCTFail("Expected .error, got \(String(describing: event))")
        }
    }

    func testReturnsNilForUnknownType() {
        let line = """
        {"type":"ping"}
        """
        let event = ClaudeService.parseStreamLine(line)
        XCTAssertNil(event)
    }

    func testReturnsNilForInvalidJSON() {
        let event = ClaudeService.parseStreamLine("not json at all")
        XCTAssertNil(event)
    }

    func testReturnsNilForEmptyLine() {
        let event = ClaudeService.parseStreamLine("")
        XCTAssertNil(event)
    }

    // MARK: - Real CLI Format (stream_event wrapper)

    func testParsesWrappedTextDelta() {
        let line = """
        {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello from CLI"}},"uuid":"abc","session_id":"xyz"}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .assistantText(let text) = event {
            XCTAssertEqual(text, "Hello from CLI")
        } else {
            XCTFail("Expected .assistantText, got \(String(describing: event))")
        }
    }

    func testParsesWrappedToolUseStart() {
        let line = """
        {"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_123","name":"Read","input":{}}},"uuid":"abc","session_id":"xyz"}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .toolUse(let name, _) = event {
            XCTAssertEqual(name, "Read")
        } else {
            XCTFail("Expected .toolUse, got \(String(describing: event))")
        }
    }

    func testParsesWrappedToolResult() {
        // Use a shared context so trackToolName persists for the result parse
        let context = StreamParsingContext()
        context.trackToolName(id: "toolu_456", name: "Glob")

        let line = """
        {"type":"stream_event","event":{"type":"message_start","message":{"id":"msg_1","type":"message","role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_456","content":"found 5 files"}],"model":"sonnet","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":0,"output_tokens":0}}},"uuid":"abc","session_id":"xyz"}
        """
        let event = ClaudeService.parseStreamLine(line, context: context)

        if case .toolResult(let name, let output) = event {
            XCTAssertEqual(name, "Glob")
            XCTAssertEqual(output, "found 5 files")
        } else {
            XCTFail("Expected .toolResult, got \(String(describing: event))")
        }
    }

    func testParsesWrappedResult() {
        let line = """
        {"type":"stream_event","event":{"type":"result","result":"Done","is_error":false,"total_cost_usd":0.05},"uuid":"abc","session_id":"xyz"}
        """
        let event = ClaudeService.parseStreamLine(line)

        if case .result(let result) = event {
            XCTAssertEqual(result.result, "Done")
            XCTAssertFalse(result.isError)
            XCTAssertEqual(result.costUsd!, 0.05, accuracy: 0.001)
        } else {
            XCTFail("Expected .result, got \(String(describing: event))")
        }
    }

    func testIgnoresMessageDelta() {
        let line = """
        {"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"}},"uuid":"abc","session_id":"xyz"}
        """
        let event = ClaudeService.parseStreamLine(line)
        XCTAssertNil(event)
    }

    func testIgnoresMessageStop() {
        let line = """
        {"type":"stream_event","event":{"type":"message_stop"},"uuid":"abc","session_id":"xyz"}
        """
        let event = ClaudeService.parseStreamLine(line)
        XCTAssertNil(event)
    }
}

// MARK: - ToolActivity Tests

final class ToolActivityTests: XCTestCase {

    func testReadDisplayLabel() {
        let activity = ToolActivity(
            name: "Read",
            input: "{\"file_path\":\"/src/components/App.tsx\"}"
        )
        XCTAssertEqual(activity.displayLabel, "Read components/App.tsx")
    }

    func testGlobDisplayLabel() {
        let activity = ToolActivity(
            name: "Glob",
            input: "{\"pattern\":\"src/**/*.ts\"}"
        )
        XCTAssertEqual(activity.displayLabel, "Glob src/**/*.ts")
    }

    func testGrepDisplayLabel() {
        let activity = ToolActivity(
            name: "Grep",
            input: "{\"pattern\":\"function handleAuth\"}"
        )
        XCTAssertEqual(activity.displayLabel, "Search \"function handleAuth\"")
    }

    func testUnknownToolDisplayLabel() {
        let activity = ToolActivity(name: "Write", input: "{}")
        XCTAssertEqual(activity.displayLabel, "Write")
    }

    func testInvalidInputFallsBack() {
        let activity = ToolActivity(name: "Read", input: "not json")
        XCTAssertEqual(activity.displayLabel, "Read file")
    }
}

// MARK: - MockExecutor Stream Tests

final class MockExecutorStreamTests: XCTestCase {

    func testStreamYieldsLines() async throws {
        let lines = "line1\nline2\nline3\n"
        let data = lines.data(using: .utf8)!
        let executor = MockExecutor(data: data)

        var collected: [String] = []
        for try await chunk in executor.stream(executable: "test", arguments: [], workingDirectory: nil, timeout: nil) {
            if let str = String(data: chunk, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                collected.append(str)
            }
        }

        XCTAssertTrue(collected.contains("line1"))
        XCTAssertTrue(collected.contains("line2"))
        XCTAssertTrue(collected.contains("line3"))
    }

    func testStreamThrowsOnError() async {
        let executor = MockExecutor(error: ForgeError.cliNotFound)

        do {
            for try await _ in executor.stream(executable: "test", arguments: [], workingDirectory: nil, timeout: nil) {
                XCTFail("Should not yield")
            }
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
    }
}

// MARK: - LineBuffer Tests

final class LineBufferTests: XCTestCase {

    func testSplitsCompleteLines() {
        let buffer = LineBuffer()
        let data = "line1\nline2\n".data(using: .utf8)!

        let lines = buffer.append(data)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(data: lines[0], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), "line1")
        XCTAssertEqual(String(data: lines[1], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), "line2")
    }

    func testBuffersPartialLines() {
        let buffer = LineBuffer()
        let data = "partial".data(using: .utf8)!

        let lines = buffer.append(data)

        XCTAssertTrue(lines.isEmpty)
    }

    func testFlushesRemainingBuffer() {
        let buffer = LineBuffer()
        _ = buffer.append("partial".data(using: .utf8)!)

        let remaining = buffer.flush()

        XCTAssertNotNil(remaining)
        XCTAssertEqual(String(data: remaining!, encoding: .utf8), "partial")
    }

    func testFlushReturnsNilWhenEmpty() {
        let buffer = LineBuffer()

        let remaining = buffer.flush()

        XCTAssertNil(remaining)
    }

    func testHandlesMultipleAppends() {
        let buffer = LineBuffer()

        let lines1 = buffer.append("first part".data(using: .utf8)!)
        XCTAssertTrue(lines1.isEmpty)

        let lines2 = buffer.append(" continued\nsecond line\n".data(using: .utf8)!)
        XCTAssertEqual(lines2.count, 2)
    }
}
