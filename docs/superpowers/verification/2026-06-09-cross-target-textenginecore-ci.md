# Cross-Target CI For TextEngineCore Verification

Date: 2026-06-09

## Scope

Slice 13 verifies PR #7 on branch `slice-12-post-slice-review` for cross-target CI coverage of the `TextEngineCore` package graph. The hosted run validated blocking iOS device and iOS simulator builds on GitHub-hosted macOS, while WASM targets remained nonblocking and were skipped when no runner-matched SDK was available.

The verification covers local host tests, release build, benchmark gate, memory diagnostics, helper self-test, local iOS package graph builds, the hosted PR run, and non-goal source checks. This verification does not change `Sources/TextEngineCore`, `Sources/ViewportBenchmarks`, `Tests`, or `Package.swift`.

## Local Verification

Captured logs are under `/tmp/slice13-local/`.

Command:

```text
swift test
```

Output:

```text
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-09 21:32:53.088.
Executed 39 tests, with 0 failures (0 unexpected) in 0.004 (0.006) seconds
Test Suite 'All tests' passed at 2026-06-09 21:32:53.088.
Executed 39 tests, with 0 failures (0 unexpected) in 0.004 (0.007) seconds
```

Command:

```text
swift build -c release
```

Output:

```text
Building for production...
Build complete! (0.08s)
```

Command:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Output:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1270 p99_ns=1417 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5164 p99_ns=5481 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17231 p99_ns=20109 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
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
```

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Output:

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1835008 rss_after_provider_setup_bytes=1835008 rss_after_core_operation_bytes=2031616 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=2097152 rss_after_core_operation_bytes=2097152 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2113536 rss_after_provider_setup_bytes=13352960 rss_after_core_operation_bytes=13352960 rss_page_size_bytes=16384 rss_provider_delta_bytes=11239424 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

Command:

```text
.github/scripts/cross-target-compile.sh --self-test
```

Output:

```text
self_test=pass
```

Command:

```text
xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS' -derivedDataPath /tmp/ct-preflight-device
```

Output:

```text
** BUILD SUCCEEDED **
```

Command:

```text
xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ct-preflight-sim
```

Output:

```text
** BUILD SUCCEEDED **
```

Local WASM note:

```text
local_swift_version=6.2.1
installed_sdks=swift-6.2.1-RELEASE_wasm,swift-6.2.1-RELEASE_wasm-embedded
textenginecore_wasm_local_build=pass
textenginecore_wasm_embedded_local_build=pass
runner_match=false
```

## Hosted Run

Captured log: `/tmp/slice13-final.log`.

Run metadata:

```text
run_id=27227780370
run_attempt=1
run_url=https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27227780370
event=pull_request
head_sha=5b157e9c62fdd2ecb75edd50ebc8f46dcee34126
conclusion=success
runner_image=macos-15-arm64
runner_image_version=20260527.0100.1
hosted_compute_agent_version=20260520.533
os=macOS 15.7.7
os_build=24G720
cpu_model=Apple M1 (Virtual)
runner_image_env=macos15
```

Head SHA note:

The recorded run covers `5b157e9`, the commit that captured this verification.
Every commit after it on this branch is documentation-only, so the CI-affecting
helper and workflow at the PR HEAD are byte-identical to the verified run
(`git diff 5b157e9..HEAD -- .github/` is empty). The latest hosted PR run at the
time of writing, `27228413355` on `485bab4`, is green on both jobs and
corroborates this. Proof of the exact merged code is the post-merge push run
recorded under Post-Merge Push Run (Task 7), since any pre-merge run necessarily
runs on a pre-merge SHA.

Toolchain:

```text
developer_dir=unset
xcode_select_path=/Applications/Xcode_16.4.app/Contents/Developer
swift_version=Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)
swift_target=arm64-apple-macosx15.0
xcodebuild_version=Xcode 16.4;Build version 16F6
darwin_version=24.6.0
```

Helper metadata:

```text
cross_target_swift_version=6.1.2
cross_target_developer_dir=unset
cross_target_xcode_select_path=/Applications/Xcode_16.4.app/Contents/Developer
cross_target_xcodebuild_version=Xcode 16.4;Build version 16F6
cross_target_iphoneos_sdk_path=/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.5.sdk
cross_target_iphoneos_sdk_version=18.5
cross_target_iphonesimulator_sdk_path=/Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator18.5.sdk
cross_target_iphonesimulator_sdk_version=18.5
```

Cross-target compile results:

```text
cross_target_command target=ios_device cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'"
mode=cross_target_compile target=ios_device result=pass reason=none blocking=true
cross_target_command target=ios_simulator cmd="xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'"
mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true
mode=cross_target_compile target=wasm result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile target=wasm_embedded result=skipped reason=sdk_unavailable blocking=false
mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped blocking_failures=0 exit=0
```

Job timings:

```text
job=Cross-target compile started_at=2026-06-09T18:39:31Z completed_at=2026-06-09T18:40:07Z duration=0m36s timeout=20m conclusion=success
job=Host tests and benchmark gate started_at=2026-06-09T18:39:31Z completed_at=2026-06-09T18:43:59Z conclusion=success
```

Hosted host tests and benchmark gate:

```text
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-09 18:39:58.930.
Executed 39 tests, with 0 failures (0 unexpected) in 0.013 (0.015) seconds
Test Suite 'All tests' passed at 2026-06-09 18:39:58.930.
Executed 39 tests, with 0 failures (0 unexpected) in 0.013 (0.017) seconds
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=2534 p99_ns=4993 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=11201 p99_ns=18081 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=41029 p99_ns=58328 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

