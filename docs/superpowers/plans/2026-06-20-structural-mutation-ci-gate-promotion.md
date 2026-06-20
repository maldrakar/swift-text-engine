# Structural-Mutation CI Gate Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the existing `--structural-mutation --gate` benchmark to the required host CI job as a new blocking step, in one PR, so structural insert/delete regressions block merge.

**Architecture:** Keep `TextEngineCore`, `TextEngineReferenceProviders`, benchmark scenarios, and budgets unchanged. Insert one new host GitHub Actions step that invokes the executable-owned `--structural-mutation --gate` path (no `continue-on-error`), positioned between the variable-height mutation gate and the memory-shape diagnostic, then update durable repo guidance and verification evidence. The three required job context names and the trusted docs-only shortcut stay unchanged.

**Tech Stack:** GitHub Actions YAML, SwiftPM `ViewportBenchmarks`, Ruby YAML parser for workflow-shape assertions, GitHub CLI, Markdown. Spec: `docs/superpowers/specs/2026-06-20-structural-mutation-ci-gate-promotion-design.md`.

## Global Constraints

- No Foundation in `Sources/TextEngineCore` (scan `rg -n "Foundation" Sources/TextEngineCore` must be empty, exit `1`).
- No Swift source, tests, or `Package.swift` changes in this slice unless the executable gate is found broken (then stop and revise the spec).
- Benchmark budgets live only in `Sources/ViewportBenchmarks`; never duplicate numeric thresholds in workflow YAML.
- Keep the current macOS-calibrated structural-mutation budgets. If the first hosted PR-head run exceeds budget, STOP, revise the spec with the hosted numbers, and re-derive Linux budgets — do not add `continue-on-error`, a workflow-only threshold, or a silent budget widening.
- The three required GitHub status context names stay exactly: `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM cross-target observation`. Do not rename jobs or create/rename required contexts.
- Leave the docs-only detector, trusted-CI invocation, ruleset, and bypass policy unchanged.
- Conventional-commit prefixes: `ci:` for the workflow step, `docs:` for guidance and verification.
- Branch: `slice-24-structural-mutation-ci-gate-promotion`. Temporary captures under `/private/tmp/slice-24-*`.

---

## Scope Check

This plan implements Slice 24:

```text
docs/superpowers/specs/2026-06-20-structural-mutation-ci-gate-promotion-design.md
```

This slice covers one operational subsystem: adding an already-existing benchmark
executable gate (`--structural-mutation --gate`) as a new blocking step in the
existing hosted host job.

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

If any verification step shows that `--structural-mutation --gate` itself is
broken or unstable on hosted Linux, stop implementation and revise the spec with
that evidence instead of widening budgets or adding `continue-on-error`.

## File Structure

- Modify `.github/workflows/swift-ci.yml`: insert a new
  `Run structural mutation benchmark gate` step between
  `Run variable-height mutation benchmark gate` and
  `Run memory shape diagnostic`. Do not rename jobs or move unrelated steps.
- Modify `AGENTS.md`: update the CI section so the `Host tests and benchmark
  gate` bullet lists the structural-mutation gate as blocking, keeping the
  docs-only, iOS, WASM, ruleset, and bypass wording unchanged.
- Create `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`:
  record local command evidence, workflow-shape proof, non-source scope proof,
  PR-head hosted proof, and post-merge hosted proof.
- Use temporary files under `/private/tmp/slice-24-*` for command captures and
  hosted log snippets.

## Task 1: Preflight And Red Workflow Proof

