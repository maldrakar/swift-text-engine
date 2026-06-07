# RSS Memory Observation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a host-only RSS observation diagnostic to `ViewportBenchmarks`, run it in CI without RSS budgets, and record verification evidence.

**Architecture:** `TextEngineCore` remains unchanged. `ViewportBenchmarks` gains a separate `--memory-observation` mode in a new focused diagnostic file that reuses the existing memory-shape scenarios, captures Darwin RSS snapshots, preserves measured object lifetimes through the post-operation snapshot, and prints key-value summaries. GitHub Actions runs the new command after the deterministic `--memory-shape` diagnostic but does not parse RSS values or enforce memory thresholds.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, Swift standard library, `TextEngineCore`, `ViewportBenchmarks`, Darwin Mach `task_info`, GitHub Actions, ripgrep, git.

---

## Source Design

Implement the approved Slice 9 design:

```text
docs/superpowers/specs/2026-06-07-rss-memory-observation-design.md
```

The repository may contain this untracked Slice 8 post-slice review:

```text
docs/superpowers/reviews/2026-06-06-slice-8-post-slice-review.md
```

Leave that file untracked unless the user explicitly asks to add it.

## Scope Check

This plan covers one subsystem: the host-only `ViewportBenchmarks` executable and one CI workflow step.

Do not modify:

```text
Sources/TextEngineCore
Tests
Package.swift
```

Do not add:

```text
RSS hard budgets
malloc or allocator statistics
realistic-provider latency budgets
new production storage adapters
variable-height layout
GitHub rulesets or branch protection
iOS, WASM, or embedded WASM support for ViewportBenchmarks
```

## File Structure

Create:

```text
Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
docs/superpowers/verification/2026-06-07-rss-memory-observation.md
```

Modify:

```text
Sources/ViewportBenchmarks/BenchmarkOptions.swift
Sources/ViewportBenchmarks/BenchmarkProgram.swift
Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
.github/workflows/swift-ci.yml
```

Final responsibility map:

```text
BenchmarkOptions.swift
  BenchmarkMode.memoryObservation
  --memory-observation parsing
  invalid memory-observation flag combinations
  usage text

BenchmarkProgram.swift
  dispatch .memoryObservation to runMemoryObservationDiagnostics()

SyntheticBenchmarks.swift
  precondition branch for .memoryObservation in synthetic mode switch

MemoryObservationDiagnostics.swift
  Darwin RSS snapshot helper
  memory observation scenarios
  memory observation summary values
  deterministic fixed-height operation
  explicit lifetime retention around measured objects
  key-value formatting
  diagnostic runner

.github/workflows/swift-ci.yml
  observational CI step after Run memory shape diagnostic
```

## Task 1: Preflight And Failing CLI Check

**Files:**
- Read: `docs/superpowers/specs/2026-06-07-rss-memory-observation-design.md`
- Read: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Read: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- Read: `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`
- Read: `.github/workflows/swift-ci.yml`
- Read: `git status --short`

- [ ] **Step 1: Confirm the approved Slice 9 spec is present**

Run:

```bash
rg -n "RSS Memory Observation Design|--memory-observation|rss_page_size_bytes|withExtendedLifetime|All four invalid" docs/superpowers/specs/2026-06-07-rss-memory-observation-design.md
```

Expected: output includes all five patterns.

