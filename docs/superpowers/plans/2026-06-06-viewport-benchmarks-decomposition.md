# Viewport Benchmarks Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `ViewportBenchmarks` into focused Swift files while preserving every existing CLI mode, output contract, benchmark budget, workflow command, and `TextEngineCore` boundary.

**Architecture:** Keep `ViewportBenchmarks` as one executable target and move existing declarations out of the 1,005-line `main.swift` into concern-focused files. `main.swift` becomes a small process entrypoint, `BenchmarkProgram.swift` owns parse-and-dispatch, and each benchmark concern owns its own scenarios, fixtures, runners, and formatting. This slice is behavior-preserving; it does not add benchmarks, diagnostics, gates, or core API.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, Swift standard library, `TextEngineCore`, `ViewportBenchmarks`, `Darwin.exit`, `ContinuousClock`, ripgrep, git.

---

## Source Design

Implement the approved Slice 8 design:

```text
docs/superpowers/specs/2026-06-06-viewport-benchmarks-decomposition-design.md
```

The repository may contain an untracked Slice 7 post-slice review file:

```text
docs/superpowers/reviews/2026-06-06-slice-7-post-slice-review.md
```

Leave that file untracked unless the user explicitly asks to add it.

## Scope Check

This plan covers one subsystem: the existing `ViewportBenchmarks` executable target plus a Slice 8 verification record.

Do not modify:

```text
Sources/TextEngineCore
Tests
Package.swift
.github/workflows/swift-ci.yml
```

Do not add:

```text
new CLI modes
new benchmark budgets
new realistic-provider gates
RSS, heap, malloc, allocation-count, or peak-memory measurement
cross-target CI jobs
variable-height layout
GitHub rulesets or branch protection
```

## File Structure

Create these files:

```text
Sources/ViewportBenchmarks/BenchmarkOptions.swift
Sources/ViewportBenchmarks/BenchmarkModels.swift
Sources/ViewportBenchmarks/BenchmarkSupport.swift
Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
Sources/ViewportBenchmarks/BenchmarkProgram.swift
docs/superpowers/verification/2026-06-06-viewport-benchmarks-decomposition.md
```

Modify:

```text
Sources/ViewportBenchmarks/main.swift
```

Final responsibility map:

```text
BenchmarkOptions.swift
  BenchmarkMode
  BenchmarkOptionParse
  BenchmarkOptions

BenchmarkModels.swift
  BenchmarkScenario
  RealisticProviderScenario
  BenchmarkSummary
  BenchmarkOperationResult

BenchmarkSupport.swift
  nanoseconds(_:)
  percentile(_:numerator:denominator:)
  deterministicScrollOffset(sample:maxOffset:)
  runProviderOperation(input:source:foldLineContent:)
  formatSummary(_:includeGate:)

SyntheticBenchmarks.swift
  SyntheticLineSource
  benchmarkScenarios()
  runRangeOnlyOperation(input:)
  runPipelineOperation(input:source:)
  runScenario(_:mode:iterations:operationsPerSample:)
  runSyntheticBenchmarks(options:)

RealisticProviderBenchmark.swift
  RealisticLinePayload
  RealisticDocumentStorage
  RealisticLineSource
  realisticProviderScenarios()
  runRealisticProviderOperation(input:source:)
  runRealisticProviderScenario(_:iterations:operationsPerSample:)
  runRealisticProviderBenchmarks()

MemoryShapeDiagnostics.swift
  MemoryShapeProviderKind
  MemoryShapeScenario
  MemoryShapeTraversalResult
  MemoryShapeSummary
  memoryShapeScenarios()
  memoryShapeScrollOffset(lineCount:lineHeight:viewportHeight:)
  coreOwnedBytesEstimate()
  expectedMemoryShapeVisibleLines(_:)
  expectedMemoryShapeBufferedLines(_:)
  memoryShapeRangeIsOrderedAndBounded(_:lineCount:)
  countGeometryLines(range:lineHeight:)
  countProviderLines(range:source:foldLineContent:)
  runMemoryShapeScenario(_:)
  formatMemoryShapeSummary(_:invariantPasses:)
  runMemoryShapeDiagnostics()

BenchmarkProgram.swift
  runBenchmarks(options:)
  runProgram(arguments:)

main.swift
  macOS availability check
  CommandLine argument forwarding
  Darwin.exit for non-zero result
```

