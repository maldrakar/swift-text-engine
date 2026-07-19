# Slice 45 — Realistic-provider CI-gate promotion (12th blocking gate)

## Summary

Promote the realistic 100k-line / 10 MB viewport-compute benchmark
(`--realistic-provider`, scenario `100k_lines_10mb_text`) to a **merge-blocking
regression gate** — the **12th** blocking gate — by wiring
`swift run … ViewportBenchmarks -- --realistic-provider --gate` into CI as a
standard blocking step, and **removing** today's PR-only, `continue-on-error`,
base-vs-head *relative observation* of the same workload.

This is a **zero-engine-behavior-change** slice: `runRealisticProviderBenchmarks(enforceGate:)`
(`Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`) already honours
`--gate` and exits non-zero on a budget miss. The engine surface, budgets, corpus,
and derivation scripts are untouched. The work is CI wiring, one standing-guard
extension, docs, deleting the now-orphaned observation script, and one comment-only
fix in `RealisticProviderBenchmark.swift` (a narrative that goes false the moment
the gate runs — see §5) — the same "observation → Nth blocking gate" shape as
Slices 24/26/28/32/34/36/38/40.

It is also a deliberate **trade, not pure gap-closing**: promotion buys
merge-blocking enforcement against gross realistic regressions but retires the
observational base-vs-head detector's sensitivity to *small* ones (Decision 1).

## Motivation — brief alignment

The product brief's success criteria include, verbatim:

- **#1:** «Стабильный scroll performance на документах 100k+ строк / >10 MB.»
- **last:** «Регрессионные бенчмарки блокируют merge при деградации производительности.»
- and «превратить "60 FPS" в измеримый headless budget … p95/p99 latency для
  пересчёта viewport».

The intersection of #1 and the last criterion — *a merge-blocking regression gate
on the actual 100k/10MB workload* — is exactly what is missing today. Of the 12
gateable `BenchmarkMode`s, **11 synthetic/uniform ones already block merge; the one
realistic workload that matches the brief's headline goal is the sole exception.**
AGENTS.md states this outright: "`--realistic-provider` is the one gated mode CI
never runs with `--gate`." This slice closes that gap, making the realistic scroll
budget the truest realization of «превратить 60 FPS в измеримый budget» — enforced
on the realistic workload rather than a synthetic proxy, and (being frame-hot-path)
also held under the fixed 1.67 ms 60-FPS absolute ceiling.

## Relation to the Slice 44 recommendation

