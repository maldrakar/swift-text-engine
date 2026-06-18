# Variable-Height Mutation CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the existing variable-height mutation benchmark from hosted observation to a blocking gate in the required host CI job.

**Architecture:** Keep `TextEngineCore`, `TextEngineReferenceProviders`, benchmark scenarios, and budgets unchanged. Change only the host GitHub Actions step so it invokes the executable-owned `--variable-height-mutation --gate` path without `continue-on-error`, then update durable repo guidance and verification evidence. The required job context names and trusted docs-only shortcut stay unchanged.

**Tech Stack:** GitHub Actions YAML, SwiftPM `ViewportBenchmarks`, Ruby YAML parser for workflow-shape assertions, GitHub CLI, Markdown. Spec: `docs/superpowers/specs/2026-06-18-variable-height-mutation-ci-gate-promotion-design.md`.

---

## Scope Check

This plan implements Slice 21:

```text
docs/superpowers/specs/2026-06-18-variable-height-mutation-ci-gate-promotion-design.md
```

This slice covers one operational subsystem: promotion of an already-existing
benchmark executable gate into the existing hosted host job.

This plan does not change:

- `Sources/TextEngineCore`
- `Sources/TextEngineReferenceProviders`
- `Tests/**`
- `Package.swift`
- benchmark mode parsing
- benchmark workloads
- benchmark budgets
- required GitHub status context names
- docs-only detector behavior
- repository rulesets
- iOS or WASM job behavior

If any verification step shows that `--variable-height-mutation --gate` itself
is broken or unstable on hosted Linux, stop implementation and revise the spec
with that evidence instead of widening budgets or restoring `continue-on-error`.

## File Structure

- Modify `.github/workflows/swift-ci.yml`: rename the mutation step to
  `Run variable-height mutation benchmark gate`, remove its
  `continue-on-error: true`, and add `--gate` to the existing
  `--variable-height-mutation` command. Do not rename jobs or move unrelated
  steps.
- Modify `AGENTS.md`: update the CI section so it describes the mutation
  benchmark as a blocking host-job gate and keeps the docs-only, iOS, WASM,
  ruleset, and bypass wording unchanged.
- Create `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`:
  record local command evidence, workflow-shape proof, non-source scope proof,
  PR-head hosted proof, and post-merge hosted proof.
- Use temporary files under `/private/tmp/slice-21-*` for command captures and
  hosted log snippets.

## Task 1: Preflight And Red Workflow Proof

**Files:**
- Read: `docs/superpowers/specs/2026-06-18-variable-height-mutation-ci-gate-promotion-design.md`
- Read: `docs/superpowers/reviews/2026-06-17-slice-20-post-slice-review.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Write temporary command outputs under `/private/tmp/slice-21-*`

- [ ] **Step 1: Confirm branch and preserve existing docs work**

Run:

```bash
git status --short --branch
git branch --show-current
```

Expected: branch is `slice-21-variable-height-mutation-gate`. Existing
uncommitted files, if any, are limited to the Slice 21 spec/plan docs unless the
current worker intentionally added more. If `.github/workflows/swift-ci.yml`,
`AGENTS.md`, or the Slice 21 verification record are already modified, inspect
the diff before continuing and preserve user-owned changes.

- [ ] **Step 2: Confirm the approved spec content**

Run:

```bash
rg -n "Variable-Height Mutation CI Gate Promotion Design|Slice 21|Promote the existing executable gate path|Keep current budgets|Do not change required context names|Leave docs-only behavior unchanged" docs/superpowers/specs/2026-06-18-variable-height-mutation-ci-gate-promotion-design.md
```

Expected: command exits `0` and prints matches for all listed spec anchors.

- [ ] **Step 3: Confirm Slice 20 handed off to this direction**

Run:

```bash
rg -n 'Option A: Promote `--variable-height-mutation` To A Hosted Blocking Gate|Host tests and benchmark gate|policy-sensitive Markdown' docs/superpowers/reviews/2026-06-17-slice-20-post-slice-review.md
```

Expected: command exits `0`. The review recommends promoting the mutation
benchmark gate after the trusted docs-only path hardening.

- [ ] **Step 4: Capture the current observation-only workflow state**

Run:

```bash
ruby -ryaml -e '
workflow = YAML.load_file(".github/workflows/swift-ci.yml")
steps = workflow.fetch("jobs").fetch("host-tests-and-benchmark-gate").fetch("steps")
mutation = steps.find { |step| step["name"].to_s.include?("variable-height mutation") }
abort("missing mutation step") unless mutation
puts mutation.fetch("name")
puts mutation.key?("continue-on-error") ? "continue_on_error_present" : "continue_on_error_absent"
puts mutation.fetch("run")
'
```

Expected output before implementation:

```text
Observe variable-height mutation benchmark
continue_on_error_present
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation
```

- [ ] **Step 5: Run the future-state workflow assertion and verify it fails red**

Run:

```bash
set +e
ruby -ryaml -e '
step = YAML.load_file(".github/workflows/swift-ci.yml")
  .fetch("jobs")
  .fetch("host-tests-and-benchmark-gate")
  .fetch("steps")
  .find { |candidate| candidate["name"].to_s.include?("variable-height mutation") }
