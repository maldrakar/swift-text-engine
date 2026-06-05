# CI Benchmark Gate Wiring Verification

Date: 2026-06-05

## Scope

Slice 5 wires the existing synthetic benchmark gate into GitHub Actions.

Created file:

```text
.github/workflows/swift-ci.yml
```

The workflow runs on `pull_request` and `push` to `main`.

The workflow job uses `runs-on: macos-latest` and `timeout-minutes: 20`.

Known GitHub remote:

```text
git@github.com:arthurbanshchikov/swift-text-engine.git
```

## Commands

- `rg --files -g '.github/**' -g '.gitlab-ci.yml' -g 'bitbucket-pipelines.yml' -g 'Jenkinsfile' -g '.circleci/**'`: no committed CI configuration before this slice
- `git remote -v`: no configured local remote before this slice in the current clone
- `rg --files --hidden -g '.github/**'`: pass
- `rg -n "pull_request|push:|branches:|main" .github/workflows/swift-ci.yml`: pass
- `rg -n "runs-on: macos-latest|timeout-minutes: 20" .github/workflows/swift-ci.yml`: pass
- `rg -n "swift --version|xcodebuild -version|uname -a|swift test|swift run -c release ViewportBenchmarks -- --gate" .github/workflows/swift-ci.yml`: pass
- `rg -n "realistic-provider|swift build --swift-sdk|xcrun swiftc" .github/workflows/swift-ci.yml`: no matches
- `swift test`: pass
- `swift run -c release ViewportBenchmarks -- --gate`: pass

Local verification used `--hidden` for `.github` workflow discovery because ripgrep 15.1.0 does not traverse hidden directories for `--files` by default.

## Workflow Commands

```text
swift --version
xcodebuild -version
uname -a
swift test
swift run -c release ViewportBenchmarks -- --gate
```

## Host Test Output

```text
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version-58A378E29CF047B.txt
Build complete! (0.11s)
Test Suite 'All tests' started at 2026-06-05 19:06:18.307.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-06-05 19:06:18.307.
Test Suite 'DocumentLineCursorTests' started at 2026-06-05 19:06:18.307.
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
Test Suite 'DocumentLineCursorTests' passed at 2026-06-05 19:06:18.309.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'DocumentLineValueTests' started at 2026-06-05 19:06:18.309.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineCursorElementEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineFetchEquatableWhenPayloadIsEquatable]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' started.
Test Case '-[TextEngineCoreTests.DocumentLineValueTests testDocumentLineStoresIndexAndContent]' passed (0.000 seconds).
Test Suite 'DocumentLineValueTests' passed at 2026-06-05 19:06:18.309.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'LineGeometryCursorTests' started at 2026-06-05 19:06:18.309.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorForEmptyRangeYieldsNoGeometry]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' started.
Test Case '-[TextEngineCoreTests.LineGeometryCursorTests testCursorYieldsOnlyBufferedLines]' passed (0.000 seconds).
Test Suite 'LineGeometryCursorTests' passed at 2026-06-05 19:06:18.309.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportInputValueTests' started at 2026-06-05 19:06:18.309.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testLineGeometryStoresIndexAndDimensions]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testViewportInputStoresAllFields]' passed (0.000 seconds).
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' started.
Test Case '-[TextEngineCoreTests.ViewportInputValueTests testVirtualRangeReportsEmpty]' passed (0.000 seconds).
Test Suite 'ViewportInputValueTests' passed at 2026-06-05 19:06:18.309.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'ViewportOverscanInvariantTests' started at 2026-06-05 19:06:18.309.
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
Test Suite 'ViewportOverscanInvariantTests' passed at 2026-06-05 19:06:18.312.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'ViewportRangeTests' started at 2026-06-05 19:06:18.312.
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
Test Suite 'ViewportRangeTests' passed at 2026-06-05 19:06:18.313.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'ViewportValidationTests' started at 2026-06-05 19:06:18.313.
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
Test Suite 'ViewportValidationTests' passed at 2026-06-05 19:06:18.314.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-05 19:06:18.314.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.005 (0.006) seconds
Test Suite 'All tests' passed at 2026-06-05 19:06:18.314.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.005 (0.007) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

## Synthetic Benchmark Gate Output

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.09s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1236 p99_ns=1303 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4965 p99_ns=5178 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16954 p99_ns=17858 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

## Non-Goals Confirmed

This slice does not add realistic-provider budgets, run `--realistic-provider` in CI, add memory profiling, add baseline comparison, add cross-target CI, change benchmark budgets, add storage adapters, or start variable-height layout work.

This slice does not configure GitHub branch protection settings.

## Remote Runner Follow-Up

Local verification proves the workflow commands pass on the current host. The first GitHub Actions run after pushing to the approved remote should be checked before treating CI as fully operational. Hosted-runner toolchain and performance variance should be follow-up and review-backed adjustment.
