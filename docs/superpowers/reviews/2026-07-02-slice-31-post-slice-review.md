# Slice 31 Post-Slice Review

Date: 2026-07-02

## Scope Reviewed

This review covers Slice 31: **geometry-bearing vertical query**. It adds
`ViewportVirtualizer.lineGeometryAt(y:metrics:)`, the geometry-bearing companion to
the Slice 27 `lineAt(y:metrics:)`. Where `lineAt` answers *"which line?"*
(`lineIndex` + clamp), `lineGeometryAt` answers *"which line, and where within
it?"* — it returns the located line's box (`LineGeometry`: index, top `y`, height),
the within-line `fractionInLine`, and the same clamp flag `lineAt` produces. This is
the primitive that tap-to-caret / selection / hit-test consumers need, and the first
step of the pivot from vertical-axis *optimization* (Slices 27→30) to *capability*.

It was the Slice 30 post-slice review's recommended **Option A** (geometry-bearing
vertical query), and the user-selected direction at the A-vs-C product call the
review surfaced: deepen the vertical axis toward editing affordances rather than
open the horizontal/wrap axis.

Like the vertical-query capability slices before it (Slice 27's `lineAt`), this
slice is **functional and adds a local gate only**: it ships a
`--line-geometry-query` benchmark mode with a **local** `--gate` but does **not**
wire it into hosted CI. Promotion to a blocking hosted gate is deferred to the
recommended Slice 32, exactly as `--line-query` → Slice 28. So this slice carries
**CI-promotion debt** forward (unlike the two prior optimization slices, which
reused existing gates and left none) — that is the one governance follow-up.

The change is deliberately **additive and composed**, touching no shared search or
provider path:

- Two new public types (`LineGeometryQuery`, `LineGeometryLocation`) in
  `ViewportTypes.swift`, **reusing** the existing `LineGeometry` box and
  `LineLocation.Clamp` flag rather than minting parallel vocabulary.
- One new method `lineGeometryAt(y:metrics:)` in `PositionQuery.swift`, which
  **delegates to `lineAt`** for validation, the located index, and the clamp — so
  index/clamp **parity with `lineAt` holds by construction** — then reads two
  `offset(ofLine:)` probes (`i`, `i+1`) to build the box and computes the fraction.
- No change to `lineAt`, `compute`, the `LineMetricsSource` protocol, `LineQuery`,
  or any reference provider. The only provider-file touch is a one-line doc-comment
  update to the `offset(ofLine:)` stability precondition (adding `lineGeometryAt` to
  the enumerated operations).

The slice was delivered through **two** PRs, both now merged:

- PR #59 (`slice-31-geometry-bearing-vertical-query`), title *"Slice 31:
  geometry-bearing vertical query"*, verified head
  `dff83f63bf34c3374bddad42b5c2324a86c95a89` (`dff83f6`), merged to `main` as
  `f364b452603c809611e0657144b826b27e1f179c` (`f364b45`) by `maldrakar` at
  2026-07-02T11:42:45Z — the two types, the method, the doc-comment update, the
  benchmark mode + local gate, the tests, the doc updates, and the verification
  record's local + PR-head + hosted sections.
- PR #60 (`slice-31-post-merge-verification`), title *"Record Slice 31 post-merge
  proof"*, merged as `0fd8b5e6efb7c02023f119af22a9e0629f1dd635` (`0fd8b5e`, current
  `main` HEAD) by `maldrakar` at 2026-07-02T12:24:03Z — the docs-only follow-up
  (`97c5c51`) that filled the verification record's `Hosted verification` section
  with the real merged-code push run.

