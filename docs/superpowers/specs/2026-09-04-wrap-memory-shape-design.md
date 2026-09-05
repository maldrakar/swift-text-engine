# Slice 57 — wrap memory shape (design)

**Map node:** wrap arc node 5. **Criterion:** 2 — *core memory not linear with wrap
on; `--memory-shape` extended to the wrap path* — the only wrap criterion with no
evidence at all.

**Selected by** the [slice-56 post-slice review](../reviews/2026-09-04-slice-56-post-slice-review.md)
(Option A, topological). Its fold-in was one row (D-43); the user raised the depth to
**nine** rows on 2026-09-04 ("close as much debt as is relevant"), and this design adds a
tenth, **D-45**, discovered while reading the mode this slice extends. It also opens
**D-46** as `accepted-risk` — not a fold-in and not work: the named residual of the
observable this slice picks (Decision 1), recorded so criterion 2's evidence link says what
was measured.

## 1. Scope

Three things, in this order, and the order is load-bearing (Decision 10):

1. **The spine** — a wrap half of `--memory-shape`: six scenarios over the wrap query
   surface a viewport reaches — `compute(_:layout:)`, `DocumentVisualRowCursor`,
   `visualRowAt`, `visualPointAt` — asserting that core-owned work is bounded by the
   viewport and does not grow with the document. Node 1's per-line
   `visualRows(inLine:wrapWidth:metrics:)` is the fifth public entry point and is covered
   **transitively**, not by a scenario of its own: the drain re-drives it across logical
   lines, so a linear term inside it lands in `drain_probes`.
2. **The repair** — two vacuous measurements in the existing fixed/variable half: its
   cross-scenario comparison, which today compares a constant with itself, and its
   `touched_lines` column, which on the variable half is an *assignment* of
   `buffered_lines` rather than a count (§2). Opened as **D-45** and discharged here,
   because a criterion cannot be closed by a mode whose only cross-scenario comparison
   cannot fail — and because a repair that folded the second one in unrepaired would
   satisfy itself by construction on two of eleven lines.
3. **The fold-ins** — D-43 (P2) and D-10, D-11, D-14, D-15, D-19, D-20, D-21, D-38 (P3).

Not in scope: promoting anything to a gate (node 6), `--memory-observation` (Decision 5),
and every row on node 6's precondition list (D-9, D-20's *runtime* consequence, D-28,
D-30, D-31, D-36). See §9. D-46 is opened, not worked: closing it needs a memory instrument
this mode does not have.

## 2. What `--memory-shape` proves today, and what it does not

Measured by reading `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`, not
asserted:

- `coreOwnedBytesEstimate()` (line 98) and `variableCoreOwnedBytesEstimate()` (line 104)
  **take no scenario**. Each is a fixed sum of `MemoryLayout<T>.size` and returns the same
  value for every scenario in its group.
- `runMemoryShapeDiagnostics()` (line 417) compares each summary's `coreOwnedBytes`
  against **the first of its provider group** (lines 427-428). For the `synthetic` group
  that is `x == x`. For `large_text` **neither** branch matches, so it falls to
  `else { comparisonPasses = true }` — that scenario is not compared at all.
- `MemoryLayout<T>.size` counts the inline footprint. A struct that captured an array
  reports the size of a pointer, so the estimate cannot see the growth it exists to
  detect.
- `runVariableMemoryShapeScenario` sets `providerLines: bufferedLines` (line 386) and
  `formatMemoryShapeSummary` prints it as `touched_lines` (line 330). On the two
  `variable_uniform` lines that column is therefore **not a measurement**: it is the
  buffered window written twice. `geometryLines` beside it *is* counted from the cursor.

What carries weight today, stated more carefully than "the structural checks do": the
per-scenario checks are about the **range and the cursors**, and both are bounded by
construction. `ViewportVirtualizer.geometry(for:)` and `lines(for:in:)` yield exactly the
elements of the range they are handed, so `geometry.lineCount == expectedBufferedLines` and
`provider.lineCount == expectedBufferedLines` would redden only if a cursor stopped
respecting its range — a real failure mode, and the reason these checks stay untouched, but
not one that can observe core-owned memory. `providerBytesPasses` is the one check in the
mode today that compares a measured quantity against an independently derived expectation.

Three consequences. First, the wrap half must not be built on the byte estimate — hence
Decision 1, whose probe count is the first quantity in this mode that *could* grow with the
document. Second, both vacuous measurements are repaired here rather than recorded for
later (**D-45**): this slice's whole purpose is to give criterion 2 evidence, and closing a
criterion on a comparison that cannot fail is the exact shape this repository has shipped
five times (`## Gate budgets`, "Never hand-type a budget"). Third, the repair must not
inherit the idiom that produced the vacuity — comparison against a **neighbour** rather
than against a declared expectation (Decision 4).