The Slice 44 post-slice review recommended, in order, **Option A — harvester
provenance hardening** ("the root-of-trust gap under the entire pinned chain …
needs no external decision") and **Option B — a bulk-edit absolute budget**. This
slice is **neither**: it is a deliberate pivot to the realistic-gate promotion,
chosen because it is the single most brief-aligned gate available (criterion #1 ×
the last criterion — see Motivation), a known standing gap, and — like Option A —
decision-free.

The pivot has one honest cost worth stating: promotion makes the realistic budget
**merge-blocking**, and its calibration provenance is the **thinnest** of the twelve
(its corpus rows have only ever arrived via shape 2 — see Risks). Critically, this
does **not** introduce a new *class* of risk: the other eleven budgets already block
merge on the *same* unguarded provenance, so promotion extends an already-accepted
systemic exposure to one more mode rather than creating a new one. It does, however,
**raise the stakes** on that exposure — a bad corpus row can now redden the headline
workload. Provenance hardening (Slice 44 Option A) therefore remains the recommended
**immediate follow-on**, now covering **12** blocking budgets instead of 11; it is
the natural next slice, not superseded by this one.

## Background — current state

The realistic benchmark (`RealisticProviderBenchmark.swift`) builds a 100 000-line
× 112-byte (≈ 11.2 MB) document and times `ViewportVirtualizer.compute` over it
across a deterministic scroll sequence — the brief's exact scroll workload. It is:

- **`isGateable == true`** (`BenchmarkOptions.swift:68`) — it can be gated, and
  `runRealisticProviderBenchmarks(enforceGate:)` already implements the gate.
- **`isFrameHotPath == true`** (`BenchmarkOptions.swift:107`) — the fixed absolute
  60-FPS ceiling (`GateLimits.absoluteP99Nanoseconds = 1_666_666`) applies to it.
- Already carries committed, corpus-derived budgets (**p95 = 97 000 ns,
  p99 = 200 000 ns**), enforced by `GateFloorTests` (3× floor + byte-reproduction).

Yet the **only** CI step touching it (`swift-ci.yml:142`) is
`Observe realistic provider relative performance`: **PR-only**
(`github.event_name == 'pull_request'`), **`continue-on-error: true`** (swallows
every non-zero exit — the Slice 16 dead-step shape), and a **relative** base-vs-head
comparison (`head ≤ 1.221556 × base`) run via
`.github/scripts/realistic-relative-observation.sh`, **not** `--realistic-provider
--gate`. It is also this mode's current corpus source, via the
`mode=realistic_relative_observation` line the harvester reads as "shape 2".

**Local confirmation (macOS, this slice):** `--realistic-provider --gate` already
passes with wide margin — `p95_ns=5299 p99_ns=5663`, `headroom_p95=18.3x
headroom_p99=35.3x`, `headroom_absolute_p99=294.3x`, `gate=pass`. Hosted Linux runs
~2–3× slower, landing comfortably in-band there too.

## Design decisions

### Decision 1 — Replace, don't keep both (the "Option 1" call)

The new blocking `--realistic-provider --gate` step **replaces** the relative
observation step. Realistic then behaves like every other gate: one step, one
`mode=realistic_provider … p95_ns=…` summary line (harvester "shape 1"), runs on
**PR and push** (today it runs on neither as a gate, and never on push at all),
builds **one** tree (head) instead of two (base+head worktrees — cheaper), and
feeds the corpus through the standard path.

Rejected alternative — keep both: if the gate step (shape 1) and the observation
step (shape 2) both run on a PR, a single run contributes 1 + 8 rows for the same
`realistic_provider|100k_lines_10mb_text` key, **double-weighting** it in
`median()`/`max()` — the exact "exactly one CI step may print a mode's summary
lines" hazard AGENTS.md warns about. Keeping both would also require teaching the
harvester to de-duplicate the two shapes — extra scope and moving parts.

Rejected alternative — keep the gate **and** a redirected-off-log observation: the
double-count above exists only because the observation prints its
`mode=realistic_relative_observation` line to the *log*; redirecting that line to a
temp file (as the raw benchmark output already is) would let both coexist without
double-weighting. Rejected anyway — the observation is `continue-on-error`, so it
blocks nothing: a toothless detector on the headline workload is low value and costs
a second (base) tree build every PR. If small-realistic-regression sensitivity is
ever wanted, the right answer is a *blocking* relative gate or a tighter
mode-specific regression budget, not a resurrected observation (see Risks).

**Accepted trade-off:** we lose the sensitive `1.22×` base-vs-head detector, which
could catch sub-8× realistic regressions the coarser absolute budget cannot. That
detector was deliberately *observational and noisy* (hence `continue-on-error`),
never blocked a merge, and its reliable replacement — the absolute gate over the
windowed corpus — is the sanctioned mechanism the other 11 gates already trust. We
also lose the PR-time environment diagnostics that step printed (runner image, CPU,
OS); minor, and unrelated to the gate.

### Decision 2 — Delete the orphaned script (scope decision A)

After removing its only caller, `.github/scripts/realistic-relative-observation.sh`
is fully dead — no Swift test invokes it (confirmed: its only non-historical
references are the CI step being removed and AGENTS.md prose). Deleting it is the
honest completion of "replace" and keeps the tree tidy. `.github/scripts/**` is a
policy-sensitive path, so this diff is (correctly) not docs-only and runs the full CI.

### Decision 3 — Guard-scaffolding depth (scope decision B)

Recommended scope: **(1)** the CI step swap, **(2)** extend `WorkflowShapeTests` to
pin the new gate step, **(3)** AGENTS.md updates, **(4)** delete the dead script.

- **Skip** a bespoke realistic checksum-stability test: unlike the point-geometry
  gate (whose checksum *fold* was the novel thing under test), the realistic
  checksum is already computed today and simply starts appearing in the hosted log
  once the gate step runs; a dedicated byte-identity test is low marginal value here.
- **Skip** a new options-parsing test: the mode was always `isGateable`; no option
  logic changes.

### Decision 4 — No budget re-derivation, no re-harvest

The committed budget (p95 97 µs / p99 200 µs) is corpus-derived, already
`GateFloorTests`-enforced (3× floor + `testEveryCommittedBudgetReproducesFromCorpus`
byte-reproduction), passes with ~8× regression headroom hosted, and sits 8× under
the absolute ceiling. Nothing to re-derive to go green. The first post-merge harvest
that ingests this slice's push run will pick up realistic via the standard shape-1
line like every other mode — expected steady-state, not this slice's work.

**Transitional window wrinkle (benign):** each realistic run used to contribute
**8** corpus rows (shape 2: base+head arrays) and will now contribute **1** (shape
1: head only), so for the ~20 runs it takes the N=20 window to roll over, the window
mixes both shapes and over-weights the older shape-2 rows in `median()`. Same
benchmark, comparable magnitudes, so no budget move is expected; and if a
`budget_stale` ever does surface during the transition it is a re-derive, **not** an
engine regression (the reason string names itself).

## Change set

### 1. `.github/workflows/swift-ci.yml`
- **Add** step `Run realistic provider benchmark gate`:
  `swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks
  -- --realistic-provider --gate`, with the docs-only guard
  (`steps.change-scope.outputs.docs_only_pr != 'true'`), **not** `continue-on-error`,
  positioned immediately after the `--point-geometry-query --gate` step and before
  `Run memory shape diagnostic` (all **12 gates contiguous**, ahead of the diagnostics).
- **Remove** the `Observe realistic provider relative performance` step and its
  `REALISTIC_RELATIVE_OBSERVATION_THRESHOLD` / `BASE_SHA` / `HEAD_SHA` env.

### 2. `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`
- Pin the new gate step with the **same six invariants** that protect point-geometry
  (exactly-one-step, exact-command equality, not-`continue-on-error`, docs-only
  guard, correct name, contiguous position). Implement by lightly generalizing the
  six tests to iterate a **two-entry table** `{point-geometry, realistic}` of
  `(flag, stepName, command, afterStepName, beforeStepName)` rather than copy-pasting
  ~120 lines. The position invariant now pins the full tail order
  `point-query < point-geometry < realistic < memory-shape`.
- This stops **short** of the review's Option D (a full `BenchmarkMode → flag`
  mapping + exhaustive exemption registry); the remaining reason not to generalize
  fully is that the `pipeline` default mode has no flag and there is still no
  flag-mapping — but `realistic` is no longer an exception.
