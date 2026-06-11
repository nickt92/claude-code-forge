import SwiftUI

public struct DashboardView: View {
    @Bindable var state: ForgeState
    let onRefresh: () -> Void
    @State private var searchText = ""
    @State private var showPersonaSwitcher = false
    @State private var showNewProject = false
    @State private var showTelemetry = false
    @AppStorage("sidebarSort") private var sortOrder: String = "name"
    @State private var activeFilters: Set<SidebarFilter> = []
    @Environment(\.openSettings) private var openSettings

    public init(state: ForgeState, onRefresh: @escaping () -> Void) {
        self.state = state
        self.onRefresh = onRefresh
    }

    /// Case discriminator so load-state swaps can be keyed for transitions
    /// without requiring DashboardData/Error to be Equatable.
    private var loadPhase: String {
        switch state.loadState {
        case .idle: "idle"
        case .loading: "loading"
        case .loaded: "loaded"
        case .failed: "failed"
        }
    }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let repo = state.selectedRepo {
                RepoDetailView(repo: repo, onDashboardRefresh: onRefresh)
            } else {
                ForgeEmptyState(
                    icon: "folder",
                    title: "Select a Repository",
                    message: "Choose a repository from the sidebar to see its health, audit findings, and fixes."
                )
            }
        }
        .searchable(text: $searchText, prompt: "Filter repositories")
        .navigationTitle("Forge")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewProject = true } label: {
                    Label("New Project", systemImage: "folder.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
                .help("Create a new project with Claude-generated CLAUDE.md")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { onRefresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.isBusy)
                .help("Rescan all repositories (⌘R)")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { state.showDoctor = true } label: {
                        Label("Doctor", systemImage: "stethoscope")
                    }
                    Button { openSettings() } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.titleAndIcon)
                }
                .help("Doctor, Settings, and more")
            }
        }
        .sheet(isPresented: $state.showDoctor) {
            DoctorView(state: state)
        }
        .sheet(isPresented: $showTelemetry) {
            TelemetryView()
        }
        .sheet(isPresented: $showPersonaSwitcher) {
            if let dashboard = state.dashboard {
                PersonaSwitcherView(
                    currentPersona: dashboard.global.persona.persona,
                    onSwitched: { onRefresh() }
                )
            }
        }
        .sheet(isPresented: $showNewProject) {
            if let dashboard = state.dashboard {
                OnboardingView(
                    mode: .greenfield(projectPath: "", projectName: "", description: ""),
                    persona: dashboard.global.persona,
                    onComplete: { onRefresh() }
                )
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        Group {
            switch state.loadState {
            case .idle:
                ForgeEmptyState(
                    icon: "tray",
                    title: "No Data",
                    message: "Press ⌘R to scan your repositories."
                )
                .transition(.opacity)
            case .loading:
                loadingSidebar
                    .transition(.opacity)
            case .loaded(let data):
                loadedSidebar(data)
                    .transition(.opacity)
            case .failed(let error):
                ForgeEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Couldn't Load Dashboard",
                    message: error.localizedDescription
                ) {
                    Button("Retry") { onRefresh() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .transition(.opacity)
            }
        }
        .forgeAnimation(ForgeTheme.Animations.easeReveal, value: loadPhase)
    }

    private var loadingSidebar: some View {
        SkeletonGroup {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.md) {
                SkeletonHealthCard()
                VStack(spacing: ForgeTheme.Spacing.xs) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonRepoRow()
                    }
                }
                .padding(.horizontal, ForgeTheme.Spacing.xs)
                Spacer()
            }
            .padding(.horizontal, ForgeTheme.Spacing.md)
            .padding(.top, ForgeTheme.Spacing.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanning repositories")
    }

    @ViewBuilder
    private func loadedSidebar(_ data: DashboardData) -> some View {
        if data.repos.isEmpty {
            VStack(spacing: ForgeTheme.Spacing.lg) {
                GlobalHealthCard(
                    data: data,
                    onPersonaTap: { showPersonaSwitcher = true },
                    onTelemetryTap: { showTelemetry = true }
                )
                .padding(.horizontal, ForgeTheme.Spacing.md)
                .padding(.top, ForgeTheme.Spacing.sm)

                ForgeEmptyState(
                    icon: "folder.badge.questionmark",
                    title: "No Repositories Found",
                    message: "Set a scan path in Settings so Forge knows where to find your projects."
                ) {
                    HStack(spacing: ForgeTheme.Spacing.sm) {
                        Button("Open Settings") { openSettings() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Refresh") { onRefresh() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        } else {
            let filteredRepos = sortedAndFilteredRepos(data)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: ForgeTheme.Spacing.sm) {
                    GlobalHealthCard(
                        data: data,
                        updateReady: state.forgeStatus?.reinstallPending == true,
                        onPersonaTap: { showPersonaSwitcher = true },
                        onTelemetryTap: { showTelemetry = true },
                        onUpdateTap: { openSettings() }
                    )
                    controlsRow
                    if let refreshError = state.refreshError {
                        HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 10))
                                .foregroundStyle(ForgeTheme.Colors.warning)
                                .accessibilityHidden(true)
                            Text("Refresh failed — showing last results")
                                .font(ForgeTheme.Typography.micro)
                                .foregroundStyle(.secondary)
                                .help(refreshError)
                        }
                        .padding(.horizontal, ForgeTheme.Spacing.sm)
                        .padding(.vertical, ForgeTheme.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            ForgeTheme.Colors.warning.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.chipRadius)
                        )
                    }
                }
                .padding(.horizontal, ForgeTheme.Spacing.md)
                .padding(.top, ForgeTheme.Spacing.sm)
                .padding(.bottom, ForgeTheme.Spacing.xs)

                List(selection: $state.selectedRepoPath) {
                    Section("Repositories (\(filteredRepos.count))") {
                        ForEach(filteredRepos) { repo in
                            RepoRow(repo: repo)
                                .tag(repo.path)
                        }
                    }
                }
                .listStyle(.sidebar)
                .forgeAnimation(
                    ForgeTheme.Animations.springSnappy,
                    value: filteredRepos.map(\.path)
                )
            }
        }
    }

    private var controlsRow: some View {
        HStack(alignment: .center, spacing: ForgeTheme.Spacing.sm) {
            FlowLayout(spacing: ForgeTheme.Spacing.xs) {
                ForEach(SidebarFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        label: filter.label,
                        isActive: activeFilters.contains(filter),
                        onToggle: {
                            if activeFilters.contains(filter) {
                                activeFilters.remove(filter)
                            } else {
                                activeFilters.insert(filter)
                            }
                        }
                    )
                }
            }

            Spacer(minLength: ForgeTheme.Spacing.xs)

            if state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .help("Refreshing repositories…")
                    .accessibilityLabel("Refreshing repositories")
                    .transition(.opacity)
            }

            Picker("Sort", selection: $sortOrder) {
                Text("Name (A-Z)").tag("name")
                Text("Score (Low)").tag("score_asc")
                Text("Score (High)").tag("score_desc")
                Text("Findings").tag("findings")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Sort repositories")
            .accessibilityLabel("Sort repositories")
        }
    }

    private func sortedAndFilteredRepos(_ data: DashboardData) -> [RepoData] {
        var repos = data.repos

        // Text search
        if !searchText.isEmpty {
            repos = repos.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Filters
        for filter in activeFilters {
            repos = repos.filter { filter.matches($0) }
        }

        // Sort
        switch sortOrder {
        case "score_asc":
            repos.sort { ($0.score?.total ?? 0) < ($1.score?.total ?? 0) }
        case "score_desc":
            repos.sort { ($0.score?.total ?? 0) > ($1.score?.total ?? 0) }
        case "findings":
            repos.sort { ($0.claudeMdAudit?.findings.count ?? 0) > ($1.claudeMdAudit?.findings.count ?? 0) }
        default:
            repos.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return repos
    }
}

// MARK: - Global Health Card

struct GlobalHealthCard: View {
    let data: DashboardData
    var updateReady: Bool = false
    var onPersonaTap: (() -> Void)?
    var onTelemetryTap: (() -> Void)?
    var onUpdateTap: (() -> Void)?

    @State private var personaHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.md) {
            HStack(alignment: .top, spacing: ForgeTheme.Spacing.md) {
                ScoreRing(score: data.globalScore.total, grade: data.globalScore.grade, size: 56)

                VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xxs) {
                    Button { onPersonaTap?() } label: {
                        HStack(spacing: ForgeTheme.Spacing.xs) {
                            Text(data.global.persona.label)
                                .font(ForgeTheme.Typography.rowTitle)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(personaHovered ? Color.secondary : Color(nsColor: .tertiaryLabelColor))
                                .offset(x: personaHovered ? 2 : 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { personaHovered = $0 }
                    .onDisappear { personaHovered = false }
                    .forgeAnimation(ForgeTheme.Animations.springSnappy, value: personaHovered)
                    .help("Switch persona")
                    .accessibilityLabel("Switch persona. Current: \(data.global.persona.label)")

                    HStack(spacing: ForgeTheme.Spacing.xs) {
                        Text("v\(data.global.install.forgeVersion)")
                        Text("·")
                        Text("\(data.global.plugins.group) plugins")
                    }
                    .font(ForgeTheme.Typography.caption)
                    .foregroundStyle(.secondary)

                    if updateReady {
                        Button { onUpdateTap?() } label: {
                            StatusBadge(
                                "Update ready to install",
                                icon: "arrow.down.circle",
                                tint: ForgeTheme.Colors.info
                            )
                        }
                        .buttonStyle(.plain)
                        .help("A newer forge version is in your source repo — install it from Settings")
                        .accessibilityLabel("Forge update ready to install. Open settings.")
                        .padding(.top, ForgeTheme.Spacing.xxs)
                    }
                }

                Spacer(minLength: 0)

                if onTelemetryTap != nil {
                    Button { onTelemetryTap?() } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                    .buttonStyle(.forgeIcon)
                    .help("Hook Telemetry")
                    .accessibilityLabel("Hook telemetry")
                }
            }

            DimensionBars(dimensions: data.globalScore.dimensions)
        }
        .padding(ForgeTheme.Spacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
                    .fill(ForgeTheme.Colors.surface)
                RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
                    .fill(ForgeTheme.Gradients.subtleBg)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius)
                .stroke(.quaternary)
        )
        .forgeShadow(ForgeTheme.Elevation.card)
    }
}

