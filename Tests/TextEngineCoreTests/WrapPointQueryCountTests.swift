import XCTest
import TextEngineCore

/// The probe table of the slice-55 spec's Contract 55b. Two counters and two fixtures,
/// because the four quantities cannot share one harness (Testing Strategy):
///
///  * Counter 1, the LAYOUT axis (`firstVisualRow` + `visualRowCount`): node 3's constant
///    `<= ceilLog2(lineCount) + 4`, unchanged and still tight, because node 4 adds NO
///    layout-axis probe. Never `ceilLog2(totalRows)` — the row-axis search touches no
///    provider (`UniformLineMetrics.offset` is arithmetic), so such a term would count
///    nothing and hand slack to a regression. It is pinned where it IS observable, by
///    `LineAtQueryCountTests`.
///  * Counter 2, the COLUMN axis (`columnCount` + `columnOffset` + `canBreak`).
///  * Fixture 1 does NOT override either inverse hook, so the default searches run
///    against the wrapper and their probes are counted.
///  * Fixture 2 OVERRIDES both, which is the only way to count "exactly one dispatch" —
///    and the reason it cannot double as fixture 1.
final class WrapPointQueryCountTests: XCTestCase {
    private final class ProbeCounter {
        var firstVisualRowCalls = 0
        var visualRowCountCalls = 0
        var columnCountCalls = 0
        var columnOffsetCalls = 0
        var canBreakCalls = 0
        var logicalLineDispatches = 0
        var columnIndexDispatches = 0

        /// Summed, exactly as node 3 sums its two fields: a bound pinned to one accessor
        /// goes blind to a scan that walks the document through the other.
        var layoutCalls: Int { firstVisualRowCalls + visualRowCountCalls }
        var columnCalls: Int { columnCountCalls + columnOffsetCalls + canBreakCalls }
    }

