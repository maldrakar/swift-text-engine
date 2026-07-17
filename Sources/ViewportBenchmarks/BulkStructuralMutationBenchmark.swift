import TextEngineCore
import TextEngineReferenceProviders

// Reuses variableHeights(lineCount:) and deterministicScrollOffset from
// VariableHeightBenchmark.swift / BenchmarkSupport.swift.
struct BulkStructuralMutationScenario {
    let name: String
    let lineCount: Int
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
    let batchSize: Int
    let operationsPerSample: Int
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// Budgets derived from hosted Linux x86_64 by .github/scripts/derive-gate-budgets.sh
// against docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv.
// Hosted is the calibration authority: it runs 2-3x slower than local macOS, so it
// binds. Do not hand-edit — re-derive.
func bulkStructuralMutationScenarios() -> [BulkStructuralMutationScenario] {
    [
        // Small batch (K=64): typical paste/selection.
        BulkStructuralMutationScenario(
            name: "1k_lines_batch_64",
            lineCount: 1_000,
            viewportHeight: 20.0 * 16.0,
            overscanBefore: 0,
            overscanAfter: 0,
            batchSize: 64,
            operationsPerSample: 256,
            p95BudgetNanoseconds: 50_000,
            p99BudgetNanoseconds: 100_000
        ),
        BulkStructuralMutationScenario(
            name: "100k_lines_batch_64",
            lineCount: 100_000,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            batchSize: 64,
            operationsPerSample: 256,
            p95BudgetNanoseconds: 130_000,
            p99BudgetNanoseconds: 260_000
        ),
        BulkStructuralMutationScenario(
            name: "1m_lines_batch_64",
            lineCount: 1_000_000,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50,
            batchSize: 64,
            operationsPerSample: 256,
            p95BudgetNanoseconds: 470_000,
            p99BudgetNanoseconds: 940_000
        ),
        // Large batch (K=4096): large paste / range delete.
        BulkStructuralMutationScenario(
            name: "100k_lines_batch_4096",
            lineCount: 100_000,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            batchSize: 4_096,
            operationsPerSample: 16,
            p95BudgetNanoseconds: 1_500_000,
            p99BudgetNanoseconds: 3_000_000
        ),
        BulkStructuralMutationScenario(
            name: "1m_lines_batch_4096",
            lineCount: 1_000_000,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50,
            batchSize: 4_096,
            operationsPerSample: 16,
            p95BudgetNanoseconds: 2_900_000,
            p99BudgetNanoseconds: 5_800_000
        )
    ]
}

@inline(never)
func runBulkStructuralMutationOperation(
    input: VariableViewportInput,
    metrics: BalancedTreeLineMetrics
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.compute(input, metrics: metrics) {
    case let .success(range):
        var checksum = 0
        checksum &+= range.visibleStart
        checksum &+= range.visibleEndExclusive
        checksum &+= range.bufferStart
        checksum &+= range.bufferEndExclusive

        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        while let geometry = cursor.next() {
            checksum &+= geometry.lineIndex
            checksum &+= Int(geometry.y)
            checksum &+= Int(geometry.height)
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runBulkStructuralMutationScenario(
    _ scenario: BulkStructuralMutationScenario,
    iterations: Int
) -> BenchmarkSummary {
    var metrics = BalancedTreeLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
    let initialTotal = metrics.offset(ofLine: metrics.lineCount)
    let maxOffset = initialTotal > scenario.viewportHeight ? initialTotal - scenario.viewportHeight : 0.0
    let lineCount = scenario.lineCount
    let batch = scenario.batchSize
    let insertedHeights = (0..<batch).map { Double(14 + ($0 % 4) * 6) }
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<scenario.operationsPerSample {
            let sample = iteration * scenario.operationsPerSample + operation
            let modulus = lineCount - batch + 1
            let removeIndex = deterministicIndex(sample: sample, multiplier: 2_654_435_761, modulus: modulus)
            metrics.removeLines(at: removeIndex, count: batch)
            checksum &+= metrics.lastMutationNodeVisits

            let insertIndex = deterministicIndex(sample: sample, multiplier: 40_503, modulus: modulus)
            metrics.insertLines(at: insertIndex, heights: insertedHeights)
            checksum &+= metrics.lastMutationNodeVisits

            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
            let input = VariableViewportInput(
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )
            let operationResult = runBulkStructuralMutationOperation(input: input, metrics: metrics)
            checksum &+= operationResult.checksum
            failureCount &+= operationResult.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(scenario.operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .bulkStructuralMutation,
        providerName: "balanced_tree",
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: scenario.operationsPerSample,
        lineCount: scenario.lineCount,
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
func runBulkStructuralMutationBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 2_000
    var passed = true

    for scenario in bulkStructuralMutationScenarios() {
        let summary = runBulkStructuralMutationScenario(scenario, iterations: iterations)
        print(formatSummary(summary, includeGate: enforceGate))

        if enforceGate && !summary.passesGate {
            passed = false
        } else if !enforceGate && summary.failureCount != 0 {
            passed = false
        }
    }

    return passed
}
