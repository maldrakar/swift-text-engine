# Point-Geometry-Query CI Gate Promotion + Corpus Trailing-Window Ratchet Repair Design

Date: 2026-07-16

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 40 of SwiftTextEngine, following the Slice 39 post-slice review:

```text
docs/superpowers/reviews/2026-07-15-slice-39-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
That requirement already holds for **ten** blocking latency gates in the hosted
`Host tests and benchmark gate` job: synthetic, static variable-height,
variable-height-mutation, structural-mutation, bulk-structural-mutation,
line-query, line-geometry-query, column-query, column-geometry-query, and
point-query. It does **not** yet hold for the geometry-bearing 2D point query
`pointGeometryAt` introduced in Slice 39.

Slice 39 added the public stateless query
`ViewportVirtualizer.pointGeometryAt(x:y:lineMetrics:columnMetrics:) ->
PointGeometryQuery` — the geometry-bearing companion to Slice 37's `pointAt`,
which composes `lineGeometryAt` with `columnGeometryAt` to return both axes'
boxes, within-box fractions, and clamp flags. Unlike every prior functional
capability slice, Slice 39 was the **first to mint a gated budget under Slice
38's derived-budget rules** — no hand-typed placeholder is legal any more — so it
shipped its budget through the corpus derivation and landed the CI gate in a
deliberate **two-step, not-yet-blocking** shape (Slice 39 design Decision 5):

- a bare `--point-geometry-query` step **without** `continue-on-error`, blocking
  on **correctness** (`failureCount != 0` fails the job), writing its benchmark
  output to a temp file so it does not double-weight future harvests;
- a `--point-geometry-query --gate` step **with** `continue-on-error`,
  **observational on latency** — its budget is enforced by the script but a
  budget miss cannot fail the job yet.

The Slice 39 post-slice review recommends Slice 40 as:

```text
Option A: promote --point-geometry-query to the eleventh blocking gate — and
repair the ratchet
```

folding in **Slice 38's still-open P2 #2** — the `3×max` floor over an
append-only corpus as a one-way ratchet — because Slice 40 must harvest and
re-derive anyway, making it the cheapest place to also repair the ratchet rather
than trigger it once more. The user selected **Option A** and, for the ratchet
repair, the **trailing-window** mechanism over outlier rejection, a written
curation policy, or deferral.

### Relationship to the prior promotions (Slices 15, 21, 24, 26, 28, 32, 34, 36, 38)

This slice is the eleventh benchmark-gate promotion in the established cadence,
and — like Slice 26 (which folded in the `deterministicIndex` overflow hardening)
and Slice 38 (which recalibrated every budget before promoting `--point-query`) —
it is **not a bare promotion**: it bundles a substantive change to the
calibration machinery. The bundling is admitted under the standing
functional-vs-CI separation convention *only because* Slice 40 is already a
CI/infra promotion slice that must harvest and re-derive, so the ratchet repair
lives in the same concern, not a smuggled-in second one (Slice 39 review, final
section).

Unlike Slices 28/32/34/36 (pure zero-Swift promotions of a never-hosted
benchmark), the `--point-geometry-query` benchmark **already runs in hosted CI**
since Slice 39 — bare (correctness) and gated (observational). So this promotion
is the **flip-an-existing-observation-to-blocking** shape (like Slices 15 and
21), with prior hosted Linux evidence in hand and more accumulating on every run
since the Slice 39 merge.

### The two concerns, and why they compose

1. **Ratchet repair (substantive).** `derive-gate-budgets.sh` and
   `GateFloorTests.swift` both compute their floor and median from `max()` /
   `median()` over the **entire append-only corpus**. That has no reverse gear: a
   single noisy hosted sample permanently loosens a budget, and the floor test
   then *enforces* that outlier (Slice 38 P2 #2). Slice 39's P2 #1 shows it biting
   — six budgets repo-wide within ~5% of the `3×max` floor, worst case
   `line_geometry_query|uniform_1k` p99 at **0.0% margin**, one noisy sample away
   from reddening every PR on a clean tree.

2. **Promotion (mechanical).** Collapse the two-step CI wiring into one step
   blocking on both correctness and budget, making `--point-geometry-query` the
   eleventh blocking gate.

They compose because the promotion *requires* a harvest-and-re-derive, and per
`AGENTS.md`'s `## Gate budgets`, **a harvest re-derives every mode**. Slice 40
therefore re-derives the whole suite anyway; doing that through the
newly-windowed derivation is the ratchet repair, and it is the same sweep.

