import TextEngineCore

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

// Budgets derived from hosted Linux x86_64 by .github/scripts/derive-gate-budgets.sh
// against docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv.
// Hosted is the calibration authority: it runs 2-3x slower than local macOS, so it
// binds. Do not hand-edit — re-derive.
//
// This mode's samples reach the corpus by a different route than every other gate's.
// It is the one gated mode CI never runs with --gate: the PR-only observation step runs
// it bare and keeps the raw benchmark output in a temp file, so no `p95_ns=` line for
// this mode ever reaches the hosted log. Its per-repetition values ride inside the
// `mode=realistic_relative_observation` line instead, and
// .github/scripts/harvest-gate-corpus.sh reads them from there. That is why this mode
// was missing from the first corpus, and why its budget was the last one in the suite
// still sitting under the 3x floor after everything else had been re-derived.
func realisticProviderScenarios() -> [RealisticProviderScenario] {
    [
        RealisticProviderScenario(
            name: "100k_lines_10mb_text",
            lineCount: 100_000,
            lineBytes: 112,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5,
            p95BudgetNanoseconds: 98_000,
            p99BudgetNanoseconds: 200_000
        )
    ]
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
        p95BudgetNanoseconds: scenario.p95BudgetNanoseconds,
        p99BudgetNanoseconds: scenario.p99BudgetNanoseconds
    )
}

@available(macOS 13.0, *)
func runRealisticProviderBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in realisticProviderScenarios() {
        let summary = runRealisticProviderScenario(
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
