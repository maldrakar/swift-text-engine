# Slice 51 — post-slice review (cross-target script hardening: D-1 / D-2 / D-3 / D-6)

**Slice:** 51 — soft-wrap arc, **debt route** (no map node, no brief criterion)
**Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md) · **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)
**Spec:** [`specs/2026-08-07-cross-target-script-hardening-design.md`](../specs/2026-08-07-cross-target-script-hardening-design.md) · **Plan:** [`plans/2026-08-07-cross-target-script-hardening.md`](../plans/2026-08-07-cross-target-script-hardening.md)
**Merged:** [PR #120](https://github.com/maldrakar/swift-text-engine/pull/120), merge commit `bd5e042` (merge commit — child SHAs preserved, no rebase-rewrite). 19 commits over `927251e..bd5e042`.
**Merged proof:** post-merge `push`-to-`main` run `31214035498` @ `bd5e042` — green at **step** level (3/3 jobs; heavy path ran — `result=not_pull_request docs_only_pr=false`; 361/0 tests; 46 `gate=pass` over twelve modes; one `cross_target_sdk_install_seconds=5 attempts=1`; four WASM + four iOS blocking passes; zero `result=fail`/`gate=fail`/`self_test=fail` in the log). Recorded via docs PR [#121](https://github.com/maldrakar/swift-text-engine/pull/121), verification §8.

## What shipped

The slice the user chose over the topological node-3 lean: four recorded debt
items in one file plus one process gap. Delivered via subagent-driven
development (6 tasks), with a whole-branch review that found and fixed a
fail-open guard before merge.

- **D-1 — asymmetric-SDK-drift now reports the truth.**
  `WASM_BUNDLE_FAILED_REASON` → `WASM_BUNDLE_STATE`, which records
  `bundle_installed_ok` on the success path where it previously recorded
  nothing. `wasm_install_precheck` gains its fifth contract row: an installed
  bundle whose second kind's id still does not resolve returns
  `sdk_unresolved_after_install` instead of `""`, so the second kind no longer
  burns a full bounded-retry ladder against an already-installed bundle and no
  longer reports a fabricated `sdk_install_failed`. The short-circuit **message**
  was fixed with it (`reason=bundle_installed_id_unresolved`) — D-1 exists to
  stop that path from lying, so a truthful return with an untruthful log line
  would have been a half-fix.
- **D-3 — the retry ladder owns its diagnostics.** Attempt `i` writes
  `${logfile}.attempt-${i}` via the new pure `attempt_logfile`; on exhaustion
  `swift_sdk_install_retry` prints one labelled tail **per attempt**, and
  `prepare_wasm_sdk`'s single `print_log_tail` call is gone — the caller cannot
  know how many attempts ran. New one-line `run_swift_sdk_install` seam exists
  solely to be stubbed.
- **D-6 — the exemption set is pinned, not prose.** Two hand-maintained
  top-level arrays (`SELF_TEST_COVERED`, `SELF_TEST_EXEMPT` with one
  justification per entry) plus a **derived** harness set. `--self-test` enforces
  a two-direction partition (unclassified function → red; phantom name → red)
  and a coverage check under four anti-tautology rules: arrays outside the
  extracted body, declaration lines stripped, comments stripped, and **token**
  rather than substring matching.
- **D-2 — plan-assertion conventions in `AGENTS.md`,** four of them, and applied
  to this slice's own plan.
- **Enforcement (the multiplier).** New `ScriptSelfTestTests` drives `--self-test`
  for **all four** `.github/scripts` scripts from `swift test`, asserting exit 0,
  `self_test=pass` present, and `self_test=fail` **absent** — plus a second case
  pinning the table against the directory, so a new self-tested script cannot
  silently join the set of checks that cannot fail. `runProcess`/`repositoryRoot`
  lifted out of both former twins into `ProcessSupport.swift`.

Suite **361/0** (up from 359 — the two new cases; no other count moved). Zero
`Sources/**`, workflow, budget, corpus, or gate-registry change; the three
synthetic gate checksums are byte-identical.

## Acceptance-criteria status

All eight ACs discharged (spec §Acceptance Criteria). Every row below was
**independently re-verified in this review** by re-running the mutation rather
than re-reading the recorded red.

| AC | Status | Evidence |
|---|---|---|
| 1 five precheck contract rows, fifth observed red first | ✅ | 6 assertion sites at `:659-676`; reverting row 5 → `precheck_installed_bundle_reports_unresolved expected=sdk_unresolved_after_install actual=bundle_installed_ok` |
| 2 `bundle_installed_ok` + exactly one install across both kinds | ✅ | `scenario_asymmetric_drift_reports_truth`; deleting the state recording → `drift_state_recorded expected=bundle_installed_ok actual=` |
| 3 truthful short-circuit message, asserted on the printed line | ✅ | Two independent mutations (swap the printed string; delete the whole branch) → both `drift_message_truthful` |
| 4 per-attempt logs + labelled tails + `( … ) \|\| exit 1` + meta-mutation | ✅ | Shared-logfile revert → `ladder_recover_attempt1_log … actual=missing`; tail-loop deletion → `ladder_exhaust_tail_count expected=3 actual=0`; **meta-mutation** (break an assert *inside* a scenario subshell) → `rc=1` + `self_test=fail`, so `run_scenario` really propagates |
| 5 classification at top level, bash 3.2, partition both directions, 4 anti-tautology rules | ✅ | 45 = 8 harness + 27 covered + 10 exempt; five mutations all red, incl. `resolve_wasm_sdk_id` classified covered → red **despite** `resolve_wasm_sdk_id_from_list` appearing four times, and a sole call moved into a comment → red |
| 6 `swift test` drives all four scripts; helpers in exactly one place | ✅ | Injected failure in `derive-gate-budgets.sh` → all three assertions fire with output attached; `repositoryRoot`/`runProcess` exist only in `ProcessSupport.swift` |
| 7 four conventions in `AGENTS.md`; the plan obeys them; no temp debris | ✅ | Plan audit: **0** checks on the left of a pipe, 13 `${PIPESTATUS[0]}`, `$SCRATCH` appears only inside the prose of rule 4. Debris: 0 temp roots after both a passing and a **failing** self-test |
| 8 hosted green at step level, PR-head **and** post-merge | ✅ | PR-head `31207266117` + `31213009464`; post-merge `31214035498`. Each read from the downloaded log, not from job conclusions |

## Strengths

- **The guarantees are falsifiable, and it shows.** This is the first slice in
  the repo whose central artifact is a check on other checks, and it did not fall
  into the trap it exists to fix: 15 of 17 standing guarantees shipped with a
  recorded red. Re-running all of them from scratch in this review reproduced
  every one.
- **The spec's own review rounds caught a P1 in the load-bearing construct.**
  The first draft mandated `( scenario )` subshells whose `exit 1` would have
  terminated only the subshell, leaving `self_test=pass` and exit 0 — a heavier
  version of the very defect the slice was written to close. Decision 5's
  `( … ) || exit 1` rule, the third XCTest assertion, and a mandated
  meta-mutation all trace to that one finding.
- **The whole-branch review caught a fail-open guard that only bites in CI.** An
  unchecked `mktemp -d` left `SELF_TEST_TMP_ROOT=""`; on macOS that fails safely,
  but in a root-run container — which is exactly the hosted image — every
  scenario would have written stray files to `/` while still reporting
  `self_test=pass`. Found, fixed, and verified by pointing `mktemp` at a
  nonexistent parent.
- **The enforcement reaches further than the slice's own file.**
  `detect-docs-only-pr.sh` — the trusted docs-only gate that decides whether the
  heavy CI path runs at all — had never had an assertion capable of failing a
  build. It does now, at the cost of ~10 lines over a single-script version.
  That gate proved itself twice on merge day: `docs_only_pr=false` on the
  code-bearing push, `docs_only_pr=true` on the docs-only PR.
- **The plan obeyed the conventions it introduced,** and the record says so with
  measurements rather than a claim — including three of the plan's *own*
  assertion defects found while executing it (§2a–2c), written up factually
  instead of quietly patched.

## Issues

No P0/P1. Four P3s and one nit; two of them are findings this review produced
rather than inherited.

**P3 #1 — D-15 records a hazard that cannot occur.** The ledger row (born in the
whole-branch review) says the sibling scripts' `run_self_test; exit 0` dispatcher
"would bite the moment either script grows an assertion or scenario helper that
`return`s non-zero without also `exit`ing — that path's failure would be
swallowed by the trailing `exit 0`." Measured, that is false:
`derive-gate-budgets.sh:19` and `harvest-gate-corpus.sh:29` both run
`set -euo pipefail`, so a `return 1` from `run_self_test` aborts under `-e`
before the dispatcher's `exit 0` is ever reached.

```
derive-gate-budgets.sh:  run_self_test returns 1 -> script exit=1
harvest-gate-corpus.sh:  run_self_test returns 1 -> script exit=1
cross-target-compile.sh (no set -e, pre-Task-1 dispatcher) -> exit=0
```

The last line is why `cross-target-compile.sh` genuinely needed the Task 1 fix:
it is the **only** one of the four without `-e`. The asymmetry is real as a
*shape* difference and worth removing for consistency, but it is cosmetic, not
latent risk. D-15's statement is corrected in the ledger with this measurement;
severity stays P3, status stays open.

**P3 #2 — two guarantees shipped without a recorded red.** The falsifiability
audit below found that `ScriptSelfTestTests.testTableCoversEveryScriptWithASelfTest`
and the `usage`-documents-`--self-test` assertion had no evidence they could
fail. Both were drilled in this review and both bite (see the audit). The
pattern worth naming: the slice mutation-tested its *new* guarantees
thoroughly, and skipped the two that felt structurally obvious. "Obvious" is
what the audit exists to disbelieve.

**P3 #3 — the D-6 pin's own detector was never mutation-tested in-slice
(found post-merge-PR, fixed in-slice).** `defined_functions` matched
`^[a-z_]+\(\) \{`, so a top-level function declared any other way escaped the
partition **silently, with `self_test=pass`**: a digit or capital in the name,
`name(){`, `name () {`, and both `function` spellings — six forms, all measured
green where they had to be red. Every mutation the slice ran exercised the pin's
*consumers* (arrays, coverage, comment stripping); none attacked the extraction
underneath them. Fixed test-first in `2c71676` (recorded red:
`actual=plain_form outer_form`), widened to POSIX ERE, with the `^` anchor —
load-bearing, because the scenarios define nested stubs — now pinned too. The
generalizable lesson: **a pin built on a parser needs a mutation aimed at the
parser**, which is this repo's own "pins must model what runtime reads" lesson
one level down.

**P3 #4 — the fifth-convention question is still open.** Verification §2d
records a real defect the plan's drill pattern caused: a mutation drill ending
in `git checkout --` reverts to `HEAD` when the task's own work is still
unstaged, silently wiping it (it happened once, in Task 5). The record correctly
declines to add it as a fifth *assertion* convention — it is about drill
**ordering**, not assertion **shape** — and defers the call here. Recommendation:
add it to the same `AGENTS.md` section as a short separate note rather than a
fifth numbered rule, so the class distinction the record drew is preserved.
Fold-in candidate, not a slice.

**Nit — verification §3's diffstat is stale.** It reports 371 lines / 9 files;
the merged slice is 432 / 11. Honestly labelled ("as measured before this task's
own commit"), and two later commits landed after the capture, so it is
disclosed rather than wrong — but a reader comparing it to `git diff --stat
927251e bd5e042` will find a mismatch.

---

# Recommendation (skill Mode 2)

Map pass first (its output is the updated arc file): Slice 51 was a **debt
slice** and consumed **no map node** — the same shape as the process slice 48.
Nothing it shipped touched wrap feasibility, so nodes 3–9 and fork V stand
unrevised and un-relearned. The next step is **topological**, not a fork: node 3
(y→row) is the next criterion-3 analog behind node 2, and the first genuine fork
remains node 8 (host order) / fork V.

### Scoreboard delta

**None — by design.** Slice 51 advanced no brief criterion; the debt route was
chosen with that explicitly stated at selection time (arc decision log,
2026-08-06). No criterion status changes, and no evidence link moves.

Still open or partial:

| # | Criterion | Status |
|---|---|---|
| 1 | Width change does not recompute the document | partial — core half retired (Slice 50); `done` gated on fork V (the exact reindex is Ω(N)) |
| 2 | Core memory not linear with wrap on; `--memory-shape` extended | open |
| 3 | Wrap-aware query analogs + ∞ equivalence | partial — per-line + whole-document equivalence proven, `compute` analog shipped; **y→row** and **point→(row,cell)** remain |
| 4 | 100k+/10 MB wrapped scroll inside budgets + blocking wrap gates | open |
| 5 | Incremental edits under wrap inside frame-hot-path budgets | open |
| 6 | Thin iOS + browser verification hosts | open |

### Debt ledger delta

**Discharged (4)** — all four scheduled items, with links:

- **D-1** (P2) → `discharged`: `WASM_BUNDLE_STATE` + `bundle_installed_ok` +
  precheck row 5 + the truthful message. Both escalated P2s from slice 47 are
  now closed by scheduling, not by a fourth defer.
- **D-2** (P2) → `discharged`: four conventions in `AGENTS.md`, demonstrably
  applied to this slice's plan (audited above).
- **D-3** (P3) → `discharged`: per-attempt logfiles + one labelled tail per
  attempt.
- **D-6** (P3) → `discharged`: the two-array classification with partition and
  coverage enforcement.

**Amended (1):** **D-15** — statement corrected; its stated trigger cannot fire
under the sibling scripts' `set -e` (P3 #1, measured). Stays open at P3 as a
consistency nit.

**New (1):** **D-16** (P3, `accepted-risk`) — the coverage check does not strip
**string literals**, so a function name inside a quoted assertion label would
count as a reference. Deliberate (spec Decision 8: a shell-grade string parser
costs more than the leak is worth, and the partition check still forces
classification either way); recorded so the accepted residual is visible rather
than only living in a design document. Trigger to revisit: the first assertion
label that equals a function name.

**Counts after this review:** 16 rows — 2 discharged this slice's predecessors
aside, the live picture is **3 open P2s** (D-7, D-8, D-9 — *all* carrying
`deferred(user, …)`), **5 open P3s** (D-10, D-11, D-13, D-14, D-15), 1 deferred
P3 (D-5), 2 `accepted-risk` (D-4, D-16), 5 discharged (D-1, D-2, D-3, D-6,
D-12).

**Escalation rule:** no P2 is in an illegal state — D-7/D-8/D-9 all carry
`deferred(user, date)`, which the rule accepts. But two of those defers are
**aging**: D-7 was re-affirmed 2026-08-06 at this slice's selection and is
fresh, while **D-8 and D-9 have been deferred since 2026-07-22 with three
completed slices since (49, 50, 51)** and no re-observation. They therefore
appear under Candidate options for a re-affirm-or-schedule, so the defer stays
an explicit decision rather than decaying into silence.

### Falsifiability audit

Seventeen standing guarantees added or changed. Every one now has evidence it
can fail; **fifteen** carried it into the slice, and **two** were supplied by
this review (marked ⚠) — which is why they are also P3 #2 above.

| Guarantee | Evidence it can fail |
|---|---|
| `wasm_install_precheck` row 5 | Revert the row → `precheck_installed_bundle_reports_unresolved` |
| Drift wiring records `bundle_installed_ok` | Delete the recording → `drift_state_recorded expected=bundle_installed_ok actual=` |
| Truthful short-circuit message | Swap the printed string, and separately delete the branch → both `drift_message_truthful` |
| Per-attempt install logfiles | Revert to one shared logfile → `ladder_recover_attempt1_log … actual=missing` |
| One labelled tail per attempt | Delete the tail loop → `ladder_exhaust_tail_count expected=3 actual=0` |
| `run_scenario` propagates subshell status (**meta**) | Break an assert *inside* a scenario → `rc=1`, `self_test=fail` |
| Partition, direction 1 (unclassified) | Append an unclassified function → `classified_<name> expected=1 actual=0` |
| Partition, direction 2 (phantom) | Add a name for no function → `covered_defined_<name> actual=missing` |
| Coverage, **token** not substring | Classify `resolve_wasm_sdk_id` covered → red despite `resolve_wasm_sdk_id_from_list` ×4 |
| Coverage, comments stripped | Move a sole call into a comment → `covered_but_unreferenced` |
| Exempt entries carry a justification | Strip the TAB + reason → `exempt_justified_<name>` |
| `defined_functions` sees every declaration form | Recorded red `actual=plain_form outer_form`; six per-form mutations red; nested definitions still excluded |
| `tmp_root_unavailable` fails closed | Point `mktemp -d` at a nonexistent parent → `self_test=fail label=tmp_root_unavailable`, exit 1 |
| `ScriptSelfTestTests` exit-status assertion | Inject a failure in `derive-gate-budgets.sh` → red with output attached |
| `ScriptSelfTestTests` `self_test=fail`-absent assertion | Same drill: fires as its own third failure — the swallowed-subshell catcher |
| ⚠ `testTableCoversEveryScriptWithASelfTest` | **Drilled here:** add an unenrolled `zz-probe.sh` with `--self-test` → red, listing the extra script |
| ⚠ `usage` documents `--self-test` | **Drilled here:** rename the flag in the usage text → `usage_documents_self_test expected=documented actual=missing`. (A first attempt at this mutation edited the wrong line and passed — worth recording, because a mutation that misses looks exactly like a guarantee that cannot fail.) |

No guarantee is left without a red, so **no mandatory candidate option** is
spawned.

### Candidate options

**Option A — node 3: the y→row wrap-aware inverse query (LEAN, topological).**
Advances **criterion 3** (the next query analog behind node 2 — `lineAt`'s
mirror over the visual-row axis). Sits at map node 3, the forced next step;
node 4 (point→(row,cell)) is behind it. Natural fold-in: **D-13** (per-axis
binary-search triplication) — node 3 adds another inverse search on the
visual-row axis, so it is the slice where a shared generic helper either
happens or becomes a fourth copy. Cost: a normal feature slice. This is the
step the map has pointed at since the Slice 50 review, deferred once by the
user's debt-route call, which is now paid.

**Option B — finish the script-hardening job: D-14 (+ the D-15 consistency
nit).** Extend the classification pin to the other three scripts, and align
their dispatchers. Advances **no criterion**; discharges D-14 and D-15. Sits
off the map entirely. Honest assessment: D-14 is a genuine half-measure — three
scripts gained enforcement without classification — but the measured severity is
low (all three are far smaller than `cross-target-compile.sh`, and their
self-tests now fail the build), and two consecutive off-map slices would leave
the wrap arc untouched since 2026-07-25.

**Option C — re-affirm or schedule the aging defers, D-8 and D-9.** **D-8**
(bulk-edit absolute backstop) cannot be scheduled without a product decision:
what latency target a bulk paste / range delete should hold, given it may
legitimately span more than one frame. **D-9** (p95 thin axis) is a watch-item
that was expected to self-heal as pre-slice-45 rows age out of the N=20 window —
that prediction is now testable and has never been checked. Neither is urgent;
both have been deferred for three completed slices without re-observation.

**Route.** The next step is topological, not a fork, so per the checklist this
is a **selection, not a product call**: **Option A, node 3**, with D-13 as a
fold-in candidate and P3 #4's drill-ordering note folded into `AGENTS.md`
alongside it. The user can override.

One thing genuinely needs a user answer regardless of that selection, and it is
Option C's first half: **D-8 needs a product target before it can ever be
scheduled.** A re-affirmation ("keep deferring") is a complete answer — the
point is that it be said, not that it be acted on.
