# Compute-Native Prefix Search Design

Slice 30 - extend provider-native prefix search into
`ViewportVirtualizer.compute(_:metrics:)`, the scroll hot path.

## Status

Proposed. Brainstormed 2026-06-27 after the Slice 29 post-slice review
recommended Option A: extend provider-native prefix search into `compute`. The
user selected the recommended direction and approved the design sections:

- Direction: Option A - make `compute` over a balanced-tree provider fully
  O(log N), finishing the arc Slice 29 started on `lineAt`.
- Visible-end implementation: A1 - add a second native `LineMetricsSource`
  primitive `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` with a balanced-tree override,
  rather than deriving the end-exclusive answer from the Slice 29 primitive.
- Proof and protection: reuse the existing gates plus a new compute-equivalence
  oracle and a native visit-count test; record the speedup as a one-off timing
  observation. No new benchmark mode and no new blocking gate.

## Source Context

The brief (`docs/initial-project-brief.md`) requires a headless layout and
virtualization core that supports stable scrolling on 100k+ line / >10 MB
documents, keeps core-owned memory from scaling linearly with document size,
stays Foundation-free and zero-dependency, and compiles for iOS and WASM without
source changes. Regression benchmarks must block merge on degradation.

`ViewportVirtualizer.compute(_:metrics:)` is the stateless variable-height
viewport query. After up-front validation it resolves the visible range with two
monotone searches over `LineMetricsSource.offset(ofLine:)`:

- visible start via `firstLineTopAtOrBelow(effectiveOffsetY, ...)` - the largest
  line index `i` with `offset(ofLine: i) <= effectiveOffsetY` (the line
  containing the viewport top), or `lineCount` when the target is at or past the
  document end.
- visible end via `firstLineTopAtOrAbove(effectiveOffsetY + viewportHeight, ...)`
  - the smallest line index `i` with `offset(ofLine: i) >= target` (the first
  line whose top is at or below the viewport bottom, end-exclusive), or
  `lineCount` at/past the document end. It currently takes a `lowerBound`
  (= visible start) micro-optimization.

Slice 27 added the inverse query `ViewportVirtualizer.lineAt(y:metrics:)`. Slice
28 put it under the blocking `--line-query --gate`. Slice 29 added a defaulted
`LineMetricsSource.lineIndex(containingOffset:)` requirement (default = generic
binary search) and a `BalancedTreeLineMetrics` native subtree-sum descent
override, and routed `lineAt`'s in-range branch through it - making the
balanced-tree `lineAt` path a single O(log N) descent. Slice 29 deliberately
scoped `compute` out (its Decision 4): the visible-end search has end-exclusive
"first top at or above" semantics that need a different provider primitive than
the "line containing y" primitive Slice 29 shipped.

`compute` is the most-exercised query: it runs on every viewport recomputation
(every scroll). After Slice 29 it is the last O(log^2 N) balanced-tree vertical
consumer - both of its searches still go through the generic binary search over
balanced-tree offsets (O(log N) outer probes, each an O(log N) provider offset).

## Problem

`compute` is correct, tested, and gated, but over a `BalancedTreeLineMetrics`
provider it pays an avoidable O(log^2 N) cost on the scroll hot path. The
provider already stores `subtreeHeightSum`/`subtreeCount` and (since Slice 29)
can answer "which line contains this y?" in one O(log N) descent. The only
missing piece is the end-exclusive "first line top at or above y" primitive that
visible end needs. This is not a correctness defect and budgets have large
headroom, but it leaves the core/provider composition weaker than the data
structure allows on the single most important path for stable scrolling.

## Scope

This slice routes both of `compute`'s monotone searches through provider-native
hooks, keeping `compute`'s public signature and `ViewportComputation` contract
unchanged:

- Route visible start through the existing Slice 29 hook
  `metrics.lineIndex(containingOffset:)` (after the `target >= totalHeight` edge
  guard), so balanced-tree gets its native descent and other providers keep the
  default binary search.
- Add a second defaulted `LineMetricsSource` requirement
  `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` for the end-exclusive primitive, with
  the generic binary search as its default.
