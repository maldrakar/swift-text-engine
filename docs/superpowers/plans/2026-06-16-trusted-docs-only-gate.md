# Trusted Docs-Only Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Swift CI docs-only shortcut execute trusted base-commit classifier code while preserving the three required GitHub Actions job contexts.

**Architecture:** Keep `pull_request` Swift CI as the heavy test/build path, but add a trusted base worktree under `$RUNNER_TEMP` in each required job and run the docs-only detector from that worktree instead of the PR workspace. Tighten the Bash detector so real `--base/--head` runtime classification fails closed on empty diffs, then update durable docs and verification evidence. No Swift source, benchmark, package, or ruleset mutation is part of this slice.

**Tech Stack:** GitHub Actions, Bash, Git worktrees, GitHub CLI, GitHub REST ruleset readback, Markdown.

---

## File Structure

- Modify `.github/scripts/detect-docs-only-pr.sh`: keep the existing CLI (`--base SHA --head SHA [--github-output FILE]`, `--self-test`) and add runtime self-test coverage for docs-only, mixed, workflow/helper, missing commit, and empty-diff cases; fail closed on empty real `BASE...HEAD` diffs.
- Modify `.github/workflows/swift-ci.yml`: keep the three job names unchanged, preserve `push.paths-ignore`, leave `pull_request` unfiltered, and replace each PR change-scope step so it creates `$RUNNER_TEMP/trusted-ci` from `github.event.pull_request.base.sha` and invokes the detector from that trusted path.
- Modify `AGENTS.md`: document that docs-only PR classification is executed from the base commit trusted worktree, not from PR-owned helper code.
- Create `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md`: record local detector/workflow/doc checks, non-Swift scope proof, final PR-head heavy hosted proof, post-merge push proof, ruleset readback, and a hosted docs-only PR proof.
- Use temporary files under `/private/tmp/slice-19-*` for local shape checks, command output captures, GitHub API readbacks, and hosted run logs.

No changes are planned for `Sources/**`, `Tests/**`, `Package.swift`, benchmark budgets, benchmark modes, required status-check contexts, bypass actors, or `pull_request_target` workflows.

## Scope Check

This plan implements:

```text
docs/superpowers/specs/2026-06-16-trusted-docs-only-gate-design.md
```

The slice covers one operational subsystem: the docs-only PR classifier used by the existing Swift CI required jobs. It does not redesign benchmarks, source APIs, providers, package metadata, repository rulesets, merge queue behavior, admin bypass, or cross-target coverage.

## Task 1: Preflight And Red Proofs

**Files:**
- Read: `docs/superpowers/specs/2026-06-16-trusted-docs-only-gate-design.md`
- Read: `.github/scripts/detect-docs-only-pr.sh`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Write temporary command output under `/private/tmp/slice-19-*`

- [x] **Step 1: Confirm branch and local state**

Run:

```bash
git status --short --branch
git branch --show-current
git log --oneline --decorate -3
```

Expected: branch is `slice-19-trusted-docs-only-gate`. Existing user changes are acceptable only if they do not touch `.github/scripts/detect-docs-only-pr.sh`, `.github/workflows/swift-ci.yml`, `AGENTS.md`, or `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md`. If any of those files are already modified, inspect the diff before continuing and do not overwrite blindly.

- [x] **Step 2: Confirm the approved spec is present**

Run:

```bash
sed -n '1,380p' docs/superpowers/specs/2026-06-16-trusted-docs-only-gate-design.md
```

Expected: command exits `0` and output includes all of these strings:

```text
# Trusted Docs-Only Required-Check Gate Design
Slice 19
Run the classifier from the base commit
detect-docs-only-pr.sh --base SHA --head SHA [--github-output FILE]
Empty runtime diffs fail closed
Policy-sensitive paths are never docs-only
Hosted docs-only proof is required after merge
```

- [x] **Step 3: Capture the current empty runtime diff bug**

Run:

```bash
base_sha="$(git rev-parse HEAD)"
set +e
./.github/scripts/detect-docs-only-pr.sh --base "$base_sha" --head "$base_sha" > /private/tmp/slice-19-empty-runtime-before.out 2>&1
status=$?
set -e
cat /private/tmp/slice-19-empty-runtime-before.out
echo "status=${status}"
test "$status" -eq 0
rg -n "docs_only_pr=true|file_count=0" /private/tmp/slice-19-empty-runtime-before.out
```