- [ ] **Step 2: Confirm the current CLI does not support the new flag**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-observation
```

Expected: command exits non-zero and output contains:

```text
error=unknown argument --memory-observation
```

- [ ] **Step 3: Confirm baseline host commands pass before implementation**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected:

- `swift test` exits `0`;
- `swift build -c release` exits `0`;
- `--memory-shape` prints three `mode=memory_shape` lines with `invariant=pass`.

- [ ] **Step 4: Confirm local RSS page size**

Run:

```bash
getconf PAGE_SIZE
```

Expected on the current Apple Silicon macOS host:

```text
16384
```

If this prints another positive value, continue and record the actual value in verification output. Do not hard-code `16384` into implementation logic.

- [ ] **Step 5: Check working tree and protect unrelated files**

Run:

```bash
git status --short
```

Expected: no tracked files are modified. This untracked file may be present and must remain uncommitted:

```text
?? docs/superpowers/reviews/2026-06-06-slice-8-post-slice-review.md
```

## Task 2: Add Memory-Observation CLI Contract And Diagnostic

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- Modify: `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- Modify: `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- Create: `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`

- [ ] **Step 1: Replace `BenchmarkOptions.swift` with the extended CLI contract**

Use `apply_patch` to update `Sources/ViewportBenchmarks/BenchmarkOptions.swift` so the file contains:

```swift
enum BenchmarkMode {
    case pipeline
    case rangeOnly
    case realisticProvider
    case memoryShape
    case memoryObservation

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
        case .memoryObservation:
            return "memory_observation"
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
    Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--memory-observation] [--help]

    Options:
      --range-only          Run only viewport range recompute benchmark.
      --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
      --realistic-provider  Run large-text provider benchmark without gate enforcement.
      --memory-shape        Run deterministic core-owned memory-shape diagnostics.
      --memory-observation  Run host RSS observation diagnostics.
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
                if mode == .memoryObservation {
                    return .failure("--memory-observation cannot be combined with --range-only")
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
                if mode == .memoryObservation {
                    return .failure("--memory-observation cannot be combined with --realistic-provider")
                }
                mode = .realisticProvider
            case "--memory-shape":
                if mode == .rangeOnly {
                    return .failure("--range-only cannot be combined with --memory-shape")
                }
                if mode == .realisticProvider {
                    return .failure("--realistic-provider cannot be combined with --memory-shape")
                }
                if mode == .memoryObservation {
                    return .failure("--memory-observation cannot be combined with --memory-shape")
                }
                mode = .memoryShape
            case "--memory-observation":
                if mode == .rangeOnly {
                    return .failure("--range-only cannot be combined with --memory-observation")
                }
                if mode == .realisticProvider {
                    return .failure("--realistic-provider cannot be combined with --memory-observation")
                }
                if mode == .memoryShape {
                    return .failure("--memory-shape cannot be combined with --memory-observation")
                }
                mode = .memoryObservation
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
        if mode == .memoryObservation && enforceGate {
            return .failure("--memory-observation cannot be combined with --gate")
        }

        return .run(BenchmarkOptions(mode: mode, enforceGate: enforceGate))
    }
}
```

- [ ] **Step 2: Update `BenchmarkProgram.swift` dispatch**

Use `apply_patch` to update `runBenchmarks(options:)` in `Sources/ViewportBenchmarks/BenchmarkProgram.swift`:

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
    case .memoryObservation:
        return runMemoryObservationDiagnostics()
    }
}
```

Keep `runProgram(arguments:)` unchanged.

- [ ] **Step 3: Update the synthetic benchmark mode switch**

Use `apply_patch` to add this branch inside the `switch mode` in `runScenario(_:mode:iterations:operationsPerSample:)` in `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`:

```swift
            case .memoryObservation:
                preconditionFailure("memory observation mode uses runMemoryObservationDiagnostics")
```

The complete switch should cover:

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
            case .memoryObservation:
                preconditionFailure("memory observation mode uses runMemoryObservationDiagnostics")
            }
```

- [ ] **Step 4: Create `MemoryObservationDiagnostics.swift`**

Use `apply_patch` to create `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift` with:

```swift
import Darwin
import TextEngineCore

struct MemoryObservationRSSSnapshot {
    let bytes: Int
    let pageSizeBytes: Int
}

struct MemoryObservationSummary {
    let providerName: String
    let scenarioName: String
    let lineCount: Int
    let documentBytes: Int?
    let visibleLines: Int?
    let bufferedLines: Int?
    let geometryLines: Int?
    let providerLines: Int?
    let missingLines: Int?
    let coreOwnedBytesModel: Int?
    let providerOwnedBytes: Int?
    let rssBaselineBytes: Int?
    let rssAfterProviderSetupBytes: Int?
    let rssAfterCoreOperationBytes: Int?
    let rssPageSizeBytes: Int?
    let rssProviderDeltaBytes: Int?
    let rssCoreOperationDeltaBytes: Int?
    let observationPasses: Bool
    let failureReason: String?
    let checksum: Int
}

