# Hosted Baseline-Relative Realistic Observation Verification

Date: 2026-06-08

## Scope

Slice 12 adds a PR-only nonblocking hosted realistic-provider base-vs-head observation. The observation uses ungated `--realistic-provider` runs, median-of-4 per side, interleaved run order, and `continue-on-error: true`. Blocking remains disabled.

## Local Verification

Command:

```text
swift test
```

Output:

```text
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version-58A378E29CF047B.txt
Build complete! (0.11s)
Test Suite 'All tests' started at 2026-06-09 03:55:48.134.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-06-09 03:55:48.134.
Test Suite 'DocumentLineCursorTests' started at 2026-06-09 03:55:48.134.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorFetchesOneLinePerBufferedIndex]' started.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorFetchesOneLinePerBufferedIndex]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorReportsMissingIndexesWithoutClampingRange]' started.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorReportsMissingIndexesWithoutClampingRange]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorYieldsBufferedRangeLinesInOrder]' started.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorYieldsBufferedRangeLinesInOrder]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorYieldsNothingForEmptyRangeAndDoesNotFetch]' started.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorYieldsNothingForEmptyRangeAndDoesNotFetch]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testGeneratedRangesFetchOnlyBufferedIndexes]' started.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testGeneratedRangesFetchOnlyBufferedIndexes]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testViewportComputationDoesNotFetchProviderLines]' started.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testViewportComputationDoesNotFetchProviderLines]' passed (0.000 seconds).
Test Suite 'DocumentLineCursorTests' passed at 2026-06-09 03:55:48.136.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'DocumentLineValueTests' started at 2026-06-09 03:55:48.136.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' passed (0.000 seconds).
Test Suite 'DocumentLineValueTests' passed at 2026-06-09 03:55:48.136.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'LineGeometryCursorTests' started at 2026-06-09 03:55:48.136.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' passed (0.000 seconds).
Test Suite 'LineGeometryCursorTests' passed at 2026-06-09 03:55:48.136.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportInputValueTests' started at 2026-06-09 03:55:48.136.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' passed (0.000 seconds).
Test Suite 'ViewportInputValueTests' passed at 2026-06-09 03:55:48.137.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-09 03:55:48.137.
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testGeneratedInputsStayInBounds]' started.
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testGeneratedInputsStayInBounds]' passed (0.002 seconds).
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testOverscanBeforeClampsToZeroWithIntegerMath]' started.
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testOverscanBeforeClampsToZeroWithIntegerMath]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testOverscanClampsAtTopAndBottom]' started.
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testOverscanClampsAtTopAndBottom]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testOverscanExpandsBufferedRange]' started.
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testOverscanExpandsBufferedRange]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testOverscanPreservesPrecisionNearIntMax]' started.
Test Case '-[TextEngineCoreTests.ViewportOverscanInvariantTests testOverscanPreservesPrecisionNearIntMax]' passed (0.000 seconds).
Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-09 03:55:48.139.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'ViewportRangeTests' started at 2026-06-09 03:55:48.139.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testFiniteExtremeOffsetClampsIndexBeforeIntConversion]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testFiniteExtremeOffsetClampsIndexBeforeIntConversion]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testFractionalLineHeightEndBoundaryDoesNotIncludeNextLine]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testFractionalLineHeightStartBoundaryBeginsAtExactLine]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testFractionalLineHeightStartBoundaryBeginsAtExactLine]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testFractionalLineHeightSublineOffsetIncludesPartialLines]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testFractionalLineHeightSublineOffsetIncludesPartialLines]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testLargeEndPartialLineDoesNotSnapDownToBoundary]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testLargeEndPartialLineDoesNotSnapDownToBoundary]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testLargeFractionalOffsetDoesNotSnapToBoundary]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testLargeFractionalOffsetDoesNotSnapToBoundary]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testLargeStartPartialLineDoesNotSnapUpToBoundary]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testLargeStartPartialLineDoesNotSnapUpToBoundary]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testNegativeScrollOffsetClampsToTop]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testNegativeScrollOffsetClampsToTop]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testSublineOffsetUsesFloorForStartAndCeilForEnd]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testSublineOffsetUsesFloorForStartAndCeilForEnd]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testViewportLargerThanDocumentReturnsWholeDocument]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testViewportLargerThanDocumentReturnsWholeDocument]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportRangeTests testZeroHeightViewportProducesEmptyRangeAtOffset]' started.
Test Case '-[TextEngineCoreTests.ViewportRangeTests testZeroHeightViewportProducesEmptyRangeAtOffset]' passed (0.000 seconds).
Test Suite 'ViewportRangeTests' passed at 2026-06-09 03:55:48.140.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ViewportValidationTests' started at 2026-06-09 03:55:48.140.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testEmptyDocumentReturnsEmptyRange]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testEmptyDocumentReturnsEmptyRange]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNegativeLineCountFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNegativeLineCountFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNegativeOverscanFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNegativeOverscanFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNegativeViewportHeightFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNegativeViewportHeightFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteLineHeightFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteLineHeightFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteScrollOffsetYFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteScrollOffsetYFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteViewportHeightFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonFiniteViewportHeightFails]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonPositiveLineHeightFails]' started.
Test Case '-[TextEngineCoreTests.ViewportValidationTests testNonPositiveLineHeightFails]' passed (0.000 seconds).
Test Suite 'ViewportValidationTests' passed at 2026-06-09 03:55:48.141.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-09 03:55:48.141.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.004 (0.006) seconds
Test Suite 'All tests' passed at 2026-06-09 03:55:48.141.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.004 (0.007) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
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
[0/2] Write swift-version-58A378E29CF047B.txt
Build complete! (0.08s)
```