abort("missing mutation step") unless step
abort("mutation step is not named as a gate") unless step["name"] == "Run variable-height mutation benchmark gate"
abort("mutation step still has continue-on-error") if step.key?("continue-on-error")
abort("mutation step does not run --variable-height-mutation --gate") unless step["run"].to_s.include?("--variable-height-mutation --gate")
puts "mutation_gate_step=ok"
'
status=$?
set -e
echo "future_state_assertion_status=${status}"
test "$status" -ne 0
```

Expected output before implementation includes:

```text
mutation step is not named as a gate
future_state_assertion_status=1
```

This is the failing-first check for the workflow promotion.

- [ ] **Step 6: Confirm the executable-owned mutation gate already passes locally**

Run:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Expected: command exits `0` and prints exactly three
`mode=variable_height_mutation provider=fenwick ... gate=pass` rows. Each row
must include `budget_p95_ns=`, `budget_p99_ns=`, and `gate=pass`.

- [ ] **Step 7: Confirm no Swift source/package scope is needed**

Run:

```bash
git diff --name-only -- Sources Tests Package.swift
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Expected: no output from either command. If source/package files appear, inspect
the diff and stop unless the spec has been revisited.

## Task 2: Promote The Hosted Workflow Step

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Apply the minimal workflow patch**

Use `apply_patch` with this patch:

```diff
*** Begin Patch
*** Update File: .github/workflows/swift-ci.yml
@@
-      - name: Observe variable-height mutation benchmark
+      - name: Run variable-height mutation benchmark gate
         if: steps.change-scope.outputs.docs_only_pr != 'true'
-        continue-on-error: true
-        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation
+        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation --gate
*** End Patch
```

- [ ] **Step 2: Verify the future-state workflow assertion now passes**

Run:

```bash
ruby -ryaml -e '
workflow = YAML.load_file(".github/workflows/swift-ci.yml")
jobs = workflow.fetch("jobs")
expected_contexts = [
  "Host tests and benchmark gate",
  "iOS cross-target compile",
  "WASM cross-target observation"
]
actual_contexts = jobs.values.map { |job| job.fetch("name") }
missing = expected_contexts - actual_contexts
abort("missing_required_contexts=#{missing.join(",")}") unless missing.empty?
host_steps = jobs.fetch("host-tests-and-benchmark-gate").fetch("steps")
mutation = host_steps.find { |step| step["name"].to_s.include?("variable-height mutation") }
abort("missing mutation step") unless mutation
abort("wrong_mutation_name=#{mutation["name"]}") unless mutation["name"] == "Run variable-height mutation benchmark gate"
abort("mutation_continue_on_error_present") if mutation.key?("continue-on-error")
abort("wrong_mutation_run=#{mutation["run"]}") unless mutation["run"].to_s.include?("--variable-height-mutation --gate")
puts "yaml_ok"
puts "required_contexts=#{expected_contexts.join("|")}"
puts "mutation_gate_step=ok"
'
```

Expected output:

```text
yaml_ok
required_contexts=Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation
mutation_gate_step=ok
```

- [ ] **Step 3: Verify the old observation step name is gone**

Run:

```bash
set +e
rg -n "Observe variable-height mutation benchmark" .github/workflows/swift-ci.yml
status=$?
set -e
echo "old_observation_step_status=${status}"
test "$status" -eq 1
```

Expected:

```text
old_observation_step_status=1
```

- [ ] **Step 4: Verify the mutation command is the hosted gate command**

Run:

```bash
rg -n -- "Run variable-height mutation benchmark gate|--variable-height-mutation --gate" .github/workflows/swift-ci.yml
```

Expected: command exits `0` and prints the mutation step name plus the hosted
`swift run ... -- --variable-height-mutation --gate` command.