**Both PRs are merged at review time**, so `main`'s verification record carries real
hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-29-geometry-bearing-vertical-query-design.md`
- `docs/superpowers/plans/2026-06-29-geometry-bearing-vertical-query.md`
- `docs/superpowers/verification/2026-06-29-geometry-bearing-vertical-query.md`
- `docs/superpowers/reviews/2026-06-29-slice-30-post-slice-review.md`
- `Sources/TextEngineCore/PositionQuery.swift`,
  `Sources/TextEngineCore/ViewportTypes.swift`,
  `Sources/TextEngineCore/LineMetricsSource.swift`
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`,
  `Sources/ViewportBenchmarks/BenchmarkProgram.swift`,
  `Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift`,
  `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- `Tests/TextEngineCoreTests/LineGeometryAtTests.swift`,
  `Tests/TextEngineCoreTests/LineGeometryAtEquivalenceTests.swift`,
  `Tests/TextEngineCoreTests/LineGeometryAtQueryCountTests.swift`,
  `Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift`
- `AGENTS.md`
- PR #59 / #60 metadata, hosted run evidence (step-level conclusions), merge
  parentage, and the merged Slice 31 diff

The reviewed Slice 31 range (PR #58 merge → current `main` HEAD), excluding this
review document itself, is:

```text
56d4af2..0fd8b5e
```

`git merge-base 56d4af2 0fd8b5e` returns `56d4af2`, confirming the Slice 30 review
merge (PR #58, `56d4af2`) is a clean ancestor and the range captures exactly the
Slice 31 work. Merge parentage confirmed via `git rev-list --parents`: `f364b45`'s
parents are the base `56d4af2` and the verified PR head `dff83f6`; `0fd8b5e` (PR #60)
merges `97c5c51` onto `f364b45`.

## Product Brief Alignment

The brief (`docs/initial-project-brief.md`) wants a headless
layout/virtualization core that supports realistic editing/scrolling of 100k+ line /
>10 MB documents, stays Foundation-free and Embedded-compatible, keeps core-owned
memory sub-linear in document size, compiles for iOS and WASM without source
changes, and blocks merge on benchmark regression.

Slice 27 introduced the y → line mapping `lineAt` and **explicitly deferred**
geometry — its result was `lineIndex` + clamp only, with the follow-up named
precisely ("a richer result with the located line's span ... added as a new
method/result type, not a new `LineQuery` case"). Slices 28→30 completed the
vertical-query *performance* arc (`--line-query` became a blocking gate; both
`lineAt` and `compute` became single O(log N) balanced-tree descents), and the
Slice 30 review found that thread complete and handed off to a pivot from
optimization to capability.

Slice 31 executes exactly the deferred Slice 27 follow-up and the Slice 30 pivot:
it surfaces the geometry that `lineAt` already locates, as the authoritative
companion query, so a tap-to-caret consumer no longer re-implements the
box-rebuild + within-line-fraction + clamp conventions the core owns. It honors
every hard constraint: the core stays Foundation-free (both scans empty), no
dependency is added, the query adds **no** core-owned memory (O(1) core memory
preserved — a constant number of `offset(ofLine:)` probes on top of `lineAt`), and
the additive public-API change is cross-target verified for iOS (blocking) and WASM
(observational).

Because the query **composes over `lineAt`** rather than adding a new search, its
per-provider cost class is exactly `lineAt`'s: O(log N) for O(1)-offset providers
(uniform/prefix-sum) and for the balanced tree (Slice 29's native index descent),
and O(log²N) **inherited** for `FenwickLineMetrics` (O(log N) `offset` × generic
fallback index search — Fenwick has no native `lineIndex` override). The two extra
geometry probes are a constant factor, never a log factor.

## Delivered Design

Merged Slice 31 diff, Sources/Tests only (`56d4af2..0fd8b5e`):

```text
 Sources/TextEngineCore/LineMetricsSource.swift              |   3 +-
 Sources/TextEngineCore/PositionQuery.swift                  |  36 ++
 Sources/TextEngineCore/ViewportTypes.swift                  |  23 ++
 Sources/ViewportBenchmarks/BenchmarkOptions.swift           |  11 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift           |   2 +
 Sources/ViewportBenchmarks/LineGeometryQueryBenchmark.swift | 152 ++
 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift        |   2 +
 Tests/TextEngineCoreTests/LineGeometryAtTests.swift         | 123 ++
 Tests/TextEngineCoreTests/LineGeometryAtEquivalenceTests.swift | 78 ++
 Tests/TextEngineCoreTests/LineGeometryAtQueryCountTests.swift  | 125 ++
 Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift | 39 ++
 11 files changed, 592 insertions(+), 2 deletions(-)
