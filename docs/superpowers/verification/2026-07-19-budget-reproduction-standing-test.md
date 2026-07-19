# Slice 44 verification — budget-reproduction standing test

Branch `slice-44-budget-reproduction-standing-test`, on top of `main` at
`06a1358` (merge of PR #98, Slice 43 post-slice review). Commits on this
branch (Tasks 1-2, already landed before this task): `168392d` (docs: add
slice 44 budget-reproduction standing-test design), `ce5755d` (docs: add
slice 44 budget-reproduction implementation plan), `b456272` (test: reproduce
every committed gate budget from the corpus), `5940f06` (docs: record
budget-reproduction guard; fold P3 #1/#2). This record is Task 3: full local
verification + the guard-is-live demonstration (lifted from Task 1's own
report, not re-run), captured directly against the current tree.

This slice added `testEveryCommittedBudgetReproducesFromCorpus` to
`Tests/ViewportBenchmarksTests/GateFloorTests.swift`: a standing test that
shells out to `.github/scripts/derive-gate-budgets.sh` over the committed
corpus and asserts every one of the 46 committed `p95`/`p99` budget literals
in `everyGatedBudget()` byte-equals the freshly re-derived value — closing the
last "derived, never hand-typed" gap the recipe's own docs called out. No
engine, provider, script, corpus, or budget-literal change — see Section 5
below.

---

## 1. Pre-condition (Task 1 Step 1): script emits 46 scenarios

Recorded in Task 1's report (`.superpowers/sdd/task-1-report.md`), captured
before the test was written:

```
$ ./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | wc -l
      46
```

46 emitted scenarios == `everyGatedBudget().count`, so the new test's
bijective-cardinality assertion (`derived.count == budgets.count`) holds, and
(per Task 1's Step 4 focused run and this task's Step 1 full-suite run below)
all 46 committed literals reproduce byte-for-byte from the corpus today.

## 2. `swift test` — full suite, 311 tests, 0 failures

```
$ swift test 2>&1 | tail -15
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepIsNotContinueOnError]' passed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepRunsExactlyTheExpectedCommand]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepRunsExactlyTheExpectedCommand]' passed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic]' passed (0.001 seconds).
Test Suite 'WorkflowShapeTests' passed at 2026-07-19 11:05:54.822.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.006 (0.007) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-19 11:05:54.822.
	 Executed 311 tests, with 0 failures (0 unexpected) in 4.563 (4.586) seconds
Test Suite 'All tests' passed at 2026-07-19 11:05:54.822.
	 Executed 311 tests, with 0 failures (0 unexpected) in 4.563 (4.587) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

**311 = Slice 43's 310-test baseline + 1 new test** —
`testEveryCommittedBudgetReproducesFromCorpus` — exactly the increase the
brief expected. The trailing "0 tests in 0 suites" line is the empty Swift
Testing harness, not a failure, per `AGENTS.md`'s package-layout note.

## 3. Guard-is-live demonstration (lifted from Task 1 Step 5 — not re-run)

Per the task brief, this is **not** re-executed in Task 3 (Task 1 already ran
it and left the tree clean); the transcripts below are lifted verbatim from
`.superpowers/sdd/task-1-report.md`.

Confirmed the exact literal before perturbing:

```
$ grep -n "p95BudgetNanoseconds: 220, p99BudgetNanoseconds: 440" Sources/ViewportBenchmarks/LineQueryBenchmark.swift
21:                          p95BudgetNanoseconds: 220, p99BudgetNanoseconds: 440),
```

Applied the sed bump (440 -> 450):

```
$ sed -i.bak 's/p95BudgetNanoseconds: 220, p99BudgetNanoseconds: 440/p95BudgetNanoseconds: 220, p99BudgetNanoseconds: 450/' Sources/ViewportBenchmarks/LineQueryBenchmark.swift
```

### RED transcript

```
Test Case '-[ViewportBenchmarksTests.GateFloorTests testEveryCommittedBudgetReproducesFromCorpus]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateFloorTests.swift:429: error: -[ViewportBenchmarksTests.GateFloorTests testEveryCommittedBudgetReproducesFromCorpus] : XCTAssertEqual failed: ("440") is not equal to ("450") - line_query|uniform_1k: committed p99 budget 450 != 440 re-derived from the corpus — the literal no longer reproduces (budget_stale, not an engine regression). Re-derive with .github/scripts/derive-gate-budgets.sh and re-commit.
Test Case '-[ViewportBenchmarksTests.GateFloorTests testEveryCommittedBudgetReproducesFromCorpus]' failed (0.193 seconds).
Test Suite 'GateFloorTests' failed at 2026-07-19 10:54:04.627.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.193 (0.193) seconds
```

### Revert

```
$ mv Sources/ViewportBenchmarks/LineQueryBenchmark.swift.bak Sources/ViewportBenchmarks/LineQueryBenchmark.swift
```

### GREEN transcript

```
Test Case '-[ViewportBenchmarksTests.GateFloorTests testEveryCommittedBudgetReproducesFromCorpus]' started.
Test Case '-[ViewportBenchmarksTests.GateFloorTests testEveryCommittedBudgetReproducesFromCorpus]' passed (0.092 seconds).
Test Suite 'GateFloorTests' passed at 2026-07-19 10:54:13.842.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.092 (0.092) seconds
```

### Clean-tree confirmation (from Task 1)

```
$ git diff Sources/ViewportBenchmarks/LineQueryBenchmark.swift
(empty — byte-identical to HEAD)

$ find /Users/aabanschikov/swift-text-engine -maxdepth 3 -name "*.bak"
(no results — no stray .bak file left)
```

**This break was never committed** — it was applied, observed RED, reverted,
and re-confirmed GREEN entirely within Task 1's working tree, which returned
byte-clean before Task 1's own commit (`b456272`) was made. The guard is
proven live: a stale budget literal fails the new test with a message naming
the exact scenario, the exact stale/derived values, and the correct
disposition (`budget_stale`, not an engine regression); restoring the literal
restores green.

## 4. Release build, Foundation-free scan, synthetic gate

```
$ swift build -c release 2>&1 | tail -3
[1/3] Write swift-version-58A378E29CF047B.txt
[3/4] Compiling ViewportBenchmarks BenchmarkModels.swift
Build complete! (1.84s)
```

```
$ rg -n "Foundation" Sources/TextEngineCore; echo "exit=$?"
exit=1
```

`rg` found no matches (exit code 1 = no matches, per ripgrep convention);
`Sources/TextEngineCore` remains Foundation-free.

```
$ swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -5
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1501 p99_ns=1819 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=14.0x headroom_p99=23.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=916.3x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5910 p99_ns=6530 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=14.2x headroom_p99=26.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=255.2x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=18529 p99_ns=19162 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=15.1x headroom_p99=29.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=87.0x gate=pass checksum=18852477646272000
```

All three synthetic scenarios `gate=pass`.

## 5. Eleven gate-mode checksum loop — byte-identical to the Slice 43 baseline

Ran every gated mode with `--gate` (default pipeline, `--realistic-provider`,
`--variable-height`, `--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--column-geometry-query`, `--point-query`,
`--point-geometry-query`), capturing every `mode=... scenario=... checksum=...`
line:

```
$ for mode in "" "--realistic-provider" "--variable-height" "--variable-height-mutation" \
  "--structural-mutation" "--bulk-structural-mutation" "--line-query" "--line-geometry-query" \
  "--column-query" "--column-geometry-query" "--point-query" "--point-geometry-query"; do
  echo "=== ${mode:-default} ==="
  swift run -c release ViewportBenchmarks -- $mode --gate 2>&1 | grep -E 'mode=|checksum='
done

=== default ===
mode=pipeline scenario=1k_lines_20_visible_overscan_0 ... checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 ... checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 ... checksum=18852477646272000
=== --realistic-provider ===
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text ... checksum=756321289736960
=== --variable-height ===
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 ... checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 ... checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 ... checksum=3536425156727040
=== --variable-height-mutation ===
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 ... checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 ... checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 ... checksum=3571078666132451
=== --structural-mutation ===
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 ... checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 ... checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 ... checksum=3379593298396981
=== --bulk-structural-mutation ===
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 ... checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 ... checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 ... checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 ... checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 ... checksum=82203678997143
=== --line-query ===
mode=line_query provider=uniform scenario=uniform_1k ... checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k ... checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m ... checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k ... checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m ... checksum=639841547520
=== --line-geometry-query ===
mode=line_geometry_query provider=uniform scenario=uniform_1k ... checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k ... checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m ... checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k ... checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m ... checksum=852321495040
=== --column-query ===
mode=column_query provider=uniform scenario=uniform_1k ... checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k ... checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m ... checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k ... checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m ... checksum=639841560320
=== --column-geometry-query ===
mode=column_geometry_query provider=uniform scenario=uniform_1k ... checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k ... checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m ... checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k ... checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m ... checksum=839521520640
=== --point-query ===
mode=point_query provider=uniform scenario=uniform_100k ... checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m ... checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k ... checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m ... checksum=640022228480
=== --point-geometry-query ===
mode=point_geometry_query provider=uniform scenario=uniform_100k ... checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m ... checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k ... checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m ... checksum=5915921755926273280
```

(Full `p95_ns=`/`p99_ns=`/`headroom_*=` fields omitted here for brevity —
`gate=pass` on every one of these rows, matching Step 4's synthetic result.)

**Result: every `checksum=` value is byte-identical to the Slice 43 baseline**
(`docs/superpowers/verification/2026-07-18-absolute-product-budget.md`,
Section 8's 45-row table), including the `realistic_provider` row (excluded
from that table's 45-count per its own documented convention, but shown there
in Section 5 as `756321289736960` — unchanged here). This slice touched no
core, provider, script, or corpus code — only a new test in
`GateFloorTests.swift` plus docs — so an unchanged checksum on every gated
scenario is exactly the expected outcome, confirming zero workload drift.

## 6. Diff scope vs `main` — no engine/provider/script/corpus/budget-literal path

```
$ git diff --name-only main
AGENTS.md
Tests/ViewportBenchmarksTests/GateFloorTests.swift
docs/superpowers/plans/2026-07-19-budget-reproduction-standing-test.md
docs/superpowers/specs/2026-07-19-budget-reproduction-standing-test-design.md
```

(This verification doc itself is added by Task 3's own commit, immediately
after this listing was captured — so the full branch diff against `main`
will show five paths once committed: the four above plus this file.)

```
$ git diff --name-only main -- Sources/TextEngineCore Sources/TextEngineReferenceProviders \
  .github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
$
```

Empty output — no engine, provider, script, or corpus path changed, and no
budget literal touched (budget literals live under
`Sources/ViewportBenchmarks/*Benchmark.swift` / `SyntheticBenchmarks.swift` /
`BenchmarkModels.swift`, none of which appear in the first listing).

## 7. Final clean-tree confirmation

```
$ git status --short
$
```

Empty — clean immediately before this verification doc was written and
committed. The only file this task adds is this document itself.

---

## Hosted CI — Discharged

**Discharged 2026-07-19.** Both runs were read **at step level** (never trusting a
job-level `continue-on-error` conclusion, per the Slice 16 dead-step-trap rule in
`AGENTS.md`), matching the Slices 24-43 pattern of anchoring proof in the merged-code
`push` run rather than the PR-head run alone. PR #99 merged as commit `ec265d3`.

The realistic-provider observation step is **PR-only** (gated on the `pull_request`
event, so it does not run on the `push` build) **and** writes its benchmark output to a
temp file, so it emits no `gate=`/`checksum=` line in either run's log — it is not part
of this proof. The docs-only fast path was correctly **not** taken by either run: the
merge diff carries a Swift test, so the heavy path ran in both.

| | PR-head run | Post-merge push run |
|---|---|---|
| Run ID / commit | 29679693875 / `2b5e132` | 29680120202 / `ec265d3` (merge of PR #99) |
| Trigger | `pull_request` (PR #99) | `push` to `main` |
| Three required jobs (step level) | all ✓ — host 88173481190, iOS 88173481198, WASM 88173481185 | all ✓ — host 88174634071, iOS 88174634067, WASM 88174634069 |
| Eleven blocking gate steps | all ✓ | all ✓ |
| Gate tally | 45× `gate=pass`, 0 fail (40 hot-path @ `budget_absolute_p99_ns=1666666`, 5 bulk `=exempt`) | 45× `gate=pass`, 0 fail (40 hot-path @ 1666666, 5 bulk `=exempt`) |
| Host tests | `Executed 311 tests, with 0 failures` | `Executed 311 tests, with 0 failures` |
| `testEveryCommittedBudgetReproducesFromCorpus` | passed (0.068 s) | passed (0.067 s) |
| Checksum set | 53 `checksum=` lines (45 gated + 5 `memory_shape` + 3 `memory_observation`) | 53 `checksum=` lines, **byte-identical to PR-head** (tuple diff empty) and to the local Task 3 set (== Slice 43 baseline; checksums are deterministic/workload-derived) |

The merged-code `push` run **29680120202** anchors the proof. Both halves green at step
level; the new reproduction test passed hosted, and no gate reddened.
