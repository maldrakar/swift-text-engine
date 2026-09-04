import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

// D-29: `--wrap-compute`'s drain body performs no `compute(_:layout:)`. Slice 54 recorded
// this as reviewable-but-not-machine-checkable; it is checkable, because the property is
// about the LAYOUT, not the timing helper. Every compute(_:layout:) call probes
// `firstVisualRow(ofLine: lineCount)` (the layout ladder reads totalRows), and the drain
// path never can: the logicalLine search probes 0..<lineCount and the cursor probes the
// start line only. So a counting layout that sees zero such probes across the body has
// seen no compute -- and a witness call proves the probe exists to be counted.
final class WrapComputeDrainTests: XCTestCase {
    func testDrainBodyPerformsNoCompute() {
        // 64 lines x 8 cells at width 4 -> 2 rows per line, 128 rows.
        let base = BenchmarkWrapLayout(lineCount: 64, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        let input = VariableViewportInput(scrollOffsetY: 40.0, viewportHeight: 100.0, overscanLinesBefore: 4, overscanLinesAfter: 4)

        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: base) else {
            return XCTFail("expected success")
        }

        // Witness: compute(_:layout:) DOES make the probe this test counts, so a zero
        // below is a measurement and not an absence of instrumentation.
        let witness = WrapProbeCounter()
        _ = ViewportVirtualizer.compute(input, layout: CountingWrapLayout(base: base, counter: witness))
        XCTAssertGreaterThan(witness.firstVisualRowAtLineCount, 0, "compute must probe firstVisualRow(ofLine: lineCount), or the zero below is vacuous")

        let counter = WrapProbeCounter()
        let sink = drainVisualRows(range, layout: CountingWrapLayout(base: base, counter: counter))
        XCTAssertGreaterThan(sink, 0, "the drain must have streamed rows")
        XCTAssertGreaterThan(counter.firstVisualRow, 0, "the drain locates its start line through the layout")
        XCTAssertEqual(counter.firstVisualRowAtLineCount, 0, "the drain body must not compute a range")
    }
}
