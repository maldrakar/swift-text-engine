import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class WrapComputeProbeCountTests: XCTestCase {
    private func probes(lineCount: Int, wrapWidth: Double) -> WrapProbeCounter {
        let base = BenchmarkWrapLayout(
            lineCount: lineCount, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: wrapWidth)
        let counter = WrapProbeCounter()
        let input = VariableViewportInput(
            scrollOffsetY: 16.0 * Double(base.firstVisualRow(ofLine: lineCount / 2)),
            viewportHeight: 160.0, overscanLinesBefore: 5, overscanLinesAfter: 5)
        guard case .success = ViewportVirtualizer.compute(
            input, layout: CountingWrapLayout(base: base, counter: counter)) else {
            XCTFail("compute failed at \(lineCount)/\(wrapWidth)")
            return counter
        }
        return counter
    }

    // G20. compute(_:layout:)'s LAYOUT-probe count is a constant: the ladder probes
    // firstVisualRow(ofLine: 0) and firstVisualRow(ofLine: lineCount), and the two
    // boundary searches that follow run over UniformLineMetrics, which touches the layout
    // not at all. Nothing pinned this before: WrapComputeDrainTests counts the DRAIN, and
    // the ladder is otherwise covered only by its error cases.
    //
    // Scope, stated because the number invites the wrong reading: this is flat on the
    // LAYOUT axis. compute's own cost is O(log totalRows) -- UniformLineMetrics overrides
    // neither native inverse hook (D-22), so those boundary searches are binary searches
    // over offset(ofLine:) that this counter cannot see and does not claim to.
    func testComputeProbesTheLayoutAConstantNumberOfTimes() {
        for lineCount in [1_000, 10_000, 100_000] {
            for width in [Double.infinity, 40.0, 10.0, 4.0] {
                XCTAssertEqual(
                    probes(lineCount: lineCount, wrapWidth: width).total,
                    wrapMemoryShapeComputeProbes,
                    "lines=\(lineCount) width=\(width)")
            }
        }
    }

    // The constant is not an opaque 2: one of the two probes is the total-rows probe, and
    // saying so is what lets a reader check the number against the ladder rather than
    // against this test.
    func testOneOfTheTwoProbesIsTheTotalRowsProbe() {
        let counter = probes(lineCount: 10_000, wrapWidth: 10.0)
        XCTAssertEqual(counter.firstVisualRow, 2)
        XCTAssertEqual(counter.firstVisualRowAtLineCount, 1)
        XCTAssertEqual(counter.logicalLine, 0, "compute never dispatches the row inverse")
        XCTAssertEqual(counter.visualRowCount, 0, "compute reads the prefix, never a per-line count")
    }
}
