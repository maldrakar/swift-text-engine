# Trusted Docs-Only Gate Verification

Date: 2026-06-16

## Summary

Slice 19 makes the Swift CI docs-only shortcut run the classifier from the PR
base commit trusted worktree instead of PR-owned helper code. It also tightens
the detector so empty real runtime diffs fail closed.

No Swift source, tests, benchmark code, benchmark budgets, package metadata,
required job contexts, ruleset requirements, or bypass actors changed.

## Local State

Command:

```bash
git status --short --branch > /private/tmp/slice-19-git-status.txt
cat /private/tmp/slice-19-git-status.txt
```

Exit status: 0

Output:

```text
## slice-19-trusted-docs-only-gate...origin/slice-19-trusted-docs-only-gate [ahead 4]
?? docs/superpowers/plans/2026-06-16-trusted-docs-only-gate.md
```

The untracked plan file is pre-existing and intentionally not part of this
verification task.

## Detector Checks

Task 1 red proof for empty runtime diffs before the detector change:

Command:

```bash
base_sha="$(git rev-parse HEAD)"
./.github/scripts/detect-docs-only-pr.sh \
  --base "$base_sha" \
  --head "$base_sha" \
  > /private/tmp/slice-19-empty-runtime-before.out 2>&1
cat /private/tmp/slice-19-empty-runtime-before.out
```

Exit status: 0, from Task 1 report

Output:

```text
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=0 non_doc_count=0
```

This showed that empty real runtime diffs were incorrectly classified as
docs-only before the fix.

Task 2 red detector self-test:

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test \
  > /private/tmp/slice-19-detector-red.out 2>&1
cat /private/tmp/slice-19-detector-red.out
```

Exit status: 1, expected red test

Output:

```text
self_test=fail label=runtime_empty_diff_status expected=2 actual=0
```

Task 2 green runtime behavior after the detector change:

Command:

```bash
base_sha="$(git rev-parse HEAD)"
set +e
./.github/scripts/detect-docs-only-pr.sh \
  --base "$base_sha" \
  --head "$base_sha" \
  > /private/tmp/slice-19-empty-runtime-after.out 2>&1
empty_runtime_status=$?
set -e
cat /private/tmp/slice-19-empty-runtime-after.out
echo "empty_runtime_status=${empty_runtime_status}"
test "$empty_runtime_status" -eq 2
```

Detector exit status: 2; verification command exit status: 0, from Task 2 report

Output:

```text
mode=docs_only_pr result=infrastructure_failure reason=empty_diff docs_only_pr=false
```

Final detector self-test:

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-19-detector-self-test.out 2>&1
cat /private/tmp/slice-19-detector-self-test.out
```

Exit status: 0

Output:

```text
self_test=pass
```

Syntax check:

Command:

```bash
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-19-detector-bash-n.out 2>&1
```

Exit status: 0

Output: none; `/private/tmp/slice-19-detector-bash-n.out` is empty.

## Workflow Shape Checks

Task 3 red shape proof before the workflow change:

Command:

```bash
/private/tmp/slice-19-workflow-shape-check.sh \
  > /private/tmp/slice-19-workflow-shape-red.out 2>&1
cat /private/tmp/slice-19-workflow-shape-red.out
```

Exit status: 1, expected red test

Output:

```text
pull_request_paths_ignore=absent
push_paths_ignore=present
required_job_names=present
trusted_worktree_add_count=
```

Supplemental red-proof note:

Command:

```bash
parent_commit="dd5d996f5107b8d73efd0fb8514546bae15fd369^"
git show "${parent_commit}:.github/workflows/swift-ci.yml" \
  > /private/tmp/slice-19-parent-swift-ci.yml
{
  echo "parent_workflow=/private/tmp/slice-19-parent-swift-ci.yml"
  echo "parent_commit=${parent_commit}"
  echo "parent_trusted_worktree_matches=$(rg -c 'git worktree add --detach \"\\$trusted_ci_dir\" \"\\$BASE_SHA\"' /private/tmp/slice-19-parent-swift-ci.yml || true)"
  echo "parent_pr_workspace_detector_matches=$(rg -c '^\\s+\\./\\.github/scripts/detect-docs-only-pr\\.sh --base \"\\$BASE_SHA\" --head \"\\$HEAD_SHA\" --github-output \"\\$GITHUB_OUTPUT\"' /private/tmp/slice-19-parent-swift-ci.yml || true)"
  echo "note=original exact checker failed red before edits, but printed trusted_worktree_add_count= due to local rg -c no-match behavior rather than trusted_worktree_add_count=0"
  echo "conclusion=evidence_only_issue_not_workflow_implementation_issue"
} > /private/tmp/slice-19-workflow-shape-red-supplement.txt
cat /private/tmp/slice-19-workflow-shape-red-supplement.txt
```

Output:

```text
parent_workflow=/private/tmp/slice-19-parent-swift-ci.yml
parent_commit=dd5d996f5107b8d73efd0fb8514546bae15fd369^
parent_trusted_worktree_matches=0
parent_pr_workspace_detector_matches=3
note=original exact checker failed red before edits, but printed trusted_worktree_add_count= due to local rg -c no-match behavior rather than trusted_worktree_add_count=0
conclusion=evidence_only_issue_not_workflow_implementation_issue
```

Final green workflow shape check:

Command:

```bash
/private/tmp/slice-19-workflow-shape-check.sh > /private/tmp/slice-19-workflow-shape-green.out 2>&1
cat /private/tmp/slice-19-workflow-shape-green.out
```

Exit status: 0

Output:

```text
pull_request_paths_ignore=absent
push_paths_ignore=present
required_job_names=present
trusted_worktree_add_count=3
trusted_detector_path_count=3
trusted_detector_invocation_count=3
pr_workspace_detector_invocation=absent
pull_request_target=absent
workflow_shape=pass
```

The required job contexts remain:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

## Documentation Checks

Task 4 red documentation proof:

Command:

```bash
rg -n "trusted-ci|trusted base tree|BASE_SHA\\.\\.\\.HEAD_SHA|empty runtime diffs|\\.github/workflows/\\*\\*|\\.github/scripts/\\*\\*" AGENTS.md \
  > /private/tmp/slice-19-agents-before.out
cat /private/tmp/slice-19-agents-before.out
```

Exit status: 1, from Task 4 report

Output: none; `/private/tmp/slice-19-agents-before.out` is empty.

The red check confirmed the prior repo guidance did not yet document the trusted
base worktree docs-only behavior.

Final green documentation proof:

Command:

```bash
rg -n "trusted-ci|trusted base tree|BASE_SHA\\.\\.\\.HEAD_SHA|empty runtime diffs|\\.github/workflows/\\*\\*|\\.github/scripts/\\*\\*" AGENTS.md \
  > /private/tmp/slice-19-agents-after.out
cat /private/tmp/slice-19-agents-after.out
```

Exit status: 0

Output:

```text
122:`$RUNNER_TEMP/trusted-ci` with `git worktree` and executes
123:`.github/scripts/detect-docs-only-pr.sh` from that trusted base tree. The
125:`BASE_SHA...HEAD_SHA` diff, but the code that decides `docs_only_pr` is not
128:Swift/test/compile work. Missing commits, diff failures, and empty runtime diffs
129:fail closed. PR-owned workflow/helper changes under `.github/workflows/**` or
130:`.github/scripts/**`, Swift source, tests, package metadata, and all other
```

## Ruleset Readback

The first sandboxed network attempt failed with:

```text
error connecting to api.github.com
check your internet connection or https://githubstatus.com
```

The same readback was rerun with network escalation and passed.

Command:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 \
  --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' \
  > /private/tmp/slice-19-ruleset-final-local.json

jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and ([.rules[] | select(.type == "required_status_checks")] | length == 1)
  and ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy) == true
' /private/tmp/slice-19-ruleset-final-local.json
```

Exit status: 0

Output:

```text
true
```

Relevant readback summary:

```text
id=17656807
name=Main
target=branch
enforcement=active
strict_required_status_checks_policy=true
required_status_checks:
- Host tests and benchmark gate
- iOS cross-target compile
- WASM cross-target observation
bypass_actor_count=1
```

## Scope Proof

Final local check command:

```bash
git status --short --branch > /private/tmp/slice-19-git-status.txt
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-19-detector-self-test.out 2>&1
bash -n .github/scripts/detect-docs-only-pr.sh > /private/tmp/slice-19-detector-bash-n.out 2>&1
/private/tmp/slice-19-workflow-shape-check.sh > /private/tmp/slice-19-workflow-shape-green.out 2>&1
git diff --check > /private/tmp/slice-19-diff-check.out 2>&1
set +e
rg -n "Foundation" Sources/TextEngineCore > /private/tmp/slice-19-foundation-scan.out 2>&1
foundation_status=$?
git diff --name-only main...HEAD -- Sources Tests Package.swift > /private/tmp/slice-19-source-scope.out 2>&1
source_scope_status=$?
set -e
cat /private/tmp/slice-19-git-status.txt
cat /private/tmp/slice-19-detector-self-test.out
cat /private/tmp/slice-19-detector-bash-n.out
cat /private/tmp/slice-19-workflow-shape-green.out
cat /private/tmp/slice-19-diff-check.out
cat /private/tmp/slice-19-foundation-scan.out
echo "foundation_status=${foundation_status}"
cat /private/tmp/slice-19-source-scope.out
echo "source_scope_status=${source_scope_status}"
test "$foundation_status" -eq 1
test "$source_scope_status" -eq 0
test ! -s /private/tmp/slice-19-source-scope.out
```

Exit status: 0

Output:

```text
## slice-19-trusted-docs-only-gate...origin/slice-19-trusted-docs-only-gate [ahead 4]
?? docs/superpowers/plans/2026-06-16-trusted-docs-only-gate.md
self_test=pass
pull_request_paths_ignore=absent
push_paths_ignore=present
required_job_names=present
trusted_worktree_add_count=3
trusted_detector_path_count=3
trusted_detector_invocation_count=3
pr_workspace_detector_invocation=absent
pull_request_target=absent
workflow_shape=pass
foundation_status=1
source_scope_status=0
```

Additional empty-output proof:

```text
/private/tmp/slice-19-detector-bash-n.out: 0 bytes
/private/tmp/slice-19-diff-check.out: 0 bytes
/private/tmp/slice-19-foundation-scan.out: 0 bytes
/private/tmp/slice-19-source-scope.out: 0 bytes
```

No Swift source, tests, or package metadata are in the `main...HEAD` source
scope diff:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Exit status: 0

Output: none.

## Hosted PR-Head Heavy Proof

Hosted PR-head proof is not available before this local verification commit is
pushed and a PR-head Swift CI run completes.

Expected proof after push: a non-doc PR-head run exercises the heavy path for
the three required contexts:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

## Post-Merge Push Proof

Post-merge push proof is not available before the branch is merged to `main`
and the default-branch push Swift CI run completes.

Expected proof after merge: the post-merge `push` run records the trusted gate
changes on `main` and confirms the required Swift CI job topology still emits
the expected contexts.

## Hosted Docs-Only PR Proof

Hosted docs-only PR proof is not available before a docs-only PR run completes
with the trusted base detector path.

Expected proof after push/PR: a docs-only PR run prints
`mode=docs_only_pr ... result=success`, executes the detector from the trusted
base worktree, and emits the same required job contexts without running the
heavy Swift/test/compile work.