func currentRSSSnapshot() -> MemoryObservationRSSSnapshot? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                reboundPointer,
                &count
            )
        }
    }

    let pageSizeBytes = Int(getpagesize())
    guard result == KERN_SUCCESS,
          info.resident_size > 0,
          pageSizeBytes > 0 else {
        return nil
    }

    return MemoryObservationRSSSnapshot(
        bytes: Int(info.resident_size),
        pageSizeBytes: pageSizeBytes
    )
}

func memoryObservationScenarios() -> [MemoryShapeScenario] {
    memoryShapeScenarios()
}

func memoryObservationFailureSummary(
    _ scenario: MemoryShapeScenario,
    reason: String,
    rssPageSizeBytes: Int? = nil
) -> MemoryObservationSummary {
    MemoryObservationSummary(
        providerName: scenario.providerKind.outputName,
        scenarioName: scenario.name,
        lineCount: scenario.lineCount,
        documentBytes: nil,
        visibleLines: nil,
        bufferedLines: nil,
        geometryLines: nil,
        providerLines: nil,
        missingLines: nil,
        coreOwnedBytesModel: nil,
        providerOwnedBytes: nil,
        rssBaselineBytes: nil,
        rssAfterProviderSetupBytes: nil,
        rssAfterCoreOperationBytes: nil,
        rssPageSizeBytes: rssPageSizeBytes,
        rssProviderDeltaBytes: nil,
        rssCoreOperationDeltaBytes: nil,
        observationPasses: false,
        failureReason: reason,
        checksum: -1
    )
}

func runMemoryObservationScenario(_ scenario: MemoryShapeScenario) -> MemoryObservationSummary {
    guard let baseline = currentRSSSnapshot() else {
        return memoryObservationFailureSummary(
            scenario,
            reason: "rss_unavailable",
            rssPageSizeBytes: Int(getpagesize())
        )
    }

    switch scenario.providerKind {
    case .synthetic:
        let source = SyntheticLineSource(lineCount: scenario.lineCount)
        guard let afterProviderSetup = currentRSSSnapshot() else {
            return memoryObservationFailureSummary(
                scenario,
                reason: "rss_unavailable",
                rssPageSizeBytes: baseline.pageSizeBytes
            )
        }

        return withExtendedLifetime(source) {
            runMemoryObservationOperation(
                scenario,
                source: source,
                baseline: baseline,
                afterProviderSetup: afterProviderSetup,
                providerOwnedBytes: 0,
                documentBytes: nil
            ) { checksum, content in
                checksum &+= content
            }
        }
    case .largeText:
        guard let lineBytes = scenario.lineBytes else {
            return memoryObservationFailureSummary(
                scenario,
                reason: "missing_line_bytes",
                rssPageSizeBytes: baseline.pageSizeBytes
            )
        }

        let storage = RealisticDocumentStorage(lineCount: scenario.lineCount, lineBytes: lineBytes)
        let source = RealisticLineSource(storage: storage)
        guard let afterProviderSetup = currentRSSSnapshot() else {
            return memoryObservationFailureSummary(
                scenario,
                reason: "rss_unavailable",
                rssPageSizeBytes: baseline.pageSizeBytes
            )
        }

        return withExtendedLifetime(storage) {
            withExtendedLifetime(source) {
                runMemoryObservationOperation(
                    scenario,
                    source: source,
                    baseline: baseline,
                    afterProviderSetup: afterProviderSetup,
                    providerOwnedBytes: storage.documentBytes,
                    documentBytes: storage.documentBytes
                ) { checksum, content in
                    checksum &+= content.byteOffset
                    checksum &+= content.byteLength
                    checksum &+= content.firstByte
                    checksum &+= content.middleByte
                    checksum &+= content.lastByte
                }
            }
        }
    }
}

