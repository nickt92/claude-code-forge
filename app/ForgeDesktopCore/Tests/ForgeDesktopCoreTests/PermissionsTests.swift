import XCTest
import Foundation
@testable import ForgeDesktopCore

final class PermissionsTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testListPresetsDecodesCLIContract() async throws {
        let data = try fixtureData("permissions_list")
        let executor = MockExecutor(data: data)
        let service = PermissionsService(executor: executor, forgePath: "/usr/bin/true")

        let presets = try await service.listPresets()

        XCTAssertEqual(presets.count, 3)
        XCTAssertEqual(presets.map(\.id), ["ask-before-changes", "auto-edit", "full-autonomy"])

        let first = try XCTUnwrap(presets.first)
        XCTAssertEqual(first.label, "Ask Before Changes")
        XCTAssertEqual(first.tier, 1)
        XCTAssertFalse(first.description.isEmpty)
        XCTAssertFalse(first.detail.isEmpty)
        XCTAssertFalse(first.permissions.isEmpty)
        XCTAssertNil(first.inherits)

        let last = try XCTUnwrap(presets.last)
        XCTAssertEqual(last.inherits, "auto-edit", "Tier chain must survive decoding")
    }

    func testListPresetsSurfacesDecodeFailure() async {
        let executor = MockExecutor(data: Data("nonsense".utf8))
        let service = PermissionsService(executor: executor, forgePath: "/usr/bin/true")

        do {
            _ = try await service.listPresets()
            XCTFail("Expected decode error")
        } catch let error as ForgeError {
            guard case .jsonDecodingFailed = error else {
                return XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
