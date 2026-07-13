# Geometry-Bearing 2D Point-Query (`pointGeometryAt(x:y:)`) Design

Slice 39 — the geometry-bearing companion to `pointAt(x:y:)`: one point in,
both axes' boxes, fractions, and clamp flags out. The primitive a
click-to-caret consumer actually wants.

## Status

Proposed. Brainstormed 2026-07-13; recommended by the Slice 38 post-slice review
(Option A — "`pointGeometryAt(x:y:)` … the design's own Recommended Next Step")
and by the Slice 37 point-query design itself ("Geometry-bearing
`pointGeometryAt(x:y:)` (recommended next)"). Scoped by the user, in sequence, to:

1. **Option A** over C (absolute product budgets), D (native horizontal descent),
   E (infrastructure).
2. **Evidence collected in this slice** — the benchmark mode ships here and emits
   hosted samples here, so its budgets are *derived*, never hand-typed; the gate's
   promotion to blocking stays a separate slice.
3. **P2 #2 of Slice 37 closed by decision, not by code** — the two-source pairing
   remains a precondition.
4. **Composition over the two 1D geometry queries** (`lineGeometryAt` ∘
   `columnGeometryAt`), not over `pointAt` plus fresh box arithmetic.

## Source Context

The brief (`docs/initial-project-brief.md`) wants a headless
layout/virtualization core that supports realistic editing/scrolling of 100k+
line / >10 MB documents, stays Foundation-free and Embedded-compatible, keeps
core-owned memory sub-linear in document size, and keeps the document behind a
provider/source abstraction.

The query surface now stands at four 1D queries plus one 2D composite, each
already CI-gated:

- **Vertical**: `lineAt(y:)` (Slice 27) → `lineGeometryAt(y:)` (Slice 31),
  gated by `--line-query` (28) and `--line-geometry-query` (32), with
  provider-native O(log N) descent (29/30).
- **Horizontal**: `columnAt(x:inLine:)` (Slice 33) → `columnGeometryAt(x:inLine:)`
  (Slice 35), gated by `--column-query` (34) and `--column-geometry-query` (36).
- **2D**: `pointAt(x:y:)` (Slice 37), gated by `--point-query` (38).

Slice 38 was a governance slice: it found that the query gates, though green,
**could not fail** — Slice 27's unredeemed "starter budget" placeholder had been
copy-pasted through Slices 31/33/35/37 — and it replaced hand-typed budgets with
a committed corpus of hosted samples, two committed scripts, a self-detecting
ceiling (`reason=budget_stale`), and `GateFloorTests`, which fails if any gated
scenario's budget drops below 3x the worst hosted sample *or has no hosted
evidence at all*. That last clause is what makes this slice's benchmark plan
different from every functional slice before it (see Decision 5).

The Slice 38 review handed off with **no P0/P1 debt**; its P2 #1 (non-idempotent
harvest) shipped as PR #83. This slice resumes the product arc.

## Problem

`pointAt` answers *which line and which cell*. Every real consumer of that answer
immediately asks a second question the core currently refuses: **where is that
cell, and where inside it did the point land?** A click-to-caret handler must
decide whether to place the caret before or after the hit character (the
half-advance rule), and to draw the caret it needs the cell's left edge and the
line's top edge and height. Today it must reconstruct all of that itself by
calling back into the providers:

```swift
// Today: the caller re-derives what the core already located.
guard case let .point(p) = ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: v, columnMetrics: h),
      case let .cell(c) = p.column else { … }
let top    = v.offset(ofLine: p.line.lineIndex)          // re-probe
let bottom = v.offset(ofLine: p.line.lineIndex + 1)      // re-probe
let left   = h.columnOffset(inLine: p.line.lineIndex, column: c.columnIndex)      // re-probe
let right  = h.columnOffset(inLine: p.line.lineIndex, column: c.columnIndex + 1)  // re-probe
let snapped = (x - left) / (right - left) >= 0.5 ? c.columnIndex + 1 : c.columnIndex
```

