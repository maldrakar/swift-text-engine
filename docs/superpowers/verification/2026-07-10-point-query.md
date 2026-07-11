# 2D Point-Query Verification

Date: 2026-07-11
Branch: `slice-37-point-query`
Local verification HEAD: `c8b26d7` (`c8b26d7f25ead251694fdecd7ebbb80984a19a69`)
Merge base with `main`: `e3a7a28` (`e3a7a28df4e10641617f68f6ec6f07803ef59c2a`)

Spec: `docs/superpowers/specs/2026-07-10-point-query-design.md`
Plan: `docs/superpowers/plans/2026-07-10-point-query.md`

Commits on branch (base `e3a7a28` ← `main`):

```
c8b26d7 docs: describe pointAt 2D composite and its local point-query gate
af17089 feat: add --point-query benchmark mode with local gate
d6bcf5a test: exercise pointAt over prefix-sum reference providers
02a5c16 test: add pointAt composition-parity oracle
990e43d test: pin pointAt failure precedence and horizontal-dispatch contract
ea5c0da feat: add pointAt 2D composite position query
12fa848 docs: add slice 37 2D point-query implementation plan
cdd68b0 docs: use line-agnostic horizontal provider in point benchmark
9f9da4d docs: refine 2D point-query design
75a82de docs: add 2D point-query design
```

This slice adds `ViewportVirtualizer.pointAt(x:y:lineMetrics:columnMetrics:)`
(the first 2D position query, a pure composition of `lineAt` + `columnAt` —
position-only; the geometry-bearing companion `pointGeometryAt` is deferred to
a future slice), three new public result types (`PointQuery`, `PointLocation`,
`ColumnResolution`), the full test suite (17 core tests: `PointAtTests` 11 +
`PointAtDispatchTests` 3 + `PointAtEquivalenceTests` 3; 2 reference-provider
tests: `PointAtReferenceProviderTests`), a **local** `--point-query --gate`,
and `AGENTS.md` docs. No `.github/workflows/swift-ci.yml` change (CI promotion
is a deferred follow-up slice, matching the `columnAt`/`columnGeometryAt`
pattern). `ViewportValidationError` is unchanged — every failure `pointAt`
surfaces is already a case of the existing enum.

## 1. Host tests + release build

