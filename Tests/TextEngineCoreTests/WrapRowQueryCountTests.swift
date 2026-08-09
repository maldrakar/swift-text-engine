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

    private func counting() -> (CountingVisualRowLayout, ProbeCounter) {
        let base = TestVisualRowLayout(
            lines: Array(repeating: (advances: [8.0], breaks: Set<Int>()), count: Self.lineCount),
            rowHeight: Self.rowHeight,
            wrapWidth: .infinity)
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

    func testProbeCountDoesNotGrowLinearlyWithTheDocument() {
        let (layout, counter) = counting()
        guard case .row = ViewportVirtualizer.visualRowAt(y: 1_000.0 * Self.rowHeight + 3.0, layout: layout) else {
            return XCTFail("expected .row")
        }
        // A linear walk over 1024 lines would blow this by two orders of magnitude.
        XCTAssertLessThan(counter.totalCalls, Self.lineCount / 10)
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
}
