# Variable-Height Mutation CI Gate Promotion Design

Date: 2026-06-18

## Status

Draft design direction, written for user review.

## Source Context

This is Slice 21 of SwiftTextEngine, following the Slice 20 post-slice review:

```text
docs/superpowers/reviews/2026-06-17-slice-20-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses. That requirement now has a
trusted repository-policy path:

- the active default-branch ruleset requires the three Swift CI job contexts for
  normal PR flow:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- docs-only PRs still emit those contexts through a lightweight path;
- the docs-only classifier is executed from the PR base commit under
  `$RUNNER_TEMP/trusted-ci`, not from PR-owned code;
- policy-sensitive `.github/workflows/**` and `.github/scripts/**` paths are
  deny-first and always take the heavy Swift CI path.

Slice 17 introduced the mutable variable-height reference provider and benchmark
path:

- `TextEngineReferenceProviders.FenwickLineMetrics`;
- `--variable-height-mutation`;
- local `--variable-height-mutation --gate` budgets;
- hosted CI observation with `continue-on-error: true` and no `--gate`.

Slice 20 closed the last known docs-only path-classification gap. Its
post-slice review recommends Slice 21 as:

```text
Option A: Promote `--variable-height-mutation` To A Hosted Blocking Gate
```

Current host CI shape:

```yaml
- name: Run variable-height benchmark gate
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height --gate

- name: Observe variable-height mutation benchmark
  continue-on-error: true
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation
```

The mutation mode already has executable-owned budgets:

| Scenario | p95 budget | p99 budget |
| --- | ---: | ---: |
| `1k_lines_20_visible_overscan_0` | 5,000 ns | 10,000 ns |
| `100k_lines_80_visible_overscan_5` | 20,000 ns | 25,000 ns |
| `1m_lines_200_visible_overscan_50` | 60,000 ns | 75,000 ns |

Recorded Slice 17 hosted observation evidence was comfortably under those
budgets:

| Run | Event | Head / merge | 1M p99 |
| --- | --- | --- | ---: |
| `27515537441` | pull_request | `a9e291b` | 10,939 ns |
| `27533521987` | push | `829845e` | 10,620 ns |

A fresh local pre-spec sanity run on 2026-06-18 also passed the existing gate:

```text
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 ... p95_ns=397 p99_ns=447 ... budget_p95_ns=5000 budget_p99_ns=10000 gate=pass
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 ... p95_ns=1575 p99_ns=1701 ... budget_p95_ns=20000 budget_p99_ns=25000 gate=pass
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 ... p95_ns=5097 p99_ns=5326 ... budget_p95_ns=60000 budget_p99_ns=75000 gate=pass
```

## Problem

The mutable variable-height path is proven locally and observed in hosted CI, but
hosted CI does not yet fail when that path regresses.

Today, the host job can stay green if `--variable-height-mutation` exceeds its
budgets or exits non-zero, because the step is explicitly `continue-on-error`
and does not pass `--gate`. That leaves a real enforcement gap:

- regressions in `FenwickLineMetrics` update/query behavior may be visible but
  non-blocking;
- regressions in the unchanged generic variable-height core path may be visible
  but non-blocking when exercised through mutation + recompute;
- the brief's "benchmark gates block merge" principle is not yet true for the
  dynamic height-remeasurement path.

Now that required checks and docs-only shortcut trust are hardened, the next
highest-value governance step is to make the mutation benchmark fail the same
required host job as the synthetic and static variable-height gates.

## Scope

Slice 21 promotes the existing mutation benchmark from hosted observation to a
hosted blocking gate.

Expected implementation surface:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`

Expected paper trail:

- this design spec;
- a task-by-task plan after this spec is approved;
- a verification record with local and hosted evidence;
- a post-slice review after implementation and merge.

The slice should not change Swift source unless implementation verification
finds that the existing benchmark executable gate is broken.

## Goals

- Make `--variable-height-mutation --gate` run in the hosted
  `Host tests and benchmark gate` job.
- Remove `continue-on-error: true` from the mutation benchmark CI step.
- Rename the step from observation to gate, for example:
  `Run variable-height mutation benchmark gate`.
- Keep the step in the host job after `Run variable-height benchmark gate` and
  before memory diagnostics.
- Keep benchmark budgets in `Sources/ViewportBenchmarks`, not duplicated in
  workflow YAML.
- Keep the current mutation budgets unless fresh hosted Linux evidence proves
  they are unstable.
- Keep the three required job contexts unchanged.
- Keep trusted docs-only PR behavior unchanged.
- Update `AGENTS.md` so it describes the mutation gate as blocking in hosted CI.
- Record local and hosted proof that mutation benchmark output includes
  `budget_p95_ns`, `budget_p99_ns`, and `gate=pass`, and that the hosted step is
  no longer `continue-on-error`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No `FenwickLineMetrics` API changes.
- No benchmark workload redesign.
- No benchmark budget retune unless the approved spec is revisited with fresh
  hosted evidence.
- No new benchmark mode.
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

### Decision 1 - Promote the existing executable gate path

The workflow should call the benchmark executable exactly as local verification
does:

```bash
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation --gate
```

Rejected alternative: encode mutation budgets in workflow YAML. Budgets already
live with the benchmark scenarios and are printed by the executable. A workflow
budget copy would create two sources of truth.

### Decision 2 - Keep current budgets for promotion

The current budgets are intentionally wider than observed local and hosted
numbers. The latest recorded hosted 1M p99 for this mode is about `10,939 ns`
against a `75,000 ns` budget, roughly a 6.8x margin. The 2026-06-18 local 1M
p99 was `5,326 ns`, roughly a 14x margin.

This slice should promote the existing budgets rather than retune them. If the
first hosted PR-head run fails because hosted Linux behavior no longer fits the
existing budgets, implementation should stop and update the design with the new
evidence instead of silently widening thresholds.

### Decision 3 - Keep the host job order

The mutation gate should remain immediately after the static variable-height
gate:

1. `swift test`
2. synthetic benchmark gate
3. static variable-height benchmark gate
4. mutation variable-height benchmark gate
5. memory-shape diagnostic
6. RSS memory observation
7. PR-only realistic relative observation

This keeps all blocking latency gates together and fails before lower-priority
diagnostics if the mutation path regresses.

### Decision 4 - Do not change required context names

The ruleset already requires `Host tests and benchmark gate`. Slice 21 makes
that job stricter, but it should not create or rename required contexts.

The iOS and WASM jobs remain unchanged.

### Decision 5 - Leave docs-only behavior unchanged

Docs-only PRs should still complete the required contexts through the trusted
lightweight path and skip heavy Swift work. The mutation gate is part of the
heavy host path and should run whenever `docs_only_pr != 'true'`.

Policy-sensitive workflow/helper changes are already non-doc under Slice 20, so
the Slice 21 workflow edit itself will be tested by the heavy path in its PR.

### Decision 6 - A one-line Swift command needs no shell override

Unlike the PR-only realistic relative observation step, the mutation gate step
does not use `set -o pipefail`, pipes, or shell-specific behavior. It can stay a
plain `run:` line and does not need `shell: bash`.

The important workflow property is absence of `continue-on-error: true` on this
step.

## Implementation Architecture

### Workflow

Change the host job step from:

```yaml
- name: Observe variable-height mutation benchmark
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  continue-on-error: true
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation
```

to:

```yaml
- name: Run variable-height mutation benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation --gate
```

No other workflow step should need to move or change.

### Documentation

Update `AGENTS.md` in the CI section:

- replace `--variable-height-mutation` observation wording with
  `--variable-height-mutation --gate`;
- state that synthetic, static variable-height, and mutation variable-height
  gates fail the host job on performance regression;
- keep memory diagnostics, RSS observation, realistic relative observation,
  iOS, WASM, docs-only shortcut, ruleset, and bypass caveat wording unchanged
  unless the workflow actually changes.

The command list already documents the local mutation gate command and should
remain consistent with the workflow wording.

### Verification Record

Create:

```text
docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
```

The record should include exact commands, exit statuses, and representative
output lines.

Local verification should include at minimum:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
git diff --check
rg -n "Foundation" Sources/TextEngineCore
```

Because this slice changes the hosted gate sequence, the plan should also
consider running the adjacent local gates for confidence:

```bash
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Hosted verification should include:

- final PR-head Swift CI run ID;
- all three required jobs `success`;
- host job step `Run variable-height mutation benchmark gate` `success`;
- hosted mutation rows with `gate=pass` and budget fields;
- proof the mutation step is not `continue-on-error`;
- post-merge push run ID for the merge commit, unless the merge is docs-only and
  intentionally skipped by `push.paths-ignore` (not expected here because this
  slice changes workflow YAML).

## Acceptance Criteria

- `.github/workflows/swift-ci.yml` no longer contains
  `Observe variable-height mutation benchmark`.
- The mutation step is named as a gate and invokes
  `--variable-height-mutation --gate`.
- The mutation step has no `continue-on-error: true`.
- The three required job context names remain unchanged:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- `AGENTS.md` describes the mutation benchmark as a blocking host-job gate.
- Local mutation gate passes with `gate=pass` for all three scenarios.
- Hosted PR-head CI runs the mutation gate step and succeeds.
- Post-merge push CI on `main` anchors the merged workflow behavior.

## Risks And Gaps

### Hosted Linux variance could exceed current budgets

The current budgets have recorded headroom, but hosted runners can vary. If the
promotion PR fails because the benchmark exceeds budget, treat that as evidence
and revisit the spec. Do not hide the failure with `continue-on-error` or a
workflow-only threshold.

### Host job becomes stricter but not materially longer

The benchmark already runs in hosted CI today. Adding `--gate` does not add a new
benchmark workload; it changes failure semantics and output fields.

### Bypass actors remain

The active ruleset still has a bypass actor shape. Slice 21 does not change
repository bypass policy.

### Provider cross-target coverage remains separate

`TextEngineReferenceProviders` is still not part of the hosted iOS/WASM
cross-target helper surface. That is Slice 21 non-goal territory and should stay
separate from mutation gate promotion.

### WASM remains observational

The required `WASM cross-target observation` context remains green/required but
the helper is still non-blocking when matching Swift SDKs are unavailable. This
slice does not alter that documented CI contract.

## Recommended Next Step

After this spec is approved, write the Slice 21 implementation plan. The plan
should be small and TDD-style where possible, but this is primarily a workflow
promotion slice: the most meaningful failing-first check is an executable or
textual workflow assertion showing the mutation step is still observation-only
before the YAML change and is a true gate after the YAML change.