## Task 1: Confirm Baseline And Protect Scope

**Files:**
- Read: `docs/superpowers/specs/2026-06-06-viewport-benchmarks-decomposition-design.md`
- Read: `Sources/ViewportBenchmarks/main.swift`
- Read: `.github/workflows/swift-ci.yml`
- Read: `git status --short`

- [ ] **Step 1: Confirm the approved Slice 8 spec is present**

Run:

```bash
rg -n "Viewport Benchmarks Decomposition Design|BenchmarkOptions.swift|MemoryShapeDiagnostics.swift|behavior-preserving" docs/superpowers/specs/2026-06-06-viewport-benchmarks-decomposition-design.md
```

Expected: output includes all four patterns.

- [ ] **Step 2: Confirm the current benchmark entrypoint is still overgrown**

Run:

```bash
wc -l Sources/ViewportBenchmarks/main.swift
```

Expected before implementation:

```text
    1005 Sources/ViewportBenchmarks/main.swift
```

- [ ] **Step 3: Record current declaration order before moving code**

Run:

```bash
rg -n "^(import|enum|struct|final class|class|protocol|extension|func|let|var|@main)" Sources/ViewportBenchmarks/main.swift
```

Expected: output starts with `import Darwin`, `import TextEngineCore`, `enum BenchmarkMode`, and ends with `func runProgram(arguments: [String]) -> Int32`.

- [ ] **Step 4: Confirm the working tree and note unrelated untracked files**

Run:

```bash
git status --short
```

Expected before implementation: the committed Slice 8 design is clean. If this untracked file is present, leave it untouched and uncommitted:

```text
?? docs/superpowers/reviews/2026-06-06-slice-7-post-slice-review.md
```

- [ ] **Step 5: Confirm baseline commands pass before refactor**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected:

- `swift test` exits `0`;
- `swift build -c release` exits `0`;
- default benchmark prints three `mode=pipeline` lines;
- range-only benchmark prints three `mode=range_only` lines;
- gate benchmark prints three `mode=pipeline` lines with `gate=pass`;
- realistic-provider benchmark prints one `mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text` line;
- memory-shape diagnostic prints three `mode=memory_shape` lines with `invariant=pass`.

## Task 2: Split Benchmark Source Files

**Files:**
- Create: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Create: `Sources/ViewportBenchmarks/BenchmarkModels.swift`
- Create: `Sources/ViewportBenchmarks/BenchmarkSupport.swift`
- Create: `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- Create: `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- Create: `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`
- Create: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- Modify: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Create `BenchmarkOptions.swift` from the existing CLI declarations**

Create `Sources/ViewportBenchmarks/BenchmarkOptions.swift` with the existing `BenchmarkMode`, `BenchmarkOptionParse`, and `BenchmarkOptions` declarations moved verbatim from `main.swift`.

The file must start with this code and preserve all existing error strings:

```swift
enum BenchmarkMode {
    case pipeline
    case rangeOnly
    case realisticProvider
    case memoryShape

    var outputName: String {
        switch self {
        case .pipeline:
            return "pipeline"
        case .rangeOnly:
            return "range_only"
        case .realisticProvider:
            return "realistic_provider"
        case .memoryShape:
            return "memory_shape"
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
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark without gate enforcement.
      --memory-shape        Run deterministic core-owned memory-shape diagnostics.
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
                if mode == .memoryShape {
                    return .failure("--range-only cannot be combined with --memory-shape")
                }
                mode = .rangeOnly
            case "--gate":
                enforceGate = true
            case "--realistic-provider":
                if mode == .rangeOnly {
                    return .failure("--realistic-provider cannot be combined with --range-only")
                }
                if mode == .memoryShape {
                    return .failure("--realistic-provider cannot be combined with --memory-shape")
                }
                mode = .realisticProvider
            case "--memory-shape":
                if mode == .rangeOnly {
                    return .failure("--range-only cannot be combined with --memory-shape")
                }
                if mode == .realisticProvider {
                    return .failure("--realistic-provider cannot be combined with --memory-shape")
                }
                mode = .memoryShape
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
        if mode == .memoryShape && enforceGate {
            return .failure("--memory-shape cannot be combined with --gate")
        }

        return .run(BenchmarkOptions(mode: mode, enforceGate: enforceGate))
    }
}
```

