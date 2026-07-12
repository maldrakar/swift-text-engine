import TextEngineCore

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

// Deterministic, always-non-negative index in 0..<modulus. Mixing is done in
// UInt so the wrapping multiply can never produce a negative dividend that
// Swift's signed `%` would carry into a negative index (which would trip an
// `index >= 0` precondition and crash a benchmark gate). `modulus` must be > 0.
func deterministicIndex(sample: Int, multiplier: UInt, modulus: Int) -> Int {
    Int(UInt(bitPattern: sample) &* multiplier % UInt(modulus))
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

// One decimal place, without Foundation: `String(format:)` would drag Foundation
// into a target that has none, and the benchmark target must stay free of it.
// Returns the complete field value, `x` suffix included, so the unbounded case
// reads `inf` rather than `infx`.
func formatHeadroom(_ headroom: Double) -> String {
    if !headroom.isFinite {
        return "inf"
    }
    let tenths = Int64((headroom * 10.0).rounded())
    return "\(tenths / 10).\(tenths % 10)x"
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
              let p99BudgetNanoseconds = summary.p99BudgetNanoseconds,
              let headroomP95 = summary.headroomP95,
              let headroomP99 = summary.headroomP99 else {
            preconditionFailure("gate output requires budget values")
        }

        output += " budget_p95_ns=\(p95BudgetNanoseconds)"
        output += " budget_p99_ns=\(p99BudgetNanoseconds)"
        output += " headroom_p95=\(formatHeadroom(headroomP95))"
        output += " headroom_p99=\(formatHeadroom(headroomP99))"
        output += " gate=\(summary.passesGate ? "pass" : "fail")"
        if let reason = summary.gateFailureReason {
            output += " reason=\(reason.rawValue)"
        }
    }

    output += " checksum=\(summary.checksum)"
    return output
}
