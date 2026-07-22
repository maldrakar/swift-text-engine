import XCTest
import TextEngineCore

final class WrapPackingTests: XCTestCase {
    // advances [10,10,10,10] (total 40), break before every column, width 25.
    // Row0 [0,2) (offset 20 ≤ 25; 30 > 25); Row1 [2,4) (20 ≤ 25).
    func testGreedyBreaksAtLastFittingOpportunity() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0, 10.0], breakColumns: [1, 2, 3])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 25.0, metrics: metrics))
        XCTAssertEqual(rows, [
            VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 2, width: 20.0),
            VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0),
        ])
    }

    // Only column 2 is breakable. width 25. The core may end a row only at 2 or 4,
    // never at 1 or 3, even though cells would otherwise fit.
    func testBreakOnlyAtDeclaredOpportunities() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0, 10.0], breakColumns: [2])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 25.0, metrics: metrics))
        XCTAssertEqual(rows, [
            VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 2, width: 20.0),
            VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 2, endColumn: 4, width: 20.0),
        ])
    }

    // No interior breaks; width 5 < total 40. One overflowing row wider than width.
    func testUnbreakableRunOverflowsOneRow() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0, 10.0], breakColumns: [])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 5.0, metrics: metrics))
        XCTAssertEqual(rows, [VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 4, width: 40.0)])
    }

    // Break before every column; width 5 < each advance 10 ⇒ one cell per row.
    func testCharWrapOneCellPerRow() {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0], breakColumns: [1, 2])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 5.0, metrics: metrics))
        XCTAssertEqual(rows, [
            VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 1, width: 10.0),
            VisualRow(logicalLine: 0, rowInLine: 1, startColumn: 1, endColumn: 2, width: 10.0),
            VisualRow(logicalLine: 0, rowInLine: 2, startColumn: 2, endColumn: 3, width: 10.0),
        ])
    }

    // Property: rows are contiguous, cover [0, count), non-empty, rowInLine 0-based
    // monotone, logicalLine constant — for an irregular line.
    func testPartitionTilesTheLine() {
        let advances = [7.0, 13.0, 5.0, 21.0, 9.0, 4.0] // offsets [0,7,20,25,46,55,59]
        let metrics = TestWrapMetrics(advances: advances, breakColumns: [1, 2, 3, 4, 5])
        let rows = collectRows(ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 20.0, metrics: metrics))
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(rows.first?.startColumn, 0)
        XCTAssertEqual(rows.last?.endColumn, advances.count)
        for (i, row) in rows.enumerated() {
            XCTAssertEqual(row.rowInLine, i, "rowInLine at \(i)")
            XCTAssertEqual(row.logicalLine, 0)
            XCTAssertLessThan(row.startColumn, row.endColumn, "non-empty row \(i)")
            if i > 0 { XCTAssertEqual(row.startColumn, rows[i - 1].endColumn, "contiguous at \(i)") }
        }
    }
}
