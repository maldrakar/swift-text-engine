import TextEngineCore
import TextEngineReferenceProviders

struct LineQueryScenario {
    let name: String
    let providerName: String
    let lineCount: Int
    let useBalancedTree: Bool
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// Budgets remain the hosted Slice 28 values. Uniform uses the default O(log N)
// fallback; balanced-tree scenarios exercise the native O(log N) provider
// descent through ViewportVirtualizer.lineAt(y:metrics:).
func lineQueryScenarios() -> [LineQueryScenario] {
    [
        LineQueryScenario(name: "uniform_1k", providerName: "uniform",
                          lineCount: 1_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 30_000, p99BudgetNanoseconds: 60_000),
        LineQueryScenario(name: "uniform_100k", providerName: "uniform",
                          lineCount: 100_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 60_000, p99BudgetNanoseconds: 120_000),
        LineQueryScenario(name: "uniform_1m", providerName: "uniform",
                          lineCount: 1_000_000, useBalancedTree: false,
                          p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        LineQueryScenario(name: "balanced_tree_100k", providerName: "balanced_tree",
                          lineCount: 100_000, useBalancedTree: true,
                          p95BudgetNanoseconds: 300_000, p99BudgetNanoseconds: 600_000),
        LineQueryScenario(name: "balanced_tree_1m", providerName: "balanced_tree",
                          lineCount: 1_000_000, useBalancedTree: true,
                          p95BudgetNanoseconds: 600_000, p99BudgetNanoseconds: 1_200_000),
    ]
}

@inline(never)
func runLineQueryOperation<Metrics: LineMetricsSource>(
    y: Double,
    metrics: Metrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.lineAt(y: y, metrics: metrics) {
    case let .line(location):
        var checksum = location.lineIndex
        switch location.clamp {
        case .inRange: checksum &+= 1
        case .clampedToTop: checksum &+= 2
        case .clampedToBottom: checksum &+= 3
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runLineQueryScenarioCore<Metrics: LineMetricsSource>(
    _ scenario: LineQueryScenario,
    metrics: Metrics,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let totalHeight = metrics.offset(ofLine: metrics.lineCount)
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let y: Double
            switch sample % 8 {
            case 0:
                y = -1.0 - Double(sample % 1_000)         // below the document
            case 1:
                y = totalHeight + Double(sample % 1_000)  // past the document end
            default:
                y = deterministicScrollOffset(sample: sample, maxOffset: totalHeight)
            }
            let result = runLineQueryOperation(y: y, metrics: metrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .lineQuery,
        providerName: scenario.providerName,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: metrics.lineCount,
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
func runLineQueryScenario(
    _ scenario: LineQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useBalancedTree {
        let metrics = BalancedTreeLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
        return runLineQueryScenarioCore(scenario, metrics: metrics,
                                        iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let metrics = UniformLineMetrics(lineCount: scenario.lineCount, lineHeight: 16.0)
        return runLineQueryScenarioCore(scenario, metrics: metrics,
                                        iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runLineQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in lineQueryScenarios() {
        let summary = runLineQueryScenario(
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
