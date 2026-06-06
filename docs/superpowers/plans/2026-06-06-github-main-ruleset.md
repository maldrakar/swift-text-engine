# GitHub Main Ruleset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Deferred. Do not execute this plan unless Slice 6 is explicitly
> resumed. Execution was attempted on 2026-06-06 and blocked because GitHub
> rulesets for the private repository returned:
>
> ```text
> Upgrade to GitHub Pro or make this repository public to enable this feature.
> ```
>
> For now, the accepted state is the existing `Swift CI` workflow running on
> pull requests and pushes to `main`; repository-enforced rulesets are
> postponed while the repository is maintained by a single owner.

**Goal:** Configure and verify a GitHub repository ruleset that requires pull requests and the existing `Host tests and benchmark gate` check before `main` can be updated.

**Architecture:** This is an operational configuration slice. The implementation changes GitHub repository settings through `gh api`, then commits a verification record proving the final ruleset state. Swift source, tests, benchmark code, and workflow YAML stay unchanged.

**Tech Stack:** GitHub CLI, GitHub REST API repository rulesets, GitHub Actions, Swift Package Manager, ripgrep, git.

---

## Scope Check

This plan implements the approved Slice 6 design:

```text
docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md
```

The slice covers one subsystem: GitHub repository policy for `main`.

This plan does not change:

- `TextEngineCore`
- `ViewportBenchmarks`
- `Package.swift`
- `Tests/TextEngineCoreTests`
- `.github/workflows/swift-ci.yml`
- benchmark budgets
- realistic-provider behavior
- cross-target CI
- memory or allocation measurement
- human review policy
- unrelated GitHub rulesets
- legacy branch protection

The target repository is:

```text
arthurbanshchikov/swift-text-engine
```

The target branch is:

```text
main
```

The required check context is:

```text
Host tests and benchmark gate
```

The desired ruleset name is:

```text
Swift CI required on main
```

## File Structure

- Read: `docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md`
- Create temporarily: `/private/tmp/github-main-ruleset-payload.json`
- Create temporarily: `/private/tmp/github-main-ruleset-preflight-*.out`
- Create temporarily: `/private/tmp/github-main-ruleset-apply.out`
- Create temporarily: `/private/tmp/github-main-ruleset-final.out`
- Create: `docs/superpowers/verification/2026-06-06-github-main-ruleset.md`
- Do not modify: `Sources/**`
- Do not modify: `Tests/**`
- Do not modify: `Package.swift`
- Do not modify: `.github/workflows/swift-ci.yml`

## Task 1: Preflight Local Repository And GitHub Access

**Files:**
- Read: `docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md`
- Read: local git status
- Write temporary command output under `/private/tmp`

- [ ] **Step 1: Confirm the approved design is present**

Run:

```bash
sed -n '1,420p' docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md
```

Expected: command exits `0`; output includes:

```text
# GitHub Main Ruleset Design
Swift CI required on main
Host tests and benchmark gate
refs/heads/main
required_status_checks
pull_request
```

- [ ] **Step 2: Confirm local working tree state before external mutation**

Run:

```bash
git status --short
```

Expected: command exits `0`. It is acceptable for this already-known user file
to appear as untracked:

```text
?? docs/superpowers/reviews/2026-06-06-slice-5-post-slice-review.md
```

If `Sources/**`, `Tests/**`, `Package.swift`, or
`.github/workflows/swift-ci.yml` appear as modified, stop and inspect before
continuing.

- [ ] **Step 3: Confirm GitHub CLI is installed**

Run:

```bash
gh --version
```

Expected: command exits `0` and prints a `gh version` line.

- [ ] **Step 4: Confirm GitHub authentication**

Run:

```bash
gh auth status
```

Expected: command exits `0` and reports an authenticated account for
`github.com`.

If this fails because the user is not authenticated, stop and report the
blocker. Do not try to configure the ruleset through undocumented manual steps.

- [ ] **Step 5: Confirm repository identity and default branch**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine --jq '{full_name, default_branch, permissions}'
```

Expected: command exits `0`; output includes:

```json
{
  "full_name": "arthurbanshchikov/swift-text-engine",
  "default_branch": "main"
}
```

Expected permission: `.permissions.admin` is `true`. If `.permissions.admin` is
not `true`, continue no further and record that GitHub settings write access is
blocked.

- [ ] **Step 6: Capture repository identity output**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine --jq '{full_name, default_branch, permissions}' > /private/tmp/github-main-ruleset-preflight-repo.out
```

