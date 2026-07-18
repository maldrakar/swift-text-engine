# Absolute Product Budget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fixed, never-recalibrated absolute product ceiling (10% of a 60 FPS frame = 1,666,666 ns) that fails the gate when a **frame-hot-path** operation's observed p99 exceeds it, catching the slow drift a median-anchored regression budget structurally re-derives around.

**Architecture:** A `BenchmarkMode.isFrameHotPath` classifier (exhaustive switch, `false` only for `.bulkStructuralMutation`) scopes the ceiling to per-frame operations; bulk multi-line edits are discrete, possibly multi-frame user actions and stay gated on their regression budget only. Two `GateLimits` constants express the frame math; one mode-gated condition inside `BenchmarkSummary.gateFailureReason` returns a new `budgetAbsoluteExceeded` reason; the gate output line grows keyed tokens (`budget_absolute_p99_ns=` / `headroom_absolute_p99=`, or `=exempt` for bulk); and a `GateFloorTests` standing invariant proves every frame-hot-path regression p99 budget stays under the ceiling. No engine, provider, corpus, or budget-literal change — all 45 gate checksums stay byte-identical.

**Tech Stack:** Swift 6.0 / XCTest (`ViewportBenchmarks` executable target + `ViewportBenchmarksTests`). Benchmark target is Foundation-free; tests may use Foundation (already do).

## Global Constraints

Copied verbatim from the spec and AGENTS.md hard constraints. Every task's requirements implicitly include this section.

- **Zero change to `Sources/TextEngineCore` or `Sources/TextEngineReferenceProviders`.** `git diff --name-only main` must show no path under either. Expected engine/provider diff: **zero lines**. `rg -n "Foundation" Sources/TextEngineCore` stays empty.
- **Zero change to any budget literal, the corpus, `.github/scripts/derive-gate-budgets.sh`, or any benchmark workload.** No harvest, no re-derivation. All **45** `--gate` checksums stay **byte-identical** to the Slice 42 baseline (main HEAD `5c775b8`).
- **No new benchmark mode, no new CI step, no `.github/workflows/swift-ci.yml` change** — `WorkflowShapeTests` stays green untouched.
- **The absolute ceiling is FIXED**: derived once from the frame math (`1_000_000_000 / 60 / 10`), never corpus-derived, never recalibrated. It applies to frame-hot-path modes only; `bulk_structural_mutation` is exempt.
- **One logical step per commit**, conventional-commit prefixes (`feat:`, `test:`, `docs:`).
- Branch: `slice-43-absolute-product-budget` (already created; spec already committed there as `9fcb95d`).

---

### Task 1: `BenchmarkMode.isFrameHotPath` classifier + exclusion pin

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (add `isFrameHotPath` after `isGateable`, ~line 85)
- Test: `Tests/ViewportBenchmarksTests/GateLogicTests.swift` (add one test)

**Interfaces:**
- Produces: `BenchmarkMode.isFrameHotPath: Bool` — `false` for exactly `.bulkStructuralMutation`, `true` for every other case. Consumed by Task 3 (the mode-gated check), Task 4 (token emission), Task 5 (floor filter).

- [ ] **Step 1: Write the failing test**

Add to `GateLogicTests` (inside the `final class GateLogicTests: XCTestCase { ... }` body):

```swift
    // The absolute ceiling applies to frame-hot-path modes only. Bulk multi-line edits
    // are a discrete, possibly multi-frame user action, not a scroll-frame op, so they
    // are exempt. Pin the excluded set so the exemption cannot silently widen: an
    // exhaustive switch forces a new mode to classify itself, and this asserts the only
    // gated mode that opts out is bulk_structural_mutation.
    func testFrameHotPathExclusionsAreExactlyDocumented() {
        let excluded = Set(
            BenchmarkMode.allCases
                .filter { $0.isGateable && !$0.isFrameHotPath }
                .map(\.outputName))
        XCTAssertEqual(excluded, ["bulk_structural_mutation"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GateLogicTests`
Expected: **compile failure** — `value of type 'BenchmarkMode' has no member 'isFrameHotPath'`. (A missing property is a build error; that is the red state for an added-property TDD step.)

- [ ] **Step 3: Write minimal implementation**

