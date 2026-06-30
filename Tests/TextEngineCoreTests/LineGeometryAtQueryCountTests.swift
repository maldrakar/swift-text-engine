import XCTest
@testable import TextEngineCore

final class LineGeometryAtQueryCountTests: XCTestCase {
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

    private enum NativeSearchEvent: Equatable {
        case offset(Int)
        case native(Double)
    }

    private final class NativeSearchCounter {
        var events: [NativeSearchEvent] = []
    }

    private struct NativeSearchMetrics: LineMetricsSource {
        let offsets: [Double]
        let counter: NativeSearchCounter

        var lineCount: Int { offsets.count - 1 }

        func offset(ofLine index: Int) -> Double {
            counter.events.append(.offset(index))
            return offsets[index]
        }

        func lineIndex(containingOffset y: Double) -> Int {
            counter.events.append(.native(y))
            var result = 0
            for index in 0..<(offsets.count - 1) {
                if offsets[index] <= y { result = index } else { break }
            }
            return result
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

    func testInRangeUsesLogarithmicQueriesPlusTwoGeometryProbes() {
        let lineCount = 1_000_000
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: counter)

        let result = ViewportVirtualizer.lineGeometryAt(y: Double(lineCount / 2) * 16.0 + 8.0, metrics: metrics)

        guard case .geometry = result else { return XCTFail("expected .geometry, got \(result)") }
        // lineAt's 2 contract probes + binary search (<= ceilLog2(n)+1) + 2 geometry probes.
        let expectedMax = 2 + (ceilLog2(lineCount) + 1) + 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testEmptyDocumentQueriesOnlyFirstOffset() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 0, lineHeight: 16.0, counter: counter)

        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: 0.0, metrics: metrics), .empty)
        XCTAssertEqual(counter.count, 1)
    }

    func testClampBranchesUseFourProbes() {
        let lineCount = 1_000_000

        let topCounter = QueryCounter()
        let topMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: topCounter)
        _ = ViewportVirtualizer.lineGeometryAt(y: -1.0, metrics: topMetrics)
        XCTAssertEqual(topCounter.count, 4) // lineAt offset(0)+total, then box offset(0)+offset(1)

        let bottomCounter = QueryCounter()
        let bottomMetrics = CountingLineMetrics(lineCount: lineCount, lineHeight: 16.0, counter: bottomCounter)
        _ = ViewportVirtualizer.lineGeometryAt(y: Double(lineCount) * 16.0 + 1.0, metrics: bottomMetrics)
        XCTAssertEqual(bottomCounter.count, 4)
    }

    func testNonFiniteYDoesNotQueryOffsets() {
        let counter = QueryCounter()
        let metrics = CountingLineMetrics(lineCount: 1_000, lineHeight: 16.0, counter: counter)

        XCTAssertEqual(ViewportVirtualizer.lineGeometryAt(y: .nan, metrics: metrics), .failure(.nonFiniteValue))
        XCTAssertEqual(counter.count, 0)
    }

    func testDispatchesToNativeHookThenTakesTwoGeometryProbesInOrder() {
        let counter = NativeSearchCounter()
        let metrics = NativeSearchMetrics(offsets: [0.0, 10.0, 30.0, 35.0, 80.0], counter: counter)

        let result = ViewportVirtualizer.lineGeometryAt(y: 31.0, metrics: metrics)

        XCTAssertEqual(result, .geometry(LineGeometryLocation(
            geometry: LineGeometry(lineIndex: 2, y: 30.0, height: 5.0),
            fractionInLine: (31.0 - 30.0) / 5.0,
            clamp: .inRange
        )))
        // lineAt: offset(0), offset(lineCount=4), native(31); then box: offset(2), offset(3).
        XCTAssertEqual(counter.events, [.offset(0), .offset(4), .native(31.0), .offset(2), .offset(3)])
    }
}
