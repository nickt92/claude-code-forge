import SwiftUI

public struct RepoDetailView: View {
    let repo: RepoData

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
                configSection
                if let audit = repo.claudeMdAudit {
                    auditSection(audit)
                    findingsSection(audit.findings)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(repo.name)
        .frame(minWidth: 450)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            if let score = repo.score {
                ScoreRing(score: score.total, grade: score.grade, size: 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(repo.name)
                    .font(.title2)
                    .fontWeight(.bold)
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
            Spacer()
        }
    }

    // MARK: - Score

    private func scoreSection(_ score: ScoreData) -> some View {
        DetailCard("Score Breakdown") {
            DimensionBars(dimensions: score.dimensions)
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
        DetailCard("Findings (\(findings.count))") {
            if findings.isEmpty {
                Text("No findings — looking good!")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(findings) { finding in
                        FindingRow(finding: finding)
                    }
                }
            }
        }
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

    var body: some View {
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
                        Text("FIXABLE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(severityColor(finding.severity).opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
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
