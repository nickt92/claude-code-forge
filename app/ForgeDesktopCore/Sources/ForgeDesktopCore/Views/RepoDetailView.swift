import SwiftUI

public struct RepoDetailView: View {
    let repo: RepoData
    let onDashboardRefresh: () -> Void
    @State private var dismissedFindings: Set<String> = []
    @State private var contentHashAtLoad: String?
    @State private var fixRunning: Bool = false
    @State private var claudeMdRefreshTrigger: Int = 0
    @State private var showOnboarding = false
    @State private var coordinator: BulkFixCoordinator?
    @Environment(\.fixService) private var fixService
    @Environment(\.forgeService) private var forgeService
    @Environment(\.forgeState) private var forgeState
    @Environment(\.dismissalService) private var dismissalService
    @Environment(\.claudeService) private var claudeService

    public init(repo: RepoData, onDashboardRefresh: @escaping () -> Void) {
        self.repo = repo
        self.onDashboardRefresh = onDashboardRefresh
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.lg) {
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
            .padding(ForgeTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(repo.name)
        .frame(minWidth: 450)
        .task(id: repo.path) {
            coordinator = BulkFixCoordinator(fixService: fixService, dismissalService: dismissalService)
            if let mdPath = repo.claudeMdAudit?.locations.first {
                contentHashAtLoad = try? fixService.contentHash(for: mdPath)
            }
            dismissedFindings = dismissalService.dismissedIds(for: repo.path)
        }
        .sheet(isPresented: Binding(
            get: { coordinator?.showReview ?? false },
            set: { newValue in
                if !newValue, let review = coordinator?.currentReview {
                    coordinator?.handleReviewReject(
                        beforeContent: review.before,
                        claudeMdPath: repo.claudeMdAudit?.locations.first,
                        onContentChanged: { recomputeContentHash() },
                        onRefresh: { await refreshRepoAudit() }
                    )
                }
            }
        )) {
            if let review = coordinator?.currentReview {
                DiffPreviewView(
                    before: review.before,
                    after: review.after,
                    sectionName: review.finding.section ?? review.finding.code,
                    remaining: coordinator?.reviewQueue.count ?? 0,
                    reviewIndex: (coordinator?.completedReviews ?? 0) + 1,
                    reviewTotal: coordinator?.totalPendingReviews ?? 0,
                    onApprove: {
                        coordinator?.handleReviewApprove(
                            afterContent: review.after,
                            finding: review.finding,
                            repoPath: repo.path,
                            claudeMdPath: repo.claudeMdAudit?.locations.first,
                            onDismissed: { id in
                                dismissalService.dismiss(repoPath: repo.path, findingId: id)
                                forgeWithAnimation { _ = dismissedFindings.insert(id) }
                                claudeMdRefreshTrigger += 1
                            },
                            onContentChanged: { recomputeContentHash() },
                            onRefresh: { await refreshRepoAudit() }
                        )
                    },
                    onReject: {
                        coordinator?.handleReviewReject(
                            beforeContent: review.before,
                            claudeMdPath: repo.claudeMdAudit?.locations.first,
                            onContentChanged: { recomputeContentHash() },
                            onRefresh: { await refreshRepoAudit() }
                        )
                    }
                )
            }
        }
    }

    // MARK: - Header

    @State private var isRefreshingAudit = false

    private var header: some View {
        HStack(alignment: .center, spacing: ForgeTheme.Spacing.lg) {
            if let score = repo.score {
                ScoreRing(score: score.total, grade: score.grade, size: 64)
                    .id(repo.path)
            }
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
                Text(repo.name)
                    .font(ForgeTheme.Typography.screenTitle)
                Text(repo.path)
                    .font(ForgeTheme.Typography.mono)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if repo.git.isRepo, !repo.git.branch.isEmpty {
                    HStack(spacing: ForgeTheme.Spacing.xs) {
                        Image(systemName: "arrow.triangle.branch")
                            .accessibilityHidden(true)
                        Text(repo.git.branch)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Branch \(repo.git.branch)")
                }
            }

            Spacer(minLength: ForgeTheme.Spacing.sm)

            HStack(spacing: ForgeTheme.Spacing.xs) {
                Button { SystemActions.openInFinder(path: repo.path) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.forgeIcon)
                .help("Open in Finder")
                .accessibilityLabel("Open in Finder")

                Button { SystemActions.openInTerminal(path: repo.path) } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.forgeIcon)
                .help("Open in Terminal")
                .accessibilityLabel("Open in Terminal")

                Button { SystemActions.openInEditor(path: repo.path) } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.forgeIcon)
                .help("Open in Editor")
                .accessibilityLabel("Open in Editor")

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
                            .frame(
                                width: ForgeTheme.Metrics.iconButtonSize,
                                height: ForgeTheme.Metrics.iconButtonSize
                            )
                    } else {
                        Image(systemName: "ellipsis.circle")
                            .frame(
                                width: ForgeTheme.Metrics.iconButtonSize,
                                height: ForgeTheme.Metrics.iconButtonSize
                            )
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Regenerate, re-audit, and more")
                .accessibilityLabel("More actions")
            }
        }
    }

    // MARK: - Score

    private func scoreSection(_ score: ScoreData) -> some View {
        ForgeCard("Score Breakdown", icon: "chart.bar.fill") {
            DimensionBars(dimensions: score.dimensions)
                .id(repo.path)
        }
        .staggeredReveal(index: 0)
    }

    // MARK: - Onboarding Card

    private var showOnboardingCard: Bool {
        !repo.claudeMd.exists || (repo.score?.total ?? 100) < 50
    }

    private var onboardingCard: some View {
        ForgeCard(
            repo.claudeMd.exists ? "Improve CLAUDE.md" : "Generate CLAUDE.md",
            icon: "sparkles"
        ) {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.md) {
                Text(repo.claudeMd.exists
                    ? "Your CLAUDE.md scored low. Regenerate it with Claude for comprehensive codebase analysis."
                    : "Analyze this codebase and generate a comprehensive CLAUDE.md with Claude.")
                    .font(ForgeTheme.Typography.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: ForgeTheme.Spacing.sm) {
                    Button {
                        showOnboarding = true
                    } label: {
                        HStack(spacing: ForgeTheme.Spacing.xs) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Generate with Claude")
                        }
                    }
                    .buttonStyle(.forgePrimary)
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
            RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
                .stroke(ForgeTheme.Gradients.forge, lineWidth: 1.5)
                .opacity(0.5)
        )
        .staggeredReveal(index: 1)
        .sheet(isPresented: $showOnboarding) {
            if let dashboard = forgeState.dashboard {
                OnboardingView(
                    mode: .brownfield(repoPath: repo.path),
                    persona: dashboard.global.persona,
                    onComplete: {
                        claudeMdRefreshTrigger += 1
                        onDashboardRefresh()
                    }
                )
            }
        }
    }

    // MARK: - Config

    private var configSection: some View {
        ForgeCard("Configuration", icon: "slider.horizontal.3") {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 140), spacing: ForgeTheme.Spacing.md),
            ], alignment: .leading, spacing: ForgeTheme.Spacing.md) {
                ConfigChip(label: "CLAUDE.md", value: repo.claudeMd.exists ? "\(repo.claudeMd.lines)L" : "—", ok: repo.claudeMd.exists)
                ConfigChip(label: "Rules", value: "\(repo.rules.count)", ok: repo.rules.count > 0)
                ConfigChip(label: "Hooks", value: repo.hooks.present ? "\(repo.hooks.count)" : "—", ok: repo.hooks.present)
                ConfigChip(label: "PROJECT", value: nil, ok: repo.docChain.projectMd)
                ConfigChip(label: "REQUIREMENTS", value: nil, ok: repo.docChain.requirementsMd)
                ConfigChip(label: "ROADMAP", value: nil, ok: repo.docChain.roadmapMd)
            }
        }
        .staggeredReveal(index: 2)
    }

    // MARK: - Audit

    private func auditSection(_ audit: AuditData) -> some View {
        ForgeCard("CLAUDE.md Audit", icon: "doc.text.magnifyingglass") {
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
                            StatusBadge(section, tint: ForgeTheme.Colors.success)
                                .accessibilityLabel("\(section) section present")
                        }
                        ForEach(audit.sections.missing, id: \.self) { section in
                            StatusBadge(section, tint: ForgeTheme.Colors.danger)
                                .accessibilityLabel("\(section) section missing")
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
                                StatusBadge(tech, tint: ForgeTheme.Colors.warning)
                            }
                        }
                    }
                }

                // Quality metrics
                if audit.quality.lineCount != nil || audit.quality.imperativeRatio != nil {
                    Divider()
                    QualityGauge(
                        lineCount: audit.quality.lineCount,
                        imperativeRatio: audit.quality.imperativeRatio,
                        lengthAssessment: audit.quality.lengthAssessment
                    )
                }

                // Hook compatibility
                if let hookCompat = audit.hookCompat, !hookCompat.missing.isEmpty {
                    Divider()
                    HookCompatBadge(hookCompat: hookCompat)
                }

                // Staleness warning
                if audit.staleness.stale {
                    HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(ForgeTheme.Colors.warning)
                            .accessibilityHidden(true)
                        Text("CLAUDE.md may be stale — \(audit.staleness.claudeMdDays) days since last update")
                            .font(ForgeTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(ForgeTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ForgeTheme.Colors.warning.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                    )
                }
            }
        }
        .staggeredReveal(index: 3)
    }

    // MARK: - Findings

    private func findingsSection(_ findings: [Finding]) -> some View {
        let visibleFindings = findings.filter { !dismissedFindings.contains($0.id) }
        let fixableCount = visibleFindings.filter(\.fixable).count
        let infoFindings = visibleFindings.filter { $0.severity == "info" }

        return ForgeCard("Findings (\(visibleFindings.count))", icon: "exclamationmark.bubble", content: {
            if visibleFindings.isEmpty {
                HStack(spacing: ForgeTheme.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(ForgeTheme.Colors.success)
                        .accessibilityHidden(true)
                    Text("No findings — looking good!")
                        .font(ForgeTheme.Typography.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, ForgeTheme.Spacing.xs)
            } else {
                VStack(alignment: .leading, spacing: ForgeTheme.Spacing.sm) {
                    // Bulk fix progress
                    if let bulk = coordinator?.bulkFixState {
                        BulkFixProgressView(state: bulk)
                    }

                    // Pending reviews indicator
                    if let coordinator, coordinator.isReviewing {
                        let remaining = coordinator.totalPendingReviews - coordinator.completedReviews
                        HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                            Image(systemName: "eye.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(ForgeTheme.Colors.info)
                                .accessibilityHidden(true)
                            Text("\(remaining) change\(remaining == 1 ? "" : "s") awaiting review")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(ForgeTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            ForgeTheme.Colors.info.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                        )
                    }

                    // Individual finding rows
                    VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xxs) {
                        ForEach(visibleFindings) { finding in
                            FindingRow(
                                finding: finding,
                                repoPath: repo.path,
                                claudeMdPath: repo.claudeMdAudit?.locations.first,
                                contentHashAtLoad: contentHashAtLoad,
                                fixDisabled: fixRunning || coordinator?.isRunning == true,
                                onFixed: { [finding] in
                                    let id = finding.id
                                    dismissalService.dismiss(repoPath: repo.path, findingId: id)
                                    forgeWithAnimation {
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
        }, trailing: {
            HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                if fixableCount >= 2 {
                    Button {
                        fixRunning = true
                        coordinator?.runBulkFix(
                            findings: visibleFindings.filter(\.fixable),
                            repoPath: repo.path,
                            claudeMdPath: repo.claudeMdAudit?.locations.first,
                            contentHashAtLoad: contentHashAtLoad,
                            onDismissed: { id in
                                dismissalService.dismiss(repoPath: repo.path, findingId: id)
                                forgeWithAnimation { _ = dismissedFindings.insert(id) }
                                claudeMdRefreshTrigger += 1
                            },
                            onContentChanged: { recomputeContentHash() },
                            onRefresh: {
                                fixRunning = false
                                await refreshRepoAudit()
                            }
                        )
                    } label: {
                        Label("Fix All (\(fixableCount))", systemImage: "wrench.and.screwdriver.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(fixRunning || coordinator?.isRunning == true)
                    .accessibilityLabel("Fix all \(fixableCount) fixable findings")
                }

                if !infoFindings.isEmpty {
                    Button {
                        dismissInfoFindings(infoFindings)
                    } label: {
                        Label("Dismiss Info (\(infoFindings.count))", systemImage: "eye.slash")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Dismiss \(infoFindings.count) informational findings")
                }
            }
        })
        .staggeredReveal(index: 4)
    }

    // MARK: - Bulk Operations

    private func dismissInfoFindings(_ findings: [Finding]) {
        let ids = findings.map(\.id)
        dismissalService.dismissAll(repoPath: repo.path, findingIds: ids)
        forgeWithAnimation {
            for id in ids {
                dismissedFindings.insert(id)
            }
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

// MARK: - Staggered Reveal

/// Gentle one-time entrance for detail cards. Fires only when the view first joins
/// the hierarchy (not on repo re-selection — view identity persists), and the total
/// stagger is capped by `Animations.staggerBudget` so it never reads theatrical.
private struct StaggeredRevealModifier: ViewModifier {
    let index: Int
    @State private var revealed = false

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .onAppear {
                let delay = min(
                    Double(index) * ForgeTheme.Animations.staggerDelay,
                    ForgeTheme.Animations.staggerBudget
                )
                forgeWithAnimation(ForgeTheme.Animations.easeReveal.delay(delay)) {
                    revealed = true
                }
            }
    }
}

extension View {
    fileprivate func staggeredReveal(index: Int) -> some View {
        modifier(StaggeredRevealModifier(index: index))
    }
}
