import XCTest
@testable import ViewportBenchmarks

// Both wrap modes' printed lines, pinned through their pure formatters.
//
// Two claims live here that were previously eyeballed:
//
//  1. Every measurement names its own operation count (`*_operations_per_sample=`), and
//     reindex's is the VALUE 1 rather than an absent token -- spec Decision 3: a missing
//     token reads as an oversight, a token reading 1 reads as a decision.
//  2. Neither line carries a BARE `p95_ns` / `p99_ns` key. That is the whole reason these
//     modes are inert to the harvester: harvest-gate-corpus.sh matches `p95_ns=` as a
//     substring but then requires the EXACT key, so `query_p95_ns=` yields no row. Node 6
//     flips this deliberately; until then, un-prefixing one by accident must be a red test,
//     not a surprise corpus row.
final class WrapBenchmarkLineShapeTests: XCTestCase {

    // The harvester's exact-key rule, mirrored: split on spaces, take the text before the
    // first `=`. `query_p95_ns` and `p95_ns` are different keys; substring matching is not.
    private func tokenKeys(_ line: String) -> [String] {
        line.split(separator: " ").map { String($0.split(separator: "=")[0]) }
    }

    private func value(_ key: String, in line: String) -> String? {
        for token in line.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == Substring(key) { return String(parts[1]) }
        }
        return nil
    }

    func testWrapRowQueryLineCarriesItsOperationCountAndNoBareLatencyKeys() {
        let line = formatWrapRowQueryLine(
            scenarioName: "uniform_1k", totalRows: 1_000, operationsPerSample: 256,
            p95Nanoseconds: 37, p99Nanoseconds: 41, checksum: 12_345)

        XCTAssertEqual(value("mode", in: line), "wrap_row_query")
        XCTAssertEqual(value("scenario", in: line), "uniform_1k")
        XCTAssertEqual(value("query_operations_per_sample", in: line), "256")
        XCTAssertEqual(value("query_p95_ns", in: line), "37")
        XCTAssertEqual(value("query_p99_ns", in: line), "41")
        XCTAssertEqual(value("checksum", in: line), "12345")

        let keys = tokenKeys(line)
        XCTAssertFalse(keys.contains("p95_ns"), "bare p95_ns would make this line harvestable")
        XCTAssertFalse(keys.contains("p99_ns"), "bare p99_ns would make this line harvestable")
    }

    func testWrapComputeLineCarriesThreeOperationCountsAndNoBareLatencyKeys() {
        let line = formatWrapComputeLine(
            widthLabel: "40", totalRows: 200_000,
            computeOperationsPerSample: 256, computeP95Nanoseconds: 210, computeP99Nanoseconds: 260,
            drainOperationsPerSample: 16, drainP95Nanoseconds: 4_100, drainP99Nanoseconds: 5_200,
            reindexNanoseconds: 61_000_000)

        XCTAssertEqual(value("mode", in: line), "wrap_compute")
        // scenario= is what both consumers group on (`mode|scenario`); the line carried only
        // width= before this slice, so node 6 would have had no grouping key.
        XCTAssertEqual(value("scenario", in: line), "width_40")
        XCTAssertEqual(value("width", in: line), "40")
        XCTAssertEqual(value("compute_operations_per_sample", in: line), "256")
        XCTAssertEqual(value("drain_operations_per_sample", in: line), "16")
        // Spec Decision 3: reindex is a one-shot O(N) setup, exempt from amortisation, and
        // the exemption is stated as a VALUE.
        XCTAssertEqual(value("reindex_operations_per_sample", in: line), "1")
        XCTAssertEqual(value("compute_p95_ns", in: line), "210")
        XCTAssertEqual(value("compute_p99_ns", in: line), "260")
        XCTAssertEqual(value("drain_p95_ns", in: line), "4100")
        // No gate can be derived from p95 alone: node 6 needs both statistics.
        XCTAssertEqual(value("drain_p99_ns", in: line), "5200")
        XCTAssertEqual(value("reindex_ns", in: line), "61000000")

        let keys = tokenKeys(line)
        XCTAssertFalse(keys.contains("p95_ns"), "bare p95_ns would make this line harvestable")
        XCTAssertFalse(keys.contains("p99_ns"), "bare p99_ns would make this line harvestable")
    }
}
