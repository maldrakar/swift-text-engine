# Slice 41 Post-Slice Review

The `3× max` gate-budget floor repaired from a one-way ratchet into a **two-way**
floor, by deriving `median`/`max` over a trailing window of the most-recent
**N=20 distinct hosted runs** (keyed on the integer run id) instead of all corpus
history. The window is applied **identically** in both corpus consumers
(`derive-gate-budgets.sh` in awk, `GateFloorTests` in Swift) and pinned to one
documented N by a cross-language test. Zero `TextEngineCore`/
`TextEngineReferenceProviders` change; zero measured-workload change (all eleven
gate checksums byte-identical). Merged as `fe02899` (PR #90); AC1/AC8 discharged
by the docs-only hosted-proof follow-up **PR #91** (`0471ce7`).

This is the ratchet repair the Slice 39 and Slice 40 reviews both asked for, and
delivered as the Slice 40 review's recommended **Option A** — scoped to the
*lightest* lever (a trailing window alone; no outlier rejection, no curation
policy). This review was written after independently re-running the local
verification on the merged tree and re-reading both hosted runs at step level via
`gh`.

## Scope Reviewed

- `.github/scripts/derive-gate-budgets.sh` — `WINDOW=20`, the pure
  `window_run_ids()` selector (`sort -rnu | head -N`), the `--self-test`, and the
  awk process-substitution first-file wiring (`FNR==NR` KEEP filter).
- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` — `windowSize=20`,
  `mostRecentRunIDs`, the pure `corpusExtremes(from:windowSize:)` refactor, the
  AC6 two-way-floor fixture test, and the cross-language pin test.
- The re-derivation: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
  (append-only, +45 run `29606487287`) and the budget literals under
  `Sources/ViewportBenchmarks/`.
- `AGENTS.md` — the `## Gate budgets` window documentation, the `GateFloorTests`
  description update, and the two folded Slice-40 P3s.
- `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` — the P3 #2 comment fix.
- The spec, plan, and verification record for the slice.

Out of review scope, because the slice did not touch them (confirmed by
`git diff --name-only b0efeef..be7dd2b`): `Sources/TextEngineCore`,
`Sources/TextEngineReferenceProviders`, and any benchmark **workload**.

## Product Brief Alignment

The brief's hard constraints hold; the perf invariant is strengthened.

- **Foundation-free core** — no core file changed; `rg -n Foundation
  Sources/TextEngineCore` is empty (re-run for this review). The only Foundation
  import is `GateFloorTests`'s pre-existing test-target one, to read the corpus
  file — it cannot leak into the shipped core.
- **Zero-dependency** — no parser added. Both consumers keep hand-rolled narrow
  readers (`sort -rnu | head` in shell; `Set(...).sorted(by:>).prefix` in Swift;
  the pin test reads the `WINDOW=` line by prefix, mirroring `WorkflowShapeTests`).
- **Swift Embedded / iOS+WASM** — the run-id key is pure integer arithmetic; no
  timestamps, no Foundation, no Embedded strain. The iOS/WASM surface is untouched
  (both cross-target jobs green on both hosted runs).
- **Memory / virtualization invariants** — unchanged; not in scope.
- **Perf invariant** — this is the slice's contribution: the `3× max` floor over
  an append-only corpus was a **one-way ratchet** (`max` can only rise → budgets
  could only loosen). The window makes it **two-way**: an aged-out freak releases
  the budget it inflated, and the budget can tighten again — proven on the hosted
  runner (see below).

## Delivered Design

### The trailing window, identical in both consumers

The corpus stays full-history **append-only**; the window is a **read-time
filter** — N is a re-tunable knob with no data loss. Both consumers compute the
same set:

- Shell `window_run_ids()` = `tail -n +2 | cut -f1 | sort -rnu | head -N` (reverse
  numeric unique → distinct run ids, newest first, since GitHub `databaseId` is
  monotonic), fed into the awk derivation as a process-substitution **first file**
  (`FNR==NR { KEEP[$1]=1 }`), which also sidesteps the `awk -v` newline-mangling a
  newline-separated value would trigger and correctly drops the header row.
- Swift `mostRecentRunIDs(_:limit:)` = `Set(Set(ids).sorted(by:>).prefix(limit))`
  — dedups first (a run contributes many rows), then the same "largest N by
  value" selection.

The central risk of the slice is that these two silently diverge. It is closed
two ways: **AC6**'s `testWindowedExtremesDropAnAgedOutFreak` proves the Swift side
is genuinely bidirectional (window 3 → the 999 freak in the oldest run ages out,
max drops to 32/64; window 10 → the freak is retained, 999/999), and the
cross-language **pin test** `testWindowConstantMatchesDeriveScript` reads the
shell `WINDOW=` line and fails if it disagrees with `windowSize`. I re-verified
from both ends: on the merged corpus, `sort -rnu | head -20` yields the identical
top-20 run-id set a distinct-sort reference produces, and my from-scratch
re-derivation matches the committed budgets byte-for-byte.

### The re-derivation — every mode, swept under the window

The harvest appended Slice 40's post-merge push run `29606487287` (append-only;
`git numstat` = `45 0`) and re-derived **all 46** gated budgets under the window.
Re-verified for this review by running `derive-gate-budgets.sh <corpus>` with no
mode argument and diffing against every committed literal: **46/46 reproduce
byte-for-byte, 0 mismatches** — the "derived, never hand-typed" invariant holds
across the whole suite, including modes the slice's narrative never touched.

