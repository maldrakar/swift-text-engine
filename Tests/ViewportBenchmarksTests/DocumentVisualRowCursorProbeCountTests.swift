import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class DocumentVisualRowCursorProbeCountTests: XCTestCase {
    private func drainProbes(lineCount: Int, wrapWidth: Double) -> Int {
        let base = BenchmarkWrapLayout(
            lineCount: lineCount, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: wrapWidth)
        // The buffer starts at the middle line's first row, so the within-line phase is
        // the same at every document size (spec Decision 9) and what is left varying is
        // the logarithmic search.
        let input = VariableViewportInput(
            scrollOffsetY: 16.0 * Double(base.firstVisualRow(ofLine: lineCount / 2)),
            viewportHeight: 160.0, overscanLinesBefore: 5, overscanLinesAfter: 5)
        guard case let .success(range) = ViewportVirtualizer.compute(input, layout: base) else {
            XCTFail("compute failed at \(lineCount)/\(wrapWidth)")
            return -1
        }
        let counter = WrapProbeCounter()
        _ = drainVisualRows(range, layout: CountingWrapLayout(base: base, counter: counter))
        return counter.total
    }

    // G21. The drain's probe count does not grow with the DOCUMENT. It grows with the
    // width (fewer logical lines per buffered row), which is a different axis and the
    // subject of the mode's invariant 11. WrapComputeDrainTests pins that the drain
    // performs no compute; nothing pinned that it does not walk the document.
    //
    // A 100x jump in lineCount buys at most the extra levels of one binary search --
    // log2(100) is under 7, and the bound is deliberately loose against that.
    func testDrainProbesDoNotGrowWithTheDocument() {
        for width in [Double.infinity, 10.0] {
            let small = drainProbes(lineCount: 1_000, wrapWidth: width)
            let large = drainProbes(lineCount: 100_000, wrapWidth: width)
            XCTAssertGreaterThan(small, 0, "width=\(width): the drain must probe something")
            XCTAssertLessThanOrEqual(
                large - small, 32,
                "width=\(width): probes went \(small) -> \(large) across a 100x document")
        }
    }

    // ...and it DOES move with the width, so the bound above is not passing because the
    // counter is inert.
    func testDrainProbesMoveWithTheWidth() {
        XCTAssertNotEqual(
            drainProbes(lineCount: 10_000, wrapWidth: .infinity),
            drainProbes(lineCount: 10_000, wrapWidth: 4.0))
    }
}
