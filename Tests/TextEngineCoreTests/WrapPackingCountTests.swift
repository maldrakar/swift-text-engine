import XCTest
import TextEngineCore

/// Decision 12's two O(1) cases (slice 55 spec), pinned at node 1's own entry point.
///
/// Result-bearing suites cannot see this: the short-circuit changes no row, so a
/// version that fires on too few rows -- say only when `start == 0` -- leaves every
/// packing result, every checksum and every result test green while the cost claim in
/// AGENTS.md ("the last row of every line [packs in O(1)] unless it overflows") is
/// false. Only a probe count can read it. Both cases are RED on the packer as shipped
/// before slice 55a.
final class WrapPackingCountTests: XCTestCase {
    private final class ProbeCounter {
        var columnCountCalls = 0
        var columnOffsetCalls = 0
        var canBreakCalls = 0
    }

    private struct CountingWrapMetrics: WrapMetricsSource {
        let base: TestWrapMetrics
        let counter: ProbeCounter
        func columnCount(inLine line: Int) -> Int {
            counter.columnCountCalls += 1; return base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.columnOffsetCalls += 1; return base.columnOffset(inLine: line, column: column)
        }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
            counter.canBreakCalls += 1; return base.canBreak(beforeColumn: column, inLine: line)
        }
    }

    // A line that fits: 8 cells of 10 (total 80) at width 100, breakable at every interior
    // column -- so a scan would have seven opportunities to read.
    func testFittingLinePacksWithoutScanning() {
        let counter = ProbeCounter()
        let metrics = CountingWrapMetrics(
            base: TestWrapMetrics(advances: Array(repeating: 10.0, count: 8), breakColumns: Set(1..<8)),
            counter: counter)
        guard case .rows(var cursor) = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 100.0, metrics: metrics) else {
            return XCTFail("expected .rows")
        }
        XCTAssertEqual(counter.columnCountCalls, 1, "the ladder reads columnCount once")
        XCTAssertEqual(counter.columnOffsetCalls, 2, "the ladder reads columnOffset(0) and columnOffset(count)")

        XCTAssertEqual(cursor.next(), VisualRow(logicalLine: 0, rowInLine: 0, startColumn: 0, endColumn: 8, width: 80.0))
        XCTAssertEqual(counter.canBreakCalls, 0, "a line that fits must not scan its break opportunities")
        // Exactly two more: the row's start and end offsets, nothing per cell. This is the
        // `+ 2` in node 4's `3 + 2` column-axis count.
        XCTAssertEqual(counter.columnOffsetCalls, 4, "next() on a fitting line reads start and end, and nothing else")
        XCTAssertNil(cursor.next())
    }

    // A wrapped line: 12 cells of 10 at width 40 -> rows [0,4) [4,8) [8,12). The last
    // row's remaining suffix fits by definition, so it must add no scan; the row before
    // it must, or "adds zero" would be vacuous.
    func testLastRowOfAWrappedLineAddsNoScan() {
        let counter = ProbeCounter()
        let metrics = CountingWrapMetrics(
            base: TestWrapMetrics(advances: Array(repeating: 10.0, count: 12), breakColumns: Set(1..<12)),
            counter: counter)
        guard case .rows(var cursor) = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 40.0, metrics: metrics) else {
            return XCTFail("expected .rows")
        }
        var rows: [VisualRow] = []
        var canBreakAfterRow: [Int] = []
        while let row = cursor.next() {
            rows.append(row)
            canBreakAfterRow.append(counter.canBreakCalls)
        }
        XCTAssertEqual(rows.map { $0.endColumn }, [4, 8, 12], "fixture must pack to exactly three rows")

        let penultimateAdded = canBreakAfterRow[1] - canBreakAfterRow[0]
        let lastAdded = canBreakAfterRow[2] - canBreakAfterRow[1]
        XCTAssertGreaterThan(penultimateAdded, 0, "fixture guard: an interior row must scan, or the assertion below covers nothing")
        XCTAssertEqual(lastAdded, 0, "the last row of a wrapped line must not scan -- its suffix fits")
    }
}
