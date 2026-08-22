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

/// Observational only: NOT gateable, NOT wired into CI. The latency tokens are
/// deliberately PREFIXED (`query_p95_ns=`), following `--wrap-compute`: the harvester
/// matches `p95_ns=` as a substring but then requires the exact key, so a prefixed line
/// emits no corpus row even if it ever reached a hosted log. Map node 6 flips this to the
/// bare shape in the same slice that adds the gate step and the corpus rows.
@available(macOS 13.0, *)
func runWrapRowQueryBenchmarks() -> Bool {
    let rowHeight = 16.0
    let cells = 20
    let advance = 8.0
    let samples = 2_000
    let clock = ContinuousClock()

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

        var querySamples: [Int64] = []
        querySamples.reserveCapacity(samples)
        var checksum = 0

        for sample in 0..<samples {
            let y: Double
            if scenario.clamped {
                let offset = Double(deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: 10_000))
                y = sample % 2 == 0 ? -(offset + 1.0) : totalHeight + offset
            } else {
                let row = deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: totalRows)
                y = Double(row) * rowHeight + rowHeight / 2.0
            }
            let elapsed = clock.measure {
                if case .row(let location) = ViewportVirtualizer.visualRowAt(y: y, layout: layout) {
                    checksum &+= wrapRowQueryChecksum(location)
                }
            }
            querySamples.append(nanoseconds(elapsed))
        }

        querySamples.sort()
        print("mode=wrap_row_query scenario=\(scenario.name) total_rows=\(totalRows)"
            + " query_p95_ns=\(percentile(querySamples, numerator: 95, denominator: 100))"
            + " query_p99_ns=\(percentile(querySamples, numerator: 99, denominator: 100))"
            + " checksum=\(checksum)")
    }
    return true
}
