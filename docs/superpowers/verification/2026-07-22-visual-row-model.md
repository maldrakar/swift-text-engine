# Slice 49 verification — visual-row model + row-packing (wrap node 1)

Branch `slice-49-visual-row-model`, on top of `main` at `a183205` (merge of
PR #112, Slice 48 outer-loop codification). Commits on this branch (Tasks 1-4,
already landed before this task):

- `72cb50c` — feat: add WrapMetricsSource contract + test driver (wrap node 1)
- `ac2b64e` — feat: add VisualRow model + streaming cursor + visualRows (blank/equivalence)
- `1e50735` — feat: greedy multi-row row-packing + overflow (wrap node 1)
- `47b4e5e` — feat: visualRows width + metrics validation ladder (columnAt parity)

This task (Task 5) is documentation + full verification, plus one carried
doc-comment fix from the Task 4 review:

- `eb9361c` — docs: past-tense the visualRows validation-ladder doc comment
- (this commit) — docs: AGENTS.md wrap layer + slice 49 verification record

This slice introduces the soft-wrap layer's first node: `WrapMetricsSource`
(refines `LineHorizontalMetricsSource` with a `canBreak(beforeColumn:inLine:)`
predicate) and `ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)`,
which streams a logical line's `VisualRow`s via a generic `VisualRowCursor<Metrics>`
wrapped in `VisualRowQuery<Metrics>`, greedily packing to `wrapWidth` in visual
order (with overflow for unbreakable runs wider than the width). No engine
behavior outside the new wrap surface changed — `ViewportVirtualizer`'s
existing compute/query methods, all providers, and all gate budgets are
untouched by this slice.

---

## 0. Carried fix (Commit 1): doc-comment before/after

`Sources/TextEngineCore/VisualRowCursor.swift:81` (now spanning lines 81-83)
described the width + metrics validation ladder as future work
("Task 4 adds..."), but Task 4 already shipped it in `47b4e5e`, making the
comment stale. Fixed to a present-tense description of current behavior.

**Before:**

```
/// Streams the visual rows of logical line `inLine` packed to `wrapWidth`, in
/// visual order. Stateless; the cursor is lazy (no packing happens here).
/// `inLine` is a precondition (the source carries no `lineCount`), exactly like
/// `columnAt`. Task 4 adds the width + metrics validation ladder.
```

**After:**

```
/// Streams the visual rows of logical line `inLine` packed to `wrapWidth`, in
/// visual order. Stateless; the cursor is lazy (no packing happens here).
/// `inLine` is a precondition (the source carries no `lineCount`), exactly like
/// `columnAt`. Validates `wrapWidth` (`> 0`, so `+∞` is allowed — the
/// equivalence case) and runs the same O(1) metrics ladder as `columnAt`
/// before handing back the lazy cursor.
```

Only the trailing sentence changed; the first three comment lines and all
code are untouched. `swift build` was re-run immediately after and succeeded
(see Section 2).

## 1. AGENTS.md placement

The brief's exact markdown block (verbatim, confirmed via a substring check
against the brief's fenced block before commit) was inserted immediately
after the `pointGeometryAt(...)` paragraph — specifically after the sentence
ending `` `--point-geometry-query --gate` is its blocking host-job CI gate
(the eleventh). `` — and immediately before `## Package layout`, exactly as
the brief specified. No other AGENTS.md content was touched.

## 2. `swift build` (debug) after the carried fix

```
$ swift build 2>&1 | tail -30
[0/1] Planning build
Building for debugging...
[0/4] Write sources
[1/4] Write swift-version-58A378E29CF047B.txt
[3/6] Compiling TextEngineCore VisualRowCursor.swift
[4/6] Emitting module TextEngineCore
[4/7] Write Objects.LinkFileList
[5/7] Linking ViewportBenchmarks
[6/7] Applying ViewportBenchmarks
Build complete! (0.31s)
```

Comment-only change compiles clean.