```text
$ swift test 2>&1 | tail -5
	 Executed 232 tests, with 0 failures (0 unexpected) in 2.263 (2.274) seconds
◇ Test run started.
↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
↳ Target Platform: arm64-apple-macosx
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

Test count: **232** (Slice 36 baseline 213, **+19** new this slice). Confirmed
per-suite via a full non-truncated run:

```
Test Suite 'PointAtTests' passed — Executed 11 tests, with 0 failures
Test Suite 'PointAtDispatchTests' passed — Executed 3 tests, with 0 failures
Test Suite 'PointAtEquivalenceTests' passed — Executed 3 tests, with 0 failures
Test Suite 'PointAtReferenceProviderTests' passed — Executed 2 tests, with 0 failures
```

11 + 3 + 3 + 2 = 19, matching the plan's expected delta exactly (17 core +
2 reference-provider). 0 failures overall. The "0 tests in 0 suites" line is
the expected empty Swift Testing harness, not a failure.

```text
$ swift build -c release 2>&1 | tail -2
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
```

## 2. New gate: `--point-query --gate`

```text
$ swift run -c release ViewportBenchmarks -- --point-query --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=25 p99_ns=35 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=34 p99_ns=43 failures=0 budget_p95_ns=240000 budget_p99_ns=480000 gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=37 p99_ns=48 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=56 p99_ns=77 failures=0 budget_p95_ns=240000 budget_p99_ns=480000 gate=pass checksum=640022228480
```

All four scenarios `gate=pass`, `failures=0`, exit 0. Per plan Task 5, the
vertical provider varies (`uniform` line metrics vs `prefixsum`
`BalancedTree`-free prefix-sum line metrics) while the horizontal provider is
held constant at the line-agnostic `UniformColumnMetrics` in every scenario.

### Per-scenario headroom (local, macOS arm64) — new point-query baseline

| Scenario | p95 ns | p99 ns | Budget p95 ns | Headroom (budget ÷ p95) | Budget p99 ns | Checksum (this slice's baseline) |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| uniform_100k   | 25 | 35 | 120,000 | 4800.0×  | 240,000 | 64166237440  |
| uniform_1m     | 34 | 43 | 240,000 | 7058.8×  | 480,000 | 640022280960 |
| prefixsum_100k | 37 | 48 | 120,000 | 3243.2×  | 240,000 | 64166280960  |
| prefixsum_1m   | 56 | 77 | 240,000 | 4285.7×  | 480,000 | 640022228480 |

(Observed timings are approximate and non-reproducible run to run; the
deterministic anchor is the checksum set above.) These four checksums are
**new** — this is the first recording of the `--point-query` gate's baseline;
there is no prior slice to compare them against. `prefixsum_1m` (largest line
count on the prefix-sum provider) is the tightest-headroom scenario at
3243.2×–4285.7×, still comfortably inside budget.

## 3. Existing gates — `gate=pass`, no checksum movement

Per the plan's Global Constraints ("Strictly additive... all nine existing
gates must pass with byte-identical checksums") and spec Non-Goals, this slice
touches no shared search or provider path — `pointAt` is pure composition over
the existing `lineAt`/`columnAt` — so every existing gate's checksum must be,
and is, **byte-identical** to the Slice 36 baseline recorded in
`docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md`
(which itself carries forward the Slice 32/33/34/35 baselines unchanged).

```text
$ swift run -c release ViewportBenchmarks -- --gate
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1224 p99_ns=1309 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5001 p99_ns=5181 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16450 p99_ns=16851 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --variable-height --gate
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=206 p99_ns=220 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=659 p99_ns=683 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2009 p99_ns=2078 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=375 p99_ns=415 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1521 p99_ns=1608 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4764 p99_ns=4972 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=927 p99_ns=988 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5107 p99_ns=5319 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=25066 p99_ns=26996 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2637 p99_ns=2790 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=8061 p99_ns=8409 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=38003 p99_ns=40291 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=60513 p99_ns=62226 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=135427 p99_ns=145138 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --line-query --gate
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=12 p99_ns=15 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=15 p99_ns=19 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=17 p99_ns=22 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=85 p99_ns=106 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=118 p99_ns=143 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=18 p99_ns=25 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=18 p99_ns=24 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=21 p99_ns=27 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=129 p99_ns=164 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=180 p99_ns=219 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=852321495040
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --column-query --gate
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=11 p99_ns=14 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=14 p99_ns=18 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=17 p99_ns=24 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=33 p99_ns=41 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=39 p99_ns=46 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841560320
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --column-geometry-query --gate
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=20 p99_ns=22 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=24 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=24 p99_ns=31 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=43 p99_ns=52 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=47 p99_ns=67 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=839521520640
EXIT:0
```

### Checksum-identity table vs 2026-07-10 (Slice 36) baseline

| Gate | Scenario | Baseline checksum (Slice 36 doc) | This run's checksum | Identical? |
| --- | --- | --- | --- | --- |
| `--gate` | 1k_lines_20_visible_overscan_0 | 1319670707200 | 1319670707200 | Y |
| `--gate` | 100k_lines_80_visible_overscan_5 | 570448232307200 | 570448232307200 | Y |
| `--gate` | 1m_lines_200_visible_overscan_50 | 18852477646272000 | 18852477646272000 | Y |
| `--variable-height --gate` | 1k_lines_20_visible_overscan_0 | 231017730560 | 231017730560 | Y |
| `--variable-height --gate` | 100k_lines_80_visible_overscan_5 | 101209179008000 | 101209179008000 | Y |
| `--variable-height --gate` | 1m_lines_200_visible_overscan_50 | 3536425156727040 | 3536425156727040 | Y |
| `--variable-height-mutation --gate` | 1k_lines_20_visible_overscan_0 | 196866548667 | 196866548667 | Y |
| `--variable-height-mutation --gate` | 100k_lines_80_visible_overscan_5 | 88324286099072 | 88324286099072 | Y |
| `--variable-height-mutation --gate` | 1m_lines_200_visible_overscan_50 | 3571078666132451 | 3571078666132451 | Y |
| `--structural-mutation --gate` | 1k_lines_20_visible_overscan_0 | 200106952336 | 200106952336 | Y |
| `--structural-mutation --gate` | 100k_lines_80_visible_overscan_5 | 89494497658324 | 89494497658324 | Y |
| `--structural-mutation --gate` | 1m_lines_200_visible_overscan_50 | 3379593298396981 | 3379593298396981 | Y |
| `--bulk-structural-mutation --gate` | 1k_lines_batch_64 | 82740062444 | 82740062444 | Y |
| `--bulk-structural-mutation --gate` | 100k_lines_batch_64 | 36564666309410 | 36564666309410 | Y |
| `--bulk-structural-mutation --gate` | 1m_lines_batch_64 | 1317343499882000 | 1317343499882000 | Y |
| `--bulk-structural-mutation --gate` | 100k_lines_batch_4096 | 2285022074625 | 2285022074625 | Y |
| `--bulk-structural-mutation --gate` | 1m_lines_batch_4096 | 82203678997143 | 82203678997143 | Y |
| `--line-query --gate` | uniform_1k | 641440000 | 641440000 | Y |
| `--line-query --gate` | uniform_100k | 63985556480 | 63985556480 | Y |
| `--line-query --gate` | uniform_1m | 639841600000 | 639841600000 | Y |
| `--line-query --gate` | balanced_tree_100k | 63985600000 | 63985600000 | Y |
| `--line-query --gate` | balanced_tree_1m | 639841547520 | 639841547520 | Y |
| `--line-geometry-query --gate` | uniform_1k | 160641440000 | 160641440000 | Y |
| `--line-geometry-query --gate` | uniform_100k | 267505512960 | 267505512960 | Y |
| `--line-geometry-query --gate` | uniform_1m | 799841600000 | 799841600000 | Y |
| `--line-geometry-query --gate` | balanced_tree_100k | 223985600000 | 223985600000 | Y |
| `--line-geometry-query --gate` | balanced_tree_1m | 852321495040 | 852321495040 | Y |
| `--column-query --gate` | uniform_1k | 641440000 | 641440000 | Y |
| `--column-query --gate` | uniform_100k | 63985556480 | 63985556480 | Y |
| `--column-query --gate` | uniform_1m | 639841600000 | 639841600000 | Y |
| `--column-query --gate` | prefixsum_100k | 63985600000 | 63985600000 | Y |
| `--column-query --gate` | prefixsum_1m | 639841560320 | 639841560320 | Y |
| `--column-geometry-query --gate` | uniform_1k | 160641440000 | 160641440000 | Y |
| `--column-geometry-query --gate` | uniform_100k | 267505512960 | 267505512960 | Y |
| `--column-geometry-query --gate` | uniform_1m | 799841600000 | 799841600000 | Y |
| `--column-geometry-query --gate` | prefixsum_100k | 223985600000 | 223985600000 | Y |
| `--column-geometry-query --gate` | prefixsum_1m | 839521520640 | 839521520640 | Y |

All 36 checksums across all **nine** existing gates (`--gate`,
`--variable-height`, `--variable-height-mutation`, `--structural-mutation`,
`--bulk-structural-mutation`, `--line-query`, `--line-geometry-query`,
`--column-query`, `--column-geometry-query`) are byte-identical to the Slice 36
baseline recorded in
`docs/superpowers/verification/2026-07-10-column-geometry-query-ci-gate-promotion.md`
— which itself carries the values forward unchanged from Slice 32/33/34/35.
All scenarios report `gate=pass`, `failures=0`. This confirms the plan's
strict-additivity constraint: `pointAt` is pure composition over the existing
`lineAt`/`columnAt` search paths — no existing algorithm, provider, or search
code was touched.

## 4. Memory-shape invariant

```text
$ swift run -c release ViewportBenchmarks -- --memory-shape
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
EXIT:0
```

`invariant=pass` on every scenario, `core_owned_bytes` byte-identical per
provider to the Slice 36 baseline — this diagnostic doesn't exercise
`pointAt` directly, but its being unaffected corroborates that no shared core
memory-shape path was touched. `pointAt` itself is O(1) core memory by
construction (Global Constraints): it allocates nothing beyond the returned
value structs and delegates all searching to `lineAt`/`columnAt`.

## 5. Foundation-free scans

```text
$ rg -n "Foundation" Sources/TextEngineCore; echo "core exit=$?"
core exit=1

$ rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "refprov exit=$?"
refprov exit=1
```

No matches in either target (exit 1 = ripgrep found nothing). Both targets
remain Foundation-free — including the new `PointQuery`/`PointLocation`/
`ColumnResolution` types and `PointAtReferenceProviderTests`.

## 6. Cross-target compile self-test

```text
$ ./.github/scripts/cross-target-compile.sh --self-test
self_test=pass
EXIT:0
```

The shell-logic self-test (no toolchain required) passes. Per the plan's Task
7 Step 1 scope, the full iOS (blocking) and WASM (observational) cross-target
compiles are not re-run locally in this task — they are proven per-PR by the
hosted CI job (`iOS cross-target compile`) and will be part of the hosted
proof captured in the post-merge follow-up below, consistent with how prior
public-API-adding slices (e.g. Slice 33/35) anchored their cross-target
correctness in the hosted run.

## Working tree

`git status` before and after this entire verification run reported "nothing
to commit, working tree clean" (aside from this new verification doc) — no
source, test, benchmark, or CI files were modified by any command above.

## Notes

- Strictly additive slice: all 36 checksums across the nine existing gates are
  byte-identical to the Slice 36 baseline (see the checksum-identity table
  above), confirming `pointAt` touches no shared search or provider path.
  `pointAt` composes `lineAt` (vertical) then `columnAt` (horizontal, only on
  vertical success) and adds no new search code, no new metrics protocol, no
  new provider, and no new `ViewportValidationError` case.
- No CI workflow changes were made in this slice — the new
  `--point-query --gate` is intentionally local-only until a future
  CI-promotion slice, matching the established pattern
  (`--column-query`: Slice 33→34; `--line-geometry-query`: Slice 31→32;
  `--column-geometry-query`: Slice 35→36).
- Hosted proof is intentionally deferred to the post-merge follow-up, per the
  project's stale-on-write lesson (a verification doc committed before the
  PR's final head would otherwise cite a run ID that doesn't correspond to
  the merged code).

## Post-Review Corrections (2026-07-11)

A pre-merge review of the slice against its spec found no P0/P1 and no functional
defect, but three descriptions that overclaimed. All three were corrected; **no
algorithm, budget, scenario, or result type changed**, so every number above still
holds (re-confirmed below).

1. **`PointQuery.swift` doc comment overstated the validation ordering.** It read as
   an unconditional "a non-finite coordinate ... is checked before *either* axis's
   zero-count short-circuit", but `pointAt(x: .nan, y: 0.0, lineMetrics: <lineCount 0>)`
   correctly returns `.empty`: the vertical query short-circuits on the empty document
   and `x` is never examined. The code is right (and pinned by
   `PointAtEquivalenceTests.testParityEmptyDocument`); the comment now states the real
   contract — each 1D query validates its own coordinate before its own zero-count
   branch, and `x` is only ever examined by the horizontal query.
2. **The benchmark's provider-path claim was factually wrong.** The scenario comment
   (and the spec's Benchmark Mode section) said the uniform vertical scenarios cover an
   "O(1) native-arithmetic vertical path". `UniformLineMetrics` does **not** override
   `lineIndex(containingOffset:)`, and `UniformColumnMetrics` does not override
   `columnIndex(containingOffset:inLine:)` — so all four point scenarios take the
   **generic binary-search fallback on both axes**, and the vertical variation is only in
   how `offset(ofLine:)` is answered (arithmetic vs prefix-sum array read). Corrected in
   both places, since the follow-up CI-promotion slice would otherwise reason about gate
   coverage from a false premise.
3. **The spec asked the workload to exercise "at least one blank line", which its own
   provider choice makes impossible.** `UniformColumnMetrics` gives every line the same
   non-zero cell count, so `.blankLine` is unreachable in all four scenarios. The spec now
   says so explicitly and records why that is the right trade (a blank line short-circuits
   `columnAt` early, so it would only *lower* measured latency). Blank-line correctness
   stays covered by `PointAtTests`, the equivalence oracle, and the reference-provider test.

Additionally, `PointAtTests` now pins the two failure cases the spec's Testing Strategy
enumerated but the suite had not covered: `.invalidLineMetrics` (vertical
`offset(ofLine: 0) != 0`) and `.invalidColumnMetrics` (horizontal
`columnOffset(inLine:column: 0) != 0`). Both were added as assertions inside the existing
`testVerticalFailureShortCircuits` / `testHorizontalFailureSurfaces` tests, so the **test
count is unchanged at 232**.

Re-verification at the corrected head:

```text
$ swift test 2>&1 | grep "Executed 232"
	 Executed 232 tests, with 0 failures (0 unexpected) in 2.290 (2.301) seconds

