# Headless Pipeline Benchmark And Regression Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `ViewportBenchmarks` so it measures the full headless pipeline by default and fails `--gate` runs when conservative absolute latency budgets are exceeded.

**Architecture:** Keep `TextEngineCore` unchanged and keep benchmark support code inside the existing `ViewportBenchmarks` executable target. The executable parses a small CLI, runs either pipeline or range-only mode, formats key-value output, and returns non-zero only for invalid CLI usage or failed gate budgets. The pipeline path uses existing public core APIs: viewport range computation, buffered geometry cursor traversal, and buffered provider cursor traversal over a synthetic source.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, Swift standard library, `Darwin.exit` for benchmark executable exit codes, `ContinuousClock` for release benchmark timing.

---

## Scope Check

This plan implements the approved Slice 3 spec:

- `docs/superpowers/specs/2026-06-01-headless-pipeline-benchmark-regression-gate-design.md`

This plan covers one subsystem: the existing `ViewportBenchmarks` executable plus the slice verification document. It does not add CI wiring, a baseline file, real storage adapters, allocation profiling, variable-height layout, or new `TextEngineCore` public API.

## File Structure

- Modify `Sources/ViewportBenchmarks/main.swift`: add CLI parsing, benchmark modes, synthetic provider fixture, pipeline traversal, range-only diagnostic mode, gate budgets, key-value output, and process exit behavior.
- Create `docs/superpowers/verification/2026-06-03-headless-pipeline-benchmark-regression-gate.md`: record host tests, release build, benchmark output, gate output, invalid CLI result, and cross-target `TextEngineCore` compile verification.
- Leave `Package.swift` unchanged: the existing executable target is sufficient.
- Leave `Sources/TextEngineCore/*.swift` unchanged unless compilation exposes an unexpected compatibility issue.
- Leave `Tests/TextEngineCoreTests/*.swift` unchanged: latency behavior is verified through release executable runs rather than debug XCTest assertions.

## Task 1: Pipeline Benchmark CLI And Gate

**Files:**
- Modify: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Run commands that show the new CLI behavior is missing**

Run:

```bash
swift run -c release ViewportBenchmarks -- --help
swift run -c release ViewportBenchmarks -- --range-only --gate
```

Expected before implementation:

- `--help` still runs the old benchmark instead of printing usage.
- `--range-only --gate` exits successfully instead of rejecting the invalid combination.
- Benchmark output has no `mode=`, `budget_p95_ns=`, `budget_p99_ns=`, or `gate=` fields.

- [ ] **Step 2: Replace `Sources/ViewportBenchmarks/main.swift` with the full implementation**

Replace the file content with:

```swift
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
```

- [ ] **Step 3: Build the executable**

Run:

```bash
swift build -c release
```

Expected: PASS. `TextEngineCore` and `ViewportBenchmarks` build successfully.

- [ ] **Step 4: Verify the default benchmark is pipeline mode**

Run:

```bash
swift run -c release ViewportBenchmarks
```

Expected: PASS. Output has three scenario lines and each line starts with `mode=pipeline`. Each line includes `iterations=10000`, `operations_per_sample=256`, `p95_ns=`, `p99_ns=`, `failures=0`, and `checksum=`.

- [ ] **Step 5: Verify the range-only diagnostic mode**

Run:

```bash
swift run -c release ViewportBenchmarks -- --range-only
```

Expected: PASS. Output has three scenario lines and each line starts with `mode=range_only`. The output does not include `budget_p95_ns=`, `budget_p99_ns=`, or `gate=`.

- [ ] **Step 6: Verify the gate mode**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: PASS. Output has three scenario lines and each line starts with `mode=pipeline`. Each line includes `budget_p95_ns=`, `budget_p99_ns=`, `gate=pass`, `failures=0`, and `checksum=`.

- [ ] **Step 7: Verify help output**

Run:

```bash
swift run -c release ViewportBenchmarks -- --help
```

Expected: PASS. Output includes:

```text
Usage: ViewportBenchmarks [--range-only] [--gate] [--help]
```

- [ ] **Step 8: Verify invalid mode plus gate is rejected**

Run:

```bash
swift run -c release ViewportBenchmarks -- --range-only --gate
```

Expected: FAIL with non-zero exit. Output includes:

```text
error=--range-only cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--help]
```

- [ ] **Step 9: Verify unknown arguments are rejected**

Run:

```bash
swift run -c release ViewportBenchmarks -- --json
```

Expected: FAIL with non-zero exit. Output includes:

```text
error=unknown argument --json
Usage: ViewportBenchmarks [--range-only] [--gate] [--help]
```

- [ ] **Step 10: Run the full test suite**

Run:

```bash
swift test
```

Expected: PASS. Existing `TextEngineCoreTests` still pass because this task does not modify core APIs.

- [ ] **Step 11: Commit**

Run:

```bash
git add Sources/ViewportBenchmarks/main.swift
git commit -m "feat: add headless pipeline benchmark gate"
```

Expected: commit succeeds.

## Task 2: Slice Verification Record

**Files:**
- Create: `docs/superpowers/verification/2026-06-03-headless-pipeline-benchmark-regression-gate.md`

