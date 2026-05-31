import XCTest
@testable import TextEngineCore

final class ViewportInputValueTests: XCTestCase {
    func testViewportInputStoresAllFields() {
        let input = ViewportInput(
            lineCount: 100,
            lineHeight: 12.5,
            scrollOffsetY: 25.0,
            viewportHeight: 80.0,
            overscanLinesBefore: 2,
            overscanLinesAfter: 3
        )

        XCTAssertEqual(input.lineCount, 100)
        XCTAssertEqual(input.lineHeight, 12.5)
        XCTAssertEqual(input.scrollOffsetY, 25.0)
        XCTAssertEqual(input.viewportHeight, 80.0)
        XCTAssertEqual(input.overscanLinesBefore, 2)
        XCTAssertEqual(input.overscanLinesAfter, 3)
    }

    func testVirtualRangeReportsEmpty() {
        let range = VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )

        XCTAssertTrue(range.isEmpty)
        XCTAssertTrue(range.isAtTop)
        XCTAssertTrue(range.isAtBottom)
    }

    func testLineGeometryStoresIndexAndDimensions() {
        let geometry = LineGeometry(lineIndex: 7, y: 84.0, height: 12.0)

        XCTAssertEqual(geometry.lineIndex, 7)
        XCTAssertEqual(geometry.y, 84.0)
        XCTAssertEqual(geometry.height, 12.0)
    }
}
