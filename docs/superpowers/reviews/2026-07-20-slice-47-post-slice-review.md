# Slice 47 Post-Slice Review

**Slice:** 47 — WASM required-check rename, ruleset moved with it
**Date:** 2026-07-20
**Verdict:** **READY** — shipped state correct and coherent. No P0, no P1.
**Merged:** PR #108 → `cdae8d3`; verification PR #109 → `34c7fb1` (current `main`)

This review was written by the agent that executed the slice, with an **independent
adversarial retrospective** dispatched first specifically so the slice was not solely
marking its own homework. Every claim below was reproduced by execution on merged `main`,
by one or both parties. Where the two disagreed or where the executor missed something,
that is stated plainly rather than smoothed over.

## Scope Reviewed

| Artifact | Commit |
|---|---|
| Spec | `3d4b6df`, corrected `9df29a6` |
| Plan | `58b454c` |
| Implementation | `87265d5` … `bb6e67b` (7 commits), merged `cdae8d3` |
| Verification record | `f7af501`, `39294bc`, merged `34c7fb1` |

```
 .github/scripts/cross-target-compile.sh          | 100 +-
 .github/workflows/swift-ci.yml                   |   6 +-
 AGENTS.md                                        |  35 +-
 Sources/ViewportBenchmarks/BenchmarkModels.swift |   6 +-
 Tests/.../WorkflowShapeTests.swift               |  46 +-
```

Plus 1889 lines of spec/plan/verification prose. The functional surface is small; the
governance surface is the slice.

## Product Brief Alignment

The brief's hard constraints are untouched and re-verified on merged `main`: no Foundation
in `Sources/TextEngineCore` (scan empty, exit 1); no engine, provider, budget, corpus, or
calibration-script change; the only `Sources/` edit is one comment in
`BenchmarkModels.swift`, corroborated by all 46 gate checksums being byte-identical.

This slice advances the brief only indirectly — it is repo-policy work, correctly kept in
its own slice per the "keep concerns separate" convention. Its product value is that the
twelfth blocking gate promoted in Slice 46 now *says what it is*, and that a class of
silent drift (job renamed, ruleset forgotten) is now loud at `swift test`.

## Delivered Design

### The wedge was created deliberately and observed, not argued

The strongest artifact in the paper trail. PR #108 opened with all three jobs **reporting
and passing** — including the newly-named `WASM cross-target compile` — and
`mergeStateStatus=BLOCKED`, because the ruleset still required a context nothing reports.
That is a falsifiable demonstration that GitHub matches required checks by exact string,
rather than an assertion that it does.

AC7 is its mirror image: same three jobs, `CLEAN`, mergeable. Together they show the rename
*moved* the requirement rather than merely adding a name.

### The sequence was tight, and the numbers say so

Ruleset history (`/rulesets/17656807/history`) independently corroborates three versions:
3 contexts → 2 (14:58:01Z) → 3-renamed (14:59:05Z).

- **Unrequired window: 64 seconds.** Merge → re-add: **16 seconds.**
- Full before→after diff is **one line** — the context string. `strict_required_status_checks_policy`,
  `bypass_actors`, `enforcement`, and all five rule types byte-identical across all three versions.
- No bypass used, no force-merge, no third-party PR exposed (`gh pr list --state open`
  empty, measured twice before the window and confirmed empty after).

GitHub *saw* the new context reported on a real PR before the ruleset required it. That
ordering is what made a non-atomic change safe.

### The new pin is load-bearing, not theatre

`testJobNamesMatchRequiredCheckContexts` compares the workflow against **hardcoded
literals**, unlike every sibling guard in `WorkflowShapeTests.swift`, which cross-checks two
repo artifacts. That asymmetry is *forced, not sloppy*: the counterparty is GitHub
configuration outside the repository, and `swift test` has no network.

It genuinely fails on the realistic edits: renaming a job's `name:` alone; deleting `name:`
(which would silently switch the reported context to the job key); renaming or removing a
job key. Broken deliberately during the slice, it produced exactly one failing method with
a runnable `gh api` command in the message.

**Its limitation is stated honestly and in three places** — the test's own comment,
`AGENTS.md:153-161`, and the verification record: it makes the repository half loud; it does
not prove the pair agrees. Rename the job *and* the table together while forgetting the
ruleset, and it still passes. Given the incentive to dress a new guard as stronger than it
is, conceding this prominently was the right call.

