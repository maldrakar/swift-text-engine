# Policy-Sensitive Markdown Path Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the trusted docs-only detector classify Markdown files under `.github/workflows/**` and `.github/scripts/**` as non-doc so policy-sensitive PRs run the heavy Swift CI path.

**Architecture:** Keep the Slice 19 trusted-base workflow topology unchanged: each required job still invokes `.github/scripts/detect-docs-only-pr.sh` from `$RUNNER_TEMP/trusted-ci`. Harden only the Bash detector's path classifier with deny-first policy-sensitive directory rules, then update `AGENTS.md` and verification evidence. No Swift source, package metadata, benchmark, workflow job-name, or ruleset mutation belongs to this slice.

**Tech Stack:** Bash, Git, GitHub Actions, GitHub CLI, Markdown.

---

## File Structure

- Modify `.github/scripts/detect-docs-only-pr.sh`: add self-test coverage for policy-sensitive Markdown paths and change `is_docs_only_path` to reject `.github/workflows/*` and `.github/scripts/*` before the generic `*.md` allow rule.
- Modify `AGENTS.md`: clarify that Markdown files under `.github/workflows/**` and `.github/scripts/**` are denied before Markdown docs-only matching.
- Create `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md`: record exact local red/green command evidence, workflow-shape proof, non-Swift scope proof, hosted PR-head proof, post-merge proof, ruleset readback, policy-sensitive Markdown proof PR, and true-docs-only proof PR.
- Read `.github/workflows/swift-ci.yml`: verify the Slice 19 trusted-base invocation remains unchanged; do not edit it unless verification finds drift from the approved Slice 20 spec.
- Use temporary files under `/private/tmp/slice-20-*` for local output captures and hosted log analysis.

No changes are planned for `Sources/**`, `Tests/**`, `Package.swift`, benchmark budgets, benchmark modes, required status-check contexts, bypass actors, or `pull_request_target` workflows.

## Scope Check

This plan implements:

```text
docs/superpowers/specs/2026-06-17-policy-sensitive-markdown-path-hardening-design.md
```

The spec covers one operational subsystem: docs-only PR path classification for the existing trusted Swift CI detector. It does not cover source/API behavior, benchmark calibration, provider portability, repository ruleset mutation, workflow topology changes, or bypass actor policy.

## Task 1: Preflight And Current Bug Proof

**Files:**
- Read: `docs/superpowers/specs/2026-06-17-policy-sensitive-markdown-path-hardening-design.md`
- Read: `.github/scripts/detect-docs-only-pr.sh`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Write temporary command outputs under `/private/tmp/slice-20-*`

- [ ] **Step 1: Confirm branch and clean local state**

Run:

```bash
git status --short --branch
git branch --show-current
git log --oneline --decorate -5
```

Expected: branch is `slice-20-policy-sensitive-markdown-hardening`, and the working tree is clean before implementation starts. The latest local commits include:

```text
docs: design policy-sensitive markdown hardening
docs: record slice 19 post-slice review
```

If `.github/scripts/detect-docs-only-pr.sh`, `.github/workflows/swift-ci.yml`, `AGENTS.md`, or `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md` are already modified, inspect the diff before continuing and preserve user-owned changes.

- [ ] **Step 2: Confirm approved spec content**

Run:

```bash
sed -n '1,420p' docs/superpowers/specs/2026-06-17-policy-sensitive-markdown-path-hardening-design.md
```

Expected: command exits `0` and output includes all of these strings:

```text
# Policy-Sensitive Markdown Path Hardening Design
Slice 20
Use deny-first classification in the detector
Keep the workflow topology unchanged
Test the bug before fixing it
Keep true docs-only behavior intact
Documentation must describe the exception precisely
```

- [ ] **Step 3: Capture current detector baseline**

