import TextEngineCore
import TextEngineReferenceProviders

struct ColumnGeometryQueryScenario {
    let name: String
    let providerName: String
    let columnCount: Int
    let useVariableAdvance: Bool
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// columnGeometryAt is columnAt plus a constant two O(1) columnOffset probes, so it
// stays within the --column-query headroom. Both provider families answer
// columnOffset in O(1); there is no balanced-tree/Fenwick horizontal analog. Budgets
// start from the --column-query numbers; the verification step confirms gate=pass and
// bumps with the project's customary headroom if the constant probes need it.
func columnGeometryQueryScenarios() -> [ColumnGeometryQueryScenario] {
    [
        ColumnGeometryQueryScenario(name: "uniform_1k", providerName: "uniform",
                                    columnCount: 1_000, useVariableAdvance: false,
                                    p95BudgetNanoseconds: 30_000, p99BudgetNanoseconds: 60_000),
        ColumnGeometryQueryScenario(name: "uniform_100k", providerName: "uniform",
                                    columnCount: 100_000, useVariableAdvance: false,
                                    p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        ColumnGeometryQueryScenario(name: "uniform_1m", providerName: "uniform",
                                    columnCount: 1_000_000, useVariableAdvance: false,
                                    p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        ColumnGeometryQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                                    columnCount: 100_000, useVariableAdvance: true,
                                    p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        ColumnGeometryQueryScenario(name: "prefixsum_1m", providerName: "prefixsum",
                                    columnCount: 1_000_000, useVariableAdvance: true,
                                    p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
    ]
}

@inline(never)
func runColumnGeometryQueryOperation<Metrics: LineHorizontalMetricsSource>(
    x: Double,
    inLine line: Int,
    metrics: Metrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.columnGeometryAt(x: x, inLine: line, metrics: metrics) {
    case let .geometry(location):
        var checksum = location.geometry.columnIndex
        switch location.clamp {
        case .inRange: checksum &+= 1
        case .clampedToLeft: checksum &+= 2
        case .clampedToRight: checksum &+= 3
        }
        checksum &+= Int(location.fractionInColumn * 1_000_000.0)
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runColumnGeometryQueryScenarioCore<Metrics: LineHorizontalMetricsSource>(
    _ scenario: ColumnGeometryQueryScenario,
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
            let result = runColumnGeometryQueryOperation(x: x, inLine: 0, metrics: metrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .columnGeometryQuery,
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
func runColumnGeometryQueryScenario(
    _ scenario: ColumnGeometryQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useVariableAdvance {
        let metrics = PrefixSumColumnMetrics(advancesPerLine: [variableAdvances(cellCount: scenario.columnCount)])
        return runColumnGeometryQueryScenarioCore(scenario, metrics: metrics,
                                                  iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let metrics = UniformColumnMetrics(columnsPerLine: scenario.columnCount, columnWidth: 8.0)
        return runColumnGeometryQueryScenarioCore(scenario, metrics: metrics,
                                                  iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runColumnGeometryQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in columnGeometryQueryScenarios() {
        let summary = runColumnGeometryQueryScenario(
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
