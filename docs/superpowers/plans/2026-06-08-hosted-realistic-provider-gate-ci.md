# Hosted Realistic Provider Gate CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collect hosted macOS evidence for the existing realistic-provider gate and keep the GitHub Actions gate step only if pull-request-head samples prove enough margin.

**Architecture:** `TextEngineCore`, `Sources/ViewportBenchmarks`, `Tests`, and `Package.swift` stay unchanged. Slice 11 changes only `.github/workflows/swift-ci.yml` and a verification document: the workflow temporarily runs `--realistic-provider --gate` on a calibration PR head, hosted samples are collected from runs or reruns that prove the step executed on that head SHA, and the final workflow either keeps or removes the step based on the approved 70% margin policy.

**Tech Stack:** Swift Package Manager, Swift 6.2.1, `ViewportBenchmarks`, GitHub Actions, `gh`, `rg`, git.

---

## Source Design

Implement the approved Slice 11 design:

```text
docs/superpowers/specs/2026-06-08-hosted-realistic-provider-gate-ci-design.md
```

Preserve these constraints:

- Do not edit `Sources/TextEngineCore`.
- Do not edit `Sources/ViewportBenchmarks`.
- Do not edit `Tests`.
- Do not edit `Package.swift`.
- Do not change synthetic or realistic-provider benchmark budgets.
- Do not add `workflow_dispatch` as a side effect of this slice.
- Do not claim repository-level merge blocking; repository policy is separate.
- Do not keep `Run realistic provider benchmark gate` in the final workflow unless accepted hosted samples satisfy the decision policy.

## Scope Check

This plan covers one subsystem: GitHub Actions hosted evidence for the already-existing realistic-provider benchmark gate.

It does not cover:

```text
variable-height layout
storage adapters
memory hard budgets
baseline-relative benchmark gating
branch protection or rulesets
iOS, WASM, or embedded WASM CI
Swift source changes
```

## File Structure

Modify:

```text
.github/workflows/swift-ci.yml
```

Create:

```text
docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md
```

Do not modify:

```text
Sources/TextEngineCore
Sources/ViewportBenchmarks
Tests
Package.swift
```

Responsibility map:

```text
.github/workflows/swift-ci.yml
  Adds Run realistic provider benchmark gate on the calibration branch.
  Keeps the step in the final tree only if accepted hosted samples pass the margin policy.
  Does not add workflow_dispatch unless a separate explicit decision is made and recorded.

docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md
  Records local preflight, calibration branch head SHA, PR run or rerun evidence,
  accepted sample values, final CI decision, final workflow state, and non-goal checks.
```

## Decision Policy

Current realistic-provider budgets remain:

```text
budget_p95_ns=20000
budget_p99_ns=50000
```

CI enforcement is added only if at least three accepted hosted samples meet all conditions:

```text
sample_ran_realistic_provider_gate_step=true
sample_head_sha_matches_calibration_head=true
sample_job_conclusion=success
sample_gate=pass
max_hosted_p95_ns <= 14000
max_hosted_p99_ns <= 35000
```

If any condition is not met, remove the realistic-provider gate step from the final workflow and record:

```text
ci_enforcement=deferred
```

## Task 1: Preflight And Branch Setup

**Files:**
- Read: `docs/superpowers/specs/2026-06-08-hosted-realistic-provider-gate-ci-design.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift`
- Read: `docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md`

- [ ] **Step 1: Confirm the approved spec includes the revised sampling path**

Run:

```bash
rg -n "Approved design, revised after user review|pull-request-head sampling|workflow_dispatch.*default branch|branch-only.*not a valid calibration mechanism|max_hosted_p95_ns <= 14000|max_hosted_p99_ns <= 35000" docs/superpowers/specs/2026-06-08-hosted-realistic-provider-gate-ci-design.md
```

Expected: output includes all six searched requirements.

- [ ] **Step 2: Confirm the current workflow has pull-request CI and no manual dispatch trigger**

Run:

```bash
sed -n '1,80p' .github/workflows/swift-ci.yml
rg -n "workflow_dispatch" .github/workflows/swift-ci.yml
```

Expected:

```text
name: Swift CI

on:
  pull_request:
  push:
    branches:
      - main
```

`rg -n "workflow_dispatch" .github/workflows/swift-ci.yml` exits `1` with no output.

- [ ] **Step 3: Confirm the local realistic-provider gate passes before touching workflow YAML**

Run:

```bash
git status --short
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Expected:

- `git status --short` has no output.
- `swift test` exits `0`.
- `swift build -c release` exits `0`.
- `--realistic-provider --gate` exits `0` and prints one `mode=realistic_provider` line with `gate=pass`, `budget_p95_ns=20000`, and `budget_p99_ns=50000`.

- [ ] **Step 4: Create the Slice 11 implementation branch**

Run:

```bash
git switch -c slice-11-hosted-realistic-provider-gate-ci
git status --short
git branch --show-current
```

Expected:

```text
slice-11-hosted-realistic-provider-gate-ci
```

`git status --short` has no output.

## Task 2: Add The PR-Head Calibration Workflow Step

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Add the realistic-provider gate as a separate workflow step**

Modify `.github/workflows/swift-ci.yml` so the `steps` section is exactly:

```yaml
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Show toolchain
        run: |
          swift --version
          xcodebuild -version
          uname -a

      - name: Run host tests
        run: swift test

      - name: Run synthetic benchmark gate
        run: swift run -c release ViewportBenchmarks -- --gate

      - name: Run realistic provider benchmark gate
        run: swift run -c release ViewportBenchmarks -- --realistic-provider --gate

      - name: Run memory shape diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-shape

      - name: Run RSS memory observation diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-observation
```

Do not add `workflow_dispatch`.

- [ ] **Step 2: Verify the workflow diff contains only the calibration step**

Run:

```bash
git diff -- .github/workflows/swift-ci.yml
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
rg -n "workflow_dispatch" .github/workflows/swift-ci.yml
git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Expected:

- `git diff -- .github/workflows/swift-ci.yml` shows one new step between `Run synthetic benchmark gate` and `Run memory shape diagnostic`.
- The realistic-provider `rg` command prints the new step name and command.
- `rg -n "workflow_dispatch" .github/workflows/swift-ci.yml` exits `1` with no output.
- `git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift` has no output.

- [ ] **Step 3: Run local workflow-equivalent benchmark commands**

Run:

```bash
swift test
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

Expected:

- `swift test` exits `0`.
- `--gate` prints three `mode=pipeline` lines with `gate=pass`.
- `--realistic-provider --gate` prints one `mode=realistic_provider` line with `gate=pass`.
- `--memory-shape` prints three `mode=memory_shape` lines with `invariant=pass`.
- `--memory-observation` prints three `mode=memory_observation` lines with `observation=pass`.

- [ ] **Step 4: Commit the calibration workflow step**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: add realistic provider gate calibration step"
git status --short
```

Expected:

- Commit succeeds.
- `git status --short` has no output.

## Task 3: Collect Hosted Pull-Request Samples

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Later create: `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md`

- [ ] **Step 1: Push the calibration branch**

Run:

```bash
git push -u origin slice-11-hosted-realistic-provider-gate-ci
```

Expected: push succeeds and sets upstream for `slice-11-hosted-realistic-provider-gate-ci`.

- [ ] **Step 2: Open the calibration pull request**

Run:

```bash
gh pr create \
  --title "Calibrate hosted realistic provider gate" \
  --body "Slice 11 calibration PR. Keep the realistic-provider gate step in the PR head until hosted samples are collected and recorded."
```

Expected: command prints a pull request URL.

If the pull request already exists, run:

```bash
gh pr view --web=false --json number,url,headRefName,baseRefName
```

Expected: output shows `headRefName` as `slice-11-hosted-realistic-provider-gate-ci` and `baseRefName` as `main`.

- [ ] **Step 3: Capture the calibration head SHA and initial workflow run**

Run:

```bash
BRANCH="$(git branch --show-current)"
HEAD_SHA="$(git rev-parse HEAD)"
echo "branch=$BRANCH"
echo "head_sha=$HEAD_SHA"
gh run list --workflow "Swift CI" --branch "$BRANCH" --event pull_request --limit 10 --json databaseId,url,event,headBranch,headSha,status,conclusion,createdAt,updatedAt
```

Expected:

- `branch=slice-11-hosted-realistic-provider-gate-ci`.
- `head_sha=` prints the current commit hash.
- `gh run list` includes a `pull_request` run whose `headSha` matches `HEAD_SHA`.

- [ ] **Step 4: Select the matching pull-request run**

Run:

```bash
BRANCH="$(git branch --show-current)"
HEAD_SHA="$(git rev-parse HEAD)"
RUN_ID="$(gh run list --workflow "Swift CI" --branch "$BRANCH" --event pull_request --limit 20 --json databaseId,headSha,status --jq ".[] | select(.headSha == \"$HEAD_SHA\") | .databaseId" | head -n 1)"
echo "run_id=$RUN_ID"
```

