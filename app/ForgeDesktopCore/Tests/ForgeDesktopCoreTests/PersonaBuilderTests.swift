import XCTest
import Foundation
@testable import ForgeDesktopCore

final class PersonaBuilderTests: XCTestCase {

    private let builtins = ["senior-engineer", "cto-architect"]
    private let customs = ["custom-backend-lead"]

    // MARK: - Name validation (mirrors lib/cmd-build.sh rules)

    func testValidName() {
        var draft = PersonaDraft()
        draft.name = "my-persona2"
        XCTAssertEqual(draft.validateName(builtinIds: builtins, customIds: customs), .valid)
    }

    func testEmptyName() {
        let draft = PersonaDraft()
        XCTAssertEqual(draft.validateName(builtinIds: builtins, customIds: customs), .empty)
    }

    func testInvalidFormatRejected() {
        var draft = PersonaDraft()
        for bad in ["9starts-with-digit", "has space", "has_underscore", "-leading-hyphen", "ümlaut"] {
            draft.name = bad
            XCTAssertEqual(
                draft.validateName(builtinIds: builtins, customIds: customs),
                .invalidFormat, "expected '\(bad)' to be invalid"
            )
        }
    }

    func testBuiltinCollisionRejected() {
        var draft = PersonaDraft()
        draft.name = "senior-engineer"
        XCTAssertEqual(draft.validateName(builtinIds: builtins, customIds: customs), .builtinCollision)
    }

    func testExistingCustomRequiresForce() {
        var draft = PersonaDraft()
        draft.name = "backend-lead"
        XCTAssertEqual(draft.validateName(builtinIds: builtins, customIds: customs), .customExists)

        draft.force = true
        XCTAssertEqual(draft.validateName(builtinIds: builtins, customIds: customs), .valid)
    }

    // MARK: - CLI argument assembly

    func testCliArgumentsAssembly() {
        var draft = PersonaDraft()
        draft.name = "lead"
        draft.communication = "expert"
        draft.autonomy = "high"
        draft.workflow = "advanced"
        draft.depth = "engineering"
        draft.engineeringQuality = true
        draft.pluginGroup = "standard"
        draft.switchAfterCreate = false

        XCTAssertEqual(draft.cliArguments, [
            "build",
            "--name", "lead",
            "--communication", "expert",
            "--autonomy", "high",
            "--workflow", "advanced",
            "--depth", "engineering",
            "--quality", "engineering",
            "--plugins", "standard",
            "--no-switch",
        ])
        XCTAssertEqual(draft.personaKey, "custom-lead")
    }

    func testCliArgumentsCoreQualitySwitchAndForce() {
        var draft = PersonaDraft()
        draft.name = "x"
        draft.engineeringQuality = false
        draft.switchAfterCreate = true
        draft.force = true

        let args = draft.cliArguments
        XCTAssertTrue(args.contains("--switch"))
        XCTAssertFalse(args.contains("--no-switch"))
        XCTAssertEqual(args.last, "--force")
        let qualityIndex = args.firstIndex(of: "--quality").map { args[$0 + 1] }
        XCTAssertEqual(qualityIndex, "core")
    }

    // MARK: - Service

    func testBuildReturnsCLIOutput() async throws {
        let executor = MockExecutor(data: Data("Created custom-lead (142 lines when assembled)\n".utf8))
        let service = PersonaBuilderService(executor: executor, forgePath: "/usr/bin/true")
        var draft = PersonaDraft()
        draft.name = "lead"

        let output = try await service.build(draft)
        XCTAssertTrue(output.contains("custom-lead"))
    }

    func testBuildSurfacesCLIError() async {
        let executor = MockExecutor(error: ForgeError.cliExitCode(1, stderr: "A built-in persona named 'cto-architect' already exists."))
        let service = PersonaBuilderService(executor: executor, forgePath: "/usr/bin/true")
        var draft = PersonaDraft()
        draft.name = "cto-architect"

        do {
            _ = try await service.build(draft)
            XCTFail("Expected error")
        } catch let error as ForgeError {
            guard case .cliExitCode(_, let stderr) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertTrue(stderr.contains("built-in persona"), "CLI message must surface verbatim")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