### Current corpus and calibration shape (relevant facts)

- Corpus:
  `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`, **append-only**,
  header `run_id  mode  scenario  p95_ns  p99_ns`, 1,691 data rows from 42
  distinct runs at the time of writing. The run id is the harvester's dedup key
  (`gh run list --json databaseId`), so it is GitHub's **globally monotonic**
  run database id: a numeric sort of `run_id` is exactly chronological order.
- Per-key run counts range **6 → 42**: the oldest modes (`pipeline`,
  `variable_height`, `variable_height_mutation`) have 42 runs; `point_geometry_query`
  (newest, Slice 39) has 6; `realistic_provider` has 29 and — being the one gated
  mode CI never runs with `--gate` — reaches the corpus only through the PR-only
  `mode=realistic_relative_observation` line, so it appears only in PR runs.
- The recipe (`derive-gate-budgets.sh`, Slice 38 Decision 2):

  ```text
  budget_p95 = round_up_2sf(max(8 * median(p95), 3 * max(p95)))
  budget_p99 = round_up_2sf(max(2 * budget_p95, 8 * median(p99), 3 * max(p99)))
  ```

  The `3×max` floor is inside the formula and covers both statistics; `GateFloorTests`
  independently re-asserts `budget >= 3 * max(corpus)` on every `swift test`.
- Slice 38 deliberately left **13 scenarios NOT recipe-derived** (pipeline ×2,
  structural_mutation ×3, variable_height_mutation ×3, bulk_structural_mutation
  ×5), keeping their tighter-than-recipe hand budgets because deriving them would
  *loosen* several. `GateFloorTests` still holds those 13 to the `3×max` floor;
  it does not require them to equal the recipe output.

## Problem

Two enforcement/robustness gaps:

1. **The point-geometry-query path's latency is not blocking.** Its `--gate` step
   carries `continue-on-error`, so a budget miss — and, if the two steps were ever
   merged wrong, a correctness failure — cannot fail the job. The brief's
   "benchmark gates block merge" principle is not yet true for the geometry-bearing
   2D point query.