- Extract one shared internal monotone-search helper for the end-exclusive
  search, used by both the new default hook and `compute`'s
  `firstLineTopAtOrAbove`, so they cannot drift on the `>=` boundary convention.
- Override the new requirement in `BalancedTreeLineMetrics` with a native
  subtree-sum descent, making the balanced-tree visible-end search one O(log N)
  walk.
- Route `compute`'s visible-end search through the new hook (after its
  `target >= totalHeight` edge guard), forwarding the existing `lowerBound`
  (= visible start) narrowing hint to the hook so fallback O(log N) providers
  keep their current probe count.
- Add core tests proving both compute searches dispatch to native hooks and that
  the new default remains logarithmic; add a compute-equivalence oracle.
- Add reference-provider tests proving the native end-exclusive search matches a
  `PrefixSumLineMetrics` oracle across boundaries and after mutations, and that
  its visit count stays logarithmic.
- Update durable docs that describe `compute` as binary-search-only.

## Goals

- Make `BalancedTreeLineMetrics` `compute` calls fully O(log N) wall-clock per
  call (both visible start and visible end), using the provider's existing
  subtree height sums directly.
- Preserve `ViewportVirtualizer.compute(_:metrics:) -> ViewportComputation` and
  all `VirtualRange`, clamp/`isAtTop`/`isAtBottom`, empty-document, and failure
  semantics exactly.
- Keep the generic fallback O(log N) `offset(ofLine:)` probes and O(1) core
  memory for non-native providers.
- Keep existing `LineMetricsSource` conformers source-compatible through a
  default implementation.
- Keep `TextEngineCore` Foundation-free, Embedded-compatible, and
  zero-dependency.
- Prove behavior structurally against an oracle rather than relying on timing
  deltas.

## Non-Goals

- No new or changed public query API, `ViewportComputation` shape, `VirtualRange`
  shape, or `ViewportError` case.
- No geometry-bearing vertical query, within-line fraction, y span, or height in
  the result (that is the separate Option C direction).
- No horizontal axis, wrapping, visual-row model, or x/y point query.
- No native override for `UniformLineMetrics`/`PrefixSumLineMetrics`; they keep
  the binary-search fallback for both primitives (Slice 29 precedent - a
  closed-form override risks a one-line floating-point disagreement at exact
  boundaries and is a separate verified slice).
- No new benchmark mode and no new blocking gate. No budget retuning and no
  Linux-native budget re-baseline.
- No `lineAt` behavior change.
- No hosted WASM policy change.

## Decisions

### Decision 1 - Route visible start through the existing Slice 29 hook

`compute`'s visible-start search is "largest `i` with `offset(ofLine: i) <=
target`", which is exactly the line-containing-y primitive Slice 29 shipped.
`firstLineTopAtOrBelow` keeps its `target >= totalHeight -> lineCount` edge guard
(which `compute` needs and the hook never hits) and, for the in-range case, calls
`metrics.lineIndex(containingOffset: target)` instead of `binarySearchLineIndex`
directly.

This is safe because by the time `firstLineTopAtOrBelow` runs, `compute` has
already established the hook's documented preconditions: `lineCount > 0`,
`offset(ofLine: 0) == 0`, and (post-edge-guard) `target` finite in
`[0, offset(ofLine: lineCount))`. `effectiveOffsetY` is clamped to
`[0, maxOffsetY]` with `maxOffsetY = max(0, totalHeight - viewportHeight)`, so it
can equal `totalHeight` only when `viewportHeight == 0`; that case is caught by
the `>= totalHeight` guard and returns `lineCount` before the hook is reached.

No new API is needed for visible start: it reuses the Slice 29 requirement.

### Decision 2 - Add a defaulted end-exclusive prefix-search requirement (A1)

`LineMetricsSource` gains a second defaulted requirement, declared **in the
protocol body** (not only in an extension) so a generic caller constrained to
`LineMetricsSource` - which is exactly `compute<Metrics: LineMetricsSource>` -
dispatches through the witness table and reaches a conformer's override. This is
the load-bearing Slice 29 lesson; declaring it only in an extension would
statically bind `compute` to the default and silently bypass the balanced-tree
override.

```swift
public protocol LineMetricsSource {
    var lineCount: Int { get }
    func offset(ofLine index: Int) -> Double
    func lineIndex(containingOffset y: Double) -> Int          // Slice 29

