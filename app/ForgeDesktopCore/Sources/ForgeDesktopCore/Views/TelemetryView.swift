import SwiftUI

public struct TelemetryView: View {
    @Environment(\.forgeService) private var forgeService
    @Environment(\.dismiss) private var dismiss

    @State private var hookData: HookTelemetryData?
    @State private var sessionData: SessionScorecard?
    @State private var loadError: String?
    @State private var isLoading = true

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingState
                } else if let error = loadError {
                    errorState(error)
                } else {
                    loadedState
                }
            }
            .navigationTitle("Hook Telemetry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .task { await loadData() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 28))
                .foregroundStyle(ForgeTheme.Colors.forgeOrange)
                .symbolEffect(.pulse, options: .repeating)
            Text("Loading telemetry...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                isLoading = true
                loadError = nil
                Task { await loadData() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var loadedState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let hooks = hookData {
                    hookTelemetrySection(hooks)
                }
                if let session = sessionData {
                    sessionScorecardSection(session)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Hook Telemetry Section

    private func hookTelemetrySection(_ data: HookTelemetryData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Big metric
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("\(data.totalInvocations)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(ForgeTheme.Colors.forgeOrange)
                    Text("invocations")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                BlockRateGauge(rate: data.blockRate)

                VStack(spacing: 2) {
                    Text("\(data.avgDurationMs)ms")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("avg duration")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: ForgeTheme.Metrics.cardRadius).stroke(.quaternary))

            // Per-hook bars
            if !data.byHook.isEmpty {
                DetailCard("By Hook", accentColor: ForgeTheme.Colors.forgeOrange) {
                    let sorted = data.byHook.sorted { $0.value > $1.value }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(sorted.enumerated()), id: \.element.key) { index, entry in
                            TelemetryMetricRow(
                                label: entry.key,
                                value: entry.value,
                                total: data.totalInvocations,
                                index: index
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Session Scorecard Section

    private func sessionScorecardSection(_ data: SessionScorecard) -> some View {
        DetailCard("Session Scorecard") {
            if data.totalEvents == 0 {
                Text("No session events yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        StatBadge(label: "Events", value: data.totalEvents, color: .primary)
                        StatBadge(label: "Allowed", value: data.allows, color: .green)
                        if data.blocks > 0 {
                            StatBadge(label: "Blocked", value: data.blocks, color: .red)
                        }
                        if data.detects > 0 {
                            StatBadge(label: "Detected", value: data.detects, color: ForgeTheme.Colors.forgeOrange)
                        }
                        if data.overrides > 0 {
                            StatBadge(label: "Overrides", value: data.overrides, color: .purple)
                        }
                    }

                    if !data.byHook.isEmpty {
                        Divider()
                        let sorted = data.byHook.sorted { $0.value > $1.value }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(sorted.enumerated()), id: \.element.key) { index, entry in
                                TelemetryMetricRow(
                                    label: entry.key,
                                    value: entry.value,
                                    total: data.totalEvents,
                                    index: index
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        do { hookData = try await forgeService.loadHookTelemetry() }
        catch is CancellationError { return }
        catch { /* hook data unavailable — view handles nil */ }

        do { sessionData = try await forgeService.loadSessionScorecard() }
        catch is CancellationError { return }
        catch { /* session data unavailable — view handles nil */ }

        if hookData == nil && sessionData == nil {
            loadError = "Failed to load telemetry data."
        }
        isLoading = false
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
