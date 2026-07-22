import XCTest
import TextEngineCore

final class VisualRowEquivalenceTests: XCTestCase {
    // A blank logical line is exactly one empty visual row, then nil.
    func testBlankLineIsOneEmptyRow() {
        let metrics = TestWrapMetrics(offsets: [0.0]) // columnCount 0
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics))
        XCTAssertEqual(rows, [VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 0, width: 0.0)])
    }

    func testSingleCellLineIsOneRow() {
        let metrics = TestWrapMetrics(advances: [8.0])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics))
        XCTAssertEqual(rows, [VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 1, width: 8.0)])
    }

    // The marquee guarantee: irregular advances + irregular breaks; at any width
    // ≥ the line's total advance (+∞ included), packing yields exactly one row
    // [0, count) whose width is the total — the no-wrap column model read off the
    // same source. The `.infinity` case is also the F1 regression test (a
    // `wrapWidth.isFinite` guard would wrongly reject it).
    func testWidthAtOrAboveTotalYieldsOneRowEqualToNoWrap() {
        let advances = [12.0, 3.0, 40.0, 7.0, 25.0]      // total 87
        let metrics = TestWrapMetrics(advances: advances, breakColumns: [1, 3])
        let total = metrics.columnOffset(inLine: 0, column: advances.count)
        for width in [total, total + 0.5, Double.infinity] {
            let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: width, metrics: metrics))
            XCTAssertEqual(
                rows,
                [VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 5, width: 87.0)],
                "width=\(width)"
            )
        }
    }
}
