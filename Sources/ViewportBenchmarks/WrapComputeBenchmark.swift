import TextEngineCore

/// Benchmark-local aggregation provider (not shipped). Every logical line is the same
/// `cells` cells of `advance` width, breakable at every cell (char-wrap). The prefix sum
/// is built by packing EACH line via node 1 at construction — an honest O(N) reindex, so
/// the width-change cost is measured, not faked.
struct BenchmarkWrapLayout: VisualRowLayoutSource {
    let lineCount: Int
    let rowHeight: Double
    let wrapWidth: Double
    let cells: Int
    let advance: Double
    let firstRow: [Int]

    init(lineCount: Int, cells: Int, advance: Double, rowHeight: Double, wrapWidth: Double) {
        self.lineCount = lineCount
        self.rowHeight = rowHeight
        self.wrapWidth = wrapWidth
        self.cells = cells
        self.advance = advance
        // Build the prefix by packing every line (identical here, but packed each time to
        // measure the real O(N) reindex).
        var pref: [Int] = [0]
        pref.reserveCapacity(lineCount + 1)
        let single = SingleLineWrap(cells: cells, advance: advance)
        var running = 0
        for _ in 0..<lineCount {
            var n = 0
            if case .rows(var c) = ViewportVirtualizer.visualRows(inLine: 0, wrapWidth: wrapWidth, metrics: single) {
                while c.next() != nil { n += 1 }
            }
            running += n
            pref.append(running)
        }
        self.firstRow = pref
    }

    func columnCount(inLine line: Int) -> Int { cells }
    func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * advance }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { column > 0 && column < cells }
    func visualRowCount(inLine line: Int) -> Int { firstRow[line + 1] - firstRow[line] }
    func firstVisualRow(ofLine line: Int) -> Int { firstRow[line] }
}

/// Single-line char-wrap metrics for packing one representative line.
private struct SingleLineWrap: WrapMetricsSource {
    let cells: Int
    let advance: Double
    func columnCount(inLine line: Int) -> Int { cells }
    func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * advance }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { column > 0 && column < cells }
}

// Pure so WrapBenchmarkLineShapeTests can pin the token shape without running the
// benchmark. Latency tokens stay PREFIXED, so this line emits no corpus row.
//
// `scenario=` is new and inert today: both derive-gate-budgets.sh and GateFloorTests
// group on `mode|scenario`, and this line carried only `width=`, so node 6 would have had
// nothing to group on. `drain_p99_ns=` is new for the same reason -- no gate can be derived
// from p95 alone. Adding both here rather than at node 6 lets this slice's extract_rows()
// truth table cover the wrap_compute line shape end to end, and reduces node 6's flip to
// un-prefixing.
func formatWrapComputeLine(
    widthLabel: String,
    totalRows: Int,
    computeOperationsPerSample: Int,
    computeP95Nanoseconds: Int64,
    computeP99Nanoseconds: Int64,
    drainOperationsPerSample: Int,
    drainP95Nanoseconds: Int64,
    drainP99Nanoseconds: Int64,
    reindexNanoseconds: Int64
) -> String {
    "mode=wrap_compute scenario=width_\(widthLabel) width=\(widthLabel) total_rows=\(totalRows)"
        + " compute_operations_per_sample=\(computeOperationsPerSample)"
        + " compute_p95_ns=\(computeP95Nanoseconds)"
        + " compute_p99_ns=\(computeP99Nanoseconds)"
        + " drain_operations_per_sample=\(drainOperationsPerSample)"
        + " drain_p95_ns=\(drainP95Nanoseconds)"
        + " drain_p99_ns=\(drainP99Nanoseconds)"
        // reindex is a ONE-SHOT O(N) setup over 100 000 lines -- the width-change cost this
        // mode exists to demonstrate -- not a repeatable operation, so averaging it over
        // repetitions would destroy its meaning (spec Decision 3). The discriminator is
        // setup-vs-operation, NOT magnitude: `drain` measures in microseconds, as far above
        // tick granularity as reindex is, and is amortised anyway so node 6 promotes one
        // shape rather than two. The token is the VALUE 1 rather than absent, so the
        // exemption reads as a decision and not an oversight. Do not "consolidate" it.
        + " reindex_operations_per_sample=1"
        + " reindex_ns=\(reindexNanoseconds)"
}

