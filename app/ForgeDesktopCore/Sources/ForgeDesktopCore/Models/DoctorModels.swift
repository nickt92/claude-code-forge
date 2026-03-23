import Foundation

public struct DoctorResult: Codable, Sendable {
    public let schemaVersion: Int
    public let checks: [DoctorCheck]
    public let summary: DoctorSummary

    public init(schemaVersion: Int, checks: [DoctorCheck], summary: DoctorSummary) {
        self.schemaVersion = schemaVersion
        self.checks = checks
        self.summary = summary
    }
}

public struct DoctorCheck: Codable, Sendable, Identifiable {
    public let category: String
    public let name: String
    public let status: String
    public let detail: String?

    public var id: String { "\(category)-\(name)" }

    public init(category: String, name: String, status: String, detail: String?) {
        self.category = category
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct DoctorSummary: Codable, Sendable {
    public let pass: Int
    public let warnings: Int
    public let failures: Int

    public init(pass: Int, warnings: Int, failures: Int) {
        self.pass = pass
        self.warnings = warnings
        self.failures = failures
    }
}
