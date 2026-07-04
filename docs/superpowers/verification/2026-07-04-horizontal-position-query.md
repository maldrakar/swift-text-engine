# Horizontal Position-Query Verification

Date: 2026-07-04
Branch: `slice-33-horizontal-position-query`
Local verification HEAD: `a8b1028f26ba862bd298a61e873bc9fd27122023` (`a8b1028`)

## Hosted Proof

Pending. Per the project's standing stale-on-write lesson, hosted proof (PR-head
run and post-merge push run) is recorded in the post-merge follow-up against the
stable final head, not against a pre-final commit.

- PR-head run ID: Pending
- Post-merge push run ID: Pending

## Host Tests And Release Build

Command:

```bash
swift test
```

Result: exit 0.

Relevant output:

```text
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-04 18:30:49.814.
	 Executed 188 tests, with 0 failures (0 unexpected) in 2.332 (2.340) seconds
Test Suite 'All tests' passed at 2026-07-04 18:30:49.814.
	 Executed 188 tests, with 0 failures (0 unexpected) in 2.332 (2.341) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

The 188 XCTest tests are the prior baseline of 160 (recorded in the 2026-07-03
verification doc) plus 28 new tests added across Slice 33's tasks:
`LineHorizontalMetricsSourceTests`, `ColumnAtTests`, `ColumnAtEquivalenceTests`,
`ColumnAtQueryCountTests`, and `PrefixSumColumnMetricsTests`. The "0 tests in 0
suites" line is the expected empty Swift Testing harness, not a failure.

Command:

```bash
swift build -c release
```

Result: exit 0.

Output:

```text
Building for production...
Build complete! (0.09s)
```

## New Column-Query Gate

Command:

```bash
swift run -c release ViewportBenchmarks -- --column-query --gate
```

Result: exit 0. All five scenarios `gate=pass`.

Output:

```text
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=13 p99_ns=15 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=14 p99_ns=20 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=17 p99_ns=22 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=30 p99_ns=42 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=41 p99_ns=45 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841560320
```

Checksums are byte-identical to those recorded during calibration in Task 6
(`641440000`, `63985556480`, `639841600000`, `63985600000`, `639841560320`),
confirming determinism across the intervening commits (Tasks 7 documentation-only
changes made no algorithmic difference).

Budget decision: no budget adjustments were made (see Task 6 report) — the
starting budgets, copied from the `--line-query` sibling's uniform shape, were
already well-calibrated. All five scenarios pass with ~1000x-5000x headroom.

## Existing Gates: Checksum-Identity Against 2026-07-03 Baseline

This slice changed no existing algorithm (strictly additive: new protocol,
new query, new providers, new benchmark mode). Every existing gate's checksum
must be — and is — byte-identical to the baseline recorded in
`docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md`.

| Gate | Scenario | Baseline checksum (2026-07-03) | This run's checksum | Identical? |
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

All 27 checksums across all 7 existing gates are byte-identical to baseline.
All scenarios report `gate=pass`.

Full output:

```text
$ swift run -c release ViewportBenchmarks -- --gate
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1200 p99_ns=1276 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4903 p99_ns=5017 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16257 p99_ns=16567 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

```text
$ swift run -c release ViewportBenchmarks -- --variable-height --gate
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=205 p99_ns=227 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=672 p99_ns=689 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2013 p99_ns=2057 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

```text
$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=380 p99_ns=403 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1523 p99_ns=1581 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4835 p99_ns=4952 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
```

```text
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1011 p99_ns=1040 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5692 p99_ns=5925 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=23859 p99_ns=25509 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

```text
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2629 p99_ns=2698 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=7960 p99_ns=8110 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=36439 p99_ns=38515 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=60994 p99_ns=62377 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=135679 p99_ns=143802 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

```text
$ swift run -c release ViewportBenchmarks -- --line-query --gate
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=13 p99_ns=16 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=16 p99_ns=16 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=19 p99_ns=22 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=74 p99_ns=94 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=118 p99_ns=138 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
```

```text
$ swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=16 p99_ns=21 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=21 p99_ns=28 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=22 p99_ns=31 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=129 p99_ns=170 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=176 p99_ns=217 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=852321495040
```

## Memory-Shape Invariant

Command:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: exit 0.

Output:

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
```

