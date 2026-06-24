# Vertical Position-Query Verification

Date: 2026-06-21
Branch: `slice-27-vertical-position-query`
Local verification HEAD: `dfdb49f077f28d0357347f3f11a53ac1a5079357`

## Hosted Proof

- PR-head Swift CI run: Pending
- Post-merge `push` Swift CI run: Pending

The hosted run IDs are intentionally pending until the PR head and post-merge
commit exist. Do not backfill them from a pre-final local commit.

## Host Tests And Release Build

Command:

```bash
swift test && swift build -c release
```

Result: exit 0.

Relevant output:

```text
Test Suite 'SwiftTextEnginePackageTests.xctest' passed
Executed 124 tests, with 0 failures (0 unexpected)
Test Suite 'All tests' passed
Executed 124 tests, with 0 failures (0 unexpected)
Test run with 0 tests in 0 suites passed
Build complete!
```

The 124 XCTest tests are the previous 107 plus `LineAtTests` (12),
`LineAtEquivalenceTests` (1), and `LineAtQueryCountTests` (4).

## New Line-Query Gate

Command:

```bash
swift run -c release ViewportBenchmarks -- --line-query --gate
```

Result: exit 0.

Output:

```text
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=23 p99_ns=41 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=29 p99_ns=47 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=40 p99_ns=55 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=860 p99_ns=998 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=1838 p99_ns=2546 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
```

Budget decision: the starter budgets were retained. Local p95/p99 values have
well over 10x headroom in every scenario.

## Existing Gates

Command:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Result: exit 0.

Output:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1330 p99_ns=1434 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5365 p99_ns=5580 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17206 p99_ns=17642 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Result: exit 0.

Output:

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=229 p99_ns=260 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=790 p99_ns=965 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2561 p99_ns=2979 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Result: exit 0.

Output:

```text
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=451 p99_ns=534 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1821 p99_ns=2101 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5952 p99_ns=6726 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```

Result: exit 0.

Output:

```text
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1864 p99_ns=1991 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=8841 p99_ns=9559 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=39206 p99_ns=41159 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
```

Result: exit 0.

Output:

```text
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3724 p99_ns=3912 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=12832 p99_ns=14094 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=66695 p99_ns=69960 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=88687 p99_ns=109018 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=182143 p99_ns=192401 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

All existing gate checksums matched the pre-slice baselines recorded by the
project gates.

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

## Foundation-Free Scans

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore; echo "core exit: $?"; rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "providers exit: $?"
```

Result: exit 0. The `rg` subcommands found no matches.

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

Result: exit 0.

Relevant output:

```text
cross_target_swift_version=6.2.1
cross_target_xcode_select_path=/Applications/Xcode_26_3.app/Contents/Developer
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
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

Result: exit 0.

Relevant output:

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

## Notes

- No CI workflow changes were made in this slice.
- The local `--line-query --gate` is intentionally not a hosted blocking gate
  until the follow-up CI-promotion slice.
