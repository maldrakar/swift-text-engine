# Core-Owned Memory Shape Verification

Date: 2026-06-06

Swift: Apple Swift version 6.2.1 (swift-6.2.1-RELEASE)

## Commands

- `swift test`: pass
- `swift build -c release`: pass
- `swift run -c release ViewportBenchmarks`: pass
- `swift run -c release ViewportBenchmarks -- --range-only`: pass
- `swift run -c release ViewportBenchmarks -- --gate`: pass
- `swift run -c release ViewportBenchmarks -- --realistic-provider`: pass
- `swift run -c release ViewportBenchmarks -- --memory-shape`: pass
- `swift run -c release ViewportBenchmarks -- --memory-shape --gate`: expected non-zero exit
- `rg -n "Run synthetic benchmark gate|Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`: pass
- `xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule`: pass
- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule`: pass

## Host Test Output

`swift test`:

```text
[0/1] Planning build
Building for debugging...
[0/5] Write sources
[1/5] Write swift-version--2EFC8FE404102F05.txt
[3/6] Emitting module ViewportBenchmarks
[4/6] Compiling ViewportBenchmarks main.swift
[4/7] Write Objects.LinkFileList
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswiftCore.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswiftSwiftOnoneSupport.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswift_Builtin_float.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswift_Concurrency.dylib' which was built for newer version 13.0
[5/7] Linking ViewportBenchmarks
[6/7] Applying ViewportBenchmarks
Build complete! (1.49s)
Test Suite 'All tests' started at 2026-06-06 15:40:12.080.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-06-06 15:40:12.081.
Test Suite 'DocumentLineCursorTests' started at 2026-06-06 15:40:12.081.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorFetchesOneLinePerBufferedIndex]' started.
Test Case '-[TextEngineCoreTests.DocumentLineCursorTests testCursorFetchesOneLinePerBufferedIndex]' passed (0.002 seconds).
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
Test Suite 'DocumentLineCursorTests' passed at 2026-06-06 15:40:12.084.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.003 (0.003) seconds
Test Suite 'DocumentLineValueTests' started at 2026-06-06 15:40:12.084.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' passed (0.000 seconds).
Test Suite 'DocumentLineValueTests' passed at 2026-06-06 15:40:12.085.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'LineGeometryCursorTests' started at 2026-06-06 15:40:12.085.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' passed (0.000 seconds).
Test Suite 'LineGeometryCursorTests' passed at 2026-06-06 15:40:12.085.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportInputValueTests' started at 2026-06-06 15:40:12.085.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' passed (0.000 seconds).
Test Suite 'ViewportInputValueTests' passed at 2026-06-06 15:40:12.085.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-06 15:40:12.085.
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
Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-06 15:40:12.088.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
Test Suite 'ViewportRangeTests' started at 2026-06-06 15:40:12.088.
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
Test Suite 'ViewportRangeTests' passed at 2026-06-06 15:40:12.089.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ViewportValidationTests' started at 2026-06-06 15:40:12.089.
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
Test Suite 'ViewportValidationTests' passed at 2026-06-06 15:40:12.089.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-06 15:40:12.089.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.007 (0.008) seconds
Test Suite 'All tests' passed at 2026-06-06 15:40:12.089.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.007 (0.009) seconds
◇ Test run started.
↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
↳ Target Platform: arm64-apple-macosx
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

## Release Build Output

`swift build -c release`:

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
```

## Default Pipeline Benchmark Output

`swift run -c release ViewportBenchmarks`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1273 p99_ns=1356 failures=0 checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5187 p99_ns=5396 failures=0 checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17053 p99_ns=17864 failures=0 checksum=18852477646272000
```

## Range-Only Benchmark Output

`swift run -c release ViewportBenchmarks -- --range-only`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=range_only scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=9 failures=0 checksum=5114982400
mode=range_only scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=7 p99_ns=9 failures=0 checksum=511488422400
mode=range_only scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=7 p99_ns=9 failures=0 checksum=5114881152000
```

## Gate Output

`swift run -c release ViewportBenchmarks -- --gate`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1272 p99_ns=1329 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5169 p99_ns=5327 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16918 p99_ns=17589 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

## Realistic Provider Benchmark Output

`swift run -c release ViewportBenchmarks -- --realistic-provider`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5399 p99_ns=5577 failures=0 checksum=756321289736960
```

## Memory Shape Diagnostic Output

`swift run -c release ViewportBenchmarks -- --memory-shape`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
```

## Invalid CLI Output

`swift run -c release ViewportBenchmarks -- --memory-shape --gate` exited non-zero as expected:

```text
[0/1] Planning build
Building for production...
[0/3] Write swift-version-58A378E29CF047B.txt
[2/4] Compiling TextEngineCore DocumentLineCursor.swift
[3/5] Compiling ViewportBenchmarks main.swift
[3/5] Write Objects.LinkFileList
[4/5] Linking ViewportBenchmarks
Build of product 'ViewportBenchmarks' complete! (1.70s)
error=--memory-shape cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--memory-shape] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --memory-shape        Run deterministic core-owned memory-shape diagnostics.
  --help                Print this help.
```

## Workflow Scan

`rg -n "Run synthetic benchmark gate|Run memory shape diagnostic|--memory-shape|Host tests and benchmark gate" .github/workflows/swift-ci.yml`:

```text
18:    name: Host tests and benchmark gate
35:      - name: Run synthetic benchmark gate
38:      - name: Run memory shape diagnostic
39:        run: swift run -c release ViewportBenchmarks -- --memory-shape
```

## Target Verification Output

`swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`:

```text
[0/1] Planning build
Building for debugging...
[0/1] Write swift-version--2EFC8FE404102F05.txt
[2/2] Emitting module TextEngineCore
Build of target: 'TextEngineCore' complete! (0.21s)
```

`swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`:

```text
[0/1] Planning build
Building for debugging...
[0/1] Write swift-version--2EFC8FE404102F05.txt
[2/3] Compiling TextEngineCore DocumentLineCursor.swift
[3/3] Emitting module TextEngineCore
Build of target: 'TextEngineCore' complete! (0.29s)
```

`xcrun swiftc` iOS device module compile:

```text

```

The iOS device compile emitted no stdout or stderr and exited successfully.

`xcrun swiftc` iOS simulator module compile:

```text

```

The iOS simulator compile emitted no stdout or stderr and exited successfully.

## Memory Shape Interpretation

The memory-shape diagnostic reports deterministic model estimates, not RSS,
heap, or allocation profiler output.

The synthetic 100,000-line and 1,000,000-line scenarios use the same visible
and overscan shape. Their `core_owned_bytes` values match, which verifies
within the deterministic model that the current fixed-height core-owned scalar
and cursor state does not grow with total line count for that shape.

The realistic-provider scenario reports `document_bytes=11200000` and
`provider_owned_bytes=11200000`. That payload is caller/provider-owned
benchmark storage and is not classified as core-owned memory.

The diagnostic reports `invariant=pass` for all scenarios. It is now run in
`.github/workflows/swift-ci.yml` after the synthetic benchmark gate.

## Scope Boundaries

Slice 7 does not enforce RSS, heap, or allocation budgets. It does not add
realistic-provider latency budgets, branch protection, GitHub rulesets,
variable-height layout, production storage adapters, or public
TextEngineCore API.