Expected: command exits `0`; the output file exists and contains
`"full_name": "arthurbanshchikov/swift-text-engine"`.

## Task 2: Verify Existing Workflow Check And Current Policy

**Files:**
- Read remote GitHub Actions state
- Read remote GitHub ruleset state
- Write temporary command output under `/private/tmp`

- [ ] **Step 1: List recent Swift CI runs**

Run:

```bash
gh run list --repo arthurbanshchikov/swift-text-engine --workflow "Swift CI" --limit 5 --json databaseId,event,headBranch,status,conclusion,createdAt,url
```

Expected: command exits `0`; output includes at least one completed run with
`"conclusion": "success"`.

- [ ] **Step 2: Capture recent Swift CI runs**

Run:

```bash
gh run list --repo arthurbanshchikov/swift-text-engine --workflow "Swift CI" --limit 5 --json databaseId,event,headBranch,status,conclusion,createdAt,url > /private/tmp/github-main-ruleset-preflight-runs.out
```

Expected: command exits `0`; the output file contains JSON for recent `Swift CI`
runs.

- [ ] **Step 3: Capture the newest successful Swift CI run id**

Run:

```bash
gh run list --repo arthurbanshchikov/swift-text-engine --workflow "Swift CI" --limit 20 --json databaseId,status,conclusion --jq 'map(select(.status == "completed" and .conclusion == "success"))[0].databaseId // empty' > /private/tmp/github-main-ruleset-success-run-id.out
```

Expected: command exits `0`; the output file contains one numeric run id.

If the output file is empty, stop. The required check context should not be
configured until a successful `Swift CI` run proves the check name exists.

- [ ] **Step 4: Verify the successful run has the expected job name**

Run:

```bash
RUN_ID=$(cat /private/tmp/github-main-ruleset-success-run-id.out); gh run view "$RUN_ID" --repo arthurbanshchikov/swift-text-engine --json databaseId,event,headBranch,conclusion,jobs,url --jq '{databaseId, event, headBranch, conclusion, url, jobs: [.jobs[] | {name, conclusion}]}'
```

Expected: command exits `0`; output includes:

```json
{
  "name": "Host tests and benchmark gate",
  "conclusion": "success"
}
```

If the job name differs, stop and return to design review before requiring a
different check context.

- [ ] **Step 5: Capture the successful run details**

Run:

```bash
RUN_ID=$(cat /private/tmp/github-main-ruleset-success-run-id.out); gh run view "$RUN_ID" --repo arthurbanshchikov/swift-text-engine --json databaseId,event,headBranch,conclusion,jobs,url --jq '{databaseId, event, headBranch, conclusion, url, jobs: [.jobs[] | {name, conclusion}]}' > /private/tmp/github-main-ruleset-preflight-run-view.out
```

Expected: command exits `0`; the output file contains the run id, URL, and a
successful `Host tests and benchmark gate` job.

- [ ] **Step 6: List repository rulesets**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/rulesets --jq '[.[] | {id, name, target, enforcement, conditions}]'
```

Expected: command exits `0`. Output may be an empty array or an array of
existing rulesets.

- [ ] **Step 7: Capture repository rulesets**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/rulesets --jq '[.[] | {id, name, target, enforcement, conditions}]' > /private/tmp/github-main-ruleset-preflight-rulesets.out
```

Expected: command exits `0`; the output file contains a JSON array.

- [ ] **Step 8: Inspect active rules that currently apply to main**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/rules/branches/main --jq '[.[] | {type, ruleset_id, ruleset_source_type, ruleset_source, parameters}]'
```

Expected: command exits `0`. Output may be an empty array or active rules that
already apply to `main`.

- [ ] **Step 9: Capture active main rules**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/rules/branches/main --jq '[.[] | {type, ruleset_id, ruleset_source_type, ruleset_source, parameters}]' > /private/tmp/github-main-ruleset-preflight-active-main-rules.out
```

Expected: command exits `0`; the output file contains a JSON array.

