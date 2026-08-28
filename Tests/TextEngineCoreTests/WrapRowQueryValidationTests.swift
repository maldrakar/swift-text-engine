import XCTest
import TextEngineCore

/// `visualRowAt`'s ladder, and its parity with `compute(_:layout:)`.
///
/// The two entry points share one layout helper, so parity catches DIVERGENCE — a check
/// that moved, fires in a different order, or exists on one side only. It cannot catch
/// ABSENCE: deleting a check from the shared helper changes both callers identically and
/// leaves parity green. That is what the per-error-case tests below are for, and
/// `wrapWidth` needs them most — it is the check this query never uses and a later reader
/// would delete as dead weight.
final class WrapRowQueryValidationTests: XCTestCase {
    private func rigged(lineCount: Int = 2, rowHeight: Double = 5.0, wrapWidth: Double = 20.0,
                        firstRow: [Int] = [0, 1, 2]) -> RiggedVisualRowLayout {
        RiggedVisualRowLayout(lineCount: lineCount, rowHeight: rowHeight, wrapWidth: wrapWidth, firstRow: firstRow)
    }

    private func expectFailure(_ y: Double, _ layout: RiggedVisualRowLayout, _ expected: ViewportValidationError,
                               _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: y, layout: layout), .failure(expected),
                       file: file, line: line)
    }

    // --- presence: one test per error case -------------------------------------

    func testNegativeLineCount() { expectFailure(0, rigged(lineCount: -1, firstRow: [0]), .negativeLineCount) }

    func testNonFiniteY() {
        for y in [Double.nan, .infinity, -.infinity] {
            expectFailure(y, rigged(), .nonFiniteValue)
        }
    }

    func testNonPositiveRowHeight() {
        for h in [0.0, -1.0, -Double.infinity, Double.nan] {
            expectFailure(0, rigged(rowHeight: h), .nonPositiveRowHeight)
        }
    }

    // The check this query never uses. Deleting it would let visualRowAt accept a layout
    // compute rejects — see the class comment and drill 6.
    func testNonPositiveWrapWidth() {
        for w in [0.0, -1.0, -Double.infinity, Double.nan] {
            expectFailure(0, rigged(wrapWidth: w), .nonPositiveWrapWidth)
        }
    }

    func testInfiniteWrapWidthDoesNotFail() {
        let layout = TestVisualRowLayout(lines: [(advances: [5.0], breaks: [])], rowHeight: 5.0, wrapWidth: .infinity)
        if case .failure = ViewportVirtualizer.visualRowAt(y: 0, layout: layout) { XCTFail("∞ width must not fail") }
    }

    func testFirstVisualRowZeroNotZero() { expectFailure(0, rigged(firstRow: [5, 6, 7]), .invalidVisualRowLayout) }

    func testNonPositiveTotalRows() { expectFailure(0, rigged(lineCount: 1, firstRow: [0, 0]), .invalidVisualRowLayout) }

    func testTotalHeightOverflowIsWrapCoherent() {
        let huge = 1 << 40
        expectFailure(0, rigged(lineCount: 1, rowHeight: .greatestFiniteMagnitude, firstRow: [0, huge]),
                      .invalidVisualRowLayout)
    }

    func testEmptyDocumentIsEmptyNotFailure() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 0, layout: rigged(lineCount: 0, firstRow: [0])), .empty)
    }

    // --- precedence -------------------------------------------------------------

    func testLadderOrderLineCountBeforeY() {
        expectFailure(.nan, rigged(lineCount: -1, firstRow: [0]), .negativeLineCount)
    }

    func testLadderOrderYBeforeRowHeight() {
        // y finiteness is this query's value check and sits above the layout half, exactly
        // as compute's input checks do.
        expectFailure(.nan, rigged(rowHeight: -1), .nonFiniteValue)
    }

    // --- parity with compute ----------------------------------------------------

    private func riggedMatrix() -> [(name: String, layout: RiggedVisualRowLayout)] {
        [
            ("valid", rigged()),
            ("negativeLineCount", rigged(lineCount: -1, firstRow: [0])),
            ("emptyDocument", rigged(lineCount: 0, firstRow: [0])),
            ("zeroRowHeight", rigged(rowHeight: 0)),
            ("nanRowHeight", rigged(rowHeight: .nan)),
            ("zeroWrapWidth", rigged(wrapWidth: 0)),
            ("nanWrapWidth", rigged(wrapWidth: .nan)),
            ("infiniteWrapWidth", rigged(wrapWidth: .infinity)),
            ("firstRowNotZero", rigged(firstRow: [5, 6, 7])),
            ("zeroTotalRows", rigged(lineCount: 1, firstRow: [0, 0])),
            ("totalHeightOverflow", rigged(lineCount: 1, rowHeight: .greatestFiniteMagnitude, firstRow: [0, 1 << 40])),
        ]
    }

    private func computeError(_ layout: RiggedVisualRowLayout, badValue: Bool) -> ViewportValidationError? {
        let input = VariableViewportInput(
            scrollOffsetY: badValue ? .nan : 0, viewportHeight: 30,
            overscanLinesBefore: 0, overscanLinesAfter: 0)
        if case .failure(let error) = ViewportVirtualizer.compute(input, layout: layout) { return error }
        return nil
    }

    private func rowError(_ layout: RiggedVisualRowLayout, badValue: Bool) -> ViewportValidationError? {
        if case .failure(let error) = ViewportVirtualizer.visualRowAt(y: badValue ? .nan : 0, layout: layout) {
            return error
        }
        return nil
    }

    func testLadderParityWithCompute() {
        for (name, layout) in riggedMatrix() {
            for badValue in [false, true] {
                XCTAssertEqual(
                    computeError(layout, badValue: badValue),
                    rowError(layout, badValue: badValue),
                    "\(name) (badValue: \(badValue)): compute and visualRowAt disagree")
            }
        }
    }

    // --- slice 55a, guards 1 and 2 (spec Decision 4): a malformed logicalLine override ---
    // RiggedVisualRowLayout cannot carry these: they need real column metrics behind an
    // overridden hook, so they run on TestVisualRowLayout wrapped by
    // OverridingLogicalLineLayout. If a case here seems to need a conformer whose
    // firstVisualRow is total just to survive, the guard has been placed in the wrong
    // function (it belongs here, at the producer, not in node 4's query).

    // 3 lines x 1 row at width 20; firstRow [0,1,2,3]. y = 7 -> global row 1.
    private func plainLayout() -> TestVisualRowLayout {
        TestVisualRowLayout(lines: Array(repeating: (advances: [5.0], breaks: Set<Int>()), count: 3),
                            rowHeight: 5.0, wrapWidth: 20.0)
    }

    private func overriding(_ answer: Int) -> OverridingLogicalLineLayout {
        OverridingLogicalLineLayout(base: plainLayout(), log: HookLog(), answer: { _ in answer })
    }

    // Traps at firstVisualRow (WrapPositionQuery.swift:41) on the shipped code. Drill (d1).
    func testHookAnsweringAboveLineCountIsRejectedNotTrapped() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 7.0, layout: overriding(4)), .failure(.invalidVisualRowLayout))
    }

    // The boundary does NOT trap at the named site (conformer arrays are lineCount + 1
    // long): the unguarded query reads totalRows, yields a negative rowInLine, and returns
    // a location naming no row. Carried as its own value so the pin does not rest on a trap.
    func testHookAnsweringExactlyLineCountIsRejected() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 7.0, layout: overriding(3)), .failure(.invalidVisualRowLayout))
    }

    // The natural wrong edit is `logicalLine < lineCount` alone; the two values above
    // cannot see it. Traps on the shipped code.
    func testHookAnsweringNegativeIsRejectedNotTrapped() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 7.0, layout: overriding(-1)), .failure(.invalidVisualRowLayout))
    }

    // Guard 2: an in-range line whose firstVisualRow exceeds the row -- line 2 for global
    // row 1 (firstVisualRow(2) = 2 > 1). The shipped code returns
    // .row(globalRow: 1, logicalLine: 2, rowInLine: -1, .inRange): a location naming no row.
    func testHookMakingRowInLineNegativeIsRejected() {
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 7.0, layout: overriding(2)), .failure(.invalidVisualRowLayout))
    }
}