Crucially, budgets moved in **both** directions this time — the ratchet is no
longer one-way. Several tightened as old freaks aged out; a few loosened where the
median rose. Both are correct derived outcomes; committing whatever `derive`
prints is the discipline.

### `AGENTS.md` and the folded P3s

`AGENTS.md` `## Gate budgets` now documents the window (N=20, the run-id key, both
consumers applying it identically, pinned by the test) and the two-way-floor
rationale — including the correct nuance that an aged-out freak's *recurrence* is
backstopped by the **median-anchored floor terms** (and, on p99, `2×budget_p95`),
**not** the `3×`-max term, so **p95 is the thin axis to watch**. Slice 40's two
carried P3s are folded and **closed**: the `Tests/ViewportBenchmarksTests` list
now names all five files (P3 #1), and the `WorkflowShapeTests` comment (P3 #2) was
de-staled — repointed from the deleted point-query rationale block at the
still-present realistic-provider `continue-on-error` comment, and rewritten to be
mechanism-accurate (it no longer claims comment-exclusion is what prevents a
continue-on-error *key* miscount; the 8-space key anchoring does that, and the
load-bearing role of comment exclusion is correctly located in the block-scalar
payload token collection).

## Verification Evidence Reviewed

### Fresh local checks on the merged tree (`fe02899`)

| Check | Result |
|---|---|
| `swift test` | **299 tests, 0 failures** (incl. the 2 new window tests + the pin test) |
| all 46 budgets reproduce from the windowed corpus | **0 mismatches** |
| `derive-gate-budgets.sh --self-test` | `self_test=pass` |
| `rg -n Foundation Sources/TextEngineCore` | empty |
| whole-branch diff vs engine/provider | zero `TextEngineCore`/`TextEngineReferenceProviders` paths (AC2) |
| at-floor cluster after the window | only **2** scenarios at 3.0× (`line_query\|uniform_1k` p95, `column_query\|uniform_100k` p99), both with a *recent* in-window freak |

### Hosted runs (verified at step level, not job conclusion)

Read at step level per the standing rule — a `continue-on-error` step can conclude
a job green while its own step failed.

- **PR-head run `29634227651`** (head `be7dd2b`): three required jobs `success`;
  all eleven blocking gate **steps** `success`; whole-run tally **45 `gate=pass`,
  0 `gate=fail`**; host tests `299/0`. Tightest hosted headroom: **5.4× p95 /
  7.5× p99**. `Complete docs-only PR` correctly skipped (touches shell/Swift).
- **Post-merge `push` run `29634768501`** (merge commit `fe02899`): three required
  jobs `success`; all eleven blocking gate steps `success`; tally **45 `gate=pass`,
  0 `gate=fail`**; host tests `299/0`; the realistic-provider observation correctly
  **skipped** (a `push` event skips its `if: pull_request`). Tightest hosted
  headroom: **5.5× p95 / 7.3× p99**. The four `point_geometry_query` checksums are
  **byte-identical** to the PR-head run, the local runs, and the Slice 40 baseline
  — the workload is unchanged across host, PR-head, and merged commit.

The two-way floor is visible on merged-code hosted numbers:
`point_geometry_query|prefixsum_100k` moved `1100/2200` (Slice 40) → `960/2000`,
its hosted p95 headroom `8.1× → 5.9×` — the ratchet releasing in the *tightening*
direction, still well inside the `3×`–`50×`/`100×` band.

## Git History

Six implementation commits on top of the pre-committed design docs, cleanly
separated by concern and following the slice lifecycle: `3a9c8a5` (feat: window
the derive script) → `f78a69d` (test: window `GateFloorTests`) → `4cb1a5f` (test:
the cross-language pin) → `9ce6975` (feat: harvest + re-derive) → `05c7c7f` (docs:
window docs + P3 folds) → `be7dd2b` (docs: verification record, incl. one
review-fix round). Prefixes are correct. The post-merge hosted proof lives in
PR #91 (`0471ce7`), matching the Slices 24–40 pattern of anchoring proof in the
merged-code `push` run.

One process note carried from Slice 40 and still unaddressed: the committed plan's
checkbox steps are left `- [ ]` though the work shipped (P3 below).

## Code Review Findings

### P0 / Release Blockers

**None.** The slice is merged, all eleven gates are green on the merged commit at
step level, both hard constraints hold (Foundation-free, zero engine/provider
diff), and every budget reproduces from the committed windowed corpus.

### P1 / Must Fix Before Merge

**None.** The two new tests are red-before/green-after with recorded evidence, the
pin test's guard-is-live was demonstrated (temporary `WINDOW=21` → red → revert),
and the two windows are provably identical.

### P2 / Production Readiness

**P2 #1 — The shell window-*selection* logic has no standing automated guard —
only a manual `--self-test`.** This is the one place the slice's own thesis
("the two consumers must not diverge") is *not* enforced by a standing test.
`testWindowConstantMatchesDeriveScript` pins the N **constant** across languages,
and `GateFloorTests` exercises the **Swift** selection logic in CI — but the
**shell** selection logic (`window_run_ids` + the awk `FNR==NR/KEEP` filter) is
covered only by `derive-gate-budgets.sh --self-test`, which is invoked by neither
CI nor any test target (grep confirms zero references). The uncaught direction: a
shell window that silently computes *looser* than the Swift window (e.g. someone
drops `-u`, or edits the `head` semantics, without running the self-test) — the
resulting looser budgets would still clear `GateFloorTests` (which uses the
correct Swift window) and still pass the pin test (the N constant is unchanged).
**Well-mitigated today** — `derive` is a dev-tool, not a CI step; the per-slice
"reproduce every literal" check catches a drifted derivation; and it follows the
repo's established manual-shell-self-test convention (`harvest`,
`cross-target-compile`). Not a defect in the merged code; it is the strongest
next-slice candidate (see recommendation).

