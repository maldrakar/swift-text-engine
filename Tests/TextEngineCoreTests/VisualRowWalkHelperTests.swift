import XCTest
@testable import TextEngineCore

/// The shared within-line walk, pinned directly. Once both producers guard their own
/// input (slice 55 spec, Decision 4), no public entry point reaches the helper with
/// k < 0, so its own rule is observable only here. Three guards for one input, each with
/// its own drill -- do not read one of these reds as evidence for another.
final class VisualRowWalkHelperTests: XCTestCase {
    // Three rows [0,1) [1,2) [2,3): three cells of 10, breakable everywhere, width 5.
    private func cursor() -> VisualRowCursor<TestWrapMetrics> {
        let metrics = TestWrapMetrics(advances: [10.0, 10.0, 10.0], breakColumns: [1, 2])
        guard case .rows(let c) = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: 5.0, metrics: metrics) else {
            fatalError("fixture must pack")
        }
        return c
    }

    // Drill (f3): restore the raw `for _ in 0..<k` and this traps.
    func testNegativeCountReturnsNilWithoutTrapping() {
        var c = cursor()
        XCTAssertNil(advanceVisualRows(&c, by: -1))
        XCTAssertEqual(c.next()?.rowInLine, 0, "nothing may be consumed")
    }

    func testZeroCountReturnsNilAndConsumesNothing() {
        var c = cursor()
        XCTAssertNil(advanceVisualRows(&c, by: 0))
        XCTAssertEqual(c.next()?.rowInLine, 0)
    }

    // The k-th next() result, and the cursor is left AT row k. The second assertion is
    // the inout pin: a by-value helper would advance a copy and leave this cursor at row 0.
    func testReturnsTheKthRowAndLeavesTheCursorAfterIt() {
        var c = cursor()
        XCTAssertEqual(advanceVisualRows(&c, by: 2)?.rowInLine, 1)
        XCTAssertEqual(c.next()?.rowInLine, 2)
    }

    // Past the end the answer is nil -- NOT the last row that was seen. Node 4's
    // exhaustion guard rests on exactly this (spec Decision 4).
    func testPastTheEndReturnsNilNotTheLastRowSeen() {
        var c = cursor()
        XCTAssertNil(advanceVisualRows(&c, by: 4))
        XCTAssertNil(c.next())
    }

    // Stops at the first nil rather than spinning: a helper that looped k times over an
    // exhausted cursor would not return from Int.max.
    func testStopsAtTheFirstNilRatherThanSpinning() {
        var c = cursor()
        XCTAssertNil(advanceVisualRows(&c, by: Int.max))
    }
}
