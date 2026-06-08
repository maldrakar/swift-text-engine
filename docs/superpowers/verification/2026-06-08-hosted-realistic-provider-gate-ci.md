# Hosted Realistic Provider Gate CI Verification

Date: 2026-06-08

## Scope

Slice 11 collects hosted macOS evidence for the existing realistic-provider gate and decides whether `.github/workflows/swift-ci.yml` should run `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`.

The slice does not change `TextEngineCore`, `Sources/ViewportBenchmarks`, `Tests`, `Package.swift`, benchmark budgets, memory budgets, branch protection, rulesets, cross-target CI, or variable-height layout.

## Local Preflight

```text
command=git status --short
result=no output before branch creation
```

```text
command=swift test
exit_code=0
xctest_tests=39
failures=0
```

```text
command=swift build -c release
exit_code=0
```

```text
command=swift run -c release ViewportBenchmarks -- --realistic-provider --gate
exit_code=0
output=mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5428 p99_ns=5721 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

## Calibration Branch

```text
branch=slice-11-hosted-realistic-provider-gate-ci
calibration_head_sha=428a5b72d09112d2ef191a323af281862149bdcb
workflow_dispatch_on_main=false
workflow_dispatch_reason=not-introduced
```

## Hosted Samples

```text
sample=1
run_id=27156757711
run_attempt=1
run_url=https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27156757711/attempts/1
event=pull_request
head_branch=slice-11-hosted-realistic-provider-gate-ci
head_sha=428a5b72d09112d2ef191a323af281862149bdcb
conclusion=success
step_ran=true
output=mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=15664 p99_ns=21660 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

```text
sample=2
run_id=27156757711
run_attempt=2
run_url=https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27156757711/attempts/2
event=pull_request
head_branch=slice-11-hosted-realistic-provider-gate-ci
head_sha=428a5b72d09112d2ef191a323af281862149bdcb
conclusion=success
step_ran=true
output=mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=15553 p99_ns=21366 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

```text
sample=3
run_id=27156757711
run_attempt=3
run_url=https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27156757711/attempts/3
event=pull_request
head_branch=slice-11-hosted-realistic-provider-gate-ci
head_sha=428a5b72d09112d2ef191a323af281862149bdcb
conclusion=success
step_ran=true
output=mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=19745 p99_ns=25845 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

## Hosted Decision

```text
accepted_hosted_samples=3
max_hosted_p95_ns=19745
max_hosted_p99_ns=25845
p95_margin_threshold_ns=14000
p99_margin_threshold_ns=35000
p95_margin_ok=false
p99_margin_ok=true
ci_enforcement=deferred
workflow_step_final_state=not_added
workflow_dispatch_final_state=absent
```

## Final Local Verification

