import SwiftUI

public struct MenuBarView: View {
    @Bindable var state: ForgeState
    let onRefresh: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenSettings: () -> Void
    let onRunDoctor: () -> Void
    let onSelectRepo: (String) -> Void

    public init(
        state: ForgeState,
        onRefresh: @escaping () -> Void,
        onOpenDashboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onRunDoctor: @escaping () -> Void = {},
        onSelectRepo: @escaping (String) -> Void = { _ in }
    ) {
        self.state = state
        self.onRefresh = onRefresh
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
        self.onRunDoctor = onRunDoctor
        self.onSelectRepo = onSelectRepo
    }

    private var loadPhase: String {
        switch state.loadState {
        case .idle: "idle"
        case .loading: "loading"
        case .loaded: "loaded"
        case .failed: "failed"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch state.loadState {
                case .idle:
                    idleView.transition(.opacity)
                case .loading:
                    loadingView.transition(.opacity)
                case .loaded(let data):
                    loadedView(data).transition(.opacity)
                case .failed(let error):
                    errorView(error).transition(.opacity)
                }
            }
            .forgeAnimation(ForgeTheme.Animations.easeReveal, value: loadPhase)

            Divider()
                .padding(.vertical, ForgeTheme.Spacing.sm)

            HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                Button { onOpenDashboard() } label: {
                    HStack(spacing: ForgeTheme.Spacing.xs) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 11))
                        Text("Dashboard")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Open dashboard")

                Button { onRunDoctor() } label: {
                    Image(systemName: "stethoscope")
                }
                .buttonStyle(.forgeIcon)
                .help("Run Doctor")
                .accessibilityLabel("Run doctor")

                Button { onRefresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.forgeIcon)
                .disabled(state.isBusy)
                .help("Refresh")
                .accessibilityLabel("Refresh repositories")

                Button { onOpenSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.forgeIcon)
                .help("Settings")
                .accessibilityLabel("Open settings")
            }
        }
        .padding(ForgeTheme.Spacing.lg - 2)
        .frame(width: 320)
    }

    // MARK: - States

    private var idleView: some View {
        ForgeEmptyState(
            icon: "hammer.fill",
            title: "Forge",
            message: "Click refresh to scan your repositories."
        )
        .padding(.vertical, -ForgeTheme.Spacing.sm)
    }

    private var loadingView: some View {
        SkeletonGroup {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.md) {
                HStack(spacing: ForgeTheme.Spacing.md) {
                    SkeletonCircle(diameter: 52)
                    VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
                        SkeletonBox(width: 100, height: 12)
                        SkeletonBox(width: 140, height: 10)
                    }
                    Spacer()
                }
                SkeletonRepoRow()
                SkeletonRepoRow()
            }
            .padding(.vertical, ForgeTheme.Spacing.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanning repositories")
    }

    private func loadedView(_ data: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.md) {
            // Header with score
            HStack(spacing: ForgeTheme.Spacing.md) {
                ScoreRing(score: data.globalScore.total, grade: data.globalScore.grade, size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Forge Health")
                        .font(ForgeTheme.Typography.rowTitle)
                    Text("\(data.repos.count) repos · v\(data.global.install.forgeVersion)")
                        .font(ForgeTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text(data.global.persona.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            // Repos needing attention
            let needsAttention = data.repos
                .sorted { ($0.score?.total ?? 0) < ($1.score?.total ?? 0) }
                .prefix(3)
                .filter { ($0.score?.total ?? 100) < 80 }

            if !needsAttention.isEmpty {
                VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs + 2) {
                    Text("NEEDS ATTENTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    ForEach(Array(needsAttention.enumerated()), id: \.element.id) { index, repo in
                        Button {
                            onSelectRepo(repo.path)
                        } label: {
                            HStack(spacing: ForgeTheme.Spacing.sm) {
                                if let score = repo.score {
                                    ScoreRing(score: score.total, grade: score.grade, size: 22)
                                }
                                Text(repo.name)
                                    .font(ForgeTheme.Typography.body)
                                    .lineLimit(1)
                                Spacer()
                                if let audit = repo.claudeMdAudit {
                                    let warnCount = audit.findings.filter { $0.severity == "warn" || $0.severity == "error" }.count
                                    if warnCount > 0 {
                                        HStack(spacing: ForgeTheme.Spacing.xxs) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 8))
                                                .accessibilityHidden(true)
                                            Text("\(warnCount)")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .foregroundStyle(ForgeTheme.Colors.forgeText)
                                    }
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, ForgeTheme.Spacing.xs)
                            .padding(.horizontal, ForgeTheme.Spacing.xs + 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .forgeHoverHighlight(radius: ForgeTheme.Metrics.chipRadius)
                        .accessibilityLabel("Open \(repo.name) in dashboard")
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .forgeAnimation(
                            ForgeTheme.Animations.easeReveal.delay(
                                min(Double(index) * ForgeTheme.Animations.staggerDelay, ForgeTheme.Animations.staggerBudget)
                            ),
                            value: needsAttention.count
                        )
                    }
                }
                .padding(ForgeTheme.Spacing.sm)
                .background(
                    .quaternary.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius)
                )
            }
        }
    }

    private func errorView(_ error: ForgeError) -> some View {
        ForgeEmptyState(
            icon: "exclamationmark.triangle",
            title: "Couldn't Load",
            message: error.localizedDescription
        ) {
            Button("Retry") { onRefresh() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, -ForgeTheme.Spacing.sm)
    }
}

// MARK: - Score Ring

public struct ScoreRing: View {
    let score: Int
    let grade: String
    let size: CGFloat

    @State private var animatedProgress: CGFloat = 0

    public init(score: Int, grade: String, size: CGFloat) {
        self.score = score
        self.grade = grade
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(gradeColor.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(gradeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(grade)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(gradeColor)
        }
        .frame(width: size, height: size)
        .onAppear {
            forgeWithAnimation(ForgeTheme.Animations.springBouncy) {
                animatedProgress = CGFloat(score) / 100
            }
        }
        .onChange(of: score) { _, newValue in
            forgeWithAnimation(ForgeTheme.Animations.springBouncy) {
                animatedProgress = CGFloat(newValue) / 100
            }
        }
        .accessibilityLabel("Score \(score) out of 100, grade \(grade)")
    }

    private var lineWidth: CGFloat { size > 30 ? 4 : 2.5 }
    private var fontSize: CGFloat { size > 30 ? size * 0.38 : size * 0.42 }

    private var gradeColor: Color {
        scoreColor(score)
    }
}

@MainActor
public func menuBarIconColor(for state: ForgeState) -> Color {
    switch state.loadState {
    case .idle, .loading:
        return .secondary
    case .loaded(let data):
        return scoreColor(data.globalScore.total)
    case .failed:
        return .red
    }
}