That is the same shape of gap `lineGeometryAt` closed for `lineAt` (Slice 31) and
`columnGeometryAt` closed for `columnAt` (Slice 35), now on both axes at once. The
probes are cheap; the *duplication of the geometry contract* is not. Every caller
re-implements the half-open span convention, the clamp-to-fraction rule
(`fraction == 0.0` at the top/left clamp, `1.0` at the bottom/right), and the
blank-line special case — and every caller can get them subtly wrong, most easily
by computing a fraction from a clamped coordinate that lies outside the box.

The core already holds this information at the moment it locates the point. The
fix is to return it.

## Scope

**In:**

- `ViewportVirtualizer.pointGeometryAt(x:y:lineMetrics:columnMetrics:)` — a new
  public static query on the existing `ViewportVirtualizer` enum.
- Three new public result types: `PointGeometryQuery`, `PointGeometryLocation`,
  `ColumnGeometryResolution`.
- A new benchmark mode `--point-geometry-query` with four scenarios mirroring
  `--point-query`'s.
- One **non-blocking, observational** CI step running that mode bare, whose hosted
  output is the evidence from which this slice's budgets are derived (Decision 5).
- Corpus rows harvested from that evidence; budgets derived by the committed
  script; `--gate` enabled for the mode **locally**; the mode's scenarios
  registered in `GateFloorTests`.
- A recorded, falsifiable latency prediction, written before the measurement
  (Decision 6).

**Out (and why):**

- **No promotion to a blocking hosted gate.** That is Slice 40 — a zero-Swift
  promotion slice, exactly as 28 / 32 / 34 / 36 were for the prior query modes.
- **No new metrics protocol and no new provider.** Consumes `LineMetricsSource`
  and `LineHorizontalMetricsSource` unchanged.
- **No new error case.** Every failure this query can surface already exists in
  `ViewportValidationError`.
- **No `lineCount` on the horizontal protocol, and no fused single-source
  overload** — see Decision 4.
- **No caret snapping.** The core reports where the point fell; rounding that to a
  caret index is a caller policy (the half-advance rule is one of several, and
  bidi/IME change it). Non-goal inherited verbatim from Slice 35.
- **No new search, and no new arithmetic** — see Decision 3.
- **No wrap / visual rows, no bidi reordering, no shaping.** Inherited from the
  1D queries.
- **No change to `pointAt`, the 1D queries, `compute`, or any provider.** Strictly
  additive.

## Goals

1. **Composition, not computation.** `pointAt` added no new *search*;
   `pointGeometryAt` adds no new *arithmetic*. Every box and fraction it returns
   is produced by the single existing implementation on that axis.
2. **Cost class unchanged from `pointAt`**: O(log N) + O(log M) queries, O(1) core
   memory, zero allocation beyond the returned value structs, plus exactly four
   constant probes.
3. **Semantics inherited, not restated**: the validation ladder, failure
   precedence, clamp flags, and the empty/blank-line distinction all come from the
   1D queries. No case of the input space is decided in this file.
4. **A budget derived from hosted evidence on the day it ships.** Not a starter
   value, not a local extrapolation, not a number in a table. This is the first
   functional slice to ship under Slice 38's rules, and it must not reopen the
   hole Slice 38 closed.
5. Foundation-free, Embedded-compatible, iOS/WASM-clean, zero-dependency.

## Non-Goals

Restated as hard boundaries so the plan cannot drift into them: no gate promotion,
no protocol change, no provider change, no error-enum change, no caret policy, no
fused source, no wrap/bidi, no changes to any existing query.

## Decisions

### Decision 1 — Result shape mirrors `PointQuery` exactly, one level richer

```swift
public enum PointGeometryQuery: Equatable {
    case geometry(PointGeometryLocation)  // a line was located (its cell may be blank)
    case empty                            // empty document: lineCount == 0
    case failure(ViewportValidationError) // vertical or horizontal validation failure
}

public struct PointGeometryLocation: Equatable {
    /// The located line's box (y + height + index), the within-line fraction, and
    /// the vertical clamp flag — verbatim from `lineGeometryAt`.
    public let line: LineGeometryLocation
    /// The located cell's box + fraction + horizontal clamp, or `.blankLine`.
    public let column: ColumnGeometryResolution
}

public enum ColumnGeometryResolution: Equatable {
    case cell(ColumnGeometryLocation)     // box (x + width + index), fraction, horizontal clamp
    case blankLine                        // located line has no cells (columnCount(inLine:) == 0)
}
```