Run:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-self-test-before.out 2>&1
self_status=$?
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-20-bash-n-before.out 2>&1
bash_status=$?
cat /private/tmp/slice-20-self-test-before.out
echo "self_test_status=${self_status}"
cat /private/tmp/slice-20-bash-n-before.out
echo "bash_n_status=${bash_status}"
test "$self_status" -eq 0
test "$bash_status" -eq 0
```

Expected:

```text
self_test=pass
self_test_status=0
bash_n_status=0
```

The `bash -n` output file should be empty.

- [ ] **Step 4: Capture the current policy-sensitive Markdown bug**

Run:

```bash
bash -lc '
set -euo pipefail
repo=$(mktemp -d /private/tmp/slice-20-policy-md-before.XXXXXX)
cleanup() { rm -rf "$repo"; }
trap cleanup EXIT
script="$PWD/.github/scripts/detect-docs-only-pr.sh"
cd "$repo"
git init -q
git config user.name "Slice 20 Test"
git config user.email "slice20@example.invalid"
mkdir -p docs
printf "base\n" > docs/base.md
git add docs/base.md
git commit -q -m base
base_sha=$(git rev-parse HEAD)
git checkout -q -B policy-md "$base_sha"
mkdir -p .github/workflows .github/scripts
printf "workflow docs\n" > .github/workflows/README.md
printf "script docs\n" > .github/scripts/README.md
git add .github/workflows/README.md .github/scripts/README.md
git commit -q -m policy-md
head_sha=$(git rev-parse HEAD)
set +e
output=$(bash "$script" --base "$base_sha" --head "$head_sha" 2>&1)
status=$?
set -e
printf "detector_status=%s\n%s\n" "$status" "$output"
' > /private/tmp/slice-20-policy-md-before.out 2>&1
cat /private/tmp/slice-20-policy-md-before.out
rg -n "detector_status=0" /private/tmp/slice-20-policy-md-before.out
rg -n "result=docs_only docs_only_pr=true file_count=2 non_doc_count=0" /private/tmp/slice-20-policy-md-before.out
```

Expected output includes:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

This is the pre-change runtime red proof for the confirmed Slice 19 P2.

- [ ] **Step 5: Capture current workflow trusted-base shape**

Run:

```bash
workflow=".github/workflows/swift-ci.yml"
printf "pull_request_lines="
rg -c "^  pull_request:" "$workflow"
printf "push_paths_ignore_lines="
rg -c "paths-ignore:" "$workflow"
printf "trusted_detector_count="
rg -c 'trusted_detector="\$\{trusted_ci_dir\}/\.github/scripts/detect-docs-only-pr\.sh"' "$workflow"
printf "trusted_invoke_count="
rg -c 'bash "\$trusted_detector" --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"' "$workflow"
printf "host_job_name_count="
rg -c "name: Host tests and benchmark gate" "$workflow"
printf "ios_job_name_count="
rg -c "name: iOS cross-target compile" "$workflow"
printf "wasm_job_name_count="
rg -c "name: WASM cross-target observation" "$workflow"
set +e
rg '^\s+\./\.github/scripts/detect-docs-only-pr\.sh --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"' "$workflow" > /private/tmp/slice-20-pr-owned-detector-before.out 2>&1
pr_owned_status=$?
set -e
cat /private/tmp/slice-20-pr-owned-detector-before.out
echo "pr_owned_detector_status=${pr_owned_status}"
test "$pr_owned_status" -eq 1
```

Expected:

```text
pull_request_lines=1
push_paths_ignore_lines=1
trusted_detector_count=3
trusted_invoke_count=3
host_job_name_count=1
ios_job_name_count=1
wasm_job_name_count=1
pr_owned_detector_status=1
```

This proves Slice 20 starts from the Slice 19 trusted-base workflow shape and should not need workflow YAML edits.

- [ ] **Step 6: Confirm source/package scope is empty**

Run:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift > /private/tmp/slice-20-source-scope-before.out
cat /private/tmp/slice-20-source-scope-before.out
test ! -s /private/tmp/slice-20-source-scope-before.out
```

Expected: no output and `test` exits `0`.

## Task 2: Add Runtime Self-Test Coverage For Policy-Sensitive Markdown

**Files:**
- Modify: `.github/scripts/detect-docs-only-pr.sh`

- [ ] **Step 1: Add runtime Markdown branches to detector self-test**

Patch `.github/scripts/detect-docs-only-pr.sh` inside `run_self_test()`.

Replace this local variable declaration:

```bash
  local script_path runtime_repo base_sha docs_head mixed_head workflow_head helper_head missing_sha
```

with:

```bash
  local script_path runtime_repo base_sha docs_head mixed_head workflow_head helper_head workflow_markdown_head helper_markdown_head missing_sha
```

After the existing `helper-change` branch block:

```bash
    git checkout -q -B helper-change "$base_sha"
    mkdir -p .github/scripts
    printf '#!/usr/bin/env bash\n' > .github/scripts/detect-docs-only-pr.sh
    git add .github/scripts/detect-docs-only-pr.sh
    git commit -q -m helper-change
    helper_head="$(git rev-parse HEAD)"
```

add:

```bash
    git checkout -q -B workflow-markdown-change "$base_sha"
    mkdir -p .github/workflows
    printf 'workflow docs\n' > .github/workflows/README.md
    git add .github/workflows/README.md
    git commit -q -m workflow-markdown-change
    workflow_markdown_head="$(git rev-parse HEAD)"

    git checkout -q -B helper-markdown-change "$base_sha"
    mkdir -p .github/scripts
    printf 'helper docs\n' > .github/scripts/README.md
    git add .github/scripts/README.md
    git commit -q -m helper-markdown-change
    helper_markdown_head="$(git rev-parse HEAD)"
```

After the existing runtime workflow/helper assertions:

```bash
    assert_runtime_classification "$script_path" "runtime_workflow_change" "$base_sha" "$workflow_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_helper_change" "$base_sha" "$helper_head" "0" "docs_only_pr=false" "docs_only_pr=false"
```

add:

```bash
    assert_runtime_classification "$script_path" "runtime_workflow_markdown_change" "$base_sha" "$workflow_markdown_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_helper_markdown_change" "$base_sha" "$helper_markdown_head" "0" "docs_only_pr=false" "docs_only_pr=false"
```

- [ ] **Step 2: Run self-test and verify runtime red failure**

Run:

```bash
set +e
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-runtime-red.out 2>&1
status=$?
set -e
cat /private/tmp/slice-20-runtime-red.out
echo "runtime_red_status=${status}"
test "$status" -eq 1
rg -n "self_test=fail label=runtime_workflow_markdown_change_output" /private/tmp/slice-20-runtime-red.out
rg -n "expected_contains=docs_only_pr=false" /private/tmp/slice-20-runtime-red.out
rg -n "docs_only_pr=true" /private/tmp/slice-20-runtime-red.out
```

Expected: status is `1`; output shows `runtime_workflow_markdown_change_output` failed because the current detector emitted `docs_only_pr=true` for `.github/workflows/README.md`.

Do not commit this failing state.

