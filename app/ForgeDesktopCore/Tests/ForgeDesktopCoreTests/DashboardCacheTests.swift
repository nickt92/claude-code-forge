import XCTest
import Foundation
@testable import ForgeDesktopCore

final class DashboardCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-cache-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testSaveAndLoadRoundtrip() throws {
        let cache = DashboardCache(directory: tempDir)
        let payload = try fixtureData("dashboard")

        cache.save(payload)

        XCTAssertEqual(cache.load(), payload)
    }

    func testLoadReturnsNilWhenEmpty() {
        let cache = DashboardCache(directory: tempDir)
        XCTAssertNil(cache.load())
    }

    func testClearRemovesCachedData() throws {
        let cache = DashboardCache(directory: tempDir)
        cache.save(try fixtureData("dashboard"))

        cache.clear()

        XCTAssertNil(cache.load())
    }

    func testLoadDashboardPopulatesCache() async throws {
        let cache = DashboardCache(directory: tempDir)
        let payload = try fixtureData("dashboard")
        let executor = MockExecutor(data: payload)
        let service = ForgeService(executor: executor, forgePath: "/usr/bin/true", cache: cache)

        _ = try await service.loadDashboard()

        let cached = service.cachedDashboard()
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.schemaVersion, 1)
        XCTAssertFalse(cached!.repos.isEmpty)
    }

    func testFailedLoadDoesNotTouchCache() async throws {
        let cache = DashboardCache(directory: tempDir)
        cache.save(try fixtureData("dashboard"))
        let executor = MockExecutor(error: ForgeError.cliExitCode(1, stderr: "boom"))
        let service = ForgeService(executor: executor, forgePath: "/usr/bin/true", cache: cache)

        _ = try? await service.loadDashboard()

        XCTAssertNotNil(service.cachedDashboard(), "A failed load must not clobber a good cache")
    }

    func testCachedDashboardReturnsNilForCorruptData() {
        let cache = DashboardCache(directory: tempDir)
        cache.save(Data("not json".utf8))
        let service = ForgeService(executor: MockExecutor(data: Data()), forgePath: "/usr/bin/true", cache: cache)

        XCTAssertNil(service.cachedDashboard())
    }

    func testCachedDashboardReturnsNilWithoutCache() {
        let service = ForgeService(executor: MockExecutor(data: Data()), forgePath: "/usr/bin/true")
        XCTAssertNil(service.cachedDashboard())
    }
}
