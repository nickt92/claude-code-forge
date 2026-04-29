import XCTest
import Foundation
@testable import ForgeDesktopCore

final class StreamParsingContextTests: XCTestCase {

    // MARK: - Isolation

    func testSeparateContextsDoNotShareState() {
        let ctx1 = StreamParsingContext()
        let ctx2 = StreamParsingContext()

        ctx1.trackToolName(id: "toolu_1", name: "Read")
        XCTAssertEqual(ctx1.resolveToolName(forId: "toolu_1"), "Read")
        XCTAssertEqual(ctx2.resolveToolName(forId: "toolu_1"), "unknown")
    }

    func testContextCleansUpAfterBlockStop() {
        let ctx = StreamParsingContext()

        // Start a tool use block at index 0
        let startLine = """
        {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"Edit","input":{}}}
        """
        let event = ctx.parseLine(startLine)
        XCTAssertNotNil(event)
        XCTAssertEqual(ctx.toolInputBuffers.count, 1)

        // Stop the block
        let stopLine = """
        {"type":"content_block_stop","index":0}
        """
        _ = ctx.parseLine(stopLine)
        XCTAssertEqual(ctx.toolInputBuffers.count, 0)
    }

    // MARK: - Tool Input Accumulation

    func testAccumulatesInputJsonDeltas() {
        let ctx = StreamParsingContext()

        // Start tool use
        let startLine = """
        {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_2","name":"Read","input":{}}}
        """
        _ = ctx.parseLine(startLine)

        // Send partial JSON deltas
        let delta1 = """
        {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"file"}}
        """
        _ = ctx.parseLine(delta1)

        let delta2 = """
        {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"_path\\":\\"test.txt\\"}"}}
        """
        _ = ctx.parseLine(delta2)

        XCTAssertTrue(ctx.toolInputBuffers[1]?.json.contains("file") == true)
    }

    // MARK: - Delta Events

    func testTextDeltaReturnsAssistantText() {
        let ctx = StreamParsingContext()
        let line = """
        {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello world"}}
        """
        let event = ctx.parseLine(line)

        if case .assistantText(let text) = event {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .assistantText, got \(String(describing: event))")
        }
    }

    func testResultEventParsed() {
        let ctx = StreamParsingContext()
        let line = """
        {"type":"result","result":"Done","is_error":false,"total_cost_usd":0.10}
        """
        let event = ctx.parseLine(line)

        if case .result(let result) = event {
            XCTAssertEqual(result.result, "Done")
            XCTAssertFalse(result.isError)
            XCTAssertEqual(result.costUsd!, 0.10, accuracy: 0.001)
        } else {
            XCTFail("Expected .result, got \(String(describing: event))")
        }
    }

    func testErrorEventParsed() {
        let ctx = StreamParsingContext()
        let line = """
        {"type":"error","error":"Something broke"}
        """
        let event = ctx.parseLine(line)

        if case .error(let msg) = event {
            XCTAssertEqual(msg, "Something broke")
        } else {
            XCTFail("Expected .error, got \(String(describing: event))")
        }
    }

    // MARK: - Legacy Format

    func testLegacyFlatToolUse() {
        let ctx = StreamParsingContext()
        let line = """
        {"type":"tool_use","name":"Grep","input":{"pattern":"TODO"}}
        """
        let event = ctx.parseLine(line)

        if case .toolUse(let name, let input) = event {
            XCTAssertEqual(name, "Grep")
            XCTAssertTrue(input.contains("TODO"))
        } else {
            XCTFail("Expected .toolUse, got \(String(describing: event))")
        }
    }

    func testLegacyFlatToolResult() {
        let ctx = StreamParsingContext()
        let line = """
        {"type":"tool_result","name":"Read","output":"file contents"}
        """
        let event = ctx.parseLine(line)

        if case .toolResult(let name, let output) = event {
            XCTAssertEqual(name, "Read")
            XCTAssertEqual(output, "file contents")
        } else {
            XCTFail("Expected .toolResult, got \(String(describing: event))")
        }
    }

    func testLegacyAssistantMessage() {
        let ctx = StreamParsingContext()
        let line = """
        {"type":"assistant","message":{"content":[{"text":"I will help you."}]}}
        """
        let event = ctx.parseLine(line)

        if case .assistantText(let text) = event {
            XCTAssertEqual(text, "I will help you.")
        } else {
            XCTFail("Expected .assistantText, got \(String(describing: event))")
        }
    }

    // MARK: - Edge Cases

    func testInvalidJsonReturnsNil() {
        let ctx = StreamParsingContext()
        XCTAssertNil(ctx.parseLine("not json"))
    }

    func testEmptyStringReturnsNil() {
        let ctx = StreamParsingContext()
        XCTAssertNil(ctx.parseLine(""))
    }

    func testUnknownTypeReturnsNil() {
        let ctx = StreamParsingContext()
        let line = """
        {"type":"ping","data":"keepalive"}
        """
        XCTAssertNil(ctx.parseLine(line))
    }
}

// MARK: - Additional Model Decoding Tests

final class PermissionModelTests: XCTestCase {

    func testPermissionPresetDecoding() throws {
        let json = """
        {"id":"balanced","label":"Balanced","tier":2,"description":"Read and write with prompts","detail":"Moderate access","permissions":["Read","Edit","Write"],"inherits":null}
        """.data(using: .utf8)!

        let preset = try JSONDecoder().decode(PermissionPreset.self, from: json)
        XCTAssertEqual(preset.id, "balanced")
        XCTAssertEqual(preset.label, "Balanced")
        XCTAssertEqual(preset.tier, 2)
        XCTAssertEqual(preset.permissions.count, 3)
    }

    func testPermissionPresetWithInheritance() throws {
        let json = """
        {"id":"full","label":"Full Access","tier":3,"description":"All tools","detail":"Max access","permissions":["Read","Edit","Write","Bash"],"inherits":"balanced"}
        """.data(using: .utf8)!

        let preset = try JSONDecoder().decode(PermissionPreset.self, from: json)
        XCTAssertEqual(preset.inherits, "balanced")
    }

    func testPermissionsStateDecoding() throws {
        let json = """
        {"current_preset":"balanced","effective_permissions":["Read","Edit"]}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let state = try decoder.decode(PermissionsState.self, from: json)
        XCTAssertEqual(state.currentPreset, "balanced")
        XCTAssertEqual(state.effectivePermissions.count, 2)
    }

    func testPermissionsStateWithNullPreset() throws {
        let json = """
        {"current_preset":null,"effective_permissions":[]}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let state = try decoder.decode(PermissionsState.self, from: json)
        XCTAssertNil(state.currentPreset)
        XCTAssertTrue(state.effectivePermissions.isEmpty)
    }
}
