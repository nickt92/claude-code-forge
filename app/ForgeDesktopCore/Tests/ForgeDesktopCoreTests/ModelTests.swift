import XCTest
import Foundation
@testable import ForgeDesktopCore

final class ModelTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func testDecodesFullDashboard() throws {
        let data = try loadFixture("dashboard")
        let dashboard = try decoder.decode(DashboardData.self, from: data)

        XCTAssertEqual(dashboard.schemaVersion, 1)
        XCTAssertFalse(dashboard.repos.isEmpty)
        XCTAssertFalse(dashboard.generatedAt.isEmpty)
    }

    func testDecodesGlobalConfig() throws {
        let data = try loadFixture("dashboard")
        let dashboard = try decoder.decode(DashboardData.self, from: data)

        XCTAssertEqual(dashboard.global.persona.persona, "cto-architect")
        XCTAssertEqual(dashboard.global.persona.label, "CTO / Technical Architect")
        XCTAssertEqual(dashboard.global.persona.axes.communication, "expert")
        XCTAssertFalse(dashboard.global.hooks.isEmpty)
        XCTAssertEqual(dashboard.global.plugins.group, "full")
        XCTAssertGreaterThan(dashboard.global.plugins.count, 0)
        XCTAssertEqual(dashboard.global.rules.count, 8)
        XCTAssertEqual(dashboard.global.install.forgeVersion, "1.2.1")
        XCTAssertTrue(dashboard.global.claudeMd.exists)
    }

    func testDecodesGlobalScore() throws {
        let data = try loadFixture("dashboard")
        let dashboard = try decoder.decode(DashboardData.self, from: data)

        XCTAssertEqual(dashboard.globalScore.total, 100)
        XCTAssertEqual(dashboard.globalScore.grade, "A")
        XCTAssertFalse(dashboard.globalScore.dimensions.isEmpty)

        let configDim = try XCTUnwrap(dashboard.globalScore.dimensions["config_completeness"])
        XCTAssertEqual(configDim.score, 100)
        XCTAssertEqual(configDim.weight, 25)
    }

    func testDecodesRepoData() throws {
        let data = try loadFixture("dashboard")
        let dashboard = try decoder.decode(DashboardData.self, from: data)

        let repo = try XCTUnwrap(dashboard.repos.first)
        XCTAssertFalse(repo.name.isEmpty)
        XCTAssertFalse(repo.path.isEmpty)
        XCTAssertEqual(repo.id, repo.path)
    }

    func testDecodesRepoAudit() throws {
        let data = try loadFixture("dashboard")
        let dashboard = try decoder.decode(DashboardData.self, from: data)

        let repoWithAudit = try XCTUnwrap(dashboard.repos.first { $0.claudeMdAudit != nil })
        let audit = try XCTUnwrap(repoWithAudit.claudeMdAudit)

        XCTAssertEqual(audit.schemaVersion, 1)
        XCTAssertTrue(audit.hasClaudeMd)
        XCTAssertFalse(audit.locations.isEmpty)
        XCTAssertGreaterThanOrEqual(audit.sections.coverage, 0)
        XCTAssertFalse(audit.findings.isEmpty)

        let finding = try XCTUnwrap(audit.findings.first)
        XCTAssertTrue(["error", "warn", "info"].contains(finding.severity))
        XCTAssertFalse(finding.code.isEmpty)
        XCTAssertFalse(finding.detail.isEmpty)
    }

    func testDecodesDocChain() throws {
        let data = try loadFixture("dashboard")
        let dashboard = try decoder.decode(DashboardData.self, from: data)

        let repo = try XCTUnwrap(dashboard.repos.first)
        XCTAssertTrue(repo.docChain.projectMd)
        XCTAssertTrue(repo.docChain.requirementsMd)
        XCTAssertTrue(repo.docChain.roadmapMd)
    }

    func testDecodesEmptyDashboard() throws {
        let data = try loadFixture("dashboard_empty")
        let dashboard = try decoder.decode(DashboardData.self, from: data)

        XCTAssertEqual(dashboard.schemaVersion, 1)
        XCTAssertTrue(dashboard.repos.isEmpty)
        XCTAssertEqual(dashboard.globalScore.total, 0)
        XCTAssertEqual(dashboard.globalScore.grade, "F")
        XCTAssertEqual(dashboard.global.plugins.count, 0)
    }

    func testFindingSeverityHelper() {
        XCTAssertEqual(Finding(severity: "error", code: "t", detail: "t", section: nil, fixable: true).severityLevel, .error)
        XCTAssertEqual(Finding(severity: "warn", code: "t", detail: "t", section: nil, fixable: false).severityLevel, .warn)
        XCTAssertEqual(Finding(severity: "info", code: "t", detail: "t", section: nil, fixable: true).severityLevel, .info)
        XCTAssertEqual(Finding(severity: "x", code: "t", detail: "t", section: nil, fixable: false).severityLevel, .info)
    }

    func testRepoScoreCanBeNil() throws {
        let json = """
        {
            "path": "/test",
            "name": "test",
            "claude_md": {"exists": false, "lines": 0},
            "rules": {"count": 0, "files": []},
            "doc_chain": {"project_md": false, "requirements_md": false, "roadmap_md": false, "dismissed": false},
            "git": {"is_repo": false, "branch": ""},
            "hooks": {"present": false, "count": 0},
            "claude_md_audit": null,
            "score": null
        }
        """.data(using: .utf8)!

        let repo = try decoder.decode(RepoData.self, from: json)
        XCTAssertNil(repo.score)
        XCTAssertNil(repo.claudeMdAudit)
    }
}
