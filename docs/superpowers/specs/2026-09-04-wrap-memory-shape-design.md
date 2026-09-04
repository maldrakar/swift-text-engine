# Slice 57 — wrap memory shape (design)

**Map node:** wrap arc node 5. **Criterion:** 2 — *core memory not linear with wrap
on; `--memory-shape` extended to the wrap path* — the only wrap criterion with no
evidence at all.

**Selected by** the [slice-56 post-slice review](../reviews/2026-09-04-slice-56-post-slice-review.md)
(Option A, topological). Its fold-in was one row (D-43); the user raised the depth to
**nine** rows on 2026-09-04 ("close as much debt as is relevant"), and this design adds a
tenth, **D-45**, discovered while reading the mode this slice extends.

## 1. Scope

Three things, in this order, and the order is load-bearing (Decision 10):

1. **The spine** — a wrap half of `--memory-shape`: six scenarios over the complete wrap
   query surface, asserting that core-owned work is bounded by the viewport and does not
   grow with the document.
2. **The repair** — the existing fixed/variable half's cross-scenario comparison, which
   today compares a constant with itself (§2). Opened as **D-45** and discharged here,
   because a criterion cannot be closed by a mode whose headline invariant cannot fail.
3. **The fold-ins** — D-43 (P2) and D-10, D-11, D-14, D-15, D-19, D-20, D-21, D-38 (P3).

Not in scope: promoting anything to a gate (node 6), `--memory-observation` (Decision 5),
and every row on node 6's precondition list (D-9, D-20's *runtime* consequence, D-28,
D-30, D-31, D-36). See §9.

## 2. What `--memory-shape` proves today, and what it does not

Measured by reading `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift`, not
asserted:

- `coreOwnedBytesEstimate()` (line 98) and `variableCoreOwnedBytesEstimate()` (line 104)
  **take no scenario**. Each is a fixed sum of `MemoryLayout<T>.size` and returns the same
  value for every scenario in its group.
- `runMemoryShapeDiagnostics()` (line 417) compares each summary's `coreOwnedBytes`
  against the first of its provider group. For the `synthetic` group that is `x == x`.
  For `large_text` **neither** branch matches, so it falls to `else { comparisonPasses =
  true }` — that scenario's headline invariant is not compared at all.
- `MemoryLayout<T>.size` counts the inline footprint. A struct that captured an array
  reports the size of a pointer, so the estimate cannot see the growth it exists to
  detect.

What *does* carry weight today, and stays untouched: the per-scenario structural checks —
`geometry.lineCount == expectedBufferedLines`, `provider.lineCount ==
expectedBufferedLines`, `provider.missingCount == 0`, and `providerBytesPasses`.

Two consequences. First, the wrap half must not be built on the byte estimate — hence
Decision 1. Second, the existing half's comparison is repaired here rather than recorded
for later (**D-45**): this slice's whole purpose is to give criterion 2 evidence, and
leaving half the mode proving nothing would close the criterion on a measurement that
cannot fail — the exact shape this repository has shipped five times (`## Gate budgets`,
"Never hand-type a budget").

## 3. Decisions

**Decision 1 — the observable is provider probes, not bytes.** Every wrap entry point
returns fixed-size values, so "core memory does not grow" is observed through the only
quantity that *would* grow if it stopped being true: the number of calls the core makes
into the layout source. Bytes remain a printed token (`core_owned_bytes`) for continuity
with the existing lines, and the code says in a comment that it is continuity, not
evidence.

**Decision 2 — `compute` is asserted flat; the other three are asserted logarithmic.**
`compute(_:layout:)` reads `totalRows` with one `firstVisualRow(ofLine: lineCount)` probe
and then runs both boundary searches over `UniformLineMetrics`, which is arithmetic and
touches no provider. Its layout-probe count is therefore a **constant**, and the six
scenarios must report the *same* number. `DocumentVisualRowCursor`, `visualRowAt` and
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

**Decision 4 — a mode-wide structural equality replaces the vacuous byte comparison
(D-45).** Every scenario in the mode — three fixed, two variable, six wrap — shares
`lineHeight = 16`, `viewportHeight = 80 * 16` and `overscan 5/5`, so every one of them must
report a buffered window of **90** and must have streamed and touched exactly that many
elements. One number, four code paths, eleven lines. `large_text` stops being exempt. The
byte comparison is kept as a subordinate check rather than deleted, so nothing that passes
today starts failing for a reason unrelated to this slice; it is simply no longer the only
thing being compared. Printed `checksum=` values do not move: the comparison is not folded
into them.

