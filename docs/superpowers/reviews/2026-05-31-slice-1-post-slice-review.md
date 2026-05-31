# Slice 1 Post-Slice Review

Date: 2026-05-31

## Scope Reviewed

This review covers Slice 1: headless fixed-height viewport virtualization.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/specs/2026-05-30-headless-fixed-height-viewport-virtualization-design.md`
- `docs/superpowers/plans/2026-05-31-headless-fixed-height-viewport-virtualization.md`
- `Sources/TextEngineCore`
- `Tests/TextEngineCoreTests`
- `Sources/ViewportBenchmarks/main.swift`
- `docs/superpowers/verification/2026-05-31-headless-fixed-height-viewport-virtualization.md`
- local git commit history

No separate PR notes were found in the repository.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core that computes geometry and virtualizes the visible area while staying independent from UI frameworks.

Slice 1 intentionally narrowed that product goal to fixed-height logical lines. This was the right first slice because it proves the central virtualization invariant before document providers, variable-height layout, text shaping, rasterization, or UI adapters are introduced.

Slice 1 directly addresses these brief requirements:

- UI-framework independence.
- No Foundation dependency in the core module.
- Public API that avoids Foundation-specific types.
- Strict virtualization: compute only visible viewport plus buffer/overscan.
- Core-owned memory independent from full document size for range-only recompute.
- Headless latency measured as p95/p99 benchmark output.

Slice 1 does not yet prove these brief requirements:

- iOS source compatibility.
- WASM source compatibility.
- Swift Embedded compile compatibility.
- Merge-blocking benchmark regression gates.
- External document/source provider contract.

Those were either out of scope for Slice 1 or explicitly recorded as blockers.

## Delivered Design

The Slice 1 design decomposed the larger product into separate slices:

1. Fixed-height headless viewport virtualization.
2. Document/source provider contract and integration adapters.
3. Variable-height line layout and layout invalidation.
4. Text shaping, bidi, font fallback, and rich text layout.
5. Rasterization or UI-framework adapters.
6. Cross-platform and Swift Embedded compile verification.
7. Performance benchmark suite and merge-blocking regression gates.

The implemented slice matches item 1 with enough benchmark scaffolding to establish a baseline.

The core API consists of:

- `ViewportInput`
- `VirtualRange`
- `LineGeometry`
- `ViewportValidationError`
- `ViewportComputation`
- `ViewportVirtualizer.compute(_:)`
- `ViewportVirtualizer.geometry(for:lineHeight:)`
- `LineGeometryCursor`

The implementation remains stateless. Consumers own document storage, scroll state, and rendering.

## Implementation Assessment

The implementation is appropriately small and focused.

Strengths:

- The public core API is value-type based and does not import Foundation.
- `ViewportVirtualizer.compute(_:)` validates input before range calculation.
- Range calculation is O(1) with respect to total document size.
- Overscan expansion uses integer math, avoiding precision loss near large indexes.
- Geometry generation is cursor-based and only covers the buffered range.
- The core does not retain document text, scroll state, UI objects, provider references, or caches.

Important design choices:

- `Int` and `Double` are used in the public API.
- Validation returns a lightweight enum result instead of throwing.
- Geometry uses `LineGeometryCursor` rather than `Sequence` conformance.
- `ContinuousClock` is isolated to the benchmark executable target.

These choices fit the Slice 1 constraints, but the public numeric and enum representations still need target compile verification before being treated as proven under Swift Embedded, iOS, and WASM.

## Test Assessment

The test suite covers the main functional surface:

- value storage
- validation failures
- empty document behavior
- negative scroll clamping
- oversized scroll clamping
- viewport larger than document
- zero-height viewport
- subline offsets
- exact and fractional boundaries
- large indexes
- overscan expansion and clamping
- deterministic generated input invariants
- cursor geometry output

The strongest part of the test suite is the coverage around fractional boundaries and large indexes. The commit history shows several fixes around snapping and boundary precision, so these tests are carrying real regression value.

Remaining test gaps:

- Geometry invariants are covered by cursor examples, but not by generated/property-style tests.
- The benchmark does not currently include geometry cursor traversal in the measured operation.
- No target-specific compile checks exist for iOS, WASM, or Swift Embedded.
- No automated memory measurement exists. Memory complexity is supported by code shape, not measured.

## Verification Results

Fresh verification was run on 2026-05-31.

Commands:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
```