Three properties this shape buys:

- **A located line is never lost to a blank cell.** `.blankLine` still carries the
  full `LineGeometryLocation` — the caret box of an empty line is exactly the
  information a consumer needs there, and a flat `(line, cell)` tuple or an
  optional cell would either lose it or make the caller unwrap for it.
- **No line index is duplicated.** `LineGeometry` already carries `lineIndex` and
  `ColumnGeometry` already carries `columnIndex`; `PointGeometryLocation` adds no
  third copy that could disagree.
- **It is `PointQuery`'s shape with each component swapped for its geometry-bearing
  counterpart** — `LineLocation` → `LineGeometryLocation`, `ColumnLocation` →
  `ColumnGeometryLocation`, `ColumnResolution` → `ColumnGeometryResolution`. A
  reader who knows one knows the other.

**Rejected: appending a case to `PointQuery`.** Same reasoning as Slices 31/35 —
the geometry-bearing query is a *new query*, not a new outcome of the old one.
Widening the existing enum would break every exhaustive `switch` at every call
site for a result they did not ask for.

### Decision 2 — `pointGeometryAt` composes the two 1D **geometry** queries

```swift
public static func pointGeometryAt<VMetrics: LineMetricsSource, HMetrics: LineHorizontalMetricsSource>(
    x: Double, y: Double, lineMetrics: VMetrics, columnMetrics: HMetrics
) -> PointGeometryQuery {
    switch lineGeometryAt(y: y, metrics: lineMetrics) {
    case let .failure(error):
        return .failure(error)
    case .empty:
        return .empty
    case let .geometry(line):
        switch columnGeometryAt(x: x, inLine: line.geometry.lineIndex, metrics: columnMetrics) {
        case let .failure(error):
            return .failure(error)
        case .empty:
            return .geometry(PointGeometryLocation(line: line, column: .blankLine))
        case let .geometry(column):
            return .geometry(PointGeometryLocation(line: line, column: .cell(column)))
        }
    }
}
```

The signature mirrors `pointAt`'s parameter labels (`lineMetrics:` /
`columnMetrics:`) so the pair reads as one family, and the vertical axis runs
first for the same forced reason: the horizontal query needs an `inLine`, and only
a vertical success can supply one.

**The alternative was composing over `pointAt` and adding the four box probes
here.** Both produce identical results; they differ in *which property is true by
construction*:

| | composes over the 1D geometry queries (chosen) | composes over `pointAt` |
|---|---|---|
| box + fraction + clamp agree with the 1D geometry queries | by construction | by test |
| index + clamp agree with `pointAt` | by test | by construction |
| new arithmetic in the core | none | a third copy of the box/fraction formula |

The chosen side buys the property that cannot be recovered cheaply: **no new
arithmetic**. The fraction rule has a real trap in it — on a clamp, the fraction is
pinned to `0.0`/`1.0` rather than computed from an `x`/`y` that lies *outside* the
box — and a third hand-written copy of it is a place for that to silently drift.
What the chosen side gives up (2D ordering parity with `pointAt` by construction)
is ~12 lines of `switch` whose every branch is pinned by the parity oracle in
Testing Strategy, and by the full input→result table in Decision 7.

### Decision 3 — No new search, no new arithmetic; cost = `pointAt` + 4 probes

`pointGeometryAt` performs no search of its own: both inverse searches happen
inside the 1D queries, which dispatch to the provider-native hooks
(`lineIndex(containingOffset:)`, `columnIndex(containingOffset:inLine:)`) or their
binary-search defaults. Over `pointAt` it adds exactly four probes — two
`offset(ofLine:)` (from `lineGeometryAt`) and two
`columnOffset(inLine:column:)` (from `columnGeometryAt`) — a constant, so it never
adds a log factor and its per-provider cost class **equals `pointAt`'s**:

- Queries: O(log N) + O(log M), or better where a provider overrides its hook.
- Core memory: O(1). Allocation: none beyond the returned value structs.

### Decision 4 — The two-source pairing stays a precondition (closes Slice 37 P2 #2)

Slice 37's review left open: now that the *core* supplies `inLine` from the
vertical query, what should a mismatched source pairing do? Today a horizontal
provider handed a line index beyond its document traps.

