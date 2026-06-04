# Realistic Provider Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `ViewportBenchmarks` with an opt-in realistic large-text provider benchmark while preserving the existing synthetic pipeline gate.

**Architecture:** Keep `TextEngineCore` unchanged and keep all realistic storage/provider code inside the existing `ViewportBenchmarks` executable target. Add `--realistic-provider` as a separate benchmark mode that builds a deterministic 100,000-line UTF-8 fixture before timing, traverses the current fixed-height pipeline over a lightweight provider handle, and reports provider/document shape fields without enforcing gate budgets.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, Swift standard library, `TextEngineCore`, `Darwin.exit`, `ContinuousClock`.

---

## Scope Check

This plan implements the approved Slice 4 spec:

- `docs/superpowers/specs/2026-06-04-realistic-provider-benchmark-design.md`

This plan covers one subsystem: the existing `ViewportBenchmarks` executable plus a verification record. It does not add CI wiring, production storage adapters, `TextEngineCore` API, allocation profiling, baseline comparison, variable-height layout, or tests with latency assertions.

## File Structure

- Modify `Sources/ViewportBenchmarks/main.swift`: add `realisticProvider` CLI mode, realistic provider scenario metadata, reference-backed UTF-8 fixture storage, lightweight line source, realistic payload folding, mode-specific benchmark dispatch, output fields, and invalid CLI combinations.
- Create `docs/superpowers/verification/2026-06-04-realistic-provider-benchmark.md`: record host tests, release build, benchmark outputs, invalid CLI outputs, and cross-target `TextEngineCore` compile verification.
- Leave `Package.swift` unchanged: the existing executable target is sufficient.
- Leave `Sources/TextEngineCore/*.swift` unchanged: Slice 4 must not move storage fixtures into the core.
- Leave `Tests/TextEngineCoreTests/*.swift` unchanged unless implementation uncovers a real core compatibility issue.

## Task 1: Establish Missing CLI Behavior

**Files:**
- Read: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Run the realistic provider command before implementation**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Expected before implementation:

```text
error=unknown argument --realistic-provider
```

The command exits non-zero. SwiftPM build lines may appear before the `error=` line.

- [ ] **Step 2: Run the realistic provider gate combination before implementation**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected before implementation:

```text
error=unknown argument --realistic-provider
```

The command exits non-zero. This proves Slice 4 needs explicit CLI handling for `--realistic-provider` and for the invalid gate combination.

## Task 2: Add Realistic Provider Benchmark Mode

**Files:**
- Modify: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Replace `Sources/ViewportBenchmarks/main.swift` with the full Slice 4 implementation**

Replace the entire file with:

```swift
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
                if mode != .pipeline {
                    return .failure("--range-only cannot be combined with --realistic-provider")
                }
                mode = .rangeOnly
            case "--gate":
                enforceGate = true
            case "--realistic-provider":
                if mode != .pipeline {
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
func runRealisticProviderOperation(
    input: ViewportInput,
    source: RealisticLineSource
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
                checksum &+= line.content.byteOffset
                checksum &+= line.content.byteLength
                checksum &+= line.content.firstByte
                checksum &+= line.content.middleByte
                checksum &+= line.content.lastByte
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
            let fraction = Double((sample * 37) % 1_000) / 1_000.0
            let offset = maxOffset * fraction
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
        p95BudgetNanoseconds: 0,
        p99BudgetNanoseconds: 0
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
        output += " budget_p95_ns=\(summary.p95BudgetNanoseconds)"
        output += " budget_p99_ns=\(summary.p99BudgetNanoseconds)"
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
```

- [ ] **Step 2: Build the release executable**

Run:

```bash
swift build -c release
```

Expected: command exits `0`. macOS deployment-target linker warnings are acceptable if they match the existing Slice 3 warning pattern.

- [ ] **Step 3: Verify help output includes the new flag**

Run:

```bash
swift run -c release ViewportBenchmarks -- --help
```

Expected output contains:

```text
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--help]
```

Expected output also contains:

```text
--realistic-provider  Run large-text provider benchmark without gate enforcement.
```

- [ ] **Step 4: Verify the realistic provider gate combination is rejected**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected: command exits non-zero and output contains:

```text
error=--realistic-provider cannot be combined with --gate
```

- [ ] **Step 5: Commit the executable implementation**

Run:

```bash
git add Sources/ViewportBenchmarks/main.swift
git commit -m "perf: add realistic provider benchmark mode"
```

Expected: commit succeeds.

