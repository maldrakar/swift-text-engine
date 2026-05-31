# Slice 2 Post-Slice Review

Date: 2026-05-31

## Scope Reviewed

This review covers Slice 2: document source provider contract.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/specs/2026-05-31-document-source-provider-contract-design.md`
- `docs/superpowers/plans/2026-05-31-document-source-provider-contract.md`
- `Sources/TextEngineCore/DocumentLineTypes.swift`
- `Sources/TextEngineCore/DocumentLineCursor.swift`
- `Sources/TextEngineCore/ViewportVirtualizer.swift`
- `Tests/TextEngineCoreTests/DocumentLineValueTests.swift`
- `Tests/TextEngineCoreTests/DocumentLineCursorTests.swift`
- `Sources/ViewportBenchmarks/main.swift`
- `docs/superpowers/verification/2026-05-31-document-source-provider-contract.md`
- local git commit history

No separate PR notes were found in the repository.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core that computes geometry and virtualizes the visible area while staying independent from UI frameworks.

Slice 2 narrows that product goal to the document/source provider boundary. This was the right follow-up to Slice 1 because fixed-height viewport virtualization can now be paired with caller-owned document storage without moving storage, file IO, or UI concerns into `TextEngineCore`.

Slice 2 directly addresses these brief requirements:

- No Foundation dependency in the core module.
- Public API that avoids Foundation-specific types.
- Document storage can live outside the core through a provider/source abstraction.
- Strict virtualization: provider access is limited to the buffered viewport range.
- `ViewportVirtualizer.compute(_:)` remains independent from document content fetching.
- Core-owned provider cursor memory does not grow with total document size.
- The core compiles without source changes for host, iOS, WASM, and embedded WASM library-target checks.

Slice 2 does not yet prove these brief requirements:

- Stable scroll performance for a full end-to-end render pipeline on 100k+ lines or >10 MB documents.
- Merge-blocking benchmark regression gates.
- Real storage adapters.
- Variable-height layout, text shaping, rasterization, or UI-framework integration.

Those remain out of scope for this slice.

## Delivered Design

The Slice 2 design added a provider boundary beside, not inside, the viewport calculation path.

The implemented public API consists of:

- `DocumentLineSource`
- `DocumentLineFetch`
- `DocumentLine`
- `DocumentLineCursorElement`
- `DocumentLineCursor`
- `ViewportVirtualizer.lines(for:in:)`

The core data flow is now:

1. Consumer owns document storage and scroll state.
2. Consumer reads `source.lineCount`.
3. Consumer builds `ViewportInput`.
4. Consumer calls `ViewportVirtualizer.compute(_:)`.
5. Consumer passes the returned `VirtualRange` to `ViewportVirtualizer.lines(for:in:)`.
6. Consumer advances the cursor to fetch only `bufferStart..<bufferEndExclusive`.
7. Consumer combines line payloads with geometry from `ViewportVirtualizer.geometry(for:lineHeight:)` or renderer-specific layout.

No provider call happens during range computation.

## Implementation Assessment

The implementation is appropriately small and closely matches the approved design.

Strengths:

- The provider contract is generic over the caller's line payload type.
- Provider fetches are non-throwing and represented by a lightweight enum.
- Missing provider lines are explicit through `.missing(index:)`.
- `ViewportVirtualizer.compute(_:)` remains provider-free.
- The cursor walks only `VirtualRange.bufferStart..<bufferEndExclusive`.
- The cursor does not clamp the supplied range, preserving caller/provider mismatches for consumers to observe.
- The cursor does not materialize a buffered-lines array.
- The core still imports no Foundation and adds no third-party dependencies.

Important design choices:

- `DocumentLineSource` uses an associated type rather than forcing `String`.
- `DocumentLineCursor` uses a mutating `next()` method rather than `Sequence` conformance.
- Conditional `Equatable` conformances are limited to payloads that are themselves `Equatable`.
- The cursor stores the supplied source value or reference.

That last point is acceptable for Slice 2, but it should remain visible in future adapter design. Real providers should likely be lightweight handles or reference types so callers do not accidentally copy large storage values into a cursor.

## Test Assessment

Slice 2 added focused tests for the new provider boundary.

The test suite covers:

- `DocumentLine` value storage.
- Conditional equality for `DocumentLineFetch`, `DocumentLine`, and `DocumentLineCursorElement`.
- Array-backed in-test provider behavior.
- Cursor output for exactly `bufferStart..<bufferEndExclusive`.
- Ascending request order.
- Empty ranges producing no output and no fetches.
- Missing provider indexes producing `.missing(index:)`.
- One provider fetch per requested buffered index.
- `ViewportVirtualizer.compute(_:)` performing zero provider fetches.
- Generated buffered ranges proving work is proportional to buffered range size, not total document size.

Existing Slice 1 viewport, overscan, validation, and geometry tests remain unchanged and continue to pass.

Remaining test gaps:

- No real 100k+ or >10 MB storage adapter is tested.
- No property-style test pairs geometry cursor output with provider cursor output across generated ranges.
- No benchmark includes provider cursor traversal.
- No allocation or memory measurement exists for cursor creation/traversal.
- Malformed `VirtualRange` values are intentionally not normalized or defensively tested in this slice.

## Verification Results

Fresh verification was run on 2026-05-31.

Commands:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
xcrun swiftc -target arm64-apple-ios17.0 -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios.swiftmodule
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk /Applications/Xcode_26_3.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.2.sdk -parse-as-library -emit-module Sources/TextEngineCore/ViewportTypes.swift Sources/TextEngineCore/ViewportVirtualizer.swift Sources/TextEngineCore/LineGeometryCursor.swift Sources/TextEngineCore/DocumentLineTypes.swift Sources/TextEngineCore/DocumentLineCursor.swift -module-name TextEngineCore -o /private/tmp/TextEngineCore-ios-simulator.swiftmodule
```

