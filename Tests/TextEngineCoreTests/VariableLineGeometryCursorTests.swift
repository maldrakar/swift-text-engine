import XCTest
@testable import TextEngineCore

final class VariableLineGeometryCursorTests: XCTestCase {
    func testCursorYieldsBufferedLineGeometry() {
        // offsets: [0, 10, 40, 45, 145].
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        let range = VirtualRange(
            visibleStart: 2,
            visibleEndExclusive: 3,
            bufferStart: 1,
            bufferEndExclusive: 4,
            isAtTop: false,
            isAtBottom: false
        )

        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        var output: [LineGeometry] = []
        while let geometry = cursor.next() {
            output.append(geometry)
        }

        XCTAssertEqual(
            output,
            [
                LineGeometry(lineIndex: 1, y: 10.0, height: 30.0),
                LineGeometry(lineIndex: 2, y: 40.0, height: 5.0),
                LineGeometry(lineIndex: 3, y: 45.0, height: 100.0)
            ]
        )
    }

    func testCursorForEmptyRangeYieldsNoGeometry() {
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        let range = VirtualRange(
            visibleStart: 0,
            visibleEndExclusive: 0,
            bufferStart: 0,
            bufferEndExclusive: 0,
            isAtTop: true,
            isAtBottom: true
        )

        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        XCTAssertNil(cursor.next())
    }
}
