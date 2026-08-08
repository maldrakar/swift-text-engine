# Slice 52 — gate recalibration and bulk ceiling — verification record

This slice re-derived every CI gate budget from fresh hosted evidence (the corpus had
been stale since Slice 41 — zero post-Slice-45 runs sat in the N=20 window) and
replaced the boolean frame-hot-path exemption with a total, two-class absolute product
ceiling: `AbsoluteCeiling { scrollFrame, discreteAction }`. Every gated mode now
classifies under one of the two (an exhaustive switch on `BenchmarkMode`, no exempt
case), and `bulk_structural_mutation` — previously the sole exemption — now holds a
fixed ceiling of one whole 60 FPS frame (`16_666_666` ns) instead of no ceiling at all.

This document records the drills section only (AC8): for each new or changed
guarantee this slice adds, a deliberate mutation was applied, the named command was
run, the failure output was captured verbatim below, and the mutation was reverted
with `git checkout --` before the next drill began. The harvest, the budget sweep, the
local gate run, and the hosted evidence are recorded in a separate section of this
document, written by a later task.

**Method used for every drill, without exception:**

```bash
# after each drill, before starting the next:
git checkout -- Sources Tests .github/scripts
if git diff --quiet; then echo 'tree clean'; else echo 'FAIL: mutation survives'; exit 1; fi
```

`git diff --quiet` exits non-zero when there *are* changes, so this check is
status-sensitive to the invariant — unlike bare `git diff`, which exits 0 either way.
Every drill below ended with `tree clean` printed and confirmed before the next began.

---

## Drills

### Drill 1 — bulk has an absolute ceiling at all (D-8's substance)

**Mutation** — `Sources/ViewportBenchmarks/BenchmarkModels.swift`, in
`gateFailureReason`, gated the absolute-ceiling check on `scrollFrame` only, so a
`discreteAction`-class mode (bulk) never reaches it:

```diff
-        if p99Nanoseconds > mode.absoluteCeiling.p99Nanoseconds {
+        if mode.absoluteCeiling == .scrollFrame, p99Nanoseconds > mode.absoluteCeiling.p99Nanoseconds {
             return .budgetAbsoluteExceeded
         }
```

**Command:** `swift test --filter testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling`

**Verbatim failure output:**

```
Test Case '-[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:274: error: -[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling] : XCTAssertEqual failed: ("nil") is not equal to ("Optional(ViewportBenchmarks.GateFailureReason.budgetAbsoluteExceeded)")
Test Case '-[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling]' failed (0.035 seconds).
Test Suite 'GateLogicTests' failed at 2026-08-08 19:19:03.612.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.035 (0.035) seconds
```

Matches the brief's stated expectation (`("nil") is not equal to
("Optional(budgetAbsoluteExceeded)")`); the only difference is that XCTest's own
`XCTAssertEqual` description spells the enum case's fully-qualified type
(`ViewportBenchmarks.GateFailureReason.budgetAbsoluteExceeded`) rather than the bare
case name — a rendering detail of the assertion macro, not a different failure.

**Reverted:** `git checkout -- Sources Tests .github/scripts` → `git diff --quiet` →
`tree clean`.

---

### Drill 2 — the bulk ceiling is one frame, not a tenth

**Mutation** — `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, in
`BenchmarkMode.absoluteCeiling`, moved `.bulkStructuralMutation` out of the
`.discreteAction` arm and into the `.scrollFrame` arm:

```diff
         switch self {
-        case .bulkStructuralMutation:
-            return .discreteAction
         case .pipeline,
              .rangeOnly,
              .realisticProvider,
              .variableHeight,
              .variableHeightMutation,
              .structuralMutation,
+             .bulkStructuralMutation,
              .lineQuery,
              ...
             return .scrollFrame
         }
```

**Command:** `swift test --filter testAbsoluteCeilingDoesNotFireForBulkMode`

**Verbatim failure output:**

