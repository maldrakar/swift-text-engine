# Structural-Mutation CI Gate Promotion Design

Date: 2026-06-20

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 24 of SwiftTextEngine, following the Slice 23 post-slice review:

```text
docs/superpowers/reviews/2026-06-20-slice-23-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
That requirement already holds for the synthetic, static variable-height, and
variable-height-mutation latency gates, which run blocking in the hosted
`Host tests and benchmark gate` job. It does **not** yet hold for the structural
insert/delete path.

Slice 23 introduced the dynamic line insert/delete capability and benchmark
path:

- `TextEngineReferenceProviders.BalancedTreeLineMetrics` — a mutable,
  order-statistics balanced tree whose `insertLine` / `removeLine` /
  `setHeight` / `offset(ofLine:)` are each O(log N);
- `--structural-mutation` benchmark mode (output `structural_mutation`,
  provider `balanced_tree`) over the 1k / 100k / 1M scenarios;
- local `--structural-mutation --gate` budgets, passing locally with ~10x
  headroom.

The Slice 23 post-slice review recommends Slice 24 as:

```text
Option A: Structural-Mutation CI Gate Promotion
```

### Key difference from the prior mutation-gate promotion (Slice 21)

When the variable-height-mutation gate was promoted in Slice 21, that benchmark
was **already running in hosted CI** as a `continue-on-error` observation step
(no `--gate`). Slice 21 therefore had hosted Linux x86_64 evidence that its
budgets fit, and promotion only removed `continue-on-error` and added `--gate`.

The structural-mutation benchmark has a different starting state: it has
**never run in hosted CI**. There is no observation step to flip and no prior
hosted Linux evidence. Its budgets are macOS-calibrated only. This difference
shapes the rollout decision below.

### Current host CI shape (relevant excerpt)

```yaml
- name: Run variable-height benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height --gate

- name: Run variable-height mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation --gate

- name: Run memory shape diagnostic
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

There is no `--structural-mutation` step anywhere in the workflow today.

### Current structural-mutation budgets and local evidence

The benchmark mode already carries executable-owned budgets. Recorded Slice 23
local observation (macOS), reproduced bit-identically during the Slice 23
review:

| Scenario | Observed p95 ns | Budget p95 ns | Gate |
| --- | ---: | ---: | --- |
| 1k lines | ~1.6–2.0k | 20,000 | pass |
| 100k lines | ~7.5–9.3k | 80,000 | pass |
| 1m lines | ~33–39k | 250,000 | pass |

The macOS p95 numbers sit roughly an order of magnitude under budget at every
size.

## Problem

The structural insert/delete path is proven locally but invisible to hosted CI.
Today the host job stays green regardless of structural-mutation performance,
because the benchmark is not invoked in the workflow at all. That leaves an
enforcement gap:

- regressions in `BalancedTreeLineMetrics` insert/delete/query behavior are not
  blocking;
- regressions in the unchanged generic variable-height core path, when
  exercised through structural mutation + recompute, are not blocking;
- the brief's "benchmark gates block merge" principle is not yet true for the
  structural editing path.

With required checks, docs-only shortcut trust, and the other three latency
gates already hardened, making the structural-mutation benchmark fail the same
required host job is the natural next governance step, and it closes the single
regression-protection gap Slice 23 opened.

## Scope

Slice 24 introduces the structural-mutation benchmark to the hosted host-tests
job as a **blocking gate** in a single PR.

