import Foundation

/// Decoded `forge status --json` (schema_version 1).
public struct ForgeStatus: Codable, Sendable {
    public let schemaVersion: Int
    public let persona: PersonaInfo
    public let plugins: PluginsInfo
    public let version: VersionInfo
    public let hooks: HooksInfo
    public let installedAt: String?
    public let sourceDir: String?

    public struct PersonaInfo: Codable, Sendable {
        public let id: String
        public let label: String
    }

    public struct PluginsInfo: Codable, Sendable {
        public let group: String
        public let count: Int
    }

    public struct VersionInfo: Codable, Sendable {
        public let installed: String
        public let source: String
    }

    public struct HooksInfo: Codable, Sendable {
        public let count: Int
    }

    /// True when the already-pulled source repo is newer than the installed copy.
    /// This means "reinstall pending", NOT "a new release exists on origin" —
    /// `forge update` fetches and reinstalls, but the comparison here is local.
    public var reinstallPending: Bool {
        version.installed != version.source
    }

    /// `installed_at` parsed for display; nil if the CLI emitted no/invalid date.
    public var installedAtDate: Date? {
        guard let installedAt else { return nil }
        return ISO8601DateFormatter().date(from: installedAt)
    }
}
