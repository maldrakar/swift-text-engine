# Compute-Native Prefix Search Verification
Date: 2026-06-28 (local sweep); hosted evidence appended 2026-06-29
Branch: slice-30-compute-native-prefix-search
Local verification code head: 74bcee4ef90d7f1ba6ec003449d2828a09857c0d
Current PR #56 head: aa3b755c58f84fb14b5d0cd85a12841da6cffd09

The three commits between the local-sweep head and the current PR head
(`d80edf0` docs, `22cc38a` docs, `aa3b755` chore) touch only docs and
`.gitignore` — no Swift source, tests, or `Package.swift` — so the local
source-level evidence captured at `74bcee4` still represents the source on the
current PR head. Confirmed with
`git diff --name-only 74bcee4..aa3b755 -- Sources Tests Package.swift` (empty).
The hosted run below executed against `aa3b755`.

## Summary

- `LineMetricsSource.firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` is the core hook that lets variable `compute` find the visible-end boundary without open-coding another offset search.
- Variable `compute` routes visible-start through `lineIndex(containingOffset:)` and visible-end through `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`, while preserving the generic fallback for providers that do not override the hooks.
- `BalancedTreeLineMetrics` answers visible-end lookup with a native subtree-sum descent; the structural and bulk structural gates exercise `compute` over this balanced-tree provider.
- Equivalence proof is covered by the balanced-tree compute oracle test and the existing uniform fixed/variable equivalence suite.
- Full local verification passed: host tests/build, every Task 6 benchmark gate, memory-shape invariant, Foundation-free scans, cross-target self-test, and iOS/WASM cross-target compile.

## Local Commands

Execution note: the first sandboxed `swift test` attempt failed before package
compilation because Swift/Clang could not write
`/Users/aabanschikov/.cache/clang/ModuleCache/.../SwiftShims-23HTR8TX6995F.pcm`
(`Operation not permitted`). The Swift and cross-target commands below were then
rerun with normal toolchain cache access; these reruns are the verification
evidence.

### swift test

```terminal
$ swift test
Build complete! (0.11s)
Test Suite 'BalancedTreeLineMetricsTests' passed at 2026-06-28 19:39:11.379.
	 Executed 42 tests, with 0 failures (0 unexpected) in 2.081 (2.084) seconds
Test Suite 'ComputeNativePrefixSearchTests' passed at 2026-06-28 19:39:11.379.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-28 19:39:11.585.
	 Executed 140 tests, with 0 failures (0 unexpected) in 2.284 (2.290) seconds
Test Suite 'All tests' passed at 2026-06-28 19:39:11.585.
	 Executed 140 tests, with 0 failures (0 unexpected) in 2.284 (2.290) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

### swift build -c release

```terminal
$ swift build -c release
Building for production...
[3/4] Compiling TextEngineReferenceProviders BalancedTreeLineMetrics.swift
[4/6] Compiling ViewportBenchmarks BenchmarkModels.swift
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswiftCore.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswift_Builtin_float.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswift_Concurrency.dylib' which was built for newer version 13.0
[5/6] Linking ViewportBenchmarks
Build complete! (2.42s)
```

### swift run -c release ViewportBenchmarks -- --gate

```terminal
$ swift run -c release ViewportBenchmarks -- --gate
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1138 p99_ns=1377 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4719 p99_ns=4853 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=15712 p99_ns=16282 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

### swift run -c release ViewportBenchmarks -- --variable-height --gate

```terminal
$ swift run -c release ViewportBenchmarks -- --variable-height --gate
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=201 p99_ns=212 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=650 p99_ns=690 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=1979 p99_ns=2020 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

### swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate

```terminal
$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=380 p99_ns=397 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1565 p99_ns=1674 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4783 p99_ns=5263 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
```

### swift run -c release ViewportBenchmarks -- --structural-mutation --gate

```terminal
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=894 p99_ns=984 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5012 p99_ns=5108 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=22324 p99_ns=24052 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

### swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate

```terminal
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2567 p99_ns=2646 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=7778 p99_ns=7890 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=34507 p99_ns=37141 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=58945 p99_ns=59739 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=122596 p99_ns=129361 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

### swift run -c release ViewportBenchmarks -- --line-query --gate

```terminal
$ swift run -c release ViewportBenchmarks -- --line-query --gate
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=11 p99_ns=12 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=17 p99_ns=21 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=21 p99_ns=27 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=88 p99_ns=100 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=114 p99_ns=133 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
```

### swift run -c release ViewportBenchmarks -- --memory-shape

```terminal
$ swift run -c release ViewportBenchmarks -- --memory-shape
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 invariant=pass checksum=765061875
```

### Foundation scans

```terminal
$ rg -n "Foundation" Sources/TextEngineCore
no output; exit 1

