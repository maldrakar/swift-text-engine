# Slice 27 Post-Slice Review

Date: 2026-06-24

## Scope Reviewed

This review covers Slice 27: the **vertical position-query** capability. It adds
`ViewportVirtualizer.lineAt(y:metrics:)`, a public stateless inverse query that
maps document y offsets back to logical line indexes over the existing
`LineMetricsSource` abstraction. The query uses the same cumulative-offset model
as variable-height layout, reuses the existing `firstLineTopAtOrBelow` binary
search instead of copying it, returns explicit top/bottom clamp metadata, and
keeps the core Foundation-free, zero-dependency, and O(1) in core-owned memory.

The slice also adds the local `--line-query --gate` benchmark mode, with both
O(1)-offset uniform scenarios and realistic `BalancedTreeLineMetrics` scenarios
that exercise the current O(log^2 N) mutable-provider path. The gate is
deliberately **local only** in this slice; CI promotion is the natural follow-up
slice, matching the project's established functional-slice then gate-promotion
cadence.

The implementation PR is merged:

- PR #47 (`slice-27-vertical-position-query`), title *"Slice 27: add vertical
  position query"*, final head
  `16f69c0fb1e0078509d0ad604a2561723f243ddf` (`16f69c0`), merged to `main` as
  `619805e05b152da95b90ca479db91deee51a94b0` (`619805e`).

At review time this branch also includes the docs-only post-merge evidence commit:

- `4b6fd79` (`docs: record slice 27 post-merge proof`) fills the verification
  record's hosted proof with the final PR-head run and the post-merge push run.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-21-vertical-position-query-design.md`
- `docs/superpowers/plans/2026-06-21-vertical-position-query.md`
- `docs/superpowers/verification/2026-06-21-vertical-position-query.md`
- `docs/superpowers/reviews/2026-06-21-slice-26-post-slice-review.md`
- `Sources/TextEngineCore/PositionQuery.swift`
- `Sources/TextEngineCore/ViewportTypes.swift`
- `Sources/TextEngineCore/LineMetricsSource.swift`
- `Sources/TextEngineCore/VariableViewportVirtualizer.swift`
- `Tests/TextEngineCoreTests/LineAtTests.swift`
- `Tests/TextEngineCoreTests/LineAtEquivalenceTests.swift`
- `Tests/TextEngineCoreTests/LineAtQueryCountTests.swift`
- `Sources/ViewportBenchmarks/LineQueryBenchmark.swift`
- `Sources/ViewportBenchmarks/BenchmarkOptions.swift`
- `Sources/ViewportBenchmarks/BenchmarkProgram.swift`
- `Sources/ViewportBenchmarks/SyntheticBenchmarks.swift`
- `AGENTS.md`
- PR #47 metadata and hosted Swift CI runs

The reviewed Slice 27 range, excluding this review document itself, is:

```text
660860d..4b6fd79
```

This range contains the Slice 27 spec/plan, the implementation PR merge, and the
post-merge verification update. It is confined to `TextEngineCore`,
`ViewportBenchmarks`, `Tests/TextEngineCoreTests`, `AGENTS.md`, and `docs/**`.
Fresh name-only diff confirmed **no changes** to `.github/workflows/**`,
`Package.swift`, or `Sources/TextEngineReferenceProviders`.

## Product Brief Alignment

The brief asks for a headless text-rendering core that computes layout geometry
and virtualizes visible rows while remaining independent of UI frameworks,
Foundation-free, zero-dependency, portable to iOS/WASM, and bounded in
core-owned memory. It also requires stable scroll performance on 100k+ line /
10MB+ documents and benchmark evidence for regression-sensitive paths.

Slice 27 fits that direction directly. A real text engine needs inverse vertical
mapping for hit-testing, anchor math, and scroll/caret coordination: given a
document y offset, find the logical line owning that half-open vertical span. The
new API keeps the document outside the core behind `LineMetricsSource`, adds no
rendering/shaping/UI concern, and exposes only Swift value types:

```swift
public static func lineAt<Metrics: LineMetricsSource>(
    y: Double,
    metrics: Metrics
) -> LineQuery
```