**Decision 5 — wrap scenarios get their own list and driver.**
`MemoryObservationDiagnostics.swift:151` calls `memoryShapeScenarios()`, so appending wrap
scenarios to that function would silently extend `--memory-observation` too — a second
mode's output changed by a slice whose fingerprint is supposed to be the first. Wrap
scenarios live in `wrapMemoryShapeScenarios()` in a new file,
`WrapMemoryShapeDiagnostics.swift`, and `runMemoryShapeDiagnostics()` calls both.

**Decision 6 — `CountingWrapLayout` moves into the target; the test copy is deleted, not
pinned.** `Tests/ViewportBenchmarksTests/WrapComputeDrainTests.swift:18` already carries a
`CountingLayout` counting one hook. The generalized version — counting all six
`VisualRowLayoutSource` hooks — belongs in `Sources/ViewportBenchmarks`, and
`WrapComputeDrainTests` is rewritten to use it. Deleting a copy beats pinning one (the
D-41 argument, applied where it is cheap).

**Decision 7 — every counter carries a witness.** A probe count of zero is evidence only if
the probe would have been counted. `WrapComputeDrainTests` already does this ("a witness
call proves the probe exists to be counted"); the new assertions inherit the rule, and each
one names the witness that makes its number non-vacuous.

**Decision 8 — the constants come from a measurement, not a prediction.** The exact flat
value for `compute_probes` (1 is the reading of the code; the validation ladder may make it
2 or 3) and the observed deltas for the other three are **measured in the plan's first
task** and written into the spec's contract table then. No acceptance criterion states a
number this design guessed.

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
provider, and emits one line:

```
mode=memory_shape provider=wrap scenario=<size>_lines_width_<w> line_count=<N>
wrap_width=<w> total_rows=<R> visible_rows=80 buffered_rows=90 streamed_rows=90
point_row_in_line=<k> compute_probes=<a> drain_probes=<b> row_query_probes=<c>
point_query_probes=<d> core_owned_bytes=<e> provider_owned_bytes=<f>
invariant=<pass|fail> checksum=<x>
```

Per-scenario invariants (each can fail on its own line):

1. the range is ordered and bounded within `0...totalRows`;
2. `visible_rows == 80` and `buffered_rows == 90`;
3. `streamed_rows == buffered_rows` — the cursor streams the buffer, no more and no less;
4. `compute_probes` equals the measured constant (Decision 8);
5. at width 10, `point_row_in_line > 0` — the within-line walk is exercised, not assumed.

Cross-scenario invariants, checked in the driver over the collected results:

6. **flatness** — `compute_probes` is identical across all six;
7. **shape** — for each entry point and each width, `probes(1M) - probes(100k) <= 32`;
8. **width independence of the buffer** — `buffered_rows` and `streamed_rows` are identical
   across all six;
9. **the walk is a width term, not a size term** — `point_query_probes` at width 10 exceeds
   its value at width infinity (the walk costs something, so the counter tracks it), while
   the width-10 delta between 1M and 100k stays inside the bound of (7).

A violated cross-scenario invariant prints `invariant=fail` on the offending line and exits
non-zero, exactly as the existing driver does.

### B. The repair (D-45)

`runMemoryShapeDiagnostics()` gains a mode-wide structural comparison: every summary — fixed,
variable and wrap — contributes `(scenarioName, bufferedWindow, streamedElements)`, and all
of them must agree on both numbers. The existing per-group byte comparison stays, with its
`large_text` gap closed by the new check rather than by extending the byte comparison
(bytes would still be a constant compared with itself).

### C. Counting layout and witness discipline

`CountingWrapLayout` (new file, `Sources/ViewportBenchmarks`) wraps any
`VisualRowLayoutSource` and counts all six hooks — `columnCount`, `columnOffset`,
`canBreak`, `visualRowCount`, `firstVisualRow`, `logicalLine` — through a reference counter
box, so a non-mutating protocol call can record. `WrapComputeDrainTests` is rewritten onto
it and its private copy is deleted.

### D. Fold-ins

| Row | Contract |
|---|---|
| **D-43** (P2) | The `Lint plan assertions` step runs the self-test first: `./.github/scripts/lint-plan-assertions.sh --self-test && ./.github/scripts/lint-plan-assertions.sh`. `WorkflowShapeTests.testPlanLintStepIsBlockingAndUnguarded` pins the new payload by exact equality; the step stays unguarded and not `continue-on-error`. |
| **D-19** (P3) | `frame-hot-path` prose in `GateLogicTests.swift` (five sites incl. a test name) renamed to the `.scrollFrame` vocabulary the code uses. |
| **D-20** (P3) | A test pins the `AbsoluteCeiling` class of every **non-gateable** mode. The ledger row says "five" because it was written before `wrapPointQuery` existed; there are **six** today (`rangeOnly`, `memoryShape`, `memoryObservation`, `wrapCompute`, `wrapRowQuery`, `wrapPointQuery`). The test enumerates them from `BenchmarkMode.allCases` filtered on `isGateable`, so the count is derived and the row's stale number cannot be transcribed into a new pin. |
| **D-21** (P3) | The `.scrollFrame` membership pin is made bidirectional, so a gateable mode landing in that arm is checked rather than accepted by default. |
| **D-10** (P3) | A superseded banner on `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md` naming the current WASM context, so the live `AGENTS.md` pointer stops leading to the retired name. |
| **D-11** (P3) | `WorkflowShapeTests.testJobNamesMatchRequiredCheckContexts` additionally pins the **job set**: the workflow's job count and the exact set of names, so a fourth job cannot appear unmodelled. |
| **D-14** (P3) | `derive-gate-budgets.sh`, `harvest-gate-corpus.sh` and `detect-docs-only-pr.sh` each gain the function classification `cross-target-compile.sh` already enforces inside its own `--self-test`: every function is either exercised or explicitly exempt, and an unclassified function fails the self-test. |
| **D-15** (P3) | The four dispatchers converge on one shape (`run_self_test \|\| exit 1` followed by an explicit `exit 0`), so a self-test's failure cannot be swallowed by a dispatcher that merely falls through. |
| **D-38** (P3) | `WrapPointQueryCountTests`'s `let mustScan = 55 - 15` is derived from the fixture's own variables instead of transcribed. |

### E. CI wiring

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
- **AC4** — the width-10 scenarios report `point_row_in_line > 0`, and `point_query_probes`
  at width 10 exceeds the width-infinity value.
- **AC5** — D-45's repair is in place: a deliberately wrong buffered window in **any** of
  the eleven lines, `large_text` included, turns the mode red.
- **AC6** — `--memory-observation`'s output is byte-identical to `main`'s apart from
  host-dependent RSS figures: the wrap scenarios did not leak into it (Decision 5).
- **AC7** — the 46 gated checksums and all committed budgets are byte-identical to `main`;
  no gated mode's measured path is touched.
- **AC8** — `swift test` green, `swift build -c release` green, the Foundation-free scan
  empty, and `swift run -c release ViewportBenchmarks -- --gate` reports `gate=pass`.
- **AC9** — every fold-in row in §4D is implemented, and each carries evidence it can fail.
- **AC10** — hosted proof at **step level** on both halves (PR head and post-merge push):
  three jobs green, twelve gates `gate=pass`, `--memory-shape` `invariant=pass` on every
  line. A green job conclusion is not evidence (`verify-ci-step-logs-not-job-conclusion`).
- **AC11** — the ledger records D-45 opened and discharged, the nine fold-ins discharged,
  and the arc file's map pass marks node 5 `done` with criterion 2's evidence link.

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
| G6 | the walk is counted (`point` at 10 > at ∞) | stop counting `columnOffset`, and watch the inequality fail |
| G7 | D-45's mode-wide window equality | corrupt the buffered window in the `large_text` scenario, the one that was exempt |
| G8 | `CountingWrapLayout` counts every hook | drop one hook's increment |
| G9 | D-43's payload pin | append `\|\| true` to the lint step |
| G10 | D-11's job-set pin | add a fourth job to the workflow |
| G11 | D-14's classification, per script | add an unexercised function to each |
| G12 | D-20/D-21's class pins | move a mode between arms |

## 7. Invariant fingerprint

Nothing measured moves. The 46 gated checksums, all committed budgets, the corpus, and
`--wrap-compute` / `--wrap-row-query` / `--wrap-point-query` checksums are byte-identical
across this slice. `--memory-shape`'s existing eleven-token lines keep their `checksum=`
values (Decision 4). The new output is six additional lines and nothing else.

## 8. Risks and residuals

- **The flat constant may not be 1.** The layout ladder may probe more than the code
  reading suggests. Decision 8 answers this: Task 1 measures, and the contract table is
  filled from the measurement. The risk is to the *number*, never to the shape.
- **Provider construction cost at 1M x width 10.** `BenchmarkWrapLayout` packs every line
  honestly (its comment says why), so the widest scenario does roughly 80M cell steps.
  Task 1 measures the wall time of all six builds; if it is material, the fallback is to
  build one provider at a time and reuse a single 1M-line prefix across widths — **not** a
  faster constructor, which would fork the provider `--wrap-compute` measures.
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
to wrap (RSS evidence, considered and declined at brainstorm); D-13 and D-22 (engine work
with independent merit — D-22 drags a budget re-derivation); D-40, D-41, D-42 and D-44 (the
slice-56 linter residuals, which would make this a third consecutive infrastructure slice).
