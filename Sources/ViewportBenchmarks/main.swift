import Darwin
import TextEngineCore

enum BenchmarkMode {
    case pipeline
    case rangeOnly
    case realisticProvider

    var outputName: String {
        switch self {
        case .pipeline:
            return "pipeline"
        case .rangeOnly:
            return "range_only"
        case .realisticProvider:
            return "realistic_provider"
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
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark without gate enforcement.
      --help                Print this help.
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
                if mode == .realisticProvider {
                    return .failure("--range-only cannot be combined with --realistic-provider")
                }
                mode = .rangeOnly
            case "--gate":
                enforceGate = true
            case "--realistic-provider":
                if mode == .rangeOnly {
                    return .failure("--realistic-provider cannot be combined with --range-only")
                }
                mode = .realisticProvider
            default:
                return .failure("unknown argument \(argument)")
            }
        }

        if mode == .rangeOnly && enforceGate {
            return .failure("--range-only cannot be combined with --gate")
        }
        if mode == .realisticProvider && enforceGate {
            return .failure("--realistic-provider cannot be combined with --gate")
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

struct RealisticProviderScenario {
    let name: String
    let lineCount: Int
    let lineBytes: Int
    let lineHeight: Double
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
}

struct BenchmarkSummary {
    let mode: BenchmarkMode
    let providerName: String?
    let scenarioName: String
    let iterations: Int
    let operationsPerSample: Int
    let lineCount: Int?
    let documentBytes: Int?
    let lineBytes: Int?
    let p95Nanoseconds: Int64
    let p99Nanoseconds: Int64
    let checksum: Int
    let failureCount: Int
    let p95BudgetNanoseconds: Int64?
    let p99BudgetNanoseconds: Int64?

    var passesGate: Bool {
        guard let p95BudgetNanoseconds, let p99BudgetNanoseconds else {
            return false
        }

        return failureCount == 0
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

struct RealisticLinePayload {
    let byteOffset: Int
    let byteLength: Int
    let firstByte: Int
    let middleByte: Int
    let lastByte: Int
}

final class RealisticDocumentStorage {
    let lineCount: Int
    let lineBytes: Int
    private let bytes: [UInt8]

    var documentBytes: Int {
        bytes.count
    }

    init(lineCount: Int, lineBytes: Int) {
        precondition(lineCount > 0)
        precondition(lineBytes >= 8)

        self.lineCount = lineCount
        self.lineBytes = lineBytes
        self.bytes = RealisticDocumentStorage.makeBytes(lineCount: lineCount, lineBytes: lineBytes)
    }

    func payload(at index: Int) -> RealisticLinePayload? {
        if index < 0 || index >= lineCount {
            return nil
        }

        let byteOffset = index * lineBytes
        let middleOffset = byteOffset + lineBytes / 2
        let lastOffset = byteOffset + lineBytes - 1

        return RealisticLinePayload(
            byteOffset: byteOffset,
            byteLength: lineBytes,
            firstByte: Int(bytes[byteOffset]),
            middleByte: Int(bytes[middleOffset]),
            lastByte: Int(bytes[lastOffset])
        )
    }

    private static func makeBytes(lineCount: Int, lineBytes: Int) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(lineCount * lineBytes)

        for lineIndex in 0..<lineCount {
            for column in 0..<lineBytes {
                if column == lineBytes - 1 {
                    result.append(10)
                } else {
                    result.append(UInt8(65 + ((lineIndex &+ column) % 26)))
                }
            }
        }

        return result
    }
}

struct RealisticLineSource: DocumentLineSource {
    typealias Line = RealisticLinePayload

    let storage: RealisticDocumentStorage

    var lineCount: Int {
        storage.lineCount
    }

    func line(at index: Int) -> DocumentLineFetch<RealisticLinePayload> {
        guard let payload = storage.payload(at: index) else {
            return .missing
        }

        return .found(payload)
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

func deterministicScrollOffset(sample: Int, maxOffset: Double) -> Double {
    let fraction = Double((sample * 37) % 1_000) / 1_000.0
    return maxOffset * fraction
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

func realisticProviderScenarios() -> [RealisticProviderScenario] {
    [
        RealisticProviderScenario(
            name: "100k_lines_10mb_text",
            lineCount: 100_000,
            lineBytes: 112,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5
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
func runProviderOperation<Source: DocumentLineSource>(
    input: ViewportInput,
    source: Source,
    foldLineContent: (inout Int, Source.Line) -> Void
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
                foldLineContent(&checksum, line.content)
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
func runPipelineOperation(
    input: ViewportInput,
    source: SyntheticLineSource
) -> BenchmarkOperationResult {
    runProviderOperation(input: input, source: source) { checksum, content in
        checksum &+= content
    }
}

@inline(never)
func runRealisticProviderOperation(
    input: ViewportInput,
    source: RealisticLineSource
) -> BenchmarkOperationResult {
    runProviderOperation(input: input, source: source) { checksum, content in
        checksum &+= content.byteOffset
        checksum &+= content.byteLength
        checksum &+= content.firstByte
        checksum &+= content.middleByte
        checksum &+= content.lastByte
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
            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
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
            case .realisticProvider:
                preconditionFailure("realistic provider mode uses runRealisticProviderScenario")
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
        providerName: nil,
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

@inline(never)
@available(macOS 13.0, *)
func runRealisticProviderScenario(
    _ scenario: RealisticProviderScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let storage = RealisticDocumentStorage(lineCount: scenario.lineCount, lineBytes: scenario.lineBytes)
    let source = RealisticLineSource(storage: storage)
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0
    let documentHeight = Double(source.lineCount) * scenario.lineHeight
    let maxOffset = documentHeight > scenario.viewportHeight
        ? documentHeight - scenario.viewportHeight
        : 0.0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let offset = deterministicScrollOffset(sample: sample, maxOffset: maxOffset)
            let input = ViewportInput(
                lineCount: source.lineCount,
                lineHeight: scenario.lineHeight,
                scrollOffsetY: offset,
                viewportHeight: scenario.viewportHeight,
                overscanLinesBefore: scenario.overscanBefore,
                overscanLinesAfter: scenario.overscanAfter
            )

            let operationResult = runRealisticProviderOperation(input: input, source: source)
            checksum &+= operationResult.checksum
            failureCount &+= operationResult.failureCount
        }
        let elapsed = start.duration(to: clock.now)

        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .realisticProvider,
        providerName: "large_text",
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: source.lineCount,
        documentBytes: storage.documentBytes,
        lineBytes: scenario.lineBytes,
        p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
        p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
        checksum: checksum,
        failureCount: failureCount,
        p95BudgetNanoseconds: nil,
        p99BudgetNanoseconds: nil
    )
}

func formatSummary(_ summary: BenchmarkSummary, includeGate: Bool) -> String {
    var output = "mode=\(summary.mode.outputName)"
    if let providerName = summary.providerName {
        output += " provider=\(providerName)"
    }
    output += " scenario=\(summary.scenarioName)"
    output += " iterations=\(summary.iterations)"
    output += " operations_per_sample=\(summary.operationsPerSample)"
    if let lineCount = summary.lineCount {
        output += " line_count=\(lineCount)"
    }
    if let documentBytes = summary.documentBytes {
        output += " document_bytes=\(documentBytes)"
    }
    if let lineBytes = summary.lineBytes {
        output += " line_bytes=\(lineBytes)"
    }
    output += " p95_ns=\(summary.p95Nanoseconds)"
    output += " p99_ns=\(summary.p99Nanoseconds)"
    output += " failures=\(summary.failureCount)"

    if includeGate {
        guard let p95BudgetNanoseconds = summary.p95BudgetNanoseconds,
              let p99BudgetNanoseconds = summary.p99BudgetNanoseconds else {
            preconditionFailure("gate output requires budget values")
        }

        output += " budget_p95_ns=\(p95BudgetNanoseconds)"
        output += " budget_p99_ns=\(p99BudgetNanoseconds)"
        output += " gate=\(summary.passesGate ? "pass" : "fail")"
    }

    output += " checksum=\(summary.checksum)"
    return output
}

@available(macOS 13.0, *)
func runSyntheticBenchmarks(options: BenchmarkOptions) -> Bool {
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
func runRealisticProviderBenchmarks() -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in realisticProviderScenarios() {
        let summary = runRealisticProviderScenario(
            scenario,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
        print(formatSummary(summary, includeGate: false))

        if summary.failureCount != 0 {
            passed = false
        }
    }

    return passed
}

@available(macOS 13.0, *)
func runBenchmarks(options: BenchmarkOptions) -> Bool {
    switch options.mode {
    case .pipeline, .rangeOnly:
        return runSyntheticBenchmarks(options: options)
    case .realisticProvider:
        return runRealisticProviderBenchmarks()
    }
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