The query uses O(log N) `offset(ofLine:)` probes and O(1) core memory. For
`UniformLineMetrics` and prefix-sum providers that means O(log N) wall-clock; for
`BalancedTreeLineMetrics` each offset probe is O(log N), so today's generic query
is O(log^2 N) over that mutable provider. The spec records that honestly, and
the benchmark includes balanced-tree scenarios so the real hot path is measured
instead of hidden behind an O(1)-offset provider.

The one deliberate brief-adjacent gap is CI enforcement: the new line-query
benchmark is local-only until Slice 28. This is not a Slice 27 defect; it follows
the same pattern used for variable-height, mutation, structural-mutation, and
bulk-structural-mutation work. The next slice should promote the gate so
line-query performance regressions block merge just like the previous latency
paths.

## Delivered Design

Merged Slice 27 diff (`660860d..4b6fd79`):

```text
 AGENTS.md                                          |  16 +-
 Sources/TextEngineCore/LineMetricsSource.swift     |   7 +-
 Sources/TextEngineCore/PositionQuery.swift         |  50 ++
 .../VariableViewportVirtualizer.swift              |   2 +-
 Sources/TextEngineCore/ViewportTypes.swift         |  22 +
 Sources/ViewportBenchmarks/BenchmarkOptions.swift  |  11 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift  |   2 +
 .../ViewportBenchmarks/LineQueryBenchmark.swift    | 149 ++++
 .../ViewportBenchmarks/SyntheticBenchmarks.swift   |   2 +
 .../LineAtEquivalenceTests.swift                   |  58 ++
 .../LineAtQueryCountTests.swift                    |  81 ++
 Tests/TextEngineCoreTests/LineAtTests.swift        | 119 +++
 .../plans/2026-06-21-vertical-position-query.md    | 903 +++++++++++++++++++++
 .../2026-06-21-vertical-position-query-design.md   | 547 +++++++++++++
 .../2026-06-21-vertical-position-query.md          | 285 +++++++
 15 files changed, 2243 insertions(+), 11 deletions(-)
```

### Core API

`PositionQuery.swift` adds one extension method on `ViewportVirtualizer`:

```swift
public static func lineAt<Metrics: LineMetricsSource>(
    y: Double,
    metrics: Metrics
) -> LineQuery
```

Its validation order mirrors variable-height `compute`:

1. negative `lineCount` -> `.failure(.negativeLineCount)`
2. non-finite `y` -> `.failure(.nonFiniteValue)`
3. `offset(ofLine: 0) != 0` -> `.failure(.invalidLineMetrics)`
4. empty document -> `.empty`
5. invalid total height -> `.failure(.invalidLineMetrics)`
6. `y < 0` -> first line with `.clampedToTop`
7. `y >= totalHeight` -> last line with `.clampedToBottom`
8. otherwise -> shared binary search and `.inRange`

That is the right shape for this codebase: return-based validation, no throws, no
Foundation types, no provider allocation, and no special fixed-height overload.
The empty-document case is a separate `LineQuery.empty` because there is no
meaningful line index to return, unlike `compute`'s empty range.

### Shared Search Refactor

`firstLineTopAtOrBelow` in `VariableViewportVirtualizer.swift` lost only its
`private` access modifier. The loop body is unchanged. This keeps `lineAt` and
`compute` on one binary-search implementation, which avoids boundary convention
drift. The in-range `lineAt` path only calls the helper after total-height clamp
handling, so the public query returns indexes in `0..<lineCount`; it never exposes
the helper's internal `lineCount` sentinel branch.

### Public Result Types

`ViewportTypes.swift` now carries:

```swift
public enum LineQuery: Equatable {
    case line(LineLocation)
    case empty
    case failure(ViewportValidationError)
}

public struct LineLocation: Equatable {
    public let lineIndex: Int
    public let clamp: Clamp

    public enum Clamp: Equatable {
        case inRange
        case clampedToTop
        case clampedToBottom
    }
}
```

The enum and struct sit with the existing viewport vocabulary, and the nested
`Clamp` avoids leaking a generic top-level name. Reusing
`ViewportValidationError` keeps the public failure vocabulary single-sourced.

### Tests

The test coverage is the important part of the slice:

- `LineAtTests` checks the explicit behavior table: invalid line counts,
  non-finite `y`, invalid metrics, empty docs, top/bottom clamps, exact
  boundaries, non-uniform metrics, and single-line documents.
- `LineAtEquivalenceTests` uses product-built, exactly-representable uniform
  offsets rather than `floor(y / lineHeight)`, so exact-boundary assertions are
  structurally aligned with the binary search.
- `LineAtQueryCountTests` proves the cost envelope deterministically: in-range
  1M-line queries stay under `2 + ceilLog2(n) + 1` offset probes and `< 100`;
  empty docs query only `offset(0)`; clamps avoid the binary search; non-finite
  `y` does not query the provider at all.

The test count rises from 107 to 124: `LineAtTests` (+12),
`LineAtEquivalenceTests` (+1), and `LineAtQueryCountTests` (+4).

### Benchmark

`LineQueryBenchmark.swift` adds the `line_query` benchmark mode:

- uniform 1k / 100k / 1M scenarios measure the O(1)-offset baseline;
- balanced-tree 100k / 1M scenarios measure the real mutable-provider path;
- deterministic in-range and out-of-range y samples exercise `.inRange`,
  `.clampedToTop`, and `.clampedToBottom`;
- returned line index and clamp status feed the checksum;
- `--line-query --gate` enforces local p95/p99 budgets.

`BenchmarkOptions` accepts `--line-query`, includes it in usage text, and keeps
`--gate` rejected for `--range-only`, `--memory-shape`, and
`--memory-observation`. `SyntheticBenchmarks` gets the exhaustive-switch
precondition arm for the new mode, matching prior benchmark additions.

## Verification Evidence Reviewed

### Fresh local checks during this review

Current review branch before adding this file was `slice-27-post-merge-verification`
at `4b6fd79`.

- `git diff --check 660860d..HEAD` -> no output, exit `0`.
- `git diff --name-only 660860d..HEAD -- .github/workflows Package.swift
  Sources/TextEngineReferenceProviders` -> empty.
- `rg -n "Foundation" Sources/TextEngineCore Sources/TextEngineReferenceProviders`
  -> no matches, exit `1`.
- `swift test` -> **124 XCTest tests, 0 failures**; expected Swift Testing
  harness line `0 tests in 0 suites`.
- `swift build -c release` -> `Build complete!`.
- `swift run -c release ViewportBenchmarks -- --line-query --gate` -> all five
  scenarios `gate=pass`, 0 failures, checksums match the verification record:
  `641440000`, `63985556480`, `639841600000`, `63985600000`,
  `639841547520`.
- `swift run -c release ViewportBenchmarks -- --gate` -> all three synthetic
  scenarios `gate=pass`, checksums match the verification record:
  `1319670707200`, `570448232307200`, `18852477646272000`.
- `swift run -c release ViewportBenchmarks -- --memory-shape` -> all five
  scenarios `invariant=pass`.
- `swift run -c release ViewportBenchmarks -- --range-only --gate` -> expected
  exit `1`, `error=--gate cannot be combined with range_only mode`, usage includes
  `--line-query`.
- `./.github/scripts/cross-target-compile.sh --self-test` -> `self_test=pass`.

The full iOS/WASM local cross-target compile outputs are recorded in the
verification doc. I did not rerun those long target builds during this review
because the hosted proof below confirms both required cross-target jobs on the
final PR head and merged code, and the local helper self-test still passes.

### Hosted proof, verified live via GitHub CLI

PR #47 is `MERGED`, base `main`, head branch
`slice-27-vertical-position-query`, final head
`16f69c0fb1e0078509d0ad604a2561723f243ddf`, merge commit
`619805e05b152da95b90ca479db91deee51a94b0`.

PR-head Swift CI run:

- Run `27914867890`, event `pull_request`, conclusion `success`, head
  `16f69c0fb1e0078509d0ad604a2561723f243ddf`.
- Required jobs:
  - `Host tests and benchmark gate` -> job `82598316450`, `success`
  - `iOS cross-target compile` -> job `82598316429`, `success`
  - `WASM cross-target observation` -> job `82598316437`, `success`
