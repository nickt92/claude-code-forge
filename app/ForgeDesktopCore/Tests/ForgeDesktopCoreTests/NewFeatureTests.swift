import XCTest
import Foundation
@testable import ForgeDesktopCore

// MARK: - PersonaService Tests

final class PersonaServiceTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testListPersonasDecodesAll() async throws {
        let data = try fixtureData("persona_list")
        let executor = MockExecutor(data: data)
        let service = PersonaService(executor: executor, forgePath: "/usr/bin/true")

        let personas = try await service.listPersonas()
        XCTAssertEqual(personas.count, 3)
    }

    func testListPersonasIncludesBuiltinAndCustom() async throws {
        let data = try fixtureData("persona_list")
        let executor = MockExecutor(data: data)
        let service = PersonaService(executor: executor, forgePath: "/usr/bin/true")

        let personas = try await service.listPersonas()
        let builtin = personas.filter { $0.source == "builtin" }
        let custom = personas.filter { $0.source == "custom" }
        XCTAssertEqual(builtin.count, 2)
        XCTAssertEqual(custom.count, 1)
    }

    func testListPersonasDecodesAxes() async throws {
        let data = try fixtureData("persona_list")
        let executor = MockExecutor(data: data)
        let service = PersonaService(executor: executor, forgePath: "/usr/bin/true")

        let personas = try await service.listPersonas()
        let senior = personas.first { $0.persona == "senior-engineer" }!
        XCTAssertEqual(senior.axes.communication, "expert")
        XCTAssertEqual(senior.axes.autonomy, "high")
        XCTAssertEqual(senior.label, "Senior Engineer")
        XCTAssertEqual(senior.defaultPluginGroup, "full")
    }

    func testSwitchPersonaDoesNotThrowOnSuccess() async throws {
        let executor = MockExecutor(data: Data())
        let service = PersonaService(executor: executor, forgePath: "/usr/bin/true")

        try await service.switchPersona(name: "senior-engineer")
    }

    func testSwitchPersonaThrowsOnCliError() async throws {
        let executor = MockExecutor(error: ForgeError.cliExitCode(1, stderr: "Unknown persona"))
        let service = PersonaService(executor: executor, forgePath: "/usr/bin/true")

        do {
            try await service.switchPersona(name: "nonexistent")
            XCTFail("Expected error")
        } catch let error as ForgeError {
            if case .cliExitCode(let code, _) = error {
                XCTAssertEqual(code, 1)
            } else {
                XCTFail("Wrong error type")
            }
        }
    }

    func testPersonaProfileIdentifiable() async throws {
        let data = try fixtureData("persona_list")
        let executor = MockExecutor(data: data)
        let service = PersonaService(executor: executor, forgePath: "/usr/bin/true")

        let personas = try await service.listPersonas()
        XCTAssertEqual(personas.first?.id, personas.first?.persona)
    }
}

// MARK: - DismissalService Tests

final class DismissalServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var service: DismissalService!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "DismissalServiceTests")!
        defaults.removePersistentDomain(forName: "DismissalServiceTests")
        service = DismissalService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "DismissalServiceTests")
        super.tearDown()
    }

    func testInitiallyNothingDismissed() {
        XCTAssertFalse(service.isDismissed(repoPath: "/test", findingId: "finding-1"))
        XCTAssertTrue(service.dismissedIds(for: "/test").isEmpty)
    }

    func testDismissAndQuery() {
        service.dismiss(repoPath: "/test", findingId: "finding-1")
        XCTAssertTrue(service.isDismissed(repoPath: "/test", findingId: "finding-1"))
        XCTAssertFalse(service.isDismissed(repoPath: "/test", findingId: "finding-2"))
    }

    func testUndismiss() {
        service.dismiss(repoPath: "/test", findingId: "finding-1")
        service.undismiss(repoPath: "/test", findingId: "finding-1")
        XCTAssertFalse(service.isDismissed(repoPath: "/test", findingId: "finding-1"))
    }

    func testDismissAllBulk() {
        service.dismissAll(repoPath: "/test", findingIds: ["a", "b", "c"])
        XCTAssertTrue(service.isDismissed(repoPath: "/test", findingId: "a"))
        XCTAssertTrue(service.isDismissed(repoPath: "/test", findingId: "b"))
        XCTAssertTrue(service.isDismissed(repoPath: "/test", findingId: "c"))
        XCTAssertEqual(service.dismissedIds(for: "/test").count, 3)
    }

    func testIsolationBetweenRepos() {
        service.dismiss(repoPath: "/repo-a", findingId: "finding-1")
        XCTAssertTrue(service.isDismissed(repoPath: "/repo-a", findingId: "finding-1"))
        XCTAssertFalse(service.isDismissed(repoPath: "/repo-b", findingId: "finding-1"))
    }

    func testPersistenceAcrossInstances() {
        service.dismiss(repoPath: "/test", findingId: "persist-me")
        let newService = DismissalService(defaults: defaults)
        XCTAssertTrue(newService.isDismissed(repoPath: "/test", findingId: "persist-me"))
    }

    func testDuplicateDismissIsIdempotent() {
        service.dismiss(repoPath: "/test", findingId: "dup")
        service.dismiss(repoPath: "/test", findingId: "dup")
        XCTAssertEqual(service.dismissedIds(for: "/test").count, 1)
    }
}

