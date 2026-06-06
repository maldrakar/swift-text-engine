# Viewport Benchmarks Decomposition Verification

Date: 2026-06-06

## Scope

Slice 8 split `Sources/ViewportBenchmarks/main.swift` into focused files without changing benchmark behavior.

## Changed Source Files

- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- `Sources/ViewportBenchmarks/BenchmarkModels.swift`
- `Sources/ViewportBenchmarks/BenchmarkSupport.swift`
- `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- `Sources/ViewportBenchmarks/main.swift`

## Non-Goal Checks

The slice did not change:

- `Sources/TextEngineCore`
- `Tests`
- `Package.swift`
- `.github/workflows/swift-ci.yml`

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
[0/6] Write sources
[1/6] Write swift-version--2EFC8FE404102F05.txt
[3/14] Compiling ViewportBenchmarks RealisticProviderBenchmark.swift
[4/14] Compiling ViewportBenchmarks SyntheticBenchmarks.swift
[5/14] Compiling ViewportBenchmarks BenchmarkSupport.swift
[6/14] Compiling ViewportBenchmarks BenchmarkOptions.swift
[7/14] Emitting module ViewportBenchmarks
[8/14] Compiling ViewportBenchmarks BenchmarkModels.swift
[9/14] Compiling ViewportBenchmarks main.swift
[10/14] Compiling ViewportBenchmarks BenchmarkProgram.swift
[11/14] Compiling ViewportBenchmarks MemoryShapeDiagnostics.swift
[11/14] Write Objects.LinkFileList
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswiftCore.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswiftSwiftOnoneSupport.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswift_Builtin_float.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswift_Concurrency.dylib' which was built for newer version 13.0
[12/14] Linking ViewportBenchmarks
[13/14] Applying ViewportBenchmarks
Build complete! (0.81s)
Test Suite 'All tests' started at 2026-06-06 23:59:50.146.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-06-06 23:59:50.147.
Test Suite 'DocumentLineCursorTests' started at 2026-06-06 23:59:50.147.
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
Test Suite 'DocumentLineCursorTests' passed at 2026-06-06 23:59:50.148.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'DocumentLineValueTests' started at 2026-06-06 23:59:50.148.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' passed (0.000 seconds).
Test Suite 'DocumentLineValueTests' passed at 2026-06-06 23:59:50.149.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'LineGeometryCursorTests' started at 2026-06-06 23:59:50.149.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' passed (0.000 seconds).
Test Suite 'LineGeometryCursorTests' passed at 2026-06-06 23:59:50.149.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportInputValueTests' started at 2026-06-06 23:59:50.149.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' passed (0.000 seconds).
Test Suite 'ViewportInputValueTests' passed at 2026-06-06 23:59:50.149.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-06 23:59:50.149.
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
Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-06 23:59:50.152.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
Test Suite 'ViewportRangeTests' started at 2026-06-06 23:59:50.152.
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
Test Suite 'ViewportRangeTests' passed at 2026-06-06 23:59:50.153.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ViewportValidationTests' started at 2026-06-06 23:59:50.153.
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
Test Suite 'ViewportValidationTests' passed at 2026-06-06 23:59:50.153.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-06 23:59:50.153.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.005 (0.007) seconds
Test Suite 'All tests' passed at 2026-06-06 23:59:50.154.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.005 (0.007) seconds
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
Build complete! (0.09s)
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
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1306 p99_ns=1404 failures=0 checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5342 p99_ns=5550 failures=0 checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17364 p99_ns=18193 failures=0 checksum=18852477646272000
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
mode=range_only scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=7 p99_ns=8 failures=0 checksum=5114982400
mode=range_only scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=7 p99_ns=8 failures=0 checksum=511488422400
mode=range_only scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=7 p99_ns=8 failures=0 checksum=5114881152000
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
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1322 p99_ns=1387 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5339 p99_ns=5530 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17473 p99_ns=18242 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
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
Build of product 'ViewportBenchmarks' complete! (0.07s)
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5593 p99_ns=5776 failures=0 checksum=756321289736960
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

### Invalid Memory-Shape Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-shape --gate
```

Result: expected non-zero exit with `error=--memory-shape cannot be combined with --gate`.

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--memory-shape cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --help                Print this help.
```

### Additional Invalid CLI Checks

Commands:

```text
swift run -c release ViewportBenchmarks -- --range-only --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --range-only --realistic-provider
swift run -c release ViewportBenchmarks -- --range-only --memory-shape
swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape
swift run -c release ViewportBenchmarks -- --unknown
```

Result: each command exited non-zero with the existing error text.

```text
swift run -c release ViewportBenchmarks -- --range-only --gate

[0/1] Planning build
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.09s)
error=--range-only cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --help                Print this help.

swift run -c release ViewportBenchmarks -- --realistic-provider --gate

Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--realistic-provider cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --help                Print this help.

swift run -c release ViewportBenchmarks -- --range-only --realistic-provider

Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--realistic-provider cannot be combined with --range-only
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --help                Print this help.

swift run -c release ViewportBenchmarks -- --range-only --memory-shape

Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--range-only cannot be combined with --memory-shape
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --help                Print this help.

swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape

Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--realistic-provider cannot be combined with --memory-shape
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --help                Print this help.

swift run -c release ViewportBenchmarks -- --unknown

Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=unknown argument --unknown
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --help                Print this help.
```

### Workflow Scan

Command:

```text
rg -n "Run synthetic benchmark gate|Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml
```

Result: workflow status name and benchmark commands are unchanged.

```text
18:    name: Host tests and benchmark gate
35:      - name: Run synthetic benchmark gate
38:      - name: Run memory shape diagnostic
39:        run: swift run -c release ViewportBenchmarks -- --memory-shape
```

### Non-Goal Diff Check

Command:

```text
git diff -- Sources/TextEngineCore Tests Package.swift .github/workflows/swift-ci.yml
```

Result: no output.

### Source File Size Check

Command:

```text
wc -l Sources/ViewportBenchmarks/*.swift
```

Result: `main.swift` is reduced to a small entrypoint and benchmark concerns are split across focused files.

```text
      52 Sources/ViewportBenchmarks/BenchmarkModels.swift
      95 Sources/ViewportBenchmarks/BenchmarkOptions.swift
      26 Sources/ViewportBenchmarks/BenchmarkProgram.swift
      98 Sources/ViewportBenchmarks/BenchmarkSupport.swift
     360 Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
     193 Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
     171 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
      10 Sources/ViewportBenchmarks/main.swift
    1005 total
```

## Conclusion

Slice 8 preserves the benchmark executable's behavior while resolving the Slice 7 maintainability finding that `main.swift` crossed 1,000 lines.
