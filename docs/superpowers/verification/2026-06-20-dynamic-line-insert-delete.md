# Slice 23 Dynamic Line Insert/Delete Verification

Date: 2026-06-20
Branch: `slice-23-dynamic-line-insert-delete`
Implementation head SHA verified before this artifact:
`2bcda9683a765622e6ca04b1218b2daf80ff6bde`

## Summary

Verified Slice 23 dynamic line insert/delete implementation evidence for
`BalancedTreeLineMetrics`, structural mutation benchmarks, portability-sensitive
provider builds, Foundation-free source boundaries, diff hygiene, and iOS
cross-target compile coverage for both `TextEngineCore` and
`TextEngineReferenceProviders`.

Baseline XCTest total before the slice was 75 tests, from the pre-slice
baseline run. Final verification executed 90 XCTest tests, matching the
expected increase of 15 balanced-tree tests, including the additional free-list
quality review test.

SwiftPM commands initially hit the sandbox-denied Clang module cache path
`/Users/aabanschikov/.cache/clang/.../SwiftShims-23HTR8TX6995F.pcm` and were
rerun with approval using the same command strings. The iOS cross-target command
also initially failed in the sandbox with `xcodebuild_list_failed`; the approved
rerun below passed.

Local verification command outputs were captured at implementation SHA
`2bcda9683a765622e6ca04b1218b2daf80ff6bde` before this artifact was committed.
The final Task 9 artifact commit adds only
`docs/superpowers/verification/2026-06-20-dynamic-line-insert-delete.md` on top
of that implementation scope; final artifact-scope evidence is recorded below.

## Structural Mutation Budgets

Task 7 original ungated observations:

| Scenario | Observed p95 ns | Observed p99 ns | Budget p95 ns | Budget p99 ns |
| --- | ---: | ---: | ---: | ---: |
| 1k lines | 1709 | 2716 | 20000 | 40000 |
| 100k lines | 7606 | 7798 | 80000 | 120000 |
| 1m lines | 30989 | 33275 | 250000 | 400000 |

Later quality-review observations:

| Scenario | Observed p95 ns | Observed p99 ns | Budget p95 ns | Budget p99 ns |
| --- | ---: | ---: | ---: | ---: |
| 1k lines | 2032 | 2260 | 20000 | 40000 |
| 100k lines | 9256 | 10101 | 80000 | 120000 |
| 1m lines | 38964 | 41298 | 250000 | 400000 |

Current gated verification observations:

| Scenario | Observed p95 ns | Observed p99 ns | Budget p95 ns | Budget p99 ns | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| 1k lines | 1763 | 1844 | 20000 | 40000 | pass |
| 100k lines | 8412 | 9313 | 80000 | 120000 | pass |
| 1m lines | 37176 | 39708 | 250000 | 400000 | pass |

Task 7 plan correction: `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
was added to the Task 7 diff because the compiler red-state exposed an
exhaustive switch that had to handle `.structuralMutation`.

## Hosted Runs

All three required job contexts are `success` on both the PR-head run and the
post-merge push run, verified at the **step-log** level (not just job
conclusion). The new `--structural-mutation` gate is deliberately **not** wired
into CI this slice (Non-Goal: no workflow change), so it does not appear in the
hosted host-tests job; its proof is the local gate recorded above.

### PR #34 head run

- Run: `27864913365` (workflow `Swift CI`), head SHA
  `2f59454583178274564561e5de46bbe37a3efe1d`.
- `Host tests and benchmark gate` — job `82467240177`, conclusion `success`.
  Step logs: `Executed 90 tests, with 0 failures`; synthetic `gate=pass` (1k/100k/1m),
  `variable_height provider=prefix_sum gate=pass`,
  `variable_height_mutation provider=fenwick gate=pass` (unchanged Fenwick gate),
  `memory_shape ... invariant=pass`.
- `iOS cross-target compile` — job `82467240161`, conclusion `success`. Step logs:
  `package=core` and `package=providers` both `result=pass` on `ios_device` and
  `ios_simulator`; `mode=cross_target_compile_overall blocking_failures=0 exit=0`.
- `WASM cross-target observation` — job `82467240163`, conclusion `success`. Step
  logs: both packages on both WASM kinds `result=skipped reason=sdk_unavailable
  blocking=false`; overall `exit=0` (expected non-blocking SDK skip).

### Post-merge push run

- Merge commit: `f20c2479ba87770461ae9ef14ae38508e0c3199a`
  (`Merge pull request #34 from maldrakar/slice-23-dynamic-line-insert-delete`).
- Run: `27865474380` (workflow `Swift CI`, event `push` on `main`), head SHA
  `f20c2479ba87770461ae9ef14ae38508e0c3199a`, conclusion `success`.
