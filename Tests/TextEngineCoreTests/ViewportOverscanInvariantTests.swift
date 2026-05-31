import XCTest
@testable import TextEngineCore

final class ViewportOverscanInvariantTests: XCTestCase {
    func testOverscanExpandsBufferedRange() {
        let input = ViewportInput(
            lineCount: 100,
            lineHeight: 10.0,
            scrollOffsetY: 50.0,
            viewportHeight: 20.0,
            overscanLinesBefore: 2,
            overscanLinesAfter: 3
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 5,
                    visibleEndExclusive: 7,
                    bufferStart: 3,
                    bufferEndExclusive: 10,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testOverscanClampsAtTopAndBottom() {
        let topInput = ViewportInput(
            lineCount: 4,
            lineHeight: 10.0,
            scrollOffsetY: 0.0,
            viewportHeight: 10.0,
            overscanLinesBefore: 50,
            overscanLinesAfter: 1
        )
        let bottomInput = ViewportInput(
            lineCount: 10,
            lineHeight: 10.0,
            scrollOffsetY: 999.0,
            viewportHeight: 30.0,
            overscanLinesBefore: 1,
            overscanLinesAfter: 50
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(topInput),
            .success(
                VirtualRange(
                    visibleStart: 0,
                    visibleEndExclusive: 1,
                    bufferStart: 0,
                    bufferEndExclusive: 2,
                    isAtTop: true,
                    isAtBottom: false
                )
            )
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(bottomInput),
            .success(
                VirtualRange(
                    visibleStart: 7,
                    visibleEndExclusive: 10,
                    bufferStart: 6,
                    bufferEndExclusive: 10,
                    isAtTop: false,
                    isAtBottom: true
                )
            )
        )
    }

    func testOverscanPreservesPrecisionNearIntMax() {
        let input = ViewportInput(
            lineCount: Int.max,
            lineHeight: 1.0,
            scrollOffsetY: Double(Int.max),
            viewportHeight: 0.0,
            overscanLinesBefore: 1,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: Int.max,
                    visibleEndExclusive: Int.max,
                    bufferStart: Int.max - 1,
                    bufferEndExclusive: Int.max,
                    isAtTop: false,
                    isAtBottom: true
                )
            )
        )
    }

    func testOverscanBeforeClampsToZeroWithIntegerMath() {
        let input = ViewportInput(
            lineCount: Int.max,
            lineHeight: 1.0,
            scrollOffsetY: 2.0,
            viewportHeight: 0.0,
            overscanLinesBefore: 3,
            overscanLinesAfter: 0
        )

        XCTAssertEqual(
            ViewportVirtualizer.compute(input),
            .success(
                VirtualRange(
                    visibleStart: 2,
                    visibleEndExclusive: 2,
                    bufferStart: 0,
                    bufferEndExclusive: 2,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testGeneratedInputsStayInBounds() {
        let lineCounts = [0, 1, 2, 10, 100_000, 1_000_000]
        let lineHeights = [1.0, 10.0, 17.5]
        let viewportHeights = [0.0, 1.0, 25.0, 1_000.0]
        let offsets = [-100.0, 0.0, 0.5, 10.0, 999_999.0]
        let overscans = [(0, 0), (1, 2), (50, 50)]

        for lineCount in lineCounts {
            for lineHeight in lineHeights {
                for viewportHeight in viewportHeights {
                    for offset in offsets {
                        for overscan in overscans {
                            let input = ViewportInput(
                                lineCount: lineCount,
                                lineHeight: lineHeight,
                                scrollOffsetY: offset,
                                viewportHeight: viewportHeight,
                                overscanLinesBefore: overscan.0,
                                overscanLinesAfter: overscan.1
                            )

                            guard case let .success(range) = ViewportVirtualizer.compute(input) else {
                                XCTFail("Valid generated input failed: \(input)")
                                return
                            }

                            XCTAssertGreaterThanOrEqual(range.visibleStart, 0)
                            XCTAssertLessThanOrEqual(range.visibleStart, range.visibleEndExclusive)
                            XCTAssertLessThanOrEqual(range.visibleEndExclusive, lineCount)
                            XCTAssertGreaterThanOrEqual(range.bufferStart, 0)
                            XCTAssertLessThanOrEqual(range.bufferStart, range.bufferEndExclusive)
                            XCTAssertLessThanOrEqual(range.bufferEndExclusive, lineCount)
                            XCTAssertLessThanOrEqual(range.bufferStart, range.visibleStart)
                            XCTAssertLessThanOrEqual(range.visibleEndExclusive, range.bufferEndExclusive)
                        }
                    }
                }
            }
        }
    }
}
