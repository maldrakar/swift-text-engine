import XCTest
@testable import ViewportBenchmarks

// All three wrap modes' printed lines, pinned through their pure formatters.
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
            reindexNanoseconds: 61_000_000, checksum: 987_654)

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
        // Slice 55a commit 0: the result-preservation witness for every edit on this
        // mode's path (spec Decision 13). Folds the compute and drain checksums the
        // anti-dead-code guard used to hold; must be byte-identical across every column
        // of the --wrap-compute record.
        XCTAssertEqual(value("checksum", in: line), "987654")

        let keys = tokenKeys(line)
        XCTAssertFalse(keys.contains("p95_ns"), "bare p95_ns would make this line harvestable")
        XCTAssertFalse(keys.contains("p99_ns"), "bare p99_ns would make this line harvestable")
    }

    func testWrapPointQueryLineCarriesItsTokensAndNoBareLatencyKeys() {
        let line = formatWrapPointQueryLine(
            scenarioName: "long_line_deep_row", totalRows: 400_000,
            cellsPerLine: 2_000, rowsPerLine: 400, fastPath: false, rowInLine: 399,
            operationsPerSample: 16, p95Nanoseconds: 1_234, p99Nanoseconds: 2_345,
            checksum: 987_654)

        XCTAssertEqual(value("mode", in: line), "wrap_point_query")
        XCTAssertEqual(value("scenario", in: line), "long_line_deep_row")
        XCTAssertEqual(value("total_rows", in: line), "400000")
        XCTAssertEqual(value("cells_per_line", in: line), "2000")
        XCTAssertEqual(value("rows_per_line", in: line), "400")
        XCTAssertEqual(value("fast_path", in: line), "false")
        XCTAssertEqual(value("row_in_line", in: line), "399")
        XCTAssertEqual(value("query_operations_per_sample", in: line), "16")
        XCTAssertEqual(value("query_p95_ns", in: line), "1234")
        XCTAssertEqual(value("query_p99_ns", in: line), "2345")
        XCTAssertEqual(value("checksum", in: line), "987654")

        let keys = tokenKeys(line)
        XCTAssertFalse(keys.contains("p95_ns"), "bare p95_ns would make this line harvestable")
        XCTAssertFalse(keys.contains("p99_ns"), "bare p99_ns would make this line harvestable")

        // row_in_line is printed only where the sampling rule fixes the depth; elsewhere
        // it is OMITTED rather than filled with an average.
        let uniform = formatWrapPointQueryLine(
            scenarioName: "uniform_1k", totalRows: 1_000,
            cellsPerLine: 20, rowsPerLine: 1, fastPath: true, rowInLine: nil,
            operationsPerSample: 256, p95Nanoseconds: 37, p99Nanoseconds: 41, checksum: 12_345)
        XCTAssertNil(value("row_in_line", in: uniform))
        XCTAssertEqual(value("fast_path", in: uniform), "true")
    }

    /// The scenario table's parameters, pinned so a later shortening is a RED TEST rather
    /// than a quieter benchmark printing a smaller, plausible number.
    ///
    /// The floors are the scenarios' own values, not the spec's `>= 1_000` / `>= 100`:
    /// at those, HALVING `long_line_deep_row`'s cells leaves 1 000 cells and 200 rows,
    /// both still above the floor, so the pin could not fail — the exact shape D-25
    /// describes. The spec permits raising floors, never lowering them.
    func testWrapPointQueryScenarioParametersAreAtTheirFloors() {
        guard let deep = wrapPointQueryScenarios.first(where: { $0.name == "long_line_deep_row" }) else {
            return XCTFail("the long_line_deep_row scenario must exist: it is the only one that measures the walk")
        }
        XCTAssertGreaterThanOrEqual(deep.cells, 2_000, "shortening the line deletes the term this scenario exposes")
        let rowsPerLine = Int((Double(deep.cells) * deep.advance / deep.wrapWidth).rounded(.down))
        XCTAssertGreaterThanOrEqual(rowsPerLine, 400, "the walk must be hundreds of rows deep")
        XCTAssertEqual(deep.rowInLine, rowsPerLine - 1, "the scenario must query the LAST row of its line")
        XCTAssertEqual(deep.operationsPerSample, 16, "a linear-cost scenario takes the smaller operation count")

        // fast_path is a per-scenario constant decidable from the parameters, and every
        // scenario's stored value must equal what its parameters imply.
        for scenario in wrapPointQueryScenarios {
            let implied = Double(scenario.cells) * scenario.advance <= scenario.wrapWidth
            XCTAssertEqual(scenario.fastPath, implied, "\(scenario.name): fast_path must match its parameters")
        }
        XCTAssertEqual(wrapPointQueryScenarios.count, 6)
    }

    /// The multiplication shortcut in `WrapPointQueryLayout` is valid only because every
    /// line in these fixtures is identical — a property of the FIXTURE, not of the type.
    /// So the two constructions are compared element for element on a small shape.
    func testTheTwoWrapLayoutsAgreeOnTheirPrefixSums() {
        let shortcut = WrapPointQueryLayout(lineCount: 8, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        let repacked = BenchmarkWrapLayout(lineCount: 8, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        XCTAssertGreaterThan(repacked.visualRowCount(inLine: 0), 1, "the shape must WRAP, or this compares 1 == 1")
        for line in 0...8 {
            XCTAssertEqual(shortcut.firstVisualRow(ofLine: line), repacked.firstVisualRow(ofLine: line), "line \(line)")
        }
        for line in 0..<8 {
            XCTAssertEqual(shortcut.visualRowCount(inLine: line), repacked.visualRowCount(inLine: line), "line \(line)")
        }
    }
}
