import Foundation

public struct PermissionPreset: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let tier: Int
    public let description: String
    public let detail: String
    public let permissions: [String]
    public let inherits: String?
}

public struct PermissionsState: Codable, Sendable {
    public let currentPreset: String?
    public let effectivePermissions: [String]
}
