import TextEngineCore

struct BenchmarkScenario {
    let name: String
    let lineCount: Int
    let lineHeight: Double
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
}

struct BenchmarkSummary {
    let scenarioName: String
    let operationsPerSample: Int
    let p95Nanoseconds: Int64
    let p99Nanoseconds: Int64
    let checksum: Int
}

@available(macOS 13.0, *)
func nanoseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
}

func percentile(_ sortedSamples: [Int64], numerator: Int, denominator: Int) -> Int64 {
    if sortedSamples.isEmpty {
        return 0
    }
    let index = (sortedSamples.count - 1) * numerator / denominator
    return sortedSamples[index]
}

@inline(never)
@available(macOS 13.0, *)
func runScenario(
    _ scenario: BenchmarkScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    let documentHeight = Double(scenario.lineCount) * scenario.lineHeight
    let maxOffset = documentHeight > scenario.viewportHeight
        ? documentHeight - scenario.viewportHeight
        : 0.0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let fraction = Double((sample * 37) % 1_000) / 1_000.0
            let offset = maxOffset * fraction
            let input = ViewportInput(
                lineCount: scenario.lineCount,
                lineHeight: scenario.lineHeight,
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )
            let result = ViewportVirtualizer.compute(input)

            switch result {
            case let .success(range):
                checksum &+= range.visibleStart
                checksum &+= range.visibleEndExclusive
                checksum &+= range.bufferStart
                checksum &+= range.bufferEndExclusive
            case .failure:
                checksum &-= 1
            }
        }
        let elapsed = start.duration(to: clock.now)

        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        scenarioName: scenario.name,
        operationsPerSample: operationsPerSample,
        p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
        p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
        checksum: checksum
    )
}

@available(macOS 13.0, *)
func runBenchmarks() {
    let scenarios = [
        BenchmarkScenario(
            name: "1k_lines_20_visible_overscan_0",
            lineCount: 1_000,
            lineHeight: 16.0,
            viewportHeight: 20.0 * 16.0,
            overscanBefore: 0,
            overscanAfter: 0
        ),
        BenchmarkScenario(
            name: "100k_lines_80_visible_overscan_5",
            lineCount: 100_000,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5
        ),
        BenchmarkScenario(
            name: "1m_lines_200_visible_overscan_50",
            lineCount: 1_000_000,
            lineHeight: 16.0,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50
        )
    ]

    let iterations = 10_000
    let operationsPerSample = 256

    for scenario in scenarios {
        let summary = runScenario(
            scenario,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
        print(
            "scenario=\(summary.scenarioName) iterations=\(iterations) operations_per_sample=\(summary.operationsPerSample) p95_ns=\(summary.p95Nanoseconds) p99_ns=\(summary.p99Nanoseconds) checksum=\(summary.checksum)"
        )
    }
}

if #available(macOS 13.0, *) {
    runBenchmarks()
} else {
    fatalError("ViewportBenchmarks requires macOS 13.0 or newer")
}
