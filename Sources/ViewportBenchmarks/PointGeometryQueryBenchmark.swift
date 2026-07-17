import TextEngineCore
import TextEngineReferenceProviders

struct PointGeometryQueryScenario {
    let name: String
    let providerName: String
    let lineCount: Int
    let useVariableHeights: Bool     // true -> PrefixSumLineMetrics, false -> UniformLineMetrics
    // Non-optional, like every other gated scenario table. The mode shipped with
    // `Optional` budgets while it had no hosted evidence and `--gate` was refused for it,
    // so there was nowhere to hand-type a placeholder; once the budgets were derived that
    // state stopped being representable on purpose. A scenario with no budget is not a
    // thing this table can express: derive first, then add the row.
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

private let pointGeometryColumnsPerLine = 256
private let pointGeometryColumnWidth = 8.0
private let pointGeometryLineHeight = 16.0

// Scenarios mirror --point-query one for one, deliberately: same providers, same line
// counts, same sampler, so the two modes' hosted rows are comparable line by line.
//
// What the row-to-row difference is NOT is a clean measurement of the composite's own
// overhead. This mode's timed loop also carries a heavier checksum fold than
// --point-query's (six bit-pattern folds and two index multiplies against two plain
// adds — see the fold comment below), and that work is inside the timed region. The
// fold is a handful of integer ops against a ~100 ns composite, so it does not move a
// budget; but read the delta as an UPPER BOUND on the four box probes' cost, not as
// their value.
//
// Budgets derived from hosted Linux x86_64 samples by
// .github/scripts/derive-gate-budgets.sh against the committed corpus at
// docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv. Hosted is the
// calibration authority: it runs materially slower than local macOS, so it binds.
// Never hand-edit these — re-derive.
//
// The 3x-over-worst-sample floor does NOT make a thin corpus base safe: over an
// append-only corpus it freezes a noisy sample in permanently. Re-derive as
// evidence accumulates; the verification record carries this mode's sample count
// at the time its budgets were cut.
func pointGeometryQueryScenarios() -> [PointGeometryQueryScenario] {
    [
        PointGeometryQueryScenario(name: "uniform_100k", providerName: "uniform",
                                   lineCount: 100_000, useVariableHeights: false,
                                   p95BudgetNanoseconds: 910, p99BudgetNanoseconds: 1_900),
        PointGeometryQueryScenario(name: "uniform_1m", providerName: "uniform",
                                   lineCount: 1_000_000, useVariableHeights: false,
                                   p95BudgetNanoseconds: 880, p99BudgetNanoseconds: 1_800),
        PointGeometryQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                                   lineCount: 100_000, useVariableHeights: true,
                                   p95BudgetNanoseconds: 1_100, p99BudgetNanoseconds: 2_200),
        PointGeometryQueryScenario(name: "prefixsum_1m", providerName: "prefixsum",
                                   lineCount: 1_000_000, useVariableHeights: true,
                                   p95BudgetNanoseconds: 1_300, p99BudgetNanoseconds: 2_600),
    ]
}

// The checksum must fold the GEOMETRY, not just the indices. --point-query folds
// `lineIndex + clamp + columnIndex + clamp`, which is right for a query that returns
// only indices — but here the entire payload this mode exists to measure (two boxes,
// two fractions) would be absent from the "workload unchanged" anchor the promotion
// slice leans on, and a drifted fraction would leave it byte-identical.
//
// Distinct odd multipliers per field also fix the weakness the Slice 37 review
// recorded (its P3 #5): a purely additive fold makes an axis SWAP invisible.
//
// Reproducible across runs and platforms: Swift does not enable fast-math, and
// + - * / are exactly-rounded under IEEE-754, so the bit patterns are stable.
@inline(__always)
private func fold(_ value: Double, _ multiplier: Int) -> Int {
    Int(truncatingIfNeeded: Int64(bitPattern: value.bitPattern)) &* multiplier
}

