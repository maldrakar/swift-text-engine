import XCTest
import TextEngineCore

final class WrapComputeEquivalenceTests: XCTestCase {
    // Irregular advances + irregular breaks + VARIABLE per-line column counts.
    private func irregularLines() -> [(advances: [Double], breaks: Set<Int>)] {
        [
            (advances: [7, 3, 11, 5], breaks: [1, 2, 3]),
            (advances: [13], breaks: []),
            (advances: [2, 2, 2, 2, 2, 2], breaks: [2, 4]),
            (advances: [], breaks: []),          // blank line
            (advances: [9, 9], breaks: [1]),
        ]
    }

    private func inputs() -> [VariableViewportInput] {
        [
            VariableViewportInput(scrollOffsetY: 0, viewportHeight: 30, overscanLinesBefore: 0, overscanLinesAfter: 0),
            VariableViewportInput(scrollOffsetY: 12, viewportHeight: 20, overscanLinesBefore: 1, overscanLinesAfter: 2),
            VariableViewportInput(scrollOffsetY: 9_999, viewportHeight: 20, overscanLinesBefore: 0, overscanLinesAfter: 0),
        ]
    }

    // At infinite width every logical line is one visual row, so the visual-row axis is
    // exactly UniformLineMetrics(lineCount, rowHeight) and the ranges must be identical.
    func testInfiniteWidthComputeEqualsUniformLogicalCompute() {
        let rowHeight = 4.0
        for width in [Double.infinity, 1_000_000.0] {   // ∞ and >= every line total
            let layout = TestVisualRowLayout(lines: irregularLines(), rowHeight: rowHeight, wrapWidth: width)
            XCTAssertEqual(layout.firstVisualRow(ofLine: layout.lineCount), layout.lineCount,
                           "at width \(width) every line should be one row")
            let uniform = UniformLineMetrics(lineCount: layout.lineCount, lineHeight: rowHeight)
            for input in inputs() {
                XCTAssertEqual(
                    ViewportVirtualizer.compute(input, layout: layout),
                    ViewportVirtualizer.compute(input, metrics: uniform),
                    "width \(width), scroll \(input.scrollOffsetY)")
            }
        }
    }

    func testEmptyDocumentIsEmptyRange() {
        let layout = TestVisualRowLayout(lines: [], rowHeight: 4.0, wrapWidth: 20.0)
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 30, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(range.isEmpty)
    }

    func testInfiniteWidthStreamsOneRowPerLine() {
        let rowHeight = 4.0
        let layout = TestVisualRowLayout(lines: irregularLines(), rowHeight: rowHeight, wrapWidth: .infinity)
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 10_000, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else { return XCTFail() }
        let rows = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertEqual(rows.count, layout.lineCount)
        for (L, g) in rows.enumerated() {
            XCTAssertEqual(g.row.logicalLine, L)
            XCTAssertEqual(g.row.rowInLine, 0)
            XCTAssertEqual(g.row.startColumn, 0)
            XCTAssertEqual(g.row.endColumn, layout.columnCount(inLine: L))
            XCTAssertEqual(g.y, Double(L) * rowHeight)
        }
    }
}