**Files:**
- Read: `docs/superpowers/specs/2026-06-20-structural-mutation-ci-gate-promotion-design.md`
- Read: `docs/superpowers/reviews/2026-06-20-slice-23-post-slice-review.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Write temporary command outputs under `/private/tmp/slice-24-*`

- [ ] **Step 1: Confirm branch and preserve existing docs work**

Run:

```bash
git status --short --branch
git branch --show-current
```

Expected: branch is `slice-24-structural-mutation-ci-gate-promotion`. Any
uncommitted files are limited to the Slice 24 spec/plan docs unless intentionally
added. If `.github/workflows/swift-ci.yml`, `AGENTS.md`, or the Slice 24
verification record are already modified, inspect the diff before continuing and
preserve user-owned changes.

- [ ] **Step 2: Confirm the approved spec content**

Run:

```bash
rg -n "Structural-Mutation CI Gate Promotion Design|Slice 24|One-shot blocking gate|Keep current budgets; treat a first-run hosted failure as evidence|Keep the host job order|Do not change required context names" docs/superpowers/specs/2026-06-20-structural-mutation-ci-gate-promotion-design.md
```

Expected: command exits `0` and prints matches for all listed spec anchors.

- [ ] **Step 3: Confirm Slice 23 handed off to this direction**

Run:

```bash
rg -n "Option A: Structural-Mutation CI Gate Promotion|Recommended Slice 24 is \*\*Option A|should be promoted before the next functional change" docs/superpowers/reviews/2026-06-20-slice-23-post-slice-review.md
```

Expected: command exits `0`. The review recommends promoting the
structural-mutation gate as Slice 24.

- [ ] **Step 4: Capture the current absence of a structural step**

Run:

```bash
ruby -ryaml -e '
workflow = YAML.load_file(".github/workflows/swift-ci.yml")
steps = workflow.fetch("jobs").fetch("host-tests-and-benchmark-gate").fetch("steps")
names = steps.map { |s| s["name"].to_s }
structural = names.find { |n| n.include?("structural mutation") }
puts structural ? "structural_step_present" : "structural_step_absent"
vh_mut = names.index { |n| n.include?("variable-height mutation") }
mem = names.index { |n| n.include?("memory shape") }
abort("missing variable-height mutation step") unless vh_mut
abort("missing memory shape step") unless mem
puts "variable_height_mutation_index=#{vh_mut}"
puts "memory_shape_index=#{mem}"
puts "steps_between_vh_mutation_and_memory_shape=#{mem - vh_mut - 1}"
'
```

Expected output before implementation:

```text
structural_step_absent
variable_height_mutation_index=7
memory_shape_index=8
steps_between_vh_mutation_and_memory_shape=0
```

(The exact indices may differ by toolchain ordering; the load-bearing facts are
`structural_step_absent` and that the memory-shape step immediately follows the
variable-height mutation gate, i.e. `steps_between_... = 0`.)

- [ ] **Step 5: Run the future-state workflow assertion and verify it fails red**

Run:

```bash
set +e
ruby -ryaml -e '
steps = YAML.load_file(".github/workflows/swift-ci.yml")
  .fetch("jobs")
  .fetch("host-tests-and-benchmark-gate")
  .fetch("steps")
step = steps.find { |c| c["name"].to_s.include?("structural mutation") }
abort("structural mutation gate step is absent") unless step
abort("structural step is not a blocking gate (has continue-on-error)") if step.key?("continue-on-error")
abort("structural step does not run --structural-mutation --gate") unless step["run"].to_s.include?("--structural-mutation --gate")
puts "structural_gate_step=ok"
'
status=$?
set -e
echo "future_state_assertion_status=${status}"
test "$status" -ne 0
```

Expected output before implementation includes:

```text
structural mutation gate step is absent
future_state_assertion_status=1
```

This is the failing-first check for the workflow promotion.

- [ ] **Step 6: Confirm the executable-owned structural gate already passes locally**

Run:

```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```

Expected: command exits `0` and prints exactly three
`mode=structural_mutation provider=balanced_tree ... gate=pass` rows. Each row
must include `budget_p95_ns=`, `budget_p99_ns=`, and `gate=pass`.

- [ ] **Step 7: Confirm no Swift source/package scope is needed**

Run:

```bash
git diff --name-only -- Sources Tests Package.swift
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Expected: no output from either command. If source/package files appear, inspect
the diff and stop unless the spec has been revisited.

## Task 2: Add The Hosted Workflow Gate Step

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [ ] **Step 1: Insert the structural-mutation gate step before the memory-shape diagnostic**

Edit `.github/workflows/swift-ci.yml`. Find this exact block (the memory-shape
diagnostic step, which currently immediately follows the variable-height
mutation gate):

```yaml
      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

Replace it with the new structural-mutation gate step followed by the unchanged
memory-shape step:

```yaml
      - name: Run structural mutation benchmark gate
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate

      - name: Run memory shape diagnostic
        if: steps.change-scope.outputs.docs_only_pr != 'true'
        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --memory-shape
