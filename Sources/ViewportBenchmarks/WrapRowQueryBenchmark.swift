import TextEngineCore

struct WrapRowQueryScenario {
    let name: String
    let lineCount: Int
    let wrapWidth: Double
    let clamped: Bool
}

/// Folds ALL THREE returned fields under distinct multipliers. Folding one index would
/// let a release build delete the other two and still print a plausible number --
/// `PointGeometryChecksumTests` exists because exactly that reversion once passed
/// silently. Pinned by `WrapRowQueryChecksumTests`.
func wrapRowQueryChecksum(_ location: VisualRowLocation) -> Int {
    var value = 0
    value &+= location.globalRow &* 1
    value &+= location.logicalLine &* 31
    value &+= location.rowInLine &* 131
    return value
}

// Pure so WrapBenchmarkLineShapeTests can pin the token shape without running the
// benchmark. The latency tokens stay PREFIXED (`query_p95_ns=`): the harvester requires
// the exact key `p95_ns`, so this line emits no corpus row. Node 6 flips that in the same
// slice that adds the gate step.
func formatWrapRowQueryLine(
    scenarioName: String,
    totalRows: Int,
    operationsPerSample: Int,
    p95Nanoseconds: Int64,
    p99Nanoseconds: Int64,
    checksum: Int
) -> String {
    "mode=wrap_row_query scenario=\(scenarioName) total_rows=\(totalRows)"
        + " query_operations_per_sample=\(operationsPerSample)"
        + " query_p95_ns=\(p95Nanoseconds)"
        + " query_p99_ns=\(p99Nanoseconds)"
        + " checksum=\(checksum)"
}

/// Observational only: NOT gateable, NOT wired into CI. Measured on the same amortised
/// shape as every gated mode (`amortisedSamples`): one clock read per iteration over 256
/// queries, divided. Timing a single query instead reported the host clock tick, not the
/// operation (D-23) -- the query costs a fraction of a tick, as its gated siblings' 17-94 ns
/// show.
@available(macOS 13.0, *)
func runWrapRowQueryBenchmarks() -> Bool {
    let rowHeight = 16.0
    let cells = 20
    let advance = 8.0
    let iterations = 5_000
    let operationsPerSample = 256

    let scenarios: [WrapRowQueryScenario] = [
        // ∞ width -> one row per line: the no-wrap-equivalent geometry.
        WrapRowQueryScenario(name: "uniform_1k", lineCount: 1_000, wrapWidth: .infinity, clamped: false),
        WrapRowQueryScenario(name: "uniform_100k", lineCount: 100_000, wrapWidth: .infinity, clamped: false),
        // Narrow -> totalRows >> lineCount, so the two searches differ in depth.
        WrapRowQueryScenario(name: "narrow_100k", lineCount: 100_000, wrapWidth: 40.0, clamped: false),
        // The branch Decision 7 routes through the layout search rather than short-circuiting.
        WrapRowQueryScenario(name: "clamped_100k", lineCount: 100_000, wrapWidth: 40.0, clamped: true),
    ]

    for scenario in scenarios {
        let layout = BenchmarkWrapLayout(
            lineCount: scenario.lineCount, cells: cells, advance: advance,
            rowHeight: rowHeight, wrapWidth: scenario.wrapWidth)
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        let totalHeight = Double(totalRows) * rowHeight

        // `sample` is the GLOBAL operation index, so the input sequence is exactly what the
        // single-operation loop produced -- only the clock reads changed.
        let measured = amortisedSamples(
            iterations: iterations, operationsPerSample: operationsPerSample
        ) { sample in
            let y: Double
            if scenario.clamped {
                let offset = Double(deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: 10_000))
                y = sample % 2 == 0 ? -(offset + 1.0) : totalHeight + offset
            } else {
                let row = deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: totalRows)
                y = Double(row) * rowHeight + rowHeight / 2.0
            }
            if case .row(let location) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) {
                return wrapRowQueryChecksum(location)
            }
            return 0
        }

        var querySamples = measured.samples
        querySamples.sort()
        print(formatWrapRowQueryLine(
            scenarioName: scenario.name,
            totalRows: totalRows,
            operationsPerSample: operationsPerSample,
            p95Nanoseconds: percentile(querySamples, numerator: 95, denominator: 100),
            p99Nanoseconds: percentile(querySamples, numerator: 99, denominator: 100),
            checksum: measured.checksum))
    }
    return true
}
