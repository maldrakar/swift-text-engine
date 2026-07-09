# Horizontal Geometry Query Verification

Date: 2026-07-07
Branch: `slice-35-horizontal-geometry-query`
Local verification HEAD: `a366928` (`a366928245914c5ad7a66be7a4e82efa8e6730ca`)
Merge base with `main`: `60e2c14`

Spec: `docs/superpowers/specs/2026-07-07-horizontal-geometry-query-design.md`
Plan: `docs/superpowers/plans/2026-07-07-horizontal-geometry-query.md`

Commits on branch (base `60e2c14` ← `main`):

```
a366928 docs: document columnGeometryAt + --column-geometry-query local gate
318cd7f feat: add --column-geometry-query benchmark mode with local gate
1aec1a0 test: add columnGeometryAt PrefixSum reference equivalence
8e786b9 test: add columnGeometryAt structural uniform oracle + columnAt parity
a965227 test: pin columnGeometryAt query-count + native dispatch order
00bef1d feat: add columnGeometryAt geometry-bearing horizontal query
835e570 docs: add slice 35 horizontal geometry query plan
f5246f9 docs: refine slice 35 spec after review
d3ce8b8 docs: add horizontal geometry query design
```

This slice adds `ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:)` (the
geometry-bearing companion to `columnAt`), three public result types
(`ColumnGeometry`, `ColumnGeometryQuery`, `ColumnGeometryLocation`), test
coverage, and a **local** `--column-geometry-query --gate`. No
`.github/workflows/swift-ci.yml` change (CI promotion is a follow-up slice —
Decision 5). This is a public-API change, so cross-target compile is required
(Acceptance Criterion 9).

## 1. Host tests + release build