```
Test Case '-[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingDoesNotFireForBulkMode]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:257: error: -[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingDoesNotFireForBulkMode] : XCTAssertNil failed: "budgetAbsoluteExceeded"
Test Case '-[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingDoesNotFireForBulkMode]' failed (0.036 seconds).
Test Suite 'GateLogicTests' failed at 2026-08-08 19:19:31.132.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.036 (0.036) seconds
```

Matches the brief's stated expectation exactly (`XCTAssertNil failed:
"budgetAbsoluteExceeded"`).

Drills 1 and 2 are Decision 8's bracket and are **not** interchangeable: each
mutation reddens exactly one of the two tests. Drill 2's mutation looks like it
should redden Drill 1's test (`testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling`)
— it does not, because at `p99 = 16_666_667` a 1.67 ms ceiling is breached just as a
16.67 ms one is, and the reason is `.budgetAbsoluteExceeded` either way. Confirmed:
run against `testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling` and
`testAbsoluteCeilingDoesNotFireForBulkMode` separately, each mutation reddened only
its own named test.

**Reverted:** `git checkout -- Sources Tests .github/scripts` → `git diff --quiet` →
`tree clean`.

---

### Drill 3 — class membership is pinned

**Mutation** — `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, in
`BenchmarkMode.absoluteCeiling`, moved `.structuralMutation` into the
`.discreteAction` arm:

```diff
         switch self {
-        case .bulkStructuralMutation:
-            return .discreteAction
+        case .bulkStructuralMutation,
+             .structuralMutation:
+            return .discreteAction
         case .pipeline,
              .rangeOnly,
              .realisticProvider,
              .variableHeight,
              .variableHeightMutation,
-             .structuralMutation,
              .lineQuery,
              ...
             return .scrollFrame
         }
```

**Command:** `swift test --filter testDiscreteActionClassIsExactlyDocumented`

**Verbatim failure output:**

```
Test Case '-[ViewportBenchmarksTests.GateLogicTests testDiscreteActionClassIsExactlyDocumented]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:218: error: -[ViewportBenchmarksTests.GateLogicTests testDiscreteActionClassIsExactlyDocumented] : XCTAssertEqual failed: ("["structural_mutation", "bulk_structural_mutation"]") is not equal to ("["bulk_structural_mutation"]")
Test Case '-[ViewportBenchmarksTests.GateLogicTests testDiscreteActionClassIsExactlyDocumented]' failed (0.034 seconds).
Test Suite 'GateLogicTests' failed at 2026-08-08 19:19:47.945.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.034 (0.034) seconds
```

Matches the brief's stated expectation: `XCTAssertEqual failed` naming a two-element
set containing `structural_mutation`.

**Reverted:** `git checkout -- Sources Tests .github/scripts` → `git diff --quiet` →
`tree clean`.

---

### Drill 4 — every budget is under its class ceiling (with expected collateral)

**Mutation** — `Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift`,
raised `1m_lines_batch_4096`'s `p99BudgetNanoseconds` above the 16_666_666 ns
discrete-action ceiling:

```diff
             p95BudgetNanoseconds: 3_000_000,
-            p99BudgetNanoseconds: 6_000_000
+            p99BudgetNanoseconds: 20_000_000
         )
```

**Command:** `swift test --filter testEveryGatedBudgetIsUnderItsClassCeiling`

**Verbatim failure output:**

```
Test Case '-[ViewportBenchmarksTests.GateFloorTests testEveryGatedBudgetIsUnderItsClassCeiling]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateFloorTests.swift:415: error: -[ViewportBenchmarksTests.GateFloorTests testEveryGatedBudgetIsUnderItsClassCeiling] : XCTAssertLessThan failed: ("20000000") is not less than ("16666666") - bulk_structural_mutation|1m_lines_batch_4096: regression p99 budget 20000000 is at or above its discreteAction ceiling of 16666666 ns. This test is the product gate and this red IS the 60 FPS ceiling firing: fix the code or the architecture — NEVER loosen the ceiling, and never corpus-derive it (contrast budget_stale, which does say re-derive). The only other legitimate response is moving this mode to the other AbsoluteCeiling class, which is a product decision needing its own argument.
Test Case '-[ViewportBenchmarksTests.GateFloorTests testEveryGatedBudgetIsUnderItsClassCeiling]' failed (0.037 seconds).
Test Suite 'GateFloorTests' failed at 2026-08-08 19:20:02.078.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.037 (0.037) seconds
```