func runMemoryObservationOperation<Source: DocumentLineSource>(
    _ scenario: MemoryShapeScenario,
    source: Source,
    baseline: MemoryObservationRSSSnapshot,
    afterProviderSetup: MemoryObservationRSSSnapshot,
    providerOwnedBytes: Int,
    documentBytes: Int?,
    foldLineContent: (inout Int, Source.Line) -> Void
) -> MemoryObservationSummary {
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
    let coreOwnedBytesModel = coreOwnedBytesEstimate()

    switch ViewportVirtualizer.compute(input) {
    case let .success(range):
        let visibleLines = range.visibleEndExclusive - range.visibleStart
        let bufferedLines = range.bufferEndExclusive - range.bufferStart
        let expectedVisibleLines = expectedMemoryShapeVisibleLines(scenario)
        let expectedBufferedLines = expectedMemoryShapeBufferedLines(scenario)
        let rangePasses = memoryShapeRangeIsOrderedAndBounded(range, lineCount: scenario.lineCount)
        let geometry = countGeometryLines(range: range, lineHeight: scenario.lineHeight)
        let provider = countProviderLines(range: range, source: source, foldLineContent: foldLineContent)

        let expectedProviderBytes: Int
        let providerBytesPasses: Bool
        switch scenario.providerKind {
        case .synthetic:
            expectedProviderBytes = 0
            providerBytesPasses = providerOwnedBytes == expectedProviderBytes && documentBytes == nil
        case .largeText:
            if let lineBytes = scenario.lineBytes {
                expectedProviderBytes = scenario.lineCount * lineBytes
            } else {
                expectedProviderBytes = -1
            }
            providerBytesPasses = providerOwnedBytes == expectedProviderBytes
                && documentBytes == expectedProviderBytes
        }

        let invariantPasses = rangePasses
            && visibleLines == expectedVisibleLines
            && bufferedLines == expectedBufferedLines
            && geometry.lineCount == expectedBufferedLines
            && provider.lineCount == expectedBufferedLines
            && provider.missingCount == 0
            && providerBytesPasses

        var operationChecksum = 0
        operationChecksum &+= scenario.lineCount
        operationChecksum &+= visibleLines
        operationChecksum &+= bufferedLines
        operationChecksum &+= geometry.checksum
        operationChecksum &+= provider.checksum
        operationChecksum &+= coreOwnedBytesModel
        operationChecksum &+= providerOwnedBytes

        let afterCoreOperation = withExtendedLifetime((source, range, geometry, provider, operationChecksum)) {
            currentRSSSnapshot()
        }

        guard let afterCoreOperation else {
            return memoryObservationFailureSummary(
                scenario,
                reason: "rss_unavailable",
                rssPageSizeBytes: baseline.pageSizeBytes
            )
        }

        let rssProviderDeltaBytes = afterProviderSetup.bytes - baseline.bytes
        let rssCoreOperationDeltaBytes = afterCoreOperation.bytes - afterProviderSetup.bytes
        var checksum = operationChecksum
        checksum &+= baseline.bytes
        checksum &+= afterProviderSetup.bytes
        checksum &+= afterCoreOperation.bytes
        checksum &+= afterCoreOperation.pageSizeBytes
        checksum &+= rssProviderDeltaBytes
        checksum &+= rssCoreOperationDeltaBytes

        return MemoryObservationSummary(
            providerName: scenario.providerKind.outputName,
            scenarioName: scenario.name,
            lineCount: scenario.lineCount,
            documentBytes: documentBytes,
            visibleLines: visibleLines,
            bufferedLines: bufferedLines,
            geometryLines: geometry.lineCount,
            providerLines: provider.lineCount,
            missingLines: provider.missingCount,
            coreOwnedBytesModel: coreOwnedBytesModel,
            providerOwnedBytes: providerOwnedBytes,
            rssBaselineBytes: baseline.bytes,
            rssAfterProviderSetupBytes: afterProviderSetup.bytes,
            rssAfterCoreOperationBytes: afterCoreOperation.bytes,
            rssPageSizeBytes: afterCoreOperation.pageSizeBytes,
            rssProviderDeltaBytes: rssProviderDeltaBytes,
            rssCoreOperationDeltaBytes: rssCoreOperationDeltaBytes,
            observationPasses: invariantPasses,
            failureReason: invariantPasses ? nil : "invariant_failed",
            checksum: checksum
        )
    case .failure:
        return memoryObservationFailureSummary(
            scenario,
            reason: "viewport_compute_failed",
            rssPageSizeBytes: baseline.pageSizeBytes
        )
    }
}

