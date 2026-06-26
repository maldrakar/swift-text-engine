# Provider-Native Prefix Search Design

Slice 29 - optimize the existing vertical y->line query for mutable indexed
providers.

## Status

Proposed. Brainstormed 2026-06-26 after the Slice 28 post-slice review
recommended Option A: provider-native prefix search. The user selected the
recommended direction and approved the design sections:

- API boundary: defaulted `LineMetricsSource` requirement plus native
  `BalancedTreeLineMetrics` override.
- Implementation flow: optimize `ViewportVirtualizer.lineAt(y:metrics:)` only;
  do not expand this slice into `compute`.
- Testing and verification: structural oracle, native-hook dispatch proof,
  existing `--line-query --gate` benchmark evidence.
- Scope: include the small carried provider-doc P3 cleanup because this is a
  provider-touching slice.

## Source Context

The brief (`docs/initial-project-brief.md`) requires a headless layout and
virtualization core that supports stable scrolling on 100k+ line / >10 MB
documents, keeps core-owned memory from scaling linearly with document size,
stays Foundation-free and zero-dependency, and compiles for iOS and WASM without
source changes.

Slice 27 added `ViewportVirtualizer.lineAt(y:metrics:)`, the public inverse of
`LineMetricsSource.offset(ofLine:)`. It maps a document y offset to the logical
line whose half-open vertical span contains it, preserving explicit clamp flags
for out-of-range y values. The current implementation is generic: after
validation it binary-searches over `offset(ofLine:)`. That is O(log N)
`offset` probes and O(1) core memory.

Slice 28 promoted the existing `--line-query --gate` benchmark to a blocking
hosted CI gate. The path this slice changes is now protected in hosted CI and
already has `balanced_tree_100k` and `balanced_tree_1m` scenarios.

The remaining asymptotic gap is provider-specific. `BalancedTreeLineMetrics`
answers `offset(ofLine:)` in O(log N), so the generic binary search makes a
balanced-tree line query O(log^2 N) wall-clock: O(log N) outer probes, each with
an O(log N) provider offset. The provider already stores `subtreeHeightSum`, so
it can answer "which line contains this y offset?" in one O(log N) tree descent.

## Problem

The public `lineAt` behavior is correct, tested, and now CI-protected, but the
mutable balanced-tree provider pays an avoidable O(log^2 N) cost for y->line
queries. That is not a correctness defect, and current budgets have large
headroom, but it leaves the core/provider composition weaker than the data
structure allows.

Consumers should still call the core query. They should not have to choose
between a provider-specific method and the authoritative core boundary/clamp
semantics. The provider should expose a lower-level primitive that core can use
after it has validated and clamped the public query.

## Scope

This slice adds a provider-native prefix-search hook under the existing
`ViewportVirtualizer.lineAt(y:metrics:)` public API:

- Add a defaulted requirement to `LineMetricsSource` for the in-range primitive:
  "given a validated non-empty metrics snapshot and `0 <= y < totalHeight`,
  return the line index whose half-open span contains y."
- Implement the default requirement with the current generic binary search, so
  existing conformers keep source compatibility and behavior.
- Change `lineAt` to preserve its validation/clamp order and call the new hook
  only for the in-range branch.
- Override the hook in `BalancedTreeLineMetrics` with a native descent over
  `subtreeHeightSum`, making the balanced-tree y->line path one O(log N) walk.
- Add core tests proving native-hook dispatch and fallback behavior.
- Add reference-provider tests proving `BalancedTreeLineMetrics` native search
  matches a `PrefixSumLineMetrics` oracle across boundaries and after mutations.
- Reuse the existing `--line-query --gate` benchmark as the performance evidence
  for the optimized path.
- Update durable docs that describe `lineAt` as generic-binary-search-only.
- Retire the carried Slice 25/26 P3 provider-doc naming drift with a narrow
  cross-reference from the old bulk-edits spec wording to the shipped
  `join2`/`join3` primitives.

## Goals

- Preserve `ViewportVirtualizer.lineAt(y:metrics:) -> LineQuery` as the only
  consumer-facing vertical query API for this slice.
- Preserve all `LineQuery`, `LineLocation`, clamp, empty-document, and failure
  semantics from Slice 27.
- Keep the generic fallback O(log N) `offset(ofLine:)` probes and O(1) core
  memory.
- Make `BalancedTreeLineMetrics` in-range line queries O(log N) wall-clock by
  using the provider's existing subtree height sums directly.
- Keep `TextEngineCore` Foundation-free, Embedded-compatible, and
  zero-dependency.
- Keep existing `LineMetricsSource` conformers source-compatible through a
  default implementation.
- Prove behavior structurally against an oracle rather than relying on timing
  deltas.

## Non-Goals

- No new public `LineQuery` result shape.
- No geometry-bearing vertical query, within-line fraction, y span, or height in
  the result.
- No horizontal axis, wrapping, visual-row model, or x/y point query.
- No `ViewportVirtualizer.compute` optimization in this slice. Its visible-start
  and visible-end searches have a different behavioral surface, especially the
  end-exclusive `firstLineTopAtOrAbove` path.
