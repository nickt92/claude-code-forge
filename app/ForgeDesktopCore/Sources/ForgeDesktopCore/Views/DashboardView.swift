import SwiftUI

public struct DashboardView: View {
    @Bindable var state: ForgeState
    let onRefresh: () -> Void
    @State private var searchText = ""
    @State private var selectedRepo: RepoData?
    @State private var showDoctor = false
    @State private var showPersonaSwitcher = false
    @State private var showNewProject = false
    @AppStorage("sidebarSort") private var sortOrder: String = "name"
    @State private var activeFilters: Set<SidebarFilter> = []

    public init(state: ForgeState, onRefresh: @escaping () -> Void) {
        self.state = state
        self.onRefresh = onRefresh
    }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let repo = selectedRepo {
                RepoDetailView(repo: repo)
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "folder",
                    description: Text("Choose a repository from the sidebar.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Filter repositories")
        .navigationTitle("Forge Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewProject = true } label: {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
                .help("New Project...")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { onRefresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.isLoading)
                .help("Refresh (⌘R)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showDoctor = true } label: {
                    Label("Doctor", systemImage: "stethoscope")
                }
                .help("Run Forge Doctor")
            }
        }
        .sheet(isPresented: $showDoctor) {
            DoctorView(state: state)
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
        switch state.loadState {
        case .idle:
            ContentUnavailableView("No Data", systemImage: "tray", description: Text("Press ⌘R to load."))
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning repositories...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let data):
            loadedSidebar(data)
        case .failed(let error):
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Retry") { onRefresh() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func loadedSidebar(_ data: DashboardData) -> some View {
        List(selection: $selectedRepo) {
            Section {
                GlobalHealthCard(data: data, onPersonaTap: { showPersonaSwitcher = true })
            }

            Section {
                HStack(spacing: 6) {
                    Picker("Sort", selection: $sortOrder) {
                        Text("Name (A-Z)").tag("name")
                        Text("Score (Low)").tag("score_asc")
                        Text("Score (High)").tag("score_desc")
                        Text("Findings").tag("findings")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }

                FlowLayout(spacing: 4) {
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
            }

            Section("Repositories (\(sortedAndFilteredRepos(data).count))") {
                ForEach(sortedAndFilteredRepos(data)) { repo in
                    RepoRow(repo: repo)
                        .tag(repo)
                }
            }
        }
        .listStyle(.sidebar)
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
    var onPersonaTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ScoreRing(score: data.globalScore.total, grade: data.globalScore.grade, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Button { onPersonaTap?() } label: {
                        HStack(spacing: 4) {
                            Text(data.global.persona.label)
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 4) {
                        Text("v\(data.global.install.forgeVersion)")
                        Text("·")
                        Text("\(data.global.plugins.group) plugins")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }

            DimensionBars(dimensions: data.globalScore.dimensions)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Repo Row

struct RepoRow: View {
    let repo: RepoData

    var body: some View {
        HStack(spacing: 10) {
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
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if repo.git.isRepo, !repo.git.branch.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text(repo.git.branch)
                                .lineLimit(1)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }

                    if let audit = repo.claudeMdAudit {
                        let errorCount = audit.findings.filter { $0.severity == "error" }.count
                        let warnCount = audit.findings.filter { $0.severity == "warn" }.count
                        if errorCount > 0 {
                            CountBadge(count: errorCount, color: .red)
                        }
                        if warnCount > 0 {
                            CountBadge(count: warnCount, color: .orange)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Count Badge

struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Dimension Bars

struct DimensionBars: View {
    let dimensions: [String: DimensionScore]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sortedDimensions, id: \.key) { key, dim in
                HStack(spacing: 6) {
                    Text(formatDimensionName(key))
                        .font(.system(size: 10))
                        .frame(width: 100, alignment: .trailing)
                        .foregroundStyle(.secondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
                            Capsule()
                                .fill(scoreColor(dim.score).gradient)
                                .frame(width: max(0, geo.size.width * CGFloat(dim.score) / 100))
                        }
                    }
                    .frame(height: 6)

                    Text("\(dim.score)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .frame(width: 24, alignment: .trailing)
                        .foregroundStyle(scoreColor(dim.score))
                }
            }
        }
    }

    private var sortedDimensions: [(key: String, value: DimensionScore)] {
        dimensions.sorted { $0.value.weight > $1.value.weight }
    }

    private func formatDimensionName(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
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
        Button(action: onToggle) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RepoData Hashable

extension RepoData: Hashable {
    public static func == (lhs: RepoData, rhs: RepoData) -> Bool {
        lhs.path == rhs.path
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