func formatMemoryObservationSummary(_ summary: MemoryObservationSummary) -> String {
    var output = "mode=\(BenchmarkMode.memoryObservation.outputName)"
    output += " provider=\(summary.providerName)"
    output += " scenario=\(summary.scenarioName)"
    output += " line_count=\(summary.lineCount)"
    if let documentBytes = summary.documentBytes {
        output += " document_bytes=\(documentBytes)"
    }
    if let visibleLines = summary.visibleLines {
        output += " visible_lines=\(visibleLines)"
    }
    if let bufferedLines = summary.bufferedLines {
        output += " buffered_lines=\(bufferedLines)"
    }
    if let geometryLines = summary.geometryLines {
        output += " geometry_lines=\(geometryLines)"
    }
    if let providerLines = summary.providerLines {
        output += " provider_lines=\(providerLines)"
    }
    if let missingLines = summary.missingLines {
        output += " missing_lines=\(missingLines)"
    }
    if let coreOwnedBytesModel = summary.coreOwnedBytesModel {
        output += " core_owned_bytes_model=\(coreOwnedBytesModel)"
    }
    if let providerOwnedBytes = summary.providerOwnedBytes {
        output += " provider_owned_bytes=\(providerOwnedBytes)"
    }
    if let rssBaselineBytes = summary.rssBaselineBytes {
        output += " rss_baseline_bytes=\(rssBaselineBytes)"
    }
    if let rssAfterProviderSetupBytes = summary.rssAfterProviderSetupBytes {
        output += " rss_after_provider_setup_bytes=\(rssAfterProviderSetupBytes)"
    }
    if let rssAfterCoreOperationBytes = summary.rssAfterCoreOperationBytes {
        output += " rss_after_core_operation_bytes=\(rssAfterCoreOperationBytes)"
    }
    if let rssPageSizeBytes = summary.rssPageSizeBytes {
        output += " rss_page_size_bytes=\(rssPageSizeBytes)"
    }
    if let rssProviderDeltaBytes = summary.rssProviderDeltaBytes {
        output += " rss_provider_delta_bytes=\(rssProviderDeltaBytes)"
    }
    if let rssCoreOperationDeltaBytes = summary.rssCoreOperationDeltaBytes {
        output += " rss_core_operation_delta_bytes=\(rssCoreOperationDeltaBytes)"
    }
    output += " observation=\(summary.observationPasses ? "pass" : "fail")"
    if let failureReason = summary.failureReason {
        output += " reason=\(failureReason)"
    }
    output += " checksum=\(summary.checksum)"
    return output
}

func runMemoryObservationDiagnostics() -> Bool {
    var passed = true

    for scenario in memoryObservationScenarios() {
        let summary = runMemoryObservationScenario(scenario)
        print(formatMemoryObservationSummary(summary))

        if !summary.observationPasses {
            passed = false
        }
    }

    return passed
}
```

- [ ] **Step 5: Run build to catch integration errors**

Run:

```bash
swift build -c release
```

Expected: command exits `0`.

- [ ] **Step 6: Run the new diagnostic**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-observation
```

Expected: command exits `0` and prints exactly three `mode=memory_observation` lines in this order:

```text
provider=synthetic scenario=100k_lines_80_visible_overscan_5
provider=synthetic scenario=1m_lines_80_visible_overscan_5
provider=large_text scenario=100k_lines_10mb_text
```

Each line must include:

```text
core_owned_bytes_model=74
rss_page_size_bytes=
observation=pass
checksum=
```

The realistic line must include:

```text
document_bytes=11200000
provider_owned_bytes=11200000
```

- [ ] **Step 7: Run invalid CLI combinations**

Run each command:

```bash
swift run -c release ViewportBenchmarks -- --memory-observation --gate
swift run -c release ViewportBenchmarks -- --memory-observation --range-only
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-observation --memory-shape
```

Expected: each command exits non-zero and prints `Usage: ViewportBenchmarks`.

Expected error lines:

```text
error=--memory-observation cannot be combined with --gate
error=--memory-observation cannot be combined with --range-only
error=--memory-observation cannot be combined with --realistic-provider
error=--memory-observation cannot be combined with --memory-shape
```

- [ ] **Step 8: Run existing modes to verify behavior is preserved**

Run:

```bash
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
```

Expected:

