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
    reindexNanoseconds: Int64,
    checksum: Int
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
        // The result-preservation witness (slice 55 spec, Decision 13): every drained
        // row's endColumn and every computed range's length, folded, over 100 000 lines
        // at this width. Deterministic under deterministicScrollOffset, so it must be
        // byte-identical across every edit on this mode's path while the timings move.
        // Not a latency key: the harvester still sees no bare p95_ns/p99_ns here.
        + " checksum=\(checksum)"
}

/// The `--wrap-compute` drain body, one operation: stream the buffer range through
/// `visualRowGeometry` and fold every row's `endColumn`. A function rather than a
/// closure so `WrapComputeDrainTests` can drive it through a counting layout and assert
/// it performs no `compute(_:layout:)` (D-29) -- witnessed by zero
/// `firstVisualRow(ofLine: lineCount)` probes, which every compute makes and the drain
/// path structurally never does. The drain ranges are built outside the clock by the
/// caller (slice 54 spec, Decision 4); computing one in here would make drain_p95_ns
/// measure compute+drain and gate node 6 on the wrong quantity.
func drainVisualRows<Layout: VisualRowLayoutSource>(_ range: VirtualRange, layout: Layout) -> Int {
    var cursor = ViewportVirtualizer.visualRowGeometry(for: range, layout: layout)
    var sink = 0
    while let geometry = cursor.next() { sink &+= geometry.row.endColumn }
    return sink
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
    // Sized so the pre-built array loses no input diversity against computing the offset
    // inline: deterministicScrollOffset (BenchmarkSupport.swift) is
    // `(sample * 37) % 1_000`, and gcd(37, 1 000) = 1, so its period is exactly 1 000 and
    // 1 000 ranges cover its whole image bijectively.
    //
    // A drain sample never replays one range either, but that follows from the INDEXING,
    // not from this count: the body indexes by the global operation index, so the 16
    // operations in one sample read 16 CONSECUTIVE indices -- distinct modulo any count
    // >= 16, whatever it is.
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
            drainVisualRows(drainRanges[operation % drainRangeCount], layout: layout)
        }

        var computeSamples = computeMeasured.samples
        var drainSamples = drainMeasured.samples
        computeSamples.sort()
        drainSamples.sort()

        // Both measured bodies stay observably live by being PRINTED (the checksum= token
        // below), which replaced the former `== Int.min` guard in slice 55a.
        let checksum = computeMeasured.checksum &+ drainMeasured.checksum

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
            reindexNanoseconds: nanoseconds(reindexElapsed),
            checksum: checksum))
    }
    return true
}