@inline(never)
func runPointGeometryQueryOperation<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
    x: Double, y: Double, lineMetrics: V, columnMetrics: H
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.pointGeometryAt(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics) {
    case let .geometry(location):
        var checksum = location.line.geometry.lineIndex &* 19
        switch location.line.clamp {
        case .inRange: checksum &+= 1
        case .clampedToTop: checksum &+= 2
        case .clampedToBottom: checksum &+= 3
        }
        checksum &+= fold(location.line.geometry.y, 3)
        checksum &+= fold(location.line.geometry.height, 5)
        checksum &+= fold(location.line.fractionInLine, 7)

        switch location.column {
        case let .cell(cell):
            checksum &+= cell.geometry.columnIndex &* 23
            switch cell.clamp {
            case .inRange: checksum &+= 10
            case .clampedToLeft: checksum &+= 20
            case .clampedToRight: checksum &+= 30
            }
            checksum &+= fold(cell.geometry.x, 11)
            checksum &+= fold(cell.geometry.width, 13)
            checksum &+= fold(cell.fractionInColumn, 17)
        case .blankLine:
            checksum &+= 7
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runPointGeometryQueryScenarioCore<V: LineMetricsSource>(
    _ scenario: PointGeometryQueryScenario,
    lineMetrics: V,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let columnMetrics = UniformColumnMetrics(columnsPerLine: pointGeometryColumnsPerLine,
                                             columnWidth: pointGeometryColumnWidth)
    let totalHeight = lineMetrics.offset(ofLine: lineMetrics.lineCount)
    let width = Double(pointGeometryColumnsPerLine) * pointGeometryColumnWidth
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    // The sampler is IDENTICAL to --point-query's, deliberately, including its known
    // correlation (Slice 37 review, P3 #2: five of every eight operations draw x and y
    // from the same deterministicScrollOffset fraction, so the workload walks a 1-D
    // diagonal). The design predicts this mode's latency against --point-query's row by
    // row, and that comparison is only valid if the workload is identical. Decorrelating
    // the axes changes BOTH modes and belongs to a slice that re-derives both budgets.
    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let y: Double
            let x: Double
            switch sample % 8 {
            case 0:
                y = -1.0 - Double(sample % 1_000)            // above the document
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            case 1:
                y = totalHeight + Double(sample % 1_000)     // past the document end
                x = width + Double(sample % 1_000)           // right of the line end
            case 2:
                y = deterministicScrollOffset(sample: sample, maxOffset: totalHeight)
                x = -1.0 - Double(sample % 1_000)            // left of the line
            default:
                y = deterministicScrollOffset(sample: sample, maxOffset: totalHeight)
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            }
            let result = runPointGeometryQueryOperation(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .pointGeometryQuery,
        providerName: scenario.providerName,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: lineMetrics.lineCount,
        documentBytes: nil,
        lineBytes: nil,
        p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
        p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
        checksum: checksum,
        failureCount: failureCount,
        p95BudgetNanoseconds: scenario.p95BudgetNanoseconds,
        p99BudgetNanoseconds: scenario.p99BudgetNanoseconds
    )
}

@available(macOS 13.0, *)
func runPointGeometryQueryScenario(
    _ scenario: PointGeometryQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useVariableHeights {
        let lineMetrics = PrefixSumLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
        return runPointGeometryQueryScenarioCore(scenario, lineMetrics: lineMetrics,
                                                 iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let lineMetrics = UniformLineMetrics(lineCount: scenario.lineCount, lineHeight: pointGeometryLineHeight)
        return runPointGeometryQueryScenarioCore(scenario, lineMetrics: lineMetrics,
                                                 iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runPointGeometryQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in pointGeometryQueryScenarios() {
        let summary = runPointGeometryQueryScenario(
            scenario,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
        print(formatSummary(summary, includeGate: enforceGate))

        // Budget-blind is not failure-blind: without --gate this still reddens on a
        // scenario that starts returning .empty/.failure.
        if enforceGate && !summary.passesGate {
            passed = false
        } else if !enforceGate && summary.failureCount != 0 {
            passed = false
        }
    }

    return passed
}
