import SwiftUI

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
    @State private var fixTask: Task<Void, Never>?

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

    /// Case discriminator so fix-state changes can drive animations without
    /// FixState being Equatable.
    private var fixPhase: String {
        switch fixState {
        case .idle: "idle"
        case .running: "running"
        case .pendingReview: "pendingReview"
        case .success: "success"
        case .failed: "failed"
        case .claudeDidNotModify: "claudeDidNotModify"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: ForgeTheme.Spacing.sm + 2) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(severityColor(finding.severity))
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(severityColor(finding.severity))
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 2)
                    .accessibilityLabel(severityLabel)

                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.detail)
                        .font(.system(size: 12))
                    HStack(spacing: 6) {
                        Text(finding.code.formattedAsTitle)
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
                        .padding(ForgeTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            .quaternary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.chipRadius)
                        )
                }
            }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, ForgeTheme.Spacing.sm)
        .forgeHoverHighlight()
        .forgeAnimation(.easeInOut(duration: 0.2), value: fixActivities.count)
        .forgeAnimation(ForgeTheme.Animations.springSnappy, value: fixPhase)
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
        .onDisappear { fixTask?.cancel() }
    }

    @ViewBuilder
    private var fixButton: some View {
        Group {
            switch fixState {
            case .idle:
                if usesClaudeFix && !fixService.claudeAvailable {
                    StatusBadge("Fix", icon: "wrench.and.screwdriver.fill", tint: .secondary)
                        .help("Requires Claude Code CLI to generate intelligent fixes")
                } else {
                    Button {
                        showConfirm = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: usesClaudeFix ? "sparkles" : "wrench.and.screwdriver.fill")
                                .font(.system(size: 9))
                                .accessibilityHidden(true)
                            Text("Fix")
                        }
                    }
                    .buttonStyle(.forgePill(tint: ForgeTheme.Colors.forgeText))
                    .disabled(fixDisabled)
                    .accessibilityLabel("Fix this finding")
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
                StatusBadge("Reviewing...", icon: "eye.fill", tint: ForgeTheme.Colors.info)
            case .success:
                StatusBadge(
                    usesClaudeFix ? "Section added" : "Fixed",
                    icon: "checkmark.circle.fill",
                    tint: ForgeTheme.Colors.success
                )
            case .claudeDidNotModify(_, let cost):
                Button {
                    showClaudeResponse.toggle()
                } label: {
                    StatusBadge(
                        cost > 0 ? "No changes needed" : "Not processed",
                        icon: cost > 0 ? "info.circle.fill" : "exclamationmark.circle.fill",
                        tint: cost > 0 ? ForgeTheme.Colors.warning : ForgeTheme.Colors.danger
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showClaudeResponse ? "Hide Claude's response" : "Show Claude's response")
            case .failed(let message):
                StatusBadge(message, icon: "xmark.circle.fill", tint: ForgeTheme.Colors.danger)
                    .lineLimit(1)
            }
        }
        .contentTransition(.opacity)
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

        fixTask = Task {
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

    private var severityLabel: String {
        switch finding.severity {
        case "error": return "Error"
        case "warn": return "Warning"
        default: return "Info"
        }
    }
}
