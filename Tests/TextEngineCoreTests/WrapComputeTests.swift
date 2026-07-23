import XCTest
import TextEngineCore

final class WrapComputeTests: XCTestCase {
    // 4 lines, each 4 cells advance 10, break at every cell, width 20 -> 2 rows/line.
    // totalRows = 8 (NOT lineCount 4). rowHeight 5 -> total height 40.
    private func layout(width: Double = 20.0) -> TestVisualRowLayout {
        TestVisualRowLayout(
            lines: Array(repeating: (advances: [10.0, 10.0, 10.0, 10.0], breaks: Set([1, 2, 3])), count: 4),
            rowHeight: 5.0,
            wrapWidth: width
        )
    }

    // A viewport of height 15 from the top covers rows [0,3): 3 visual rows, not 3 lines.
    // A stub compute that used lineCount (4) instead of totalRows (8) would clamp/scale
    // wrong here -- this is the finite-width test that the recorded-red stub fails.
    func testFiniteWidthVisibleRangeIsInVisualRows() {
        let input = VariableViewportInput(scrollOffsetY: 0, viewportHeight: 15, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(range.visibleStart, 0)
        XCTAssertEqual(range.visibleEndExclusive, 3)   // rows 0,1,2 (y in [0,15))
        XCTAssertTrue(range.isAtTop)
        XCTAssertFalse(range.isAtBottom)
    }

    // Scrolling to the very bottom: total height 40, viewport 15 -> maxOffset 25 ->
    // visibleStart at row 5 (y=25), through row 8. isAtBottom true.
    func testScrollToBottomIsInVisualRows() {
        let input = VariableViewportInput(scrollOffsetY: 9_999, viewportHeight: 15, overscanLinesBefore: 0, overscanLinesAfter: 0)
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: layout()) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(range.visibleEndExclusive, 8)   // 8 total rows
        XCTAssertTrue(range.isAtBottom)
    }
}
