# Core-Owned Memory Shape Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic memory-shape diagnostic to `ViewportBenchmarks`, run it in the existing GitHub Actions workflow, and record verification proving core-owned fixed-height state does not grow with total document size.

**Architecture:** `TextEngineCore` stays unchanged and remains the source of the range and cursor types under inspection. The host-only `ViewportBenchmarks` executable gains a `--memory-shape` mode that classifies core-owned, provider-owned, and benchmark-owned memory shape using deterministic model estimates and invariant checks. The existing `Swift CI` workflow runs the diagnostic after the synthetic benchmark gate and relies on the executable exit code.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, `TextEngineCore`, `ViewportBenchmarks`, GitHub Actions, ripgrep.

---

## Source Design

Implement the approved Slice 7 design:

```text
docs/superpowers/specs/2026-06-06-core-owned-memory-shape-design.md
```

Do not execute the deferred Slice 6 GitHub ruleset plan. The repository may contain an untracked Slice 6 post-slice review file:

```text
docs/superpowers/reviews/2026-06-06-slice-6-post-slice-review.md
```

Leave that file untracked unless the user explicitly asks to add it.

## File Structure

- Modify `Sources/ViewportBenchmarks/main.swift`: add `BenchmarkMode.memoryShape`, parse `--memory-shape`, add memory-shape scenario/summary helpers, print key-value diagnostic output, and return non-zero when deterministic invariants fail.
- Modify `.github/workflows/swift-ci.yml`: add one workflow step that runs `swift run -c release ViewportBenchmarks -- --memory-shape` after the existing synthetic benchmark gate.
- Create `docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md`: record commands, exact local output, workflow scan, and target verification.
- Do not modify `Sources/TextEngineCore/*`.
- Do not modify `Package.swift`.

## Task 1: Confirm Baseline And Existing Gate

**Files:**
- Read: `docs/superpowers/specs/2026-06-06-core-owned-memory-shape-design.md`
- Read: `Sources/ViewportBenchmarks/main.swift`
- Read: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Confirm the approved spec is present**

Run:

```bash
rg -n "Core-Owned Memory Shape Design|--memory-shape|Run memory shape diagnostic" docs/superpowers/specs/2026-06-06-core-owned-memory-shape-design.md
```

Expected: output includes all three patterns.

- [ ] **Step 2: Confirm the new CLI flag is unsupported before implementation**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected: command exits non-zero and output contains:

```text
error=unknown argument --memory-shape
```

- [ ] **Step 3: Confirm the existing synthetic gate passes before implementation**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: command exits `0` and prints three `mode=pipeline` lines with `gate=pass`.

- [ ] **Step 4: Confirm the workflow currently has no memory-shape step**

Run:

```bash
rg -n -- "--memory-shape|Run memory shape diagnostic" .github/workflows/swift-ci.yml
```

Expected: no output.

## Task 2: Add Memory-Shape CLI And Diagnostic

**Files:**
- Modify: `Sources/ViewportBenchmarks/main.swift`

- [ ] **Step 1: Extend `BenchmarkMode` and command-line parsing**

