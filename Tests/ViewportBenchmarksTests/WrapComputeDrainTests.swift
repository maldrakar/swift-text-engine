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
    private final class ProbeCounter {
        var firstVisualRowCalls = 0
        var firstVisualRowAtLineCount = 0
    }

    private struct CountingLayout: VisualRowLayoutSource {
        let base: BenchmarkWrapLayout
        let counter: ProbeCounter
        var lineCount: Int { base.lineCount }
        var rowHeight: Double { base.rowHeight }
        var wrapWidth: Double { base.wrapWidth }
        func columnCount(inLine line: Int) -> Int { base.columnCount(inLine: line) }
        func columnOffset(inLine line: Int, column: Int) -> Double { base.columnOffset(inLine: line, column: column) }
        func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { base.canBreak(beforeColumn: column, inLine: line) }
        func visualRowCount(inLine line: Int) -> Int { base.visualRowCount(inLine: line) }
        func firstVisualRow(ofLine line: Int) -> Int {
            counter.firstVisualRowCalls += 1
            if line == base.lineCount { counter.firstVisualRowAtLineCount += 1 }
            return base.firstVisualRow(ofLine: line)
        }
    }

    func testDrainBodyPerformsNoCompute() {
        // 64 lines x 8 cells at width 4 -> 2 rows per line, 128 rows.
        let base = BenchmarkWrapLayout(lineCount: 64, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
        let input = VariableViewportInput(scrollOffsetY: 40.0, viewportHeight: 100.0, overscanLinesBefore: 4, overscanLinesAfter: 4)

        // The range is built OUTSIDE the counted region, exactly as the benchmark builds
        // its drain ranges outside the clock (slice 54 spec, Decision 4).
        guard case .success(let range) = ViewportVirtualizer.compute(input, layout: base) else {
            return XCTFail("expected success")
        }

        // Witness: compute(_:layout:) DOES make the probe this test counts, so a zero
        // below is a measurement and not an absence of instrumentation.
        let witness = ProbeCounter()
        _ = ViewportVirtualizer.compute(input, layout: CountingLayout(base: base, counter: witness))
        XCTAssertGreaterThan(witness.firstVisualRowAtLineCount, 0, "compute must probe firstVisualRow(ofLine: lineCount), or the zero below is vacuous")

        let counter = ProbeCounter()
        let sink = drainVisualRows(range, layout: CountingLayout(base: base, counter: counter))
        XCTAssertGreaterThan(sink, 0, "the drain must have streamed rows")
        XCTAssertGreaterThan(counter.firstVisualRowCalls, 0, "the drain locates its start line through the layout")
        XCTAssertEqual(counter.firstVisualRowAtLineCount, 0, "the drain body must not compute a range")
    }
}
