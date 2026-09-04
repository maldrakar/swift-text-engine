import XCTest
import TextEngineCore
@testable import ViewportBenchmarks

final class CountingWrapLayoutTests: XCTestCase {
    // 64 lines x 8 cells at width 4 -> 2 rows per line, 128 rows. Small enough for
    // `swift test`, wide enough that every hook is reachable.
    private func base() -> BenchmarkWrapLayout {
        BenchmarkWrapLayout(lineCount: 64, cells: 8, advance: 1.0, rowHeight: 16.0, wrapWidth: 4.0)
    }

    private func input() -> VariableViewportInput {
        VariableViewportInput(
            scrollOffsetY: 40.0, viewportHeight: 100.0,
            overscanLinesBefore: 4, overscanLinesAfter: 4)
    }

    // G8. Every hook increments its own counter. A hook whose increment is missing reads
    // as "the core never called it", which is exactly the reading a memory-shape
    // assertion would take at face value. Each assertion names the entry point that
    // WITNESSES the hook (Decision 7), so a zero here is a measurement, not an absence of
    // instrumentation.
    func testEveryHookIsCounted() {
        let counter = WrapProbeCounter()
        let layout = CountingWrapLayout(base: base(), counter: counter)

        // Witness for firstVisualRow + the by-argument counter: compute's ladder.
        guard case let .success(range) = ViewportVirtualizer.compute(input(), layout: layout) else {
            return XCTFail("expected success")
        }
        XCTAssertGreaterThan(counter.firstVisualRow, 0, "compute probes firstVisualRow")

        // Witness for logicalLine: the drain locates its start line and walks lines.
        let drainCounter = WrapProbeCounter()
        let drainLayout = CountingWrapLayout(base: base(), counter: drainCounter)
        XCTAssertGreaterThan(drainVisualRows(range, layout: drainLayout), 0, "the drain streamed rows")
        XCTAssertGreaterThan(drainCounter.logicalLine, 0, "the drain dispatches logicalLine")
        // FINDING (Task 1, not predicted by the plan/brief): `visualRowCount(inLine:)` has
        // no consuming call site anywhere in `Sources/TextEngineCore` -- not in
        // `validateVisualRowLayout` (compute's ladder), not in `DocumentVisualRowCursor`
        // (this drain), not in `visualRowAt`, not in `visualPointAt`. Confirmed by
        // `grep -rn '\.visualRowCount(' Sources/TextEngineCore/` returning zero hits
        // outside the protocol declaration in `VisualRowLayoutSource.swift`. So this hook
        // reads 0 through every entry point `--memory-shape`'s wrap half measures; the
        // plan's ">0, the packer reads visualRowCount" claim
        // (docs/superpowers/plans/2026-09-04-wrap-memory-shape.md:121) does not hold
        // against the shipped core and is corrected here rather than silently dropped --
        // see the Task 1 record for the drill-equivalent read of this. The pair below reads
        // as one argument: the core never calls this hook (`== 0`), AND the wrapper does
        // count it when called (the direct witness) -- so the `== 0` above is a statement
        // about the core, not a symptom of a missing increment.
        XCTAssertEqual(
            drainCounter.visualRowCount, 0,
            "visualRowCount(inLine:) has no consuming call site in the core's wrap query paths")
        // Decision 7's witness for this hook. No core entry point calls it (the finding
        // above), so the witness is a direct call: without this, deleting the increment
        // inside CountingWrapLayout.visualRowCount(inLine:) reddens nothing, and the `== 0`
        // above would silently become a statement about missing instrumentation rather than
        // about the core.
        let hookWitness = WrapProbeCounter()
        _ = CountingWrapLayout(base: base(), counter: hookWitness).visualRowCount(inLine: 0)
        XCTAssertEqual(hookWitness.visualRowCount, 1, "the hook increments its own counter")

        // Witness for columnCount, columnOffset and canBreak: the packer measures cells.
        XCTAssertGreaterThan(drainCounter.columnCount, 0, "the packer reads columnCount")
        XCTAssertGreaterThan(drainCounter.columnOffset, 0, "the packer reads columnOffset")
        XCTAssertGreaterThan(drainCounter.canBreak, 0, "the packer reads canBreak")

        // `total` is the sum of the six hooks. Checked here on the DRAIN counter as a
        // broader combination -- columnCount, columnOffset, canBreak, firstVisualRow and
        // logicalLine are all non-zero on this path -- so a `total` formula that omits or
        // duplicates one of THOSE terms trips it.
        XCTAssertEqual(
            drainCounter.total,
            drainCounter.columnCount + drainCounter.columnOffset + drainCounter.canBreak
                + drainCounter.visualRowCount + drainCounter.firstVisualRow + drainCounter.logicalLine)

        // The claim that still needs its own falsifiable check is narrower: `total` MUST
        // NOT double-count the BY-ARGUMENT counter `firstVisualRowAtLineCount`, which is a
        // strict SUBSET of `firstVisualRow`, not a seventh hook. `drainCounter` cannot
        // witness that claim -- its `firstVisualRowAtLineCount` is always 0 (the drain
        // never reads totalRows; G19, pinned separately below), so folding it into the sum
        // above would change nothing and the identity would stay green even if `total`
        // mistakenly counted it twice. `counter` -- the COMPUTE counter built at the top of
        // this test -- has `firstVisualRowAtLineCount == 1`, so asserting the same identity
        // on it is the version that can actually fail for the reason stated.
        XCTAssertEqual(
            counter.total,
            counter.columnCount + counter.columnOffset + counter.canBreak
                + counter.visualRowCount + counter.firstVisualRow + counter.logicalLine)
    }