- `Host tests and benchmark gate` — job `82468769079`, conclusion `success`.
  Step logs: `Executed 90 tests, with 0 failures`; synthetic `gate=pass`,
  `variable_height gate=pass`, `variable_height_mutation gate=pass`,
  `memory_shape ... invariant=pass`.
- `iOS cross-target compile` — job `82468769065`, conclusion `success`. Step logs:
  `package=core` and `package=providers` both `result=pass` on `ios_device` and
  `ios_simulator`; `mode=cross_target_compile_overall blocking_failures=0 exit=0`.
- `WASM cross-target observation` — job `82468769083`, conclusion `success`. Step
  logs: both packages on both WASM kinds `result=skipped reason=sdk_unavailable
  blocking=false`; overall `exit=0`.

This evidence-fill commit lands on `slice-23-post-merge-verification` (PR after
the merged Slice 23 PR #34), mirroring the Slice 21 / Slice 22 split of PR-head
behavior from post-merge push evidence. Land it before writing the Slice 23
post-slice review so `main`'s verification record never sits with `Pending`
hosted placeholders (Slice 22 review lesson #3).

## Commands

### Host Tests

```bash
swift test 2>&1 | tail -15
```

```text
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteScrollOffsetYFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteViewportHeightFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteViewportHeightFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonPositiveLineHeightFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonPositiveLineHeightFails]' passed (0.000 seconds).
Test Suite 'ViewportValidationTests' passed at 2026-06-20 10:03:45.651.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-20 10:03:45.651.
	 Executed 90 tests, with 0 failures (0 unexpected) in 1.039 (1.043) seconds
Test Suite 'All tests' passed at 2026-06-20 10:03:45.651.
	 Executed 90 tests, with 0 failures (0 unexpected) in 1.039 (1.044) seconds
◇ Test run started.
↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
↳ Target Platform: arm64-apple-macosx
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

### Release Build

```bash
swift build -c release 2>&1 | tail -3
```

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
```

### Reference Provider Release Build

```bash
swift build -c release --target TextEngineReferenceProviders 2>&1 | tail -3
```

```text
Building for production...
[0/1] Write swift-version--2EFC8FE404102F05.txt
Build of target: 'TextEngineReferenceProviders' complete! (0.06s)
```

### Synthetic Benchmark Gate

```bash
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -6
```

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1276 p99_ns=1361 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5419 p99_ns=5797 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17385 p99_ns=17946 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

### Variable-Height Benchmark Gate

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate 2>&1 | tail -4
```

```text
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=214 p99_ns=237 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=708 p99_ns=797 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2203 p99_ns=2454 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

### Variable-Height Mutation Benchmark Gate

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate 2>&1 | tail -4
```

```text
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=417 p99_ns=447 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1641 p99_ns=1694 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5134 p99_ns=5302 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
```

### Structural Mutation Benchmark Gate

```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate 2>&1 | tail -4
```

```text
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1763 p99_ns=1844 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=8412 p99_ns=9313 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=37176 p99_ns=39708 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

### Memory Shape

```bash
swift run -c release ViewportBenchmarks -- --memory-shape 2>&1 | tail -4
```

```text
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
```

### Foundation Scan: Core

```bash
rg -n "Foundation" Sources/TextEngineCore; echo "core_scan_exit=$?"
```

```text
core_scan_exit=1
```

### Foundation Scan: Reference Providers

```bash
rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "providers_scan_exit=$?"
```

```text
providers_scan_exit=1
```

### Cross-Target Helper Self-Test

```bash
./.github/scripts/cross-target-compile.sh --self-test 2>&1 | tail -3
```

```text
self_test=pass
```

### Diff Whitespace Check

```bash
git diff --check; echo "diff_check_exit=$?"
```

```text
diff_check_exit=0
```

### Diff Scope

This scope was captured at implementation SHA
`2bcda9683a765622e6ca04b1218b2daf80ff6bde`, before this verification artifact
was committed.

```bash
git diff --name-only main...HEAD
```

```text
AGENTS.md
Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift
Sources/ViewportBenchmarks/BenchmarkOptions.swift
Sources/ViewportBenchmarks/BenchmarkProgram.swift
Sources/ViewportBenchmarks/StructuralMutationBenchmark.swift
Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
docs/superpowers/plans/2026-06-20-dynamic-line-insert-delete.md
docs/superpowers/specs/2026-06-20-dynamic-line-insert-delete-design.md
```

### Verification Artifact Scope

```bash
git diff --name-only 2bcda9683a765622e6ca04b1218b2daf80ff6bde..HEAD
```

```text
docs/superpowers/verification/2026-06-20-dynamic-line-insert-delete.md
```

### iOS Cross-Target Compile

```bash
./.github/scripts/cross-target-compile.sh --targets ios 2>&1 | tail -10
```

```text
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
```
