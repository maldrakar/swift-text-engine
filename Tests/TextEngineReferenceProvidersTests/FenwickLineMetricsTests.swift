import XCTest
import TextEngineReferenceProviders

final class FenwickLineMetricsTests: XCTestCase {
    // Deterministic, integer-valued, strictly-positive non-uniform heights in
    // {14,16,20,32}. Integer values with totals < 2^53 make Fenwick prefix sums
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

    // floor(log2(value)) for value >= 1.
    private func floorLog2(_ value: Int) -> Int {
        precondition(value >= 1)
        return Int.bitWidth - 1 - value.leadingZeroBitCount
    }

    func testOffsetMatchesPrefixSumOracleOnBuild() {
        let heights = sampleHeights(1_000)
        let fenwick = FenwickLineMetrics(heights: heights)
        let oracle = PrefixSumLineMetrics(heights: heights)

        XCTAssertEqual(fenwick.lineCount, oracle.lineCount)
        for i in 0...heights.count {
            XCTAssertEqual(
                fenwick.offset(ofLine: i),
                oracle.offset(ofLine: i),
                "offset mismatch at \(i)"
            )
        }
    }

    func testMutationKeepsOffsetsEqualToFreshOracle() {
        let heights = sampleHeights(500)
        var fenwick = FenwickLineMetrics(heights: heights)
        var mutated = heights

        // First line, last line, an interior line, then the same interior line
        // again (repeated edit). All values integer-valued and positive.
        let edits: [(index: Int, height: Double)] = [
            (0, 40.0), (heights.count - 1, 12.0), (250, 28.0), (250, 50.0)
        ]

        for edit in edits {
            fenwick.setHeight(ofLine: edit.index, to: edit.height)
            mutated[edit.index] = edit.height
            let oracle = PrefixSumLineMetrics(heights: mutated)
            for i in 0...heights.count {
                XCTAssertEqual(
                    fenwick.offset(ofLine: i),
                    oracle.offset(ofLine: i),
                    "mismatch at \(i) after editing line \(edit.index)"
                )
            }
        }
    }

    func testUpdateWriteCountIsLogarithmicAcrossSizes() {
        // Updating line 0 (BIT position 1) writes to positions 1,2,4,...,<=N,
        // i.e. exactly floor(log2 N) + 1 cells. A 1000x size jump adds ~10
        // writes, not 1000x - the localized O(log N) update proof.
        let cases: [(n: Int, expected: Int)] = [
            (1_000, 10), (100_000, 17), (1_000_000, 20)
        ]
        for testCase in cases {
            var fenwick = FenwickLineMetrics(heights: sampleHeights(testCase.n))
            let writes = fenwick.setHeight(ofLine: 0, to: 17.0)
            XCTAssertEqual(writes, testCase.expected, "n=\(testCase.n)")
            XCTAssertEqual(writes, floorLog2(testCase.n) + 1, "n=\(testCase.n)")
            XCTAssertEqual(fenwick.lastUpdateWriteCount, testCase.expected, "n=\(testCase.n)")
        }
    }

    func testUpdateWriteCountExactForKnownSmallCases() {
        var fenwick = FenwickLineMetrics(heights: sampleHeights(8))
        // line 0 -> BIT position 1 -> writes 1,2,4,8
        XCTAssertEqual(fenwick.setHeight(ofLine: 0, to: 10.0), 4)
        // line 7 -> BIT position 8 -> writes 8 only
        XCTAssertEqual(fenwick.setHeight(ofLine: 7, to: 10.0), 1)
    }

    func testPrefixQueryWalkBoundIsLogarithmic() {
        // offset(ofLine: index) reads exactly popcount(index) BIT cells (one per
        // set bit; see FenwickLineMetrics.offset). Over the index domain
        // 0...lineCount that never exceeds floor(log2 N) + 1, including the
        // max-popcount (all-ones) index. We also confirm those long-walk indices
        // produce correct offsets.
        for n in [1_000, 100_000, 1_000_000] {
            let bound = floorLog2(n) + 1
            let heights = sampleHeights(n)
            let fenwick = FenwickLineMetrics(heights: heights)
            let oracle = PrefixSumLineMetrics(heights: heights)
            let allOnes = (1 << floorLog2(n)) - 1   // largest 2^k - 1 <= n

            for index in [0, 1, n / 2, n - 1, n, allOnes] {
                XCTAssertLessThanOrEqual(index.nonzeroBitCount, bound, "index=\(index) n=\(n)")
                XCTAssertEqual(
                    fenwick.offset(ofLine: index),
                    oracle.offset(ofLine: index),
                    "offset mismatch at long-walk index \(index) for n=\(n)"
                )
            }
        }
    }

    func testOffsetsStrictlyIncreasingAfterMutation() {
        let heights = sampleHeights(300)
        var fenwick = FenwickLineMetrics(heights: heights)
        fenwick.setHeight(ofLine: 0, to: 64.0)
        fenwick.setHeight(ofLine: 299, to: 2.0)
        fenwick.setHeight(ofLine: 150, to: 5.0)

        for i in 0..<fenwick.lineCount {
            XCTAssertLessThan(
                fenwick.offset(ofLine: i),
                fenwick.offset(ofLine: i + 1),
                "offsets not strictly increasing at line \(i)"
            )
        }
    }
}
