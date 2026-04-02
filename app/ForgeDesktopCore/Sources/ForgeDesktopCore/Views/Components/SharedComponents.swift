import SwiftUI

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

// MARK: - Bulk Fix State

struct BulkFixState {
    let total: Int
    var currentIndex: Int = 0
    var completedCount: Int = 0
    var currentFinding: String = ""
    var failedFinding: String?
    var currentActivities: [ToolActivity] = []
}

struct BulkFixProgressView: View {
    let state: BulkFixState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView(value: Double(state.completedCount), total: Double(state.total))
                    .progressViewStyle(.linear)
                Text("\(state.completedCount)/\(state.total)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let failed = state.failedFinding {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 10))
                    Text("Failed: \(failed)")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(state.currentFinding)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !state.currentActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(state.currentActivities) { activity in
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
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}
