import XCTest
import TextEngineCore

/// The LAYOUT-axis probe bound. This harness sees one of the two searches by
/// construction: `visualRowAt` builds its `UniformLineMetrics` INSIDE the core, so a
/// counting wrapper around `layout` cannot observe the row-axis search at all. That is
/// not a gap being papered over — `UniformLineMetrics.offset` is pure arithmetic touching
/// no provider, and the row-axis search is pinned by `LineAtQueryCountTests`
/// (`testInRangeUsesLogarithmicQueriesAtOneMillionLines`, whose
/// `expectedMax = 2 + (ceilLog2(lineCount) + 1)` is the shape the bound below copies).
///
/// On neither axis is the count constant in document size: "bounded" here means
/// LOGARITHMIC, in the vocabulary the no-wrap suite already uses.
final class WrapRowQueryCountTests: XCTestCase {
    private final class ProbeCounter {
        var firstVisualRowCalls = 0
        var visualRowCountCalls = 0

        /// Every bound below is checked against this SUM, not either field alone. A
        /// bound pinned to only `firstVisualRowCalls` would go blind to a scan that
        /// walks the document by reading `visualRowCount(inLine:)` per step instead —
        /// exactly the mutation form the widened Drill 5 exercises — and the reverse
        /// holds too. Summing both provider calls closes that hole: a scan cannot hide
        /// in whichever one the counter used to ignore.
        var totalCalls: Int { firstVisualRowCalls + visualRowCountCalls }
    }

    private struct CountingVisualRowLayout: VisualRowLayoutSource {
        let base: TestVisualRowLayout
        let counter: ProbeCounter

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }

        func visualRowCount(inLine line: Int) -> Int {
            counter.visualRowCountCalls += 1
            return base.visualRowCount(inLine: line)
        }

