import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class WrapMemoryShapeTests: XCTestCase {
    private func scenario(_ label: String, _ width: Double) -> WrapMemoryShapeScenario {
        WrapMemoryShapeScenario(
            name: "1k_lines_width_\(label)", lineCount: 1_000, wrapWidth: width, widthLabel: label)
    }

    private var allWidths: [(String, Double)] { [("inf", .infinity), ("40", 40.0), ("10", 10.0)] }

    // Pins `wrapMemoryShapeScenarios()`'s exact six-scenario list, in order. Nothing else in
    // this suite asserts the LIST itself -- every other test here calls the scenario
    // constructor directly, never the production function. That matters more than it looks:
    // `wrapMemoryShapeCrossScenarioFailures` reads two of these labels back by STRING --
    // `$0.widthLabel == "10"` and `$0.widthLabel == "inf"` -- to pair invariant 11 (and the
    // per-size pairing for 9/12) across the two document sizes. Relabel a width (say "10" ->
    // "8") and those `first(where:)` lookups simply find nothing: the `if let` fails silently,
    // invariant 11 evaporates, and every emitted line still prints `invariant=pass`. This test
    // is what stops that from happening unnoticed -- the same discipline `pinnedGateSteps` and
    // `everyGatedBudget()` already apply elsewhere in this repository: a downstream check's
    // read set is pinned at the point the check itself cannot see it move.
    func testTheScenarioListIsExactlySixInOrder() {
        let scenarios = wrapMemoryShapeScenarios()
        let expected: [(name: String, lineCount: Int, widthLabel: String, wrapWidth: Double)] = [
            (name: "100k_lines_width_inf", lineCount: 100_000, widthLabel: "inf", wrapWidth: .infinity),
            (name: "100k_lines_width_40", lineCount: 100_000, widthLabel: "40", wrapWidth: 40.0),
            (name: "100k_lines_width_10", lineCount: 100_000, widthLabel: "10", wrapWidth: 10.0),
            (name: "1m_lines_width_inf", lineCount: 1_000_000, widthLabel: "inf", wrapWidth: .infinity),
            (name: "1m_lines_width_40", lineCount: 1_000_000, widthLabel: "40", wrapWidth: 40.0),
            (name: "1m_lines_width_10", lineCount: 1_000_000, widthLabel: "10", wrapWidth: 10.0),
        ]
        XCTAssertEqual(scenarios.count, expected.count, "scenario count")
        for (index, pair) in zip(scenarios, expected).enumerated() {
            let (scenario, want) = pair
            XCTAssertEqual(scenario.name, want.name, "scenario \(index): name")
            XCTAssertEqual(scenario.lineCount, want.lineCount, "scenario \(index): lineCount")
            XCTAssertEqual(scenario.widthLabel, want.widthLabel, "scenario \(index): widthLabel")
            XCTAssertEqual(scenario.wrapWidth, want.wrapWidth, "scenario \(index): wrapWidth")
        }
    }

    // G13 + G14 + G1. The three per-scenario structural invariants, asserted together
    // because they describe one range: it is ordered and inside the row axis, the window
    // is 80/90 at every width (Decision 3), and the cursor streams the buffer exactly.
    func testEveryWidthReportsTheSameWindowAndStreamsIt() {
        for (label, width) in allWidths {
            let summary = runWrapMemoryShapeScenario(scenario(label, width))
            XCTAssertEqual(summary.visibleRows, 80, "\(label): visible window")
            XCTAssertEqual(summary.bufferedRows, 90, "\(label): buffered window")
            XCTAssertEqual(summary.streamedRows, summary.bufferedRows, "\(label): streamed == buffered")
            XCTAssertTrue(summary.rangeIsOrderedAndBounded, "\(label): range ordered and bounded")
            XCTAssertTrue(summary.baseInvariantPasses, "\(label): per-scenario invariants")
        }
    }

    // G5. The within-line walk is EXERCISED, not assumed. The `+ 3` offset puts the query
    // three rows past the middle line's first row, so rowInLine is 0/1/3 at inf/40/10
    // (Decision 9). Asserting the exact triple, not just `> 0` at width 10, is what makes
    // the fixture's own arithmetic falsifiable.
    func testTheQueryLandsOffARowStartAtEveryWrappedWidth() {
        XCTAssertEqual(runWrapMemoryShapeScenario(scenario("inf", .infinity)).pointRowInLine, 0)
        XCTAssertEqual(runWrapMemoryShapeScenario(scenario("40", 40.0)).pointRowInLine, 1)
        XCTAssertEqual(runWrapMemoryShapeScenario(scenario("10", 10.0)).pointRowInLine, 3)
    }

    // G15. x = 5.0 must land INSIDE the located row at every width, or point_query_probes
    // measures the clamp path at one width and the delegating path at another: a clamped
    // x costs 3 + 2 column probes and never reaches columnIndex(containingOffset:inLine:).
    // The narrowest row spans 10 layout units, so 5.0 is the fixture's whole margin.
    func testThePointQueryNeverClamps() {
        for (label, width) in allWidths {
            XCTAssertEqual(
                runWrapMemoryShapeScenario(scenario(label, width)).pointClamp, "none",
                "\(label): x must be in range, or the probe counts compare two branches")
        }
    }

    // G16. Criterion 2's second clause: the linear data is PROVIDER-owned. The measured
    // value is the prefix array's own footprint; the expectation is derived from the line
    // count, independently of the array. Identical across widths at a fixed size, because
    // the prefix has one entry per logical line whatever the width does to the row count.
    func testProviderOwnedBytesIsTheDerivedPrefixSize() {
        let expected = (1_000 + 1) * MemoryLayout<Int>.size
        for (label, width) in allWidths {
            XCTAssertEqual(
                runWrapMemoryShapeScenario(scenario(label, width)).providerOwnedBytes, expected,
                "\(label): provider-owned bytes")
        }
    }

    // The emitted line carries every token §4A names, in order. A token silently dropped
    // from the formatter is a column the hosted record cannot show and a future harvest
    // cannot read.
    func testTheEmittedLineCarriesEveryToken() {
        let line = formatWrapMemoryShapeSummary(
            runWrapMemoryShapeScenario(scenario("10", 10.0)), invariantPasses: true)
        for token in [
            "mode=memory_shape", "provider=wrap", "scenario=1k_lines_width_10", "line_count=1000",
            "wrap_width=10", "total_rows=8000", "visible_rows=80", "buffered_rows=90",
            "streamed_rows=90", "point_row_in_line=3", "point_clamp=none", "compute_probes=",
            "drain_probes=", "row_query_probes=", "point_query_probes=", "core_owned_bytes=",
            "provider_owned_bytes=", "invariant=pass", "checksum="
        ] {
            XCTAssertTrue(line.contains(token), "missing \(token) in: \(line)")
        }
    }

    // The infinite width must print `inf`, the spelling --wrap-compute already uses. Two
    // modes labelling the same width two ways is a reading hazard in the record and a
    // grouping hazard for node 6.
    func testInfiniteWidthPrintsInf() {
        let line = formatWrapMemoryShapeSummary(
            runWrapMemoryShapeScenario(scenario("inf", .infinity)), invariantPasses: true)
        XCTAssertTrue(line.contains("wrap_width=inf"), line)
    }
}
