# RSS Memory Observation Verification

Date: 2026-06-07

## Scope

Slice 9 adds a host-only `--memory-observation` diagnostic to `ViewportBenchmarks`, records Darwin RSS snapshots for the existing memory-shape scenario set, and runs the command in GitHub Actions without RSS budgets.

## Changed Source Files

- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- `Sources/ViewportBenchmarks/MemoryObservationDiagnostics.swift`
- `.github/workflows/swift-ci.yml`

## Non-Goal Checks

The slice did not change:

- `Sources/TextEngineCore`
- `Tests`
- `Package.swift`

## Verification Commands

### Host Tests

Command:

```text
swift test
```

Result: pass.

```text
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
Test Suite 'All tests' started at 2026-06-07 10:53:48.632.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-06-07 10:53:48.632.
Test Suite 'DocumentLineCursorTests' started at 2026-06-07 10:53:48.632.
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
Test Suite 'DocumentLineCursorTests' passed at 2026-06-07 10:53:48.634.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
Test Suite 'DocumentLineValueTests' started at 2026-06-07 10:53:48.634.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' passed (0.000 seconds).
Test Suite 'DocumentLineValueTests' passed at 2026-06-07 10:53:48.634.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'LineGeometryCursorTests' started at 2026-06-07 10:53:48.634.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' passed (0.000 seconds).
Test Suite 'LineGeometryCursorTests' passed at 2026-06-07 10:53:48.635.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportInputValueTests' started at 2026-06-07 10:53:48.635.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' passed (0.000 seconds).
Test Suite 'ViewportInputValueTests' passed at 2026-06-07 10:53:48.635.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-07 10:53:48.635.
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
Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-07 10:53:48.637.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'ViewportRangeTests' started at 2026-06-07 10:53:48.637.
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
Test Suite 'ViewportRangeTests' passed at 2026-06-07 10:53:48.638.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ViewportValidationTests' started at 2026-06-07 10:53:48.638.
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
Test Suite 'ViewportValidationTests' passed at 2026-06-07 10:53:48.639.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-07 10:53:48.639.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.005 (0.007) seconds
Test Suite 'All tests' passed at 2026-06-07 10:53:48.639.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.005 (0.008) seconds
◇ Test run started.
↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
↳ Target Platform: arm64-apple-macosx
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

### Release Build

Command:

```text
swift build -c release
```

Result: pass.

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.08s)
```

### Default Pipeline Benchmark

Command:

```text
swift run -c release ViewportBenchmarks
```

Result: pass.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1354 p99_ns=1484 failures=0 checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5467 p99_ns=5915 failures=0 checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17174 p99_ns=19392 failures=0 checksum=18852477646272000
```

### Range-Only Benchmark

Command:

```text
swift run -c release ViewportBenchmarks -- --range-only
```

Result: pass.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=range_only scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=10 p99_ns=10 failures=0 checksum=5114982400
mode=range_only scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=9 p99_ns=11 failures=0 checksum=511488422400
mode=range_only scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=10 p99_ns=11 failures=0 checksum=5114881152000
```

### Synthetic Benchmark Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.07s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1345 p99_ns=1495 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5579 p99_ns=6294 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17506 p99_ns=18746 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

### Realistic Provider Benchmark

Command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Result: pass.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5785 p99_ns=6123 failures=0 checksum=756321289736960
```

### Memory-Shape Diagnostic

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
```

### RSS Memory Observation Diagnostic

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=1835008 rss_after_provider_setup_bytes=1835008 rss_after_core_operation_bytes=2031616 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=196608 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=2064384 rss_after_provider_setup_bytes=2064384 rss_after_core_operation_bytes=2064384 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=2097152 rss_after_provider_setup_bytes=13336576 rss_after_core_operation_bytes=13336576 rss_page_size_bytes=16384 rss_provider_delta_bytes=11239424 rss_core_operation_delta_bytes=0 observation=pass checksum=596788650
```

### Invalid RSS Observation Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --gate
```

Result: expected non-zero exit (observed exit code `1`) with `error=--memory-observation cannot be combined with --gate`.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--memory-observation cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--memory-observation] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --memory-observation  Run host RSS observation diagnostics.
  --help                Print this help.
```

### Invalid RSS Observation Range-Only Combination

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --range-only
```

Result: expected non-zero exit (observed exit code `1`) with `error=--memory-observation cannot be combined with --range-only`.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.07s)
error=--memory-observation cannot be combined with --range-only
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--memory-observation] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --memory-observation  Run host RSS observation diagnostics.
  --help                Print this help.
```

### Invalid RSS Observation Realistic-Provider Combination

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
```

Result: expected non-zero exit (observed exit code `1`) with `error=--memory-observation cannot be combined with --realistic-provider`.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--memory-observation cannot be combined with --realistic-provider
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--memory-observation] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --memory-observation  Run host RSS observation diagnostics.
  --help                Print this help.
```

### Invalid RSS Observation Memory-Shape Combination

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --memory-shape
```

Result: expected non-zero exit (observed exit code `1`) with `error=--memory-observation cannot be combined with --memory-shape`.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--memory-observation cannot be combined with --memory-shape
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--memory-observation] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --memory-observation  Run host RSS observation diagnostics.
  --help                Print this help.
```

### Workflow Scan

Command:

```text
rg -n "Run memory shape diagnostic|Run RSS memory observation diagnostic|--memory-observation" .github/workflows/swift-ci.yml
```

Result: workflow runs memory shape before RSS memory observation.

```text
38:      - name: Run memory shape diagnostic
41:      - name: Run RSS memory observation diagnostic
42:        run: swift run -c release ViewportBenchmarks -- --memory-observation
```

### Non-Goal Diff Check

Command:

```text
git diff -- Sources/TextEngineCore Tests Package.swift
```

Result: no output.

```text
```

### Implementation Range Non-Goal Diff Check

Command:

```text
git diff fb0277f..HEAD -- Sources/TextEngineCore Tests Package.swift
```

Result: no output for the Slice 9 implementation range.

```text
```

## RSS Interpretation

RSS is page-granular process-level evidence. The diagnostic records `rss_page_size_bytes` and does not treat RSS deltas as exact proof of the `core_owned_bytes_model` value.

## Conclusion

Slice 9 adds observational RSS evidence while preserving existing fixed-height benchmark and memory-shape behavior. The command is CI-visible but not a hard RSS budget.