- [ ] **Step 10: Inspect legacy branch protection without depending on it**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/branches/main/protection --jq '{required_status_checks, required_pull_request_reviews, enforce_admins}' > /private/tmp/github-main-ruleset-preflight-legacy-protection.out 2>&1 || true
```

Expected: command completes. A `404` response is acceptable and means legacy
branch protection is not configured for `main`. This slice does not modify
legacy branch protection either way.

## Task 3: Create Or Update The Narrow Ruleset

**Files:**
- Create temporary: `/private/tmp/github-main-ruleset-payload.json`
- Write temporary command output under `/private/tmp`
- Mutate external GitHub repository settings only through `gh api`

- [ ] **Step 1: Create the desired ruleset payload**

Use `apply_patch` with this patch:

```diff
*** Begin Patch
*** Add File: /private/tmp/github-main-ruleset-payload.json
+{
+  "name": "Swift CI required on main",
+  "target": "branch",
+  "enforcement": "active",
+  "conditions": {
+    "ref_name": {
+      "include": [
+        "refs/heads/main"
+      ],
+      "exclude": []
+    }
+  },
+  "rules": [
+    {
+      "type": "pull_request",
+      "parameters": {
+        "required_approving_review_count": 0,
+        "dismiss_stale_reviews_on_push": false,
+        "require_code_owner_review": false,
+        "require_last_push_approval": false,
+        "required_review_thread_resolution": false
+      }
+    },
+    {
+      "type": "required_status_checks",
+      "parameters": {
+        "strict_required_status_checks_policy": true,
+        "required_status_checks": [
+          {
+            "context": "Host tests and benchmark gate"
+          }
+        ]
+      }
+    }
+  ]
+}
*** End Patch
```

Expected: `/private/tmp/github-main-ruleset-payload.json` exists with the JSON
above.

- [ ] **Step 2: Validate the payload file can be parsed**

Run:

```bash
plutil -lint /private/tmp/github-main-ruleset-payload.json
```

Expected: command exits `0` and prints:

```text
/private/tmp/github-main-ruleset-payload.json: OK
```

This validates JSON syntax only. GitHub ruleset semantics are validated by the
apply step.

- [ ] **Step 3: Capture an existing same-name ruleset id, if present**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/rulesets --jq 'map(select(.name == "Swift CI required on main"))[0].id // empty' > /private/tmp/github-main-ruleset-existing-id.out
```

Expected: command exits `0`. The output file is either empty or contains one
numeric ruleset id.

- [ ] **Step 4: If a same-name ruleset exists, inspect it before update**

Run:

```bash
RULESET_ID=$(cat /private/tmp/github-main-ruleset-existing-id.out); if [ -n "$RULESET_ID" ]; then gh api "repos/arthurbanshchikov/swift-text-engine/rulesets/$RULESET_ID" --jq '{id, name, target, enforcement, conditions, rules}'; fi
```

Expected when output exists: it is the same narrow policy owned by this slice,
or a partial previous attempt at the same narrow policy. If it contains broader
unrelated policy such as merge queue, deployments, signed commits, restrictions,
or non-fast-forward rules, stop before overwriting it.

- [ ] **Step 5: Apply the ruleset**

Run:

```bash
RULESET_ID=$(cat /private/tmp/github-main-ruleset-existing-id.out); if [ -n "$RULESET_ID" ]; then gh api --method PUT "repos/arthurbanshchikov/swift-text-engine/rulesets/$RULESET_ID" --input /private/tmp/github-main-ruleset-payload.json > /private/tmp/github-main-ruleset-apply.out; else gh api --method POST repos/arthurbanshchikov/swift-text-engine/rulesets --input /private/tmp/github-main-ruleset-payload.json > /private/tmp/github-main-ruleset-apply.out; fi
```

Expected: command exits `0`; `/private/tmp/github-main-ruleset-apply.out`
contains the created or updated ruleset JSON.

If GitHub returns `403`, stop and record a permissions blocker. If GitHub
returns `422`, stop and record the validation response. Do not switch to legacy
branch protection in this slice.

- [ ] **Step 6: Capture the resulting ruleset id**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/rulesets --jq 'map(select(.name == "Swift CI required on main"))[0].id // empty' > /private/tmp/github-main-ruleset-final-id.out
```

Expected: command exits `0`; output file contains one numeric ruleset id.

If the output file is empty, stop because the ruleset was not created or updated
as expected.

## Task 4: Verify Final GitHub State

**Files:**
- Read external GitHub repository settings
- Write temporary command output under `/private/tmp`

- [ ] **Step 1: Read back the final ruleset**

Run:

```bash
RULESET_ID=$(cat /private/tmp/github-main-ruleset-final-id.out); gh api "repos/arthurbanshchikov/swift-text-engine/rulesets/$RULESET_ID" --jq '{id, name, target, enforcement, conditions, rules, links: ._links}'
```

Expected: command exits `0`; output includes:

```text
Swift CI required on main
branch
active
refs/heads/main
pull_request
required_status_checks
Host tests and benchmark gate
strict_required_status_checks_policy
```

- [ ] **Step 2: Capture final ruleset readback**

Run:

```bash
RULESET_ID=$(cat /private/tmp/github-main-ruleset-final-id.out); gh api "repos/arthurbanshchikov/swift-text-engine/rulesets/$RULESET_ID" --jq '{id, name, target, enforcement, conditions, rules, links: ._links}' > /private/tmp/github-main-ruleset-final.out
```

Expected: command exits `0`; the output file contains final ruleset JSON.

- [ ] **Step 3: Verify active main rules include the desired policy**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/rules/branches/main --jq '[.[] | {type, ruleset_id, ruleset_source_type, ruleset_source, parameters}]'
```