## 3. Decisions

**Decision 1 — the observable is provider probes, not bytes.** Every wrap entry point
returns fixed-size values, so "core memory does not grow" is observed through the quantity
that would grow if the core started walking the document: the number of calls it makes into
the layout source. Bytes remain a printed token (`core_owned_bytes`) for continuity with the
existing lines — the wrap half's estimator is `wrapCoreOwnedBytesEstimate()`, the same
`MemoryLayout` sum shape as its two siblings — and the code says in a comment that it is
continuity, not evidence.

**Its residual is named, not implied.** A probe count is a proxy: it sees a core that
*traverses* the document and is blind to one that *allocates* without traversing
(`Array(repeating:count: totalRows)` inside a cursor probes nothing and would pass every
assertion in §4A). No available observable closes that gap — `MemoryLayout` reports a
pointer for exactly this case (§2), and RSS is `--memory-observation`'s non-blocking
instrument, declined here in §9. So the gap is recorded as a ledger row (**D-46**,
`accepted-risk`) and criterion 2's evidence link is scoped to what was actually measured.
Claiming the probe count is "the only quantity that would grow" would overstate it.

**Decision 2 — `compute` is asserted flat on the layout axis; the other three are asserted
logarithmic.** `validateVisualRowLayout` (`WrapViewportVirtualizer.swift:32,34`) probes the
layout exactly twice — `firstVisualRow(ofLine: 0)` and `firstVisualRow(ofLine: lineCount)`;
`rowHeight` and `wrapWidth` are properties, not counted hooks — and `compute` then runs both
boundary searches over `UniformLineMetrics`, which touches the layout not at all. Its
layout-probe count is therefore a **constant**, and the six scenarios must report the *same*
number. **What this does and does not say:** `UniformLineMetrics` overrides neither native
inverse hook (D-22), so those boundary searches are binary searches over `offset(ofLine:)`
and `compute`'s own cost is O(log totalRows), not O(1) — the arc file's node-2 correction,
unchanged. Flatness here is a statement about the **layout axis**, which is the axis a
provider-owned linear term would appear on; the uniform-axis half is arithmetic the counter
cannot see and does not claim to. `DocumentVisualRowCursor`, `visualRowAt` and
`visualPointAt` each run a `logicalLine(containingVisualRow:)` search, so their probe
counts grow with `log(lineCount)`; they are asserted as a **bounded delta across the 10x
size jump** (`probes(1M) - probes(100k) <= 32`), not as equality. A linear term would show
as roughly 10x — hundreds of thousands of probes — so the bound separates logarithmic from
linear by three orders of magnitude while tolerating the handful of levels the jump really
costs. The bound is a *shape* bound: it is not corpus-derived, not re-calibrated, and it is
not a latency budget (contrast `## Gate budgets`).

**Decision 3 — the width axis asserts buffered-row identity, and the within-line walk is
the one legal growth.** `rowHeight` and `viewportHeight` are the same in every scenario, so
the visible window is 80 rows and the buffer 90 rows **whatever the wrap width does to the
row count**. That identity is asserted across all six scenarios. The one entry point whose
probes may legitimately grow as the width narrows is `visualPointAt`, whose within-line
walk is linear in `rowInLine` (the documented term behind fork R); its growth is asserted
to be bounded by the line's own row count and **independent of `lineCount`**.

**Amended by the validation pass (2026-09-05), which found this sentence wider than §4A's
contract.** What ships, and what §4A's invariants 9 and 11 actually state, is the second
half only: the walk is asserted to be **independent of `lineCount`** (invariant 9's
`<= 32` delta) and to **cost something** as the width narrows (invariant 11). No bound
against the line's own row count is implemented, and none was ever in the contract table —
the mode's fixture packs a uniform 1/2/8 rows per line, so such a bound would compare a
probe count against a constant and would not separate the walk from anything else. The
sentence is corrected rather than the code: read Decision 3 as the two clauses §4A
enforces.

**Decision 4 — a mode-wide structural equality replaces the vacuous byte comparison
(D-45), and it compares against a declared expectation rather than a neighbour.** Every
scenario in the mode — three fixed, two variable, six wrap — shares `lineHeight = 16`,
`viewportHeight = 80 * 16` and `overscan 5/5`, so every one of them must report a buffered
window of **90** and must have streamed and touched exactly that many elements. One number,
four code paths, eleven lines. `large_text` stops being exempt.

Three properties of the repair, each answering a way the first attempt would have been
vacuous:

- **Declared, not first-of-group.** The expectation is a constant the driver states
  (`expectedMemoryShapeWindow = 90`, derived once from the shared viewport configuration),
  not `summaries.first`. Comparing against a neighbour is the idiom that produced `x == x`,
  and it has a second defect this repair must not inherit: the first element is never
  itself checked, so corrupting *it* reddens the other ten lines and leaves the guilty one
  green. With a declared expectation the guilty line is the one that says `invariant=fail`.
