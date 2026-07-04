# Slice 33 Post-Slice Review

Date: 2026-07-04

## Scope Reviewed

This review covers Slice 33: the **horizontal within-line position query**. It
opens the engine's horizontal axis with
`ViewportVirtualizer.columnAt(x:inLine:metrics:) -> ColumnQuery`, the inverse
query `x -> cell` within a single line, over a **new standalone**
`LineHorizontalMetricsSource` provider abstraction. It is the faithful structural
mirror of Slice 27's vertical `lineAt(y:metrics:)`: same validation ladder, same
half-open boundary + clamp semantics, same defaulted binary-search inverse hook,
same "local gate now, CI promotion deferred" rhythm. It was the Slice 32 review's
recommended **Option C** (horizontal / point / wrap), which the user selected and
then scoped tightly to *the horizontal within-line mapping primitive only* — no
2D point query, no sub-cell geometry, no wrap.

This is a **functional core** slice (a genuine capability increment), unlike the
pure CI/governance Slice 32 that preceded it. It ships, all strictly additive:

- a new public protocol `LineHorizontalMetricsSource` (`columnCount(inLine:)`,
  `columnOffset(inLine:column:)`, and a defaulted
  `columnIndex(containingOffset:inLine:)` binary-search hook);
- the public query `ViewportVirtualizer.columnAt(x:inLine:metrics:)` and its
  result types `ColumnQuery` / `ColumnLocation` / `ColumnLocation.Clamp`;
- two providers — `UniformColumnMetrics` **in the core** (the equivalence-oracle
  target, beside `UniformLineMetrics`) and `PrefixSumColumnMetrics` in
  `TextEngineReferenceProviders`;
- a `--column-query` benchmark mode with a **local** gate (5 scenarios);
- 28 new tests and `AGENTS.md` architecture/command documentation.

It changes **no vertical-axis source**, no existing provider or algorithm, no
existing benchmark scenario/budget, no test, no package metadata, and no CI
workflow. `ViewportValidationError` gains two additive cases; every other change
is a pure addition.

The slice was delivered through **two** PRs, both now merged:

- PR #65 (`slice-33-horizontal-position-query`), title *"Slice 33: horizontal
  within-line position query (columnAt)"*, final head
  `c234ce0c2649cac913ffc4a625d213c5f759bb6d` (`c234ce0`), merged to `main` as
  `4e35091da5f7d6c79f6306ec7e27eb4f7d9d6a06` (`4e35091`) by `maldrakar` at
  2026-07-04T19:12:55Z — the protocol, the query, the types, both providers, the
  benchmark mode + local gate, the tests, the `AGENTS.md` update, the spec, the
  plan, and the verification record's local sections.
- PR #66 (`slice-33-post-merge-verification`), title *"Record Slice 33 post-merge
  proof"*, merged as `8c5dfcb6dd60b05cf28a11abea30b5a67555f374` (`8c5dfcb`,
  current `main` HEAD) by `maldrakar` at 2026-07-04T20:24:38Z — the docs-only
  follow-up (`b4c9842`) that filled the verification record's `Hosted Proof`
  section with the real PR-head and merged-code push run IDs.

