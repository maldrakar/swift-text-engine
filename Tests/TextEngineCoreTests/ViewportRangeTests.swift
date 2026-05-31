import XCTest
@testable import TextEngineCore

final class ViewportRangeTests: XCTestCase {
    func testSublineOffsetUsesFloorForStartAndCeilForEnd() {
        let input = ViewportInput(
            lineCount: 100,
            lineHeight: 10.0,
            scrollOffsetY: 25.0,
            viewportHeight: 35.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 2,
                    visibleEndExclusive: 6,
                    bufferStart: 2,
                    bufferEndExclusive: 6,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testNegativeScrollOffsetClampsToTop() {
        let input = ViewportInput(
            lineCount: 100,
            lineHeight: 10.0,
            scrollOffsetY: -12.0,
            viewportHeight: 20.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 2,
                    bufferStart: 0,
                    bufferEndExclusive: 2,
                    isAtTop: true,
                    isAtBottom: false
                )
            )
        )
    }

    func testViewportLargerThanDocumentReturnsWholeDocument() {
        let input = ViewportInput(
            lineCount: 3,
            lineHeight: 10.0,
            scrollOffsetY: 40.0,
            viewportHeight: 100.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 3,
                    bufferStart: 0,
                    bufferEndExclusive: 3,
                    isAtTop: true,
                    isAtBottom: true
                )
            )
        )
    }

    func testZeroHeightViewportProducesEmptyRangeAtOffset() {
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 20.0,
            viewportHeight: 0.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 2,
                    visibleEndExclusive: 2,
                    bufferStart: 2,
                    bufferEndExclusive: 2,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }
}
