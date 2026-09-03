import XCTest
import TextEngineCore

/// Node 4's behaviour. The fixture carries all three row kinds the ladder distinguishes:
/// a wrapped line (three equal rows), a blank line (one `[0, 0)` row), and a line whose
/// first row OVERFLOWS the wrap width (an unbreakable run wider than the width — node 1
/// packs it rather than force-breaking, so an `x` between `wrapWidth` and `rowSpan.width`
/// is a real point inside a real row).
final class WrapPointQueryTests: XCTestCase {
    static let rowHeight = 10.0
    static let wrapWidth = 20.0

    /// line 0: 6 cells x 10, breakable everywhere -> rows [0,2) [2,4) [4,6), each 20 wide
    /// line 1: blank                              -> one [0,0) row
    /// line 2: advances [30, 10], break before 1  -> rows [0,1) width 30 (OVERFLOW), [1,2) width 10
    /// firstVisualRow = [0, 3, 4, 6]; totalRows 6; total height 60.
    static func layout() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [
                (advances: Array(repeating: 10.0, count: 6), breaks: Set(1..<6)),
                (advances: [], breaks: []),
                (advances: [30.0, 10.0], breaks: [1]),
            ],
            rowHeight: rowHeight,
            wrapWidth: wrapWidth)
    }

    private func located(
        x: Double, y: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) -> VisualPointLocation? {
        switch ViewportVirtualizer.visualPointAt(x: x, y: y, layout: Self.layout()) {
        case .point(let location):
            return location
        case .empty:
            XCTFail("expected .point, got .empty", file: file, line: line); return nil
        case .failure(let error):
            XCTFail("expected .point, got .failure(\(error))", file: file, line: line); return nil
        }
    }

    // Global row 1 = line 0, row 1: span [2, 4), rowLeft 20, width 20.
    func testInteriorOfAMiddleRowResolvesToItsCell() {
        guard let point = located(x: 5.0, y: 15.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 1, logicalLine: 0, rowInLine: 1, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0))
        // Line-ABSOLUTE (Decision 2): x = 5 is row-relative, cell 2 is the line's index.
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 2, clamp: .inRange)))
    }

    // Half-open spans: an x landing exactly on a cell boundary belongs to the LATER cell.
    func testExactCellBoundaryResolvesToTheLaterCell() {
        guard let point = located(x: 10.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 3, clamp: .inRange)))
    }

    // Decision 1: the clamps land on the ROW's edges, not the line's.
    func testXAtTheRowWidthClampsToTheRowsLastCell() {
        guard let point = located(x: 20.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 3, clamp: .clampedToRight)))
    }

    func testNegativeXClampsToTheRowsFirstCell() {
        guard let point = located(x: -1.0, y: 15.0) else { return }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 2, clamp: .clampedToLeft)))
    }

    // Decision 7: read from the span, not from a second columnCount probe.
    func testBlankLineResolvesToBlankLine() {
        guard let point = located(x: 5.0, y: 35.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 3, logicalLine: 1, rowInLine: 0, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 1, rowInLine: 0, startColumn: 0, endColumn: 0, width: 0.0))
        XCTAssertEqual(point.column, .blankLine)
    }

    // AC2: on an OVERFLOW row the clamp compares against the row's own advance sum, not
    // against wrapWidth -- so wrapWidth < x < rowSpan.width is .inRange, a real point.
    func testXBetweenWrapWidthAndRowWidthOnAnOverflowRowStaysInRange() {
        guard let point = located(x: 25.0, y: 45.0) else { return }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 4, logicalLine: 2, rowInLine: 0, clamp: .inRange))
        XCTAssertEqual(point.rowSpan, VisualRow(logicalLine: 2, rowInLine: 0, startColumn: 0, endColumn: 1, width: 30.0))
        XCTAssertGreaterThan(25.0, Self.wrapWidth, "the fixture must put x past the wrap width, or this covers nothing")
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 0, clamp: .inRange)))
    }

    // Both clamp flags observed together: the vertical one on `row`, the horizontal one
    // on the cell. A query that dropped either would still pass every test above.
    func testClampedYCrossedWithEachXBranch() {
        guard let topLeft = located(x: -1.0, y: -5.0) else { return }
        XCTAssertEqual(topLeft.row, VisualRowLocation(globalRow: 0, logicalLine: 0, rowInLine: 0, clamp: .clampedToTop))
        XCTAssertEqual(topLeft.column, .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)))

        guard let bottomRight = located(x: 100.0, y: 1_000.0) else { return }
        XCTAssertEqual(bottomRight.row, VisualRowLocation(globalRow: 5, logicalLine: 2, rowInLine: 1, clamp: .clampedToBottom))
        XCTAssertEqual(bottomRight.rowSpan, VisualRow(logicalLine: 2, rowInLine: 1, startColumn: 1, endColumn: 2, width: 10.0))
        XCTAssertEqual(bottomRight.column, .cell(ColumnLocation(columnIndex: 1, clamp: .clampedToRight)))

        guard let bottomInterior = located(x: 5.0, y: 1_000.0) else { return }
        XCTAssertEqual(bottomInterior.row.clamp, .clampedToBottom)
        XCTAssertEqual(bottomInterior.column, .cell(ColumnLocation(columnIndex: 1, clamp: .inRange)))
    }
}