$ rg -n "Foundation" Sources/TextEngineReferenceProviders
no output; exit 1
```

### ./.github/scripts/cross-target-compile.sh --self-test

```terminal
$ ./.github/scripts/cross-target-compile.sh --self-test
self_test=pass
```

### ./.github/scripts/cross-target-compile.sh

```terminal
$ ./.github/scripts/cross-target-compile.sh
cross_target_swift_version=6.2.1
cross_target_xcode_select_path=/Applications/Xcode_26_3.app/Contents/Developer
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
cross_target_iphoneos_sdk_version=26.2
cross_target_iphonesimulator_sdk_version=26.2
mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator package=core result=pass reason=none blocking=true
mode=cross_target_compile target=wasm package=core result=pass reason=none blocking=false
mode=cross_target_compile target=wasm_embedded package=core result=pass reason=none blocking=false
mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass
mode=cross_target_compile target=ios_device package=providers result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator package=providers result=pass reason=none blocking=true
mode=cross_target_compile target=wasm package=providers result=pass reason=none blocking=false
mode=cross_target_compile target=wasm_embedded package=providers result=pass reason=none blocking=false
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

## Before/After Timing Observation

Baseline/pre-slice commit:
`a98d29ac394bf5680712a78a8e4f4a602a3f1f41`.

Current after commit:
`74bcee4ef90d7f1ba6ec003449d2828a09857c0d`.

Method: materialized the baseline with
`git archive a98d29ac394bf5680712a78a8e4f4a602a3f1f41 | tar -x -C /private/tmp/slice30-compute-native-prefix-baseline`,
ran the two benchmark modes there, and removed the temporary extraction after
capture. Current rows are the same rows recorded in the local sweep above.

This is a one-off timing observation only. No benchmark mode was added and all
benchmark budgets are unchanged. Structural and bulk checksum comparisons were
clean (`diff -u` produced no output, exit 0), so the native compute routing
preserves the same benchmark result checksums.

### Checksum comparisons

Structural checksum extraction and comparison:

```terminal
$ awk '/^mode=/ { for (i = 1; i <= NF; i++) { if ($i ~ /^scenario=/) scenario=$i; if ($i ~ /^checksum=/) checksum=$i } print scenario, checksum }' /private/tmp/slice30-compute-native-prefix-verification/gate-structural-mutation-baseline.txt > /private/tmp/slice30-compute-native-prefix-verification/structural-baseline-checksums.txt
$ awk '/^mode=/ { for (i = 1; i <= NF; i++) { if ($i ~ /^scenario=/) scenario=$i; if ($i ~ /^checksum=/) checksum=$i } print scenario, checksum }' /private/tmp/slice30-compute-native-prefix-verification/gate-structural-mutation-current.txt > /private/tmp/slice30-compute-native-prefix-verification/structural-current-checksums.txt
$ cat /private/tmp/slice30-compute-native-prefix-verification/structural-baseline-checksums.txt
scenario=1k_lines_20_visible_overscan_0 checksum=200106952336
scenario=100k_lines_80_visible_overscan_5 checksum=89494497658324
scenario=1m_lines_200_visible_overscan_50 checksum=3379593298396981
$ cat /private/tmp/slice30-compute-native-prefix-verification/structural-current-checksums.txt
scenario=1k_lines_20_visible_overscan_0 checksum=200106952336
scenario=100k_lines_80_visible_overscan_5 checksum=89494497658324
scenario=1m_lines_200_visible_overscan_50 checksum=3379593298396981
$ diff -u /private/tmp/slice30-compute-native-prefix-verification/structural-baseline-checksums.txt /private/tmp/slice30-compute-native-prefix-verification/structural-current-checksums.txt
no output; exit 0
```

Bulk structural checksum extraction and comparison:

```terminal
$ awk '/^mode=/ { for (i = 1; i <= NF; i++) { if ($i ~ /^scenario=/) scenario=$i; if ($i ~ /^checksum=/) checksum=$i } print scenario, checksum }' /private/tmp/slice30-compute-native-prefix-verification/gate-bulk-structural-mutation-baseline.txt > /private/tmp/slice30-compute-native-prefix-verification/bulk-baseline-checksums.txt
$ awk '/^mode=/ { for (i = 1; i <= NF; i++) { if ($i ~ /^scenario=/) scenario=$i; if ($i ~ /^checksum=/) checksum=$i } print scenario, checksum }' /private/tmp/slice30-compute-native-prefix-verification/gate-bulk-structural-mutation-current.txt > /private/tmp/slice30-compute-native-prefix-verification/bulk-current-checksums.txt
$ cat /private/tmp/slice30-compute-native-prefix-verification/bulk-baseline-checksums.txt
scenario=1k_lines_batch_64 checksum=82740062444
scenario=100k_lines_batch_64 checksum=36564666309410
scenario=1m_lines_batch_64 checksum=1317343499882000
scenario=100k_lines_batch_4096 checksum=2285022074625
scenario=1m_lines_batch_4096 checksum=82203678997143
$ cat /private/tmp/slice30-compute-native-prefix-verification/bulk-current-checksums.txt
scenario=1k_lines_batch_64 checksum=82740062444
scenario=100k_lines_batch_64 checksum=36564666309410
scenario=1m_lines_batch_64 checksum=1317343499882000
scenario=100k_lines_batch_4096 checksum=2285022074625
scenario=1m_lines_batch_4096 checksum=82203678997143
$ diff -u /private/tmp/slice30-compute-native-prefix-verification/bulk-baseline-checksums.txt /private/tmp/slice30-compute-native-prefix-verification/bulk-current-checksums.txt
no output; exit 0
```

