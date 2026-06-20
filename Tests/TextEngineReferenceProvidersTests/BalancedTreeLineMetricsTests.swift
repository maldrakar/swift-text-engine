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

    func testSetHeightMatchesFreshOracle() {
        let heights = sampleHeights(500)
        var tree = BalancedTreeLineMetrics(heights: heights)
        var mutated = heights
        // First line, last line, an interior line, then the same interior line
        // again (repeated edit).
        let edits: [(index: Int, height: Double)] = [
            (0, 40.0), (heights.count - 1, 12.0), (250, 28.0), (250, 50.0)
        ]
        for edit in edits {
            let returned = tree.setHeight(ofLine: edit.index, to: edit.height)
            XCTAssertEqual(returned, tree.lastMutationNodeVisits)
            mutated[edit.index] = edit.height
            assertMatchesOracle(tree, mutated, "after editing line \(edit.index)")
        }
    }

    func testSetHeightKeepsOffsetsStrictlyIncreasing() {
        let heights = sampleHeights(300)
        var tree = BalancedTreeLineMetrics(heights: heights)
        tree.setHeight(ofLine: 0, to: 64.0)
        tree.setHeight(ofLine: 299, to: 2.0)
        tree.setHeight(ofLine: 150, to: 5.0)
        for i in 0..<tree.lineCount {
            XCTAssertLessThan(
                tree.offset(ofLine: i),
                tree.offset(ofLine: i + 1),
                "offsets not strictly increasing at line \(i)"
            )
        }
    }

    func testSetHeightVisitCountIsLogarithmic() {
        for n in [1_000, 100_000, 1_000_000] {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
            let visits = tree.setHeight(ofLine: n / 2, to: 24.0)
            // Descent depth only (no rebalance): bounded by the tree height.
            XCTAssertLessThanOrEqual(visits, 4 * (floorLog2(n) + 1), "n=\(n)")
            XCTAssertGreaterThan(visits, 0)
        }
    }

    func testInsertSequenceMatchesOracleAndStaysBalanced() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(40))
        var mutated = sampleHeights(40)
        // 500 deterministic inserts at head, tail, and interior positions, heights
        // from a fixed integer set. Head inserts (index 0) force left-heavy
        // rebalancing; tail inserts force right-heavy.
        let positionsCycle = 5
        for k in 0..<500 {
            let count = mutated.count
            let index: Int
            switch k % positionsCycle {
            case 0: index = 0
            case 1: index = count            // tail (insert at end)
            case 2: index = count / 2
            case 3: index = count / 3
            default: index = (count * 2) / 3
            }
            let height = Double(10 + (k % 5) * 6) // 10,16,22,28,34
            let visits = tree.insertLine(at: index, height: height)
            XCTAssertGreaterThan(visits, 0)
            mutated.insert(height, at: index)
            assertMatchesOracle(tree, mutated, "after insert #\(k) at \(index)")
        }
        // Balanced after 500 inserts: height stays logarithmic, not linear.
        XCTAssertLessThanOrEqual(
            tree.treeHeight(),
            3 * (floorLog2(tree.lineCount) + 1),
            "tree height not logarithmic: \(tree.treeHeight()) for lineCount \(tree.lineCount)"
        )
    }

    func testInsertIntoEmptyDocument() {
        var tree = BalancedTreeLineMetrics(heights: [])
        XCTAssertEqual(tree.lineCount, 0)
        tree.insertLine(at: 0, height: 21.0)
        assertMatchesOracle(tree, [21.0])
        tree.insertLine(at: 1, height: 13.0)
        assertMatchesOracle(tree, [21.0, 13.0])
        tree.insertLine(at: 0, height: 17.0)
        assertMatchesOracle(tree, [17.0, 21.0, 13.0])
    }

    func testRemoveSequenceMatchesOracleDownToEmpty() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(600))
        var mutated = sampleHeights(600)
        var k = 0
        while !mutated.isEmpty {
            let count = mutated.count
            // Cycle head / tail / interior removals (interior exercises the
            // two-children successor-swap delete path).
            let raw: Int
            switch k % 3 {
            case 0: raw = 0
            case 1: raw = count - 1
            default: raw = count / 2
            }
            let index = raw % count
            let visits = tree.removeLine(at: index)
            XCTAssertGreaterThan(visits, 0)
            mutated.remove(at: index)
            assertMatchesOracle(tree, mutated, "after removing index \(index) (k=\(k))")
            k += 1
        }
        XCTAssertEqual(tree.lineCount, 0)
        XCTAssertEqual(tree.offset(ofLine: 0), 0.0)
        XCTAssertEqual(tree.treeHeight(), 0)
    }

    func testRemoveThenInsertMatchesOracleWithRecycledSlots() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(12))
        var mutated = sampleHeights(12)

        for step in 0..<3 {
            let index: Int
            switch step {
            case 0: index = 0
            case 1: index = mutated.count - 1
            default: index = mutated.count / 2
            }
            tree.removeLine(at: index)
            mutated.remove(at: index)
            assertMatchesOracle(tree, mutated, "after removing index \(index)")
        }

        for step in 0..<3 {
            let index: Int
            switch step {
            case 0: index = 0
            case 1: index = mutated.count
            default: index = mutated.count / 2
            }
            let height = Double(41 + step * 2)
            tree.insertLine(at: index, height: height)
            mutated.insert(height, at: index)
            assertMatchesOracle(
                tree,
                mutated,
                "after inserting \(height) at \(index)"
            )
        }
    }
}
