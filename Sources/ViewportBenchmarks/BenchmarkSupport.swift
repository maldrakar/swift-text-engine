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

// The division that turns one batched clock read into a per-operation cost.
//
// A FREE FUNCTION rather than an inline `/` on purpose (spec Decision 2). ContinuousClock
// cannot be substituted in a unit test, so a test can pin `amortisedSamples`' structure --
// the body runs `iterations * operationsPerSample` times, exactly `iterations` samples come
// back -- but not its arithmetic: a dropped division leaves both of those true and silently
// restores the defect this slice repairs. Pinned by exact equality in AmortisedSamplesTests.
//
// Truncating, matching every gated mode (LineQueryBenchmark.swift:89): an operation cheaper
// than one clock tick reports 0, not 1.
func amortise(elapsedNanoseconds: Int64, operationsPerSample: Int) -> Int64 {
    precondition(operationsPerSample > 0, "operationsPerSample must be > 0")
    return elapsedNanoseconds / Int64(operationsPerSample)
}

// One clock read per iteration, `operationsPerSample` operations inside it, divided by
// `amortise` -- the measurement shape every gated mode uses (LineQueryBenchmark.swift:73-89),
// extracted so it lives in exactly one place and can be tested there.
//
// It serves the WRAP modes only. The twelve gated modes deliberately keep their own loops:
// any change to them can shift their numbers, and a shift drags a budget re-derivation under
// the headroom-ceiling rule (spec Non-Goal 1). Routing this through BenchmarkSummary /
// formatSummary was rejected for the same reason -- that printer is pinned by
// WorkflowShapeTests and the checksum tests, and it would put harvestability one wrong
// default away.
//
// `body` receives the GLOBAL operation index, so deterministicScrollOffset /
// deterministicIndex carry over unchanged, and returns an Int folded into `checksum` --
// which the caller must consume, or a release build is free to delete the measured work.
// Samples come back unsorted; the caller sorts before `percentile`.
@available(macOS 13.0, *)
func amortisedSamples(
    iterations: Int,
    operationsPerSample: Int,
    body: (Int) -> Int
) -> (samples: [Int64], checksum: Int) {
    precondition(iterations > 0, "iterations must be > 0")
    precondition(operationsPerSample > 0, "operationsPerSample must be > 0")

    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            checksum &+= body(iteration * operationsPerSample + operation)
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(
            amortise(elapsedNanoseconds: nanoseconds(elapsed),
                     operationsPerSample: operationsPerSample))
    }

    return (samples, checksum)
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
        // The budgets are the only thing that can genuinely be absent here; headroom is
        // non-nil exactly when its budget is, so unwrapping it separately would guard an
        // invariant that does not exist.
        guard let p95BudgetNanoseconds = summary.p95BudgetNanoseconds,
              let p99BudgetNanoseconds = summary.p99BudgetNanoseconds,
              let headroomP95 = summary.headroomP95,
              let headroomP99 = summary.headroomP99 else {
            preconditionFailure("gate output requires budget values")
        }

        // One evaluation of the gate decision, printed twice -- so `gate=` and `reason=`
        // cannot disagree.
        let reason = summary.gateFailureReason

        output += " budget_p95_ns=\(p95BudgetNanoseconds)"
        output += " budget_p99_ns=\(p99BudgetNanoseconds)"
        output += " headroom_p95=\(formatHeadroom(headroomP95))"
        output += " headroom_p99=\(formatHeadroom(headroomP99))"
        output += " budget_absolute_p99_ns=\(summary.mode.absoluteCeiling.p99Nanoseconds)"
        output += " headroom_absolute_p99=\(formatHeadroom(summary.headroomAbsoluteP99))"
        output += " gate=\(reason == nil ? "pass" : "fail")"
        if let reason {
            output += " reason=\(reason.rawValue)"
        }
    }

    output += " checksum=\(summary.checksum)"
    return output
}