Expected implementation surface:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`

Expected paper trail:

- this design spec;
- a task-by-task plan after this spec is approved;
- a verification record with local and hosted evidence;
- a post-slice review after implementation and merge.

The slice should not change Swift source unless implementation verification
finds that the existing benchmark executable gate is broken.

## Goals

- Add a `--structural-mutation --gate` step to the hosted
  `Host tests and benchmark gate` job.
- Make the step blocking: no `continue-on-error: true`.
- Place the step immediately after `Run variable-height mutation benchmark gate`
  and before `Run memory shape diagnostic`, keeping all blocking latency gates
  together and failing before lower-priority diagnostics.
- Keep benchmark budgets in `Sources/ViewportBenchmarks`, not duplicated in
  workflow YAML.
- Keep the current macOS-calibrated budgets for this promotion, and use the
  PR-head hosted run as the Linux x86_64 evidence that confirms they fit.
- Keep the three required job contexts unchanged.
- Keep trusted docs-only PR behavior unchanged.
- Update `AGENTS.md` so the CI section lists the structural-mutation gate as
  blocking in hosted CI.
- Record local and hosted proof that structural-mutation benchmark output
  includes `budget_p95_ns`, `budget_p99_ns`, and `gate=pass`, and that the
  hosted step is not `continue-on-error`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No `BalancedTreeLineMetrics` API changes.
- No benchmark workload redesign.
- No new benchmark mode.
- No benchmark budget retune unless the first hosted run forces a spec revisit.
- No new Swift test target or benchmark XCTest harness.
- No cross-target provider coverage expansion.
- No hosted WASM promotion.
- No realistic-provider observation promotion.
- No ruleset mutation.
- No new required GitHub status context.
- No workflow job rename.
- No docs-only detector change.
- No `pull_request_target` workflow.
- No bypass-actor policy change.

## Decisions

### Decision 1 - One-shot blocking gate, no transient observation step

Add the step directly as a blocking gate in one PR, rather than first landing a
`continue-on-error` observation step and flipping it later.

Rationale: the budgets carry ~10x macOS headroom; the PR-head CI run executes
the step on hosted Linux x86_64 and prints `p95_ns` / `p99_ns` / budget fields
whether or not it passes, so a single blocking step both enforces and produces
the hosted evidence. The other latency gates were promoted successfully against
similarly generous budgets. This keeps the slice to one clean PR.

Rejected alternative — observe-then-block: add a non-blocking observation step
first, read the hosted numbers, then promote in a follow-up. Safer against a
surprise red gate, but more ceremony for a benchmark with large headroom, and
the one-shot path's failure mode (Decision 3) recovers the same evidence.

### Decision 2 - Promote the existing executable gate path

The workflow should call the benchmark executable exactly as local verification
does:

```bash
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate
```

Rejected alternative: encode structural-mutation budgets in workflow YAML.
Budgets already live with the benchmark scenarios in `Sources/ViewportBenchmarks`
and are printed by the executable. A workflow budget copy would create two
sources of truth.

### Decision 3 - Keep current budgets; treat a first-run hosted failure as evidence

This slice promotes the existing macOS-calibrated budgets rather than retuning
them up front. The standing budget-calibration rule asks for hosted Linux
x86_64 evidence before trusting budgets; the one-shot PR-head run **is** that
evidence, recorded in the verification doc.

If the first hosted PR-head run fails because hosted Linux behavior does not fit
the existing budgets, implementation must **stop** and update this design with
the new hosted numbers, then re-derive Linux-appropriate budgets in
`Sources/ViewportBenchmarks`. It must **not** hide the failure with
`continue-on-error`, a workflow-only threshold, or a silent budget widening.

### Decision 4 - Keep the host job order

The structural-mutation gate sits immediately after the variable-height
mutation gate:

1. `swift test`
2. synthetic benchmark gate
3. static variable-height benchmark gate
4. variable-height mutation benchmark gate
5. **structural-mutation benchmark gate (new)**
6. memory-shape diagnostic
7. RSS memory observation
8. PR-only realistic relative observation

This keeps all blocking latency gates contiguous and fails before lower-priority
diagnostics if the structural path regresses.

### Decision 5 - Do not change required context names

The ruleset already requires `Host tests and benchmark gate`. Slice 24 makes
that job stricter but must not create or rename required contexts. The iOS and
WASM jobs remain unchanged.

### Decision 6 - Leave docs-only behavior unchanged

Docs-only PRs still complete the required contexts through the trusted
lightweight path and skip heavy Swift work. The structural-mutation gate is part
of the heavy host path and runs whenever `docs_only_pr != 'true'`, matching
every adjacent gate. Policy-sensitive workflow changes are already non-doc, so
the Slice 24 workflow edit itself is tested by the heavy path in its own PR.

### Decision 7 - A one-line Swift command needs no shell override

Like the other gate steps, the structural-mutation gate uses no pipes,
`set -o pipefail`, or shell-specific behavior. It stays a plain `run:` line and
does not need `shell: bash`. The important workflow property is the absence of
`continue-on-error: true` on this step.

## Implementation Architecture

### Workflow

Insert into the host job, between the variable-height mutation gate and the
memory-shape diagnostic:

```yaml
- name: Run structural mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate
```

No other workflow step should need to move or change.

### Documentation

Update `AGENTS.md` in the CI section (the `Host tests and benchmark gate`
bullet):

- add `→ --structural-mutation --gate (blocking)` to the host-job step sequence,
  after `--variable-height-mutation --gate (blocking)` and before
  `--memory-shape`;
- extend the "fail the job on perf regression" sentence so it also names the
  structural-mutation gate (e.g. "synthetic, static variable-height, mutation
  variable-height, and structural-mutation gates");
- keep memory diagnostics, RSS observation, realistic relative observation, iOS,
  WASM, docs-only shortcut, ruleset, and bypass caveat wording unchanged.

The command list already documents the local `--structural-mutation --gate`
command; following the convention used for the already-promoted variable-height
and variable-height-mutation gates, the command-list comment (which describes
local invocation) stays consistent with its siblings.

### Verification Record

Create:

```text
docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
```

The record should include exact commands, exit statuses, and representative
output lines.

Local verification should include at minimum:

```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
git diff --check
rg -n "Foundation" Sources/TextEngineCore
```

Hosted verification should include:

- final PR-head Swift CI run ID;
- all three required jobs `success`;
- host job step `Run structural mutation benchmark gate` `success`, with its
  hosted Linux x86_64 `structural_mutation` rows showing `gate=pass`,
  `budget_p95_ns`, and `budget_p99_ns` (the Linux budget-fit evidence);
- proof the structural-mutation step is not `continue-on-error`;
- post-merge push run ID for the merge commit (this slice changes workflow YAML,
  so the merge is not docs-only and will not be skipped by `push.paths-ignore`).

## Acceptance Criteria

- `.github/workflows/swift-ci.yml` contains a `Run structural mutation benchmark
  gate` step that invokes `--structural-mutation --gate`.
- The structural-mutation step has no `continue-on-error: true`.
- The step is positioned after the variable-height mutation gate and before the
  memory-shape diagnostic.
- The three required job context names remain unchanged:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- `AGENTS.md` describes the structural-mutation benchmark as a blocking host-job
  gate that fails the job on perf regression.
- Local structural-mutation gate passes with `gate=pass` for all three
  scenarios.
- Hosted PR-head CI runs the structural-mutation gate step and succeeds, with
  recorded Linux p95/p99 as budget-fit evidence.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Risks And Gaps

### Hosted Linux variance could exceed current budgets

The budgets have recorded macOS headroom, but hosted Linux x86_64 differs from
macOS arm64 and has never run this mode. If the promotion PR fails because the
benchmark exceeds budget, treat that as evidence and revisit this spec
(Decision 3). Do not hide the failure with `continue-on-error` or a
workflow-only threshold.

### Host job becomes stricter and slightly longer

Unlike the Slice 21 promotion (which only changed failure semantics of an
already-running step), this slice adds a benchmark workload that did not run in
hosted CI before. The added cost is one more benchmark mode over the same
1k/100k/1M scenarios, comparable to the adjacent gates; it stays within the
job's 20-minute timeout.

### Budgets remain macOS-derived after this slice

Promotion confirms the macOS budgets fit hosted Linux but does not re-derive
Linux-native budgets. That matches the standing project posture for the other
gates (budgets macOS-calibrated unless hosted Linux evidence justifies a retune)
and is acceptable; a dedicated Linux budget re-baseline remains possible future
work.

### Bypass actors remain

The active `Main` ruleset still has a bypass-actor shape and the admin user can
bypass it. Slice 24 does not change repository bypass policy.

### WASM remains observational

The required `WASM cross-target observation` context stays green/required but
non-blocking when matching Swift SDKs are unavailable. This slice does not alter
that documented CI contract.

## Recommended Next Step

After this spec is approved, write the Slice 24 implementation plan. The plan
should be small and TDD-style: the most meaningful failing-first check is a
textual workflow assertion showing there is no blocking structural-mutation gate
step before the YAML change, and a true blocking gate (with `--gate`, without
`continue-on-error`) after it.