// MARK: - Repo Row

struct RepoRow: View {
    let repo: RepoData

    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.sm + 2) {
            if let score = repo.score {
                ScoreRing(score: score.total, grade: score.grade, size: 28)
            } else {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text("?")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Not scored")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: ForgeTheme.Spacing.xs + 2) {
                    if repo.git.isRepo, !repo.git.branch.isEmpty {
                        HStack(spacing: ForgeTheme.Spacing.xxs) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                                .accessibilityHidden(true)
                            Text(repo.git.branch)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }

                    if let audit = repo.claudeMdAudit {
                        let errorCount = audit.findings.filter { $0.severity == "error" }.count
                        let warnCount = audit.findings.filter { $0.severity == "warn" }.count
                        if errorCount > 0 {
                            StatusBadge("\(errorCount)", tint: ForgeTheme.Colors.danger)
                                .accessibilityLabel("\(errorCount) errors")
                        }
                        if warnCount > 0 {
                            StatusBadge("\(warnCount)", tint: ForgeTheme.Colors.warning)
                                .accessibilityLabel("\(warnCount) warnings")
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Dimension Bars

struct DimensionBars: View {
    let dimensions: [String: DimensionScore]

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.xs) {
            ForEach(Array(sortedDimensions.enumerated()), id: \.element.key) { index, entry in
                DimensionBarRow(key: entry.key, dim: entry.value, index: index)
            }
        }
    }

    private var sortedDimensions: [(key: String, value: DimensionScore)] {
        dimensions.sorted { $0.value.weight > $1.value.weight }
    }
}

// MARK: - Dimension Bar Row

private struct DimensionBarRow: View {
    let key: String
    let dim: DimensionScore
    let index: Int

    @State private var barWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.xs + 2) {
            Text(key.formattedAsTitle)
                .font(.system(size: 10))
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(scoreColor(dim.score).gradient)
                        .frame(width: max(0, barWidth * geo.size.width))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            .onAppear {
                let delay = min(
                    Double(index) * ForgeTheme.Animations.staggerDelay,
                    ForgeTheme.Animations.staggerBudget
                )
                forgeWithAnimation(ForgeTheme.Animations.springSnappy.delay(delay)) {
                    barWidth = CGFloat(dim.score) / 100
                }
            }
            .onChange(of: dim.score) { _, newValue in
                forgeWithAnimation(ForgeTheme.Animations.springSnappy) {
                    barWidth = CGFloat(newValue) / 100
                }
            }

            Text("\(dim.score)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(scoreColor(dim.score))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.formattedAsTitle): \(dim.score) out of 100")
    }
}

// MARK: - Sidebar Filter

public enum SidebarFilter: String, CaseIterable, Sendable {
    case needsAttention
    case hasErrors
    case missingClaudeMd

    var label: String {
        switch self {
        case .needsAttention: return "Needs Attention"
        case .hasErrors: return "Has Errors"
        case .missingClaudeMd: return "Missing CLAUDE.md"
        }
    }

    func matches(_ repo: RepoData) -> Bool {
        switch self {
        case .needsAttention:
            return (repo.score?.total ?? 100) < 80
        case .hasErrors:
            return (repo.claudeMdAudit?.findings.filter { $0.severity == "error" }.count ?? 0) > 0
        case .missingClaudeMd:
            return !repo.claudeMd.exists
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(label, action: onToggle)
            .buttonStyle(.forgePill(tint: ForgeTheme.Colors.forgeText, isActive: isActive))
            .accessibilityLabel("\(label) filter")
            .accessibilityValue(isActive ? "on" : "off")
    }
}

// MARK: - RepoData Hashable

extension RepoData: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
