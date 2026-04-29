import XCTest
import Foundation
@testable import ForgeDesktopCore

final class ServiceTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testLoadsDashboardFromMockExecutor() async throws {
        let data = try fixtureData("dashboard")
        let executor = MockExecutor(data: data)
        let service = ForgeService(executor: executor, forgePath: "/usr/bin/true")

        let dashboard = try await service.loadDashboard()
        XCTAssertEqual(dashboard.schemaVersion, 1)
        XCTAssertFalse(dashboard.repos.isEmpty)
        XCTAssertEqual(dashboard.globalScore.grade, "A")
    }

    func testSurfacesCliErrors() async throws {
        let executor = MockExecutor(error: ForgeError.cliExitCode(1, stderr: "scan path not set"))
        let service = ForgeService(executor: executor, forgePath: "/usr/bin/true")

        do {
            _ = try await service.loadDashboard()
            XCTFail("Expected error")
        } catch let error as ForgeError {
            if case .cliExitCode(let code, let stderr) = error {
                XCTAssertEqual(code, 1)
                XCTAssertTrue(stderr.contains("scan path"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testSurfacesDecodingErrors() async throws {
        let badJSON = "{ invalid json".data(using: .utf8)!
        let executor = MockExecutor(data: badJSON)
        let service = ForgeService(executor: executor, forgePath: "/usr/bin/true")

        do {
            _ = try await service.loadDashboard()
            XCTFail("Expected error")
        } catch let error as ForgeError {
            guard case .jsonDecodingFailed = error else {
                XCTFail("Wrong error type: \(error)")
                return
            }
        }
    }

    func testLoadsEmptyDashboard() async throws {
        let data = try fixtureData("dashboard_empty")
        let executor = MockExecutor(data: data)
        let service = ForgeService(executor: executor, forgePath: "/usr/bin/true")

        let dashboard = try await service.loadDashboard()
        XCTAssertTrue(dashboard.repos.isEmpty)
        XCTAssertEqual(dashboard.globalScore.total, 0)
    }

    func testCliNotFoundForMissingPath() async throws {
        let executor = MockExecutor(data: Data())
        let service = ForgeService(executor: executor, forgePath: "/nonexistent/path/forge")

        do {
            _ = try await service.loadDashboard()
            XCTFail("Expected error")
        } catch let error as ForgeError {
            guard case .cliNotFound = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
        }
    }
}

final class ForgeErrorTests: XCTestCase {

    func testErrorDescriptionsAreHumanReadable() {
        let errors: [ForgeError] = [
            .cliNotFound,
            .cliExitCode(1, stderr: "something broke"),
            .unexpected("test"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testCliExitCodeIncludesStderr() {
        let error = ForgeError.cliExitCode(2, stderr: "scan path not configured")
        XCTAssertTrue(error.errorDescription!.contains("scan path"))
        XCTAssertTrue(error.errorDescription!.contains("2"))
    }
}

@MainActor
final class ForgeStateTests: XCTestCase {

    func testInitialStateIsIdle() {
        let state = ForgeState()
        XCTAssertNil(state.dashboard)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isLoading)
    }

    func testLoadedStateExposesDashboard() {
        let state = ForgeState()
        let dashboard = DashboardData(
            schemaVersion: 1,
            global: GlobalConfig(
                persona: PersonaInfo(persona: "test", label: "Test", description: "", axes: PersonaAxes(communication: "", autonomy: "", workflow: "", depth: ""), quality: []),
                hooks: [],
                plugins: PluginInfo(group: "test", count: 0, plugins: []),
                rules: RulesInfo(count: 0, files: []),
                install: InstallInfo(forgeVersion: "0.0.0", installTimestamp: "", manifestVersion: 0, sourceDir: ""),
                claudeMd: ClaudeMdInfo(exists: false, lines: 0, size: nil)
            ),
            globalScore: ScoreData(total: 50, grade: "D", dimensions: [:]),
            repos: [],
            generatedAt: "2026-01-01T00:00:00Z"
        )

        state.loadState = .loaded(dashboard)
        XCTAssertNotNil(state.dashboard)
        XCTAssertEqual(state.dashboard?.globalScore.total, 50)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isLoading)
    }

    func testFailedStateExposesError() {
        let state = ForgeState()
        state.loadState = .failed(.cliNotFound)
        XCTAssertNil(state.dashboard)
        XCTAssertNotNil(state.error)
        XCTAssertFalse(state.isLoading)
    }

    func testLoadingStateFlagsCorrectly() {
        let state = ForgeState()
        state.loadState = .loading
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.dashboard)
        XCTAssertNil(state.error)
    }
}