- Host job ran the full heavy path: `Complete docs-only PR` was `skipped`; host
  tests, synthetic gate, variable-height gate, variable-height mutation gate,
  structural mutation gate, bulk structural mutation gate, memory-shape,
  RSS observation, and PR-only realistic-provider observation all completed
  successfully.

Post-merge push run:

- Run `28105492251`, event `push`, branch `main`, conclusion `success`, head
  `619805e05b152da95b90ca479db91deee51a94b0`.
- Required jobs:
  - `Host tests and benchmark gate` -> job `83218493520`, `success`
  - `iOS cross-target compile` -> job `83218493497`, `success`
  - `WASM cross-target observation` -> job `83218493488`, `success`
- Host job again ran the full heavy path for merged code. The PR-only
  realistic-provider observation was correctly `skipped` on the push event.

The hosted record correctly does **not** include `--line-query --gate`: the slice
explicitly kept that gate local until the follow-up promotion slice.

## Git History

Reviewed Slice 27 commits:

```text
811822b docs: add vertical position-query design
322adae docs: address spec review for vertical position-query
81de480 docs: purge stale floor oracle and O(1)-query claims from position-query spec
3b341ab docs: add vertical position-query implementation plan
2ab1e03 refactor: share firstLineTopAtOrBelow across the core for position-query reuse
153c051 feat: add ViewportVirtualizer.lineAt vertical position-query
e827d41 test: add structural equivalence oracle for lineAt
ef6768c test: assert lineAt query-count envelope (O(log N), O(1) memory)
668bf79 feat: add --line-query benchmark mode with local gate
dfdb49f docs: document lineAt and the --line-query local gate in AGENTS.md
16f69c0 docs: record local verification sweep for vertical position-query
619805e Merge pull request #47 from maldrakar/slice-27-vertical-position-query
4b6fd79 docs: record slice 27 post-merge proof
```

The history is clean and bisectable: spec corrections precede the plan,
behavior-preserving search sharing is separate from the public API, tests land as
dedicated oracle/query-count commits, benchmark wiring is isolated, and
verification is separate from implementation. Conventional prefixes match the
repo pattern.

## Code Review Findings

Reviewing across architecture, code quality, simplification, integration, QA, and
security concerns:

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None.

### P2 / Production Readiness

None.

### P3 / Minor But Valid

None that warrant a code or paper-trail change. The implementation is scoped,
tested at the right boundaries, and verified on both local and hosted paths. The
line-query gate remains local-only by explicit spec decision; that is tracked
below as the next slice, not a defect in this one.

## Risks And Gaps

### `--line-query --gate` is not hosted yet

This is the single important open gap. A performance regression in
`ViewportVirtualizer.lineAt` would pass hosted CI until the gate is promoted. The
gap is deliberate and time-boxed by the spec, matching the previous functional
slice cadence. It should be closed next.

### Balanced-tree line queries are O(log^2 N)

The generic `lineAt` binary-searches over `offset(ofLine:)`; for
`BalancedTreeLineMetrics`, each offset query is itself O(log N). The benchmark
measures this path and still passes with large local headroom, but a future
provider-native prefix search could turn y-to-line over balanced trees into one
O(log N) descent.

### Result carries no line geometry

The result is intentionally `lineIndex + clamp` only. A caller that needs the
line's span or within-line fraction must make extra provider queries. That keeps
the API minimal now and avoids forcing geometry cost onto index-only callers.
If usage proves the richer result is hot, add a new method/result type rather
than extending `LineQuery` with a source-breaking case.

### Historical plan snippet had one stale expected value (now corrected)

The implementation plan's first illustrative TDD snippet originally carried the
pre-review pasted expectation for `y = 44.0` in offsets `[0, 10, 40, 45, 95]`
(`lineIndex: 1`), while the final code, spec, tests, and verification all use the
correct half-open answer (`lineIndex: 2`). This was never a code defect — only a
stale snippet in a historical plan — and the plan line has since been corrected
to `lineIndex: 2` to match the shipped `LineAtTests.testNonUniformMetricsResolveCorrectly`.
The standing lesson is to treat the spec and final tests as authoritative when a
plan snippet predates a review correction.

