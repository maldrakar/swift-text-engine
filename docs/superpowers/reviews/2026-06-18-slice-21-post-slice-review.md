# Slice 21 Post-Slice Review

Date: 2026-06-18

## Scope Reviewed

This review covers Slice 21: promotion of the variable-height mutation
benchmark from hosted observation to a blocking hosted gate in the required
`Host tests and benchmark gate` job.

The slice was delivered through:

- PR #28 (`slice-21-variable-height-mutation-gate`), merged to `main` as
  `c646645ba1f0fc097951d40ad30144a61b078ab3`
  (`Merge pull request #28 from maldrakar/slice-21-variable-height-mutation-gate`);
- PR #29 (`slice-21-post-merge-verification`), merged to `main` as
  `b5b7bc39a98c159f8b36787336fbc55732f4e929`
  (`Merge pull request #29 from maldrakar/slice-21-post-merge-verification`).

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-18-variable-height-mutation-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-06-18-variable-height-mutation-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`
- `docs/superpowers/reviews/2026-06-17-slice-20-post-slice-review.md`
- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- PR metadata, hosted run evidence, ruleset readback, and merged Slice 21 diff

The reviewed Slice 21 range is:

```text
24fed3533d0f505ced7a41377f56b8a95142b8bc..b5b7bc39a98c159f8b36787336fbc55732f4e929
```

This is a CI governance and verification slice. It deliberately leaves
`Sources/**`, `Tests/**`, `Package.swift`, benchmark workloads, benchmark
budgets, required status context names, docs-only detector logic, and ruleset
settings unchanged.

Review used the code-review-team flow with independent reviewer lenses:
`architect-reviewer`, `code-reviewer`, `code-simplifier`,
`fullstack-developer`, `qa-expert`, and `security-auditor`.

## Product Brief Alignment

Slice 21 strengthens the brief's benchmark-regression requirement at merge
time. The mutable variable-height path introduced in Slice 17 already had an
executable-owned local gate and hosted observation evidence; this slice moves
that same gate into the hosted required host job.

The change does not alter the headless engine, provider API, layout math,
benchmark scenarios, or budget values. It changes enforcement: a hosted
mutation benchmark regression now fails the same required job context as the
synthetic and static variable-height benchmark gates.

## Delivered Design

Merged Slice 21 diff (`24fed35..b5b7bc3`):

```text
 .github/workflows/swift-ci.yml                     |    5 +-
 AGENTS.md                                          |    9 +-
 ...8-variable-height-mutation-ci-gate-promotion.md | 1115 ++++++++++++++++++++
 ...ble-height-mutation-ci-gate-promotion-design.md |  361 +++++++
 ...8-variable-height-mutation-ci-gate-promotion.md |  244 +++++
 5 files changed, 1727 insertions(+), 7 deletions(-)
```

### Workflow Promotion

The host job now runs the mutation benchmark as a gate immediately after the
static variable-height gate:

```yaml
- name: Run variable-height mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation --gate
```

The previous observation-only shape is gone from that step:

```text
Observe variable-height mutation benchmark
continue-on-error: true
--variable-height-mutation
```

`continue-on-error` remains only on the PR-only realistic provider relative
observation step, which is outside this slice's scope.

### Required Contexts And Docs-Only Boundary

The three required job names remain unchanged:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

Docs-only PRs still emit the required contexts through the trusted lightweight
path. The workflow edit did not change `.github/scripts/detect-docs-only-pr.sh`
or the trusted-base `$RUNNER_TEMP/trusted-ci` execution model from Slices 19 and
20.

### Durable Guidance And Evidence

`AGENTS.md` now describes the host job as:

```text
swift test -> synthetic --gate -> --variable-height --gate -> --variable-height-mutation --gate
```

and states that the synthetic, static variable-height, and mutation
variable-height gates fail the job on performance regression.

The verification record includes:

- pre-implementation red proof against the old observation-only workflow;
- local synthetic, variable-height, and mutation benchmark gate output;
- YAML shape assertions proving the required contexts are unchanged and the
  mutation step has no `continue-on-error`;
- PR-head hosted proof for PR #28;
- post-merge push proof for PR #28;
- a docs-only follow-up PR #29 proving the required contexts still materialize
  through the lightweight path after documentation-only evidence refresh.

## Verification Evidence Reviewed

Fresh local checks during this review:

- `git diff --check 24fed35..b5b7bc3` -> no output, exit status `0`.
- Workflow YAML shape assertion -> `workflow_shape=ok`, exit status `0`.
- `rg -n "Foundation" Sources/TextEngineCore` -> no matches, exit status `1`.
- `git diff --name-only 24fed35..b5b7bc3 -- Sources Tests Package.swift` -> no
  output.
- `swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate`
  -> `gate=pass` for all three mutation rows. Fresh local 1M row:
  `p95_ns=4799 p99_ns=4910`, budgets `60000` / `75000`.

Live PR and run evidence checked during this review:

- PR #28 merged, final head `f92cdca35b4528000a953a7a3d8e640c1d1ddd6e`,
  merge commit `c646645ba1f0fc097951d40ad30144a61b078ab3`.
- PR #28 final Swift CI run `27741054093`:
  - all three required jobs `success`;
  - host job ran `Run variable-height mutation benchmark gate`;
  - hosted mutation rows included `budget_p95_ns=`, `budget_p99_ns=`, and
    `gate=pass`;
  - hosted 1M mutation row reported `p95_ns=10490 p99_ns=10666`.
- Post-merge push run `27741616147` on merge commit `c646645...`:
  - all three required jobs `success`;
  - host job ran `Run variable-height mutation benchmark gate`;
  - hosted 1M mutation row reported `p95_ns=10376 p99_ns=10572`;
  - the PR-only realistic provider relative observation was correctly skipped
    on the push event.
- PR #29 merged, final head `57787854859324e2aaaf1cc1321df9da19e48601`,
  merge commit `b5b7bc39a98c159f8b36787336fbc55732f4e929`.
- PR #29 Swift CI run `27745826227`:
  - all three required jobs `success`;
  - all three jobs used `Complete docs-only PR`;
  - heavy Swift/test/benchmark/compile steps were skipped, matching the
    documented docs-only required-context behavior.

Live ruleset readback during this review confirms the active `Main` ruleset
still requires exactly:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
strict_required_status_checks_policy=true
```

No `main` push run appears for PR #29's merge commit in the recent Swift CI run
list. That is expected for a docs-only merge under the documented
`push.paths-ignore` behavior; PR required checks were the merge gate.

## Git History

Reviewed Slice 21 commits:

```text
e3d877f ci: promote variable-height mutation benchmark gate
274b1fd docs: document variable-height mutation ci gate
b471497 docs: record variable-height mutation gate verification
f92cdca docs: record variable-height mutation gate hosted proof
c646645 Merge pull request #28 from maldrakar/slice-21-variable-height-mutation-gate
b445075 docs: record variable-height mutation gate post-merge proof
56a875a docs: refresh variable-height mutation gate pr-head proof
5778785 docs: add variable-height mutation gate spec and plan
b5b7bc3 Merge pull request #29 from maldrakar/slice-21-post-merge-verification
```

The behavior commits are narrowly scoped: workflow promotion, durable guidance,
local verification, and hosted proof. The later follow-up commits are
documentation and evidence refreshes, with PR #29 taking the docs-only required
context path.

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None.

### P2 / Production Readiness

None.

### P3 / Minor But Valid

#### P3 - Slice 21 spec still says the merged design is a draft

`docs/superpowers/specs/2026-06-18-variable-height-mutation-ci-gate-promotion-design.md:7`
still says:

```text
Draft design direction, written for user review.
```

That contradicts the durable slice state: the plan, implementation,
verification record, PR-head proof, post-merge proof, and this post-slice review
all exist. It also diverges from the adjacent governance specs for Slices 19 and
20, which use `Approved design direction, written for user review.` after the
approved-spec step.

Impact: future slice work can treat the merged Slice 21 design as unapproved
draft material and reopen scope instead of using it as the approved source of
truth for the implemented gate promotion.

Fact-check evidence:

- `AGENTS.md:149` through `AGENTS.md:157` documents the lifecycle as
  spec -> plan -> implementation -> verification record -> post-slice review.
- `docs/superpowers/specs/2026-06-16-trusted-docs-only-gate-design.md`
  lines 5-7 and
  `docs/superpowers/specs/2026-06-17-policy-sensitive-markdown-path-hardening-design.md`
  lines 5-7 use the approved status wording.
- The Slice 21 spec line is newly introduced by this slice.

Suggested fix: update the Slice 21 spec status line to
`Approved design direction, written for user review.` or another explicit
approved/final status.

Source agent: `code-reviewer`.

All other independent reviewer lenses returned no production-relevant findings.

## Risks And Gaps

### Spec Status Drift

The confirmed P3 above should be fixed before using the Slice 21 spec as the
starting point for future planning. It is a one-line documentation correction,
not a CI/runtime defect.

### Bypass Actors Remain

The active ruleset still has the previously documented bypass actor shape.
Required checks are enforced for normal PR flow, but bypass-capable actors can
still override the ruleset. Slice 21 did not change that policy.

### WASM Remains Observational

The required `WASM cross-target observation` context is emitted and green, but
the helper still treats unavailable WASM SDKs as non-blocking skips. This is
existing documented behavior, not a Slice 21 regression.

### Realistic Provider Relative Observation Remains Non-Blocking

The PR-only realistic provider relative observation step still uses
`continue-on-error: true`. Slice 21 intentionally promoted only
`--variable-height-mutation --gate`, whose budgets already live in the benchmark
executable and had enough hosted headroom.

### Reference Provider Cross-Target Coverage Is Still A Decision

Hosted cross-target compile coverage still targets `TextEngineCore`. The
reference provider target is Foundation-free and has local WASM proof from
Slice 17, but the hosted helper does not yet compile
`TextEngineReferenceProviders`. This remains a product-boundary decision: either
promote it to hosted cross-target coverage or document it as host/reference-only
support.

## Lessons For The Next Slice

1. The mutation benchmark gate is now enforced in the required host job; future
   benchmark-mode promotions should follow the same executable-owned-budget
   pattern instead of duplicating thresholds in workflow YAML.
2. Hosted proof should continue to separate PR-head heavy-path evidence,
   post-merge push evidence, and docs-only follow-up evidence. Slice 21 needed
   all three because behavior and final paper trail landed through separate PRs.
3. Docs-only follow-ups are acceptable for evidence refreshes, but the durable
   spec status must match the lifecycle state before future agents use it as
   source context.
4. With the synthetic, static variable-height, and mutation variable-height
   gates now blocking, the next portability gap is no longer this benchmark
   mode; it is the boundary of what targets must be cross-compiled in hosted CI.

## Slice 22 Candidate Options

### Option A: Cross-Target Provider Coverage Decision

Decide whether `TextEngineReferenceProviders` is a supported portable product.
If yes, extend the hosted cross-target helper to compile it for iOS and WASM
where toolchains are available. If no, document the target as a reference /
benchmark support library and keep hosted cross-target coverage focused on
`TextEngineCore`.

### Option B: Realistic Provider Observation Promotion Or Recalibration

Review whether the PR-only realistic provider relative observation has enough
hosted Linux evidence to become stricter. This should stay separate from
mutation gating because it uses a relative baseline and currently remains
`continue-on-error`.

### Option C: Line Insert/Delete Provider Design

Design dynamic line-count changes for reference providers. This is a larger
functional provider slice than height mutation because the current Fenwick
array shape does not cheaply support mid-document insert/delete.

### Option D: Ruleset Bypass Policy Review

Decide whether the current bypass actor shape is acceptable long-term. This is
a repository-policy slice and should stay separate from benchmark or provider
work.

## Recommended Slice 22 Selection

First apply the one-line P3 documentation fix to mark the Slice 21 spec as
approved/final.

After that, recommended Slice 22 is **Option A: Cross-Target Provider Coverage
Decision**. Slice 21 closes the mutation-gate enforcement gap; the next
highest-value CI/portability decision is whether the now-important reference
provider target should be compiled by the hosted cross-target helper or
explicitly remain outside the supported portable surface.

## Slice 21 Review Conclusion

Slice 21 delivered the intended CI enforcement change. The hosted host job now
runs `--variable-height-mutation --gate` without `continue-on-error`; required
job contexts stayed unchanged; docs-only required-context behavior stayed
trusted and lightweight; and PR-head plus post-merge hosted evidence prove the
promoted gate on the merged workflow.

The review found no P0, P1, or P2 issues. One P3 paper-trail issue remains: the
merged Slice 21 spec still labels itself as draft. Fix that status line before
using the Slice 21 design as durable input for the next slice.