// MARK: - ForgeService.auditRepo Tests

final class ForgeServiceAuditTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testAuditRepoDecodesSuccessfully() async throws {
        let data = try fixtureData("audit")
        let executor = MockExecutor(data: data)
        let service = ForgeService(executor: executor, forgePath: "/usr/bin/true")

        let audit = try await service.auditRepo(path: "/Users/test/repo")
        XCTAssertEqual(audit.schemaVersion, 1)
        XCTAssertTrue(audit.hasClaudeMd)
        XCTAssertEqual(audit.lines, 200)
        XCTAssertEqual(audit.sections.coverage, 60)
        XCTAssertEqual(audit.findings.count, 2)
    }

    func testAuditRepoThrowsOnBadJSON() async throws {
        let badData = "not json".data(using: .utf8)!
        let executor = MockExecutor(data: badData)
        let service = ForgeService(executor: executor, forgePath: "/usr/bin/true")

        do {
            _ = try await service.auditRepo(path: "/test")
            XCTFail("Expected decoding error")
        } catch let error as ForgeError {
            guard case .jsonDecodingFailed = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
        }
    }
}

// MARK: - Sidebar Filter Tests

final class SidebarFilterTests: XCTestCase {

    private func makeRepo(
        name: String = "test",
        score: Int? = 90,
        claudeMdExists: Bool = true,
        errorFindings: Int = 0
    ) -> RepoData {
        let findings: [Finding] = (0..<errorFindings).map { i in
            Finding(severity: "error", code: "test_\(i)", detail: "Error \(i)", section: nil, fixable: false)
        }
        let audit = AuditData(
            schemaVersion: 1,
            hasClaudeMd: claudeMdExists,
            lines: 100,
            locations: [],
            sections: AuditSections(found: [], missing: [], coverage: 50),
            staleness: StalenessInfo(claudeMdDays: 0, repoDays: 0, stale: false),
            techStack: TechStackInfo(detected: [], mentioned: [], gaps: []),
            quality: QualityInfo(hasPlaceholders: false, lengthAssessment: "ok", lineCount: nil, imperativeRatio: nil),
            hookCompat: nil,
            findings: findings
        )
        return RepoData(
            path: "/test/\(name)",
            name: name,
            claudeMd: ClaudeMdBasic(exists: claudeMdExists, lines: claudeMdExists ? 100 : 0),
            rules: RulesInfo(count: 0, files: []),
            docChain: DocChainInfo(projectMd: false, requirementsMd: false, roadmapMd: false, dismissed: false),
            git: GitInfo(isRepo: true, branch: "main"),
            hooks: RepoHooksInfo(present: false, count: 0),
            claudeMdAudit: audit,
            score: score.map { ScoreData(total: $0, grade: $0 >= 90 ? "A" : "C", dimensions: [:]) }
        )
    }

    func testNeedsAttentionFilterMatchesLowScore() {
        let repo = makeRepo(score: 60)
        XCTAssertTrue(SidebarFilter.needsAttention.matches(repo))
    }

    func testNeedsAttentionFilterRejectsHighScore() {
        let repo = makeRepo(score: 95)
        XCTAssertFalse(SidebarFilter.needsAttention.matches(repo))
    }