## 3. Full core-change verification suite (Task 5 Step 2)

### 3a. `swift test` — full suite, 333 tests, 0 failures

```
$ swift test 2>&1 | tail -60
...
Test Suite 'WrapMetricsSourceTests' started at 2026-07-22 23:52:20.321.
Test Case '-[TextEngineCoreTests.WrapMetricsSourceTests testDriverCumulativeOffsetsAndBreaks]' started.
Test Case '-[TextEngineCoreTests.WrapMetricsSourceTests testDriverCumulativeOffsetsAndBreaks]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapMetricsSourceTests testOffsetsInitExpressesMalformedCounts]' started.
Test Case '-[TextEngineCoreTests.WrapMetricsSourceTests testOffsetsInitExpressesMalformedCounts]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapMetricsSourceTests testRefinesLineHorizontalMetricsSource]' started.
Test Case '-[TextEngineCoreTests.WrapMetricsSourceTests testRefinesLineHorizontalMetricsSource]' passed (0.000 seconds).
Test Suite 'WrapMetricsSourceTests' passed at 2026-07-22 23:52:20.321.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'WrapPackingTests' started at 2026-07-22 23:52:20.321.
Test Case '-[TextEngineCoreTests.WrapPackingTests testBreakOnlyAtDeclaredOpportunities]' started.
Test Case '-[TextEngineCoreTests.WrapPackingTests testBreakOnlyAtDeclaredOpportunities]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapPackingTests testCharWrapOneCellPerRow]' started.
Test Case '-[TextEngineCoreTests.WrapPackingTests testCharWrapOneCellPerRow]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapPackingTests testGreedyBreaksAtLastFittingOpportunity]' started.
Test Case '-[TextEngineCoreTests.WrapPackingTests testGreedyBreaksAtLastFittingOpportunity]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapPackingTests testPartitionTilesTheLine]' started.
Test Case '-[TextEngineCoreTests.WrapPackingTests testPartitionTilesTheLine]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapPackingTests testUnbreakableRunOverflowsOneRow]' started.
Test Case '-[TextEngineCoreTests.WrapPackingTests testUnbreakableRunOverflowsOneRow]' passed (0.000 seconds).
Test Suite 'WrapPackingTests' passed at 2026-07-22 23:52:20.322.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'WrapValidationTests' started at 2026-07-22 23:52:20.322.
Test Case '-[TextEngineCoreTests.WrapValidationTests testBlankLineWithBadFirstOffsetFailsBeforeShortCircuit]' started.
Test Case '-[TextEngineCoreTests.WrapValidationTests testBlankLineWithBadFirstOffsetFailsBeforeShortCircuit]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapValidationTests testFirstOffsetNonZeroFails]' started.
Test Case '-[TextEngineCoreTests.WrapValidationTests testFirstOffsetNonZeroFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapValidationTests testInfiniteWidthDoesNotFail]' started.
Test Case '-[TextEngineCoreTests.WrapValidationTests testInfiniteWidthDoesNotFail]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapValidationTests testLadderChecksCountBeforeWidth]' started.
Test Case '-[TextEngineCoreTests.WrapValidationTests testLadderChecksCountBeforeWidth]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapValidationTests testNegativeColumnCountFails]' started.
Test Case '-[TextEngineCoreTests.WrapValidationTests testNegativeColumnCountFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapValidationTests testNonPositiveOrNonFiniteWidthFails]' started.
Test Case '-[TextEngineCoreTests.WrapValidationTests testNonPositiveOrNonFiniteWidthFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.WrapValidationTests testZeroOrNonFiniteLineTotalFails]' started.
Test Case '-[TextEngineCoreTests.WrapValidationTests testZeroOrNonFiniteLineTotalFails]' passed (0.000 seconds).
Test Suite 'WrapValidationTests' passed at 2026-07-22 23:52:20.322.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-22 23:52:20.322.
	 Executed 333 tests, with 0 failures (0 unexpected) in 4.182 (4.203) seconds
Test Suite 'All tests' passed at 2026-07-22 23:52:20.322.
	 Executed 333 tests, with 0 failures (0 unexpected) in 4.182 (4.204) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

Also confirmed the `VisualRowEquivalenceTests` suite separately in the same
run's full log:

```
Test Suite 'VisualRowEquivalenceTests' started at 2026-07-22 23:52:20.314.
Test Case '-[TextEngineCoreTests.VisualRowEquivalenceTests testBlankLineIsOneEmptyRow]' started.
Test Case '-[TextEngineCoreTests.VisualRowEquivalenceTests testBlankLineIsOneEmptyRow]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.VisualRowEquivalenceTests testSingleCellLineIsOneRow]' started.
Test Case '-[TextEngineCoreTests.VisualRowEquivalenceTests testSingleCellLineIsOneRow]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.VisualRowEquivalenceTests testWidthAtOrAboveTotalYieldsOneRowEqualToNoWrap]' started.
Test Case '-[TextEngineCoreTests.VisualRowEquivalenceTests testWidthAtOrAboveTotalYieldsOneRowEqualToNoWrap]' passed (0.000 seconds).
Test Suite 'VisualRowEquivalenceTests' passed at 2026-07-22 23:52:20.314.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
```

**New test counts by file** (matching Tasks 1-4's TDD steps exactly):

| Test file | Tests |
|---|---|
| `WrapMetricsSourceTests` | 3 |
| `VisualRowEquivalenceTests` | 3 |
| `WrapPackingTests` | 5 |
| `WrapValidationTests` | 7 |
| **New total** | **18** |

**333 = Slice 48's prior baseline (315) + 18 new wrap-layer tests.** The
trailing "0 tests in 0 suites" line is the empty Swift Testing harness, not a
failure, per `AGENTS.md`'s package-layout note.

### 3b. `swift build -c release` — succeeds

```
$ swift build -c release 2>&1
[0/1] Planning build
Building for production...
[0/3] Write sources
[1/3] Write swift-version-58A378E29CF047B.txt
[3/4] Compiling TextEngineCore DocumentLineCursor.swift
[4/6] Compiling TextEngineReferenceProviders BalancedTreeLineMetrics.swift
[5/7] Compiling ViewportBenchmarks BenchmarkModels.swift
[5/7] Write Objects.LinkFileList
[6/7] Linking ViewportBenchmarks
Build complete! (2.13s)
```

### 3c. `swift run -c release ViewportBenchmarks -- --gate` — `gate=pass` (unchanged; no new mode this slice)

```
$ swift run -c release ViewportBenchmarks -- --gate
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1242 p99_ns=1461 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=16.9x headroom_p99=28.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1140.8x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5054 p99_ns=5152 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=16.6x headroom_p99=33.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=323.5x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16841 p99_ns=17184 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=16.6x headroom_p99=32.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=97.0x gate=pass checksum=18852477646272000
```

All three synthetic scenarios `gate=pass`. This slice added no new gated
benchmark mode (the wrap layer is not yet wired into `compute`/CI — per the
brief, "wrap-aware `compute` are later nodes"), so these checksums are
expected to be — and are — byte-identical to prior slices' synthetic-pipeline
checksums (`1319670707200` / `570448232307200` / `18852477646272000`, matching
e.g. Slice 44's Section 5 table).

### 3d. Foundation-free scan — empty

```
$ rg -n "Foundation" Sources/TextEngineCore; echo "exit=$?"
exit=1
```

`rg` exit code 1 = no matches (ripgrep convention); no output printed.
`Sources/TextEngineCore` — including the new `WrapMetricsSource.swift` and
`VisualRowCursor.swift` — remains Foundation-free.

### 3e. Cross-target self-test — passes (no toolchain needed)

```
$ ./.github/scripts/cross-target-compile.sh --self-test
self_test=pass
```

The real iOS + WASM cross-compiles run in hosted CI on the PR; those run IDs
are recorded in the Hosted CI section below once the PR is open.

## 4. Diff scope vs `main`

```
$ git diff --name-only main
AGENTS.md
Sources/TextEngineCore/ViewportTypes.swift
Sources/TextEngineCore/VisualRowCursor.swift
Sources/TextEngineCore/WrapMetricsSource.swift
Tests/TextEngineCoreTests/TestWrapMetrics.swift
Tests/TextEngineCoreTests/VisualRowEquivalenceTests.swift
Tests/TextEngineCoreTests/WrapMetricsSourceTests.swift
Tests/TextEngineCoreTests/WrapPackingTests.swift
Tests/TextEngineCoreTests/WrapTestSupport.swift
Tests/TextEngineCoreTests/WrapValidationTests.swift
docs/superpowers/arcs/wrap.md
docs/superpowers/debt-ledger.md
docs/superpowers/plans/2026-07-22-visual-row-model.md
docs/superpowers/reviews/2026-07-22-slice-48-post-slice-review.md
docs/superpowers/specs/2026-07-22-visual-row-model-design.md
```

(This verification doc itself, plus its commit, is added by this task's own
commit immediately after this listing was captured.)

No existing gate script, corpus, or budget-literal path is touched — the new
surface (`WrapMetricsSource`, `VisualRow`, `VisualRowCursor`, `VisualRowQuery`,
`visualRows`) is purely additive to `Sources/TextEngineCore`, alongside its
tests and this slice's docs.

## 5. Final clean-tree confirmation

```
$ git status --short
```

Clean immediately before this verification doc + `AGENTS.md` were staged for
this task's commit.

---

## Hosted CI

Per repo convention, hosted proof is read at **step** level, not job
conclusion — a green job can hide a dead `continue-on-error` step (the Slice
16 dead-step trap). Merged proof is anchored in the **post-merge push run**,
not the PR-head run alone (the pattern used in every prior slice's
verification record, e.g. Slice 44/45/47).

PR #114 (`https://github.com/maldrakar/swift-text-engine/pull/114`).