### Making `wasm_install_precheck` pure was the right refactor

It converts a path Slice 46 could reach *only* with a live bogus-URL network run into five
offline `--self-test` assertions. The whole-branch reviewer additionally exercised the drift
path live by stubbing `swift` on `PATH` (version 6.2.1, `sdk install` succeeds, `sdk list`
empty) — a path Slice 46 never exercised at all.

The comment at `cross-target-compile.sh:370-379` documents the assertion's *own* blind spot
(`assert_equal` compares printed values and cannot see an exit status, so a helper that
errors while still printing `true` passes unnoticed). A test documenting where it is blind
is rare and worth keeping.

## Verification Evidence Reviewed

Reproduced on merged `main` (`34c7fb1`), independently, not read from the record:

| Check | Claimed | Observed |
|---|---|---|
| `swift test` | 315 / 0 | **315 / 0** |
| `swift build -c release` | Build complete | **Build complete** |
| 12 blocking gates | 46 `gate=pass`, 0 fail | **46 / 0** |
| Gate checksums | 46, byte-identical | **46, identical** |
| `--self-test` | pass | **pass** |
| Foundation scan | empty | **empty, exit 1** |
| Fail-closed, no SDK | `exit=1` | **`blocking_failures=4 exit=1`** |
| AC1 sweep | 1 hit at `AGENTS.md:316` | **exactly 1** |
| Runs `29750898846` / `29751576859` / `29753085265` / `29753701084` | success | **all four reproduce** |

**Fail-closed traced exhaustively on merged `main`: no path yields exit 0 on a WASM
failure.** Every skip reason routes through `wasm_skip_result` → `fail` on a blocking kind →
counted; unknown kind hard-exits at both dispatch sites, neither inside a command
substitution. `CROSS_TARGET_WASM_EMBEDDED_BLOCKING` demotes only on exact `"false"` —
`"0"` and `"FALSE"` stay blocking.

## Code Review Findings

### P0 / Release Blockers

**None.**

### P1 / Must Fix Before Merge

**None.**

### P2 / Production Readiness

#### P2 #1 — The drift short-circuit records only *failure*, so asymmetric drift is still misdiagnosed — in the very function this slice rewrote

`.github/scripts/cross-target-compile.sh:556-574`. `WASM_BUNDLE_FAILED_REASON` is written in
the install-failure arm (`:567`) and the unresolved-after-install arm (`:574`) — **never on
success**.

The happy path is fine: a `resolve_wasm_sdk_id` guard at `:543` runs *before* the install
branch, so once kind 1 installs the bundle, kind 2 resolves immediately and never re-enters.
The comment at `:544-547` is accurate, and hosted logs confirm one `install_seconds` line.

The failure is **asymmetric drift**:

1. Bundle installs. `wasm` resolves. Success → **nothing recorded**.
2. `wasm_embedded`'s outer resolve at `:543` fails (bundle lacks the embedded id).
3. Precheck reads `WASM_BUNDLE_FAILED_REASON=""` → returns `""` → falls through.
4. Full bounded-retry ladder re-runs against an **already-installed** bundle.
5. `swift sdk install` rejects the duplicate → reported reason is **`sdk_install_failed`**,
   when the truth is `sdk_unresolved_after_install`.

This is the same class of misleading reason the slice's own P3 #2 fix targeted — closed for
failure→failure, left open for success→drift. It is also precisely the "asymmetric SDK
drift" item carried from Slice 46, so **the slice touched this function without closing the
debt attached to it**. Latent under the current pin (the 6.2.1 bundle provides both ids),
but it fires exactly on the SDK-drift scenario the fail-closed design exists to diagnose,
and burns three retries plus backoff doing it.

**Fix:** give the precheck a third state (e.g. `bundle_installed_ok`) recorded on a
successful shared install, so a second kind skips the *install* while still letting its
*resolve* fail honestly.

#### P2 #2 — The plan's own assertions are near-universally non-failing

A mechanical audit of all ~1188 plan lines for **exit semantics** found **4 unpassable and
12 decorative** assertion sites. Two of the four were caught in flight and adjudicated; two
were not. The material additions beyond the already-known ones:

- **`$SCRATCH` is never assigned in any executable block** — defined only in prose (plan
  `:68`) but used at 23 command sites. Each Bash invocation is a fresh shell, so
  `> "$SCRATCH/after-checksums.txt"` would resolve to `/after-checksums.txt`. The executor
  exported it per-call and never hit this; a literal executor would have.
- **Task 8 Step 2** (plan `:881-886`): AC2 demands the failure message contain the ruleset id
  **and** the `gh api` command, but the message embeds a newline before the `gh api` line,
  which the step's own `rg` filter strips. The evidence AC2 requires is unreachable through
  the plan's own command. Also `sed -i ''` exits 0 on zero matches, so a no-op "break it"
  step is indistinguishable from a real one.
- **The no-open-PRs precondition** (plan `:62`, `:934`) — on which Decision 1's entire
  zero-blast-radius argument rests — is `gh pr list --state open`, which exits 0 on empty
  *and* populated lists. Purely eyeballed.
- **Task 9 Step 7** (plan `:1094-1099`), the final AC4 safety assertion, carries no
  assertion at all: a non-empty diff is *expected*, so `diff`'s exit is meaningless, and
  unlike its sound sibling at `:1032-1038` there is no `&&`-gated success message.
  "Exactly one context differs" and "`bypass_actors` wiped by the PUT" are mechanically
  indistinguishable.

Only **13** sites in the whole plan carry discriminating exit semantics, and every one is
*inherited* (`--self-test`, `bash -n`, an unpiped `swift build`, the one correct
`diff <() <() && echo`). **Every gate the plan placed on its own correctness was eyeballed.**

The shipped state is nonetheless correct — human judgment caught what the plan could not.
But that is a dependency on executor alertness, which is not a control. See *Lessons*.

### P3 / Minor But Valid

1. **Verification record staleness** — records PR #109 as `state=OPEN mergeStateStatus=CLEAN`;
   it is now MERGED (`34c7fb1`). Accurate when written, stale today. **Corrected in this PR.**
2. **Verification record internal inconsistency** — header says "Implementation HEAD:
   `38ac4e4`" and the commit table ends there, but the commit actually merged is `bb6e67b`,
   which the record itself names correctly later at AC5. **Corrected in this PR.**
3. **AC7 evidence head mismatch** — run `29753701084` is at head `f7af501`; PR #109's merged
   head is `39294bc`. The record states no SHA, so nothing asserted is false, but the
   enforcement evidence comes from an earlier head than the one that landed.
4. **`AGENTS.md:320-321`** still cites `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`
   as a live "see" reference. That file carries the old context name at 9+ sites with no
   superseded banner; a reader following the pointer for *current* policy finds
   `WASM cross-target observation` in ruleset JSON.
5. **The pin models only `name:`** (`WorkflowShapeTests.swift:37, 493`). GitHub's reported
   context also depends on job-level `strategy:` (a matrix job reports `name (values)`) and
   job-level `if:` (a job that never runs never reports). Neither exists today — verified: no
   job-level `strategy:`/`if:`, three jobs, three table rows. Forward risk only, but it is
   the repo's own recorded lesson *"pins must model what runtime reads"* recurring. The
   table also does not pin the job *set*, so a fourth required job would leave it silently
   incomplete.
6. **Retry logfile overwrite** (`:515-530`) — each attempt writes the same `"$logfile"`, so
   `print_log_tail` shows only the last attempt. Unchanged carried debt; the slice worked in
   this function's neighbourhood without addressing it.

## Risks And Gaps

