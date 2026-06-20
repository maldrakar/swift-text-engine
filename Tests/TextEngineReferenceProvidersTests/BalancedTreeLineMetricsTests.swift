import XCTest
@testable import TextEngineReferenceProviders
import TextEngineCore

private final class QueryCounter {
    var count = 0
}

private struct CountingMetrics<Base: LineMetricsSource>: LineMetricsSource {
    let base: Base
    let counter: QueryCounter

    var lineCount: Int { base.lineCount }

    func offset(ofLine index: Int) -> Double {
        counter.count += 1
        return base.offset(ofLine: index)
    }
}

final class BalancedTreeLineMetricsTests: XCTestCase {
    // Deterministic, integer-valued, strictly-positive non-uniform heights in
    // {14,16,20,32}. Integer values with totals < 2^53 make tree partial sums
    // bit-exactly equal to the left-to-right prefix-sum oracle.
    private func sampleHeights(_ lineCount: Int) -> [Double] {
        var heights: [Double] = []
        heights.reserveCapacity(lineCount)
        for index in 0..<lineCount {
            let bucket = ((index &* 31) &+ 7) % 4
            switch bucket {
            case 0: heights.append(14.0)
            case 1: heights.append(16.0)
            case 2: heights.append(20.0)
            default: heights.append(32.0)
            }
        }
        return heights
    }

    private func floorLog2(_ value: Int) -> Int {
        precondition(value >= 1)
        return Int.bitWidth - 1 - value.leadingZeroBitCount
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

    private func expectSuccess(
        _ computation: ViewportComputation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> VirtualRange {
        switch computation {
        case let .success(range):
            return range
        case let .failure(error):
            XCTFail("expected success, got \(error)", file: file, line: line)
            return VirtualRange(
                visibleStart: 0, visibleEndExclusive: 0,
                bufferStart: 0, bufferEndExclusive: 0,
                isAtTop: true, isAtBottom: true
            )
        }
    }

    // Compares lineCount and every offset(0...count) against a freshly-built
    // prefix-sum oracle over `array`. The array is the easy oracle.
    private func assertMatchesOracle(
        _ tree: BalancedTreeLineMetrics,
        _ array: [Double],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let oracle = PrefixSumLineMetrics(heights: array)
        XCTAssertEqual(tree.lineCount, oracle.lineCount, "lineCount \(message())", file: file, line: line)
        for i in 0...array.count {
            XCTAssertEqual(
                tree.offset(ofLine: i),
                oracle.offset(ofLine: i),
                "offset[\(i)] \(message())",
                file: file,
                line: line
            )
        }
    }

    func testOffsetMatchesPrefixSumOracleOnBuild() {
        let heights = sampleHeights(1_000)
        let tree = BalancedTreeLineMetrics(heights: heights)
        assertMatchesOracle(tree, heights)
    }

    func testBalancedBuildHeightIsLogarithmic() {
        let n = 100_000
        let tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
        // Perfectly-balanced midpoint build: height == floor(log2 n) + 1.
        XCTAssertLessThanOrEqual(tree.treeHeight(), ceilLog2(n + 1))
        XCTAssertGreaterThan(tree.treeHeight(), 0)
    }

    func testEmptyDocument() {
        let tree = BalancedTreeLineMetrics(heights: [])
        XCTAssertEqual(tree.lineCount, 0)
        XCTAssertEqual(tree.offset(ofLine: 0), 0.0)
        XCTAssertEqual(tree.treeHeight(), 0)
    }
}
