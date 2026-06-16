# Swift CI Required Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Require the current Swift CI jobs for updates to `main` while keeping fully docs-only PRs mergeable without bypass.

**Architecture:** This is a policy/workflow/docs slice. Add a small self-tested Bash helper that classifies the full PR diff as docs-only or not, wire all three required GitHub Actions jobs through that helper, then update the existing `Main` ruleset in place with strict required status checks for the three Swift CI job contexts. Swift source, tests, benchmark code, and `Package.swift` stay unchanged.

**Tech Stack:** GitHub Actions, Bash, Git, GitHub CLI, GitHub REST repository rulesets, `jq`, Markdown.

---

## File Structure

- Create `.github/scripts/detect-docs-only-pr.sh`: pure Bash helper with `--self-test`; classifies a PR diff using `git diff --name-only BASE...HEAD`, emits stable `mode=docs_only_pr` lines, writes `docs_only_pr=true|false` to `$GITHUB_OUTPUT` when requested, and fails closed on missing commits or diff failure.
- Modify `.github/workflows/swift-ci.yml`: remove `pull_request.paths-ignore`, preserve `push` docs-only `paths-ignore`, run the detector in each of the three jobs, skip heavy work only when `docs_only_pr=true`, and emit a lightweight success line for docs-only PRs.
- Modify `AGENTS.md`: replace stale private-repo/no-required-check wording with current public repo, active `Main` ruleset, required Swift CI contexts, docs-only PR lightweight path, push docs-only skip, and bypass caveat.
- Create `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`: record local checks, GitHub API preflight, ruleset mutation, final readback, and explicit non-Swift-source scope proof.
- Temporary files under `/private/tmp/slice-18-*`: capture GitHub API readbacks, generated ruleset payload, and command outputs during implementation.

No changes are planned for `Sources/**`, `Tests/**`, `Package.swift`, benchmark budgets, benchmark modes, or cross-target compile semantics.

## Scope Check

This plan implements the approved Slice 18 spec:

```text
docs/superpowers/specs/2026-06-16-swift-ci-required-checks-design.md
```

The slice covers one operational subsystem: repository-required Swift CI checks for `main`, plus the workflow correction needed to keep fully docs-only PRs from hanging on pending required checks.

It does not change `TextEngineCore`, `TextEngineReferenceProviders`, `ViewportBenchmarks`, tests, package metadata, benchmark budgets, WASM target-level blocking status, bypass actors, human-review policy, merge queue, signed commits, legacy branch protection, or destructive merge-rejection behavior.

## Task 1: Preflight Local And Live State

**Files:**
- Read: `docs/superpowers/specs/2026-06-16-swift-ci-required-checks-design.md`
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Write temporary command output under `/private/tmp/slice-18-*`

- [x] **Step 1: Confirm branch and local state**

Run:

```bash
git status --short --branch
git branch --show-current
```

Expected: branch is `slice-18-swift-ci-required-checks`. Existing user changes are acceptable only if they are unrelated to the files listed in this plan. If `.github/workflows/swift-ci.yml`, `AGENTS.md`, `.github/scripts/**`, or `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md` are already modified by someone else, inspect before continuing and do not overwrite blindly.

- [x] **Step 2: Confirm the approved spec is present**

Run:

```bash
sed -n '1,380p' docs/superpowers/specs/2026-06-16-swift-ci-required-checks-design.md
```

Expected: command exits `0` and output includes:

```text
# Swift CI Required Checks Design
Status
Approved direction
required_status_checks
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
remove `paths-ignore` from the `pull_request` trigger
```

- [x] **Step 3: Confirm current workflow still has the docs-only PR path-filter problem**

Run:

```bash
sed -n '1,170p' .github/workflows/swift-ci.yml
rg -n "pull_request:|paths-ignore|Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation" .github/workflows/swift-ci.yml
```

Expected: `pull_request.paths-ignore` is present, `push.paths-ignore` is present, and the three job names are exactly:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

- [x] **Step 4: Confirm stale AGENTS wording before the docs update**

Run:

```bash
rg -n "Docs-only changes skip Swift CI|private repo without branch protection|required checks|paths-ignore" AGENTS.md
```

Expected: output includes the current stale caveat that the repo is private and without branch protection / required checks. This is the failing documentation proof for Task 4.

- [x] **Step 5: Confirm local tools for the policy mutation path**

Run:

```bash
gh --version
jq --version
gh auth status
```

