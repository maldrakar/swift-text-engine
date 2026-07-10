# Column-Geometry-Query CI Gate Promotion Verification

Date: 2026-07-10
Branch: `slice-36-column-geometry-query-ci-gate-promotion`
Local verification HEAD: `422b7ff`

## Change Scope

`git diff --name-only 95b735e..HEAD` — only `.github/workflows/swift-ci.yml`,
`AGENTS.md`, and `docs/**`. No benchmark or core Swift source changed.

```
$ git diff --name-only 95b735e..HEAD
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/plans/2026-07-10-column-geometry-query-ci-gate-promotion.md
docs/superpowers/specs/2026-07-10-column-geometry-query-ci-gate-promotion-design.md
```

(This verification doc itself lands under `docs/**` in the same commit that
produced this record.)

## Workflow-Invariant Assertion

The new step exists, invokes `--column-geometry-query --gate`, is not
`continue-on-error`, shares its sibling's docs-only guard, is ordered
column-query → column-geometry-query → memory-shape, and the three required
job context names (`Host tests and benchmark gate`, `iOS cross-target
compile`, `WASM cross-target observation`) are unchanged.

```
$ ruby "$SCRATCH/wf_assert.rb"
workflow_assertions_ok
```

The assertion script (`$SCRATCH/wf_assert.rb`, created in Task 1, not
committed) parses `.github/workflows/swift-ci.yml` with Ruby's YAML loader and
checks, in order:

1. a step named "Run column geometry query benchmark gate" exists in the
   `host-tests-and-benchmark-gate` job;
2. its `run:` command includes `--column-geometry-query --gate`;
3. it does **not** set `continue-on-error` (a regression fails the job);
4. its `if:` guard is identical to the sibling "Run column query benchmark
   gate" step's guard (both skip under the docs-only short-circuit);
5. step ordering is column-query → column-geometry-query → memory-shape;
6. the three required job context names are unchanged.

Corroborated directly against the workflow file:

```
$ grep -n -A3 "column geometry query\|column query\|memory shape" .github/workflows/swift-ci.yml
      - name: Run column query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate

      - name: Run column geometry query benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-geometry-query --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

## Column-Geometry-Query Gate (local, the new 9th blocking gate)

```
$ swift run -c release ViewportBenchmarks -- --column-geometry-query --gate
Building for production...
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=20 p99_ns=22 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=24 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=24 p99_ns=31 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=43 p99_ns=52 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=47 p99_ns=67 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=839521520640
EXIT:0
```

All five rows `gate=pass`, `failures=0`.

### Benchmark-Unchanged Integrity Check

The five per-scenario `column_geometry_query` checksums are byte-identical to
the Slice 35 values, proving the benchmark workload itself is unchanged by this
promotion (this slice only adds a CI workflow step and docs — no benchmark or
core source edits):

| Scenario | Checksum | Slice 35 value | Match |
| --- | --- | --- | --- |
| uniform_1k     | 160641440000 | 160641440000 | matches |
| uniform_100k   | 267505512960 | 267505512960 | matches |
| uniform_1m     | 799841600000 | 799841600000 | matches |
| prefixsum_100k | 223985600000 | 223985600000 | matches |
| prefixsum_1m   | 839521520640 | 839521520640 | matches |

### Per-Scenario Headroom (local, macOS arm64)

| Scenario | Observed p95 ns | Budget p95 ns | Headroom (budget ÷ obs) | Budget p99 ns | Observed p99 ns |
| --- | ---: | ---: | ---: | ---: | ---: |
| uniform_1k     | 20 | 30,000  | 1500.0× | 60,000  | 22 |
| uniform_100k   | 21 | 60,000  | 2857.1× | 120,000 | 24 |
| uniform_1m     | 24 | 120,000 | 5000.0× | 240,000 | 31 |
| prefixsum_100k | 43 | 60,000  | 1395.3× | 120,000 | 52 |
| prefixsum_1m   | 47 | 120,000 | 2553.2× | 240,000 | 67 |

(Observed timings are approximate and non-reproducible run to run; the
deterministic anchor is the checksum set above, which is byte-identical to
Slice 35.)

## Pre-existing Gates Still Pass (all eight)

```
$ swift run -c release ViewportBenchmarks -- --column-query --gate
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=11 p99_ns=15 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=14 p99_ns=17 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=17 p99_ns=22 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=36 p99_ns=43 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=36 p99_ns=47 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841560320
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=18 p99_ns=21 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=18 p99_ns=23 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=21 p99_ns=26 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=137 p99_ns=169 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=169 p99_ns=217 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=852321495040
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --line-query --gate
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=11 p99_ns=16 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=14 p99_ns=20 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=18 p99_ns=24 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=79 p99_ns=97 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=114 p99_ns=137 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --gate
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1200 p99_ns=1268 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4953 p99_ns=5140 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16408 p99_ns=16695 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --variable-height --gate
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=220 p99_ns=246 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=678 p99_ns=699 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2062 p99_ns=2132 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=379 p99_ns=414 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1509 p99_ns=1592 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4770 p99_ns=4918 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=923 p99_ns=988 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5196 p99_ns=5482 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=26062 p99_ns=28232 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2625 p99_ns=2724 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=8186 p99_ns=8447 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=40433 p99_ns=43044 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=61604 p99_ns=63994 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=138835 p99_ns=151510 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
EXIT:0
```

All eight pre-existing gates `gate=pass`, `failures=0`; checksums unmoved from
their established baselines (spot-checked against the values already recorded
in the Slice 32/33/34/35 verification docs).

## Host Tests

```
$ swift test 2>&1 | tail -5
Test Suite 'ViewportValidationTests' passed at 2026-07-10 19:43:32.442.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-10 19:43:32.442.
	 Executed 213 tests, with 0 failures (0 unexpected) in 2.375 (2.385) seconds
