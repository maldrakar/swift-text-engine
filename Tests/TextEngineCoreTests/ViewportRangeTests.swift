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

    func testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine() {
        let lineHeight = 0.1
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: lineHeight,
            scrollOffsetY: 0.0,
            viewportHeight: lineHeight * 3,
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
                    isAtBottom: false
                )
            )
        )
    }

    func testFractionalLineHeightStartBoundaryBeginsAtExactLine() {
        let lineHeight = 0.1
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: lineHeight,
            scrollOffsetY: lineHeight * 3,
            viewportHeight: lineHeight * 2,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 3,
                    visibleEndExclusive: 5,
                    bufferStart: 3,
                    bufferEndExclusive: 5,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testFractionalLineHeightSublineOffsetIncludesPartialLines() {
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: 0.1,
            scrollOffsetY: 0.05,
            viewportHeight: 0.2,
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
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testLargeEndPartialLineDoesNotSnapDownToBoundary() {
        let input = ViewportInput(
            lineCount: 1_000_010,
            lineHeight: 1.0,
            scrollOffsetY: 1_000_000.0,
            viewportHeight: 3.0000000005,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 1_000_000,
                    visibleEndExclusive: 1_000_004,
                    bufferStart: 1_000_000,
                    bufferEndExclusive: 1_000_004,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testLargeStartPartialLineDoesNotSnapUpToBoundary() {
        let input = ViewportInput(
            lineCount: 1_000_010,
            lineHeight: 1.0,
            scrollOffsetY: 1_000_000.9999999995,
            viewportHeight: 2.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 1_000_000,
                    visibleEndExclusive: 1_000_003,
                    bufferStart: 1_000_000,
                    bufferEndExclusive: 1_000_003,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testLargeFractionalOffsetDoesNotSnapToBoundary() {
        let baseLine = 1_000_000_000_000_000
        let input = ViewportInput(
            lineCount: baseLine + 10,
            lineHeight: 1.0,
            scrollOffsetY: Double(baseLine) + 0.75,
            viewportHeight: 2.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: baseLine,
                    visibleEndExclusive: baseLine + 3,
                    bufferStart: baseLine,
                    bufferEndExclusive: baseLine + 3,
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

    func testFiniteExtremeOffsetClampsIndexBeforeIntConversion() {
        let input = ViewportInput(
            lineCount: Int.max,
            lineHeight: 1.0,
            scrollOffsetY: Double(Int.max),
            viewportHeight: 0.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: Int.max,
                    visibleEndExclusive: Int.max,
                    bufferStart: Int.max,
                    bufferEndExclusive: Int.max,
                    isAtTop: false,
                    isAtBottom: true
                )
            )
        )
    }
}
