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

Command:

```text
Task 1 Step 4 reproduction script, output captured in /private/tmp/slice-20-policy-md-before.out
```

Output:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

Status: `0`

### Runtime Self-Test Red

Command:

```text
Task 2 Step 1 runtime self-test red check, output captured in /private/tmp/slice-20-runtime-red.out
```

Output:

```text
self_test=fail label=runtime_workflow_markdown_change_output expected_contains=docs_only_pr=false actual=mode=docs_only_pr result=docs_only docs_only_pr=true file_count=1 non_doc_count=0
```

Reviewed red substrings:

```text
self_test=fail label=runtime_workflow_markdown_change_output
expected_contains=docs_only_pr=false
docs_only_pr=true
```

Status: `1`

### Direct Path Self-Test Red

Command:

```text
Task 2 Step 2 direct path self-test red check, output captured in /private/tmp/slice-20-direct-red.out
```

Output:

```text
self_test=fail label=workflow_markdown_is_policy_sensitive expected=failure actual=success
```

Status: `1`

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

```text
Task 3 Step 5 reproduction script, output captured in /private/tmp/slice-20-policy-md-after.out
```

Output:

```text
detector_status=0
mode=docs_only_pr result=not_docs_only docs_only_pr=false file_count=2 non_doc_count=2
```

Status: `0`

### True Docs-Only Runtime Classification

Command:

```text
Task 3 Step 6 reproduction script, output captured in /private/tmp/slice-20-docs-md-after.out
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