- [ ] **Step 1: Run host verification commands**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --help
```

Expected:

- `swift test`: PASS.
- `swift build -c release`: PASS.
- default benchmark: PASS with three `mode=pipeline` lines.
- range-only benchmark: PASS with three `mode=range_only` lines.
- gate: PASS with three `gate=pass` lines.
- help: PASS with usage output.

- [ ] **Step 2: Run invalid CLI verification commands**

Run:

```bash
swift run -c release ViewportBenchmarks -- --range-only --gate
swift run -c release ViewportBenchmarks -- --json
```

Expected:

- Both commands exit non-zero.
- The first output includes `error=--range-only cannot be combined with --gate`.
- The second output includes `error=unknown argument --json`.

- [ ] **Step 3: Run WASM core compile verification**

Run:

```bash
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
```

Expected: both commands PASS. These commands compile only the `TextEngineCore` target; they do not require `ViewportBenchmarks` to compile under WASM.

- [ ] **Step 4: Run iOS core module compile verification**

Run:

```bash
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

Expected: both commands PASS. If an SDK path is unavailable, record that exact blocker in the verification document instead of omitting the check.

- [ ] **Step 5: Create the verification document**

Create `docs/superpowers/verification/2026-06-03-headless-pipeline-benchmark-regression-gate.md` from the command outputs captured in Steps 1-4.

The saved document must contain these exact sections:

- `# Headless Pipeline Benchmark And Regression Gate Verification`
- `Date: 2026-06-03`
- `Swift:` followed by the first line of `swift --version`
- `## Commands`
- `## Pipeline Benchmark Output`
- `## Range-Only Benchmark Output`
- `## Gate Output`
- `## Invalid CLI Output`
- `## Target Verification`
- `## Benchmark Scope`

The `## Commands` section must record each of these command results:

```markdown
- `swift test`: pass
- `swift build -c release`: pass
- `swift run -c release ViewportBenchmarks`: pass
- `swift run -c release ViewportBenchmarks -- --range-only`: pass
- `swift run -c release ViewportBenchmarks -- --gate`: pass
- `swift run -c release ViewportBenchmarks -- --help`: pass
- `swift run -c release ViewportBenchmarks -- --range-only --gate`: expected non-zero exit
- `swift run -c release ViewportBenchmarks -- --json`: expected non-zero exit
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`: pass
- `xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule`: pass
- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule`: pass
```

The output sections must use fenced `text` blocks containing the actual captured output from the corresponding commands. The saved file must not contain angle-bracket template text.

The `## Target Verification` section must include:

```markdown
- Host SwiftPM build and tests: verified.
- Pipeline benchmark gate: verified by `--gate` returning `0` with all scenarios under budget.
- Invalid benchmark CLI behavior: verified by non-zero exits for invalid combinations and unknown flags.
- iOS device source compatibility: verified by direct `xcrun swiftc` module compile.
- iOS simulator source compatibility: verified by direct `xcrun swiftc` module compile.
- WASM source compatibility: verified for the `TextEngineCore` target.
- Embedded WASM source compatibility: verified for the `TextEngineCore` target.
```

The `## Benchmark Scope` section must state:

```markdown
The default benchmark now measures the fixed-height headless pipeline:

1. `ViewportVirtualizer.compute(_:)`
2. `ViewportVirtualizer.geometry(for:lineHeight:)` cursor traversal
3. `ViewportVirtualizer.lines(for:in:)` cursor traversal over a synthetic source

The synthetic source returns lightweight integer payloads and does not allocate document-sized storage. `ViewportBenchmarks` remains outside embedded WASM verification because it uses `ContinuousClock` and `Darwin.exit`; the cross-target gate applies to `TextEngineCore`.
```

- [ ] **Step 6: Scan the verification document for unreplaced template markers**

Run:

```bash
rg -n "<|>|TB[D]|TO[D]O" docs/superpowers/verification/2026-06-03-headless-pipeline-benchmark-regression-gate.md
```

Expected: no matches.

- [ ] **Step 7: Commit**

Run:

```bash
git add docs/superpowers/verification/2026-06-03-headless-pipeline-benchmark-regression-gate.md
git commit -m "docs: record headless pipeline benchmark verification"
```

Expected: commit succeeds.

## Task 3: Final Slice Check

**Files:**
- Read: `docs/superpowers/specs/2026-06-01-headless-pipeline-benchmark-regression-gate-design.md`
- Read: `docs/superpowers/verification/2026-06-03-headless-pipeline-benchmark-regression-gate.md`
- Read: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Confirm the worktree is clean**

Run:

```bash
git status --short
```

Expected: no output.

- [ ] **Step 2: Re-run final host checks**

Run:

```bash
swift test
swift run -c release ViewportBenchmarks -- --gate
```

Expected:

- `swift test`: PASS.
- `--gate`: PASS and all three scenario lines include `gate=pass`.

- [ ] **Step 3: Check acceptance criteria against the implementation**

Open `docs/superpowers/specs/2026-06-01-headless-pipeline-benchmark-regression-gate-design.md` and verify:

- `ViewportBenchmarks` defaults to `mode=pipeline`.
- `--range-only` prints `mode=range_only`.
- `--gate` prints budget fields and `gate=pass` or `gate=fail`.
- Invalid `--range-only --gate` exits non-zero.
- Synthetic provider stores only `lineCount`, not an array of lines.
- `TextEngineCore` files were not modified for benchmark support.
- Verification record includes host, gate, invalid CLI, WASM, embedded WASM, iOS device, and iOS simulator checks.

Expected: every item is true.

- [ ] **Step 4: Report completion**

Summarize:

- implementation commits
- verification commands that passed
- any warnings or blockers
- exact path of the verification document
