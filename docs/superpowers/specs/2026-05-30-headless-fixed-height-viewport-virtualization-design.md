# Headless Fixed-Height Viewport Virtualization Design

Date: 2026-05-30

## Status

Draft for user review.

## Source Brief

This design treats `docs/initial-project-brief.md` as a product brief, not as a ready implementation specification.

The full brief describes a headless text rendering engine: geometry calculation, viewport virtualization, document provider abstraction, performance budgets, platform portability, and later rendering-related capabilities. That scope is too large for one implementation specification. This document defines only the first vertical slice.

## High-Level Decomposition

The product should be split into separate specifications and implementation plans:

1. Fixed-height headless viewport virtualization.
2. Document/source provider contract and integration adapters.
3. Variable-height line layout and layout invalidation.
4. Text shaping, bidi, font fallback, and rich text layout.
5. Rasterization or UI-framework adapters.
6. Cross-platform and Swift Embedded compile verification.
7. Performance benchmark suite and merge-blocking regression gates.

This document covers only item 1, with enough benchmark scaffolding requirements to prove the architecture does not depend on total document size.

## First Slice

Build a headless viewport virtualization core for fixed-height logical lines.

The first slice proves that the core can calculate the visible window of a large logical document without owning document storage, without touching UI frameworks, and without doing glyph shaping or rasterization.

## Goals

- Compute visible and buffered logical line ranges for a vertical viewport.
- Produce per-line geometry only for the buffered range.
- Keep the core independent of Foundation types in public API.
- Keep document storage outside the core.
- Make recompute cost independent of total document size except for constant-time clamping.
- Support iOS and WASM source compatibility.
- Mark Swift Embedded-sensitive API choices as requiring compile verification.
- Define measurable headless latency and memory expectations.

## Non-Goals

- Glyph shaping.
- Text rasterization.
- Bidi handling.
- Rich text.
- Font fallback.
- Variable-height lines.
- UI integration.
- Async prefetch.
- Per-document layout cache.
- Storing document text inside the core.

## Assumptions

- All logical lines in this slice have the same positive height.
- Vertical scrolling is represented as a numeric y offset.
- Consumers own scroll state and document storage.
- Consumers can ask an external provider for line content after the core returns line indexes.
- Public API avoids Foundation-specific types.
- Any questionable API under Swift Embedded must be verified by compilation before implementation is considered complete.

## Architecture

The first specification introduces a `ViewportVirtualizationCore` for fixed-height logical lines.

The core does not know about fonts, glyphs, text runs, UIKit, SwiftUI, AppKit, Canvas, Foundation collections, files, or actual document storage. It receives numeric viewport input and returns bounded logical line ranges and lightweight geometry for those lines.

The core calculates a window; it does not own the document.

Document/source abstraction remains outside the critical geometry path. The first slice may name a future `DocumentLineSource` boundary, but range calculation must not depend on fetching text. This keeps the proof focused: viewport recomputation depends on viewport size and overscan, not on total document bytes or line count.

## Components

### ViewportInput

Immutable input value for one recomputation:

- `lineCount`
- `lineHeight`
- `scrollOffsetY`
- `viewportHeight`
- `overscanLinesBefore`
- `overscanLinesAfter`

The implementation may use concrete numeric types chosen during planning, but the public API must not require Foundation.

### VirtualRange

Result value for one recomputation:

- `visibleStart`
- `visibleEndExclusive`
- `bufferStart`
- `bufferEndExclusive`
- `isEmpty`
- `isAtTop`
- `isAtBottom`

All ranges are half-open and clamped to `[0, lineCount)`.

### LineGeometry

Per-line geometry for the buffered range:

- `lineIndex`
- `y`
- `height`

For this slice, `height == lineHeight`. `y` is computed arithmetically from `lineIndex` and `lineHeight`.

### ViewportVirtualizer

Pure stateless calculation API, shaped around:

- compute a `VirtualRange` from `ViewportInput`
- iterate or build `LineGeometry` only for `bufferStart..<bufferEndExclusive`

The API must not allocate or return geometry for non-buffered document lines.

### DocumentLineSource Boundary

A provider/source abstraction is a product requirement, but it is not part of the range calculation dependency graph for this first slice.

The design may document a future boundary:

- provider owns text storage
- provider exposes line count and visible line content outside the core
- provider can be implemented differently for iOS, WASM, files, memory, or editor buffers

The first implementation should not require a complete provider system to prove viewport virtualization.

## Data Flow

1. Consumer or adapter owns document storage and scroll state.
2. Consumer obtains `lineCount`, `scrollOffsetY`, `viewportHeight`, `lineHeight`, and overscan settings.
3. Consumer calls the headless core with `ViewportInput`.
4. Core validates or normalizes input.
5. Core calculates:
   - first visible logical line
   - end-exclusive visible logical line
   - overscanned buffer range