```

This inserts the new blocking gate without `continue-on-error` and without
`shell: bash` (single one-line command, no pipes), keeping all latency gates
contiguous.

- [ ] **Step 2: Verify the future-state workflow assertion now passes, including ordering**

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
steps = jobs.fetch("host-tests-and-benchmark-gate").fetch("steps")
names = steps.map { |s| s["name"].to_s }
structural = steps.find { |s| s["name"].to_s.include?("structural mutation") }
abort("missing structural step") unless structural
abort("wrong_structural_name=#{structural["name"]}") unless structural["name"] == "Run structural mutation benchmark gate"
abort("structural_continue_on_error_present") if structural.key?("continue-on-error")
abort("wrong_structural_run=#{structural["run"]}") unless structural["run"].to_s.include?("--structural-mutation --gate")
abort("structural step has shell override") if structural.key?("shell")
vh_mut = names.index { |n| n.include?("variable-height mutation") }
struct_idx = names.index { |n| n.include?("structural mutation") }
mem = names.index { |n| n.include?("memory shape") }
abort("ordering_wrong vh=#{vh_mut} struct=#{struct_idx} mem=#{mem}") unless vh_mut && struct_idx && mem && vh_mut < struct_idx && struct_idx < mem
puts "yaml_ok"
puts "required_contexts=#{expected_contexts.join("|")}"
puts "structural_gate_step=ok"
puts "structural_order=after_vh_mutation_before_memory_shape"
'
```

Expected output:

```text
yaml_ok
required_contexts=Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation
structural_gate_step=ok
structural_order=after_vh_mutation_before_memory_shape
```

- [ ] **Step 3: Verify the structural gate command is present and the other steps are intact**

Run:

```bash
rg -n -- "Run structural mutation benchmark gate|--structural-mutation --gate|Run variable-height mutation benchmark gate|Run memory shape diagnostic" .github/workflows/swift-ci.yml
```

Expected: command exits `0` and prints the new structural step name and command,
plus the still-present variable-height mutation gate and memory-shape diagnostic.

- [ ] **Step 4: Confirm no `continue-on-error` was added to the structural step**

Run:

```bash
set +e
rg -n -B2 -A1 "structural-mutation --gate" .github/workflows/swift-ci.yml | rg -n "continue-on-error"
status=$?
set -e
echo "structural_continue_on_error_status=${status}"
test "$status" -eq 1
```

Expected:

```text
structural_continue_on_error_status=1
```

- [ ] **Step 5: Commit the workflow gate addition**

Run:

```bash
git diff -- .github/workflows/swift-ci.yml
git add .github/workflows/swift-ci.yml
git commit -m "ci: add structural mutation benchmark gate to host job"
```

Expected: commit succeeds. The diff adds only the new structural-mutation gate
step in the correct position; no other step changes.

## Task 3: Update Durable CI Guidance

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Update the AGENTS CI host-job bullet**

Edit `AGENTS.md`. Find this exact block:

```text
  `swift:6.2.1-bookworm`: `swift test` → synthetic `--gate` (blocking)
  → `--variable-height --gate` (blocking) → `--variable-height-mutation --gate`
  (blocking) → `--memory-shape` → `--memory-observation` → realistic
  relative observation (PR-only, `continue-on-error`). The synthetic, static
  variable-height, and mutation variable-height gates **fail the job on perf
  regression**. Benchmark budgets
```

Replace it with:

```text
  `swift:6.2.1-bookworm`: `swift test` → synthetic `--gate` (blocking)
  → `--variable-height --gate` (blocking) → `--variable-height-mutation --gate`
  (blocking) → `--structural-mutation --gate` (blocking) → `--memory-shape`
  → `--memory-observation` → realistic relative observation (PR-only,
  `continue-on-error`). The synthetic, static variable-height, mutation
  variable-height, and structural-mutation gates **fail the job on perf
  regression**. Benchmark budgets
```

- [ ] **Step 2: Verify `AGENTS.md` now describes the blocking structural gate**

Run:

```bash
rg -n -- "\(blocking\) → .--structural-mutation --gate. \(blocking\)" AGENTS.md
rg -n -- "structural-mutation gates \*\*fail the job on perf" AGENTS.md
```

