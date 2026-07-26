import Foundation

/// Draft state for the native persona builder. Swift-side validation is a
/// fast-path UX mirror of `forge build`'s rules — the CLI remains the
/// authority and its errors are surfaced verbatim if the two ever disagree.
public struct PersonaDraft: Sendable, Equatable {
    public var name: String = ""
    public var communication: String = "technical"
    public var autonomy: String = "moderate"
    public var workflow: String = "standard"
    public var depth: String = "practical"
    public var engineeringQuality: Bool = true
    public var pluginGroup: String = "full"
    public var switchAfterCreate: Bool = true
    public var force: Bool = false

    public init() {}

    public enum Axis: String, CaseIterable, Sendable {
        case communication, autonomy, workflow, depth

        public var label: String { rawValue.capitalized }

        public var options: [(value: String, description: String)] {
            switch self {
            case .communication:
                [("plain", "Simple language, no jargon, explains everything"),
                 ("technical", "Uses technical terms, assumes domain knowledge"),
                 ("expert", "Dense, precise, assumes deep expertise")]
            case .autonomy:
                [("guided", "Checks in frequently, explains before acting"),
                 ("moderate", "Proceeds on clear tasks, asks on ambiguity"),
                 ("high", "Acts independently, only asks on critical decisions")]
            case .workflow:
                [("simplified", "Minimal process, just get things done"),
                 ("standard", "Balanced process with reasonable checks"),
                 ("advanced", "Full engineering workflow with gates and reviews")]
            case .depth:
                [("conceptual", "High-level explanations, focus on what not how"),
                 ("practical", "Implementation-focused, code examples"),
                 ("engineering", "Deep technical detail, architecture rationale")]
            }
        }
    }

    public static let pluginGroups: [(value: String, description: String)] = [
        ("full", "All plugins (engineering-focused)"),
        ("standard", "Drops HR/legal and startup plugins"),
        ("minimal", "Core plugins only (lightweight)"),
    ]

    // MARK: - Name validation (mirrors lib/cmd-build.sh)

    public enum NameValidation: Equatable, Sendable {
        case valid
        case empty
        /// Must start with a letter; letters, numbers, and hyphens only.
        case invalidFormat
        /// Collides with a built-in persona — never allowed.
        case builtinCollision
        /// `custom-<name>` already exists — allowed only with `force`.
        case customExists
    }

    public func validateName(builtinIds: [String], customIds: [String]) -> NameValidation {
        if name.isEmpty { return .empty }
        if name.range(of: "^[a-zA-Z][a-zA-Z0-9-]*$", options: .regularExpression) == nil {
            return .invalidFormat
        }
        if builtinIds.contains(name) { return .builtinCollision }
        if customIds.contains("custom-\(name)"), !force { return .customExists }
        return .valid
    }

    /// The persona id `forge build` will create.
    public var personaKey: String { "custom-\(name)" }

    /// Arguments for the non-interactive `forge build` invocation.
    public var cliArguments: [String] {
        var args = [
            "build",
            "--name", name,
            "--communication", communication,
            "--autonomy", autonomy,
            "--workflow", workflow,
            "--depth", depth,
            "--quality", engineeringQuality ? "engineering" : "core",
            "--plugins", pluginGroup,
            switchAfterCreate ? "--switch" : "--no-switch",
        ]
        if force { args.append("--force") }
        return args
    }
}