## Task 3: Verify Benchmark Modes

**Files:**
- Read: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Run host tests**

Run:

```bash
swift test
```

Expected: command exits `0`; all `TextEngineCoreTests` pass.

- [ ] **Step 2: Run the default synthetic pipeline benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks
```

Expected: command exits `0` and prints three lines beginning with:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0
mode=pipeline scenario=100k_lines_80_visible_overscan_5
mode=pipeline scenario=1m_lines_200_visible_overscan_50
```

Each line includes `iterations=`, `operations_per_sample=`, `p95_ns=`, `p99_ns=`, `failures=0`, and `checksum=`.

- [ ] **Step 3: Run the range-only diagnostic benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks -- --range-only
```

Expected: command exits `0` and prints three lines beginning with:

```text
mode=range_only scenario=1k_lines_20_visible_overscan_0
mode=range_only scenario=100k_lines_80_visible_overscan_5
mode=range_only scenario=1m_lines_200_visible_overscan_50
```

Each line includes `failures=0` and `checksum=`.

- [ ] **Step 4: Run the synthetic gate**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: command exits `0`. Every output line includes `gate=pass`, `budget_p95_ns=`, `budget_p99_ns=`, and `failures=0`.

- [ ] **Step 5: Run the realistic provider benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Expected: command exits `0` and prints one benchmark line beginning with:

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text
```

The line includes:

```text
iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112
```

The line also includes `p95_ns=`, `p99_ns=`, `failures=0`, and `checksum=`.

- [ ] **Step 6: Verify the realistic provider gate combination remains invalid**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected: command exits non-zero and output contains:

```text
error=--realistic-provider cannot be combined with --gate
```

- [ ] **Step 7: Verify the existing invalid range-only gate behavior**

Run:

```bash
swift run -c release ViewportBenchmarks -- --range-only --gate
```

Expected: command exits non-zero and output contains:

```text
error=--range-only cannot be combined with --gate
```

- [ ] **Step 8: Verify unknown flags are still rejected**

Run:

```bash
swift run -c release ViewportBenchmarks -- --json
```

Expected: command exits non-zero and output contains:

```text
error=unknown argument --json
```

## Task 4: Cross-Target Core Verification

**Files:**
- Read: `Sources/TextEngineCore/ViewportTypes.swift`
- Read: `Sources/TextEngineCore/ViewportVirtualizer.swift`
- Read: `Sources/TextEngineCore/LineGeometryCursor.swift`
- Read: `Sources/TextEngineCore/DocumentLineTypes.swift`
- Read: `Sources/TextEngineCore/DocumentLineCursor.swift`

- [ ] **Step 1: Verify WASM core target**

Run:

```bash
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
```

Expected: command exits `0`.

- [ ] **Step 2: Verify embedded WASM core target**

Run:

```bash
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
```

Expected: command exits `0`.

- [ ] **Step 3: Verify iOS device core module compile**

Run:

```bash
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
```

Expected: command exits `0`.

- [ ] **Step 4: Verify iOS simulator core module compile**

Run:

```bash
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

Expected: command exits `0`.

## Task 5: Record Slice Verification

**Files:**
- Create: `docs/superpowers/verification/2026-06-04-realistic-provider-benchmark.md`

- [ ] **Step 1: Create the verification record**

Create `docs/superpowers/verification/2026-06-04-realistic-provider-benchmark.md` after running the commands in Tasks 3 and 4. Use the structure below, and put the exact local output for each named command in that section's fenced `text` block. Do not summarize or invent latency values.

````markdown
# Realistic Provider Benchmark Verification

Date: 2026-06-04

Swift: Apple Swift version 6.2.1 (swift-6.2.1-RELEASE)

## Commands

- `swift test`: pass
- `swift build -c release`: pass
- `swift run -c release ViewportBenchmarks`: pass
- `swift run -c release ViewportBenchmarks -- --range-only`: pass
- `swift run -c release ViewportBenchmarks -- --gate`: pass
- `swift run -c release ViewportBenchmarks -- --realistic-provider`: pass
- `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`: expected non-zero exit
- `swift run -c release ViewportBenchmarks -- --range-only --gate`: expected non-zero exit
- `swift run -c release ViewportBenchmarks -- --json`: expected non-zero exit
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`: pass
- `xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule`: pass
- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule`: pass

## Default Pipeline Benchmark Output

`swift run -c release ViewportBenchmarks`:

Add one fenced `text` block containing the exact output from Task 3 Step 2.

## Range-Only Benchmark Output

`swift run -c release ViewportBenchmarks -- --range-only`:

Add one fenced `text` block containing the exact output from Task 3 Step 3.

## Gate Output

`swift run -c release ViewportBenchmarks -- --gate`:

Add one fenced `text` block containing the exact output from Task 3 Step 4.

## Realistic Provider Benchmark Output

`swift run -c release ViewportBenchmarks -- --realistic-provider`:

Add one fenced `text` block containing the exact output from Task 3 Step 5.

## Invalid CLI Output

`swift run -c release ViewportBenchmarks -- --realistic-provider --gate` exited 1:

Add one fenced `text` block containing the exact output from Task 3 Step 6.

`swift run -c release ViewportBenchmarks -- --range-only --gate` exited 1:

Add one fenced `text` block containing the exact output from Task 3 Step 7.

`swift run -c release ViewportBenchmarks -- --json` exited 1:

Add one fenced `text` block containing the exact output from Task 3 Step 8.

## Target Verification

- Host SwiftPM build and tests: verified.
- Existing synthetic pipeline benchmark gate: verified by `--gate` returning `0` with all scenarios under budget.
- Realistic provider benchmark: verified by `--realistic-provider` returning `0`, reporting `line_count=100000`, `document_bytes=11200000`, `line_bytes=112`, and `failures=0`.
- Invalid benchmark CLI behavior: verified by non-zero exits for invalid combinations and unknown flags.
- iOS device source compatibility: verified by direct `xcrun swiftc` module compile.
- iOS simulator source compatibility: verified by direct `xcrun swiftc` module compile.
- WASM source compatibility: verified for the `TextEngineCore` target.
- Embedded WASM source compatibility: verified for the `TextEngineCore` target.

## Benchmark Scope

The realistic provider benchmark builds a deterministic 100,000-line, 11,200,000-byte UTF-8 fixture before timed samples begin. Each timed operation computes the fixed-height viewport range, traverses buffered geometry, and traverses buffered provider lines through `DocumentLineCursor`.

The provider source stored in `DocumentLineCursor` is a lightweight handle containing one reference to `RealisticDocumentStorage`; the large byte payload remains outside `TextEngineCore`.

No realistic-provider p95/p99 budget is enforced in this slice. The recorded output is a baseline for later CI calibration or memory/allocation work.
````

- [ ] **Step 2: Verify the verification record has no instruction text**

Run this check after writing the command output blocks:

Run:

```bash
rg -n "Add one fenced|Do not summarize|Task 3 Step" docs/superpowers/verification/2026-06-04-realistic-provider-benchmark.md
```

Expected: command exits `1` with no matches.

- [ ] **Step 3: Verify the realistic provider fields are recorded**

Run:

```bash
rg -n "mode=realistic_provider|line_count=100000|document_bytes=11200000|line_bytes=112|failures=0" docs/superpowers/verification/2026-06-04-realistic-provider-benchmark.md
```

Expected: output includes matches for all five field patterns in the realistic provider benchmark section.

- [ ] **Step 4: Commit the verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-04-realistic-provider-benchmark.md
git commit -m "docs: record realistic provider benchmark verification"
```

Expected: commit succeeds.

## Task 6: Final Review

**Files:**
- Read: `docs/superpowers/specs/2026-06-04-realistic-provider-benchmark-design.md`
- Read: `Sources/ViewportBenchmarks/main.swift`
- Read: `docs/superpowers/verification/2026-06-04-realistic-provider-benchmark.md`

- [ ] **Step 1: Confirm `TextEngineCore` was not changed**

Run:

```bash
git diff HEAD~2..HEAD -- Sources/TextEngineCore Tests/TextEngineCoreTests Package.swift
```

Expected: no diff output.

- [ ] **Step 2: Confirm the new benchmark mode is executable-only**

Run:

```bash
rg -n "RealisticDocumentStorage|RealisticLineSource|realisticProvider|realistic_provider" Sources
```

Expected: every match is in `Sources/ViewportBenchmarks/main.swift`.

- [ ] **Step 3: Confirm no realistic provider gate was added**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected: command exits non-zero and output contains:

```text
error=--realistic-provider cannot be combined with --gate
```

- [ ] **Step 4: Confirm final status**

Run:

```bash
git status --short
```

Expected: no modified tracked files from this slice. An unrelated untracked `docs/superpowers/reviews/2026-06-04-slice-3-post-slice-review.md` may still be present and must not be reverted or committed unless the user asks.
