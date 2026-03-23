import Foundation

// MARK: - Top-Level

public struct DashboardData: Codable, Sendable {
    public let schemaVersion: Int
    public let global: GlobalConfig
    public let globalScore: ScoreData
    public let repos: [RepoData]
    public let generatedAt: String
}

// MARK: - Global Config

public struct GlobalConfig: Codable, Sendable {
    public let persona: PersonaInfo
    public let hooks: [HookInfo]
    public let plugins: PluginInfo
    public let rules: RulesInfo
    public let install: InstallInfo
    public let claudeMd: ClaudeMdInfo
}

public struct PersonaInfo: Codable, Sendable {
    public let persona: String
    public let label: String
    public let description: String
    public let axes: PersonaAxes
    public let quality: [String]
}

public struct PersonaAxes: Codable, Sendable {
    public let communication: String
    public let autonomy: String
    public let workflow: String
    public let depth: String
}

public struct HookInfo: Codable, Sendable {
    public let event: String
    public let matcher: String
    public let command: String
    public let timeout: Int?
    public let name: String
}

public struct PluginInfo: Codable, Sendable {
    public let group: String
    public let count: Int
    public let plugins: [String]
}

public struct RulesInfo: Codable, Sendable {
    public let count: Int
    public let files: [String]
}

public struct InstallInfo: Codable, Sendable {
    public let forgeVersion: String
    public let installTimestamp: String
    public let manifestVersion: Int
    public let sourceDir: String
}

public struct ClaudeMdInfo: Codable, Sendable {
    public let exists: Bool
    public let lines: Int
    public let size: Int?
}

// MARK: - Score

public struct ScoreData: Codable, Sendable {
    public let total: Int
    public let grade: String
    public let dimensions: [String: DimensionScore]
}

public struct DimensionScore: Codable, Sendable {
    public let score: Int
    public let weight: Int
}

// MARK: - Repo

public struct RepoData: Codable, Sendable, Identifiable {
    public let path: String
    public let name: String
    public let claudeMd: ClaudeMdBasic
    public let rules: RulesInfo
    public let docChain: DocChainInfo
    public let git: GitInfo
    public let hooks: RepoHooksInfo
    public let claudeMdAudit: AuditData?
    public let score: ScoreData?

    public var id: String { path }
}

public struct ClaudeMdBasic: Codable, Sendable {
    public let exists: Bool
    public let lines: Int
}

public struct DocChainInfo: Codable, Sendable {
    public let projectMd: Bool
    public let requirementsMd: Bool
    public let roadmapMd: Bool
    public let dismissed: Bool
}

public struct GitInfo: Codable, Sendable {
    public let isRepo: Bool
    public let branch: String
}

public struct RepoHooksInfo: Codable, Sendable {
    public let present: Bool
    public let count: Int
}

// MARK: - Audit

public struct AuditData: Codable, Sendable {
    public let schemaVersion: Int
    public let hasClaudeMd: Bool
    public let lines: Int
    public let locations: [String]
    public let sections: AuditSections
    public let staleness: StalenessInfo
    public let techStack: TechStackInfo
    public let quality: QualityInfo
    public let findings: [Finding]
}

public struct AuditSections: Codable, Sendable {
    public let found: [String]
    public let missing: [String]
    public let coverage: Int
}

public struct StalenessInfo: Codable, Sendable {
    public let claudeMdDays: Int
    public let repoDays: Int
    public let stale: Bool
}

public struct TechStackInfo: Codable, Sendable {
    public let detected: [String]
    public let mentioned: [String]
    public let gaps: [String]
}

public struct QualityInfo: Codable, Sendable {
    public let hasPlaceholders: Bool
    public let lengthAssessment: String
}

public struct Finding: Codable, Sendable, Identifiable {
    public let severity: String
    public let code: String
    public let detail: String
    public let section: String?
    public let fixable: Bool

    public var id: String { "\(code)-\(detail)" }
}

// MARK: - Severity Helpers

extension Finding {
    public enum Severity: String {
        case error, warn, info
    }

    public var severityLevel: Severity {
        Severity(rawValue: severity) ?? .info
    }
}
