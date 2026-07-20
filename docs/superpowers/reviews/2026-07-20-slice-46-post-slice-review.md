# Slice 46 Post-Slice Review

The last observational success criterion is now enforced — and the slice found that
it was never even observed. Slice 46 turns the **WASM cross-target compile** into a
merge-blocking CI gate, symmetric to the already-blocking iOS job: both WASM kinds
(`wasm`, `wasm-embedded`) for both packages (`TextEngineCore`,
`TextEngineReferenceProviders`) now cross-compile against a swift.org 6.2.1 Swift SDK
pinned by URL + sha256, provisioned with a checksum-verified bounded-retry install,
and **fail-closed**: a provisioning failure reddens the job rather than skipping
quietly. Blocking is **per-kind**, so demoting embedded WASM is a one-flag config flip
rather than new code.

The load-bearing discovery is in the spec's Background section and deserves top
billing: the WASM job was not merely observational, it **compiled nothing at all**.
`swift:6.2.1-bookworm` ships no WASM SDK, the workflow provisioned none, so
`prepare_wasm_sdk` recorded `skip=sdk_unavailable` for all four pairs — and
`compile_wasm_package_for_kind` hard-coded `LAST_BLOCKING="false"`, so the job was
structurally incapable of failing. Brief criterion #6 («Компилируется без изменений
под iOS и **WASM**») has been documented as "proven locally, observed in CI" for the
life of the project while hosted CI verified it **zero times**. This slice is the
first hosted evidence that the core and the reference providers compile for WASM at
all.