Results:

- `swift test`: pass, 29 tests, 0 failures.
- `swift build -c release`: pass.
- `swift run -c release ViewportBenchmarks`: pass.

Fresh benchmark output:

```text
scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=7 p99_ns=9 checksum=5114982400
scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=9 p99_ns=10 checksum=511488422400
scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=7 p99_ns=9 checksum=5114881152000
```

These numbers are far below the initial Slice 1 target budgets:

- p95 under 100 us
- p99 under 250 us

Interpretation caveat: the benchmark currently measures range recomputation only. It does not include geometry cursor traversal, UI rendering, provider access, text shaping, rasterization, or file IO.

## Commit History Notes

The Slice 1 commit history shows a healthy progression:

- design and implementation plan
- package and core value types
- validation
- fixed-height range calculation
- non-finite input handling
- clamped index conversion
- overscan
- integer precision fixes
- buffered geometry cursor
- benchmark executable
- benchmark batching
- verification record
- fractional boundary snapping fixes
- final verification updates

The notable risk pattern is boundary precision. Multiple commits were needed after initial benchmark and verification work to handle fractional viewport boundaries correctly. This suggests future layout work should continue to treat numeric boundary behavior as a first-class design topic, not an incidental detail.

## Risks And Gaps

### Cross-Target Verification

iOS and WASM compatibility are product requirements, but they remain blocked until build commands/toolchains are configured.

This matters because future provider, iterator, protocol, generic, and layout APIs could accidentally introduce source or compile assumptions that only fail outside the host SwiftPM build.

### Benchmark Scope

The benchmark is useful as a baseline, but it is not yet a merge-blocking gate and does not measure geometry cursor generation. It should not be treated as a complete scroll-performance proof.

### Provider Boundary Missing

Slice 1 deliberately avoided the document/source provider. That kept the first slice clean, but the product still needs a boundary that proves document storage can stay outside the core while consumers can fetch visible content from returned line indexes.

### Memory Is Reasoned, Not Measured

The implementation shape supports O(1) range recompute memory and O(buffered line count) geometry traversal. However, there is no automated memory benchmark or allocation check.

### Public API Is Still Early

`ViewportInput`, `VirtualRange`, and `LineGeometry` are coherent for Slice 1. The next slice may reveal whether these types need small adjustments to integrate cleanly with a provider boundary or future variable-height layout.

## Lessons For Slice 2

1. Keep the next slice narrow.

Slice 1 succeeded because it separated fixed-height viewport math from document storage, UI, shaping, and rendering. Slice 2 should preserve that discipline.

2. Treat compile verification as a design constraint, not cleanup.

The source brief makes iOS/WASM/Swift Embedded compatibility central. Any new public API introduced in Slice 2 should include an explicit target verification strategy or a recorded blocker.

3. Keep provider access outside the hot geometry path.

Slice 1 proved the range calculation can stay independent from document size. Slice 2 should not undo that by coupling viewport recomputation to text loading.

4. Extend benchmarks only where they prove a product risk.

The current benchmark proves range recomputation is cheap. Slice 2 can either keep provider benchmarks out of scope or explicitly measure only adapter/provider boundary overhead in a separate benchmark path.

5. Preserve numeric boundary tests.

Fractional boundaries were the highest-friction area in Slice 1. Future layout slices should keep exact-boundary, subpixel, and large-index tests as baseline coverage.

## Slice 1 Review Conclusion

Slice 1 is a solid foundation for the headless core. It establishes the first critical invariant: the core can compute visible and buffered line windows for large fixed-height documents without owning document storage, touching UI frameworks, or allocating by total document size.

The slice is not a full product proof yet. The biggest unresolved risks are cross-target compile verification, provider/source integration, and benchmark gate automation.

The most natural next product slice is the document/source provider contract, provided it includes an explicit compile-verification gate for the new public API shape.