- [ ] **Step 5: Commit the workflow promotion**

Run:

```bash
git diff -- .github/workflows/swift-ci.yml
git add .github/workflows/swift-ci.yml
git commit -m "ci: promote variable-height mutation benchmark gate"
```

Expected: commit succeeds. The diff changes only the mutation step name,
removes that step's `continue-on-error: true`, and adds `--gate`.

## Task 3: Update Durable CI Guidance

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Apply the AGENTS CI wording patch**

Use `apply_patch` with this patch:

```diff
*** Begin Patch
*** Update File: AGENTS.md
@@
-  `swift:6.2.1-bookworm`: `swift test` → synthetic `--gate` (blocking)
-  → `--variable-height --gate` (blocking) → `--variable-height-mutation`
-  (observational) → `--memory-shape` → `--memory-observation` → realistic
-  relative observation (PR-only, `continue-on-error`). The synthetic and
-  variable-height gates **fail the job on perf regression**. Benchmark budgets
+  `swift:6.2.1-bookworm`: `swift test` → synthetic `--gate` (blocking)
+  → `--variable-height --gate` (blocking) → `--variable-height-mutation --gate`
+  (blocking) → `--memory-shape` → `--memory-observation` → realistic
+  relative observation (PR-only, `continue-on-error`). The synthetic, static
+  variable-height, and mutation variable-height gates **fail the job on perf
+  regression**. Benchmark budgets
*** End Patch
```

- [ ] **Step 2: Verify `AGENTS.md` now describes the blocking mutation gate**

Run:

```bash
rg -n -- "--variable-height-mutation --gate|synthetic, static|mutation variable-height gates \\*\\*fail the job on perf|regression\\*\\*\\. Benchmark budgets" AGENTS.md
```

Expected: command exits `0` and prints the CI paragraph lines showing
`--variable-height-mutation --gate` and the blocking gate wording.

- [ ] **Step 3: Verify the docs-only and required-check policy wording remained present**

Run:

```bash
rg -n "Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation|trusted-ci|policy-sensitive|Bypass caveat" AGENTS.md
```

Expected: command exits `0` and prints matches for the required contexts,
trusted docs-only execution, policy-sensitive path denial, and bypass caveat.

- [ ] **Step 4: Commit the durable guidance update**

Run:

```bash
git diff -- AGENTS.md
git add AGENTS.md
git commit -m "docs: document variable-height mutation ci gate"
```

Expected: commit succeeds. The diff is limited to the CI paragraph wording for
the host mutation benchmark gate.

## Task 4: Record Local Verification Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Write temporary command outputs under `/private/tmp/slice-21-*`

- [ ] **Step 1: Capture local benchmark gate outputs**

Run:

```bash
set +e
swift run -c release ViewportBenchmarks -- --gate > /private/tmp/slice-21-synthetic-gate.out 2>&1
synthetic_status=$?
swift run -c release ViewportBenchmarks -- --variable-height --gate > /private/tmp/slice-21-variable-gate.out 2>&1
variable_status=$?
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate > /private/tmp/slice-21-mutation-gate.out 2>&1
mutation_status=$?
set -e
cat /private/tmp/slice-21-synthetic-gate.out
echo "synthetic_gate_status=${synthetic_status}"
cat /private/tmp/slice-21-variable-gate.out
echo "variable_gate_status=${variable_status}"
cat /private/tmp/slice-21-mutation-gate.out
echo "mutation_gate_status=${mutation_status}"
test "$synthetic_status" -eq 0
test "$variable_status" -eq 0
test "$mutation_status" -eq 0
```

Expected: all three statuses are `0`. Synthetic, variable-height, and mutation
rows include `gate=pass`. Mutation rows also include `budget_p95_ns=` and
`budget_p99_ns=`.

- [ ] **Step 2: Capture workflow and docs shape proof**

Run:

```bash
set +e
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'" > /private/tmp/slice-21-yaml-ok.out 2>&1
yaml_status=$?
ruby -ryaml -e '
workflow = YAML.load_file(".github/workflows/swift-ci.yml")
jobs = workflow.fetch("jobs")
expected_contexts = [
  "Host tests and benchmark gate",
  "iOS cross-target compile",
  "WASM cross-target observation"
]
actual_contexts = jobs.values.map { |job| job.fetch("name") }
missing = expected_contexts - actual_contexts
abort("missing_required_contexts=#{missing.join(",")}") unless missing.empty?
host_steps = jobs.fetch("host-tests-and-benchmark-gate").fetch("steps")
mutation = host_steps.find { |step| step["name"].to_s.include?("variable-height mutation") }
abort("missing mutation step") unless mutation
abort("wrong_mutation_name=#{mutation["name"]}") unless mutation["name"] == "Run variable-height mutation benchmark gate"
abort("mutation_continue_on_error_present") if mutation.key?("continue-on-error")
abort("wrong_mutation_run=#{mutation["run"]}") unless mutation["run"].to_s.include?("--variable-height-mutation --gate")
puts "required_contexts=#{expected_contexts.join("|")}"
puts "mutation_gate_step=ok"
' > /private/tmp/slice-21-workflow-shape.out 2>&1
workflow_status=$?
rg -n -- "--variable-height-mutation --gate|mutation variable-height gates \\*\\*fail the job on perf|regression\\*\\*\\. Benchmark budgets" AGENTS.md > /private/tmp/slice-21-agents-scan.out 2>&1
agents_status=$?
set -e
cat /private/tmp/slice-21-yaml-ok.out
echo "yaml_status=${yaml_status}"
cat /private/tmp/slice-21-workflow-shape.out
echo "workflow_shape_status=${workflow_status}"
cat /private/tmp/slice-21-agents-scan.out
echo "agents_scan_status=${agents_status}"
test "$yaml_status" -eq 0
test "$workflow_status" -eq 0
test "$agents_status" -eq 0
```

Expected output includes:

```text
yaml_ok
yaml_status=0
required_contexts=Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation
mutation_gate_step=ok
workflow_shape_status=0
agents_scan_status=0
```

- [ ] **Step 3: Capture whitespace, Foundation-free, and source-scope proof**

Run:

```bash
set +e
git diff --check > /private/tmp/slice-21-diff-check.out 2>&1
diff_check_status=$?
rg -n "Foundation" Sources/TextEngineCore > /private/tmp/slice-21-foundation-scan.out 2>&1
foundation_status=$?
git diff --name-only main...HEAD -- Sources Tests Package.swift > /private/tmp/slice-21-source-scope.out 2>&1
source_scope_status=$?
set -e
cat /private/tmp/slice-21-diff-check.out
echo "diff_check_status=${diff_check_status}"
cat /private/tmp/slice-21-foundation-scan.out
echo "foundation_scan_status=${foundation_status}"
cat /private/tmp/slice-21-source-scope.out
echo "source_scope_status=${source_scope_status}"
test "$diff_check_status" -eq 0
test "$foundation_status" -eq 1
test "$source_scope_status" -eq 0
test ! -s /private/tmp/slice-21-source-scope.out
```

Expected:

```text
diff_check_status=0
foundation_scan_status=1
source_scope_status=0
```

The Foundation scan output and source-scope output are empty.

- [ ] **Step 4: Create the verification record with captured output**

Create `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`.
Use the section order below and populate every output block immediately from
the matching `/private/tmp/slice-21-*` file produced in Steps 1-3. The file
must contain actual command output, not editorial marker text.

````markdown
# Variable-Height Mutation CI Gate Promotion Verification

Date: 2026-06-18

## Scope

Slice 21 promotes the existing `--variable-height-mutation --gate` benchmark
path from hosted observation to a blocking step in the required
`Host tests and benchmark gate` job.

Changed files:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`

No Swift source, tests, package metadata, benchmark workloads, benchmark
budgets, required status context names, docs-only detector logic, or ruleset
settings changed in this slice.

## Pre-Implementation Red Proof

Before the workflow edit, the host job mutation step was still observation-only:

```text
Observe variable-height mutation benchmark
continue_on_error_present
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation
```

The future-state workflow assertion failed before implementation:

```text
mutation step is not named as a gate
future_state_assertion_status=1
```

## Local Benchmark Gates

Command:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Status: `0`

Representative output:

```text
Use the exact rows from /private/tmp/slice-21-synthetic-gate.out.
synthetic_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Status: `0`

Representative output:

```text
Use the exact rows from /private/tmp/slice-21-variable-gate.out.
variable_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Status: `0`

Representative output:

```text
Use the exact rows from /private/tmp/slice-21-mutation-gate.out.
mutation_gate_status=0
```

The mutation output includes `budget_p95_ns=`, `budget_p99_ns=`, and
`gate=pass` for all three scenarios.

## Workflow Shape

Command:

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
```

Status: `0`

Output:

```text
yaml_ok
yaml_status=0
```

Workflow assertion:

```text
required_contexts=Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation
mutation_gate_step=ok
workflow_shape_status=0
```

This proves:

- the three required job contexts are unchanged;
- the mutation step is named `Run variable-height mutation benchmark gate`;
- the mutation step invokes `--variable-height-mutation --gate`;
- the mutation step has no `continue-on-error`.

## Durable Guidance

`AGENTS.md` scan:

```text
Use the exact lines from /private/tmp/slice-21-agents-scan.out.
agents_scan_status=0
```

## Scope And Hygiene

Command:

```bash
git diff --check
```

Status: `0`

Output:

```text
diff_check_status=0
```

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore
```

Status: `1`

Output:

```text
foundation_scan_status=1
```

Command:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Status: `0`

Output:

```text
source_scope_status=0
```

## Hosted PR-Head Evidence

Hosted PR-head evidence is added after the Slice 21 PR has a completed Swift CI
run for the final head SHA.

Required evidence:

- PR number and head SHA;
- Swift CI run ID;
- all three required jobs `success`;
- host job step `Run variable-height mutation benchmark gate` `success`;
- hosted mutation rows include `budget_p95_ns=`, `budget_p99_ns=`, and
  `gate=pass`;
- the committed PR-head workflow has no `continue-on-error` on the mutation
  step.

## Post-Merge Push Evidence

Post-merge evidence is added after the Slice 21 PR is merged and the `main`
push Swift CI run for the merge commit completes.

Required evidence:

- merge commit SHA;
- push run ID;
- all three required jobs `success`;
- host job mutation gate step `success`;
- hosted mutation rows include `gate=pass` and budget fields.
````

- [ ] **Step 5: Verify the record has no unresolved marker text**

Run:

```bash
set +e
rg -n "Use the exact rows from|Use the exact lines from|REPLACE_ME|PASTE_ME" docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
marker_status=$?
set -e
echo "marker_scan_status=${marker_status}"
test "$marker_status" -eq 1
```

Expected:

```text
marker_scan_status=1
```

- [ ] **Step 6: Verify the local evidence record is internally consistent**

Run:

```bash
rg -n "Pre-Implementation Red Proof|synthetic_gate_status=0|variable_gate_status=0|mutation_gate_status=0|budget_p95_ns=.*budget_p99_ns=.*gate=pass|required_contexts=Host tests and benchmark gate\\|iOS cross-target compile\\|WASM cross-target observation|mutation_gate_step=ok|foundation_scan_status=1|source_scope_status=0" docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
```

Expected: command exits `0` and prints matches for every required local proof
anchor.

- [ ] **Step 7: Commit the local verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
git commit -m "docs: record variable-height mutation gate verification"
```

Expected: commit succeeds.

## Task 5: Open PR And Record PR-Head Hosted Proof

**Files:**
- Modify: `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`
- Read: `.github/workflows/swift-ci.yml`
- Write temporary command outputs under `/private/tmp/slice-21-*`

- [ ] **Step 1: Push the branch and open the Slice 21 PR**

Run:

```bash
git status --short --branch
git push -u origin slice-21-variable-height-mutation-gate
gh pr create \
  --title "Promote variable-height mutation benchmark gate" \
  --body "Promotes the existing variable-height mutation benchmark to a blocking hosted host-job gate and records verification evidence."
```

Expected: push succeeds and GitHub opens a PR targeting `main`.

- [ ] **Step 2: Capture PR metadata**

Run:

```bash
gh pr view --json number,headRefName,headRefOid,baseRefName,url,mergeStateStatus,statusCheckRollup > /private/tmp/slice-21-pr.json
jq -r '"pr=#\(.number)", "url=\(.url)", "headRefName=\(.headRefName)", "baseRefName=\(.baseRefName)", "headSha=\(.headRefOid)", "mergeStateStatus=\(.mergeStateStatus)"' /private/tmp/slice-21-pr.json
```

Expected: output shows the Slice 21 PR number, branch
`slice-21-variable-height-mutation-gate`, base `main`, and current head SHA.

- [ ] **Step 3: Wait for the final PR-head Swift CI run**

Run:

```bash
head_sha=$(jq -r '.headRefOid' /private/tmp/slice-21-pr.json)
gh run list \
  --workflow "Swift CI" \
  --branch slice-21-variable-height-mutation-gate \
  --event pull_request \
  --limit 10 \
  --json databaseId,headSha,event,status,conclusion,displayTitle,createdAt \
  --jq ".[] | select(.headSha == \"${head_sha}\")"
```

