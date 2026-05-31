# Headless Fixed-Height Viewport Virtualization Verification

Date: 2026-05-31

## Commands

- `swift test`: pass
- `swift build -c release`: pass
- `swift run -c release ViewportBenchmarks`: pass

## Benchmark Output

This is the exact stdout from the verification run recorded for this commit; latency values are sample-specific.

```text
scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=10 p99_ns=10 checksum=5114982400
scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=9 p99_ns=11 checksum=511488422400
scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=10 checksum=5114881152000
```

## Swift Embedded-Sensitive Choices

- `TextEngineCore` public API uses `Int`, `Double`, public structs, and enums.
- `TextEngineCore` does not import Foundation.
- Geometry generation uses `LineGeometryCursor` instead of `Sequence` conformance.
- `ContinuousClock` is used only in the benchmark executable target.

## Target Verification

- Host SwiftPM build: verified by `swift test` and `swift build -c release`.
- iOS source compatibility: blocked until an iOS SDK build command is configured for this repository.
- WASM source compatibility: blocked until a Swift WASM SDK or `wasm32-unknown-wasi` toolchain is configured for this repository.
