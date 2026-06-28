import XCTest
@testable import TextEngineCore

final class ComputeNativePrefixSearchTests: XCTestCase {
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

    private func ceilLog2(_ value: Int) -> Int {
        if value <= 1 { return 0 }
        var power = 0
        var capacity = 1
        while capacity < value {
            capacity <<= 1
            power += 1
        }
        return power
    }

    func testDefaultFirstLineIndexAtOrAboveReturnsSmallestIndexAtOrAbove() {
        let metrics = CountingLineMetrics(lineCount: 5, lineHeight: 10.0, counter: QueryCounter())
        // offsets: 0,10,20,30,40,50
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 20.0, startingAtLine: 0), 2) // exact top -> that line
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 21.0, startingAtLine: 0), 3) // interior -> next line
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 0.0, startingAtLine: 0), 0)
        XCTAssertEqual(metrics.firstLineIndex(withOffsetAtOrAbove: 45.0, startingAtLine: 0), 5) // last interior -> lineCount
    }

    func testDefaultFirstLineIndexAtOrAboveUsesLogarithmicFallback() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)

        let index = metrics.firstLineIndex(
            withOffsetAtOrAbove: Double(lineCount / 2) * 16.0 + 8.0,
            startingAtLine: 0
        )

        XCTAssertEqual(index, lineCount / 2 + 1)
        XCTAssertLessThanOrEqual(counter.count, ceilLog2(lineCount) + 1)
        XCTAssertLessThan(counter.count, 100)
    }

    func testFirstLineIndexAtOrAboveHintNarrowsSearch() {
        let lineCount = 1_000_000
        let target = Double(lineCount - 2) * 16.0 // deep scroll: answer near the end

        let wide = QueryCounter()
        let wideMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: wide)
        let wideIndex = wideMetrics.firstLineIndex(withOffsetAtOrAbove: target, startingAtLine: 0)

        let narrow = QueryCounter()
        let narrowMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: narrow)
        let narrowIndex = narrowMetrics.firstLineIndex(withOffsetAtOrAbove: target, startingAtLine: lineCount - 4)

        XCTAssertEqual(wideIndex, lineCount - 2)
        XCTAssertEqual(narrowIndex, lineCount - 2)
        // Same answer, but the hint must strictly reduce the probe count at deep scroll.
        XCTAssertLessThan(narrow.count, wide.count)
    }
}
