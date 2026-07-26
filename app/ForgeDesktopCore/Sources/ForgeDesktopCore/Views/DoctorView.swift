import SwiftUI

public struct DoctorView: View {
    @Bindable var state: ForgeState
    @Environment(\.doctorService) private var doctorService
    @Environment(\.dismiss) private var dismiss
    @State private var doctorError: String?

    public init(state: ForgeState) {
        self.state = state
    }

    public var body: some View {
        ForgeSheet(
            icon: "stethoscope",
            title: "Forge Doctor",
            subtitle: "Health checks for your forge installation",
            content: {
                content
                    .frame(minHeight: 380, maxHeight: 560)
            },
            headerTrailing: {
                Button {
                    runDoctor()
                } label: {
                    Label("Run Again", systemImage: "arrow.clockwise")
                        .font(ForgeTheme.Typography.body)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.doctorLoading)
            },
            footer: {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut(.cancelAction)
                }
            }
        )
        .task { runDoctorIfNeeded() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if state.doctorLoading {
            loadingContent
        } else if let result = state.doctorResult {
            resultContent(result)
        } else if let doctorError {
            ForgeEmptyState(
                icon: "exclamationmark.triangle",
                title: "Diagnostics Failed",
                message: doctorError
            ) {
                Button("Retry") { runDoctor() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        } else {
            ForgeEmptyState(
                icon: "stethoscope",
                title: "No Results",
                message: "Click \"Run Again\" to start diagnostics."
            )
        }
    }

    private var loadingContent: some View {
        SkeletonGroup {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.lg) {
                SkeletonBox(width: nil, height: 60, radius: ForgeTheme.Metrics.cardRadius)
                VStack(spacing: ForgeTheme.Spacing.xxs) {
                    ForEach(0..<7, id: \.self) { _ in
                        SkeletonCheckRow()
                    }
                }
                Spacer()
            }
            .padding(ForgeTheme.Spacing.xl)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Running diagnostics")
    }

    // MARK: - Result Content

    private func resultContent(_ result: DoctorResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeTheme.Spacing.lg) {
                summaryBanner(result.summary)

                let grouped = Dictionary(grouping: result.checks) { $0.category }
                let sortedCategories = grouped.keys.sorted()

                ForEach(sortedCategories, id: \.self) { category in
                    if let checks = grouped[category] {
                        categorySection(category, checks: checks)
                    }
                }
            }
            .padding(ForgeTheme.Spacing.xl)
        }
    }

    // MARK: - Summary

    private func summaryBanner(_ summary: DoctorSummary) -> some View {
        HStack(spacing: 0) {
            summaryPill(count: summary.pass, label: "Passed", color: ForgeTheme.Colors.success, icon: "checkmark.circle.fill")
            Divider().frame(height: 32)
            summaryPill(count: summary.warnings, label: "Warnings", color: ForgeTheme.Colors.warning, icon: "exclamationmark.triangle.fill")
            Divider().frame(height: 32)
            summaryPill(count: summary.failures, label: "Failures", color: ForgeTheme.Colors.danger, icon: "xmark.circle.fill")
        }
        .padding(.vertical, ForgeTheme.Spacing.lg - 2)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius, style: .continuous)
                .fill(ForgeTheme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .forgeShadow(ForgeTheme.Elevation.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.pass) passed, \(summary.warnings) warnings, \(summary.failures) failures")
    }

    private func summaryPill(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: ForgeTheme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? color : .secondary.opacity(0.4))
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(count > 0 ? color : .secondary)
                Text(label)
                    .font(ForgeTheme.Typography.micro)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category

    private func categorySection(_ category: String, checks: [DoctorCheck]) -> some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Spacing.sm) {
            Text(formatCategory(category))
                .font(ForgeTheme.Typography.cardTitle)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            VStack(spacing: 1) {
                ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                    checkRow(check)
                        .background {
                            if index % 2 == 0 {
                                Color.primary.opacity(0.02)
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ForgeTheme.Metrics.rowRadius, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.5)
            }
        }
    }

    private func checkRow(_ check: DoctorCheck) -> some View {
        HStack(alignment: .center, spacing: ForgeTheme.Spacing.sm + 2) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(statusColor(check.status))
                .frame(width: 3, height: 24)
                .accessibilityHidden(true)

            Image(systemName: statusIcon(check.status))
                .font(.system(size: 13))
                .foregroundStyle(statusColor(check.status))
                .frame(width: 18, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(check.name)
                    .font(.system(size: 12, weight: .medium))
                if let detail = check.detail {
                    Text(detail)
                        .font(ForgeTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            StatusBadge(check.status.uppercased(), tint: statusColor(check.status))
        }
        .padding(.vertical, ForgeTheme.Spacing.sm)
        .padding(.horizontal, ForgeTheme.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "pass": return "checkmark.circle.fill"
        case "warn": return "exclamationmark.triangle.fill"
        case "fail": return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pass": return ForgeTheme.Colors.success
        case "warn": return ForgeTheme.Colors.warning
        case "fail": return ForgeTheme.Colors.danger
        default: return .secondary
        }
    }

    private func formatCategory(_ category: String) -> String {
        category.formattedAsTitle
    }

    private func runDoctorIfNeeded() {
        if state.doctorResult == nil {
            runDoctor()
        }
    }

    private func runDoctor() {
        state.doctorLoading = true
        state.doctorResult = nil
        doctorError = nil
        Task {
            do {
                let result = try await doctorService.runDoctor()
                state.doctorResult = result
            } catch {
                doctorError = error.localizedDescription
            }
            state.doctorLoading = false
        }
    }
}