- [ ] **Step 2: Create `BenchmarkModels.swift` from the existing shared value types**

Create `Sources/ViewportBenchmarks/BenchmarkModels.swift` with the existing declarations moved verbatim:

```swift
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
```

- [ ] **Step 3: Create `BenchmarkSupport.swift` by moving shared helper functions**

Create `Sources/ViewportBenchmarks/BenchmarkSupport.swift`.

The file must import `TextEngineCore` and contain these existing declarations moved verbatim:

```swift
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
```

Then move the existing generic `runProviderOperation(input:source:foldLineContent:)` implementation into the same file without changing its body.

Move the existing `formatSummary(_:includeGate:)` implementation into the same file without changing its body. This is the shared latency-output formatter used by both synthetic and realistic-provider benchmark runners; memory-shape diagnostics keep their separate formatter.

- [ ] **Step 4: Create `SyntheticBenchmarks.swift` by moving synthetic benchmark declarations**

Create `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`.

The file must import `TextEngineCore` and contain these existing declarations moved verbatim:

```text
SyntheticLineSource
benchmarkScenarios()
runRangeOnlyOperation(input:)
runPipelineOperation(input:source:)
runScenario(_:mode:iterations:operationsPerSample:)
runSyntheticBenchmarks(options:)
```

Do not change:

```text
iterations = 10_000
operationsPerSample = 256
p95BudgetNanoseconds
p99BudgetNanoseconds
scenario names
checksum arithmetic
gate output field order
```

- [ ] **Step 5: Create `RealisticProviderBenchmark.swift` by moving realistic-provider declarations**

Create `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`.

The file must import `TextEngineCore` and contain these existing declarations moved verbatim:

```text
RealisticLinePayload
RealisticDocumentStorage
RealisticLineSource
realisticProviderScenarios()
runRealisticProviderOperation(input:source:)
runRealisticProviderScenario(_:iterations:operationsPerSample:)
runRealisticProviderBenchmarks()
```

Do not change:

```text
lineCount = 100_000
lineBytes = 112
iterations = 5_000
operationsPerSample = 256
providerName = "large_text"
scenario name = "100k_lines_10mb_text"
payload checksum fields
```

- [ ] **Step 6: Create `MemoryShapeDiagnostics.swift` by moving memory-shape declarations**

Create `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`.

The file must import `TextEngineCore` and contain these existing declarations moved verbatim:

```text
MemoryShapeProviderKind
MemoryShapeScenario
MemoryShapeTraversalResult
MemoryShapeSummary
memoryShapeScenarios()
memoryShapeScrollOffset(lineCount:lineHeight:viewportHeight:)
coreOwnedBytesEstimate()
expectedMemoryShapeVisibleLines(_:)
expectedMemoryShapeBufferedLines(_:)
memoryShapeRangeIsOrderedAndBounded(_:lineCount:)
countGeometryLines(range:lineHeight:)
countProviderLines(range:source:foldLineContent:)
runMemoryShapeScenario(_:)
formatMemoryShapeSummary(_:invariantPasses:)
runMemoryShapeDiagnostics()
```

Do not change:

```text
coreOwnedBytesEstimate()
benchmark_owned_bytes=0
provider names synthetic and large_text
memory-shape scenario names
document_bytes and provider_owned_bytes calculations
invariant output field order
checksum arithmetic
```