- No hosted WASM policy change.
- No Linux-native budget re-baseline and no budget tightening for
  `--line-query --gate`.
- No provider data-structure rewrite beyond the native search method.

## Decisions

### Decision 1 - Add a defaulted `LineMetricsSource` prefix-search requirement

`LineMetricsSource` gains a defaulted requirement with this semantic shape:

```swift
public protocol LineMetricsSource {
    var lineCount: Int { get }
    func offset(ofLine index: Int) -> Double

    func lineIndex(containingOffset y: Double, totalHeight: Double) -> Int
}
```

The exact implementation will live in `LineMetricsSource.swift`. The requirement
is intentionally lower-level than `lineAt`:

- Preconditions: `lineCount > 0`; `offset(ofLine: 0) == 0`; `totalHeight` is the
  validated `offset(ofLine: lineCount)`; `totalHeight` is finite and positive;
  `0 <= y && y < totalHeight`.
- Return: the largest line index `i` in `0..<lineCount` such that
  `offset(ofLine: i) <= y`.
- It does not validate inputs, clamp edges, or return `LineQuery`. Public
  validation remains centralized in `ViewportVirtualizer.lineAt`.

The default implementation calls the existing generic binary search helper. This
is effectively an optional provider hook implemented through a default protocol
requirement: existing providers inherit the fallback, while providers with a
better native prefix search override the requirement.

Rationale:

- A separate opt-in protocol would keep the base protocol narrower, but generic
  callers constrained only to `LineMetricsSource` would continue to hit the
  fallback unless the core adds runtime type casts or call sites are reworked.
- A provider-only method would not improve the public core query and would force
  consumers to duplicate the choice of path.
- A defaulted requirement lets existing generic benchmark and core code dispatch
  through the witness table, so `BalancedTreeLineMetrics` gets the native path
  without special casing in benchmark code.

### Decision 2 - Keep `lineAt` as the semantic owner

`ViewportVirtualizer.lineAt(y:metrics:)` keeps the Slice 27 validation order:

1. `metrics.lineCount < 0` -> `.failure(.negativeLineCount)`
2. non-finite y -> `.failure(.nonFiniteValue)`
3. `metrics.offset(ofLine: 0) != 0.0` -> `.failure(.invalidLineMetrics)`
4. empty document -> `.empty`
5. invalid total height -> `.failure(.invalidLineMetrics)`
6. `y < 0` -> `.clampedToTop`
7. `y >= totalHeight` -> `.clampedToBottom`
8. otherwise call `metrics.lineIndex(containingOffset: y, totalHeight: totalHeight)`
   and wrap the returned index as `.line(LineLocation(index, .inRange))`

No public behavior changes are allowed. The hook is used only after the core has
established the exact preconditions it documents.

For non-native providers, the default hook preserves the current binary-search
fallback and query-count envelope. For native providers, the validation probes
still happen (`offset(0)` and `offset(lineCount)`), but the in-range search
avoids the generic binary-search offset probes.

### Decision 3 - Implement balanced-tree search as one subtree-sum descent

`BalancedTreeLineMetrics` overrides the requirement with a non-mutating tree walk:

- Track the current node, the accumulated in-order base index, and the remaining
  y offset inside the current subtree.
- Compare y with the left subtree sum.
  - If `y < leftSum`, descend left.
  - Otherwise subtract `leftSum`.
- Compare the remaining y with the current node height.
  - If `remaining < node.height`, return `baseIndex + leftCount`.
  - Otherwise subtract the node height, advance `baseIndex` by `leftCount + 1`,
    and descend right.

Boundary semantics match the existing half-open contract:

- `y == offset(i)` resolves to line `i`, the line starting at that boundary.
- `y == offset(i + 1)` advances to the next line, except `y == totalHeight` is
  never passed to the hook because `lineAt` clamps it before the in-range branch.

The implementation uses existing `subtreeHeightSum` and `subtreeCount` fields.
It does not allocate, does not mutate the tree, and does not add core-owned
memory.

### Decision 4 - Do not optimize `compute` in Slice 29

`ViewportVirtualizer.compute(_:metrics:)` currently uses
`firstLineTopAtOrBelow` for visible start and `firstLineTopAtOrAbove` for visible
end. The provider-native primitive in this slice answers only "line containing
this y", which is the exact in-range primitive `lineAt` needs.

Using it in `compute` would only cover visible start directly. Visible end has
end-exclusive semantics and needs "first top at or above target", which is a
different primitive. That can be a future slice if profiling shows value. Keeping
Slice 29 limited to `lineAt` keeps the proof surface tight and directly tied to
the Slice 28 gate.

### Decision 5 - Reuse the existing line-query gate without retuning budgets

The existing `--line-query --gate` benchmark is now a blocking hosted gate and
already includes balanced-tree scenarios. This slice should reuse it rather than
inventing a new benchmark mode.

Expected benchmark behavior:

- Checksums remain byte-identical to the generic/oracle behavior.
- `balanced_tree_100k` and `balanced_tree_1m` p95/p99 should improve because the
  in-range path is one tree descent instead of binary-searching over tree offsets.
