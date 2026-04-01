import SwiftUI

public struct RepoDetailView: View {
    let repo: RepoData
    @State private var dismissedFindings: Set<String> = []
    @State private var contentHashAtLoad: String?
    @State private var fixRunning: Bool = false
    @State private var claudeMdRefreshTrigger: Int = 0
    @State private var bulkFixState: BulkFixState?
    @State private var showOnboarding = false
    @Environment(\.fixService) private var fixService
    @Environment(\.forgeService) private var forgeService
    @Environment(\.forgeState) private var forgeState
    @Environment(\.dismissalService) private var dismissalService
    @Environment(\.claudeService) private var claudeService

    public init(repo: RepoData) {
        self.repo = repo
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let score = repo.score {
                    scoreSection(score)
                }
                if showOnboardingCard {
                    onboardingCard
                }
                configSection
                if let audit = repo.claudeMdAudit {
                    auditSection(audit)
                    if let mdPath = audit.locations.first {
                        ClaudeMdContentView(
                            filePath: mdPath,
                            audit: audit,
                            refreshTrigger: claudeMdRefreshTrigger
                        )
                    }
                    findingsSection(audit.findings)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(repo.name)
        .frame(minWidth: 450)
        .task(id: repo.path) {
            if let mdPath = repo.claudeMdAudit?.locations.first {
                contentHashAtLoad = try? fixService.contentHash(for: mdPath)
            }
            dismissedFindings = dismissalService.dismissedIds(for: repo.path)
        }
        .sheet(isPresented: $showBulkReview, onDismiss: {
            // User dismissed without approving — reject the current review
            if let review = currentBulkReview {
                handleBulkReviewReject(review.before)
            }
        }) {
            if let review = currentBulkReview {
                DiffPreviewView(
                    before: review.before,
                    after: review.after,
                    sectionName: review.finding.section ?? review.finding.code,
                    remaining: bulkReviewQueue.count,
                    onApprove: { handleBulkReviewApprove(review.after, finding: review.finding) },
                    onReject: { handleBulkReviewReject(review.before) }
                )
            }
        }
    }

    // MARK: - Header

    @State private var isRefreshingAudit = false

    private var header: some View {
        HStack(spacing: 14) {
            if let score = repo.score {
                ScoreRing(score: score.total, grade: score.grade, size: 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(repo.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    HStack(spacing: 4) {
                        Button { SystemActions.openInFinder(path: repo.path) } label: {
                            Label("Finder", systemImage: "folder")
                        }
                        .help("Open in Finder")

                        Button { SystemActions.openInTerminal(path: repo.path) } label: {
                            Label("Terminal", systemImage: "terminal")
                        }
                        .help("Open in Terminal")

                        Button { SystemActions.openInEditor(path: repo.path) } label: {
                            Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .help("Open in Editor")

                        Menu {
                            if repo.claudeMd.exists, claudeService.isAvailable {
                                Button { showOnboarding = true } label: {
                                    Label("Regenerate CLAUDE.md", systemImage: "sparkles")
                                }
                            }
                            Button {
                                isRefreshingAudit = true
                                Task {
                                    await refreshRepoAudit()
                                    isRefreshingAudit = false
                                }
                            } label: {
                                Label("Re-audit Repository", systemImage: "arrow.clockwise")
                            }
                            .disabled(isRefreshingAudit)
                        } label: {
                            if isRefreshingAudit {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Label("More", systemImage: "ellipsis.circle")
                            }
                        }
                        .help("Regenerate, re-audit, and more")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text(repo.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if repo.git.isRepo, !repo.git.branch.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(repo.git.branch)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Score

    private func scoreSection(_ score: ScoreData) -> some View {
        DetailCard("Score Breakdown") {
            DimensionBars(dimensions: score.dimensions)
        }
    }

    // MARK: - Onboarding Card

    private var showOnboardingCard: Bool {
        !repo.claudeMd.exists || (repo.score?.total ?? 100) < 50
    }

    private var onboardingCard: some View {
        DetailCard("Generate CLAUDE.md") {
            VStack(alignment: .leading, spacing: 10) {
                Text(repo.claudeMd.exists
                    ? "Your CLAUDE.md scored low. Regenerate it with Claude for comprehensive codebase analysis."
                    : "Analyze this codebase and generate a comprehensive CLAUDE.md with Claude.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        showOnboarding = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Generate with Claude")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!claudeService.isAvailable)

                    if !claudeService.isAvailable {
                        Text("Requires Claude CLI")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.blue.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showOnboarding) {
            if let dashboard = forgeState.dashboard {
                OnboardingView(
                    mode: .brownfield(repoPath: repo.path),
                    persona: dashboard.global.persona,
                    onComplete: {
                        claudeMdRefreshTrigger += 1
                        Task { await refreshRepoAudit() }
                    }
                )
            }
        }
    }

    // MARK: - Config

    private var configSection: some View {
        DetailCard("Configuration") {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], alignment: .leading, spacing: 10) {
                ConfigChip(label: "CLAUDE.md", value: repo.claudeMd.exists ? "\(repo.claudeMd.lines)L" : "—", ok: repo.claudeMd.exists)
                ConfigChip(label: "Rules", value: "\(repo.rules.count)", ok: repo.rules.count > 0)
                ConfigChip(label: "Hooks", value: repo.hooks.present ? "\(repo.hooks.count)" : "—", ok: repo.hooks.present)
                ConfigChip(label: "PROJECT", value: nil, ok: repo.docChain.projectMd)
                ConfigChip(label: "REQUIREMENTS", value: nil, ok: repo.docChain.requirementsMd)
                ConfigChip(label: "ROADMAP", value: nil, ok: repo.docChain.roadmapMd)
            }
        }
    }

    // MARK: - Audit

    private func auditSection(_ audit: AuditData) -> some View {
        DetailCard("CLAUDE.md Audit") {
            VStack(alignment: .leading, spacing: 12) {
                // Coverage bar
                HStack {
                    Text("Section Coverage")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(audit.sections.coverage)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor(audit.sections.coverage))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(scoreColor(audit.sections.coverage).gradient)
                            .frame(width: max(0, geo.size.width * CGFloat(audit.sections.coverage) / 100))
                    }
                }
                .frame(height: 8)

                // Section tags
                if !audit.sections.found.isEmpty || !audit.sections.missing.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(audit.sections.found, id: \.self) { section in
                            SectionTag(name: section, present: true)
                        }
                        ForEach(audit.sections.missing, id: \.self) { section in
                            SectionTag(name: section, present: false)
                        }
                    }
                }

                // Tech stack gaps
                if !audit.techStack.gaps.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tech Stack Gaps")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 5) {
                            ForEach(audit.techStack.gaps, id: \.self) { tech in
                                Text(tech)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.orange.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                // Staleness warning
                if audit.staleness.stale {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text("CLAUDE.md may be stale — \(audit.staleness.claudeMdDays) days since last update")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Findings

    private func findingsSection(_ findings: [Finding]) -> some View {
        let visibleFindings = findings.filter { !dismissedFindings.contains($0.id) }
        let fixableCount = visibleFindings.filter(\.fixable).count
        let infoFindings = visibleFindings.filter { $0.severity == "info" }

        return DetailCard("Findings (\(visibleFindings.count))") {
            if visibleFindings.isEmpty {
                Text("No findings — looking good!")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Bulk action buttons
                    HStack(spacing: 8) {
                        if fixableCount >= 2 {
                            Button {
                                runBulkFix(visibleFindings.filter(\.fixable))
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .font(.system(size: 10))
                                    Text("Fix All (\(fixableCount))")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(fixRunning || bulkFixState != nil)
                        }

                        if !infoFindings.isEmpty {
                            Button {
                                dismissInfoFindings(infoFindings)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye.slash")
                                        .font(.system(size: 10))
                                    Text("Dismiss Info (\(infoFindings.count))")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Spacer()
                    }

                    // Bulk fix progress
                    if let bulk = bulkFixState {
                        BulkFixProgressView(state: bulk)
                    }

                    // Individual finding rows
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(visibleFindings) { finding in
                            FindingRow(
                                finding: finding,
                                repoPath: repo.path,
                                claudeMdPath: repo.claudeMdAudit?.locations.first,
                                contentHashAtLoad: contentHashAtLoad,
                                fixDisabled: fixRunning || bulkFixState != nil,
                                onFixed: { [finding] in
                                    let id = finding.id
                                    dismissalService.dismiss(repoPath: repo.path, findingId: id)
                                    withAnimation {
                                        _ = dismissedFindings.insert(id)
                                    }
                                    claudeMdRefreshTrigger += 1
                                    recomputeContentHash()
                                    Task { await refreshRepoAudit() }
                                },
                                onFixStarted: { fixRunning = true },
                                onFixEnded: { fixRunning = false }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bulk Operations

    private func dismissInfoFindings(_ findings: [Finding]) {
        let ids = findings.map(\.id)
        dismissalService.dismissAll(repoPath: repo.path, findingIds: ids)
        withAnimation {
            for id in ids {
                dismissedFindings.insert(id)
            }
        }
    }

    @State private var bulkReviewQueue: [(finding: Finding, before: String, after: String)] = []
    @State private var currentBulkReview: (finding: Finding, before: String, after: String)?
    @State private var showBulkReview = false

    private func handleBulkStreamEvent(_ event: ClaudeStreamEvent) {
        switch event {
        case .toolUse(let name, let input):
            bulkFixState?.currentActivities.append(ToolActivity(name: name, input: input))
        case .toolResult(let name, _):
            if let idx = bulkFixState?.currentActivities.lastIndex(where: { $0.name == name && !$0.isComplete }) {
                bulkFixState?.currentActivities[idx].isComplete = true
            }
        default:
            break
        }
    }

    private func runBulkFix(_ fixableFindings: [Finding]) {
        let state = BulkFixState(total: fixableFindings.count)
        bulkFixState = state
        fixRunning = true

        Task {
            for (index, finding) in fixableFindings.enumerated() {
                bulkFixState?.currentIndex = index
                bulkFixState?.currentFinding = finding.detail
                bulkFixState?.currentActivities = []

                let usesClaudeFix = ["missing_section", "tech_gap", "low_coverage"].contains(finding.code)

                do {
                    let result = try await fixService.fix(
                        finding: finding,
                        repoPath: repo.path,
                        claudeMdPath: repo.claudeMdAudit?.locations.first,
                        contentHashAtLoad: contentHashAtLoad,
                        onEvent: usesClaudeFix ? handleBulkStreamEvent : nil
                    )

                    switch result {
                    case .success:
                        bulkFixState?.completedCount += 1
                        dismissalService.dismiss(repoPath: repo.path, findingId: finding.id)
                        _ = withAnimation {
                            dismissedFindings.insert(finding.id)
                        }
                        claudeMdRefreshTrigger += 1
                        recomputeContentHash()
                    case .pendingReview(let before, let after):
                        bulkReviewQueue.append((finding: finding, before: before, after: after))
                        bulkFixState?.completedCount += 1
                        recomputeContentHash()
                    default:
                        bulkFixState?.failedFinding = finding.detail
                        break
                    }
                } catch {
                    bulkFixState?.failedFinding = finding.detail
                    break
                }

                if bulkFixState?.failedFinding != nil { break }
            }

            fixRunning = false

            // Clear bulk progress after a delay
            try? await Task.sleep(for: .seconds(1))
            bulkFixState = nil

            // Present queued reviews one at a time
            if !bulkReviewQueue.isEmpty {
                currentBulkReview = bulkReviewQueue.removeFirst()
                showBulkReview = true
            } else {
                await refreshRepoAudit()
            }
        }
    }

    private func handleBulkReviewApprove(_ afterContent: String, finding: Finding) {
        showBulkReview = false
        guard let mdPath = repo.claudeMdAudit?.locations.first else {
            advanceBulkReview()
            return
        }
        do {
            let consistent = try fixService.approveChange(mdPath: mdPath, expectedAfterContent: afterContent)
            if consistent {
                dismissalService.dismiss(repoPath: repo.path, findingId: finding.id)
                withAnimation { _ = dismissedFindings.insert(finding.id) }
                claudeMdRefreshTrigger += 1
                recomputeContentHash()
            }
        } catch {
            // Approval failed — the file remains as-is on disk
        }
        advanceBulkReview()
    }

    private func handleBulkReviewReject(_ beforeContent: String) {
        showBulkReview = false
        guard let mdPath = repo.claudeMdAudit?.locations.first else {
            advanceBulkReview()
            return
        }
        try? fixService.rejectChange(mdPath: mdPath, originalContent: beforeContent)
        recomputeContentHash()
        advanceBulkReview()
    }

    private func advanceBulkReview() {
        if bulkReviewQueue.isEmpty {
            currentBulkReview = nil
            Task { await refreshRepoAudit() }
        } else {
            currentBulkReview = bulkReviewQueue.removeFirst()
            showBulkReview = true
        }
    }

    private func recomputeContentHash() {
        if let mdPath = repo.claudeMdAudit?.locations.first {
            contentHashAtLoad = try? fixService.contentHash(for: mdPath)
        }
    }

    // MARK: - Repo Refresh

    private func refreshRepoAudit() async {
        do {
            let audit = try await forgeService.auditRepo(path: repo.path)
            forgeState.updateRepo(path: repo.path, audit: audit)
        } catch {
            // Refresh is best-effort — don't surface errors for background refresh
        }
    }
}

// MARK: - Bulk Fix State

struct BulkFixState {
    let total: Int
    var currentIndex: Int = 0
    var completedCount: Int = 0
    var currentFinding: String = ""
    var failedFinding: String?
    var currentActivities: [ToolActivity] = []
}

struct BulkFixProgressView: View {
    let state: BulkFixState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView(value: Double(state.completedCount), total: Double(state.total))
                    .progressViewStyle(.linear)
                Text("\(state.completedCount)/\(state.total)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let failed = state.failedFinding {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 10))
                    Text("Failed: \(failed)")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(state.currentFinding)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Show tool activities for the current fix
                if !state.currentActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(state.currentActivities) { activity in
                            HStack(spacing: 4) {
                                if activity.isComplete {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.green)
                                } else {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                Text(activity.displayLabel)
                                    .font(.system(size: 9))
                                    .foregroundStyle(activity.isComplete ? .tertiary : .secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Detail Card

struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}

// MARK: - Config Chip

struct ConfigChip: View {
    let label: String
    let value: String?
    let ok: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                if let value {
                    Text(value)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Finding Row

struct FindingRow: View {
    let finding: Finding
    var repoPath: String = ""
    var claudeMdPath: String?
    var contentHashAtLoad: String?
    var fixDisabled: Bool = false
    var onFixed: (() -> Void)?
    var onFixStarted: (() -> Void)?
    var onFixEnded: (() -> Void)?

    @Environment(\.fixService) private var fixService
    @State private var showConfirm = false
    @State private var fixState: FixState = .idle
    @State private var showClaudeResponse = false
    @State private var fixActivities: [ToolActivity] = []
    @State private var fixStartTime: Date?

    enum FixState {
        case idle, running, pendingReview(before: String, after: String), success, failed(String)
        case claudeDidNotModify(response: String, costUsd: Double)
    }

    private var usesClaudeFix: Bool {
        ["missing_section", "tech_gap", "low_coverage"].contains(finding.code)
    }

    private var isPendingReview: Binding<Bool> {
        Binding(
            get: {
                if case .pendingReview = fixState { return true }
                return false
            },
            set: { newValue in
                if !newValue, case .pendingReview(let before, _) = fixState {
                    handleReject(before)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(severityColor(finding.severity))
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.detail)
                        .font(.system(size: 12))
                    HStack(spacing: 6) {
                        Text(finding.code.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        if finding.fixable {
                            fixButton
                        }
                    }
                }

                Spacer()
            }

            // Inline tool activity during Claude fix
            if case .running = fixState, usesClaudeFix {
                VStack(alignment: .leading, spacing: 2) {
                    if fixActivities.isEmpty {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Connecting to Claude...")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(fixActivities) { activity in
                            HStack(spacing: 4) {
                                if activity.isComplete {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.green)
                                } else {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                Text(activity.displayLabel)
                                    .font(.system(size: 9))
                                    .foregroundStyle(activity.isComplete ? .tertiary : .secondary)
                                    .lineLimit(1)
                            }
                        }

                        // Show "writing" status when all tools are done but fix is still running
                        if fixActivities.allSatisfy(\.isComplete) {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Writing changes...")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Elapsed timer
                    if let start = fixStartTime {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            let seconds = Int(context.date.timeIntervalSince(start))
                            Text(seconds < 60 ? "\(seconds)s elapsed" : "\(seconds / 60)m \(seconds % 60)s elapsed")
                                .font(.system(size: 8, design: .rounded))
                                .foregroundStyle(.quaternary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if case .claudeDidNotModify(let response, let cost) = fixState, showClaudeResponse {
                Text(cost > 0
                    ? "Claude analyzed the file but determined no changes were needed."
                    : "Claude did not process the request. Check CLI configuration and authentication.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                if !response.isEmpty {
                    Text(response)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(severityColor(finding.severity).opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .animation(.easeInOut(duration: 0.2), value: fixActivities.count)
        .sheet(isPresented: isPendingReview) {
            if case .pendingReview(let before, let after) = fixState {
                DiffPreviewView(
                    before: before,
                    after: after,
                    sectionName: finding.section ?? finding.code,
                    onApprove: { handleApprove(after) },
                    onReject: { handleReject(before) }
                )
            }
        }
    }

    @ViewBuilder
    private var fixButton: some View {
        switch fixState {
        case .idle:
            if usesClaudeFix && !fixService.claudeAvailable {
                HStack(spacing: 3) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 8))
                    Text("Fix")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.1), in: Capsule())
                .foregroundStyle(.gray)
                .help("Requires Claude Code CLI to generate intelligent fixes")
            } else {
                Button {
                    showConfirm = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: usesClaudeFix ? "sparkles" : "wrench.and.screwdriver.fill")
                            .font(.system(size: 8))
                        Text("Fix")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(fixDisabled)
                .opacity(fixDisabled ? 0.4 : 1)
                .popover(isPresented: $showConfirm) {
                    fixConfirmPopover
                }
            }
        case .running:
            HStack(spacing: 3) {
                ProgressView()
                    .controlSize(.mini)
                Text(fixActivities.isEmpty
                    ? (usesClaudeFix ? "Starting Claude..." : "Fixing...")
                    : (fixActivities.allSatisfy(\.isComplete) ? "Claude is writing..." : "Claude is analyzing..."))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .pendingReview:
            HStack(spacing: 3) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 9))
                Text("Reviewing...")
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.1), in: Capsule())
            .foregroundStyle(.blue)
        case .success:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                Text(usesClaudeFix ? "Section added" : "Fixed")
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.1), in: Capsule())
            .foregroundStyle(.green)
        case .claudeDidNotModify:
            Button {
                showClaudeResponse.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9))
                    Text("No changes")
                        .font(.system(size: 9, weight: .bold))
                    Image(systemName: showClaudeResponse ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.1), in: Capsule())
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        case .failed(let message):
            HStack(spacing: 3) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                Text(message)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.1), in: Capsule())
            .foregroundStyle(.red)
        }
    }

    private var fixConfirmPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: usesClaudeFix ? "sparkles" : "wrench.and.screwdriver.fill")
                    .foregroundStyle(.blue)
                Text("Apply Fix?")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text(fixDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { showConfirm = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Apply Fix") { applyFix() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var fixDescription: String {
        switch finding.code {
        case "no_claude_md":
            return "Run 'forge init' to create a CLAUDE.md in this repository."
        case "missing_section":
            let section = finding.section ?? "Section"
            return "Claude will analyze your codebase and generate a proper \(section) section. This takes about 10-30 seconds."
        case "tech_gap":
            return "Claude will analyze your codebase and document how this technology is actually used. This takes about 10-30 seconds."
        case "low_coverage":
            if let section = finding.section {
                return "Claude will analyze your codebase and generate a proper \(section) section. This takes about 10-30 seconds."
            }
            return "Fix individual missing sections to improve coverage."
        default:
            return "Apply an automatic fix for this finding."
        }
    }

    private func handleStreamEvent(_ event: ClaudeStreamEvent) {
        switch event {
        case .toolUse(let name, let input):
            fixActivities.append(ToolActivity(name: name, input: input))
        case .toolResult(let name, _):
            if let idx = fixActivities.lastIndex(where: { $0.name == name && !$0.isComplete }) {
                fixActivities[idx].isComplete = true
            }
        default:
            break
        }
    }

    private func applyFix() {
        showConfirm = false
        fixState = .running
        fixActivities = []
        fixStartTime = usesClaudeFix ? Date() : nil
        onFixStarted?()

        Task {
            do {
                let result = try await fixService.fix(
                    finding: finding,
                    repoPath: repoPath,
                    claudeMdPath: claudeMdPath,
                    contentHashAtLoad: contentHashAtLoad,
                    onEvent: usesClaudeFix ? handleStreamEvent : nil
                )

                switch result {
                case .success:
                    fixState = .success
                    onFixed?()
                    onFixEnded?()
                case .pendingReview(let before, let after):
                    fixState = .pendingReview(before: before, after: after)
                case .claudeDidNotModify(let response, let costUsd):
                    fixState = .claudeDidNotModify(response: response, costUsd: costUsd)
                    onFixEnded?()
                case .notFixable(let reason):
                    fixState = .failed(reason)
                    onFixEnded?()
                case .staleContent:
                    fixState = .failed("File changed externally")
                    onFixEnded?()
                case .fileNotFound:
                    fixState = .failed("CLAUDE.md not found")
                    onFixEnded?()
                case .claudeNotAvailable:
                    fixState = .failed("Claude CLI not found")
                    onFixEnded?()
                case .claudeFailed(let msg):
                    fixState = .failed(msg)
                    onFixEnded?()
                case .claudeTimeout:
                    fixState = .failed("Timed out")
                    onFixEnded?()
                case .fixInProgress:
                    fixState = .failed("Another fix is running")
                    onFixEnded?()
                }
            } catch {
                fixState = .failed(error.localizedDescription)
                onFixEnded?()
            }
        }
    }

    private func handleApprove(_ afterContent: String) {
        guard let mdPath = claudeMdPath else {
            fixState = .failed("CLAUDE.md path unknown")
            onFixEnded?()
            return
        }
        do {
            let consistent = try fixService.approveChange(mdPath: mdPath, expectedAfterContent: afterContent)
            if consistent {
                fixState = .success
                onFixed?()
            } else {
                fixState = .failed("File changed during review")
            }
        } catch {
            fixState = .failed(error.localizedDescription)
        }
        onFixEnded?()
    }

    private func handleReject(_ beforeContent: String) {
        guard let mdPath = claudeMdPath else {
            fixState = .idle
            onFixEnded?()
            return
        }
        do {
            try fixService.rejectChange(mdPath: mdPath, originalContent: beforeContent)
            fixState = .idle
        } catch {
            fixState = .failed("Could not restore original file")
        }
        onFixEnded?()
    }

    private var icon: String {
        switch finding.severity {
        case "error": return "xmark.octagon.fill"
        case "warn": return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }
}

// MARK: - Section Tag

struct SectionTag: View {
    let name: String
    let present: Bool

    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(present ? .green.opacity(0.1) : .red.opacity(0.08), in: Capsule())
            .foregroundStyle(present ? .green : .red)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
