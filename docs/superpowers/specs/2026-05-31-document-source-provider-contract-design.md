# Document Source Provider Contract Design

Date: 2026-05-31

## Status

Approved design, written for user review.

## Source Context

This design is Slice 2 of the headless Swift text engine described in `docs/initial-project-brief.md`.

Slice 1 delivered fixed-height viewport virtualization and intentionally kept document storage outside the core. The Slice 1 post-slice review identified the next product risk as the missing document/source provider boundary, with compile verification required for any new public API shape.

This slice preserves the main Slice 1 invariant: viewport range computation must not fetch document content, retain provider state, or allocate by total document size.

## Scope

Build a small document/source provider contract and an integration boundary that lets consumers fetch content for the already-computed buffered viewport range.

This slice proves that document storage can remain outside `TextEngineCore` while the core still offers a lightweight bridge from `VirtualRange` line indexes to caller-owned line content.

## Goals

- Define a public provider/source contract in `TextEngineCore`.
- Keep the contract generic over the caller's line payload type.
- Avoid Foundation-specific public API.
- Avoid throwing provider APIs in the core contract.
- Keep `ViewportVirtualizer.compute(_:)` independent from provider access.
- Fetch only `VirtualRange.bufferStart..<bufferEndExclusive`.
- Expose missing provider lines explicitly.
- Provide focused tests using test-only in-memory sources.
- Add an explicit compile verification gate for host, iOS, WASM, and embedded WASM library builds.

## Non-Goals

- File-backed storage.
- Rope or piece-table storage.
- Async loading or prefetch.
- Caching visible content.
- Variable-height layout.
- Text shaping.
- Rich text.
- UI adapters.
- Provider performance benchmark gates.
- Making benchmark executables compile under embedded WASM.

## Architecture

Slice 2 adds a provider boundary beside, not inside, the viewport calculation path.

`ViewportVirtualizer.compute(_:)` continues to accept `ViewportInput` and return `ViewportComputation`. It must not know about document storage or call a provider.

Provider integration is a second step. After a consumer has a `VirtualRange`, the consumer can create a line cursor that walks the range's buffered indexes and requests content from a caller-owned source.

The core owns no text storage. It owns only lightweight protocol, enum, value type, and cursor definitions.

## Public Components

### DocumentLineSource

`DocumentLineSource` is the provider contract.

Expected shape:

```swift
public protocol DocumentLineSource {
    associatedtype Line

    var lineCount: Int { get }

    func line(at index: Int) -> DocumentLineFetch<Line>
}
```

`Line` is generic so the core does not force `String` as the document representation. A caller may use `String`, UTF-8 slices, editor-buffer handles, rich text fragments, or another payload in later slices.

### DocumentLineFetch

`DocumentLineFetch` is the provider fetch result.

Expected shape:

```swift
public enum DocumentLineFetch<Line> {
    case found(Line)
    case missing
}
```

The core contract is non-throwing. Missing content is represented explicitly without importing Foundation or defining storage-specific errors.

### DocumentLine

`DocumentLine` pairs a logical line index with provider content.

Expected shape:

```swift
public struct DocumentLine<Line> {
    public let index: Int
    public let content: Line
}
```

### DocumentLineCursorElement

The cursor should return one element per requested logical line index.

Expected shape:

```swift
public enum DocumentLineCursorElement<Line> {
    case line(DocumentLine<Line>)
    case missing(index: Int)
}
```

This makes provider inconsistencies visible to callers. A provider whose `lineCount` is smaller than the supplied buffered range should produce `.missing(index:)` for indexes it cannot serve.

### DocumentLineCursor

`DocumentLineCursor<Source>` walks `VirtualRange.bufferStart..<bufferEndExclusive` and fetches from a `DocumentLineSource`.

Expected behavior:

- It yields no elements for an empty range.
- It requests indexes in ascending order.
- It yields `.line(DocumentLine(index:content:))` when the provider returns `.found`.
- It yields `.missing(index:)` when the provider returns `.missing`.
- It does not materialize an array of all buffered lines.
- It does not clamp the supplied `VirtualRange`.
- It does not retain document storage beyond the source value/reference supplied by the caller.

### ViewportVirtualizer Integration Helper

Provider integration should be exposed separately from range computation:

```swift
extension ViewportVirtualizer {
    public static func lines<Source: DocumentLineSource>(
        for range: VirtualRange,
        in source: Source
    ) -> DocumentLineCursor<Source>
}
```

The helper uses the buffered range, not just the visible range, because Slice 1 defines geometry over the buffered viewport. This preserves strict virtualization while giving renderers access to overscan content.

## Data Flow

