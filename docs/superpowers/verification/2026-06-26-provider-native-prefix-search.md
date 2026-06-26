# Provider-Native Prefix Search Verification
Date: 2026-06-26
Branch: slice-29-provider-native-prefix-search
Verified code head: 15d3f2f12a9e80d579f5ed086e55ac1e333f8b39

## Summary

- `ViewportVirtualizer.lineAt(y:metrics:)` keeps Slice 27 validation and clamp semantics.
- `LineMetricsSource.lineIndex(containingOffset:)` provides the default fallback hook.
- `BalancedTreeLineMetrics` overrides the hook with an iterative subtree-sum descent.
- `--line-query --gate` passes; balanced-tree checksums match the pre-change baseline.

## Local Commands

### swift test

```terminal
$ swift test
Test Suite 'BalancedTreeLineMetricsTests' passed at 2026-06-26 12:48:15.712.
	 Executed 36 tests, with 0 failures (0 unexpected) in 1.940 (1.942) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-26 12:48:15.931.
	 Executed 130 tests, with 0 failures (0 unexpected) in 2.154 (2.160) seconds
Test Suite 'All tests' passed at 2026-06-26 12:48:15.931.
	 Executed 130 tests, with 0 failures (0 unexpected) in 2.154 (2.161) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

### swift build -c release

```terminal
$ swift build -c release
[5/6] Compiling TextEngineCore DocumentLineCursor.swift
[6/7] Compiling TextEngineReferenceProviders BalancedTreeLineMetrics.swift
[7/8] Compiling ViewportBenchmarks BenchmarkModels.swift
[8/9] Linking ViewportBenchmarks
Build complete! (2.65s)
```

### swift run -c release ViewportBenchmarks -- --gate

```terminal
$ swift run -c release ViewportBenchmarks -- --gate
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1393 p99_ns=1682 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5244 p99_ns=5822 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16995 p99_ns=17618 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

### swift run -c release ViewportBenchmarks -- --line-query --gate

```terminal
$ set -o pipefail; swift run -c release ViewportBenchmarks -- --line-query --gate 2>&1 | tee /tmp/slice29-line-query-after.txt | tee /tmp/slice29-verification/line-query-gate.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=14 p99_ns=16 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=19 p99_ns=21 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=21 p99_ns=25 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=99 p99_ns=112 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=127 p99_ns=150 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
```

### Line-query checksum comparison

```terminal
$ diff -u <(rg "balanced_tree_(100k|1m)" /tmp/slice29-line-query-before.txt | sed -E 's/.*scenario=([^ ]+).*checksum=([^ ]+).*/scenario=\1 checksum=\2/') <(rg "balanced_tree_(100k|1m)" /tmp/slice29-line-query-after.txt | sed -E 's/.*scenario=([^ ]+).*checksum=([^ ]+).*/scenario=\1 checksum=\2/')
no output; exit 0
```

### swift run -c release ViewportBenchmarks -- --memory-shape

```terminal
$ swift run -c release ViewportBenchmarks -- --memory-shape
Build of product 'ViewportBenchmarks' complete! (0.07s)
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
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
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
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

## Hosted Evidence

- PR: #53, https://github.com/maldrakar/swift-text-engine/pull/53
- Full-code PR head: `0607962a096a7c115c6876be4f76c1023b7a2f0d`.
  The artifact-only update after this evidence does not change implementation
  files; the verified implementation head remains
  `15d3f2f12a9e80d579f5ed086e55ac1e333f8b39`.
- Swift CI pull_request run: `28236023961`, conclusion `success`,
  https://github.com/maldrakar/swift-text-engine/actions/runs/28236023961

### Host tests and benchmark gate

- Job id: `83650996680`
- Conclusion: `success`
- Completed: 2026-06-26T11:55:15Z
- URL: https://github.com/maldrakar/swift-text-engine/actions/runs/28236023961/job/83650996680

```terminal
Run host tests: Executed 130 tests, with 0 failures (0 unexpected) in 4.716 (4.716) seconds
Run synthetic benchmark gate: mode=pipeline scenario=1m_lines_200_visible_overscan_50 p95_ns=33989 p99_ns=35489 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
Run bulk structural mutation benchmark gate: mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 p95_ns=388781 p99_ns=403766 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
Run line query benchmark gate: mode=line_query provider=balanced_tree scenario=balanced_tree_100k p95_ns=243 p99_ns=262 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
Run line query benchmark gate: mode=line_query provider=balanced_tree scenario=balanced_tree_1m p95_ns=252 p99_ns=299 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
Run memory shape diagnostic: mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 core_owned_bytes=74 provider_owned_bytes=0 invariant=pass checksum=2206176509
```

### iOS cross-target compile

- Job id: `83650996697`
- Conclusion: `success`
- Completed: 2026-06-26T11:48:08Z
- URL: https://github.com/maldrakar/swift-text-engine/actions/runs/28236023961/job/83650996697

```terminal
mode=cross_target_compile target=ios_device package=core result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator package=core result=pass reason=none blocking=true
mode=cross_target_compile_summary package=core ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile target=ios_device package=providers result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator package=providers result=pass reason=none blocking=true
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

### WASM cross-target observation

- Job id: `83650996707`
- Conclusion: `success`
- Completed: 2026-06-26T11:47:54Z
- URL: https://github.com/maldrakar/swift-text-engine/actions/runs/28236023961/job/83650996707

```terminal
mode=cross_target_compile target=wasm package=core result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile target=wasm_embedded package=core result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile_summary package=core ios_device=skipped ios_simulator=skipped wasm=skipped wasm_embedded=skipped
mode=cross_target_compile target=wasm package=providers result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile target=wasm_embedded package=providers result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile_summary package=providers ios_device=skipped ios_simulator=skipped wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
```
