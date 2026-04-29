import Foundation

// MARK: - Onboarding Mode

public enum OnboardingMode: Sendable {
    case brownfield(repoPath: String)
    case greenfield(projectPath: String, projectName: String, description: String)
}

// MARK: - Onboarding Phase

public enum OnboardingPhase: Sendable, Equatable {
    case setup                              // Greenfield only: user inputs description
    case analyzing                          // Brownfield only: running forge analyze
    case generating                         // Claude is streaming CLAUDE.md
    case review(content: String)            // User reviews generated content
    case saving                             // Writing file to disk
    case complete                           // Done
    case failed(String)                     // Error state
}

// MARK: - Codebase Context (from forge analyze --json)

public struct CodebaseContext: Codable, Sendable {
    public let path: String
    public let name: String
    public let directoryStructure: String
    public let dependencies: [ContextFile]
    public let configs: [ContextFile]
    public let documentation: [ContextFile]
    public let git: GitContext
    public let testFiles: [String]
    public let scripts: [String]
    public let existingClaudeMd: String?
    public let ciConfigs: [ContextFile]

    public init(
        path: String, name: String, directoryStructure: String,
        dependencies: [ContextFile], configs: [ContextFile],
        documentation: [ContextFile], git: GitContext,
        testFiles: [String], scripts: [String],
        existingClaudeMd: String?, ciConfigs: [ContextFile]
    ) {
        self.path = path
        self.name = name
        self.directoryStructure = directoryStructure
        self.dependencies = dependencies
        self.configs = configs
        self.documentation = documentation
        self.git = git
        self.testFiles = testFiles
        self.scripts = scripts
        self.existingClaudeMd = existingClaudeMd
        self.ciConfigs = ciConfigs
    }
}

public struct ContextFile: Codable, Sendable {
    public let file: String
    public let content: String

    public init(file: String, content: String) {
        self.file = file
        self.content = content
    }
}

public struct GitContext: Codable, Sendable {
    public let isRepo: Bool
    public let branch: String?
    public let defaultBranch: String?
    public let recentCommits: [String]
    public let contributors: [String]

    public init(isRepo: Bool, branch: String?, defaultBranch: String?, recentCommits: [String], contributors: [String]) {
        self.isRepo = isRepo
        self.branch = branch
        self.defaultBranch = defaultBranch
        self.recentCommits = recentCommits
        self.contributors = contributors
    }
}

// MARK: - Tool Activity (for streaming UI)

public struct ToolActivity: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let input: String
    public var isComplete: Bool

    public init(name: String, input: String, isComplete: Bool = false) {
        self.name = name
        self.input = input
        self.isComplete = isComplete
    }

    public var displayLabel: String {
        switch name {
        case "Read":
            if let path = extractPath(from: input) {
                return "Read \(shortenPath(path))"
            }
            return "Read file"
        case "Glob":
            if let pattern = extractPattern(from: input) {
                return "Glob \(pattern)"
            }
            return "Search files"
        case "Grep":
            if let pattern = extractSearchPattern(from: input) {
                return "Search \"\(pattern)\""
            }
            return "Search content"
        case "Edit":
            if let path = extractPath(from: input) {
                return "Edit \(shortenPath(path))"
            }
            return "Edit file"
        default:
            return name
        }
    }

    private func extractPath(from input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = obj["file_path"] as? String ?? obj["path"] as? String else {
            return nil
        }
        return path
    }

    private func extractPattern(from input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pattern = obj["pattern"] as? String else {
            return nil
        }
        return pattern
    }

    private func extractSearchPattern(from input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pattern = obj["pattern"] as? String else {
            return nil
        }
        return String(pattern.prefix(30))
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count <= 2 {
            return path
        }
        return components.suffix(2).joined(separator: "/")
    }
}