Expected: command exits `0`; output includes one `pull_request` rule and one
`required_status_checks` rule from the final ruleset id.

- [ ] **Step 4: Capture active main rules after apply**

Run:

```bash
gh api repos/arthurbanshchikov/swift-text-engine/rules/branches/main --jq '[.[] | {type, ruleset_id, ruleset_source_type, ruleset_source, parameters}]' > /private/tmp/github-main-ruleset-final-active-main-rules.out
```

Expected: command exits `0`; the output file contains active rules for `main`.

- [ ] **Step 5: Verify the final ruleset has exactly the required check context**

Run:

```bash
RULESET_ID=$(cat /private/tmp/github-main-ruleset-final-id.out); gh api "repos/arthurbanshchikov/swift-text-engine/rulesets/$RULESET_ID" --jq '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context'
```

Expected output:

```text
Host tests and benchmark gate
```

- [ ] **Step 6: Verify strict required status checks are enabled**

Run:

```bash
RULESET_ID=$(cat /private/tmp/github-main-ruleset-final-id.out); gh api "repos/arthurbanshchikov/swift-text-engine/rulesets/$RULESET_ID" --jq '.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy'
```

Expected output:

```text
true
```

- [ ] **Step 7: Verify pull request rule is present and does not require human reviews**

Run:

```bash
RULESET_ID=$(cat /private/tmp/github-main-ruleset-final-id.out); gh api "repos/arthurbanshchikov/swift-text-engine/rulesets/$RULESET_ID" --jq '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count'
```

Expected output:

```text
0
```

## Task 5: Record Verification And Commit

**Files:**
- Create: `docs/superpowers/verification/2026-06-06-github-main-ruleset.md`
- Read: `/private/tmp/github-main-ruleset-preflight-repo.out`
- Read: `/private/tmp/github-main-ruleset-preflight-runs.out`
- Read: `/private/tmp/github-main-ruleset-preflight-run-view.out`
- Read: `/private/tmp/github-main-ruleset-preflight-rulesets.out`
- Read: `/private/tmp/github-main-ruleset-preflight-active-main-rules.out`
- Read: `/private/tmp/github-main-ruleset-preflight-legacy-protection.out`
- Read: `/private/tmp/github-main-ruleset-apply.out`
- Read: `/private/tmp/github-main-ruleset-final.out`
- Read: `/private/tmp/github-main-ruleset-final-active-main-rules.out`

- [ ] **Step 1: Confirm product source and workflow files are unchanged**

Run:

```bash
git diff -- Sources Tests Package.swift .github/workflows/swift-ci.yml
```

Expected: command exits `0` and prints no output.

- [ ] **Step 2: Run host tests**

Run:

```bash
swift test
```

Expected: command exits `0`; output reports `39 tests` and `0 failures`.

- [ ] **Step 3: Run the existing synthetic benchmark gate**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Expected: command exits `0`; output includes three `mode=pipeline` lines, each
with `failures=0` and `gate=pass`.

- [ ] **Step 4: Capture final local git status**

Run:

```bash
git status --short
```

Expected: command exits `0`. Expected uncommitted entries before creating the
verification record:

```text
?? docs/superpowers/reviews/2026-06-06-slice-5-post-slice-review.md
```

If `Sources/**`, `Tests/**`, `Package.swift`, or
`.github/workflows/swift-ci.yml` appear, stop and inspect.

- [ ] **Step 5: Create the verification record**

Use `apply_patch` to add
`docs/superpowers/verification/2026-06-06-github-main-ruleset.md`.

Use this structure. For every section that says to insert captured output, put
the exact observed command output inside the specified fenced block before
committing the file.

