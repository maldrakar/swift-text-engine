# Column-Query CI Gate Promotion Verification

Date: 2026-07-05
Branch: `slice-34-column-query-ci-gate`
Local verification HEAD: `9dc717f`

## Change Scope

`git diff --name-only main...HEAD` — only `.github/workflows/swift-ci.yml`,
`AGENTS.md`, and `docs/**`. No benchmark or core Swift source changed.

```
$ git diff --name-only main...HEAD
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/plans/2026-07-05-column-query-ci-gate-promotion.md
docs/superpowers/specs/2026-07-05-column-query-ci-gate-promotion-design.md
```

## Workflow-Invariant Assertion

The new step exists, invokes `--column-query --gate`, is not `continue-on-error`,
shares its siblings' docs-only guard, is ordered line-geometry-query →
column-query → memory-shape, and the three required job context names are
unchanged.

```
$ ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/24c7be6e-bb8b-4d14-8a4a-bf5696f47e5d/scratchpad/assert_column_query_gate.rb
workflow_assertions_ok
EXIT:0
```

## Column-Query Gate (local)

```
$ swift run -c release ViewportBenchmarks -- --column-query --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.11s)
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=14 p99_ns=14 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=14 p99_ns=18 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=18 p99_ns=19 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=30 p99_ns=42 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=41 p99_ns=55 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841560320
EXIT:0
```

### Benchmark-Unchanged Integrity Check

The five per-scenario `column_query` checksums are byte-identical to the Slice 33
values, proving the benchmark workload is unchanged:

| Scenario | Checksum | Slice 33 value | Match |
| --- | --- | --- | --- |
| uniform_1k     | 641440000     | 641440000     | ✅ |
| uniform_100k   | 63985556480   | 63985556480   | ✅ |
| uniform_1m     | 639841600000  | 639841600000  | ✅ |
| prefixsum_100k | 63985600000   | 63985600000   | ✅ |
| prefixsum_1m   | 639841560320  | 639841560320  | ✅ |

### Per-Scenario Headroom (local, macOS arm64)

| Scenario | Observed p95 ns | Budget p95 ns | Headroom (budget ÷ obs) | Budget p99 ns |
| --- | ---: | ---: | ---: | ---: |
| uniform_1k     | 14 | 30,000  | 2142.9× | 60,000  |
| uniform_100k   | 14 | 60,000  | 4285.7× | 120,000 |
| uniform_1m     | 18 | 120,000 | 6666.7× | 240,000 |
| prefixsum_100k | 30 | 60,000  | 2000.0× | 120,000 |
| prefixsum_1m   | 41 | 120,000 | 2926.8× | 240,000 |

(Observed timings are approximate and non-reproducible; the deterministic anchor
is the checksum set above.)

## Pre-existing Gates Still Pass

```
$ swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=19 p99_ns=24 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=23 p99_ns=35 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=23 p99_ns=30 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=129 p99_ns=156 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=173 p99_ns=218 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=852321495040
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --line-query --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=12 p99_ns=14 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=17 p99_ns=22 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=17 p99_ns=23 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=79 p99_ns=99 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=109 p99_ns=123 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1196 p99_ns=1269 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4864 p99_ns=5070 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16167 p99_ns=16495 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --variable-height --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=208 p99_ns=243 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=661 p99_ns=681 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2021 p99_ns=2125 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=375 p99_ns=416 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1502 p99_ns=1563 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4746 p99_ns=4929 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=915 p99_ns=976 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5026 p99_ns=5300 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=23593 p99_ns=25974 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
EXIT:0
```

```
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2582 p99_ns=2632 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=7970 p99_ns=8450 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=47102 p99_ns=49768 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=62567 p99_ns=65343 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=175635 p99_ns=185591 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
EXIT:0
```

## Host Tests