- default benchmark prints three `mode=pipeline` lines;
- range-only benchmark prints three `mode=range_only` lines;
- gate benchmark prints three `mode=pipeline` lines with `gate=pass`;
- realistic-provider benchmark prints one `mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text` line;
- memory-shape diagnostic prints three `mode=memory_shape` lines with `invariant=pass`;
- existing output keys and scenario names are unchanged except for natural latency values.

- [ ] **Step 9: Commit the source changes**

Run:

```bash
git add Sources/ViewportBenchmarks/BenchmarkOptions.swift Sources/ViewportBenchmarks/BenchmarkProgram.swift Sources/ViewportBenchmarks/SyntheticBenchmarks.swift Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
git commit -m "feat: add rss memory observation diagnostic"
```

Expected: commit includes only the four `Sources/ViewportBenchmarks` files.

## Task 3: Add CI Workflow Step

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Add RSS observation after memory shape**

Use `apply_patch` to add this step after `Run memory shape diagnostic`:

```yaml
      - name: Run RSS memory observation diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-observation
```

The resulting workflow tail should be:

```yaml
      - name: Run synthetic benchmark gate
        run: swift run -c release ViewportBenchmarks -- --gate

      - name: Run memory shape diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-shape

      - name: Run RSS memory observation diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-observation
```

- [ ] **Step 2: Verify workflow scan**

Run:

```bash
rg -n "Host tests and benchmark gate|Run memory shape diagnostic|Run RSS memory observation diagnostic|--memory-observation" .github/workflows/swift-ci.yml
```

Expected output includes:

```text
name: Host tests and benchmark gate
Run memory shape diagnostic
Run RSS memory observation diagnostic
swift run -c release ViewportBenchmarks -- --memory-observation
```

- [ ] **Step 3: Run the CI command locally**

Run:

```bash
swift run -c release ViewportBenchmarks -- --memory-observation
```

Expected: command exits `0` with three `mode=memory_observation` lines and no RSS budget fields.

- [ ] **Step 4: Commit the workflow change**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: run rss memory observation"
```

Expected: commit includes only `.github/workflows/swift-ci.yml`.

## Task 4: Record Slice 9 Verification

**Files:**
- Create: `docs/superpowers/verification/2026-06-07-rss-memory-observation.md`

- [ ] **Step 1: Run verification commands and capture output**

Run each command and capture output for the verification record:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
swift run -c release ViewportBenchmarks -- --memory-observation --gate
swift run -c release ViewportBenchmarks -- --memory-observation --range-only
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-observation --memory-shape
rg -n "Run memory shape diagnostic|Run RSS memory observation diagnostic|--memory-observation" .github/workflows/swift-ci.yml
git diff -- Sources/TextEngineCore Tests Package.swift
```

Expected:

- host tests pass;
- release build passes;
- all existing valid benchmark modes pass;
- `--memory-observation` passes with three `observation=pass` lines;
- all four invalid `--memory-observation` combinations exit non-zero with clear errors;
- workflow scan shows the new CI step;
- non-goal diff check has no output.

- [ ] **Step 2: Create the verification document**

Create `docs/superpowers/verification/2026-06-07-rss-memory-observation.md` with this structure and populate each command section with the exact output observed in Step 1:

```markdown
# RSS Memory Observation Verification

Date: 2026-06-07

## Scope

Slice 9 adds a host-only `--memory-observation` diagnostic to `ViewportBenchmarks`, records Darwin RSS snapshots for the existing memory-shape scenario set, and runs the command in GitHub Actions without RSS budgets.

## Changed Source Files

- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`
- `.github/workflows/swift-ci.yml`

## Non-Goal Checks

The slice did not change:

- `Sources/TextEngineCore`
- `Tests`
- `Package.swift`

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

### RSS Memory Observation Diagnostic

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass.

### Invalid RSS Observation Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --gate
```

Result: expected non-zero exit with `error=--memory-observation cannot be combined with --gate`.

### Invalid RSS Observation Range-Only Combination

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --range-only
```

Result: expected non-zero exit with `error=--memory-observation cannot be combined with --range-only`.

### Invalid RSS Observation Realistic-Provider Combination

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
```

Result: expected non-zero exit with `error=--memory-observation cannot be combined with --realistic-provider`.

### Invalid RSS Observation Memory-Shape Combination

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --memory-shape
```

