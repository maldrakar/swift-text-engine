# Slice 42 verification — shell window-selection guard pinned to Swift twin

Branch `slice-42-shell-window-selection-guard`. Commits on top of `main`:
`71df260` (fix: trap-clean `derive-gate-budgets.sh` self-test fixture on red
path), `91e67d5` (feat: add `--window-run-ids` seam to
`derive-gate-budgets.sh`), `b3b0885` (test: pin shell window-selection to
Swift `mostRecentRunIDs`), `384a2da` (docs: record the seam + pin in
`AGENTS.md`). This record is Task 4, Steps 1-2 (local evidence) + Step 3
(commit). Hosted proof (AC8) is an explicit placeholder below, to be filled
in after CI runs on the PR and after the post-merge `push` run.

This slice changed **only** three files across the whole branch:
`.github/scripts/derive-gate-budgets.sh` (the `--window-run-ids` seam + a
trap-cleanup fold), `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (the
new `testWindowSelectionMatchesDeriveScript` guard + its subprocess helper),
and `AGENTS.md` (docs). No engine, provider, budget literal, corpus, or
workload changed. Everything below is evidence for that claim, captured
directly against the current tree (HEAD `384a2da`).

---

## 1. `swift test` — full suite, 300 tests, 0 failures

```
$ swift test 2>&1 | tail -5
	 Executed 300 tests, with 0 failures (0 unexpected) in 4.144 (4.164) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

**300 = Slice 41's 299-test baseline + 1** (`testWindowSelectionMatchesDeriveScript`,
added in `b3b0885`). The trailing "0 tests in 0 suites" line is the empty
Swift Testing harness, not a failure, per `AGENTS.md`'s package-layout note.
The full run (not just `tail -5`) confirms `GateFloorTests` and
`WorkflowShapeTests` both pass in full, including the new test.

## 2. Guard-is-live evidence (copied from Task 2's own report, not re-run)

Per the task-4 brief and the parent task's instruction, this section is
**quoted verbatim** from `.superpowers/sdd/task-2-report.md` — Task 2's own
break -> RED -> revert -> GREEN transcript for
`testWindowSelectionMatchesDeriveScript`. It is not re-executed here: doing so
would re-touch `.github/scripts/derive-gate-budgets.sh` and risk a dirty tree
for no new evidence.

Task 2 edited `.github/scripts/derive-gate-budgets.sh` line 32 from
`tail -n +2 | cut -f1 | sort -rnu | head -n "$n"` to
`tail -n +2 | cut -f1 | sort -rn | head -n "$n"` (dropped `-u`):

**RED output (verbatim from `task-2-report.md`):**

```
$ swift test --filter GateFloorTests/testWindowSelectionMatchesDeriveScript
...
Test Case '-[ViewportBenchmarksTests.GateFloorTests testWindowSelectionMatchesDeriveScript]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateFloorTests.swift:347: error: -[ViewportBenchmarksTests.GateFloorTests testWindowSelectionMatchesDeriveScript] : XCTAssertEqual failed: ("[305]") is not equal to ("[210, 305]") - shell window_run_ids and Swift mostRecentRunIDs disagree at N=2 — the two corpus consumers would window differently; re-run `.github/scripts/derive-gate-budgets.sh --self-test`
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/GateFloorTests.swift:347: error: -[ViewportBenchmarksTests.GateFloorTests testWindowSelectionMatchesDeriveScript] : XCTAssertEqual failed: ("[210, 305]") is not equal to ("[210, 305, 100]") - shell window_run_ids and Swift mostRecentRunIDs disagree at N=3 — the two corpus consumers would window differently; re-run `.github/scripts/derive-gate-budgets.sh --self-test`
Test Case '-[ViewportBenchmarksTests.GateFloorTests testWindowSelectionMatchesDeriveScript]' failed (0.315 seconds).
Test Suite 'GateFloorTests' failed at 2026-07-18 16:37:31.903.
	 Executed 1 test, with 2 failures (0 unexpected) in 0.315 (0.315) seconds
```

