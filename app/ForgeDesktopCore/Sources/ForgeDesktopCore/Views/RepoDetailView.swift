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
        DetailCard(repo.claudeMd.exists ? "Improve CLAUDE.md" : "Generate CLAUDE.md") {
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

