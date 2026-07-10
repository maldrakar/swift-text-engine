# Slice 35 Post-Slice Review

Date: 2026-07-10

## Scope Reviewed

This review covers Slice 35: **geometry-bearing horizontal query**. It adds
`ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:)`, the geometry-bearing
companion to the Slice 33 `columnAt(x:inLine:metrics:)`. Where `columnAt` answers
*"which cell?"* (`columnIndex` + clamp), `columnGeometryAt` answers *"which cell,
and where within it?"* — it returns the located cell's box (`ColumnGeometry`:
index, left `x`, advance width), the within-cell `fractionInColumn`, and the same
clamp flag `columnAt` produces. This is the primitive a tap-to-caret / selection /
hit-test consumer needs on the horizontal axis, and it completes the horizontal
axis's *capability* pair (mapping + geometry) begun in Slice 33.

Slice 35 is the tight **27→31 mirror applied to the horizontal axis**: Slice 33
(`columnAt`, the mirror of Slice 27 `lineAt`) → Slice 34 (`--column-query` gate,
the mirror of Slice 28) → **Slice 35 (`columnGeometryAt`, the mirror of Slice 31
`lineGeometryAt`)**. It was the Slice 34 post-slice review's recommended **Option
C** (`columnGeometryAt` / caret-x, the tight 27→31 mirror), and the user's selected
direction at the C-vs-B-vs-D-vs-E product call that review surfaced — deepen the
horizontal axis toward caret geometry rather than take the larger 2D `pointAt` leap
(B), the horizontal native-descent cleanup (D), or standing infra (E). The user
further chose the **pure geometry-mirror shape** (box + fraction, caret snapping
left to the caller) over baking a caret-snap policy into the core.

Like the vertical geometry slice it mirrors (Slice 31's `lineGeometryAt`), this
slice is **functional and adds a local gate only**: it ships a
`--column-geometry-query` benchmark mode with a **local** `--gate` but does **not**
wire it into hosted CI. Promotion to a blocking hosted gate (the ninth) is deferred
to the recommended Slice 36, exactly as `--line-geometry-query` → Slice 32 and
`--column-query` → Slice 34. So this slice carries **CI-promotion debt** forward,
ending the debt-free handoff Slice 34 gave — by design, because a capability slice
that adds a new measurable path owes a promotion slice.

The change is deliberately **additive and composed**, touching no shared search or
provider path:

- Three new public types (`ColumnGeometry`, `ColumnGeometryQuery`,
  `ColumnGeometryLocation`) in `ViewportTypes.swift`. Unlike the vertical case —
  which *reused* the pre-existing `LineGeometry` box (already streamed by the
  geometry cursor) — there is **no** pre-existing horizontal cell-box type, so this
  slice mints `ColumnGeometry` (one more new type than `lineGeometryAt` needed). It
  **reuses** the existing `ColumnLocation.Clamp` flag rather than minting a parallel
  clamp enum.
- One new method `columnGeometryAt(x:inLine:metrics:)` in
  `HorizontalPositionQuery.swift`, which **delegates to `columnAt`** for validation,
  the located index, and the clamp — so index/clamp **parity with `columnAt` holds
  by construction** — then reads two `columnOffset(inLine:column:)` probes (`i`,
  `i+1`) to build the box and computes the fraction.
- No change to `columnAt`, the `LineHorizontalMetricsSource` protocol, `ColumnQuery`,
  or any reference provider. The only provider-file touch is a one-line doc-comment
  update to the `columnOffset(inLine:column:)` stability precondition (adding
  `columnGeometryAt` to the enumerated operations) — the identical update Slice 31
  made to `offset(ofLine:)` when it added `lineGeometryAt`.

The slice was delivered through **two** PRs, both now merged:

- PR #71 (`slice-35-horizontal-geometry-query`), title *"Slice 35: horizontal
  geometry query (columnGeometryAt)"*, verified head
  `a1ef9799a400847de74995c7af727e829c210865` (`a1ef979`), merged to `main` as
  `5da380b64308aae1d049e9f4a7bce36a578d3144` (`5da380b`) by `maldrakar` at
  2026-07-08T16:01:32Z — the three types, the method, the doc-comment update, the
  benchmark mode + local gate, the tests, the doc updates, and the verification
  record's local + PR-head sections (with the `Hosted Proof` section left as an
  explicit `Pending` placeholder).
- PR #72 (`slice-35-post-merge-verification`), title *"Slice 35: record post-merge
  hosted proof for columnGeometryAt"*, merged as
  `eff6bf25ad6a5c9f8d234c391f1bf9ab134f6686` (`eff6bf2`, current `main` HEAD) by
  `maldrakar` at 2026-07-10T15:31:22Z — the docs-only follow-up (`0e788ae`) that
  filled the verification record's `Hosted Proof` section with the real merged-code
  push run and final PR-head run.