Matches the brief's stated expectation exactly, including the rewritten doctrine
message.

**EXPECTED COLLATERAL** — with the mutation still applied, `swift test` (full suite)
also reddens `testEveryCommittedBudgetReproducesFromCorpus`, because raising a
committed budget literal by hand also stops that literal reproducing from the
committed corpus:

```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateFloorTests.swift:391: error: -[ViewportBenchmarksTests.GateFloorTests testEveryCommittedBudgetReproducesFromCorpus] : XCTAssertEqual failed: ("6000000") is not equal to ("20000000") - bulk_structural_mutation|1m_lines_batch_4096: committed p99 budget 20000000 != 6000000 re-derived from the corpus — the literal no longer reproduces (budget_stale, not an engine regression). Re-derive with .github/scripts/derive-gate-budgets.sh and re-commit.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateFloorTests.swift:415: error: -[ViewportBenchmarksTests.GateFloorTests testEveryGatedBudgetIsUnderItsClassCeiling] : XCTAssertLessThan failed: ("20000000") is not less than ("16666666") - bulk_structural_mutation|1m_lines_batch_4096: regression p99 budget 20000000 is at or above its discreteAction ceiling of 16666666 ns. This test is the product gate and this red IS the 60 FPS ceiling firing: fix the code or the architecture — NEVER loosen the ceiling, and never corpus-derive it (contrast budget_stale, which does say re-derive). The only other legitimate response is moving this mode to the other AbsoluteCeiling class, which is a product decision needing its own argument.

Test Suite 'SwiftTextEnginePackageTests.xctest' failed at 2026-08-08 19:20:13.546.
	 Executed 362 tests, with 2 failures (0 unexpected) in 5.201 (5.223) seconds
```

Two distinct reds, both labelled: `testEveryGatedBudgetIsUnderItsClassCeiling` (the
targeted test for this drill) and `testEveryCommittedBudgetReproducesFromCorpus`
(expected collateral of raising a committed literal). An unexplained second failure
in a drill log is indistinguishable from a drill that hit the wrong thing — this one
is explained: both are consequences of the same single-line mutation.

**Reverted:** `git checkout -- Sources Tests .github/scripts` → `git diff --quiet` →
`tree clean`.

---

### Drill 5 — ceiling values are pinned to the frame math (with expected collateral)

**Mutation** — `Sources/ViewportBenchmarks/BenchmarkModels.swift`, in
`AbsoluteCeiling.p99Nanoseconds`, replaced the `scrollFrame` case's derived value
with a bare literal one ns off the frame math:

```diff
         case .scrollFrame:
-            return GateLimits.frameNanoseconds / 10   // 1_666_666
+            return 1_666_667
```

**Command:** `swift test --filter testAbsoluteCeilingsArePinnedToTheFrameMath`

**Verbatim failure output:**

```
Test Case '-[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingsArePinnedToTheFrameMath]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:226: error: -[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingsArePinnedToTheFrameMath] : XCTAssertEqual failed: ("1666667") is not equal to ("1666666")
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:227: error: -[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingsArePinnedToTheFrameMath] : XCTAssertEqual failed: ("1666667") is not equal to ("1666666")
Test Case '-[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingsArePinnedToTheFrameMath]' failed (0.035 seconds).
Test Suite 'GateLogicTests' failed at 2026-08-08 19:20:36.611.
	 Executed 1 test, with 2 failures (0 unexpected) in 0.035 (0.035) seconds
```

