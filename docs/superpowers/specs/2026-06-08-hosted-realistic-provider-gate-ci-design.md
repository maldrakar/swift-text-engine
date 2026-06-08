# Hosted Realistic Provider Gate CI Design

Date: 2026-06-08

## Status

Approved design.

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

A failing workflow only blocks merges if repository policy requires that
status check. This slice may make the workflow fail when the realistic-provider
gate fails, but it does not claim repository-level merge blocking.

## Scope

Collect same-environment hosted-runner evidence for the existing
realistic-provider gate and add the GitHub Actions workflow step only if the
evidence supports reliable enforcement.

The selected hosted sampling mechanism is a controlled `workflow_dispatch`
calibration path on the existing `Swift CI` workflow. A calibration branch will
contain:

- a `workflow_dispatch` trigger;
- a separate `Run realistic provider benchmark gate` step;
- the existing host tests, synthetic benchmark gate, memory-shape diagnostic,
  and RSS memory observation diagnostic unchanged.

The final workflow keeps the realistic-provider gate step only if accepted
hosted samples satisfy the decision policy below. If samples cannot be
collected, cannot be verified, or do not have enough margin, the final workflow
keeps enforcement deferred and records the reason.

## Goals

- Add a deliberate hosted sampling path that avoids Slice 10's commit
  sequencing failure.
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

Use `workflow_dispatch` on the existing `Swift CI` workflow as the hosted
calibration path.

This keeps the sampling environment close to the final workflow while giving
the implementer control over which head SHA is evaluated. The accepted samples
must come from runs whose logs prove that the realistic-provider gate step
actually executed. Recording only run IDs is insufficient.

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

#### Pull-Request Head Retains The Step

Collect samples from pull-request runs while ensuring the PR head still
contains the realistic-provider gate step.

This mirrors the normal PR path, but it is easier to repeat Slice 10's mistake:
if the step is removed before the run happens or before samples are collected,
the run no longer proves the intended gate.

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

- `.github/workflows/swift-ci.yml` adds `workflow_dispatch`.
- `.github/workflows/swift-ci.yml` contains `Run realistic provider benchmark
  gate` while hosted evidence is collected.
- `.github/workflows/swift-ci.yml` keeps that step in the final tree only if
  accepted hosted samples satisfy the decision policy.
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
3. Add `workflow_dispatch` and the realistic-provider gate step on a
   calibration branch.
4. Push the branch.
5. Trigger `Swift CI` at least three times against the same calibration head
   SHA through `workflow_dispatch`, or use equivalent pull-request runs if they
   evaluate that exact head.
6. For each candidate run, inspect logs and metadata.
7. Accept a run as a sample only if it ran the realistic-provider gate step and
   exposes the expected output line.
8. Decide whether to keep the final workflow step.
9. Record the decision in the verification document.
10. Run final local/source-boundary checks.

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
failure step.

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

If GitHub access, workflow dispatch, or log access is unavailable, do not infer
or fabricate hosted samples. Record the blocker and keep enforcement deferred.

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
rg -n "workflow_dispatch|Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
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
absent.

## Acceptance Criteria

- The final design does not claim repository-level merge blocking.
- `workflow_dispatch` is available on `Swift CI` for controlled hosted
  calibration, unless GitHub access prevents the workflow change from being
  tested and the limitation is recorded.
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
