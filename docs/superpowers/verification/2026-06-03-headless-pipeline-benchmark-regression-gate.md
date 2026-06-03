# Headless Pipeline Benchmark And Regression Gate Verification

Date: 2026-06-03

Swift: Apple Swift version 6.2.1 (swift-6.2.1-RELEASE)

## Commands

- `swift test`: pass
- `swift build -c release`: pass
- `swift run -c release ViewportBenchmarks`: pass
- `swift run -c release ViewportBenchmarks -- --range-only`: pass
- `swift run -c release ViewportBenchmarks -- --gate`: pass
- `swift run -c release ViewportBenchmarks -- --help`: pass
- `swift run -c release ViewportBenchmarks -- --range-only --gate`: expected non-zero exit
- `swift run -c release ViewportBenchmarks -- --json`: expected non-zero exit
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`: pass
- `xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule`: pass
- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule`: pass

## Pipeline Benchmark Output

`swift run -c release ViewportBenchmarks`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1276 p99_ns=1579 failures=0 checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5049 p99_ns=5224 failures=0 checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16548 p99_ns=17594 failures=0 checksum=18852477646272000
```

## Range-Only Benchmark Output

`swift run -c release ViewportBenchmarks -- --range-only`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.07s)
mode=range_only scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=9 p99_ns=10 failures=0 checksum=5114982400
mode=range_only scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=9 failures=0 checksum=511488422400
mode=range_only scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=9 p99_ns=9 failures=0 checksum=5114881152000
```

## Gate Output

`swift run -c release ViewportBenchmarks -- --gate`:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1276 p99_ns=1343 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5135 p99_ns=5292 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16806 p99_ns=17549 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

## Invalid CLI Output

`swift run -c release ViewportBenchmarks -- --help`:

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.08s)
Usage: ViewportBenchmarks [--range-only] [--gate] [--help]

Options:
  --range-only   Run only viewport range recompute benchmark.
  --gate         Enforce pipeline p95/p99 budgets and exit non-zero on failure.
  --help         Print this help.
```

`swift run -c release ViewportBenchmarks -- --range-only --gate` exited 1:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=--range-only cannot be combined with --gate
Usage: ViewportBenchmarks [--range-only] [--gate] [--help]

Options:
  --range-only   Run only viewport range recompute benchmark.
  --gate         Enforce pipeline p95/p99 budgets and exit non-zero on failure.
  --help         Print this help.
```

`swift run -c release ViewportBenchmarks -- --json` exited 1:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
error=unknown argument --json
Usage: ViewportBenchmarks [--range-only] [--gate] [--help]

Options:
  --range-only   Run only viewport range recompute benchmark.
  --gate         Enforce pipeline p95/p99 budgets and exit non-zero on failure.
  --help         Print this help.
```

## Target Verification

- Host SwiftPM build and tests: verified.
- Pipeline benchmark gate: verified by `--gate` returning `0` with all scenarios under budget.
- Invalid benchmark CLI behavior: verified by non-zero exits for invalid combinations and unknown flags.
- iOS device source compatibility: verified by direct `xcrun swiftc` module compile.
- iOS simulator source compatibility: verified by direct `xcrun swiftc` module compile.
- WASM source compatibility: verified for the `TextEngineCore` target.
- Embedded WASM source compatibility: verified for the `TextEngineCore` target.

Host `swift build -c release` output:

```text
Building for production...
[0/3] Write sources
[1/3] Write swift-version--2EFC8FE404102F05.txt
[3/4] Compiling ViewportBenchmarks main.swift
[3/5] Write Objects.LinkFileList
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswiftCore.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswift_Builtin_float.dylib' which was built for newer version 13.0
ld: warning: building for macOS-11.0, but linking with dylib '/usr/lib/swift/libswift_Concurrency.dylib' which was built for newer version 13.0
[4/5] Linking ViewportBenchmarks
Build complete! (0.78s)
```

Host `swift test` summary:

```text
Build complete! (0.74s)
Test Suite 'All tests' passed at 2026-06-04 00:45:36.350.
	 Executed 39 tests, with 0 failures (0 unexpected) in 0.007 (0.009) seconds
◇ Test run started.
↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
↳ Target Platform: arm64-apple-macosx
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

WASM target output:

```text
[0/1] Planning build
Building for debugging...
[0/1] Write swift-version--2EFC8FE404102F05.txt
[2/2] Emitting module TextEngineCore
Build of target: 'TextEngineCore' complete! (0.21s)
```

Embedded WASM target output:

```text
[0/1] Planning build
Building for debugging...
[0/1] Write swift-version--2EFC8FE404102F05.txt
[2/3] Emitting module TextEngineCore
[3/3] Compiling TextEngineCore DocumentLineCursor.swift
Build of target: 'TextEngineCore' complete! (0.30s)
```

Both iOS direct `xcrun swiftc` module compile commands produced no stdout or stderr and exited 0.

## Benchmark Scope

The default benchmark now measures the fixed-height headless pipeline:

1. `ViewportVirtualizer.compute(_:)`
2. `ViewportVirtualizer.geometry(for:lineHeight:)` cursor traversal
3. `ViewportVirtualizer.lines(for:in:)` cursor traversal over a synthetic source

The synthetic source returns lightweight integer payloads and does not allocate document-sized storage. `ViewportBenchmarks` remains outside embedded WASM verification because it uses `ContinuousClock` and `Darwin.exit`; the cross-target gate applies to `TextEngineCore`.
