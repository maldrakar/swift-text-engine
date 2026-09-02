import XCTest
import TextEngineCore

/// D-24. `logicalLine(containingVisualRow:)` is documented as provider-overridable with a
/// binary-search default -- in the protocol, in AGENTS.md, in visualRowAt's doc comment --
/// and until this file nothing pinned that a consumer dispatches through it: the slice-53
/// review's drill C replaced the dispatch in visualRowAt with a direct
/// binarySearchLogicalLine call and 397 tests stayed green. The conformer here overrides
/// the hook with the CORRECT answer and logs the call, so a test can only see dispatch.
/// Model: PointAtDispatchTests on the column axis.
final class VisualRowDispatchTests: XCTestCase {
    // 4 lines x 2 rows at width 20 (4 cells of 10, breakable everywhere): firstRow
    // [0,2,4,6,8], rowHeight 5, total height 40.
    private func base() -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: [10.0, 10.0, 10.0, 10.0], breaks: Set([1, 2, 3])), count: 4),
            rowHeight: 5.0, wrapWidth: 20.0)
    }

    private func recording() -> (OverridingLogicalLineLayout, HookLog) {
        let b = base()
        let log = HookLog()
        return (OverridingLogicalLineLayout(base: b, log: log, answer: { b.logicalLine(containingVisualRow: $0) }), log)
    }

    func testVisualRowAtDispatchesThroughTheHookExactlyOnce() {
        let (layout, log) = recording()
        // y = 27 -> global row 5 = line 2, row 1.
        XCTAssertEqual(ViewportVirtualizer.visualRowAt(y: 27.0, layout: layout),
                       .row(VisualRowLocation(globalRow: 5, logicalLine: 2, rowInLine: 1, clamp: .inRange)))
        XCTAssertEqual(log.logicalLineCalls, [5], "one dispatch, with the located global row")
    }

    // Node 3's Decision 7: clamped queries take no special case -- both edges go through
    // the same provider search as an in-range hit, so the dispatch must show there too.
    func testClampedVisualRowAtStillDispatchesThroughTheHook() {
        for (y, expectedRow) in [(-1.0, 0), (1_000.0, 7)] {
            let (layout, log) = recording()
            guard case .row(let located) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) else {
                return XCTFail("expected .row at y=\(y)")
            }
            XCTAssertEqual(located.globalRow, expectedRow, "y=\(y)")
            XCTAssertNotEqual(located.clamp, .inRange, "y=\(y) must clamp")
            XCTAssertEqual(log.logicalLineCalls, [expectedRow], "y=\(y): the clamped edge dispatches once")
        }
    }

    func testDocumentCursorDispatchesThroughTheHookOnceForTheBufferStart() {
        let (layout, log) = recording()
        let input = VariableViewportInput(scrollOffsetY: 25, viewportHeight: 10, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout) else { return XCTFail("expected success") }
        XCTAssertEqual(log.logicalLineCalls, [], "compute never consults the hook")
        XCTAssertEqual(range.bufferStart, 5, "fixture: buffer starts at row 1 of line 2")

        let rows = collectGeometry(ViewportVirtualizer.visualRowGeometry(for: range, layout: layout))
        XCTAssertEqual(rows.first?.row.logicalLine, 2)
        XCTAssertEqual(rows.first?.row.rowInLine, 1)
        XCTAssertEqual(log.logicalLineCalls, [range.bufferStart], "one dispatch for the buffer start; the stream itself never searches")
    }
}
