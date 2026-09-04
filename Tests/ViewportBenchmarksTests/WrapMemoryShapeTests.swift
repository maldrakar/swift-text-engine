import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class WrapMemoryShapeTests: XCTestCase {
    private func scenario(_ label: String, _ width: Double) -> WrapMemoryShapeScenario {
        WrapMemoryShapeScenario(
            name: "1k_lines_width_\(label)", lineCount: 1_000, wrapWidth: width, widthLabel: label)
    }

    private var allWidths: [(String, Double)] { [("inf", .infinity), ("40", 40.0), ("10", 10.0)] }

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
