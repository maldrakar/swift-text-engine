import XCTest
@testable import TextEngineCore

final class LineGeometryCursorTests: XCTestCase {
    func testCursorYieldsOnlyBufferedLines() {
        let range = VirtualRange(
            visibleStart: 5,
            visibleEndExclusive: 7,
            bufferStart: 3,
            bufferEndExclusive: 6,
            isAtTop: false,
            isAtBottom: false
        )

        var cursor = ViewportVirtualizer.geometry(for: range, lineHeight: 10.0)
        var output: [LineGeometry] = []
        while let geometry = cursor.next() {
            output.append(geometry)
        }

        XCTAssertEqual(
            output,
            [
                LineGeometry(lineIndex: 3, y: 30.0, height: 10.0),
                LineGeometry(lineIndex: 4, y: 40.0, height: 10.0),
                LineGeometry(lineIndex: 5, y: 50.0, height: 10.0)
            ]
        )
    }

    func testCursorForEmptyRangeYieldsNoGeometry() {
        let range = VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )

        var cursor = ViewportVirtualizer.geometry(for: range, lineHeight: 10.0)

        XCTAssertNil(cursor.next())
    }
}