    /// Fixture 1 — counts both axes, overrides neither hook.
    private struct CountingLayout: VisualRowLayoutSource {
        let base: TestVisualRowLayout
        let counter: ProbeCounter

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int {
            counter.columnCountCalls += 1; return base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.columnOffsetCalls += 1; return base.columnOffset(inLine: line, column: column)
        }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
            counter.canBreakCalls += 1; return base.canBreak(beforeColumn: column, inLine: line)
        }
        func visualRowCount(inLine line: Int) -> Int {
            counter.visualRowCountCalls += 1; return base.visualRowCount(inLine: line)
        }
        func firstVisualRow(ofLine line: Int) -> Int {
            counter.firstVisualRowCalls += 1; return base.firstVisualRow(ofLine: line)
        }
    }

    /// Fixture 2 — counts both axes AND overrides both inverse hooks with the correct
    /// answers, forwarding to `base` so the hooks' own probes are not counted.
    private struct CountingOverridingLayout: VisualRowLayoutSource {
        let base: TestVisualRowLayout
        let counter: ProbeCounter

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int {
            counter.columnCountCalls += 1; return base.columnCount(inLine: line)
        }
        func columnOffset(inLine line: Int, column: Int) -> Double {
            counter.columnOffsetCalls += 1; return base.columnOffset(inLine: line, column: column)
        }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
            counter.canBreakCalls += 1; return base.canBreak(beforeColumn: column, inLine: line)
        }
        func visualRowCount(inLine line: Int) -> Int {
            counter.visualRowCountCalls += 1; return base.visualRowCount(inLine: line)
        }
        func firstVisualRow(ofLine line: Int) -> Int {
            counter.firstVisualRowCalls += 1; return base.firstVisualRow(ofLine: line)
        }
        func logicalLine(containingVisualRow g: Int) -> Int {
            counter.logicalLineDispatches += 1; return base.logicalLine(containingVisualRow: g)
        }
        func columnIndex(containingOffset x: Double, inLine line: Int) -> Int {
            counter.columnIndexDispatches += 1; return base.columnIndex(containingOffset: x, inLine: line)
        }
    }

    // Identical to the seven existing *QueryCountTests — same helper, same shape.
    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value { capacity <<= 1; power += 1 }
        return power
    }

    private static let lineCount = 1_024
    private static let rowHeight = 16.0
    private var expectedMax: Int { ceilLog2(Self.lineCount) + 4 }

    /// 1024 lines, one 8-wide cell each, at ∞ — one row per line, and the line FITS, so
    /// the packer short-circuits and the exact column counts below are the `3 + 2` of the
    /// spec's table.
    private static func fittingLines() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: [8.0], breaks: Set<Int>()), count: lineCount),
            rowHeight: rowHeight, wrapWidth: .infinity)
    }

    /// One line of 4 cells x 10 at ∞ — the fitting-line fixture for the exact counts,
    /// small enough that the numbers are read rather than bounded.
    private static func oneFittingLine() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [(advances: Array(repeating: 10.0, count: 4), breaks: Set([1, 2, 3]))],
            rowHeight: rowHeight, wrapWidth: .infinity)
    }

    /// One line of 100 cells x 10 at width 50 — 5 cells per row, 20 rows. Char-wrap, so
    /// every interior column is a break opportunity and an interior row genuinely scans.
    private static func wrappedLine() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: [(advances: Array(repeating: 10.0, count: 100), breaks: Set(1..<100))],
            rowHeight: rowHeight, wrapWidth: 50.0)
    }

    // ---- Counter 1: the layout axis ----

    /// The IN-RANGE branch, at the target where the bound carries ZERO slack.
    ///
    /// The target is load-bearing, and picking it by convenience is the D-25 defect this
    /// same slice discharges on the sibling axis: over 1 024 lines the default
    /// `logicalLine` search costs 10 probes at almost every row, so row 700 measures
    /// `2 + 10 + 1 = 13` against a bound of 14 — one probe of slack, and a `visualPointAt`
    /// that added a layout-axis probe would pass. Only rows 1 022 and 1 023 reach the
    /// search's 11-probe worst case, where the count is exactly `ceilLog2(lineCount) + 4`.
    /// `testClampedQueriesDoNotWidenTheLayoutBound` also reaches 14, but on the clamp
    /// branch — a different path, exactly as `WrapRowQueryCountTests` records for its own
    /// pair.
    ///
    /// The claim this pins is node 4's: it adds NO layout-axis probe over node 3.
    func testLayoutAxisStaysLogarithmicInLineCount() {
        let counter = ProbeCounter()
        let layout = CountingLayout(base: Self.fittingLines(), counter: counter)
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(
            x: 4.0, y: 1_022.0 * Self.rowHeight + 3.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        // Fixture guards: the target must be the row the doc comment names, and it must be
        // IN RANGE -- a clamped target would measure the branch the sibling below covers.
        XCTAssertEqual(point.row.globalRow, 1_022)
        XCTAssertEqual(point.row.clamp, .inRange)
        // node 3's constant, copied and NOT widened: 2 ladder probes + <= ceilLog2 + 1
        // inside the default logicalLine search + 1 for the rowInLine subtraction.
        XCTAssertLessThanOrEqual(counter.layoutCalls, expectedMax)
    }

    func testClampedQueriesDoNotWidenTheLayoutBound() {
        for y in [-1.0, Double(Self.lineCount) * Self.rowHeight + 1.0] {
            let counter = ProbeCounter()
            let layout = CountingLayout(base: Self.fittingLines(), counter: counter)
            guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 4.0, y: y, layout: layout) else {
                return XCTFail("expected .point at y=\(y)")
            }
            XCTAssertNotEqual(point.row.clamp, .inRange, "y=\(y) must clamp")
            XCTAssertLessThanOrEqual(counter.layoutCalls, expectedMax, "y=\(y)")
        }
    }

    // ---- Counter 2: zero column-metric calls on every non-located path ----
    //
    // This is the ONLY observation of the `x` rung's PLACEMENT rather than its result: an
    // implementation that checked `x` after the walk would pass the ±∞ result tests
    // unchanged, and the walk is the expensive half.

    func testEmptyDocumentTouchesNoColumnMetrics() {
        let counter = ProbeCounter()
        let layout = CountingLayout(
            base: TestVisualRowLayout(lines: [], rowHeight: Self.rowHeight, wrapWidth: .infinity),
            counter: counter)
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .empty)
        XCTAssertEqual(counter.columnCalls, 0)
    }

    func testVerticalFailureTouchesNoColumnMetrics() {
        let counter = ProbeCounter()
        let layout = CountingLayout(base: Self.oneFittingLine(), counter: counter)
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: .nan, layout: layout),
                       .failure(.nonFiniteValue))
        XCTAssertEqual(counter.columnCalls, 0)
    }

    func testNonFiniteXTouchesNoColumnMetrics() {
        for x in [Double.infinity, -.infinity, .nan] {
            let counter = ProbeCounter()
            let layout = CountingLayout(base: Self.oneFittingLine(), counter: counter)
            XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: x, y: 5.0, layout: layout),
                           .failure(.nonFiniteValue), "x=\(x)")
            XCTAssertEqual(counter.columnCalls, 0,
                           "x=\(x): the x rung must run BEFORE any horizontal work")
        }
    }

    // ---- Counter 2: the exact counts on a fitting line ----

    func testFittingLineClampedCostsThreePlusTwo() {
        let counter = ProbeCounter()
        let layout = CountingOverridingLayout(base: Self.oneFittingLine(), counter: counter)
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: -1.0, y: 5.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 0, clamp: .clampedToLeft)))
        // 3 in the shared ladder (columnCount, columnOffset(0), columnOffset(count))
        // + 2 in the one row the cursor yields (its start and end offsets).
        // Nothing for Decision 12's predicate or Decision 14's guard: both read stored
        // values. Nothing for rowLeft: a clamped x never reads it.
        XCTAssertEqual(counter.columnCalls, 5)
        XCTAssertEqual(counter.columnIndexDispatches, 0, "a clamped x must not dispatch")
        XCTAssertEqual(counter.logicalLineDispatches, 1)
    }

    func testFittingLineDelegatingCostsThreePlusTwoPlusOneAndOneDispatch() {
        let counter = ProbeCounter()
        let layout = CountingOverridingLayout(base: Self.oneFittingLine(), counter: counter)
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 15.0, y: 5.0, layout: layout) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.column, .cell(ColumnLocation(columnIndex: 1, clamp: .inRange)))
        XCTAssertEqual(counter.columnCalls, 6, "3 ladder + 2 row + 1 rowLeft")
        XCTAssertEqual(counter.columnIndexDispatches, 1, "exactly one dispatch through the provider hook")
        XCTAssertEqual(counter.logicalLineDispatches, 1)
    }

    // ---- Counter 2: growth with rowInLine, as a LOWER bound ----

    /// "Strictly more" is not enough: it passes on a growth of one probe, and that is
    /// D-25's shape. The bound is the cells the scan MUST pay for the rows between the two
    /// samples — `endColumn(k + m) − endColumn(k)`. On a uniform fixture that equals the
    /// start-column distance, which is why the phrasing matters: the quantity is the END
    /// columns.
    func testColumnCostGrowsWithTheRowInLine() {
        let base = Self.wrappedLine()
        // Fixture guards. The line must EXCEED the width (a fitting line has one row and
        // no growth), and neither sampled row may be its last (a last row packs in O(1),
        // so the test would measure one row less than its name says).
        XCTAssertEqual(base.visualRowCount(inLine: 0), 20, "fixture: the line must wrap into 20 rows")

        func columnCalls(atRow rowInLine: Int) -> Int {
            let counter = ProbeCounter()
            let layout = CountingLayout(base: base, counter: counter)
            let y = Double(rowInLine) * Self.rowHeight + Self.rowHeight / 2.0
            guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 5.0, y: y, layout: layout) else {
                XCTFail("expected .point at rowInLine=\(rowInLine)"); return 0
            }
            XCTAssertEqual(point.row.rowInLine, rowInLine)
            return counter.columnCalls
        }

        let near = 2
        let far = 10
        // Derived from the fixture, never a literal: written as `XCTAssertLessThan(far, 19)`
        // this compared two constants and could not fail, so a fixture reshaped to ten rows
        // would leave `far` ON the last row with the guard still green -- D-25's own shape,
        // in the task that discharges D-25.
        XCTAssertLessThan(far, base.visualRowCount(inLine: 0) - 1,
                          "neither sample may be the line's last row")
        // Derived, never transcribed (D-38). Rows are uniform here, so cells-per-row is
        // the fixture's own quotient; the guard makes the uniformity a checked premise
        // rather than an assumption inherited from the comment above.
        let rowCount = base.visualRowCount(inLine: 0)
        let cellCount = base.columnCount(inLine: 0)
        XCTAssertEqual(cellCount % rowCount, 0, "fixture: rows must hold equal cell counts")
        let cellsPerRow = cellCount / rowCount
        let mustScan = (far - near) * cellsPerRow
        XCTAssertGreaterThanOrEqual(columnCalls(atRow: far) - columnCalls(atRow: near), mustScan)
    }
}
