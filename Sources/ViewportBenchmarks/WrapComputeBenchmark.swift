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

@available(macOS 13.0, *)
func runWrapComputeBenchmarks() -> Bool {
    let lineCount = 100_000
    let cells = 80
    let advance = 1.0
    let rowHeight = 16.0
    let viewportHeight = 800.0
    let samples = 2_000
    let clock = ContinuousClock()

    // Wide (∞ -> 1 row/line) to narrow (more rows/line). Compute cost grows only as
    // O(log totalRows) across these -- viewport-bounded, NOT literally width-independent.
    let widths: [Double] = [.infinity, 40.0, 10.0]

    for width in widths {
        let reindexElapsed = clock.measure {
            _ = BenchmarkWrapLayout(lineCount: lineCount, cells: cells, advance: advance, rowHeight: rowHeight, wrapWidth: width)
        }
        let layout = BenchmarkWrapLayout(lineCount: lineCount, cells: cells, advance: advance, rowHeight: rowHeight, wrapWidth: width)
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        let maxOffset = Double(totalRows) * rowHeight - viewportHeight

        var computeSamples: [Int64] = []
        var drainSamples: [Int64] = []
        computeSamples.reserveCapacity(samples)
        drainSamples.reserveCapacity(samples)
        for s in 0..<samples {
            let scroll = deterministicScrollOffset(sample: s, maxOffset: max(0, maxOffset))
            let input = VariableViewportInput(scrollOffsetY: scroll, viewportHeight: viewportHeight, overscanLinesBefore: 4, overscanLinesAfter: 4)
            var range = VirtualRange(visibleStart: 0, visibleEndExclusive: 0, bufferStart: 0, bufferEndExclusive: 0, isAtTop: true, isAtBottom: true)
            let computeElapsed = clock.measure {
                if case .success(let r) = ViewportVirtualizer.compute(input, layout: layout) { range = r }
            }
            computeSamples.append(nanoseconds(computeElapsed))
            let drainElapsed = clock.measure {
                var cursor = ViewportVirtualizer.visualRowGeometry(for: range, layout: layout)
                var sink = 0
                while let g = cursor.next() { sink &+= g.row.endColumn }
                if sink == Int.min { print("") }   // prevent dead-code elimination
            }
            drainSamples.append(nanoseconds(drainElapsed))
        }
        computeSamples.sort()
        drainSamples.sort()
        // No Foundation in this target: `String(format:)` is unavailable, so format the
        // (always-integral) finite widths via `Int(_:)` rather than importing Foundation.
        let widthLabel = width.isFinite ? String(Int(width)) : "inf"
        print("mode=wrap_compute width=\(widthLabel) total_rows=\(totalRows)"
            + " compute_p95_ns=\(percentile(computeSamples, numerator: 95, denominator: 100))"
            + " compute_p99_ns=\(percentile(computeSamples, numerator: 99, denominator: 100))"
            + " drain_p95_ns=\(percentile(drainSamples, numerator: 95, denominator: 100))"
            + " reindex_ns=\(nanoseconds(reindexElapsed))")
    }
    return true
}