```markdown
# GitHub Main Ruleset Verification

Date: 2026-06-06

## Scope

Slice 6 configured and verified a GitHub repository ruleset for
`arthurbanshchikov/swift-text-engine` that applies to `refs/heads/main`.

Ruleset:

```text
Swift CI required on main
```

Required check context:

```text
Host tests and benchmark gate
```

## Commands

- `gh --version`: pass
- `gh auth status`: pass
- `gh api repos/arthurbanshchikov/swift-text-engine --jq '{full_name, default_branch, permissions}'`: pass
- `gh run list --repo arthurbanshchikov/swift-text-engine --workflow "Swift CI" --limit 5 --json databaseId,event,headBranch,status,conclusion,createdAt,url`: pass
- `gh run view` for the selected successful run id: pass
- `gh api repos/arthurbanshchikov/swift-text-engine/rulesets`: pass
- `gh api repos/arthurbanshchikov/swift-text-engine/rules/branches/main`: pass
- `gh api repos/arthurbanshchikov/swift-text-engine/branches/main/protection`: pass or expected 404
- `gh api --method POST` or `gh api --method PUT` for the ruleset: pass
- `gh api` readback for the final ruleset id: pass
- `git diff -- Sources Tests Package.swift .github/workflows/swift-ci.yml`: no output
- `swift test`: pass
- `swift run -c release ViewportBenchmarks -- --gate`: pass

## Repository Identity

Insert the exact JSON from `/private/tmp/github-main-ruleset-preflight-repo.out`.

```json
```

## Recent Swift CI Runs

Insert the exact JSON from `/private/tmp/github-main-ruleset-preflight-runs.out`.

```json
```

## Selected Successful Swift CI Run

Insert the exact JSON from `/private/tmp/github-main-ruleset-preflight-run-view.out`.

```json
```

## Preflight Rulesets

Insert the exact JSON from `/private/tmp/github-main-ruleset-preflight-rulesets.out`.

```json
```

## Preflight Active Main Rules

Insert the exact JSON from `/private/tmp/github-main-ruleset-preflight-active-main-rules.out`.

```json
```

## Preflight Legacy Branch Protection

Insert the exact text from `/private/tmp/github-main-ruleset-preflight-legacy-protection.out`.

```text
```

## Ruleset Apply Result

Insert the exact JSON from `/private/tmp/github-main-ruleset-apply.out`.

```json
```

## Final Ruleset Readback

Insert the exact JSON from `/private/tmp/github-main-ruleset-final.out`.

```json
```

## Final Active Main Rules

Insert the exact JSON from `/private/tmp/github-main-ruleset-final-active-main-rules.out`.

```json
```

## Local Non-Goal Checks

`git diff -- Sources Tests Package.swift .github/workflows/swift-ci.yml`:

Insert the exact output. The expected block is empty.

```text
```

`swift test`:

Insert the exact output from Step 2.

```text
```

`swift run -c release ViewportBenchmarks -- --gate`:

Insert the exact output from Step 3.

```text
```

## Result

- Repository: `arthurbanshchikov/swift-text-engine`
- Target branch: `main`
- Ruleset name: `Swift CI required on main`
- Ruleset enforcement: `active`
- Required update path: pull request
- Required status check: `Host tests and benchmark gate`
- Strict status-check policy: enabled

## Limitations

This slice verifies GitHub configuration state through API readback. It does not
perform a destructive live merge-rejection test.

This slice does not change Swift source, tests, benchmark code, benchmark
budgets, realistic-provider behavior, cross-target CI, or workflow YAML.
```

Expected: the verification record contains exact observed outputs. It must not
leave unresolved marker text in the committed file.

- [ ] **Step 6: Verify the verification record has no unresolved markers**

Run:

```bash
rg -n "T[B]D|T[O]DO|exact output|selected successful run id|ruleset-id|unresolved marker" docs/superpowers/verification/2026-06-06-github-main-ruleset.md
```

Expected: command exits `1` with no output.

- [ ] **Step 7: Review final git status**

Run:

```bash
git status --short
```

Expected output includes the new verification record and the already-known
untracked Slice 5 review. It must not show modifications under `Sources`,
`Tests`, `Package.swift`, or `.github/workflows/swift-ci.yml`.

- [ ] **Step 8: Commit the verification record only**

Run:

```bash
git add docs/superpowers/verification/2026-06-06-github-main-ruleset.md
git commit -m "docs: verify github main ruleset"
```

Expected: commit succeeds and includes only the verification record.

The untracked `docs/superpowers/reviews/2026-06-06-slice-5-post-slice-review.md`
must remain untouched unless the user separately asks to commit it.