        func firstVisualRow(ofLine line: Int) -> Int {
            counter.firstVisualRowCalls += 1
            return base.firstVisualRow(ofLine: line)
        }
        // logicalLine(containingVisualRow:) is deliberately NOT overridden: the default
        // binary search runs against this wrapper, so its probes are counted.
    }

    // Identical to the six existing *QueryCountTests — same helper, same shape.
    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value {
            capacity <<= 1
            power += 1
        }
        return power
    }

    private static let lineCount = 1_024
    private static let rowHeight = 16.0
    /// Rows per line in the multi-row fixture below. 8 is arbitrary but > 1 by a margin:
    /// a per-row cost term has to show up as a multiple, not as a rounding difference.
    private static let rowsPerLine = 8

    private func counting() -> (CountingVisualRowLayout, ProbeCounter) {
        let base = TestVisualRowLayout(
            lines: Array(repeating: (advances: [8.0], breaks: Set<Int>()), count: Self.lineCount),
            rowHeight: Self.rowHeight,
            wrapWidth: .infinity)
        let counter = ProbeCounter()
        return (CountingVisualRowLayout(base: base, counter: counter), counter)
    }

    /// The same document at `totalRows == rowsPerLine * lineCount`, not `== lineCount`.
    ///
    /// `counting()` above wraps at `.infinity`, so every line packs to exactly one row
    /// and the two axes coincide. That fixture is blind by construction to any cost term
    /// proportional to rows *within* a line: at one row per line there is no such thing
    /// to be proportional to. Eight cells of advance 8 with a break before each, at
    /// `wrapWidth: 8`, pack one cell per row — so this fixture holds `lineCount` fixed
    /// and multiplies the row axis by 8, which is the only way the counter can tell a
    /// per-line term from a per-row one.
    private func countingMultiRow() -> (CountingVisualRowLayout, ProbeCounter) {
        let advances = Array(repeating: 8.0, count: Self.rowsPerLine)
        let breaks = Set(1..<Self.rowsPerLine)
        let base = TestVisualRowLayout(
            lines: Array(repeating: (advances: advances, breaks: breaks), count: Self.lineCount),
            rowHeight: Self.rowHeight,
            wrapWidth: 8.0)
        let counter = ProbeCounter()
        return (CountingVisualRowLayout(base: base, counter: counter), counter)
    }

    // 2 ladder probes (firstVisualRow(0), firstVisualRow(lineCount))
    // + <= ceilLog2(lineCount) + 1 inside the default logicalLine search
    // + 1 final probe for the rowInLine subtraction.
    //
    // The bound is tight at 1024 lines but not uniformly across every test: the
    // clamped-to-bottom sample (testClampedQueriesStillSearchTheLayoutAxis, y past the
    // document's end) drives the default binary search to its full 11-probe worst
    // case, landing exactly on 2 + 11 + 1 = 14 = ceilLog2(1024) + 4 — no slack there.
    // The in-range sample (testInRangeQueryIsLogarithmicOnTheLayoutAxis) measures one
    // probe under, at 13, because its target isn't the search's adversarial worst
    // case. Slack is still what lets a regression hide, so if a future change makes
    // either test red, check whether a probe was genuinely added before widening the
    // bound.
    private var expectedMax: Int { ceilLog2(Self.lineCount) + 4 }

    func testInRangeQueryIsLogarithmicOnTheLayoutAxis() {
        let (layout, counter) = counting()
        guard case .row = ViewportVirtualizer.visualRowAt(y: 700.0 * Self.rowHeight + 3.0, layout: layout) else {
            return XCTFail("expected .row")
        }
        XCTAssertLessThanOrEqual(counter.totalCalls, expectedMax)
    }

    /// The layout axis's IN-RANGE worst case, held to the tight bound with NO slack
    /// (D-25, discharged in slice 55b). It used to assert `< lineCount / 10` — 102 against
    /// a sibling's 14 on the same fixture and the same located branch — so no
    /// implementation could fail it without the sibling failing first.
    ///
    /// The TARGET is what gives it a claim the sibling does not make, and tightening alone
    /// would not have: over 1 024 lines the default `logicalLine` search costs 10 probes at
    /// almost every target, so row 700 (the sibling) and row 1 000 (this test's old target)
    /// both measure `2 + 10 + 1 = 13` — same fixture, same branch, same count, same bound.
    /// Only rows 1 022 and 1 023 reach the search's 11-probe worst case, so row 1 022
    /// measures exactly `14 == ceilLog2(lineCount) + 4`: one added probe anywhere reddens
    /// here and nowhere else on the in-range branch.
    /// `testClampedQueriesStillSearchTheLayoutAxis` also reaches 14, but through the clamp
    /// branch, which is a different path.
    func testTheInRangeWorstCaseTargetHasNoSlackAgainstTheBound() {
        let (layout, counter) = counting()
        guard case .row(let located) = ViewportVirtualizer.visualRowAt(
            y: 1_022.0 * Self.rowHeight + 3.0, layout: layout
        ) else {
            return XCTFail("expected .row")
        }
        // Fixture guards: the target must be the one the doc comment names, and it must be
        // IN RANGE — a clamped target would measure the branch the sibling already covers.
        XCTAssertEqual(located.globalRow, 1_022)
        XCTAssertEqual(located.clamp, .inRange)
        XCTAssertLessThanOrEqual(counter.totalCalls, expectedMax)
    }

    /// `LineAtQueryCountTests.testClampBranchesDoNotSearch` pins a two-probe CONSTANT for
    /// clamped queries on the no-wrap axis. That does NOT carry over here, and this test
    /// states the difference so a reader who knows the no-wrap axis does not copy the
    /// constant across: `lineAt` does skip the row-axis search when clamping, but the
    /// `logicalLine` search on the layout axis still runs, because Decision 7 routes both
    /// edges through the same two provider calls as an in-range hit.
    func testClampedQueriesStillSearchTheLayoutAxis() {
        for y in [-1.0, Double(Self.lineCount) * Self.rowHeight + 1.0] {
            let (layout, counter) = counting()
            guard case .row(let located) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
                return XCTFail("expected .row at y=\(y)")
            }
            XCTAssertNotEqual(located.clamp, .inRange, "y=\(y) must clamp")
            XCTAssertGreaterThan(counter.totalCalls, 2,
                                 "the no-wrap axis's two-probe clamp constant must NOT hold here")
            XCTAssertLessThanOrEqual(counter.totalCalls, expectedMax, "y=\(y)")
        }
    }

    /// The bound stays keyed to `lineCount` when the row axis is eight times longer.
    ///
    /// `expectedMax` is `ceilLog2(lineCount) + 4` — never `ceilLog2(totalRows) + 4`,
    /// which at 8192 rows would allow 17 and hand three probes of slack to a regression.
    /// The layout axis is searched over LINES; rows within a line must cost nothing on
    /// it, and the only fixture that can say so is one where the two axes differ. Without
    /// this test, a term proportional to `rowInLine` is pinned by nothing in the suite —
    /// only by the observational benchmark's latency, which is not a gate.
    func testProbeCountIsIndependentOfRowsPerLine() {
        // Fixture guard, read off the uncounted `base`: if the packing ever stopped
        // producing 8 rows per line, this test would silently degenerate into a second
        // copy of the infinity fixture and keep passing while covering nothing.
        let (guardLayout, _) = countingMultiRow()
        XCTAssertEqual(guardLayout.base.firstVisualRow(ofLine: Self.lineCount),
                       Self.rowsPerLine * Self.lineCount,
                       "fixture must be multi-row, or this test covers nothing")

        // In range and deliberately NOT on its line's first row: global row 5603 is
        // line 700, row 3 — so a per-`rowInLine` term has three steps to show up in.
        let globalRow = 700 * Self.rowsPerLine + 3
        let (layout, counter) = countingMultiRow()
        guard case .row(let located) = ViewportVirtualizer.visualRowAt(
            y: Double(globalRow) * Self.rowHeight + 3.0, layout: layout
        ) else {
            return XCTFail("expected .row")
        }
        XCTAssertEqual(located.globalRow, globalRow)
        XCTAssertEqual(located.logicalLine, 700)
        XCTAssertEqual(located.rowInLine, 3, "the query must land INSIDE a line's rows")
        XCTAssertLessThanOrEqual(counter.totalCalls, expectedMax)

        // Both clamp edges on the same fixture. The bottom edge lands on the last row of
        // the last line (`rowInLine == rowsPerLine - 1`), the deepest within-line offset
        // the document has.
        for y in [-1.0, Double(Self.rowsPerLine * Self.lineCount) * Self.rowHeight + 1.0] {
            let (clampLayout, clampCounter) = countingMultiRow()
            guard case .row(let clamped) = ViewportVirtualizer.visualRowAt(y: y, layout: clampLayout) else {
                return XCTFail("expected .row at y=\(y)")
            }
            XCTAssertNotEqual(clamped.clamp, .inRange, "y=\(y) must clamp")
            XCTAssertLessThanOrEqual(clampCounter.totalCalls, expectedMax, "y=\(y)")
        }
    }
}