2. **The calibration corpus is a one-way ratchet.** `max()` over an append-only
   corpus is monotonically non-decreasing, and `GateFloorTests` makes the worst
   sample load-bearing: you cannot ship a tighter budget while an old spike exists,
   and the only remedy today is deleting the row (undocumented, and against the
   "corpus is the evidence" ethos). Followed to its end (Slice 38 P2 #2), a bad
   enough sample ratchets a budget past the 50× ceiling, the gate reports
   `budget_stale`, the agent re-derives — and the script returns a budget that
   *still* violates the ceiling because the outlier is immortal: a deadlock with no
   documented escape. Slice 39 grew the near-floor cluster 3 → 6, so the mechanism
   is biting now, not hypothetically.

## Scope

Slice 40, in a single PR:

- introduces a **per-key trailing window of the last N runs** (N = 20) to the
  budget derivation and the floor test, giving the append-only corpus a reverse
  gear;
- harvests fresh hosted runs and **re-derives every recipe-derived mode** from the
  now-windowed corpus, re-committing every budget the windowed recipe produces
  differently (the 13 Slice-38 carve-out scenarios stay at their hand budgets —
  see Decision 6);
- collapses the point-geometry-query two-step CI wiring into **one blocking step**
  (correctness + budget), making it the eleventh blocking latency gate;
- updates `AGENTS.md` (`## Gate budgets` documents the window; the CI section and
  the architecture paragraph graduate point-geometry-query from
  "gateable, not yet blocking" to blocking).

Expected implementation surface:

- `.github/scripts/derive-gate-budgets.sh` (windowing in the awk derivation; a
  `--self-test` fixture proving an out-of-window spike is ignored)
- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (windowing at corpus read;
  a synthetic-corpus test proving the same)
- `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` (append-only:
  new harvested rows)
- the recipe-derived benchmark scenario budget tables under
  `Sources/ViewportBenchmarks` that the windowed re-derivation changes
- `.github/workflows/swift-ci.yml` (collapse the two point-geometry-query steps)
- `AGENTS.md`
- `docs/superpowers/verification/2026-07-16-point-geometry-query-gate-and-ratchet-repair.md`

Expected paper trail: this design spec; a task-by-task TDD plan after approval; a
verification record with local + hosted evidence and hosted run IDs; a post-slice
review after implementation and merge.

## Non-Goals

- No `TextEngineCore` changes. No public API change. No `pointGeometryAt` /
  `pointAt` / query-type change.
- No `TextEngineReferenceProviders` changes.
- No benchmark **workload** change: no scenario added/removed, no viewport
  parameter, provider, `lineCount`, or sampler edit. Only recipe-derived **budget
  literals** move, and only where the windowed derivation moves them. Every
  `point_geometry_query` checksum must stay byte-identical to Slice 39's.
- No change to the recipe formula itself (the `8×median` / `3×max` / `2×budget_p95`
  terms are unchanged; only the *sample set* those terms read is windowed).
- No corpus rewrite, row deletion, or `sort -u`: the corpus stays strictly
  append-only. Windowing is a read-time concern only.
- No harvester change (`harvest-gate-corpus.sh` and its idempotent `--corpus`
  dedup are untouched).
- No absolute/product budget (Slice 38 Option C) — the strongest open idea, and
  the natural sequel once the ratchet is repaired, but its own slice.
- No provider-native horizontal `columnIndex` descent (Slice 39 Option C/D).
- No ruleset mutation, required-context rename, docs-only-detector change, WASM
  promotion, or bypass-actor policy change.

## Decisions

### Decision 1 — The window is per-key, over the last N distinct `run_id`s, N = 20

For each key `mode|scenario`, sort its rows by `run_id` numerically, keep the rows
belonging to the **N = 20 most recent distinct `run_id`s**, and compute
`median()`, `max()`, and the `3×max` floor over **only those rows**. A key with
≤ N distinct runs uses all its rows — behavior identical to today.

- **Per-key, not global.** Mode run-counts range 6 → 42 and `realistic_provider`
  appears only in PR runs. A single global "last N runs" window would starve
  newer and PR-only modes of their own recent evidence and trip
  `testEveryGatedScenarioHasCorpusEvidence`. Per-key guarantees every scenario
  always sees up to N of *its own* most recent runs.
- **Sort by `run_id` numerically.** File order is *not* chronological (verified:
  the corpus's rows are not run-id-monotone in file order). `databaseId` is
  globally monotonic, so numeric `run_id` sort is the only correct "last N."
- **N = 20.** The corpus grows ~3–4 runs per slice, so N = 20 ≈ ~5–6 slices of
  history: long enough that `median()` is stable, short enough that a spike clears
  in a bounded number of slices. N = 10 turns the gear faster but makes the median
  noisier; N = 30 is barely distinguishable from "all." N is the one governance
  knob; it is a **named constant duplicated** in the awk script and the Swift test
  (like `floorFactor = 3` today), each cross-referencing the other as must-match.

Rejected — a **global** window (simpler awk/Swift): starves per-mode evidence and
breaks the evidence-existence invariant, per above.

Rejected — **time/date** windowing: the corpus stores no timestamp, only
`run_id`; a run-count window is deterministic and needs no new column.

### Decision 2 — Window both terms and both enforcers, identically

The window applies to **`median()` and `max()`** (not `max` alone) and in **both**
`derive-gate-budgets.sh` (which produces budgets) and `GateFloorTests.swift`
(which enforces the floor).

- Windowing only `max` would fix the lone-spike case but not slow drift, since the
  median term would still read stale samples.
- If the derivation and the floor test windowed differently, they could disagree —
  a budget the script produces could fail the floor the test enforces. They must
  read the identical sample set. This is why N is pinned in both.

### Decision 3 — Landing the window is safe before re-deriving (monotone-floor-lowering)

Because a window is a **subset** of the corpus rows, `max(window) ≤ max(corpus)`
for every key, so introducing the window can only **lower or hold** each
scenario's `3×max` floor — never raise it. Therefore **no currently-passing budget
can be pushed below its floor by adding the window**. The machinery change is safe
to land first; the re-derivation that follows can only *tighten* budgets into the
freshly-lowered floors (that tightening is the ratchet unwinding, and it is what
restores margin to the near-floor cluster). This property is stated because it is
the reason Slice 40 does not risk a red `GateFloorTests` from the window change
itself; any red after the harvest is `budget_stale` (a new sample raised a floor),
diagnosed and re-derived, never chased as an engine regression.

### Decision 4 — Re-derive every recipe-derived mode from the windowed corpus, then re-commit

Per `AGENTS.md`, a harvest re-derives every mode. After appending the fresh
harvested rows, run `derive-gate-budgets.sh <corpus>` (no mode arg → all modes)
and re-commit every recipe-derived budget the **windowed** recipe now produces
differently, so the "derived, never hand-typed" invariant reproduces from the
committed corpus + script. Deriving only `point-geometry-query` would leave the
other recipe-derived modes silently not-reproducing under the new window.

### Decision 5 — Collapse the two point-geometry-query CI steps into one blocking step

Delete the bare `--point-geometry-query` correctness step **and** the
`continue-on-error` on the `--point-geometry-query --gate` step **together**,
leaving a single `--point-geometry-query --gate` step with **no**
`continue-on-error`, blocking on both correctness and budget. The two-step split
existed only to keep correctness blocking while the budget was observational
(Slice 39 Decision 5 / the Slice 16 dead-step trap); once the budget is blocking,
one step is both. Deleting only one half is the trap: keeping the bare step alone
would double-run the mode; keeping `continue-on-error` alone would swallow
correctness failures too.

### Decision 6 — Leave the 13 Slice-38 carve-out scenarios untouched

The 13 hand-budget scenarios (pipeline ×2, structural_mutation ×3,
variable_height_mutation ×3, bulk_structural_mutation ×5) stay at their current
budgets. Windowing only lowers their floors (Decision 3), so they gain margin and
cannot be pushed red; the recipe would still *loosen* them (Slice 38 P3 #1), which
the carve-out exists to prevent. This slice does not recipe-derive them and does
not change their literals.

### Decision 7 — Keep the host job order and the required contexts

The surviving point-geometry-query gate stays where the gated step is today —
after the point-query gate, before the memory-shape diagnostic — keeping all
eleven blocking latency gates contiguous. The three required job contexts
(`Host tests and benchmark gate`, `iOS cross-target compile`,
`WASM cross-target observation`) are unchanged. Docs-only detector, ruleset, and
bypass shape are unchanged; this PR changes workflow YAML and a policy-sensitive
script (`.github/scripts/**`), so it is never docs-only and runs the full heavy
path.

### Decision 8 — Treat a first-run hosted budget miss as evidence, not a thing to hide

If the promotion's hosted PR-head run fails because the (windowed, re-derived)
budget does not fit hosted Linux, **stop** and re-derive from the fresh hosted
evidence in this same PR (the standing rule). Do not restore `continue-on-error`,
add a workflow-only threshold, or hand-widen a budget.

## Implementation Architecture

### Windowing the awk derivation (`derive-gate-budgets.sh`)

The script currently single-passes the corpus, grouping p95/p99 per `key`. Change
it to also record each row's `run_id` per key, then in `END`, for each key:

1. collect the distinct `run_id`s seen for that key, sort them numerically
   descending, and mark the top N as "in window";
2. compute `median()` and `max()` over only the in-window rows.

The printed line already reports `n=` per key; after windowing it reports the
**in-window** count (≤ N), which is the honest sample base the budget rests on. N
is a named constant near the top of the script with a comment pointing at
`GateFloorTests.swift`'s twin.

Add a **`--self-test`** (mirroring `harvest-gate-corpus.sh --self-test`,
`cross-target-compile.sh --self-test`) that feeds a small fixture corpus in which
an ancient run carries a large spike outside a small window and asserts the
derived budget ignores it — the failing-first anchor for the awk change, runnable
with no network and no toolchain.

### Windowing the floor test (`GateFloorTests.swift`)

`loadCorpus()` currently folds `maxP95`/`maxP99` over every row per key. Change it
to first bucket rows by key **with their `run_id`**, then per key keep only rows
from the N largest `run_id`s before folding the extremes. `windowRuns = 20` is a
named constant with a comment pinning it to the shell script's twin. The evidence
and floor assertions are otherwise unchanged: a key present in the corpus is
present in its own window, so `testEveryGatedScenarioHasCorpusEvidence` still holds.

Add a focused test that builds a synthetic in-memory corpus (a key with N+ runs, an
ancient spike, recent calm samples) and asserts the windowed extreme equals the
recent max, not the ancient spike — the failing-first anchor for the Swift change.
(If the current `loadCorpus` only reads from disk, factor the windowing into a pure
function over parsed rows so the test can drive it without a fixture file.)

### Harvest + re-derive

```bash
# append fresh hosted samples (idempotent via --corpus; preview with --dry-run)
./.github/scripts/harvest-gate-corpus.sh --limit 40 \
  --corpus docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
  >> docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv

# re-derive ALL modes from the windowed corpus and re-commit what changed
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
```

### Workflow (collapse to one blocking step)

Delete the bare `Run point geometry query benchmark (correctness; blocking)` step
(a multi-line `run:` that captures output to a temp file) and remove
`continue-on-error: true` from the `Run point geometry query benchmark gate` step,
leaving:

```yaml
- name: Run point geometry query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate
```

positioned after the point-query gate and before the memory-shape diagnostic.

### Documentation (`AGENTS.md`)

- **`## Gate budgets`** — document the trailing window: budgets and the floor are
  derived over the last N = 20 runs per scenario, not the whole corpus; the corpus
  stays append-only (windowing is read-time); this is the reverse gear that
  retires old spikes and closes the Slice 38 P2 #2 deadlock. Update the "corpus is
  append-only" and "3×max floor" prose to reflect that `max`/`median` read the
  window.
- **Architecture paragraph** — the `pointGeometryAt` sentence currently says
  `--point-geometry-query` is "derived-budget gateable" and CI runs it as **two
  steps** (bare-blocking + `continue-on-error` observational). Rewrite to: it is a
  blocking host-job CI gate (the eleventh). Drop the two-step description.
- **CI section** — the `Host tests and benchmark gate` bullet: change the
  point-geometry-query wiring from the two-step description to
  `→ --point-geometry-query --gate (blocking)`; update the blocking-gate count from
  ten to **eleven** and add point-geometry-query to the enumerated blocking gates;
  delete the "Slice 40 promotes the mode by deleting the bare step and the
  `continue-on-error` together" note (now done).
- **Commands** — the `--point-geometry-query --gate` command line stays; drop any
  "not yet blocking in CI" qualifier.

### Verification record

Create
`docs/superpowers/verification/2026-07-16-point-geometry-query-gate-and-ratchet-repair.md`
with exact commands, exit statuses, and representative output. At minimum:

- `derive-gate-budgets.sh --self-test` passes; `swift test` passes (incl. the new
  windowing test and `GateFloorTests` green against the windowed floor).
- Every committed recipe-derived budget **reproduces** from
  `derive-gate-budgets.sh <corpus>` under the window (paste the sweep); the 13
  carve-outs are unchanged and still clear the windowed floor.
- The window demonstrably has a reverse gear: show a scenario whose full-corpus
  `3×max` floor exceeds its windowed `3×max` floor (an aged-out spike), with both
  numbers.
- All eleven latency gates pass locally, including `--point-geometry-query --gate`
  with all four `gate=pass`; the four `point_geometry_query` checksums are
  byte-identical to Slice 39's (proving the workload is unchanged).
- A **workflow-invariant assertion**: exactly one `--point-geometry-query` step;
  it invokes `--point-geometry-query --gate`; it is **not** `continue-on-error`; no
  bare correctness step remains; it carries the sibling `docs_only_pr` guard; it is
  ordered point-query → point-geometry-query → memory-shape; the three required
  contexts are unchanged.
- Foundation-free scans empty for both `Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders`.
- **Hosted**, at **step** level (a green job can hide a dead `continue-on-error`
  step): final PR-head Swift CI run id; all three required jobs `success`; the
  point-geometry-query gate step `gate=pass` ×4 with hosted p95/p99 and per-scenario
  headroom; proof the step is not `continue-on-error`; and the **post-merge push**
  run id on the merge commit as the merged-code anchor (this PR changes YAML +
  scripts, so the merge is not docs-only).

## Acceptance Criteria

1. `derive-gate-budgets.sh` and `GateFloorTests.swift` compute budgets and the
   floor over a per-key trailing window of the last **N = 20** runs (by numeric
   `run_id`), identically; N is a named constant in each, cross-referenced as
   must-match.
2. `derive-gate-budgets.sh --self-test` and a new Swift windowing test both pass,
   each proving an out-of-window spike does not inflate the derived
   budget / enforced floor.
3. The corpus file gains only appended rows (append-only; no deletion, no reorder).
4. Every recipe-derived committed budget reproduces byte-for-byte from
   `derive-gate-budgets.sh <corpus>` under the window; the 13 Slice-38 carve-out
   budgets are unchanged and clear the windowed `3×max` floor on both statistics.
5. `.github/workflows/swift-ci.yml` has exactly **one** `--point-geometry-query`
   step, invoking `--point-geometry-query --gate`, with **no**
   `continue-on-error: true` and no separate bare correctness step; it sits after
   the point-query gate and before the memory-shape diagnostic.
6. The three required job context names are unchanged.
7. No `TextEngineCore` / `TextEngineReferenceProviders` / benchmark **workload**
   change; the four `point_geometry_query` checksums equal Slice 39's; `git diff`
   for the PR touches only the derive script, `GateFloorTests.swift`, the corpus,
   recipe-derived budget tables, `swift-ci.yml`, `AGENTS.md`, and `docs/**`.
8. `AGENTS.md` documents the trailing window in `## Gate budgets`, describes
   `--point-geometry-query` as the eleventh blocking host-job gate, and no longer
   describes the two-step / not-yet-blocking wiring.
9. Local: all eleven latency gates pass, `--point-geometry-query --gate` is
   `gate=pass` ×4, `swift test` green, both Foundation scans empty.
10. Hosted PR-head CI runs the single blocking point-geometry-query gate step and
    succeeds, with recorded Linux per-scenario p95/p99 and headroom; post-merge
    push CI on `main` anchors the merged behavior — both verified at step level.

## Risks And Gaps

### A burst of runs could evict good baselines faster than intended

A slice that harvests many runs at once shifts each key's window forward by that
many runs. At N = 20 the window is several slices wide, and the corpus stays fully
intact for audit, so a burst narrows *which* samples are load-bearing but never
destroys evidence. Acceptable; the alternative (a larger N) slows the reverse gear
the repair exists to provide.

### The gate is genuinely failable — and can therefore flake

`point_geometry_query`'s tightest hosted headroom was ~3.3× p95 on the Slice 39
PR-head run — close to the floor. That is a gate working as designed (a gate that
cannot fail is not a gate), but strict required checks mean a flaking gate blocks
every PR. Windowing *raises* the margin under this cluster (Decision 3), and the
mode's own budget is re-derived from a wider, windowed base in this slice.

### Hosted Linux variance vs the re-derived budgets

The re-derived budgets rest on hosted evidence, and the PR-head run is more hosted
evidence; if it misses, re-derive in-PR (Decision 8), do not hide it.

### N is duplicated across awk and Swift

Like `floorFactor = 3` today, N lives in two languages and cannot be auto-pinned
by the compiler. Mitigation: a named constant on each side with a comment naming
its twin, plus the reproduction check in verification (a mismatch would make some
committed budget fail to reproduce or fail the floor). A future infra slice could
hoist shared calibration constants into one source read by both.

### The regression budgets are still anchored to a moving (now windowed) median

The trailing window gives the corpus a reverse gear but does not add an
*absolute* product budget: legitimate slow drift within the window can still be
re-derived green. Closing that hole is Slice 38 Option C (the absolute/product
budget), which §8 of the Slice 39 review groundworked (every hosted p99 clears a
1 µs product line by 4.0×–6.4×) and which is far safer to add **after** the
ratchet stops pushing budgets upward — i.e. after this slice. It remains the
strongest open roadmap item and its own future slice.

### Standing items

WASM remains observational; the realistic-provider observation remains PR-only
`continue-on-error`; the `Main` ruleset keeps its documented bypass-actor shape.
None change here.

## Recommended Next Step

After this spec is approved, write the Slice 40 implementation plan (TDD). The two
failing-first anchors are (a) the `derive-gate-budgets.sh --self-test` /
`GateFloorTests` windowing tests — red before the window exists, green after — and
(b) the workflow-invariant assertion — a lone blocking `--point-geometry-query
--gate` step exists only after the YAML collapse. Sequence: window the machinery
(safe first, Decision 3) → harvest → re-derive-all + re-commit → collapse CI →
`AGENTS.md` → hosted PR run → post-merge proof.

After Slice 40, the eleven-gate blocking suite is complete and the append-only
ratchet has a reverse gear. The roadmap's strongest remaining idea — the absolute
(product) budget, Slice 38 Option C — becomes the natural next candidate, now that
it can be added over a corpus that no longer drifts monotonically looser.