Command:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1150 p99_ns=1197 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4733 p99_ns=4910 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=15562 p99_ns=16361 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

Command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5031 p99_ns=5169 failures=0 checksum=756321289736960
```

Command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=6288 p99_ns=6576 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
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
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1851392 rss_after_provider_setup_bytes=1851392 rss_after_core_operation_bytes=2048000 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=2097152 rss_after_core_operation_bytes=2097152 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2113536 rss_after_provider_setup_bytes=13352960 rss_after_core_operation_bytes=13352960 rss_page_size_bytes=16384 rss_provider_delta_bytes=11239424 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

Command:

```text
.github/scripts/realistic-relative-observation.sh --self-test
```

Output:

```text
self_test=pass
```

## Hosted No-Op Samples

### Accepted Sample 1

- Run ID: `27169643767`
- Attempt: `1`
- Run URL: `https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27169643767`
- Event: `pull_request`
- Head branch: `slice-12-hosted-baseline-relative-realistic-observation`
- Base SHA: `cd907a8d7ddcf1d7defd25f1eee60adec60379e4`
- Head SHA: `203bcf4b0b31d0308c11119e4f74e03cb457d8a0`
- Runner image: `macos15`; setup log image: `macos-15-arm64`
- CPU model: `Apple M1 (Virtual)`
- Swift version: `Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)`
- Xcode version: `Xcode 16.4`; build version `16F6`
- `uname -a`: `Darwin sjc20-cw713-7a24d7ba-3d01-43bf-b40b-6e188ecb3023-C611674A3AD3.local 24.6.0 Darwin Kernel Version 24.6.0: Tue Apr 21 20:18:00 PDT 2026; root:xnu-11417.140.69.710.16~1/RELEASE_ARM64_VMAPPLE arm64`
- Started timestamp: `2026-06-08T22:01:17Z`
- Finished timestamp: `2026-06-08T22:03:30Z`; observation finished at `2026-06-08T22:02:58Z`
- Time gap from previous accepted sample: not applicable
- Summary line:

```text
mode=realistic_relative_observation base_sha=cd907a8d7ddcf1d7defd25f1eee60adec60379e4 head_sha=203bcf4b0b31d0308c11119e4f74e03cb457d8a0 comparison_repetitions_per_side=4 run_order=base,head,head,base,base,head,head,base base_p95_ns_values=8756,8783,8787,8831 head_p95_ns_values=8727,8752,8786,9286 base_p99_ns_values=9183,9877,9647,9948 head_p99_ns_values=9244,9158,9486,13116 base_median_p95_ns=8785.000000 head_median_p95_ns=8769.000000 base_median_p99_ns=9762.000000 head_median_p99_ns=9365.000000 p95_ratio=0.998179 p99_ratio=0.959332 max_ratio=0.998179 observation_threshold=1.50 observation=clean blocking_ready=false
```

### Accepted Sample 2

- Run ID: `27169643767`
- Attempt: `2`
- Run URL: `https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27169643767`
- Event: `pull_request`
- Head branch: `slice-12-hosted-baseline-relative-realistic-observation`
- Base SHA: `cd907a8d7ddcf1d7defd25f1eee60adec60379e4`
- Head SHA: `203bcf4b0b31d0308c11119e4f74e03cb457d8a0`
- Runner image: `macos15`; setup log image: `macos-15-arm64`
- CPU model: `Apple M1 (Virtual)`
- Swift version: `Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)`
- Xcode version: `Xcode 16.4`; build version `16F6`
- `uname -a`: `Darwin sjc20-bb714-fbeddc5e-ea30-4c98-98db-92082b620963-DA8D07B1B752.local 24.6.0 Darwin Kernel Version 24.6.0: Tue Apr 21 20:18:00 PDT 2026; root:xnu-11417.140.69.710.16~1/RELEASE_ARM64_VMAPPLE arm64`
- Started timestamp: `2026-06-08T22:52:55Z`
- Finished timestamp: `2026-06-08T22:55:06Z`; observation finished at `2026-06-08T22:54:55Z`
- Time gap from previous accepted sample finish to this start: `49m25s`
- Summary line:

```text
mode=realistic_relative_observation base_sha=cd907a8d7ddcf1d7defd25f1eee60adec60379e4 head_sha=203bcf4b0b31d0308c11119e4f74e03cb457d8a0 comparison_repetitions_per_side=4 run_order=base,head,head,base,base,head,head,base base_p95_ns_values=17551,13561,12920,14589 head_p95_ns_values=15232,12721,17910,14493 base_p99_ns_values=24401,21188,22000,22817 head_p99_ns_values=22467,21420,23173,22442 base_median_p95_ns=14075.000000 head_median_p95_ns=14862.500000 base_median_p99_ns=22408.500000 head_median_p99_ns=22454.500000 p95_ratio=1.055950 p99_ratio=1.002053 max_ratio=1.055950 observation_threshold=1.50 observation=clean blocking_ready=false
```

### Accepted Sample 3

- Run ID: `27169643767`
- Attempt: `3`
- Run URL: `https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27169643767`
- Event: `pull_request`
- Head branch: `slice-12-hosted-baseline-relative-realistic-observation`
- Base SHA: `cd907a8d7ddcf1d7defd25f1eee60adec60379e4`
- Head SHA: `203bcf4b0b31d0308c11119e4f74e03cb457d8a0`
- Runner image: `macos15`; setup log image: `macos-15-arm64`
- CPU model: `Apple M1 (Virtual)`
- Swift version: `Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)`
- Xcode version: `Xcode 16.4`; build version `16F6`
- `uname -a`: `Darwin iad20-eo1210-83e172ad-26a8-4322-a9f0-fce056f8539a-16676B6CEC32.local 24.6.0 Darwin Kernel Version 24.6.0: Tue Apr 21 20:18:00 PDT 2026; root:xnu-11417.140.69.710.16~1/RELEASE_ARM64_VMAPPLE arm64`
- Started timestamp: `2026-06-08T23:27:42Z`
- Finished timestamp: `2026-06-08T23:29:53Z`; observation finished at `2026-06-08T23:29:48Z`
- Time gap from previous accepted sample finish to this start: `32m36s`
- Summary line:

```text
mode=realistic_relative_observation base_sha=cd907a8d7ddcf1d7defd25f1eee60adec60379e4 head_sha=203bcf4b0b31d0308c11119e4f74e03cb457d8a0 comparison_repetitions_per_side=4 run_order=base,head,head,base,base,head,head,base base_p95_ns_values=21153,20940,21294,15501 head_p95_ns_values=20732,20969,19479,19762 base_p99_ns_values=27475,27148,26459,24749 head_p99_ns_values=26267,28266,25385,25090 base_median_p95_ns=21046.500000 head_median_p95_ns=20247.000000 base_median_p99_ns=26803.500000 head_median_p99_ns=25826.000000 p95_ratio=0.962013 p99_ratio=0.963531 max_ratio=0.963531 observation_threshold=1.50 observation=clean blocking_ready=false
```

### Accepted Sample 4

- Run ID: `27169643767`
- Attempt: `4`
- Run URL: `https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27169643767`
- Event: `pull_request`
- Head branch: `slice-12-hosted-baseline-relative-realistic-observation`
- Base SHA: `cd907a8d7ddcf1d7defd25f1eee60adec60379e4`
- Head SHA: `203bcf4b0b31d0308c11119e4f74e03cb457d8a0`
- Runner image: `macos15`; setup log image: `macos-15-arm64`
- CPU model: `Apple M1 (Virtual)`
- Swift version: `Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)`
- Xcode version: `Xcode 16.4`; build version `16F6`
- `uname -a`: `Darwin sat12-dp151-1291979e-ae65-4f2b-bb6f-2242f0ea0f3b-E2DE37B9FDC2.local 24.6.0 Darwin Kernel Version 24.6.0: Tue Apr 21 20:18:00 PDT 2026; root:xnu-11417.140.69.710.16~1/RELEASE_ARM64_VMAPPLE arm64`
- Started timestamp: `2026-06-09T00:17:33Z`
- Finished timestamp: `2026-06-09T00:19:42Z`; observation finished at `2026-06-09T00:19:31Z`
- Time gap from previous accepted sample finish to this start: `47m40s`
- Summary line:

```text
mode=realistic_relative_observation base_sha=cd907a8d7ddcf1d7defd25f1eee60adec60379e4 head_sha=203bcf4b0b31d0308c11119e4f74e03cb457d8a0 comparison_repetitions_per_side=4 run_order=base,head,head,base,base,head,head,base base_p95_ns_values=9662,16566,18500,17775 head_p95_ns_values=18682,15315,19579,10209 base_p99_ns_values=11742,21309,23486,24263 head_p99_ns_values=24441,21051,24621,14473 base_median_p95_ns=17170.500000 head_median_p95_ns=16998.500000 base_median_p99_ns=22397.500000 head_median_p99_ns=22746.000000 p95_ratio=0.989983 p99_ratio=1.015560 max_ratio=1.015560 observation_threshold=1.50 observation=clean blocking_ready=false
```

### Accepted Sample 5

- Run ID: `27169643767`
- Attempt: `5`
- Run URL: `https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27169643767`
- Event: `pull_request`
- Head branch: `slice-12-hosted-baseline-relative-realistic-observation`
- Base SHA: `cd907a8d7ddcf1d7defd25f1eee60adec60379e4`
- Head SHA: `203bcf4b0b31d0308c11119e4f74e03cb457d8a0`
- Runner image: `macos15`; setup log image: `macos-15-arm64`
- CPU model: `Apple M1 (Virtual)`
- Swift version: `Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)`
- Xcode version: `Xcode 16.4`; build version `16F6`
- `uname -a`: `Darwin sjc22-be110-d9649281-2cd1-46b8-beda-36ddfdbe4599-C6746AFB673E.local 24.6.0 Darwin Kernel Version 24.6.0: Tue Apr 21 20:18:00 PDT 2026; root:xnu-11417.140.69.710.16~1/RELEASE_ARM64_VMAPPLE arm64`
- Started timestamp: `2026-06-09T00:51:55Z`
- Finished timestamp: `2026-06-09T00:53:51Z`; observation finished at `2026-06-09T00:53:39Z`
- Time gap from previous accepted sample finish to this start: `32m13s`
- Summary line:

```text
mode=realistic_relative_observation base_sha=cd907a8d7ddcf1d7defd25f1eee60adec60379e4 head_sha=203bcf4b0b31d0308c11119e4f74e03cb457d8a0 comparison_repetitions_per_side=4 run_order=base,head,head,base,base,head,head,base base_p95_ns_values=8764,8799,8895,10940 head_p95_ns_values=9103,8897,10750,10047 base_p99_ns_values=10136,11781,10932,17094 head_p99_ns_values=13563,12669,14484,12861 base_median_p95_ns=8847.000000 head_median_p95_ns=9575.000000 base_median_p99_ns=11356.500000 head_median_p99_ns=13212.000000 p95_ratio=1.082288 p99_ratio=1.163387 max_ratio=1.163387 observation_threshold=1.50 observation=clean blocking_ready=false
```

Runner image was identical across accepted samples: `macos15` in the observation environment and `macos-15-arm64` in setup logs. CPU model was identical across accepted samples: `Apple M1 (Virtual)`. All accepted samples share run ID `27169643767` through rerun attempts 1-5; that correlation is an initial-calibration limitation because the accepted samples are reruns of one PR workflow run rather than five independent workflow run IDs.

## Threshold Decision

`/tmp/slice12-realistic-relative-samples/accepted-count.txt`:

```text
accepted_noop_samples=5
```

`/tmp/slice12-realistic-relative-samples/threshold.txt`:

```text
max_noop_ratio=1.163387
candidate_threshold=1.221556
observation_threshold=1.221556
threshold_eligible_for_future_blocking=true
```

## Final Workflow State

Command:

```text
rg -n "fetch-depth: 0|Observe realistic provider relative performance|continue-on-error: true" .github/workflows/swift-ci.yml
```

Output captured after editing:

```text
26:          fetch-depth: 0
46:      - name: Observe realistic provider relative performance
48:        continue-on-error: true
```

Command:

```text
rg -n "REALISTIC_RELATIVE_OBSERVATION_THRESHOLD" .github/workflows/swift-ci.yml
```

Output captured after editing:

```text
50:          REALISTIC_RELATIVE_OBSERVATION_THRESHOLD: "1.221556"
77:            --threshold "${REALISTIC_RELATIVE_OBSERVATION_THRESHOLD}"
```

Command:

```text
rg -n -- "--realistic-provider --gate" .github/workflows/swift-ci.yml
```

Output captured after editing:

```text
```

Exit code: `1`. No hosted relative workflow command uses `--realistic-provider --gate`.

Existing stable gates in `.github/workflows/swift-ci.yml` remain:

```text
37:      - name: Run synthetic benchmark gate
38:        run: swift run -c release ViewportBenchmarks -- --gate
40:      - name: Run memory shape diagnostic
41:        run: swift run -c release ViewportBenchmarks -- --memory-shape
43:      - name: Run RSS memory observation diagnostic
44:        run: swift run -c release ViewportBenchmarks -- --memory-observation
```

## Final Hosted PR Verification

- Run ID: `27177155119`
- Attempt: `1`
- Run URL: `https://github.com/arthurbanshchikov/swift-text-engine/actions/runs/27177155119`
- Event: `pull_request`
- Head SHA: `45fa749d866d26891e829a7047d3bb821f30a0a9`
- Conclusion: `success`
- Job duration: `4m54s` (`2026-06-09T01:04:55Z` to `2026-06-09T01:09:49Z`)
- Final observation summary line:

```text
mode=realistic_relative_observation base_sha=cd907a8d7ddcf1d7defd25f1eee60adec60379e4 head_sha=45fa749d866d26891e829a7047d3bb821f30a0a9 comparison_repetitions_per_side=4 run_order=base,head,head,base,base,head,head,base base_p95_ns_values=19355,20866,18791,21034 head_p95_ns_values=15070,20880,20034,21321 base_p99_ns_values=25048,30238,25093,26673 head_p99_ns_values=21803,36698,26718,35101 base_median_p95_ns=20110.500000 head_median_p95_ns=20457.000000 base_median_p99_ns=25883.000000 head_median_p99_ns=30909.500000 p95_ratio=1.017230 p99_ratio=1.194201 max_ratio=1.194201 observation_threshold=1.221556 observation=clean blocking_ready=false
```

Stable gates passed in the final hosted run:

```text
Run host tests
Run synthetic benchmark gate
Run memory shape diagnostic
Run RSS memory observation diagnostic
```

The observation step was nonblocking by workflow configuration:

```text
continue-on-error: true
```

## Non-Goal Checks

Command:

```text
git diff main -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Output:

```text
```

Result: no `TextEngineCore` changes, no benchmark budget changes, and no `Package.swift` changes.

## Conclusion

Slice 12 is observational-only, blocking remains disabled, and promotion requires a later slice after the frozen no-op-equivalent evidence rule is satisfied.