At N=2, the shell without `-u` emits the duplicated run `305` *twice*:
`sort -rn | head -n 2` returns the two physically-adjacent `305` lines (the
two highest values) and never reaches `210`. `head` does not dedup — it is the
test parsing that stdout into a `Set` that collapses the two `305` lines to
`{305}`, whereas Swift's `mostRecentRunIDs` dedups by value *first* and returns
`{305, 210}`. So the two sets diverge. N=3 diverges similarly (`{210,305}` vs
`{210,305,100}`); N=10 was not reported as a failure — a window wide enough
to be a no-op agreed for both, as expected. This is the discriminating
fixture (`fixtureIDs = [100, 305, 305, 210, 99, 210, 42]`, distinct ids
`{100, 305, 210, 99, 42}`, physically out of chronological order, 305 and 210
each duplicated) doing its job: the guard is demonstrably live, not a
vacuously-passing tautology.

**Revert + confirm byte-clean (verbatim from `task-2-report.md`):**

```
$ git checkout .github/scripts/derive-gate-budgets.sh
Updated 1 path from the index
$ git diff .github/scripts/derive-gate-budgets.sh
(empty)
```

**GREEN after revert (verbatim from `task-2-report.md`):**

```
$ swift test --filter GateFloorTests/testWindowSelectionMatchesDeriveScript
...
Test Case '-[ViewportBenchmarksTests.GateFloorTests testWindowSelectionMatchesDeriveScript]' passed (0.215 seconds).
Test Suite 'GateFloorTests' passed at 2026-07-18 16:37:48.091.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.215 (0.215) seconds
```

Task 2's commit (`b3b0885`) touched only
`Tests/ViewportBenchmarksTests/GateFloorTests.swift`; the shell script was
never actually committed in its broken state.

## 3. `derive-gate-budgets.sh --self-test` — still green with the trap fold

Re-run directly by this task:

```
$ bash .github/scripts/derive-gate-budgets.sh --self-test
self_test=pass
```

Confirms Task 1's trap-cleanup fold (fixture cleaned on the self-test's own
red path, per AC6) doesn't regress the self-test's green path.

## 4. The `--window-run-ids` seam, by hand

Re-run directly by this task:

```
$ printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n100\tm\ts\t1\t2\n305\tm\ts\t1\t2\n305\tm\ts2\t1\t2\n210\tm\ts\t1\t2\n99\tm\ts\t1\t2\n210\tm\ts2\t1\t2\n42\tm\ts\t1\t2\n' \
  | bash .github/scripts/derive-gate-budgets.sh --window-run-ids 2
305
210
```

Matches the brief's expectation exactly (`305` then `210`) — the top-2
distinct run ids by value from a corpus with duplicated and out-of-order run
ids, i.e. the same set `testWindowSelectionMatchesDeriveScript` pins against
Swift's `mostRecentRunIDs(fixtureIDs, limit: 2)`.

## 5. Foundation-free scan — empty

Re-run directly by this task:

```
$ rg -n "Foundation" Sources/TextEngineCore || echo "EMPTY (pass)"
EMPTY (pass)
```

## 6. Zero engine/provider diff vs `main`

Re-run directly by this task:

```
$ git diff --name-only main -- Sources/TextEngineCore Sources/TextEngineReferenceProviders || true
echo "^ must be empty"
^ must be empty
```

No output before the echoed sentinel — the constrained diff is empty. For
completeness, the **whole-branch** `git diff --name-only main` (not scoped to
those two directories) lists exactly:

```
.github/scripts/derive-gate-budgets.sh
AGENTS.md
Tests/ViewportBenchmarksTests/GateFloorTests.swift
docs/superpowers/plans/2026-07-18-shell-window-selection-guard.md
docs/superpowers/specs/2026-07-18-shell-window-selection-guard-design.md
```

Five files: one shell script, one test file, one docs/AGENTS.md edit, and two
plan/spec docs from the slice's own paper trail. Zero
`Sources/TextEngineCore` or `Sources/TextEngineReferenceProviders` paths, and
zero budget-literal source files (`Sources/ViewportBenchmarks/*.swift`) or
corpus files — confirming this slice touched nothing but CI/governance
tooling, tests, and docs.