- **`touched_lines` becomes a count on the variable half too.** `providerLines:
  bufferedLines` (line 386) is replaced by a real count: `runVariableMemoryShapeScenario`
  drives its `UniformLineMetrics` through a counting `LineMetricsSource` wrapper and reports
  the number of distinct buffered lines the geometry cursor actually resolved. Without this
  the mode-wide equality is satisfied **by construction** on two of eleven lines — the
  repair would restate the defect it is repairing. This also unifies the mode on one
  observable: after the slice, both halves count provider calls (Decision 1).
- **The comparison is a pure function, so it can be unit-tested.** The cross-scenario logic
  moves into `memoryShapeComparisonFailures(_ summaries: [MemoryShapeSummary]) -> [String]`,
  which takes summaries and returns the names that failed, printing nothing. This is the
  `GateLogicTests` seam applied to this mode: the gate's pass/fail logic is unit-tested
  against synthetic `BenchmarkSummary` values "independent of any hosted timing"
  (`AGENTS.md`), and D-45 exists precisely because nothing did the equivalent here. G1/G2/G4
  and G7 become unit tests over synthetic summaries instead of hand-mutations of a
  1M-line run.

The byte comparison is kept as a subordinate check rather than deleted, so nothing that
passes today starts failing for a reason unrelated to this slice; it is simply no longer the
only thing being compared. Printed `checksum=` values do not move: the comparison is not
folded into them, and `touched_lines` is not a checksum input on the variable path.

**Decision 5 — wrap scenarios get their own list and driver.**
`MemoryObservationDiagnostics.swift:151` calls `memoryShapeScenarios()`, so appending wrap
scenarios to that function would silently extend `--memory-observation` too — a second
mode's output changed by a slice whose fingerprint is supposed to be the first. Wrap
scenarios live in `wrapMemoryShapeScenarios()` in a new file,
`WrapMemoryShapeDiagnostics.swift`, and `runMemoryShapeDiagnostics()` calls both.

**Decision 6 — `CountingWrapLayout` moves into the target; the test copy is deleted, not
pinned — and it keeps the argument-sensitive counter.**
`Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift:18` already carries a
`CountingLayout` counting one hook. The generalized version — counting all six
`VisualRowLayoutSource` hooks — belongs in `Sources/ViewportBenchmarks`, and
`WrapComputeDrainTests` is rewritten to use it. Deleting a copy beats pinning one (the
D-41 argument, applied where it is cheap).

**The generalization must not be six totals.** `WrapComputeDrainTests` does not rest on a
call count; it rests on a count *by argument* — `firstVisualRowAtLineCount`
(`WrapComputeDrainTests.swift:15,28-30`), because "the drain performs no `compute`" is
exactly "no probe with the argument `lineCount` happened". A `CountingWrapLayout` exposing
only six per-hook totals cannot express that assertion, and rewriting the test onto it would
silently retire D-29's discharge while leaving the file green. So `CountingWrapLayout`
carries both: six per-hook totals **and** `firstVisualRowAtLineCount`. That second counter
is also what makes `compute_probes` readable as "two probes, one of them the total-rows
probe" rather than as an opaque 2.