| | PR-head run | Post-merge push run |
|---|---|---|
| Run ID / commit | `29958326817` @ `3e4f511` | TBD (fill after merge) |
| Trigger | `pull_request` | `push` to `main` |
| Three required jobs (step level) | **all `success`** — Host tests and benchmark gate, iOS cross-target compile, WASM cross-target compile | TBD |
| `Complete docs-only PR` step | **`[skipped]`** in all three jobs (correct — PR touches `Sources/`, so the heavy path ran, not the docs-only fast path) | TBD |
| Twelve blocking gate steps | **all `[success]`** — synthetic, variable-height, variable-height-mutation, structural-mutation, bulk-structural-mutation, line-query, line-geometry-query, column-query, column-geometry-query, point-query, point-geometry-query, realistic-provider (`gate=pass`, unchanged budgets) | TBD |
| Host tests (`Run host tests` step) | **`[success]`** (the 333/0 suite incl. `GateFloorTests.testEveryCommittedBudgetReproducesFromCorpus`, so budgets/checksums reproduce) | TBD |
| Memory diagnostics | **`[success]`** — `Run memory shape diagnostic`, `Run RSS memory observation diagnostic` | TBD |
| iOS cross-target compile (`Compile cross-target packages for iOS` step) | **`[success]`** (blocking) | TBD |
| WASM cross-target compile (`Compile cross-target packages for WASM` step, wasm + wasm-embedded) | **`[success]`** (blocking) | TBD |

PR-head half verified at step level 2026-07-23 via
`gh run view 29958326817 --json jobs` (every substantive step `success`; the
only `[skipped]` is the docs-only fast-path step, which correctly did not
apply). Post-merge column to be filled from the `push`-to-`main` run after
merge, per `AGENTS.md`'s step-level-not-job-conclusion rule. Note: a docs
commit adding this evidence retriggers PR CI; strict required-status-check
policy binds the merge to the latest (also-green) run.