## Task 3: Add Direct Path Coverage And Deny-First Fix

**Files:**
- Modify: `.github/scripts/detect-docs-only-pr.sh`

- [ ] **Step 1: Add direct path-level self-test coverage**

Patch `.github/scripts/detect-docs-only-pr.sh` inside `run_self_test()`.

After:

```bash
  assert_command_failure "workflow_yaml" is_docs_only_path .github/workflows/swift-ci.yml
```

add:

```bash
  assert_command_failure "workflow_markdown_is_policy_sensitive" is_docs_only_path .github/workflows/README.md
  assert_command_failure "helper_markdown_is_policy_sensitive" is_docs_only_path .github/scripts/README.md
```

- [ ] **Step 2: Run self-test and verify direct path red failure**

Run:

```bash
set +e
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-direct-red.out 2>&1
status=$?
set -e
cat /private/tmp/slice-20-direct-red.out
echo "direct_red_status=${status}"
test "$status" -eq 1
rg -n "self_test=fail label=workflow_markdown_is_policy_sensitive expected=failure actual=success" /private/tmp/slice-20-direct-red.out
```

Expected: status is `1`; output shows `.github/workflows/README.md` still matches the current generic `*.md` allow rule.

Do not commit this failing state.

- [ ] **Step 3: Apply the minimal deny-first classifier**

Patch `is_docs_only_path()` in `.github/scripts/detect-docs-only-pr.sh`.

Replace:

```bash
is_docs_only_path() {
  local path="$1"
  case "$path" in
    docs/*|*.md) return 0 ;;
    *) return 1 ;;
  esac
}
```

with:

```bash
is_docs_only_path() {
  local path="$1"
  case "$path" in
    .github/workflows/*|.github/scripts/*) return 1 ;;
    docs/*|*.md) return 0 ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Run detector green checks**

Run:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-self-test-after.out 2>&1
self_status=$?
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-20-bash-n-after.out 2>&1
bash_status=$?
cat /private/tmp/slice-20-self-test-after.out
echo "self_test_status=${self_status}"
cat /private/tmp/slice-20-bash-n-after.out
echo "bash_n_status=${bash_status}"
test "$self_status" -eq 0
test "$bash_status" -eq 0
```

Expected:

```text
self_test=pass
self_test_status=0
bash_n_status=0
```

The `bash -n` output file should be empty.

- [ ] **Step 5: Verify combined runtime policy-sensitive Markdown classification**

Run:

```bash
bash -lc '
set -euo pipefail
repo=$(mktemp -d /private/tmp/slice-20-policy-md-after.XXXXXX)
cleanup() { rm -rf "$repo"; }
trap cleanup EXIT
script="$PWD/.github/scripts/detect-docs-only-pr.sh"
cd "$repo"
git init -q
git config user.name "Slice 20 Test"
git config user.email "slice20@example.invalid"
mkdir -p docs
printf "base\n" > docs/base.md
git add docs/base.md
git commit -q -m base
base_sha=$(git rev-parse HEAD)
git checkout -q -B policy-md "$base_sha"
mkdir -p .github/workflows .github/scripts
printf "workflow docs\n" > .github/workflows/README.md
printf "script docs\n" > .github/scripts/README.md
git add .github/workflows/README.md .github/scripts/README.md
git commit -q -m policy-md
head_sha=$(git rev-parse HEAD)
set +e
output=$(bash "$script" --base "$base_sha" --head "$head_sha" 2>&1)
status=$?
set -e
printf "detector_status=%s\n%s\n" "$status" "$output"
' > /private/tmp/slice-20-policy-md-after.out 2>&1
cat /private/tmp/slice-20-policy-md-after.out
rg -n "detector_status=0" /private/tmp/slice-20-policy-md-after.out
rg -n "result=not_docs_only docs_only_pr=false file_count=2 non_doc_count=2" /private/tmp/slice-20-policy-md-after.out
```

Expected output includes:

```text
detector_status=0
mode=docs_only_pr result=not_docs_only docs_only_pr=false file_count=2 non_doc_count=2
```

- [ ] **Step 6: Verify true docs-only runtime classification still passes**

Run:

```bash
bash -lc '
set -euo pipefail
repo=$(mktemp -d /private/tmp/slice-20-docs-md-after.XXXXXX)
cleanup() { rm -rf "$repo"; }
trap cleanup EXIT
script="$PWD/.github/scripts/detect-docs-only-pr.sh"
cd "$repo"
git init -q
git config user.name "Slice 20 Test"
git config user.email "slice20@example.invalid"
mkdir -p docs
printf "base\n" > docs/base.md
git add docs/base.md
git commit -q -m base
base_sha=$(git rev-parse HEAD)
git checkout -q -B docs-only "$base_sha"
printf "root docs\n" > README.md
mkdir -p docs/assets
printf "diagram\n" > docs/assets/diagram.png
git add README.md docs/assets/diagram.png
git commit -q -m docs-only
head_sha=$(git rev-parse HEAD)
set +e
output=$(bash "$script" --base "$base_sha" --head "$head_sha" 2>&1)
status=$?
set -e
printf "detector_status=%s\n%s\n" "$status" "$output"
' > /private/tmp/slice-20-docs-md-after.out 2>&1
cat /private/tmp/slice-20-docs-md-after.out
rg -n "detector_status=0" /private/tmp/slice-20-docs-md-after.out
rg -n "result=docs_only docs_only_pr=true file_count=2 non_doc_count=0" /private/tmp/slice-20-docs-md-after.out
```