**Decision 7 — every counter carries a witness.** A probe count of zero is evidence only if
the probe would have been counted. `WrapComputeDrainTests` already does this ("a witness
call proves the probe exists to be counted"); the new assertions inherit the rule, and each
one names the witness that makes its number non-vacuous.

**Decision 8 — the constants come from a measurement, not a prediction.** The reading of
the code gives `compute_probes = 2` (`WrapViewportVirtualizer.swift:32,34`, Decision 2), and
the observed deltas for the other three entry points are not predicted at all. Both are
**measured in the plan's first task** and written into the contract table then; the design's
2 is a prediction the measurement is free to falsify, not a number an acceptance criterion
rests on. No acceptance criterion states a number this design guessed.

**Decision 9 — the fixture separates its axes, and anchors the phase it is not
measuring.** 80 cells per line at advance 1.0 gives a line total of 80.0, so the three
widths pack to **1 / 2 / 8** rows per line — three distinct values, none of them equal to
the buffered window (90), the visible window (80), or each other.

Every offset in a scenario is `rowHeight * (firstVisualRow(ofLine: lineCount / 2) + 3)`.
Two properties follow, and both are load-bearing:

- **The within-line phase is identical across document sizes by construction.** Rows per
  line is uniform, so the middle line's first row is a multiple of it at *both* sizes, and
  the buffer therefore starts at the same `rowInLine` at 100k and at 1M. Without that
  anchor the two sizes would start mid-line at different depths, and the drain's
  walk-to-start term — up to seven rows of cell scanning at width 10 — would land in the
  size delta of Decision 2's `<= 32` bound and redden it for a reason that has nothing to
  do with document size. What is left varying across sizes is then only the logarithmic
  search, which is what the bound is about.
- **The `+ 3` puts the query off a row-start.** The located row's `rowInLine` is 0 at
  width ∞, 1 at width 40 and 3 at width 10. On the unshifted middle row it would be 0 at
  every width, and the within-line walk — the entire width axis of Decision 3 — would be
  silently unexercised. `point_row_in_line=` is printed so the walk depth is read rather
  than assumed.

The offset is an exact multiple of `rowHeight`, so the visible window is exactly 80 rows
rather than 81; `visible_rows == 80` is an assertion about alignment as much as about the
viewport.

**The same reasoning applies to `x`, and the horizontal axis needs it more.** `x = 5.0` at
every width, and the scenario asserts the query did **not** clamp. The vertical `+ 3`
argument has an exact horizontal twin: a clamped `x` costs `3 + 2` column-metric probes and
**never reaches** `columnIndex(containingOffset:inLine:)`, where an unclamped one costs
`3 + 2 + 1` plus the hook dispatch (`AGENTS.md`, node 4;
`WrapPointQueryCountTests.testFittingLineClampedCostsThreePlusTwo` and its delegating
sibling). At width 10 the located row spans 10 layout units, so any `x >= 10` clamps — and
`point_query_probes`, on which invariant 11 and AC4 rest, would then be measuring the clamp
path at one width and the delegating path at another. `x = 5.0` is in range at all three
widths (row spans are 10, 40 and 80), and `point_clamp=none` is printed so the branch is
read rather than assumed.

**Decision 10 — the spine lands before the fold-ins.** Nine of the ten rows in §1 touch
neither the wrap path nor `--memory-shape`. They are sequenced after the spine so that a
fold-in cannot delay the criterion, and so that a fold-in that turns out larger than
estimated is dropped to a named residual rather than pushing the node.

**Decision 11 — the wrap checksum folds the streamed rows and both query answers.** The
fold covers every drained row's `endColumn` (the packing witness, per the D-33 argument),
the located row's `globalRow`, `logicalLine` and `rowInLine`, and the located point's
`columnIndex`, with distinct multipliers so an index fold cannot collide. This mode's lines
are new, so there is no byte-comparability constraint to trade against (contrast
`wrapComputeChecksum`, where there is).

## 4. Contracts

### A. The wrap half of `--memory-shape`

Six scenarios, `{100_000, 1_000_000} x {infinity, 40, 10}`, each built from
`BenchmarkWrapLayout(lineCount:cells: 80, advance: 1.0, rowHeight: 16.0, wrapWidth:)`.
Providers are built and released **one at a time**: the prefix array is 8 MB at 1M lines.

Each scenario runs all four wrap entry points against a `CountingWrapLayout` wrapping that
provider, with `x = 5.0` on the point query (Decision 9), and emits one line:

```
mode=memory_shape provider=wrap scenario=<size>_lines_width_<w> line_count=<N>
wrap_width=<w> total_rows=<R> visible_rows=80 buffered_rows=90 streamed_rows=90
point_row_in_line=<k> point_clamp=none compute_probes=<a> drain_probes=<b>
row_query_probes=<c> point_query_probes=<d> core_owned_bytes=<e>
provider_owned_bytes=<f> invariant=<pass|fail> checksum=<x>
```

`wrap_width=` prints `inf` for the infinite width, the spelling `--wrap-compute` already
uses (`scenario=width_inf width=inf`), so the two wrap-bearing modes do not label the same
width two ways.

Per-scenario invariants (each can fail on its own line):

1. the range is ordered and bounded within `0...totalRows`;
2. `visible_rows == 80` and `buffered_rows == 90`;
3. `streamed_rows == buffered_rows` — the cursor streams the buffer, no more and no less;
4. `compute_probes` equals the measured constant (Decision 8);
5. at width 10, `point_row_in_line > 0` — the within-line walk is exercised, not assumed;
6. `point_clamp == none` — the point query reached
   `columnIndex(containingOffset:inLine:)` rather than answering from the clamp path, so
   `point_query_probes` measures the same branch at all three widths (Decision 9);
7. `provider_owned_bytes == (line_count + 1) * MemoryLayout<Int>.size` — the prefix sum
   `BenchmarkWrapLayout` owns, compared against an independently derived expectation the way
   `providerBytesPasses` already does on the fixed half.

Invariant 7 is not decoration. Criterion 2 has two clauses, and the second one — «wrap-данные
живут за провайдерской абстракцией, как остальные метрики» — is about *where* the linear
data lives, not about its absence. Asserting that the provider's bytes grow by 10x across the
size jump while every core probe count stays flat or logarithmic is the most direct statement
of that clause the mode can make, and it is the pair of columns a reader of the hosted log
should be pointed at.

Cross-scenario invariants, computed by `memoryShapeComparisonFailures` (Decision 4) over the
collected results:

8. **flatness** — `compute_probes` is identical across all six;
9. **shape** — for each entry point and each width, `probes(1M) - probes(100k) <= 32`;
10. **width independence of the buffer** — `buffered_rows` and `streamed_rows` are identical
    across all six;
11. **the walk is a width term, not a size term** — `point_query_probes` at width 10 exceeds
    its value at width infinity (the walk costs something, so the counter tracks it), while
    the width-10 delta between 1M and 100k stays inside the bound of (9);
12. **provider bytes are a size term** — `provider_owned_bytes` at 1M is ~10x its value at
    100k at every width, and identical across widths at a fixed size (the prefix sum has one
    entry per logical line whatever the width does to the row count).

A cross-scenario invariant names the scenarios that violate it, and each named scenario
prints `invariant=fail` on its own line before the driver exits non-zero, exactly as the
existing driver does. "Named" is by comparison against the declared expectation where one
exists (invariants 8, 10, 12 against the mode's constants) and against the *pair* where the
invariant is inherently relational (9 and 11 fail both scenarios of the offending pair) —
never against `summaries.first`, per Decision 4.

### B. The repair (D-45)

`runMemoryShapeDiagnostics()` gains a mode-wide structural comparison: every summary — fixed,
variable and wrap — contributes `(scenarioName, bufferedWindow, streamedElements,
touchedElements)`, and every one of the eleven must equal the driver's declared
`expectedMemoryShapeWindow` (90) on the first two. `touchedElements` is `Int?`: the five
non-wrap scenarios have a third, independent traversal (a document-source walk, or the
metrics the geometry cursor resolves) and must equal 90 on it too; a wrap scenario has none,
and reporting its streamed rows a second time under another name would be exactly the
vacuity this repair removes. The comparison itself is the pure
`memoryShapeComparisonFailures(_:) -> [String]` of Decision 4; `runMemoryShapeDiagnostics`
calls it, prints, and returns.

Two sub-repairs land with it, and neither is optional:

- **`touched_lines` becomes a count on the variable half.** `providerLines: bufferedLines`
  (`MemoryShapeDiagnostics.swift:386`) is replaced by a count taken through a counting
  `LineMetricsSource` wrapper around the scenario's `UniformLineMetrics`. Until it is, two of
  the eleven contributions satisfy the new equality by assignment.
- **The baseline is the declared constant, never `summaries.first`.** The existing per-group
  byte comparison keeps its first-of-group shape (it is subordinate now, and changing it
  would move `checksum=` values for no gain), but the new comparison does not inherit it.

The existing per-group byte comparison stays, with its `large_text` gap closed by the new
check rather than by extending the byte comparison (bytes would still be a constant compared
with itself).

### C. Counting layout and witness discipline

`CountingWrapLayout` (new file, `Sources/ViewportBenchmarks`) wraps any
`VisualRowLayoutSource` and counts all six hooks — `columnCount`, `columnOffset`,
`canBreak`, `visualRowCount`, `firstVisualRow`, `logicalLine` — through a reference counter
box, so a non-mutating protocol call can record. It **also** carries
`firstVisualRowAtLineCount`, the by-argument counter D-29's discharge rests on (Decision 6);
six totals alone would let the `WrapComputeDrainTests` rewrite retire that pin silently.
`WrapComputeDrainTests` is rewritten onto it and its private copy is deleted.

A counting `LineMetricsSource` wrapper (`CountingLineMetrics`, same file, same reference-box
shape) exists for the variable half's `touched_lines` repair (§4B). It counts
`offset(ofLine:)` and both native inverse hooks, so the fixed/variable half and the wrap half
report the same kind of number.

### D. Unit-level pins for the two properties the mode alone would not pin

The mode is a once-per-CI-run diagnostic at 100k/1M. Two of the four entry points it covers
already have tighter, faster pins in `swift test`:
`WrapRowQueryCountTests.testLayoutAxisStaysLogarithmicInLineCount`-style bounds (`<= 14`,
`3 + 2`, `3 + 2 + 1`) are stricter than this slice's deliberately loose `<= 32`, and they run
on every commit. The two properties with **no** unit-level pin today are exactly the two this
slice invents:

- `WrapComputeProbeCountTests` — `compute(_:layout:)`'s layout-probe count is a constant,
  independent of `lineCount` and of `wrapWidth`, driven through `CountingWrapLayout` at unit
  scale. Nothing pins this today: `WrapComputeDrainTests` counts the *drain*, and
  `compute`'s ladder is covered only by its error cases.
- `DocumentVisualRowCursorProbeCountTests` — the drain's probe count is independent of
  `lineCount` at a fixed width (it varies with width, and that is invariant 11's subject).
  `WrapComputeDrainTests` pins that the drain performs no `compute`; it does not pin that the
  drain does not grow with the document.

Both are cheap, both redden in seconds rather than in a 1M-line run, and both are the
falsification the mode's `<= 32` bound would otherwise be carrying alone. The mode keeps its
own assertions: its job is the scale and the criterion-2 artifact, not the first line of
defence.

### E. Fold-ins

| Row | Contract |
|---|---|
| **D-43** (P2) | The `Lint plan assertions` step runs the self-test first: `./.github/scripts/lint-plan-assertions.sh --self-test && ./.github/scripts/lint-plan-assertions.sh`. `WorkflowShapeTests.testPlanLintStepIsBlockingAndUnguarded` pins the new payload by exact equality; the step stays unguarded and not `continue-on-error`. |
| **D-19** (P3) | **Every** occurrence of `frame-hot-path` in `GateLogicTests.swift` — prose and the test *name* alike — renamed to the `.scrollFrame` vocabulary the code uses, with `rg -i 'frame.hot.path' Tests/ Sources/` empty afterwards. The ledger row says "five sites"; a case-insensitive scan of the merged tree finds **four** (lines 232, 245, 298 and the name `testAbsoluteCeilingFiresForFrameHotPathMode` at 235). The row's number is stale for the same reason D-20's is, so the contract is the empty scan, not a count. |
| **D-20** (P3) | A test pins the `AbsoluteCeiling` class of every **non-gateable** mode. The ledger row says "five" because it was written before `wrapPointQuery` existed; there are **six** today (`rangeOnly`, `memoryShape`, `memoryObservation`, `wrapCompute`, `wrapRowQuery`, `wrapPointQuery`). The test enumerates them from `BenchmarkMode.allCases` filtered on `isGateable`, so the count is derived and the row's stale number cannot be transcribed into a new pin. |
| **D-21** (P3) | The `.scrollFrame` membership pin is made bidirectional, so a gateable mode landing in that arm is checked rather than accepted by default. |
| **D-10** (P3) | A superseded banner on `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md` naming the current WASM context, so the live `AGENTS.md` pointer stops leading to the retired name. |
| **D-11** (P3) | `WorkflowShapeTests.testJobNamesMatchRequiredCheckContexts` additionally pins the **job set**: the workflow's job count and the exact set of names, so a fourth job cannot appear unmodelled. |
| **D-14** (P3) | `derive-gate-budgets.sh`, `harvest-gate-corpus.sh` and `detect-docs-only-pr.sh` each gain the function classification `cross-target-compile.sh` already enforces inside its own `--self-test`: every function is either exercised or explicitly exempt, and an unclassified function fails the self-test. |
| **D-15** (P3) | ~~The four dispatchers converge on one shape (`run_self_test \|\| exit 1` followed by an explicit `exit 0`), so a self-test's failure cannot be swallowed by a dispatcher that merely falls through.~~ **FALSIFIED in execution (Task 8; ledger D-47).** Under `set -e` the prescribed shape is the UNSAFE one: `||` lifts `-e` from the callee's entire body, so a returning assertion reaches `echo "self_test=pass"` and that success becomes the function's status. The edits were made, measured, and reverted; D-15 stays open with its remedy withdrawn. **A fifth script, `lint-plan-assertions.sh`, was checked here and is not vulnerable** (bare call, no trailing `exit 0`) — it later gained D-14's coverage partition in the validation pass (`747682f`, record §7.10 M-7). |
| **D-38** (P3) | `Tests/TextEngineCoreTests/WrapPointQueryCountTests.swift:271`'s `let mustScan = 55 - 15` is derived from the fixture's own `near`/`far` variables instead of transcribed. |

### F. CI wiring

No new step and no new flag. `--memory-shape` is already a blocking step in the host job, so
the wrap half is enforced the moment it prints. The only workflow edit in this slice is
D-43's.

## 5. Acceptance criteria

- **AC1** — `swift run -c release ViewportBenchmarks -- --memory-shape` prints six
  `provider=wrap` lines in the shape of §4A, all `invariant=pass`, and exits 0.
- **AC2** — every per-scenario and cross-scenario invariant in §4A is implemented and each
  one has a recorded red produced by a deliberate break (§6).
- **AC3** — `compute_probes` is identical across all six wrap scenarios, and the value is
  the one measured in Task 1 rather than a number this design predicted.
- **AC4** — the width-10 scenarios report `point_row_in_line > 0`, every scenario reports
  `point_clamp=none`, and `point_query_probes` at width 10 exceeds the width-infinity value.
- **AC5** — D-45's repair is in place, in all three of its parts: a deliberately wrong
  buffered window in **any** of the eleven lines turns the mode red — `large_text` (the
  formerly exempt one) and the **first** line (the one a first-of-group baseline would
  never check) each carry their own recorded red; `touched_lines` on the two
  `variable_uniform` lines is a count, shown by a drill that breaks the count without
  touching `bufferedLines`; and the comparison is reachable as a pure function under
  `swift test`.
- **AC6** — `--memory-observation`'s output is byte-identical to `main`'s apart from
  host-dependent RSS figures: the wrap scenarios did not leak into it (Decision 5).
- **AC7** — the 46 gated checksums and all committed budgets are byte-identical to `main`;
  no gated mode's measured path is touched.
- **AC8** — `swift test` green, `swift build -c release` green, the Foundation-free scan
  empty, and `swift run -c release ViewportBenchmarks -- --gate` reports `gate=pass`.
- **AC9** — every fold-in row in §4E is implemented, and each carries evidence it can fail.
- **AC10** — hosted proof at **step level** on both halves (PR head and post-merge push):
  three jobs green, twelve gates `gate=pass`, `--memory-shape` `invariant=pass` on every
  line. A green job conclusion is not evidence (`verify-ci-step-logs-not-job-conclusion`).
- **AC11** — the ledger records D-45 opened and discharged, **D-46 opened as
  `accepted-risk`** (Decision 1's residual: a probe count cannot see an allocation that does
  not traverse), the nine fold-ins discharged, and the arc file's map pass marks node 5
  `done` with criterion 2's evidence link — scoped to what was measured, naming D-46.
- **AC12** — every wrap line reports `provider_owned_bytes == (line_count + 1) *
  MemoryLayout<Int>.size`, that value is ~10x larger at 1M than at 100k and identical across
  widths at a fixed size, and a deliberate break of the expectation turns the mode red. This
  is criterion 2's second clause — the linear data is provider-owned — made observable.
- **AC13** — the two unit-level pins of §4D exist and each has a recorded red:
  `compute(_:layout:)`'s layout-probe count is constant, and the drain's probe count is
  independent of `lineCount` at a fixed width. Both run under `swift test`, not only in the
  diagnostic.
- **AC14** — `AGENTS.md` describes the wrap half of `--memory-shape`: what it asserts, that
  the observable is provider probes rather than bytes, and D-46's residual. Hard constraint 5
  names this mode as the enforcement of the memory invariant, and every feature slice since
  49 has updated `AGENTS.md` in the same PR.

## 6. Guarantee inventory and drill list (lower bound)

Per D-35: this list is a **lower bound**, and the plan's per-task inventory is the
authority. Each guarantee below must carry a drill producing a recorded red.

| # | Guarantee | Drill |
|---|---|---|
| G1 | `streamed_rows == buffered_rows` | truncate the drain by one row |
| G2 | `compute_probes` flat across sizes and widths | add one gratuitous `firstVisualRow` probe on one scenario |
| G3 | the `<= 32` shape bound | give the drain a linear-in-`lineCount` probe |
| G4 | `buffered_rows` identical across widths | change one scenario's overscan |
| G5 | width-10 `point_row_in_line > 0` | move the query offset back onto a row-start multiple |
| G6 | the walk is counted (`point` at 10 > at ∞) | **positive control, not a mutation**: at width 10, query the row-start offset (`rowInLine == 0`) as well as the `+ 3` offset, and assert the probe count drops. Dropping `columnOffset` from the counter is *not* a valid drill: `canBreak` is counted on the same walk, so the inequality can survive the mutation and the drill would report a green that means nothing |
| G7 | D-45's mode-wide window equality | corrupt the buffered window in the `large_text` scenario, the one that was exempt |
| G8 | `CountingWrapLayout` counts every hook | drop one hook's increment |
| G9 | D-43's payload pin | append `\|\| true` to the lint step |
| G10 | D-11's job-set pin | add a fourth job to the workflow |
| G11 | D-14's classification, per script | add an unexercised function to each |
| G12 | D-20/D-21's class pins | move a mode between arms |
| G13 | the range is ordered and bounded (invariant 1) | hand the checker a range with `bufferEndExclusive > totalRows` |
| G14 | `visible_rows == 80` (the alignment half of invariant 2) | shift the offset by half a row and watch 80 become 81 |
| G15 | `point_clamp == none` (invariant 6) | raise `x` to 12.0, which clamps at width 10 and not at the other two |
| G16 | `provider_owned_bytes` (invariant 7 / AC12) | assert against `lineCount` instead of `lineCount + 1` |
| G17 | D-45's baseline is declared, not first-of-group | corrupt the **first** summary and assert that *it* is the line printing `invariant=fail` |
| G18 | `touched_lines` is counted on the variable half | make the counting wrapper miss one probe; `buffered_lines` must stay 90 while `touched_lines` moves |
| G19 | `CountingWrapLayout` keeps the by-argument counter | rewrite `WrapComputeDrainTests`'s assertion onto the six totals and confirm it can no longer distinguish a drain that computes |
| G20 | §4D's compute-probe pin | give the ladder a `lineCount`-dependent probe |
| G21 | §4D's drain pin | give the drain a `lineCount`-dependent probe |

## 7. Invariant fingerprint

Nothing measured moves. The 46 gated checksums, all committed budgets, the corpus, and
`--wrap-compute` / `--wrap-row-query` / `--wrap-point-query` checksums are byte-identical
across this slice.

`--memory-shape`'s **five existing lines** (three fixed, two variable; 15 tokens each, 16 on
`large_text`, which also prints `document_bytes=`) keep their `checksum=` values, because the
comparison is not folded into them (Decision 4). They stay byte-identical in full, the
`touched_lines` repair included: on the variable half the counted value **is** 90, so the
repair changes the number's provenance from an assignment to a measurement without changing
the number. If it does not print 90, that is the repair reporting a defect, not a fingerprint
miss.

The new output is six additional lines and nothing else — but note the mode's line count goes
**5 → 11**, so any checksum extraction over a hosted log that does not carry D-18's
`grep -v -e 'mode=memory_shape' -e 'mode=memory_observation'` filter changes its total. The
plan's AC7 step uses the filter; the raw count moves from 54 to 60.

## 8. Risks and residuals

- **The flat constant may not be 2.** The design reads two layout probes out of
  `validateVisualRowLayout` (Decision 2), but a probe reached through a path the reading
  missed would make it 3. Decision 8 answers this: Task 1 measures, and the contract table
  is filled from the measurement. The risk is to the *number*, never to the shape — and the
  shape is what invariant 8 and AC3 assert.
- **Provider construction cost at 1M x width 10 — quantified from shipped evidence, not
  deferred to a measurement.** `BenchmarkWrapLayout` packs every line honestly (its comment
  says why), so the narrowest scenario does roughly 80M cell steps. That cost is already on
  record: `--wrap-compute` builds the same type at 100k lines / 80 cells and prints
  `reindex_ns=54_559_667` at width 10, `20_945_000` at ∞ and `13_327_375` at width 40
  (`verification/2026-09-03-wrap-point-query.md:550-552`, local release). Construction is
  linear by construction, so 1M costs ~10x: about **0.55 s** for the worst scenario and
  **~1 s** for all six builds locally, 2-3x that hosted. That is noise against a step that
  already builds a 1M-line synthetic provider and an 11.2 MB text document. Task 1 records
  the actual wall time; the risk is retired rather than carried.
  **The fallback previously written here does not exist and has been removed:** the prefix
  sum is width-dependent (different widths pack to different row counts), so no 1M-line
  prefix can be "reused across widths". If the cost ever does become material, the available
  move is a **second initializer** on `BenchmarkWrapLayout` taking a precomputed `firstRow` —
  same type, same stored properties, same protocol behaviour, same `provider_owned_bytes`,
  differing only in how the array is filled. That is not a fork of the provider
  `--wrap-compute` measures, because what `--wrap-compute` measures is the *packing*
  constructor, which stays its only caller. Building one provider at a time stands on its own
  (§4A) as a peak-memory decision, not as a time fallback.
- **D-14 is the heaviest fold-in.** Three scripts gain a coverage partition each. If it
  exceeds its task budget it drops to a named residual (Decision 10) rather than delaying
  node 5.
- **The `<= 32` bound is a judgement.** It is deliberately loose against the noise it must
  tolerate and deliberately tight against the failure it must catch; it is not calibrated
  evidence and must not be re-derived when it fires. If it fires, a probe count grew — read
  the code.

## 9. Out of scope

Node 6 and every row on its precondition list (D-9, D-28, D-30, D-31, D-36, and D-20's
*runtime* consequence once a wrap mode becomes gateable); `--memory-observation` extension
to wrap; D-13 and D-22 (engine work with independent merit — D-22 drags a budget
re-derivation); D-40, D-41, D-42 and D-44 (the slice-56 linter residuals, which would make
this a third consecutive infrastructure slice).

**The `--memory-observation` decline is load-bearing enough to restate.** RSS is the only
instrument in this repository that reads memory *directly*, so it is also the only thing
that would close D-46 (Decision 1). It is declined here anyway, for a reason that is about
the instrument and not about the cost: `--memory-shape` is a **blocking** step and RSS is
host-dependent and noisy, so an RSS-derived assertion in this mode would be a gate that
fails on the runner rather than on the code. The available follow-up, if criterion 2's
evidence is later judged too indirect, is to extend the **non-blocking**
`--memory-observation` with one wrap scenario per size at a single width — a separate,
deliberate call, not the accidental extension Decision 5 exists to prevent. D-46 records
the gap so that call can be made on evidence.
