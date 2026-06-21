# Vertical Position-Query (`lineAt(y:)`) Design

Slice 27 — return to functional core after the Slice 25/26 bulk-edit + gate pair.

## Status

Proposed. Brainstormed 2026-06-21; recommended by the Slice 26 post-slice review
(Option A — advance the next real engine capability) and selected by the user as
the vertical position-query increment.

## Source Context

The brief (`docs/initial-project-brief.md`) wants a headless layout/virtualization
core that supports realistic editing/scrolling of 100k+ line / >10 MB documents,
stays Foundation-free and Embedded-compatible, and keeps core-owned memory
sub-linear in document size.

The engine to date is **vertical-axis only and one-directional**: it maps
**line → y** through `LineMetricsSource.offset(ofLine:)` (cumulative top offset),
and `ViewportVirtualizer.compute(_:metrics:)` virtualizes the visible row range
with an O(log N) binary search over those offsets, streaming per-line
`LineGeometry(lineIndex, y, height)` over the buffer with
`VariableLineGeometryCursor`. There is no public **y → line** mapping, even though
the binary search that computes it already lives — `private` — inside
`VariableViewportVirtualizer.firstLineTopAtOrBelow`.

The Slice 26 review handed off to a new-capability slice with no CI/governance
debt remaining: all five latency gates (synthetic, static + mutating
variable-height, single + bulk structural mutation) run blocking in hosted CI, so
the provider's full edit surface is regression-protected. This slice builds on
that protected base.

## Problem

Every real consumer of a layout engine needs the inverse of line layout:

- **Hit-testing / tap-to-position** — a pointer or tap lands at a document `y`;
  the UI must know which line that is.
- **Scroll/anchor math** — "which line is at the top of the viewport for this
  scroll offset", "which line owns this scrollbar position".
- **Caret/selection placement** — the vertical half of locating a caret from a
  point.

Today a consumer must re-implement the binary search over `offset(ofLine:)`
itself, duplicating the exact logic the core already runs internally and risking
divergent boundary/clamp conventions. The core should own this mapping, as the
authoritative inverse of `offset(ofLine:)`, with the same validation discipline,
the same boundary convention, and the same O(log N) / O(1)-memory envelope as
`compute`.

## Scope

Add a single public, stateless query to `TextEngineCore`:

> Given a document `y` offset and a `LineMetricsSource`, return the line whose
> vertical span contains `y`, clamped into the document with an explicit flag
> telling the caller whether the query landed inside the document or past an edge.

Plus its equivalence-oracle and unit tests, a `--line-query` benchmark mode with a
**local** `--gate`, and the slice paper trail. No rendering, no horizontal axis,
no wrap, no new provider data.

## Goals

- Public `ViewportVirtualizer.lineAt(y:metrics:) -> LineQuery` over the general
  `LineMetricsSource` path, symmetric with `compute(_:metrics:)` and
  `geometry(for:metrics:)`.
- **O(log N)** queries, **O(1)** core memory — the same envelope as `compute`,
  reusing the existing binary search (no second copy of the algorithm).
- Validation parity with `compute`: up-front, return-based (no `throws`),
  Foundation-free, reusing the existing `ViewportValidationError`.
- An **equivalence oracle**: for `UniformLineMetrics`, `lineAt(y:)` equals the
  closed form `clamp(floor(y / lineHeight), 0, lineCount-1)` with the correct
  clamp flag — the same "variable path provably equals the closed form for uniform
  metrics" discipline the project already uses for `compute`.
- A `--line-query` benchmark mode + local `--gate` with a macOS-calibrated budget,
  following the established functional-slice rhythm.
- Foundation-free, Embedded-compatible, zero-dependency; iOS/WASM cross-target
  compile unchanged.

## Non-Goals

- **No horizontal axis** (no `x`, width, or `pointAt(x:y:)`). This slice is
  strictly the vertical inverse. Horizontal/point queries are a future slice.
- **No wrap / visual rows.** The unit stays the logical line.
- **No fixed-height overload.** One metrics-based entry point only (Decision 2).
- **No within-line fractional offset / geometry in the result.** The result is
  `lineIndex` + clamp status; a caller wanting the line's span derives it from the
  existing `offset(ofLine:)`. (Considered and deferred — see Risks And Gaps.)
- **No CI promotion.** The `--line-query --gate` runs locally only this slice;
  promoting it to a blocking hosted gate is a separate follow-up slice
  (Decision 6), exactly as variable-height → Slice 15, mutation → Slice 21,
  structural → Slice 24, bulk → Slice 26.