Expected: status is `0`, and output includes `docs_only_pr=true` with `file_count=0`. This is the failing pre-change proof for Task 2.

- [x] **Step 4: Capture the current PR-owned detector invocation**

Run:

```bash
rg -n '^\s+\./\.github/scripts/detect-docs-only-pr\.sh --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"' .github/workflows/swift-ci.yml
set +e
rg -n 'trusted_detector=|git worktree add --detach "\$trusted_ci_dir" "\$BASE_SHA"' .github/workflows/swift-ci.yml > /private/tmp/slice-19-trusted-worktree-before.out 2>&1
trusted_status=$?
set -e
cat /private/tmp/slice-19-trusted-worktree-before.out
echo "trusted_status=${trusted_status}"
test "$trusted_status" -eq 1
```

Expected: the first `rg` prints three matches in the required jobs, and the trusted-worktree search exits `1` with no matches. This is the failing pre-change proof for Task 3.

- [x] **Step 5: Capture current required-check ruleset readback**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-19-ruleset-before.json
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
' /private/tmp/slice-19-ruleset-before.json
```

Expected: `jq -e` exits `0`. If `gh` authentication or repo access is unavailable, continue with local implementation but record the exact blocker in the verification file before opening the PR.

- [x] **Step 6: Confirm this slice starts outside Swift source scope**

Run:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Expected: no output. If output appears, stop and inspect; this slice must not include Swift source, tests, or package metadata.

## Task 2: Tighten Detector Runtime Classification

**Files:**
- Modify: `.github/scripts/detect-docs-only-pr.sh`

- [x] **Step 1: Add failing runtime self-test coverage**

Patch `.github/scripts/detect-docs-only-pr.sh` by adding this helper after `assert_equal()` and before `assert_command_success()`:

```bash
assert_contains() {
  local needle="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" != *"$needle"* ]]; then
    echo "self_test=fail label=$label expected_contains=$needle actual=$actual"
    exit 1
  fi
}