Expected: a completed pull request run for the PR head SHA appears with
`status` `completed` and `conclusion` `success`. If the run is still queued or
in progress, wait for completion before continuing.

- [ ] **Step 4: Save the PR-head run JSON and required job conclusions**

Run:

```bash
head_sha=$(jq -r '.headRefOid' /private/tmp/slice-21-pr.json)
run_id=$(gh run list \
  --workflow "Swift CI" \
  --branch slice-21-variable-height-mutation-gate \
  --event pull_request \
  --limit 10 \
  --json databaseId,headSha,status,conclusion \
  --jq ".[] | select(.headSha == \"${head_sha}\" and .status == \"completed\") | .databaseId" | head -n 1)
echo "pr_head_run_id=${run_id}" > /private/tmp/slice-21-pr-run-id.out
gh run view "$run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-21-pr-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-21-pr-run.json
```

Expected output includes:

```text
Swift CI
pull_request
completed
success
Host tests and benchmark gate=success
iOS cross-target compile=success
WASM cross-target observation=success
```

- [ ] **Step 5: Capture hosted host-job log evidence**

Run:

```bash
run_id=$(cat /private/tmp/slice-21-pr-run-id.out | sed 's/pr_head_run_id=//')
host_job_id=$(jq -r '.jobs[] | select(.name == "Host tests and benchmark gate") | .databaseId' /private/tmp/slice-21-pr-run.json)
gh run view "$run_id" --job "$host_job_id" --log > /private/tmp/slice-21-pr-host-job.log
rg -n "Run variable-height mutation benchmark gate|mode=variable_height_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass" /private/tmp/slice-21-pr-host-job.log
```

Expected: command exits `0`. The log includes the hosted step name and three
`mode=variable_height_mutation ... gate=pass` rows with `budget_p95_ns=` and
`budget_p99_ns=`.

- [ ] **Step 6: Prove the committed PR-head workflow has no mutation `continue-on-error`**

Run:

```bash
head_sha=$(jq -r '.headRefOid' /private/tmp/slice-21-pr.json)
git fetch origin slice-21-variable-height-mutation-gate
git show "$head_sha:.github/workflows/swift-ci.yml" > /private/tmp/slice-21-pr-head-workflow.yml
ruby -ryaml -e '
workflow = YAML.load_file("/private/tmp/slice-21-pr-head-workflow.yml")
mutation = workflow.fetch("jobs")
  .fetch("host-tests-and-benchmark-gate")
  .fetch("steps")
  .find { |step| step["name"].to_s.include?("variable-height mutation") }
abort("missing mutation step") unless mutation
abort("wrong name") unless mutation["name"] == "Run variable-height mutation benchmark gate"
abort("continue-on-error present") if mutation.key?("continue-on-error")
abort("missing gate") unless mutation["run"].to_s.include?("--variable-height-mutation --gate")
puts "pr_head_mutation_gate_step=ok"
'
```

Expected:

```text
pr_head_mutation_gate_step=ok
```

- [ ] **Step 7: Update the verification record with PR-head evidence**

Update `## Hosted PR-Head Evidence` in
`docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`
with:

- PR number and URL from `/private/tmp/slice-21-pr.json`;
- head SHA from `/private/tmp/slice-21-pr.json`;
- Swift CI run ID from `/private/tmp/slice-21-pr-run-id.out`;
- required job conclusions from `/private/tmp/slice-21-pr-run.json`;
- hosted mutation gate log lines from `/private/tmp/slice-21-pr-host-job.log`;
- `pr_head_mutation_gate_step=ok`.

Run:

```bash
rg -n "Hosted PR-Head Evidence|PR #|head SHA|Swift CI run|Host tests and benchmark gate=success|iOS cross-target compile=success|WASM cross-target observation=success|Run variable-height mutation benchmark gate|mode=variable_height_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass|pr_head_mutation_gate_step=ok" docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
```

Expected: command exits `0` and prints matches for every PR-head proof anchor.

- [ ] **Step 8: Commit PR-head hosted evidence**

Run:

```bash
git add docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
git commit -m "docs: record variable-height mutation gate hosted proof"
git push
```

Expected: commit and push succeed. The pushed documentation commit starts a new
PR-head Swift CI run because the full PR diff still includes workflow YAML. Wait
for that new run and confirm the required contexts are green before merge, but
do not churn the verification document solely to chase the CI run created by its
own evidence update. Task 6 records the merged workflow behavior from the
post-merge push run.