### structural-mutation --gate

| Scenario | Baseline p95/p99 ns | Current p95/p99 ns | Checksum |
| --- | ---: | ---: | ---: |
| 1k_lines_20_visible_overscan_0 | 1847 / 2314 | 894 / 984 | 200106952336 |
| 100k_lines_80_visible_overscan_5 | 8068 / 8629 | 5012 / 5108 | 89494497658324 |
| 1m_lines_200_visible_overscan_50 | 33365 / 35483 | 22324 / 24052 | 3379593298396981 |

Baseline terminal rows:

```terminal
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1847 p99_ns=2314 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=8068 p99_ns=8629 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=33365 p99_ns=35483 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

Current terminal rows:

```terminal
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=894 p99_ns=984 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5012 p99_ns=5108 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=22324 p99_ns=24052 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

### bulk-structural-mutation --gate

| Scenario | Baseline p95/p99 ns | Current p95/p99 ns | Checksum |
| --- | ---: | ---: | ---: |
| 1k_lines_batch_64 | 3495 / 3669 | 2567 / 2646 | 82740062444 |
| 100k_lines_batch_64 | 12005 / 13252 | 7778 / 7890 | 36564666309410 |
| 1m_lines_batch_64 | 51647 / 55823 | 34507 / 37141 | 1317343499882000 |
| 100k_lines_batch_4096 | 67679 / 72966 | 58945 / 59739 | 2285022074625 |
| 1m_lines_batch_4096 | 181744 / 195343 | 122596 / 129361 | 82203678997143 |

Baseline terminal rows:

```terminal
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3495 p99_ns=3669 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=12005 p99_ns=13252 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=51647 p99_ns=55823 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=67679 p99_ns=72966 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=181744 p99_ns=195343 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

Current terminal rows:

```terminal
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2567 p99_ns=2646 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=7778 p99_ns=7890 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=34507 p99_ns=37141 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=58945 p99_ns=59739 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=122596 p99_ns=129361 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

## Hosted Evidence

PR-head hosted evidence, verified live via `gh` at the **step** level (per the
project lesson that a green job can hide a dead `continue-on-error` step) on
2026-06-29. All three required Swift CI job contexts passed on the exact current
PR head `aa3b755`.

- PR: [#56 — Slice 30: compute-native prefix search](https://github.com/maldrakar/swift-text-engine/pull/56) (state `OPEN`, mergeable `CLEAN`)
- Full-code PR head: `aa3b755c58f84fb14b5d0cd85a12841da6cffd09`
- Swift CI `pull_request` run: `28334474924` (event `pull_request`, branch
  `slice-30-compute-native-prefix-search`, conclusion `success`)

### Host tests and benchmark gate — job `83938177803` (`success`)

Ran the full heavy path on the source-bearing PR (step 5 `Complete docs-only PR`
`skipped`, so the PR is correctly classified as **not** docs-only):

```terminal
4  Detect PR change scope            -> success
5  Complete docs-only PR             -> skipped
7  Run host tests                    -> success
8  Run synthetic benchmark gate      -> success
9  Run variable-height benchmark gate            -> success
10 Run variable-height mutation benchmark gate   -> success
11 Run structural mutation benchmark gate        -> success
12 Run bulk structural mutation benchmark gate   -> success
13 Run line query benchmark gate     -> success
14 Run memory shape diagnostic       -> success
15 Run RSS memory observation diagnostic         -> success
16 Observe realistic provider relative performance -> success
```

All six blocking latency gates (steps 8→13) ran and passed on hosted Linux.

### iOS cross-target compile — job `83938177816` (`success`)

```terminal
4 Complete docs-only PR              -> skipped
6 Compile cross-target packages for iOS -> success
```

iOS device + simulator compile for `TextEngineCore` and
`TextEngineReferenceProviders` (blocking) passed.

### WASM cross-target observation — job `83938177800` (`success`)

```terminal
4 Complete docs-only PR              -> skipped
7 Observe cross-target packages for WASM -> success
```

WASM + embedded WASM observation (non-blocking) passed.

### Post-merge anchor

- Post-merge push run on the `main` merge commit: **Pending** (record after PR
  #56 merges, as the merged-code evidence anchor, following the Slice 29
  two-step pattern).