1. Consumer owns document storage and scroll state.
2. Consumer reads `source.lineCount`.
3. Consumer builds `ViewportInput` using the source line count, viewport geometry, and overscan settings.
4. Consumer calls `ViewportVirtualizer.compute(_:)`.
5. If range computation succeeds, consumer calls `ViewportVirtualizer.lines(for:in:)`.
6. Consumer advances the returned cursor.
7. The cursor fetches only the buffered logical indexes from the source.
8. Consumer pairs those line payloads with geometry from `ViewportVirtualizer.geometry(for:lineHeight:)` or its own renderer-specific flow.

No provider call happens in steps 3 or 4.

## Error Handling And Edge Cases

Viewport validation errors remain represented by `ViewportComputation.failure`.

Provider misses are represented separately by cursor elements because they occur after a valid range is computed.

Expected behavior:

- `range.isEmpty`: line cursor yields no elements and performs no fetches.
- Provider returns `.missing`: line cursor yields `.missing(index:)`.
- Source `lineCount` does not match the range used by the caller: cursor does not hide the mismatch by clamping; it reports provider misses as they occur.
- Negative or otherwise malformed `VirtualRange` values are outside normal construction flow. Slice 2 does not add defensive normalization to provider integration; valid ranges are produced by Slice 1 APIs and tested there.

## Testing

Tests should use in-test provider implementations, not production storage adapters.

Functional tests should cover:

- `DocumentLine` value storage.
- `DocumentLineFetch` and `DocumentLineCursorElement` equality if these types conform to `Equatable`.
- An array-backed test source returns payload by index.
- Cursor yields exactly `bufferStart..<bufferEndExclusive`.
- Cursor yields indexes in ascending order.
- Empty ranges do not fetch.
- Missing indexes yield `.missing(index:)`.
- A counting source proves `ViewportVirtualizer.compute(_:)` performs zero provider fetches.
- Advancing the line cursor performs one provider fetch per requested buffered index.
- Existing Slice 1 range and geometry tests remain unchanged.

Generated or loop-based tests should include large `lineCount` values to confirm the cursor's work is proportional to buffered range size, not document size.

## Compile Verification Gate

Slice 2 introduces protocol, generic enum, generic struct, and cursor public APIs. These are Swift Embedded-sensitive enough to require explicit compile verification.

The implementation is complete only when the following pass or the missing toolchain is recorded as a blocker:

```text
swift test
swift build -c release
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
xcrun swiftc -target arm64-apple-ios17.0 -sdk <iphoneos-sdk> -parse-as-library -emit-module Sources/TextEngineCore/*.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk <iphonesimulator-sdk> -parse-as-library -emit-module Sources/TextEngineCore/*.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

The gate targets the `TextEngineCore` library target. `ViewportBenchmarks` is excluded because it uses `ContinuousClock`, and Slice 1 already records benchmark timing as executable-specific rather than core API.

Current local environment discovery on 2026-05-31:

- Swift 6.2.1 host toolchain is available.
- `swift-6.2.1-RELEASE_wasm` SDK is available.
- `swift-6.2.1-RELEASE_wasm-embedded` SDK is available.
- iPhoneOS and iPhoneSimulator SDKs are available through Xcode 26.3.
- Slice 1 `TextEngineCore` compiles under host, iOS device, iOS simulator, WASM, and embedded WASM library-target checks.

## Performance And Memory Expectations

Provider integration must stay outside the hot viewport recomputation path.

Expected complexity:

- `ViewportVirtualizer.compute(_:)`: unchanged from Slice 1.
- Creating a line cursor: O(1).
- Advancing a line cursor: O(1) per buffered index, plus provider-specific fetch cost.
- Cursor-owned memory: O(1), excluding source storage owned by the caller.

This slice does not require a provider benchmark. A provider-boundary benchmark may be added later if real adapters introduce measurable overhead risk.

## Acceptance Criteria

Slice 2 is complete when:

- `TextEngineCore` exposes a generic `DocumentLineSource` contract.
- Provider fetch results are non-throwing and Foundation-free.
- A public cursor walks only `VirtualRange.bufferStart..<bufferEndExclusive`.
- Missing provider lines are explicit in cursor output.
- `ViewportVirtualizer.compute(_:)` remains provider-free.
- Tests prove empty range, buffered-range, missing-line, ordering, and zero-fetch-during-compute behavior.
- The library compile verification gate passes for host, iOS, WASM, and embedded WASM, or any unavailable target is recorded as a blocker.
- No production storage adapter is added to the core module.

## Open Decisions For Later Slices

- Whether to add visible-only or caller-selected range scopes.
- Whether to add async or prefetch APIs.
- Whether real adapters should live in separate targets.
- How variable-height layout will map provider indexes to measured layout records.
- Whether line payloads should eventually carry stable document revision identifiers.
- How benchmark regression gates should treat provider-boundary overhead.
