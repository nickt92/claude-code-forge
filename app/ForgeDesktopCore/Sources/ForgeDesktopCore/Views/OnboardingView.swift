import SwiftUI

public struct OnboardingView: View {
    let mode: OnboardingMode
    let persona: PersonaInfo
    let onComplete: () -> Void

    @Environment(\.onboardingService) private var onboardingService
    @Environment(\.dismiss) private var dismiss

    @State private var phase: OnboardingPhase = .analyzing
    @State private var activities: [ToolActivity] = []
    @State private var generatedContent: String = ""
    @State private var contextSummary: ContextSummary?
    @State private var streamTask: Task<Void, Never>?

    // Greenfield inputs
    @State private var projectDescription: String = ""
    @State private var projectPath: String = ""
    @State private var projectName: String = ""

    public init(mode: OnboardingMode, persona: PersonaInfo, onComplete: @escaping () -> Void) {
        self.mode = mode
        self.persona = persona
        self.onComplete = onComplete

        switch mode {
        case .greenfield(let path, let name, let description):
            _projectPath = State(initialValue: path)
            _projectName = State(initialValue: name)
            _projectDescription = State(initialValue: description)
            _phase = State(initialValue: .setup)
        case .brownfield:
            _phase = State(initialValue: .analyzing)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            if case .brownfield(let repoPath) = mode {
                await startBrownfield(repoPath: repoPath)
            }
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: isGreenfield ? "folder.badge.plus" : "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if phase == .generating {
                Button("Cancel") {
                    streamTask?.cancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerTitle: String {
        switch phase {
        case .setup: return "New Project Setup"
        case .analyzing: return "Analyzing Codebase"
        case .generating: return "Generating CLAUDE.md"
        case .review: return "Review CLAUDE.md"
        case .saving: return "Saving..."
        case .complete: return "Complete"
        case .failed: return "Error"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .brownfield(let path):
            return path.components(separatedBy: "/").suffix(2).joined(separator: "/")
        case .greenfield(_, let name, _):
            return name
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .setup:
            greenfieldSetupView
        case .analyzing:
            analyzingView
        case .generating:
            generatingView
        case .review(let content):
            reviewView(content: content)
        case .saving:
            VStack(spacing: 12) {
                ProgressView()
                Text("Saving CLAUDE.md...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .complete:
            completeView
        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: - Phase: Setup (Greenfield)

    private var greenfieldSetupView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Project Directory")
                    .font(.system(size: 12, weight: .medium))
                HStack {
                    TextField("Path", text: $projectPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button("Choose...") {
                        chooseDirectory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Project Name")
                    .font(.system(size: 12, weight: .medium))
                TextField("my-project", text: $projectName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Describe what you're building")
                    .font(.system(size: 12, weight: .medium))
                TextEditor(text: $projectDescription)
                    .font(.system(size: 12))
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                Text(placeholderText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Generate") {
                    startGreenfield()
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || projectPath.isEmpty)
            }
        }
        .padding(20)
    }

    private var placeholderText: String {
        let isNonTechnical = persona.axes.depth == "conceptual" || persona.axes.communication == "plain"
        if isNonTechnical {
            return "e.g., A website for my bakery with online ordering and a menu page"
        } else {
            return "e.g., A GraphQL API with Postgres, Redis caching, and JWT auth for a SaaS dashboard"
        }
    }

    // MARK: - Phase: Analyzing

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing codebase...")
                .font(.system(size: 14, weight: .medium))

            if let summary = contextSummary {
                VStack(alignment: .leading, spacing: 6) {
                    summaryRow("Dependencies", count: summary.dependencyCount)
                    summaryRow("Config files", count: summary.configCount)
                    summaryRow("Test files", count: summary.testFileCount)
                    summaryRow("Scripts", count: summary.scriptCount)
                    if summary.hasGit {
                        summaryRow("Git commits", count: summary.commitCount)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryRow(_ label: String, count: Int) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
            Text("\(label): \(count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Phase: Generating (Split View)

    private var generatingView: some View {
        HSplitView {
            // Left pane: Activity log
            VStack(alignment: .leading, spacing: 0) {
                Text("ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(activities) { activity in
                                HStack(spacing: 6) {
                                    if activity.isComplete {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.green)
                                    } else {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                    Text(activity.displayLabel)
                                        .font(.system(size: 11))
                                        .foregroundStyle(activity.isComplete ? .secondary : .primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 2)
                                .id(activity.id)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .onChange(of: activities.count) {
                        if let last = activities.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Progress indicator
                HStack {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Generating...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(activities.filter(\.isComplete).count) tools")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
            }
            .frame(minWidth: 200, idealWidth: 250)

            // Right pane: Live preview
            VStack(alignment: .leading, spacing: 0) {
                Text("LIVE PREVIEW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(generatedContent.isEmpty ? "Waiting for Claude..." : generatedContent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(generatedContent.isEmpty ? .tertiary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .id("preview-bottom")
                    }
                    .onChange(of: generatedContent) {
                        withAnimation {
                            proxy.scrollTo("preview-bottom", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minWidth: 350)
        }
    }

    // MARK: - Phase: Review

    private func reviewView(content: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            Divider()

            HStack {
                let repoPath: String = {
                    switch mode {
                    case .brownfield(let path): return path
                    case .greenfield(let path, _, _): return path
                    }
                }()

                Text("\(repoPath)/.claude/CLAUDE.md")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Regenerate") {
                    regenerate()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Open in Editor") {
                    saveAndOpenInEditor(content: content)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Save") {
                    save(content: content)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Phase: Complete

    private var completeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("CLAUDE.md Generated")
                .font(.system(size: 16, weight: .semibold))

            Text("Your project is ready for Claude Code.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button("Done") {
                onComplete()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Phase: Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Generation Failed")
                .font(.system(size: 16, weight: .semibold))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Retry") { regenerate() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Workflows

    private func startBrownfield(repoPath: String) async {
        phase = .analyzing
        do {
            let context = try await onboardingService.analyzeRepo(path: repoPath)
            contextSummary = ContextSummary(
                dependencyCount: context.dependencies.count,
                configCount: context.configs.count,
                testFileCount: context.testFiles.count,
                scriptCount: context.scripts.count,
                hasGit: context.git.isRepo,
                commitCount: context.git.recentCommits.count
            )

            // Brief pause to show summary before streaming
            try? await Task.sleep(for: .seconds(1))

            phase = .generating
            generatedContent = ""
            activities = []

            await streamGeneration(
                onboardingService.generateClaudeMd(context: context, persona: persona)
            )
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startGreenfield() {
        phase = .generating
        generatedContent = ""
        activities = []

        let description = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = projectPath
        let name = projectName.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : projectName

        streamTask = Task {
            await streamGeneration(
                onboardingService.generateNewProject(
                    description: description,
                    path: path,
                    projectName: name,
                    persona: persona
                )
            )
        }
    }

    private func streamGeneration(_ stream: AsyncThrowingStream<ClaudeStreamEvent, Error>) async {
        do {
            for try await event in stream {
                switch event {
                case .assistantText(let text):
                    generatedContent += text

                case .toolUse(let name, let input):
                    activities.append(ToolActivity(name: name, input: input))

                case .toolResult(let name, _):
                    // Mark the most recent matching tool as complete
                    if let idx = activities.lastIndex(where: { $0.name == name && !$0.isComplete }) {
                        activities[idx].isComplete = true
                    }

                case .result(let result):
                    if result.isError {
                        phase = .failed(result.result ?? "Unknown error")
                    } else {
                        let finalContent = generatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        if finalContent.isEmpty {
                            phase = .failed("Claude did not generate any content")
                        } else {
                            phase = .review(content: finalContent)
                        }
                    }

                case .error(let message):
                    phase = .failed(message)
                }
            }

            // Stream finished without a result event
            if case .generating = phase {
                let finalContent = generatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if finalContent.isEmpty {
                    phase = .failed("Generation ended without producing content")
                } else {
                    phase = .review(content: finalContent)
                }
            }
        } catch is CancellationError {
            // User cancelled
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func regenerate() {
        generatedContent = ""
        activities = []

        streamTask?.cancel()
        streamTask = Task {
            switch mode {
            case .brownfield(let repoPath):
                await startBrownfield(repoPath: repoPath)
            case .greenfield:
                startGreenfield()
            }
        }
    }

    private func save(content: String) {
        phase = .saving
        let repoPath: String
        switch mode {
        case .brownfield(let path): repoPath = path
        case .greenfield(let path, _, _): repoPath = path
        }

        Task {
            do {
                try onboardingService.saveClaudeMd(content: content, repoPath: repoPath)
                phase = .complete
            } catch {
                phase = .failed("Failed to save: \(error.localizedDescription)")
            }
        }
    }

    private func saveAndOpenInEditor(content: String) {
        let repoPath: String
        switch mode {
        case .brownfield(let path): repoPath = path
        case .greenfield(let path, _, _): repoPath = path
        }

        do {
            try onboardingService.saveClaudeMd(content: content, repoPath: repoPath)
            let mdPath = "\(repoPath)/.claude/CLAUDE.md"
            SystemActions.openInEditor(path: mdPath)
            onComplete()
            dismiss()
        } catch {
            phase = .failed("Failed to save: \(error.localizedDescription)")
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
            if projectName.isEmpty {
                projectName = url.lastPathComponent
            }
        }
    }

    private var isGreenfield: Bool {
        if case .greenfield = mode { return true }
        return false
    }
}

// MARK: - Context Summary

private struct ContextSummary {
    let dependencyCount: Int
    let configCount: Int
    let testFileCount: Int
    let scriptCount: Int
    let hasGit: Bool
    let commitCount: Int
}
