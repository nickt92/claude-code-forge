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
    @State private var detectedSections: [DetectedSection] = []
    @State private var generationStartTime: Date?
    @State private var hasStarted = false

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

    /// The effective repo path — uses @State for greenfield (user may change it), mode for brownfield.
    private var effectivePath: String {
        switch mode {
        case .brownfield(let path): return path
        case .greenfield: return projectPath
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
        case .review: return "Review Generated CLAUDE.md"
        case .saving: return "Saving..."
        case .complete: return "Complete"
        case .failed: return "Error"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .brownfield(let path):
            return path.components(separatedBy: "/").suffix(2).joined(separator: "/")
        case .greenfield:
            return projectName.isEmpty ? "New Project" : projectName
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
            // Left pane: Activity log with sections + tool calls
            VStack(alignment: .leading, spacing: 0) {
                Text("PROGRESS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            // Detected sections from markdown headers
                            ForEach(detectedSections) { section in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.green)
                                    Text(section.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .id(section.id)
                            }

                            // Current section being written (pulsing)
                            if !generatedContent.isEmpty, case .generating = phase {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text(currentSectionLabel)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .id("current-section")
                            }

                            if !activities.isEmpty {
                                Divider()
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)

                                Text("TOOL CALLS")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .tracking(0.5)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 4)

                                ForEach(activities) { activity in
                                    HStack(spacing: 6) {
                                        if activity.isComplete {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.green)
                                        } else {
                                            ProgressView()
                                                .controlSize(.mini)
                                        }
                                        Text(activity.displayLabel)
                                            .font(.system(size: 10))
                                            .foregroundStyle(activity.isComplete ? .tertiary : .secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 1)
                                    .id(activity.id)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .onChange(of: activities.count) {
                        if let last = activities.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: detectedSections.count) {
                        withAnimation { proxy.scrollTo("current-section", anchor: .bottom) }
                    }
                }

                Divider()

                // Progress footer with elapsed timer and line count
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(progressLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if generatedLineCount > 0 {
                        Text("\(generatedLineCount) lines")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    if let start = generationStartTime {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            Text(elapsedString(from: start, to: context.date))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 200, idealWidth: 250)

            // Right pane: Live rendered markdown preview
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("LIVE PREVIEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Spacer()
                    if generatedLineCount > 0 {
                        Text("\(generatedLineCount) lines")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        if generatedContent.isEmpty {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Claude is reading your codebase...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 60)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                RenderedMarkdownView(
                                    content: generatedContent,
                                    fontSize: 12
                                )
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Typing cursor
                                if case .generating = phase {
                                    HStack(spacing: 0) {
                                        Rectangle()
                                            .fill(Color.accentColor)
                                            .frame(width: 2, height: 14)
                                            .opacity(cursorOpacity)
                                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: cursorOpacity)
                                    }
                                    .padding(.top, 2)
                                    .id("cursor")
                                }
                            }
                            .padding(12)
                            .id("preview-bottom")
                        }
                    }
                    .onChange(of: generatedContent) {
                        withAnimation {
                            proxy.scrollTo("cursor", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minWidth: 350)
        }
    }

    @State private var cursorOpacity: Double = 1.0

    /// Label for the section currently being written
    private var currentSectionLabel: String {
        // Find the last header line in the content
        let lines = generatedContent.components(separatedBy: "\n")
        if let lastHeader = lines.last(where: { $0.hasPrefix("#") }) {
            let title = lastHeader.trimmingCharacters(in: .init(charactersIn: "# "))
            if !title.isEmpty {
                return "Writing \(title)..."
            }
        }
        return "Writing..."
    }

    private var generatedLineCount: Int {
        guard !generatedContent.isEmpty else { return 0 }
        return generatedContent.components(separatedBy: "\n").count
    }

    private var allToolsComplete: Bool {
        !activities.isEmpty && activities.allSatisfy(\.isComplete)
    }

    private var progressLabel: String {
        if generatedContent.isEmpty {
            if activities.isEmpty {
                return "Starting generation..."
            }
            return "Reading codebase..."
        } else if allToolsComplete {
            return currentSectionLabel
        } else {
            return "Analyzing & writing..."
        }
    }

    private func elapsedString(from start: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes)m \(remainder)s"
    }

    // MARK: - Phase: Review

    private func reviewView(content: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                RenderedMarkdownView(
                    content: content,
                    fontSize: 12
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }

            Divider()

            HStack {
                Text("\(effectivePath)/.claude/CLAUDE.md")
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
        guard !hasStarted else { return }
        hasStarted = true
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
            detectedSections = []
            cursorOpacity = 0.0
            generationStartTime = Date()

            await streamGeneration(
                onboardingService.generateClaudeMd(context: context, persona: persona)
            )
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startGreenfield() {
        guard !hasStarted else { return }
        hasStarted = true
        phase = .generating
        generatedContent = ""
        activities = []
        detectedSections = []
        cursorOpacity = 0.0
        generationStartTime = Date()

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
                    updateDetectedSections()

                case .toolUse(let name, let input):
                    activities.append(ToolActivity(name: name, input: input))

                case .toolResult(let name, _):
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

    /// Scan generatedContent for completed markdown sections (headers followed by more content)
    private func updateDetectedSections() {
        let lines = generatedContent.components(separatedBy: "\n")
        var sections: [DetectedSection] = []

        for (i, line) in lines.enumerated() {
            guard line.hasPrefix("#") else { continue }
            let title = line.trimmingCharacters(in: .init(charactersIn: "# "))
            guard !title.isEmpty else { continue }

            // A section is "complete" if there's a subsequent header after it,
            // meaning Claude has moved on to the next section
            let hasSubsequentHeader = lines[(i + 1)...].contains(where: { $0.hasPrefix("#") })
            if hasSubsequentHeader {
                // Avoid duplicates by title
                if !sections.contains(where: { $0.title == title }) {
                    sections.append(DetectedSection(title: title))
                }
            }
        }

        detectedSections = sections
    }

    private func regenerate() {
        generatedContent = ""
        activities = []
        detectedSections = []
        generationStartTime = Date()
        hasStarted = false

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

        Task {
            do {
                try onboardingService.saveClaudeMd(content: content, repoPath: effectivePath)
                phase = .complete
            } catch {
                phase = .failed("Failed to save: \(error.localizedDescription)")
            }
        }
    }

    private func saveAndOpenInEditor(content: String) {
        do {
            try onboardingService.saveClaudeMd(content: content, repoPath: effectivePath)
            let mdPath = "\(effectivePath)/.claude/CLAUDE.md"
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

// MARK: - Detected Section

private struct DetectedSection: Identifiable {
    let id = UUID()
    let title: String
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
