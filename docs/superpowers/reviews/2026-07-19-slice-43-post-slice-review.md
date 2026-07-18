# Slice 43 Post-Slice Review

The perf gate gains a **second, distinct axis**. Every prior gate enforces a
median-anchored *regression* band ("slower than recent code?"); Slice 43 adds a
**fixed, never-recalibrated absolute product ceiling** ("still fast enough for a
60 FPS frame?") — 10% of a 60 FPS frame, `GateLimits.absoluteP99Nanoseconds =
1_000_000_000 / 60 / 10 = 1_666_666` ns — checked against observed p99 for
**frame-hot-path** modes only. On breach the gate returns a new reason
`budget_absolute_exceeded`; the response is to fix the code, never loosen the
ceiling. `bulk_structural_mutation` is exempt (a multi-line paste/range-delete is a
discrete, possibly multi-frame action, not a scroll frame) and prints
`budget_absolute_p99_ns=exempt`. Zero `TextEngineCore` /
`TextEngineReferenceProviders` change; zero budget/corpus/workload/CI-workflow
change (all 45 gate checksums byte-identical). Merged as `4a3b83d` (PR #96); AC8
hosted proof recorded in the docs-only follow-up **PR #97** (`8d5bb36`).

This is the Slice 42 review's recommended **Option A** and the spec's own Next
Step, delivered exactly as scoped: the calibration machinery was closed on all
three axes of "both consumers agree" (Slices 41–42), which is the precondition the
spec names for an absolute backstop to *compose* with the median floor rather than
fight a moving median. This review was written after independently re-running the
local verification on the merged tree, re-reading both hosted runs at step level,
and re-reproducing the guard-is-live break→red→revert→green cycle.

## Scope Reviewed

- `Sources/ViewportBenchmarks/BenchmarkOptions.swift` — the
  `BenchmarkMode.isFrameHotPath` classifier (exhaustive `switch`, `false` only for
  `.bulkStructuralMutation`, beside its sibling `isGateable`).
- `Sources/ViewportBenchmarks/BenchmarkModels.swift` — the two `GateLimits`
  constants (`frameNanoseconds`, `absoluteP99Nanoseconds`, expression-form, FIXED),
  the `GateFailureReason.budgetAbsoluteExceeded` case, the mode-gated check inside
  `gateFailureReason`, and the non-optional `headroomAbsoluteP99` property.
- `Sources/ViewportBenchmarks/BenchmarkSupport.swift` — the two additive gate-output
  tokens (`budget_absolute_p99_ns=` + `headroom_absolute_p99=` for frame-hot-path;
  a visible `budget_absolute_p99_ns=exempt` marker for bulk).
- `Tests/ViewportBenchmarksTests/GateLogicTests.swift` — the `mode:`-parameterized
  `summary` helper and the nine new tests (exclusion pin, frame-math pin, fire /
  exempt / precedence / non-masking, and the three output-token tests).
- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` — the `GatedBudget.mode`
  field, the `add` threading, and the standing invariant
  `testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling`.
- `AGENTS.md` — the `## Gate budgets` absolute-ceiling subsection.
- The spec, plan, and verification record for the slice; the AC8 hosted-proof edit
  in PR #97.

Out of review scope, because the slice did not touch them (confirmed by
`git diff --name-only 62500fc 8d5bb36 -- Sources/TextEngineCore
Sources/TextEngineReferenceProviders` → empty, and no budget literal / corpus /
workflow path in the whole-slice stat): `Sources/TextEngineCore`,
`Sources/TextEngineReferenceProviders`, every budget literal under
`Sources/ViewportBenchmarks/`, the corpus, `derive-gate-budgets.sh`, and
`.github/workflows/swift-ci.yml`.

## Product Brief Alignment

The brief's hard constraints hold; the perf story moves from *regression-only* to
*regression + product*.

- **Foundation-free core** — no core file changed; `rg -n Foundation
  Sources/TextEngineCore` is empty (re-run for this review). The new output tokens
  use only stdlib interpolation and the pre-existing `formatHeadroom`; no
  `String(format:)` or Foundation API entered `ViewportBenchmarks`.
- **Swift Embedded / iOS+WASM** — no engine surface touched; both cross-target jobs
  are green on both hosted runs. The whole diff is confined to the benchmark
  executable target and its test target.
- **Zero-dependency** — no package added; the ceiling is two arithmetic constants
  and one mode-gated `if`.
- **Memory / virtualization invariants** — unchanged; not in scope.
- **Perf invariant (the brief's «блокируют merge при деградации» / «60 FPS»)** —
  *advanced*. The regression band answers "slower than recent code?"; it
  structurally re-derives around a legitimate, slow, cumulative drift toward the
  frame boundary. The fixed ceiling is the backstop that a moving median cannot be:
  it turns the brief's «60 FPS» success criterion into a measurable headless budget
  that never recalibrates. No measured latency and no budget number moved — the
  45-checksum byte-identity proves the addition is purely a new *decision* layer
  over unchanged measurements.

## Delivered Design

### One classifier, three consumers, one exempt mode

`BenchmarkMode.isFrameHotPath` is read identically by the runtime check
(`BenchmarkModels.swift` `gateFailureReason`), the output layer
(`BenchmarkSupport.swift` `formatSummary`), and the static floor filter
(`GateFloorTests.swift`). `bulk_structural_mutation` is the sole `false` case in all
three, so a bulk row is exempt at runtime, marked `exempt` in output, and excluded
from the floor invariant — coherently, in one place. The switch is **exhaustive, not
a deny-list** (the same discipline as `isGateable`): a future mode must classify
itself or fail to compile, and `testFrameHotPathExclusionsAreExactlyDocumented` pins
the exempt set to exactly `{bulk_structural_mutation}`.

### Precedence is the whole trick

The check is one mode-gated line placed **after** `budgetExceeded` and **before**
`budgetStale`: `missingBudget → operationFailures → budgetExceeded →
budgetAbsoluteExceeded → budgetStale`. That ordering is load-bearing and correct:
- `budgetExceeded` outranks it, so code that broke even the (looser, re-derived)
  regression budget reports the familiar regression reason.
- It outranks `budgetStale`, but it can never *mask* staleness: staleness needs a
  tiny observed (huge headroom), where the absolute check — which only fires on
  observed p99 **>** the ceiling — is silent. The two conditions are mutually
  exclusive. `testAbsoluteCeilingDoesNotMaskStaleBudget` pins it.

The net effect: `budgetAbsoluteExceeded` fires **only** when the regression budget
passes but the frame is blown — precisely the drift a median-anchored budget
re-derives around.

### The runtime gate and the static floor are complementary, not redundant

The runtime check guards observed p99 crossing the ceiling; the standing invariant
`testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling` guards every frame-hot-path
*budget* staying under it. Together they make it impossible to *commit* a state
where the absolute gate would redden a clean tree: a regression budget is `≥` its
own observed latency, so `budget < ceiling ⇒ observed < ceiling` with room. This is
the static half the runtime gate structurally cannot see — the same
floor-vs-runtime split that governs the regression band.

### Loose-by-design, and honest about it

Even the slowest frame-hot-path op (`structural_mutation|1m`, hosted p99 ≈ 37,821
ns) sits ~44× under the ceiling; the fast queries sit thousands of times under it.
The absolute gate therefore effectively never bites for *today's* operations — its
value is latent, a coarse backstop against future cumulative drift, not a
fine-grained per-scenario regression guard (which the regression band already is).
The spec states this intentionally (Decision 2), and the `budget_absolute_p99_ns=`
token makes the ceiling and its headroom visible on every gated row so the latency
budget it enforces is never a silent implicit.

### Guard-is-live, independently reproduced

A gate that cannot fail protects nothing. I reproduced the break independently for
this review on the merged tree (not trusting the recorded transcript): lowering the
ceiling to `frameNanoseconds / 1000` (16,666 ns) via a `.bak`-backed `sed` edit
turns `--structural-mutation --gate` **red on exactly the `1m` scenario** with
`gate=fail reason=budget_absolute_exceeded` (its observed p99 ≈ 27 µs exceeds the
lowered ceiling) while the faster `1k`/`100k` rows stay green; reverting from `.bak`
restores all three to `gate=pass` and leaves the tree byte-clean (the break never
touched git). The unit test `testAbsoluteCeilingFiresForFrameHotPathMode` pins the
same fire path with a regression budget that genuinely passes, so the test proves
the *new* behavior and not a `budgetExceeded` it would already catch.

## Verification Evidence Reviewed

### Fresh local checks on the merged tree (`main` @ `8d5bb36`)

| Check | Result |
|---|---|
| `swift test` | **310 tests, 0 failures** (incl. all 9 new gate-logic + the floor invariant) |
| `swift build -c release` | clean |
| `rg -n Foundation Sources/TextEngineCore` | empty |
| whole-slice engine/provider diff (`62500fc..8d5bb36`) | zero `TextEngineCore` / `TextEngineReferenceProviders` paths |
| whole-slice changed set | only `ViewportBenchmarks/*.swift` (3), the two gate test files, `AGENTS.md`, and slice docs |
| `--structural-mutation --gate` (real ceiling) | 3 × `gate=pass` |
| guard-is-live (ceiling `/1000` → red → revert → green) | reproduced independently; RED on `1m` only, clean revert, back to 3 × `gate=pass` |
| all 45 gate checksums | byte-identical to the Slice 42 baseline (recorded in the verification doc, re-confirmed by the hosted tally) |

### Hosted runs (verified at step level, not job conclusion)

Read at step level per the standing rule — a `continue-on-error` step can conclude a
job green while its own step failed.

- **PR-head run `29660672085`** (head `da4c52a`): three required jobs `success`; all
  eleven blocking gate **steps** `success`; whole-run tally **45 `gate=pass`, 0
  `gate=fail`**, **0** `reason=budget_absolute_exceeded`; **40** rows carry
  `budget_absolute_p99_ns=1666666` and **5** carry `=exempt`; host tests **310/0**.
  `Observe realistic provider relative performance` **ran** (PR event,
  `continue-on-error`); `Complete docs-only PR` **skipped** (the branch touches Swift
  → heavy path ran). Tightest **absolute** headroom **44.4×** (`structural_mutation|1m`).
- **Post-merge `push` run `29661132399`** (merge commit `4a3b83d`): run `success`;
  three required jobs `success`; all eleven gate steps `success`; identical tally
  **45 `gate=pass`, 0 `gate=fail`**, 40 × `1666666` + 5 × `exempt`, host tests
  **310/0**. `Observe realistic provider relative performance` correctly **skipped**
  (a `push` event skips `if: pull_request`), matching the Slices 24–42 pattern of
  anchoring proof in the merged-code `push` run. Tightest absolute headroom **44.1×**
  (`structural_mutation|1m`, hosted p99 ≈ 37,821 ns). The four `point_geometry_query`
  checksums are byte-identical to the PR-head run, the local runs, and the Slice
  40/41/42 baseline.
- **Hosted-proof PR `#97`** (docs-only, merge `8d5bb36`): the AC8 record in the
  verification doc, correcting the "Hosted CI — Pending" placeholder with both run
  IDs and the step-level tallies above.

The ~44× tightest absolute headroom is an order of magnitude above the ~2.7× hosted
run-to-run spread, so — consistent with the floor invariant — the absolute gate
cannot redden a clean tree from runner noise. It is even looser than the spec's ~28×
estimate.

## Git History

Seven implementation commits on top of three pre-committed design/plan docs, cleanly
separated by concern and following the slice lifecycle: `173b1f4` (feat:
`isFrameHotPath` classifier) → `a77747e` (feat: `GateLimits` frame + absolute p99
constants) → `4dc9c87` (feat: fail gate on frame-hot-path absolute p99 breach) →
`7d1c9dd` (feat: emit absolute-ceiling gate tokens) → `f6b710e` (test: pin every
frame-hot-path budget under the ceiling) → `987568d` (docs: AGENTS.md) → `da4c52a`
(docs: local verification). Conventional-commit prefixes are correct and the
`feat`/`test`/`docs` split matches the work (TDD: each `feat`/`test` commit pairs its
tests with its code). The AC8 hosted proof lives in PR #97 (`1fa1f3c`), matching the
Slices 24–42 pattern of anchoring proof in the merged-code `push` run rather than the
PR-head run alone.

## Code Review Findings

### P0 / Release Blockers

**None.** The slice is merged; all eleven gates are green on the merged commit at
step level; both hard constraints hold (Foundation-free, zero engine/provider diff);
the 45 checksums are byte-identical; and the new gate is demonstrably live and
demonstrably unable to redden a clean tree (floor invariant + ~44× hosted headroom).

### P1 / Must Fix Before Merge

**None.** The new tests assert real behavior (the exclusion pin asserts an exact
set; the floor invariant carries its non-vacuity guard; each precedence relationship
is isolated in its own test); the guard-is-live break was reproduced independently;
and the two hard constraints and the 45-checksum byte-identity are re-verified.

### P2 / Production Readiness

**P2 #1 — Bulk-edit latency has no absolute backstop (deliberate residual,
recorded).** `bulk_structural_mutation` is exempt from the ceiling (Decision 2), so
*slow drift in bulk-edit latency* is caught only by its median-anchored regression
budget — the very blind spot this slice closes for the frame path, left open for
bulk. This is the correct *scope* (a multi-line paste is not a scroll frame), but it
is a real, recorded gap: if the product later needs a bulk-edit latency guarantee it
wants its own absolute budget anchored to a bulk-appropriate target (e.g. "a
4096-line paste in ≤ N frames"), not the 60 FPS scroll frame. The spec records this
under Risks; carried, not closed.

**P2 #2 — Carried from Slice 42: the derivation *arithmetic* residual is
untouched.** A *within-band-looser* regression-arithmetic drift (`8×median`,
`3×max`, `round_up_2sf`) is still caught only by the manual per-slice
"reproduce-every-literal" check — the loose-side analog Slice 42 closed for
`window_run_ids` selection. This slice adds a *product* axis; it explicitly does not
close the *regression-recipe* residual (spec, "Arithmetic residual carried from
Slice 42"). Still the strongest tooling-completion candidate.

**P2 #3 — Carried from Slice 42: harvester provenance gap.**
`harvest-gate-corpus.sh` still selects rows by run id alone (no
`conclusion`/`event`/fork check), so a fork PR could in principle inject fabricated
`p95_ns=` lines into a future harvest. Untouched by this slice; a security-shaped
roadmap item.

**P2 #4 — Carried from Slice 41/42: p95 thin axis / `point_geometry_query` thin
evidence.** Under the trailing window, the sub-µs `line`/`column`/`point` cluster
sits closest to the starvation floor and is where a hosted `budget_stale` would
surface first. This slice touches none of it and moves no budget; monitor p95 and
re-derive on any hosted `budget_stale`.

### P3 / Minor But Valid

**P3 #1 — Measured value `580 µs / 2.87×` embedded in two source comments + a doc
(`measured-values-in-comments-rot`).** `BenchmarkModels.swift` (`gateFailureReason`
comment: "every regression p99 budget is ≤ 580us"), `GateFloorTests.swift` (the
invariant's comment: "structural_mutation|1m (580us, 2.87x under)"), and `AGENTS.md`
each quote the current `structural_mutation|1m` p99 budget (`580_000`) and its
derived `2.87×`. Both figures are falsified by the next re-derivation that raises
that budget (while staying under the ceiling) — the exact
[[measured-values-in-comments-rot]] anti-pattern. **Mitigating:** the number is
accurate today, is only illustrating the tightest scenario, was mandated verbatim by
the approved plan, and all three sites explicitly cite `GateFloorTests` as the
*enforcing* mechanism (the load-bearing claim does not depend on the exact number).
**The user consciously chose "ship as-is"** at the whole-branch review, honoring the
plan text. Recorded here as the standing-lesson instance it is; the cheapest honest
softening (keep the structural claim, drop the frozen number) is a clean
opportunistic fold for any future slice that touches these files.

**P3 #2 — `AGENTS.md` "The two failure reasons are opposite instructions" now
undercounts.** A third reason (`budget_absolute_exceeded`, with its own instruction
"fix the code, never loosen the ceiling") was added in the new subsection, but that
pre-existing paragraph still says "two" and lists only `budget_exceeded` /
`budget_stale`. Not a contradiction (the statement is true for those two, and the
third reason is fully documented in its own subsection), but a reader landing there
alone would read the taxonomy as complete. A one-clause fix; out of this slice's
scope (Task 6 added a subsection, it did not edit that paragraph).

**P3 #3 — `isFrameHotPath` returns `true` for the non-gateable `rangeOnly` /
`memoryShape` / `memoryObservation` modes (inert observation, not a defect).**
Semantically these are not "frame-hot-path" operations, so `true` reads slightly
oddly, but it is inert in all three consumers: `gateFailureReason` returns
`.missingBudget` for them before the check (no budgets); the `formatSummary` gate
block only runs under `--gate` (rejected for these modes); the floor filter only
iterates gateable modes. The invariant that actually governs — *among gateable
modes, only bulk is exempt* — is correct and pinned. Matches the plan's exhaustive
switch. No action.

**P3 #4 — Plan checkboxes left unchecked.** Every step in the committed plan is
`- [ ]` though the work shipped; the commit messages are the completion evidence.
Cosmetic paper-trail nit, recurring across slices.

**P3 #5 — Carried from Slice 41/42: `WorkflowShapeTests` comment cites
`swift-ci.yml` by line range** — a pointer that drifts if that YAML is edited above
it. Correctly out of scope (this slice does not touch `WorkflowShapeTests.swift`).

## Risks And Gaps

- **Bulk-edit absolute backstop (P2 #1)** — the frame path is guarded; bulk is not,
  by deliberate scope. The natural product successor if a bulk-edit latency
  guarantee is ever needed.
- **Arithmetic residual (P2 #2)** — the loose-side regression-recipe analog; still
  manual-only. The natural tooling successor.
- **Harvester provenance (P2 #3)** — run-id-only selection; injection-shaped roadmap
  item.
- **p95 thin axis / point-geometry thin evidence (P2 #4)** — re-derive on any hosted
  `budget_stale`; watch the sub-µs cluster.
- **Absolute gate is latent today** — ~44× headroom means it does not bite for
  current ops; its value is against *future* drift. Intentional (Decision 2), but it
  means the axis is presently unexercised in production save by its own tests.
- **Standing items unchanged** — WASM observational; realistic-provider observation
  PR-only `continue-on-error`; the `Main` ruleset keeps its documented bypass-actor
  shape.

## Lessons For The Next Slice

- **A fixed budget composes only after the moving one is pinned.** The reason an
  absolute ceiling lands cleanly now — rather than fighting a re-derived median — is
  that Slices 41–42 first stopped the upward ratchet and pinned the windowing on all
  three "both consumers agree" axes. Sequencing the product backstop *after* the
  calibration hardening is what let it be a pure additive decision layer (45
  checksums byte-identical) instead of a budget renegotiation.
- **Complementary static + runtime guards beat either alone.** The runtime check
  (observed vs ceiling) is blind to a budget sitting too close to the ceiling; the
  floor invariant (budget vs ceiling) is blind to a live regression. Shipping both
  is what makes "the absolute gate can never redden a clean tree" a *committed*
  property, not a hope — the same lesson the regression band's floor-vs-runtime
  split already taught.
- **Re-run the guard, don't quote it.** As in Slice 42, the guard-is-live claim is
  load-bearing (a gate that can't fail is not a gate); this review re-reproduced the
  break→red→revert→green cycle on the merged tree rather than trusting the recorded
  transcript. Prefer re-execution for any load-bearing claim.
- **Exhaustive switch over deny-list, again.** Both `isGateable` and now
  `isFrameHotPath` force a new mode to classify itself. The P3 #3 "true for
  non-gateable modes" oddity is the small price of that discipline — and it is inert
  — which is the right trade against a mode silently escaping (or inheriting) the
  ceiling.

## Slice 44 Candidate Options

### Option A: the arithmetic "reproduce every committed literal" standing test — recommended

The tooling-completion analog of Slice 42, and the last open within-band residual in
the *regression* recipe (Slice 42 P2 #1, carried here as P2 #2). A standing test
re-derives every budget from the windowed corpus and asserts byte-equality with the
committed literals, closing the within-band-looser *arithmetic* drift the same way
Slice 42 closed the *selection* one. It directly completes the "keep budgets honest"
machinery, is small and infra-flavored, and finishes the thesis Slices 41–42 began —
now that the product axis (Slice 43) is also in place, the calibration story is the
only remaining incomplete one.

### Option B: bulk-edit absolute budget anchored to a bulk-appropriate target (P2 #1)

Give `bulk_structural_mutation` its own absolute ceiling ("a 4096-line paste in ≤ N
frames"), closing the deliberate residual this slice records. Advances the *product*
story a second step; needs a product decision on the target (N frames for a bulk
edit) before it can be a fixed constant.

### Option C: harvester provenance hardening (P2 #3)

Filter harvested runs by `conclusion=success` / non-fork / expected event, closing
the injection gap. Security-shaped; small.

### Option D: generalize `WorkflowShapeTests` to every gated mode

Add a `flagName` mapping + a named-and-justified exemption set + a test pinning the
two together, so all eleven gate steps are shape-pinned, not just point-geometry
(folds P3 #5). Standing infra.

## Recommended Slice 44 Selection

**Option A — the arithmetic "reproduce every committed literal" standing test.**
With Slice 43 landing the product axis, the calibration machinery is the only story
left partly manual: Slices 41–42 pinned the window's constant, its Swift selection,
and its shell selection, but the *derivation arithmetic itself*
(`8×median`/`3×max`/`round_up_2sf`) is still guarded against within-band-looser drift
only by a human re-deriving each slice. A standing test that reproduces every
committed budget literal from the windowed corpus closes that last residual and makes
"every budget is derived, never hand-typed" a build-enforced invariant rather than a
discipline. **Option B** (a bulk-edit absolute budget) is the strongest *product*
alternative and the direct completion of this slice's own recorded residual; prefer
it if the user would rather advance the product budget than finish hardening the
tooling — but it needs a product target decided first. Fold the trivial P3 #1
(soften the frozen `580 µs` figures), P3 #2 (the "two failure reasons" clause), P3 #4
(plan checkboxes), and P3 #5 (comment anchor) opportunistically if Slice 44 touches
those files.

## Slice 43 Review Conclusion

Slice 43 does exactly what the Slice 42 review and the spec asked for, with no scope
creep: a fixed absolute product ceiling now backstops the frame-hot-path query and
recompute surface, catching the one thing a median-anchored regression budget
structurally cannot — a legitimate, slow, re-derived-around drift toward the 60 FPS
frame. One classifier drives the runtime check, the output tokens, and a standing
floor invariant coherently, with bulk exempt in all three; the precedence is correct
and non-masking; and the two guards together make "the absolute gate can never redden
a clean tree" a committed property (re-confirmed by ~44× hosted headroom and the
floor test). No core, provider, budget, corpus, or workflow byte moved (all 45
checksums byte-identical); the merged commit is green across all eleven blocking
gates at step level on both the PR-head and post-merge push runs, with host tests
310/0 and the new absolute-ceiling tokens live on hosted Linux (40 × `1666666` + 5 ×
`exempt`). The guard-is-live break was re-reproduced for this review. No P0, no P1.
The substantive carry-forwards are the deliberate bulk-edit residual (P2 #1) and the
standing Slice 41/42 items (arithmetic residual, harvester provenance, p95 thin
axis). **READY — merged and verified; Slice 44 = the arithmetic "reproduce every
literal" standing test (Option A), or a bulk-edit absolute budget (Option B) to
advance the product story.**