- Update the two now-**false** comments: the header note claiming realistic "is
  deliberately never run with `--gate`" (lines ~16–27), and the parser example
  citing the realistic-observation step's prose comment (lines ~97–102), whose
  referent is being deleted.

### 3. `.github/scripts/realistic-relative-observation.sh`
- **Delete** (Decision 2).

### 4. `AGENTS.md`
- `## Commands`: add `--realistic-provider --gate` to the gate command list.
- `## CI`: eleven → **twelve** blocking gates; add the new step to the ordered list;
  remove the "realistic relative observation (PR-only, continue-on-error)" line.
- `## Gate budgets`: rewrite the paragraph stating `--realistic-provider` "is the
  one gated mode CI never runs with `--gate`" — it now runs with `--gate` like every
  other mode and reaches the corpus through the standard shape-1 line; note the
  historical shape-2 corpus rows remain (append-only) and the harvester's shape-2
  branch is now vestigial (follow-up cleanup, out of scope here).
- `## Package layout`: `WorkflowShapeTests` now pins point-geometry **and** realistic.

### 5. `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- **Comment-only fix.** The 8-line note above `realisticProviderScenarios()`
  (lines ~88–95) narrates the *old* corpus route: "the one gated mode CI never runs
  with `--gate` … no `p95_ns=` line for this mode ever reaches the hosted log … values
  ride inside the `mode=realistic_relative_observation` line instead." All of that
  goes **false** the moment this slice merges — the gate now runs with `--gate`, a
  `p95_ns=` line reaches the log, and shape 2 is gone. Rewrite it to describe the
  standard shape-1 route every other gate uses. This is the same comment-rot hazard
  the repo has burned on before; no code, budget, or behavior changes — only the
  comment. (This is why the slice is "zero-engine-behavior-change," not "zero-Swift-file-change.")

## Acceptance criteria

- **AC1** — CI runs `--realistic-provider --gate` as a blocking, non-`continue-on-error`
  step carrying the docs-only guard, on both PR and push.