```
$ swift test
...
Executed 189 tests, with 0 failures (0 unexpected) in 2.461 (2.470) seconds
Test Suite 'All tests' passed at 2026-07-06 22:11:43.766.
	 Executed 189 tests, with 0 failures (0 unexpected) in 2.461 (2.471) seconds
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

189 tests, 0 failures, plus the harmless empty Swift Testing harness line
("0 tests in 0 suites").

Also confirmed: `git diff --check` produced no output (exit 0) — no
whitespace-error regressions in the branch diff.

## Foundation-Free Scan

```
$ rg -n "Foundation" Sources/TextEngineCore; echo "core exit: $?"
core exit: 1
```

No matches — `Sources/TextEngineCore` remains Foundation-free.

## Hosted Proof

Recorded post-merge against the stable final PR-head SHA and the merge commit.

- **PR:** #68 (`slice-34-column-query-ci-gate` → `main`), MERGED 2026-07-06,
  merge commit `2281f00`.
- **Final PR-head run:** `28818762407` (event `pull_request`, head `e55dfc0`) —
  all three required contexts `success` (Host tests and benchmark gate 8m9s,
  iOS 35s, WASM 36s).
- **Post-merge push run:** `28819411144` (event `push`, head `2281f00` = merge
  commit) — `success`; all three required jobs `success`.

### Step-Level Proof (not just job conclusion)

Verified via `gh run view --json jobs` on both runs' `Host tests and benchmark
gate` job. The `Run column query benchmark gate` step is a real, blocking,
non-skipped step in the correct position:

| Run | Step #14 | Step #15 | Step #16 | docs-only step #5 |
| --- | --- | --- | --- | --- |
| PR-head `28818762407` | Run line geometry query benchmark gate → success | **Run column query benchmark gate → success** | Run memory shape diagnostic → success | Complete docs-only PR → skipped |
| push `28819411144` | Run line geometry query benchmark gate → success | **Run column query benchmark gate → success** | Run memory shape diagnostic → success | Complete docs-only PR → skipped |

The column-query gate ran (not skipped), is ordered line-geometry-query →
column-query → memory-shape, and carries no `continue-on-error` (a failure would
fail the job). The `Complete docs-only PR` short-circuit was correctly **skipped**
on both runs because the merged change touches `.github/workflows/**` (source-
bearing), so the full eight-gate heavy path executed.

### Hosted Linux `column_query` Rows — budget-fit evidence (PR-head run `28818762407`)

All five scenarios `gate=pass`, `failures=0`, on hosted Linux x86_64
(`swift:6.2.1-bookworm`). Checksums byte-identical to the Slice 33 record,
proving the benchmark workload is unchanged across the promotion.

| Scenario | Observed p95 ns | Observed p99 ns | Budget p95 ns | Hosted headroom (budget ÷ p95) | Budget p99 ns | Checksum |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| uniform_1k     | 26 | 31  | 30,000  | 1153.8× | 60,000  | 641440000    |
| uniform_100k   | 38 | 67  | 60,000  | 1578.9× | 120,000 | 63985556480  |
| uniform_1m     | 44 | 73  | 120,000 | 2727.3× | 240,000 | 639841600000 |
| prefixsum_100k | 55 | 94  | 60,000  | 1090.9× | 120,000 | 63985600000  |
| prefixsum_1m   | 63 | 110 | 120,000 | 1904.8× | 240,000 | 639841560320 |

The `prefixsum_1m` watch-scenario (spec Decision 3 — the realistic
proportional-advance path at the largest cell count) clears its p95 budget by
1904.8× and its p99 budget (120→240k) by a comparable margin on hosted Linux;
the macOS-calibrated budgets fit Linux with wide headroom, so no retune is
needed. (`prefixsum_100k` holds the numerically tightest hosted headroom at
1090.9×, still ~1090× under budget.)

### Merged-Behavior Anchor (push run `28819411144`, merge commit `2281f00`)

The merge commit's own run re-executes the gate with identical checksums and all
rows `gate=pass`, anchoring the merged workflow behavior (timings differ run to
run, as expected; the deterministic anchor is the checksum set):

| Scenario | p95 ns | p99 ns | Budget p95 ns | Checksum | gate |
| --- | ---: | ---: | ---: | --- | --- |
| uniform_1k     | 24 | 54  | 30,000  | 641440000    | pass |
| uniform_100k   | 35 | 66  | 60,000  | 63985556480  | pass |
| uniform_1m     | 40 | 72  | 120,000 | 639841600000 | pass |
| prefixsum_100k | 57 | 93  | 60,000  | 63985600000  | pass |
| prefixsum_1m   | 79 | 122 | 120,000 | 639841560320 | pass |