@available(macOS 13.0, *)
func runWrapComputeBenchmarks() -> Bool {
    let lineCount = 100_000
    let cells = 80
    let advance = 1.0
    let rowHeight = 16.0
    let viewportHeight = 800.0
    let iterations = 2_000
    let computeOperationsPerSample = 256
    // drain walks the whole buffer per operation, so it takes the smaller count -- the
    // precedent BulkStructuralMutationBenchmark.swift:66-77 already sets for heavy scenarios.
    let drainOperationsPerSample = 16
    // deterministicScrollOffset is periodic with period 1 000 (BenchmarkSupport.swift), so
    // 1 000 pre-built ranges cover its entire image exactly. Sized independently of
    // drainOperationsPerSample -- and 1 000 is not a multiple of 16 -- so no drain sample
    // ever replays one range sixteen times.
    let drainRangeCount = 1_000
    let clock = ContinuousClock()

    // Wide (∞ -> 1 row/line) to narrow (more rows/line). Compute cost grows only as
    // O(log totalRows) across these -- viewport-bounded, NOT literally width-independent.
    let widths: [Double] = [.infinity, 40.0, 10.0]

    for width in widths {
        // The timed construction is BOUND and REUSED. It used to be discarded
        // (`_ = BenchmarkWrapLayout(...)`) with a second identical layout built for use:
        // two O(N) passes per width, and the mode's headline measurement was the one
        // carrying no dead-code guard while the far cheaper drain below did. Binding it
        // removes the second pass and makes the measured work observably live -- `layout`
        // is read on the very next line (spec Decision 3).
        let reindexStart = clock.now
        let layout = BenchmarkWrapLayout(
            lineCount: lineCount, cells: cells, advance: advance,
            rowHeight: rowHeight, wrapWidth: width)
        let reindexElapsed = reindexStart.duration(to: clock.now)

        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        let maxOffset = Double(totalRows) * rowHeight - viewportHeight

        func input(forOperation operation: Int) -> VariableViewportInput {
            VariableViewportInput(
                scrollOffsetY: deterministicScrollOffset(sample: operation, maxOffset: max(0, maxOffset)),
                viewportHeight: viewportHeight,
                overscanLinesBefore: 4,
                overscanLinesAfter: 4)
        }

        let computeMeasured = amortisedSamples(
            iterations: iterations, operationsPerSample: computeOperationsPerSample
        ) { operation in
            if case .success(let range) = ViewportVirtualizer.compute(input(forOperation: operation), layout: layout) {
                return range.bufferEndExclusive &- range.bufferStart
            }
            return 0
        }

        // Spec Decision 4: the ranges the drain body walks are built HERE, outside the clock.
        // Computing one inside the drain body would make drain_p95_ns measure compute+drain,
        // contradicting the two independent tokens this line prints and gating node 6 on the
        // wrong quantity. It is also a repair: the old shape ran compute and drain in the same
        // iteration, so every drain sample was contaminated by what the compute call before it
        // left in cache and branch predictors, while the two tokens claimed independence.
        var drainRanges: [VirtualRange] = []
        drainRanges.reserveCapacity(drainRangeCount)
        for index in 0..<drainRangeCount {
            switch ViewportVirtualizer.compute(input(forOperation: index), layout: layout) {
            case .success(let range):
                drainRanges.append(range)
            case .failure:
                preconditionFailure("wrap compute failed while pre-building the drain ranges")
            }
        }

        let drainMeasured = amortisedSamples(
            iterations: iterations, operationsPerSample: drainOperationsPerSample
        ) { operation in
            var cursor = ViewportVirtualizer.visualRowGeometry(
                for: drainRanges[operation % drainRangeCount], layout: layout)
            var sink = 0
            while let geometry = cursor.next() { sink &+= geometry.row.endColumn }
            return sink
        }

        var computeSamples = computeMeasured.samples
        var drainSamples = drainMeasured.samples
        computeSamples.sort()
        drainSamples.sort()

        // Keeps both measured bodies observably live without adding a token to a line the
        // harvester must keep ignoring -- the same guard the drain body carried before, now
        // covering compute as well.
        if computeMeasured.checksum &+ drainMeasured.checksum == Int.min { print("") }

        // No Foundation in this target: `String(format:)` is unavailable, so format the
        // (always-integral) finite widths via `Int(_:)` rather than importing Foundation.
        let widthLabel = width.isFinite ? String(Int(width)) : "inf"
        print(formatWrapComputeLine(
            widthLabel: widthLabel,
            totalRows: totalRows,
            computeOperationsPerSample: computeOperationsPerSample,
            computeP95Nanoseconds: percentile(computeSamples, numerator: 95, denominator: 100),
            computeP99Nanoseconds: percentile(computeSamples, numerator: 99, denominator: 100),
            drainOperationsPerSample: drainOperationsPerSample,
            drainP95Nanoseconds: percentile(drainSamples, numerator: 95, denominator: 100),
            drainP99Nanoseconds: percentile(drainSamples, numerator: 99, denominator: 100),
            reindexNanoseconds: nanoseconds(reindexElapsed)))
    }
    return true
}
