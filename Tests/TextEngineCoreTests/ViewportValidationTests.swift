import XCTest
@testable import TextEngineCore

final class ViewportValidationTests: XCTestCase {
    func testNegativeLineCountFails() {
        let input = ViewportInput(
            lineCount: -1,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: 50.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(ViewportVirtualizer.compute(input), .failure(.negativeLineCount))
    }

    func testNonPositiveLineHeightFails() {
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: 0.0,
            scrollOffsetY: 0.0,
            viewportHeight: 50.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(ViewportVirtualizer.compute(input), .failure(.nonPositiveLineHeight))
    }

    func testNegativeViewportHeightFails() {
        let input = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: -1.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(ViewportVirtualizer.compute(input), .failure(.negativeViewportHeight))
    }

    func testNegativeOverscanFails() {
        let beforeInput = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: 50.0,
            overscanLinesBefore: -1,
            overscanLinesAfter: 0
        )
        let afterInput = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: 50.0,
            overscanLinesBefore: 0,
            overscanLinesAfter: -1
        )

        XCTAssertEqual(ViewportVirtualizer.compute(beforeInput), .failure(.negativeOverscan))
        XCTAssertEqual(ViewportVirtualizer.compute(afterInput), .failure(.negativeOverscan))
    }

    func testEmptyDocumentReturnsEmptyRange() {
        let input = ViewportInput(
            lineCount: 0,
            lineHeight: 10.0,
            scrollOffsetY: 100.0,
            viewportHeight: 50.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 0,
                    bufferStart: 0,
                    bufferEndExclusive: 0,
                    isAtTop: true,
                    isAtBottom: true
                )
            )
        )
    }
}