Expected: both commands exit `0`. The first proves the CI host-job sequence now
lists `--structural-mutation --gate (blocking)` after the variable-height
mutation gate; the second proves the "fail the job on perf regression" sentence
now names the structural-mutation gate.

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
git commit -m "docs: document structural mutation ci gate"
```

Expected: commit succeeds. The diff is limited to the CI host-job paragraph
wording for the structural-mutation gate.

## Task 4: Record Local Verification Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Write temporary command outputs under `/private/tmp/slice-24-*`

- [ ] **Step 1: Capture local benchmark gate outputs**

Run:

```bash
set +e
swift run -c release ViewportBenchmarks -- --gate > /private/tmp/slice-24-synthetic-gate.out 2>&1
synthetic_status=$?
swift run -c release ViewportBenchmarks -- --variable-height --gate > /private/tmp/slice-24-variable-gate.out 2>&1
variable_status=$?
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate > /private/tmp/slice-24-vh-mutation-gate.out 2>&1
vh_mutation_status=$?
swift run -c release ViewportBenchmarks -- --structural-mutation --gate > /private/tmp/slice-24-structural-gate.out 2>&1
structural_status=$?
set -e
cat /private/tmp/slice-24-synthetic-gate.out
echo "synthetic_gate_status=${synthetic_status}"
cat /private/tmp/slice-24-variable-gate.out
echo "variable_gate_status=${variable_status}"
cat /private/tmp/slice-24-vh-mutation-gate.out
echo "vh_mutation_gate_status=${vh_mutation_status}"
cat /private/tmp/slice-24-structural-gate.out
echo "structural_gate_status=${structural_status}"
test "$synthetic_status" -eq 0
test "$variable_status" -eq 0
test "$vh_mutation_status" -eq 0
test "$structural_status" -eq 0
```

Expected: all four statuses are `0`. The structural rows include
`mode=structural_mutation provider=balanced_tree`, `budget_p95_ns=`,
`budget_p99_ns=`, and `gate=pass` for all three scenarios.

- [ ] **Step 2: Capture workflow and docs shape proof**

Run:

```bash
set +e
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'" > /private/tmp/slice-24-yaml-ok.out 2>&1
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
steps = jobs.fetch("host-tests-and-benchmark-gate").fetch("steps")
names = steps.map { |s| s["name"].to_s }
structural = steps.find { |s| s["name"].to_s.include?("structural mutation") }
abort("missing structural step") unless structural
abort("wrong_structural_name=#{structural["name"]}") unless structural["name"] == "Run structural mutation benchmark gate"
abort("structural_continue_on_error_present") if structural.key?("continue-on-error")
abort("wrong_structural_run=#{structural["run"]}") unless structural["run"].to_s.include?("--structural-mutation --gate")
vh_mut = names.index { |n| n.include?("variable-height mutation") }
struct_idx = names.index { |n| n.include?("structural mutation") }
mem = names.index { |n| n.include?("memory shape") }
abort("ordering_wrong") unless vh_mut && struct_idx && mem && vh_mut < struct_idx && struct_idx < mem
puts "required_contexts=#{expected_contexts.join("|")}"
puts "structural_gate_step=ok"
puts "structural_order=after_vh_mutation_before_memory_shape"
' > /private/tmp/slice-24-workflow-shape.out 2>&1
workflow_status=$?
rg -n -- "--structural-mutation --gate|structural-mutation gates \\*\\*fail the job on perf|regression\\*\\*\\. Benchmark budgets" AGENTS.md > /private/tmp/slice-24-agents-scan.out 2>&1
agents_status=$?
set -e
cat /private/tmp/slice-24-yaml-ok.out
echo "yaml_status=${yaml_status}"
cat /private/tmp/slice-24-workflow-shape.out
echo "workflow_shape_status=${workflow_status}"
cat /private/tmp/slice-24-agents-scan.out
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
structural_gate_step=ok
structural_order=after_vh_mutation_before_memory_shape
workflow_shape_status=0
agents_scan_status=0
```

- [ ] **Step 3: Capture whitespace, Foundation-free, and source-scope proof**

Run:

```bash
set +e
git diff --check > /private/tmp/slice-24-diff-check.out 2>&1
diff_check_status=$?
rg -n "Foundation" Sources/TextEngineCore > /private/tmp/slice-24-foundation-scan.out 2>&1
foundation_status=$?
git diff --name-only main...HEAD -- Sources Tests Package.swift > /private/tmp/slice-24-source-scope.out 2>&1
source_scope_status=$?
set -e
cat /private/tmp/slice-24-diff-check.out
echo "diff_check_status=${diff_check_status}"
cat /private/tmp/slice-24-foundation-scan.out
echo "foundation_scan_status=${foundation_status}"
cat /private/tmp/slice-24-source-scope.out
echo "source_scope_status=${source_scope_status}"
test "$diff_check_status" -eq 0
test "$foundation_status" -eq 1
test "$source_scope_status" -eq 0
test ! -s /private/tmp/slice-24-source-scope.out
```

Expected:

```text
diff_check_status=0
foundation_scan_status=1
source_scope_status=0
```

The Foundation scan output and source-scope output are empty.

- [ ] **Step 4: Create the verification record with captured output**

Create `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`.
Use the section order below and populate every output block immediately from the
matching `/private/tmp/slice-24-*` file produced in Steps 1-3. The file must
contain actual command output, not editorial marker text.

````markdown
# Structural-Mutation CI Gate Promotion Verification

Date: 2026-06-20

## Scope

Slice 24 adds the existing `--structural-mutation --gate` benchmark path as a new
blocking step in the required `Host tests and benchmark gate` job.

Changed files:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`

