import XCTest
import TextEngineCore

final class WrapComputeTests: XCTestCase {
    // 4 lines, each 4 cells advance 10, break at every cell, width 20 -> 2 rows/line.
    // totalRows = 8 (NOT lineCount 4). rowHeight 5 -> total height 40.
    private func layout(width: Double = 20.0) -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: [10.0, 10.0, 10.0, 10.0], breaks: Set([1, 2, 3])), count: 4),
            rowHeight: 5.0,
            wrapWidth: width
        )
    }

    // A viewport of height 15 from the top covers rows [0,3): 3 visual rows, not 3 lines.
    // A stub compute that used lineCount (4) instead of totalRows (8) would clamp/scale
    // wrong here -- this is the finite-width test that the recorded-red stub fails.
    func testFiniteWidthVisibleRangeIsInVisualRows() {
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 15, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(range.visibleStart, 0)
        XCTAssertEqual(range.visibleEndExclusive, 3)   // rows 0,1,2 (y in [0,15))
        XCTAssertTrue(range.isAtTop)
        XCTAssertFalse(range.isAtBottom)
    }

    // Scrolling to the very bottom: total height 40, viewport 15 -> maxOffset 25 ->
    // visibleStart at row 5 (y=25), through row 8. isAtBottom true.
    func testScrollToBottomIsInVisualRows() {
        let input = VariableViewportInput(scrollOffsetY: 9_999, viewportHeight: 15, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(range.visibleEndExclusive, 8)   // 8 total rows
        XCTAssertTrue(range.isAtBottom)
    }

    private func drain(_ layout: TestVisualRowLayout, _ input: VariableViewportInput) -> [VisualRowGeometry] {
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else {
            XCTFail("expected success"); return []
        }
        return collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
    }

    func testCursorTilesBufferRangeInVisualRows() {
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 15, overscanLinesBefore: 0, overscanLinesAfter: 1)
        let rows = drain(layout(), input)
        // buffer = visible [0,3) + 1 overscan after -> 4 rows (globalRow 0..4 exclusive).
        XCTAssertEqual(rows.count, 4)
        // globalRow contiguous, y increases by rowHeight (5).
        for (i, g) in rows.enumerated() {
            XCTAssertEqual(g.y, Double(i) * 5.0, accuracy: 0)
            XCTAssertEqual(g.height, 5.0)
        }
        // each row's span matches node 1's packing: line L = globalRow/2, rowInLine = globalRow%2.
        for (i, g) in rows.enumerated() {
            XCTAssertEqual(g.row.logicalLine, i / 2)
            XCTAssertEqual(g.row.rowInLine, i % 2)
        }
    }

    func testCursorMidLineStart() {
        // Scroll so the buffer starts at row 1 of line 0 (an odd global row) -> the
        // O(rowInLine) discard walk must land on rowInLine 1.
        let input = VariableViewportInput(scrollOffsetY: 5, viewportHeight: 5, overscanLinesBefore: 0, overscanLinesAfter: 0)
        let rows = drain(layout(), input)
        XCTAssertEqual(rows.first?.row.logicalLine, 0)
        XCTAssertEqual(rows.first?.row.rowInLine, 1)
        XCTAssertEqual(rows.first?.y, 5.0)
    }

    func testBlankLineIsOneRow() {
        let layout = TestVisualRowLayout(
            lines: [(advances: [10, 10], breaks: [1]), (advances: [], breaks: []), (advances: [10], breaks: [])],
            rowHeight: 5.0, wrapWidth: 20.0)
        // line0 -> 1 row (both cells fit in 20), line1 blank -> 1 row [0,0), line2 -> 1 row.
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 100, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else { return XCTFail() }
        let rows = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1].row.startColumn, 0)
        XCTAssertEqual(rows[1].row.endColumn, 0)   // blank -> [0,0)
        XCTAssertEqual(rows[1].row.logicalLine, 1)
    }

    // D-12 fold-in: a break lands EXACTLY on wrapWidth (columnOffset(2) - 0 == 20 == width).
    // The inclusive `<=` edge must keep it on the row; a `<`-vs-`<=` mutation in
    // greedyEnd would split it and this fixture reddens.
    func testInteriorExactEqualWidthBoundary() {
        let layout = TestVisualRowLayout(
            lines: [(advances: [10, 10, 10], breaks: [1, 2])], rowHeight: 5.0, wrapWidth: 20.0)
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 100, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else { return XCTFail() }
        let rows = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].row.startColumn, 0)
        XCTAssertEqual(rows[0].row.endColumn, 2)   // [0,2) width exactly 20 -- inclusive edge
        XCTAssertEqual(rows[1].row.startColumn, 2)
    }
}