- **No provider change.** `TextEngineReferenceProviders` is untouched; existing
  `LineMetricsSource` conformances suffice.

## Decisions

### Decision 1 — Result shape: `LineQuery` / `LineLocation` / `Clamp`

The query returns a small three-case result enum, mirroring `ViewportComputation`'s
success/failure discipline but with an explicit, non-error empty-document case:

```swift
public enum LineQuery: Equatable {
    case line(LineLocation)               // a real line was located
    case empty                            // document has zero lines (not an error)
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct LineLocation: Equatable {
    public let lineIndex: Int
    public let clamp: Clamp

    public init(lineIndex: Int, clamp: Clamp) {
        self.lineIndex = lineIndex
        self.clamp = clamp
    }

    public enum Clamp: Equatable {
        case inRange          // y was inside [0, totalHeight)
        case clampedToTop     // y < 0; resolved to line 0
        case clampedToBottom  // y >= totalHeight; resolved to last line
    }
}
```

Rationale:

- A **distinct `.empty`** is correct: a zero-line document is structurally valid,
  not a validation error, and has no line to return. Folding it into `.failure`
  would conflate "no lines" with "bad input"; inventing a sentinel `lineIndex`
  inside `.line` would be a footgun. `compute` returns `.success(emptyRange())`
  for the empty doc; `lineAt` makes the empty outcome explicit because — unlike a
  range — there is no meaningful "empty line index".
- The **clamp flag** is what hit-testing wants: out-of-range `y` resolves to the
  nearest line (so tap-to-position never fails on an edge), while the flag lets a
  caller that cares (e.g. "are we past the end?") distinguish an exact-edge hit
  from a clamp. This mirrors `VirtualRange`'s `isAtTop`/`isAtBottom` flavor.
- `Clamp` is **nested** in `LineLocation` (`LineLocation.Clamp`) to namespace a
  generic-sounding name; use sites read `.inRange`/`.clampedToTop`/
  `.clampedToBottom` via inference.
- Reuses the existing `ViewportValidationError` — **no new error type** — so the
  failure vocabulary stays single-sourced.

### Decision 2 — One metrics-based entry point, no fixed-height overload

`lineAt` is a single generic over `LineMetricsSource`:

```swift
extension ViewportVirtualizer {
    public static func lineAt<Metrics: LineMetricsSource>(
        y: Double, metrics: Metrics
    ) -> LineQuery
}
```

There is **no** separate fixed-height (`ViewportInput`-style) overload. The uniform
case is served by `UniformLineMetrics`, whose `offset(ofLine:)` is O(1), so the
binary search degenerates to the same closed-form answer the equivalence oracle
asserts. `compute` carries a historical fixed-height overload (it predates the
metrics abstraction); there is no reason to grow a second `lineAt` surface for the
same algorithm. YAGNI: one path, proven equal to the closed form by the oracle.

### Decision 3 — Reuse the existing binary search; do not duplicate it

The in-range answer is "largest `i` in `[0, lineCount)` with `offset(i) ≤ y`",
which is exactly `VariableViewportVirtualizer.firstLineTopAtOrBelow`. That method
is currently `private static` in `VariableViewportVirtualizer.swift`. This slice
**relaxes it to internal** (drops `private`) — or extracts its loop body into an
internal helper — so `PositionQuery.swift` calls the same implementation `compute`
uses. No second copy of the search exists after this slice.

This refactor must be **behavior-preserving for `compute`**: the variable-height
and synthetic gate checksums and the `compute` equivalence oracle must be
byte-identical before and after. The plan captures the pre-refactor checksum
baseline and re-asserts it, the same discipline Slice 26 used for the
`deterministicIndex` extraction.

`firstLineTopAtOrBelow` already returns `lineCount` for `target >= totalHeight`;
`lineAt` never relies on that branch because it handles `y >= totalHeight`
explicitly as `clampedToBottom` (Decision 4), passing only in-range `y` to the
search. The search therefore returns an index in `[0, lineCount)` for `lineAt`.

### Decision 4 — Half-open boundary + clamp semantics

Lines occupy **half-open** vertical spans `[offset(i), offset(i+1))`. A `y` exactly
on a boundary `offset(i)` resolves to line `i` (the line *starting* there), which is
precisely what `firstLineTopAtOrBelow` ("largest `i` with `offset(i) ≤ y`") yields.
This introduces **no new convention** — it is the one `compute` already uses
internally.