In `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, immediately after the `isGateable` computed property (after its closing `}` at ~line 85, still inside `enum BenchmarkMode`), add:

```swift

    // Whether the absolute product ceiling (GateLimits.absoluteP99Nanoseconds) applies to
    // this mode. Frame-hot-path operations run inside the 60 FPS scroll/keystroke loop --
    // viewport compute, incremental recompute after a single edit, and every
    // position/geometry query -- so they must fit well within a frame.
    // bulk_structural_mutation inserts/removes thousands of lines in one operation (a
    // large paste or range delete): a discrete user action that may legitimately span
    // more than one frame, NOT on the scroll path. Its hosted p99 (~570us) and
    // median-derived regression budgets (3-5.8ms) sit ABOVE a 10%-frame ceiling, so it is
    // gated on its regression budget only and exempt here.
    //
    // Exhaustive switch, never a deny-list -- the same discipline as isGateable: a new
    // mode must classify itself, so it cannot silently inherit the ceiling or silently
    // escape it. testFrameHotPathExclusionsAreExactlyDocumented pins the excluded set.
    var isFrameHotPath: Bool {
        switch self {
        case .bulkStructuralMutation:
            return false
        case .pipeline,
             .rangeOnly,
             .realisticProvider,
             .variableHeight,
             .variableHeightMutation,
             .structuralMutation,
             .lineQuery,
             .lineGeometryQuery,
             .columnQuery,
             .columnGeometryQuery,
             .pointQuery,
             .pointGeometryQuery,
             .memoryShape,
             .memoryObservation:
            return true
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GateLogicTests`
Expected: PASS (all existing GateLogicTests plus `testFrameHotPathExclusionsAreExactlyDocumented`).

- [ ] **Step 5: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkOptions.swift Tests/ViewportBenchmarksTests/GateLogicTests.swift
git commit -m "feat: add BenchmarkMode.isFrameHotPath classifier (bulk exempt)"
```

---

### Task 2: `GateLimits` frame constants + derivation pin

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift` (add two constants inside `enum GateLimits`, after `maxHeadroomP99` at ~line 57)
- Test: `Tests/ViewportBenchmarksTests/GateLogicTests.swift` (add one test)

**Interfaces:**
- Produces: `GateLimits.frameNanoseconds: Int64 == 16_666_666` and `GateLimits.absoluteP99Nanoseconds: Int64 == 1_666_666`. Consumed by Task 3 (the check), Task 4 (tokens), Task 5 (floor invariant).

- [ ] **Step 1: Write the failing test**

Add to `GateLogicTests`:

```swift
    // The absolute ceiling is data, not logic: pin it to the frame math so it cannot be
    // silently changed or accidentally corpus-derived. FIXED, never recalibrated.
    func testAbsoluteCeilingIsTenPercentOfFrame() {
        XCTAssertEqual(GateLimits.frameNanoseconds, 1_000_000_000 / 60)
        XCTAssertEqual(GateLimits.frameNanoseconds, 16_666_666)
        XCTAssertEqual(GateLimits.absoluteP99Nanoseconds, GateLimits.frameNanoseconds / 10)
        XCTAssertEqual(GateLimits.absoluteP99Nanoseconds, 1_666_666)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GateLogicTests`
Expected: **compile failure** — `type 'GateLimits' has no member 'frameNanoseconds'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/ViewportBenchmarks/BenchmarkModels.swift`, inside `enum GateLimits`, after the `maxHeadroomP99` declaration (after line 57, before the closing `}` of `GateLimits`), add:

```swift

    // The absolute PRODUCT ceiling -- a distinct axis from the regression band above.
    // The brief's success criterion is 60 FPS, "p95/p99 latency для пересчёта viewport".
    // A core frame operation must fit well within a frame, so the ceiling is 10% of a
    // 60 FPS frame, leaving the remainder for shaping/rasterization/UI outside the
    // headless core.
    //
    // FIXED: never recalibrated, never corpus-derived. A regression budget is anchored to
    // a moving median and can be legitimately re-derived looser slice by slice; this
    // ceiling is the fixed product target that catches the slow drift a regression budget
    // re-derives around. On breach the response is to fix the code/architecture, NEVER to
    // loosen the ceiling (contrast budget_stale, which says re-derive the budget). See
    // AGENTS.md "## Gate budgets".
    //
    // Applies to frame-hot-path modes only (BenchmarkMode.isFrameHotPath): bulk multi-line
    // edits are discrete, possibly multi-frame user actions and are exempt. GateLogicTests
    // pins this frame math; GateFloorTests pins that every frame-hot-path regression p99
    // budget stays under this ceiling.
    static let frameNanoseconds: Int64 = 1_000_000_000 / 60          // 16_666_666 (60 FPS)
    static let absoluteP99Nanoseconds: Int64 = frameNanoseconds / 10 // 1_666_666 (10% of a frame)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GateLogicTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkModels.swift Tests/ViewportBenchmarksTests/GateLogicTests.swift
git commit -m "feat: add GateLimits frame + absolute p99 ceiling constants"
```

---

### Task 3: `budgetAbsoluteExceeded` reason + mode-gated check

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift` (add enum case ~line 63; add one condition inside `gateFailureReason` after the `budgetExceeded` return, ~line 111)
- Test: `Tests/ViewportBenchmarksTests/GateLogicTests.swift` (parameterize the `summary` helper; add four tests)

**Interfaces:**
- Consumes: `BenchmarkMode.isFrameHotPath` (Task 1), `GateLimits.absoluteP99Nanoseconds` (Task 2).
- Produces: `GateFailureReason.budgetAbsoluteExceeded` (rawValue `"budget_absolute_exceeded"`); `gateFailureReason` now returns it for a frame-hot-path summary whose regression budget passes but whose observed p99 exceeds the ceiling. Precedence: `budgetExceeded` outranks it; it outranks `budgetStale`.

- [ ] **Step 1: Write the failing tests**

First, parameterize the private `summary` helper at the top of `GateLogicTests.swift` — add a `mode` parameter defaulting to `.lineQuery` so every existing caller is unchanged. Replace the current helper signature/body:

```swift
private func summary(
    mode: BenchmarkMode = .lineQuery,
    p95: Int64,
    p99: Int64,
    budgetP95: Int64?,
    budgetP99: Int64?,
    failures: Int = 0
) -> BenchmarkSummary {
    BenchmarkSummary(
        mode: mode,
        providerName: "uniform",
        scenarioName: "test",
        iterations: 1,
        operationsPerSample: 1,
        lineCount: 1_000,
        documentBytes: nil,
        lineBytes: nil,
        p95Nanoseconds: p95,
        p99Nanoseconds: p99,
        checksum: 0,
        failureCount: failures,
        p95BudgetNanoseconds: budgetP95,
        p99BudgetNanoseconds: budgetP99
    )
}
```

Then add these four tests to `GateLogicTests`:

```swift
    // The reason this slice exists: a frame-hot-path op blows the 60 FPS frame while its
    // (legitimately re-derived, looser) regression budget still PASSES. The product gate
    // must catch it -- this is the slow drift the regression gate re-derives around.
    func testAbsoluteCeilingFiresForFrameHotPathMode() {
        let obsP99 = GateLimits.absoluteP99Nanoseconds + 1  // one ns over the frame ceiling
        let s = summary(
            mode: .structuralMutation,
            p95: 100_000, p99: obsP99,
            budgetP95: 300_000, budgetP99: obsP99 + 100_000)  // regression budget passes
        XCTAssertEqual(s.gateFailureReason, .budgetAbsoluteExceeded)
    }

    // The same latency/budget shape on a non-hot-path (bulk) mode must NOT fire it: bulk
    // is exempt from the frame ceiling and gated on its regression budget alone.
    func testAbsoluteCeilingDoesNotFireForBulkMode() {
        let obsP99 = GateLimits.absoluteP99Nanoseconds + 1
        let s = summary(
            mode: .bulkStructuralMutation,
            p95: 100_000, p99: obsP99,
            budgetP95: 300_000, budgetP99: obsP99 + 100_000)
        XCTAssertNil(s.gateFailureReason)
    }

    // budget_exceeded outranks the product reason: code that broke even the regression
    // budget reports the familiar regression failure, not the product one.
    func testBudgetExceededOutranksAbsoluteCeiling() {
        let obsP99 = GateLimits.absoluteP99Nanoseconds + 1
        let s = summary(
            mode: .structuralMutation,
            p95: 100_000, p99: obsP99,
            budgetP95: 300_000, budgetP99: obsP99 - 1)  // regression budget BROKEN
        XCTAssertEqual(s.gateFailureReason, .budgetExceeded)
    }

    // The absolute check must not mask a genuinely stale budget: when observed is tiny
    // (far under the ceiling) the reason stays budget_stale even for a hot-path mode.
    func testAbsoluteCeilingDoesNotMaskStaleBudget() {
        let s = summary(
            mode: .structuralMutation,
            p95: 20, p99: 40,
            budgetP95: 60_000, budgetP99: 120_000)  // ~3000x headroom -> stale
        XCTAssertEqual(s.gateFailureReason, .budgetStale)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GateLogicTests`
Expected: **compile failure** — `type 'GateFailureReason' has no member 'budgetAbsoluteExceeded'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/ViewportBenchmarks/BenchmarkModels.swift`:

(a) Add the case to `GateFailureReason` (place it after `budgetExceeded`):

```swift
enum GateFailureReason: String {
    case operationFailures = "operation_failures"
    case budgetExceeded = "budget_exceeded"
    case budgetAbsoluteExceeded = "budget_absolute_exceeded"
    case budgetStale = "budget_stale"
    case missingBudget = "missing_budget"
}
```

(b) In `gateFailureReason`, insert the mode-gated check immediately after the `budgetExceeded` return and before the headroom (`budgetStale`) block:

```swift
        if p95Nanoseconds > p95BudgetNanoseconds || p99Nanoseconds > p99BudgetNanoseconds {
            return .budgetExceeded
        }

        // The absolute PRODUCT ceiling, checked for frame-hot-path modes only (bulk edits
        // are discrete, possibly multi-frame actions -- exempt). It sits between
        // budgetExceeded and budgetStale on purpose: across the frame-hot-path set every
        // regression p99 budget is <= 580us < the 1.67ms ceiling (GateFloorTests pins
        // this), so exceeding the ceiling always also exceeds the regression budget and a
        // plain regression already reported budget_exceeded above. This therefore fires
        // ONLY when the regression budget passes but the frame is blown -- the slow drift a
        // re-derived regression budget cannot catch. It never masks budget_stale, which
        // needs a tiny observed (huge headroom) where this check is silent.
        if mode.isFrameHotPath, p99Nanoseconds > GateLimits.absoluteP99Nanoseconds {
            return .budgetAbsoluteExceeded
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GateLogicTests`
Expected: PASS (all prior tests plus the four new ones).

- [ ] **Step 5: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkModels.swift Tests/ViewportBenchmarksTests/GateLogicTests.swift
git commit -m "feat: fail gate on frame-hot-path absolute p99 ceiling breach"
```

---

### Task 4: Gate output tokens (`budget_absolute_p99_ns` / `headroom_absolute_p99`; `exempt` for bulk)

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift` (add `headroomAbsoluteP99` computed property on `BenchmarkSummary`, ~after `headroomP99` at line 96)
- Modify: `Sources/ViewportBenchmarks/BenchmarkSupport.swift` (add token emission in the `includeGate` block of `formatSummary`, after the `headroom_p99` line at line 123, before `gate=` at line 124)
- Test: `Tests/ViewportBenchmarksTests/GateLogicTests.swift` (add three tests)

**Interfaces:**
- Consumes: `BenchmarkMode.isFrameHotPath` (Task 1), `GateLimits.absoluteP99Nanoseconds` (Task 2).
- Produces: `BenchmarkSummary.headroomAbsoluteP99: Double` (non-optional; `.infinity` when `p99 == 0`). Gate output for a frame-hot-path mode grows ` budget_absolute_p99_ns=<n> headroom_absolute_p99=<h>x` between `headroom_p99=` and `gate=`; for a non-hot-path mode it grows ` budget_absolute_p99_ns=exempt` (no headroom token).

- [ ] **Step 1: Write the failing tests**

Add to `GateLogicTests`:

```swift
    // Frame-hot-path gate output carries the fixed ceiling and its headroom, positioned
    // after headroom_p99 and before gate=. 1666666 / 200000 = 8.33 -> "8.3x".
    func testGateOutputCarriesAbsoluteCeilingForFrameHotPath() {
        let line = formatSummary(
            summary(mode: .structuralMutation, p95: 100_000, p99: 200_000,
                    budgetP95: 300_000, budgetP99: 600_000),
            includeGate: true)
        XCTAssertTrue(line.contains(" budget_absolute_p99_ns=1666666"), line)
        XCTAssertTrue(line.contains(" headroom_absolute_p99=8.3x"), line)

        let tokens = line.split(separator: " ")
        guard let p99Index = tokens.firstIndex(where: { $0.hasPrefix("headroom_p99=") }),
              let absIndex = tokens.firstIndex(where: { $0.hasPrefix("budget_absolute_p99_ns=") }),
              let gateIndex = tokens.firstIndex(where: { $0.hasPrefix("gate=") }) else {
            XCTFail("expected headroom_p99, budget_absolute_p99_ns, and gate fields: \(line)")
            return
        }
        XCTAssertTrue(p99Index < absIndex, line)
        XCTAssertTrue(absIndex < gateIndex, line)
    }

    // Bulk is exempt: its gate line says so explicitly (a visible marker, not a silent
    // omission -- the repo's "no silent caps" discipline) and carries no absolute headroom.
    func testGateOutputMarksBulkExempt() {
        let line = formatSummary(
            summary(mode: .bulkStructuralMutation, p95: 400_000, p99: 900_000,
                    budgetP95: 2_900_000, budgetP99: 5_800_000),
            includeGate: true)
        XCTAssertTrue(line.contains(" budget_absolute_p99_ns=exempt"), line)
        XCTAssertFalse(line.contains("headroom_absolute_p99"), line)
        XCTAssertTrue(line.contains(" gate=pass"), line)
    }

    // Non-gate output is a separate contract and must not grow the absolute token.
    func testNonGateOutputHasNoAbsoluteToken() {
        let line = formatSummary(
            summary(mode: .structuralMutation, p95: 100_000, p99: 200_000,
                    budgetP95: 300_000, budgetP99: 600_000),
            includeGate: false)
        XCTAssertFalse(line.contains("budget_absolute_p99_ns"), line)
        XCTAssertFalse(line.contains("headroom_absolute_p99"), line)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GateLogicTests`
Expected: FAIL — `testGateOutputCarriesAbsoluteCeilingForFrameHotPath` and `testGateOutputMarksBulkExempt` fail their `XCTAssertTrue(... contains ...)` (the token is not emitted yet). `testNonGateOutputHasNoAbsoluteToken` passes trivially. (No compile error — `headroomAbsoluteP99` is only referenced in impl, added in Step 3.)

- [ ] **Step 3: Write minimal implementation**

(a) In `Sources/ViewportBenchmarks/BenchmarkModels.swift`, add a computed property on `BenchmarkSummary` immediately after `headroomP99` (after its closing `}` at line 96):

```swift

    // The absolute product ceiling's headroom: fixed ceiling / observed p99. Non-optional
    // (the ceiling always exists) and reuses the zero-observed guard, so p99 == 0 yields
    // .infinity rather than trapping. Only meaningful for frame-hot-path modes; the output
    // layer emits it for those and marks the rest exempt.
    var headroomAbsoluteP99: Double {
        BenchmarkSummary.headroom(budget: GateLimits.absoluteP99Nanoseconds, observed: p99Nanoseconds)
    }
```

(b) In `Sources/ViewportBenchmarks/BenchmarkSupport.swift`, in `formatSummary`'s `includeGate` block, insert between the `headroom_p99` line (line 123) and the `gate=` line (line 124):

```swift
        output += " headroom_p99=\(formatHeadroom(headroomP99))"
        if summary.mode.isFrameHotPath {
            output += " budget_absolute_p99_ns=\(GateLimits.absoluteP99Nanoseconds)"
            output += " headroom_absolute_p99=\(formatHeadroom(summary.headroomAbsoluteP99))"
        } else {
            // Visible marker, not a silent omission: a reader sees the ceiling was
            // deliberately not applied to this discrete multi-frame edit mode.
            output += " budget_absolute_p99_ns=exempt"
        }
        output += " gate=\(reason == nil ? "pass" : "fail")"
```

(Only the two `if`/`else` blocks are new; the `headroom_p99` and `gate=` lines already exist — shown for placement.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GateLogicTests`
Expected: PASS (all three new tests plus every existing GateLogicTests case, including `testNonGateOutputIsUnchanged` and `testGateOutputCarriesHeadroomP99`, which are unaffected).

- [ ] **Step 5: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkModels.swift Sources/ViewportBenchmarks/BenchmarkSupport.swift Tests/ViewportBenchmarksTests/GateLogicTests.swift
git commit -m "feat: emit absolute-ceiling gate tokens (exempt marker for bulk)"
```

---

### Task 5: `GateFloorTests` standing invariant — frame-hot-path budget under the ceiling

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (add `mode` field to `GatedBudget` ~line 121, thread it through `add` in `everyGatedBudget()` ~line 137, add one test to the `GateFloorTests` class)

**Interfaces:**
- Consumes: `BenchmarkMode.isFrameHotPath` (Task 1), `GateLimits.absoluteP99Nanoseconds` (Task 2), `everyGatedBudget()` (existing registry).
- Produces: `GatedBudget` grows a `mode: BenchmarkMode` field (additive; existing consumers `testEveryGatedBudgetKeepsP99AtLeastTwiceP95`, the floor/evidence tests, still compile unchanged since they read `.key`/`.p95`/`.p99`).

- [ ] **Step 1: Write the failing test**

First extend the `GatedBudget` struct (top-level in `GateFloorTests.swift`, ~line 121):

```swift
struct GatedBudget {
    let key: String
    let mode: BenchmarkMode
    let p95: Int64
    let p99: Int64
}
```

And thread `mode` through the `add` helper inside `everyGatedBudget()` (~line 137):

```swift
    func add(_ mode: BenchmarkMode, _ name: String, _ p95: Int64, _ p99: Int64) {
        budgets.append(GatedBudget(key: "\(mode.outputName)|\(name)", mode: mode, p95: p95, p99: p99))
    }
```

Then add the test to the `final class GateFloorTests: XCTestCase { ... }` body:

```swift
    // The runtime companion to Decision 4's ordering: the absolute product ceiling is
    // enforced at runtime for frame-hot-path modes, and this pins the static half -- every
    // frame-hot-path gated scenario's committed regression p99 budget must sit UNDER the
    // ceiling. If a budget crossed it, the absolute gate would fire on a clean tree (a
    // regression budget is >= its own observed latency, so budget < ceiling => observed <
    // ceiling with room). Bulk is filtered out here exactly as isFrameHotPath filters it
    // at runtime, so the two agree. Binding scenario: structural_mutation|1m (580us,
    // 2.87x under). This is the check that would have caught the original
    // bulk_structural_mutation batch_4096 collision (budgets 3ms / 5.8ms > the ceiling).
    func testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling() {
        let frameHotPath = everyGatedBudget().filter { $0.mode.isFrameHotPath }
        XCTAssertFalse(frameHotPath.isEmpty)

        for budget in frameHotPath {
            XCTAssertLessThan(
                budget.p99, GateLimits.absoluteP99Nanoseconds,
                "\(budget.key): regression p99 budget \(budget.p99) is at or above the "
                    + "absolute frame ceiling \(GateLimits.absoluteP99Nanoseconds) — the "
                    + "absolute gate would fire on a clean tree. Reclassify the mode as not "
                    + "frame-hot-path, raise the ceiling fraction (a conscious product "
                    + "decision), or accept the op is too slow for a frame.")
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Temporarily prove the guard is live: it must pass on the real tables, so to see red, run it once with a deliberately-too-low ceiling is NOT possible without editing the constant. Instead verify the test compiles and passes on the true budgets (the real committed tables all clear the ceiling because bulk is filtered out). Run:

Run: `swift test --filter GateFloorTests`
Expected: PASS. (This test cannot start red on the real tree — the tables already satisfy it once bulk is filtered. Its live-ness is proven in Task 7's guard-is-live demo, where lowering the ceiling reddens it. Adding the `mode` field first without the filter would be a no-op; the value comes from the filter + assertion together.)

If instead you see a **compile failure** (`value of type 'GatedBudget' has no member 'mode'`), the struct/`add` edits above were not applied — apply them, then re-run.

- [ ] **Step 3: (implementation already applied in Step 1)**

The struct field, the `add` threading, and the test are the whole change — there is no separate production code for this task. Confirm `git diff` shows only `GateFloorTests.swift`.

- [ ] **Step 4: Run the full test target to verify nothing regressed**

Run: `swift test --filter ViewportBenchmarksTests`
Expected: PASS — `testEveryGatedBudgetKeepsP99AtLeastTwiceP95` (reads `.p95`/`.p99`, unaffected by the new field) and every floor/evidence test still green.

- [ ] **Step 5: Commit**

```bash
git add Tests/ViewportBenchmarksTests/GateFloorTests.swift
git commit -m "test: pin every frame-hot-path budget under the absolute ceiling"
```

---

### Task 6: Document the absolute ceiling in `AGENTS.md`

**Files:**
- Modify: `AGENTS.md` (the `## Gate budgets` section)

**Interfaces:** none (docs only).

- [ ] **Step 1: Add the absolute-ceiling documentation**

In `AGENTS.md`, in the `## Gate budgets` section, after the paragraph introducing the regression band ("**The band**: floor 3x, ceilings ...") add a new subsection. Use exactly this content:

```markdown
**The absolute product ceiling** is a *second, distinct* gate axis, added in Slice 43.
The regression band above asks "slower than recent code?"; the absolute ceiling asks
"still fast enough for the 60 FPS frame?" — the brief's «превратить "60 FPS" в
измеримый headless budget». It is `GateLimits.absoluteP99Nanoseconds = 1_000_000_000 /
60 / 10 = 1_666_666` ns (10% of a 60 FPS frame), **FIXED**: never recalibrated, never
corpus-derived. On breach the gate reports `reason=budget_absolute_exceeded`, and the
response is to **fix the code/architecture — never loosen the ceiling** (contrast
`budget_stale`, which says re-derive the budget). It is checked against **p99 only**
(a passing p99 implies a passing p95 under a uniform ceiling).

It applies to **frame-hot-path** modes only — viewport compute, incremental recompute
after a single edit, and every position/geometry query — classified by the exhaustive
`BenchmarkMode.isFrameHotPath` switch. `bulk_structural_mutation` is **exempt**: a bulk
multi-line paste / range delete is a discrete user action that may span more than one
frame, not a scroll-frame op, so its gate line prints `budget_absolute_p99_ns=exempt`
and it stays gated on its regression budget alone. Two standing tests keep the axes
coherent: `GateLogicTests` pins the excluded set to exactly
`{bulk_structural_mutation}`, and `GateFloorTests` pins that **every frame-hot-path
regression p99 budget stays under the absolute ceiling** (binding scenario
`structural_mutation|1m`, 580 µs, 2.87× under) — so the runtime absolute gate can never
redden a clean tree.
```

- [ ] **Step 2: Verify the doc reads coherently**

Run: `grep -n "budget_absolute_exceeded\|isFrameHotPath\|absoluteP99Nanoseconds" AGENTS.md`
Expected: the new subsection's lines are present; no contradiction with the existing "two failure reasons are opposite instructions" paragraph (that paragraph still describes `budget_exceeded` vs `budget_stale`; the new axis is a third reason, described here).

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: document the absolute product ceiling in AGENTS.md"
```

---

### Task 7: Local verification record + guard-is-live demo

**Files:**
- Create: `docs/superpowers/verification/2026-07-18-absolute-product-budget.md`

**Interfaces:** none (records evidence).

- [ ] **Step 1: Run the full local verification and capture output**

Run each and capture verbatim:

```bash
swift test 2>&1 | tail -5
swift build -c release 2>&1 | tail -3
rg -n "Foundation" Sources/TextEngineCore ; echo "exit=$?"   # expect no matches, exit=1
git diff --name-only main -- Sources/TextEngineCore Sources/TextEngineReferenceProviders   # expect empty
```

Then every frame-hot-path gate mode (expect `gate=pass` and the `budget_absolute_p99_ns=1666666` token):

```bash
for m in "" "--realistic-provider" "--variable-height" "--variable-height-mutation" \
         "--structural-mutation" "--line-query" "--line-geometry-query" \
         "--column-query" "--column-geometry-query" "--point-query" "--point-geometry-query"; do
  echo "### $m --gate"
  swift run -c release ViewportBenchmarks -- $m --gate 2>&1 | grep -E "mode=|gate="
done
```

And bulk (expect `budget_absolute_p99_ns=exempt` and still `gate=pass`):

```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate 2>&1 | grep -E "mode=|gate="
```

- [ ] **Step 2: Guard-is-live demonstration**

Temporarily lower the ceiling below a frame-hot-path scenario's observed p99, show the red, revert:

```bash
# structural_mutation|1m observes ~40-58us p99 hosted; ~20us local. Lower the ceiling
# under that to force a breach on a clean tree.
sed -i.bak 's#frameNanoseconds / 10 #frameNanoseconds / 1000 #' Sources/ViewportBenchmarks/BenchmarkModels.swift
swift run -c release ViewportBenchmarks -- --structural-mutation --gate 2>&1 | grep -E "mode=|gate=|reason="
# expect: gate=fail reason=budget_absolute_exceeded on at least the 1m scenario
mv Sources/ViewportBenchmarks/BenchmarkModels.swift.bak Sources/ViewportBenchmarks/BenchmarkModels.swift
git diff --stat   # expect: clean, no change to tracked files
swift run -c release ViewportBenchmarks -- --structural-mutation --gate 2>&1 | grep -E "gate="   # back to gate=pass
```

(Choose `/ 1000` or whatever divisor puts the ceiling just under the local observed p99; record the actual observed p99 and the divisor used.)

- [ ] **Step 3: 45-checksum byte-identity check**

Capture every gated mode's `checksum=` and confirm byte-identical to the Slice 42 baseline (the verification doc records the 45-row table; compare against `docs/superpowers/verification/2026-07-18-shell-window-selection-guard.md` or the Slice 42 review's recorded table). Record the table in the new verification doc.

- [ ] **Step 4: Write the verification record**

Create `docs/superpowers/verification/2026-07-18-absolute-product-budget.md` with: the captured commands + outputs from Steps 1–3; the Foundation-free scan result; the engine/provider zero-diff proof; the frame-hot-path `gate=pass` lines showing `budget_absolute_p99_ns=1666666`; the bulk `=exempt` line; the guard-is-live red→revert→green transcript with the divisor and observed p99 recorded; and the 45-checksum byte-identity table. Leave a **Hosted CI** placeholder to be filled from the PR-head and post-merge `push` runs (AC8), anchored per the slice convention in the merged-code `push` run.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/verification/2026-07-18-absolute-product-budget.md
git commit -m "docs: record slice 43 local verification (absolute product budget)"
```

---

## Self-Review

**Spec coverage** (each AC → task):
- AC1 (`absoluteP99Nanoseconds == 1_666_666`, frame math, pinned) → Task 2.
- AC2 (`budget_absolute_exceeded` fires for hot-path only; bulk does not; precedence; non-masking) → Task 3.
- AC3 (`isFrameHotPath` false for exactly `{bulk_structural_mutation}`, pinned) → Task 1.
- AC4 (every frame-hot-path regression p99 budget under the ceiling, `GateFloorTests` invariant) → Task 5.
- AC5 (every hot-path `--gate` prints `budget_absolute_p99_ns=1666666` + `gate=pass`; bulk prints `=exempt` + `gate=pass`) → Task 4 (impl) + Task 7 (proof).
- AC6 (guard-is-live: lowered ceiling → `gate=fail reason=budget_absolute_exceeded`; reverts clean) → Task 7.
- AC7 (Foundation-free; no core/provider/corpus/budget/workflow change; 45 checksums byte-identical) → Global Constraints + Task 7.
- AC8 (hosted CI green, PR-head + post-merge) → post-merge, tracked in Task 7's verification-doc placeholder (follows the slice's hosted-proof convention).

Spec Decisions 1–5 all land: D1 (distinct axis, no staleness) → Task 2 comment + Task 3 ordering; D2 (uniform ceiling over frame-hot-path, bulk excluded, exhaustive switch) → Task 1; D3 (10% of frame, p99 only) → Task 2; D4 (fold into gate, ordering) → Task 3; D5 (standing invariant) → Task 5.

**Placeholder scan:** every code step shows complete code; no "TBD"/"handle edge cases"/"similar to". The only deferred item is AC8's hosted run IDs, which are genuinely post-merge and cannot exist at authoring time.

**Type consistency:** `isFrameHotPath` (Bool) used identically in Tasks 1/3/4/5; `absoluteP99Nanoseconds`/`frameNanoseconds` (Int64) consistent Tasks 2/3/4/5; `budgetAbsoluteExceeded` rawValue `"budget_absolute_exceeded"` used in Task 3 impl and asserted via `reason=budget_absolute_exceeded` in Task 7; `headroomAbsoluteP99` (Double) defined Task 4, used only in Task 4's `formatSummary`; `GatedBudget.mode` added Task 5, consumed only Task 5. `summary(mode:...)` default `.lineQuery` keeps all pre-existing GateLogicTests callers valid.

## Note on spec file-location detail

The spec's Implementation Architecture lists `isFrameHotPath` under `BenchmarkModels.swift`, but `BenchmarkMode` and its sibling `isGateable`/`outputName` live in `BenchmarkOptions.swift`. This plan places `isFrameHotPath` beside `isGateable` in `BenchmarkOptions.swift` (same file, same exhaustive-switch pattern). The spec's Scope/Impl references have been corrected to match.