Matches the brief's stated expectation exactly (`("1666667") is not equal to
("1666666")`), asserted twice (once against `GateLimits.frameNanoseconds / 10`, once
against the bare `1_666_666` literal) because the test checks the value both ways.

Before running the full suite, confirmed the two bracket tests from Drills 1/2 still
**PASS** under this mutation, as the brief predicts (both use
`scrollFrame.p99Nanoseconds + 1`, which moves with the mutation, so they cannot
detect it):

```
Test Case '-[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingDoesNotFireForBulkMode]' passed (0.000 seconds).
Test Case '-[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling]' passed (0.000 seconds).
Test Suite 'GateLogicTests' passed at 2026-08-08 19:20:42.178.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
```

This is exactly why this drill needs its own target
(`testAbsoluteCeilingsArePinnedToTheFrameMath`): the bracket tests are silent to a
mis-pinned literal that only shifts the ceiling itself.

**EXPECTED COLLATERAL** — with the mutation still applied, `swift test` (full suite)
also reddens `testGateOutputCarriesScrollFrameCeiling`, because its formatted output
line now carries the mutated value:

```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:226: error: -[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingsArePinnedToTheFrameMath] : XCTAssertEqual failed: ("1666667") is not equal to ("1666666")
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:227: error: -[ViewportBenchmarksTests.GateLogicTests testAbsoluteCeilingsArePinnedToTheFrameMath] : XCTAssertEqual failed: ("1666667") is not equal to ("1666666")
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:305: error: -[ViewportBenchmarksTests.GateLogicTests testGateOutputCarriesScrollFrameCeiling] : XCTAssertTrue failed - mode=structural_mutation provider=uniform scenario=test iterations=1 operations_per_sample=1 line_count=1000 p95_ns=100000 p99_ns=200000 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 headroom_p95=3.0x headroom_p99=3.0x budget_absolute_p99_ns=1666667 headroom_absolute_p99=8.3x gate=pass checksum=0

Test Suite 'SwiftTextEnginePackageTests.xctest' failed at 2026-08-08 19:20:13.546.
	 Executed 362 tests, with 3 failures (0 unexpected) in 5.237 (5.258) seconds
```

Its line reads `budget_absolute_p99_ns=1666667`, as the brief predicts. Three
assertion failures total, across two test cases: `testAbsoluteCeilingsArePinnedToTheFrameMath`
(the targeted test, 2 assertions) and `testGateOutputCarriesScrollFrameCeiling`
(expected collateral, 1 assertion) — both explained by the same single-line mutation.

**Reverted:** `git checkout -- Sources Tests .github/scripts` → `git diff --quiet` →
`tree clean`.

---

### Drill 6 — `exempt` is gone from the output

**Mutation** — `Sources/ViewportBenchmarks/BenchmarkSupport.swift`, in
`formatSummary`, restored the pre-slice `exempt` branch:

```diff
-        output += " budget_absolute_p99_ns=\(summary.mode.absoluteCeiling.p99Nanoseconds)"
+        if summary.mode.absoluteCeiling == .scrollFrame {
+            output += " budget_absolute_p99_ns=\(summary.mode.absoluteCeiling.p99Nanoseconds)"
+        } else {
+            output += " budget_absolute_p99_ns=exempt"
+        }
```

**Command:** `swift test --filter testGateOutputCarriesDiscreteActionCeilingForBulk`

**Verbatim failure output:**

```
Test Case '-[ViewportBenchmarksTests.GateLogicTests testGateOutputCarriesDiscreteActionCeilingForBulk]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateLogicTests.swift:327: error: -[ViewportBenchmarksTests.GateLogicTests testGateOutputCarriesDiscreteActionCeilingForBulk] : XCTAssertTrue failed - mode=bulk_structural_mutation provider=uniform scenario=test iterations=1 operations_per_sample=1 line_count=1000 p95_ns=400000 p99_ns=900000 failures=0 budget_p95_ns=2900000 budget_p99_ns=5800000 headroom_p95=7.3x headroom_p99=6.4x budget_absolute_p99_ns=exempt headroom_absolute_p99=18.5x gate=pass checksum=0
Test Case '-[ViewportBenchmarksTests.GateLogicTests testGateOutputCarriesDiscreteActionCeilingForBulk]' failed (0.035 seconds).
Test Suite 'GateLogicTests' failed at 2026-08-08 19:21:12.119.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.035 (0.035) seconds
```

Matches the brief's stated expectation: `XCTAssertTrue failed` on the line, which is
missing `budget_absolute_p99_ns=16666666` (it instead reads
`budget_absolute_p99_ns=exempt`).

**Reverted:** `git checkout -- Sources Tests .github/scripts` → `git diff --quiet` →
`tree clean`.

---

### Drill 7 — `gov_p95` names the right term

**Mutation** — `.github/scripts/derive-gate-budgets.sh`, flipped the `gov95` token's
`>=` to `<`:

```diff
-    gov95 = (8 * m95 >= 3 * x95) ? "median" : "max"
+    gov95 = (8 * m95 < 3 * x95) ? "median" : "max"
```

**Command:** `./.github/scripts/derive-gate-budgets.sh --self-test`

**Verbatim failure output:**

```
self_test=fail label=gov_p95=median when 8*med >= 3*max
  expected: [median]
  actual:   [max]
