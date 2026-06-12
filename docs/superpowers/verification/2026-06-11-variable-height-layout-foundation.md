# Variable-Height Layout Foundation Verification

Date: 2026-06-12

## Scope

Branch `slice-14-variable-height-layout-foundation` implements the static query half of variable-height layout for `TextEngineCore`: `LineMetricsSource`, `UniformLineMetrics`, `VariableViewportInput`, variable-height viewport computation, variable geometry traversal, deterministic query-count tests, a variable-height benchmark mode with local gate, CI observation wiring, and variable memory-shape diagnostics. PR #9 verifies hosted Swift CI at head `4a55aee9192b2a9dbadc62dc1b5f129c0f2407f3`.

## Local Verification

Command:

```text
swift test
```

Output:

```text
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-12 03:03:15.463.
	 Executed 67 tests, with 0 failures (0 unexpected) in 0.007 (0.010) seconds
Test Suite 'All tests' passed at 2026-06-12 03:03:15.463.
	 Executed 67 tests, with 0 failures (0 unexpected) in 0.007 (0.010) seconds
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

Command:

```text
swift build -c release
```

Output:

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.08s)
```

Command:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Output:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1276 p99_ns=1327 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4998 p99_ns=5054 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=15556 p99_ns=16171 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

Command:

```text
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Output:

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=227 p99_ns=240 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=757 p99_ns=771 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2347 p99_ns=2374 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

Command:

```text
rg -n -C 2 "Run variable-height benchmark observation" .github/workflows/swift-ci.yml
rg -n "swift run -c release ViewportBenchmarks -- --variable-height" .github/workflows/swift-ci.yml
! rg -n "swift run -c release ViewportBenchmarks -- --variable-height --gate" .github/workflows/swift-ci.yml
```

Output:

```text
38-        run: swift run -c release ViewportBenchmarks -- --gate
39-
40:      - name: Run variable-height benchmark observation
41-        continue-on-error: true
42-        run: swift run -c release ViewportBenchmarks -- --variable-height
42:        run: swift run -c release ViewportBenchmarks -- --variable-height
```

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Output:

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 buffered_lines=90 geometry_lines=90 core_owned_bytes=90 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 buffered_lines=90 geometry_lines=90 core_owned_bytes=90 invariant=pass checksum=765061875
```

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Output:

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1867776 rss_after_provider_setup_bytes=1867776 rss_after_core_operation_bytes=2064384 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2113536 rss_after_provider_setup_bytes=2113536 rss_after_core_operation_bytes=2113536 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2113536 rss_after_provider_setup_bytes=13352960 rss_after_core_operation_bytes=13352960 rss_page_size_bytes=16384 rss_provider_delta_bytes=11239424 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

Command:

```text
swift sdk list
```

Output:

```text
swift-6.2.1-RELEASE_wasm
swift-6.2.1-RELEASE_wasm-embedded
```

Command:

```text
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
```

Output:

```text
Build of target: 'TextEngineCore' complete! (0.33s)
```

Command:

```text
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
```

Output:

```text
Build of target: 'TextEngineCore' complete! (0.33s)
```

Command:

```text
./.github/scripts/cross-target-compile.sh --self-test
```

Output:

```text
self_test=pass
```

Command:

```text
./.github/scripts/cross-target-compile.sh
```

Output:

```text
cross_target_swift_version=6.2.1
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
mode=cross_target_compile target=ios_device result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true
mode=cross_target_compile target=wasm result=pass reason=none blocking=false
mode=cross_target_compile target=wasm_embedded result=pass reason=none blocking=false
mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass blocking_failures=0 exit=0
```

Command:

```text
! rg -n "Foundation" Sources/TextEngineCore
```

Output:

```text
<no output>
```

## Hosted PR Run

PR:

```text
pr_number=9
pr_url=https://github.com/arthurbanshchikov/swift-text-engine/pull/9
branch=slice-14-variable-height-layout-foundation
head_sha=4a55aee9192b2a9dbadc62dc1b5f129c0f2407f3
run_id=27385494123
run_url=https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27385494123
event=pull_request
conclusion=success
created_at=2026-06-12T00:05:48Z
updated_at=2026-06-12T00:11:08Z
```

Job conclusions:

```text
job=Cross-target compile id=80931512796 started_at=2026-06-12T00:05:51Z completed_at=2026-06-12T00:06:29Z conclusion=success
job=Host tests and benchmark gate id=80931512797 started_at=2026-06-12T00:05:51Z completed_at=2026-06-12T00:11:07Z conclusion=success
```

Hosted toolchain and cross-target result:

```text
cross_target_swift_version=6.1.2
cross_target_xcodebuild_version=Xcode 16.4;Build version 16F6
mode=cross_target_compile target=ios_device result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true
mode=cross_target_compile target=wasm result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile target=wasm_embedded result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0
```

Hosted tests and synthetic gate:

```text
Test Suite 'All tests' passed at 2026-06-12 00:06:31.110.
Executed 67 tests, with 0 failures (0 unexpected) in 0.018 (0.024) seconds
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=4874 p99_ns=6859 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=19788 p99_ns=25423 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=55509 p99_ns=73605 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

Hosted variable-height observation:

```text
Run swift run -c release ViewportBenchmarks -- --variable-height
swift run -c release ViewportBenchmarks -- --variable-height
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=324 p99_ns=751 failures=0 checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1624 p99_ns=3039 failures=0 checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=8814 p99_ns=10782 failures=0 checksum=3536425156727040
```

Workflow wiring for hosted observation:

```text
      - name: Run variable-height benchmark observation
        continue-on-error: true
        run: swift run -c release ViewportBenchmarks -- --variable-height
```

Hosted memory diagnostics and realistic observation:

```text
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 buffered_lines=90 geometry_lines=90 core_owned_bytes=90 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 buffered_lines=90 geometry_lines=90 core_owned_bytes=90 invariant=pass checksum=765061875
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1572864 rss_after_provider_setup_bytes=1572864 rss_after_core_operation_bytes=1589248 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=16384 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1671168 rss_after_provider_setup_bytes=1671168 rss_after_core_operation_bytes=1671168 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=1671168 rss_after_provider_setup_bytes=12894208 rss_after_core_operation_bytes=12959744 rss_page_size_bytes=16384 rss_provider_delta_bytes=11223040 rss_core_operation_delta_bytes=65536 observation=pass checksum=596788650
mode=realistic_relative_observation base_sha=67320f0d01f830fdff75d49208aee4b87575253b head_sha=4a55aee9192b2a9dbadc62dc1b5f129c0f2407f3 comparison_repetitions_per_side=4 run_order=base,head,head,base,base,head,head,base base_p95_ns_values=19652,21513,18344,20398 head_p95_ns_values=15721,21212,18622,18255 base_p99_ns_values=26202,28668,25494,26408 head_p99_ns_values=22218,27521,26268,24316 base_median_p95_ns=20025.000000 head_median_p95_ns=18438.500000 base_median_p99_ns=26305.000000 head_median_p99_ns=25292.000000 p95_ratio=0.920774 p99_ratio=0.961490 max_ratio=0.961490 observation_threshold=1.221556 observation=clean blocking_ready=false
```

## Post-Merge Push Run

PR #9 merged to `main` as merge commit `7f7df2f8df9ccc78d3a5e5544bbee715d9632649`; the `push` workflow on that commit is green.

```text
run_id=27404861416
run_url=https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27404861416
event=push
branch=main
head_sha=7f7df2f8df9ccc78d3a5e5544bbee715d9632649
conclusion=success
created_at=2026-06-12T08:41:37Z
updated_at=2026-06-12T08:44:39Z
```

Job conclusions:

```text
job=Cross-target compile id=80991367556 started_at=2026-06-12T08:41:41Z completed_at=2026-06-12T08:42:41Z conclusion=success
job=Host tests and benchmark gate id=80991367513 started_at=2026-06-12T08:41:41Z completed_at=2026-06-12T08:44:37Z conclusion=success
```

Hosted toolchain and cross-target result:

```text
cross_target_swift_version=6.1.2
cross_target_xcodebuild_version=Xcode 16.4;Build version 16F6
mode=cross_target_compile target=ios_device result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true
mode=cross_target_compile target=wasm result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile target=wasm_embedded result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0
```

Host tests and synthetic gate:

```text
Executed 67 tests, with 0 failures (0 unexpected) in 0.016 (0.018) seconds
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=4238 p99_ns=5600 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=12785 p99_ns=18040 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=45739 p99_ns=62710 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

Variable-height observation:

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=509 p99_ns=838 failures=0 checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1553 p99_ns=3153 failures=0 checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=6456 p99_ns=9884 failures=0 checksum=3536425156727040
```

Memory diagnostics:

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 buffered_lines=90 geometry_lines=90 core_owned_bytes=90 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 buffered_lines=90 geometry_lines=90 core_owned_bytes=90 invariant=pass checksum=765061875
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 core_owned_bytes_model=74 provider_owned_bytes=0 rss_core_operation_delta_bytes=16384 observation=pass checksum=220776509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_provider_delta_bytes=11223040 rss_core_operation_delta_bytes=65536 observation=pass checksum=596788650
```

The realistic relative observation does not run on `push` (`realistic_relative_observation=skipped_on_push`); it is a pull-request-only diagnostic, consistent with prior slices.

## Conclusion

The slice meets the pre-merge acceptance criteria: local host tests, release build, synthetic gate, variable-height local gate, workflow observation scan, memory-shape diagnostics, RSS memory observation, local WASM builds, local cross-target helper, Foundation-free scan, and hosted PR Swift CI all pass. Hosted PR CI runs variable-height as observation-only without `--gate` and with `continue-on-error: true`; iOS hosted targets are blocking and green; hosted WASM targets remain skipped on Swift 6.1.2, unchanged from Slice 13. Post-merge push CI on merge commit `7f7df2f8df9ccc78d3a5e5544bbee715d9632649` (run 27404861416) is green, completing the slice's evidence set.