Merged as `1a14fc8` (PR #105); the AC7 post-merge proof was discharged in the
docs-only follow-up `192f44f` (PR #106, merged as `c5ce1e0` = current `main`). This
review was written against merged `main` at `c5ce1e0`, re-running the local
verification independently, **re-reproducing both new pins' break→red→revert→green
cycles on the merged tree** rather than trusting the recorded transcripts, and
spot-checking all six hosted runs at job **and** step level.

## Scope Reviewed

- `.github/scripts/cross-target-compile.sh` — the header contract comment; three new
  pure helpers (`sdk_install_display`, `wasm_kind_blocking`, `wasm_skip_result`); the
  `swift_sdk_install_retry` bounded-retry wrapper with install-time measurement;
  `prepare_wasm_sdk` rewritten to a single shared URL + checksum with a
  `WASM_BUNDLE_INSTALL_FAILED` short-circuit; `compile_wasm_package_for_kind` losing
  its hard-coded `LAST_BLOCKING="false"`; the extended `run_self_test`; the new
  `Environment:` usage block.
- `.github/workflows/swift-ci.yml` — the WASM step renamed `Observe …` → `Compile …`
  (a step name is not a required context, so this is free) and given the pinned
  `CROSS_TARGET_WASM_SDK_URL` / `CROSS_TARGET_WASM_SDK_CHECKSUM` env. **Five changed
  lines total.**
- `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` — `hostJobSteps()`
  generalized into `jobSteps(_:)` + `jobLines(_:)` + `jobLevelValue(of:jobKey:)`; the
  step parser taught to model `env:`; three new tests
  (`testWasmCompileStepIsBlockingShaped`,
  `testWasmCompileStepEnvIsExactlyThePinnedSdk`,
  `testWasmContainerVersionMatchesPinnedSdkURL`). 6 → 9 methods; suite 311 → 314.
- `AGENTS.md` — hard constraint #4, Package-layout, Commands, the CI job description
  (including the explicit "Known wart" note about the deferred rename), and the local
  WASM-build paragraph.
- The spec, plan, and verification record; the AC7 discharge edit.

Out of review scope because the slice did not touch them — confirmed by
`git diff --name-only ffc932b 1a14fc8 -- Sources/ docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv .github/scripts/derive-gate-budgets.sh .github/scripts/harvest-gate-corpus.sh`
→ **empty**: `Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`, every
budget literal, the corpus TSV, and both calibration scripts. The whole changed set is
exactly seven files: the compile script, the workflow, the workflow-shape test,
`AGENTS.md`, and the three slice docs.

## Product Brief Alignment

- **Criterion #6 («Компилируется без изменений под iOS и WASM»)** — *converted from
  asserted to verified.* This is the slice's entire point and it lands. Four
  `result=pass reason=none blocking=true` lines per run, across two kinds and two
  packages, on merged `main`. iOS was already blocking; WASM now matches, and the six
  success criteria have no observational holdouts left.
- **«без изменений в source code»** — the invariant is now *evidenced* rather than
  assumed. Embedded Swift is experimental and the spec budgeted a whole fallback
  ladder for it; it compiled clean on the first hosted attempt for both packages with
  **zero engine or provider source changed**. The confinement diff proves the "no
  source changes" clause literally, which no prior slice could.
- **Foundation-free core** — holds trivially; no `Sources/` file changed. Re-ran
  `rg -n Foundation Sources/TextEngineCore` on `c5ce1e0`: empty, `exit=1`. (The
  `import Foundation` in `WorkflowShapeTests` is pre-existing and is how the test
  reads YAML off disk.)
- **Swift Embedded compatible** — materially strengthened. `wasm-embedded` is the
  Embedded Swift variant, so this is the first *continuous* enforcement of constraint
  #2 rather than a local spot-check.
- **Zero-dependency** — holds. No package added; the rejected alternative (a custom
  prebaked container image) would have added a registry dependency and was correctly
  declined.
- **Memory/virtualization and perf invariants** — untouched and not in scope; the 46
  `gate=pass` tally is byte-identical to Slice 45's, as it must be for a slice that
  moved no budget.

## Delivered Design

### Fail-closed is the correct and load-bearing call

Decision 4 turns `sdk_unavailable`, `sdk_install_failed`,
`sdk_unresolved_after_install`, and checksum mismatch into `fail:true` for the WASM
pairs. This is the difference between a gate and a decoration: without it, the gate
disarms **exactly when provisioning breaks**, which is the Slice-16 dead-step trap in
a different costume. The tradeoff is real and correctly accepted in the spec — a
download.swift.org outage can redden a clean tree — and mitigated by the bounded
retry. Honest red beats silent green.

Both halves were proven **live in hosted CI**, which is what elevates this above
assertion: run `29701333581` (corrupted checksum → four `reason=sdk_install_failed
blocking=true`, `exit=1`) and run `29701547123` (bogus compile target → four
`reason=compile_failed blocking=true`, `exit=1`). In both, the host and iOS jobs
stayed green, confirming the fault is scoped to the job that owns it.

### The per-kind seam earns its keep before it is needed

Decision 1 introduces `wasm_kind_blocking` up front rather than after embedded proves
flaky, on the reasoning that writing per-kind branching mid-slice — at the moment you
have just discovered a problem — is the worst time to design it. Embedded then
compiled clean and the ladder was never engaged. That is the right outcome and the
seam was still correct to build: it is three lines, it is self-tested, and it converts
a future SDK regression from a code change into an env flip. Building the escape hatch
you end up not needing is cheap insurance, not waste.

### One bundle, two SDKs — and the plan's guess was corrected by evidence

The spec's feasibility probe established that one artifactbundle installs both
`_wasm` and `_wasm-embedded` ids, so a single checksum-verified install provisions
both kinds. The plan's prose guessed the ids would be `swift-6.2.1_wasm`; the real
ids carry `-RELEASE` (`swift-6.2.1-RELEASE_wasm`). The verification record calls this
out explicitly rather than quietly using the right value — good discipline, and the
kind of small honesty that makes the rest of a record trustworthy.

### The checksum's provenance is stated honestly, including its limit

The record does not overclaim: swift.org's `.sha256` sidecar 404s, so there is no
second hosted file to diff against, and the provenance is "TLS download from the
official host, recomputed locally" — exactly the trust `swift sdk install --checksum`
itself enforces. It then notes that liveness run `29701333581` independently
reconfirms the value, because Swift's installer printed the *real* computed checksum
while rejecting the corrupted pin. Deriving a trust anchor from a failure run is a
neat and genuinely convincing move.

### The caching decision was made from data, not deferred by default

Decision 7 refused to pre-defer caching and instead bound it to a measurement. The
answer came back 5–6s against a 1200s budget (~0.4–0.5%), always `attempts=1`, now
across **five** runs (5/5/6/6/5). Skipping `actions/cache` — with its known
in-`container:` finickiness — is clearly right on that evidence, and the numbers are
recorded so a future reader can re-litigate it without re-measuring.

### Governance deferral is correctly reasoned

Decision 5 keeps the job/context name `WASM cross-target observation` and leaves the
`Main` ruleset untouched, so WASM becomes blocking under the existing required
context with **no ruleset change at all**. I verified via `gh api` that the ruleset
still requires exactly the three original contexts. Coupling the rename here would
have taken a genuine ordering hazard (rename and ruleset update must land together or
the old context goes permanently unreported and PRs wedge) into an otherwise pure
portability slice, against AGENTS.md's explicit "repo-policy work gets its own slice."
The cost — a job named "observation" that blocks — is called out in AGENTS.md with an
unusually direct instruction ("Do not rename it as a drive-by edit"), which is the
right way to leave deliberate debt. See P2 #5 for why it should not sit long.

## The Review Round Materially Improved the Slice

Four issues were raised in review after the implementation was otherwise complete;
all four were fixed on-branch before merge. One was serious.

**The P1 — a silently disarmable gate.** `WorkflowShapeTests.parseStep` did not model
`env:` at all, so adding `CROSS_TARGET_WASM_EMBEDDED_BLOCKING: "false"` to the WASM
step's env demoted embedded WASM from blocking to observational **with the entire
suite green**. Half the gate could be disarmed by a one-line YAML edit that no test
could see. `0de1ef6` fixes it by teaching the parser `env:` and pinning the step's env
dict to *exactly* the URL/checksum pair.

The fix is better than the minimum in four ways worth recording: it uses **exact
dictionary equality** (catching added, removed, *and* altered keys, not just the one
key we thought of); it strips surrounding quotes so `"false"` cannot slip through on
quoting style; it splits on the **first** `:` only, so the URL's `://` is not sheared
apart; and it hoists the URL/checksum into shared constants read by both new tests
rather than duplicating literals — avoiding exactly the `afterStepName` duplication
that Slice 45's review flagged as P3 #7. The test comment also records the negative
control ("verified before this test existed: adding the key left all tests green"),
which is what makes the pin's value legible to a future reader.

I re-proved it live on merged `main`: injecting the quoted `"false"` fails exactly one
of nine methods, naming the key and explaining the consequence; revert restores green;
tree byte-clean.

**The container cross-pin (`0de1ef6`).** `container: swift:6.2.1-bookworm` and the
pinned URL's `swift-6.2.1-RELEASE` must move together, and nothing enforced it. Drift
already failed closed at runtime, but as `sdk_unresolved_after_install` — a reason
string that does not read as "you bumped the container without bumping the SDK." The
new `testWasmContainerVersionMatchesPinnedSdkURL` pins the relationship at
`swift test` time, explicitly modelled on `testWindowConstantMatchesDeriveScript`.
Re-proved live on merged `main` (bumping only the container tag to `6.3.3` fails
exactly that one test with a message naming both values). This is the repo's
cross-pinning culture applied to a new pair, and it is the right instinct.

**The double retry ladder (`4dd7111`).** `prepare_wasm_sdk` runs per kind, so a
definitive install failure burned two full 3-attempt ladders (~21s, visible as six
`warn=sdk_install_attempt_failed` lines in run `29701333581`), doubling time-to-red on
a real outage. Fixed by recording the failure once in `WASM_BUNDLE_INSTALL_FAILED` and
short-circuiting the second kind to
`cross_target_sdk_install_skipped … reason=bundle_install_already_failed`. I
reproduced the fix locally with a bogus URL: **3** attempt lines, short-circuit line
present, and still `blocking_failures=4 exit=1` — the speed-up did not erode
fail-closed.

**The doc corrections (`9ee33f0`, `7ad1839`).** AGENTS.md now states that
`--targets wasm` without the env and without a matching installed SDK is a **hard
red**, not a quiet skip, and — going beyond what was asked — that the resolver matches
the *local toolchain version*, so the CI 6.2.1 pin will not resolve on any other
toolchain. `7ad1839` corrects the AC2 transcript from one ladder to six attempts, and
labels itself "Correction to an earlier draft of this record" instead of silently
rewriting. Amending a verification record in the open, with the correction visible, is
exactly the right handling.

## Verification Evidence Reviewed

### Fresh local checks on merged `main` (`c5ce1e0`)

| Check | Result |
|---|---|
| `swift test` | **314 tests, 0 failures** (311 pre-slice + 3 new pins) |
| `./.github/scripts/cross-target-compile.sh --self-test` | `self_test=pass` |
| `bash -n .github/scripts/cross-target-compile.sh` | exit 0 |
| `swift build -c release` | `Build complete!` |
| `rg -n Foundation Sources/TextEngineCore` | empty, **exit=1** |
| confinement diff (engine/provider/budget/corpus/derive/harvest) | **empty** |
| whole changed set (`ffc932b..1a14fc8`) | exactly 7 files |
| `git diff 7ad1839 1a14fc8` | **empty** — the merge introduced no drift |
| pin liveness — env demote (probe A) | RED on `testWasmCompileStepEnvIsExactlyThePinnedSdk` only, 1 of 9 |
| pin liveness — container drift (probe B) | RED on `testWasmContainerVersionMatchesPinnedSdkURL` only, 1 of 9 |
| tree after both probes | **byte-clean** (`git status --short` empty) |
| retry short-circuit (bogus URL, local) | 3 attempts (not 6), short-circuit line, `blocking_failures=4 exit=1` |

### Hosted runs (all six, read at step level)

| Run | Commit | Purpose | Result |
|---|---|---|---|
| `29701110835` | `3457a8e` | spike | green; 4 pass; install 5s/1 |
| `29701333581` | `d732bf3` | **AC2 liveness** | **red**; 4 `sdk_install_failed blocking=true`; `exit=1` |
| `29701547123` | `388678f` | **AC3 liveness** | **red**; 4 `compile_failed blocking=true`; `exit=1`; install 5s/1 |
| `29701773264` | `3457a8e` | green at pre-review tip | green; 4 pass; install 6s/1 |
| `29704646269` | `7ad1839` | **merge candidate** | green; 4 pass; install 6s/1; 46 `gate=pass`; 314/0 |
| `29727064661` | `1a14fc8` | **post-merge push (AC7 anchor)** | green; 4 pass; install 5s/1; 46 `gate=pass`; 314/0 |

I confirmed every row independently — job conclusions via `gh api`, and the WASM
per-target lines, SDK ids, install timings, and host tallies by reading the logs. The
two red runs are the evidence that this gate can fail, which is what distinguishes it
from the green no-op it replaced.

A note on the merge-candidate row: the verification record originally called
`29701773264` @ `3457a8e` "the current branch HEAD," but the review round moved the
tip to `7ad1839`, and `4dd7111` changed the compile script — so that run no longer
covered the merged code. PR #106 corrected this rather than leaving it stale, and
recorded `29704646269` @ `7ad1839` as the actual merge-candidate proof. Catching a
stale "final green run" claim is precisely the sort of drift a post-merge pass exists
to find.

### AC coverage

AC1, AC2, AC3, AC5, AC6, AC7, AC8, AC9 are all discharged with evidence I re-verified.
**AC4** is discharged in substance but its record slightly overstates its coverage —
see P3 #1.

## Git History

Seventeen commits: three docs (design, spec refinement, plan), two `feat:` (retry +
checksum install; the blocking/fail-closed flip), one `ci:` (the workflow pin), four
`test:`/`fix:` across the implementation and review rounds, and seven `docs:` for
comment de-rotting, the verification record, and the review corrections. Conventional
prefixes throughout, one logical step per commit, and — notably — the review-round
fixes are separate, individually-messaged commits (`0de1ef6`, `4dd7111`, `9ee33f0`,
`7ad1839`) rather than an amend or a squash, so the review's effect on the slice is
legible in history. `4dd7111`'s message states the concrete consequence ("burning 6
attempts instead of 3 and doubling the time to a red build") rather than the change
alone. Good practice.

## Code Review Findings

### P0 / Release Blockers

**None.** The slice is merged; all three required jobs are green at step level on the
post-merge push run; both hard constraints hold (Foundation-free, zero
engine/provider/budget/corpus diff); all four WASM pairs compile `blocking=true`; the
gate is proven able to fail on both the provisioning and compile axes; and all three
new pins are demonstrably live on the merged tree.

### P1 / Must Fix Before Merge

**None outstanding.** The one P1-class defect found in review — the silently
disarmable `env:` path — was fixed in `0de1ef6` before merge and its pin re-proved
live for this review.

### P2 / Production Readiness

**P2 #5 (NEW): the job/context name now actively misleads, and the fix is
order-sensitive.** `WASM cross-target observation` is a required check that blocks.
Anyone reading the checks on a PR, or the ruleset, will conclude WASM is advisory when
it is load-bearing. The deferral is well-reasoned (Decision 5) and AGENTS.md documents
it prominently, but this is the one item whose cost **grows with time**: every
subsequent doc, review, and memory entry accretes around the wrong name, and the
rename must land in the same change as the `gh api` ruleset update or the old context
goes permanently unreported and PRs wedge. It is small, decision-free, and should be
scheduled soon rather than allowed to become permanent furniture. This is the slice's
own named follow-up.

**P2 #3 (carried from Slice 42→45): harvester provenance gap.**
`harvest-gate-corpus.sh` still selects rows by run id alone, with no
`conclusion`/`event`/fork check, so a fork PR's run could in principle print fabricated
`p95_ns=` lines that a later harvest ingests. Still the **only unverified link in the
calibration chain** now under twelve blocking budgets. Untouched this slice (correctly
— it is unrelated to portability), and it remains the standing recommendation from
Slice 45.

**P2 #1 (carried from Slice 43→45): bulk-edit absolute backstop.**
`bulk_structural_mutation` remains exempt from the absolute product ceiling. Correct
scope, real recorded gap, needs a product-target decision. Untouched; carries.

**P2 #4 (carried from Slice 41→45): p95 thin axis / realistic shape transition.**
Unchanged by this slice, which moved no budget and no corpus row. Carries; self-heals.

### P3 / Minor But Valid

**P3 #1 (NEW): AC4's record overstates its test coverage.** The verification doc says
version drift "is already covered by the existing `wasm_skip_result`/
`count_blocking_failures` self-tests." Those cover the *generic* `skip → fail` mapping
and the resolver's miss cases — not a drift scenario end-to-end. The fail-closed
*behavior* is real and structurally guaranteed (resolve-by-detected-version yields
`sdk_unresolved_after_install`, which is now `fail`), and the spec explicitly made the
explicit `version_mismatch` guard optional, so AC4 is satisfied. Only the coverage
claim is a shade stronger than the evidence. Also now substantially mitigated by
`testWasmContainerVersionMatchesPinnedSdkURL`, which catches the realistic drift
trigger before CI ever runs.

**P3 #2 (NEW): the version-drift path still double-installs.** The
`sdk_unresolved_after_install` branch (`cross-target-compile.sh:507-508`) does *not*
set `WASM_BUNDLE_INSTALL_FAILED`. So in the drift scenario — install succeeds, resolve
fails — the second kind re-enters the install branch and runs a full ladder against an
already-installed SDK, and the two kinds report *different* reasons
(`sdk_unresolved_after_install` for `wasm`, `sdk_install_failed` for `wasm_embedded`),
which reads as two unrelated faults. `4dd7111` closed the install-failure path; this
sibling path was not folded in. Always fail-closed, so this is diagnostics and ~6s of
wasted backoff, not a safety hole — and the new container cross-pin makes the scenario
much harder to reach. Low urgency.

**P3 #3 (NEW): `wasm_kind_blocking`'s `*)` default returns `false` — fail-open in a
fail-closed design.** Unreachable today (only two kinds exist and all call sites pass
literals), but a third kind added later would silently default to *observational*,
which is the opposite of this slice's whole thesis. A `*)` that returns `true`, or one
that hard-errors on an unknown kind, would match the design's posture. Trivial to
change; worth doing when that file is next touched.

**P3 #4 (NEW): the retry short-circuit is not reachable by `--self-test`.**
`WASM_BUNDLE_INSTALL_FAILED` lives in the impure `prepare_wasm_sdk`, so the repo's
"pure helpers + `--self-test`" pattern does not cover it; I verified it by live local
run with a bogus URL instead. A small asymmetry — the three new pure helpers *are*
covered — and extracting the short-circuit decision into a pure helper would close it
cheaply.

**P3 #5 (NEW, spec-conformance nit): the rename note landed in a different section
than specified.** The spec's change-set §3 asked for a one-line note in the
**required-check policy paragraph** that a follow-up renames the context. That
paragraph is unchanged; the note instead lives in the CI job description as a
prominent "Known wart" block. The information is present and arguably better placed
(next to the job it describes), so this is satisfied in substance — recorded only so
the discrepancy is not mistaken for an omission later.

**P3 #6 (NEW): the Commands list still shows a bare `--targets wasm` invocation.**
`AGENTS.md`'s Commands block lists
`./.github/scripts/cross-target-compile.sh --targets wasm` with no indication that it
now exits 1 on any machine without the env pin and a version-matching installed SDK. I
confirmed this on a 6.2.4 toolchain: `exit=1`, four `result=fail
reason=sdk_unavailable blocking=true`. The prose two sections down explains it fully,
so a reader who reads on is fine — but the command list is the part people copy.

**P3 #7 (carried from Slice 43→45, now third slice): the two frozen `580 µs` sites.**
`Sources/ViewportBenchmarks/BenchmarkModels.swift:145` and `AGENTS.md:365` still quote
the frozen number. Slice 46 edited `AGENTS.md` in **five** places and did not fold
line 365. The "fold rotting quotes in the file you're already in" lesson has now gone
unapplied for three consecutive slices, which suggests it needs to become a checklist
item rather than a lesson.

**P3 #8 (carried, recurring): plan checkboxes.** 0 of 40 steps checked in the
committed plan though the work shipped. Commit messages are the completion evidence.
Unchanged from prior slices.

**P3 #9 (carried from Slice 45): `derivedBudgets(fromScriptOutput:)` has no isolated
fixture test.** Out of scope; carries.

**Non-finding (recorded for completeness).** Deleting the SDK URL/checksum env would
*not* silently disarm the gate — it yields `sdk_unavailable` → `fail` → red. Only the
*additive* env path (`CROSS_TARGET_WASM_EMBEDDED_BLOCKING`) was dangerous, which is
precisely why the miss was easy: the obvious direction was already safe. Worth keeping
in mind as a review heuristic rather than as a defect.

## Risks And Gaps

- **The misleading required-check name (P2 #5)** — the freshest debt, order-sensitive
  to fix, and the only one that worsens with delay.
- **download.swift.org is now in the merge path** — accepted, mitigated by the bounded
  retry, and evidenced as fast and steady (5–6s, `attempts=1`, five runs). A genuine
  outage will redden clean trees; that is the designed tradeoff, not a defect.
- **Toolchain-bump coupling** — a container bump now requires a matching SDK
  URL+checksum bump. Guarded at `swift test` time by the new cross-pin, and fail-closed
  at runtime regardless. Well handled.
- **Harvester provenance (P2 #3)** — unchanged; the single unverified link under twelve
  blocking budgets.
- **Bulk-edit absolute backstop (P2 #1)** — unchanged; needs a product decision.
- **Fail-open `*)` default (P3 #3)** and **drift-path double install (P3 #2)** — both
  latent, both cheap, both in the same file.
- **Local WASM DX** — the documented bare command now hard-fails without env; explained
  in prose, not at the command (P3 #6).

## Lessons For The Next Slice

- **"Observational" can quietly mean "never ran."** The most valuable thing this slice
  produced was not the gate — it was discovering that the thing everyone believed was
  being observed had executed zero times, for the life of the project, while a hard
  constraint in AGENTS.md described it as verified. When a step is non-blocking, its
  *output* is the only proof it did anything; a green job proves nothing. Audit the
  remaining non-blocking steps for the same shape: does it print evidence it ran, or
  only evidence it exited?
- **A shape pin is only as strong as the fields its parser reads.** `WorkflowShapeTests`
  looked thorough — exact command equality, `continue-on-error`, docs-only guard,
  ordering anchors — and was blind to `env:` because the reader never modelled it. When
  a test asserts "this step is correctly shaped," enumerate what the *runtime* reads
  from that step and check the parser covers all of it.
- **Audit the quieting direction, not just the deleting one.** Removing the SDK pin
  failed loudly; *adding* one env key disarmed half the gate silently. Config surfaces
  are asymmetric that way, and review instinct naturally tests the destructive
  direction. Ask what an *addition* could turn off.
- **Build the escape hatch before you need it, then don't need it.** The per-kind
  blocking seam was designed up front precisely so engaging the embedded fallback would
  never require mid-crisis design work. Embedded then passed clean. The seam cost three
  lines and a self-test, and it is still the right call — the alternative was designing
  a fallback while standing in the failure.
- **Correct a verification record in the open.** `7ad1839` labels itself a correction
  to an earlier draft rather than quietly fixing the number, and PR #106 does the same
  for the stale merge-candidate claim. A record that shows its own corrections is more
  trustworthy than one that has never been wrong.
- **Sub-lesson from discharging AC7: `gh run watch --exit-status` exited 0 after dying
  on a network error.** Success and "I fell over" produced the identical signal — the
  same failure mode this repo's step-level-logs rule exists to prevent, one layer up in
  the tooling. Confirm run state from `gh api .../actions/runs/<id>`.

## Slice 47 Candidate Options

### Option A: the deferred rename + `Main` ruleset update (P2 #5) — recommended

Rename the job/context `WASM cross-target observation` → `WASM cross-target compile`
and update the ruleset's required-status-check context in the **same** change, with a
before/after `gh api` verification note matching
`docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`. Tiny,
decision-free, this slice's own named follow-up, and the only open item whose cost
grows with delay. It also removes an actively wrong signal: a required check named
"observation" that blocks merges.

### Option B: harvester provenance hardening (P2 #3)

Filter harvested runs by `conclusion=success` / expected event / non-fork before
ingesting their `p95_ns=` lines. Still the only unverified link in the calibration
chain, now under twelve blocking budgets, with an existing `--self-test` seam to hang
a standing guard on. Higher consequence than Option A; decision-free; has been the
standing recommendation since Slice 45.

### Option C: bulk-edit absolute budget (P2 #1)

Give `bulk_structural_mutation` its own absolute ceiling. The strongest *product*
step, but it must open with a product-target decision (N frames for a bulk paste), so
it is a product call rather than a cold-start engineering slice.

### Option D: residual fold in `cross-target-compile.sh`

Fold P3 #2 (drift-path double install), P3 #3 (fail-open `*)` default), P3 #4 (pure
helper for the short-circuit), P3 #6 (Commands-list caveat), and the two frozen
`580 µs` sites (P3 #7). All small, all in files this slice already touched. Best
folded opportunistically into Option A, which reopens the same workflow/AGENTS.md
surface.

## Recommended Slice 47 Selection

**Option A — the rename + ruleset update, with Option D's residuals folded in.** It is
this slice's own named follow-up; it is small and needs no product decision; it reopens
exactly the files (`swift-ci.yml`, `AGENTS.md`, `cross-target-compile.sh`) where the
P3 residuals live, so folding them costs almost nothing; and it is the only candidate
that gets *harder and more confusing* the longer it waits, since every new doc and
review entrenches the wrong name. The ordering hazard (rename and ruleset must land
together) is also cheapest to manage now, while the slice is fresh and no unrelated PRs
are in flight.

**Option B (harvester provenance) is the higher-consequence work** and should follow
immediately after. Weighed honestly: B guards a live trust gap under twelve blocking
budgets and A fixes a name — if the user prefers impact over tidiness, take B first and
schedule A right behind it. The recommendation for A rests on it being small, fresh,
self-contained, order-sensitive, and this slice's own debt — not on it being more
important. **Option C** remains the product axis and needs a decision to open.

## Slice 46 Review Conclusion

Slice 46 does what its spec asked and finds something more valuable than it set out to:
brief criterion #6 was not merely under-enforced, it was **never verified in hosted CI
at all**, because the WASM job provisioned no SDK and hard-coded its results
non-blocking. The slice closes that with a pinned, checksum-verified swift.org 6.2.1
bundle, a bounded-retry install, per-kind blocking, and fail-closed provisioning — and
proves the gate can actually fail, live in hosted CI, on **both** the provisioning and
compile axes. Embedded WASM compiled clean with zero engine or provider source changed,
so the brief's "compiles for iOS and WASM without source changes" clause is now
evidenced rather than asserted, and the confinement diff proves it literally. The
review round materially improved the result: a genuinely disarmable gate (the unmodeled
`env:`) was found, reproduced, and fixed with a stronger pin than the minimum, plus a
container↔SDK cross-pin, a retry-ladder fix, and two honest doc corrections. All three
new pins were re-proved live on the merged tree for this review, and the tree left
byte-clean. AC7 is discharged at step level on the post-merge push run
`29727064661` @ `1a14fc8` (three jobs green, four WASM pairs `blocking=true`, 46
`gate=pass`, 314/0). **No P0, no P1.** One new P2 (the misleading required-check name,
deliberate and documented), three carried P2s untouched by scope, and nine P3s — all
minor, four of them latent one-liners in a single file. **READY — merged and verified;
Slice 47 = the deferred rename + ruleset update with the P3 residuals folded in
(Option A), or harvester provenance hardening (Option B) if impact should lead over
tidiness.**