Results:

- `swift test`: pass, 39 tests, 0 failures.
- `swift build -c release`: pass.
- `swift run -c release ViewportBenchmarks`: pass.
- WASM `TextEngineCore` target build: pass.
- Embedded WASM `TextEngineCore` target build: pass.
- iOS device module compile: pass.
- iOS simulator module compile: pass.

Fresh benchmark output:

```text
scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=43 p99_ns=55 checksum=5114982400
scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=11 p99_ns=12 checksum=511488422400
scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=8 p99_ns=9 checksum=5114881152000
```

These numbers remain far below the initial Slice 1 target budgets:

- p95 under 100 us
- p99 under 250 us

Interpretation caveat: the benchmark currently measures range recomputation only. It does not include geometry cursor traversal, provider cursor traversal, UI rendering, text shaping, rasterization, file IO, or real document storage.

The release build emitted macOS deployment-target linker warnings while building the benchmark executable. This did not affect the `TextEngineCore` compile checks, but CI packaging should make the intended macOS benchmark deployment target explicit later.

## Commit History Notes

The Slice 2 commit history is compact and healthy:

- design document for the provider boundary
- implementation plan
- document line source value types
- buffered document line cursor
- verification record

The implementation commits are small and map directly to the design:

- `feat: add document line source types`
- `feat: add buffered document line cursor`
- `docs: record document source provider verification`

No correction commits were needed after implementation. The main technical risk from Slice 1, fractional viewport boundary precision, was not touched by this slice.

## Risks And Gaps

### Benchmark Gate Still Missing

The product brief asks for regression benchmarks that block merge on performance degradation. Slice 1 created a benchmark executable, and Slice 2 preserved range-recompute performance, but there is still no automated gate.

This is now the largest explicit product-brief gap.

### Benchmark Scope Remains Narrow

The current benchmark is useful as a range-recompute baseline, but it does not measure the full headless traversal path that a renderer would use after Slice 2:

- compute viewport range
- traverse line geometry
- traverse provider lines

That means the project still lacks a quantified budget for the actual core-side work a scroll frame would perform.

### Provider Boundary Is Synthetic

The provider contract is tested with in-memory test doubles. That is correct for Slice 2, but it does not yet prove ergonomics or performance with a realistic large document representation.

The next storage-related slice should keep real adapters outside `TextEngineCore` unless there is a deliberate target split.

### Cursor Source Ownership Needs Care

`DocumentLineCursor` stores the supplied source. For reference-backed providers this is cheap. For large value-backed providers, callers could accidentally copy too much state into the cursor.

This does not require a Slice 2 fix, but future examples and adapters should model providers as lightweight values or references.

### Malformed Ranges Are Still Caller Responsibility

Slice 2 intentionally does not defensively normalize arbitrary `VirtualRange` values. This keeps the cursor simple and preserves the Slice 1 invariant that valid ranges come from `ViewportVirtualizer.compute(_:)`.

Before the public API stabilizes, the project should decide whether `VirtualRange` should remain freely constructible or gain a stricter construction path.

### Memory Is Still Reasoned, Not Measured

The cursor implementation is O(1) in owned state, and traversal is O(buffered line count), but there is no automated memory or allocation check.

## Lessons For Slice 3

1. Treat the full headless traversal path as the next performance unit.

Slice 1 proved range recomputation. Slice 2 proved provider traversal. The next performance proof should measure the two together with geometry traversal.

2. Make benchmark results actionable.

Manual benchmark output is useful for review, but the product brief calls for merge-blocking regression gates. The next slice should define budgets, output format, and failure behavior.

3. Keep real storage outside the core until a target boundary is explicit.

Slice 2 succeeded because it avoided production storage adapters. If the next slice touches real document data, it should likely do so in a separate target or benchmark fixture rather than `TextEngineCore`.

4. Preserve cross-target compile verification.

Slice 2 closed the previous iOS/WASM/embedded verification gap. New public APIs should keep the same gate, especially if they introduce closures, generics, protocols, or benchmark infrastructure.

5. Do not start variable-height layout without a stronger performance baseline.

Variable-height layout and invalidation will be more complex than the first two slices. Entering that work without a benchmark gate makes regressions harder to interpret.

## Slice 3 Candidate Options

### Option A: Headless Pipeline Benchmark And Regression Gate

Measure `ViewportVirtualizer.compute(_:)` plus buffered geometry cursor traversal plus provider cursor traversal. Add explicit p95/p99 budgets and a command that fails on regression.

This is the recommended Slice 3 because it closes the largest remaining product-brief gap before the engine grows more complex.

### Option B: Realistic Provider Proof Outside Core

Add a non-core benchmark/test fixture that models a large line source and proves provider ergonomics on 100k+ lines or >10 MB content.

This would improve confidence in the provider API, but it risks starting storage design before benchmark gating is settled.

### Option C: Variable-Height Layout Foundation

Begin the next product capability: mapping logical lines to measured heights and invalidating layout ranges.

This moves product functionality forward, but it is higher risk without a benchmark gate and should likely wait until the performance harness covers the current fixed-height pipeline.

## Slice 2 Review Conclusion

Slice 2 is a clean completion of the document/source provider boundary. It preserves the headless architecture, keeps storage outside the core, exposes missing provider lines explicitly, and verifies the new generic public API across host, iOS, WASM, and embedded WASM library targets.

The slice does not yet prove real storage behavior or full scroll-frame performance, and it does not add merge-blocking benchmark gates. Those are now the most important unresolved product risks.

The most natural next product slice is a headless pipeline benchmark and regression gate that measures range computation, geometry traversal, and provider traversal together.
