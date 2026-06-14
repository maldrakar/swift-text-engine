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
}