In `Sources/ViewportBenchmarks/main.swift`, replace the current `BenchmarkMode` enum and `BenchmarkOptions` implementation near the top of the file with this version:

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
                    return .failure("--memory-shape cannot be combined with --range-only")
                }
                if mode == .realisticProvider {
                    return .failure("--memory-shape cannot be combined with --realistic-provider")
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

- [ ] **Step 2: Add memory-shape value types**

Add these types immediately after `BenchmarkOperationResult`:

```swift
enum MemoryShapeProviderKind {
    case synthetic
    case largeText

    var outputName: String {
        switch self {
        case .synthetic:
            return "synthetic"
        case .largeText:
            return "large_text"
        }
    }
}

struct MemoryShapeScenario {
    let name: String
    let providerKind: MemoryShapeProviderKind
    let lineCount: Int
    let lineBytes: Int?
    let lineHeight: Double
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
}

struct MemoryShapeTraversalResult {
    let lineCount: Int
    let missingCount: Int
    let checksum: Int
}

struct MemoryShapeSummary {
    let providerName: String
    let scenarioName: String
    let lineCount: Int
    let documentBytes: Int?
    let visibleLines: Int
    let bufferedLines: Int
    let geometryLines: Int
    let providerLines: Int
    let missingLines: Int
    let coreOwnedBytes: Int
    let providerOwnedBytes: Int
    let benchmarkOwnedBytes: Int
    let baseInvariantPasses: Bool
    let checksum: Int
}
```

- [ ] **Step 3: Add memory-shape scenarios**

Add this function immediately after `realisticProviderScenarios()`:

```swift
func memoryShapeScenarios() -> [MemoryShapeScenario] {
    [
        MemoryShapeScenario(
            name: "100k_lines_80_visible_overscan_5",
            providerKind: .synthetic,
            lineCount: 100_000,
            lineBytes: nil,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5
        ),
        MemoryShapeScenario(
            name: "1m_lines_80_visible_overscan_5",
            providerKind: .synthetic,
            lineCount: 1_000_000,
            lineBytes: nil,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5
        ),
        MemoryShapeScenario(
            name: "100k_lines_10mb_text",
            providerKind: .largeText,
            lineCount: 100_000,
            lineBytes: 112,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5
        )
    ]
}
```

- [ ] **Step 4: Add memory-shape helper functions**

Add these helper functions immediately after `runRealisticProviderOperation(input:source:)`:

```swift
func memoryShapeScrollOffset(lineCount: Int, lineHeight: Double, viewportHeight: Double) -> Double {
    let documentHeight = Double(lineCount) * lineHeight
    let maxOffset = documentHeight > viewportHeight ? documentHeight - viewportHeight : 0.0
    let middleOffset = Double(lineCount / 2) * lineHeight

    if middleOffset > maxOffset {
        return maxOffset
    }

    return middleOffset
}

func coreOwnedBytesEstimate() -> Int {
    MemoryLayout<VirtualRange>.size
        + MemoryLayout<LineGeometryCursor>.size
        + MemoryLayout<Int>.size * 2
}

func countGeometryLines(range: VirtualRange, lineHeight: Double) -> MemoryShapeTraversalResult {
    var cursor = ViewportVirtualizer.geometry(for: range, lineHeight: lineHeight)
    var lineCount = 0
    var checksum = 0

    while let geometry = cursor.next() {
        lineCount += 1
        checksum &+= geometry.lineIndex
        checksum &+= Int(geometry.y)
        checksum &+= Int(geometry.height)
    }

    return MemoryShapeTraversalResult(
        lineCount: lineCount,
        missingCount: 0,
        checksum: checksum
    )
}

func countProviderLines<Source: DocumentLineSource>(
    range: VirtualRange,
    source: Source,
    foldLineContent: (inout Int, Source.Line) -> Void
) -> MemoryShapeTraversalResult {
    var cursor = ViewportVirtualizer.lines(for: range, in: source)
    var lineCount = 0
    var missingCount = 0
    var checksum = 0

    while let element = cursor.next() {
        switch element {
        case let .line(line):
            lineCount += 1
            checksum &+= line.index
            foldLineContent(&checksum, line.content)
        case let .missing(index):
            missingCount += 1
            checksum &-= index
        }
    }

    return MemoryShapeTraversalResult(
        lineCount: lineCount,
        missingCount: missingCount,
        checksum: checksum
    )
}
```

- [ ] **Step 5: Add memory-shape scenario execution and formatting**

Add these functions immediately before `formatSummary(_ summary:includeGate:)`:

```swift
func runMemoryShapeScenario(_ scenario: MemoryShapeScenario) -> MemoryShapeSummary {
    let scrollOffset = memoryShapeScrollOffset(
        lineCount: scenario.lineCount,
        lineHeight: scenario.lineHeight,
        viewportHeight: scenario.viewportHeight
    )
    let input = ViewportInput(
        lineCount: scenario.lineCount,
        lineHeight: scenario.lineHeight,
        scrollOffsetY: scrollOffset,
        viewportHeight: scenario.viewportHeight,
        overscanLinesBefore: scenario.overscanBefore,
        overscanLinesAfter: scenario.overscanAfter
    )
    let coreOwnedBytes = coreOwnedBytesEstimate()

    switch ViewportVirtualizer.compute(input) {
    case let .success(range):
        let visibleLines = range.visibleEndExclusive - range.visibleStart
        let bufferedLines = range.bufferEndExclusive - range.bufferStart
        let geometry = countGeometryLines(range: range, lineHeight: scenario.lineHeight)
        let provider: MemoryShapeTraversalResult
        let providerOwnedBytes: Int
        let documentBytes: Int?

        switch scenario.providerKind {
        case .synthetic:
            let source = SyntheticLineSource(lineCount: scenario.lineCount)
            provider = countProviderLines(range: range, source: source) { checksum, content in
                checksum &+= content
            }
            providerOwnedBytes = 0
            documentBytes = nil
        case .largeText:
            guard let lineBytes = scenario.lineBytes else {
                return MemoryShapeSummary(
                    providerName: scenario.providerKind.outputName,
                    scenarioName: scenario.name,
                    lineCount: scenario.lineCount,
                    documentBytes: nil,
                    visibleLines: visibleLines,
                    bufferedLines: bufferedLines,
                    geometryLines: geometry.lineCount,
                    providerLines: 0,
                    missingLines: 1,
                    coreOwnedBytes: coreOwnedBytes,
                    providerOwnedBytes: 0,
                    benchmarkOwnedBytes: 0,
                    baseInvariantPasses: false,
                    checksum: -1
                )
            }

            let storage = RealisticDocumentStorage(lineCount: scenario.lineCount, lineBytes: lineBytes)
            let source = RealisticLineSource(storage: storage)
            provider = countProviderLines(range: range, source: source) { checksum, content in
                checksum &+= content.byteOffset
                checksum &+= content.byteLength
                checksum &+= content.firstByte
                checksum &+= content.middleByte
                checksum &+= content.lastByte
            }
            providerOwnedBytes = storage.documentBytes
            documentBytes = storage.documentBytes
        }

        let expectedProviderBytes: Int
        switch scenario.providerKind {
        case .synthetic:
            expectedProviderBytes = 0
        case .largeText:
            expectedProviderBytes = documentBytes ?? -1
        }

        let baseInvariantPasses = bufferedLines == range.bufferEndExclusive - range.bufferStart
            && geometry.lineCount == bufferedLines
            && provider.lineCount == bufferedLines
            && provider.missingCount == 0
            && providerOwnedBytes == expectedProviderBytes

        var checksum = 0
        checksum &+= scenario.lineCount
        checksum &+= visibleLines
        checksum &+= bufferedLines
        checksum &+= geometry.checksum
        checksum &+= provider.checksum
        checksum &+= coreOwnedBytes
        checksum &+= providerOwnedBytes

        return MemoryShapeSummary(
            providerName: scenario.providerKind.outputName,
            scenarioName: scenario.name,
            lineCount: scenario.lineCount,
            documentBytes: documentBytes,
            visibleLines: visibleLines,
            bufferedLines: bufferedLines,
            geometryLines: geometry.lineCount,
            providerLines: provider.lineCount,
            missingLines: provider.missingCount,
            coreOwnedBytes: coreOwnedBytes,
            providerOwnedBytes: providerOwnedBytes,
            benchmarkOwnedBytes: 0,
            baseInvariantPasses: baseInvariantPasses,
            checksum: checksum
        )
    case .failure:
        return MemoryShapeSummary(
            providerName: scenario.providerKind.outputName,
            scenarioName: scenario.name,
            lineCount: scenario.lineCount,
            documentBytes: nil,
            visibleLines: 0,
            bufferedLines: 0,
            geometryLines: 0,
            providerLines: 0,
            missingLines: 1,
            coreOwnedBytes: coreOwnedBytes,
            providerOwnedBytes: 0,
            benchmarkOwnedBytes: 0,
            baseInvariantPasses: false,
            checksum: -1
        )
    }
}

func formatMemoryShapeSummary(_ summary: MemoryShapeSummary, invariantPasses: Bool) -> String {
    var output = "mode=\(BenchmarkMode.memoryShape.outputName)"
    output += " provider=\(summary.providerName)"
    output += " scenario=\(summary.scenarioName)"
    output += " line_count=\(summary.lineCount)"
    if let documentBytes = summary.documentBytes {
        output += " document_bytes=\(documentBytes)"
    }
    output += " visible_lines=\(summary.visibleLines)"
    output += " buffered_lines=\(summary.bufferedLines)"
    output += " touched_lines=\(summary.providerLines)"
    output += " geometry_lines=\(summary.geometryLines)"
    output += " provider_lines=\(summary.providerLines)"
    output += " missing_lines=\(summary.missingLines)"
    output += " core_owned_bytes=\(summary.coreOwnedBytes)"
    output += " provider_owned_bytes=\(summary.providerOwnedBytes)"
    output += " benchmark_owned_bytes=\(summary.benchmarkOwnedBytes)"
    output += " invariant=\(invariantPasses ? "pass" : "fail")"
    output += " checksum=\(summary.checksum)"
    return output
}

func runMemoryShapeDiagnostics() -> Bool {
    let summaries = memoryShapeScenarios().map(runMemoryShapeScenario)
    let syntheticCoreOwnedBytes = summaries
        .filter { $0.providerName == MemoryShapeProviderKind.synthetic.outputName }
        .map(\.coreOwnedBytes)
    let comparisonCoreOwnedBytes = syntheticCoreOwnedBytes.first
    var passed = true

    for summary in summaries {
        let comparisonPasses: Bool
        if summary.providerName == MemoryShapeProviderKind.synthetic.outputName,
           let comparisonCoreOwnedBytes {
            comparisonPasses = summary.coreOwnedBytes == comparisonCoreOwnedBytes
        } else {
            comparisonPasses = true
        }

        let invariantPasses = summary.baseInvariantPasses && comparisonPasses
        print(formatMemoryShapeSummary(summary, invariantPasses: invariantPasses))

        if !invariantPasses {
            passed = false
        }
    }

    return passed
}
```

- [ ] **Step 6: Route `memoryShape` through the benchmark runner**

In `runScenario(_:mode:iterations:operationsPerSample:)`, update the mode switch to include `.memoryShape`:

```swift
            switch mode {
            case .pipeline:
                operationResult = runPipelineOperation(input: input, source: source)
            case .rangeOnly:
                operationResult = runRangeOnlyOperation(input: input)
            case .realisticProvider:
                preconditionFailure("realistic provider mode uses runRealisticProviderScenario")
            case .memoryShape:
                preconditionFailure("memory shape mode uses runMemoryShapeDiagnostics")
            }
```

In `runBenchmarks(options:)`, replace the current switch with this version:

```swift
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
```

- [ ] **Step 7: Run the new memory-shape diagnostic**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected: command exits `0` and prints exactly three lines with:

```text
mode=memory_shape
provider=synthetic
provider=large_text
scenario=100k_lines_80_visible_overscan_5
scenario=1m_lines_80_visible_overscan_5
scenario=100k_lines_10mb_text
document_bytes=11200000
provider_owned_bytes=11200000
invariant=pass
```

- [ ] **Step 8: Verify invalid memory-shape combinations**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape --gate
swift run -c release ViewportBenchmarks -- --memory-shape --range-only
swift run -c release ViewportBenchmarks -- --memory-shape --realistic-provider
```

Expected: each command exits non-zero. The first output contains:

```text
error=--memory-shape cannot be combined with --gate
```

The second output contains:

```text
error=--range-only cannot be combined with --memory-shape
```

The third output contains:

```text
error=--realistic-provider cannot be combined with --memory-shape
```

- [ ] **Step 9: Verify existing benchmark modes still work**

Run:

```bash
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Expected:

- default command exits `0` and prints three `mode=pipeline` lines;
- `--range-only` exits `0` and prints three `mode=range_only` lines;
- `--gate` exits `0` and prints three `gate=pass` lines;
- `--realistic-provider` exits `0` and prints one `mode=realistic_provider provider=large_text` line.

- [ ] **Step 10: Confirm core and package files were not touched**

Run:

```bash
git diff -- Sources/TextEngineCore Package.swift
```

Expected: no output.

- [ ] **Step 11: Commit the diagnostic implementation**

Run:

```bash
git add Sources/ViewportBenchmarks/main.swift
git commit -m "feat: add memory shape diagnostic"
```

Expected: commit succeeds with only `Sources/ViewportBenchmarks/main.swift` staged.

## Task 3: Add Memory-Shape Diagnostic To Swift CI

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Insert the workflow step after the synthetic benchmark gate**

Edit `.github/workflows/swift-ci.yml` so the final steps are:

```yaml
      - name: Run host tests
        run: swift test

      - name: Run synthetic benchmark gate
        run: swift run -c release ViewportBenchmarks -- --gate

      - name: Run memory shape diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-shape
```

Do not change the workflow name, job id, job name, triggers, runner, timeout, or permissions.

- [ ] **Step 2: Verify the workflow contains the new step and keeps the job name**

Run:

```bash
rg -n "name: Host tests and benchmark gate|Run synthetic benchmark gate|Run memory shape diagnostic|--memory-shape" .github/workflows/swift-ci.yml
```

Expected: output includes:

```text
name: Host tests and benchmark gate
Run synthetic benchmark gate
Run memory shape diagnostic
swift run -c release ViewportBenchmarks -- --memory-shape
```

- [ ] **Step 3: Run the exact command used by the workflow**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected: command exits `0` and all memory-shape lines include `invariant=pass`.

- [ ] **Step 4: Commit the workflow change**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: run memory shape diagnostic"
```

Expected: commit succeeds with only `.github/workflows/swift-ci.yml` staged.

## Task 4: Record Slice Verification

**Files:**
- Create: `docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md`

- [ ] **Step 1: Capture host tests**

Run:

```bash
swift test 2>&1 | tee /private/tmp/core-memory-shape-swift-test.out
```

Expected: command exits `0`.

- [ ] **Step 2: Capture release build**

Run:

```bash
swift build -c release 2>&1 | tee /private/tmp/core-memory-shape-release-build.out
```

Expected: command exits `0`.

- [ ] **Step 3: Capture default pipeline benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks 2>&1 | tee /private/tmp/core-memory-shape-pipeline.out
```

Expected: command exits `0`.

- [ ] **Step 4: Capture range-only benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks -- --range-only 2>&1 | tee /private/tmp/core-memory-shape-range-only.out
```

Expected: command exits `0`.

- [ ] **Step 5: Capture synthetic benchmark gate**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tee /private/tmp/core-memory-shape-gate.out
```

Expected: command exits `0` and each benchmark line includes `gate=pass`.

- [ ] **Step 6: Capture realistic-provider benchmark**

Run:

```bash
swift run -c release ViewportBenchmarks -- --realistic-provider 2>&1 | tee /private/tmp/core-memory-shape-realistic-provider.out
```

Expected: command exits `0` and output includes `document_bytes=11200000`.

- [ ] **Step 7: Capture memory-shape diagnostic**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape 2>&1 | tee /private/tmp/core-memory-shape-diagnostic.out
```

Expected: command exits `0` and output includes three `mode=memory_shape` lines with `invariant=pass`.

- [ ] **Step 8: Capture invalid memory-shape gate behavior**

Run:

```bash
/bin/zsh -lc 'swift run -c release ViewportBenchmarks -- --memory-shape --gate > /private/tmp/core-memory-shape-invalid-gate.out 2>&1; test $? -ne 0'
```

Expected: command exits `0` because the benchmark command inside exited non-zero as expected.

- [ ] **Step 9: Capture workflow scan**

Run:

```bash
rg -n "Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml 2>&1 | tee /private/tmp/core-memory-shape-workflow-scan.out
```

Expected: command exits `0`.

- [ ] **Step 10: Capture WASM target verification**

Run:

```bash
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore 2>&1 | tee /private/tmp/core-memory-shape-wasm.out
```

Expected: command exits `0`.

- [ ] **Step 11: Capture embedded WASM target verification**

Run:

```bash
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore 2>&1 | tee /private/tmp/core-memory-shape-wasm-embedded.out
```

Expected: command exits `0`.

- [ ] **Step 12: Capture iOS device module verification**

Run:

```bash
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule 2>&1 | tee /private/tmp/core-memory-shape-ios-device.out
```

Expected: command exits `0`.

- [ ] **Step 13: Capture iOS simulator module verification**

Run:

```bash
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule 2>&1 | tee /private/tmp/core-memory-shape-ios-simulator.out
```

Expected: command exits `0`.

- [ ] **Step 14: Create the verification document from captured outputs**

Run:

```bash
ruby - <<'RUBY'
def read(path)
  File.read(path).rstrip
end

content = <<~MD
  # Core-Owned Memory Shape Verification

  Date: 2026-06-06

  Swift: Apple Swift version 6.2.1 (swift-6.2.1-RELEASE)

  ## Commands

  - `swift test`: pass
  - `swift build -c release`: pass
  - `swift run -c release ViewportBenchmarks`: pass
  - `swift run -c release ViewportBenchmarks -- --range-only`: pass
  - `swift run -c release ViewportBenchmarks -- --gate`: pass
  - `swift run -c release ViewportBenchmarks -- --realistic-provider`: pass
  - `swift run -c release ViewportBenchmarks -- --memory-shape`: pass
  - `swift run -c release ViewportBenchmarks -- --memory-shape --gate`: expected non-zero exit
  - `rg -n "Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml`: pass
  - `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`: pass
  - `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`: pass
  - `xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule`: pass
  - `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule`: pass

  ## Host Test Output

  `swift test`:

  ```text
  #{read("/private/tmp/core-memory-shape-swift-test.out")}
  ```

  ## Release Build Output

  `swift build -c release`:

  ```text
  #{read("/private/tmp/core-memory-shape-release-build.out")}
  ```

  ## Default Pipeline Benchmark Output

  `swift run -c release ViewportBenchmarks`:

  ```text
  #{read("/private/tmp/core-memory-shape-pipeline.out")}
  ```

  ## Range-Only Benchmark Output

  `swift run -c release ViewportBenchmarks -- --range-only`:

  ```text
  #{read("/private/tmp/core-memory-shape-range-only.out")}
  ```

  ## Gate Output

  `swift run -c release ViewportBenchmarks -- --gate`:

  ```text
  #{read("/private/tmp/core-memory-shape-gate.out")}
  ```

  ## Realistic Provider Benchmark Output

  `swift run -c release ViewportBenchmarks -- --realistic-provider`:

  ```text
  #{read("/private/tmp/core-memory-shape-realistic-provider.out")}
  ```

  ## Memory Shape Diagnostic Output

  `swift run -c release ViewportBenchmarks -- --memory-shape`:

  ```text
  #{read("/private/tmp/core-memory-shape-diagnostic.out")}
  ```

  ## Invalid CLI Output

  `swift run -c release ViewportBenchmarks -- --memory-shape --gate` exited non-zero as expected:

  ```text
  #{read("/private/tmp/core-memory-shape-invalid-gate.out")}
  ```

  ## Workflow Scan

  `rg -n "Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml`:

  ```text
  #{read("/private/tmp/core-memory-shape-workflow-scan.out")}
  ```

  ## Target Verification Output

  `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`:

  ```text
  #{read("/private/tmp/core-memory-shape-wasm.out")}
  ```

  `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`:

  ```text
  #{read("/private/tmp/core-memory-shape-wasm-embedded.out")}
  ```

  `xcrun swiftc` iOS device module compile:

  ```text
  #{read("/private/tmp/core-memory-shape-ios-device.out")}
  ```

  `xcrun swiftc` iOS simulator module compile:

  ```text
  #{read("/private/tmp/core-memory-shape-ios-simulator.out")}
  ```

  ## Memory Shape Interpretation

  The memory-shape diagnostic reports deterministic model estimates, not RSS,
  heap, or allocation profiler output.

  The synthetic 100,000-line and 1,000,000-line scenarios use the same visible
  and overscan shape. Their `core_owned_bytes` values match, which proves the
  current fixed-height core-owned scalar and cursor state does not grow with
  total line count for that shape.

  The realistic-provider scenario reports `document_bytes=11200000` and
  `provider_owned_bytes=11200000`. That payload is caller/provider-owned
  benchmark storage and is not classified as core-owned memory.

  The diagnostic reports `invariant=pass` for all scenarios. It is now run in
  `.github/workflows/swift-ci.yml` after the synthetic benchmark gate.

  ## Scope Boundaries

  Slice 7 does not enforce RSS, heap, or allocation budgets. It does not add
  realistic-provider latency budgets, branch protection, GitHub rulesets,
  variable-height layout, production storage adapters, or public
  `TextEngineCore` API.
MD

File.write("docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md", content)
RUBY
```

Expected: `docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md` is created.

- [ ] **Step 15: Scan the verification document for unresolved markers**

Run:

```bash
rg -n "TB[D]|TO[D]O|FIXM[E]|PLACEHOLD[E]R|X[X]X" docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md
```

Expected: no output.

- [ ] **Step 16: Confirm the verification document records required evidence**

Run:

```bash
rg -n "mode=memory_shape|scenario=1m_lines_80_visible_overscan_5|document_bytes=11200000|provider_owned_bytes=11200000|invariant=pass|Run memory shape diagnostic|TextEngineCore API" docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md
```

Expected: output includes all listed evidence patterns.

- [ ] **Step 17: Commit the verification document**

Run:

```bash
git add docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md
git commit -m "docs: record memory shape verification"
```

Expected: commit succeeds with only the verification document staged.

## Task 5: Final Slice Audit

**Files:**
- Read: `docs/superpowers/specs/2026-06-06-core-owned-memory-shape-design.md`
- Read: `docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md`
- Read: `Sources/ViewportBenchmarks/main.swift`
- Read: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Re-run host tests**

Run:

```bash
swift test
```

Expected: command exits `0`.

- [ ] **Step 2: Re-run the synthetic benchmark gate**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: command exits `0` and prints three `gate=pass` lines.

- [ ] **Step 3: Re-run the memory-shape diagnostic**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected: command exits `0`, prints exactly three `mode=memory_shape` lines, and each line includes `invariant=pass`.

- [ ] **Step 4: Confirm no core or package source changed**

Run:

```bash
git diff HEAD~3..HEAD -- Sources/TextEngineCore Package.swift
```

Expected: no output.

- [ ] **Step 5: Confirm workflow scope stayed narrow**

Run:

```bash
rg -n "realistic-provider|swift build --swift-sdk|xcrun swiftc|continue-on-error|branch protection|ruleset" .github/workflows/swift-ci.yml
```

Expected: no output.

- [ ] **Step 6: Confirm Slice 7 changed only the intended tracked files**

Run:

```bash
git diff --name-only 82a829d..HEAD
```

Expected tracked Slice 7 files:

```text
docs/superpowers/specs/2026-06-06-core-owned-memory-shape-design.md
docs/superpowers/plans/2026-06-06-core-owned-memory-shape.md
Sources/ViewportBenchmarks/main.swift
.github/workflows/swift-ci.yml
docs/superpowers/verification/2026-06-06-core-owned-memory-shape.md
```

- [ ] **Step 7: Confirm working tree state**

Run:

```bash
git status --short
```

Expected: no modified tracked files from Slice 7. The untracked `docs/superpowers/reviews/2026-06-06-slice-6-post-slice-review.md` may still be present and must remain uncommitted unless the user asks.