Expected: `run_id=` prints a non-empty numeric value.

- [ ] **Step 5: Wait for the initial run and save attempt 1 evidence**

Run:

```bash
gh run watch "$RUN_ID" --exit-status
mkdir -p /tmp/slice11-hosted-realistic-provider-gate
gh run view "$RUN_ID" --attempt 1 --json databaseId,url,event,headBranch,headSha,status,conclusion,jobs > /tmp/slice11-hosted-realistic-provider-gate/attempt-1.json
gh run view "$RUN_ID" --attempt 1 --log > /tmp/slice11-hosted-realistic-provider-gate/attempt-1.log
rg -n "Run realistic provider benchmark gate|mode=realistic_provider.*budget_p95_ns=20000.*budget_p99_ns=50000.*gate=pass" /tmp/slice11-hosted-realistic-provider-gate/attempt-1.log
cat /tmp/slice11-hosted-realistic-provider-gate/attempt-1.json
```

Expected:

- `gh run watch "$RUN_ID" --exit-status` exits `0`.
- The `rg` command prints both the step name and the realistic-provider output line.
- `attempt-1.json` has `event` equal to `pull_request`, `headBranch` equal to `slice-11-hosted-realistic-provider-gate-ci`, `headSha` equal to the current `HEAD_SHA`, and `conclusion` equal to `success`.

- [ ] **Step 6: Rerun the same workflow run and save attempt 2 evidence**

Run:

```bash
gh run rerun "$RUN_ID"
gh run watch "$RUN_ID" --exit-status
gh run view "$RUN_ID" --attempt 2 --json databaseId,url,event,headBranch,headSha,status,conclusion,jobs > /tmp/slice11-hosted-realistic-provider-gate/attempt-2.json
gh run view "$RUN_ID" --attempt 2 --log > /tmp/slice11-hosted-realistic-provider-gate/attempt-2.log
rg -n "Run realistic provider benchmark gate|mode=realistic_provider.*budget_p95_ns=20000.*budget_p99_ns=50000.*gate=pass" /tmp/slice11-hosted-realistic-provider-gate/attempt-2.log
cat /tmp/slice11-hosted-realistic-provider-gate/attempt-2.json
```

Expected:

- `gh run watch "$RUN_ID" --exit-status` exits `0`.
- The `rg` command prints both the step name and the realistic-provider output line.
- `attempt-2.json` keeps the same `headSha` and has `conclusion` equal to `success`.

- [ ] **Step 7: Rerun the same workflow run and save attempt 3 evidence**

Run:

```bash
gh run rerun "$RUN_ID"
gh run watch "$RUN_ID" --exit-status
gh run view "$RUN_ID" --attempt 3 --json databaseId,url,event,headBranch,headSha,status,conclusion,jobs > /tmp/slice11-hosted-realistic-provider-gate/attempt-3.json
gh run view "$RUN_ID" --attempt 3 --log > /tmp/slice11-hosted-realistic-provider-gate/attempt-3.log
rg -n "Run realistic provider benchmark gate|mode=realistic_provider.*budget_p95_ns=20000.*budget_p99_ns=50000.*gate=pass" /tmp/slice11-hosted-realistic-provider-gate/attempt-3.log
cat /tmp/slice11-hosted-realistic-provider-gate/attempt-3.json
```

Expected:

- `gh run watch "$RUN_ID" --exit-status` exits `0`.
- The `rg` command prints both the step name and the realistic-provider output line.
- `attempt-3.json` keeps the same `headSha` and has `conclusion` equal to `success`.

- [ ] **Step 8: Extract the three accepted sample output lines**

Run:

```bash
rg "mode=realistic_provider.*budget_p95_ns=20000.*budget_p99_ns=50000.*gate=pass" /tmp/slice11-hosted-realistic-provider-gate/attempt-1.log > /tmp/slice11-hosted-realistic-provider-gate/accepted-lines.txt
rg "mode=realistic_provider.*budget_p95_ns=20000.*budget_p99_ns=50000.*gate=pass" /tmp/slice11-hosted-realistic-provider-gate/attempt-2.log >> /tmp/slice11-hosted-realistic-provider-gate/accepted-lines.txt
rg "mode=realistic_provider.*budget_p95_ns=20000.*budget_p99_ns=50000.*gate=pass" /tmp/slice11-hosted-realistic-provider-gate/attempt-3.log >> /tmp/slice11-hosted-realistic-provider-gate/accepted-lines.txt
wc -l /tmp/slice11-hosted-realistic-provider-gate/accepted-lines.txt
cat /tmp/slice11-hosted-realistic-provider-gate/accepted-lines.txt
```