Full input → result table (evaluated in `compute`'s deliberate order — Decision 5):

| Input condition | Result |
| --- | --- |
| `metrics.lineCount < 0` | `.failure(.negativeLineCount)` |
| `y` not finite (`NaN`/`±inf`) | `.failure(.nonFiniteValue)` |
| `metrics.offset(ofLine: 0) != 0.0` | `.failure(.invalidLineMetrics)` |
| `lineCount == 0` | `.empty` |
| total height non-finite or `<= 0` | `.failure(.invalidLineMetrics)` |
| `y < 0` | `.line(LineLocation(0, .clampedToTop))` |
| `y >= totalHeight` | `.line(LineLocation(lineCount - 1, .clampedToBottom))` |
| otherwise (`0 <= y < totalHeight`) | `.line(LineLocation(search(y), .inRange))` |

Notes:

- `y == 0` on a non-empty document is **`.inRange`** at line 0 — `0` is inside
  `[0, totalHeight)`. Only strictly negative `y` is `clampedToTop`.
- `y == totalHeight` is `clampedToBottom` (the bottom edge is the exclusive end of
  the last line's half-open span), resolving to `lineCount - 1`.
- `totalHeight = metrics.offset(ofLine: lineCount)`. For a non-empty document the
  `LineMetricsSource` contract guarantees it is finite and strictly positive; the
  explicit `<= 0` / non-finite check is defensive parity with `compute` against a
  contract-violating provider.

### Decision 5 — Validation order is parity with `compute`

`compute(_:metrics:)` validates in a deliberate order — `lineCount < 0` →
finiteness → `offset(ofLine: 0) == 0` (checked **before** the `lineCount == 0`
short-circuit) → empty short-circuit → total-height sanity. `lineAt` follows the
same order so a malformed provider and a malformed `y` produce the same failure in
both APIs. The `offset(ofLine: 0)` probe stays before the `.empty` return, exactly
as `compute` checks it before its empty return.

### Decision 6 — Local gate now, CI promotion deferred (established rhythm)

This functional slice ships the `--line-query` benchmark mode **and** local
`--gate` enforcement with macOS-calibrated budgets, but does **not** wire the gate
into `.github/workflows/swift-ci.yml`. Promotion to a blocking hosted gate is a
separate follow-up slice (the recommended Slice 28), identical to the project's
four prior functional → promotion pairs (variable-height → 15,
variable-height-mutation → 21, structural-mutation → 24,
bulk-structural-mutation → 26). `AGENTS.md` gains the new local command and the
`--line-query` flag; its CI section is unchanged because the workflow is unchanged.

`--gate` becomes valid with `--line-query` (added to the gateable set alongside
the pipeline, realistic-provider, variable-height, variable-height-mutation,
structural-mutation, and bulk-structural-mutation modes); it remains rejected with
`--range-only`, `--memory-shape`, and `--memory-observation`.

### Decision 7 — Scope stays vertical; result carries no geometry

The result is `lineIndex` + `clamp` only — no `y`/`height` of the located line, no
fractional within-line offset, no horizontal data. A caller needing the line's span
gets it from the existing `offset(ofLine:)` (one or two O(log N) probes). Keeping
the result minimal avoids widening the public type and an extra `offset(ofLine:)`
query on the hot path for callers that only need the index. The richer
geometry-bearing variant was considered in brainstorming and deferred (Risks And
Gaps).

## Component Design

### New file: `Sources/TextEngineCore/PositionQuery.swift`

An `extension ViewportVirtualizer` holding the public `lineAt(y:metrics:)`. It:

1. Runs the Decision 4/5 validation ladder, returning `.failure`/`.empty` as
   tabulated.
2. Computes `totalHeight = metrics.offset(ofLine: lineCount)` once.
3. Handles the two clamp branches (`y < 0`, `y >= totalHeight`) without touching
   the search.
4. For in-range `y`, calls the shared internal binary search and wraps the result
   as `.line(LineLocation(i, .inRange))`.

### Types added to `Sources/TextEngineCore/ViewportTypes.swift`

`LineQuery`, `LineLocation`, and `LineLocation.Clamp` (Decision 1), alongside the
existing `ViewportComputation` / `VirtualRange` / `LineGeometry` definitions, so the
public vocabulary stays in one file.

### Refactor: `Sources/TextEngineCore/VariableViewportVirtualizer.swift`

Relax `firstLineTopAtOrBelow` from `private static` to internal `static` (Decision
3) so `PositionQuery.swift` shares it. No logic change; `compute` keeps calling it
identically. (If review prefers, the loop body can instead be lifted into a named
internal helper both call — equivalent and behavior-preserving either way; the
plan picks the minimal diff.)

### Algorithm sketch

```
lineAt(y, metrics):
    lineCount = metrics.lineCount
    if lineCount < 0:            return .failure(.negativeLineCount)
    if !y.isFinite:             return .failure(.nonFiniteValue)
    if metrics.offset(0) != 0:  return .failure(.invalidLineMetrics)
    if lineCount == 0:          return .empty
    total = metrics.offset(lineCount)
    if !total.isFinite || total <= 0: return .failure(.invalidLineMetrics)
    if y < 0:                   return .line(0, .clampedToTop)
    if y >= total:              return .line(lineCount - 1, .clampedToBottom)
    i = firstLineTopAtOrBelow(y, metrics, lineCount, total)   // shared search
    return .line(i, .inRange)
```

O(log N) (one binary search; O(1) for `UniformLineMetrics`), O(1) core memory.

## Testing Strategy

XCTest only, in `Tests/TextEngineCoreTests`, TDD failing-first.

### Equivalence oracle (load-bearing)

For `UniformLineMetrics(lineCount:lineHeight:)`, sweep `y` across a grid covering:
negative `y`; `y == 0`; exact line boundaries `k * lineHeight`; mid-line values
`k * lineHeight + lineHeight/2`; `y == totalHeight`; `y > totalHeight`. Assert
`lineAt(y:)` equals the closed form:

```
expected(y):
    if y < 0:               .line(0, .clampedToTop)
    else if y >= total:     .line(lineCount - 1, .clampedToBottom)
    else:                   .line(min(Int(floor(y / lineHeight)), lineCount - 1), .inRange)
```

Run the sweep for several `(lineCount, lineHeight)` pairs, including `lineCount == 1`.

### Unit tests

- **Empty document** (`lineCount == 0`) → `.empty`, for any `y` (negative, zero,
  positive).
- **Failure cases**: `negativeLineCount`; non-finite `y` (`.nan`, `.infinity`,
  `-.infinity`); a hand-built `LineMetricsSource` with `offset(ofLine: 0) != 0` →
  `.invalidLineMetrics`; a provider whose total height is `0`/non-finite →
  `.invalidLineMetrics`.
- **Clamp flags**: `y < 0` → `clampedToTop` at line 0; `y >= totalHeight` →
  `clampedToBottom` at last line; `y == 0` → `inRange` at line 0;
  `y == totalHeight` → `clampedToBottom`.
- **Exact-boundary resolution**: `y == offset(i)` → line `i` (`inRange`).
- **Non-uniform metrics**: a hand-built provider with varied heights (e.g.
  `[10, 30, 5, 50]`) — verify each boundary and mid-span `y` maps to the correct
  line, independent of the uniform oracle.
- **Single-line document**: every in-range `y` → line 0 `inRange`; `y < 0` /
  `y >= total` → the clamp flags.

### Behavior-preservation of the shared-search refactor

Re-run the existing `compute` equivalence-oracle and variable-height tests; they
must pass unchanged. The plan also captures the pre-refactor `--variable-height`
and `--gate` (synthetic) checksums and re-asserts them post-refactor (Decision 3).

## Benchmark Mode (`ViewportBenchmarks`)

New file `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`, modeled on
`VariableHeightBenchmark.swift`:

- **Mode**: add `.lineQuery` to `BenchmarkMode` (`outputName = "line_query"`),
  `--line-query` to `BenchmarkOptions.parse`/usage, and a `runLineQueryBenchmarks`
  arm in `BenchmarkProgram.runBenchmarks`.
- **Scenarios**: large synthetic docs (e.g. `1k`, `100k`, `1m` lines) over a
  `LineMetricsSource` (uniform and/or the non-uniform `variableHeights` generator
  reused from `VariableHeightBenchmark`), each with `p95`/`p99` budgets.
- **Workload**: per operation, derive a deterministic `y` spanning in-range and
  out-of-range values (reusing `deterministicScrollOffset` / a deterministic
  fraction of `totalHeight`, with a slice of samples pushed below 0 and above
  `totalHeight` to exercise both clamp branches), call `lineAt(y:metrics:)`, and
  fold the returned `lineIndex` and an integer encoding of the `clamp` case into a
  running **checksum** (determinism guard, matching every other benchmark).
- **Gate**: `--line-query --gate` enforces `p95`/`p99` budgets and exits non-zero
  on regression; without `--gate` it asserts `failureCount == 0`. Budgets are
  macOS-calibrated; the plan records the observed numbers and sets budgets with the
  project's customary headroom.

`--gate` validity is extended to `.lineQuery` in `BenchmarkOptions.parse`
(Decision 6).

## CI

**No `.github/workflows/swift-ci.yml` change.** The `--line-query --gate` is a
local gate this slice (Decision 6). The required job contexts, docs-only path,
iOS/WASM jobs, and the `Main` ruleset are all unchanged. CI promotion is the
recommended Slice 28.

## Verification

Recorded in `docs/superpowers/verification/2026-06-21-vertical-position-query.md`:

- `swift test` — host unit tests (new oracle + unit tests green; existing suite
  unchanged count + 0 failures).
- `swift build -c release`.
- `swift run -c release ViewportBenchmarks -- --line-query --gate` →
  every scenario `gate=pass`; record p95/p99 and checksums.
- Existing gates still green and **checksum-identical** (behavior-preservation of
  the shared-search refactor): `--gate`, `--variable-height --gate`,
  `--variable-height-mutation --gate`, `--structural-mutation --gate`,
  `--bulk-structural-mutation --gate`.
- `--memory-shape` invariant `pass` (the query is O(1) memory; the invariant must
  not regress).
- Foundation-free scans: `rg -n "Foundation" Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders` → empty (exit 1).
- `./.github/scripts/cross-target-compile.sh --self-test`, then the iOS (blocking)
  and WASM (observational) cross-target paths for both `TextEngineCore` and
  `TextEngineReferenceProviders`.
- Hosted PR run + post-merge push run IDs, verified at **step level**, recorded in
  the post-merge follow-up (per the Slice 26 stale-on-write lesson: record the
  PR-head proof against the stable final head in the post-merge doc, never against
  a pre-final commit).

## Acceptance Criteria

1. `ViewportVirtualizer.lineAt(y:metrics:) -> LineQuery` is public, stateless, and
   behaves exactly per the Decision 4 table.
2. The equivalence oracle passes: `lineAt` equals the uniform closed form
   (index + clamp flag) across the full `y` sweep, for multiple `(lineCount,
   lineHeight)` including `lineCount == 1`.
3. All listed unit and failure tests pass; `.empty` and all four
   `ViewportValidationError` outcomes are covered.
4. The shared-search refactor is behavior-preserving: existing `compute`
   tests/oracle and all five existing gates pass with identical checksums.
5. `--line-query` benchmark runs; `--line-query --gate` enforces budgets and is
   rejected only where the other gateable modes are accepted; `--gate` stays
   rejected with `--range-only`/`--memory-shape`/`--memory-observation`.
6. Foundation-free scans empty; iOS cross-target compile green (blocking); WASM
   observational; `--memory-shape` invariant `pass`.
7. Full paper trail (spec, plan, verification, post-slice review) on a
   `slice-27-vertical-position-query` branch; one PR; conventional commits.

## Risks And Gaps

### Result carries no geometry (deferred richness)

A caller doing tap-to-caret wants the line's `y`/`height` and the fractional offset
within the line. This slice returns only `lineIndex` + `clamp`; such a caller makes
one or two extra `offset(ofLine:)` probes. If real usage shows this is a common hot
path, a future slice can add a geometry-bearing query (or a `pointAt(x:y:)` once the
horizontal axis exists) without breaking `lineAt` — `LineQuery` is additive. Chosen
now for minimal surface (Decision 7).

### Budgets are macOS-calibrated and local-only

Like every gate before CI promotion, the `--line-query` budgets are macOS-derived
and unenforced in hosted CI until Slice 28. A regression in `lineAt` would be caught
locally but not block merge until promotion. This matches the established rhythm and
is an accepted, time-boxed gap.

### Shared-search refactor touches a hot, gate-covered path

Relaxing `firstLineTopAtOrBelow`'s access changes no logic, but it sits under the
already-blocking variable-height and synthetic gates. The behavior-preservation
checks (identical checksums, unchanged oracle) are mandatory, not optional — the
same discipline that made Slice 26's `deterministicIndex` extraction auditable.

### Contract-trusting total-height check

For a non-empty document the `LineMetricsSource` contract guarantees a finite,
strictly-positive total height; the explicit non-finite/`<= 0` check is defensive
parity with `compute`, not a guarantee the core can fully enforce against a
misbehaving provider mid-document. Consistent with the existing variable-height
path's contract posture.

## Future Slices

- **Slice 28 (recommended next): promote `--line-query --gate` to a blocking hosted
  CI gate**, completing the functional → promotion pair, exactly as Slices 15 / 21 /
  24 / 26 did for the prior four modes.
- **Geometry-bearing / point queries**: a richer result with the located line's
  span, and eventually `pointAt(x:y:)` once a horizontal axis exists.
- **Horizontal axis** (x / width, max-width query, horizontal virtualization) and
  **wrap-aware visual rows** remain the larger future capabilities flagged by the
  Slice 26 review; each needs its own brainstorm.
