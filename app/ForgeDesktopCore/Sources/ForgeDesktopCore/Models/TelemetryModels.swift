import Foundation

public struct HookTelemetryData: Codable, Sendable {
    public let totalInvocations: Int
    public let byHook: [String: Int]
    public let blockRate: Int
    public let avgDurationMs: Int
}

public struct SessionScorecard: Codable, Sendable {
    public let totalEvents: Int
    public let byHook: [String: Int]
    public let blocks: Int
    public let allows: Int
    public let detects: Int
    public let overrides: Int
}
