import XCTest
@testable import TextEngineCore

final class VariableViewportComputeTests: XCTestCase {
    private func input(
        scrollOffsetY: Double,
        viewportHeight: Double,
        overscanLinesBefore: Int = 0,
        overscanLinesAfter: Int = 0
    ) -> VariableViewportInput {
        VariableViewportInput(
            scrollOffsetY: scrollOffsetY,
            viewportHeight: viewportHeight,
            overscanLinesBefore: overscanLinesBefore,
            overscanLinesAfter: overscanLinesAfter
        )
    }

    func testNonUniformVisibleRange() {
        // offsets: [0, 10, 40, 45, 145], totalHeight 145.
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 20.0, viewportHeight: 30.0),
            metrics: metrics
        )

        XCTAssertEqual(
            result,
            .success(
                VirtualRange(
                    visibleStart: 1,
                    visibleEndExclusive: 4,
                    bufferStart: 1,
                    bufferEndExclusive: 4,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testNonUniformWithOverscan() {
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 40.0, viewportHeight: 5.0, overscanLinesBefore: 1, overscanLinesAfter: 1),
            metrics: metrics
        )

        XCTAssertEqual(
            result,
            .success(
                VirtualRange(
                    visibleStart: 2,
                    visibleEndExclusive: 3,
                    bufferStart: 1,
                    bufferEndExclusive: 4,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testEmptyDocumentReturnsEmptyRange() {
        let metrics = ListLineMetrics(heights: [])
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 0.0, viewportHeight: 100.0),
            metrics: metrics
        )

        XCTAssertEqual(
            result,
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

    func testEmptyDocumentStillValidatesFirstOffset() {
        let metrics = ClosureLineMetrics(lineCount: 0) { _ in 1.0 }
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 0.0, viewportHeight: 100.0),
            metrics: metrics
        )

        XCTAssertEqual(result, .failure(.invalidLineMetrics))
    }

    func testZeroHeightViewportExactLineTopIsEmpty() {
        // offsets: [0, 10, 40, 45, 145]. scrollOffset 40 == line 2 top -> empty [2, 2).
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 40.0, viewportHeight: 0.0), metrics: metrics),
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

    func testZeroHeightViewportMidLineKeepsCrossedLine() {
        // scrollOffset 20 is inside line 1 ([10, 40)) -> single crossed line [1, 2).
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 20.0, viewportHeight: 0.0), metrics: metrics),
            .success(
                VirtualRange(
                    visibleStart: 1,
                    visibleEndExclusive: 2,
                    bufferStart: 1,
                    bufferEndExclusive: 2,
                    isAtTop: false,
                    isAtBottom: false
                )
            )
        )
    }

    func testZeroHeightViewportAtDocumentEndClampsToLineCount() {
        // scrollOffset 145 == totalHeight (document end) -> visibleStart == lineCount.
        let metrics = ListLineMetrics(heights: [10, 30, 5, 100])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 145.0, viewportHeight: 0.0), metrics: metrics),
            .success(
                VirtualRange(
                    visibleStart: 4,
                    visibleEndExclusive: 4,
                    bufferStart: 4,
                    bufferEndExclusive: 4,
                    isAtTop: false,
                    isAtBottom: true
                )
            )
        )
    }

    func testNegativeLineCountFails() {
        let metrics = ClosureLineMetrics(lineCount: -1) { Double($0) }
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: 10.0), metrics: metrics),
            .failure(.negativeLineCount)
        )
    }

    func testNonFiniteScrollOffsetFails() {
        let metrics = ListLineMetrics(heights: [10, 10])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: .infinity, viewportHeight: 10.0), metrics: metrics),
            .failure(.nonFiniteValue)
        )
    }

    func testNonFiniteViewportHeightFails() {
        let metrics = ListLineMetrics(heights: [10, 10])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: .nan), metrics: metrics),
            .failure(.nonFiniteValue)
        )
    }

    func testNegativeViewportHeightFails() {
        let metrics = ListLineMetrics(heights: [10, 10])
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: -1.0), metrics: metrics),
            .failure(.negativeViewportHeight)
        )
    }

    func testNegativeOverscanFails() {
        let metrics = ListLineMetrics(heights: [10, 10])
        XCTAssertEqual(
            ViewportVirtualizer.compute(
                input(scrollOffsetY: 0.0, viewportHeight: 10.0, overscanLinesBefore: -1),
                metrics: metrics
            ),
            .failure(.negativeOverscan)
        )
    }

    func testNonZeroFirstOffsetFails() {
        let metrics = ClosureLineMetrics(lineCount: 3) { _ in 5.0 }
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: 10.0), metrics: metrics),
            .failure(.invalidLineMetrics)
        )
    }

    func testNonPositiveTotalHeightFails() {
        let metrics = ClosureLineMetrics(lineCount: 3) { _ in 0.0 }
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: 10.0), metrics: metrics),
            .failure(.invalidLineMetrics)
        )
    }

    func testNonFiniteTotalHeightFails() {
        let metrics = ClosureLineMetrics(lineCount: 3) { $0 == 3 ? .infinity : Double($0) }
        XCTAssertEqual(
            ViewportVirtualizer.compute(input(scrollOffsetY: 0.0, viewportHeight: 10.0), metrics: metrics),
            .failure(.invalidLineMetrics)
        )
    }
}