- **AC2** — The relative-observation step is gone from `swift-ci.yml`; the script
  file is deleted; no live reference to either remains outside historical docs.
- **AC3** — All 12 gates are contiguous and ahead of the diagnostics
  (`… point-query < point-geometry < realistic < memory-shape …`).
- **AC4** — `WorkflowShapeTests` pins the new gate's shape (all six invariants) and
  is demonstrably **live** (break → red → revert → green re-reproduced on the tree).
- **AC5** — `swift test` green (extended `WorkflowShapeTests`); `swift build -c
  release` clean; `rg -n Foundation Sources/TextEngineCore` empty.
- **AC6** — Local `--realistic-provider --gate` prints `gate=pass` with the absolute
  ceiling line present (`budget_absolute_p99_ns=1666666`); no budget/corpus/derive-script
  byte changed and no engine behavior changed (diff confined to `swift-ci.yml`,
  `WorkflowShapeTests.swift`, `AGENTS.md`, the comment-only `RealisticProviderBenchmark.swift`
  edit, the deleted observation script, and the three slice docs).
- **AC7** — Hosted proof, read at **step level** (per the dead-step-trap rule):
  three required jobs green; **12** blocking gate steps present and passing on both
  the PR-head run and the post-merge **push** run; the realistic gate prints
  `gate=pass`; host tests green. Anchored in the post-merge push run.

## Non-goals / out of scope

- **Harvester shape-2 cleanup.** The `mode=realistic_relative_observation` branch in
  `harvest-gate-corpus.sh` is not vestigial *immediately*: while pre-slice-45 run logs
  remain in GitHub's retention window it is still needed to harvest them correctly
  (their logs carry only the shape-2 line). It becomes truly dead only after those
  logs age out. Removing it — and softening its now-partially-stale comment — is
  separate, riskier scope: a follow-up P3.
- **Full `WorkflowShapeTests` generalization (Option D).** A `BenchmarkMode → flag`
  map + exhaustive exemption registry is a design of its own.
- **Budget re-derivation / re-harvest.** Not needed (Decision 4).
- **Any engine, provider, or `derive-gate-budgets.sh` change.**

## Verification plan

1. `swift build -c release` — clean.
2. `swift test` — green, including the extended `WorkflowShapeTests`.
3. `swift run -c release ViewportBenchmarks -- --realistic-provider --gate` —
   `gate=pass`, absolute-ceiling line present.
4. `rg -n Foundation Sources/TextEngineCore` — empty (exit 1).
5. `WorkflowShapeTests` liveness: break the new step (e.g. add `|| true`, or
   `continue-on-error: true`) → red naming the step → revert → green; tree left
   byte-clean.
6. Confirm the whole diff is confined to the expected paths (no engine/provider/
   budget/corpus/derive-script byte moved).
7. Hosted: PR-head run + post-merge push run, read at **step level**; record run IDs,
   job conclusions, the 12 gate steps, and the realistic `gate=pass` line in the
   verification record. Anchor the proof in the push run.

## Risks & trade-offs

- **Loss of the sensitive relative detector** (Decision 1) — accepted; it was
  observational/noisy and never blocking. If a bulk/realistic small-regression
  guarantee is ever wanted, that is a future *product* slice, not this one.
- **Cross-runner absolute budget vs same-runner relative** — the absolute gate
  trusts the corpus-derived budget across runners; the 11 existing absolute gates
  prove that works, and the realistic budget passes hosted with ~8× headroom. The
  windowed corpus + 3× floor absorb runner noise.
- **Thin realistic calibration history** — this mode's corpus rows historically came
  only via shape 2; `GateFloorTests` already enforces the floor and reproduction, so
  the budget is honest today. This thinness is a *historical* artifact that
  **self-heals going forward**: after this slice every new realistic row arrives via
  the standard shape-1 line — identical provenance to the other eleven gates — so the
  exposure is not a permanent asymmetry, it dilutes as shape-1 rows accumulate.
  Monitor for a hosted `budget_stale` and re-derive if one ever surfaces (it would
  name itself precisely).

## Next step

On approval, invoke the writing-plans skill to produce a task-by-task TDD plan
(`docs/superpowers/plans/2026-07-19-realistic-provider-ci-gate-promotion.md`).
