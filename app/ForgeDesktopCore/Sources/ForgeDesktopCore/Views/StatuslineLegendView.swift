import SwiftUI

public struct StatuslineLegendView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    exampleStatusline
                    zoneGit
                    zoneModel
                    zoneContext
                    zoneLimits
                    zoneSession
                    colorKey
                }
                .padding(20)
            }
        }
        .frame(width: 560)
        .frame(minHeight: 480, maxHeight: 700)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Statusline Guide")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Example Statusline

    private var exampleStatusline: some View {
        HStack(spacing: 6) {
            Text("🌿 feat/thing")
                .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 0.55))
            Text("✦3")
                .foregroundStyle(.orange)
            Text("↑2")
                .foregroundStyle(.cyan)
            separator
            modelBadge("Opus", color: Color(red: 0.6, green: 0.2, blue: 0.5))
            separator
            Text("◈")
                .foregroundStyle(.blue)
            gradientBar
            Text("62%")
                .fontWeight(.bold)
                .foregroundStyle(.cyan)
            separator
            Text("🔋 48%")
                .foregroundStyle(.green)
            separator
            Text("💰 $2.87")
                .foregroundStyle(Color(red: 0.8, green: 0.65, blue: 0.35))
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var separator: some View {
        Text("║")
            .foregroundStyle(.gray.opacity(0.4))
    }

    private func modelBadge(_ name: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("🧠")
            Text(name)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color, in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(.white)
    }

    private var gradientBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<20, id: \.self) { i in
                Rectangle()
                    .fill(barColor(at: i, filled: 12))
                    .frame(width: 4, height: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func barColor(at index: Int, filled: Int) -> Color {
        guard index < filled else {
            return Color.gray.opacity(0.2)
        }
        let pct = Double(index) / 20.0
        if pct < 0.4 { return .blue }
        if pct < 0.7 { return .cyan }
        if pct < 0.9 { return .orange }
        return .red
    }

    // MARK: - Zone Sections

    private var zoneGit: some View {
        zoneSection("Zone 1: Git", icon: "arrow.triangle.branch") {
            iconRow("🌿", label: "Branch name", desc: "Current git branch (green = feature)")
            iconRow("🌲", label: "Worktree branch", desc: "Pink when in a git worktree")
            iconRow("📂", label: "Working directory", desc: "Shown when not in a git repo")
            iconRow("✦N", label: "Uncommitted changes", desc: "Staged + unstaged count")
            iconRow("↑N", label: "Commits ahead", desc: "Local commits not yet pushed")
            iconRow("↓N", label: "Commits behind", desc: "Remote commits not yet pulled")
            iconRow("📦N", label: "Stash count", desc: "Git stash entries")
            iconRow("REBASING", label: "Active git state", desc: "Also MERGING, CHERRY-PICK")
        }
    }

    private var zoneModel: some View {
        zoneSection("Zone 2: Model + Agent", icon: "brain") {
            HStack(spacing: 8) {
                modelBadge("Opus", color: Color(red: 0.6, green: 0.2, blue: 0.5))
                    .font(.system(size: 11, design: .monospaced))
                modelBadge("Sonnet", color: Color(red: 0.1, green: 0.2, blue: 0.5))
                    .font(.system(size: 11, design: .monospaced))
                modelBadge("Haiku", color: Color(red: 0.1, green: 0.35, blue: 0.4))
                    .font(.system(size: 11, design: .monospaced))
            }
            .padding(.bottom, 4)
            iconRow("⬆ high", label: "Effort level", desc: "Reasoning depth: high / med / low")
            iconRow("🤖 name", label: "Active subagent", desc: "Shown during agent delegation")
        }
    }

    private var zoneContext: some View {
        zoneSection("Zone 3: Context Window", icon: "gauge.with.dots.needle.33percent") {
            iconRow("◈", label: "Context section", desc: "Marker for context zone")
            HStack(spacing: 8) {
                gradientBar
                Text("Gradient bar")
                    .font(.system(size: 12, weight: .medium))
                Text("— blue → cyan → amber → red as usage increases")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            iconRow("62%", label: "Context used", desc: "Bold, color matches bar edge")
            iconRow("💾 46%", label: "Cache hit ratio", desc: "Higher = faster responses")
            iconRow("⚠ 200k+", label: "Context warning", desc: "Shown when exceeding 200k tokens")
        }
    }

    private var zoneLimits: some View {
        zoneSection("Zone 4: Limits + Speed", icon: "battery.75percent") {
            iconRow("🔋 N%", label: "5-hour rate limit", desc: "Green <50%, yellow 50-80%, red 80%+")
            iconRow("📅 7d N%", label: "7-day rate limit", desc: "Max plan usage, shown when ≥50%")
            iconRow("⚡ Nt/s", label: "Token speed", desc: "Generation throughput")
        }
    }

    private var zoneSession: some View {
        zoneSection("Zone 5: Session", icon: "clock") {
            iconRow("📝 name", label: "Session name", desc: "From /rename or --name")
            iconRow("💰 $N.NN", label: "Session cost", desc: "Accumulated API cost")
            iconRow("✏️ +N/−N", label: "Lines changed", desc: "Green for added, red for removed")
            iconRow("⏱️ Nm", label: "Session duration", desc: "Elapsed time")
            iconRow("◆ INS", label: "Vim mode", desc: "INS/VIS/NOR/REP when active")
        }
    }

    // MARK: - Color Key

    private var colorKey: some View {
        zoneSection("Colors", icon: "paintpalette") {
            colorRow(.green, label: "Green", desc: "All clear / low usage")
            colorRow(.yellow, label: "Yellow", desc: "Moderate / attention")
            colorRow(.red, label: "Red", desc: "High / critical")
            HStack(spacing: 8) {
                Text("Bold")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 80, alignment: .leading)
                Text("Important values (context %, model name)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Reusable Components

    private func zoneSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.5)
            }
        }
    }

    private func iconRow(_ icon: String, label: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 80, alignment: .leading)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 140, alignment: .leading)
            Text("— \(desc)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func colorRow(_ color: Color, label: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 72, alignment: .leading)
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