### Standing items unchanged

WASM cross-target remains observational; realistic-provider relative observation
remains PR-only `continue-on-error`; the `Main` ruleset keeps its documented
bypass-actor shape. None were in scope for Slice 27.

## Lessons For The Next Slice

1. **The structural oracle was the right guardrail.** The earlier floor-based
   instinct would have made boundary behavior depend on division artifacts. The
   final product-built oracle asserts the same half-open convention used by the
   binary search.
2. **Query-count tests are stronger than benchmark prose.** The benchmark proves
   the path is fast under current budgets; the counting tests prove no accidental
   linear scan or clamp-branch search entered the core.
3. **Benchmarking the balanced-tree provider matters.** A uniform-only gate would
   have measured only the O(1)-offset baseline and hidden the current O(log^2 N)
   mutable-provider path.
4. **Post-merge proof should keep using the evidence-fill pattern.** The current
   branch replaces the verification doc's `Pending` placeholders with final
   PR-head and post-merge run IDs; keep that discipline for every
   source-bearing slice.

## Slice 28 Candidate Options

### Option A: Promote `--line-query --gate` to hosted CI

Wire `swift run -c release ViewportBenchmarks -- --line-query --gate` into the
`Host tests and benchmark gate` job as the sixth blocking latency gate, after the
bulk-structural-mutation gate and before memory-shape diagnostics. Preserve the
trusted docs-only skip, keep required job context names unchanged, and record
final PR-head plus post-merge push proof.

### Option B: Provider-native prefix search

Add an optional provider-native y-to-line primitive so
`BalancedTreeLineMetrics` can answer line-containing-offset in one tree descent
instead of generic binary search over O(log N) offsets. Higher algorithmic value,
but it changes provider/core contracts and needs a careful compatibility design.

### Option C: Geometry-bearing vertical query

Add a richer query returning line index plus y/height or within-line fraction.
Useful for tap-to-caret flows, but wider public API surface. Should be a new
method/result type, not a new `LineQuery` case.

### Option D: Horizontal / wrap-aware next capability

Advance toward x/y point queries, wrapping, or visual rows. Highest product value
and largest design surface; needs a fresh brainstorm/spec.

### Option E: Promote WASM cross-target to blocking

Provision a pinned matching WASM Swift SDK in hosted CI and flip the WASM job
from observational to blocking for both `TextEngineCore` and
`TextEngineReferenceProviders`. This is the strongest standing infra option but
does not close the immediate Slice 27 gate gap.

## Recommended Slice 28 Selection

Recommended Slice 28 is **Option A: promote `--line-query --gate` to hosted CI**.

The reasoning is the same cadence that has kept this repo honest across the
previous four functional/gate pairs: a functional slice adds a local benchmark
gate, then the next governance slice makes that gate block merge. Slice 27
introduced a new public query and a new local gate; leaving it local while moving
to the next functional surface would create a known regression-protection gap.
Promotion is narrow, low-risk, and already specified by Slice 27.

Option B is the highest-value algorithmic follow-up once the gate is hosted: the
balanced-tree path is correct and fast enough today, but provider-native prefix
search is the structural way to move it from O(log^2 N) to O(log N). Option D is
the larger product direction after the line-query path is protected.

## Slice 27 Review Conclusion

Slice 27 delivered the intended functional-core capability cleanly:
`ViewportVirtualizer.lineAt(y:metrics:)` is public, stateless, Foundation-free,
uses the existing `LineMetricsSource` abstraction, returns explicit clamp state,
and shares the variable-height binary search instead of duplicating boundary
logic. The tests cover the behavior table, a structural uniform oracle, and
deterministic query-count bounds; fresh review runs confirmed 124 passing tests,
release build success, `--line-query --gate` success with matching checksums,
synthetic gate success, memory-shape invariants, Foundation-free scans, and the
expected gate rejection behavior. Live GitHub proof shows PR #47 green at the
final head and merged code green on the post-merge push run across all three
required Swift CI jobs.

The review found no P0, P1, P2, or actionable P3 issues. The one real gap is the
intentional local-only state of `--line-query --gate`; Slice 28 should promote it
to the hosted blocking job before the next functional core/provider increment.
