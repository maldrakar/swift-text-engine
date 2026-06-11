import TextEngineCore

struct PrefixSumLineMetrics: LineMetricsSource {
    let prefix: [Double]

    init(heights: [Double]) {
        var sums: [Double] = [0.0]
        sums.reserveCapacity(heights.count + 1)
        var running = 0.0
        for height in heights {
            running += height
            sums.append(running)
        }
        self.prefix = sums
    }

    var lineCount: Int { prefix.count - 1 }

    func offset(ofLine index: Int) -> Double { prefix[index] }
}

struct VariableHeightScenario {
    let name: String
    let lineCount: Int
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

func variableHeightScenarios() -> [VariableHeightScenario] {
    [
        VariableHeightScenario(
            name: "1k_lines_20_visible_overscan_0",
            lineCount: 1_000,
            viewportHeight: 20.0 * 16.0,
            overscanBefore: 0,
            overscanAfter: 0,
            p95BudgetNanoseconds: 50_000,
            p99BudgetNanoseconds: 100_000
        ),
        VariableHeightScenario(
            name: "100k_lines_80_visible_overscan_5",
            lineCount: 100_000,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            p95BudgetNanoseconds: 100_000,
            p99BudgetNanoseconds: 200_000
        ),
        VariableHeightScenario(
            name: "1m_lines_200_visible_overscan_50",
            lineCount: 1_000_000,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50,
            p95BudgetNanoseconds: 250_000,
            p99BudgetNanoseconds: 500_000
        )
    ]
}

// Deterministic, strictly-positive, non-uniform heights in {14, 16, 20, 32}.
func variableHeights(lineCount: Int) -> [Double] {
    var heights: [Double] = []
    heights.reserveCapacity(lineCount)
    for index in 0..<lineCount {
        let bucket = ((index &* 31) &+ 7) % 4
        switch bucket {
        case 0:
            heights.append(14.0)
        case 1:
            heights.append(16.0)
        case 2:
            heights.append(20.0)
        default:
            heights.append(32.0)
        }
    }
    return heights
}

@inline(never)
func runVariableHeightOperation(
    input: VariableViewportInput,
    metrics: PrefixSumLineMetrics
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
func runVariableHeightScenario(
    _ scenario: VariableHeightScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let metrics = PrefixSumLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
    let totalHeight = metrics.offset(ofLine: metrics.lineCount)
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0
    let maxOffset = totalHeight > scenario.viewportHeight ? totalHeight - scenario.viewportHeight : 0.0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
            let input = VariableViewportInput(
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )

            let operationResult = runVariableHeightOperation(input: input, metrics: metrics)
            checksum &+= operationResult.checksum
            failureCount &+= operationResult.failureCount
        }
        let elapsed = start.duration(to: clock.now)

        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .variableHeight,
        providerName: "prefix_sum",
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
func runVariableHeightBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in variableHeightScenarios() {
        let summary = runVariableHeightScenario(
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