**P2 #2 — `point_geometry_query` is the thinnest-evidence gated mode, at n=12
windowed runs.** Under the window, the four point-geometry scenarios carry only
**12** distinct runs each — just above the **11-run starvation floor** that
`GateFloorTests.testEveryGatedScenarioHasCorpusEvidence` enforces. This slice
*improved* the situation Slice 40's review flagged (Slice 40 had **loosened**
point-geometry; this slice's window **tightened** `prefixsum_100k` `1100→960`,
hosted headroom `8.1×→5.9×`), so the direction is now right. But thin evidence
plus strict required checks means a flaking point-geometry gate blocks every PR;
it remains the mode to watch, and its n=12 is the closest any gated mode sits to
the starvation floor. Monitoring item, not a defect.

**P2 #3 — Recurrence-safety of an aged-out freak now rests on the median-anchored
floors, not the `3×`-max term — and p95 is the thin axis.** This is a property of
the design, correctly documented in `AGENTS.md` and the verification record, but
worth restating as a standing risk. After the window relieved three of Slice 40's
five at-floor scenarios (`line_geometry_query|uniform_1k` p99 `990→500`,
`line_geometry_query|uniform_1m`, `line_query|uniform_100k` p95), two remain
*exactly* at the 3.0× floor — `line_query|uniform_1k` p95 and
`column_query|uniform_100k` p99 — because their worst sample is **recent** (still
in the top-20 window), which is the floor working *correctly*. If one of those
freaks ages out later and then recurs, the `3×`-max term will have already
relaxed, and only the `8×median` term (p95) / `8×median` + `2×budget_p95` (p99)
backstops it. p95 carries only the median backstop, so a `gate=fail
reason=budget_stale` there is the first thing to re-derive.

