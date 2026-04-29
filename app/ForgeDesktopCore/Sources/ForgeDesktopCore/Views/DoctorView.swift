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
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 540)
        .frame(minHeight: 420, maxHeight: 600)
        .task { runDoctorIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "stethoscope")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Forge Doctor")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                runDoctor()
            } label: {
                Label("Run Again", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.doctorLoading)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if state.doctorLoading {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                Text("Running diagnostics...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result = state.doctorResult {
            resultContent(result)
        } else if let doctorError {
            ContentUnavailableView {
                Label("Diagnostics Failed", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(doctorError)
            } actions: {
                Button("Retry") { runDoctor() }
                    .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView(
                "No Results",
                systemImage: "stethoscope",
                description: Text("Click \"Run Again\" to start diagnostics.")
            )
        }
    }

    // MARK: - Result Content

    private func resultContent(_ result: DoctorResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryBanner(result.summary)

                let grouped = Dictionary(grouping: result.checks) { $0.category }
                let sortedCategories = grouped.keys.sorted()

                ForEach(sortedCategories, id: \.self) { category in
                    if let checks = grouped[category] {
                        categorySection(category, checks: checks)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Summary

    private func summaryBanner(_ summary: DoctorSummary) -> some View {
        HStack(spacing: 0) {
            summaryPill(count: summary.pass, label: "Passed", color: .green, icon: "checkmark.circle.fill")
            Divider().frame(height: 32)
            summaryPill(count: summary.warnings, label: "Warnings", color: .orange, icon: "exclamationmark.triangle.fill")
            Divider().frame(height: 32)
            summaryPill(count: summary.failures, label: "Failures", color: .red, icon: "xmark.circle.fill")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
    }

    private func summaryPill(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? color : .secondary.opacity(0.4))
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(count > 0 ? color : .secondary)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category

    private func categorySection(_ category: String, checks: [DoctorCheck]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatCategory(category))
                .font(.system(size: 11, weight: .bold))
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 0.5)
            }
        }
    }

    private func checkRow(_ check: DoctorCheck) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusIcon(check.status))
                .font(.system(size: 13))
                .foregroundStyle(statusColor(check.status))
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(check.name)
                    .font(.system(size: 12, weight: .medium))
                if let detail = check.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(check.status.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor(check.status))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor(check.status).opacity(0.1), in: Capsule())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
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
        case "pass": return .green
        case "warn": return .orange
        case "fail": return .red
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
