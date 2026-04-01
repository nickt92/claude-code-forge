import MarkdownUI
import SwiftUI

public struct ClaudeMdContentView: View {
    let filePath: String
    let audit: AuditData
    let refreshTrigger: Int

    @State private var showContent = false
    @State private var showAll = false
    @State private var fileContent: String?
    @State private var showRendered = true

    private let maxCollapsedHeight: CGFloat = 300

    public init(filePath: String, audit: AuditData, refreshTrigger: Int) {
        self.filePath = filePath
        self.audit = audit
        self.refreshTrigger = refreshTrigger
    }

    public var body: some View {
        DetailCard("CLAUDE.MD CONTENT") {
            VStack(alignment: .leading, spacing: 8) {
                headerRow
                if showContent {
                    contentBody
                }
            }
        }
        .task(id: refreshTrigger) {
            loadFile()
        }
        .task(id: filePath) {
            loadFile()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showContent.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showContent ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(showContent ? "Hide" : "Show")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if showContent {
                Picker("", selection: $showRendered) {
                    Text("Rendered").tag(true)
                    Text("Source").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .controlSize(.mini)
            }

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
            } label: {
                HStack(spacing: 3) {
                    Text("Open")
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentBody: some View {
        if let content = fileContent {
            if showRendered {
                renderedBody(content)
            } else {
                sourceBody(content)
            }
        } else {
            Text("Could not read file")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    private func renderedBody(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RenderedMarkdownView(content: content, fontSize: 12)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    missingMarkers
                }
                .padding(12)
            }
            .frame(maxHeight: showAll ? .infinity : maxCollapsedHeight)

            if !showAll, content.components(separatedBy: "\n").count > 15 {
                expandButton(lineCount: content.components(separatedBy: "\n").count)
            }
        }
        .background(.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }

    private func sourceBody(_ content: String) -> some View {
        let annotatedLines = buildAnnotatedLines(from: content)

        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(annotatedLines.enumerated()), id: \.offset) { index, line in
                        annotatedLineView(line, index: index)
                    }

                    missingMarkers
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: showAll ? .infinity : maxCollapsedHeight)

            if !showAll, annotatedLines.count > 15 {
                expandButton(lineCount: annotatedLines.count)
            }
        }
        .background(.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }

    private func expandButton(lineCount: Int) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                withAnimation { showAll = true }
            } label: {
                Text("Show all \(lineCount) lines")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Line Rendering

    private func annotatedLineView(_ line: AnnotatedLine, index: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(line.lineNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 6)

            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(line.isHeading ? .primary : .secondary)
                .fontWeight(line.isHeading ? .semibold : .regular)

            Spacer()

            if let tag = line.sectionTag {
                Text(tag)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.green.opacity(0.1), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var missingMarkers: some View {
        ForEach(audit.sections.missing, id: \.self) { section in
            HStack(spacing: 6) {
                Rectangle()
                    .fill(.orange.opacity(0.4))
                    .frame(height: 1)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                Text("Missing: \(formatSectionName(section))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                Rectangle()
                    .fill(.orange.opacity(0.4))
                    .frame(height: 1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
    }

    // MARK: - Data Model

    private struct AnnotatedLine {
        let lineNumber: Int
        let text: String
        let isHeading: Bool
        let sectionTag: String?
    }

    private func buildAnnotatedLines(from content: String) -> [AnnotatedLine] {
        let lines = content.components(separatedBy: "\n")
        let foundNormalized = Set(audit.sections.found.map { normalize($0) })

        return lines.enumerated().map { index, text in
            let isHeading = text.hasPrefix("## ")
            var tag: String? = nil

            if isHeading {
                let headingText = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if foundNormalized.contains(normalize(headingText)) {
                    tag = "found"
                }
            }

            return AnnotatedLine(
                lineNumber: index + 1,
                text: text,
                isHeading: isHeading,
                sectionTag: tag
            )
        }
    }

    // MARK: - Helpers

    private func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private func formatSectionName(_ section: String) -> String {
        section.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func loadFile() {
        fileContent = try? String(contentsOfFile: filePath, encoding: .utf8)
    }
}
