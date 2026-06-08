# Hosted Realistic Provider Gate CI Design

Date: 2026-06-08

## Status

Approved design, revised after user review.

## Source Context

This design is Slice 11 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slices 1 through 10 built the current fixed-height proof envelope:

- fixed-height viewport virtualization;
- external document/source provider traversal;
- synthetic p95/p99 benchmark gate;
- realistic 100,000-line, 11.2 MB provider benchmark;
- GitHub Actions host tests and synthetic benchmark gate;
- documented GitHub ruleset blocker for the current private repository state;
- deterministic core-owned memory-shape diagnostic and CI wiring;
- concern-based decomposition of `ViewportBenchmarks`;
- host-only RSS memory observation diagnostic and CI wiring;
- local `--realistic-provider --gate` support with calibrated p95/p99 budgets.

The product brief requires stable scroll performance on 100,000+ lines and
documents larger than 10 MB, plus regression benchmarks that block merge on
performance degradation. In this repository, that merge-blocking behavior still
depends on repository policy requiring the reporting workflow as a status
check. Slice 10 made this command valid and locally gateable:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Slice 10 intentionally left GitHub Actions enforcement deferred. The temporary
workflow step was added and removed in the same branch, and the observed
pull-request run evaluated the post-defer head where the step no longer
existed. Slice 11 closes that sequencing weakness by collecting hosted-runner
samples from a commit that still contains the realistic-provider gate step.

GitHub Actions documentation states that `workflow_dispatch` triggers only
receive events when the workflow file is on the default branch:

```text
https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_dispatch
```

The current `main` workflow does not include `workflow_dispatch`, so Slice 11
must not rely on adding that trigger only on a calibration branch.

A failing workflow only blocks merges if repository policy requires that
status check. This slice may make the workflow fail when the realistic-provider
gate fails, but it does not claim repository-level merge blocking.

## Scope

Collect same-environment hosted-runner evidence for the existing
realistic-provider gate and add the GitHub Actions workflow step only if the
evidence supports reliable enforcement.

The selected hosted sampling mechanism is pull-request-head sampling on the
existing `Swift CI` workflow. A calibration branch will contain:

- a separate `Run realistic provider benchmark gate` step;
- the existing host tests, synthetic benchmark gate, memory-shape diagnostic,
  and RSS memory observation diagnostic unchanged.

The calibration branch must keep the realistic-provider gate step in its head
until accepted hosted samples are collected and recorded. `workflow_dispatch`
may be used only if preflight proves the trigger already exists on `main`, or
if a separate preliminary change first lands the trigger on `main`.

The final workflow keeps the realistic-provider gate step only if accepted
hosted samples satisfy the decision policy below. If samples cannot be
collected, cannot be verified, or do not have enough margin, the final workflow
keeps enforcement deferred and records the reason.

## Goals

- Add a deliberate hosted sampling path that avoids Slice 10's commit
  sequencing failure and does not depend on branch-only `workflow_dispatch`.
- Collect at least three accepted macOS hosted-runner samples of
  `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`.
- Prove each accepted sample evaluated a head commit that still contained the
  realistic-provider gate step.
- Record run IDs, run URLs, event types, head branches, head SHAs, job
  conclusions, realistic-provider output lines, p95/p99 values, budgets, and
  gate results.
- Keep the final `Run realistic provider benchmark gate` workflow step only
  when accepted samples support enforcement.
- Preserve existing local benchmark behavior and budgets.
- Preserve existing host tests, synthetic gate, memory-shape diagnostic, and
  RSS memory observation workflow behavior.
- Record final verification evidence and the CI enforcement decision.

## Non-Goals

Slice 11 does not:

- change `TextEngineCore` source or public API;
- change `Sources/ViewportBenchmarks`;
- change `Tests`;
- change `Package.swift`;
- change the existing synthetic or realistic-provider benchmark budgets;
- add storage adapters such as memory-mapped files, ropes, piece tables, or
  editor buffers;
- add variable-height layout, localized invalidation, shaping, rasterization,
  or UI integration;
