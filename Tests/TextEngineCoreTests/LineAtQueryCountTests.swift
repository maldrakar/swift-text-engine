import XCTest
@testable import TextEngineCore

final class LineAtQueryCountTests: XCTestCase {
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

    func testInRangeUsesLogarithmicQueriesAtOneMillionLines() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)

        let result = ViewportVirtualizer.lineAt(y: Double(lineCount / 2) * 16.0 + 8.0, metrics: metrics)

        guard case .line = result else { return XCTFail("expected .line, got \(result)") }
        // Two O(1) contract queries (offset 0 and total height) plus one binary
        // search of at most ceilLog2(n)+1 probes.
        let expectedMax = 2 + (ceilLog2(lineCount) + 1)
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testEmptyDocumentQueriesOnlyFirstOffset() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 0, lineHeight: 16.0, counter: counter)

        XCTAssertEqual(ViewportVirtualizer.lineAt(y: 0.0, metrics: metrics), .empty)
        XCTAssertEqual(counter.count, 1)
    }

    func testClampBranchesDoNotSearch() {
        let lineCount = 1_000_000

        let topCounter = QueryCounter()
        let topMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: topCounter)
        _ = ViewportVirtualizer.lineAt(y: -1.0, metrics: topMetrics)
        XCTAssertEqual(topCounter.count, 2) // offset(0) + total, no search

        let bottomCounter = QueryCounter()
        let bottomMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: bottomCounter)
        _ = ViewportVirtualizer.lineAt(y: Double(lineCount) * 16.0 + 1.0, metrics: bottomMetrics)
        XCTAssertEqual(bottomCounter.count, 2)
    }

    func testNonFiniteYDoesNotQueryOffsets() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 1_000, lineHeight: 16.0, counter: counter)

        XCTAssertEqual(ViewportVirtualizer.lineAt(y: .nan, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(counter.count, 0)
    }
}