Test Suite 'All tests' passed at 2026-07-10 19:43:32.442.
	 Executed 213 tests, with 0 failures (0 unexpected) in 2.375 (2.386) seconds
```

213 tests, 0 failures, plus the benign empty Swift Testing harness line ("0
tests in 0 suites passed") that is not a failure.

```
$ git diff --check; echo "diff-check-exit=$?"
diff-check-exit=0
```

No whitespace-error regressions in the branch diff.

## Foundation-Free Scan

```
$ rg -n "Foundation" Sources/TextEngineCore ; echo "rg-exit=$?"
rg-exit=1
```

No matches — `Sources/TextEngineCore` remains Foundation-free (exit 1 = ripgrep
found nothing, which is the expected/correct result for this scan).

## Scope Proof

```
$ git diff --name-only 95b735e..HEAD
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/plans/2026-07-10-column-geometry-query-ci-gate-promotion.md
docs/superpowers/specs/2026-07-10-column-geometry-query-ci-gate-promotion-design.md
```

Base `95b735e` is the Slice 35 post-slice-review merge commit. Everything since
then touches only the CI workflow, `AGENTS.md`, and files under `docs/**`
(design, plan, and this verification record) — no Swift source, benchmark, or
provider file changed, consistent with a promotion-only slice.

## Hosted Proof

Recorded post-merge, once the head SHA was stable (per the clean-evidence
convention / Decision 3 documented in the slice plan). Both hosted runs are
green at **step level** — not merely at job conclusion — on `ubuntu-latest`
with `swift:6.2.1-bookworm` (Linux x86_64).

**PR-head run — [`29108998305`](https://github.com/maldrakar/swift-text-engine/actions/runs/29108998305)**
(`pull_request` event, head `bb24c95`):

- All three required contexts `success`: `Host tests and benchmark gate`,
  `iOS cross-target compile`, `WASM cross-target observation`.
- Host job step `Run column geometry query benchmark gate` = `success` (not
  skipped, not `continue-on-error`), sitting between `Run column query
  benchmark gate` and `Run memory shape diagnostic` — the nine blocking
  latency gates stay contiguous.
- `Complete docs-only PR` step skipped: this PR touches
  `.github/workflows/**`, so the heavy path ran, exactly as designed.

**Post-merge push run — [`29110714042`](https://github.com/maldrakar/swift-text-engine/actions/runs/29110714042)**
(`push` event, merge commit `52a2eaf` on `main`) — the anchor proof of merged
behavior:

- All three required contexts `success`; the new gate step `Run column
  geometry query benchmark gate` = `success`.
- `Observe realistic provider relative performance` step **skipped** on push
  (it is PR-only), confirming the event-scoped guard behaves as designed on
  `main`.

Both runs pass all five `column_geometry_query` scenarios (`gate=pass`,
`failures=0`) with the five checksums **byte-identical** to the Slice 35
values, so the promoted benchmark workload is provably unchanged on hosted
Linux as well as locally:

| scenario | budget p95 (ns) | PR-head p95 / p99 (ns) | push p95 / p99 (ns) | push headroom (p95) | checksum |
|---|---|---|---|---|---|
| uniform_1k | 30 000 | 32 / 63 | 34 / 63 | ~882× | 160641440000 |
| uniform_100k | 60 000 | 43 / 73 | 46 / 75 | ~1 304× | 267505512960 |
| uniform_1m | 120 000 | 48 / 79 | 52 / 84 | ~2 308× | 799841600000 |
| **prefixsum_100k** | 60 000 | 70 / 106 | 67 / 105 | ~895× | 223985600000 |
| **prefixsum_1m** | 120 000 | 82 / 121 | 74 / 109 | ~1 622× | 839521520640 |

Watch-scenario outcome as predicted: **`prefixsum_100k`** held the least
multiplicative hosted headroom (~857× PR-head, ~895× post-merge) and
**`prefixsum_1m`** the largest absolute latency (82 ns p95 PR-head, 74 ns
post-merge) — both comfortably inside budget. Decision 3's stop-and-retune
path was therefore **not** triggered: no `continue-on-error`, no budget
widening. The nine blocking latency gates now run contiguously on every
hosted PR and push.