**Both PRs are merged at review time**, so `main`'s verification record carries real
hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-07-07-horizontal-geometry-query-design.md`
- `docs/superpowers/plans/2026-07-07-horizontal-geometry-query.md`
- `docs/superpowers/verification/2026-07-07-horizontal-geometry-query.md`
- `docs/superpowers/reviews/2026-07-07-slice-34-post-slice-review.md`,
  `docs/superpowers/reviews/2026-07-02-slice-31-post-slice-review.md` (the vertical
  mirror)
- `Sources/TextEngineCore/HorizontalPositionQuery.swift`,
  `Sources/TextEngineCore/ViewportTypes.swift`,
  `Sources/TextEngineCore/LineHorizontalMetricsSource.swift`
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`,
  `Sources/ViewportBenchmarks/BenchmarkProgram.swift`,
  `Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift`,
  `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- `Tests/TextEngineCoreTests/ColumnGeometryAtTests.swift`,
  `Tests/TextEngineCoreTests/ColumnGeometryAtQueryCountTests.swift`,
  `Tests/TextEngineCoreTests/ColumnGeometryAtEquivalenceTests.swift`,
  `Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift`
- `AGENTS.md`
- PR #71 / #72 metadata, hosted run evidence (step-level conclusions), merge
  parentage, and the merged Slice 35 diff

The reviewed Slice 35 range (PR #70 review merge → current `main` HEAD), excluding
this review document itself, is:

```text
60e2c14..eff6bf2
```

`git merge-base 60e2c14 eff6bf2` returns `60e2c14`, confirming the Slice 34 review
merge (PR #70, `60e2c14`) is a clean ancestor and the range captures exactly the
Slice 35 work. Merge parentage confirmed via `git rev-list --parents`: `5da380b`
(PR #71)'s parents are the base `60e2c14` and the verified PR head `a1ef979`
(`5da380b^2 == a1ef979`); `eff6bf2` (PR #72) merges the post-merge-proof commit
`0e788ae` onto `5da380b` (`eff6bf2^2 == 0e788ae`). A fresh name-only diff confirms
the range touches `Sources/TextEngineCore` (three files),
`Sources/ViewportBenchmarks` (four files), `Tests/**` (four files), `AGENTS.md`, and
`docs/**` — it does **not** touch `Sources/TextEngineReferenceProviders` provider
source, `.github/workflows/**`, or `Package.swift`
(`git diff --name-only 60e2c14..eff6bf2 -- Package.swift .github` is empty; the only
`Tests/TextEngineReferenceProvidersTests` file is a new test, not a provider change).

## Product Brief Alignment

The brief (`docs/initial-project-brief.md`) wants a headless
layout/virtualization core that supports realistic editing/scrolling of 100k+ line /
>10 MB documents, stays Foundation-free and Embedded-compatible, keeps core-owned
memory sub-linear in document size, compiles for iOS and WASM without source changes,
and blocks merge on benchmark regression.

Slice 33 introduced the x → cell mapping `columnAt` and **explicitly deferred**
geometry — its result was `columnIndex` + clamp only, with the follow-up named
precisely (Decision 6: "a future geometry-bearing companion (`columnGeometryAt`, the
`lineGeometryAt` analog) — added as a **new method / result type**"). Slice 34
completed the horizontal-query *regression-protection* step (`--column-query` became
the eighth blocking gate — the first for the horizontal axis), and the Slice 34
review found the horizontal axis at the exact point the vertical axis occupied after
Slice 28 (mapping query + gate, no geometry, not yet asymptotically optimal), then
handed off to a genuine product call.

Slice 35 executes exactly the deferred Slice 33 follow-up and the Slice 34-recommended
Option C: it surfaces the geometry that `columnAt` already locates, as the
authoritative companion query, so a tap-to-caret consumer no longer re-implements the
box-rebuild + within-cell-fraction + clamp conventions the core owns. This is the same
duplication Slice 31 removed on the vertical axis — the identical treatment applied
horizontally. It honors every hard constraint: the core stays Foundation-free (both
scans empty), no dependency is added, the query adds **no** core-owned memory (O(1)
core memory preserved — a constant number of `columnOffset(inLine:column:)` probes on
top of `columnAt`), and the additive public-API change is cross-target verified for
iOS (blocking) and WASM (observational).

Because the query **composes over `columnAt`** rather than adding a new search, its
per-provider cost class is exactly `columnAt`'s: O(log M) for both shipped providers
(`UniformColumnMetrics`, `PrefixSumColumnMetrics` both answer `columnOffset` in O(1)
and use the generic binary-search `columnIndex`). The two extra geometry probes are a
constant factor, never a log factor. Here the horizontal story is **simpler than the
vertical one**: the vertical axis had a `BalancedTreeLineMetrics` native O(log N)
descent and a `FenwickLineMetrics` at O(log²N) to enumerate; the horizontal axis has
neither — both shipped providers sit at a uniform O(log M).

The brief's "benchmark gates block merge" principle is *not* yet extended to this
path — the new gate is local-only this slice — which is exactly the CI-promotion debt
this slice hands to Slice 36, mirroring `lineGeometryAt` → Slice 32.

## Delivered Design

Merged Slice 35 diff, Sources/Tests only (`60e2c14..eff6bf2`):

```text
 Sources/TextEngineCore/HorizontalPositionQuery.swift        |  38 ++
 Sources/TextEngineCore/LineHorizontalMetricsSource.swift    |   2 +-
 Sources/TextEngineCore/ViewportTypes.swift                  |  35 ++
 Sources/ViewportBenchmarks/BenchmarkOptions.swift           |  11 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift           |   2 +
 Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift | 154 ++
 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift        |   2 +
 Tests/TextEngineCoreTests/ColumnGeometryAtTests.swift       | 178 ++
 Tests/TextEngineCoreTests/ColumnGeometryAtQueryCountTests.swift | 126 ++
 Tests/TextEngineCoreTests/ColumnGeometryAtEquivalenceTests.swift | 81 ++
 Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift | 28 ++
 11 files changed, 655 insertions(+), 2 deletions(-)
```

(Plus the spec, plan, and verification docs — `docs/superpowers/**` — and the
`AGENTS.md` update. No `Package.swift` change.)

### The three new public types (Decision 1)

`ViewportTypes.swift` gains a cell-box struct, a three-case result enum mirroring
`ColumnQuery`'s located/empty/failure discipline, and a location struct that **reuses**
the existing `ColumnLocation.Clamp` flag:

```swift
public struct ColumnGeometry: Equatable {
    public let columnIndex: Int
    public let x: Double        // cell left edge (columnOffset of columnIndex)
    public let width: Double    // advance width (columnOffset(i+1) - columnOffset(i))
}

public enum ColumnGeometryQuery: Equatable {
    case geometry(ColumnGeometryLocation) // a real cell was located, with its box
    case empty                            // blank line: columnCount(inLine:) == 0
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct ColumnGeometryLocation: Equatable {
    public let geometry: ColumnGeometry      // the located cell's box
    public let fractionInColumn: Double       // 0.0 left / (x-left)/width in-range / 1.0 right
    public let clamp: ColumnLocation.Clamp    // reused, not duplicated
}
```

This is the right shape. `ColumnGeometry` mirrors `LineGeometry{lineIndex, y, height}`
field-for-field (`columnIndex`↔`lineIndex`, `x`↔`y`, `width`↔`height`), and the clamp
reuses `ColumnLocation.Clamp`, so `columnGeometryAt` and `columnAt` speak one vocabulary
for "a cell's box" and "edge clamp state." The `.empty` / `.failure` cases parallel
`ColumnQuery` exactly, so the two query results are switched the same way and validation
outcomes map 1:1. Centralizing `fractionInColumn` in the core is the point: the
clamp-edge fraction contract lives in one place instead of every caller re-deriving
`(x - left) / width` and re-deciding the edges — from which a caller derives the snapped
caret (`caretColumn = fraction < 0.5 ? columnIndex : columnIndex + 1`) under its own
affinity policy. It is **additive and non-breaking** — a new method and new types, not a
new `ColumnQuery` case (which would be source-breaking for client `switch`es), honoring
the Slice 27/31/33 extension rule.

The one structural difference from the vertical mirror is honest and correct: the
vertical axis had a pre-existing `LineGeometry` box to reuse, so Slice 31 added only
*two* types; the horizontal axis had no cell-box type, so Slice 35 adds *three*. The
spec's Risks section names this explicitly rather than hiding it.

### `columnGeometryAt` composes over `columnAt` — parity by construction (Decisions 2, 3)

`HorizontalPositionQuery.swift` gains `columnGeometryAt` right next to `columnAt`, a
single generic over `LineHorizontalMetricsSource` with no fixed-height overload (parity
with `columnAt`; `inLine` stays a documented precondition, the source has no `lineCount`):

```swift
switch columnAt(x: x, inLine: line, metrics: metrics) {
case let .failure(error): return .failure(error)   // validation single-sourced
case .empty:              return .empty             // blank line, no geometry
case let .column(location):
    let left  = metrics.columnOffset(inLine: line, column: location.columnIndex)
    let right = metrics.columnOffset(inLine: line, column: location.columnIndex + 1)
    let box   = ColumnGeometry(columnIndex: location.columnIndex, x: left, width: right - left)
    let fraction: Double
    switch location.clamp {
    case .clampedToLeft:  fraction = 0.0
    case .clampedToRight: fraction = 1.0
    case .inRange:        fraction = (x - left) / box.width
    }
    return .geometry(ColumnGeometryLocation(geometry: box, fractionInColumn: fraction, clamp: location.clamp))
}
```

I traced the whole surface:

- **Parity by construction.** Index, clamp, and the entire validation ladder
  (`negativeColumnCount`, `nonFiniteValue`, the `columnOffset(_, 0) != 0` contract
  probe and the width-`<= 0`/non-finite `invalidColumnMetrics` probe) come straight
  from `columnAt`; `columnGeometryAt` structurally *cannot* disagree with `columnAt`
  on which cell or which clamp. That collapses the correctness burden to the *geometry*
  only, which the oracles then pin.
- **The fraction contract matches Decision 3 exactly.** `clampedToLeft` → `0.0` (a tap
  left of the line caret-positions at the very left of cell 0), `clampedToRight` →
  `1.0` (a tap past the right edge → very right of the last cell), `inRange` → the exact
  arithmetic ratio `(x - left) / width` in `[0, 1)` by the half-open
  `[columnOffset(i), columnOffset(i+1))` contract, `0.0` at an exact cell left edge.
  `1.0` is only ever a clamp sentinel for in-range queries (modulo the documented
  floating-point upper-edge caveat).
- **`box.width = right - left` is finite and strictly positive** for any valid provider
  (`columnOffset` is a strictly increasing chain over `0..<columnCount`), so the division
  has no zero-width special case, and `columnAt`'s width `<= 0`/non-finite guard already
  rejects a degenerate *total* width before geometry is computed.
- **No new search, no provider change.** The located index already came from the (default
  binary-search, provider-overridable) `columnIndex(containingOffset:inLine:)` inside
  `columnAt`; the two extra `columnOffset(inLine:column:)` probes reuse the existing offset
  contract. This is a conscious accept of two extra probes (Decision 4) rather than
  threading a native `(index, left, right)` one-walk descent — that is a deferred Future
  Slice.

This is the exact mirror of the vertical Decision 3 (`lineGeometryAt`), with
`x`/`left`/`width`/`lineWidth`/left-right substituted for `y`/`top`/`height`/
`totalHeight`/top-bottom.

### Cost envelope (Decision 4) is exactly `columnAt`'s

The query issues `columnAt`'s `columnOffset(inLine:column:)` queries plus **two** more on
the located branch — a constant number of probes plus `columnAt`'s single index search —
so query count stays O(log M) and core memory O(1). The two geometry probes are a constant
factor, so the per-provider asymptotic class equals `columnAt`'s: O(log M) for both shipped
providers. The spec is honest that ~1 of the 2 geometry probes re-reads a value `columnAt`
already computed and discarded (composing over the *public* `columnAt`, which returns only
`(columnIndex, clamp)`, forces the re-read); it is accepted here because for both providers
`columnOffset` is O(1), so the re-read is unmeasurable — strictly cheaper than the vertical
axis's re-reads, which were O(log N) balanced-tree descents. This is verified structurally by
the query-count tests, not just asserted (below).

### Benchmark mode + local gate (Decision 5)

`BenchmarkOptions.swift` adds the `.columnGeometryQuery` mode
(`outputName = "column_geometry_query"`), the `--column-geometry-query` flag with its
mode-exclusivity guard, and adds `.columnGeometryQuery` to the `--gate`-valid set (it stays
rejected with `--range-only`/`--memory-shape`/`--memory-observation`).
`ColumnGeometryQueryBenchmark.swift` (new, modeled on `ColumnQueryBenchmark.swift`) drives
the five `--column-query` scenarios exactly — three `uniform` (1k/100k/1m) and two
`prefixsum` (100k/1m, the realistic proportional-advance path and the **watch scenario** at
the largest cell count) — with a deterministic `x` spanning in-range and both out-of-range
clamp branches, folding `geometry.columnIndex`, an integer clamp encoding, and a quantized
`fractionInColumn` into a determinism checksum. There is no balanced-tree/Fenwick scenario
because the horizontal axis has no such provider — correctly simpler than the vertical suite.

### Docs

`AGENTS.md`'s architecture paragraph now describes `columnGeometryAt` as the
geometry-bearing companion to `columnAt` (box + within-cell fraction + clamp, composed over
`columnAt` + two `columnOffset` probes, O(1) core memory, per-provider cost class equal to
`columnAt`'s, caret snapping a caller concern), and the Commands / benchmark-flags lists gain
the `--column-geometry-query` / `--column-geometry-query --gate` entries — described, per the
Slice 33 precedent, as the **local (not-yet-CI)** gate. The CI section is unchanged because
the workflow is unchanged (Decision 5). The `LineHorizontalMetricsSource.columnOffset`
stability precondition adds `columnGeometryAt` to the enumerated operations that must observe
one consistent snapshot — the identical update Slice 31 made to `offset(ofLine:)`.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `eff6bf2`)

- `git diff --name-only 60e2c14..eff6bf2 -- Package.swift .github` → **empty** (no manifest
  or workflow surface touched); provider source untouched (the only
  `TextEngineReferenceProvidersTests` change is a new test).
- `git diff --check 60e2c14..eff6bf2 -- Sources Tests` → no output, exit `0` (no whitespace
  errors).
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `swift build -c release` → `Build complete!` (exit 0).
- `swift test` → **213 tests, 0 failures**, plus the expected empty Swift Testing harness
  line (`0 tests in 0 suites`). Up from 189 at the Slice 34 baseline — the twenty-four new
  tests landed (`ColumnGeometryAtTests`, `ColumnGeometryAtQueryCountTests`,
  `ColumnGeometryAtEquivalenceTests`, and the `PrefixSumColumnMetrics` reference test).
- `swift run -c release ViewportBenchmarks -- --column-geometry-query --gate` → all five
  scenarios `gate=pass`, 0 failures; the five checksums are byte-identical to the
  verification record (`160641440000`, `267505512960`, `799841600000`, `223985600000`,
  `839521520640`), and every scenario lands ~1,500–5,700× under budget locally.
- `swift run -c release ViewportBenchmarks -- --column-query --gate` and
  `--line-geometry-query --gate` → all five scenarios each `gate=pass`; all checksums
  byte-identical to the record — confirming this slice touched no shared search/provider
  path (`columnAt` and `lineGeometryAt` are unaffected). The verification doc's full
  32-checksum identity table across all eight existing gates is consistent with these
  spot checks.

A telling cross-check on the determinism checksums: the three `uniform_*`
`--column-geometry-query` checksums (`160641440000`, `267505512960`, `799841600000`) are
**identical** to the three `uniform_*` `--line-geometry-query` checksums — the two geometry
queries fold `index + clamp + quantized fraction` identically, and for uniform metrics the
horizontal and vertical geometry coincide, so this equality is the expected mirror, not an
accident. The `prefixsum_1m` checksum (`839521520640`) correctly *differs* from the
`--column-query` `prefixsum_1m` checksum (`639841560320`) — geometry adds the fraction
encoding the mapping query lacks.

### The correctness payoff (the point of the slice)

The evidence is layered and structural, mirroring the Slice 31 oracle set:

1. **Structural uniform oracle (products, not quotients)** — over `UniformColumnMetrics`,
   picks exactly-representable widths (`[1.0, 10.0, 16.0, 12.5, 256.0]`) and column counts
   (including `columnCount == 1`), **builds each `x` from a product** over the width, and
   asserts the full `ColumnGeometryQuery`: left-clamp (`frac 0.0`, cell-0 box), exact cell
   lefts (`frac 0.0`, in-range), mid-cell (`frac 0.5`, in-range), and at/past the line width
   (`frac 1.0`, clamped-to-right, last-cell box). Because every `x` is a product over a
   representable width, the box `x`/`width` and the fraction are known exactly by
   construction — dodging the `floor(x/columnWidth)` boundary fragility the same way the
   Slice 33 `columnAt` oracle did.
2. **Index/clamp parity with `columnAt`** — sweeps an `x` set (clamps, exact lefts, interior)
   and asserts `columnGeometryAt(...).geometry.columnIndex == columnAt(...).columnIndex` and
   the clamp flags match, pinning the construction guarantee as a regression test.
3. **Reconstruction invariant** — for several *interior, non-half* in-range `x`, asserts
   `abs(geometry.x + fractionInColumn * geometry.width - x) <= eps`, i.e. the box + fraction
   round-trip back to the query `x`. This pins the Decision 3 relation
   `x == left + fractionInColumn * width` directly rather than by re-deriving the same ratio
   — a stronger check than the equivalence oracle's recompute.
4. **Reference-provider equivalence oracle** — over `PrefixSumColumnMetrics`, across an `x`
   sweep (left, right, interior, exact cell edges, fractional offsets, out-of-range
   left/right), asserts `columnGeometryAt(...).clamp == columnAt(...).clamp`, indices match,
   `geometry` equals the box rebuilt from that provider's own `columnOffset`, and
   `fractionInColumn` equals the offset-derived value under the Decision 3 contract. As the
   spec is careful to note, this is a **self-consistency** proof (there is only one variable
   horizontal provider so far; a second is the deferred Option D), and the genuinely
   *independent* check is the structural uniform oracle in (1).
5. **Query-count / envelope + native-dispatch order** — over `CountingColumnMetrics`, the
   per-path `columnOffset` counts match the Decision 4 table exactly: non-finite `x` → `0`
   probes, blank line → `1`, both clamp branches → `4`, in-range → `≤ 2 + (ceilLog2(M)+1) + 2`
   and `< 100` (proving no accidental linear scan and the O(log M)/O(1) envelope). The
   load-bearing one is the native-dispatch order test: over `NativeSearchColumnMetrics` with
   an ordered event log, an in-range `x = 31` produces exactly
   `[.offset(0,0), .offset(0,count), .native(0,31.0), .offset(0,i), .offset(0,i+1)]` —
   `columnAt`'s contract + width probes, its **native** index dispatch, then the two geometry
   probes, *in order*. This is the Slice 29/31 lesson applied: it directly exhibits that the
   composed query reuses `columnAt`'s index dispatch and does **not** silently fall back to a
   generic search or re-search redundantly.

### Fresh local column-geometry numbers (macOS arm64, this review)

| Scenario | p95 (ns) | Budget p95 | Headroom |
| --- | ---: | ---: | ---: |
| uniform_1k     | 17 | 30,000  | ~1,765× |
| uniform_100k   | 19 | 60,000  | ~3,158× |
| uniform_1m     | 23 | 120,000 | ~5,217× |
| prefixsum_100k | 42 | 60,000  | ~1,429× |
| prefixsum_1m   | 44 | 120,000 | ~2,727× |

Consistent with the verification record's macOS numbers (run-to-run noise aside); the timing
rows are non-reproducible, but the five deterministic checksums are byte-identical to the
record. Every scenario sits well over ~1,400× under budget locally, matching the shape of the
`--column-query` sibling plus the tiny constant cost of two extra O(1) `columnOffset` probes.
These budgets are macOS-calibrated and **local-only** until the Slice 36 promotion.

### Hosted runs (verified live via `gh`, at step-log level not just job conclusion)

Both runs re-verified via `gh` during this review — and, per the project's "a green job can
hide a dead `continue-on-error` step" lesson, checked at the **step** level, not just the job
conclusion:

- **PR #71 final-head run `28893267949`** (head `a1ef979`, event `pull_request`): conclusion
  `success`; all three required jobs `success` (Host tests and benchmark gate, iOS
  cross-target compile, WASM cross-target observation).
- **Post-merge push run `28956968583`** on merge commit `5da380b` (event `push`, branch
  `main`): conclusion `success`; all three required jobs `success`. In the host job, step #5
  `Complete docs-only PR` = `skipped` (correctly **not** docs-only — the merged change is
  source-bearing), steps #8–#15 — the pre-existing **eight** blocking latency gates
  (synthetic, variable-height, variable-height-mutation, structural-mutation,
  bulk-structural-mutation, line-query, line-geometry-query, column-query) — all `success`,
  step #16 `Run memory shape diagnostic` `success`, and step #18 `Observe realistic provider
  relative performance` correctly `skipped` on the `push` event. **This is the merged-code
  evidence anchor for Slice 35.** Merge parentage confirms `5da380b`'s second parent is
  `a1ef979`, so the proof anchors the actually-merged head.

Two step-level facts confirm Decision 5 directly: **there is no `Run column geometry query
benchmark gate` step** in either run's host job (the new gate is local-only this slice), and
**`columnGeometryAt` correctness is nonetheless enforced hosted** through step #7 `Run host
tests`, which executes the full 213-test suite including the new `ColumnGeometryAt*` suites and
the `PrefixSumColumnMetrics` reference oracle. PR #72 was a docs-only follow-up touching only
the verification record (`0e788ae`, a single file), so it legitimately took the trusted
docs-only path; the workflow YAML has not changed since `5da380b`, so run `28956968583` still
represents current `main`'s workflow behavior.

The cross-target self-test (`self_test=pass`) and the full local iOS device/simulator +
WASM/embedded-WASM compile (`blocking_failures=0 exit=0`) for both `TextEngineCore` and
`TextEngineReferenceProviders` are recorded in the verification doc against the additive
public-API change.

## Git History

Reviewed Slice 35 commits (PR #71 → #72):

```text
d3ce8b8 docs: add horizontal geometry query design
f5246f9 docs: refine slice 35 spec after review
835e570 docs: add slice 35 horizontal geometry query plan
00bef1d feat: add columnGeometryAt geometry-bearing horizontal query
a965227 test: pin columnGeometryAt query-count + native dispatch order
8e786b9 test: add columnGeometryAt structural uniform oracle + columnAt parity
1aec1a0 test: add columnGeometryAt PrefixSum reference equivalence
318cd7f feat: add --column-geometry-query benchmark mode with local gate
a366928 docs: document columnGeometryAt + --column-geometry-query local gate
a1ef979 docs: record slice 35 horizontal geometry query verification
5da380b Merge pull request #71 …
0e788ae docs: record slice 35 post-merge hosted proof
eff6bf2 Merge pull request #72 …
```

Clean, one-logical-step-per-commit with correct conventional-commit prefixes: spec → plan
precede code; the spec took **two rounds** (`d3ce8b8` add → `f5246f9` refine after review)
before the plan; the method lands as one `feat:` (`00bef1d`); the three test suites land as
separate `test:` commits (`a965227` query-count + native dispatch, `8e786b9` uniform oracle +
parity, `1aec1a0` reference equivalence) with the benchmark mode + local gate as its own
`feat:` (`318cd7f`); durable docs (`a366928`) and verification (`a1ef979`) are isolated. Note
the TDD ordering is honest: `00bef1d` (the method) precedes the test commits in the log, but
the plan is written failing-test-first and the verification records a green suite — the commit
grouping bundles the method with its immediately-following tests, one logical capability per
commit, which is within the project's convention. The PR head is `a1ef979`, exactly the head
the PR-head run `28893267949` tested — no post-head drift. The two-PR split (implementation +
local/PR-head proof, then post-merge proof) is the standard pattern.

## Code Review Findings

Reviewed across correctness, composition semantics, scope discipline, evidence integrity, and
the hard constraints.

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, the geometry is correct (product-built structural uniform oracle,
`columnAt`-parity test, reconstruction round-trip invariant, and a `PrefixSumColumnMetrics`
self-consistency oracle across an `x` sweep including both clamps), the composition reuses
`columnAt`'s index dispatch and takes exactly two ordered geometry probes (proven by the
event-log dispatch test), validation is single-sourced through `columnAt`, the scope is tight
(no shared search/provider path touched — 32 existing checksums byte-identical), and the
Foundation-free / zero-dependency / O(1)-core-memory invariants are intact and cross-target
verified.

### P2 / Production Readiness

None. The merged result is correct and proven green on merged code at step level
(`28956968583`), and the verification record carries **no evidence-accuracy defect**: at PR
#71's head (`a1ef979`), the `Hosted Proof` section was an explicit `## Hosted Proof — Pending`
placeholder (no stale-on-write run IDs against a still-moving head), and the real hosted run
IDs (`28893267949`, `28956968583`) were added only in the post-merge follow-up (PR #72,
`0e788ae`, a single-file docs-only change) once the final head was stable. The source-bearing
PR #71 was never described as taking the docs-only shortcut (the record documents that the
merged change is source-bearing and the docs-only step was skipped). Decision 4's requested
per-scenario headroom table is present for all five scenarios.

### P3 / Minor But Valid

**1. Located-case naming asymmetry — the horizontal mirror of the Slice 31 P3 #1.**
`ColumnGeometryQuery`'s located case is `.geometry`, while the sibling `ColumnQuery`'s is
`.column` (a caller switching both uses `.column(loc)` for one and `.geometry(loc)` for the
other). This is the exact horizontal twin of the vertical `.line` vs `.geometry` seam Slice 31
noted, and the same deliberate, defensible choice (the payload *is* geometry, `.geometry` reads
well at the call site), with `.empty` / `.failure` paralleling `ColumnQuery` exactly. It is in
fact *consistent across the two geometry queries* — a caller switching `lineGeometryAt` and
`columnGeometryAt` sees `.geometry` in both — so the asymmetry is only against the mapping
query, mirroring the vertical axis. Cosmetic; no action.

**2. `fractionInColumn` floating-point at the in-range upper edge (documented, accepted).**
For an in-range `x` extremely close to `right`, the exact ratio `(x - left) / width` may round
toward `1.0`, indistinguishable from the `clampedToRight` sentinel `1.0`. The spec documents and
accepts this (consistent with how the engine trusts the `columnOffset` contract elsewhere), and
a consumer that needs to disambiguate has the `clamp` flag. The exact vertical `lineGeometryAt`
posture (Slice 31 P3 #2). Not a defect.

**3. Non-monotone interior is contract-trusted (documented, accepted).** `columnAt` validates
only `columnOffset(_, 0) == 0` and the *total* `width > 0`; it never scans every interior offset
(that would break the O(log M) envelope). A contract-violating provider that is non-monotone
*in the interior* — two equal consecutive offsets on the located cell — yields
`geometry.width == 0`, so `fractionInColumn = (x - left) / 0` becomes NaN/inf, undetected. This
is the identical contract-trust posture the vertical `lineGeometryAt` takes toward
`height = bottom - top > 0`; defending it is impossible without an O(M) scan. The spec names it
explicitly rather than leaving it implicit. Accepted.

**4. Carried-forward provider costs / deferrals (documented Non-Goals / Future Slices).**
(a) The two extra `columnOffset` probes on the located branch are a constant factor; a
provider-native one-walk `(index, left, right)` hook (default = today's composed form), or a
protocol-free internal helper returning the already-computed offsets, would trim ~half the
re-reads — deferred. (b) Both shipped horizontal providers stay **fallback-bound**: they answer
the index search via the generic O(log M) `binarySearchColumnIndex`, so the uniform case pays an
O(log M) search where a closed form would be O(1) — the horizontal Option D (mirror of vertical
Slices 29/30), now measurable against this slice's and Slice 34's gates. Both are conscious,
documented deferrals, not gaps.

**5. Spec/implementation primitive-naming drift, still open (carried from Slice 25 P3 #3 /
Slice 26 / 28 / 32 / 34 P3).** The bulk-edits spec names the join primitive `join(_:_:)` while
the implementation ships `join3`/`join2`. Provider-doc hygiene unrelated to this slice; Slice 35
touches no provider source or the bulk-edits spec, so it is correctly **not** a Slice 35 defect —
but it remains an open item with no home slice yet. A one-line cross-reference in the bulk-edits
spec would retire it whenever a provider-touching slice next opens.

No P3 changes whether the merged result is correct.

## Risks And Gaps

### CI-promotion debt: the `--column-geometry-query` gate is local-only

This is the one governance follow-up, and it re-opens the debt Slice 34's debt-free handoff had
drained. The new gate enforces its macOS-calibrated budgets **locally** but is not wired into
`.github/workflows/swift-ci.yml`, so a `columnGeometryAt` latency regression would be caught
locally but would **not** block a merge until the gate is promoted. This is the established
functional → promotion rhythm (the eighth such pair before it: variable-height → 15,
variable-height-mutation → 21, structural-mutation → 24, bulk-structural-mutation → 26,
line-query → 28, line-geometry-query → 32, column-query → 34), and the recommended Slice 36
closes it — the horizontal mirror of `lineGeometryAt` → Slice 32. A capability slice that adds a
new measurable path owes a promotion slice; this is that debt, by design.

### Budgets are macOS-calibrated and local-only until promotion

Like every gate before CI promotion, the `--column-geometry-query` budgets are macOS-derived and
unenforced in hosted CI until Slice 36. Accepted, time-boxed gap.

### No isolated hosted guard for `columnGeometryAt`'s own probes/fraction path during the interim

Because the new gate is local-only and the query composes over `columnAt`, a *latency* regression
*inside* `columnGeometryAt`'s own probes/fraction path is not hosted-gated until Slice 36. Its
*correctness* is guarded by the merged unit + oracle tests (which the hosted host-tests step runs
in the 213-test suite), so this is a latency-only interim gap, not a correctness one — exactly
what Slice 36 exists to close.

### The horizontal axis is now geometry-bearing but still fallback-bound and not 2D-composed

With this slice the horizontal axis has *both* its mapping query (`columnAt`) *and* its geometry
query (`columnGeometryAt`) — matching the vertical axis's Slice 27 + Slice 31 pair. But it is
still **fallback-bound** (both providers use the generic `columnIndex` binary search; no native
O(1) closed form — the deferred Option D) and there is **no 2D composite** (`pointAt(x:y:)`)
combining the vertical and horizontal geometry primitives. Those are the horizontal axis's open
capability distance — and, notably, with **both** axes now geometry-bearing, the `pointAt` 2D
leap (Option B) is finally *unblocked*: it was waiting on horizontal geometry, which this slice
delivers.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative observation remains
PR-only `continue-on-error`; budgets remain macOS-derived; the `Main` ruleset keeps its
documented bypass-actor shape (the admin user can still bypass required checks). None were in
scope for Slice 35.

## Lessons For The Next Slice

1. **Composing a new query over an existing one buys parity for free — and shrinks the test
   surface to the delta.** Delegating `columnGeometryAt` to `columnAt` for validation/index/clamp
   meant index and clamp *cannot* drift, so the oracles only had to pin the geometry and fraction.
   This is the same lesson Slice 31 recorded on the vertical axis, now confirmed a second time on
   the horizontal one — the pattern generalizes. When a new capability is a strict superset of an
   existing query, compose over it.
2. **Prove native-dispatch reuse with an ordered event log, not just a count.** The dispatch-order
   test (`[.offset(0,0), .offset(0,count), .native(0,31.0), .offset(0,i), .offset(0,i+1)]`) is what
   makes "composes over `columnAt`'s index dispatch + exactly two ordered geometry probes" a *fact*
   rather than a claim — it would fail loudly if the composed query re-searched or fell back to the
   generic path. Reuse the ordered-event-log harness for any future composed/native query.
3. **Introduce a new box type only when none exists to reuse; reuse the clamp enum regardless.**
   The vertical axis reused `LineGeometry` (two new types); the horizontal axis had no cell-box
   type, so it minted `ColumnGeometry` (three) but still reused `ColumnLocation.Clamp`. Naming the
   extra type honestly in the spec's Risks (rather than pretending the mirror was exact) kept the
   surface accountable. Prefer extending shared vocabulary; add a type only for a genuinely new
   concept.
4. **The clean-evidence convention held again — for the ninth source/workflow-touching slice.**
   The recurring stale-on-write defect (recording PR-head proof against a still-moving head, or
   mis-classifying a source-bearing PR as docs-only) stayed absent: Slice 35 left an explicit
   `Pending` placeholder in PR #71, recorded the hosted proof only in the post-merge follow-up
   (PR #72) against the stable final head `a1ef979`, and documented PR #71 as source-bearing. This
   is the proven default; keep it.
5. **A capability slice owes a promotion slice; track which kind you are shipping.** Slice 34
   handed off debt-free (a governance slice reusing no new path); Slice 35 adds a new measurable
   path, so it ships a local gate and hands a promotion slice forward — re-opening the debt by
   design. Slice 36 is that promotion, exactly as Slice 32 followed Slice 31.

## Slice 36 Candidate Options

With Slice 35 the horizontal axis is now **geometry-bearing** (matching the vertical axis since
Slice 31), and this slice **re-opened CI-promotion debt** — so, unlike the debt-free Slice 34
handoff, Slice 36 has a natural, low-risk forced move available (close the debt) alongside the
richer capability options the now-geometry-bearing horizontal axis unlocks. The live options
(carried and re-anchored from the Slice 34 review):

### Option A: Promote `--column-geometry-query --gate` to a blocking hosted CI gate

Wire the local gate into `.github/workflows/swift-ci.yml` as the **ninth** blocking latency gate,
completing the functional → promotion pair, exactly as Slices 15 / 21 / 24 / 26 / 28 / 32 / 34
did for the prior seven modes and precisely mirroring `line-geometry-query` → Slice 32. Zero
Swift-source change (a pure CI/governance slice): add the gate step after the column-query gate,
confirm the macOS budgets fit hosted Linux (the one-shot PR-head run being that evidence, per the
established Decision-3 pattern), and verify the required-check contexts are unchanged. Retires
this slice's CI-promotion debt. The smallest, most obvious, lowest-risk next step, and the one
this slice was explicitly designed to hand off to.

### Option B: `pointAt(x:y:)` 2D composite (the product leap, now unblocked)

Compose this slice's horizontal `ColumnGeometryLocation` with the vertical `LineGeometryLocation`
into a single point → (line, cell) hit-test over both metrics sources. This is the biggest step
toward realistic click-to-caret / selection on large documents — and it is **newly unblocked**:
it was waiting on horizontal geometry, which Slice 35 delivers, so both axes are now
geometry-bearing. Largest design surface; needs a fresh brainstorm + spec (how the two independent
sources compose, the combined result/clamp shape). Reads most cleanly *after* Option A makes the
horizontal geometry latency contract hosted-blocking.

### Option D: horizontal native / closed-form `columnIndex` overrides (fallback-bound cleanup)

O(1) / native-prefix-search overrides of `columnIndex` for `UniformColumnMetrics` and
`PrefixSumColumnMetrics`, boundary-safe against the equivalence oracle — the horizontal mirror of
the vertical Slices 29/30 native-descent work. Retires the horizontal fallback-bound-provider
item and is now directly measurable against this slice's and Slice 34's hosted `--column-query`
gates. Small, clean; lower product value than B. A provider-native one-walk `(index, left, right)`
geometry hook (the constant-factor trim) is the adjacent optimization.

### Option E: standing infra (WASM blocking / Linux budget re-baseline)

Promote WASM cross-target from observational to blocking (gated on stable SDK provisioning), or
re-derive Linux-native budgets from the soon nine-gate-deep accumulated x86_64 evidence and retire
the macOS-calibration caveat. Standing hygiene; independent of the capability arc.

## Recommended Slice 36 Selection

Recommended Slice 36 is **Option A — promote `--column-geometry-query --gate` to a blocking hosted
CI gate.**

The reasoning: Slice 35 is a functional capability slice that shipped a new measurable path behind
a **local-only** gate, exactly the pattern each of the prior seven functional modes followed. Every
one of those was promoted in the very next governance slice (15, 21, 24, 26, 28, 32, 34), and the
Slice 35 spec/verification named this promotion as the recommended follow-up by design. It is the
smallest, lowest-risk, zero-Swift-change increment; it retires the one piece of governance debt this
slice re-opened; and it makes the `columnGeometryAt` latency contract hosted-blocking **before** any
follow-on (Option B's 2D `pointAt`, Option D's native descent) tries to optimize or build against it
— so the win is measured by a gate that actually blocks. Keeping functional work and CI/governance
work in separate slices is the project's standing convention, and this is the clean CI slice that
pairs with Slice 35 — the exact horizontal twin of how Slice 32 paired with Slice 31.

After Slice 36 closes the pair, the project reaches a genuinely new crossroads: with **both** axes
CI-protected and geometry-bearing, the `pointAt(x:y:)` 2D hit-test (Option B) is unblocked and is
the highest-value product leap — but it wants its own brainstorm + spec for how two independent
metrics sources compose. That B-vs-D-vs-E direction is worth surfacing to the user as a product call
once the gate is promoted, with B the natural lean given the user's sustained steer toward editing
affordances (Slice 32 review → Slice 33 `columnAt`, Slice 33 review → Slice 34 gate, Slice 34 review
→ this slice). Whichever is chosen, keep functional/capability work and CI/infra work in separate
slices, per the project's standing convention.

## Slice 35 Review Conclusion

Slice 35 delivered the intended capability increment cleanly:
`ViewportVirtualizer.columnGeometryAt(x:inLine:metrics:)` extends the horizontal query from "which
cell?" to "which cell, and where within it?", returning the located cell's `ColumnGeometry` box, the
within-cell `fractionInColumn`, and `columnAt`'s clamp flag, delivered as three additive public types
(`ColumnGeometry`, `ColumnGeometryQuery`, `ColumnGeometryLocation`) that reuse the existing
`ColumnLocation.Clamp` vocabulary — one more type than the vertical `lineGeometryAt` needed, because no
horizontal cell-box type existed, named honestly in the spec. Because the method **composes over
`columnAt`**, index and clamp parity hold by construction, validation is single-sourced, and the
per-provider cost class is exactly `columnAt`'s — O(log M) for both shipped providers, with two
constant-factor geometry probes that never add a log factor (a simpler cost story than the vertical
axis's balanced-tree / Fenwick cases). The geometry is pinned by a product-built structural uniform
oracle, a `columnAt`-parity test, a box+fraction reconstruction round-trip invariant, and a
`PrefixSumColumnMetrics` self-consistency oracle across an `x` sweep including both clamps; the
composition's native-dispatch reuse and exact two-probe order are proven by an ordered event-log test;
and no shared search/provider path was touched (all 32 existing-gate checksums byte-identical, local
and hosted).

The review found **no P0, P1, or P2 issues** and **no evidence-accuracy defect** against the merged
result: PR #71's final-head run `28893267949` and the merged-code push run `28956968583` (merge commit
`5da380b`, second parent the tested head `a1ef979`) are both green at step level, with all eight
blocking latency gates run, no `--column-geometry-query` hosted step (confirming Decision 5's local-only
gate), and the realistic-observation step correctly `skipped` on push. The clean-evidence convention
held for the ninth source-touching slice — an explicit `Pending` placeholder in PR #71, filled only in
the docs-only post-merge follow-up (PR #72) against the stable final head. The five P3s are minor and
carried/cosmetic (located-case naming asymmetry mirroring Slice 31; documented floating-point upper-edge;
contract-trusted non-monotone interior; deferred native/closed-form provider work; the pre-existing
`join` spec/code naming drift this slice legitimately did not touch). Every hard constraint holds:
Foundation-free, zero-dependency, O(1) core memory, and cross-target verified (iOS blocking, WASM
observational).

The one item this slice hands forward is **CI-promotion debt**: the `--column-geometry-query` gate is
local-only, re-opening the debt Slice 34's handoff had drained — by design, because this is a capability
slice adding a new measurable path. Slice 35 completes the horizontal axis's capability pair (mapping +
geometry, the exact Slice 27 + Slice 31 vertical mirror) and hands off cleanly to **Slice 36 — promote
`--column-geometry-query` to a blocking hosted gate**, the established next step that retires that debt
before the newly-unblocked 2D `pointAt` leap (Option B) or the horizontal native-descent cleanup
(Option D) builds against it.
