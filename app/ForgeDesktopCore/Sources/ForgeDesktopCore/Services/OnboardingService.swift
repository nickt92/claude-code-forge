import Foundation
import os

public final class OnboardingService: Sendable {
    private static let logger = Logger(subsystem: "com.forge.desktop", category: "OnboardingService")

    private let executor: CLIExecutor
    private let claudeService: ClaudeService
    private let forgePathOverride: String?
    private let fileSystem: FileSystemProtocol

    public init(
        executor: CLIExecutor = ProcessExecutor(),
        claudeService: ClaudeService,
        forgePath: String? = nil,
        fileSystem: FileSystemProtocol = RealFileSystem()
    ) {
        self.executor = executor
        self.claudeService = claudeService
        self.forgePathOverride = forgePath
        self.fileSystem = fileSystem
    }

    // MARK: - Brownfield: Analyze Repo

    public func analyzeRepo(path: String) async throws -> CodebaseContext {
        let forgePath = try await resolveForgePath()

        Self.logger.info("Analyzing repo at \(path, privacy: .public)")

        let data = try await executor.run(
            executable: forgePath,
            arguments: ["analyze", path, "--json"],
            timeout: 30
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(CodebaseContext.self, from: data)
        } catch let error as DecodingError {
            Self.logger.error("Failed to decode analyze output: \(error.localizedDescription, privacy: .public)")
            throw ForgeError.jsonDecodingFailed(error)
        }
    }

    // MARK: - Brownfield: Generate CLAUDE.md

    public func generateClaudeMd(
        context: CodebaseContext,
        persona: PersonaInfo
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let prompt = buildBrownfieldPrompt(context: context)
        let systemPrompt = buildSystemPrompt(persona: persona, isGreenfield: false)

        Self.logger.info("Generating CLAUDE.md for \(context.name, privacy: .public) (brownfield)")

        return claudeService.streamInRepo(
            prompt: prompt,
            repoPath: context.path,
            systemPrompt: systemPrompt,
            allowedTools: ["Read", "Glob", "Grep"],
            maxBudget: "1.00",
            timeout: 300
        )
    }

    // MARK: - Greenfield: Generate CLAUDE.md

    public func generateNewProject(
        description: String,
        path: String,
        projectName: String,
        persona: PersonaInfo
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let prompt = buildGreenfieldPrompt(description: description, projectName: projectName)
        let systemPrompt = buildSystemPrompt(persona: persona, isGreenfield: true)

        Self.logger.info("Generating CLAUDE.md for \(projectName, privacy: .public) (greenfield)")

        return claudeService.streamInRepo(
            prompt: prompt,
            repoPath: path,
            systemPrompt: systemPrompt,
            allowedTools: ["Read", "Glob", "Grep"],
            maxBudget: "0.50",
            timeout: 180
        )
    }

    // MARK: - Save

    public func saveClaudeMd(content: String, repoPath: String) throws {
        let claudeDir = "\(repoPath)/.claude"
        let mdPath = "\(claudeDir)/CLAUDE.md"

        // Ensure .claude/ directory exists
        if !FileManager.default.fileExists(atPath: claudeDir) {
            try FileManager.default.createDirectory(
                atPath: claudeDir,
                withIntermediateDirectories: true
            )
        }

        try fileSystem.writeString(content, to: mdPath)
        Self.logger.info("Saved CLAUDE.md to \(mdPath, privacy: .public)")
    }

    // MARK: - Prompts