```text
command=swift test
exit_code=0
output=[0/1] Planning build
output=Building for debugging...
output=[0/4] Write swift-version--2EFC8FE404102F05.txt
output=Build complete! (0.10s)
output=Test Suite 'All tests' started at 2026-06-08 21:23:17.404.
output=Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-06-08 21:23:17.405.
output=Test Suite 'DocumentLineCursorTests' started at 2026-06-08 21:23:17.405.
output=Test Suite 'DocumentLineCursorTests' passed at 2026-06-08 21:23:17.407.
output=	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
output=Test Suite 'DocumentLineValueTests' started at 2026-06-08 21:23:17.407.
output=Test Suite 'DocumentLineValueTests' passed at 2026-06-08 21:23:17.407.
output=	 Executed 4 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
output=Test Suite 'LineGeometryCursorTests' started at 2026-06-08 21:23:17.407.
output=Test Suite 'LineGeometryCursorTests' passed at 2026-06-08 21:23:17.407.
output=	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
output=Test Suite 'ViewportInputValueTests' started at 2026-06-08 21:23:17.407.
output=Test Suite 'ViewportInputValueTests' passed at 2026-06-08 21:23:17.407.
output=	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
output=Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-08 21:23:17.407.
output=Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-08 21:23:17.410.
output=	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
output=Test Suite 'ViewportRangeTests' started at 2026-06-08 21:23:17.410.
output=Test Suite 'ViewportRangeTests' passed at 2026-06-08 21:23:17.410.
output=	 Executed 11 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
output=Test Suite 'ViewportValidationTests' started at 2026-06-08 21:23:17.410.
output=Test Suite 'ViewportValidationTests' passed at 2026-06-08 21:23:17.411.
output=	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
output=Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-08 21:23:17.411.
output=	 Executed 39 tests, with 0 failures (0 unexpected) in 0.004 (0.006) seconds
output=Test Suite 'All tests' passed at 2026-06-08 21:23:17.411.
output=	 Executed 39 tests, with 0 failures (0 unexpected) in 0.004 (0.007) seconds
output=◇ Test run started.
output=↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
output=↳ Target Platform: arm64-apple-macosx
output=✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

```text
command=swift build -c release
exit_code=0
output=[0/1] Planning build
output=Building for production...
output=[0/2] Write swift-version--2EFC8FE404102F05.txt
output=Build complete! (0.11s)
```

```text
command=swift run -c release ViewportBenchmarks -- --gate
exit_code=0
output=Building for production...
output=[0/2] Write swift-version--2EFC8FE404102F05.txt
output=Build of product 'ViewportBenchmarks' complete! (0.07s)
output=mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1360 p99_ns=1502 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
output=mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5352 p99_ns=5606 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
output=mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17894 p99_ns=19617 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

```text
command=swift run -c release ViewportBenchmarks -- --realistic-provider --gate
exit_code=0
output=Building for production...
output=[0/2] Write swift-version--2EFC8FE404102F05.txt
output=Build of product 'ViewportBenchmarks' complete! (0.07s)
output=mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5555 p99_ns=5762 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

```text
command=swift run -c release ViewportBenchmarks -- --memory-shape
exit_code=0
output=Building for production...
output=[0/2] Write swift-version--2EFC8FE404102F05.txt
output=Build of product 'ViewportBenchmarks' complete! (0.06s)
output=mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
output=mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
output=mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
```

```text
command=swift run -c release ViewportBenchmarks -- --memory-observation
exit_code=0
output=Building for production...
output=[0/2] Write swift-version--2EFC8FE404102F05.txt
output=Build of product 'ViewportBenchmarks' complete! (0.06s)
output=mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1818624 rss_after_provider_setup_bytes=1818624 rss_after_core_operation_bytes=2015232 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
output=mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=2097152 rss_after_core_operation_bytes=2097152 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
output=mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=13320192 rss_after_core_operation_bytes=13320192 rss_page_size_bytes=16384 rss_provider_delta_bytes=11223040 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

## Workflow Scan

```text
command=rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
exit_code=1
result=no output
```

```text
command=rg -n "workflow_dispatch" .github/workflows/swift-ci.yml
exit_code=1
result=no output
```

## Non-Goal Checks

```text
command=git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
result=no output
```

## Final Hosted PR Verification

```text
command=gh run list --workflow "Swift CI" --branch slice-11-hosted-realistic-provider-gate-ci --event pull_request --limit 10 --json databaseId,url,event,headBranch,headSha,status,conclusion,createdAt,updatedAt
matched_run_id=27158848316
matched_run_url=https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27158848316
event=pull_request
head_branch=slice-11-hosted-realistic-provider-gate-ci
head_sha=0bee2eae6d424a9ecec765fd35d9578a2c8dfbdf
status=completed
conclusion=success
created_at=2026-06-08T18:35:13Z
updated_at=2026-06-08T18:37:38Z
```

```text
command=gh run watch 27158848316 --exit-status
exit_code=0
job=Host tests and benchmark gate
job_id=80168641200
job_duration=2m20s
steps=Set up job; Check out repository; Show toolchain; Run host tests; Run synthetic benchmark gate; Run memory shape diagnostic; Run RSS memory observation diagnostic; Post Check out repository; Complete job
realistic_provider_step_absent=true
```

```text
command=gh run view 27158848316 --log | rg -n "Run realistic provider benchmark gate|--realistic-provider --gate|mode=realistic_provider"
exit_code=1
result=no output
```
