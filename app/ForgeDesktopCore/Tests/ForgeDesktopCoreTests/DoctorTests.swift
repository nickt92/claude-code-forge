import XCTest
import Foundation
@testable import ForgeDesktopCore

final class DoctorModelTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func testDecodesDoctorResult() throws {
        let data = try loadFixture("doctor")
        let result = try decoder.decode(DoctorResult.self, from: data)

        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.checks.count, 10)
        XCTAssertEqual(result.summary.pass, 8)
        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.summary.failures, 1)
    }

    func testDecodesCheckStatuses() throws {
        let data = try loadFixture("doctor")
        let result = try decoder.decode(DoctorResult.self, from: data)

        let passChecks = result.checks.filter { $0.status == "pass" }
        let warnChecks = result.checks.filter { $0.status == "warn" }
        let failChecks = result.checks.filter { $0.status == "fail" }

        XCTAssertEqual(passChecks.count, 8)
        XCTAssertEqual(warnChecks.count, 1)
        XCTAssertEqual(failChecks.count, 1)
    }

    func testDecodesCheckCategories() throws {
        let data = try loadFixture("doctor")
        let result = try decoder.decode(DoctorResult.self, from: data)

        let categories = Set(result.checks.map(\.category))
        XCTAssertTrue(categories.contains("cli"))
        XCTAssertTrue(categories.contains("manifest"))
        XCTAssertTrue(categories.contains("files"))
        XCTAssertTrue(categories.contains("hooks"))
        XCTAssertTrue(categories.contains("plugins"))
        XCTAssertTrue(categories.contains("project"))
    }

    func testDecodesNullDetail() throws {
        let data = try loadFixture("doctor")
        let result = try decoder.decode(DoctorResult.self, from: data)

        let manifestExists = result.checks.first { $0.name == "manifest exists" }
        XCTAssertNotNil(manifestExists)
        XCTAssertNil(manifestExists?.detail)
    }

    func testDecodesHealthyDoctor() throws {
        let data = try loadFixture("doctor_healthy")
        let result = try decoder.decode(DoctorResult.self, from: data)

        XCTAssertEqual(result.summary.pass, 10)
        XCTAssertEqual(result.summary.warnings, 0)
        XCTAssertEqual(result.summary.failures, 0)
    }

    func testCheckIdentifiable() throws {
        let check = DoctorCheck(category: "cli", name: "forge binary", status: "pass", detail: nil)
        XCTAssertEqual(check.id, "cli-forge binary")
    }
}

final class DoctorServiceTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testRunsDoctorFromMockExecutor() async throws {
        let data = try fixtureData("doctor")
        let executor = MockExecutor(data: data)
        let service = DoctorService(executor: executor, forgePath: "/usr/bin/true")

        let result = try await service.runDoctor()
        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.checks.count, 10)
    }

    func testSurfacesDoctorCliErrors() async throws {
        let executor = MockExecutor(error: ForgeError.cliExitCode(1, stderr: "doctor failed"))
        let service = DoctorService(executor: executor, forgePath: "/usr/bin/true")

        do {
            _ = try await service.runDoctor()
            XCTFail("Expected error")
        } catch let error as ForgeError {
            if case .cliExitCode(let code, _) = error {
                XCTAssertEqual(code, 1)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testSurfacesDoctorDecodingErrors() async throws {
        let badJSON = "not json".data(using: .utf8)!
        let executor = MockExecutor(data: badJSON)
        let service = DoctorService(executor: executor, forgePath: "/usr/bin/true")

        do {
            _ = try await service.runDoctor()
            XCTFail("Expected error")
        } catch let error as ForgeError {
            guard case .jsonDecodingFailed = error else {
                XCTFail("Wrong error type: \(error)")
                return
            }
        }
    }
}
