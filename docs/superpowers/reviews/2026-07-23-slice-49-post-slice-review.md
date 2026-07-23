# Slice 49 — post-slice review (visual-row model + row-packing, wrap node 1)

**Slice:** 49 — soft-wrap arc, **node 1**
**Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md) · **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)
**Spec:** [`specs/2026-07-22-visual-row-model-design.md`](../specs/2026-07-22-visual-row-model-design.md) · **Plan:** [`plans/2026-07-22-visual-row-model.md`](../plans/2026-07-22-visual-row-model.md)
**Merged:** [PR #114](https://github.com/maldrakar/swift-text-engine/pull/114), merge commit `8e91f52`.
**Merged proof:** post-merge `push`-to-`main` run `29990966569` @ `8e91f52` — green at **step** level.

## What shipped

The first real functional-core increment of the soft-wrap arc: a
`WrapMetricsSource` provider contract and greedy per-logical-line row-packing,
delivered via subagent-driven-development (5 tasks, each per-task reviewed
clean; final whole-branch review on opus = ready-to-merge, 0 P0/P1).

- **`WrapMetricsSource`** (`Sources/TextEngineCore/WrapMetricsSource.swift`) —
  refines `LineHorizontalMetricsSource` with exactly one predicate,
  `canBreak(beforeColumn:inLine:)`, no default. Provider owns break
  opportunities; the core owns no Unicode/shaping/font knowledge.
- **`VisualRow`** (Equatable value type), **`VisualRowQuery<Metrics>`**
  (generic, **not** Equatable — the project's first generic query enum),
  **`VisualRowCursor<Metrics>`** (generic O(1)-state streaming cursor mirroring
  the proven `VariableLineGeometryCursor<Metrics>` shape), and
  **`ViewportValidationError.nonPositiveWrapWidth`**.
- **`ViewportVirtualizer.visualRows(inLine:wrapWidth:metrics:)`** — greedy
  first-fit (largest legal break-end that fits; unbreakable run overflows its
  row rather than force-breaking), rows tile `[0, count)`, blank line → one
  `[0,0)` row, width = advance sum. Validates `wrapWidth > 0` (accepts `+∞`;
  rejects `NaN`/`−∞`/`≤0` — the F1 `isFinite` trap avoided) and runs the
  `columnAt`-parity O(1) metrics ladder in `columnAt`'s fixed order.
- **Per-line equivalence oracle:** irregular advances + irregular breaks at
  `wrapWidth ≥ total` (`.infinity` included) pack to exactly one `[0, count)`
  row equal to the no-wrap column model.

18 new tests (WrapMetricsSourceTests 3 / VisualRowEquivalenceTests 3 /
WrapPackingTests 5 / WrapValidationTests 7); full suite 333/0. No new gate,
no CI wiring (node 1 is pure model + math, per spec §Benchmark Mode / CI).

## Acceptance-criteria status

All eight ACs discharged (spec §Acceptance Criteria):

| AC | Status | Evidence |
|---|---|---|
| 1 `WrapMetricsSource` refines + `canBreak` no default | ✅ | Task 1 review; reviewer confirmed refinement/no-default vs real `LineHorizontalMetricsSource` |
| 2 Types + error case with ratified shapes | ✅ | Task 2 review (generic non-Equatable query enum, internal cursor init, exact `VisualRow` fields) |
| 3 `visualRows` width predicate `> 0` (∞ allowed) + `columnAt`-parity ladder | ✅ | Task 4 review; ladder proved order-identical to `HorizontalPositionQuery.swift:18-37` |
| 4 Greedy packing (Decision 2) | ✅ | Task 3 review + final review hand-trace; WrapPackingTests |
| 5 Equivalence oracle over irregular inputs | ✅ | `VisualRowEquivalenceTests.testWidthAtOrAboveTotalYieldsOneRowEqualToNoWrap` |
| 6 All invariant tests pass; suite green | ✅ | 333/0 (`swift test`), PR-head + post-merge runs |
| 7 Foundation-free + release + gate + iOS/WASM cross-compile | ✅ | Verification record; both hosted runs green at step level |
| 8 Hosted CI green at step level, run IDs recorded, merged proof in post-merge run | ✅ | PR-head `29958326817` + post-merge `29990966569`, both step-level green |

## Strengths

- **The final whole-branch review (opus) proved the algorithm, not just read
  it:** greedyEnd always returns `start < e ≤ columnCount` (so strict progress,
  no empty row / gap / overlap / infinite loop), verified across five boundary
  cases (only-`columnCount`-fits, no-interior-breaks, char-wrap below one cell,
  single-cell, blank); the early-exit is sound under the monotone-offset
  precondition; the ladder is at exact `columnAt` parity; `+∞` flows through the
  same uniform branch a finite total uses.
- **DRY equivalence by construction:** the no-wrap reference and the wrap
  advances are the *same* `LineHorizontalMetricsSource` object, so the oracle
  cannot drift (Decision 1's rationale held in practice).
- **Scope discipline / correct incrementalism:** the plan's deliberate stubs
  (Task 2 whole-line `end = columnCount`; stored-but-unused `wrapWidth`) were
  transcribed as labelled intermediate steps and consumed exactly by Task 3 —
  no premature building, no dead code at HEAD.
- **Comment-truth caught and fixed in-slice:** the Task-4 review found the
  `visualRows` doc comment still calling validation future work; Task 5 folded
  a one-line past-tense fix (commit `eb9361c`).

## Issues

No P0/P1. Carried Minors (all non-blocking, from the per-task and final
reviews):

- **P3 (→ ledger D-12):** no test exercises the *interior* exact-equal width
  boundary (`columnOffset(c) − startOffset == wrapWidth`); the whole-line
  inclusive edge is covered by the equivalence oracle at `width == total`.
  Operator correct by inspection. Fold-in for node 2 (touches the same cursor).
- **P3 (style, not ledgered):** `greedyEnd` uses `-1` `Int` sentinels rather
  than `Int?` for "not found yet" (well-commented, correct); and the blank-line
  short-circuit in `visualRows` is implicit (fall-through) vs `columnAt`'s
  explicit `if count == 0`. Both functionally identical; polish only.
- **Process caution recorded (not a code defect):** the post-merge push run's
  creation lagged the merge by ~13 min, and `gh run watch --exit-status` returned
  a *false* FAILED (it sampled the JSON mid-run while the realistic-provider gate
  step's conclusion was still null). Authoritative verification is the final
  per-step conclusions, not the watch exit code — the "verify CI step logs, not
  the job conclusion" lesson, inverted (a watch verdict is not the job
  conclusion either).

---

# Recommendation (skill Mode 2)

Map pass output is the updated [arc file](../arcs/wrap.md): node 1 marked
`done`, node 2 marked next (lean), map re-validated (nodes 2–9 stand — the
per-line packing math is settled and is *not* where criterion-1 risk lives;
that risk is untouched and lives in node 2). Next step is **topological**, not
a fork.

### Scoreboard delta

- **Criterion 3** (wrap-aware query equivalents; no-wrap preserved; wrap at ∞ =
  no-wrap): `open` → **`partial`**. The **per-line** equivalence half is proven
  (wrap at `≥ total`/`∞` width = one whole-line row = the no-wrap column model,
  over irregular advances + breaks), and the no-wrap path is untouched.
  Evidence: [PR #114](https://github.com/maldrakar/swift-text-engine/pull/114)
  (`8e91f52`), post-merge run `29990966569`, `VisualRowEquivalenceTests`.
  Remaining: the query analogs (compute over visual rows, y→row,
  point→(row,cell)) and the **whole-document** equivalence half — both node 2+.

Still open/partial: criterion 1 (open — the arc's top risk, untouched),
criterion 2 (open), **criterion 3 (partial)**, criteria 4/5/6 (open).

### Debt ledger delta

- **Appended D-12** (P3, born this review): interior exact-equal wrap-width
  boundary untested — see Issues; fold-in for node 2.
- No P2/P3 discharged this slice (node 1 added no infra guardrails to pay down).
- **Open counts:** P2 = 2 open (D-1, D-2) + 3 `deferred(user, 2026-07-22)`
  (D-7, D-8, D-9); P3 = 6 open (D-3, D-6, D-10, D-11, D-12) + 1
  `deferred(user, 2026-07-21)` (D-5); 1 `accepted-risk` (D-4).
- **Escalation check:** no open P2 is yet ≥ 3 completed slices old, so none is
  forced into Candidate options this review. D-1/D-2 (born slice 47) are at **2**
  completed slices (48, 49) and **hit the ≥ 3 threshold at the Slice 50 review**
  — flagged now so the schedule-or-defer moment is not a surprise. The three
  deferred P2s (D-7/D-8/D-9) remain user-deferred; not re-surfaced.

### Falsifiability audit

Standing guarantees this slice added, each with can-it-fail evidence:

- **WrapPackingTests** (greedy correctness): **recorded red** — Task 3 ran RED
  3/5 failing against the Task-2 whole-line stub before the greedy walk existed
  (verification record). Falsifiable. ✅
- **WrapValidationTests** (the `columnAt`-parity ladder): **recorded red** —
  Task 4 ran RED with 10 failures, and `testNegativeColumnCountFails` trapped in
  the cursor before the ladder was added. Falsifiable. ✅
- **VisualRowEquivalenceTests** (per-line equivalence oracle): **no recorded
  red** — the Task-2 whole-line stub *passed* it (at `width ≥ total` correct
  behaviour IS one whole-line row), so the stub→greedy transition did not redden
  it. Its discriminating red is a `<`-instead-of-`<=` mutation in `greedyEnd`
  (which would split the line at `width == total` → two rows) or any large-width
  packing bug — established by inspection, not by a recorded run. Per the audit
  rule this spawns a **mandatory candidate**: prove the equivalence oracle can
  fail (a recorded mutation check, or the interior-boundary fixture D-12 which
  exercises the same inclusive edge). Routed into Option A's fold-in below.

### Candidate options

- **Option A — Slice 50 = node 2: wrap-aware viewport compute over visual rows +
  the width-change cost demonstration. (LEAN.)** Advances **criterion 1**
  (retires the arc's top feasibility risk — who owns row data at a width and
  what recomputes when the width changes) **and criterion 3** (whole-document
  compute half). Map node 2 — the **topological forced prerequisite** for the
  query analogs (nodes 3–4). Folds in **D-12** and the mandatory
  equivalence-oracle falsifiability follow-up (a recorded mutation / interior
  boundary test lands naturally alongside cross-line packing tests). This is the
  risk-first choice the map has front-loaded since arc start.
- **Option B — Slice 50 = node 3/4 geometry conveniences (y→row and/or
  point→(row,cell) wrap analogs).** Advances criterion 3 further but **does not
  retire criterion 1**; the map explicitly parks geometry conveniences *behind*
  node 2. Choosing this over A postpones the scariest uncertainty — the red flag
  the risk-first rule exists to catch. Not recommended.
- **Option C — Slice 50 = infra/debt: discharge D-1 and/or D-2** (the two open
  P2s from slice 47) before they escalate at the Slice 50 review, optionally
  folding D-12. Pays down debt proactively but **advances no wrap criterion** and
  delays the top-risk retirement. Reasonable only if the user wants the P2s
  cleared before the escalation moment rather than at it.

**Routing (topological step):** the selection is **Option A — node 2**. It is
the forced topological next step and the one slice that retires the arc's top
risk; D-1/D-2 are not yet forced and can ride to the Slice 50 review's
escalation moment. Stated as the recommendation per the skill's topological
routing — the user can override (e.g. pull Option C forward if they prefer to
clear the slice-47 P2s now).