assert_runtime_classification() {
  local script_path="$1"
  local label="$2"
  local base_sha="$3"
  local head_sha="$4"
  local expected_status="$5"
  local expected_output="$6"
  local expected_github_output="$7"
  local output_file output status github_output

  output_file="$(mktemp "${TMPDIR:-/tmp}/docs-only-runtime-output.XXXXXX")"
  output="$(bash "$script_path" --base "$base_sha" --head "$head_sha" --github-output "$output_file" 2>&1)"
  status=$?
  github_output="$(cat "$output_file")"
  rm -f "$output_file"

  assert_equal "$expected_status" "$status" "${label}_status"
  assert_contains "$expected_output" "$output" "${label}_output"
  assert_equal "$expected_github_output" "$github_output" "${label}_github_output"
}
```

Then add this block inside `run_self_test()` after the existing `classify_empty_count` assertion and before the GitHub output self-test:

```bash
  local script_path runtime_repo base_sha docs_head mixed_head workflow_head helper_head missing_sha
  case "${BASH_SOURCE[0]}" in
    /*) script_path="${BASH_SOURCE[0]}" ;;
    *) script_path="$(pwd)/${BASH_SOURCE[0]}" ;;
  esac

  runtime_repo="$(mktemp -d "${TMPDIR:-/tmp}/docs-only-runtime.XXXXXX")"
  (
    cd "$runtime_repo" || exit 1
    git init -q
    git config user.name "Docs Only Test"
    git config user.email "docs-only@example.invalid"

    mkdir -p docs
    printf 'base\n' > docs/guide.md
    git add docs/guide.md
    git commit -q -m base
    base_sha="$(git rev-parse HEAD)"

    git checkout -q -B docs-only "$base_sha"
    printf 'docs\n' >> docs/guide.md
    git add docs/guide.md
    git commit -q -m docs-only
    docs_head="$(git rev-parse HEAD)"

    git checkout -q -B mixed-source "$base_sha"
    printf 'docs\n' >> docs/guide.md
    mkdir -p Sources/TextEngineCore
    printf 'source\n' > Sources/TextEngineCore/Example.swift
    git add docs/guide.md Sources/TextEngineCore/Example.swift
    git commit -q -m mixed-source
    mixed_head="$(git rev-parse HEAD)"

    git checkout -q -B workflow-change "$base_sha"
    mkdir -p .github/workflows
    printf 'name: Swift CI\n' > .github/workflows/swift-ci.yml
    git add .github/workflows/swift-ci.yml
    git commit -q -m workflow-change
    workflow_head="$(git rev-parse HEAD)"

    git checkout -q -B helper-change "$base_sha"
    mkdir -p .github/scripts
    printf '#!/usr/bin/env bash\n' > .github/scripts/detect-docs-only-pr.sh
    git add .github/scripts/detect-docs-only-pr.sh
    git commit -q -m helper-change
    helper_head="$(git rev-parse HEAD)"

    missing_sha="0000000000000000000000000000000000000000"

    assert_runtime_classification "$script_path" "runtime_docs_only" "$base_sha" "$docs_head" "0" "docs_only_pr=true" "docs_only_pr=true"
    assert_runtime_classification "$script_path" "runtime_mixed_source" "$base_sha" "$mixed_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_workflow_change" "$base_sha" "$workflow_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_helper_change" "$base_sha" "$helper_head" "0" "docs_only_pr=false" "docs_only_pr=false"
    assert_runtime_classification "$script_path" "runtime_missing_base" "$missing_sha" "$docs_head" "2" "reason=base_commit_unavailable" ""
    assert_runtime_classification "$script_path" "runtime_empty_diff" "$base_sha" "$base_sha" "2" "reason=empty_diff" ""
  )
  rm -rf "$runtime_repo"
```

- [x] **Step 2: Run the detector self-test and verify it fails red**

Run:

```bash
set +e
./.github/scripts/detect-docs-only-pr.sh --self-test > /private/tmp/slice-19-detector-red.out 2>&1
status=$?
set -e
cat /private/tmp/slice-19-detector-red.out
echo "status=${status}"
test "$status" -ne 0
rg -n "runtime_empty_diff_status expected=2 actual=0" /private/tmp/slice-19-detector-red.out
```

Expected: command exits nonzero because the current runtime path still treats an empty real diff as docs-only.

- [x] **Step 3: Fail closed on empty runtime diffs**

Patch `.github/scripts/detect-docs-only-pr.sh` immediately after the existing `git diff --name-only` block:

```bash
if [[ -z "$changed_paths" ]]; then
  fail "empty_diff"
fi
```

The final runtime block at the bottom of the file must read:

```bash
git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null || fail "base_commit_unavailable"
git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null || fail "head_commit_unavailable"

if ! changed_paths="$(git diff --name-only "${BASE_SHA}...${HEAD_SHA}" 2>/dev/null)"; then
  fail "diff_unavailable"
fi

if [[ -z "$changed_paths" ]]; then
  fail "empty_diff"
fi

classify_paths <<< "$changed_paths"
emit_classification
```

- [x] **Step 4: Verify detector self-test and syntax**

Run:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test
bash -n .github/scripts/detect-docs-only-pr.sh
```

Expected: self-test prints exactly:

```text
self_test=pass
```

`bash -n` exits `0` with no output.

- [x] **Step 5: Re-run explicit empty runtime check**

Run:

```bash
base_sha="$(git rev-parse HEAD)"
set +e
./.github/scripts/detect-docs-only-pr.sh --base "$base_sha" --head "$base_sha" > /private/tmp/slice-19-empty-runtime-after.out 2>&1
status=$?
set -e
cat /private/tmp/slice-19-empty-runtime-after.out
echo "status=${status}"
test "$status" -eq 2
rg -n "result=infrastructure_failure reason=empty_diff docs_only_pr=false" /private/tmp/slice-19-empty-runtime-after.out
```

Expected: status is `2`, and output fails closed with `reason=empty_diff`.

- [x] **Step 6: Commit detector change**

Run:

```bash
git add .github/scripts/detect-docs-only-pr.sh
git commit -m "ci: fail closed on empty docs-only diffs"
```

Expected: commit succeeds.

## Task 3: Run Docs-Only Detection From Trusted Base Worktrees

**Files:**
- Modify: `.github/workflows/swift-ci.yml`
- Create temporary: `/private/tmp/slice-19-workflow-shape-check.sh`

- [x] **Step 1: Create the workflow-shape checker**

Create `/private/tmp/slice-19-workflow-shape-check.sh` with this complete content:

```bash
#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/swift-ci.yml"

if awk '
  /^  pull_request:/ { in_pr = 1; next }
  /^  push:/ { in_pr = 0 }
  in_pr && /paths-ignore:/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$workflow"; then
  echo "pull_request_paths_ignore=present"
  exit 1
fi
echo "pull_request_paths_ignore=absent"

if awk '
  /^  push:/ { in_push = 1; next }
  /^permissions:/ { in_push = 0 }
  in_push && /paths-ignore:/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$workflow"; then
  echo "push_paths_ignore=present"
else
  echo "push_paths_ignore=absent"
  exit 1
fi

for job_name in \
  "Host tests and benchmark gate" \
  "iOS cross-target compile" \
  "WASM cross-target observation"
do
  rg -q "name: ${job_name}" "$workflow"
done
echo "required_job_names=present"

worktree_count="$(rg -c 'git worktree add --detach "\$trusted_ci_dir" "\$BASE_SHA"' "$workflow" || true)"
if [[ "$worktree_count" != "3" ]]; then
  echo "trusted_worktree_add_count=${worktree_count}"
  exit 1
fi
echo "trusted_worktree_add_count=3"

detector_path_count="$(rg -c 'trusted_detector="\$\{trusted_ci_dir\}/\.github/scripts/detect-docs-only-pr\.sh"' "$workflow" || true)"
if [[ "$detector_path_count" != "3" ]]; then
  echo "trusted_detector_path_count=${detector_path_count}"
  exit 1
fi
echo "trusted_detector_path_count=3"

trusted_invocation_count="$(rg -c 'bash "\$trusted_detector" --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"' "$workflow" || true)"
if [[ "$trusted_invocation_count" != "3" ]]; then
  echo "trusted_detector_invocation_count=${trusted_invocation_count}"
  exit 1
fi
echo "trusted_detector_invocation_count=3"

if rg -n '^\s+\./\.github/scripts/detect-docs-only-pr\.sh --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"' "$workflow"; then
  echo "pr_workspace_detector_invocation=present"
  exit 1
fi
echo "pr_workspace_detector_invocation=absent"

if rg -n 'pull_request_target' "$workflow"; then
  echo "pull_request_target=present"
  exit 1
fi
echo "pull_request_target=absent"

echo "workflow_shape=pass"
```

Then run:

```bash
chmod +x /private/tmp/slice-19-workflow-shape-check.sh
```

Expected: command exits `0`.

- [x] **Step 2: Run the workflow-shape checker and verify it fails red**

Run:

```bash
set +e
/private/tmp/slice-19-workflow-shape-check.sh > /private/tmp/slice-19-workflow-shape-red.out 2>&1
status=$?
set -e
cat /private/tmp/slice-19-workflow-shape-red.out
echo "status=${status}"
test "$status" -ne 0
rg -n "trusted_worktree_add_count=0" /private/tmp/slice-19-workflow-shape-red.out
```

Expected: command exits nonzero because the current workflow has no trusted base worktree creation.

- [x] **Step 3: Replace each `Detect PR change scope` step**

In `.github/workflows/swift-ci.yml`, replace the complete `Detect PR change scope` step in all three jobs:

```text
host-tests-and-benchmark-gate
ios-cross-target-compile
wasm-cross-target-observation
```

Use this exact YAML step for each replacement:

```yaml
      - name: Detect PR change scope
        id: change-scope
        shell: bash
        env:
          EVENT_NAME: ${{ github.event_name }}
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          set -euo pipefail
          if [[ "$EVENT_NAME" != "pull_request" ]]; then
            echo "docs_only_pr=false" >> "$GITHUB_OUTPUT"
            echo "mode=docs_only_pr event=$EVENT_NAME result=not_pull_request docs_only_pr=false"
            exit 0
          fi

          fail_scope() {
            echo "mode=docs_only_pr result=infrastructure_failure reason=$1 docs_only_pr=false"
            exit 2
          }

          [[ -n "${BASE_SHA}" ]] || fail_scope "missing_base_sha"
          [[ -n "${HEAD_SHA}" ]] || fail_scope "missing_head_sha"
          [[ -n "${RUNNER_TEMP:-}" ]] || fail_scope "missing_runner_temp"

          git config --global --add safe.directory "$GITHUB_WORKSPACE"
          git cat-file -e "${BASE_SHA}^{commit}" || fail_scope "base_commit_unavailable"
          git cat-file -e "${HEAD_SHA}^{commit}" || fail_scope "head_commit_unavailable"

          trusted_ci_dir="${RUNNER_TEMP}/trusted-ci"
          case "${trusted_ci_dir}/" in
            "${GITHUB_WORKSPACE}/"*) fail_scope "trusted_worktree_inside_workspace" ;;
          esac

          git worktree remove --force "$trusted_ci_dir" 2>/dev/null || rm -rf "$trusted_ci_dir"
          git worktree add --detach "$trusted_ci_dir" "$BASE_SHA"

          trusted_detector="${trusted_ci_dir}/.github/scripts/detect-docs-only-pr.sh"
          [[ -f "$trusted_detector" ]] || fail_scope "trusted_detector_unavailable"

          bash "$trusted_detector" --base "$BASE_SHA" --head "$HEAD_SHA" --github-output "$GITHUB_OUTPUT"
```

Do not change the job names, `Complete docs-only PR` steps, heavy-step `if:` guards, `push.paths-ignore`, or the `pull_request:` trigger shape.

- [x] **Step 4: Verify workflow shape is green**

Run:

```bash
/private/tmp/slice-19-workflow-shape-check.sh
git diff --check .github/workflows/swift-ci.yml
```

Expected: shape checker prints:

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

`git diff --check` exits `0` with no output.

- [x] **Step 5: Verify bootstrap compatibility with the Slice 18 helper CLI**

Run:

```bash
rg -n 'bash "\$trusted_detector" --base "\$BASE_SHA" --head "\$HEAD_SHA" --github-output "\$GITHUB_OUTPUT"' .github/workflows/swift-ci.yml
set +e
rg -n -- '--trusted|--worktree|--base-worktree' .github/workflows/swift-ci.yml > /private/tmp/slice-19-new-helper-flags.out 2>&1
status=$?
set -e
cat /private/tmp/slice-19-new-helper-flags.out
echo "status=${status}"
test "$status" -eq 1
```

Expected: the trusted detector is invoked three times with the existing `--base/--head/--github-output` CLI, and no new helper flags are required. This matters because the Slice 19 PR will classify itself using the helper from the current `main` base commit.

- [x] **Step 6: Commit workflow change**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: run docs-only detector from trusted base"
```

Expected: commit succeeds.

## Task 4: Update Durable Repo Guidance

**Files:**
- Modify: `AGENTS.md`

- [x] **Step 1: Confirm AGENTS lacks the trusted-base boundary**

Run:

```bash
set +e
rg -n "trusted-ci|trusted worktree|base commit.*detect-docs-only|empty runtime diffs|PR-owned workflow/helper changes" AGENTS.md > /private/tmp/slice-19-agents-before.out 2>&1
status=$?
set -e
cat /private/tmp/slice-19-agents-before.out
echo "status=${status}"
test "$status" -eq 1
```

Expected: no matches. This is the red documentation proof for this task.

- [x] **Step 2: Replace the docs-only PR paragraph**

In `AGENTS.md`, replace the current paragraph beginning with:

```text
Docs-only PRs still start Swift CI so those required job contexts are emitted,
```

and ending with:

```text
because PR required checks are the merge gate.
```

with this text:

```markdown
Docs-only PRs still start Swift CI so those required job contexts are emitted,
but each required job materializes the PR base commit into
`$RUNNER_TEMP/trusted-ci` with `git worktree` and executes
`.github/scripts/detect-docs-only-pr.sh` from that trusted base tree. The
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

Leave the required-check policy paragraph and bypass caveat in place.

- [x] **Step 3: Verify AGENTS records the new trust boundary**

Run:

```bash
rg -n "trusted-ci|trusted base tree|BASE_SHA\\.\\.\\.HEAD_SHA|empty runtime diffs|\\.github/workflows/\\*\\*|\\.github/scripts/\\*\\*" AGENTS.md
```

Expected: command exits `0` and prints matches for all listed trust-boundary facts.

- [x] **Step 4: Commit AGENTS update**

Run:

```bash
git add AGENTS.md
git commit -m "docs: document trusted docs-only gate"
```

Expected: commit succeeds.

## Task 5: Record Local Verification Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md`
- Read temporary: `/private/tmp/slice-19-*`

- [x] **Step 1: Capture final local checks**

Run:

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

Expected:

```text
self_test=pass
workflow_shape=pass
foundation_status=1
source_scope_status=0
```

`bash -n`, `git diff --check`, and the source-scope diff produce no output.

- [x] **Step 2: Capture ruleset readback**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-19-ruleset-final-local.json
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

Expected: `jq -e` exits `0`. If the command cannot run because credentials are unavailable, record the exact failure output in the verification file and refresh it before final merge from an authenticated environment.

- [x] **Step 3: Create the verification record**

Create `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md` with these sections and include the exact command, exit status, and relevant output captured in `/private/tmp/slice-19-*`:

```markdown
# Trusted Docs-Only Gate Verification

Date: 2026-06-16

## Summary

Slice 19 makes the Swift CI docs-only shortcut run the classifier from the PR
base commit trusted worktree instead of PR-owned helper code. It also tightens
the detector so empty real runtime diffs fail closed.

No Swift source, tests, benchmark code, benchmark budgets, package metadata,
required job contexts, ruleset requirements, or bypass actors changed.

## Local State

## Detector Checks

## Workflow Shape Checks

## Documentation Checks

## Ruleset Readback

## Scope Proof

## Hosted PR-Head Heavy Proof

## Post-Merge Push Proof

## Hosted Docs-Only PR Proof
```

For sections whose hosted evidence is not available yet, write the current blocking state precisely, for example:

```markdown
Hosted PR-head proof is not available before the branch is pushed and the PR run completes.
```

Do not leave an empty section.

- [x] **Step 4: Verify the local verification record proof points**

Run:

```bash
rg -n "trusted worktree|trusted base|empty real runtime diffs|self_test=pass|workflow_shape=pass|Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation|No Swift source" docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md
```

Expected: command exits `0` and prints matches for detector behavior, workflow shape, required contexts, and scope proof.

- [x] **Step 5: Commit local verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md
git commit -m "docs: record trusted docs-only gate verification"
```

Expected: commit succeeds.

## Task 6: Record PR-Head Heavy Hosted Proof

**Files:**
- Modify: `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md`

- [x] **Step 1: Push the Slice 19 branch and open the PR**

Run:

```bash
git push -u origin slice-19-trusted-docs-only-gate
gh pr create \
  --title "Run docs-only gate from trusted base" \
  --body-file docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md
```

Expected: push succeeds and the PR opens against `main`. The PR should trigger `Swift CI` because the diff includes workflow/helper changes.

- [x] **Step 2: Locate the PR-head Swift CI run**

Run:

```bash
gh pr view --json number,url,headRefName,headRefOid,statusCheckRollup > /private/tmp/slice-19-pr.json
cat /private/tmp/slice-19-pr.json
head_sha="$(jq -r '.headRefOid' /private/tmp/slice-19-pr.json)"
gh run list --workflow "Swift CI" --branch slice-19-trusted-docs-only-gate --limit 10 --json databaseId,headSha,status,conclusion,url > /private/tmp/slice-19-pr-runs.json
cat /private/tmp/slice-19-pr-runs.json
jq -r --arg sha "$head_sha" '.[] | select(.headSha == $sha) | .databaseId' /private/tmp/slice-19-pr-runs.json | sed -n '1p' > /private/tmp/slice-19-pr-run-id.txt
cat /private/tmp/slice-19-pr-run-id.txt
test -s /private/tmp/slice-19-pr-run-id.txt
```

Expected: a non-empty run id is written to `/private/tmp/slice-19-pr-run-id.txt`.

- [x] **Step 3: Verify all required jobs succeeded and ran the heavy path**

Run after the run completes:

```bash
run_id="$(cat /private/tmp/slice-19-pr-run-id.txt)"
gh run view "$run_id" --json jobs --jq '[.jobs[] | {name,status,conclusion}]' > /private/tmp/slice-19-pr-jobs.json
cat /private/tmp/slice-19-pr-jobs.json
jq -e '
  ([.[].name] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and all(.[]; .status == "completed" and .conclusion == "success")
' /private/tmp/slice-19-pr-jobs.json
gh run view "$run_id" --log > /private/tmp/slice-19-pr-run.log
rg -n "Run host tests|Run synthetic benchmark gate|Compile TextEngineCore for iOS targets|Observe TextEngineCore for WASM targets" /private/tmp/slice-19-pr-run.log
set +e
rg -n "mode=docs_only_pr job=.*result=success" /private/tmp/slice-19-pr-run.log > /private/tmp/slice-19-pr-docs-only-success-lines.txt
docs_only_status=$?
set -e
cat /private/tmp/slice-19-pr-docs-only-success-lines.txt
echo "docs_only_status=${docs_only_status}"
test "$docs_only_status" -eq 1
```

Expected: all three required jobs are successful, heavy Swift/test/compile log lines are present, and no docs-only success line is present.

- [x] **Step 4: Append PR-head hosted proof to the verification record**

Generate the hosted evidence snippet:

```bash
{
  echo "run_id=$(cat /private/tmp/slice-19-pr-run-id.txt)"
  echo "pr=$(jq -r '.number' /private/tmp/slice-19-pr.json)"
  echo "head_sha=$(jq -r '.headRefOid' /private/tmp/slice-19-pr.json)"
  printf 'jobs='
  tr -d '\n' < /private/tmp/slice-19-pr-jobs.json
  printf '\n'
  printf 'heavy_path_lines='
  rg "Run host tests|Run synthetic benchmark gate|Compile TextEngineCore for iOS targets|Observe TextEngineCore for WASM targets" /private/tmp/slice-19-pr-run.log | tr '\n' ';'
  printf '\n'
} > /private/tmp/slice-19-pr-evidence-snippet.txt
cat /private/tmp/slice-19-pr-evidence-snippet.txt
```

Expected: snippet contains `run_id=`, `pr=`, `head_sha=`, `jobs=`, and `heavy_path_lines=` with non-empty values.

Update `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md` section `Hosted PR-Head Heavy Proof` with this shape, copying the generated snippet exactly:

````markdown
Command:

```bash
run_id="$(cat /private/tmp/slice-19-pr-run-id.txt)"
gh run view "$run_id" --json jobs --jq '[.jobs[] | {name,status,conclusion}]'
gh run view "$run_id" --log
```

Exit status: `0`.

Evidence:

Use a `text` fenced block containing the exact lines printed by
`cat /private/tmp/slice-19-pr-evidence-snippet.txt`.

The PR-head run is intentionally non-doc and must not take the docs-only shortcut.
````

Do not remove the local evidence already recorded.

- [x] **Step 5: Commit hosted PR evidence**

Run:

```bash
git add docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md
git commit -m "docs: record trusted docs-only gate PR evidence"
git push
```

Expected: commit and push succeed. The pushed docs commit retriggers Swift CI because the PR diff still contains workflow/helper changes; wait for the new head run and repeat Steps 2 through 4 if the verification record must cite the latest PR-head SHA before merge.

## Task 7: Record Post-Merge And Docs-Only Hosted Proof

**Files:**
- Modify: `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md`
- Create: `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate-docs-only-proof.md`

- [x] **Step 1: Merge Slice 19 after review and required checks**

Run only after the PR is approved and all required checks are green:

```bash
gh pr merge --merge --delete-branch
git checkout main
git pull --ff-only
```

Expected: merge succeeds with a merge commit on `main`, and local `main` fast-forwards to it.

- [x] **Step 2: Record post-merge push run**

Run:

```bash
merge_sha="$(git rev-parse HEAD)"
gh run list --workflow "Swift CI" --branch main --limit 10 --json databaseId,headSha,status,conclusion,url > /private/tmp/slice-19-main-runs.json
cat /private/tmp/slice-19-main-runs.json
jq -r --arg sha "$merge_sha" '.[] | select(.headSha == $sha) | .databaseId' /private/tmp/slice-19-main-runs.json | sed -n '1p' > /private/tmp/slice-19-main-run-id.txt
cat /private/tmp/slice-19-main-run-id.txt
test -s /private/tmp/slice-19-main-run-id.txt
main_run_id="$(cat /private/tmp/slice-19-main-run-id.txt)"
gh run view "$main_run_id" --json jobs --jq '[.jobs[] | {name,status,conclusion}]' > /private/tmp/slice-19-main-jobs.json
cat /private/tmp/slice-19-main-jobs.json
jq -e '
  ([.[].name] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and all(.[]; .status == "completed" and .conclusion == "success")
' /private/tmp/slice-19-main-jobs.json
```

Expected: post-merge push run for the Slice 19 merge commit exists and all three required jobs succeeded.

- [x] **Step 3: Record final ruleset readback**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-19-ruleset-post-merge.json
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
' /private/tmp/slice-19-ruleset-post-merge.json
```

Expected: `jq -e` exits `0`; required status contexts are unchanged.

- [x] **Step 4: Create a docs-only proof branch**

Run:

```bash
git checkout -b slice-19-docs-only-proof
```

Create `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate-docs-only-proof.md` with:

```markdown
# Trusted Docs-Only Gate Docs-Only Proof

Date: 2026-06-16

This docs-only PR proves that, after Slice 19 is present on `main`, the trusted
base detector path emits all three required Swift CI contexts through the
lightweight docs-only route.

Initial proof commit changes only this Markdown file.
```

Then run:

```bash
git add docs/superpowers/verification/2026-06-16-trusted-docs-only-gate-docs-only-proof.md
git commit -m "docs: add trusted docs-only gate proof"
git diff --name-only main...HEAD
```

Expected: the diff contains only:

```text
docs/superpowers/verification/2026-06-16-trusted-docs-only-gate-docs-only-proof.md
```

- [x] **Step 5: Open the docs-only proof PR**

Run:

```bash
git push -u origin slice-19-docs-only-proof
gh pr create \
  --title "Prove trusted docs-only Swift CI path" \
  --body "Docs-only proof PR for Slice 19 trusted docs-only gate verification."
```

Expected: PR opens against `main` and starts `Swift CI`.

- [x] **Step 6: Verify the docs-only proof PR uses the lightweight path**

Run after the proof PR run completes:

```bash
gh pr view --json number,url,headRefName,headRefOid > /private/tmp/slice-19-docs-proof-pr.json
cat /private/tmp/slice-19-docs-proof-pr.json
proof_head_sha="$(jq -r '.headRefOid' /private/tmp/slice-19-docs-proof-pr.json)"
gh run list --workflow "Swift CI" --branch slice-19-docs-only-proof --limit 10 --json databaseId,headSha,status,conclusion,url > /private/tmp/slice-19-docs-proof-runs.json
cat /private/tmp/slice-19-docs-proof-runs.json
jq -r --arg sha "$proof_head_sha" '.[] | select(.headSha == $sha) | .databaseId' /private/tmp/slice-19-docs-proof-runs.json | sed -n '1p' > /private/tmp/slice-19-docs-proof-run-id.txt
cat /private/tmp/slice-19-docs-proof-run-id.txt
test -s /private/tmp/slice-19-docs-proof-run-id.txt
proof_run_id="$(cat /private/tmp/slice-19-docs-proof-run-id.txt)"
gh run view "$proof_run_id" --json jobs --jq '[.jobs[] | {name,status,conclusion}]' > /private/tmp/slice-19-docs-proof-jobs.json
cat /private/tmp/slice-19-docs-proof-jobs.json
jq -e '
  ([.[].name] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and all(.[]; .status == "completed" and .conclusion == "success")
' /private/tmp/slice-19-docs-proof-jobs.json
gh run view "$proof_run_id" --log > /private/tmp/slice-19-docs-proof-run.log
rg -n "mode=docs_only_pr job=host-tests-and-benchmark-gate result=success|mode=docs_only_pr job=ios-cross-target-compile result=success|mode=docs_only_pr job=wasm-cross-target-observation result=success" /private/tmp/slice-19-docs-proof-run.log
set +e
rg -n "Run host tests|Run synthetic benchmark gate|Compile TextEngineCore for iOS targets|Observe TextEngineCore for WASM targets" /private/tmp/slice-19-docs-proof-run.log > /private/tmp/slice-19-docs-proof-heavy-lines.txt
heavy_status=$?
set -e
cat /private/tmp/slice-19-docs-proof-heavy-lines.txt
echo "heavy_status=${heavy_status}"
test "$heavy_status" -eq 1
```

Expected: all three required jobs succeed, all three docs-only success lines are present, and heavy Swift/test/compile log lines are absent.

- [x] **Step 7: Append post-merge and docs-only proof to verification**

Update `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md` with the actual post-merge run id, ruleset readback summary, docs-only proof PR number, docs-only proof run id, job JSON, and relevant log lines captured under `/private/tmp/slice-19-*`.

Then run:

```bash
git checkout main
git pull --ff-only
git checkout -b slice-19-verification-followup
git add docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md
git commit -m "docs: record trusted docs-only gate hosted proof"
git diff --name-only main...HEAD
```

Expected: follow-up diff contains only:

```text
docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md
```

Open this as a docs-only PR if the Slice 19 verification record on `main` must contain the post-merge proof. Its own Swift CI run should also take the trusted docs-only lightweight path.

- [x] **Step 8: Final local sanity check**

Run on the branch being handed off:

```bash
git status --short --branch
git diff --check
rg -n "Foundation" Sources/TextEngineCore
```

Expected: working tree is clean except any intentionally staged verification follow-up, `git diff --check` exits `0`, and the Foundation scan exits `1` with no output.
