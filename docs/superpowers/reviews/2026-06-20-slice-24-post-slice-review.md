# Slice 24 Post-Slice Review

Date: 2026-06-20

## Scope Reviewed

This review covers Slice 24: the **structural-mutation CI gate promotion**. It
adds the already-existing `--structural-mutation --gate` benchmark path as a new
**blocking** step in the required `Host tests and benchmark gate` hosted job, so
a performance regression in the `BalancedTreeLineMetrics` insert/delete path now
fails the job. This is a CI/governance slice, not a functional-core slice: it
changes no Swift source, tests, package metadata, benchmark workloads, or
benchmark budgets. It closes the single regression-protection gap the Slice 23
review identified and was Slice 23's recommended Option A.

The slice was delivered through **three** PRs, all now merged:

- PR #37 (`slice-24-structural-mutation-ci-gate-promotion`), merged to `main` as
  `716a8e6059635aef0bf1c661ec44c710454f834e`
  (`Merge pull request #37 …`) — the workflow step, the `AGENTS.md` update, and
  the verification record (with PR-head proof). Final PR head: `69ddac0`.
- PR #38 (`slice-24-post-merge-verification`), merged as `edc0349` — the
  docs-only follow-up that filled the post-merge push proof.
- PR #39 (`slice-24-final-pr-head-verification`), merged as `53b594b` (current
  `main` HEAD) — a docs-only correction that re-anchored the PR-head proof to the
  true merged head SHA `69ddac0` (see Verification Evidence → "The PR-head proof
  correction" below).

**All three PRs are merged at review time.** As in Slice 23, the post-merge
evidence landed before this review, so `main`'s verification record carries real
run IDs, not `Pending` placeholders.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-20-structural-mutation-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-06-20-structural-mutation-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`
- `docs/superpowers/reviews/2026-06-20-slice-23-post-slice-review.md`
- `.github/workflows/swift-ci.yml` (host job)
- `AGENTS.md` (CI section)
- PR #37 / #38 / #39 metadata, hosted run evidence (step-level logs), merge
  parentage, and the merged Slice 24 diff

The reviewed Slice 24 range (PR #36 merge base → current `main` HEAD) is:

```text
62f304fb1b22b62d6f03e9b6d62181f6fc7e6559..53b594bbba9b3a3c7031ab1f2765f294a3a5c633
```

This is deliberately confined to `.github/workflows/swift-ci.yml`, `AGENTS.md`,
and `docs/**`. It does **not** touch `Sources/**`, `Tests/**`, `Package.swift`,
or `.github/scripts/**` — confirmed below by a fresh name-only diff.

## Product Brief Alignment

The brief requires regression benchmarks to block merge on performance
degradation (*"Регрессионные бенчмарки блокируют merge при деградации
производительности"*). Before this slice that principle held for three of the
four latency paths — the synthetic pipeline, static variable-height, and
variable-height-mutation gates all ran blocking in hosted CI. The structural
insert/delete path, added in Slice 23, was proven **locally only**: the host job
stayed green regardless of structural-mutation performance because the benchmark
was never invoked in the workflow.

Slice 24 closes exactly that gap. The brief's "benchmark gates block merge"
principle now holds for **all four** latency paths, including the most
edit-realistic one (mid-document insert/delete, which dominates real editing).
This also completes the project's established "functional slice adds a local
gate → promotion slice wires CI" rhythm for the third time
(variable-height → its promotion, variable-height-mutation → its promotion,
structural-mutation → this slice).

## Delivered Design

Merged Slice 24 diff (`62f304f..53b594b`):

```text
 .github/workflows/swift-ci.yml                     |   4 +
 AGENTS.md                                          |   7 +-
 .../2026-06-20-structural-mutation-ci-gate-promotion.md (verification) | 1209 +++++
 .../2026-06-20-structural-mutation-ci-gate-promotion-design.md (spec)  |  379 +++
 .../2026-06-20-structural-mutation-ci-gate-promotion.md (plan)         |  312 +++
 5 files changed, 1908 insertions(+), 3 deletions(-)
```

### The workflow step (the core of the slice)

A single new step in the `host-tests-and-benchmark-gate` job, inserted between
the variable-height mutation gate and the memory-shape diagnostic:

```yaml
      - name: Run structural mutation benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate
```

This is correct against every spec decision:

- **No `continue-on-error`** → it is a true blocking gate (Decision 1, one-shot
  promotion with no transient observation step).
- **Invokes the executable-owned gate path** (`--structural-mutation --gate`),
  not a YAML-duplicated threshold → budgets stay single-sourced in
  `Sources/ViewportBenchmarks` (Decision 2).
- **Positioned after the vh-mutation gate, before memory-shape** → all blocking
  latency gates stay contiguous and fail before lower-priority diagnostics
  (Decision 4). Verified by a fresh Ruby YAML assertion:
  `order=vh<structural<memory blocking=true`.
- **Same `docs_only_pr != 'true'` guard** as every adjacent gate → docs-only PRs
  still skip it via the trusted lightweight path (Decision 6).
- **No `shell: bash` override** → a single one-line command with no pipes
  (Decision 7).
- **Required context names unchanged** (`Host tests and benchmark gate`,
  `iOS cross-target compile`, `WASM cross-target observation`) → the job becomes
  stricter without a ruleset or required-context change (Decision 5).

### `AGENTS.md` (durable guidance)

The CI section's host-job bullet now lists
`→ --structural-mutation --gate (blocking)` after the vh-mutation gate and before
`--memory-shape`, and the "fail the job on perf regression" sentence now names
the structural-mutation gate alongside the other three. The docs-only, iOS, WASM,
ruleset, and bypass-caveat wording is unchanged. (The command-list local
invocation on line 73 was already added in Slice 23.)

## Verification Evidence Reviewed

### Fresh local checks during this review (merged `main` at `53b594b`)

- `rg -n "Foundation" Sources/TextEngineCore` → no matches, exit `1`.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` → no matches, exit `1`.
- `git diff --check 61e1c18..HEAD` → no output, exit `0`.
- `git diff --name-only 62f304f..HEAD -- Sources Tests Package.swift .github/scripts`
  → **empty** (no source, manifest, test, or helper-script surface touched).
- Workflow-shape Ruby assertion → `workflow_shape=ok
  required_contexts_unchanged=true order=vh<structural<memory blocking=true`.
- `swift test` → `Executed 90 tests, with 0 failures` (plus the expected empty
  Swift Testing `0 tests in 0 suites` line). Unchanged from the Slice 23 baseline,
  as expected for a no-source slice.
- `swift run -c release ViewportBenchmarks -- --structural-mutation --gate` → all
  three scenarios `gate=pass`, and the **checksums are bit-identical** to the
  recorded runs (`200106952336`, `89494497658324`, `3379593298396981`) —
  confirming the benchmark path is deterministic and unchanged.

### Hosted Linux x86_64 budget-fit (the load-bearing evidence for this slice)

Decision 3 bet that the macOS-calibrated budgets would hold on hosted Linux, with
the one-shot PR-head run **being** that evidence. It held — comfortably — across
both hosted runs:

| Scenario | macOS local p95 | Hosted PR-head p95 | Hosted post-merge p95 | Budget p95 |
| --- | ---: | ---: | ---: | ---: |
| 1k lines | ~1.9k | 3,193 | 3,005 | 20,000 |
| 100k lines | ~8.9k | 14,090 | 12,483 | 80,000 |
| 1m lines | ~38.6k | 54,040 | 34,577 | 250,000 |

Hosted Linux is meaningfully slower than macOS arm64 (the 1m p95 ranged
34.6k–54.0k across runs, vs ~33–39k locally), and shows more run-to-run variance —
but even the worst observed hosted number sits **~4.6× under budget**. The
one-shot blocking promotion was the right call: no observe-then-block ceremony was
needed, and no budget retune was forced. Decision 3's "stop and revise the spec if
it fails" escape hatch was never triggered.

### Hosted runs (verified at step-log level, not just job conclusion)

Both runs independently re-verified via `gh` during this review:

- **PR #37 final-head run `27870025680`** (head `69ddac0`): all three required
  jobs `success`.
- **Post-merge push run `27873570781`** on merge commit `716a8e6`: all three
  required jobs `success`, and — confirming the "a green job can hide a dead
  `continue-on-error` step" lesson — the host job's **step 11
  `Run structural mutation benchmark gate` is itself `conclusion=success`**,
  sitting between step 10 (vh-mutation gate) and step 12 (memory-shape). This is
  the merged-code evidence anchor: the new gate is a real blocking step that
  passed, not a masked one. Merge parentage confirms `716a8e6`'s second parent is
  `69ddac0`, so the proof anchors the actually-merged head.

PRs #38 and #39 were docs-only follow-ups touching only the verification record,
so they legitimately took the trusted docs-only path and their `main` pushes were
eligible to skip Swift CI via `push.paths-ignore`. The workflow YAML has not
changed since `716a8e6`, so run `27873570781` still represents current `main`'s
workflow behavior.

### The PR-head proof correction (PR #39)

This is the one notable wrinkle and worth recording in full. PR #37's verification
commit originally recorded the PR-head proof against head SHA `b9725ee`
(run `27869783512`). But committing the verification doc itself pushed a **new**
commit (`69ddac0`), which became the real PR head and triggered a fresh CI run
(`27870025680`). The originally-recorded SHA was therefore **stale-on-write** —
it was the commit *before* the doc that recorded it. PR #39 corrected the proof to
the true merged head `69ddac0` and its run, which merge parentage confirms is
correct.

This is exactly the evidence-churn hazard the plan's Task 5 Step 8 explicitly
anticipated ("the pushed documentation commit starts a new PR-head Swift CI run
because the full PR diff still includes workflow YAML"). The team noticed and
corrected it rather than leaving a wrong SHA in the record — the right outcome —
but it cost a third PR. See Lessons below.

## Git History

Reviewed Slice 24 commits (PR #37 → #38 → #39):

```text
7317bd9 docs: add structural-mutation CI gate promotion spec
1aea20c docs: add structural-mutation CI gate promotion plan
04d8b3c ci: add structural mutation benchmark gate to host job
04f7bf3 docs: document structural mutation ci gate
b9725ee docs: record structural mutation gate verification
69ddac0 docs: record structural mutation gate hosted proof
716a8e6 Merge pull request #37 …
5e062f0 docs: record structural mutation gate post-merge proof
edc0349 Merge pull request #38 …
660803e docs: correct structural mutation pr-head proof
53b594b Merge pull request #39 …
```

Clean, incremental, one-logical-step-per-commit with correct conventional-commit
prefixes (`ci:` for the workflow step, `docs:` for guidance/verification). The
workflow change is isolated in a single `ci:` commit; spec, plan, guidance, and
verification are each separated. The PR-head-behavior vs post-merge-evidence split
follows the established pattern; the extra third PR (#39) is the correction
described above.

## Code Review Findings

Reviewing across workflow correctness, scope discipline, evidence integrity, and
policy concerns:

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None.

### P2 / Production Readiness

None.

### P3 / Minor But Valid

None that warrant a change to the merged result. The workflow edit is minimal and
correct, the budgets held on hosted Linux with margin, the required contexts and
docs-only behavior are untouched, and the merged verification record is complete
and accurate (the stale PR-head SHA was corrected in PR #39 before this review).
The observations below are tracked as Risks/Gaps and Lessons rather than findings.

One cosmetic note, not a defect: the corrected PR-head proof block in the
verification doc shows the step label as `UNKNOWN STEP` (a `gh run view --log`
quirk when the log is fetched such that step grouping isn't resolved). The command
line and three `gate=pass` rows are present and valid, and the post-merge proof
block carries the proper `Run structural mutation benchmark gate` label, so the
evidence stands.

## Risks And Gaps

### Budgets remain macOS-derived

This slice confirmed the macOS budgets fit hosted Linux but did not re-derive
Linux-native budgets. That matches the standing project posture for all four
gates and is acceptable. With four latency gates now running on hosted Linux,
there is accumulated x86_64 evidence; a dedicated Linux budget re-baseline is
viable future work but explicitly out of scope here.

### Host job is slightly longer and stricter

Unlike the Slice 21 vh-mutation promotion (which only flipped failure semantics of
an already-running step), this slice adds a benchmark workload that never ran in
hosted CI before — one more mode over the same 1k/100k/1M scenarios. From the
hosted timestamps the step takes roughly a minute; it stays well within the job's
timeout. Accepted, as anticipated in the spec's Risks.

### Hosted variance is real but well within headroom

The 1m p95 varied 34.6k→54.0k across two hosted runs. This is expected hosted-CI
noise and stays ~4.6×+ under budget, but it is the scenario closest to budget and
worth watching if a future change tightens the structural workload or the budget.

### Standing items unchanged

WASM cross-target remains observational; the realistic-provider relative
observation remains PR-only `continue-on-error`; the `Main` ruleset keeps its
documented bypass-actor shape (the admin user can still bypass required checks).
None were in scope for Slice 24.

## Lessons For The Next Slice

1. **A workflow-touching slice's verification commit moves its own PR head.**
   When the PR diff includes workflow YAML, committing the verification doc
   creates a new head SHA and a new CI run, so any PR-head proof recorded *before*
   that commit is stale. The plan flagged this (Task 5 Step 8) and the team
   corrected it (PR #39), but it still cost a third PR. Two ways to avoid the
   churn next time: (a) record the PR-head proof against the **final** head only
   after the last content commit is pushed, accepting one self-referential CI run;
   or (b) split the verification doc's PR-head section into the post-merge
   follow-up PR. The current approach works but is fiddly — document the chosen
   convention so the next workflow slice doesn't rediscover it.
2. **The one-shot blocking promotion is now validated for benchmarks with
   generous headroom.** Decision 1 (skip the transient observation step) held for
   the third gate; macOS budgets with ~10× local headroom comfortably survived
   hosted Linux. Keep using one-shot promotion for similarly-budgeted gates;
   reserve observe-then-block for gates with thin margins.
3. **All three mutation gates are now CI-protected.** Slice 23's precondition —
   "the structural-mutation gate should be promoted before the next functional
   change to the provider" — is now satisfied. The provider is free to evolve
   under regression protection.
4. The "functional slice → gate-promotion slice" cadence has now completed three
   full cycles. The CI/governance backlog opened by functional work is fully
   drained.

## Slice 25 Candidate Options

### Option A: Return To Functional Core — bulk/range structural edits

Build on `BalancedTreeLineMetrics` with a batched `insertLines` / `removeLines`
range API. Slice 23 explicitly deferred bulk ops (they currently compose from
single-line operations), and the new provider now has CI regression protection,
so this is the most directly teed-up functional increment. Needs its own
spec/plan, an equivalence-oracle extension for batch operations, and a benchmark
scenario. Moderate scope, high readiness, satisfies Slice 23's stated
precondition.

### Option B: Advance The Next Real Engine Capability

Move beyond the current vertical-only layout/virtualization math toward the next
brief capability (e.g. width/wrap-aware metrics, a horizontal axis, or
position-query APIs such as `lineAt(y:)`). Highest product value and largest
scope; requires a brainstorm + spec to pin the increment. The strongest choice if
the goal is product momentum rather than rounding out the provider.

### Option C: Promote WASM Cross-Target To Blocking

The long-deferred (Slice 22 Option A) infra item: provision a pinned,
version-matched WASM Swift SDK in the hosted job, prove it stably green, then flip
WASM from observational to blocking for both packages. Infra-gated on stable SDK
provisioning; both packages are already wired into the WASM path.

### Option D: Linux-Native Budget Re-Baseline

With four latency gates now on hosted Linux, re-derive Linux-native budgets from
accumulated x86_64 evidence and retire the macOS-calibration caveat. Low product
value, useful hygiene; a clean, well-scoped CI slice.

### Option E: Ruleset Bypass Policy Review

Decide whether the current bypass-actor shape is acceptable long-term. A
repo-policy slice, kept separate from benchmark/provider work.

## Recommended Slice 25 Selection

Recommended Slice 25 is to **return to functional-core work — Option A (bulk/range
structural edits) as the lowest-risk, highest-readiness pick, or Option B (next
engine capability) as the higher-ceiling alternative**.

The reasoning: Slices 18–22 and 24 have been CI / portability / governance work,
with Slice 23 the lone functional exception. That backlog is now fully drained —
the brief's "benchmark gates block merge" principle holds for all four latency
paths, and every mutation gate is CI-protected. Slice 23's explicit precondition
for the next functional change ("promote the structural-mutation gate first") is
satisfied by this slice. There is no remaining CI gap forcing another governance
slice, so the project should ride functional momentum back toward product value.

Between the two functional options: **Option A** is the safest concrete next step
and slots directly onto the now-protected provider, but **Option B** carries more
product value if the preference is to push the engine forward rather than round
out the provider's edit API. Given the user chose functional work for Slice 23, a
functional Slice 25 is the consistent choice; the A-vs-B call is a genuine product
decision worth surfacing to the user.

If the preference is instead to keep clearing infra debt, **Option C (WASM
blocking)** remains the highest-value non-functional pick and is the only standing
CI item with real coverage upside.

## Slice 24 Review Conclusion

Slice 24 delivered the intended governance increment: the
`--structural-mutation --gate` benchmark now runs as a blocking step in the
required host job, so structural insert/delete regressions block merge. The
macOS-calibrated budgets held on hosted Linux x86_64 with ~4.6×+ headroom even at
the noisiest scenario, validating the one-shot promotion decision and never
triggering the budget-failure escape hatch. The change is correctly scoped — zero
Swift source, test, package, or helper-script surface touched; required contexts,
docs-only behavior, and ruleset all unchanged — and verified at the step level on
both the final PR-head run and the post-merge push run.

The review found no P0, P1, P2, or actionable P3 issues against the merged result.
The one process wrinkle — a stale-on-write PR-head SHA requiring a third
correction PR (#39) — was anticipated by the plan, caught, and corrected before
this review, leaving `main`'s verification record accurate; it is captured as a
lesson for the next workflow-touching slice. With all four latency gates now
CI-protected and the functional precondition satisfied, Slice 24 cleanly closes
the CI/governance arc and hands off to a return to functional-core work.