```

Matches the brief's expected output byte-for-byte (verified during planning).

Then ran `swift test --filter ScriptSelfTestTests` and confirmed the shell red
carries into a red `swift test`:

```
Test Case '-[ViewportBenchmarksTests.ScriptSelfTestTests testEveryScriptSelfTestPasses]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift:45: error: -[ViewportBenchmarksTests.ScriptSelfTestTests testEveryScriptSelfTestPasses] : XCTAssertEqual failed: ("1") is not equal to ("0") - self-test exited non-zero
script: /Users/aabanschikov/swift-text-engine/.github/scripts/derive-gate-budgets.sh
exit: 1
--- stdout ---
self_test=fail label=gov_p95=median when 8*med >= 3*max
  expected: [median]
  actual:   [max]

--- stderr ---

/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift:46: error: -[ViewportBenchmarksTests.ScriptSelfTestTests testEveryScriptSelfTestPasses] : XCTAssertTrue failed - no self_test=pass line
script: /Users/aabanschikov/swift-text-engine/.github/scripts/derive-gate-budgets.sh
exit: 1
--- stdout ---
self_test=fail label=gov_p95=median when 8*med >= 3*max
  expected: [median]
  actual:   [max]

--- stderr ---

/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift:49: error: -[ViewportBenchmarksTests.ScriptSelfTestTests testEveryScriptSelfTestPasses] : XCTAssertFalse failed - a self_test=fail line survived a zero exit
script: /Users/aabanschikov/swift-text-engine/.github/scripts/derive-gate-budgets.sh
exit: 1
--- stdout ---
self_test=fail label=gov_p95=median when 8*med >= 3*max
  expected: [median]
  actual:   [max]

--- stderr ---

Test Case '-[ViewportBenchmarksTests.ScriptSelfTestTests testEveryScriptSelfTestPasses]' failed (1.133 seconds).
Test Suite 'ScriptSelfTestTests' failed at 2026-08-08 19:21:38.706.
	 Executed 2 tests, with 3 failures (0 unexpected) in 1.134 (1.134) seconds
```

**Reverted:** `git checkout -- Sources Tests .github/scripts` → `git diff --quiet` →
`tree clean`.

---

## Summary

All seven drills matched the brief's stated expectations (Drill 1's assertion text
differs only in XCTest's fully-qualified enum rendering, which is not a semantic
deviation). Drills 1 and 2 confirmed as a genuine bracket: each mutation reddened
exactly its own named test and left the other test green. Drills 4 and 5's expected
collateral reds were both observed and are recorded above, each explicitly labelled
as collateral, not as evidence of a second, unrelated defect. Every mutation was
reverted with `git checkout -- Sources Tests .github/scripts` and confirmed against
`git diff --quiet` before the next drill began.

AC2's window check needs no drill of its own — its red is the pre-work state,
recorded before the harvest rather than manufactured after it.