## Task 6: Merge And Record Post-Merge Hosted Proof

**Files:**
- Modify: `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`
- Write temporary command outputs under `/private/tmp/slice-21-*`

- [ ] **Step 1: Merge after the final PR-head required checks are green**

Run:

```bash
gh pr view --json number,mergeStateStatus,statusCheckRollup,url
```

Expected: the PR is mergeable under repository policy and the three required
Swift CI contexts are green. Merge using the repository's normal PR flow.

- [ ] **Step 2: Capture merge commit metadata**

Run after merge:

```bash
gh pr view --json number,mergeCommit,mergedAt,mergedBy,url > /private/tmp/slice-21-merged-pr.json
jq -r '"pr=#\(.number)", "mergeCommit=\(.mergeCommit.oid)", "mergedAt=\(.mergedAt)", "mergedBy=\(.mergedBy.login)"' /private/tmp/slice-21-merged-pr.json
```

Expected: output includes a non-empty merge commit SHA.

- [ ] **Step 3: Capture the post-merge push run**

Run:

```bash
merge_sha=$(jq -r '.mergeCommit.oid' /private/tmp/slice-21-merged-pr.json)
gh run list \
  --workflow "Swift CI" \
  --branch main \
  --event push \
  --limit 20 \
  --json databaseId,headSha,event,status,conclusion,displayTitle,createdAt \
  --jq ".[] | select(.headSha == \"${merge_sha}\")"
```

Expected: a completed `push` run for the merge commit appears. Because this
slice changes `.github/workflows/swift-ci.yml`, `push.paths-ignore` should not
skip the workflow. If no run appears, document the exact blocker instead of
inventing post-merge proof.

- [ ] **Step 4: Save post-merge run JSON and host-job logs**

Run:

```bash
merge_sha=$(jq -r '.mergeCommit.oid' /private/tmp/slice-21-merged-pr.json)
run_id=$(gh run list \
  --workflow "Swift CI" \
  --branch main \
  --event push \
  --limit 20 \
  --json databaseId,headSha,status,conclusion \
  --jq ".[] | select(.headSha == \"${merge_sha}\" and .status == \"completed\") | .databaseId" | head -n 1)
echo "post_merge_run_id=${run_id}" > /private/tmp/slice-21-post-merge-run-id.out
gh run view "$run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-21-post-merge-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-21-post-merge-run.json
host_job_id=$(jq -r '.jobs[] | select(.name == "Host tests and benchmark gate") | .databaseId' /private/tmp/slice-21-post-merge-run.json)
gh run view "$run_id" --job "$host_job_id" --log > /private/tmp/slice-21-post-merge-host-job.log
rg -n "Run variable-height mutation benchmark gate|mode=variable_height_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass" /private/tmp/slice-21-post-merge-host-job.log
```

Expected output includes:

```text
Swift CI
push
completed
success
Host tests and benchmark gate=success
iOS cross-target compile=success
WASM cross-target observation=success
```

The hosted host-job log includes the mutation gate step and three
`mode=variable_height_mutation ... gate=pass` rows with budget fields.

- [ ] **Step 5: Create the post-merge verification follow-up branch**

Run:

```bash
git fetch origin main
git checkout -B slice-21-post-merge-verification origin/main
```

Expected: branch `slice-21-post-merge-verification` is based on the current
`origin/main`, which contains the merged Slice 21 verification record.

- [ ] **Step 6: Record post-merge proof**

Update `## Post-Merge Push Evidence` in
`docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`
on the follow-up branch with:

- merge commit SHA;
- push run ID;
- required job conclusions;
- hosted mutation gate log lines.

Run:

```bash
rg -n "Post-Merge Push Evidence|merge commit|push run|Host tests and benchmark gate=success|iOS cross-target compile=success|WASM cross-target observation=success|Run variable-height mutation benchmark gate|mode=variable_height_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass" docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
```

Expected: command exits `0` and prints matches for every post-merge proof
anchor.

- [ ] **Step 7: Commit post-merge evidence as a docs-only follow-up**

Run:

```bash
git add docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
git commit -m "docs: record variable-height mutation gate post-merge proof"
git push -u origin slice-21-post-merge-verification
gh pr create \
  --title "Record Slice 21 post-merge verification" \
  --body "Records post-merge Swift CI evidence for the variable-height mutation gate promotion."
```