- [ ] **Step 7: Create `BenchmarkProgram.swift` from dispatch functions**

Create `Sources/ViewportBenchmarks/BenchmarkProgram.swift` with this content:

```swift
@available(macOS 13.0, *)
func runBenchmarks(options: BenchmarkOptions) -> Bool {
    switch options.mode {
    case .pipeline, .rangeOnly:
        return runSyntheticBenchmarks(options: options)
    case .realisticProvider:
        return runRealisticProviderBenchmarks()
    case .memoryShape:
        return runMemoryShapeDiagnostics()
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
```

- [ ] **Step 8: Replace `main.swift` with the small entrypoint**

Replace `Sources/ViewportBenchmarks/main.swift` with exactly:

```swift
import Darwin

if #available(macOS 13.0, *) {
    let exitCode = runProgram(arguments: Array(CommandLine.arguments.dropFirst()))
    if exitCode != 0 {
        Darwin.exit(exitCode)
    }
} else {
    fatalError("ViewportBenchmarks requires macOS 13.0 or newer")
}
```

- [ ] **Step 9: Build immediately to catch split mistakes**

Run:

```bash
swift build -c release
```

Expected: command exits `0`.

If Swift reports duplicate declaration errors, remove the moved declaration from `main.swift` or from the duplicate destination file. If Swift reports missing `TextEngineCore` symbols, add `import TextEngineCore` to the file named in the diagnostic.

- [ ] **Step 10: Inspect the resulting source file sizes**

Run:

```bash
wc -l Sources/ViewportBenchmarks/*.swift
```

Expected:

- `Sources/ViewportBenchmarks/main.swift` is a small entrypoint, about 10 lines;
- no generated file is close to 1,000 lines;
- total lines across the target may remain similar because this is a decomposition, not a behavior rewrite.

- [ ] **Step 11: Commit the behavior-preserving source split**

Run:

```bash
git status --short
git add Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkModels.swift Sources/ViewportBenchmarks/BenchmarkSupport.swift Sources/ViewportBenchmarks/SyntheticBenchmarks.swift Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/main.swift
git commit -m "refactor: split viewport benchmark executable"
```

Expected: commit includes only `Sources/ViewportBenchmarks/*.swift`. Do not stage `docs/superpowers/reviews/2026-06-06-slice-7-post-slice-review.md`.

## Task 3: Verify Behavior Preservation

**Files:**
- Read: `Sources/ViewportBenchmarks/*.swift`
- Read: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Run host tests**

Run:

```bash
swift test
```

Expected: command exits `0` and all `TextEngineCoreTests` pass.

- [ ] **Step 2: Run release build**

Run:

```bash
swift build -c release
```

Expected: command exits `0`.

- [ ] **Step 3: Run default pipeline benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks
```

Expected: command exits `0` and prints three lines with these stable fields:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256
```

Each line also includes `p95_ns=`, `p99_ns=`, `failures=0`, and `checksum=`.

- [ ] **Step 4: Run range-only benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks -- --range-only
```

Expected: command exits `0` and prints three lines with these stable fields:

```text
mode=range_only scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256
mode=range_only scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256
mode=range_only scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256
```

Each line also includes `p95_ns=`, `p99_ns=`, `failures=0`, and `checksum=`.

- [ ] **Step 5: Run synthetic benchmark gate**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: command exits `0` and prints three `mode=pipeline` lines with:

```text
budget_p95_ns=
budget_p99_ns=
gate=pass
failures=0
```

Expected budget fields remain:

```text
1k_lines_20_visible_overscan_0 budget_p95_ns=20000 budget_p99_ns=50000
100k_lines_80_visible_overscan_5 budget_p95_ns=50000 budget_p99_ns=100000
1m_lines_200_visible_overscan_50 budget_p95_ns=100000 budget_p99_ns=200000
```

- [ ] **Step 6: Run realistic-provider benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Expected: command exits `0` and prints one line with:

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112
```

The line also includes `p95_ns=`, `p99_ns=`, `failures=0`, and `checksum=`.

