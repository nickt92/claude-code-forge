import XCTest
@testable import ForgeDesktopCore

final class DiffEngineTests: XCTestCase {

    // MARK: - No Changes

    func testIdenticalContentReturnsEmptyDiff() {
        let content = "line1\nline2\nline3"
        let result = DiffEngine.diff(before: content, after: content)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Pure Additions

    func testAppendedLinesShowAsAdded() {
        let before = "# Project\n\nExisting content"
        let after = "# Project\n\nExisting content\n\n## Testing\n\nRun tests."

        let result = DiffEngine.diff(before: before, after: after)

        let added = result.filter { $0.kind == .added }
        XCTAssertFalse(added.isEmpty)
        XCTAssertTrue(added.contains { $0.text == "## Testing" })
        XCTAssertTrue(added.contains { $0.text == "Run tests." })
    }

    func testInsertedLinesInMiddleShowAsAdded() {
        let before = "line1\nline2\nline3"
        let after = "line1\nline2\nnew line\nline3"

        let result = DiffEngine.diff(before: before, after: after)

        let added = result.filter { $0.kind == .added }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.text, "new line")
    }

    // MARK: - Pure Removals

    func testRemovedLinesShowAsRemoved() {
        let before = "line1\nline2\nline3"
        let after = "line1\nline3"

        let result = DiffEngine.diff(before: before, after: after)

        let removed = result.filter { $0.kind == .removed }
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.text, "line2")
    }

    // MARK: - Mixed Changes

    func testMixedAdditionsAndRemovals() {
        let before = "alpha\nbeta\ngamma"
        let after = "alpha\nBETA\ngamma\ndelta"

        let result = DiffEngine.diff(before: before, after: after)

        let removed = result.filter { $0.kind == .removed }
        let added = result.filter { $0.kind == .added }

        XCTAssertTrue(removed.contains { $0.text == "beta" })
        XCTAssertTrue(added.contains { $0.text == "BETA" })
        XCTAssertTrue(added.contains { $0.text == "delta" })
    }

    // MARK: - Context Lines

    func testContextLinesAroundChanges() {
        var lines: [String] = []
        for i in 1...20 {
            lines.append("line \(i)")
        }
        let before = lines.joined(separator: "\n")

        // Insert a line after line 10
        var afterLines = lines
        afterLines.insert("NEW LINE", at: 10)
        let after = afterLines.joined(separator: "\n")

        let result = DiffEngine.diff(before: before, after: after, context: 2)

        let unchanged = result.filter { $0.kind == .unchanged }
        let separators = result.filter { if case .separator = $0.kind { return true }; return false }

        // Should have context lines but not all 20 original lines
        XCTAssertFalse(unchanged.isEmpty)
        XCTAssertFalse(separators.isEmpty, "Long unchanged sections should be collapsed into separators")

        let added = result.filter { $0.kind == .added }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.text, "NEW LINE")
    }

    // MARK: - Separators

    func testSeparatorShowsCorrectCollapsedCount() {
        var lines: [String] = []
        for i in 1...30 {
            lines.append("line \(i)")
        }
        let before = lines.joined(separator: "\n")

        var afterLines = lines
        afterLines.insert("ADDED", at: 15)
        let after = afterLines.joined(separator: "\n")

        let result = DiffEngine.diff(before: before, after: after, context: 2)

        let separators = result.filter {
            if case .separator(let n) = $0.kind { return n > 0 }
            return false
        }
        XCTAssertFalse(separators.isEmpty)
    }

    // MARK: - Line Numbers

    func testAddedLinesHaveNewLineNumbers() {
        let before = "a\nb\nc"
        let after = "a\nb\nNEW\nc"

        let result = DiffEngine.diff(before: before, after: after)

        let added = result.filter { $0.kind == .added }
        XCTAssertEqual(added.first?.lineNumber, 3)
    }

    func testRemovedLinesHaveOldLineNumbers() {
        let before = "a\nb\nc"
        let after = "a\nc"

        let result = DiffEngine.diff(before: before, after: after)

        let removed = result.filter { $0.kind == .removed }
        XCTAssertEqual(removed.first?.lineNumber, 2) // "b" was on old line 2
    }

    func testSeparatorsHaveNilLineNumber() {
        var lines: [String] = []
        for i in 1...20 { lines.append("line \(i)") }
        let before = lines.joined(separator: "\n")

        var afterLines = lines
        afterLines.insert("NEW", at: 10)
        let after = afterLines.joined(separator: "\n")

        let result = DiffEngine.diff(before: before, after: after, context: 1)

        let separators = result.filter { if case .separator = $0.kind { return true }; return false }
        for sep in separators {
            XCTAssertNil(sep.lineNumber)
        }
    }

    // MARK: - Unique IDs

    func testAllDiffLinesHaveUniqueIDs() {
        let before = "a\nb\nc\nd\ne"
        let after = "a\nB\nc\nD\ne\nf"

        let result = DiffEngine.diff(before: before, after: after)

        let ids = result.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All DiffLine IDs should be unique")
    }

    // MARK: - Empty Content

    func testEmptyBeforeShowsAllAsAdded() {
        let result = DiffEngine.diff(before: "", after: "line1\nline2")

        let added = result.filter { $0.kind == .added }
        XCTAssertEqual(added.count, 2)
    }

    func testEmptyAfterShowsAllAsRemoved() {
        let result = DiffEngine.diff(before: "line1\nline2", after: "")

        let removed = result.filter { $0.kind == .removed }
        XCTAssertEqual(removed.count, 2)
    }

    // MARK: - Single Line

    func testSingleLineChange() {
        let result = DiffEngine.diff(before: "old", after: "new")

        let removed = result.filter { $0.kind == .removed }
        let added = result.filter { $0.kind == .added }

        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.text, "old")
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.text, "new")
    }

    // MARK: - Context = 0

    func testZeroContextShowsOnlyChangedLines() {
        var lines: [String] = []
        for i in 1...10 { lines.append("line \(i)") }
        let before = lines.joined(separator: "\n")

        var afterLines = lines
        afterLines.insert("NEW", at: 5)
        let after = afterLines.joined(separator: "\n")

        let result = DiffEngine.diff(before: before, after: after, context: 0)

        let unchanged = result.filter { $0.kind == .unchanged }
        XCTAssertTrue(unchanged.isEmpty, "With context=0, no unchanged lines should appear")
    }
}