- add RSS, heap, malloc, allocation-count, or peak-memory hard budgets;
- add checked-in baseline-relative benchmark comparison;
- require GitHub rulesets or legacy branch protection;
- close the external repository-policy requirement that turns a failing
  workflow into a merge blocker;
- add iOS, WASM, or embedded WASM CI;
- make `ViewportBenchmarks` portable outside the existing host-only benchmark
  target.

## Selected Approach

Use pull-request-head sampling on the existing `Swift CI` workflow as the
primary hosted calibration path.

This path works with the current workflow triggers because `Swift CI` already
runs on pull requests. The calibration branch must keep the realistic-provider
gate step present while samples are collected. The accepted samples must come
from runs whose metadata and logs prove that the realistic-provider gate step
actually executed on that head SHA. Recording only run IDs is insufficient.

The workflow step should be separate:

```text
Run realistic provider benchmark gate
```

with this command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Separate steps keep synthetic-gate, realistic-provider, memory-shape, and RSS
observation failures easy to distinguish.

### Alternatives Considered

#### Workflow Dispatch After Default-Branch Trigger

First land `workflow_dispatch` on `main`, then dispatch calibration runs
against the calibration branch.

This gives direct manual control over repeated runs, but it requires a
preliminary `main` workflow change before dispatch is available. A branch-only
addition of `workflow_dispatch` is not a valid calibration mechanism for the
current repository state.

#### Temporary Calibration Workflow

Add a separate temporary workflow only for sampling, then remove it after
calibration.

This avoids touching production `Swift CI` until after the decision, but the
evidence is less direct because the final workflow shape differs from the
calibration workflow.

#### Immediate CI Enforcement From Local Budgets

Add the realistic-provider gate step directly because local budgets have wide
margin.

This is rejected. The Slice 10 local gate is useful, but CI enforcement needs
same-environment hosted evidence.

## Architecture

Slice 11 is an infrastructure and verification slice.

Expected file-level responsibilities:

- `.github/workflows/swift-ci.yml` contains `Run realistic provider benchmark
  gate` while hosted evidence is collected.
- `.github/workflows/swift-ci.yml` keeps that step in the final tree only if
  accepted hosted samples satisfy the decision policy.
- `.github/workflows/swift-ci.yml` does not add `workflow_dispatch` as a
  side effect of this slice. If `workflow_dispatch` is introduced, it must be
  explicit in the plan and verification, and its final retained-or-removed
  state must be recorded.
- `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md`
  records local preflight, hosted sample evidence, final workflow state, and
  source-boundary checks.
- `docs/superpowers/specs/2026-06-08-hosted-realistic-provider-gate-ci-design.md`
  records the approved design.

No Swift source file owns Slice 11 behavior. The benchmark command already
exists and is not redesigned in this slice.

## Calibration Flow

The implementation should follow this flow:

1. Start from `main` with clean local status.
2. Run local preflight.
3. Add the realistic-provider gate step on a calibration branch.
4. Push the branch and open or update a pull request targeting `main`.
5. Keep the gate step present in the calibration branch head while samples are
   collected.
6. Collect at least three `Swift CI` pull-request runs or reruns against the
   same calibration head SHA. Equivalent `workflow_dispatch` runs are valid
   only if preflight proves the trigger exists on `main` or a separate
   preliminary change has already landed it there.
7. For each candidate run, inspect logs and metadata.
8. Accept a run as a sample only if it ran the realistic-provider gate step and
   exposes the expected output line.
9. Decide whether to keep the final workflow step.
10. Record the decision in the verification document.
11. Run final local/source-boundary checks.

Accepted sample records must include:

- run ID;
- run URL;
- event type;
- head branch;
- head SHA;
- job conclusion;
- realistic-provider output line;
- `p95_ns`;
- `p99_ns`;
- `budget_p95_ns`;
- `budget_p99_ns`;
- `gate`.

## Decision Policy

Current realistic-provider budgets are:

```text
budget_p95_ns=20000
budget_p99_ns=50000
```

CI enforcement is supported only if at least three accepted hosted samples meet
all of these conditions:

- each sample ran the `Run realistic provider benchmark gate` step;
- each sample evaluated a head SHA where the step was still present;
- each job concluded successfully;
- each realistic-provider output line has `gate=pass`;
- maximum accepted `p95_ns` is less than or equal to 70% of `20000`;
- maximum accepted `p99_ns` is less than or equal to 70% of `50000`.

The explicit margin thresholds are:

```text
max_hosted_p95_ns <= 14000
max_hosted_p99_ns <= 35000
```

Those thresholds do not change the benchmark budgets. They decide only whether
the existing budgets have enough hosted-runner margin to be useful as a CI
failure step. The 70% cutoff leaves 30% headroom for normal hosted-runner
variance while rejecting a step that technically passes but already consumes
most of the budget and would likely be noisy.

If the samples fail, are too noisy, cannot be collected, or cannot prove that
the step executed, Slice 11 records:

```text
ci_enforcement=deferred
```

and the final workflow does not include the realistic-provider gate step.

If the accepted samples satisfy the policy, Slice 11 records:

```text
ci_enforcement=added
```

and the final workflow includes the realistic-provider gate step.

## Error Handling

If local `--realistic-provider --gate` fails before hosted sampling, stop before
workflow enforcement and record benchmark instability as the blocker.

If GitHub access, pull-request CI, reruns, or log access is unavailable, do not
infer or fabricate hosted samples. Record the blocker and keep enforcement
deferred.

If `workflow_dispatch` is attempted and returns unavailable because the trigger
is absent from `main`, fall back to pull-request-head sampling. Do not treat a
branch-only `workflow_dispatch` addition as a valid sample path.

If a hosted run succeeds but logs cannot prove the realistic-provider gate step
ran, reject that run as an accepted sample.

If hosted samples exceed the margin threshold, do not loosen budgets in this
slice. Keep the local gate, defer workflow enforcement, and record the observed
hosted values.

If the final workflow includes the step and the first final verification run
fails, treat that as evidence against enforcement unless the failure is clearly
unrelated to the realistic-provider gate and can be verified separately.

## Verification Plan

Required local preflight:

```text
git status --short
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Required hosted evidence, if GitHub access allows it:

```text
gh run list --workflow "Swift CI" --limit 20
gh run view <run-id> --json databaseId,url,event,headBranch,headSha,status,conclusion
gh run view <run-id> --log
```

The exact `gh` command shape may vary during implementation, but the
verification document must include enough data to prove accepted runs evaluated
the intended head and included the realistic-provider gate step.

Required final local/source-boundary checks:

```text
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
rg -n "workflow_dispatch" .github/workflows/swift-ci.yml
git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

If enforcement is added, a final hosted `Swift CI` run should be recorded after
the workflow reaches its final state. If enforcement is deferred, the
verification document should record the final workflow scan proving the step is
absent. In both outcomes, the verification document must record whether
`workflow_dispatch` is present or absent in the final workflow and why. No
matches from the `workflow_dispatch` scan are valid when the trigger was not
introduced.

## Acceptance Criteria

- The final design does not claim repository-level merge blocking.
- The primary sampling path uses pull-request runs or reruns while the
  calibration branch head still contains the realistic-provider gate step.
- `workflow_dispatch` is not required for Slice 11 and is not introduced as a
  side effect. If it is used, the verification record proves the trigger was
  already present on `main` or was landed through a separate preliminary change.
- At least three accepted hosted samples are recorded before CI enforcement is
  added.
- Each accepted hosted sample proves the realistic-provider gate step ran on a
  head SHA that still contained the step.
- CI includes `Run realistic provider benchmark gate` only if accepted samples
  satisfy the decision policy.
- If CI enforcement is deferred, the verification document gives a concrete
  evidence-backed reason.
- Existing local `ViewportBenchmarks` modes and budgets are unchanged.
- Existing host tests, synthetic gate, memory-shape diagnostic, and RSS memory
  observation workflow behavior are unchanged.
- `TextEngineCore`, `Sources/ViewportBenchmarks`, `Tests`, and `Package.swift`
  remain unchanged.
