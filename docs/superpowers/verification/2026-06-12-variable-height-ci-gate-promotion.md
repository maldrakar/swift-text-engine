# Variable-Height CI Gate Promotion Verification

Date: 2026-06-12

## Scope

This verification covers Slice 15 on branch `slice-15-variable-height-ci-gate`.
It verifies that variable-height benchmark enforcement is promoted to a blocking
Swift CI gate, and that variable-height memory-shape diagnostics use the common
`MemoryShapeSummary` output path while preserving the variable core-owned byte
estimate and cross-variable consistency check.

## Local Verification

The outputs below are from the captured `/private/tmp/slice-15-*.out` files.
To keep this Markdown file ASCII-only, non-ASCII Swift Testing glyphs in the
`swift test` capture are represented as ASCII Unicode escape text.

### swift test

```bash
swift test
```

```text
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
Test Suite 'All tests' started at 2026-06-12 23:53:19.524.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-06-12 23:53:19.524.
Test Suite 'DocumentLineCursorTests' started at 2026-06-12 23:53:19.524.
Test Suite 'DocumentLineCursorTests' passed at 2026-06-12 23:53:19.526.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'DocumentLineValueTests' passed at 2026-06-12 23:53:19.526.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'LineGeometryCursorTests' passed at 2026-06-12 23:53:19.526.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'LineMetricsSourceTests' passed at 2026-06-12 23:53:19.526.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'VariableHeightQueryCountTests' passed at 2026-06-12 23:53:19.527.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'VariableLineGeometryCursorTests' passed at 2026-06-12 23:53:19.528.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'VariableUniformEquivalenceTests' passed at 2026-06-12 23:53:19.528.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'VariableViewportComputeTests' passed at 2026-06-12 23:53:19.530.
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'VariableViewportInputValueTests' passed at 2026-06-12 23:53:19.530.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportInputValueTests' passed at 2026-06-12 23:53:19.530.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-12 23:53:19.533.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'ViewportRangeTests' passed at 2026-06-12 23:53:19.534.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ViewportValidationTests' passed at 2026-06-12 23:53:19.535.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-12 23:53:19.535.
	 Executed 67 tests, with 0 failures (0 unexpected) in 0.007 (0.010) seconds
Test Suite 'All tests' passed at 2026-06-12 23:53:19.535.
	 Executed 67 tests, with 0 failures (0 unexpected) in 0.007 (0.011) seconds
\u25C7 Test run started.
\u21B3 Testing Library Version: 6.2.1 (c9d57c83568b06d)
\u21B3 Target Platform: arm64-apple-macosx
\u2714 Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

Full captured output: `/private/tmp/slice-15-swift-test.out`.

### swift build -c release

```bash
swift build -c release
```

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
```

### swift run -c release ViewportBenchmarks -- --gate

```bash
swift run -c release ViewportBenchmarks -- --gate
```

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1335 p99_ns=1433 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5137 p99_ns=5361 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16845 p99_ns=18453 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

### swift run -c release ViewportBenchmarks -- --variable-height --gate

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

