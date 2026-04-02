import Foundation
import os

public final class OnboardingService: Sendable {
    private static let logger = Logger(subsystem: "com.forge.desktop", category: "OnboardingService")

    private let executor: CLIExecutor
    private let claudeService: ClaudeService
    private let pathResolver: ForgePathResolver
    private let fileSystem: FileSystemProtocol

    public init(
        executor: CLIExecutor = ProcessExecutor(),
        claudeService: ClaudeService,
        forgePath: String? = nil,
        fileSystem: FileSystemProtocol = RealFileSystem()
    ) {
        self.executor = executor
        self.claudeService = claudeService
        self.pathResolver = ForgePathResolver(executor: executor, forgePath: forgePath)
        self.fileSystem = fileSystem
    }

    public init(
        executor: CLIExecutor = ProcessExecutor(),
        claudeService: ClaudeService,
        pathResolver: ForgePathResolver,
        fileSystem: FileSystemProtocol = RealFileSystem()
    ) {
        self.executor = executor
        self.claudeService = claudeService
        self.pathResolver = pathResolver
        self.fileSystem = fileSystem
    }

    // MARK: - Brownfield: Analyze Repo

    public func analyzeRepo(path: String) async throws -> CodebaseContext {
        let forgePath = try await pathResolver.resolve()

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

        You are writing a CLAUDE.md file that will be the single source of truth for Claude Code \
        when working in this codebase. Use the Read, Glob, and Grep tools to explore the codebase \
        deeper where the context above is insufficient.

        Output ONLY the raw CLAUDE.md content. No preamble, no explanation, no markdown code fences \
        wrapping the output. Start directly with `# <Project Name>`.

        ## Required Sections

        1. **Overview** — What it is, who it's for (3-5 lines)
        2. **Architecture** — Directory structure tree, service communication, monorepo/app layout
        3. **Tech Stack** — Table: `| Layer | Technology | Version |` with EXACT versions from dependency files
        4. **Development Setup** — Step-by-step from clone to running, port table, key commands
        5. **Key Architecture Patterns** — Auth flow, API design, DB patterns, error handling, \
        component patterns. Write as imperatives ("Always use...", "Never...")  with code snippets.
        6. **Testing** — Framework, file conventions, coverage targets, test helper patterns
        7. **Git Workflow** — Branch strategy, commit format, PR process
        8. **Deployment** — Platform, environments, CI/CD
        9. **Common Pitfalls** — 5-10 numbered gotchas specific to THIS codebase

        ## Quality Rules

        - Target 150-250 lines — dense and actionable, not padded
        - Use REAL file paths, REAL commands, REAL version numbers from the codebase
        - Include code snippets showing actual import patterns and usage from the codebase
        - Cross-reference sections (testing references file paths from architecture)
        - Do NOT read or reference .env files, secrets, credentials, or API keys
        - Do NOT include generic advice — every line must be specific to THIS project
        """

        return prompt
    }

    private func buildGreenfieldPrompt(description: String, projectName: String) -> String {
        """
        You are writing a CLAUDE.md file that will be the single source of truth for Claude Code \
        when building a new project from scratch. This file must contain every technical decision \
        needed to start coding immediately — Claude Code will read this file and follow it exactly.

        ## Project
        - Name: \(projectName)
        - Description: \(description)

        ## Output Format

        Output ONLY the raw CLAUDE.md content. No preamble, no explanation, no markdown code fences \
        wrapping the output. Start directly with `# \(projectName)`.

        ## Required Sections (in this order)

        ### 1. Overview (3-5 lines)
        What the project is, who it's for, what problem it solves.

        ### 2. Architecture
        - Monorepo vs single-app decision with rationale
        - Directory structure as a tree diagram (```code block```)
        - Service communication diagram if multi-service

        ### 3. Tech Stack
        Table format: `| Layer | Technology | Version |`
        - Pick SPECIFIC versions (e.g., "React 19", "Express 5", "PostgreSQL 16") — never "latest"
        - Include package manager, runtime, ORM, test framework, linter
        - Justify non-obvious choices in a note below the table

        ### 4. Development Setup
        - Step-by-step commands to go from clone to running app
        - Port assignments table if multiple services
        - Environment variables needed (with example values, never real secrets)
        - Docker/container setup if applicable

        ### 5. Key Architecture Patterns
        Document as INSTRUCTIONS Claude Code must follow:
        - Authentication approach (session vs JWT, flow diagram)
        - API design (REST vs GraphQL, naming conventions, error response format)
        - Database schema patterns (naming, relationships, migration workflow)
        - Component/module patterns with import examples
        - Error handling strategy with code examples
        - State management approach

        ### 6. Testing Strategy
        - Framework and runner
        - File location conventions
        - Coverage targets by layer
        - Example test patterns (with code snippets)

        ### 7. Git Workflow
        - Branch naming convention
        - Commit message format
        - PR process

        ### 8. Deployment
        - Target platform recommendation
        - CI/CD approach
        - Environment strategy (dev/staging/prod)

        ### 9. Common Pitfalls
        Numbered list of 5-10 gotchas specific to the chosen stack.

        ## Quality Rules

        - Target 150-250 lines — dense and actionable, not padded
        - Every section must contain concrete decisions, not generic advice
        - Use real file paths from the directory structure you defined
        - Include code snippets showing exact import patterns and usage
        - Write patterns as imperatives: "Always use...", "Never...", "Use X for Y"
        - Cross-reference between sections (e.g., testing section references file paths from architecture)
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

}