Expected: follow-up PR contains only the verification document update. Its own
Swift CI required contexts may take the trusted docs-only lightweight path.

## Task 7: Final Acceptance Review

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Read: `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`

- [ ] **Step 1: Run the final acceptance scan**

Run:

```bash
rg -n "Observe variable-height mutation benchmark" .github/workflows/swift-ci.yml && exit 1 || true
ruby -ryaml -e '
workflow = YAML.load_file(".github/workflows/swift-ci.yml")
jobs = workflow.fetch("jobs")
expected_contexts = [
  "Host tests and benchmark gate",
  "iOS cross-target compile",
  "WASM cross-target observation"
]
actual_contexts = jobs.values.map { |job| job.fetch("name") }
missing = expected_contexts - actual_contexts
abort("missing_required_contexts=#{missing.join(",")}") unless missing.empty?
mutation = jobs.fetch("host-tests-and-benchmark-gate").fetch("steps").find { |step| step["name"].to_s.include?("variable-height mutation") }
abort("missing mutation step") unless mutation
abort("wrong mutation step name") unless mutation["name"] == "Run variable-height mutation benchmark gate"
abort("mutation step still has continue-on-error") if mutation.key?("continue-on-error")
abort("mutation step missing gate") unless mutation["run"].to_s.include?("--variable-height-mutation --gate")
puts "final_workflow_acceptance=pass"
'
rg -n -- "--variable-height-mutation --gate|mutation variable-height gates \\*\\*fail the job on perf|regression\\*\\*\\. Benchmark budgets" AGENTS.md
rg -n "mutation_gate_step=ok|budget_p95_ns=.*budget_p99_ns=.*gate=pass|Hosted PR-Head Evidence|Post-Merge Push Evidence" docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md
git diff --check
```

Expected: command sequence exits `0` and includes:

```text
final_workflow_acceptance=pass
```

- [ ] **Step 2: Confirm source and policy non-goals stayed untouched**

Run:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift .github/scripts
gh pr view --json statusCheckRollup --jq '.statusCheckRollup[] | select(.context == "Host tests and benchmark gate" or .context == "iOS cross-target compile" or .context == "WASM cross-target observation") | "\(.context)=\(.state)"'
```

Expected: first command prints no source/package/helper paths. The second
command shows the three required contexts for the active PR.

- [ ] **Step 3: Verify acceptance criteria against the spec**

Run:

```bash
rg -n "Acceptance Criteria|no longer contains|--variable-height-mutation --gate|continue-on-error|three required job context names|AGENTS.md|Hosted PR-head CI|Post-merge push CI" docs/superpowers/specs/2026-06-18-variable-height-mutation-ci-gate-promotion-design.md
```

Expected: command exits `0`. Manually check each acceptance criterion against
the workflow, `AGENTS.md`, and verification record:

- `.github/workflows/swift-ci.yml` no longer contains the old observation step.
- The mutation step is named as a gate.
- The mutation step invokes `--variable-height-mutation --gate`.
- The mutation step has no `continue-on-error`.
- Required job context names are unchanged.
- `AGENTS.md` describes mutation as a blocking host-job gate.
- Local mutation gate output includes `gate=pass` and budget fields.
- Hosted PR-head CI has the mutation gate step successful.
- Post-merge push CI anchors merged workflow behavior, or a concrete external
  blocker is documented.

- [ ] **Step 4: Leave the branch in a reviewable state**

Run:

```bash
git status --short --branch
git log --oneline --decorate -8
```

Expected: working tree is clean except for intentional post-merge documentation
work, and the recent commits are small, concern-separated commits with prefixes
`ci:` and `docs:`.

## Self-Review Checklist

Before handing off implementation as complete:

- [ ] Spec coverage: every Slice 21 goal maps to a completed task above.
- [ ] Unresolved-marker scan: the verification record contains actual command output from `/private/tmp/slice-21-*` and no remaining marker text such as `REPLACE_ME` or `PASTE_ME`.
- [ ] Type/path consistency: workflow job id is still `host-tests-and-benchmark-gate`, required job names are still exactly `Host tests and benchmark gate`, `iOS cross-target compile`, and `WASM cross-target observation`.
- [ ] Budget ownership: budgets remain only in `Sources/ViewportBenchmarks`; workflow YAML does not duplicate numeric thresholds.
- [ ] Docs-only behavior: `.github/scripts/detect-docs-only-pr.sh` and trusted detector invocation are unchanged unless a separate approved spec covers them.