### P3 / Minor But Valid

**P3 #1 — `run_self_test` leaks its `mktemp` fixture on a first-assertion (red)
failure.** `.github/scripts/derive-gate-budgets.sh`: `assert_equal` does `exit 1`
before the trailing `rm -f "$fixture"`, so a failing self-test orphans one temp
file. Harmless (red path of a manual tool). A `trap 'rm -f "$fixture"' EXIT`
closes it. Tidy opportunistically.

**P3 #2 — `AGENTS.md` still introduces `WorkflowShapeTests.swift` as "the third
guard"** though the bullet now lists five files. Accurate as a count of *described*
guards (the two new point-geometry test files that follow are not framed as
"guards"), but mildly ambiguous on a fresh read. Cosmetic.

**P3 #3 — The rewritten `WorkflowShapeTests` comment cites `swift-ci.yml:145-148`
by line range.** A location pointer that will drift if the YAML above it is edited
(cf. `[[measured-values-in-comments-rot]]`, though this is a weaker instance — a
line range, not a measured value). A step-name/prose anchor would be more durable.
The citation is exact today.

**P3 #4 — Plan checkboxes left unchecked.** Every step in the committed plan is
`- [ ]` though the work shipped; the commit messages are the completion evidence.
Cosmetic paper-trail nit, carried from prior slices.

## Risks And Gaps