**Decision: it stays a documented precondition, and this slice closes the question
rather than deferring it again.**

The reason is structural, not lazy. `LineHorizontalMetricsSource` **deliberately
does not model a line count** — `UniformColumnMetrics.columnCount(inLine:)` ignores
its argument entirely, because a uniform grid is line-agnostic and holds O(1)
memory for a document of any size. The core therefore cannot validate the pairing
with the information the protocol exposes, and the two ways to give it that
information both cost more than the bug they prevent:

- **Adding `lineCount` to the horizontal protocol** would force every line-agnostic
  provider to invent a line count it does not have and does not need, break every
  existing conformance, and widen the public error enum — all to convert a
  programmer error (pairing two different documents' sources) into a runtime
  `.failure` the caller cannot meaningfully handle either.
- **A fused single-source overload** contradicts Slice 37's own Decision 1 ("fusing
  them is a provider/caller concern, not the core's") and doubles the API surface
  of every two-axis query.

Mismatched sources are not *input data* — they are a wiring mistake, and a trap is
Swift's idiom for exactly that. What this slice owes the reader is that the
contract be stated where it is violated: the precondition is documented on
`pointGeometryAt` in the same terms as on `pointAt`, and the deliberate absence of
a line count on the horizontal protocol is recorded here as a decision rather than
left to be re-discovered as a gap.

### Decision 5 — Evidence is collected in this slice; promotion is not

This is the first functional slice to add a gated benchmark mode **since Slice 38
made hand-typed budgets illegal**, and the old recipe no longer works. The
constraint is a genuine chicken-and-egg:

- `GateFloorTests.testEveryGatedScenarioHasCorpusEvidence` fails if a gated
  scenario has **no hosted sample in the corpus**.
- A new mode has no hosted samples, and cannot acquire any until it **runs in
  hosted CI**.
- And Slice 38's rule — "**never hand-type a budget**" — forbids the obvious
  shortcut of inventing one to bridge the gap.

The resolution, and the order of work inside this slice's PR:

1. Ship the core query and its tests.
2. Ship the `--point-geometry-query` benchmark mode with **`--gate` rejected** for
   it (like `--memory-shape`), and add **one non-blocking, observational step** to
   the existing host CI job that runs the mode bare. A bare run exits 0
   unconditionally, so the step cannot turn the job red.
3. Let the PR's own hosted runs emit the evidence. Each run prints four
   `mode=point_geometry_query scenario=… p95_ns=… p99_ns=…` lines, and the
   harvester's parser is **mode-agnostic** — it matches any line carrying
   `mode=`/`scenario=`/`p95_ns=`/`p99_ns=`, so it captures the new mode with **no
   script change at all**. Collect **at least 3 hosted runs** (≥12 rows) before
   deriving.
4. Harvest into the corpus (`--corpus` for idempotency, per PR #83), derive the
   budgets with `derive-gate-budgets.sh`, then enable `--gate` for the mode and
   register its scenarios in `GateFloorTests`. The local gate and the floor test
   must both be green **on derived numbers**.
5. Slice 40 promotes the observational step to a blocking `--gate` step: the
   eleventh gate, zero Swift changed.

Three runs is a thin base and the design says so plainly rather than implying
otherwise — `--point-query` shipped its budget on six, and its source comment
records that thinness as the reason it is the likeliest to need an upward
re-derivation. The same caveat is written into this mode's scenario comment, with
the same instruction: re-derive, do not hand-edit. What three runs *do* buy is the
thing that matters: the budget is a function of hosted evidence, so it can be
re-derived by anyone, and it is inside the band a gate must sit in to be able to
fail.

**Rejected: deriving this mode's budgets from the existing corpus** by predicting
them from `point_query` + a constant, or from
`line_geometry_query` + `column_geometry_query`. That is hand-typing with an
arithmetic alibi; it would leave `GateFloorTests` red (no corpus rows for the
mode), and it would make a budget that no script can reproduce. The prediction is
still worth making — but as a *falsifiable check on the measurement*, which is
Decision 6, not as a substitute for it.

### Decision 6 — The prediction, recorded before the measurement

Written down now so it can fail. `pointGeometryAt` is `pointAt` plus four O(1)
probes on providers whose probes are an arithmetic multiply
(`UniformLineMetrics`, `UniformColumnMetrics`) or one array read
(`PrefixSumLineMetrics`). So:

- **Primary**: each `point_geometry_query` scenario's hosted median p95 should land
  **within ~30 % of the corresponding `point_query` scenario's**, and above it. The
  four probes are single-digit nanoseconds against a ~90–130 ns composite.
- **Secondary**: it should also land within ~30 % of `line_geometry_query` +
  `column_geometry_query` medians for the same shape — the same cross-check Slice
  38 made for `pointAt` (predicted 80 ns, measured 83 ns).

If the measurement lands far outside either band — say 2x `point_query` — **that is
a finding, not a budget to be widened around**: it would mean the composite is
doing work the algebra says it should not (a lost specialization, a re-probe, an
allocation), and the slice investigates the code before it derives a number.

### Decision 7 — Full input → result table

Every reachable outcome, so no branch is decided by accident. `V` = vertical source
(`lineMetrics`), `H` = horizontal source (`columnMetrics`).

| Condition (first match wins) | Result |
|---|---|
| `V.lineCount < 0` | `.failure(.negativeLineCount)` |
| `y` not finite | `.failure(.nonFiniteValue)` |
| `V.offset(ofLine: 0) != 0` | `.failure(.invalidLineMetrics)` |
| `V.lineCount == 0` | `.empty` (x is never examined — even a non-finite one) |
| `V` total height not finite or ≤ 0 | `.failure(.invalidLineMetrics)` |
| line located; `H.columnCount(inLine:) < 0` | `.failure(.negativeColumnCount)` |
| line located; `x` not finite | `.failure(.nonFiniteValue)` |
| line located; `H.columnOffset(inLine:column: 0) != 0` | `.failure(.invalidColumnMetrics)` |
| line located; `H.columnCount(inLine:) == 0` | `.geometry(line: …, column: .blankLine)` |
| line located; line width not finite or ≤ 0 | `.failure(.invalidColumnMetrics)` |
| line located; cell located | `.geometry(line: …, column: .cell(…))` |

Consequences worth naming, all inherited verbatim from the 1D ladders: a
non-finite `y` **beats** `.empty`; a non-finite `x` **beats** `.blankLine`; on an
empty document a non-finite `x` still yields `.empty`; and a horizontal failure
**discards** the located line rather than reporting a partial result — a `.failure`
means the query answered nothing, on either axis.

Clamps compose freely: `y < 0` with `x < 0` yields
`line.clamp == .clampedToTop` **and** `column.clamp == .clampedToLeft`, with
`fractionInLine == 0.0` and `fractionInColumn == 0.0`. Each axis clamps
independently; neither suppresses the other.

### Decision 8 — File placement mirrors the 1D queries

- New file `Sources/TextEngineCore/PointGeometryQuery.swift` — the extension on
  `ViewportVirtualizer` carrying only `pointGeometryAt`, exactly as
  `PointQuery.swift` carries only `pointAt`. (The 1D geometry companions live
  *beside* their position queries in `PositionQuery.swift` /
  `HorizontalPositionQuery.swift`; the 2D pair does not, because `PointQuery.swift`
  is the 2D *position* file and a separate file keeps each 2D query's doc comment
  and diff readable on its own.)
- The three new types go in `Sources/TextEngineCore/ViewportTypes.swift`, directly
  after the `PointQuery` block they mirror.
- New file `Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift`, mirroring
  `PointQueryBenchmark.swift`.
- New test file `Tests/TextEngineCoreTests/PointGeometryAtTests.swift`.

## Component Design

### `pointGeometryAt` (new)

The function of Decision 2, verbatim. Its doc comment must state, in the house style
of the existing queries: that it is a pure composition adding no search and no
arithmetic; that its cost class equals `pointAt`'s plus four constant probes; that
validation is delegated to the 1D queries and the precedence consequences of that
(Decision 7); and the two-source precondition (Decision 4).

### Types (new)

`PointGeometryQuery`, `PointGeometryLocation`, `ColumnGeometryResolution` — all
`Equatable`, all value types, all documented in terms of the 1D types they carry.

### Untouched

`pointAt`, `lineAt`, `lineGeometryAt`, `columnAt`, `columnGeometryAt`, `compute`,
`LineMetricsSource`, `LineHorizontalMetricsSource`, `ViewportValidationError`, and
every provider. If the diff touches any of them, the slice has drifted.

## Testing Strategy

TDD, tests first. The load-bearing tests are the oracles, because the chosen
composition (Decision 2) pays for "no new arithmetic" with "parity by test".

### Parity oracles (load-bearing)

Over a grid of `(x, y)` — inside, on the boundaries of, and outside both axes'
ranges — against both vertical providers (`UniformLineMetrics`,
`PrefixSumLineMetrics`) crossed with the horizontal ones (`UniformColumnMetrics`,
`PrefixSumColumnMetrics`), assert for every point:

1. **vs `pointAt`**: the located indices and **both** clamp flags are identical.
   Same `.empty` / `.failure` / `.blankLine` outcome, same error case. This is the
   test that pins the ~12 lines of 2D ordering the chosen composition re-states.
2. **vs `lineGeometryAt(y:)`**: the `line` component is *equal* to the 1D result —
   box, fraction, clamp.
3. **vs `columnGeometryAt(x:inLine:)`** for the located line: the `column`
   component is *equal* to the 1D result.

### Reconstruction property

For in-range points, the returned geometry must reproduce the input:
`line.geometry.y + line.fractionInLine * line.geometry.height == y` and
`cell.geometry.x + cell.fractionInColumn * cell.geometry.width == x`, within a
small ULP-scaled tolerance. This is the test that would catch a fraction computed
against the wrong box.

### Unit tests (`PointGeometryAtTests`)

One per row of Decision 7's table, plus: clamped corners (all four
`(±x, ±y)` combinations, asserting both clamp flags *and* fractions pinned to
exactly `0.0` / `1.0`); a blank line still carrying its full line geometry; a
single-line / single-column document; the first and last cell of the first and
last line; and a variable-height + variable-advance document where the boxes differ
per line and per cell.

### Precedence tests

The four inherited precedence rules get explicit tests, because they are the ones a
future refactor could reorder without any other test noticing: non-finite `y` over
`.empty`; non-finite `x` over `.blankLine`; `.empty` over a non-finite `x`;
horizontal failure discarding a successfully located line.

### Not tested here

No behavior-preservation burden: nothing existing changes. No performance test in
the unit suite — that is the benchmark's job.

## Benchmark Mode (`ViewportBenchmarks`)

`--point-geometry-query`, four scenarios mirroring `--point-query` one-for-one so
the two modes are comparable row by row (their difference *is* the cost of the four
probes):

| scenario | vertical provider | lines | horizontal provider |
|---|---|---|---|
| `uniform_100k` | `UniformLineMetrics` | 100k | `UniformColumnMetrics` |
| `uniform_1m` | `UniformLineMetrics` | 1M | `UniformColumnMetrics` |
| `prefixsum_100k` | `PrefixSumLineMetrics` | 100k | `UniformColumnMetrics` |
| `prefixsum_1m` | `PrefixSumLineMetrics` | 1M | `UniformColumnMetrics` |

Same 256 columns × 8.0 advance × 16.0 line height, same deterministic point
sequence, same `@inline(never)` operation shape as `PointQueryBenchmark`. Only the
vertical provider varies, for the same reason `--point-query` gives: each axis's own
search cost is already guarded by its own gate, so the composite's unique job is to
catch composition overhead, not to re-measure the searches.

`--gate` is **rejected** for this mode until step 4 of Decision 5, then accepted.

## CI

One new step in the existing host job, non-blocking by construction (a bare
benchmark run exits 0):

```yaml
- name: Point-geometry query observation
  run: swift run -c release ViewportBenchmarks -- --point-geometry-query
```

It does not become a gate in this slice. No workflow job is added; no required
check changes; the docs-only detector is untouched.

## Verification

Recorded in `docs/superpowers/verification/2026-07-13-point-geometry-query.md` as
commands + real output, not assertions:

- `swift test` (host, including the new oracles and `GateFloorTests`).
- `swift build -c release`.
- `rg -n "Foundation" Sources/TextEngineCore` → empty.
- `swift run -c release ViewportBenchmarks -- --point-geometry-query --gate` →
  `gate=pass`, plus the headroom of every scenario (must be inside the 3x–50x/100x
  band, per `AGENTS.md`).
- The full existing gate suite, unchanged and green.
- `./.github/scripts/cross-target-compile.sh` (iOS blocking, WASM observational).
- The hosted run IDs harvested, the corpus diff, and the exact
  `derive-gate-budgets.sh` invocation and output that produced the budgets.
- The Decision 6 prediction versus the measured hosted medians — including the
  arithmetic, and whether it held.
- The post-merge `push` run, per the standing "verification is evidence" rule.

## Acceptance Criteria

1. `pointGeometryAt` exists with the Decision 1/2 shape; the parity oracles and the
   reconstruction property pass on all four provider pairings.
2. Every row of Decision 7's table has a passing test.
3. The core diff touches only the new file plus the three new types in
   `ViewportTypes.swift`. No existing query, protocol, provider, or error case is
   modified.
4. Foundation-free scan is empty; iOS compile is green; WASM is green-or-skipped.
5. `--point-geometry-query --gate` passes locally on budgets **derived by
   `derive-gate-budgets.sh` from ≥3 hosted runs of this PR**, and every scenario's
   headroom sits inside the band.
6. `GateFloorTests` passes with the new scenarios registered — meaning the corpus
   carries their hosted evidence and the budgets clear 3x the worst sample on both
   statistics.
7. The Decision 6 prediction is checked against the measurement and the result is
   recorded, whichever way it went.
8. No hand-typed budget appears anywhere in the diff.

## Risks And Gaps

**The budget rests on ~3 hosted runs.** Thinner than any existing mode except
`point_query` (6). Mitigated by the 3x-over-worst-sample floor, which is computed
over the *maximum* rather than the median, and by recording the thinness in the
scenario comment with the re-derivation command. It remains the mode most likely to
need an upward re-derivation as evidence accumulates — and Slice 40, which harvests
again to promote it, is the natural place for that.

**The observational CI step spends hosted minutes for a mode that gates nothing
yet.** One benchmark run per CI run, for one slice. That is the price of a derived
budget; the alternative was a hand-typed one.

**A functional slice touches CI.** The standing convention keeps functional and CI
work in separate slices. The exception here is deliberate and bounded to a single
non-blocking step, because the evidence *cannot* exist otherwise, and the
alternative — deferring the entire benchmark mode to Slice 40 — would make the
promotion slice bootstrap, derive, and promote all at once, which is precisely the
compression that hid Slice 27's placeholder for five slices.

**The composite re-measures paths its 1D gates already cover.** Inherited from
`--point-query` and accepted for the same reason: the composite's *own* overhead
(cross-axis protocol dispatch with no cross-inlining, plus the four probes) is not
measured anywhere else.

**Clamped fractions are a convention, not a computation.** `0.0` / `1.0` at a clamp
is a choice (the alternative — a signed fraction outside `[0, 1]` reporting *how far
outside* the point fell — is defensible for drag-select autoscroll). Inherited
unchanged from Slices 31/35 for consistency; a caller that needs the overshoot still
has `x`, `y`, and the box.

## Future Slices

- **Slice 40 — promote `--point-geometry-query` to the eleventh blocking gate.**
  Zero Swift. Harvest the accumulated hosted runs, re-derive, flip the observational
  step to `--gate`. It is also the natural home for Slice 38's still-open P2 #2 (the
  `3 x max()` floor is a one-way ratchet over an append-only corpus: one noisy sample
  loosens a budget permanently, and `GateFloorTests` then enforces the outlier).
- **The absolute (product) budget** (Slice 38 review Option C): a second,
  never-recalibrated threshold per scenario, so that legitimate slow drift cannot be
  laundered green by successive re-derivations. Still the strongest open idea on the
  roadmap, and still unclaimed.
- **Provider-native horizontal descent** (Option D): O(1) `columnIndex` override for
  `UniformColumnMetrics`, balanced-tree override for a mutable horizontal provider.
  Expect it to trip the 50x ceiling on the column gates — which is the ceiling working
  as designed; re-derive in the same PR.
- **Wrap-aware visual rows** — the larger capability, still needing its own brainstorm,
  and the one that would change what a "line" means to both axes.