- Uniform scenarios may stay effectively unchanged because `UniformLineMetrics`
  inherits the fallback in this slice.
- Budgets remain unchanged. Tightening them or deriving Linux-native budgets is a
  separate policy/baseline slice, not part of this functional increment.

### Decision 6 - Retire the carried provider-doc P3 while this slice is open

The Slice 28 review carried a pre-existing P3: the bulk structural edits spec
uses the older primitive name `join(_:_:)`, while the implementation shipped
`join2` and `join3`.

Because Slice 29 touches provider behavior and provider documentation anyway, it
should add a narrow cross-reference to the bulk structural edits spec explaining
that the shipped implementation names the join helpers `join2`/`join3`. This is
docs-only hygiene. It must not change provider code or broaden the prefix-search
implementation scope.

## Testing Strategy

### Core Tests

Add focused tests in `Tests/TextEngineCoreTests`:

- A custom `LineMetricsSource` that overrides the new requirement and counts
  calls. For an in-range query, assert:
  - the result matches the expected `LineLocation`;
  - the native hook is called exactly once;
  - validation still performs only the expected `offset(0)` and total-height
    probes before the native hook.
- Preserve existing fallback query-count tests for a metrics type that does not
  override the requirement, proving the default remains logarithmic and non-finite
  y still performs zero offset queries.
- Existing `LineAtTests` and `LineAtEquivalenceTests` should continue to pass
  without expectation changes.

### Reference Provider Tests

Add tests in `Tests/TextEngineReferenceProvidersTests` for
`BalancedTreeLineMetrics`:

- Direct native search equals a `PrefixSumLineMetrics` oracle over:
  - y at the top of selected lines;
  - y inside selected lines;
  - y one representable step before a boundary where practical;
  - first and last lines.
- `ViewportVirtualizer.lineAt(y:metrics:)` with `BalancedTreeLineMetrics` matches
  the oracle for in-range and clamped y values.
- After `setHeight`, `insertLine`, `removeLine`, `insertLines`, and
  `removeLines`, native search still matches a fresh prefix-sum oracle.
- A test-only internal helper may return native descent visit count so tests can
  assert the walk remains logarithmic across 1k / 100k / 1m sizes without
  exposing a new public diagnostic.

### Benchmark And Verification Tests

The implementation plan should include:

- `swift test`
- `swift build -c release`
- `swift run -c release ViewportBenchmarks -- --line-query --gate`
- the existing hosted-gate local sweep, at least the default synthetic gate and
  any adjacent gates touched by shared benchmark code
- `rg -n "Foundation" Sources/TextEngineCore`
- `rg -n "Foundation" Sources/TextEngineReferenceProviders`
- `./.github/scripts/cross-target-compile.sh --self-test`
- `./.github/scripts/cross-target-compile.sh` for the public API/provider change,
  or a precise local blocker if the matching toolchain/SDK is unavailable

The verification record should capture line-query checksums before and after the
change. If p95/p99 improve, record the numbers as observation, not as the only
proof of correctness.

## Risks And Mitigations

### Adding a requirement to a public protocol broadens the API

Even with a default implementation, `LineMetricsSource` gains a new public
member. That is intentional because the core needs dispatch through the existing
generic boundary. The method is documented as a lower-level primitive with
strict preconditions; public callers should normally keep using
`ViewportVirtualizer.lineAt`.

### `totalHeight` can be misused by direct callers

The hook accepts `totalHeight` to avoid recomputing `offset(ofLine: lineCount)`
inside the fallback after `lineAt` has already validated it. Direct callers could
pass an inconsistent value. The mitigation is explicit documentation: the value
must be the validated total height for the same stable metrics snapshot.

### Native and fallback boundary behavior could drift

The primary risk is exact-boundary drift between the generic binary search and
the tree descent. The oracle tests must include line-top boundaries and line-end
boundaries so the half-open convention is locked down.

### Embedded Swift compatibility must be verified

The design avoids runtime casts, Foundation, dependencies, and allocation in the
native search. Because it changes a public protocol and provider implementation,
cross-target compile remains part of verification.

## Documentation Updates

After implementation, update durable docs that currently describe `lineAt` as
only reusing the generic binary search:

- `AGENTS.md` architecture paragraph should say `lineAt` uses a provider-native
  prefix-search hook when available and the generic binary-search fallback
  otherwise.
- The Slice 29 verification record should preserve the exact command output,
  benchmark rows, checksums, and any hosted run IDs.
- The bulk structural edits spec should get the one-line `join2`/`join3`
  cross-reference that retires the carried P3.

## Recommended Next Step

After this spec is reviewed and approved, write the Slice 29 implementation plan
with TDD steps:

1. Add failing core tests for native-hook dispatch while preserving fallback
   query-count behavior.
2. Add failing reference-provider oracle tests for balanced-tree native search.
3. Add the defaulted protocol requirement and wire `lineAt` to it.
4. Implement the balanced-tree native descent.
5. Update benchmark comments/docs and retire the carried provider-doc P3.
6. Run the full verification sweep and record evidence.