    func firstLineIndex(withOffsetAtOrAbove y: Double,         // Slice 30
                        startingAtLine lowerBound: Int) -> Int
}
```

Semantic shape of the new requirement:

- Preconditions: `lineCount > 0`; `offset(ofLine: 0) == 0`; `y` is finite and in
  `[0, offset(ofLine: lineCount))` for the same stable metrics snapshot;
  `0 <= lowerBound <= lineCount` and `lowerBound` is a valid lower bound on the
  answer (`offset(ofLine: lowerBound) <= y`), so narrowing the search to
  `[lowerBound, lineCount]` cannot skip the true answer.
- Return: the smallest line index `i` in `0...lineCount` such that
  `offset(ofLine: i) >= y` (the first line whose top is at or above `y`,
  end-exclusive). The result is in `lowerBound...lineCount`; it equals
  `lineCount` when `y` lies in the last line's interior
  (`y > offset(ofLine: lineCount - 1)`).
- `lowerBound` is a correctness-preserving optimization hint, not a behavioral
  input: the true answer is provably `>= lowerBound`, so an override is free to
  ignore the hint and still return the same index (the balanced-tree native
  descent does exactly that - see Decision 4). Fallback providers use it to
  narrow the binary search.
- It does not validate inputs, clamp edges, or return a viewport type. Public
  validation stays centralized in `compute`.

The default implementation calls one shared internal monotone-search helper
(Decision 3). Rationale for a defaulted requirement over alternatives mirrors
Slice 29: a separate opt-in protocol would leave generic `compute` on the
fallback without runtime casts; a provider-only method would not improve the core
query; a defaulted requirement lets `compute` dispatch through the witness table
with no special casing.

Why A1 (a second native primitive) over A2 (derive visible end from the Slice 29
primitive plus an `offset` probe and a `+1`-unless-exact adjustment): A1 is fewer
tree descents per `compute` (2 vs 3), keeps the exact-boundary reasoning inside
the provider's native walk where Slice 29 already proved that pattern, and keeps
`compute` free of a floating-point equality check. A2 would add no API but moves
boundary fragility into the core and costs an extra descent; A1 was selected.

### Decision 3 - Extract one shared end-exclusive monotone-search helper

Mirror the Slice 29 `binarySearchLineIndex` extraction. Lift the binary-search
loop out of `compute`'s `firstLineTopAtOrAbove` into one internal free function -
`firstLineIndexAtOrAbove(offset:metrics:lowerBound:lineCount:)` - used by
**both** the new default protocol hook and `compute`'s `firstLineTopAtOrAbove`
wrapper. This makes the fallback `compute` path and the default hook share a
single `>=` boundary convention so they cannot drift.

The `lowerBound` (= visible start) narrowing is **preserved**, carried as the
hint argument on the new primitive (Decision 2). This is a correction to the
first-draft design, which proposed dropping `lowerBound` for a "pure function of
`y`" primitive on the mistaken premise that the loss was "at most one extra
comparison." That premise is wrong: narrowing the visible-end binary search from
`[0, lineCount - 1]` to `[visibleStart, lineCount - 1]` removes up to
`log2(lineCount) - log2(lineCount - visibleStart)` iterations - **up to O(log N)
fewer `offset(ofLine:)` probes** at deep scroll, where the visible window is a
small slice near the document end. For a fallback provider whose `offset(ofLine:)`
is itself O(log N) - which `FenwickLineMetrics` is - that is up to O(log^2 N)
extra work per `compute`, on the **blocking** `--variable-height-mutation --gate`
(`swift-ci.yml:98`), whose benchmark drives `compute` over `FenwickLineMetrics`
(`VariableHeightMutationBenchmark.swift:39`). The original variable-height design
introduced this narrowing precisely to remove those redundant O(log N) probes for
O(log N) providers, so dropping it would regress a deliberately-optimized,
gate-protected path.

Preserving `lowerBound` as a hint keeps fallback providers
(`Uniform`/`PrefixSum`/`Fenwick`) at their exact current probe count - zero gate
regression - while the balanced-tree override ignores the hint (its native
descent is already a single root-to-line O(log N) walk whose result is
provably `>= lowerBound`). Verification still runs `--variable-height --gate`
(`PrefixSumLineMetrics`, fallback) and `--variable-height-mutation --gate`
(`FenwickLineMetrics`, fallback) as the guards that the routing change does not
regress either fallback path.

### Decision 4 - Implement balanced-tree end-exclusive search as one descent

`BalancedTreeLineMetrics` overrides the new requirement with a non-mutating,
iterative subtree-sum descent, parallel to the Slice 29
`lineIndexAndVisitCount`, with the boundary rule flipped to end-exclusive. The
override accepts the `lowerBound` hint and **ignores** it: the descent is already
a single root-to-line O(log N) walk, and its global result is provably
`>= lowerBound` (Decision 2), so narrowing would not change the answer or the
asymptotics. The walk:

- Track the current node, the accumulated in-order base index, and the
  accumulated absolute top of the current subtree (`baseOffset`).
- Compute `leftSum`, `leftCount`, and the current node's absolute top
  `nodeTop = baseOffset + leftSum`. If `y < nodeTop`, descend left.
- If `y == nodeTop`, `y` is exactly this line's top -> return
  `baseIndex + leftCount` (this line).
- Compute `nodeBottom = baseOffset + (leftSum + node.height)`. If
  `y <= nodeBottom`, `y` is inside this line or exactly at its bottom/top of the
  next line -> return `baseIndex + leftCount + 1`.
- Otherwise advance `baseOffset = nodeBottom`, advance `baseIndex` by
  `leftCount + 1`, and descend right.

The exact-boundary check compares `y` to the absolute node top rather than to a
subtractive remainder. That keeps the native path bit-consistent with
`offset(ofLine:)` for ordinary fractional heights: both paths accumulate the same
subtree sums in the same shape for a tree-produced line top. The native and
fallback paths therefore return identical indices at exact tops and inside line
spans. For valid in-range `y` the containing-line case always fires before the
walk exhausts (a trailing `preconditionFailure` guards the impossible exhaustion,
matching Slice 29). It reuses `nodeSum`/`nodeCount`, allocates nothing, does not
mutate the tree, does not add core-owned memory, and does not touch
`lastMutationNodeVisits`. An internal `...AndVisitCount` variant exposes the
visit count for white-box tests only (reached via `@testable import`; not public
API).

### Decision 5 - Reuse the existing gates; prove with an oracle and one-off timing

No new benchmark mode and no new blocking gate. The existing
`--structural-mutation --gate` and `--bulk-structural-mutation --gate` already
drive `compute` over a `BalancedTreeLineMetrics` provider and remain the
regression guard for the native path. Their measurements combine mutation and
recompute, so they do not isolate the compute speedup; that is accepted for this
slice. The fallback `compute` paths are guarded by `--variable-height --gate`
(`PrefixSumLineMetrics`) and `--variable-height-mutation --gate`
(`FenwickLineMetrics`), which must stay green under the routing change and the
preserved `lowerBound` narrowing (Decision 3).

Correctness is proven structurally:

- a new core compute-equivalence oracle test: `compute` over
  `BalancedTreeLineMetrics` returns the same `VirtualRange` (and `isAtTop` /
  `isAtBottom`) as `compute` over a `PrefixSumLineMetrics` oracle built from the
  same heights, across many scroll offsets (top, bottom, interior, exact line
  boundaries, fractional offsets) and viewport heights;
- the reference-provider oracle and visit-count tests for the native
  end-exclusive search (Testing Strategy below).

The speedup is recorded as a one-off observation in the verification record
(compute over a balanced-tree provider, before vs after, at representative
sizes), not as a new permanent benchmark and not as the only proof of
correctness.

### Decision 6 - Keep `compute`'s edge-guard wrappers

`compute` keeps its two private wrapper functions, `firstLineTopAtOrBelow` and
`firstLineTopAtOrAbove`, as thin guards that handle the document-end case the
provider primitives are not asked about (`target >= totalHeight -> lineCount`)
and then delegate to the dispatched primitives. `firstLineTopAtOrAbove` keeps its
`lowerBound` (= visible start) parameter and forwards it as the new hook's hint
argument (Decision 3). Keeping the wrappers documents the `>= totalHeight` clamp
at the call site and keeps `compute`'s body otherwise unchanged (same validation
ladder, clamp, and buffered-range assembly).

## Testing Strategy

### Core Tests (`Tests/TextEngineCoreTests`)

- A custom `LineMetricsSource` that overrides `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`
  and counts calls: assert `compute` calls the native hook for the in-range
  visible-end search exactly once, and (with a spy that also overrides
  `lineIndex(containingOffset:)`) that `compute` dispatches **both** boundary
  searches through the native hooks after the expected validation probes. This is
  the witness-table dispatch regression guard for `compute`.
- A metrics type that does NOT override the new requirement, asserting the
  default `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` remains logarithmic (probe
  count) and that the document-end / empty / failure paths perform the expected
  probe envelope.
- Compute-equivalence oracle: `compute` over `BalancedTreeLineMetrics` equals
  `compute` over a `PrefixSumLineMetrics` oracle from the same heights across a
  sweep of scroll offsets (including exact line-top and line-end boundaries and
  fractional offsets), viewport heights (including 0 and full-document), and
  overscan values. Assert equal `VirtualRange`, `isAtTop`, and `isAtBottom`.
- Existing `compute` tests and the fixed-vs-variable equivalence oracle continue
  to pass with no expectation changes.

### Reference Provider Tests (`Tests/TextEngineReferenceProvidersTests`)

- Native `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)` equals a `PrefixSumLineMetrics`
  oracle over: `y` at the exact top of selected lines (boundary -> that line);
  `y` inside selected lines (-> next line); `y` one representable step before a
  boundary where practical; the first and last lines; and `y` in the last line's
  interior (-> `lineCount`).
- The native end-exclusive search still matches a fresh prefix-sum oracle after
  `setHeight`, `insertLine`, `removeLine`, `insertLines`, and `removeLines`.
- A test-only internal `...AndVisitCount` helper returns the descent visit count
  so tests can assert the walk stays logarithmic (<= c * (floor(log2 N) + 1))
  across 1k / 100k / 1m sizes without exposing a new public diagnostic.

### Benchmark And Verification

The implementation plan should run and record:

- `swift test`
- `swift build -c release`
- `swift run -c release ViewportBenchmarks -- --gate`
- `swift run -c release ViewportBenchmarks -- --variable-height --gate`
  (`PrefixSumLineMetrics` fallback path; must stay green under the routing change)
- `swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate`
  (`FenwickLineMetrics` fallback path - the O(log N)-`offset` provider whose
  probe count the preserved `lowerBound` narrowing protects; must stay green)
- `swift run -c release ViewportBenchmarks -- --structural-mutation --gate`
- `swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate`
- `swift run -c release ViewportBenchmarks -- --line-query --gate`
  (proves `lineAt` is unaffected)
- `swift run -c release ViewportBenchmarks -- --memory-shape`
- `rg -n "Foundation" Sources/TextEngineCore`
- `rg -n "Foundation" Sources/TextEngineReferenceProviders`
- `./.github/scripts/cross-target-compile.sh --self-test`
- `./.github/scripts/cross-target-compile.sh` for the public protocol/provider
  change, or a precise local blocker if the matching toolchain/SDK is
  unavailable
- a one-off compute-over-balanced-tree timing measurement (before vs after) for
  the verification record's observation section

Record gate checksums before and after; structural / bulk-structural / line-query
checksums must stay byte-identical (the native search returns the same indices).
If p95/p99 improve, record the numbers as observation, not as the only proof.

## Risks And Mitigations

### Adding a second requirement to a public protocol broadens the API

`LineMetricsSource` gains a second public member. As in Slice 29 this is
intentional: the core needs witness-table dispatch through the generic boundary.
The method is documented as a lower-level primitive with strict preconditions;
public callers keep using `compute`. Existing conformers stay source-compatible
through the default.

### Native and fallback end-exclusive boundary behavior could drift

The primary risk is exact-boundary drift between the generic `>=` binary search
and the tree descent's native boundary rule. Mitigation: the oracle tests include
exact line-top boundaries (-> that line), line-end / interior cases (-> next
line, including the last-line-interior -> `lineCount` case), and fractional
line-top regressions built from `tree.offset(ofLine:)`. The descent compares
against absolute `nodeTop`/`nodeBottom` values accumulated in the same shape as
`offset(ofLine:)`, instead of testing a subtractive remainder for zero.

### Fallback hook and `compute` could drift

If the default hook copied the binary-search loop while `compute` kept its own,
they could drift on the `>=` convention. Mitigation is structural (Decision 3):
one shared `firstLineIndexAtOrAbove` helper used by both.

### The preserved `lowerBound` hint must not change results

`lowerBound` is carried as an optimization hint, so a provider that uses it
(fallback binary search narrowed to `[lowerBound, lineCount]`) and one that
ignores it (balanced-tree native descent) must return the same index. This holds
because the true answer is provably `>= lowerBound` (`offset(ofLine: lowerBound)
<= y` by precondition), so narrowing cannot skip it. Mitigation: the
compute-equivalence oracle compares balanced-tree `compute` (ignores the hint)
against `PrefixSumLineMetrics` `compute` (uses the hint) across the scroll sweep,
and `--variable-height --gate` (`PrefixSumLineMetrics`) and
`--variable-height-mutation --gate` (`FenwickLineMetrics`) confirm both fallback
providers keep their probe count and stay green. Had `lowerBound` instead been
dropped, the fallback visible-end search would scan the full index range, costing
up to O(log N) extra `offset(ofLine:)` probes at deep scroll - up to O(log^2 N)
extra work for `FenwickLineMetrics` on its blocking gate; preserving the hint
avoids that regression.

### Embedded Swift compatibility must be verified

The design avoids runtime casts, Foundation, dependencies, and allocation in the
native search. Because it changes a public protocol and a provider
implementation, cross-target compile remains part of verification.

## Documentation Updates

After implementation, update durable docs that describe `compute` as
binary-search-only:

- `AGENTS.md` architecture paragraph: `compute`'s visible-start and visible-end
  searches use the provider-native prefix-search hooks when available
  (balanced-tree O(log N) per call), and the generic binary-search fallback
  otherwise.
- The Slice 30 verification record preserves the exact command output, benchmark
  rows, checksums, and any hosted run IDs, plus the one-off compute timing
  observation.

## Recommended Next Step

After this spec is reviewed and approved, write the Slice 30 implementation plan
with TDD steps:

1. Add failing core tests for the new default hook (logarithmic fallback) and for
   `compute` dispatch through both native hooks.
2. Add failing reference-provider oracle and visit-count tests for the
   balanced-tree end-exclusive native search.
3. Add the failing core compute-equivalence oracle test.
4. Add the defaulted `firstLineIndex(withOffsetAtOrAbove:startingAtLine:)`
   requirement, extract the shared `firstLineIndexAtOrAbove` helper, and wire
   `compute`'s visible-end search through the hook, forwarding the existing
   `lowerBound` (= visible start) narrowing hint.
5. Route `compute`'s visible-start search through the existing
   `lineIndex(containingOffset:)` hook.
6. Implement the balanced-tree end-exclusive native descent.
7. Update durable docs (`AGENTS.md`).
8. Run the full verification sweep and record evidence, including the one-off
   compute timing observation.