    // G19. The by-argument counter, which D-29's discharge rests on: "the drain performs
    // no compute" is "no probe with the argument lineCount happened", and six per-hook
    // totals cannot express it. Both halves asserted here so the property is pinned in
    // the shared type rather than only in its one consumer.
    func testFirstVisualRowAtLineCountIsCountedSeparately() {
        let computeCounter = WrapProbeCounter()
        _ = ViewportVirtualizer.compute(input(), layout: CountingWrapLayout(base: base(), counter: computeCounter))
        XCTAssertGreaterThan(
            computeCounter.firstVisualRowAtLineCount, 0,
            "compute reads totalRows via firstVisualRow(ofLine: lineCount)")
        XCTAssertLessThan(
            computeCounter.firstVisualRowAtLineCount, computeCounter.firstVisualRow,
            "the by-argument counter is a strict subset: the ladder also probes line 0")

        guard case let .success(range) = ViewportVirtualizer.compute(input(), layout: base()) else {
            return XCTFail("expected success")
        }
        let drainCounter = WrapProbeCounter()
        _ = drainVisualRows(range, layout: CountingWrapLayout(base: base(), counter: drainCounter))
        XCTAssertEqual(
            drainCounter.firstVisualRowAtLineCount, 0,
            "the drain never reads totalRows")
        XCTAssertGreaterThan(drainCounter.firstVisualRow, 0, "...but it does probe firstVisualRow")
    }

    // G22. ATTRIBUTION. The wrapper must not forward `logicalLine` to `base`: the core's
    // default implementation of that requirement runs a binary search that probes
    // `firstVisualRow` on WHATEVER layout it is given, so forwarding would run the search
    // against the unwrapped base and every probe it makes would go uncounted. The drain
    // over a 64-line document must therefore see MORE firstVisualRow probes than the one
    // its start-line lookup needs -- roughly log2(64) of them from the search alone.
    func testTheDefaultLogicalLineSearchIsAttributedToTheCounter() {
        guard case let .success(range) = ViewportVirtualizer.compute(input(), layout: base()) else {
            return XCTFail("expected success")
        }
        let counter = WrapProbeCounter()
        _ = drainVisualRows(range, layout: CountingWrapLayout(base: base(), counter: counter))
        XCTAssertEqual(counter.logicalLine, 1, "the drain dispatches logicalLine exactly once")
        // A forwarding wrapper would report ~1-2 here (the cursor's own probes only).
        XCTAssertGreaterThanOrEqual(
            counter.firstVisualRow, 6,
            "the default logicalLine search over 64 lines costs ~log2(64) firstVisualRow "
                + "probes and they must land in this counter, not in the unwrapped base")
    }

    // G8, metrics half. The variable path's repair needs the same instrument on the
    // vertical axis, with the same attribution property: UniformLineMetrics overrides
    // neither inverse hook, so their default searches probe offset(ofLine:) and those
    // probes must be counted here too.
    //
    // The +1 is named rather than absorbed. `VariableLineGeometryCursor` reads
    // `offset(ofLine: bufferStart)` in its init and `offset(ofLine: i + 1)` per row, so a
    // 90-line buffer resolves 91 distinct indices -- the extra one is the END BOUNDARY,
    // not a buffered line. `touched_lines` counts the buffered ones, so the runner
    // intersects with the range and the counter stays dumb. Asserting both halves here is
    // what stops the interpretation from being invented at the call site later.
    func testCountingLineMetricsCountsOffsetsAndDistinctLines() {
        let counter = LineProbeCounter()
        let metrics = CountingLineMetrics(
            base: UniformLineMetrics(lineCount: 1_000, lineHeight: 16.0), counter: counter)
        let range = VirtualRange(
            visibleStart: 15, visibleEndExclusive: 95,
            bufferStart: 10, bufferEndExclusive: 100,
            isAtTop: false, isAtBottom: false)
        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        var streamed = 0
        while cursor.next() != nil { streamed += 1 }
        XCTAssertEqual(streamed, 90)
        XCTAssertGreaterThan(counter.offset, 0, "the cursor reads offsets")
        XCTAssertEqual(
            counter.distinctLines.count, 91,
            "90 buffered lines plus the end-boundary offset the last row's height needs")
        let buffered = counter.distinctLines.filter {
            $0 >= range.bufferStart && $0 < range.bufferEndExclusive
        }
        XCTAssertEqual(
            buffered.count, 90,
            "the cursor resolves exactly the buffered lines -- this is the count that "
                + "replaces `providerLines: bufferedLines`")
    }
}