Expected: `gh --version` and `jq --version` exit `0`. `gh auth status` exits `0` for `github.com`. If authentication or admin access is unavailable, stop before Task 5 and record the blocker in the verification file.

- [x] **Step 6: Capture repository identity and permissions**

Run:

```bash
gh api repos/maldrakar/swift-text-engine --jq '{full_name,visibility,default_branch,permissions}' > /private/tmp/slice-18-repo.json
cat /private/tmp/slice-18-repo.json
jq -e '.full_name == "maldrakar/swift-text-engine" and .visibility == "public" and .default_branch == "main" and .permissions.admin == true' /private/tmp/slice-18-repo.json
```

Expected: `jq -e` exits `0`. If `.permissions.admin` is not `true`, stop before mutation and record the exact output.

- [x] **Step 7: Capture active Swift CI workflow**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/actions/workflows --jq '.workflows[] | select(.name=="Swift CI") | {id,name,state,path}' > /private/tmp/slice-18-workflow.json
cat /private/tmp/slice-18-workflow.json
jq -e '.name == "Swift CI" and .state == "active" and .path == ".github/workflows/swift-ci.yml"' /private/tmp/slice-18-workflow.json
```

Expected: `jq -e` exits `0`.

- [x] **Step 8: Capture recent successful Swift CI job contexts**

Run:

```bash
gh run list --workflow "Swift CI" --branch main --limit 1 --json databaseId,headSha,conclusion,status,url > /private/tmp/slice-18-latest-run.json
cat /private/tmp/slice-18-latest-run.json
RUN_ID="$(jq -r '.[0].databaseId' /private/tmp/slice-18-latest-run.json)"
test -n "$RUN_ID"
gh run view "$RUN_ID" --json jobs --jq '[.jobs[] | {name,conclusion,status}]' > /private/tmp/slice-18-latest-run-jobs.json
cat /private/tmp/slice-18-latest-run-jobs.json
jq -e '
  ([.[].name] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and all(.[]; .status == "completed" and .conclusion == "success")
' /private/tmp/slice-18-latest-run-jobs.json
```

Expected: `jq -e` exits `0`. If the latest run is not successful or the job names differ, stop before mutation and record the observed job names.

- [x] **Step 9: Capture current ruleset and legacy branch-protection context**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-18-ruleset-before.json
cat /private/tmp/slice-18-ruleset-before.json
jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and (.conditions.ref_name.include == ["~DEFAULT_BRANCH"])
  and ([.rules[].type] | index("pull_request") != null)
  and ([.rules[].type] | index("required_status_checks") == null)
' /private/tmp/slice-18-ruleset-before.json
set +e
gh api repos/maldrakar/swift-text-engine/branches/main/protection > /private/tmp/slice-18-legacy-branch-protection.json 2> /private/tmp/slice-18-legacy-branch-protection.err
echo "legacy_branch_protection_status=$?" > /private/tmp/slice-18-legacy-branch-protection.status
set -e
cat /private/tmp/slice-18-legacy-branch-protection.status
cat /private/tmp/slice-18-legacy-branch-protection.err
```

Expected: ruleset validation exits `0`. Legacy branch protection may return `404`; record the status and do not modify legacy branch protection in this slice.

## Task 2: Add Docs-Only PR Detector

**Files:**
- Create: `.github/scripts/detect-docs-only-pr.sh`

- [x] **Step 1: Write the detector with self-tests**

Create `.github/scripts/detect-docs-only-pr.sh` with this complete content:

```bash
#!/usr/bin/env bash
set -uo pipefail

BASE_SHA=""
HEAD_SHA=""
GITHUB_OUTPUT_FILE=""
DOCS_ONLY_RESULT=""
DOCS_ONLY_FILE_COUNT="0"
DOCS_ONLY_NON_DOC_COUNT="0"

usage() {
  cat <<'EOF'
Usage:
  detect-docs-only-pr.sh --base SHA --head SHA [--github-output FILE]
  detect-docs-only-pr.sh --self-test
EOF
}

fail() {
  echo "mode=docs_only_pr result=infrastructure_failure reason=$1 docs_only_pr=false"
  exit 2
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "self_test=fail label=$label expected=$expected actual=$actual"
    exit 1
  fi
}

assert_command_success() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "self_test=fail label=$label expected=success actual=failure"
    exit 1
  fi
}

assert_command_failure() {
  local label="$1"
  shift
  if "$@"; then
    echo "self_test=fail label=$label expected=failure actual=success"
    exit 1
  fi
}

is_docs_only_path() {
  local path="$1"
  case "$path" in
    docs/*|*.md) return 0 ;;
    *) return 1 ;;
  esac
}

classify_paths() {
  local path count=0 non_doc_count=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    count=$((count + 1))
    if ! is_docs_only_path "$path"; then
      non_doc_count=$((non_doc_count + 1))
    fi
  done

  DOCS_ONLY_FILE_COUNT="$count"
  DOCS_ONLY_NON_DOC_COUNT="$non_doc_count"
  if [[ "$non_doc_count" -eq 0 ]]; then
    DOCS_ONLY_RESULT="docs_only"
  else
    DOCS_ONLY_RESULT="not_docs_only"
  fi
}

write_github_output() {
  local docs_only_flag="$1"
  if [[ -n "$GITHUB_OUTPUT_FILE" ]]; then
    printf 'docs_only_pr=%s\n' "$docs_only_flag" >> "$GITHUB_OUTPUT_FILE"
  fi
}

emit_classification() {
  local docs_only_flag="false"
  if [[ "$DOCS_ONLY_RESULT" == "docs_only" ]]; then
    docs_only_flag="true"
  fi
  write_github_output "$docs_only_flag"
  echo "mode=docs_only_pr result=$DOCS_ONLY_RESULT docs_only_pr=$docs_only_flag file_count=$DOCS_ONLY_FILE_COUNT non_doc_count=$DOCS_ONLY_NON_DOC_COUNT"
}

run_self_test() {
  assert_command_success "docs_dir_markdown" is_docs_only_path docs/guide.md
  assert_command_success "docs_dir_asset" is_docs_only_path docs/assets/diagram.png
  assert_command_success "root_markdown" is_docs_only_path README.md
  assert_command_success "nested_markdown" is_docs_only_path docs/superpowers/specs/design.md
  assert_command_failure "swift_source" is_docs_only_path Sources/TextEngineCore/ViewportVirtualizer.swift
  assert_command_failure "workflow_yaml" is_docs_only_path .github/workflows/swift-ci.yml
  assert_command_failure "uppercase_markdown_is_not_configured_pattern" is_docs_only_path Notes.MD

  classify_paths <<'EOF'
docs/guide.md
docs/assets/diagram.png
README.md
EOF
  assert_equal "docs_only" "$DOCS_ONLY_RESULT" "classify_docs_only_result"
  assert_equal "3" "$DOCS_ONLY_FILE_COUNT" "classify_docs_only_count"
  assert_equal "0" "$DOCS_ONLY_NON_DOC_COUNT" "classify_docs_only_non_doc_count"

  classify_paths <<'EOF'
docs/guide.md
.github/workflows/swift-ci.yml
EOF
  assert_equal "not_docs_only" "$DOCS_ONLY_RESULT" "classify_mixed_result"
  assert_equal "2" "$DOCS_ONLY_FILE_COUNT" "classify_mixed_count"
  assert_equal "1" "$DOCS_ONLY_NON_DOC_COUNT" "classify_mixed_non_doc_count"

  classify_paths <<'EOF'
EOF
  assert_equal "docs_only" "$DOCS_ONLY_RESULT" "classify_empty_result"
  assert_equal "0" "$DOCS_ONLY_FILE_COUNT" "classify_empty_count"
  assert_equal "0" "$DOCS_ONLY_NON_DOC_COUNT" "classify_empty_non_doc_count"

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/docs-only-output.XXXXXX")"
  GITHUB_OUTPUT_FILE="$output_file"
  DOCS_ONLY_RESULT="docs_only"
  DOCS_ONLY_FILE_COUNT="1"
  DOCS_ONLY_NON_DOC_COUNT="0"
  emit_classification >/dev/null
  assert_equal "docs_only_pr=true" "$(cat "$output_file")" "github_output_true"

  : > "$output_file"
  DOCS_ONLY_RESULT="not_docs_only"
  DOCS_ONLY_FILE_COUNT="1"
  DOCS_ONLY_NON_DOC_COUNT="1"
  emit_classification >/dev/null
  assert_equal "docs_only_pr=false" "$(cat "$output_file")" "github_output_false"

  rm -f "$output_file"
  echo "self_test=pass"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      run_self_test
      exit 0
      ;;
    --base)
      [[ $# -ge 2 ]] || fail "missing_base_argument"
      BASE_SHA="$2"
      shift 2
      ;;
    --head)
      [[ $# -ge 2 ]] || fail "missing_head_argument"
      HEAD_SHA="$2"
      shift 2
      ;;
    --github-output)
      [[ $# -ge 2 ]] || fail "missing_github_output_argument"
      GITHUB_OUTPUT_FILE="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ -n "$BASE_SHA" ]] || fail "missing_base_sha"
[[ -n "$HEAD_SHA" ]] || fail "missing_head_sha"

git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null || fail "base_commit_unavailable"
git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null || fail "head_commit_unavailable"

if ! changed_paths="$(git diff --name-only "${BASE_SHA}...${HEAD_SHA}" 2>/dev/null)"; then
  fail "diff_unavailable"
fi

classify_paths <<< "$changed_paths"
emit_classification
```

- [x] **Step 2: Make the helper executable**

Run:

```bash
chmod +x .github/scripts/detect-docs-only-pr.sh
```

Expected: command exits `0`.

- [x] **Step 3: Run detector self-test**

Run:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test
```

Expected:

```text
self_test=pass
```

- [x] **Step 4: Run shell syntax checks**

Run:

```bash
bash -n .github/scripts/detect-docs-only-pr.sh
bash -n .github/scripts/cross-target-compile.sh
bash -n .github/scripts/realistic-relative-observation.sh
```

Expected: all commands exit `0`.

- [x] **Step 5: Commit the helper**

Run:

```bash
git add .github/scripts/detect-docs-only-pr.sh
git commit -m "ci: add docs-only PR detector"
```

Expected: commit succeeds.

## Task 3: Wire Swift CI Required Jobs Through The Detector

**Files:**
- Modify: `.github/workflows/swift-ci.yml`

- [x] **Step 1: Remove PR path filtering and preserve push docs-only skip**

Patch the trigger at the top of `.github/workflows/swift-ci.yml` from:

```yaml
on:
  pull_request:
    paths-ignore:
      - "docs/**"
      - "**/*.md"
  push:
    branches:
      - main
    paths-ignore:
      - "docs/**"
      - "**/*.md"
```

to:

```yaml
on:
  pull_request:
  push:
    branches:
      - main
    paths-ignore:
      - "docs/**"
      - "**/*.md"
```

- [x] **Step 2: Add the shared detector step after checkout in the host job**

In job `host-tests-and-benchmark-gate`, keep checkout `fetch-depth: 0`, then add this step immediately after checkout:

```yaml
      - name: Detect PR change scope
        id: change-scope
        shell: bash
        env:
          EVENT_NAME: ${{ github.event_name }}
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          if [[ "$EVENT_NAME" != "pull_request" ]]; then
            echo "docs_only_pr=false" >> "$GITHUB_OUTPUT"
            echo "mode=docs_only_pr event=$EVENT_NAME result=not_pull_request docs_only_pr=false"
            exit 0
          fi
          ./.github/scripts/detect-docs-only-pr.sh --base "$BASE_SHA" --head "$HEAD_SHA" --github-output "$GITHUB_OUTPUT"
```

Add this lightweight success step after the detector:

```yaml
      - name: Complete docs-only PR
        if: steps.change-scope.outputs.docs_only_pr == 'true'
        run: echo "mode=docs_only_pr job=host-tests-and-benchmark-gate result=success"
```

- [x] **Step 3: Gate every heavy host step**

Add this condition to every existing host job step after `Complete docs-only PR`:

```yaml
        if: steps.change-scope.outputs.docs_only_pr != 'true'
```

For the existing realistic provider observation step, preserve the PR-only condition by changing it to:

```yaml
        if: github.event_name == 'pull_request' && steps.change-scope.outputs.docs_only_pr != 'true'
```

Expected heavy host steps gated this way:

```text
Show toolchain
Run host tests
Run synthetic benchmark gate
Run variable-height benchmark gate
Observe variable-height mutation benchmark
Run memory shape diagnostic
Run RSS memory observation diagnostic
Observe realistic provider relative performance
```

- [x] **Step 4: Add fetch-depth and detector to the iOS job**

Change the iOS checkout step to:

```yaml
      - name: Check out repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
```

Add the same `Detect PR change scope` step from Step 2 immediately after checkout.

Add this lightweight success step after the detector:

```yaml
      - name: Complete docs-only PR
        if: steps.change-scope.outputs.docs_only_pr == 'true'
        run: echo "mode=docs_only_pr job=ios-cross-target-compile result=success"
```

Add this condition to both existing heavy iOS steps:

```yaml
        if: steps.change-scope.outputs.docs_only_pr != 'true'
```

Expected heavy iOS steps gated this way:

```text
Show toolchain
Compile TextEngineCore for iOS targets
```

- [x] **Step 5: Add fetch-depth and detector to the WASM job**

Change the WASM checkout step to:

```yaml
      - name: Check out repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
```

Add the same `Detect PR change scope` step from Step 2 immediately after checkout.

Add this lightweight success step after the detector:

```yaml
      - name: Complete docs-only PR
        if: steps.change-scope.outputs.docs_only_pr == 'true'
        run: echo "mode=docs_only_pr job=wasm-cross-target-observation result=success"
```

Add this condition to both existing heavy WASM steps:

```yaml
        if: steps.change-scope.outputs.docs_only_pr != 'true'
```

Expected heavy WASM steps gated this way:

```text
Show toolchain
Observe TextEngineCore for WASM targets
```

- [x] **Step 6: Verify workflow diff invariants locally**

Run:

```bash
rg -n "pull_request:|paths-ignore|Detect PR change scope|Complete docs-only PR|docs_only_pr|fetch-depth: 0" .github/workflows/swift-ci.yml
git diff -- .github/workflows/swift-ci.yml
```

Expected:

```text
pull_request:
```

has no nested `paths-ignore`, `push` still has `paths-ignore`, all three jobs contain `Detect PR change scope` and `Complete docs-only PR`, and all three checkout steps use `fetch-depth: 0`.

- [x] **Step 7: Verify the detector still passes after workflow edits**

Run:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test
bash -n .github/scripts/detect-docs-only-pr.sh
git diff --check
```

Expected: self-test prints `self_test=pass`; syntax and whitespace checks exit `0`.

- [x] **Step 8: Commit workflow correction**

Run:

```bash
git add .github/workflows/swift-ci.yml
git commit -m "ci: keep required checks present for docs-only PRs"
```

Expected: commit succeeds.

## Task 4: Update Durable Repo Guidance

**Files:**
- Modify: `AGENTS.md`

- [x] **Step 1: Replace the stale CI docs-only and required-check caveat**

In `AGENTS.md`, replace the paragraph beginning with:

```text
Docs-only changes skip Swift CI via `paths-ignore`
```

and the following `Caveat:` paragraph with this text:

```markdown
Required-check policy: the public repository `maldrakar/swift-text-engine` has
an active default-branch ruleset named `Main` (id `17656807`) that requires the
three Swift CI job contexts for PRs targeting `main`: `Host tests and benchmark
gate`, `iOS cross-target compile`, and `WASM cross-target observation`. Strict
required-status-check policy is enabled, so PRs must be tested with the latest
base branch state.

Docs-only PRs still start Swift CI so those required job contexts are emitted,
but each required job first runs `.github/scripts/detect-docs-only-pr.sh`. If the
full PR diff is only `docs/**` or `**/*.md`, the job prints
`mode=docs_only_pr ... result=success` and skips the heavy Swift/test/compile
work. If the diff cannot be determined, the detector fails closed. Docs-only
pushes to `main` may still skip Swift CI through the `push.paths-ignore` rule
because PR required checks are the merge gate.

Bypass caveat: the ruleset preserves the existing bypass actor shape, and the
current admin user can bypass it. Required checks are configured and enforced
for normal PR flow, but bypass-capable actors can still override the ruleset.
Last verified: 2026-06-16 via `gh api`; see
`docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`.
```

- [x] **Step 2: Verify AGENTS wording no longer states the stale private-repo caveat**

Run:

```bash
rg -n "private repo without branch protection|GitHub Pro / public-repo feature|red check blocks the \\*\\*status\\*\\*" AGENTS.md
```

Expected: command exits `1` with no matches.

- [x] **Step 3: Verify AGENTS contains the new operational facts**

Run:

```bash
rg -n 'public repository `maldrakar/swift-text-engine`|ruleset named `Main`|Strict required-status-check policy|detect-docs-only-pr|Bypass caveat' AGENTS.md
```

Expected: command exits `0` and prints all five new facts.

- [x] **Step 4: Commit AGENTS update**

Run:

```bash
git add AGENTS.md
git commit -m "docs: document required Swift CI policy"
```

Expected: commit succeeds.

## Task 5: Apply Required Status Checks To Ruleset `Main`

**Files:**
- Read: `/private/tmp/slice-18-ruleset-before.json`
- Create temporary: `/private/tmp/slice-18-ruleset-payload.json`
- Create temporary: `/private/tmp/slice-18-ruleset-after.json`
- Create temporary: `/private/tmp/slice-18-branch-rules-after.json`

- [x] **Step 1: Re-run preflight immediately before mutation**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-18-ruleset-before.json
jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and (.conditions.ref_name.include == ["~DEFAULT_BRANCH"])
  and ([.rules[].type] | index("pull_request") != null)
' /private/tmp/slice-18-ruleset-before.json
```

Expected: `jq -e` exits `0`. If `Main` no longer targets `~DEFAULT_BRANCH`, has a different id, or has unexpected branch conditions, stop and record the changed state instead of guessing.

- [x] **Step 2: Generate the narrow ruleset update payload**

Run:

```bash
jq '
  def required_checks_rule: {
    type: "required_status_checks",
    parameters: {
      strict_required_status_checks_policy: true,
      do_not_enforce_on_create: false,
      required_status_checks: [
        {context: "Host tests and benchmark gate"},
        {context: "iOS cross-target compile"},
        {context: "WASM cross-target observation"}
      ]
    }
  };
  {
    name: .name,
    target: .target,
    enforcement: .enforcement,
    bypass_actors: (.bypass_actors // []),
    conditions: .conditions,
    rules: ((.rules | map(select(.type != "required_status_checks"))) + [required_checks_rule])
  }
' /private/tmp/slice-18-ruleset-before.json > /private/tmp/slice-18-ruleset-payload.json
cat /private/tmp/slice-18-ruleset-payload.json
```

Expected: payload preserves `name`, `target`, `enforcement`, `bypass_actors`, `conditions`, and all existing non-status rules, then adds exactly one `required_status_checks` rule.

- [x] **Step 3: Validate the generated payload before PUT**

Run:

```bash
jq -e '
  .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and (.conditions.ref_name.include == ["~DEFAULT_BRANCH"])
  and ([.rules[].type] | index("creation") != null)
  and ([.rules[].type] | index("update") != null)
  and ([.rules[].type] | index("deletion") != null)
  and ([.rules[].type] | index("non_fast_forward") != null)
  and ([.rules[].type] | index("pull_request") != null)
  and ([.rules[].type] | index("required_deployments") != null)
  and ([.rules[] | select(.type == "required_status_checks")] | length == 1)
  and ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy) == true
' /private/tmp/slice-18-ruleset-payload.json
```

Expected: `jq -e` exits `0`.

- [x] **Step 4: Apply the ruleset update**

Run:

```bash
gh api --method PUT repos/maldrakar/swift-text-engine/rulesets/17656807 --input /private/tmp/slice-18-ruleset-payload.json > /private/tmp/slice-18-ruleset-after.json
cat /private/tmp/slice-18-ruleset-after.json
```

Expected: command exits `0` and returns the updated ruleset. If GitHub rejects the payload, stop and record the exact response; do not create another ruleset and do not switch to legacy branch protection.

- [x] **Step 5: Verify ruleset readback**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-18-ruleset-after.json
jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and (.conditions.ref_name.include == ["~DEFAULT_BRANCH"])
  and ([.rules[] | select(.type == "required_status_checks")] | length == 1)
  and ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy) == true
  and (.bypass_actors == (input.bypass_actors))
' /private/tmp/slice-18-ruleset-after.json /private/tmp/slice-18-ruleset-before.json
```

Expected: `jq -e` exits `0`; bypass actors match the pre-update readback.

- [x] **Step 6: Verify active branch rules include required status checks**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rules/branches/main > /private/tmp/slice-18-branch-rules-after.json
cat /private/tmp/slice-18-branch-rules-after.json
jq -e '
  [.[] | select(.type == "required_status_checks")] | length == 1
' /private/tmp/slice-18-branch-rules-after.json
jq -e '
  [.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
' /private/tmp/slice-18-branch-rules-after.json
```

Expected: both `jq -e` commands exit `0`.

## Task 6: Record Verification Evidence

**Files:**
- Create: `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`

- [x] **Step 1: Capture final local state and diff scope**

Run:

```bash
git status --short --branch > /private/tmp/slice-18-git-status.txt
git diff --stat HEAD~3..HEAD > /private/tmp/slice-18-diff-stat.txt
git diff --name-only HEAD~3..HEAD > /private/tmp/slice-18-diff-names.txt
cat /private/tmp/slice-18-git-status.txt
cat /private/tmp/slice-18-diff-stat.txt
cat /private/tmp/slice-18-diff-names.txt
```

Expected changed tracked files are limited to:

```text
.github/scripts/detect-docs-only-pr.sh
.github/workflows/swift-ci.yml
AGENTS.md
```

The verification file itself will appear after Step 2.

- [x] **Step 2: Create the verification record**

Create `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md` with these sections, filling each section with the exact command, exit status, and relevant output captured in `/private/tmp/slice-18-*`:

```markdown
# Swift CI Required Checks Verification

Date: 2026-06-16

## Summary

Slice 18 required the three current Swift CI job contexts in the active `Main`
ruleset for `main`, corrected PR docs-only behavior so required contexts are
emitted for fully docs-only PRs, and updated `AGENTS.md`.

No Swift source, tests, benchmark code, or `Package.swift` changed. `swift test`
and benchmark commands were intentionally not run because this slice changes
repository policy, workflow gating, and documentation only; those commands would
not validate the GitHub ruleset or the docs-only required-check behavior.

## Local State

## Workflow And Detector

## GitHub Preflight

## Ruleset Mutation

## Final Ruleset Readback

## Scope Proof
```

In the final file, do not leave empty sections. Each section must include the relevant command outputs from Tasks 1 through 6.

- [x] **Step 3: Verify the verification record mentions the required proof points**

Run:

```bash
rg -n "strict_required_status_checks_policy|required_status_checks|Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation|mode=docs_only_pr|No Swift source|intentionally not run" docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md
```

Expected: command exits `0` and prints matches for all proof points.

- [x] **Step 4: Verify no forbidden source areas changed**

Run:

```bash
git diff --name-only HEAD~3..HEAD -- Sources Tests Package.swift
```

Expected: no output.

- [x] **Step 5: Run final local checks**

Run:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test
bash -n .github/scripts/detect-docs-only-pr.sh
git diff --check
```

Expected: detector prints `self_test=pass`; syntax and whitespace checks exit `0`.

- [x] **Step 6: Commit verification record**

Run:

```bash
git add docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md
git commit -m "docs: record Swift CI required checks verification"
```

Expected: commit succeeds.

## Task 7: Final Hosted And Policy Sanity Check

**Files:**
- Read: `.github/workflows/swift-ci.yml`
- Read: `AGENTS.md`
- Read: `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`

- [x] **Step 1: Confirm final working tree state**

Run:

```bash
git status --short --branch
git log --oneline --decorate -5
```

Expected: branch is `slice-18-swift-ci-required-checks`; working tree is clean unless the user has unrelated changes.

- [x] **Step 2: Confirm workflow trigger and docs-only behavior**

Run:

```bash
rg -n "pull_request:|paths-ignore|Detect PR change scope|Complete docs-only PR|docs_only_pr|fetch-depth: 0" .github/workflows/swift-ci.yml
```

Expected: `pull_request:` has no `paths-ignore`, `push` still has docs-only `paths-ignore`, and each required job has detector and docs-only success steps.

- [x] **Step 3: Confirm final ruleset still matches acceptance criteria**

Run:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-18-ruleset-final.json
jq -e '
  .id == 17656807
  and .name == "Main"
  and .target == "branch"
  and .enforcement == "active"
  and (.conditions.ref_name.include == ["~DEFAULT_BRANCH"])
  and ([.rules[] | select(.type == "required_status_checks")] | length == 1)
  and ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort) == ([
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ] | sort)
  and (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy) == true
' /private/tmp/slice-18-ruleset-final.json
```

Expected: `jq -e` exits `0`.

- [x] **Step 4: Push branch and observe PR Swift CI**

Run:

```bash
git push -u origin slice-18-swift-ci-required-checks
gh pr create --title "Require Swift CI checks on main" --body-file docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md
```

Expected: push and PR creation succeed. The PR should start `Swift CI` because this branch is not docs-only. Observe the PR run and append the run id/result to the verification record in a follow-up commit if the run is available before handoff.

- [x] **Step 5: Handoff boundary**

If hosted PR Swift CI is still queued or running, do not claim hosted verification is complete. Report the PR URL, local checks, ruleset readback status, and the pending hosted run id.
