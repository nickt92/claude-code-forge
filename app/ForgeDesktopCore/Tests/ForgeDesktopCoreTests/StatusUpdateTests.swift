import XCTest
import Foundation
@testable import ForgeDesktopCore

final class StatusUpdateTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    // MARK: - StatusService

    func testStatusDecodesCLIContract() async throws {
        let executor = MockExecutor(data: try fixtureData("status"))
        let service = StatusService(executor: executor, forgePath: "/usr/bin/true")

        let status = try await service.status()

        XCTAssertEqual(status.schemaVersion, 1)
        XCTAssertEqual(status.persona.id, "cto-architect")
        XCTAssertEqual(status.plugins.group, "full")
        XCTAssertEqual(status.plugins.count, 20)
        XCTAssertEqual(status.version.installed, "1.3.0")
        XCTAssertEqual(status.version.source, "1.3.1")
        XCTAssertEqual(status.hooks.count, 9)
        XCTAssertEqual(status.sourceDir, "/Users/nickt/claude-code-forge")
        XCTAssertNotNil(status.installedAtDate)
    }

    func testReinstallPendingSemantics() async throws {
        let executor = MockExecutor(data: try fixtureData("status"))
        let service = StatusService(executor: executor, forgePath: "/usr/bin/true")

        let status = try await service.status()
        XCTAssertTrue(status.reinstallPending, "installed 1.3.0 != source 1.3.1 means reinstall pending")
    }

    func testReinstallNotPendingWhenVersionsMatch() async throws {
        let json = """
        {"schema_version":1,"persona":{"id":"x","label":"X"},"plugins":{"group":"full","count":1},
         "version":{"installed":"1.4.0","source":"1.4.0"},"hooks":{"count":1},
         "installed_at":null,"source_dir":null}
        """
        let executor = MockExecutor(data: Data(json.utf8))
        let service = StatusService(executor: executor, forgePath: "/usr/bin/true")

        let status = try await service.status()
        XCTAssertFalse(status.reinstallPending)
        XCTAssertNil(status.installedAtDate)
    }

    func testStatusSurfacesDecodeFailure() async {
        let executor = MockExecutor(data: Data("nope".utf8))
        let service = StatusService(executor: executor, forgePath: "/usr/bin/true")

        do {
            _ = try await service.status()
            XCTFail("Expected decode error")
        } catch let error as ForgeError {
            guard case .jsonDecodingFailed = error else {
                return XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - UpdateService

    func testUpdateReturnsCLIOutput() async throws {
        let output = "Fetching origin...\nAlready up to date.\nReinstalled forge 1.4.0\n"
        let executor = MockExecutor(data: Data(output.utf8))
        let service = UpdateService(executor: executor, forgePath: "/usr/bin/true")

        let log = try await service.update()
        XCTAssertTrue(log.contains("Reinstalled forge"))
    }

    func testUpdateMapsDirtyTreeFailure() async {
        let executor = MockExecutor(error: ForgeError.cliExitCode(1, stderr: "Source repo has uncommitted changes — commit or stash first"))
        let service = UpdateService(executor: executor, forgePath: "/usr/bin/true")

        do {
            _ = try await service.update()
            XCTFail("Expected error")
        } catch {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("uncommitted changes"), "got: \(message)")
            XCTAssertTrue(message.lowercased().contains("stash"), "actionable advice expected, got: \(message)")
        }
    }

    func testFriendlyMessageMappings() {
        XCTAssertTrue(UpdateService.friendlyMessage(for: "fatal: Failed to fetch from origin").contains("network"))
        XCTAssertTrue(UpdateService.friendlyMessage(for: "Fast-forward merge failed — resolve manually").contains("diverged"))
        XCTAssertTrue(UpdateService.friendlyMessage(for: "Source directory is not a git repository: /x").contains("git repository"))
        XCTAssertTrue(UpdateService.friendlyMessage(for: "something odd").contains("Update failed"))
    }
}