`invariant=pass` on every scenario. `UniformColumnMetrics` (the new core
provider) is not exercised by this diagnostic's scenarios directly, but it adds
no per-line storage by construction (computed columns-per-line x column-width,
matching the existing `UniformLineMetrics` shape), consistent with the
core-owned-memory invariant.

## Foundation-Free Scans

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore; echo "core exit: $?"
rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "providers exit: $?"
```

Result: no matches in either target.

Output:

```text
core exit: 1
providers exit: 1
```

## Cross-Target Compile

Command:

```bash
./.github/scripts/cross-target-compile.sh --self-test
```

Result: exit 0.

Output:

```text
self_test=pass
```

Command:

```bash
./.github/scripts/cross-target-compile.sh --targets ios
```

Result: exit 0. iOS is **blocking** — both `TextEngineCore` (now including
`UniformColumnMetrics`, `LineHorizontalMetricsSource`, `ColumnQuery`,
`ColumnLocation`) and `TextEngineReferenceProviders` (now including
`PrefixSumColumnMetrics`) compile clean for device and simulator.

Output:

```text
cross_target_swift_version=6.2.1
cross_target_developer_dir=unset
cross_target_xcode_select_path=/Applications/Xcode_26_3.app/Contents/Developer
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
cross_target_iphoneos_sdk_path=/Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk
cross_target_iphoneos_sdk_version=26.2
cross_target_iphonesimulator_sdk_path=/Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk
cross_target_iphonesimulator_sdk_version=26.2
mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator package=core result=pass reason=none blocking=true
mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile target=ios_device package=providers result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator package=providers result=pass reason=none blocking=true
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

Command:

```bash
./.github/scripts/cross-target-compile.sh --targets wasm
```

Result: exit 0. WASM is **observational**; a matching Swift SDK is provisioned
locally, so both `wasm` and `wasm-embedded` actually compiled (not a skip) for
both `TextEngineCore` and `TextEngineReferenceProviders`.

Output:

```text
cross_target_swift_version=6.2.1
cross_target_wasm_sdk_id target=wasm package=core id=swift-6.2.1-RELEASE_wasm
mode=cross_target_compile target=wasm package=core result=pass reason=none blocking=false
cross_target_wasm_sdk_id target=wasm_embedded package=core id=swift-6.2.1-RELEASE_wasm-embedded
mode=cross_target_compile target=wasm_embedded package=core result=pass reason=none blocking=false
mode=cross_target_compile_summary package=core ios_device=skipped ios_simulator=skipped wasm=pass wasm_embedded=pass
cross_target_wasm_sdk_id target=wasm package=providers id=swift-6.2.1-RELEASE_wasm
mode=cross_target_compile target=wasm package=providers result=pass reason=none blocking=false
cross_target_wasm_sdk_id target=wasm_embedded package=providers id=swift-6.2.1-RELEASE_wasm-embedded
mode=cross_target_compile target=wasm_embedded package=providers result=pass reason=none blocking=false
mode=cross_target_compile_summary package=providers ios_device=skipped ios_simulator=skipped wasm=pass wasm_embedded=pass
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

## Working Tree

`git status` before and after this entire verification run reported "nothing to
commit, working tree clean" — no source, test, benchmark, or CI files were
modified by any command above.

## Notes

- No CI workflow changes were made in this slice (mirrors Slice 27's precedent:
  the new `--column-query --gate` is intentionally local-only until a future
  CI-promotion slice, matching the pattern of Slices 27→28, 29→(reused gate),
  31→32).
- Strictly additive: every existing gate's checksum is byte-identical to the
  2026-07-03 baseline (see table above), confirming no vertical-axis or existing
  horizontal-adjacent behavior changed.
- Hosted proof intentionally deferred to the post-merge follow-up, per the
  project's stale-on-write lesson (a verification doc committed before the PR's
  final head would otherwise cite a run ID that doesn't correspond to the
  merged code).