```

(Plus the spec, plan, and verification docs — `docs/superpowers/**` — and the
`AGENTS.md` update. No `Package.swift` change.)

### The two new public types (Decision 1)

`ViewportTypes.swift` gains a three-case result enum mirroring `LineQuery`'s
located/empty/failure discipline, carrying a location struct that **reuses** the
existing `LineGeometry` box and `LineLocation.Clamp` flag:

```swift
public enum LineGeometryQuery: Equatable {
    case geometry(LineGeometryLocation)
    case empty
    case failure(ViewportValidationError)
}

public struct LineGeometryLocation: Equatable {
    public let geometry: LineGeometry       // reused core box (index, y, height)
    public let fractionInLine: Double       // 0.0 top / (y-top)/height in-range / 1.0 bottom
    public let clamp: LineLocation.Clamp    // reused, not duplicated
    public init(geometry: LineGeometry, fractionInLine: Double, clamp: LineLocation.Clamp) { … }
}
```

This is the right shape. The new surface is intentionally **two new public types
only** — the line box reuses `LineGeometry` (already public, already what
`VariableLineGeometryCursor` streams) and the clamp reuses `LineLocation.Clamp`, so
`lineGeometryAt`, `lineAt`, and the geometry cursor speak one vocabulary for "a
line's box" and "edge clamp state." The `.empty` / `.failure` cases parallel
`LineQuery` exactly, so the two query results are switched the same way and
validation outcomes map 1:1. Centralizing `fractionInLine` in the core is the
point: the clamp-edge fraction contract lives in one place instead of every caller
re-deriving `(y - top) / height` and re-deciding the edges. It is **additive and
non-breaking** — a new method and new types, not a new `LineQuery` case (which would
be source-breaking for client `switch`es), honoring the Slice 27 extension rule.

### `lineGeometryAt` composes over `lineAt` — parity by construction (Decisions 2, 3)

`PositionQuery.swift` gains `lineGeometryAt` right next to `lineAt`, a single generic
over `LineMetricsSource` with no fixed-height overload (parity with `lineAt`):

```swift
switch lineAt(y: y, metrics: metrics) {
case let .failure(error): return .failure(error)   // validation single-sourced
case .empty:              return .empty             // no line, no geometry
case let .line(location):
    let top = metrics.offset(ofLine: location.lineIndex)
    let bottom = metrics.offset(ofLine: location.lineIndex + 1)
    let box = LineGeometry(lineIndex: location.lineIndex, y: top, height: bottom - top)
    let fraction: Double
    switch location.clamp {
    case .clampedToTop:    fraction = 0.0
    case .clampedToBottom: fraction = 1.0
    case .inRange:         fraction = (y - top) / box.height
    }
    return .geometry(LineGeometryLocation(geometry: box, fractionInLine: fraction, clamp: location.clamp))
}
```

I traced the whole surface:

- **Parity by construction.** Index, clamp, and the entire validation ladder come
  straight from `lineAt`; `lineGeometryAt` structurally *cannot* disagree with
  `lineAt` on which line or which clamp. That collapses the correctness burden to
  the *geometry* only, which the oracles then pin.
- **The fraction contract matches Decision 3 exactly.** `clampedToTop` → `0.0` (tap
  above the document caret-positions at the very top of line 0), `clampedToBottom` →
  `1.0` (tap below → very bottom of the last line), `inRange` → the exact arithmetic
  ratio `(y - top) / height` in `[0, 1)` by the half-open `[offset(i), offset(i+1))`
  contract, `0.0` at an exact line top. `1.0` is only ever a clamp sentinel for
  in-range queries (modulo the documented floating-point upper-edge caveat).
- **`box.height = bottom - top` is finite and strictly positive** for any valid
  provider (`offset` is a strictly increasing chain), so the division has no
  zero-height special case, and `lineAt`'s `invalidLineMetrics` guard already
  rejects a degenerate provider before geometry is computed.
- **No new search, no provider change.** The located index already came from the
  (possibly provider-native) `lineIndex(containingOffset:)` inside `lineAt`; the two
  extra `offset(ofLine:)` probes reuse the existing offset contract. This is a
  conscious accept of two extra probes (Decision 4) rather than threading a native
  `(index, top, bottom)` one-walk descent — that is a deferred Future Slice.

### Cost envelope (Decision 4) is exactly `lineAt`'s

The query issues `lineAt`'s `offset(ofLine:)` queries plus **two** more on the
located branch — a constant number of probes plus `lineAt`'s single index search —
so query count stays O(log N) and core memory O(1). The two geometry probes are a
constant factor, so the per-provider asymptotic class equals `lineAt`'s: O(log N)
for uniform/prefix-sum and for the balanced tree (native index descent), O(log²N)
inherited for Fenwick. This is verified structurally by the query-count tests, not
just asserted (below).

### Benchmark mode + local gate (Decision 5)

`BenchmarkOptions.swift` adds the `.lineGeometryQuery` mode
(`outputName = "line_geometry_query"`), the `--line-geometry-query` flag with its
mode-exclusivity guard, and adds `.lineGeometryQuery` to the `--gate`-valid set (it
stays rejected with `--range-only`/`--memory-shape`/`--memory-observation`).
`LineGeometryQueryBenchmark.swift` (new, modeled on `LineQueryBenchmark.swift`)
drives five scenarios — three `uniform` (1k/100k/1m) and **two `balanced_tree`**
(100k/1m, the realistic O(log N)-offset path whose per-query constant a
uniform-only suite would under-measure) — with a deterministic `y` spanning in-range
and both out-of-range clamp branches, folding `geometry.lineIndex`, an integer clamp
encoding, and a quantized `fractionInLine` into a determinism checksum.

### Docs

`AGENTS.md`'s architecture paragraph now describes `lineGeometryAt` as the
geometry-bearing companion to `lineAt` (box + within-line fraction + clamp, composed
over `lineAt` + two `offset` probes, O(1) core memory, per-provider cost class equal
to `lineAt`'s), and the Commands / benchmark-flags lists gain the
`--line-geometry-query` / `--line-geometry-query --gate` entries. The CI section is
unchanged because the workflow is unchanged (Decision 5). The
`LineMetricsSource.offset(ofLine:)` stability precondition adds `lineGeometryAt` to
the enumerated operations that must observe one consistent snapshot — the identical
update Slice 27 made when it added `lineAt`.

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `0fd8b5e`)

- `git diff --stat 56d4af2..0fd8b5e -- Sources Tests Package.swift` → confined to
  the three core files, the three benchmark files, and the four test files. No
  `Package.swift` change.
- `git diff --check 56d4af2..0fd8b5e -- Sources Tests` → no output, exit `0` (no
  whitespace errors).
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `swift build -c release` → `Build complete!` (exit 0).
- `swift test` → **160 tests, 0 failures**, plus the expected empty Swift Testing
  harness line. Up from 140 at the Slice 30 baseline — the twenty new tests landed
  (12 `LineGeometryAtTests`, 2 `LineGeometryAtEquivalenceTests`, 5
  `LineGeometryAtQueryCountTests`, 1 `BalancedTreeLineMetricsTests`).
- `swift run -c release ViewportBenchmarks -- --line-geometry-query --gate` → all
  five scenarios `gate=pass`, 0 failures; the five checksums are byte-identical to
  the verification record (`160641440000`, `267505512960`, `799841600000`,
  `223985600000`, `852321495040`), and every scenario lands ~1000× under budget
  (largest: balanced_tree_1m p95=191 ns / p99=236 ns against 600k / 1.2M budgets).
- `swift run -c release ViewportBenchmarks -- --line-query --gate` → all five
  scenarios `gate=pass`; all five checksums byte-identical to the record
  (`641440000`, `63985556480`, `639841600000`, `63985600000`, `639841547520`),
  confirming this slice touched no shared search/provider path — `lineAt` is
  unaffected.

### The correctness payoff (the point of the slice)

The evidence is layered and structural:

1. **Structural uniform oracle (products, not quotients)** —
   `testStructuralEquivalenceOverRepresentableUniformMetrics` picks
   exactly-representable heights (`[1.0, 10.0, 16.0, 12.5, 256.0]`) and line counts
   (`[1, 2, 3, 100, 100_000]`), **builds each `y` from a product** over the height,
   and asserts the full `LineGeometryQuery`: below-document clamp (`frac 0.0`, line 0
   box), exact line tops (`frac 0.0`, in-range), mid-line (`frac 0.5`, in-range), and
   at/past the end (`frac 1.0`, clamped-to-bottom, last-line box). Because every `y`
   is a product over a representable height, the box `y`/`height` and the fraction
   are known exactly by construction — this dodges the `floor(y/lineHeight)`
   boundary fragility the same way the Slice 27 `lineAt` oracle did.
2. **Index/clamp parity with `lineAt`** —
   `testIndexAndClampParityWithLineAt` sweeps a `y` set (clamps, exact tops,
   interior) and asserts `lineGeometryAt(y).geometry.lineIndex == lineAt(y).lineIndex`
   and the clamp flags match, pinning the construction guarantee as a regression
   test.
3. **Reference-provider equivalence oracle** —
   `testLineGeometryAtWithBalancedTreeMatchesPrefixSumOracle` compares
   `lineGeometryAt` over a `BalancedTreeLineMetrics` against `lineGeometryAt` over a
   `PrefixSumLineMetrics` oracle built from the same 1,000 heights, across a sampled
   scroll sweep **including the two out-of-range clamps** (`-1.0`, `total`,
   `total + 100`), and **re-asserts after `setHeight` / `insertLines` / `removeLines`
   mutations** so the geometry tracks the mutated tree. This is the provider-level
   proof that the composed geometry is byte-consistent with `offset(ofLine:)` under
   the real O(log N)-offset provider and after structural edits.
4. **Query-count / envelope + native-dispatch order** — over `CountingLineMetrics`,
   the per-path `offset(ofLine:)` counts match the Decision 4 table exactly:
   non-finite `y` → `0` probes, empty document → `1`, both clamp branches → `4`,
   in-range → `≤ 2 + (ceilLog2(n)+1) + 2` and `< 100` (proving no accidental linear
   scan and the O(log N)/O(1) envelope). The load-bearing one is
   `testDispatchesToNativeHookThenTakesTwoGeometryProbesInOrder`: over a
   `NativeSearchMetrics` with an ordered event log, an in-range `y = 31` produces
   exactly `[.offset(0), .offset(4), .native(31.0), .offset(2), .offset(3)]` —
   `lineAt`'s two contract probes, its **native** index dispatch, then the two
   geometry probes, *in order*. This is the Slice 29 lesson applied: it directly
   exhibits that the composed query reuses `lineAt`'s native index search and does
   **not** silently fall back to a generic search or re-search redundantly, and that
   the descent count is constant (hence O(log N), not O(log²N)) over a native
   provider.

### Timing (one-off observation, not correctness proof)

The `--line-geometry-query --gate` numbers confirm the constant-factor cost: the
uniform scenarios run at ~16–22 ns p95 (O(1)-offset), the balanced-tree scenarios at
~133–191 ns p95 (each query is a constant number of O(log N) tree descents,
including the two added geometry probes) — the expected higher-constant O(log N)
shape the balanced-tree scenario was included to measure. All far inside budget.

### Hosted runs (verified live via `gh`, at step-log level)

Re-verified during this review at the **step** level, not just the job conclusion,
per the project's "a green job can hide a dead `continue-on-error` step" lesson:

- **PR #59 full-code run `28473489678`** (head `dff83f6`, event `pull_request`):
  conclusion `success`; all three required jobs `success` (Host tests and benchmark
  gate `84391993880`, iOS cross-target compile `84391993901`, WASM cross-target
  observation `84391993891`). The host job ran the full heavy path — step `Complete
  docs-only PR` `skipped` (correctly **not** docs-only), all six blocking latency
  gates `success`, and the PR-only realistic-observation step `success`.
- **Post-merge push run `28587326869`** on merge commit `f364b45` (event `push`,
  branch `main`): conclusion `success`; all three required jobs `success` (Host
  `84762068561`, iOS `84762068516`, WASM `84762068490`). Host job `84762068561` ran
  the full heavy path on merged code — step `Complete docs-only PR` `skipped`; all
  six blocking latency gates (Run synthetic / variable-height / variable-height
  mutation / structural mutation / bulk structural mutation / line query benchmark
  gate) ran and passed; step `Observe realistic provider relative performance`
  correctly `skipped` on the `push` event (it is the PR-only `continue-on-error`
  observation). **This is the merged-code evidence anchor for Slice 31.**

The new `--line-geometry-query` gate is **local only** this slice (CI promotion
deferred to Slice 32), so the hosted gate list is unchanged — six blocking latency
gates, exactly as before. PR #60 is docs-only (it only filled the verification
record's `Hosted verification` section — confirmed: its sole changed file is
`docs/superpowers/verification/2026-06-29-geometry-bearing-vertical-query.md`), so
the workflow has not changed since `f364b45` and run `28587326869` still represents
current `main`'s behavior. The cross-target self-test (`self_test=pass`) and the full
local iOS device/simulator + WASM/embedded-WASM compile (`blocking_failures=0
exit=0`) for both `TextEngineCore` and `TextEngineReferenceProviders` are recorded in
the verification doc against the additive public-API change.

## Git History

Reviewed Slice 31 commits (PR #59 → #60):

```text
606e085 docs: add geometry-bearing vertical query design
b1a5ad7 docs: address spec review (perf contract, doc-comment, dispatch test)
cc0173c docs: correct per-provider perf to lineAt parity (Fenwick is O(log^2 N))
91dbb2e docs: add geometry-bearing vertical query plan
7e8138e feat: add geometry-bearing lineGeometryAt query
c80e227 test: pin lineGeometryAt geometry against uniform oracle and lineAt parity
ada71bd test: prove lineGeometryAt query-count envelope and native dispatch order
e62fe45 test: prove balanced-tree lineGeometryAt equals prefix-sum oracle
d468757 feat: add --line-geometry-query benchmark mode and local gate
454dedc docs: document lineGeometryAt and --line-geometry-query gate
dff83f6 docs: record geometry-bearing vertical query verification
f364b45 Merge pull request #59 …
97c5c51 docs: record slice 31 post-merge proof
0fd8b5e Merge pull request #60 …
```

Clean, one-logical-step-per-commit with correct conventional-commit prefixes: spec
→ plan precede code; two `docs:` commits (`b1a5ad7`, `cc0173c`) show the spec took
**two rounds of review** before implementation (the perf contract was corrected to
`lineAt` parity, explicitly recording that Fenwick stays O(log²N) — an honest,
load-bearing correction, not a silent overclaim); the method lands as one `feat:`
(`7e8138e`); the three test suites land as separate `test:` commits
(`c80e227` uniform oracle + parity, `ada71bd` query-count + native dispatch,
`e62fe45` balanced-tree equivalence) with the benchmark mode + local gate as its own
`feat:` (`d468757`); durable docs (`454dedc`) and verification (`dff83f6`) are
isolated. The two-PR split (implementation + local/PR-head/hosted proof, then
post-merge proof) is the standard pattern.

## Code Review Findings

Reviewed across correctness, composition semantics, scope discipline, evidence
integrity, and the hard constraints.

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, the geometry is correct (structural-uniform oracle,
`lineAt`-parity test, balanced-tree equivalence oracle across a scroll sweep + after
mutations, and byte-identical existing-gate checksums), the composition reuses
`lineAt`'s native index dispatch and takes exactly two ordered geometry probes
(proven by the event-log dispatch test), validation is single-sourced through
`lineAt`, the scope is tight (no shared search/provider path touched), and the
Foundation-free / zero-dependency / O(1)-core-memory invariants are intact and
cross-target verified.

### P2 / Production Readiness

None. The merged result is correct and proven green on merged code at step level
(`28587326869`).

### P3 / Minor But Valid

**1. `LineGeometryQuery`'s located case is named `.geometry`, while the sibling
`LineQuery`'s is `.line`.** A caller switching both results uses `.line(loc)` for one
and `.geometry(loc)` for the other. This is a deliberate, defensible choice (the
payload *is* geometry, and `.geometry` reads well at the call site), and the
`.empty` / `.failure` cases do parallel `LineQuery` exactly — but the located-case
naming asymmetry is a small vocabulary seam worth noting. Cosmetic; no action.

**2. `fractionInLine` floating-point at the in-range upper edge.** For an in-range
`y` extremely close to `bottom`, the exact ratio `(y - top) / height` may round
toward `1.0`, which is indistinguishable from the `clampedToBottom` sentinel `1.0`.
The spec documents and accepts this (consistent with how the engine trusts the
`offset` contract elsewhere), and a consumer that needs to disambiguate has the
`clamp` flag. Documented, accepted — not a defect.

**3. Carried-forward provider costs (documented Non-Goals / Future Slices).**
(a) `FenwickLineMetrics` stays O(log²N) for `lineGeometryAt` — inherited from
`lineAt`'s generic-fallback index search (Fenwick has no native `lineIndex`
override), not introduced by the two geometry probes. (b) The balanced tree pays ~5
O(log N) descents where a provider-native one-walk `(index, top, bottom)` hook would
fold them to ~2 — a constant-factor optimization, not an asymptotic one, deferred
as a Future Slice (the Slice 27→29 capability→native pattern applied to geometry).
(c) Uniform/prefix-sum still answer the index search via the generic O(log N)
fallback (carried Slice 29/30 P3). All three are conscious, documented deferrals,
not gaps.

No P3 changes whether the merged result is correct.

## Risks And Gaps

### CI-promotion debt: the `--line-geometry-query` gate is local-only

This is the one governance follow-up. The new gate enforces its macOS-calibrated
budgets **locally** but is not wired into `.github/workflows/swift-ci.yml`, so a
`lineGeometryAt` latency regression would be caught locally but would **not** block a
merge until the gate is promoted. This is the established functional → promotion
rhythm (the fifth such pair before it: variable-height → 15, variable-height-mutation
→ 21, structural-mutation → 24, bulk-structural-mutation → 26, line-query → 28), and
the recommended Slice 32 closes it. Notably, this ends the two-slice streak (29, 30)
of *zero* governance debt: those were optimization slices reusing existing gates;
this is a capability slice that adds a new measurable path, so it owes a promotion
slice — as designed.

### Budgets are macOS-calibrated and local-only until promotion

Like every gate before CI promotion, the `--line-geometry-query` budgets are
macOS-derived and unenforced in hosted CI until Slice 32. Accepted, time-boxed gap.

### No isolated hosted guard for `lineAt`/`compute` during the interim

Because the new gate is local-only and the query composes over `lineAt`, a
regression *inside* `lineGeometryAt`'s own probes/fraction path is not hosted-gated
until Slice 32. Its correctness is guarded by the merged unit + oracle tests (which
`swift test` runs in the hosted host-tests step), so this is a *latency*-only interim
gap, not a correctness one — and exactly what Slice 32 exists to close.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative observation
remains PR-only `continue-on-error`; budgets remain macOS-derived; the `Main` ruleset
keeps its documented bypass-actor shape. None were in scope for Slice 31.

## Lessons For The Next Slice

1. **Composing a new query over an existing one buys parity for free — and shrinks
   the test surface to the delta.** Delegating `lineGeometryAt` to `lineAt` for
   validation/index/clamp meant index and clamp *cannot* drift, so the oracles only
   had to pin the geometry and fraction. When a new capability is a strict superset
   of an existing query, compose over it rather than re-deriving; the correctness
   burden collapses to the new part.
2. **Prove native-dispatch reuse with an ordered event log, not just a count.** The
   dispatch-order test (`[.offset(0), .offset(4), .native(31.0), .offset(2),
   .offset(3)]`) is what makes "composes over `lineAt`'s native search + exactly two
   ordered geometry probes" a *fact* rather than a claim — it would fail loudly if
   the composed query re-searched or fell back to the generic path. Reuse the
   existing ordered-event-log harness for any future composed/native query.
3. **Correct the perf contract in the spec before writing code, and record the
   correction honestly.** The two spec-review `docs:` commits (`b1a5ad7`, `cc0173c`)
   fixed the per-provider story to `lineAt` parity and explicitly wrote down that
   Fenwick stays O(log²N). Naming the inherited cost up front (rather than
   overclaiming uniform O(log N) everywhere) is why the delivered Decision 4 table
   matches the query-count tests exactly.
4. **A capability slice owes a promotion slice; an optimization slice reusing gates
   does not.** Slices 29/30 left zero governance debt because they optimized
   already-gated paths; Slice 31 adds a new measurable path, so it ships a local gate
   and hands a promotion slice forward. Track which kind of slice you are shipping —
   it determines whether a follow-up gate slice is owed.
5. **Reuse public vocabulary (`LineGeometry`, `LineLocation.Clamp`) instead of
   minting parallel types.** Keeping `lineGeometryAt`, `lineAt`, and the geometry
   cursor on one "line box" + "clamp" vocabulary kept the additive surface to two
   types and made the equivalence oracle a direct `LineGeometry` comparison. Prefer
   extending shared types over introducing near-duplicates.

## Slice 32 Candidate Options

### Option A: Promote `--line-geometry-query --gate` to a blocking hosted CI gate

Wire the local gate into `.github/workflows/swift-ci.yml` as the **seventh** blocking
latency gate, completing the functional → promotion pair, exactly as Slices 15 / 21 /
24 / 26 / 28 did for the prior five modes. Zero Swift-source change (a pure
CI/governance slice, mirroring line-query → Slice 28): add the gate step, retune
budgets against hosted Linux if the accumulated x86_64 evidence justifies it, and
verify the required-check contexts are unchanged. Retires this slice's CI-promotion
debt. The smallest, most obvious, lowest-risk next step, and the one this slice was
explicitly designed to hand off to.

### Option B: Provider-native geometry-bearing descent (constant-factor win)

Add an optional `LineMetricsSource` hook returning `(index, top, bottom)` in one
tree walk, default-implemented as today's composed form, overridden by
`BalancedTreeLineMetrics` — the Slice 29/30 defaulted-hook + provider-override +
dispatch-test recipe applied to geometry. Folds the balanced tree's ~5 descents to
~2 (trims the constant, not the asymptotic class). Measurable against the new
balanced-tree benchmark scenario. Best sequenced **after** Option A so the gate that
measures the win is already hosted-blocking.

### Option C: Horizontal / point queries / wrap-aware visual rows

The larger product leap — `pointAt(x:y:)` (building directly on this slice's vertical
`LineGeometryLocation`), horizontal geometry, or wrapping/visual rows. Largest design
surface; needs a fresh brainstorm + spec. The natural continuation of the
capability pivot once the vertical geometry query is CI-protected.

### Option D: Verified closed-form uniform override (carried Slice 29/30 P3)

O(1) overrides for the uniform/prefix-sum providers' native hooks, boundary-safe
against the equivalence oracles. Retires the last fallback-bound common provider.
Small, clean; lower product value.

### Option E: WASM blocking / Linux budget re-baseline (standing infra)

Promote WASM cross-target from observational to blocking (gated on stable SDK
provisioning), or re-derive Linux-native budgets from the accumulated x86_64
evidence. Standing hygiene; independent of the capability arc.

## Recommended Slice 32 Selection

Recommended Slice 32 is **Option A — promote `--line-geometry-query --gate` to a
blocking hosted CI gate.**

The reasoning: Slice 31 is a functional capability slice that shipped a new
measurable path behind a **local-only** gate, exactly the pattern each of the five
prior functional modes followed. Every one of those was promoted in the very next
governance slice (15, 21, 24, 26, 28), and the Slice 31 spec/verification named this
promotion as the recommended Slice 32 by design. It is the smallest, lowest-risk,
zero-Swift-change increment; it retires the one piece of governance debt this slice
introduced; and it makes the `lineGeometryAt` latency contract hosted-blocking before
any follow-on (Option B's native descent) tries to optimize against it — so the win
is measured by a gate that actually blocks. Keeping functional work and
CI/governance work in separate slices is the project's standing convention, and this
is the clean CI slice that pairs with Slice 31.

After Slice 32 closes the pair, the project is back at the capability-vs-infra
crossroads the Slice 30 review identified: Option B (native geometry descent, a
constant-factor follow-up best done once its gate is blocking), Option C
(horizontal/point/wrap — the larger product leap that `pointAt(x:y:)` would build on
this slice's `LineGeometryLocation`), or Option E (WASM-blocking / budget re-baseline
infra). That A-then-(B/C/E) direction is worth a product call from the user once the
gate is promoted.

## Slice 31 Review Conclusion

Slice 31 delivered the intended capability increment cleanly:
`ViewportVirtualizer.lineGeometryAt(y:metrics:)` extends the vertical query from
"which line?" to "which line, and where within it?", returning the located line's
`LineGeometry` box, the within-line `fractionInLine`, and `lineAt`'s clamp flag,
delivered as two additive public types (`LineGeometryQuery`, `LineGeometryLocation`)
that reuse the existing box and clamp vocabulary. Because the method **composes over
`lineAt`**, index and clamp parity hold by construction, validation is single-sourced,
and the per-provider cost class is exactly `lineAt`'s — O(log N) for
uniform/prefix-sum and the balanced tree, O(log²N) inherited for Fenwick, with two
constant-factor geometry probes that never add a log factor. The geometry is pinned
by a product-built structural uniform oracle, a `lineAt`-parity test, and a
balanced-tree-vs-prefix-sum equivalence oracle across a scroll sweep and after
mutations; the composition's native-dispatch reuse and exact two-probe order are
proven by an ordered event-log test; and no shared search/provider path was touched
(existing-gate checksums byte-identical, local and hosted).

The review found **no P0, P1, or P2 issues** and **no evidence-accuracy defect**
against the merged result: PR #59's full-code run `28473489678` and the merged-code
push run `28587326869` (merge commit `f364b45`) are both green at step level, with
all six blocking latency gates run and the realistic-observation step correctly
`skipped` on push. The three P3s are minor and carried/cosmetic (located-case naming
asymmetry; documented floating-point upper-edge; deferred Fenwick-native /
balanced-tree-native / uniform-closed-form optimizations). Every hard constraint
holds: Foundation-free, zero-dependency, O(1) core memory, and cross-target verified
(iOS blocking, WASM observational).

The one item this slice hands forward is **CI-promotion debt**: the
`--line-geometry-query` gate is local-only, ending the two-slice zero-debt streak —
by design, because this is a capability slice adding a new measurable path. Slice 31
opens the pivot from vertical-axis optimization to capability and hands off cleanly
to **Slice 32 — promote `--line-geometry-query` to a blocking hosted gate**, the
established next step that retires that debt before any deeper geometry work.