Expected:

```text
3 /tmp/slice11-hosted-realistic-provider-gate/accepted-lines.txt
```

The file contains three realistic-provider output lines.

## Task 4: Decide Final Workflow State

**Files:**
- Modify if deferred: `.github/workflows/swift-ci.yml`
- Read: `/tmp/slice11-hosted-realistic-provider-gate/accepted-lines.txt`

- [ ] **Step 1: Compute hosted p95/p99 maxima**

Run:

```bash
awk '
{
  p95 = 0
  p99 = 0
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^p95_ns=/) {
      split($i, parts, "=")
      p95 = parts[2] + 0
    }
    if ($i ~ /^p99_ns=/) {
      split($i, parts, "=")
      p99 = parts[2] + 0
    }
  }
  if (p95 > max95) {
    max95 = p95
  }
  if (p99 > max99) {
    max99 = p99
  }
}
END {
  printf "max_hosted_p95_ns=%d\n", max95
  printf "max_hosted_p99_ns=%d\n", max99
  printf "p95_margin_ok=%s\n", max95 <= 14000 ? "true" : "false"
  printf "p99_margin_ok=%s\n", max99 <= 35000 ? "true" : "false"
}
' /tmp/slice11-hosted-realistic-provider-gate/accepted-lines.txt
```

Expected for enforcement added:

```text
p95_margin_ok=true
p99_margin_ok=true
```

Expected for enforcement deferred: either `p95_margin_ok=false`, `p99_margin_ok=false`, missing accepted sample evidence, or a hosted CI/log access blocker recorded in the verification document.

- [ ] **Step 2A: If margin is accepted, keep the workflow step**

Run:

```bash
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
git diff -- .github/workflows/swift-ci.yml
```

Expected:

- `rg` prints the retained realistic-provider gate step.
- `git diff -- .github/workflows/swift-ci.yml` has no output because the retained step was already committed in Task 2.

Use this final decision in the verification document:

```text
ci_enforcement=added
workflow_step_final_state=added
workflow_dispatch_final_state=absent
```

- [ ] **Step 2B: If margin is rejected or samples are unavailable, remove the workflow step**

Modify `.github/workflows/swift-ci.yml` so the final `steps` section is exactly:

```yaml
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Show toolchain
        run: |
          swift --version
          xcodebuild -version
          uname -a

      - name: Run host tests
        run: swift test

      - name: Run synthetic benchmark gate
        run: swift run -c release ViewportBenchmarks -- --gate

      - name: Run memory shape diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-shape

      - name: Run RSS memory observation diagnostic
        run: swift run -c release ViewportBenchmarks -- --memory-observation
```

Run:

```bash
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
rg -n "workflow_dispatch" .github/workflows/swift-ci.yml
git diff -- .github/workflows/swift-ci.yml
```

Expected:

- The realistic-provider `rg` command exits `1` with no output.
- The `workflow_dispatch` command exits `1` with no output.
- The workflow diff removes the Task 2 calibration step.

Use this final decision in the verification document:

```text
ci_enforcement=deferred
workflow_step_final_state=not_added
workflow_dispatch_final_state=absent
```

- [ ] **Step 3: Confirm no Swift source boundaries changed**

Run:

```bash
git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Expected: no output.

## Task 5: Write The Verification Document

**Files:**
- Create: `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md`

- [ ] **Step 1: Create the verification document**

Create `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md` with these sections and only exact observed values from Tasks 1 through 4:

```markdown
# Hosted Realistic Provider Gate CI Verification

Date: 2026-06-08

## Scope

Slice 11 collects hosted macOS evidence for the existing realistic-provider gate and decides whether `.github/workflows/swift-ci.yml` should run `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`.

The slice does not change `TextEngineCore`, `Sources/ViewportBenchmarks`, `Tests`, `Package.swift`, benchmark budgets, memory budgets, branch protection, rulesets, cross-target CI, or variable-height layout.

## Local Preflight

Record the exact command results for:

```text
git status --short
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

## Calibration Branch

Record the branch name, the calibration head SHA printed by `git rev-parse HEAD`, `workflow_dispatch_on_main=false`, and `workflow_dispatch_reason=not-introduced`.

## Hosted Samples

Record one block per accepted sample. Each block must include `sample`, `run_id`, `run_attempt`, `run_url`, `event`, `head_branch`, `head_sha`, `conclusion`, `step_ran`, and the exact realistic-provider `output` line copied from the corresponding attempt log. Use run attempts 1, 2, and 3 if reruns were used.

## Hosted Decision

Record `accepted_hosted_samples`, `max_hosted_p95_ns`, `max_hosted_p99_ns`, `p95_margin_threshold_ns=14000`, `p99_margin_threshold_ns=35000`, the selected `ci_enforcement` value, the final workflow step state, and `workflow_dispatch_final_state=absent`.

## Final Local Verification

Record the exact command results for:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

## Workflow Scan

Record the final scan result for:

```text
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
rg -n "workflow_dispatch" .github/workflows/swift-ci.yml
```

## Non-Goal Checks

Record:

```text
git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
```

Result must be no output.
```

- [ ] **Step 2: Verify the document records the mandatory evidence**

Run:

```bash
rg -n "ci_enforcement=|workflow_step_final_state=|workflow_dispatch_final_state=|max_hosted_p95_ns=|max_hosted_p99_ns=|sample=1|sample=2|sample=3|git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift" docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md
```

Expected:

- The `rg` command prints every required evidence marker.

## Task 6: Final Verification And Commits

**Files:**
- Modify or keep: `.github/workflows/swift-ci.yml`
- Create: `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md`

- [ ] **Step 1: Run final local verification**

Run:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

Expected:

- `swift test` exits `0`.
- `swift build -c release` exits `0`.
- `--gate` prints three `mode=pipeline` lines with `gate=pass`.
- `--realistic-provider --gate` prints one `mode=realistic_provider` line with `gate=pass`.
- `--memory-shape` prints three `mode=memory_shape` lines with `invariant=pass`.
- `--memory-observation` prints three `mode=memory_observation` lines with `observation=pass`.

- [ ] **Step 2: Run final workflow and boundary scans**

Run:

```bash
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
rg -n "workflow_dispatch" .github/workflows/swift-ci.yml
git diff -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
git status --short
```

Expected for `ci_enforcement=added`:

- The realistic-provider `rg` command prints the retained step and command.
- The `workflow_dispatch` command exits `1` with no output.
- The source-boundary diff has no output.
- `git status --short` shows only `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md`.

Expected for `ci_enforcement=deferred`:

- The realistic-provider `rg` command exits `1` with no output.
- The `workflow_dispatch` command exits `1` with no output.
- The source-boundary diff has no output.
- `git status --short` shows `.github/workflows/swift-ci.yml` and `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md`.

- [ ] **Step 3: Commit the final workflow decision and verification**

For `ci_enforcement=added`, run:

```bash
git add .github/workflows/swift-ci.yml docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md
git commit -m "ci: run hosted realistic provider gate"
```

For `ci_enforcement=deferred`, run:

```bash
git add .github/workflows/swift-ci.yml docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md
git commit -m "ci: defer hosted realistic provider gate"
```

Expected: commit succeeds.

- [ ] **Step 4: Push the final branch state**

Run:

```bash
git push
```

Expected: push succeeds.

- [ ] **Step 5: Record final hosted PR verification**

Run:

```bash
BRANCH="$(git branch --show-current)"
HEAD_SHA="$(git rev-parse HEAD)"
gh run list --workflow "Swift CI" --branch "$BRANCH" --event pull_request --limit 10 --json databaseId,url,event,headBranch,headSha,status,conclusion,createdAt,updatedAt
```

Expected:

- A final pull-request run appears for the current `HEAD_SHA`.
- If `ci_enforcement=added`, that run includes `Run realistic provider benchmark gate` and exits `0`.
- If `ci_enforcement=deferred`, that run does not include `Run realistic provider benchmark gate` and exits `0`.

Append this final run ID, URL, head SHA, and conclusion to `docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md`, then run:

```bash
git add docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md
git commit -m "docs: record hosted realistic gate ci verification"
git push
```

Expected: commit and push succeed.

- [ ] **Step 6: Final whole-slice source-boundary check**

Run:

```bash
git diff main..HEAD -- Sources/TextEngineCore Sources/ViewportBenchmarks Tests Package.swift
git status --short
```

Expected:

- The source-boundary diff has no output.
- `git status --short` has no output.

## Self-Review Checklist

After executing all tasks, verify:

- Every accepted hosted sample records run ID, run URL, event, head branch, head SHA, conclusion, step proof, and output line.
- The final `ci_enforcement` value matches the 70% margin policy.
- The final workflow state matches the recorded decision.
- `workflow_dispatch` is absent unless an explicit separate decision introduced it.
- No Swift source, tests, or package manifest changed.
- The verification document does not claim repository-level merge blocking.