Hosted memory diagnostics:

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1556480 rss_after_provider_setup_bytes=1556480 rss_after_core_operation_bytes=1572864 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=16384 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1654784 rss_after_provider_setup_bytes=1654784 rss_after_core_operation_bytes=1654784 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=1654784 rss_after_provider_setup_bytes=12877824 rss_after_core_operation_bytes=12943360 rss_page_size_bytes=16384 rss_provider_delta_bytes=11223040 rss_core_operation_delta_bytes=65536 observation=pass checksum=596788650
```

Hosted realistic observation:

```text
mode=realistic_relative_observation base_sha=7c329289c5bbd148c85bd0e62bbc806cac767964 head_sha=5b157e9c62fdd2ecb75edd50ebc8f46dcee34126 max_ratio=1.044520 observation_threshold=1.221556 observation=clean blocking_ready=false
```

WASM provisioning outcome:

```text
runner_swift_version=6.1.2
matching_wasm_sdk_installed=false
swift_org_wasm_sdks_start=Swift 6.2 and development snapshots
matching_sdk_toolchain_versions_required=true
swift_org_6_1_2_wasm_probe=https://download.swift.org/swift-6.1.2-release/wasm-sdk/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE_wasm.artifactbundle.tar.gz
swift_org_6_1_2_wasm_probe_result=https://swift.org/404.html
swiftwasm_release_probe=swift-wasm-6.1-RELEASE found; swift-wasm-6.1.2-RELEASE absent
exact_github_release_probe_for_6_1_2=http_404
ci_result=wasm_targets_skipped_nonblocking
```

## Post-Merge Push Run

```text
state=pre_merge_pending
reason=PR #7 has not been merged yet
expected_event=push
expected_branch=main
```

## Non-Goal Checks

Command:

```text
git diff main -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Output:

```text
no output
```

## Conclusion

PR #7 has local and hosted evidence for the cross-target CI path. Local verification passed host tests, release build, benchmark gate, memory shape, memory observation, helper self-test, iOS device build, and iOS simulator build. The hosted pull request run passed with iOS device and iOS simulator builds marked blocking, no blocking failures, and successful host tests and benchmark diagnostics.

WASM and WASM embedded were skipped in hosted CI because the GitHub runner used Swift 6.1.2 and no matching WASM SDK was available. The skip was nonblocking by design, and local Swift 6.2.1 WASM package graph builds passed but were not used as runner-matched hosted evidence. WASM and embedded WASM remain observational in Slice 13; promotion to blocking is left to a later slice, once hosted SDK provisioning and compile are proven reliable across runs.