```text
Another instance of SwiftPM (PID: 11017) is already running using '/Users/aabanschikov/swift-text-engine/.build', waiting until that process has finished execution...Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=232 p99_ns=263 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=713 p99_ns=764 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2233 p99_ns=2402 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

### swift run -c release ViewportBenchmarks -- --memory-shape

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

```text
Another instance of SwiftPM (PID: 11052) is already running using '/Users/aabanschikov/swift-text-engine/.build', waiting until that process has finished execution...Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
```

### swift run -c release ViewportBenchmarks -- --memory-observation

```bash
swift run -c release ViewportBenchmarks -- --memory-observation
```

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1851392 rss_after_provider_setup_bytes=1851392 rss_after_core_operation_bytes=2048000 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=2097152 rss_after_core_operation_bytes=2097152 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2129920 rss_after_provider_setup_bytes=13369344 rss_after_core_operation_bytes=13369344 rss_page_size_bytes=16384 rss_provider_delta_bytes=11239424 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

### rg -n "Foundation" Sources/TextEngineCore

```bash
rg -n "Foundation" Sources/TextEngineCore
```

Captured stdout was empty. The shell command confirmed rg status 1/no matches.

### ./.github/scripts/cross-target-compile.sh --self-test

```bash
./.github/scripts/cross-target-compile.sh --self-test
```

```text
self_test=pass
```

### ./.github/scripts/cross-target-compile.sh

```bash
./.github/scripts/cross-target-compile.sh
```

```text
cross_target_swift_version=6.2.1
cross_target_developer_dir=unset
cross_target_xcode_select_path=/Applications/Xcode_26_3.app/Contents/Developer
cross_target_xcodebuild_version=Xcode 26.3;Build version 17C529
cross_target_iphoneos_sdk_path=/Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk
cross_target_iphoneos_sdk_version=26.2
cross_target_iphonesimulator_sdk_path=/Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk
cross_target_iphonesimulator_sdk_version=26.2
cross_target_command target=ios_device cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'"
mode=cross_target_compile target=ios_device result=pass reason=none blocking=true
cross_target_command target=ios_simulator cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'"
mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true
cross_target_wasm_sdk_id target=wasm id=swift-6.2.1-RELEASE_wasm
cross_target_command target=wasm cmd="swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore"
mode=cross_target_compile target=wasm result=pass reason=none blocking=false
cross_target_wasm_sdk_id target=wasm_embedded id=swift-6.2.1-RELEASE_wasm-embedded
cross_target_command target=wasm_embedded cmd="swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore"
mode=cross_target_compile target=wasm_embedded result=pass reason=none blocking=false
mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass blocking_failures=0 exit=0
```

### rg -n -- "--variable-height --gate|synthetic and variable-height gates" AGENTS.md

```bash
rg -n -- "--variable-height --gate|synthetic and variable-height gates" AGENTS.md
```

```text
68:swift run -c release ViewportBenchmarks -- --variable-height --gate   # variable-height local gate
91:  \u2192 `--variable-height --gate` (blocking) \u2192 `--memory-shape`
93:  `continue-on-error`). The synthetic and variable-height gates **fail the job
```

### git diff --check

```bash
git diff --check
```

Captured stdout was empty. The empty output indicates no whitespace errors were reported.

## Workflow Scan

Final workflow step around the variable-height gate:

```yaml
      - name: Run synthetic benchmark gate
        run: swift run -c release ViewportBenchmarks -- --gate

      - name: Run variable-height benchmark gate
        run: swift run -c release ViewportBenchmarks -- --variable-height --gate

      - name: Run memory shape diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-shape
```

The variable-height step runs:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

There is no `continue-on-error: true` in the `Run variable-height benchmark gate` step.

## Hosted PR Run

PR: #11
URL: https://github.com/arthurbanshchikov/swift-text-engine/pull/11
Head SHA: `c06c6d11585b43b2dbddc7d26029abb9f1ce1c47`
Swift CI run id: `27443136804`
Run URL: https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27443136804
Event: `pull_request`
Conclusion: `success`

Job conclusions:

```text
Cross-target compile: success (job id 81121757362)
Host tests and benchmark gate: success (job id 81121757364)
```

Hosted variable-height gate output:

```text
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-12T21:10:14.4627240Z mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=450 p99_ns=851 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-12T21:10:14.4636930Z mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1337 p99_ns=3253 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
Host tests and benchmark gate	Run variable-height benchmark gate	2026-06-12T21:10:14.4639300Z mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=9584 p99_ns=13841 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

## Post-Merge Push Run

PR #11 merged on 2026-06-12 at 21:42:44Z.
Merge commit SHA: `cbb50364ddd0fb47b3805659074e04b1800943a4`
Swift CI push run id: `27444745973`
Run URL: https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27444745973
Event: `push`
Conclusion: `failure`

Job conclusions:

```text
Cross-target compile: failure (job id 81127007885)
Host tests and benchmark gate: failure (job id 81127007921)
```

No hosted `mode=variable_height` lines were produced for the post-merge push
run. Both jobs completed with zero workflow steps, no downloadable log, and the
same GitHub check-run annotation:

```text
The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings
```

This records the post-merge `main` run status for the merged code. It is not a
benchmark, test, or cross-target failure: the hosted jobs did not start because
GitHub Actions account billing/spending limits blocked runner execution.

## Conclusion

Local verification passed, and hosted PR evidence showed the variable-height
benchmark running as a blocking gate with `gate=pass`. The post-merge push run
on `main` exists for merge commit `cbb50364ddd0fb47b3805659074e04b1800943a4`,
but GitHub Actions did not start either job because of account billing/spending
limits. Re-run Swift CI after restoring Actions capacity to collect final
post-merge hosted `gate=pass` lines.