$ swift build -c release 2>&1 | tail -1
Build complete! (2.46s)

$ swift run -c release ViewportBenchmarks -- --point-query --gate
mode=point_query provider=uniform scenario=uniform_100k ... gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m ... gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k ... gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m ... gate=pass checksum=640022228480
EXIT:0

$ rg -n "Foundation" Sources/TextEngineCore; echo "core exit=$?"
core exit=1

$ git diff --check
(no output, exit 0)
```

All four `--point-query` checksums are **byte-identical** to the §2 baseline above,
confirming the corrections are comment/doc/test-only and moved no measured path. The nine
existing gates were independently re-run during the review at branch head `25832de` and all
36 checksums matched the §3 table byte-for-byte.

**Head note.** §1–§6 above were recorded at `c8b26d7`. Two later commits touch
`Sources/TextEngineCore/PointQuery.swift` (doc comment only: `25832de`, and correction 1
above) plus the benchmark comment and the two added assertions. None changes an algorithm,
and every command above was re-run at the corrected head with identical results, so the
recorded evidence covers the final head.

## Hosted Proof

Filled in the post-merge follow-up against the stable final head, per the
project's standing stale-on-write lesson (Slice 26 and every slice since). Both
runs were verified at **step level**, not by job conclusion, per the "a green job
can hide a dead `continue-on-error` step" lesson.

- **PR-head run: `29150235152`** — PR #77, head
  `033e7309f235e72a7af8155e4a63772b8640ca16` (`033e730`), event `pull_request`;
  conclusion `success`, all three required jobs `success`.
- **Post-merge push run: `29150501304`** — merge commit
  `ba51a33b5fae5d98c322306976d03845700b0dc8` (`ba51a33`), event `push`, branch
  `main`; conclusion `success`, all three required jobs `success`. **This is the
  merged-code evidence anchor for Slice 37.**

Merge parentage confirms the proof anchors the actually-merged head:
`git rev-list --parents -1 ba51a33` → `ba51a33 e3a7a28 033e730`, so `ba51a33^2`
is exactly the head that run `29150235152` tested.

### Step-level detail (post-merge push run `29150501304`)

`Host tests and benchmark gate` — every step `success`:

| Step | Name | Conclusion |
| ---: | --- | --- |
| 5 | Complete docs-only PR | `skipped` — correct: the merge carries Swift, so the heavy path runs |
| 7 | Run host tests | `success` — **`Executed 232 tests, with 0 failures`** on merged code |
| 8–16 | The nine blocking latency gates (synthetic, variable-height, variable-height-mutation, structural-mutation, bulk-structural-mutation, line-query, line-geometry-query, column-query, column-geometry-query) | all `success` |
| 17 | Run memory shape diagnostic | `success` |
| 18 | Run RSS memory observation diagnostic | `success` |
| 19 | Observe realistic provider relative performance | `skipped` — correct: PR-only; it ran `success` in the PR-head run |

`iOS cross-target compile` = `success` (the `Compile cross-target packages for
iOS` step ran, not skipped); `WASM cross-target observation` = `success`.

**`--point-query` is correctly absent from the hosted run.** `grep -c
"mode=point_query"` over the full push-run log returns **0** — the gate is
local-only this slice by design (Decision 6), and no workflow step invokes it.
Promoting it to a blocking hosted gate is the deferred follow-up slice.

### Hosted checksums cross-checked against the local record

Extracted from the push run's own gate-step logs (verified, not asserted): every
hosted query-gate checksum is **byte-identical** to the §3 local table —
`line_query` (`641440000`, `63985556480`, `639841600000`, `63985600000`,
`639841547520`), `line_geometry_query` (`160641440000`, `267505512960`,
`799841600000`, `223985600000`, `852321495040`), `column_query` (`641440000`,
`63985556480`, `639841600000`, `63985600000`, `639841560320`), and
`column_geometry_query` (`160641440000`, `267505512960`, `799841600000`,
`223985600000`, `839521520640`). Slice 37 moved no measured path on hosted Linux
x86_64 either.
