# Document Source Provider Contract Verification

Date: 2026-05-31

Swift: `/Users/aabanschikov/.swiftly/bin/swift`, Apple Swift version 6.2.1

## Commands

- `swift test`: pass
- `swift build -c release`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore`: pass
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore`: pass
- `xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule`: pass
- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule`: pass

## Swift Embedded-Sensitive Choices

- `DocumentLineSource` uses an associated type and a non-throwing method.
- `DocumentLineFetch`, `DocumentLine`, and `DocumentLineCursorElement` are generic public types.
- `DocumentLineCursor` is generic over `DocumentLineSource` and uses a mutating `next()` method rather than `Sequence` conformance.
- Conditional `Equatable` conformances are used only when the generic line payload is `Equatable`.
- The public API does not import Foundation.

## Target Verification

- Host SwiftPM build and tests: verified.
- iOS device source compatibility: verified by direct `xcrun swiftc` module compile.
- iOS simulator source compatibility: verified by direct `xcrun swiftc` module compile.
- WASM source compatibility: verified for the `TextEngineCore` target.
- Embedded WASM source compatibility: verified for the `TextEngineCore` target.

## Benchmark Scope

No provider benchmark was required for Slice 2.

`ViewportBenchmarks` remains outside embedded WASM verification because it uses `ContinuousClock`. The Slice 2 compile gate targets only the `TextEngineCore` library target.