- **The median-anchored recurrence backstop (P2 #3)** — the window makes the floor
  two-way, but a re-recurring freak on p95 is caught only by the `8×median` term.
  Monitor p95; re-derive on any hosted `budget_stale`.
- **Point-geometry thin evidence (P2 #2)** — n=12, closest to the 11-run
  starvation floor; watch `prefixsum_100k`.
- **Shell selection-logic has no standing guard (P2 #1)** — the one un-CI'd half of
  the "both consumers agree" invariant.
- **Harvester provenance gap (known, unmitigated, roadmap).**
  `harvest-gate-corpus.sh` still selects rows by run id alone — no
  `conclusion`/`event`/fork check — so a fork PR could in principle inject
  fabricated `p95_ns=` lines into a future harvest. Untouched by this slice;
  recorded as a security-shaped roadmap item.
- **Budgets still anchored to a moving median** — no absolute/product budget exists
  (Slice 38 Option C, still unclaimed). The window now stops the *upward* drift,
  which makes an absolute ceiling better-timed than before.
- **Standing items unchanged** — WASM observational; realistic-provider observation
  PR-only `continue-on-error`; the `Main` ruleset keeps its bypass-actor shape.

## Lessons For The Next Slice

- **A subagent died mid-Task-4 (API connection drop) after committing correct
  work; the recovery discipline held.** The controller verified the committed
  artifact independently (a completion agent ran the full 11-gate + checksum
  sweep; the per-task reviewer re-derived all 46 budgets *from scratch*) rather
  than trusting the dead agent's process. Verify the committed artifact, not the
  narrative — the same lesson `GateFloorTests` itself encodes.
- **The lightest lever was enough.** The Slice 39/40 paper trail sketched a
  two-lever fix (trailing window **plus** outlier rejection, or a curation policy).
  A trailing window *alone* delivered a genuinely two-way floor and relieved 3 of
  the 5 at-floor scenarios. Prefer the lightest mechanism that satisfies the
  invariant; add levers only when evidence demands them.
- **A plan's example code is a starting point, not verified.** The plan's
  `corpusExtremes` snippet was declared at internal visibility while returning the
  `private CorpusExtremes` type — which does not compile. Caught at implementation
  (`private func`), confirmed by the final review. Transcribe plan code with a
  compiler, not on faith.

## Slice 42 Candidate Options

### Option A: give the shell window-selection logic a standing guard — recommended

Close the one place the slice's "both consumers agree" invariant is enforced only
by a manual `--self-test` (P2 #1). Two shapes, either small: wire
`derive-gate-budgets.sh --self-test` into CI as its own step, **or** add a Swift
test that runs the shell `window_run_ids` over a fixture corpus and asserts its
output equals `mostRecentRunIDs` on the same ids — pinning the two *selection
logics* the way the pin test already pins the *constant*. One-concern, directly
completes this slice's own thesis.

### Option B: the absolute (product) budget (Slice 38 Option C, still unclaimed)

A fixed product ceiling (e.g. the 1 µs line every scenario's hosted p99 already
clears) that does not move with the median. Now better-timed than before: the
window has stopped the upward drift, so an absolute backstop composes cleanly with
the median-governed floor rather than fighting it.

### Option C: harvester provenance hardening

Filter harvested runs by `conclusion=success` / non-fork / expected event, closing
the injection gap in Risks. Security-shaped; small.

### Option D: generalize `WorkflowShapeTests` to every gated mode

Add a `flagName` mapping + a named-and-justified exemption set (`.pipeline` has no
flag; `.realisticProvider` is deliberately never `--gate`d) + a test pinning the
two together, so all eleven gate steps are shape-pinned, not just point-geometry.
Standing infra (carried from Slice 40 P3 #3).

## Recommended Slice 42 Selection

**Option A — the shell window-selection standing guard.** It is the direct
completion of the invariant *this* slice is built on: Slice 41 closed the
N-*constant* drift with a standing cross-language test but left the selection
*logic* drift to a manual, un-CI'd self-test — the single remaining place where
the shell and Swift consumers could silently diverge (looser shell → still-green
`GateFloorTests` + pin test). It is small, one-concern, and it hardens the
calibration machinery the last four slices have been building on. Option B (the
absolute product budget) is the natural follow-on now that the window has stopped
the upward drift, and is the stronger *product* play if the user prefers to move
the budget story forward rather than harden the tooling — a legitimate re-scope,
as with the Slice 39→40→41 sequence. Fold the trivial P3 #1 (`trap` cleanup) and
P3 #3 (comment anchor) opportunistically if Slice 42 touches those files.

## Slice 41 Review Conclusion

Slice 41 does exactly what the Slice 39 and Slice 40 reviews asked for, with the
lightest lever and no scope creep: the `3× max` floor is now two-way, applied
identically in both consumers and pinned by a cross-language test; every budget in
the suite re-derives byte-for-byte from a correctly-swept windowed corpus; no core,
provider, or workload byte moved (all eleven checksums byte-identical); and the
merged commit is green across all eleven blocking gates at step level, with the
two-way behavior visible on the hosted numbers. A subagent died mid-implementation
and the recovery discipline held. No P0, no P1. The single substantive
carry-forward is the shell selection-logic standing guard — the un-CI'd half of
this slice's own invariant. **READY — merged and verified; Slice 42 = shell
window-selection standing guard (Option A), or the absolute product budget
(Option B) as a product re-scope.**