**Both PRs are merged at review time**, so `main`'s verification record carries
real hosted run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-07-04-horizontal-position-query-design.md`
- `docs/superpowers/plans/2026-07-04-horizontal-position-query.md`
- `docs/superpowers/verification/2026-07-04-horizontal-position-query.md`
- `docs/superpowers/reviews/2026-07-04-slice-32-post-slice-review.md`
- `Sources/TextEngineCore/HorizontalPositionQuery.swift`,
  `LineHorizontalMetricsSource.swift`, `ViewportTypes.swift`,
  and (for the mirror comparison) `PositionQuery.swift`
- `Sources/TextEngineReferenceProviders/PrefixSumColumnMetrics.swift`
- `Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift`,
  `BenchmarkOptions.swift`, `BenchmarkProgram.swift`, `SyntheticBenchmarks.swift`
- `Tests/TextEngineCoreTests/ColumnAt{,Equivalence,QueryCount}Tests.swift`,
  `LineHorizontalMetricsSourceTests.swift`,
  `Tests/TextEngineReferenceProvidersTests/PrefixSumColumnMetricsTests.swift`
- `AGENTS.md` (architecture + commands sections)
- PR #65 / #66 metadata, hosted run evidence (step-level conclusions), merge
  parentage, and the merged Slice 33 diff

The reviewed Slice 33 range (Slice 32 review merge → current `main` HEAD),
excluding this review document itself, is:

```text
ca34ac5..8c5dfcb
```

`git merge-base ca34ac5 8c5dfcb` returns `ca34ac5`, confirming the Slice 32 review
merge (PR #64, `ca34ac5`) is a clean ancestor and the range captures exactly the
Slice 33 work. Merge parentage confirmed via `git rev-list --parents`: `4e35091`
(PR #65)'s parents are the base `ca34ac5` and the verified PR head `c234ce0`;
`8c5dfcb` (PR #66) merges the post-merge-proof commit `b4c9842` onto `4e35091`. A
fresh `git diff --name-only ca34ac5..8c5dfcb` confirms the range is confined to
`AGENTS.md`, `Sources/TextEngineCore/**`,
`Sources/TextEngineReferenceProviders/PrefixSumColumnMetrics.swift`,
`Sources/ViewportBenchmarks/**`, `Tests/**`, and `docs/**` — it does **not** touch
`Package.swift`, `.github/**`, or any vertical-axis source
(`PositionQuery.swift`, `LineMetricsSource.swift`, `VariableViewportVirtualizer.swift`,
the cursors).

## Product Brief Alignment

The brief's headline goal is realistic layout/scroll virtualization of large
documents, and its position queries are the bridge from geometry (pixels) to
document structure (lines, cells). The vertical axis had been built out fully:
mapping (`lineAt`, Slice 27), native O(log N) descent (Slices 29/30), geometry
(`lineGeometryAt`, Slice 31), and blocking CI protection for both (Slices 28/32).
The **horizontal axis did not exist** — there was no way to ask "which cell is at
pixel `x` within this line", the necessary companion to `lineAt` for any 2D
hit-test (click-to-caret, selection, cursor placement).

Slice 33 opens that axis with the first, load-bearing primitive: `columnAt`. It
does so under every hard constraint intact:

- **Foundation-free.** Fresh `rg -n "Foundation" Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders` both return no matches (exit 1). The new
  API surface exposes only `Double`/`Int`/plain structs and enums.
- **O(1) core memory / no linear growth with document size.** `columnAt` is
  stateless and holds a constant number of locals; it queries the provider
  O(log M) times (M = cells in the line) and allocates nothing per cell. Both
  in-core providers add no per-line storage (`UniformColumnMetrics` is
  computed; `PrefixSumColumnMetrics`'s prefix arrays live in the reference target,
  outside the core-memory invariant, exactly as `PrefixSumLineMetrics` does).
- **Zero-dependency, Embedded-compatible.** No new package; the code uses only
  primitives that survive Embedded Swift, and the slice compiles for iOS device +
  simulator (blocking) and WASM + embedded WASM (observational) with no source
  changes.

The slice deliberately claims *only* the mapping primitive. Sub-cell geometry
(caret-x, within-cell fraction — the horizontal analog of `lineGeometryAt`), the
2D `pointAt(x:y:)` composite, and wrap-aware visual rows are all explicitly out of
scope (Decision 6), leaving the smallest coherent increment that still advances
the brief. That is the correct altitude for opening a new axis.

## Delivered Design

Merged Slice 33 diff (`ca34ac5..8c5dfcb`):

```text
 AGENTS.md                                          |   22 +-
 Sources/TextEngineCore/HorizontalPositionQuery.swift |  49 +
 Sources/TextEngineCore/LineHorizontalMetricsSource.swift |  86 +
 Sources/TextEngineCore/ViewportTypes.swift         |   24 +
 Sources/TextEngineReferenceProviders/PrefixSumColumnMetrics.swift | 32 +
 Sources/ViewportBenchmarks/BenchmarkOptions.swift  |   11 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift  |    2 +
 Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift | 168 +
 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift |    2 +
 Tests/.../ColumnAtEquivalenceTests.swift           |   45 +
 Tests/.../ColumnAtQueryCountTests.swift            |  136 +
 Tests/.../ColumnAtTests.swift                      |  163 +
 Tests/.../LineHorizontalMetricsSourceTests.swift   |   41 +
 Tests/.../PrefixSumColumnMetricsTests.swift        |   43 +
 docs/... (spec, plan, verification)                | 2545 +
 17 files changed, 3364 insertions(+), 5 deletions(-)
```

The functional core + provider surface is just **191 lines across 4 files**, all
additive. The rest is the benchmark, the 28 tests, the docs, and the paper trail.

### `columnAt` — a line-by-line mirror of `lineAt` (Decisions 4 & 5)

`HorizontalPositionQuery.swift` is a structural copy of `PositionQuery.swift`'s
`lineAt` with the axis renamed. The validation/branch ladder is identical, step
for step:

| `lineAt` (vertical) | `columnAt` (horizontal) |
| --- | --- |
| `lineCount < 0` → `.failure(.negativeLineCount)` | `count < 0` → `.failure(.negativeColumnCount)` |
| `!y.isFinite` → `.failure(.nonFiniteValue)` | `!x.isFinite` → `.failure(.nonFiniteValue)` (reused) |
| `offset(ofLine: 0) != 0` → `.failure(.invalidLineMetrics)` **(before empty)** | `columnOffset(_, 0) != 0` → `.failure(.invalidColumnMetrics)` **(before empty)** |
| `lineCount == 0` → `.empty` | `count == 0` → `.empty` |
| `totalHeight = offset(lineCount)`; `!finite \|\| <= 0` → `.invalidLineMetrics` | `width = columnOffset(_, count)`; `!finite \|\| <= 0` → `.invalidColumnMetrics` |
| `y < 0` → `.clampedToTop`, line 0 | `x < 0` → `.clampedToLeft`, cell 0 |
| `y >= totalHeight` → `.clampedToBottom`, `lineCount-1` | `x >= width` → `.clampedToRight`, `count-1` |
| else `lineIndex(containingOffset: y)` → `.inRange` | else `columnIndex(containingOffset: x, inLine:)` → `.inRange` |

The subtle "**O(1) contract probe before the empty short-circuit**" invariant is
preserved verbatim, including the `// Do not reorder.` comment. It means a line
with a corrupt first offset (`columnOffset(_, 0) != 0`) fails with
`.invalidColumnMetrics` even when `columnCount == 0`, rather than being masked by
the `.empty` short-circuit — exactly as `lineAt` fails a corrupt document rather
than reporting it empty. This is the one ordering that is easy to get wrong, and
it is now pinned by a dedicated test (see Git History — commit `f5cf3aa`).

Cost class matches `lineAt`: O(1) core memory, one `columnCount` probe (free in
the counting model), two `columnOffset` boundary probes (`column: 0` for the
contract check, `column: count` for the width), then the O(log M) inverse search
on the in-range path only — clamp and blank paths never search. This is verified,
not asserted, by `ColumnAtQueryCountTests` (below).

### `LineHorizontalMetricsSource` — standalone 3-member protocol (Decision 1)

The protocol is a deliberate **peer** of `LineMetricsSource`, not an extension of
it: horizontal metrics carry no `lineCount` (the source is addressed *within* a
caller-supplied line), so `inLine` is a documented precondition, not a validated
input (Decision 5). Its three members mirror the vertical trio:
`columnCount(inLine:)` ↔ `lineCount`, `columnOffset(inLine:column:)` ↔
`offset(ofLine:)`, and the defaulted `columnIndex(containingOffset:inLine:)` ↔
`lineIndex(containingOffset:)`. The default hook is the shared
`binarySearchColumnIndex` free function — "largest `c` in `[0, columnCount)` with
`columnOffset(c) <= target`" — the identical shape to `binarySearchLineIndex`.

The `columnOffset` doc comment carries the load-bearing **cell contract**:
finite, strictly-increasing cumulative offsets over `0...columnCount`, with
`columnOffset(_, 0) == 0`. It explicitly names the provider's obligation to fold
zero-advance glyphs (combining marks, ZWJ, ligature components) into their base
cell and to present cells in **visual (left-to-right) order** — so a *cell* is a
positive-advance, caret-positionable unit. This correctly locates the
bidi/zero-advance complexity in the provider and keeps the core a pure
monotonic-inverse search (Decision 6).

### Result types and error vocabulary (Decisions 2 & 3)

`ViewportTypes.swift` gains `ColumnQuery` (`.column` / `.empty` / `.failure`),
`ColumnLocation` (`columnIndex` + `clamp`), and `ColumnLocation.Clamp`
(`.inRange` / `.clampedToLeft` / `.clampedToRight`) — the exact shape of
`LineQuery` / `LineLocation` / `LineLocation.Clamp` with the axis renamed. The
`.empty` case (blank line, `columnCount == 0`) is modelled as a first-class
result, not an error — parity with `lineAt`'s empty-document handling.

`ViewportValidationError` gains **two** additive cases, `negativeColumnCount` and
`invalidColumnMetrics`, and **reuses** `nonFiniteValue` for a non-finite `x`
(Decision 3). This is a minimal, principled extension: the horizontal axis needs
its own "count is negative" and "offsets are corrupt" vocabulary but shares the
finiteness failure. Adding enum cases is source-additive within the package; the
spec's Decision 3 migration note captures the standard caveat (an exhaustive
external `switch` over the public enum would need a new arm), consistent with the
variable-height Decision 4 precedent that last extended this enum. This is an
accepted API-evolution cost, not a defect.

### Providers: uniform in core, prefix-sum in reference (Decision 8)

`UniformColumnMetrics` lives **in the core** beside `UniformLineMetrics` so the
`ColumnAtEquivalenceTests` oracle can drive it without a reference-provider
dependency. It is O(1) per query, holds no per-line storage
(`columnOffset = column * columnWidth`), and relies on the binary-search default
for the inverse. `PrefixSumColumnMetrics` (reference target) is the realistic
proportional-advance case: one prefix-sum array per line built in the initializer,
O(1) `columnOffset`, per-line storage held outside the core-memory invariant —
the faithful mirror of `PrefixSumLineMetrics`. Both rely on the generic inverse
default; a native descent is explicitly a future slice.

### Benchmark mode + local gate (Decision 7)

`ColumnQueryBenchmark.swift` adds the `.columnQuery` mode with 5 scenarios
(`uniform_1k/100k/1m`, `prefixsum_100k/1m`). The plumbing changes are minimal and
correct: `BenchmarkOptions` adds the case, its `outputName` (`column_query`), the
usage/flag lines, and the "cannot be combined with another mode" guard;
`BenchmarkProgram` dispatches to `runColumnQueryBenchmarks`; `SyntheticBenchmarks`
adds the `preconditionFailure` arm so the shared runner refuses the specialized
mode. Crucially, `--gate` validity is a **denylist** (rejected only for
`rangeOnly`, `memoryShape`, `memoryObservation` — `BenchmarkOptions.swift:146`),
so `--column-query --gate` becomes valid **automatically** with no new gate-list
edit, exactly as Decision 7 intended. The scenario budgets are copied from the
`--line-query` sibling's uniform shape and, per the verification record, needed no
recalibration. The gate is **local-only** this slice; correctness is nonetheless
enforced hosted because the `ColumnAt*` suites run inside `swift test`.

The `x`-sampling ladder in `runColumnQueryScenarioCore` deliberately drives all
three branches (`sample % 8 == 0` → left-of-line, `== 1` → right-of-line, else
`deterministicScrollOffset` in-range), so the benchmark exercises the clamp and
search paths, not just the happy path, and the checksum folds the clamp variant
into the result — making a silent branch change observable as a checksum diff.

### `AGENTS.md` (durable guidance)

The architecture paragraph gains an accurate `columnAt` description (separate
`LineHorizontalMetricsSource`, O(log M) queries / O(1) core memory via the shared
`columnIndex` hook, cell model with half-open spans in visual order, the two
clamp flags, blank-line `.empty`, `inLine` precondition, the two providers, and
`--column-query` as its local gate). The commands section adds the
`--column-query --gate` invocation, and the flag lists include `--column-query`
with the correct "rejected with `--range-only`/`--memory-shape`/
`--memory-observation`" note. This is honest, durable, and does not overstate CI
status (it explicitly marks the gate **local**, not-yet-CI).

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `8c5dfcb`)

- `git diff --name-only ca34ac5..8c5dfcb` → confined to `AGENTS.md`,
  `Sources/**` (core/providers/benchmarks), `Tests/**`, `docs/**`; **no**
  `Package.swift`, **no** `.github/**`, **no** vertical-axis source.
- `git diff --check ca34ac5..8c5dfcb` → no output, exit `0` (no whitespace errors).
- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `swift build -c release` → `Build complete!` (exit 0).
- `swift test` → **189 tests, 0 failures**, plus the expected empty Swift Testing
  harness line (`0 tests in 0 suites`). This is the Slice 32 baseline of 160 plus
  the 28 Slice 33 tests plus the one post-review ordering test — the verification
  record's 189 count reproduced exactly.
- `swift run -c release ViewportBenchmarks -- --column-query --gate` → all five
  scenarios `gate=pass`, 0 failures; **all five checksums byte-identical** to the
  verification record (`641440000`, `63985556480`, `639841600000`, `63985600000`,
  `639841560320`).
- `swift run -c release ViewportBenchmarks -- --line-query --gate` → all five
  scenarios `gate=pass`; all five checksums byte-identical to the record
  (`641440000`, `63985556480`, `639841600000`, `63985600000`, `639841547520`) —
  confirming the additive horizontal work left `lineAt` and its search path
  untouched.
- `swift run -c release ViewportBenchmarks -- --gate` → all three synthetic
  scenarios `gate=pass`; checksums match the record (`1319670707200`,
  `570448232307200`, `18852477646272000`).

### Test coverage assessment (the substance of a functional slice)

The 28 new tests cover the query on all axes I would want covered before trusting
a new inverse primitive:

- **Behavioral (`ColumnAtTests`, 15 cases):** in-range mid-span, `x == 0`
  in-range, exact boundary resolves to the right cell, clamp-left, clamp-right
  (at width and far past), blank line `.empty`, `negativeColumnCount`, non-finite
  `x` (nan/±inf), non-zero first offset → `invalidColumnMetrics`, the
  **blank-line-with-corrupt-first-offset fails before empty** ordering case, zero
  width, non-finite width, a full non-uniform-advance resolution sweep, single-cell
  line clamps, and per-line addressing (same `x`, different line → different cell).
- **Cost class (`ColumnAtQueryCountTests`, 6 cases):** in-range at 1,000,000 cells
  uses `<= 2 + ceilLog2(count) + 1` probes (logarithmic, and `< 100`); blank line
  probes only the first offset (1); both clamp branches probe exactly 2 (offset 0
  + width) and never search; non-finite `x` probes 0. An **event-log** test pins
  the exact dispatch order on the in-range path
  (`[.offset(0,0), .offset(0,count), .native(...)]` — contract probe, width probe,
  then native hook) and proves the blank/clamp/non-finite paths **never** dispatch
  to the native hook. This is the same rigor Slices 29/30 used to prove native
  dispatch.
- **Equivalence oracle (`ColumnAtEquivalenceTests`):** `UniformColumnMetrics`
  `columnAt` is checked against an independent closed-form structural oracle
  across a matrix of widths × counts × lines × sampled `x` (boundaries, mid-spans,
  below-zero, exact total width, past-end). The oracle derives the cell by
  counting products, not dividing — an independent derivation, not a restatement
  of the implementation.
- **Provider parity (`PrefixSumColumnMetricsTests`):** the reference provider is
  driven through `columnAt` over the same `[0,10,40,45,95]` vectors as the core
  `testNonUniformResolution`, plus per-line addressing — cross-checking the
  shipped provider against the hand-built expectations.

The one gap worth naming: there is no *cross-provider* equivalence oracle asserting
`UniformColumnMetrics` and `PrefixSumColumnMetrics` agree on an identical logical
grid (the vertical axis has the richer variable-vs-fixed equivalence oracle). In
practice the uniform closed-form oracle plus the prefix-sum hand-built vectors
cover the same ground, so this is a note, not a defect.

### Hosted runs (verified live during the merge, step-level in the record)

Per the verification record, both hosted runs were checked at the **step** level
(not just job conclusion), honoring the project's "a green job can hide a dead
`continue-on-error` step" lesson:

- **PR #65 final-head run `28713959866`** (head `c234ce0`, event `pull_request`):
  conclusion `success`; all three required jobs `success` (`Host tests and
  benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`).
  In the host job, step 5 `Complete docs-only PR` = `skipped` (correctly **not**
  docs-only — the PR changes Swift source), step 7 `Run host tests` = `success`
  (the 189-test suite, which includes the `ColumnAt*` suites), the seven blocking
  latency gates all `success`, and step 17 realistic-provider observation
  `success` on the PR event.
- **Post-merge push run `28716790653`** on merge commit `4e35091` (event `push`,
  branch `main`): conclusion `success`; all three required jobs `success`. The
  host job again shows step 5 `skipped`, `Run host tests` `success`, the seven
  blocking gates `success`, and step 17 realistic-provider observation correctly
  `skipped` on the `push` event. **This is the merged-code evidence anchor**:
  `columnAt` correctness is proven hosted on the actually-merged head via the test
  suite. Merge parentage (`4e35091` = `ca34ac5` + `c234ce0`) confirms the proof
  anchors the merged head.

The honest note the record makes and I confirm: the new `--column-query --gate` is
**not** a hosted step this slice (local-only, Decision 7). The seven hosted
blocking gates are the pre-existing ones; the workflow was not changed. So
`columnAt`'s *latency-regression* protection is local-only — enforced only when
someone runs the gate locally — while its *correctness* is hosted-enforced through
`swift test`. That gap is deliberate and is the primary next-slice candidate
(below).

## Git History

Reviewed Slice 33 commits (PR #65 → #66):

```text
49853db docs: add horizontal position-query design
672ad76 docs: add horizontal position-query implementation plan
bfc4c32 docs: refine horizontal position-query spec
148e281 feat: add LineHorizontalMetricsSource protocol and UniformColumnMetrics
d52d329 feat: add ViewportVirtualizer.columnAt horizontal position query
6a3f14b test: add columnAt closed-form equivalence oracle
b8241a0 test: add columnAt query-count and native-dispatch event-log tests
117d398 feat: add PrefixSumColumnMetrics reference provider
bb3dead feat: add --column-query benchmark mode with local gate
a8b1028 docs: document columnAt and --column-query in AGENTS.md
cd08bb3 docs: record local verification for horizontal position query
f5cf3aa test: pin columnAt probe-before-empty ladder ordering
c234ce0 docs: note post-review ordering test in verification record
4e35091 Merge pull request #65 …
b4c9842 docs: record slice 33 post-merge proof
8c5dfcb Merge pull request #66 …
```

Clean, incremental, one-logical-step-per-commit with correct conventional-commit
prefixes. The order is textbook TDD-adjacent for this repo: spec (with a
refinement round, `bfc4c32`) and plan first; then the protocol + core provider;
then the query; then the equivalence oracle and the query-count/event-log tests;
then the reference provider; then the benchmark mode; then docs, then local
verification. Notably, the whole-branch review flagged that the "probe before
empty" ladder ordering — an invariant enforced only by an inline comment — had no
dedicated test, and `f5cf3aa` added exactly that pin
(`testInvalidFirstOffsetOnBlankLineFailsBeforeEmpty`), with `c234ce0` recording
the addition in the verification doc. That is the review loop working as intended:
a real (if minor) coverage gap found and closed **before** merge. The two-PR split
(implementation + local proof, then post-merge proof) is the standard pattern; the
hosted proof was recorded only in PR #66 against the stable final head.

## Code Review Findings

Reviewing across correctness, cost-class/asymptotics, API design, scope
discipline, evidence integrity, and portability:

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The code is merged, correct, and proven: `columnAt` is a verified line-by-line
mirror of the battle-tested `lineAt`, the validation ladder and half-open/clamp
semantics are covered by behavioral tests, the O(log M) cost class and native
dispatch order are pinned by event-log tests, the equivalence oracle checks the
core provider against an independent derivation, Foundation/core-memory invariants
hold, and iOS is blocking-green.

### P2 / Production Readiness

None. No correctness or evidence-accuracy defect. In particular: the hosted proof
(PR-head + post-merge push run) was recorded only in the post-merge follow-up
(PR #66, `b4c9842`) against the stable final head `c234ce0`, and the
source-bearing PR #65 was never described as taking the docs-only shortcut — the
record explicitly notes it is *not* docs-only because it changes Swift source. The
recurring stale-on-write evidence defect stayed absent.

### P3 / Minor But Valid

**1. Both common horizontal providers are binary-search-bound (new; horizontal
analog of the carried vertical Slice 29/30/31 P3).** `UniformColumnMetrics` and
`PrefixSumColumnMetrics` both rely on the generic `binarySearchColumnIndex`
default for the inverse. The uniform case admits an exact O(1) closed form
(`min(count-1, floor(x / columnWidth))`), and prefix-sum admits a native
descent, either of which would remove the log factor for the common providers.
The spec correctly scoped this out ("a native descent is a future slice"), and it
carries no correctness risk (the tests prove the default is exact). It simply
extends the same "last fallback-bound common provider" hygiene item that stands
open on the vertical axis into the horizontal one. Low product value.

**2. No horizontal geometry / caret-x (deferred by Decision 6, not a defect).**
`columnAt` returns the cell index + clamp but no within-cell fraction or caret
`x` — the horizontal analog of what `lineGeometryAt` (Slice 31) added over
`lineAt` (Slice 27). This is the deliberate "sub-cell position deferred" decision,
correctly out of scope for the axis-opening slice, but it is the most visible
capability gap the axis now carries and a natural next-slice candidate (below).

**3. Standing spec/implementation primitive-naming drift, still open (carried from
Slice 25 P3 #3 / 26 / 28 / 32).** The bulk-edits spec names the join primitive
`join(_:_:)` while the implementation ships `join3`/`join2`. Slice 33 touches no
provider join source or the bulk-edits spec, so it is correctly **not** a Slice 33
defect — but it remains an open provider-doc hygiene item with no home slice yet. A
one-line cross-reference in the bulk-edits spec would retire it whenever a
provider-touching slice next opens.

No P3 changes whether the merged result is correct; all three are deliberate
deferrals or pre-existing hygiene.

## Risks And Gaps

### The horizontal axis is now at the exact shape the vertical axis had after Slice 27

Opening a new axis re-opens the whole ladder the vertical axis already walked. The
horizontal axis now has: a mapping primitive (`columnAt`), generic binary-search
providers, a **local-only** gate, no geometry/caret-x, and no CI protection —
precisely the state `lineAt` was in immediately after Slice 27. The concrete debts
this creates, in rough priority order:

- **(a) `--column-query` is not hosted-blocking.** A latency regression in
  `columnAt` (a constant-factor slowdown, an added allocation) would not fail the
  hosted job; only local runs catch it. This is the direct analog of the 27→28 and
  31→32 promotion gaps and the single clearest governance debt.
- **(b) No horizontal geometry (caret-x / within-cell fraction).** The horizontal
  analog of `lineGeometryAt`; needed for a real caret/selection.
- **(c) No 2D `pointAt(x:y:)` composite.** The mapping primitives for both axes now
  exist (`lineAt` + `columnAt`); nothing yet composes them into point → (line,
  cell) hit-testing.
- **(d) No native/closed-form provider inverse (P3 #1).**

None of these is a *defect* — each is a deliberate deferral — but together they
define the next several slices of the horizontal arc.

### Budgets remain macOS-derived

The `--column-query` budgets were copied from the `--line-query` uniform shape and
validated only locally on macOS arm64 (~1000×–5000× headroom). They have **never
run in hosted Linux CI** (the gate is local-only), so there is no hosted x86_64
evidence for them yet — a hosted budget-fit check is part of what a CI-promotion
slice (Option A) would establish. This matches the standing macOS-calibration
posture and is acceptable for a local gate.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative
observation remains PR-only `continue-on-error`; the `Main` ruleset keeps its
documented bypass-actor shape (the admin user can still bypass required checks).
None were in scope for Slice 33.

## Lessons For The Next Slice

1. **Faithful-mirror slices stay clean and low-risk.** Reusing the proven Slice 27
   shape wholesale — the same validation ladder (down to the `// Do not reorder.`
   contract-probe-before-empty invariant), the defaulted binary-search hook, the
   event-log native-dispatch test, the closed-form equivalence oracle, and the
   local-gate rhythm — produced a 191-line strictly-additive slice with zero
   P0/P1/P2 and byte-identical existing-gate checksums. When a new axis is a
   structural mirror of a built one, mirror it exactly rather than re-deriving; the
   discipline is the risk control.
2. **An ordering invariant guarded only by a comment deserves a dedicated test.**
   The whole-branch review caught that the "probe before empty short-circuit"
   ladder order had only an inline `// Do not reorder.` comment and no test that
   would fail if it were reordered; `f5cf3aa` added the pin pre-merge. Any
   correctness invariant that lives in *statement order* rather than in a value
   check should get an explicit test — the comment documents intent but does not
   defend it.
3. **The clean-evidence convention held again.** Hosted proof recorded only in the
   post-merge follow-up (PR #66) against the stable final head `c234ce0`, with the
   source-bearing PR #65 explicitly flagged as *not* docs-only. This is now the
   proven default for every source-touching slice.
4. **Opening a new axis re-opens the whole functional → gate → optimize → geometry
   ladder.** The horizontal axis now faces the same sequence the vertical axis
   walked (27 map → 28 gate → 29/30 native descent → 31 geometry → 32 gate). The
   substance of the next few slices is choosing the *order* to walk it — and, per
   the standing convention, keeping functional/capability work and CI/infra work in
   separate slices.

## Slice 34 Candidate Options

Unlike the Slice 32 review — which found **no** governance debt and so framed the
next slice as a pure product call — Slice 33 **re-opens a concrete governance
debt**: the `--column-query` local-only gate, exactly as Slices 27 and 31 did for
their primitives. So there is again an obvious rhythm-consistent next move, plus
the capability continuations the newly-opened axis invites.

### Option A: `--column-query` CI-gate promotion (rhythm-consistent, debt-closing)

Wire the existing `--column-query --gate` into the required host job as the
**eighth** blocking latency gate — the exact mechanical mirror of Slice 28
(line-query) and Slice 32 (line-geometry-query). **Zero Swift**: one workflow step
+ `AGENTS.md` wording. It closes debt (a) above, establishes the first hosted
Linux x86_64 budget-fit evidence for the column budgets, and completes the
"functional slice adds a local gate → promotion slice wires CI" rhythm for the
**seventh** time. Lowest risk; the promoted benchmark already exists and passed no
prior review with an actionable defect, so — like Slices 28/32 and unlike Slice 26
— it would promote **unchanged**, with no bundled hardening.

### Option B: `pointAt(x:y:)` 2D composite (the product leap)

Compose the two mapping primitives — `lineAt`/`lineGeometryAt` (vertical) and
`columnAt` (horizontal) — into a single point → (line, cell) hit-test over both
metrics sources. This is the biggest step toward realistic click-to-caret /
selection on large documents and the capability the Slice 33 direction note named
as the next capability. Largest design surface; needs a fresh brainstorm + spec
(how the two independent sources compose, the combined result/clamp shape).

### Option C: `columnGeometryAt` / caret-x (the tight mirror)

The horizontal analog of Slice 31's `lineGeometryAt`: return the located cell's
box (left `x` + advance width) plus a within-cell fraction / caret `x`, composed
over `columnAt` with a constant number of extra `columnOffset` probes. Retires
Decision 6's deferred sub-cell position. Smaller and lower-risk than B, and the
exact 27→31 mirror; a natural precursor to B.

### Option D: closed-form / native column inverse (carried P3 #1)

O(1) / native-descent overrides of `columnIndex` for `UniformColumnMetrics` and
`PrefixSumColumnMetrics`, boundary-safe against the equivalence oracle. Retires the
horizontal fallback-bound-provider P3. Small, clean; lower product value.

### Option E: standing infra (WASM blocking / Linux budget re-baseline)

Promote WASM cross-target from observational to blocking (gated on stable SDK
provisioning), or re-derive Linux-native budgets from the accumulated x86_64
evidence. Standing hygiene; independent of the capability arc.

## Recommended Slice 34 Selection

Because Slice 33 re-opens a governance debt (the local-only column gate), the
situation resembles Slices 28 and 32 more than Slice 32's debt-free handoff — there
**is** an obvious, low-risk, rhythm-consistent next move. My recommendation is to
lean **Option A — the `--column-query` CI-gate promotion**, and to surface the
A-vs-B-vs-C call to the user.

The reasoning: the vertical axis promoted its mapping gate (Slice 28) *immediately*
after shipping the mapping primitive (Slice 27), before advancing to native descent
and geometry. Following that proven sequence, promoting `--column-query` next closes
the one debt this slice opened for zero Swift and buys the horizontal axis the same
hosted regression protection the vertical axis has enjoyed since Slice 28 — so that
every *subsequent* horizontal capability (caret-x geometry, `pointAt`) is built and
measured on a CI-protected base rather than accumulating unprotected latency debt.

That said, the user explicitly chose the **horizontal capability direction** at the
Slice 32 review, so if the preference is to keep the product moving before spending
a governance slice, **Option C (caret-x geometry)** is the tighter, lower-risk
capability step (the exact 27→31 mirror, a precursor to B), and **Option B
(`pointAt` composite)** is the larger leap toward real hit-testing. Both are sound;
both would then leave the column gate promotion (A) as follow-on debt. Whichever is
chosen, keep functional/capability work and CI/infra work in separate slices, per
the project's standing convention.

## Slice 33 Review Conclusion

Slice 33 opened the engine's horizontal axis cleanly and at the right altitude. It
ships `ViewportVirtualizer.columnAt(x:inLine:metrics:)` — a faithful, line-by-line
mirror of the battle-tested vertical `lineAt` — over a new standalone
`LineHorizontalMetricsSource`, with `ColumnQuery`/`ColumnLocation`/`Clamp` result
types, two providers (`UniformColumnMetrics` in the core, `PrefixSumColumnMetrics`
in reference), a local `--column-query` gate, and 28 tests spanning behavioral
correctness, O(log M) cost class with pinned native-dispatch order, a closed-form
equivalence oracle, and provider parity. The functional surface is just 191
strictly-additive lines; every existing gate's checksum is byte-identical to the
2026-07-03 baseline, confirming no vertical-axis behavior changed. All hard
constraints hold: Foundation-free (both targets), O(1) core memory, zero-dependency,
iOS blocking-green, WASM observational-green.

The review found **no P0, P1, or P2 issues** against the merged result, and **no
evidence-accuracy defect** — the hosted proof was recorded only in the post-merge
follow-up against the stable final head, and the source-bearing PR was never
mis-classified as docs-only. The three open P3s are deliberate deferrals
(binary-search-bound providers; no caret-x geometry) or carried hygiene
(spec/code join-primitive naming). The whole-branch review loop demonstrably
worked: it caught that the "probe before empty" ladder-order invariant had no
dedicated test and closed the gap (`f5cf3aa`) before merge.

Slice 33 leaves the horizontal axis in exactly the shape the vertical axis had
after Slice 27 — mapping primitive shipped, local-only gate, no geometry, no CI
protection — which re-opens the proven functional → gate → optimize → geometry
ladder. My recommendation is to **lean Option A (the `--column-query` CI-gate
promotion)** as the rhythm-consistent, zero-Swift debt-closer that mirrors 27→28
and 31→32, while surfacing the A-vs-B-vs-C product call — Option C (caret-x
geometry, the 27→31 mirror) and Option B (`pointAt` 2D composite, the hit-testing
leap) being the capability alternatives the user's Slice 32 horizontal-direction
choice may favor — for the user to direct.