```text
$ swift test
...
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-07 22:09:36.221.
	 Executed 213 tests, with 0 failures (0 unexpected) in 2.301 (2.310) seconds
Test Suite 'All tests' passed at 2026-07-07 22:09:36.221.
	 Executed 213 tests, with 0 failures (0 unexpected) in 2.301 (2.311) seconds
◇ Test run started.
↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
↳ Target Platform: arm64-apple-macosx
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

Test count: **213** (Slice 34 baseline 189, +24 new this slice: the
`ColumnGeometryAt*` core suites — structural uniform oracle, `columnAt`
parity, unit/failure/clamp/reconstruction tests, query-count tests, and the
native-hook dispatch-order test — plus the `PrefixSumColumnMetrics`
reference-equivalence oracle). 0 failures. The "0 tests in 0 suites" line is
the expected empty Swift Testing harness, not a failure.

```text
$ swift build -c release
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
```

## 2. New gate: `--column-geometry-query --gate`

```text
$ swift run -c release ViewportBenchmarks -- --column-geometry-query --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=16 p99_ns=21 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=20 p99_ns=23 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=27 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=38 p99_ns=48 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=51 p99_ns=64 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=839521520640
EXIT:0
```

All five scenarios `gate=pass`, `failures=0`.

### Per-scenario headroom (local, macOS arm64)

| Scenario | p95 ns | p99 ns | Budget p95 ns | Headroom (budget ÷ p95) | Budget p99 ns | Checksum |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| uniform_1k     | 16 | 21 | 30,000  | 1875.0× | 60,000  | 160641440000 |
| uniform_100k   | 20 | 23 | 60,000  | 3000.0× | 120,000 | 267505512960 |
| uniform_1m     | 21 | 27 | 120,000 | 5714.3× | 240,000 | 799841600000 |
| prefixsum_100k | 38 | 48 | 60,000  | 1578.9× | 120,000 | 223985600000 |
| prefixsum_1m   | 51 | 64 | 120,000 | 2352.9× | 240,000 | 839521520640 |

(Observed timings are approximate and non-reproducible; the deterministic
anchor is the checksum set above.) No budget adjustments were needed — the
starting budgets, copied from the `--column-query` sibling's scenario shape,
already have wide headroom. `prefixsum_1m` (the watch scenario, spec Decision
4/Non-Goals — largest cell count on the proportional-advance provider) clears
its p95 budget by 2352.9×.

## 3. Existing gates — `gate=pass`, no checksum movement

Spec Decision 5 / Acceptance Criterion 8: this slice touches no shared search
or provider path (strictly additive — new method, new types, new benchmark
mode), so every existing gate's checksum must be — and is — **byte-identical**
to the Slice 34 baseline recorded in
`docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md`.

```text
$ swift run -c release ViewportBenchmarks -- --gate
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1318 p99_ns=1399 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5437 p99_ns=6076 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16892 p99_ns=17493 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --variable-height --gate
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=214 p99_ns=242 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=686 p99_ns=718 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2159 p99_ns=2291 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=395 p99_ns=433 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1588 p99_ns=1710 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5160 p99_ns=5410 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=999 p99_ns=1100 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5703 p99_ns=6132 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=32299 p99_ns=34111 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3058 p99_ns=3247 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=9726 p99_ns=10391 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=50432 p99_ns=52215 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=66007 p99_ns=69093 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=149632 p99_ns=168919 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --line-query --gate
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=12 p99_ns=15 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=16 p99_ns=19 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=19 p99_ns=24 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=94 p99_ns=119 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=118 p99_ns=139 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=16 p99_ns=19 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=20 p99_ns=23 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=27 p99_ns=28 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=139 p99_ns=169 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=180 p99_ns=226 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=852321495040
EXIT:0
```

```text
$ swift run -c release ViewportBenchmarks -- --column-query --gate
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=12 p99_ns=14 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=15 p99_ns=19 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=19 p99_ns=24 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=33 p99_ns=40 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=44 p99_ns=55 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841560320
EXIT:0
```

### Checksum-identity table vs 2026-07-05 baseline

| Gate | Scenario | Baseline checksum (2026-07-05) | This run's checksum | Identical? |
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

All 32 checksums across all 8 existing gates are byte-identical to the Slice
34 baseline (`docs/superpowers/verification/2026-07-05-column-query-ci-gate-promotion.md`).
All scenarios report `gate=pass`. This confirms Decision 5/Non-Goals: the
slice touched no shared search or provider path — as expected for a strictly
additive change (new method, new types, new benchmark mode), not a
refactor-preservation obligation.

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

`invariant=pass` on every scenario, byte-identical `core_owned_bytes` per
provider to the Slice 34 baseline. `columnGeometryAt` adds only a constant
number of `columnOffset` probes on top of `columnAt` (Decision 4) — O(1) core
memory, confirmed by this diagnostic being unaffected.

## 5. Foundation-free scans

```text
$ rg -n "Foundation" Sources/TextEngineCore; echo "core exit: $?"
core exit: 1

$ rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "providers exit: $?"
providers exit: 1
```

No matches in either target (exit 1 = ripgrep found nothing). Both targets
remain Foundation-free.

## 6. Cross-target compile (public-API change)

```text
$ ./.github/scripts/cross-target-compile.sh --self-test
self_test=pass
EXIT:0
```

### iOS (blocking)

```text
$ ./.github/scripts/cross-target-compile.sh --targets ios
cross_target_swift_version=6.2.1
cross_target_developer_dir=unset
cross_target_xcode_select_path=/Applications/Xcode_26_3.app/Contents/Developer
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
cross_target_iphoneos_sdk_path=/Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk
cross_target_iphoneos_sdk_version=26.2
cross_target_iphonesimulator_sdk_path=/Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk
cross_target_iphonesimulator_sdk_version=26.2
cross_target_command target=ios_device scheme=TextEngineCore cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'"
mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true
cross_target_command target=ios_simulator scheme=TextEngineCore cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'"
mode=cross_target_compile target=ios_simulator package=core result=pass reason=none blocking=true
mode=cross_target_compile target=wasm package=core result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=wasm_embedded package=core result=skipped reason=not_requested blocking=false
mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
cross_target_command target=ios_device scheme=TextEngineReferenceProviders cmd="xcodebuild build -scheme TextEngineReferenceProviders -destination 'generic/platform=iOS'"
mode=cross_target_compile target=ios_device package=providers result=pass reason=none blocking=true
cross_target_command target=ios_simulator scheme=TextEngineReferenceProviders cmd="xcodebuild build -scheme TextEngineReferenceProviders -destination 'generic/platform=iOS Simulator'"
mode=cross_target_compile target=ios_simulator package=providers result=pass reason=none blocking=true
mode=cross_target_compile target=wasm package=providers result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=wasm_embedded package=providers result=skipped reason=not_requested blocking=false
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
EXIT:0
```

iOS device + simulator compile clean for **both** `TextEngineCore` (now
including `ColumnGeometry`, `ColumnGeometryQuery`, `ColumnGeometryLocation`,
`columnGeometryAt`) and `TextEngineReferenceProviders` — blocking, `pass`.

### WASM (observational)

```text
$ ./.github/scripts/cross-target-compile.sh --targets wasm
cross_target_swift_version=6.2.1
mode=cross_target_compile target=ios_device package=core result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=ios_simulator package=core result=skipped reason=not_requested blocking=false
cross_target_wasm_sdk_id target=wasm package=core id=swift-6.2.1-RELEASE_wasm
mode=cross_target_compile target=wasm package=core result=pass reason=none blocking=false
cross_target_wasm_sdk_id target=wasm_embedded package=core id=swift-6.2.1-RELEASE_wasm-embedded
mode=cross_target_compile target=wasm_embedded package=core result=pass reason=none blocking=false
mode=cross_target_compile_summary package=core ios_device=skipped ios_simulator=skipped wasm=pass wasm_embedded=pass
mode=cross_target_compile target=ios_device package=providers result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=ios_simulator package=providers result=skipped reason=not_requested blocking=false
cross_target_wasm_sdk_id target=wasm package=providers id=swift-6.2.1-RELEASE_wasm
mode=cross_target_compile target=wasm package=providers result=pass reason=none blocking=false
cross_target_wasm_sdk_id target=wasm_embedded package=providers id=swift-6.2.1-RELEASE_wasm-embedded
mode=cross_target_compile target=wasm_embedded package=providers result=pass reason=none blocking=false
mode=cross_target_compile_summary package=providers ios_device=skipped ios_simulator=skipped wasm=pass wasm_embedded=pass
mode=cross_target_compile_overall blocking_failures=0 exit=0
EXIT:0
```

A matching Swift SDK (`swift-6.2.1-RELEASE_wasm` / `-embedded`) was
provisioned locally, so WASM + embedded WASM actually compiled (not a skip)
for both `TextEngineCore` and `TextEngineReferenceProviders` — observational,
`pass`.

## Working tree

`git status` before and after this entire verification run reported "nothing
to commit, working tree clean" (aside from this new verification doc) — no
source, test, benchmark, or CI files were modified by any command above.

## Notes

- Strictly additive slice: every existing gate's checksum is byte-identical
  to the 2026-07-05 baseline (see the checksum-identity table above),
  confirming no vertical-axis or existing horizontal-adjacent behavior
  changed. `columnGeometryAt` composes over `columnAt` and adds two
  `columnOffset` probes on the located branch (Decision 4); no search or
  provider path was touched.
- No CI workflow changes were made in this slice (Decision 5) — the new
  `--column-geometry-query --gate` is intentionally local-only until a future
  CI-promotion slice, matching the pattern of `--column-query` (Slice 33→34)
  and `--line-geometry-query` (Slice 31→32).
- Hosted proof is intentionally deferred to the post-merge follow-up, per the
  project's stale-on-write lesson (a verification doc committed before the
  PR's final head would otherwise cite a run ID that doesn't correspond to
  the merged code).

## Hosted Proof

Recorded post-merge against the stable final PR-head SHA and the merge commit
(the Slice 26 stale-on-write lesson: the source-bearing PR left this section as
an explicit `Pending` placeholder; the real run IDs were filled in only once the
final head was stable).

- **PR:** #71 (`slice-35-horizontal-geometry-query` → `main`), title *"Slice 35:
  horizontal geometry query (columnGeometryAt)"*, MERGED 2026-07-08T16:01:32Z by
  `maldrakar`, merge commit `5da380b`
  (`5da380b64308aae1d049e9f4a7bce36a578d3144`). Merge parentage confirmed via
  `git rev-list --parents`: `5da380b`'s parents are the base `60e2c14` and the
  tested PR head `a1ef979` (`5da380b^2 == a1ef979`), so this proof anchors the
  actually-merged code.
- **Final PR-head run:** `28893267949` (event `pull_request`, head `a1ef979`) —
  conclusion `success`; all three required contexts `success` (Host tests and
  benchmark gate 8m6s, iOS cross-target compile 1m4s, WASM cross-target
  observation 39s).
- **Post-merge push run:** `28956968583` (event `push`, head `5da380b` = merge
  commit) — conclusion `success`; all three required jobs `success` (Host tests
  and benchmark gate 5m17s, iOS 1m22s, WASM 34s).

### Step-Level Proof (not just job conclusion)

Verified via `gh run view --json jobs` on both runs' `Host tests and benchmark
gate` job (the project's "a green job can hide a dead `continue-on-error` step"
lesson). The pre-existing **eight** blocking gates all ran (not skipped, not
`continue-on-error`) in order, and — per Decision 5 — there is **no** hosted
`Run column geometry query benchmark gate` step in either run:

| Host-job step | PR-head `28893267949` | push `28956968583` |
| --- | --- | --- |
| #5  Complete docs-only PR                       | skipped | skipped |
| #7  Run host tests                              | success | success |
| #8  Run synthetic benchmark gate                | success | success |
| #9  Run variable-height benchmark gate          | success | success |
| #10 Run variable-height mutation benchmark gate | success | success |
| #11 Run structural mutation benchmark gate      | success | success |
| #12 Run bulk structural mutation benchmark gate | success | success |
| #13 Run line query benchmark gate               | success | success |
| #14 Run line geometry query benchmark gate      | success | success |
| #15 Run column query benchmark gate             | success | success |
| #16 Run memory shape diagnostic                 | success | success |
| #17 Run RSS memory observation diagnostic       | success | success |
| #18 Observe realistic provider relative performance | success (PR event) | skipped (push event) |

Confirmations, matching the checklist this section replaces:

- **The eight blocking latency gates (steps #8–#15) are intact and green** on
  both the PR-head and merged-code runs — synthetic, variable-height,
  variable-height-mutation, structural-mutation, bulk-structural-mutation,
  line-query, line-geometry-query, column-query. This additive slice regressed
  none of them, consistent with the byte-identical checksum table above.
- **The new `--column-geometry-query --gate` is not a hosted step** — no such
  step exists in either run's host job, confirming Decision 5 (local-only gate;
  CI promotion is a deferred follow-up slice, the ninth blocking gate).
- **`columnGeometryAt` correctness is nonetheless enforced hosted** through step
  #7 `Run host tests`, which executes the full 213-test suite including the new
  `ColumnGeometryAt*` core suites (structural uniform oracle, `columnAt` parity,
  unit/failure/clamp/reconstruction, query-count, native-hook dispatch order) and
  the `PrefixSumColumnMetrics` reference-equivalence oracle; it is `success` on
  both runs.
- **`Complete docs-only PR` (step #5) was correctly `skipped`** on both runs —
  the merged change is source-bearing (Swift + tests + benchmark), so the full
  heavy path executed, not the docs-only short-circuit.
- **Step #18 realistic-provider observation** ran `success` on the PR-head
  (`pull_request`) run and was correctly `skipped` on the merged-code (`push`)
  run — it is the PR-only `continue-on-error` observation, unchanged by this
  slice.

### Merged-Behavior Anchor (push run `28956968583`, merge commit `5da380b`)

The post-merge push run on merge commit `5da380b` (second parent = the tested PR
head `a1ef979`) re-executed the entire host job — the 213-test suite and all
eight blocking gates — to `success`, anchoring the merged workflow behavior
against the stable final head. No hosted `--column-geometry-query` timings are
recorded here because that gate is intentionally local-only this slice
(Decision 5); its hosted-CI numbers will be captured by the future promotion
slice, exactly as `--column-query`'s were by Slice 34.
