# Slice 42 Post-Slice Review

The last un-CI'd axis of Slice 41's "both gate-budget-window consumers agree"
invariant is now closed by a standing test. Slice 41 pinned the window's **N
constant** across languages and CI-exercised the **Swift** selection logic, but
left the **shell** selection logic (`window_run_ids`) guarded only by a manual
`--self-test` that nothing runs. Slice 42 adds a thin `--window-run-ids [N]` seam
to `derive-gate-budgets.sh` (delegating to the existing `window_run_ids`) and a
new XCTest, `testWindowSelectionMatchesDeriveScript`, that drives that seam over a
discriminating fixture and asserts the shell's chosen run-id **set** equals
Swift's `mostRecentRunIDs`. Zero `TextEngineCore`/`TextEngineReferenceProviders`
change; zero budget/corpus/workload change (all 45 gate checksums byte-identical).
Merged as `173e644` (PR #93); AC8 hosted proof recorded in the docs-only
follow-up **PR #94** (`248b42d`).

This is the Slice 41 review's recommended **Option A**, delivered in its stronger
of the two floated shapes — a Swift cross-language pin against the actual Swift
consumer, not a CI step re-running the shell's own self-test. This review was
written after independently re-running the local verification on the merged tree
and re-reading both hosted runs at step level via `gh`.

## Scope Reviewed

- `.github/scripts/derive-gate-budgets.sh` — the new `--window-run-ids [N]`
  subcommand guard (delegates to the unchanged `window_run_ids`; reads corpus on
  stdin; `N` defaults to `$WINDOW`), the `# Usage:` header additions, and the
  P3 #1 `trap`-cleanup fold in `run_self_test`.
- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` —
  `testWindowSelectionMatchesDeriveScript` and its `runProcess` helper (the test
  target's first `Foundation.Process`/bash subprocess launch), set-equality
  against `mostRecentRunIDs`, and the loud-`XCTFail`-on-nonzero-exit contract.
- `AGENTS.md` — the `GateFloorTests` description update, the `## Gate budgets`
  window-paragraph addition, and the `## Commands` seam entry.
- The spec, plan, and verification record for the slice; the AC8 hosted-proof
  edit in PR #94.

Out of review scope, because the slice did not touch them (confirmed by
`git diff --name-only e1d879e..137a1ef`): `Sources/TextEngineCore`,
`Sources/TextEngineReferenceProviders`, every budget literal under
`Sources/ViewportBenchmarks/`, and the corpus.

## Product Brief Alignment

The brief's hard constraints hold; the perf-gate machinery is hardened.

- **Foundation-free core** — no core file changed; `rg -n Foundation
  Sources/TextEngineCore` is empty (re-run for this review). The subprocess helper
  and its `Process`/`Pipe` use live in `ViewportBenchmarksTests`, which already
  imported Foundation to read the corpus off disk — nothing crosses into the
  shipped core.
- **Swift Embedded / iOS+WASM** — no engine surface touched; both cross-target
  jobs are green on both hosted runs. The subprocess launch is test-target-only and
  never compiled for iOS/WASM (those jobs only compile `TextEngineCore` /
  `TextEngineReferenceProviders`).
- **Zero-dependency** — no parser or package added. The seam is one delegating
  `if` block; the test parses a handful of integer lines by hand.
- **Memory / virtualization invariants** — unchanged; not in scope.
- **Perf invariant (the brief's «блокируют merge при деградации»)** — strengthened,
  not weakened. This slice moves no measured latency and no budget number; what it
  hardens is the *machinery that keeps budgets honest*. Slice 41 stopped budgets
  from ratcheting loose via a windowed floor computed by two consumers; a
  silently-looser shell window would derive budgets that block less than they
  should. That direction now fails a standing build — a strictly more trustworthy
  gate.

## Delivered Design

### The seam, and why a subcommand

`window_run_ids` is a function inside a script whose main body runs on load, so it
cannot be invoked in isolation without sourcing the script (which trips
`corpus="${1:?...}"` and exits) or a fragile text-extraction hack. The
`--window-run-ids [N]` subcommand, placed beside the existing `--self-test` guard,
exposes exactly the function the derivation already uses via
`<(window_run_ids < "$corpus")` — it **delegates**, duplicating none of the
selection logic. Re-verified by hand on the merged tree: a 7-row corpus with two
duplicated, physically-out-of-order run ids yields `305`/`210` at `N=2`, all five
distinct ids newest-first at `N=10`, and a single id at the `$WINDOW` default —
the exact selection `mostRecentRunIDs` computes.

### The pin, and why set-equality

`testWindowSelectionMatchesDeriveScript` launches the seam over a fixture
(`[100, 305, 305, 210, 99, 210, 42]`) and compares the shell's emitted run-id
**set** to `mostRecentRunIDs(sameIDs, limit:)` at `N ∈ {2, 3, 10}` — both the
dropping-N and no-op-N regimes. Set, not ordered list, is the right comparison:
the awk `FNR==NR { KEEP[$1]=1 }` filter and the Swift `window.contains` fold both
use membership, so emission order never reaches the derivation (the shell
`--self-test` covers newest-first ordering separately). The comparison being
direction-blind is the whole point — it catches the *within-band-looser* shell
direction that `GateFloorTests` (which windows through the correct Swift selector),
the constant pin (N unchanged), and the runtime `--gate` (blind below its
50×/100× ceiling) all leave open.

### Guard-is-live, independently reproduced

A guard that cannot fail protects nothing, so the fixture is engineered so the
canonical break shifts the *set*: the max run id `305` is duplicated at the
dropping-N boundary, so dropping `-u` from `sort -rnu` keeps `305` twice under
`head -N` and pushes a distinct id out of the window. I reproduced the break
independently for this review (not trusting the recorded transcript): with `sort
-rn`, the test reddens at `N=2` (`{305}` vs `{305, 210}`) and `N=3`, and passes
again on revert — a byte-clean revert confirmed. The `.bak`-based break never
touched git, so the tree stayed clean.

### The P3 #1 trap fold

`run_self_test` now sets `trap "rm -f '$fixture'" EXIT` immediately after
`mktemp`, double-quoted so the path is baked in while the `local` is in scope (the
single-quote form the Slice 41 review sketched would defer expansion to EXIT time,
when `fixture` is empty). I forced the real self-test onto its red path (mutated a
fixture run id so `assert_equal` exits 1) and confirmed no `mktemp` file leaks —
the trap fires on the red path, closing Slice 41's P3 #1.

## Verification Evidence Reviewed

### Fresh local checks on the merged tree

| Check | Result |
|---|---|
| `swift test --filter GateFloorTests` | **8 tests, 0 failures** (incl. the new pin test) |
| `--window-run-ids` by hand (N=2 / N=10 / default) | `305,210` / all-5-newest-first / single id — matches `mostRecentRunIDs` |
| guard-is-live (drop `-u` → red → revert → green) | reproduced independently; RED at N=2/3, clean revert |
| `derive-gate-budgets.sh --self-test` | `self_test=pass`; fixture cleaned on a forced red path (no leak) |
| `rg -n Foundation Sources/TextEngineCore` | empty |
| whole-branch diff vs engine/provider/budget/corpus | zero `TextEngineCore`/`TextEngineReferenceProviders`/`ViewportBenchmarks/*.swift`/corpus paths |
| all 45 gate checksums | byte-identical to the Slice 41 baseline (recorded in the verification doc) |

### Hosted runs (verified at step level, not job conclusion)

Read at step level per the standing rule — a `continue-on-error` step can conclude
a job green while its own step failed.

- **PR-head run `29648059739`** (head `137a1ef`): three required jobs `success`;
  all eleven blocking gate **steps** `success`; whole-run tally **45 `gate=pass`,
  0 `gate=fail`**; host tests **300/0** (incl. `testWindowSelectionMatchesDeriveScript`
  in the log). `Complete docs-only PR` correctly **skipped** (the branch touches
  `.github/scripts/**` + a Swift test → non-docs-only). Tightest hosted headroom
  **2.6× p95 / 4.1× p99** (`line_query|uniform_100k`, 107 ns vs 280 ns budget).
- **Post-merge `push` run `29652529080`** (merge commit `173e644`): run `success`;
  three required jobs `success`; all eleven gate steps `success`; tally **45
  `gate=pass`, 0 `gate=fail`**; host tests **300/0**. `Observe realistic provider
  relative performance` correctly **skipped** (a `push` event skips its
  `if: pull_request`). Tightest hosted headroom **5.2× p95 / 7.3× p99** — in line
  with Slice 41 (5.4×/7.5×, 5.5×/7.3×). The four `point_geometry_query` checksums
  are **byte-identical** to the PR-head run, the local runs, and the Slice 40/41
  baseline.
- **Hosted-proof PR `#94`** (docs-only): three required jobs `success`; detector
  verdict `mode=docs_only_pr result=docs_only docs_only_pr=true`; `Complete
  docs-only PR` `success`; every Swift/gate step `skipped` — the docs-only path
  emitting the required contexts without running the heavy work, exactly as
  designed.

The PR-head's tighter 2.6× p95 is single-run runner jitter on the sub-microsecond,
nanosecond-quantized `line_query`/`column_query` cluster — the exact "p95 is the
thin axis" cluster the Slice 41 review flagged (its P2 #3). Budgets and checksums
are byte-identical to Slice 41, so it is not a regression; the merged-code run
lands back at the Slice 41 level (5.2×). Still `gate=pass`, well inside the ceiling.

## Git History

Six implementation commits on top of three pre-committed design/plan docs, cleanly
separated by concern and following the slice lifecycle: `71df260` (fix: trap-clean
the self-test fixture) → `91e67d5` (feat: the `--window-run-ids` seam) → `b3b0885`
(test: the cross-language selection pin) → `384a2da` (docs: AGENTS.md record) →
`8fd4a9b` (docs: local verification) → `137a1ef` (docs: a final-review wording
fix). Conventional-commit prefixes are correct and the `fix`/`feat`/`test`/`docs`
split matches the work. The AC8 hosted proof lives in PR #94 (`248b42d`), matching
the Slices 24–41 pattern of anchoring proof in the merged-code `push` run rather
than the PR-head run alone.

## Code Review Findings

### P0 / Release Blockers

**None.** The slice is merged, all eleven gates are green on the merged commit at
step level, both hard constraints hold (Foundation-free, zero engine/provider
diff), the seam delegates rather than duplicates, and the guard is demonstrably
live.

### P1 / Must Fix Before Merge

**None.** The new test is green-after with recorded (and independently reproduced)
guard-is-live evidence; a subcommand launch failure or non-zero exit is a loud
`XCTFail` carrying stderr, never a skip, so the guard cannot silently no-op; and
the two selectors are provably set-equal on the discriminating fixture.

### P2 / Production Readiness

**P2 #1 — The derivation *arithmetic* keeps the symmetric residual this slice
closed for the *selection*.** By the slice's own argument, `GateFloorTests`
catches an arithmetic drift that makes a budget *too tight* (below `3×` windowed
max) and the runtime ceiling catches one *gross enough* to exceed 50×/100×, but a
*within-band looser* arithmetic drift (`8×median`, `3×max`, `round_up_2sf`) is
caught only by the manual per-slice "reproduce every literal" check. That is the
same direction and same manual-only weakness Slice 42 just closed for
`window_run_ids`. The spec records this as a deliberate residual (Decision 1
rejects driving the whole derivation partly because closing it couples to the
budget-literal representation). It is the strongest *tooling-completion* candidate
for a future slice — a standing "reproduce every committed literal" test.

**P2 #2 — The self-test's *ordering* coverage stays manual.** Slice 42 pins shell
≡ Swift *membership*; newest-first *ordering* between the shell output and its own
`--self-test` expectations is still only checked by a human running `--self-test`.
Judged acceptable and documented: ordering does not affect the derivation (the
consumers use membership), so the property the budgets depend on is now
standing-guarded. Recorded, not closed.

**P2 #3 — Carried from Slice 41: `point_geometry_query` thin evidence (n≈12) and
the p95-thin-axis recurrence risk.** Under the window, the point-geometry scenarios
sit closest to the 11-run starvation floor, and an aged-out freak's recurrence on
p95 is backstopped only by the `8×median` term (the `3×`-max term having relaxed).
Slice 42 touches none of this, but the PR-head run's 2.6× p95 on
`line_query|uniform_100k` is a live reminder that the sub-µs cluster is where a
hosted `budget_stale` would surface first. Monitor p95; re-derive on any hosted
`budget_stale`. Not a defect in this slice.

**P2 #4 — Harvester provenance gap (known, unmitigated, roadmap).**
`harvest-gate-corpus.sh` still selects rows by run id alone — no
`conclusion`/`event`/fork check — so a fork PR could in principle inject fabricated
`p95_ns=` lines into a future harvest. Untouched by this slice; a security-shaped
roadmap item.

### P3 / Minor But Valid

**P3 #1 — The verification record miscounted the gated scenarios as "46".** The
eleven `--gate` modes carry **45** scenario rows (the record's own byte-identity
table lists 45; both hosted tallies read `45 gate=pass`). `realistic_provider` is
registered in `everyGatedBudget()` but never `--gate`d in CI, so it emits no gated
row. **Caught and fixed** in PR #94 (three occurrences corrected to 45, with the
`realistic_provider` reason noted). Recorded here as a caught-and-closed finding.

**P3 #2 — The verification record's guard-is-live evidence was copied, not
re-run.** Section 2 is quoted verbatim from the subagent's `task-2-report.md`
("not re-executed here"), in mild tension with the slice's own inherited lesson
("verify the committed artifact, not the narrative"). The stated reason is
sound (re-running would dirty the shell script for no new evidence), and this
review **independently re-ran the break→red→revert→green cycle** and confirms it
holds — so the copied evidence is accurate. Process note, not a defect.

**P3 #3 — Carried from Slice 41: the `WorkflowShapeTests` comment cites
`swift-ci.yml:145-148` by line range.** A pointer that will drift if that YAML is
edited above it (cf. `[[measured-values-in-comments-rot]]`). Correctly left out of
scope — Slice 42 does not touch `WorkflowShapeTests.swift`, and folding it would
widen the diff past one concern. Carried forward for a slice that touches that
file.

**P3 #4 — Plan checkboxes left unchecked.** Every step in the committed plan is
`- [ ]` though the work shipped; the commit messages are the completion evidence.
Cosmetic paper-trail nit, recurring across slices.

## Risks And Gaps

- **Arithmetic residual (P2 #1)** — the loose-side symmetric analog of what this
  slice closed for the selector; still manual-only. The natural tooling successor.
- **Ordering stays manual (P2 #2)** — membership is guarded; ordering is not, and
  does not affect the derivation.
- **p95 thin axis / point-geometry thin evidence (P2 #3)** — re-derive on any
  hosted `budget_stale`; watch the sub-µs cluster.
- **Harvester provenance (P2 #4)** — run-id-only selection; injection-shaped
  roadmap item.
- **Budgets still anchored to a moving median** — no absolute/product budget exists
  (Slice 38 Option C, still unclaimed). Slice 41 stopped the upward drift and Slice
  42 hardened the tooling under it, so an absolute backstop now composes cleanly.
- **Standing items unchanged** — WASM observational; realistic-provider observation
  PR-only `continue-on-error`; the `Main` ruleset keeps its documented bypass-actor
  shape.

## Lessons For The Next Slice

- **The seam-not-reimplementation discipline paid off.** The pin drives the
  script's *own* `window_run_ids` via a delegating subcommand, so the test is tied
  to the shell consumer itself, not to a copy of its logic. Re-implementing the
  selector in Swift would have pinned the test to a second copy — passing while the
  real consumer drifted. When cross-pinning two implementations, exercise the real
  one.
- **Engineer the fixture to move the observable, then prove it moves.** The guard is
  only live because the duplicate run id sits at the dropping-N boundary; without
  that placement, dropping `-u` would leave the *set* unchanged and the test green.
  The break was demonstrated, not assumed — and re-demonstrated in this review.
- **A copied transcript is not verification.** The guard-is-live evidence was
  copied from a subagent report; it happened to be correct, but the honest form is
  to re-run it (as this review did). Prefer re-execution over transcription for any
  load-bearing claim.

## Slice 43 Candidate Options

### Option A: the absolute (product) budget — recommended (spec's own Next Step)

A fixed per-scenario ceiling (e.g. the brief's "60 FPS → measurable headless
budget", such as the 1 µs line every query scenario's hosted p99 already clears)
that never recalibrates, catching the *legitimate slow drift* a median-anchored
regression budget can always re-derive around. Now well-timed: Slice 41 stopped the
upward drift and Slice 42 hardened the tooling under it, so an absolute backstop
composes cleanly with the median-governed floor rather than fighting a moving
median. Moves the *product* story forward.

### Option B: standing "reproduce every committed literal" test (closes P2 #1)

The tooling-completion analog of this slice: a standing test that re-derives every
budget from the windowed corpus and asserts byte-equality with the committed
literals, closing the within-band-looser *arithmetic* residual the same way Slice
42 closed the *selection* one. Directly completes the "keep budgets honest"
machinery; smaller and more infra-flavored than Option A.

### Option C: harvester provenance hardening (P2 #4)

Filter harvested runs by `conclusion=success` / non-fork / expected event, closing
the injection gap. Security-shaped; small.

### Option D: generalize `WorkflowShapeTests` to every gated mode

Add a `flagName` mapping + a named-and-justified exemption set + a test pinning the
two together, so all eleven gate steps are shape-pinned, not just point-geometry
(folds P3 #3). Standing infra.

## Recommended Slice 43 Selection

**Option A — the absolute product budget (Slice 38 Option C).** The calibration
machinery is now closed on all three axes of "both consumers agree" (constant
pinned, Swift logic CI-exercised, shell logic cross-pinned), which is exactly the
precondition the spec names for moving the budget story forward: with the upward
ratchet stopped and the tooling hardened, an absolute ceiling composes with the
median floor instead of fighting it, and it catches the one thing a
median-anchored regression budget structurally cannot — a legitimate, slow,
re-derived-around drift. **Option B** (the arithmetic "reproduce every literal"
standing test) is the strongest *tooling* alternative and the direct completion of
this slice's own thesis for the derivation arithmetic; prefer it if the user would
rather finish hardening the machinery before advancing the product budget. Fold the
trivial P3 #3 (comment anchor) and P3 #4 (plan checkboxes) opportunistically if
Slice 43 touches those files.

## Slice 42 Review Conclusion

Slice 42 does exactly what the Slice 41 review asked for, in the stronger of the
two floated shapes and with no scope creep: the shell window-selection logic is now
pinned to its Swift twin by a standing, demonstrably-live test, closing the third
and last axis of the "both consumers agree" invariant. No core, provider, budget,
or corpus byte moved (all 45 checksums byte-identical); the Slice 41 P3 #1 trap
fold is closed and verified on the red path; and the merged commit is green across
all eleven blocking gates at step level on both the PR-head and post-merge push
runs, with host tests 300/0 on hosted Linux proving the target's first subprocess
launch runs there. One documented miscount ("46" gated scenarios) was caught and
fixed in the hosted-proof PR #94. No P0, no P1. The substantive carry-forwards are
the symmetric *arithmetic* residual (the loose-side analog this slice leaves for a
future standing test) and the standing Slice 41 items (p95 thin axis, harvester
provenance). **READY — merged and verified; Slice 43 = the absolute product budget
(Option A), or the arithmetic "reproduce every literal" standing test (Option B)
as a tooling-completion re-scope.**
