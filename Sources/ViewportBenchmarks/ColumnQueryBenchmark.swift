import TextEngineCore
import TextEngineReferenceProviders

struct ColumnQueryScenario {
    let name: String
    let providerName: String
    let columnCount: Int
    let useVariableAdvance: Bool
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// Budgets derived from hosted Linux x86_64 by .github/scripts/derive-gate-budgets.sh
// against docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv.
// Hosted is the calibration authority: it runs 2-3x slower than local macOS, so it
// binds. Do not hand-edit — re-derive.
//
// Large cell counts exist only to exercise binary-search depth (real lines are
// short). uniform_* use UniformColumnMetrics (core); prefixsum_* use
// PrefixSumColumnMetrics (reference providers) — the realistic proportional case.
// Both answer columnOffset in O(1), so the generic search is O(log M) wall-clock.
func columnQueryScenarios() -> [ColumnQueryScenario] {
    [
        ColumnQueryScenario(name: "uniform_1k", providerName: "uniform",
                            columnCount: 1_000, useVariableAdvance: false,
                            p95BudgetNanoseconds: 200, p99BudgetNanoseconds: 400),
        ColumnQueryScenario(name: "uniform_100k", providerName: "uniform",
                            columnCount: 100_000, useVariableAdvance: false,
                            p95BudgetNanoseconds: 280, p99BudgetNanoseconds: 560),
        ColumnQueryScenario(name: "uniform_1m", providerName: "uniform",
                            columnCount: 1_000_000, useVariableAdvance: false,
                            p95BudgetNanoseconds: 320, p99BudgetNanoseconds: 640),
        ColumnQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                            columnCount: 100_000, useVariableAdvance: true,
                            p95BudgetNanoseconds: 470, p99BudgetNanoseconds: 940),
        ColumnQueryScenario(name: "prefixsum_1m", providerName: "prefixsum",
                            columnCount: 1_000_000, useVariableAdvance: true,
                            p95BudgetNanoseconds: 580, p99BudgetNanoseconds: 1_200),
    ]
}

// Deterministic positive per-cell advances (mirror of variableHeights).
func variableAdvances(cellCount: Int) -> [Double] {
    var advances: [Double] = []
    advances.reserveCapacity(cellCount)
    for index in 0..<cellCount {
        let bucket = ((index &* 31) &+ 7) % 4
        switch bucket {
        case 0: advances.append(6.0)
        case 1: advances.append(8.0)
        case 2: advances.append(10.0)
        default: advances.append(14.0)
        }
    }
    return advances
}

@inline(never)
func runColumnQueryOperation<Metrics: LineHorizontalMetricsSource>(
    x: Double,
    inLine line: Int,
    metrics: Metrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.columnAt(x: x, inLine: line, metrics: metrics) {
    case let .column(location):
        var checksum = location.columnIndex
        switch location.clamp {
        case .inRange: checksum &+= 1
        case .clampedToLeft: checksum &+= 2
        case .clampedToRight: checksum &+= 3
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runColumnQueryScenarioCore<Metrics: LineHorizontalMetricsSource>(
    _ scenario: ColumnQueryScenario,
    metrics: Metrics,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let width = metrics.columnOffset(inLine: 0, column: scenario.columnCount)
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let x: Double
            switch sample % 8 {
            case 0:
                x = -1.0 - Double(sample % 1_000)      // left of the line
            case 1:
                x = width + Double(sample % 1_000)     // right of the line end
            default:
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            }
            let result = runColumnQueryOperation(x: x, inLine: 0, metrics: metrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .columnQuery,
        providerName: scenario.providerName,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: nil,
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
func runColumnQueryScenario(
    _ scenario: ColumnQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useVariableAdvance {
        let metrics = PrefixSumColumnMetrics(advancesPerLine: [variableAdvances(cellCount: scenario.columnCount)])
        return runColumnQueryScenarioCore(scenario, metrics: metrics,
                                          iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let metrics = UniformColumnMetrics(columnsPerLine: scenario.columnCount, columnWidth: 8.0)
        return runColumnQueryScenarioCore(scenario, metrics: metrics,
                                          iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runColumnQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in columnQueryScenarios() {
        let summary = runColumnQueryScenario(
            scenario,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
        print(formatSummary(summary, includeGate: enforceGate))

        if enforceGate && !summary.passesGate {
            passed = false
        } else if !enforceGate && summary.failureCount != 0 {
            passed = false
        }
    }

    return passed
}