No Swift source, tests, package metadata, benchmark workloads, benchmark budgets,
required status context names, docs-only detector logic, or ruleset settings
changed in this slice.

## Pre-Implementation Red Proof

Before the workflow edit, the host job had no structural-mutation step; the
memory-shape diagnostic immediately followed the variable-height mutation gate:

```text
structural_step_absent
steps_between_vh_mutation_and_memory_shape=0
```

The future-state workflow assertion failed before implementation:

```text
structural mutation gate step is absent
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
Paste the exact rows from /private/tmp/slice-24-synthetic-gate.out.
synthetic_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Status: `0`

Representative output:

```text
Paste the exact rows from /private/tmp/slice-24-variable-gate.out.
variable_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Status: `0`

Representative output:

```text
Paste the exact rows from /private/tmp/slice-24-vh-mutation-gate.out.
vh_mutation_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```

Status: `0`

Representative output:

```text
Paste the exact rows from /private/tmp/slice-24-structural-gate.out.
structural_gate_status=0
```

The structural output includes `mode=structural_mutation provider=balanced_tree`,
`budget_p95_ns=`, `budget_p99_ns=`, and `gate=pass` for all three scenarios.

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
structural_gate_step=ok
structural_order=after_vh_mutation_before_memory_shape
workflow_shape_status=0
```

This proves:

- the three required job contexts are unchanged;
- the structural step is named `Run structural mutation benchmark gate`;
- the structural step invokes `--structural-mutation --gate`;
- the structural step has no `continue-on-error`;
- the structural step sits after the variable-height mutation gate and before
  the memory-shape diagnostic.

## Durable Guidance

`AGENTS.md` scan:

```text
Paste the exact lines from /private/tmp/slice-24-agents-scan.out.
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

Hosted PR-head evidence is added after the Slice 24 PR has a completed Swift CI
run for the final head SHA.

Required evidence:

- PR number and head SHA;
- Swift CI run ID;
- all three required jobs `success`;
- host job step `Run structural mutation benchmark gate` `success`;
- hosted structural rows include `mode=structural_mutation`, `budget_p95_ns=`,
  `budget_p99_ns=`, and `gate=pass` (the hosted Linux x86_64 budget-fit
  evidence);
- the committed PR-head workflow has no `continue-on-error` on the structural
  step.

If the first hosted run exceeds budget, record the failing numbers here, stop,
and revise the spec — do not mask the failure.

## Post-Merge Push Evidence

Post-merge evidence is added after the Slice 24 PR is merged and the `main` push
Swift CI run for the merge commit completes.

Required evidence:

- merge commit SHA;
- push run ID;
- all three required jobs `success`;
- host job structural gate step `success`;
- hosted structural rows include `gate=pass` and budget fields.
````

- [ ] **Step 5: Verify the record has no unresolved marker text**

Run:

```bash
set +e
rg -n "Paste the exact rows from|Paste the exact lines from|REPLACE_ME|PASTE_ME" docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
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
rg -n "Pre-Implementation Red Proof|synthetic_gate_status=0|variable_gate_status=0|vh_mutation_gate_status=0|structural_gate_status=0|mode=structural_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass|required_contexts=Host tests and benchmark gate\\|iOS cross-target compile\\|WASM cross-target observation|structural_gate_step=ok|structural_order=after_vh_mutation_before_memory_shape|foundation_scan_status=1|source_scope_status=0" docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
```

Expected: command exits `0` and prints matches for every required local proof
anchor.

- [ ] **Step 7: Commit the local verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
git commit -m "docs: record structural mutation gate verification"
```

Expected: commit succeeds.

## Task 5: Open PR And Record PR-Head Hosted Proof

**Files:**
- Modify: `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`
- Read: `.github/workflows/swift-ci.yml`
- Write temporary command outputs under `/private/tmp/slice-24-*`

- [ ] **Step 1: Push the branch and open the Slice 24 PR**

Run:

```bash
git status --short --branch
git push -u origin slice-24-structural-mutation-ci-gate-promotion
gh pr create \
  --title "Add structural mutation benchmark gate to host CI" \
  --body "Adds the existing --structural-mutation --gate benchmark as a new blocking step in the required host job and records verification evidence. Slice 24."
