import TextEngineCore
import TextEngineReferenceProviders

// Reuses VariableHeightScenario, variableHeights(lineCount:), and
// deterministicScrollOffset from VariableHeightBenchmark.swift / BenchmarkSupport.swift.
func structuralMutationScenarios() -> [VariableHeightScenario] {
    [
        VariableHeightScenario(
            name: "1k_lines_20_visible_overscan_0",
            lineCount: 1_000,
            viewportHeight: 20.0 * 16.0,
            overscanBefore: 0,
            overscanAfter: 0,
            p95BudgetNanoseconds: 20_000,
            p99BudgetNanoseconds: 40_000
        ),
        VariableHeightScenario(
            name: "100k_lines_80_visible_overscan_5",
            lineCount: 100_000,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            p95BudgetNanoseconds: 80_000,
            p99BudgetNanoseconds: 120_000
        ),
        VariableHeightScenario(
            name: "1m_lines_200_visible_overscan_50",
            lineCount: 1_000_000,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50,
            p95BudgetNanoseconds: 250_000,
            p99BudgetNanoseconds: 400_000
        )
    ]
}

@inline(never)
func runStructuralMutationOperation(
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
func runStructuralMutationScenario(
    _ scenario: VariableHeightScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    // One provider, mutated in place across all operations (no per-op rebuild of
    // any structure; the PrefixSum oracle never appears in the hot path).
    var metrics = BalancedTreeLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
    let initialTotal = metrics.offset(ofLine: metrics.lineCount)
    let maxOffset = initialTotal > scenario.viewportHeight ? initialTotal - scenario.viewportHeight : 0.0
    let lineCount = scenario.lineCount
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            // Pin lineCount constant: remove one line, insert one elsewhere, both
            // at deterministic positions spread across the document. After the
            // remove the count is lineCount - 1, so insert index domain is
            // 0...(lineCount - 1); % lineCount stays within it.
            let removeIndex = (sample &* 2_654_435_761) % lineCount
            metrics.removeLine(at: removeIndex)
            checksum &+= metrics.lastMutationNodeVisits

            let insertIndex = (sample &* 40_503) % lineCount
            let newHeight = ((sample & 1) == 0) ? 18.0 : 30.0
            metrics.insertLine(at: insertIndex, height: newHeight)
            checksum &+= metrics.lastMutationNodeVisits

            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
            let input = VariableViewportInput(
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )
            let operationResult = runStructuralMutationOperation(input: input, metrics: metrics)
            checksum &+= operationResult.checksum
            failureCount &+= operationResult.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .structuralMutation,
        providerName: "balanced_tree",
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
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
func runStructuralMutationBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in structuralMutationScenarios() {
        let summary = runStructuralMutationScenario(
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
