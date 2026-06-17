# Policy-Sensitive Markdown Path Hardening Verification

Date: 2026-06-17

## Scope

Slice 20 hardens `.github/scripts/detect-docs-only-pr.sh` so Markdown files
under `.github/workflows/**` and `.github/scripts/**` are classified as non-doc
before the generic Markdown allow rule. The slice also clarifies `AGENTS.md`.

No Swift source, tests, package metadata, workflow topology, job names,
benchmark modes, benchmark budgets, or ruleset settings are intentionally
changed.

## Local Red Evidence

### Baseline Detector Self-Test

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-self-test-before.out 2>&1
```

Output:

```text
self_test=pass
```

Status: `0`

### Pre-Change Runtime Policy-Sensitive Markdown Bug

Captured state: before Task 3 classifier fix, from the branch state before
commit `e9f5b8954cdf33a0b454ef728ca254e2bbccc26a`.

Command:

```bash
bash -lc '
set -euo pipefail
repo_root="$PWD"
repo=$(mktemp -d /private/tmp/slice-20-policy-md-before.XXXXXX)
cleanup() { rm -rf "$repo"; }
trap cleanup EXIT
script="$repo/detect-docs-only-pr-before-e9f5b895.sh"
git -C "$repo_root" show e9f5b8954cdf33a0b454ef728ca254e2bbccc26a^:.github/scripts/detect-docs-only-pr.sh > "$script"
chmod +x "$script"
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

Output:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

Status: `0`

### Runtime Self-Test Red

Captured state: intermediate uncommitted TDD state after Task 2 runtime test
additions and before Task 3 deny-first classifier fix. Running this command
against current `HEAD` is expected to produce green output, not this red proof.

Command:

```bash
bash -lc '
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
'
```

Output:

```text
self_test=fail label=runtime_workflow_markdown_change_output expected_contains=docs_only_pr=false actual=mode=docs_only_pr result=docs_only docs_only_pr=true file_count=1 non_doc_count=0
runtime_red_status=1
```

Reviewed red substrings:

```text
self_test=fail label=runtime_workflow_markdown_change_output
expected_contains=docs_only_pr=false
docs_only_pr=true
```

Detector self-test status: `1`

Verification wrapper status: `0`

### Direct Path Self-Test Red

Captured state: intermediate uncommitted TDD state after adding direct path
assertions and before applying the deny-first classifier fix. Running this
command against current `HEAD` is expected to produce green output, not this red
proof.

Command:

```bash
bash -lc '
set +e
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-direct-red.out 2>&1
status=$?
set -e
cat /private/tmp/slice-20-direct-red.out
echo "direct_red_status=${status}"
test "$status" -eq 1
rg -n "self_test=fail label=workflow_markdown_is_policy_sensitive expected=failure actual=success" /private/tmp/slice-20-direct-red.out
'
```

Output:

```text
self_test=fail label=workflow_markdown_is_policy_sensitive expected=failure actual=success
direct_red_status=1
```

Detector self-test status: `1`

Verification wrapper status: `0`

## Local Green Evidence

### Detector Self-Test

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-20-final-self-test.out 2>&1
echo "$?" > /private/tmp/slice-20-final-self-test.status
```

Output:

```text
self_test=pass
```

Status: `0`

### Bash Syntax

Command:

```bash
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-20-final-bash-n.out 2>&1
echo "$?" > /private/tmp/slice-20-final-bash-n.status
```

Output:

```text
```

Status: `0`

### Policy-Sensitive Markdown Runtime Classification

Command:

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

Output:

```text
detector_status=0
mode=docs_only_pr result=not_docs_only docs_only_pr=false file_count=2 non_doc_count=2
```

Status: `0`

### True Docs-Only Runtime Classification

Command:

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

Output:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

Status: `0`

### Workflow Shape

Command:

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
```

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

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore > /private/tmp/slice-20-foundation-scan.out 2>&1
echo "$?" > /private/tmp/slice-20-foundation-scan.status
```

Output:

```text
```

Status: `1` (`rg` found no matches)

### Swift Source And Package Scope

Command:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift > /private/tmp/slice-20-source-scope-after.out
echo "$?" > /private/tmp/slice-20-source-scope-after.status
```

Output:

```text
```

Status: `0`

### Diff Whitespace

Command:

```bash
git diff --check main...HEAD > /private/tmp/slice-20-diff-check.out 2>&1
echo "$?" > /private/tmp/slice-20-diff-check.status
```

Output:

```text
```

Status: `0`

## Hosted Evidence

Hosted evidence is added in later plan tasks after GitHub Actions runs exist.
