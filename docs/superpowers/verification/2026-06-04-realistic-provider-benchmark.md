# Realistic Provider Benchmark Verification

Date: 2026-06-04

Swift: Apple Swift version 6.2.1 (swift-6.2.1-RELEASE)

## Commands

- `swift test`: pass
- `swift build -c release`: pass
- `swift run -c release ViewportBenchmarks`: pass
- `swift run -c release ViewportBenchmarks -- --range-only`: pass
- `swift run -c release ViewportBenchmarks -- --gate`: pass
- `swift run -c release ViewportBenchmarks -- --realistic-provider`: pass
- `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`: expected non-zero exit
- `swift run -c release ViewportBenchmarks -- --range-only --gate`: expected non-zero exit
- `swift run -c release ViewportBenchmarks -- --json`: expected non-zero exit
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`: pass
- `xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule`: pass
- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule`: pass

## Default Pipeline Benchmark Output

`swift run -c release ViewportBenchmarks`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1221 p99_ns=1282 failures=0 checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4894 p99_ns=5048 failures=0 checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16187 p99_ns=16908 failures=0 checksum=18852477646272000
```

## Range-Only Benchmark Output

`swift run -c release ViewportBenchmarks -- --range-only`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=range_only scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=10 failures=0 checksum=5114982400
mode=range_only scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=7 p99_ns=9 failures=0 checksum=511488422400
mode=range_only scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=9 failures=0 checksum=5114881152000
```

## Gate Output

`swift run -c release ViewportBenchmarks -- --gate`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1249 p99_ns=1318 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4973 p99_ns=5161 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16238 p99_ns=16881 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

## Realistic Provider Benchmark Output

`swift run -c release ViewportBenchmarks -- --realistic-provider`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5240 p99_ns=5405 failures=0 checksum=756321289736960
```

## Invalid CLI Output

`swift run -c release ViewportBenchmarks -- --realistic-provider --gate` exited 1:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--realistic-provider cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --help                Print this help.
```

`swift run -c release ViewportBenchmarks -- --range-only --gate` exited 1:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--range-only cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --help                Print this help.
```

`swift run -c release ViewportBenchmarks -- --json` exited 1:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=unknown argument --json
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--help]

Options:
  --range-only          Run only viewport range recompute benchmark.
  --gate                Enforce synthetic pipeline p95/p99 budgets and exit non-zero on failure.
  --realistic-provider  Run large-text provider benchmark without gate enforcement.
  --help                Print this help.
```

## Target Verification

- Host SwiftPM build and tests: verified.
- Existing synthetic pipeline benchmark gate: verified by `--gate` returning `0` with all scenarios under budget.
- Realistic provider benchmark: verified by `--realistic-provider` returning `0`, reporting `line_count=100000`, `document_bytes=11200000`, `line_bytes=112`, and `failures=0`.
- Invalid benchmark CLI behavior: verified by non-zero exits for invalid combinations and unknown flags.
- iOS device source compatibility: verified by direct `xcrun swiftc` module compile.
- iOS simulator source compatibility: verified by direct `xcrun swiftc` module compile.
- WASM source compatibility: verified for the `TextEngineCore` target.
- Embedded WASM source compatibility: verified for the `TextEngineCore` target.

## Benchmark Scope

The realistic provider benchmark builds a deterministic 100,000-line, 11,200,000-byte UTF-8 fixture before timed samples begin. Each timed operation computes the fixed-height viewport range, traverses buffered geometry, and traverses buffered provider lines through `DocumentLineCursor`.

The provider source stored in `DocumentLineCursor` is a lightweight handle containing one reference to `RealisticDocumentStorage`; the large byte payload remains outside `TextEngineCore`.

No realistic-provider p95/p99 budget is enforced in this slice. The recorded output is a baseline for later CI calibration or memory/allocation work.
