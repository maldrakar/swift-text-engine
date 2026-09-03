import XCTest
import TextEngineCore

/// `visualPointAt`'s ladder, rung by rung (slice 55 spec, Decision 5), plus the three
/// ways a provider can be malformed. Every one of these outcomes is produced by code that
/// lives OUTSIDE this query: the vertical rungs and the two hook guards are
/// `visualRowAt`'s, the column rungs are `validateWrapLine`'s, and the helper's `k <= 0`
/// rule is `advanceVisualRows`'. This suite pins that they surface here unchanged.
final class WrapPointQueryValidationTests: XCTestCase {
    private static let rowHeight = 10.0
    private static let wrapWidth = 20.0

    /// Two lines x 2 rows at width 20 (4 cells of 10, breakable everywhere):
    /// firstVisualRow [0, 2, 4], total height 40.
    private static func good() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: Array(repeating: 10.0, count: 4), breaks: Set([1, 2, 3])), count: 2),
            rowHeight: rowHeight, wrapWidth: wrapWidth)
    }

    private static func blankLineLayout() -> TestVisualRowLayout {
        TestVisualRowLayout(lines: [(advances: [], breaks: [])], rowHeight: rowHeight, wrapWidth: wrapWidth)
    }

    private static func rigged(lineCount: Int, rowHeight: Double, wrapWidth: Double, firstRow: [Int]) -> RiggedVisualRowLayout {
        RiggedVisualRowLayout(lineCount: lineCount, rowHeight: rowHeight, wrapWidth: wrapWidth, firstRow: firstRow)
    }

    /// A layout whose ROW axis is sound and whose COLUMN metrics are not — the class the
    /// per-line ladder rejects. Only the queried accessor lies; `TestVisualRowLayout`
    /// packed its prefix sum from the honest metrics.
    private struct BrokenColumnLayout: VisualRowLayoutSource {
        let base: TestVisualRowLayout
        let negativeCount: Bool
        let offsetBias: Double

        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int { negativeCount ? -1 : base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) + offsetBias }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }
        func visualRowCount(inLine line: Int) -> Int { base.visualRowCount(inLine: line) }
        func firstVisualRow(ofLine line: Int) -> Int { base.firstVisualRow(ofLine: line) }
    }

    // ---- The vertical rungs, propagated verbatim from visualRowAt ----

    func testNegativeLineCountFails() {
        let layout = Self.rigged(lineCount: -1, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .failure(.negativeLineCount))
    }

    func testNonFiniteYBeatsTheEmptyDocument() {
        let layout = Self.rigged(lineCount: 0, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: .nan, layout: layout), .failure(.nonFiniteValue))
    }

    func testEmptyDocumentIsEmpty() {
        let layout = Self.rigged(lineCount: 0, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .empty)
    }

    /// Precedence pair 1 (Decision 5). `x` is examined only after the vertical half, so an
    /// empty document answers `.empty` even for a non-finite `x` — matching `pointAt`,
    /// whose doc comment states the same outcome for the same reason.
    func testEmptyDocumentBeatsANonFiniteX() {
        let layout = Self.rigged(lineCount: 0, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: .infinity, y: 1.0, layout: layout), .empty)
    }

    func testNonPositiveRowHeightFails() {
        let layout = Self.rigged(lineCount: 1, rowHeight: 0.0, wrapWidth: Self.wrapWidth, firstRow: [0, 1])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .failure(.nonPositiveRowHeight))
    }

    func testNonPositiveWrapWidthFails() {
        let layout = Self.rigged(lineCount: 1, rowHeight: Self.rowHeight, wrapWidth: 0.0, firstRow: [0, 1])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .failure(.nonPositiveWrapWidth))
    }

    func testMalformedPrefixSumFails() {
        let layout = Self.rigged(lineCount: 2, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [1, 2, 3])
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout), .failure(.invalidVisualRowLayout))
    }

    // ---- The x rung: a non-finite coordinate is a failure, not a clamp ----

    /// Both signs, named separately: WITHOUT this rung each reaches a DIFFERENT clamp
    /// branch (`+∞ >= rowSpan.width` and `-∞ < 0` are both true), so one test cannot stand
    /// for the other.
    func testPositiveInfinityXFailsRatherThanClampingRight() {
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: .infinity, y: 5.0, layout: Self.good()),
                       .failure(.nonFiniteValue))
    }

    func testNegativeInfinityXFailsRatherThanClampingLeft() {
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: -.infinity, y: 5.0, layout: Self.good()),
                       .failure(.nonFiniteValue))
    }

    func testNaNXFails() {
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: .nan, y: 5.0, layout: Self.good()),
                       .failure(.nonFiniteValue))
    }

    /// Precedence pair 2 (Decision 5): the `x` rung runs before the span is read, exactly
    /// as `columnAt` checks `x` before its `count == 0` short-circuit.
    func testNonFiniteXBeatsTheBlankLine() {
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: .infinity, y: 5.0, layout: Self.blankLineLayout()),
                       .failure(.nonFiniteValue))
        // Control: with a finite x the same layout answers .blankLine.
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: Self.blankLineLayout()) else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(point.column, .blankLine)
    }

    // ---- The column rungs, surfacing at the top level ----

    func testNegativeColumnCountSurfaces() {
        let layout = BrokenColumnLayout(base: Self.good(), negativeCount: true, offsetBias: 0.0)
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: layout),
                       .failure(.negativeColumnCount))
    }

    func testNonZeroFirstColumnOffsetSurfaces() {
        let layout = BrokenColumnLayout(base: Self.good(), negativeCount: false, offsetBias: 5.0)
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: layout),
                       .failure(.invalidColumnMetrics))
    }

    // ---- The three malformed-provider cases (Decision 4) ----

    /// Case 1, at THREE values. The boundary (`== lineCount`) does not trap at the named
    /// site, so a test carrying only the upper value leaves it unpinned; a negative value
    /// is what an edit to `logicalLine < lineCount` alone lets through.
    func testAnOutOfRangeLogicalLineOverrideFails() {
        for answer in [3, 2, -1] {           // lineCount == 2: above, at the boundary, below
            let base = Self.good()
            let log = HookLog()
            let layout = OverridingLogicalLineLayout(base: base, log: log, answer: { _ in answer })
            XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: layout),
                           .failure(.invalidVisualRowLayout), "answer=\(answer)")
            XCTAssertEqual(log.logicalLineCalls.count, 1, "answer=\(answer): the hook is consulted once")
        }
    }

    /// Case 2: an IN-RANGE line whose `firstVisualRow` exceeds the located row, so
    /// `rowInLine` goes negative. Global row 0 answered as line 1 (firstVisualRow 2)
    /// gives rowInLine -2.
    func testAnInRangeOverrideThatMakesRowInLineNegativeFails() {
        let base = Self.good()
        let layout = OverridingLogicalLineLayout(base: base, log: HookLog(), answer: { _ in 1 })
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 1.0, layout: layout),
                       .failure(.invalidVisualRowLayout))
    }

    /// Case 3 — the ONLY failure this query adds of its own: a layout whose row counts
    /// disagree with node 1's packer, so the walk runs out before the row it was asked
    /// for. `RiggedVisualRowLayout`'s stubbed column metrics describe a blank line (one
    /// packed row) while its prefix sum claims three.
    func testAWalkThatExhaustsEarlyFails() {
        let layout = Self.rigged(lineCount: 1, rowHeight: Self.rowHeight, wrapWidth: Self.wrapWidth, firstRow: [0, 3])

        // Control: row 0 exists in the packer's world and answers normally, so the failure
        // below is the WALK and not the fixture.
        guard case .point(let point) = ViewportVirtualizer.visualPointAt(x: 1.0, y: 5.0, layout: layout) else {
            return XCTFail("expected .point at the line's only packed row")
        }
        XCTAssertEqual(point.row, VisualRowLocation(globalRow: 0, logicalLine: 0, rowInLine: 0, clamp: .inRange))
        XCTAssertEqual(point.column, .blankLine)

        // Row 2 is claimed by the prefix sum and never produced by the packer.
        XCTAssertEqual(ViewportVirtualizer.visualPointAt(x: 1.0, y: 25.0, layout: layout),
                       .failure(.invalidVisualRowLayout))
    }
}