Expected output includes:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

- [ ] **Step 7: Commit detector hardening**

Run:

```bash
git diff -- .github/scripts/detect-docs-only-pr.sh
git diff --check .github/scripts/detect-docs-only-pr.sh
git add .github/scripts/detect-docs-only-pr.sh
git commit -m "ci: harden policy-sensitive docs classification"
```

Expected: diff contains only detector self-test additions and the deny-first `is_docs_only_path` rule. Commit succeeds.

## Task 4: Clarify Durable CI Guidance

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Update docs-only classifier wording in `AGENTS.md`**

Patch the CI section in `AGENTS.md`.

Replace this paragraph:

```markdown
detector reads Git metadata from the PR workspace and compares the full
`BASE_SHA...HEAD_SHA` diff, but the code that decides `docs_only_pr` is not
loaded from the PR checkout. If the full PR diff is only `docs/**` or `**/*.md`,
the job prints `mode=docs_only_pr ... result=success` and skips the heavy
Swift/test/compile work. Missing commits, diff failures, and empty runtime diffs
fail closed. PR-owned workflow/helper changes under `.github/workflows/**` or
`.github/scripts/**`, Swift source, tests, package metadata, and all other
non-doc paths are not docs-only and must run the heavy path. Docs-only pushes to
`main` may still skip Swift CI through the `push.paths-ignore` rule because PR
required checks are the merge gate.
```

with:

```markdown
detector reads Git metadata from the PR workspace and compares the full
`BASE_SHA...HEAD_SHA` diff, but the code that decides `docs_only_pr` is not
loaded from the PR checkout. The detector rejects `.github/workflows/**` and
`.github/scripts/**` before applying the Markdown allow rule, so files in those
policy-sensitive directories are not docs-only regardless of extension. If the
full PR diff is only `docs/**` or Markdown files outside those policy-sensitive
directories, the job prints `mode=docs_only_pr ... result=success` and skips the
heavy Swift/test/compile work. Missing commits, diff failures, and empty runtime
diffs fail closed. Swift source, tests, package metadata, and all other non-doc
paths are not docs-only and must run the heavy path. Docs-only pushes to `main`
may still skip Swift CI through the `push.paths-ignore` rule because PR required
checks are the merge gate.
```

- [ ] **Step 2: Verify updated wording**

Run:

```bash
rg -n "rejects \\.github/workflows/\\*\\*|Markdown files outside those policy-sensitive directories|regardless of extension|BASE_SHA\\.\\.\\.HEAD_SHA" AGENTS.md
git diff --check AGENTS.md
```

Expected: `rg` prints lines from the CI section, and `git diff --check` exits `0`.

- [ ] **Step 3: Commit documentation guidance**

Run:

```bash
git diff -- AGENTS.md
git add AGENTS.md
git commit -m "docs: clarify policy-sensitive markdown classification"
```

Expected: commit succeeds and only `AGENTS.md` is included.

## Task 5: Record Local Verification Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md`

- [ ] **Step 1: Run final local verification commands**

Run:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-final-self-test.out 2>&1
echo "$?" > /private/tmp/slice-20-final-self-test.status
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-20-final-bash-n.out 2>&1
echo "$?" > /private/tmp/slice-20-final-bash-n.status
rg -n "Foundation" Sources/TextEngineCore > /private/tmp/slice-20-foundation-scan.out 2>&1
echo "$?" > /private/tmp/slice-20-foundation-scan.status
git diff --name-only main...HEAD -- Sources Tests Package.swift > /private/tmp/slice-20-source-scope-after.out
echo "$?" > /private/tmp/slice-20-source-scope-after.status
git diff --check main...HEAD > /private/tmp/slice-20-diff-check.out 2>&1
echo "$?" > /private/tmp/slice-20-diff-check.status
```

Expected:

```text
/private/tmp/slice-20-final-self-test.status = 0
/private/tmp/slice-20-final-bash-n.status = 0
/private/tmp/slice-20-foundation-scan.status = 1
/private/tmp/slice-20-source-scope-after.status = 0
/private/tmp/slice-20-diff-check.status = 0
```

The Foundation scan status is `1` because `rg` found no matches.

- [ ] **Step 2: Run final workflow-shape verification**

Run:

```bash
bash -lc '
set -euo pipefail
workflow=".github/workflows/swift-ci.yml"
pull_request_lines=$(rg -c "^  pull_request:" "$workflow")
push_paths_ignore_lines=$(rg -c "paths-ignore:" "$workflow")
trusted_detector_count=$(rg -c '\''trusted_detector="\$\{trusted_ci_dir\}/\.github/scripts/detect-docs-only-pr\.sh"'\'' "$workflow")
trusted_invoke_count=$(rg -c '\''bash "\$trusted_detector" --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"'\'' "$workflow")
host_job_name_count=$(rg -c "name: Host tests and benchmark gate" "$workflow")
ios_job_name_count=$(rg -c "name: iOS cross-target compile" "$workflow")
wasm_job_name_count=$(rg -c "name: WASM cross-target observation" "$workflow")
if rg '\''^\s+\./\.github/scripts/detect-docs-only-pr\.sh --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"'\'' "$workflow" >/tmp/slice-20-pr-owned-detector-lines.out 2>&1; then
  pr_owned_detector_count=$(wc -l < /tmp/slice-20-pr-owned-detector-lines.out)
else
  pr_owned_detector_count=0
fi
printf "pull_request_lines=%s\n" "$pull_request_lines"
printf "push_paths_ignore_lines=%s\n" "$push_paths_ignore_lines"
printf "trusted_detector_count=%s\n" "$trusted_detector_count"
printf "trusted_invoke_count=%s\n" "$trusted_invoke_count"
printf "host_job_name_count=%s\n" "$host_job_name_count"
printf "ios_job_name_count=%s\n" "$ios_job_name_count"
printf "wasm_job_name_count=%s\n" "$wasm_job_name_count"
printf "pr_owned_detector_count=%s\n" "$pr_owned_detector_count"
test "$pull_request_lines" -eq 1
test "$push_paths_ignore_lines" -eq 1
test "$trusted_detector_count" -eq 3
test "$trusted_invoke_count" -eq 3
test "$host_job_name_count" -eq 1
test "$ios_job_name_count" -eq 1
test "$wasm_job_name_count" -eq 1
test "$pr_owned_detector_count" -eq 0
' > /private/tmp/slice-20-workflow-shape.out 2>&1
echo "$?" > /private/tmp/slice-20-workflow-shape.status
cat /private/tmp/slice-20-workflow-shape.out
cat /private/tmp/slice-20-workflow-shape.status
```

Expected output:

```text
pull_request_lines=1
push_paths_ignore_lines=1
trusted_detector_count=3
trusted_invoke_count=3
host_job_name_count=1
ios_job_name_count=1
wasm_job_name_count=1
pr_owned_detector_count=0
```

Status file contains `0`.

- [ ] **Step 3: Create the local verification record**

Create `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md`. The file must contain concrete command blocks, concrete output blocks, and numeric statuses for each item below. Do not summarize a command as "passed"; record the exact output captured in `/private/tmp/slice-20-*`.

The verification file must start with:

```markdown
# Policy-Sensitive Markdown Path Hardening Verification

Date: 2026-06-17

## Scope

Slice 20 hardens `.github/scripts/detect-docs-only-pr.sh` so Markdown files
under `.github/workflows/**` and `.github/scripts/**` are classified as non-doc
before the generic Markdown allow rule. The slice also clarifies `AGENTS.md`.

No Swift source, tests, package metadata, workflow topology, job names,
benchmark modes, benchmark budgets, or ruleset settings are intentionally
changed.
```

The local red evidence section must include these commands and observed facts:

````markdown
## Local Red Evidence

### Baseline Detector Self-Test

Command: `./.github/scripts/detect-docs-only-pr.sh --self-test`

Output:

```text
self_test=pass
```

Status: `0`

### Pre-Change Runtime Policy-Sensitive Markdown Bug

Command: the reproduction script from Task 1 Step 4.

Output:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

### Runtime Self-Test Red

Command: `./.github/scripts/detect-docs-only-pr.sh --self-test`

Output must include:

```text
self_test=fail label=runtime_workflow_markdown_change_output
expected_contains=docs_only_pr=false
docs_only_pr=true
```

Status: `1`

### Direct Path Self-Test Red

Command: `./.github/scripts/detect-docs-only-pr.sh --self-test`

Output:

```text
self_test=fail label=workflow_markdown_is_policy_sensitive expected=failure actual=success
```

Status: `1`
````

The local green evidence section must include these commands and observed facts:

````markdown
## Local Green Evidence

### Detector Self-Test

Command: `./.github/scripts/detect-docs-only-pr.sh --self-test`

Output:

```text
self_test=pass
```

Status: `0`

### Bash Syntax

Command: `bash -n .github/scripts/detect-docs-only-pr.sh`

Output:

```text
```

Status: `0`

### Policy-Sensitive Markdown Runtime Classification

Command: the reproduction script from Task 3 Step 5.

Output:

```text
detector_status=0
mode=docs_only_pr result=not_docs_only docs_only_pr=false file_count=2 non_doc_count=2
```

### True Docs-Only Runtime Classification

Command: the reproduction script from Task 3 Step 6.

Output:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

### Workflow Shape

Command: the workflow-shape script from Task 5 Step 2.

Output:

```text
pull_request_lines=1
push_paths_ignore_lines=1
trusted_detector_count=3
trusted_invoke_count=3
host_job_name_count=1
ios_job_name_count=1
wasm_job_name_count=1
pr_owned_detector_count=0
```

Status: `0`

### Foundation-Free Core Scan

Command: `rg -n "Foundation" Sources/TextEngineCore`

Output:

```text
```

Status: `1` (`rg` found no matches)

### Swift Source And Package Scope

Command: `git diff --name-only main...HEAD -- Sources Tests Package.swift`

Output:

```text
```

Status: `0`

### Diff Whitespace

Command: `git diff --check main...HEAD`

Output:

```text
```

Status: `0`

## Hosted Evidence

Hosted evidence is added in later plan tasks after GitHub Actions runs exist.
````

- [ ] **Step 4: Verify the local verification record**

Run:

```bash
rg -n "Status: `1`|non_doc_count=2|trusted_detector_count=3|Foundation-Free Core Scan|Hosted evidence is added" docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git diff --check docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
```

Expected: `rg` prints matching lines and `git diff --check` exits `0`.

- [ ] **Step 5: Commit local verification**

Run:

```bash
git diff -- docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git add docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git commit -m "docs: record policy-sensitive markdown verification"
```

Expected: commit succeeds and only the verification file is included.

## Task 6: Open Slice 20 PR And Record PR-Head Hosted Heavy Proof

**Files:**
- Modify: `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md`

- [ ] **Step 1: Push the implementation branch and open the PR**

Run:

```bash
git status --short --branch
git push -u origin slice-20-policy-sensitive-markdown-hardening
gh pr create \
  --base main \
  --head slice-20-policy-sensitive-markdown-hardening \
  --title "Slice 20: harden policy-sensitive Markdown classification" \
  --body "Closes the Slice 19 P2 where Markdown files under .github/workflows/** or .github/scripts/** still matched the generic docs-only allow rule. Keeps trusted-base CI topology unchanged and adds detector self-test plus verification evidence."
```

Expected: branch pushes successfully and GitHub returns a PR URL. Save the PR number in the verification record.

- [ ] **Step 2: Wait for Swift CI and capture run metadata**

Run after GitHub Actions starts:

```bash
pr_number="$(gh pr view --json number --jq '.number')"
head_sha="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid')"
run_id="$(gh run list --workflow "Swift CI" --branch slice-20-policy-sensitive-markdown-hardening --limit 10 --json databaseId,headSha,status,conclusion,event --jq '[.[] | select(.headSha == "'"$head_sha"'" and .event == "pull_request")][0].databaseId')"
echo "pr_number=${pr_number}"
echo "head_sha=${head_sha}"
echo "run_id=${run_id}"
gh run view "$run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-20-pr-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-20-pr-run.json
```

Expected:

```text
Swift CI
pull_request
completed
success
Host tests and benchmark gate=success
iOS cross-target compile=success
WASM cross-target observation=success
```

The fifth printed line must equal the `head_sha` value printed earlier in this step.

If the run is still in progress, wait and rerun this step. If the run fails, inspect logs and fix the implementation before continuing.

- [ ] **Step 3: Capture hosted heavy-path log proof**

Run:

```bash
gh run view "$run_id" --log > /private/tmp/slice-20-pr-run.log
rg -n "Run host tests|Run synthetic benchmark gate|Run variable-height benchmark gate|Compile TextEngineCore for iOS targets|Observe TextEngineCore for WASM targets" /private/tmp/slice-20-pr-run.log
set +e
rg -n "mode=docs_only_pr job=.*result=success" /private/tmp/slice-20-pr-run.log > /private/tmp/slice-20-pr-docs-only-shortcut-lines.out 2>&1
shortcut_status=$?
set -e
cat /private/tmp/slice-20-pr-docs-only-shortcut-lines.out
echo "docs_only_shortcut_status=${shortcut_status}"
test "$shortcut_status" -eq 1
```

Expected: heavy step markers are present, and `docs_only_shortcut_status=1` because the Slice 20 PR changes `.github/scripts/detect-docs-only-pr.sh` and must not take the docs-only shortcut.

- [ ] **Step 4: Append PR-head hosted proof to verification**

Generate a concrete hosted-proof Markdown snippet:

```bash
{
  printf '### PR-Head Heavy Path\n\n'
  printf 'PR: #%s\n' "$pr_number"
  printf 'Head SHA: `%s`\n' "$head_sha"
  printf 'Run: `%s`\n\n' "$run_id"
  printf 'Run summary:\n\n'
  printf '```text\n'
  jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-20-pr-run.json
  printf '```\n\n'
  printf 'Heavy path markers found in hosted logs:\n\n'
  printf '```text\n'
  rg "Run host tests|Run synthetic benchmark gate|Run variable-height benchmark gate|Compile TextEngineCore for iOS targets|Observe TextEngineCore for WASM targets" /private/tmp/slice-20-pr-run.log
  printf '```\n\n'
  printf 'Docs-only shortcut marker search:\n\n'
  printf '```text\n'
  printf 'docs_only_shortcut_status=%s\n' "$shortcut_status"
  printf '```\n'
} > /private/tmp/slice-20-pr-hosted-proof.md
cat /private/tmp/slice-20-pr-hosted-proof.md
```

Expected: the generated snippet contains the concrete PR number, head SHA, run id, job conclusions, heavy path log markers, and `docs_only_shortcut_status=1`.

Update `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md` under `## Hosted Evidence` with the exact contents of `/private/tmp/slice-20-pr-hosted-proof.md`.

- [ ] **Step 5: Commit PR-head hosted proof**

Run:

```bash
git diff -- docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git diff --check docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git add docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git commit -m "docs: record policy-sensitive markdown PR proof"
git push
```

Expected: commit and push succeed. This push retriggers Swift CI; wait for the new final PR-head run and repeat Task 6 Steps 2-5 if the verification commit changes the head SHA. The verification record must name the latest completed PR-head run for the final head.

## Task 7: Merge And Record Post-Merge Required-Check Proof

**Files:**
- Modify: `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md`

- [ ] **Step 1: Merge the Slice 20 PR after final PR-head Swift CI is green**

Run:

```bash
pr_number="$(gh pr view --json number --jq '.number')"
gh pr view "$pr_number" --json mergeStateStatus,reviewDecision,statusCheckRollup
```

Expected: PR is mergeable under the repository policy and the three required Swift CI contexts are green. Merge using the repository's normal PR flow.

- [ ] **Step 2: Update local `main` and capture merge commit**

Run after merge:

```bash
git fetch origin main
git checkout main
git pull --ff-only origin main
merge_sha="$(git rev-parse HEAD)"
echo "merge_sha=${merge_sha}"
git log --oneline --decorate -5
```

Expected: `main` fast-forwards to the Slice 20 merge commit.

- [ ] **Step 3: Capture post-merge push run**

Run:

```bash
run_id="$(gh run list --workflow "Swift CI" --branch main --limit 20 --json databaseId,headSha,event,status,conclusion --jq '[.[] | select(.headSha == "'"$merge_sha"'" and .event == "push")][0].databaseId')"
echo "post_merge_run_id=${run_id}"
gh run view "$run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-20-post-merge-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-20-post-merge-run.json
```

Expected:

```text
Swift CI
push
completed
success
Host tests and benchmark gate=success
iOS cross-target compile=success
WASM cross-target observation=success
```

The fifth printed line must equal the `merge_sha` value printed in Task 7 Step 2.

- [ ] **Step 4: Capture live ruleset readback**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{
  id,
  name,
  target,
  enforcement,
  conditions,
  bypass_actors,
  required_status_checks: ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]),
  strict_required_status_checks_policy: (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy)
}' > /private/tmp/slice-20-ruleset-readback.json
cat /private/tmp/slice-20-ruleset-readback.json
jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and (.required_status_checks | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and .strict_required_status_checks_policy == true
' /private/tmp/slice-20-ruleset-readback.json
```

Expected: JSON contains the same three required contexts and strict policy is `true`; `jq -e` exits `0`.

- [ ] **Step 5: Record post-merge proof in verification**

Create a follow-up branch from updated `main`:

```bash
git checkout -b slice-20-verification-followup
```

Update `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md` with post-merge run and ruleset readback sections. Include the concrete merge SHA, run id, job conclusions, and ruleset JSON snippet from `/private/tmp/slice-20-ruleset-readback.json`.

Run:

```bash
git diff -- docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git diff --check docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git add docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git commit -m "docs: record policy-sensitive markdown post-merge proof"
git push -u origin slice-20-verification-followup
gh pr create \
  --base main \
  --head slice-20-verification-followup \
  --title "Slice 20 verification follow-up" \
  --body "Records post-merge Swift CI and ruleset evidence for Slice 20."
```

Expected: docs-only follow-up PR opens and should take the lightweight trusted docs-only path.

## Task 8: Hosted Proof PRs For Policy-Sensitive And True Docs-Only Paths

**Files:**
- Create temporary proof branches that may be closed unmerged.
- Modify verification follow-up PR if hosted proof evidence is recorded there.

- [ ] **Step 1: Create policy-sensitive Markdown proof PR**

From updated `main`, run:

```bash
git checkout main
git pull --ff-only origin main
git checkout -b slice-20-policy-sensitive-markdown-proof
mkdir -p .github/workflows .github/scripts
printf "Slice 20 policy-sensitive workflow Markdown proof.\n" > .github/workflows/README.md
printf "Slice 20 policy-sensitive helper Markdown proof.\n" > .github/scripts/README.md
git add .github/workflows/README.md .github/scripts/README.md
git commit -m "docs: prove policy-sensitive markdown heavy path"
git push -u origin slice-20-policy-sensitive-markdown-proof
gh pr create \
  --base main \
  --head slice-20-policy-sensitive-markdown-proof \
  --title "Slice 20 policy-sensitive Markdown proof" \
  --body "Proof PR for Slice 20: Markdown-only changes under .github/workflows/** and .github/scripts/** must run the heavy Swift CI path."
```

Expected: proof PR opens. It may remain unmerged and be closed after evidence is captured.

- [ ] **Step 2: Capture policy-sensitive proof run**

Run after Swift CI completes:

```bash
proof_pr="$(gh pr view --json number --jq '.number')"
proof_head_sha="$(gh pr view "$proof_pr" --json headRefOid --jq '.headRefOid')"
proof_run_id="$(gh run list --workflow "Swift CI" --branch slice-20-policy-sensitive-markdown-proof --limit 10 --json databaseId,headSha,event,status,conclusion --jq '[.[] | select(.headSha == "'"$proof_head_sha"'" and .event == "pull_request")][0].databaseId')"
echo "policy_sensitive_proof_pr=${proof_pr}"
echo "policy_sensitive_proof_head_sha=${proof_head_sha}"
echo "policy_sensitive_proof_run_id=${proof_run_id}"
gh run view "$proof_run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-20-policy-proof-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-20-policy-proof-run.json
gh run view "$proof_run_id" --log > /private/tmp/slice-20-policy-proof-run.log
rg -n "Run host tests|Run synthetic benchmark gate|Compile TextEngineCore for iOS targets|Observe TextEngineCore for WASM targets" /private/tmp/slice-20-policy-proof-run.log
set +e
rg -n "mode=docs_only_pr job=.*result=success" /private/tmp/slice-20-policy-proof-run.log > /private/tmp/slice-20-policy-proof-shortcut-lines.out 2>&1
shortcut_status=$?
set -e
echo "policy_sensitive_docs_only_shortcut_status=${shortcut_status}"
test "$shortcut_status" -eq 1
```

Expected: all three jobs are `success`, heavy path markers are present, and `policy_sensitive_docs_only_shortcut_status=1`.

- [ ] **Step 3: Create true docs-only proof PR**

From updated `main`, run:

```bash
git checkout main
git pull --ff-only origin main
git checkout -b slice-20-true-docs-only-proof
printf "Slice 20 true docs-only proof.\n" > docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening-docs-only-proof.md
git add docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening-docs-only-proof.md
git commit -m "docs: prove true docs-only lightweight path"
git push -u origin slice-20-true-docs-only-proof
gh pr create \
  --base main \
  --head slice-20-true-docs-only-proof \
  --title "Slice 20 true docs-only proof" \
  --body "Proof PR for Slice 20: true docs-only changes should still use the trusted lightweight path while emitting required Swift CI contexts."
```

Expected: proof PR opens. This proof PR may be merged if the tiny verification note is useful, or closed unmerged after evidence is captured.

- [ ] **Step 4: Capture true docs-only proof run**

Run after Swift CI completes:

```bash
docs_proof_pr="$(gh pr view --json number --jq '.number')"
docs_proof_head_sha="$(gh pr view "$docs_proof_pr" --json headRefOid --jq '.headRefOid')"
docs_proof_run_id="$(gh run list --workflow "Swift CI" --branch slice-20-true-docs-only-proof --limit 10 --json databaseId,headSha,event,status,conclusion --jq '[.[] | select(.headSha == "'"$docs_proof_head_sha"'" and .event == "pull_request")][0].databaseId')"
echo "docs_only_proof_pr=${docs_proof_pr}"
echo "docs_only_proof_head_sha=${docs_proof_head_sha}"
echo "docs_only_proof_run_id=${docs_proof_run_id}"
gh run view "$docs_proof_run_id" --json name,event,status,conclusion,headSha,jobs > /private/tmp/slice-20-docs-proof-run.json
jq -r '.name,.event,.status,.conclusion,.headSha,([.jobs[] | "\(.name)=\(.conclusion)"] | join("\n"))' /private/tmp/slice-20-docs-proof-run.json
gh run view "$docs_proof_run_id" --log > /private/tmp/slice-20-docs-proof-run.log
rg -n "mode=docs_only_pr job=host-tests-and-benchmark-gate result=success|mode=docs_only_pr job=ios-cross-target-compile result=success|mode=docs_only_pr job=wasm-cross-target-observation result=success" /private/tmp/slice-20-docs-proof-run.log
set +e
rg -n "Run host tests|Run synthetic benchmark gate|Compile TextEngineCore for iOS targets|Observe TextEngineCore for WASM targets" /private/tmp/slice-20-docs-proof-run.log > /private/tmp/slice-20-docs-proof-heavy-lines.out 2>&1
heavy_status=$?
set -e
echo "docs_only_heavy_marker_status=${heavy_status}"
test "$heavy_status" -eq 1
```

Expected: all three jobs are `success`; logs contain all three `mode=docs_only_pr ... result=success` markers; `docs_only_heavy_marker_status=1`.

- [ ] **Step 5: Record proof PR evidence in verification follow-up**

Return to the verification follow-up branch:

```bash
git checkout slice-20-verification-followup
```

Update `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md` with:

- policy-sensitive proof PR number, head SHA, run id, job conclusions, heavy marker evidence, and `policy_sensitive_docs_only_shortcut_status=1`;
- true docs-only proof PR number, head SHA, run id, job conclusions, docs-only shortcut markers, and `docs_only_heavy_marker_status=1`;
- whether proof PRs were merged or closed unmerged.

Run:

```bash
git diff -- docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git diff --check docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git add docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
git commit -m "docs: record policy-sensitive markdown hosted proof"
git push
```

Expected: verification follow-up branch updates successfully. Its PR should take the trusted docs-only path because only `docs/**` changed.

## Task 9: Final Verification And Review Handoff

**Files:**
- Read: `.github/scripts/detect-docs-only-pr.sh`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Read: `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md`

- [ ] **Step 1: Run final local sanity checks on the active branch**

Run from the branch being merged or reviewed:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test
bash -n .github/scripts/detect-docs-only-pr.sh
rg -n "Foundation" Sources/TextEngineCore
git diff --check main...HEAD
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Expected:

- detector self-test prints `self_test=pass` and exits `0`;
- `bash -n` exits `0` with no output;
- Foundation scan has no matches and exits `1`;
- `git diff --check` exits `0`;
- source/package diff command prints no output.

- [ ] **Step 2: Confirm commit structure**

Run:

```bash
git log --oneline --decorate main..HEAD
```

Expected commits are grouped by concern and include the already-created review/spec commits plus the implementation/verification commits:

```text
docs: record slice 19 post-slice review
docs: design policy-sensitive markdown hardening
docs: plan policy-sensitive markdown hardening
ci: harden policy-sensitive docs classification
docs: clarify policy-sensitive markdown classification
docs: record policy-sensitive markdown verification
docs: record policy-sensitive markdown PR proof
```

Post-merge follow-up branches may contain additional docs-only verification commits.

- [ ] **Step 3: Prepare post-slice review prompt**

After implementation, hosted proof, and verification follow-up are complete, request a post-slice review covering:

```text
docs/superpowers/specs/2026-06-17-policy-sensitive-markdown-path-hardening-design.md
docs/superpowers/plans/2026-06-17-policy-sensitive-markdown-path-hardening.md
docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
.github/scripts/detect-docs-only-pr.sh
AGENTS.md
.github/workflows/swift-ci.yml
PR-head run evidence
post-merge push run evidence
policy-sensitive Markdown proof PR evidence
true docs-only proof PR evidence
ruleset readback
```

Expected review focus: confirm the Slice 19 P2 is closed, true docs-only PRs still work, workflow trusted-base topology and required contexts are unchanged, and no Swift/package/benchmark surface changed.
