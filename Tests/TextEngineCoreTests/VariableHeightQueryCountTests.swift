import XCTest
@testable import TextEngineCore

final class VariableHeightQueryCountTests: XCTestCase {
    private final class QueryCounter {
        var count = 0
    }

    private struct CountingLineMetrics: LineMetricsSource {
        let base: UniformLineMetrics
        let counter: QueryCounter

        init(lineCount: Int, lineHeight: Double, counter: QueryCounter) {
            self.base = UniformLineMetrics(lineCount: lineCount, lineHeight: lineHeight)
            self.counter = counter
        }

        var lineCount: Int { base.lineCount }

        func offset(ofLine index: Int) -> Double {
            counter.count += 1
            return base.offset(ofLine: index)
        }
    }

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

    private func assertSuccess(
        _ computation: ViewportComputation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VirtualRange? {
        switch computation {
        case let .success(range):
            return range
        case let .failure(error):
            XCTFail("expected success, got \(error)", file: file, line: line)
            return nil
        }
    }

    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 {
            return 0
        }

        var power = 0
        var capacity = 1
        while capacity < value {
            capacity <<= 1
            power += 1
        }
        return power
    }

    func testComputeUsesLogarithmicQueriesAtOneMillionLines() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)
        let result = ViewportVirtualizer.compute(
            input(
                scrollOffsetY: Double(lineCount / 2) * 16.0 + 8.0,
                viewportHeight: 80.0 * 16.0,
                overscanLinesBefore: 5,
                overscanLinesAfter: 5
            ),
            metrics: metrics
        )

        XCTAssertNotNil(assertSuccess(result))

        // Two O(1) contract queries (offset 0 and total height) plus two binary
        // searches. A linear scan over 1M lines would be hundreds of thousands of
        // queries; this bound intentionally stays small and deterministic.
        let expectedMax = 2 + (ceilLog2(lineCount) + 1) * 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testComputeEmptyDocumentQueriesOnlyFirstOffset() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 0, lineHeight: 16.0, counter: counter)
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 0.0, viewportHeight: 80.0 * 16.0),
            metrics: metrics
        )

        XCTAssertNotNil(assertSuccess(result))
        XCTAssertEqual(counter.count, 1)
    }

    func testComputeSingleLineStaysBounded() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 1, lineHeight: 16.0, counter: counter)
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: 4.0, viewportHeight: 8.0),
            metrics: metrics
        )

        XCTAssertNotNil(assertSuccess(result))
        XCTAssertLessThanOrEqual(counter.count, 6)
    }

    func testComputeClampAtDocumentEndDoesNotSearchMidDocumentOffsets() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)
        let result = ViewportVirtualizer.compute(
            input(scrollOffsetY: Double(lineCount) * 16.0, viewportHeight: 0.0),
            metrics: metrics
        )

        XCTAssertNotNil(assertSuccess(result))
        XCTAssertEqual(counter.count, 2)
    }

    func testNonEmptyGeometryCursorQueriesSeedPlusOnePerBufferedLine() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 100, lineHeight: 16.0, counter: counter)
        let range = VirtualRange(
            visibleStart: 11,
            visibleEndExclusive: 14,
            bufferStart: 10,
            bufferEndExclusive: 15,
            isAtTop: false,
            isAtBottom: false
        )

        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        var emitted = 0
        while cursor.next() != nil {
            emitted += 1
        }

        XCTAssertEqual(emitted, 5)
        XCTAssertEqual(counter.count, 6)
    }

    func testEmptyGeometryCursorDoesNotSeedOffsetQuery() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 100, lineHeight: 16.0, counter: counter)
        let range = VirtualRange(
            visibleStart: 10,
            visibleEndExclusive: 10,
            bufferStart: 10,
            bufferEndExclusive: 10,
            isAtTop: false,
            isAtBottom: false
        )

        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)

        XCTAssertNil(cursor.next())
        XCTAssertEqual(counter.count, 0)
    }
}