- [ ] **Step 7: Run memory-shape diagnostic**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected: command exits `0` and prints these stable fields:

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass
```

Each line also includes `checksum=`.

- [ ] **Step 8: Verify invalid memory-shape gate remains non-zero**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape --gate
```

Expected: command exits non-zero and output contains:

```text
error=--memory-shape cannot be combined with --gate
```

- [ ] **Step 9: Verify other invalid CLI combinations still use existing error text**

Run each command:

```bash
swift run -c release ViewportBenchmarks -- --range-only --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --range-only --realistic-provider
swift run -c release ViewportBenchmarks -- --range-only --memory-shape
swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape
swift run -c release ViewportBenchmarks -- --unknown
```

Expected: each command exits non-zero. Outputs contain these error lines respectively:

```text
error=--range-only cannot be combined with --gate
error=--realistic-provider cannot be combined with --gate
error=--realistic-provider cannot be combined with --range-only
error=--range-only cannot be combined with --memory-shape
error=--realistic-provider cannot be combined with --memory-shape
error=unknown argument --unknown
```

- [ ] **Step 10: Verify workflow commands and status name are unchanged**

Run:

```bash
rg -n "Run synthetic benchmark gate|Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml
```

Expected: output includes:

```text
name: Host tests and benchmark gate
Run synthetic benchmark gate
Run memory shape diagnostic
swift run -c release ViewportBenchmarks -- --memory-shape
```

- [ ] **Step 11: Verify non-goal paths have no diff**

Run:

```bash
git diff -- Sources/TextEngineCore Tests Package.swift .github/workflows/swift-ci.yml
```

Expected: no output.

- [ ] **Step 12: Verify only intended files changed since the source split commit**

Run:

```bash
git status --short
```

Expected after Task 2 commit and before verification doc creation: no modified tracked files. The untracked Slice 7 review may still appear and must remain uncommitted unless the user explicitly asks.

## Task 4: Record Slice 8 Verification

**Files:**
- Create: `docs/superpowers/verification/2026-06-06-viewport-benchmarks-decomposition.md`

- [ ] **Step 1: Create the verification document**

Create `docs/superpowers/verification/2026-06-06-viewport-benchmarks-decomposition.md` with this structure and populate each command section with the exact output observed in Task 3:

```markdown
# Viewport Benchmarks Decomposition Verification

Date: 2026-06-06

## Scope

Slice 8 split `Sources/ViewportBenchmarks/main.swift` into focused files without changing benchmark behavior.

## Changed Source Files

- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- `Sources/ViewportBenchmarks/BenchmarkModels.swift`
- `Sources/ViewportBenchmarks/BenchmarkSupport.swift`
- `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- `Sources/ViewportBenchmarks/main.swift`

## Non-Goal Checks

The slice did not change:

- `Sources/TextEngineCore`
- `Tests`
- `Package.swift`
- `.github/workflows/swift-ci.yml`

## Verification Commands

### Host Tests

Command:

```text
swift test
```

Result: pass.

### Release Build

Command:

```text
swift build -c release
```

Result: pass.

### Default Pipeline Benchmark

Command:

```text
swift run -c release ViewportBenchmarks
```

Result: pass.

### Range-Only Benchmark

Command:

```text
swift run -c release ViewportBenchmarks -- --range-only
```

Result: pass.

### Synthetic Benchmark Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass.

### Realistic Provider Benchmark

Command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Result: pass.

### Memory-Shape Diagnostic

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass.