| Risk | Status |
|---|---|
| Asymmetric SDK drift → wrong reason + wasted ladder | **open** (P2 #1); slice touched the function without closing it |
| Retry logfile overwrite | open, unchanged |
| Shell-purity exemption set unpinned (prose only) | open; the `flagName` exemption pattern in `WorkflowShapeTests.swift:21` is the model to copy |
| Container ↔ SDK pin coupling | *mitigated* — `testWasmContainerVersionMatchesPinnedSdkURL` exists and passes |
| Ruleset ↔ workflow agreement | structurally unverifiable offline; the pin covers the repo half only, and says so |
| Bypass actor (`RepositoryRole` id 5, `bypass_mode: always`) | preserved deliberately; an admin can still override every required check |
| Job-context shape beyond `name:` (matrix / `if:`) | unmodeled (P3 #5) |

## Lessons For The Next Slice

**The repo has a mature culture of making *runtime* checks fail loudly, and no equivalent
discipline for its own *plans*.**

Twelve blocking gates; "a `continue-on-error` step cannot be a gate"; "read step logs, not
job conclusion"; `isGateable` as an exhaustive switch never a deny-list; tests that fail on
an empty match set so a deleted step cannot pass vacuously — all of that rigor stops at the
plan file, where 16 of 29 assertion sites cannot fail and 4 cannot pass. The plan's own
Self-Review (`:1183`) asserts "No gaps" against an AC-coverage table that maps ACs to step
*numbers* without ever asking whether those steps can fail. That is how four unpassable
assertions cleared review.

Three conventions, cheap enough to apply immediately, belong in `AGENTS.md`:

1. **Never put a check on the left of a pipe** whose right side is `tail`/`tee`/`jq`/`wc`/`rg`
   — the pipeline's status is the right side's, and the script's own `set -o pipefail` does
   not reach the invoking shell. Use `${PIPESTATUS[0]}`, or don't pipe.
2. **Never write `echo "…=$?"` after a command whose exit is insensitive to the invariant.**
   `git diff --name-only`, `git status`, `gh pr list`, `jq`, `sed -i`, and every pipeline
   exit 0 regardless. Assert with `[ -z "$(...)" ]`, `git diff --quiet`, or
   `diff … && echo OK`.
3. **A plan must not assert its own HEAD commit** (committing the plan changes HEAD, so the
   assertion is unpassable by construction), and **must not both mandate inserting a string
   and assert zero occurrences of it** (an internal contradiction one read-through catches).

The honest framing: this slice's clean outcome depended on the executor noticing three of
these in flight — including defeating Task 6 Step 9's `| tail` masking *by name* — and
missing two others. Alertness is not a control. Encode the rules.

## Slice 48 Candidate Options

### Option A: forward mapping `pointOf(line:column:)` — **recommended**

Every query shipped so far maps **geometry → model**: `y → line`, `x → cell`,
`(x, y) → (line, cell)`, each with a geometry-bearing companion. **The inverse direction
does not exist** — nothing maps a model position back to geometry. That is what caret
placement, selection highlighting, and scroll-to-cursor all need.

It reuses both existing metrics sources unchanged, is O(1)/O(log N) with O(1) core memory,
and needs no new provider protocol. Decisively, it unlocks a **round-trip oracle**:
`pointAt(pointOf(line, column)) == (line, column)` for every in-range position, and
`pointOf(pointAt(x, y))` landing inside the originating box. That is a far stronger
correctness property than any single-direction test the repo currently has, and it
retroactively hardens all six shipped queries. It also fits the established rhythm exactly —
query slice, then gate-promotion slice.

### Option B: cross-target script hardening

Fold P2 #1 (precheck success state), P3 #6 (per-attempt retry logfiles), and the unpinned
shell-purity exemption into one coherent slice, mirroring the `flagName` exemption-set
pattern already proven in `WorkflowShapeTests.swift`. Real, bounded, test-backed — but it
would be a **third consecutive infrastructure slice**, and none of its findings is urgent
(P2 #1 is latent under the current pin).

### Option C: plan-assertion executability discipline

Should **not** be its own slice. It is a ~20-line convention addition to `AGENTS.md` plus
the three rules above.

## Recommended Slice 48 Selection

**Option A, with Option C folded into its plan-writing step.** Queue Option B for Slice 49,
or pair it with the eventual `--point-of` gate promotion.

Rationale: two consecutive infra/policy slices (46, 47) argue for returning to the
functional core; the product trajectory wants the core's round trip closed; the round-trip
oracle is the highest-value test the repo can add right now; and Slice 47's own process
lesson is best discharged by *practising* it on the next plan rather than by writing a slice
about it.

## Slice 47 Review Conclusion

**READY.** No P0, no P1. The rename and the ruleset moved together, the merge gate never
broke, and the 64-second unrequired window was entered with the preconditions measured and
exited without a pause. The paper trail records its own deviations — including two
acceptance criteria that could not pass as written — rather than quietly passing them.

Two P2s carry forward: a real latent bug in asymmetric SDK drift (in the function this slice
rewrote), and a systemic gap in how this repo's plans assert their own correctness. Neither
blocks the merged state; both should shape how the next plan is written.
