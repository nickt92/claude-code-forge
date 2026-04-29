import Foundation

public struct PersonaProfile: Codable, Sendable, Identifiable {
    public let persona: String
    public let label: String
    public let description: String
    public let axes: PersonaAxes
    public let quality: [String]
    public let defaultPluginGroup: String
    public let source: String

    public var id: String { persona }

    public init(
        persona: String,
        label: String,
        description: String,
        axes: PersonaAxes,
        quality: [String],
        defaultPluginGroup: String,
        source: String
    ) {
        self.persona = persona
        self.label = label
        self.description = description
        self.axes = axes
        self.quality = quality
        self.defaultPluginGroup = defaultPluginGroup
        self.source = source
    }
}