### Invalid Memory-Shape Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-shape --gate
```

Result: expected non-zero exit with `error=--memory-shape cannot be combined with --gate`.

### Additional Invalid CLI Checks

Commands:

```text
swift run -c release ViewportBenchmarks -- --range-only --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --range-only --realistic-provider
swift run -c release ViewportBenchmarks -- --range-only --memory-shape
swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape
swift run -c release ViewportBenchmarks -- --unknown
```

Result: each command exited non-zero with the existing error text.

### Workflow Scan

Command:

```text
rg -n "Run synthetic benchmark gate|Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml
```

Result: workflow status name and benchmark commands are unchanged.

### Non-Goal Diff Check

Command:

```text
git diff -- Sources/TextEngineCore Tests Package.swift .github/workflows/swift-ci.yml
```

Result: no output.

### Source File Size Check

Command:

```text
wc -l Sources/ViewportBenchmarks/*.swift
```

Result: `main.swift` is reduced to a small entrypoint and benchmark concerns are split across focused files.

## Conclusion

Slice 8 preserves the benchmark executable's behavior while resolving the Slice 7 maintainability finding that `main.swift` crossed 1,000 lines.
```

For each benchmark command section, add the exact command output below the `Result: pass.` sentence in a fenced `text` block. Use the actual output from Task 3; do not invent latency numbers.

- [ ] **Step 2: Verify the verification document has no incomplete markers**

Run:

```bash
rg -n "REPLACE_WITH|COPY_OUTPUT_HERE|INSERT_OUTPUT|LATENCY_NUMBER" docs/superpowers/verification/2026-06-06-viewport-benchmarks-decomposition.md
```

Expected: no output.

- [ ] **Step 3: Commit the verification document**

Run:

```bash
git add docs/superpowers/verification/2026-06-06-viewport-benchmarks-decomposition.md
git commit -m "docs: record viewport benchmark decomposition verification"
```

Expected: commit includes only the new verification document.

## Task 5: Final Slice 8 Audit

**Files:**
- Read: `Sources/ViewportBenchmarks/*.swift`
- Read: `docs/superpowers/verification/2026-06-06-viewport-benchmarks-decomposition.md`
- Read: `git status --short`
- Read: `git log --oneline -5`

- [ ] **Step 1: Confirm final tracked diff is clean**

Run:

```bash
git status --short
```

Expected: no tracked source, test, workflow, package, spec, plan, or verification files remain modified. The untracked Slice 7 review may still appear:

```text
?? docs/superpowers/reviews/2026-06-06-slice-7-post-slice-review.md
```

- [ ] **Step 2: Confirm recent commits show Slice 8 source and verification**

Run:

```bash
git log --oneline -5
```

Expected: recent history includes:

```text
refactor: split viewport benchmark executable
docs: record viewport benchmark decomposition verification
docs: plan viewport benchmarks decomposition
docs: design viewport benchmarks decomposition
```

The exact hashes will differ.

- [ ] **Step 3: Confirm non-goal paths are unchanged from before Slice 8 implementation**

Run:

```bash
git diff HEAD~2..HEAD -- Sources/TextEngineCore Tests Package.swift .github/workflows/swift-ci.yml
```

Expected: no output.

- [ ] **Step 4: Confirm `main.swift` contains only process entry responsibilities**

Run:

```bash
sed -n '1,80p' Sources/ViewportBenchmarks/main.swift
```

Expected output is:

```swift
import Darwin

if #available(macOS 13.0, *) {
    let exitCode = runProgram(arguments: Array(CommandLine.arguments.dropFirst()))
    if exitCode != 0 {
        Darwin.exit(exitCode)
    }
} else {
    fatalError("ViewportBenchmarks requires macOS 13.0 or newer")
}
```

- [ ] **Step 5: Prepare post-slice review prompt**

After implementation and verification are committed, request a post-slice review that covers:

```text
docs/initial-project-brief.md
docs/superpowers/specs/2026-06-06-viewport-benchmarks-decomposition-design.md
docs/superpowers/plans/2026-06-06-viewport-benchmarks-decomposition.md
Sources/ViewportBenchmarks/*.swift
docs/superpowers/verification/2026-06-06-viewport-benchmarks-decomposition.md
git commit history for Slice 8
```

Expected review focus:

- behavior preservation;
- no `TextEngineCore`, tests, package, or workflow drift;
- benchmark output contract preservation;
- whether file boundaries are clear enough for future benchmark/memory slices;
- whether the Slice 7 `main.swift` maintainability finding is resolved.
