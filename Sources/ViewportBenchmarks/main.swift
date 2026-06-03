import Darwin
import TextEngineCore

enum BenchmarkMode {
    case pipeline
    case rangeOnly

    var outputName: String {
        switch self {
        case .pipeline:
            return "pipeline"
        case .rangeOnly:
            return "range_only"
        }
    }
}

enum BenchmarkOptionParse {
    case run(BenchmarkOptions)
    case help
    case failure(String)
}

struct BenchmarkOptions {
    let mode: BenchmarkMode
    let enforceGate: Bool

    static let usage = """
    Usage: ViewportBenchmarks [--range-only] [--gate] [--help]

    Options:
      --range-only   Run only viewport range recompute benchmark.
      --gate         Enforce pipeline p95/p99 budgets and exit non-zero on failure.
      --help         Print this help.
    """

    static func parse(_ arguments: [String]) -> BenchmarkOptionParse {
        var mode = BenchmarkMode.pipeline
        var enforceGate = false

        for argument in arguments {
            switch argument {
            case "--":
                continue
            case "--help":
                return .help
            case "--range-only":
                mode = .rangeOnly
            case "--gate":
                enforceGate = true
            default:
                return .failure("unknown argument \(argument)")
            }
        }

        if mode == .rangeOnly && enforceGate {
            return .failure("--range-only cannot be combined with --gate")
        }

        return .run(BenchmarkOptions(mode: mode, enforceGate: enforceGate))
    }
}

struct BenchmarkScenario {
    let name: String
    let lineCount: Int
    let lineHeight: Double
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

struct BenchmarkSummary {
    let mode: BenchmarkMode
    let scenarioName: String
    let iterations: Int
    let operationsPerSample: Int
    let p95Nanoseconds: Int64
    let p99Nanoseconds: Int64
    let checksum: Int
    let failureCount: Int
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64

    var passesGate: Bool {
        failureCount == 0
            && p95Nanoseconds <= p95BudgetNanoseconds
            && p99Nanoseconds <= p99BudgetNanoseconds
    }
}

struct BenchmarkOperationResult {
    let checksum: Int
    let failureCount: Int
}

struct SyntheticLineSource: DocumentLineSource {
    typealias Line = Int

    let lineCount: Int

    func line(at index: Int) -> DocumentLineFetch<Int> {
        if index < 0 || index >= lineCount {
            return .missing
        }

        return .found((index &* 31) &+ 7)
    }
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

func benchmarkScenarios() -> [BenchmarkScenario] {
    [
        BenchmarkScenario(
            name: "1k_lines_20_visible_overscan_0",
            lineCount: 1_000,
            lineHeight: 16.0,
            viewportHeight: 20.0 * 16.0,
            overscanBefore: 0,
            overscanAfter: 0,
            p95BudgetNanoseconds: 20_000,
            p99BudgetNanoseconds: 50_000
        ),
        BenchmarkScenario(
            name: "100k_lines_80_visible_overscan_5",
            lineCount: 100_000,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            p95BudgetNanoseconds: 50_000,
            p99BudgetNanoseconds: 100_000
        ),
        BenchmarkScenario(
            name: "1m_lines_200_visible_overscan_50",
            lineCount: 1_000_000,
            lineHeight: 16.0,
            viewportHeight: 200.0 * 16.0,
            overscanBefore: 50,
            overscanAfter: 50,
            p95BudgetNanoseconds: 100_000,
            p99BudgetNanoseconds: 200_000
        )
    ]
}

@inline(never)
func runRangeOnlyOperation(input: ViewportInput) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.compute(input) {
    case let .success(range):
        var checksum = 0
        checksum &+= range.visibleStart
        checksum &+= range.visibleEndExclusive
        checksum &+= range.bufferStart
        checksum &+= range.bufferEndExclusive
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
func runPipelineOperation(
    input: ViewportInput,
    source: SyntheticLineSource
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.compute(input) {
    case let .success(range):
        var checksum = 0
        var failureCount = 0

        checksum &+= range.visibleStart
        checksum &+= range.visibleEndExclusive
        checksum &+= range.bufferStart
        checksum &+= range.bufferEndExclusive

        var geometryCursor = ViewportVirtualizer.geometry(for: range, lineHeight: input.lineHeight)
        while let geometry = geometryCursor.next() {
            checksum &+= geometry.lineIndex
            checksum &+= Int(geometry.y)
            checksum &+= Int(geometry.height)
        }

        var lineCursor = ViewportVirtualizer.lines(for: range, in: source)
        while let element = lineCursor.next() {
            switch element {
            case let .line(line):
                checksum &+= line.index
                checksum &+= line.content
            case let .missing(index):
                checksum &-= index
                failureCount &+= 1
            }
        }

        return BenchmarkOperationResult(checksum: checksum, failureCount: failureCount)
    case .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runScenario(
    _ scenario: BenchmarkScenario,
    mode: BenchmarkMode,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let clock = ContinuousClock()
    let source = SyntheticLineSource(lineCount: scenario.lineCount)
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0
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

            let operationResult: BenchmarkOperationResult
            switch mode {
            case .pipeline:
                operationResult = runPipelineOperation(input: input, source: source)
            case .rangeOnly:
                operationResult = runRangeOnlyOperation(input: input)
            }

            checksum &+= operationResult.checksum
            failureCount &+= operationResult.failureCount
        }
        let elapsed = start.duration(to: clock.now)

        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: mode,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
        p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
        checksum: checksum,
        failureCount: failureCount,
        p95BudgetNanoseconds: scenario.p95BudgetNanoseconds,
        p99BudgetNanoseconds: scenario.p99BudgetNanoseconds
    )
}

func formatSummary(_ summary: BenchmarkSummary, includeGate: Bool) -> String {
    var output = "mode=\(summary.mode.outputName)"
    output += " scenario=\(summary.scenarioName)"
    output += " iterations=\(summary.iterations)"
    output += " operations_per_sample=\(summary.operationsPerSample)"
    output += " p95_ns=\(summary.p95Nanoseconds)"
    output += " p99_ns=\(summary.p99Nanoseconds)"
    output += " failures=\(summary.failureCount)"

    if includeGate {
        output += " budget_p95_ns=\(summary.p95BudgetNanoseconds)"
        output += " budget_p99_ns=\(summary.p99BudgetNanoseconds)"
        output += " gate=\(summary.passesGate ? "pass" : "fail")"
    }

    output += " checksum=\(summary.checksum)"
    return output
}

@available(macOS 13.0, *)
func runBenchmarks(options: BenchmarkOptions) -> Bool {
    let iterations = 10_000
    let operationsPerSample = 256
    var passed = true

    for scenario in benchmarkScenarios() {
        let summary = runScenario(
            scenario,
            mode: options.mode,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
        print(formatSummary(summary, includeGate: options.enforceGate))

        if options.enforceGate && !summary.passesGate {
            passed = false
        }
    }

    return passed
}

@available(macOS 13.0, *)
func runProgram(arguments: [String]) -> Int32 {
    switch BenchmarkOptions.parse(arguments) {
    case let .run(options):
        return runBenchmarks(options: options) ? 0 : 1
    case .help:
        print(BenchmarkOptions.usage)
        return 0
    case let .failure(message):
        print("error=\(message)")
        print(BenchmarkOptions.usage)
        return 1
    }
}

if #available(macOS 13.0, *) {
    let exitCode = runProgram(arguments: Array(CommandLine.arguments.dropFirst()))
    if exitCode != 0 {
        Darwin.exit(exitCode)
    }
} else {
    fatalError("ViewportBenchmarks requires macOS 13.0 or newer")
}