    private func buildBrownfieldPrompt(context: CodebaseContext) -> String {
        var prompt = """
        Analyze this existing codebase and generate a comprehensive CLAUDE.md file.

        ## Codebase Context (gathered automatically)

        ### Project: \(context.name)
        ### Path: \(context.path)

        ### Directory Structure
        ```
        \(context.directoryStructure)
        ```

        """

        if !context.dependencies.isEmpty {
            prompt += "\n### Dependencies\n"
            for dep in context.dependencies {
                prompt += "\n#### \(dep.file)\n```\n\(dep.content)\n```\n"
            }
        }

        if !context.configs.isEmpty {
            prompt += "\n### Configuration Files\n"
            for config in context.configs {
                prompt += "\n#### \(config.file)\n```\n\(config.content)\n```\n"
            }
        }

        if !context.documentation.isEmpty {
            prompt += "\n### Existing Documentation\n"
            for doc in context.documentation {
                prompt += "\n#### \(doc.file)\n```\n\(String(doc.content.prefix(2000)))\n```\n"
            }
        }

        if context.git.isRepo {
            prompt += "\n### Git Info\n"
            if let branch = context.git.branch {
                prompt += "- Current branch: \(branch)\n"
            }
            if let defaultBranch = context.git.defaultBranch {
                prompt += "- Default branch: \(defaultBranch)\n"
            }
            if !context.git.recentCommits.isEmpty {
                prompt += "\nRecent commits:\n```\n"
                prompt += context.git.recentCommits.prefix(15).joined(separator: "\n")
                prompt += "\n```\n"
            }
            if !context.git.contributors.isEmpty {
                prompt += "\nContributors:\n```\n"
                prompt += context.git.contributors.joined(separator: "\n")
                prompt += "\n```\n"
            }
        }

        if !context.testFiles.isEmpty {
            prompt += "\n### Test Files\n```\n"
            prompt += context.testFiles.prefix(20).joined(separator: "\n")
            prompt += "\n```\n"
        }

        if !context.ciConfigs.isEmpty {
            prompt += "\n### CI/CD\n"
            for ci in context.ciConfigs {
                prompt += "\n#### \(ci.file)\n```\n\(ci.content)\n```\n"
            }
        }

        if let existing = context.existingClaudeMd {
            prompt += "\n### Existing CLAUDE.md (to be improved)\n```\n\(existing)\n```\n"
        }

        prompt += """

        ## Instructions

        Based on the context above, generate a comprehensive CLAUDE.md file. Use the Read, Glob, and \
        Grep tools to explore the codebase deeper where the context above is insufficient.

        Output ONLY the CLAUDE.md content — no explanations, no markdown code fences wrapping the \
        whole thing. Start directly with `# CLAUDE.md` or `# <Project Name>`.

        Quality rules:
        - Target under 200 lines — concise but comprehensive
        - Use specific versions from actual dependency files, not "latest"
        - Include real commands developers run
        - Document patterns as instructions to FOLLOW
        - Include Common Pitfalls section with real issues
        - Do NOT read or reference .env files, secrets, or credentials
        """

        return prompt
    }

    private func buildGreenfieldPrompt(description: String, projectName: String) -> String {
        """
        Generate a CLAUDE.md file for a new project.

        ## Project Details
        - Name: \(projectName)
        - Description: \(description)

        ## Instructions

        Based on the description, generate a comprehensive CLAUDE.md file that will guide \
        Claude Code in building this project.

        Output ONLY the CLAUDE.md content — no explanations, no markdown code fences wrapping the \
        whole thing. Start directly with `# CLAUDE.md` or `# \(projectName)`.

        The CLAUDE.md must include:
        - Overview (what it is, who it's for)
        - Tech stack table (Layer | Technology | Version — use SPECIFIC versions)
        - Project structure (proposed directory layout)
        - Development commands (install, dev, test, build)
        - Key patterns (auth approach, API design, component patterns, error handling)
        - Git workflow and deployment approach
        - Common pitfalls for the chosen stack

        Quality rules:
        - Target under 200 lines — concise but comprehensive
        - Every section should be actionable
        - Document patterns as instructions to FOLLOW
        - Make ALL technical decisions based on best practices for the described use case
        """
    }

    private func buildSystemPrompt(persona: PersonaInfo, isGreenfield: Bool) -> String {
        let isNonTechnical = persona.axes.depth == "conceptual" || persona.axes.communication == "plain"

        if isNonTechnical {
            return """
            You are generating a CLAUDE.md project blueprint. The user is non-technical — they \
            described what they want in plain language. Make all technical decisions yourself. \
            The CLAUDE.md should be written for Claude Code (a technical reader), not for the user.
            """
        } else {
            return """
            You are generating a CLAUDE.md project blueprint for a technical user. \
            Be precise about versions, patterns, and architecture decisions. \
            The CLAUDE.md should be comprehensive and actionable for Claude Code.
            """
        }
    }

    // MARK: - Path Resolution

    private func resolveForgePath() async throws -> String {
        if let override = forgePathOverride, !override.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: override) else {
                throw ForgeError.cliNotFound
            }
            return override
        }
        let service = ForgeService(executor: executor)
        return try await service.discoverForgePath()
    }
}