Result: expected non-zero exit with `error=--memory-observation cannot be combined with --memory-shape`.

### Workflow Scan

Command:

```text
rg -n "Run memory shape diagnostic|Run RSS memory observation diagnostic|--memory-observation" .github/workflows/swift-ci.yml
```

Result: workflow runs memory shape before RSS memory observation.

### Non-Goal Diff Check

Command:

```text
git diff -- Sources/TextEngineCore Tests Package.swift
```

Result: no output.

## RSS Interpretation

RSS is page-granular process-level evidence. The diagnostic records `rss_page_size_bytes` and does not treat RSS deltas as exact proof of the `core_owned_bytes_model` value.

## Conclusion

Slice 9 adds observational RSS evidence while preserving existing fixed-height benchmark and memory-shape behavior. The command is CI-visible but not a hard RSS budget.
```

For each command section, add the exact command output below the `Result:` sentence in a fenced `text` block. Use actual output from Step 1; do not invent latency, checksum, RSS, or page-size values.

- [ ] **Step 3: Verify the verification document has no incomplete markers**

Run:

```bash
rg -n "REPLACE_WITH|COPY_OUTPUT_HERE|INSERT_OUTPUT|LATENCY_NUMBER|RSS_NUMBER|CHECKSUM_NUMBER|PAGE_SIZE_NUMBER" docs/superpowers/verification/2026-06-07-rss-memory-observation.md
```

Expected: no output.

- [ ] **Step 4: Commit the verification document**

Run:

```bash
git add docs/superpowers/verification/2026-06-07-rss-memory-observation.md
git commit -m "docs: record rss memory observation verification"
```

Expected: commit includes only the new verification document.

## Task 5: Final Slice 9 Audit

**Files:**
- Read: `Sources/ViewportBenchmarks/*.swift`
- Read: `.github/workflows/swift-ci.yml`
- Read: `docs/superpowers/verification/2026-06-07-rss-memory-observation.md`
- Read: `git status --short`
- Read: `git log --oneline -6`

- [ ] **Step 1: Confirm final working tree state**

Run:

```bash
git status --short
```

Expected: no tracked files remain modified. This untracked file may still appear:

```text
?? docs/superpowers/reviews/2026-06-06-slice-8-post-slice-review.md
```

- [ ] **Step 2: Confirm recent commits show Slice 9 source, CI, and verification**

Run:

```bash
git log --oneline -6
```

Expected: recent history includes:

```text
feat: add rss memory observation diagnostic
ci: run rss memory observation
docs: record rss memory observation verification
docs: plan rss memory observation
docs: design rss memory observation
```

Exact hashes may differ.

- [ ] **Step 3: Confirm non-goal paths are unchanged across Slice 9 implementation**

Run:

```bash
git diff HEAD~3..HEAD -- Sources/TextEngineCore Tests Package.swift
```

Expected: no output.

- [ ] **Step 4: Confirm `main.swift` remains process entry only**

Run:

```bash
sed -n '1,80p' Sources/ViewportBenchmarks/main.swift
```

Expected output remains:

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

- [ ] **Step 5: Confirm RSS observation file owns the new host-specific code**

Run:

```bash
rg -n "task_info|mach_task_basic_info|getpagesize|withExtendedLifetime|rss_page_size_bytes|core_owned_bytes_model" Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift
```

Expected: all six patterns are present in `MemoryObservationDiagnostics.swift`.

- [ ] **Step 6: Prepare post-slice review prompt**

After implementation and verification are committed, request a post-slice review that covers:

```text
docs/initial-project-brief.md
docs/superpowers/specs/2026-06-07-rss-memory-observation-design.md
docs/superpowers/plans/2026-06-07-rss-memory-observation.md
Sources/ViewportBenchmarks/*.swift
.github/workflows/swift-ci.yml
docs/superpowers/verification/2026-06-07-rss-memory-observation.md
git commit history for Slice 9
```

Expected review focus:

- RSS interpretation is not overstated as exact core-owned memory proof;
- `--memory-shape` output stays unchanged;
- measured objects stay alive through post-operation RSS snapshots;
- scenario order keeps the realistic provider last;
- all invalid CLI combinations are verified;
- `TextEngineCore`, tests, and `Package.swift` remain unchanged.
