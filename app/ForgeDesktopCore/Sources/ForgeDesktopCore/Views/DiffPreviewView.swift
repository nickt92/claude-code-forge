import SwiftUI

public struct DiffPreviewView: View {
    let before: String
    let after: String
    let sectionName: String
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var selectedTab: Tab = .changes

    enum Tab: String, CaseIterable {
        case changes = "Changes"
        case fullPreview = "Full Preview"
    }

    public init(
        before: String,
        after: String,
        sectionName: String,
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.before = before
        self.after = after
        self.sectionName = sectionName
        self.onApprove = onApprove
        self.onReject = onReject
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabContent
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("Review Changes")
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .changes:
            changesView
        case .fullPreview:
            fullPreviewView
        }
    }

    // MARK: - Changes Tab (Unified Diff)

    private var changesView: some View {
        let diffLines = DiffEngine.diff(before: before, after: after)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if diffLines.isEmpty {
                    Text("No changes detected")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(16)
                } else {
                    ForEach(diffLines) { line in
                        diffLineRow(line)
                    }
                }
            }
        }
        .background(.background)
    }

    private func diffLineRow(_ line: DiffLine) -> some View {
        Group {
            switch line.kind {
            case .separator(let count):
                separatorRow(count: count)
            case .unchanged:
                contentRow(gutter: " ", lineNumber: line.lineNumber, text: line.text, kind: .unchanged)
            case .added:
                contentRow(gutter: "+", lineNumber: line.lineNumber, text: line.text, kind: .added)
            case .removed:
                contentRow(gutter: "-", lineNumber: line.lineNumber, text: line.text, kind: .removed)
            }
        }
    }

    private func separatorRow(count: Int) -> some View {
        HStack {
            Spacer()
            Text("··· \(count) unchanged line\(count == 1 ? "" : "s") ···")
                .font(.system(size: 11, design: .monospaced))
                .italic()
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5))
    }

    private func contentRow(gutter: String, lineNumber: Int?, text: String, kind: DiffLineKind) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number gutter
            Text(lineNumber.map { String($0) } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 4)

            // +/- gutter
            Text(gutter)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(gutterColor(kind))
                .frame(width: 16, alignment: .center)

            // Content
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .fontWeight(text.hasPrefix("#") ? .semibold : .regular)
                .foregroundStyle(textColor(kind))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 8)
        .background(backgroundColor(kind))
    }

    // MARK: - Full Preview Tab

    private var fullPreviewView: some View {
        let afterLines = after.components(separatedBy: "\n")
        let addedLines = addedLineNumbers()

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(afterLines.enumerated()), id: \.offset) { index, line in
                    let lineNum = index + 1
                    let isAdded = addedLines.contains(lineNum)

                    HStack(alignment: .top, spacing: 0) {
                        Text(String(lineNum))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 40, alignment: .trailing)
                            .padding(.trailing, 4)

                        Text(" ")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 16, alignment: .center)

                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .fontWeight(line.hasPrefix("#") ? .semibold : .regular)
                            .foregroundStyle(isAdded ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 1)
                    .padding(.horizontal, 8)
                    .background(isAdded ? Color.green.opacity(0.08) : Color.clear)
                }
            }
        }
        .background(.background)
    }

    /// Returns line numbers (1-based) in `after` that are additions relative to `before`.
    private func addedLineNumbers() -> Set<Int> {
        let oldLines = before.components(separatedBy: "\n")
        let newLines = after.components(separatedBy: "\n")
        let changes = newLines.difference(from: oldLines)

        var result: Set<Int> = []
        for change in changes {
            if case .insert(let offset, _, _) = change {
                result.insert(offset + 1)
            }
        }
        return result
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Reject") {
                onReject()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button("Approve Changes") {
                onApprove()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Styling

    private func backgroundColor(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return .green.opacity(0.12)
        case .removed: return .red.opacity(0.12)
        default: return .clear
        }
    }

    private func textColor(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .unchanged: return .secondary
        default: return .primary
        }
    }

    private func gutterColor(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        default: return .clear
        }
    }
}
