import SwiftUI

/// Renders markdown content with proper block-level formatting.
/// Handles headers, code blocks, lists, tables, blockquotes, and inline formatting.
/// Designed to handle streaming (incomplete) markdown gracefully.
struct MarkdownContentView: View {
    let content: String
    let isStreaming: Bool
    var fontSize: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block Parsing

    private var blocks: [MarkdownBlock] {
        parseBlocks(content)
    }

    private func parseBlocks(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var result: [MarkdownBlock] = []
        var i = 0
        var inCodeBlock = false
        var codeLang = ""
        var codeLines: [String] = []

        while i < lines.count {
            let line = lines[i]

            // Code fence toggle
            if line.hasPrefix("```") {
                if inCodeBlock {
                    result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                i += 1
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                i += 1
                continue
            }

            // Header
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty && level <= 6 {
                    result.append(.header(level: level, text: text))
                    i += 1
                    continue
                }
            }

            // Divider
            if line.trimmingCharacters(in: .whitespaces).count >= 3,
               line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == " " || $0 == "_" }),
               !line.trimmingCharacters(in: .whitespaces).isEmpty,
               Set(line.trimmingCharacters(in: .whitespaces)).count == 1 {
                result.append(.divider)
                i += 1
                continue
            }

            // Table (line contains | and next line is separator)
            if line.contains("|"), i + 1 < lines.count,
               lines[i + 1].contains("|"), lines[i + 1].contains("-") {
                var tableLines: [String] = []
                while i < lines.count, lines[i].contains("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                result.append(.table(lines: tableLines))
                continue
            }

            // Blockquote
            if line.hasPrefix("> ") {
                let text = String(line.dropFirst(2))
                result.append(.blockquote(text: text))
                i += 1
                continue
            }

            // Unordered list item
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let text = String(line.dropFirst(2))
                result.append(.listItem(text: text, ordered: false, number: 0))
                i += 1
                continue
            }

            // Ordered list item (1. text)
            if let match = line.range(of: #"^(\d+)\. "#, options: .regularExpression) {
                let numStr = line[line.startIndex..<line.index(before: match.upperBound)]
                    .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                let num = Int(numStr) ?? 0
                let text = String(line[match.upperBound...])
                result.append(.listItem(text: text, ordered: true, number: num))
                i += 1
                continue
            }

            // Empty line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Paragraph — accumulate consecutive non-special lines
            var paraLines = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                let trimmed = next.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || next.hasPrefix("#") || next.hasPrefix("```") ||
                   next.hasPrefix("- ") || next.hasPrefix("* ") || next.hasPrefix("> ") ||
                   next.contains("|") {
                    break
                }
                if let _ = next.range(of: #"^\d+\. "#, options: .regularExpression) {
                    break
                }
                paraLines.append(next)
                i += 1
            }
            result.append(.paragraph(text: paraLines.joined(separator: " ")))
        }

        // Streaming: unclosed code block
        if inCodeBlock, !codeLines.isEmpty {
            result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
        }

        return result
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .header(let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: headerSize(level), weight: .bold))
                .padding(.top, level <= 2 ? 6 : 2)

        case .codeBlock(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: fontSize - 1, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

        case .table(let lines):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(lines.joined(separator: "\n"))
                    .font(.system(size: fontSize - 1, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

        case .blockquote(let text):
            HStack(spacing: 8) {
                Rectangle()
                    .fill(.blue.opacity(0.4))
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

        case .listItem(let text, let ordered, let number):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ordered ? "\(number)." : "\u{2022}")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
                    .frame(width: ordered ? 20 : 10, alignment: .trailing)
                Text(inlineMarkdown(text))
                    .font(.system(size: fontSize))
            }

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: fontSize))

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func headerSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 8
        case 2: return fontSize + 5
        case 3: return fontSize + 2
        default: return fontSize + 1
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Block Model

private enum MarkdownBlock {
    case header(level: Int, text: String)
    case codeBlock(language: String, code: String)
    case table(lines: [String])
    case blockquote(text: String)
    case listItem(text: String, ordered: Bool, number: Int)
    case paragraph(text: String)
    case divider
}
