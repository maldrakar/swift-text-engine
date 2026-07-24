import XCTest
import TextEngineCore

final class WrapComputeValidationTests: XCTestCase {
    private func goodInput() -> VariableViewportInput {
        VariableViewportInput(scrollOffsetY: 0, viewportHeight: 30, overscanLinesBefore: 0, overscanLinesAfter: 0)
    }
    private func rigged(lineCount: Int = 2, rowHeight: Double = 5.0, wrapWidth: Double = 20.0, firstRow: [Int] = [0, 1, 2]) -> RiggedVisualRowLayout {
        RiggedVisualRowLayout(lineCount: lineCount, rowHeight: rowHeight, wrapWidth: wrapWidth, firstRow: firstRow)
    }
    private func expectFailure(_ input: VariableViewportInput, _ layout: RiggedVisualRowLayout, _ expected: ViewportValidationError,
                               _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertEqual(ViewportVirtualizer.compute(input, layout: layout), .failure(expected), file: file, line: line)
    }

    func testNegativeLineCount() { expectFailure(goodInput(), rigged(lineCount: -1, firstRow: [0]), .negativeLineCount) }
    func testNonFiniteScroll() {
        expectFailure(VariableViewportInput(scrollOffsetY: .nan, viewportHeight: 30, overscanLinesBefore: 0, overscanLinesAfter: 0), rigged(), .nonFiniteValue)
    }
    func testNegativeViewportHeight() {
        expectFailure(VariableViewportInput(scrollOffsetY: 0, viewportHeight: -1, overscanLinesBefore: 0, overscanLinesAfter: 0), rigged(), .negativeViewportHeight)
    }
    func testNegativeOverscan() {
        expectFailure(VariableViewportInput(scrollOffsetY: 0, viewportHeight: 30, overscanLinesBefore: -1, overscanLinesAfter: 0), rigged(), .negativeOverscan)
    }
    func testNonPositiveRowHeight() {
        for h in [0.0, -1.0, -Double.infinity, Double.nan] {
            expectFailure(goodInput(), rigged(rowHeight: h), .nonPositiveRowHeight)
        }
    }
    func testNonPositiveWrapWidth() {
        for w in [0.0, -1.0, -Double.infinity, Double.nan] {
            expectFailure(goodInput(), rigged(wrapWidth: w), .nonPositiveWrapWidth)
        }
    }
    func testInfiniteWrapWidthDoesNotFail() {
        // .infinity is legal; a well-formed ∞-width layout succeeds.
        let layout = TestVisualRowLayout(lines: [(advances: [5], breaks: [])], rowHeight: 5.0, wrapWidth: .infinity)
        if case .failure = ViewportVirtualizer.compute(goodInput(), layout: layout) { XCTFail("∞ width must not fail") }
    }
    func testFirstVisualRowZeroNotZero() { expectFailure(goodInput(), rigged(firstRow: [5, 6, 7]), .invalidVisualRowLayout) }
    func testNonPositiveTotalRows() { expectFailure(goodInput(), rigged(lineCount: 1, firstRow: [0, 0]), .invalidVisualRowLayout) }
    func testTotalHeightOverflowIsWrapCoherent() {
        // huge totalRows * huge rowHeight overflows to +∞ -> the wrap-specific case,
        // NOT the reused overload's .invalidLineMetrics leaking through.
        let huge = 1 << 40
        expectFailure(goodInput(), rigged(lineCount: 1, rowHeight: .greatestFiniteMagnitude, firstRow: [0, huge]), .invalidVisualRowLayout)
    }
    func testLadderOrderLineCountBeforeRowHeight() {
        // Both lineCount<0 AND rowHeight<=0 -> the earlier probe (negativeLineCount) wins.
        expectFailure(goodInput(), rigged(lineCount: -1, rowHeight: -1, firstRow: [0]), .negativeLineCount)
    }
}