    func testHasErrorsFilterMatchesRepoWithErrors() {
        let repo = makeRepo(errorFindings: 2)
        XCTAssertTrue(SidebarFilter.hasErrors.matches(repo))
    }

    func testHasErrorsFilterRejectsCleanRepo() {
        let repo = makeRepo(errorFindings: 0)
        XCTAssertFalse(SidebarFilter.hasErrors.matches(repo))
    }

    func testMissingClaudeMdFilterMatches() {
        let repo = makeRepo(claudeMdExists: false)
        XCTAssertTrue(SidebarFilter.missingClaudeMd.matches(repo))
    }

    func testMissingClaudeMdFilterRejectsPresent() {
        let repo = makeRepo(claudeMdExists: true)
        XCTAssertFalse(SidebarFilter.missingClaudeMd.matches(repo))
    }

    func testNeedsAttentionBoundaryAt80() {
        let at79 = makeRepo(score: 79)
        let at80 = makeRepo(score: 80)
        XCTAssertTrue(SidebarFilter.needsAttention.matches(at79))
        XCTAssertFalse(SidebarFilter.needsAttention.matches(at80))
    }
}

// MARK: - ForgeState.updateRepo Tests

@MainActor
final class ForgeStateUpdateTests: XCTestCase {

    private func makeDashboard(repos: [RepoData]) -> DashboardData {
        DashboardData(
            schemaVersion: 1,
            global: GlobalConfig(
                persona: PersonaInfo(persona: "test", label: "Test", description: "", axes: PersonaAxes(communication: "", autonomy: "", workflow: "", depth: ""), quality: []),
                hooks: [],
                plugins: PluginInfo(group: "test", count: 0, plugins: []),
                rules: RulesInfo(count: 0, files: []),
                install: InstallInfo(forgeVersion: "1.0.0", installTimestamp: "", manifestVersion: 1, sourceDir: ""),
                claudeMd: ClaudeMdInfo(exists: true, lines: 100, size: nil)
            ),
            globalScore: ScoreData(total: 90, grade: "A", dimensions: [:]),
            repos: repos,
            generatedAt: "2026-01-01T00:00:00Z"
        )
    }

    func testUpdateRepoReplacesAuditData() {
        let state = ForgeState()
        let originalAudit = AuditData(
            schemaVersion: 1, hasClaudeMd: true, lines: 50, locations: [],
            sections: AuditSections(found: [], missing: ["arch"], coverage: 30),
            staleness: StalenessInfo(claudeMdDays: 0, repoDays: 0, stale: false),
            techStack: TechStackInfo(detected: [], mentioned: [], gaps: []),
            quality: QualityInfo(hasPlaceholders: false, lengthAssessment: "ok", lineCount: nil, imperativeRatio: nil),
            hookCompat: nil,
            findings: []
        )
        let repo = RepoData(
            path: "/test/repo", name: "repo",
            claudeMd: ClaudeMdBasic(exists: true, lines: 50),
            rules: RulesInfo(count: 0, files: []),
            docChain: DocChainInfo(projectMd: false, requirementsMd: false, roadmapMd: false, dismissed: false),
            git: GitInfo(isRepo: true, branch: "main"),
            hooks: RepoHooksInfo(present: false, count: 0),
            claudeMdAudit: originalAudit,
            score: ScoreData(total: 70, grade: "C", dimensions: [:])
        )

        state.loadState = .loaded(makeDashboard(repos: [repo]))

        let updatedAudit = AuditData(
            schemaVersion: 1, hasClaudeMd: true, lines: 200, locations: [],
            sections: AuditSections(found: ["arch"], missing: [], coverage: 90),
            staleness: StalenessInfo(claudeMdDays: 0, repoDays: 0, stale: false),
            techStack: TechStackInfo(detected: [], mentioned: [], gaps: []),
            quality: QualityInfo(hasPlaceholders: false, lengthAssessment: "ok", lineCount: nil, imperativeRatio: nil),
            hookCompat: nil,
            findings: []
        )

        state.updateRepo(path: "/test/repo", audit: updatedAudit)

        guard let dashboard = state.dashboard else {
            XCTFail("Expected loaded state")
            return
        }

        XCTAssertEqual(dashboard.repos.first?.claudeMdAudit?.sections.coverage, 90)
        XCTAssertEqual(dashboard.repos.first?.claudeMdAudit?.lines, 200)
        XCTAssertEqual(dashboard.repos.first?.claudeMd.lines, 200)
    }