## 7. Eleven `--gate` modes: all `gate=pass`, checksum byte-identity vs. the Slice 41 baseline

Ran via `swift run -c release ViewportBenchmarks -- <mode> --gate` against
release build (`swift build -c release`, clean build, "Build complete!") on
this branch's HEAD (`384a2da`), filtered through `rg "gate=|checksum"`.

**Result: every one of the 46 gated scenario rows across all eleven modes
printed `gate=pass failures=0`.** Local macOS headroom ranged roughly
9.6x-46.1x, comfortably inside the 3x floor / 50x-100x ceiling band.

Full captured output (one block per mode, in the brief's order):

```
== gate  ==
mode=pipeline scenario=1k_lines_20_visible_overscan_0 ... p95_ns=1250 p99_ns=1486 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=16.8x headroom_p99=28.3x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 ... p95_ns=5087 p99_ns=5212 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=16.5x headroom_p99=32.6x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 ... p95_ns=16818 p99_ns=17159 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=16.6x headroom_p99=32.6x gate=pass checksum=18852477646272000

== gate --variable-height ==
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 ... gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 ... gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 ... gate=pass checksum=3536425156727040

== gate --variable-height-mutation ==
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 ... gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 ... gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 ... gate=pass checksum=3571078666132451

== gate --structural-mutation ==
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 ... gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 ... gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 ... gate=pass checksum=3379593298396981

== gate --bulk-structural-mutation ==
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 ... gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 ... gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 ... gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 ... gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 ... gate=pass checksum=82203678997143

== gate --line-query ==
mode=line_query provider=uniform scenario=uniform_1k ... gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k ... gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m ... gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k ... gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m ... gate=pass checksum=639841547520

== gate --line-geometry-query ==
mode=line_geometry_query provider=uniform scenario=uniform_1k ... gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k ... gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m ... gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k ... gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m ... gate=pass checksum=852321495040

== gate --column-query ==
mode=column_query provider=uniform scenario=uniform_1k ... gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k ... gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m ... gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k ... gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m ... gate=pass checksum=639841560320

== gate --column-geometry-query ==
mode=column_geometry_query provider=uniform scenario=uniform_1k ... gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k ... gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m ... gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k ... gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m ... gate=pass checksum=839521520640

== gate --point-query ==
mode=point_query provider=uniform scenario=uniform_100k ... gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m ... gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k ... gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m ... gate=pass checksum=640022228480

== gate --point-geometry-query ==
mode=point_geometry_query provider=uniform scenario=uniform_100k ... gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m ... gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k ... gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m ... gate=pass checksum=5915921755926273280
```

(`...` elides the iteration/timing/budget fields already shown in full for
the first mode above; every field present in the raw capture, including
`budget_p95_ns`/`budget_p99_ns`, matched the values `derive-gate-budgets.sh`
currently produces from the committed corpus, confirming no budget literal
changed either — consistent with this slice touching zero
`Sources/ViewportBenchmarks/*.swift` files, per Section 6's diff.)

### Byte-identity vs. the Slice 41 baseline

The Slice 41 verification record
(`docs/superpowers/verification/2026-07-17-gate-budget-ratchet-repair.md`,
Section 6) recorded these checksums as its own byte-identity baseline
(itself carried forward unchanged from Slice 40):

| Mode | Slice 41 baseline checksums | This run's checksums | Match |
|---|---|---|---|
| pipeline | 1319670707200, 570448232307200, 18852477646272000 | 1319670707200, 570448232307200, 18852477646272000 | yes |
| variable_height | 231017730560, 101209179008000, 3536425156727040 | 231017730560, 101209179008000, 3536425156727040 | yes |
| variable_height_mutation | 196866548667, 88324286099072, 3571078666132451 | 196866548667, 88324286099072, 3571078666132451 | yes |
| structural_mutation | 200106952336, 89494497658324, 3379593298396981 | 200106952336, 89494497658324, 3379593298396981 | yes |
| bulk_structural_mutation | 82740062444, 36564666309410, 1317343499882000, 2285022074625, 82203678997143 | 82740062444, 36564666309410, 1317343499882000, 2285022074625, 82203678997143 | yes |
| line_query | 641440000, 63985556480, 639841600000, 63985600000, 639841547520 | 641440000, 63985556480, 639841600000, 63985600000, 639841547520 | yes |
| line_geometry_query | 160641440000, 267505512960, 799841600000, 223985600000, 852321495040 | 160641440000, 267505512960, 799841600000, 223985600000, 852321495040 | yes |
| column_query | 641440000, 63985556480, 639841600000, 63985600000, 639841560320 | 641440000, 63985556480, 639841600000, 63985600000, 639841560320 | yes |
| column_geometry_query | 160641440000, 267505512960, 799841600000, 223985600000, 839521520640 | 160641440000, 267505512960, 799841600000, 223985600000, 839521520640 | yes |
| point_query | 64166237440, 640022280960, 64166280960, 640022228480 | 64166237440, 640022280960, 64166280960, 640022228480 | yes |
| point_geometry_query | 4687694617200924928, 6036755761047907072, 1712152282485110528, 5915921755926273280 | 4687694617200924928, 6036755761047907072, 1712152282485110528, 5915921755926273280 | yes |

**All 46 checksums across all eleven modes are byte-identical to the Slice 41
baseline. Zero drift.**

**AC4/AC5 anchor confirmed**: the `point_geometry_query` anchor —
`uniform_100k=4687694617200924928`, `uniform_1m=6036755761047907072`,
`prefixsum_100k=1712152282485110528`, `prefixsum_1m=5915921755926273280` —
matches the Slice 41 (and, through it, Slice 40) baseline exactly. This is
the central proof this slice was after: the shell `--window-run-ids` seam
and its Swift-parity guard changed selection *logic and tests*, never the
engine, a provider, a budget literal, the corpus, or any measured workload.

## Concerns

None. All eleven gate modes report `gate=pass` for every scenario; every
checksum matches the Slice 41 baseline byte-for-byte; `swift test` is green
at 300/0 (299 + 1 new test); the guard-is-live break/revert evidence
(copied, not re-run) shows the new test is a real, discriminating guard, not
a tautology; the Foundation-free scan is empty; and the whole-branch diff
vs. `main` touches only shell tooling, one test file, `AGENTS.md`, and this
slice's own plan/spec/verification docs — zero engine or provider paths.

---

## Hosted Proof — Pending

Local evidence above (Sections 1-7) establishes: the new
`testWindowSelectionMatchesDeriveScript` guard is live and green; the shell
`--window-run-ids` seam matches Swift's `mostRecentRunIDs` set-for-set on a
discriminating fixture; the self-test still passes with the trap-cleanup
fold; the Foundation-free scan is clean; the whole-branch diff touches zero
`TextEngineCore`/`TextEngineReferenceProviders` paths; and all eleven local
`--gate` runs report `gate=pass` with every checksum byte-identical to the
Slice 41 baseline — proof no measured path moved.

**This is necessary but not sufficient.** Per `AGENTS.md`'s verification
discipline and the Slices 24-41 anchor-proof-in-the-push-run pattern, the
real proof is the hosted PR-head run and the hosted post-merge `push` run,
both to be read **at step level** (a `continue-on-error` step can conclude
its job green while the step itself failed — the standing Slice 16
dead-step-trap rule).

**To be filled in once CI runs:**

- **PR-head run**: `<pending — PR number and run ID>`
  - All three required jobs (`Host tests and benchmark gate`, `iOS
    cross-target compile`, `WASM cross-target observation`) `success`.
  - All eleven blocking gate steps `success` at step level; log tally
    `46 gate=pass, 0 gate=fail` (all 46 gated scenarios — this slice touches
    no `realistic_provider`-affecting path, but that mode is PR-only and not
    gated regardless).
  - `Run host tests` step: `Executed 300 tests, with 0 failures`.
  - Tightest observed hosted headroom, both statistics, in-band.
- **Post-merge `push` run**: `<pending — merge commit and run ID>`
  - Same step-level checks as above, against the merged-code anchor.
  - Checksum byte-identity reconfirmed on hosted Linux x86_64 for at least
    the `point_geometry_query` anchor scenarios.

This closes **AC8** once both hosted runs are read and recorded here.