6. Core returns `VirtualRange`.
7. Consumer asks the core for geometry only for the buffered range.
8. Consumer separately asks its document provider for visible line content and renders it in any UI framework.

No scroll position, document text, UI object, or platform object is retained by the core.

## Range Calculation

The fixed-height calculation is intentionally arithmetic:

- `firstVisible = floor(scrollOffsetY / lineHeight)`
- `lastVisibleExclusive = ceil((scrollOffsetY + viewportHeight) / lineHeight)`
- clamp visible range to document bounds
- expand by overscan before and after
- clamp buffer range to document bounds

Boundary behavior must be deterministic for exact line boundaries and subpixel offsets.

## Error Handling And Edge Cases

The first slice should prefer a predictable API over trapping behavior in normal adapter usage.

Expected behavior:

- `lineCount == 0`: return empty ranges and no geometry.
- `lineHeight <= 0`: invalid input.
- `viewportHeight < 0`: invalid input.
- `scrollOffsetY < 0`: clamp to `0`.
- `scrollOffsetY` beyond document height: clamp effective offset to `max(0, lineCount * lineHeight - viewportHeight)`; output remains in bounds.
- negative overscan: invalid input.
- overscan larger than document: clamp buffer range to `[0, lineCount)`.

The design target is an explicit lightweight validation result type that does not depend on Foundation. Exact Swift representation requires compile verification for Swift Embedded.

Unchecked/internal fast paths may exist only if tests and benchmarks exercise the public validated path as well.

## Performance Budget

The product brief's "60 FPS" requirement is translated into headless recomputation budgets.

Initial target budgets for local benchmark hardware:

- p95 viewport range recompute: under 100 us
- p99 viewport range recompute: under 250 us

These numbers are design targets for the first implementation. They must be verified on real toolchains and may be tightened after baseline measurement.

The budget applies to range recomputation and geometry generation for the buffered range. It excludes UI rendering, glyph shaping, rasterization, file IO, and provider text loading.

## Memory Budget

Core-owned memory must not grow linearly with total document size.

Expected complexity:

- range-only recompute: O(1) core-owned memory
- materialized geometry: O(buffered line count)
- no per-document layout cache
- no retained text storage

The implementation should make it difficult to accidentally allocate for all lines. Tests and benchmarks should include large `lineCount` values to catch this class of mistake.

## Testing

Functional tests should cover:

- empty document
- single-line document
- viewport smaller than document
- viewport equal to document
- viewport larger than document
- negative scroll offset
- oversized scroll offset
- zero overscan
- large overscan
- exact line boundary
- subpixel offset
- viewport ending exactly on a line boundary
- large line counts such as 100k and 1M

Property-style tests can be implemented without third-party dependencies by generating numeric inputs in a deterministic loop. Invariants:

- `0 <= visibleStart <= visibleEndExclusive <= lineCount`
- `0 <= bufferStart <= bufferEndExclusive <= lineCount`
- `bufferStart <= visibleStart`
- `visibleEndExclusive <= bufferEndExclusive`
- geometry count equals `bufferEndExclusive - bufferStart`
- geometry line indexes are contiguous
- geometry y positions are monotonic

Benchmark scenarios should vary:

- document sizes: 1k, 100k, 1M logical lines
- viewport sizes: about 20, 80, and 200 visible lines
- overscan: 0, 5, and 50 lines

The first implementation should establish a baseline and later turn regressions into merge-blocking checks once the repository has CI.

## Compile Verification

Because Swift Embedded is experimental, the following require compile verification:

- chosen numeric types
- validation result representation
- protocol or generic boundaries for future provider integration
- iterator or sequence API used for geometry
- any use of standard library APIs that may be questionable under Embedded Swift

The implementation plan should include explicit compile commands for the available iOS and WASM targets, or record any missing toolchain as a blocker.

## Open Decisions For Later Specs

These are intentionally outside the first slice:

- exact provider/source API
- variable-height line indexing strategy
- layout invalidation model
- font metrics
- shaping engine
- bidi model
- rich text representation
- UI adapter contracts
- CI environment and exact benchmark hardware

## Acceptance Criteria

The first slice is complete when:

- core API computes visible and buffered ranges for fixed-height logical lines
- geometry is produced only for the buffered range
- tests cover boundary and large-document cases
- benchmark output reports p95 and p99 viewport recompute latency
- core-owned memory is O(1) for range-only recompute and O(buffered line count) for materialized geometry
- no Foundation-specific type appears in the public core API
- Swift Embedded-sensitive API choices are compile-verified or explicitly marked as blockers
