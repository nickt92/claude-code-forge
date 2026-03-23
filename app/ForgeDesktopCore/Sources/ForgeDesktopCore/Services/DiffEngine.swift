import Foundation

// MARK: - Diff Types

public enum DiffLineKind: Sendable, Equatable {
    case unchanged
    case added
    case removed
    case separator(Int)
}

public struct DiffLine: Identifiable, Sendable, Equatable {
    public let id: Int
    public let kind: DiffLineKind
    public let text: String
    public let lineNumber: Int?

    public init(id: Int, kind: DiffLineKind, text: String, lineNumber: Int?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.lineNumber = lineNumber
    }
}

// MARK: - Diff Engine

public enum DiffEngine {

    /// Produces a unified diff between `before` and `after` content.
    /// Shows `context` unchanged lines around each change, collapsing longer unchanged runs into separators.
    /// Uses `CollectionDifference` which works well for append/modify patterns typical of CLAUDE.md edits.
    /// For arbitrary file comparisons with complex interleaved edits, a Myers diff would be more robust.
    public static func diff(before: String, after: String, context: Int = 3) -> [DiffLine] {
        let oldLines = before.components(separatedBy: "\n")
        let newLines = after.components(separatedBy: "\n")

        let changes = newLines.difference(from: oldLines)

        // Indices removed from old, indices inserted into new
        var removedFromOld: Set<Int> = []
        var insertedInNew: Set<Int> = []

        for change in changes {
            switch change {
            case .remove(let offset, _, _):
                removedFromOld.insert(offset)
            case .insert(let offset, _, _):
                insertedInNew.insert(offset)
            }
        }

        // Walk both arrays to produce interleaved output
        var rawLines: [(kind: DiffLineKind, text: String, lineNum: Int?)] = []
        var oldIdx = 0
        var newIdx = 0

        while oldIdx < oldLines.count || newIdx < newLines.count {
            if newIdx < newLines.count && insertedInNew.contains(newIdx) {
                rawLines.append((.added, newLines[newIdx], newIdx + 1))
                newIdx += 1
            } else if oldIdx < oldLines.count && removedFromOld.contains(oldIdx) {
                rawLines.append((.removed, oldLines[oldIdx], oldIdx + 1))
                oldIdx += 1
            } else if oldIdx < oldLines.count && newIdx < newLines.count {
                rawLines.append((.unchanged, newLines[newIdx], newIdx + 1))
                oldIdx += 1
                newIdx += 1
            } else if newIdx < newLines.count {
                rawLines.append((.added, newLines[newIdx], newIdx + 1))
                newIdx += 1
            } else {
                rawLines.append((.removed, oldLines[oldIdx], oldIdx + 1))
                oldIdx += 1
            }
        }

        // Find which raw indices have changes nearby (within context distance)
        var showIndices: Set<Int> = []
        for (i, raw) in rawLines.enumerated() {
            if raw.kind != .unchanged {
                let lo = max(0, i - context)
                let hi = min(rawLines.count - 1, i + context)
                for j in lo...hi {
                    showIndices.insert(j)
                }
            }
        }

        // If there are no changes, return empty
        if showIndices.isEmpty {
            return []
        }

        // Build final output with separators for collapsed sections
        var result: [DiffLine] = []
        var idCounter = 0
        var lastShownIndex = -1

        for i in 0..<rawLines.count {
            guard showIndices.contains(i) else { continue }

            // Insert separator if we skipped lines
            let gap = i - lastShownIndex - 1
            if gap > 0 && lastShownIndex >= 0 {
                result.append(DiffLine(id: idCounter, kind: .separator(gap), text: "", lineNumber: nil))
                idCounter += 1
            } else if lastShownIndex == -1 && i > 0 {
                // Lines before the first shown change
                result.append(DiffLine(id: idCounter, kind: .separator(i), text: "", lineNumber: nil))
                idCounter += 1
            }

            let raw = rawLines[i]
            result.append(DiffLine(id: idCounter, kind: raw.kind, text: raw.text, lineNumber: raw.lineNum))
            idCounter += 1
            lastShownIndex = i
        }

        // Trailing separator
        let trailingGap = rawLines.count - 1 - lastShownIndex
        if trailingGap > 0 && lastShownIndex >= 0 {
            result.append(DiffLine(id: idCounter, kind: .separator(trailingGap), text: "", lineNumber: nil))
        }

        return result
    }
}
