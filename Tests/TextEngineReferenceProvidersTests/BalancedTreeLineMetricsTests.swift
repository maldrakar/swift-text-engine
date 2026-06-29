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

    private func sampledSearchOffsets(_ oracle: PrefixSumLineMetrics) -> [Double] {
        if oracle.lineCount == 0 {
            return []
        }

        let rawIndexes = [
            0,
            1,
            2,
            oracle.lineCount / 2,
            oracle.lineCount - 2,
            oracle.lineCount - 1
        ]
        let indexes = Set(rawIndexes.filter { $0 >= 0 && $0 < oracle.lineCount }).sorted()
        var samples: [Double] = []
        for index in indexes {
            let top = oracle.offset(ofLine: index)
            let bottom = oracle.offset(ofLine: index + 1)
            samples.append(top)
            samples.append((top + bottom) / 2.0)
            let beforeBoundary = bottom.nextDown
            if beforeBoundary > top {
                samples.append(beforeBoundary)
            }
        }
        return samples
    }

    private func assertNativeSearchMatchesOracle(
        _ tree: BalancedTreeLineMetrics,
        _ array: [Double],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let oracle = PrefixSumLineMetrics(heights: array)
        for y in sampledSearchOffsets(oracle) {
            XCTAssertEqual(
                tree.lineIndex(containingOffset: y),
                oracle.lineIndex(containingOffset: y),
                "lineIndex y=\(y) \(message())",
                file: file,
                line: line
            )
            XCTAssertEqual(
                tree.lineIndexAndVisitCount(containingOffset: y).lineIndex,
                oracle.lineIndex(containingOffset: y),
                "lineIndexAndVisitCount y=\(y) \(message())",
                file: file,
                line: line
            )
        }
    }

    // Independent oracle for "first line top at or above y": a linear scan over
    // the prefix-sum offsets, NOT the production binary search.
    private func bruteFirstAtOrAbove(_ oracle: PrefixSumLineMetrics, _ y: Double) -> Int {
        for i in 0...oracle.lineCount where oracle.offset(ofLine: i) >= y {
            return i
        }
        return oracle.lineCount
    }

    private func assertNativeAtOrAboveMatchesOracle(
        _ tree: BalancedTreeLineMetrics,
        _ array: [Double],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let oracle = PrefixSumLineMetrics(heights: array)
        for y in sampledSearchOffsets(oracle) {
            let expected = bruteFirstAtOrAbove(oracle, y)
            XCTAssertEqual(
                tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 0),
                expected,
                "firstLineIndex y=\(y) \(message())",
                file: file, line: line
            )
            XCTAssertEqual(
                tree.firstLineIndexAndVisitCount(withOffsetAtOrAbove: y).lineIndex,
                expected,
                "firstLineIndexAndVisitCount y=\(y) \(message())",
                file: file, line: line
            )
        }
    }

    private func assertNativeAtOrAbovePreservesExactTops(
        _ tree: BalancedTreeLineMetrics,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for index in 0..<tree.lineCount {
            let y = tree.offset(ofLine: index)
            XCTAssertEqual(
                tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 0),
                index,
                "firstLineIndex exact top y=\(y) index=\(index) \(message())",
                file: file, line: line
            )
            XCTAssertEqual(
                tree.firstLineIndexAndVisitCount(withOffsetAtOrAbove: y).lineIndex,
                index,
                "firstLineIndexAndVisitCount exact top y=\(y) index=\(index) \(message())",
                file: file, line: line
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

    func testNativeLineIndexMatchesPrefixSumOracleAtBoundaries() {
        let heights = sampleHeights(1_000)
        let tree = BalancedTreeLineMetrics(heights: heights)

        assertNativeSearchMatchesOracle(tree, heights, "initial build")
    }

    func testNativeFirstLineIndexAtOrAboveMatchesOracleAtBoundaries() {
        let heights = sampleHeights(1_000)
        let tree = BalancedTreeLineMetrics(heights: heights)
        assertNativeAtOrAboveMatchesOracle(tree, heights, "initial build")
    }

    func testNativeFirstLineIndexAtOrAbovePreservesFractionalExactLineTops() {
        var tree = BalancedTreeLineMetrics(heights: [27.4, 17.3, 38.0])
        assertNativeAtOrAbovePreservesExactTops(tree, "initial fractional tree")

        tree.insertLine(at: 1, height: 11.2)
        tree.setHeight(ofLine: 2, to: 19.7)
        assertNativeAtOrAbovePreservesExactTops(tree, "after fractional mutations")
    }

    func testNativeFirstLineIndexAtOrAboveIgnoresHintButHonorsIt() {
        let heights = sampleHeights(500)
        let tree = BalancedTreeLineMetrics(heights: heights)
        let oracle = PrefixSumLineMetrics(heights: heights)
        // For a y whose answer is index a, any lowerBound <= a returns the same a.
        let y = oracle.offset(ofLine: 300) + 1.0 // interior of line 300 -> answer 301
        XCTAssertEqual(tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 0), 301)
        XCTAssertEqual(tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 301), 301)
        XCTAssertEqual(tree.firstLineIndex(withOffsetAtOrAbove: y, startingAtLine: 200), 301)
    }

    func testNativeFirstLineIndexAtOrAboveMatchesOracleAfterMutations() {
        var array = sampleHeights(120)
        var tree = BalancedTreeLineMetrics(heights: array)

        tree.setHeight(ofLine: 0, to: 40.0); array[0] = 40.0
        assertNativeAtOrAboveMatchesOracle(tree, array, "after setHeight first")

        tree.insertLine(at: 10, height: 19.0); array.insert(19.0, at: 10)
        assertNativeAtOrAboveMatchesOracle(tree, array, "after insertLine")

        tree.removeLine(at: 3); array.remove(at: 3)
        assertNativeAtOrAboveMatchesOracle(tree, array, "after removeLine")

        let inserted = [17.0, 29.0, 31.0, 37.0]
        tree.insertLines(at: 20, heights: inserted); array.insert(contentsOf: inserted, at: 20)
        assertNativeAtOrAboveMatchesOracle(tree, array, "after insertLines")

        tree.removeLines(at: 5, count: 4); array.removeSubrange(5..<9)
        assertNativeAtOrAboveMatchesOracle(tree, array, "after removeLines")
    }

    func testLineAtWithBalancedTreeMatchesPrefixSumOracle() {
        let heights = sampleHeights(1_000)
        let tree = BalancedTreeLineMetrics(heights: heights)
        let oracle = PrefixSumLineMetrics(heights: heights)
        var samples = sampledSearchOffsets(oracle)
        samples.append(-1.0)
        samples.append(oracle.offset(ofLine: oracle.lineCount))
        samples.append(oracle.offset(ofLine: oracle.lineCount) + 100.0)

        for y in samples {
            XCTAssertEqual(
                ViewportVirtualizer.lineAt(y: y, metrics: tree),
                ViewportVirtualizer.lineAt(y: y, metrics: oracle),
                "lineAt y=\(y)"
            )
        }
    }

    func testComputeOverBalancedTreeMatchesPrefixSumOracleAcrossScrollSweep() {
        let heights = sampleHeights(5_000)
        let tree = BalancedTreeLineMetrics(heights: heights)
        let oracle = PrefixSumLineMetrics(heights: heights)
        let total = oracle.offset(ofLine: oracle.lineCount)

        // Scroll offsets: negative, exact line tops, interiors, fractional,
        // top, near-bottom, exactly bottom, and past bottom.
        var scrollOffsets: [Double] = [-50.0, 0.0, 1.5, total, total + 100.0]
        for line in [1, 2, 499, 2_500, 4_998, 4_999] {
            let top = oracle.offset(ofLine: line)
            scrollOffsets.append(top)
            scrollOffsets.append(top + 0.5)
            scrollOffsets.append(top.nextDown)
        }

        let viewportHeights: [Double] = [0.0, 16.0, 80.0 * 16.0, total + 10.0]
        let overscans: [(Int, Int)] = [(0, 0), (5, 5), (3, 9)]

        for scroll in scrollOffsets {
            for viewportHeight in viewportHeights {
                for (before, after) in overscans {
                    let input = VariableViewportInput(
                        scrollOffsetY: scroll,
                        viewportHeight: viewportHeight,
                        overscanLinesBefore: before,
                        overscanLinesAfter: after
                    )
                    let treeRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: tree))
                    let oracleRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: oracle))
                    XCTAssertEqual(
                        treeRange, oracleRange,
                        "scroll=\(scroll) vh=\(viewportHeight) overscan=(\(before),\(after))"
                    )
                }
            }
        }
    }

    func testNativeLineIndexMatchesOracleAfterSingleAndBulkMutations() {
        var array = sampleHeights(120)
        var tree = BalancedTreeLineMetrics(heights: array)

        tree.setHeight(ofLine: 0, to: 40.0)
        array[0] = 40.0
        assertNativeSearchMatchesOracle(tree, array, "after setHeight first")

        tree.setHeight(ofLine: array.count - 1, to: 12.0)
        array[array.count - 1] = 12.0
        assertNativeSearchMatchesOracle(tree, array, "after setHeight last")

        tree.insertLine(at: 10, height: 19.0)
        array.insert(19.0, at: 10)
        assertNativeSearchMatchesOracle(tree, array, "after insertLine")

        tree.removeLine(at: 3)
        array.remove(at: 3)
        assertNativeSearchMatchesOracle(tree, array, "after removeLine")

        let inserted = [17.0, 29.0, 31.0, 37.0]
        tree.insertLines(at: 20, heights: inserted)
        array.insert(contentsOf: inserted, at: 20)
        assertNativeSearchMatchesOracle(tree, array, "after insertLines")

        tree.removeLines(at: 5, count: 4)
        array.removeSubrange(5..<9)
        assertNativeSearchMatchesOracle(tree, array, "after removeLines")
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

    // MARK: - Bulk insert (Slice 25)

    func testInsertLinesMatchesArrayOracleAtHeadTailInterior() {
        let positions = [0, 500, 1_000]
        for index in positions {
            for k in [1, 8, 5_000] {
                var tree = BalancedTreeLineMetrics(heights: sampleHeights(1_000))
                var array = sampleHeights(1_000)
                let inserted = (0..<k).map { Double(10 + ($0 % 5) * 6) }
                tree.insertLines(at: index, heights: inserted)
                array.insert(contentsOf: inserted, at: index)
                assertMatchesOracle(tree, array, "insert k=\(k) at \(index)")
            }
        }
    }

    func testInsertLinesEqualsLoopOfSingleInserts() {
        var bulk = BalancedTreeLineMetrics(heights: sampleHeights(300))
        var loop = BalancedTreeLineMetrics(heights: sampleHeights(300))
        let inserted = (0..<64).map { Double(12 + ($0 % 4) * 5) }
        let index = 137
        bulk.insertLines(at: index, heights: inserted)
        for (offset, height) in inserted.enumerated() {
            loop.insertLine(at: index + offset, height: height)
        }
        XCTAssertEqual(bulk.lineCount, loop.lineCount)
        for i in 0...bulk.lineCount {
            XCTAssertEqual(bulk.offset(ofLine: i), loop.offset(ofLine: i), "offset[\(i)]")
        }
    }

    func testInsertLinesEmptyIsNoOpAndInsertIntoEmptyDocument() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(50))
        let before = (0...tree.lineCount).map { tree.offset(ofLine: $0) }
        let visits = tree.insertLines(at: 25, heights: [])
        XCTAssertEqual(visits, 0)
        XCTAssertEqual(tree.lineCount, 50)
        XCTAssertEqual((0...tree.lineCount).map { tree.offset(ofLine: $0) }, before)

        var empty = BalancedTreeLineMetrics(heights: [])
        empty.insertLines(at: 0, heights: [21.0, 13.0, 17.0])
        assertMatchesOracle(empty, [21.0, 13.0, 17.0])
    }

    func testInsertLinesKeepsOffsetsStrictlyIncreasing() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(400))
        tree.insertLines(at: 0, heights: [40.0, 12.0])
        tree.insertLines(at: tree.lineCount, heights: [5.0, 64.0, 9.0])
        tree.insertLines(at: 200, heights: (0..<100).map { Double(8 + $0 % 7) })
        for i in 0..<tree.lineCount {
            XCTAssertLessThan(tree.offset(ofLine: i), tree.offset(ofLine: i + 1), "at \(i)")
        }
    }

    func testInsertLinesKeepsTreeBalanced() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(40))
        for k in 0..<200 {
            let count = tree.lineCount
            let index: Int
            switch k % 4 {
            case 0: index = 0
            case 1: index = count
            case 2: index = count / 2
            default: index = count / 3
            }
            let batch = (0..<(1 + k % 32)).map { Double(10 + ($0 % 5) * 6) }
            tree.insertLines(at: index, heights: batch)
        }
        XCTAssertLessThanOrEqual(
            tree.treeHeight(),
            3 * (floorLog2(tree.lineCount) + 1),
            "tree height not logarithmic: \(tree.treeHeight()) for \(tree.lineCount)"
        )
    }

    func testInsertLinesVisitCountIsKPlusLogarithmic() {
        let k = 64
        for n in [1_000, 100_000, 1_000_000] {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
            let batch = (0..<k).map { Double(10 + ($0 % 5) * 6) }
            let visits = tree.insertLines(at: n / 2, heights: batch)
            XCTAssertLessThanOrEqual(visits, k + 12 * (floorLog2(n) + 1), "n=\(n)")
            XCTAssertLessThan(visits, k * (floorLog2(n) + 1), "n=\(n) not below compose cost")
        }
    }

    // MARK: - Bulk remove (Slice 25)

    func testRemoveLinesMatchesArrayOracleAtHeadTailInterior() {
        // (index, count) spans: head, interior, tail.
        let spans = [(0, 1), (0, 250), (375, 250), (900, 100), (500, 1)]
        for (index, count) in spans {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(1_000))
            var array = sampleHeights(1_000)
            tree.removeLines(at: index, count: count)
            array.removeSubrange(index..<(index + count))
            assertMatchesOracle(tree, array, "remove \(count) at \(index)")
        }
    }

    func testRemoveLinesEntireDocumentLeavesEmpty() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(640))
        tree.removeLines(at: 0, count: 640)
        XCTAssertEqual(tree.lineCount, 0)
        XCTAssertEqual(tree.offset(ofLine: 0), 0.0)
        XCTAssertEqual(tree.treeHeight(), 0)
    }

    func testRemoveLinesEqualsLoopOfSingleRemoves() {
        var bulk = BalancedTreeLineMetrics(heights: sampleHeights(500))
        var loop = BalancedTreeLineMetrics(heights: sampleHeights(500))
        let index = 113
        let count = 80
        bulk.removeLines(at: index, count: count)
        for _ in 0..<count { loop.removeLine(at: index) }
        XCTAssertEqual(bulk.lineCount, loop.lineCount)
        for i in 0...bulk.lineCount {
            XCTAssertEqual(bulk.offset(ofLine: i), loop.offset(ofLine: i), "offset[\(i)]")
        }
    }

    func testRemoveLinesZeroCountIsNoOp() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(50))
        let before = (0...tree.lineCount).map { tree.offset(ofLine: $0) }
        let visits = tree.removeLines(at: 25, count: 0)
        XCTAssertEqual(visits, 0)
        XCTAssertEqual(tree.lineCount, 50)
        XCTAssertEqual((0...tree.lineCount).map { tree.offset(ofLine: $0) }, before)
    }

    func testRemoveLinesKeepsOffsetsStrictlyIncreasing() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(400))
        tree.removeLines(at: 0, count: 30)
        tree.removeLines(at: tree.lineCount - 20, count: 20)
        tree.removeLines(at: 100, count: 50)
        for i in 0..<tree.lineCount {
            XCTAssertLessThan(tree.offset(ofLine: i), tree.offset(ofLine: i + 1), "at \(i)")
        }
    }

    func testRemoveLinesVisitCountIsCountPlusLogarithmic() {
        let count = 64
        for n in [1_000, 100_000, 1_000_000] {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
            let visits = tree.removeLines(at: n / 2, count: count)
            XCTAssertLessThanOrEqual(visits, count + 12 * (floorLog2(n) + 1), "n=\(n)")
            XCTAssertLessThan(visits, count * (floorLog2(n) + 1), "n=\(n) not below compose cost")
        }
    }

    func testBulkChurnKeepsTreeBalanced() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(2_000))
        for k in 0..<300 {
            let count = tree.lineCount
            if k % 2 == 0 {
                let batch = (0..<(1 + k % 50)).map { Double(10 + ($0 % 5) * 6) }
                tree.insertLines(at: (k * 7) % (count + 1), heights: batch)
            } else {
                let span = min(1 + k % 50, tree.lineCount)
                let index = tree.lineCount == 0 ? 0 : (k * 13) % (tree.lineCount - span + 1)
                tree.removeLines(at: index, count: span)
            }
        }
        XCTAssertGreaterThan(tree.lineCount, 0)
        XCTAssertLessThanOrEqual(
            tree.treeHeight(),
            3 * (floorLog2(tree.lineCount) + 1),
            "tree height not logarithmic: \(tree.treeHeight()) for \(tree.lineCount)"
        )
    }

    func testBulkChurnReusesArenaSlots() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(1_000))
        let batch = (0..<128).map { Double(10 + ($0 % 5) * 6) }
        // First cycle establishes the high-water mark; later cycles must not grow.
        tree.removeLines(at: 400, count: 128)
        tree.insertLines(at: 400, heights: batch)
        let arenaAfterFirstCycle = tree.arenaNodeCount
        let freeAfterFirstCycle = tree.freeSlotCount
        for c in 0..<10 {
            tree.removeLines(at: 200 + c, count: 128)
            tree.insertLines(at: 200 + c, heights: batch)
            XCTAssertEqual(tree.arenaNodeCount, arenaAfterFirstCycle, "arena grew on cycle \(c)")
            XCTAssertEqual(tree.freeSlotCount, freeAfterFirstCycle, "free slots drifted on cycle \(c)")
        }
        XCTAssertEqual(tree.lineCount, 1_000)
    }

    func testNativeLineIndexVisitCountIsLogarithmic() {
        for n in [1_000, 100_000, 1_000_000] {
            let heights = sampleHeights(n)
            let tree = BalancedTreeLineMetrics(heights: heights)
            let oracle = PrefixSumLineMetrics(heights: heights)
            let samples = [
                0.0,
                oracle.offset(ofLine: n / 2),
                oracle.offset(ofLine: n).nextDown
            ]

            for y in samples {
                let measured = tree.lineIndexAndVisitCount(containingOffset: y)
                XCTAssertEqual(measured.lineIndex, oracle.lineIndex(containingOffset: y), "n=\(n) y=\(y)")
                XCTAssertLessThanOrEqual(measured.visits, 4 * (floorLog2(n) + 1), "n=\(n) y=\(y)")
                XCTAssertGreaterThan(measured.visits, 0, "n=\(n) y=\(y)")
            }
        }
    }

    func testNativeFirstLineIndexAtOrAboveVisitCountIsLogarithmic() {
        for n in [1_000, 100_000, 1_000_000] {
            let heights = sampleHeights(n)
            let tree = BalancedTreeLineMetrics(heights: heights)
            let oracle = PrefixSumLineMetrics(heights: heights)
            let samples = [
                0.0,
                oracle.offset(ofLine: n / 2) + 1.0,
                oracle.offset(ofLine: n).nextDown
            ]
            for y in samples {
                let measured = tree.firstLineIndexAndVisitCount(withOffsetAtOrAbove: y)
                XCTAssertEqual(measured.lineIndex, bruteFirstAtOrAbove(oracle, y), "n=\(n) y=\(y)")
                XCTAssertLessThanOrEqual(measured.visits, 4 * (floorLog2(n) + 1), "n=\(n) y=\(y)")
                XCTAssertGreaterThan(measured.visits, 0, "n=\(n) y=\(y)")
            }
        }
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

    func testMixedMutationEquivalenceOracle() {
        // Deterministic LCG (no Foundation): seeded, reproducible op sequence.
        var rngState: UInt64 = 0x2545F4914F6CDD1D
        func nextRandom(_ bound: Int) -> Int {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return Int((rngState >> 33) % UInt64(bound))
        }

        var tree = BalancedTreeLineMetrics(heights: sampleHeights(40))
        var array = sampleHeights(40)
        let heightChoices = [10.0, 16.0, 22.0, 28.0, 34.0]

        for step in 0..<2_000 {
            let count = array.count
            let op = count == 0 ? 0 : nextRandom(3) // force insert when empty
            switch op {
            case 0: // insert (head / tail / interior all reachable)
                let index = nextRandom(count + 1)
                let height = heightChoices[nextRandom(heightChoices.count)]
                tree.insertLine(at: index, height: height)
                array.insert(height, at: index)
            case 1: // remove
                let index = nextRandom(count)
                tree.removeLine(at: index)
                array.remove(at: index)
            default: // setHeight
                let index = nextRandom(count)
                let height = heightChoices[nextRandom(heightChoices.count)]
                tree.setHeight(ofLine: index, to: height)
                array[index] = height
            }
            assertMatchesOracle(tree, array, "after step \(step) op \(op)")
            // Strictly-increasing invariant (spec test 3) after each op.
            for i in 0..<tree.lineCount {
                XCTAssertLessThan(
                    tree.offset(ofLine: i),
                    tree.offset(ofLine: i + 1),
                    "not strictly increasing at \(i) after step \(step)"
                )
            }
        }

        // Remove-to-empty edge, then refill from empty.
        while array.count > 0 {
            tree.removeLine(at: 0)
            array.remove(at: 0)
            assertMatchesOracle(tree, array, "draining to empty")
        }
        XCTAssertEqual(tree.lineCount, 0)
        tree.insertLine(at: 0, height: 21.0)
        array.insert(21.0, at: 0)
        assertMatchesOracle(tree, array, "refill from empty")
    }

    // MARK: - Bulk integration (Slice 25)

    func testMixedBulkAndSingleMutationEquivalenceOracle() {
        var rngState: UInt64 = 0x9E3779B97F4A7C15
        func nextRandom(_ bound: Int) -> Int {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return Int((rngState >> 33) % UInt64(bound))
        }

        var tree = BalancedTreeLineMetrics(heights: sampleHeights(60))
        var array = sampleHeights(60)
        let heightChoices = [10.0, 16.0, 22.0, 28.0, 34.0]

        for step in 0..<1_500 {
            let count = array.count
            let op = count == 0 ? 0 : nextRandom(5)
            switch op {
            case 0: // bulk insert
                let index = nextRandom(count + 1)
                let k = 1 + nextRandom(40)
                let batch = (0..<k).map { _ in heightChoices[nextRandom(heightChoices.count)] }
                tree.insertLines(at: index, heights: batch)
                array.insert(contentsOf: batch, at: index)
            case 1: // bulk remove
                let span = 1 + nextRandom(min(40, count))
                let index = nextRandom(count - span + 1)
                tree.removeLines(at: index, count: span)
                array.removeSubrange(index..<(index + span))
            case 2: // single insert
                let index = nextRandom(count + 1)
                let height = heightChoices[nextRandom(heightChoices.count)]
                tree.insertLine(at: index, height: height)
                array.insert(height, at: index)
            case 3: // single remove
                let index = nextRandom(count)
                tree.removeLine(at: index)
                array.remove(at: index)
            default: // setHeight
                let index = nextRandom(count)
                let height = heightChoices[nextRandom(heightChoices.count)]
                tree.setHeight(ofLine: index, to: height)
                array[index] = height
            }
            assertMatchesOracle(tree, array, "after step \(step) op \(op)")
        }
    }

    func testReLayoutAfterBulkEditMatchesFreshOracle() {
        var array = sampleHeights(10_000)
        var tree = BalancedTreeLineMetrics(heights: array)
        tree.removeLines(at: 4_000, count: 500)
        array.removeSubrange(4_000..<4_500)
        let inserted = (0..<500).map { Double(12 + ($0 % 5) * 6) }
        tree.insertLines(at: 2_000, heights: inserted)
        array.insert(contentsOf: inserted, at: 2_000)
        let oracle = PrefixSumLineMetrics(heights: array)

        let input = VariableViewportInput(
            scrollOffsetY: oracle.offset(ofLine: 5_000) - 100.0,
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )
        let treeRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: tree))
        let oracleRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: oracle))
        XCTAssertEqual(treeRange, oracleRange)

        var treeCursor = ViewportVirtualizer.geometry(for: treeRange, metrics: tree)
        var oracleCursor = ViewportVirtualizer.geometry(for: oracleRange, metrics: oracle)
        var emitted = 0
        while true {
            let a = treeCursor.next()
            let b = oracleCursor.next()
            XCTAssertEqual(a, b, "geometry mismatch at \(emitted)")
            if a == nil && b == nil { break }
            emitted += 1
            if emitted >= 1_000 { XCTFail("cursor did not terminate"); return }
        }
        XCTAssertGreaterThan(emitted, 0)
    }

    func testReLayoutAfterBulkEditUsesLogarithmicCoreQueries() {
        let n = 1_000_000
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
        tree.removeLines(at: n / 3, count: 1_000)
        tree.insertLines(at: n / 4, heights: (0..<1_000).map { Double(20 + $0 % 9) })

        let counter = QueryCounter()
        let counting = CountingMetrics(base: tree, counter: counter)
        let input = VariableViewportInput(
            scrollOffsetY: tree.offset(ofLine: n / 2),
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )
        _ = expectSuccess(ViewportVirtualizer.compute(input, metrics: counting))
        let expectedMax = 2 + (ceilLog2(n) + 1) * 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }

    func testStructuralMutationVisitCountIsLogarithmic() {
        var visitsBySize: [Int: Int] = [:]
        for n in [1_000, 100_000, 1_000_000] {
            var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
            let visits = tree.insertLine(at: n / 2, height: 24.0)
            XCTAssertGreaterThan(visits, 0)
            // Descent + rebalance touches stay within a small constant times log N.
            XCTAssertLessThanOrEqual(visits, 10 * (floorLog2(n) + 1), "n=\(n)")
            visitsBySize[n] = visits
        }
        // A 1000x size jump must NOT scale visits ~1000x; a balanced tree's
        // descent grows only logarithmically (~2x over this range).
        XCTAssertLessThan(
            visitsBySize[1_000_000]!,
            visitsBySize[1_000]! * 8,
            "node visits grew faster than logarithmic across a 1000x size jump"
        )
    }

    func testTreeHeightStaysLogarithmicAfterEditSequence() {
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(10_000))
        // Deterministic interleaved inserts and deletes that churn the structure.
        for k in 0..<10_000 {
            let count = tree.lineCount
            if k % 2 == 0 {
                let index = (k &* 7) % (count + 1)
                tree.insertLine(at: index, height: Double(12 + (k % 4) * 5))
            } else {
                let index = (k &* 13) % count
                tree.removeLine(at: index)
            }
        }
        XCTAssertGreaterThan(tree.lineCount, 0)
        XCTAssertLessThanOrEqual(
            tree.treeHeight(),
            3 * (floorLog2(tree.lineCount) + 1),
            "tree height not logarithmic: height=\(tree.treeHeight()) lineCount=\(tree.lineCount)"
        )
    }

    func testReLayoutAfterStructuralEditMatchesFreshOracle() {
        var array = sampleHeights(10_000)
        var tree = BalancedTreeLineMetrics(heights: array)
        // Structural edit: delete one line, insert a different one elsewhere.
        tree.removeLine(at: 4_321)
        array.remove(at: 4_321)
        tree.insertLine(at: 2_000, height: 48.0)
        array.insert(48.0, at: 2_000)
        let oracle = PrefixSumLineMetrics(heights: array)

        let input = VariableViewportInput(
            scrollOffsetY: oracle.offset(ofLine: 5_000) - 100.0,
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )
        let treeRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: tree))
        let oracleRange = expectSuccess(ViewportVirtualizer.compute(input, metrics: oracle))
        XCTAssertEqual(treeRange, oracleRange)

        var treeCursor = ViewportVirtualizer.geometry(for: treeRange, metrics: tree)
        var oracleCursor = ViewportVirtualizer.geometry(for: oracleRange, metrics: oracle)
        var emitted = 0
        while true {
            let a = treeCursor.next()
            let b = oracleCursor.next()
            XCTAssertEqual(a, b, "geometry mismatch at emitted index \(emitted)")
            if a == nil && b == nil { break }
            emitted += 1
            if emitted >= 1_000 {
                XCTFail("geometry cursor did not terminate")
                return
            }
        }
        XCTAssertGreaterThan(emitted, 0)
    }

    func testReLayoutAfterStructuralEditUsesLogarithmicCoreQueries() {
        let n = 1_000_000
        var tree = BalancedTreeLineMetrics(heights: sampleHeights(n))
        tree.removeLine(at: n / 3)
        tree.insertLine(at: n / 4, height: 50.0) // lineCount back to n

        let counter = QueryCounter()
        let counting = CountingMetrics(base: tree, counter: counter)
        let input = VariableViewportInput(
            scrollOffsetY: tree.offset(ofLine: n / 2),
            viewportHeight: 80.0 * 16.0,
            overscanLinesBefore: 5,
            overscanLinesAfter: 5
        )
        _ = expectSuccess(ViewportVirtualizer.compute(input, metrics: counting))

        // Two O(1) contract queries (offset 0 and total) plus two binary searches.
        // A linear scan would be hundreds of thousands of queries.
        let expectedMax = 2 + (ceilLog2(n) + 1) * 2
        XCTAssertLessThanOrEqual(counter.count, expectedMax)
        XCTAssertLessThan(counter.count, 100)
    }
}
