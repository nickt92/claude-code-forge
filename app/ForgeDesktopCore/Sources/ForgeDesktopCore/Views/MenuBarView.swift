import SwiftUI

public struct MenuBarView: View {
    @Bindable var state: ForgeState
    let onRefresh: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenSettings: () -> Void

    public init(
        state: ForgeState,
        onRefresh: @escaping () -> Void,
        onOpenDashboard: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.state = state
        self.onRefresh = onRefresh
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state.loadState {
            case .idle:
                idleView
            case .loading:
                loadingView
            case .loaded(let data):
                loadedView(data)
            case .failed(let error):
                errorView(error)
            }

            Divider()
                .padding(.vertical, 8)

            HStack(spacing: 6) {
                Button { onOpenDashboard() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 11))
                        Text("Dashboard")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.small)

                Button { onRefresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.isLoading)

                Button { onOpenSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Click refresh to load")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text("Scanning repositories...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func loadedView(_ data: DashboardData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with score
            HStack(spacing: 12) {
                ScoreRing(score: data.globalScore.total, grade: data.globalScore.grade, size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Forge Health")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(data.repos.count) repos · v\(data.global.install.forgeVersion)")
                        .font(.system(size: 11))
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
                .filter { ($0.score?.total ?? 100) < 100 }

            if !needsAttention.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEEDS ATTENTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    ForEach(Array(needsAttention)) { repo in
                        HStack(spacing: 8) {
                            if let score = repo.score {
                                ScoreRing(score: score.total, grade: score.grade, size: 22)
                            }
                            Text(repo.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            if let audit = repo.claudeMdAudit {
                                let warnCount = audit.findings.filter { $0.severity == "warn" || $0.severity == "error" }.count
                                if warnCount > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 8))
                                        Text("\(warnCount)")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func errorView(_ error: ForgeError) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Score Ring

public struct ScoreRing: View {
    let score: Int
    let grade: String
    let size: CGFloat

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
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(gradeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(grade)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(gradeColor)
        }
        .frame(width: size, height: size)
    }

    private var lineWidth: CGFloat { size > 30 ? 4 : 2.5 }
    private var fontSize: CGFloat { size > 30 ? size * 0.38 : size * 0.42 }

    private var gradeColor: Color {
        scoreColor(score)
    }
}

// MARK: - Color Helpers

func scoreColor(_ score: Int) -> Color {
    switch score {
    case 90...100: return .green
    case 70..<90: return .yellow
    case 50..<70: return .orange
    default: return .red
    }
}

func severityColor(_ severity: String) -> Color {
    switch severity {
    case "error": return .red
    case "warn": return .orange
    case "info": return .blue
    default: return .secondary
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