    func testUpdateRepoIgnoresWhenNotLoaded() {
        let state = ForgeState()
        let audit = AuditData(
            schemaVersion: 1, hasClaudeMd: true, lines: 100, locations: [],
            sections: AuditSections(found: [], missing: [], coverage: 50),
            staleness: StalenessInfo(claudeMdDays: 0, repoDays: 0, stale: false),
            techStack: TechStackInfo(detected: [], mentioned: [], gaps: []),
            quality: QualityInfo(hasPlaceholders: false, lengthAssessment: "ok", lineCount: nil, imperativeRatio: nil),
            hookCompat: nil,
            findings: []
        )
        // Should not crash when state is idle
        state.updateRepo(path: "/test", audit: audit)
        XCTAssertNil(state.dashboard)
    }

    func testUpdateRepoIgnoresUnknownPath() {
        let state = ForgeState()
        let repo = RepoData(
            path: "/test/repo", name: "repo",
            claudeMd: ClaudeMdBasic(exists: true, lines: 50),
            rules: RulesInfo(count: 0, files: []),
            docChain: DocChainInfo(projectMd: false, requirementsMd: false, roadmapMd: false, dismissed: false),
            git: GitInfo(isRepo: true, branch: "main"),
            hooks: RepoHooksInfo(present: false, count: 0),
            claudeMdAudit: nil,
            score: nil
        )
        state.loadState = .loaded(makeDashboard(repos: [repo]))

        let audit = AuditData(
            schemaVersion: 1, hasClaudeMd: true, lines: 100, locations: [],
            sections: AuditSections(found: [], missing: [], coverage: 50),
            staleness: StalenessInfo(claudeMdDays: 0, repoDays: 0, stale: false),
            techStack: TechStackInfo(detected: [], mentioned: [], gaps: []),
            quality: QualityInfo(hasPlaceholders: false, lengthAssessment: "ok", lineCount: nil, imperativeRatio: nil),
            hookCompat: nil,
            findings: []
        )

        state.updateRepo(path: "/unknown/path", audit: audit)
        // Should not crash; repo unchanged
        XCTAssertNil(state.dashboard?.repos.first?.claudeMdAudit)
    }
}

// MARK: - RepoData.withUpdatedAudit Tests

final class RepoDataUpdateTests: XCTestCase {

    func testWithUpdatedAuditPreservesFields() {
        let repo = RepoData(
            path: "/test/repo", name: "my-repo",
            claudeMd: ClaudeMdBasic(exists: true, lines: 50),
            rules: RulesInfo(count: 3, files: ["a.md"]),
            docChain: DocChainInfo(projectMd: true, requirementsMd: false, roadmapMd: false, dismissed: false),
            git: GitInfo(isRepo: true, branch: "develop"),
            hooks: RepoHooksInfo(present: true, count: 2),
            claudeMdAudit: nil,
            score: ScoreData(total: 85, grade: "B", dimensions: [:])
        )

        let audit = AuditData(
            schemaVersion: 1, hasClaudeMd: true, lines: 200, locations: [],
            sections: AuditSections(found: ["all"], missing: [], coverage: 100),
            staleness: StalenessInfo(claudeMdDays: 0, repoDays: 0, stale: false),
            techStack: TechStackInfo(detected: [], mentioned: [], gaps: []),
            quality: QualityInfo(hasPlaceholders: false, lengthAssessment: "ok", lineCount: nil, imperativeRatio: nil),
            hookCompat: nil,
            findings: []
        )

        let updated = repo.withUpdatedAudit(audit)

        // Preserved
        XCTAssertEqual(updated.path, "/test/repo")
        XCTAssertEqual(updated.name, "my-repo")
        XCTAssertEqual(updated.git.branch, "develop")
        XCTAssertEqual(updated.rules.count, 3)
        XCTAssertTrue(updated.docChain.projectMd)
        XCTAssertEqual(updated.score?.total, 85)

        // Updated
        XCTAssertEqual(updated.claudeMdAudit?.sections.coverage, 100)
        XCTAssertEqual(updated.claudeMd.lines, 200)
        XCTAssertTrue(updated.claudeMd.exists)
    }
}