```

Expected: push succeeds and GitHub opens a PR targeting `main`.

- [ ] **Step 2: Capture PR metadata**

Run:

```bash
gh pr view --json number,headRefName,headRefOid,baseRefName,url,mergeStateStatus,statusCheckRollup > /private/tmp/slice-24-pr.json
jq -r '"pr=#\(.number)", "url=\(.url)", "headRefName=\(.headRefName)", "baseRefName=\(.baseRefName)", "headSha=\(.headRefOid)", "mergeStateStatus=\(.mergeStateStatus)"' /private/tmp/slice-24-pr.json
```

Expected: output shows the Slice 24 PR number, branch
`slice-24-structural-mutation-ci-gate-promotion`, base `main`, and current head
SHA.

- [ ] **Step 3: Wait for the final PR-head Swift CI run**

Run:

```bash
head_sha=$(jq -r '.headRefOid' /private/tmp/slice-24-pr.json)
gh run list \
  --workflow "Swift CI" \
  --branch slice-24-structural-mutation-ci-gate-promotion \
  --event pull_request \
  --limit 10 \
  --json databaseId,headSha,event,status,conclusion,displayTitle,createdAt \
  --jq ".[] | select(.headSha == \"${head_sha}\")"
```

Expected: a completed pull request run for the PR head SHA appears with `status`
`completed` and `conclusion` `success`. If the run is still queued or in
progress, wait for completion before continuing.

- [ ] **Step 4: Save the PR-head run JSON and required job conclusions**

Run:

```bash
head_sha=$(jq -r '.headRefOid' /private/tmp/slice-24-pr.json)
run_id=$(gh run list \
  --workflow "Swift CI" \
  --branch slice-24-structural-mutation-ci-gate-promotion \
  --event pull_request \
  --limit 10 \
  --json databaseId,headSha,status,conclusion \
  --jq ".[] | select(.headSha == \"${head_sha}\" and .status == \"completed\") | .databaseId" | head -n 1)
echo "pr_head_run_id=${run_id}" > /private/tmp/slice-24-pr-run-id.out
gh run view "$run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-24-pr-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-24-pr-run.json
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
run_id=$(sed 's/pr_head_run_id=//' /private/tmp/slice-24-pr-run-id.out)
host_job_id=$(jq -r '.jobs[] | select(.name == "Host tests and benchmark gate") | .databaseId' /private/tmp/slice-24-pr-run.json)
gh run view "$run_id" --job "$host_job_id" --log > /private/tmp/slice-24-pr-host-job.log
rg -n "Run structural mutation benchmark gate|mode=structural_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass" /private/tmp/slice-24-pr-host-job.log
```

Expected: command exits `0`. The log includes the hosted step name and three
`mode=structural_mutation ... gate=pass` rows with `budget_p95_ns=` and
`budget_p99_ns=`. If any row shows `gate=fail`, STOP and follow the
budget-failure path in the Global Constraints (revise spec, do not mask).

- [ ] **Step 6: Prove the committed PR-head workflow has no structural `continue-on-error`**

Run:

```bash
head_sha=$(jq -r '.headRefOid' /private/tmp/slice-24-pr.json)
git fetch origin slice-24-structural-mutation-ci-gate-promotion
git show "$head_sha:.github/workflows/swift-ci.yml" > /private/tmp/slice-24-pr-head-workflow.yml
ruby -ryaml -e '
structural = YAML.load_file("/private/tmp/slice-24-pr-head-workflow.yml")
  .fetch("jobs")
  .fetch("host-tests-and-benchmark-gate")
  .fetch("steps")
  .find { |step| step["name"].to_s.include?("structural mutation") }
abort("missing structural step") unless structural
abort("wrong name") unless structural["name"] == "Run structural mutation benchmark gate"
abort("continue-on-error present") if structural.key?("continue-on-error")
abort("missing gate") unless structural["run"].to_s.include?("--structural-mutation --gate")
puts "pr_head_structural_gate_step=ok"
'
```

Expected:

```text
pr_head_structural_gate_step=ok
```

- [ ] **Step 7: Update the verification record with PR-head evidence**

Update `## Hosted PR-Head Evidence` in
`docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`
with:

- PR number and URL from `/private/tmp/slice-24-pr.json`;
- head SHA from `/private/tmp/slice-24-pr.json`;
- Swift CI run ID from `/private/tmp/slice-24-pr-run-id.out`;
- required job conclusions from `/private/tmp/slice-24-pr-run.json`;
- hosted structural gate log lines from `/private/tmp/slice-24-pr-host-job.log`;
- `pr_head_structural_gate_step=ok`.

Run:

```bash
rg -n "Hosted PR-Head Evidence|PR #|head SHA|Swift CI run|Host tests and benchmark gate=success|iOS cross-target compile=success|WASM cross-target observation=success|Run structural mutation benchmark gate|mode=structural_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass|pr_head_structural_gate_step=ok" docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
```

Expected: command exits `0` and prints matches for every PR-head proof anchor.

- [ ] **Step 8: Commit PR-head hosted evidence**

Run:

```bash
git add docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
git commit -m "docs: record structural mutation gate hosted proof"
git push
```

Expected: commit and push succeed. The pushed documentation commit starts a new
PR-head Swift CI run because the full PR diff still includes workflow YAML. Wait
for that new run and confirm the required contexts are green before merge, but do
not churn the verification document solely to chase the CI run created by its own
evidence update. Task 6 records the merged workflow behavior from the post-merge
push run.

## Task 6: Merge And Record Post-Merge Hosted Proof

**Files:**
- Modify: `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`
- Write temporary command outputs under `/private/tmp/slice-24-*`

- [ ] **Step 1: Confirm green required checks, then merge with user/admin approval**

Run:

```bash
gh pr view --json number,mergeStateStatus,statusCheckRollup,url
```

Expected: the three required Swift CI contexts are green. The `Main` ruleset
requires an admin bypass to merge, so this repo's normal flow needs the
bypass-capable admin user. Confirm with the user before merging; do not merge
unattended. Merge using the repository's normal PR flow once approved.

- [ ] **Step 2: Capture merge commit metadata**

Run after merge:

```bash
gh pr view --json number,mergeCommit,mergedAt,mergedBy,url > /private/tmp/slice-24-merged-pr.json
jq -r '"pr=#\(.number)", "mergeCommit=\(.mergeCommit.oid)", "mergedAt=\(.mergedAt)", "mergedBy=\(.mergedBy.login)"' /private/tmp/slice-24-merged-pr.json
```

Expected: output includes a non-empty merge commit SHA.

- [ ] **Step 3: Capture the post-merge push run**

Run:

```bash
merge_sha=$(jq -r '.mergeCommit.oid' /private/tmp/slice-24-merged-pr.json)
gh run list \
  --workflow "Swift CI" \
  --branch main \
  --event push \
  --limit 20 \
  --json databaseId,headSha,event,status,conclusion,displayTitle,createdAt \
  --jq ".[] | select(.headSha == \"${merge_sha}\")"
```

Expected: a completed `push` run for the merge commit appears. Because this slice
changes `.github/workflows/swift-ci.yml`, `push.paths-ignore` should not skip the
workflow. If no run appears, document the exact blocker instead of inventing
post-merge proof.

- [ ] **Step 4: Save post-merge run JSON and host-job logs**

Run:

```bash
merge_sha=$(jq -r '.mergeCommit.oid' /private/tmp/slice-24-merged-pr.json)
run_id=$(gh run list \
  --workflow "Swift CI" \
  --branch main \
  --event push \
  --limit 20 \
  --json databaseId,headSha,status,conclusion \
  --jq ".[] | select(.headSha == \"${merge_sha}\" and .status == \"completed\") | .databaseId" | head -n 1)
echo "post_merge_run_id=${run_id}" > /private/tmp/slice-24-post-merge-run-id.out
gh run view "$run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-24-post-merge-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-24-post-merge-run.json
host_job_id=$(jq -r '.jobs[] | select(.name == "Host tests and benchmark gate") | .databaseId' /private/tmp/slice-24-post-merge-run.json)
gh run view "$run_id" --job "$host_job_id" --log > /private/tmp/slice-24-post-merge-host-job.log
rg -n "Run structural mutation benchmark gate|mode=structural_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass" /private/tmp/slice-24-post-merge-host-job.log
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

The hosted host-job log includes the structural gate step and three
`mode=structural_mutation ... gate=pass` rows with budget fields.

- [ ] **Step 5: Create the post-merge verification follow-up branch**

Run:

```bash
git fetch origin main
git checkout -B slice-24-post-merge-verification origin/main
```

Expected: branch `slice-24-post-merge-verification` is based on the current
`origin/main`, which contains the merged Slice 24 verification record.

- [ ] **Step 6: Record post-merge proof**

Update `## Post-Merge Push Evidence` in
`docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`
on the follow-up branch with:

- merge commit SHA;
- push run ID;
- required job conclusions;
- hosted structural gate log lines.

Run:

```bash
rg -n "Post-Merge Push Evidence|merge commit|push run|Host tests and benchmark gate=success|iOS cross-target compile=success|WASM cross-target observation=success|Run structural mutation benchmark gate|mode=structural_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass" docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
```

Expected: command exits `0` and prints matches for every post-merge proof anchor.

- [ ] **Step 7: Commit post-merge evidence as a docs-only follow-up**

Run:

```bash
git add docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
git commit -m "docs: record structural mutation gate post-merge proof"
git push -u origin slice-24-post-merge-verification
gh pr create \
  --title "Record Slice 24 post-merge verification" \
  --body "Records post-merge Swift CI evidence for the structural-mutation gate promotion."
```

Expected: follow-up PR contains only the verification document update. Its own
Swift CI required contexts may take the trusted docs-only lightweight path. Merge
this follow-up before the post-slice review (Slice 23 lesson #3) with user/admin
approval.

## Task 7: Final Acceptance Review

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Read: `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`

- [ ] **Step 1: Run the final acceptance scan**

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
steps = jobs.fetch("host-tests-and-benchmark-gate").fetch("steps")
names = steps.map { |s| s["name"].to_s }
structural = steps.find { |s| s["name"].to_s.include?("structural mutation") }
abort("missing structural step") unless structural
abort("wrong structural step name") unless structural["name"] == "Run structural mutation benchmark gate"
abort("structural step has continue-on-error") if structural.key?("continue-on-error")
abort("structural step missing gate") unless structural["run"].to_s.include?("--structural-mutation --gate")
vh_mut = names.index { |n| n.include?("variable-height mutation") }
struct_idx = names.index { |n| n.include?("structural mutation") }
mem = names.index { |n| n.include?("memory shape") }
abort("ordering wrong") unless vh_mut < struct_idx && struct_idx < mem
puts "final_workflow_acceptance=pass"
'
rg -n -- "--structural-mutation --gate" AGENTS.md
rg -n "structural_gate_step=ok|mode=structural_mutation.*budget_p95_ns=.*budget_p99_ns=.*gate=pass|Hosted PR-Head Evidence|Post-Merge Push Evidence" docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
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
rg -n "Acceptance Criteria|Run structural mutation benchmark gate|--structural-mutation --gate|continue-on-error|three required job context names|positioned after the variable-height mutation gate|AGENTS.md describes the structural-mutation|Hosted PR-head|Post-merge push" docs/superpowers/specs/2026-06-20-structural-mutation-ci-gate-promotion-design.md
```

Expected: command exits `0`. Manually check each acceptance criterion against the
workflow, `AGENTS.md`, and verification record:

- `.github/workflows/swift-ci.yml` contains a `Run structural mutation benchmark
  gate` step invoking `--structural-mutation --gate`.
- The structural step has no `continue-on-error`.
- The structural step is positioned after the variable-height mutation gate and
  before the memory-shape diagnostic.
- Required job context names are unchanged.
- `AGENTS.md` describes the structural-mutation benchmark as a blocking host-job
  gate.
- Local structural gate output includes `gate=pass` and budget fields.
- Hosted PR-head CI has the structural gate step successful with recorded Linux
  p95/p99.
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

- [ ] Spec coverage: every Slice 24 goal maps to a completed task above.
- [ ] Unresolved-marker scan: the verification record contains actual command output from `/private/tmp/slice-24-*` and no remaining marker text such as `Paste the exact`, `REPLACE_ME`, or `PASTE_ME`.
- [ ] Type/path consistency: workflow job id is still `host-tests-and-benchmark-gate`; required job names are still exactly `Host tests and benchmark gate`, `iOS cross-target compile`, and `WASM cross-target observation`; the new step name is exactly `Run structural mutation benchmark gate`.
- [ ] Ordering: structural step is after the variable-height mutation gate and before the memory-shape diagnostic.
- [ ] Budget ownership: budgets remain only in `Sources/ViewportBenchmarks`; workflow YAML does not duplicate numeric thresholds.
- [ ] Budget-failure discipline: if the hosted run exceeded budget, the spec was revised with the hosted numbers rather than masking the failure.
- [ ] Docs-only behavior: `.github/scripts/detect-docs-only-pr.sh` and trusted detector invocation are unchanged.
