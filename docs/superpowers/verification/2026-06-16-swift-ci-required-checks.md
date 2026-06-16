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

Command:

```bash
git status --short --branch
```

Exit status: `0`.

```text
## slice-18-swift-ci-required-checks
?? docs/superpowers/plans/2026-06-16-swift-ci-required-checks.md
```

The untracked plan file was present before implementation and was not modified
or committed by this slice.

Command:

```bash
git diff --stat HEAD~4..HEAD
git diff --name-only HEAD~4..HEAD
```

Exit status: `0`.

```text
 .github/scripts/detect-docs-only-pr.sh             | 190 +++++++++
 .github/workflows/swift-ci.yml                     |  77 +++-
 AGENTS.md                                          |  32 +-
 .../2026-06-16-swift-ci-required-checks.md         | 433 +++++++++++++++++++++
 4 files changed, 716 insertions(+), 16 deletions(-)
```

```text
.github/scripts/detect-docs-only-pr.sh
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md
```

## Workflow And Detector

Command:

```bash
rg -n "pull_request:|paths-ignore|Detect PR change scope|Complete docs-only PR|docs_only_pr|fetch-depth: 0" .github/workflows/swift-ci.yml
```

Exit status: `0`.

```text
4:  pull_request:
8:    paths-ignore:
30:          fetch-depth: 0
32:      - name: Detect PR change scope
42:            echo "mode=docs_only_pr event=$EVENT_NAME result=not_pull_request docs_only_pr=false"
47:      - name: Complete docs-only PR
49:        run: echo "mode=docs_only_pr job=host-tests-and-benchmark-gate result=success"
86:        if: github.event_name == 'pull_request' && steps.change-scope.outputs.docs_only_pr != 'true'
136:          fetch-depth: 0
138:      - name: Detect PR change scope
153:      - name: Complete docs-only PR
155:        run: echo "mode=docs_only_pr job=ios-cross-target-compile result=success"
181:          fetch-depth: 0
183:      - name: Detect PR change scope
198:      - name: Complete docs-only PR
200:        run: echo "mode=docs_only_pr job=wasm-cross-target-observation result=success"
```

`pull_request:` has no nested `paths-ignore`; the remaining `paths-ignore` is
under `push`.

Command:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test
bash -n .github/scripts/detect-docs-only-pr.sh
git diff --check
```

Exit status: `0`.

```text
self_test=pass
```

`bash -n` and `git diff --check` produced no output.

Command:

```bash
rg -n 'public repository `maldrakar/swift-text-engine`|ruleset named `Main`|Strict required-status-check policy|detect-docs-only-pr|Bypass caveat' AGENTS.md
```

Exit status: `0`.

```text
113:Required-check policy: the public repository `maldrakar/swift-text-engine` has
114:an active default-branch ruleset named `Main` (id `17656807`) that requires the
117:Strict required-status-check policy is enabled, so PRs must be tested with the
121:but each required job first runs `.github/scripts/detect-docs-only-pr.sh`. If the
128:Bypass caveat: the ruleset preserves the existing bypass actor shape, and the
```

Stale wording check:

```bash
rg -n "private repo without branch protection|GitHub Pro / public-repo feature|red check blocks the \*\*status\*\*" AGENTS.md
```

Exit status: `1`; no output.

## GitHub Preflight

Command:

```bash
gh auth status
```

Exit status: `0`.

```text
github.com
  - Active account: true
  - Git operations protocol: ssh
  - Token scopes: 'admin:public_key', 'gist', 'read:org', 'repo'
```

Command:

```bash
gh api repos/maldrakar/swift-text-engine --jq '{full_name,visibility,default_branch,permissions}' > /private/tmp/slice-18-repo.json
jq '{full_name,visibility,default_branch,admin:.permissions.admin}' /private/tmp/slice-18-repo.json
jq -e '.full_name == "maldrakar/swift-text-engine" and .visibility == "public" and .default_branch == "main" and .permissions.admin == true' /private/tmp/slice-18-repo.json
```

Exit status: `0`.

```json
{
  "full_name": "maldrakar/swift-text-engine",
  "visibility": "public",
  "default_branch": "main",
  "admin": true
}
```

Command:

```bash
gh api repos/maldrakar/swift-text-engine/actions/workflows --jq '.workflows[] | select(.name=="Swift CI") | {id,name,state,path}'
```

Exit status: `0`.

```json
{
  "id": 289994044,
  "name": "Swift CI",
  "state": "active",
  "path": ".github/workflows/swift-ci.yml"
}
```

Command:

```bash
gh run list --workflow "Swift CI" --branch main --limit 1 --json databaseId,headSha,conclusion,status,url > /private/tmp/slice-18-latest-run.json
jq '{run:.[0]}' /private/tmp/slice-18-latest-run.json
gh run view 27533521987 --json jobs --jq '[.jobs[] | {name,conclusion,status}]' > /private/tmp/slice-18-latest-run-jobs.json
jq '[.[] | {name,status,conclusion}]' /private/tmp/slice-18-latest-run-jobs.json
```

Exit status: `0`.

```json
{
  "run": {
    "conclusion": "success",
    "databaseId": 27533521987,
    "headSha": "829845ed1b4eec7f4570834b003e6ab6e5963f7e",
    "status": "completed",
    "url": "https://github.com/maldrakar/swift-text-engine/actions/runs/27533521987"
  }
}
```

```json
[
  {
    "name": "iOS cross-target compile",
    "status": "completed",
    "conclusion": "success"
  },
  {
    "name": "Host tests and benchmark gate",
    "status": "completed",
    "conclusion": "success"
  },
  {
    "name": "WASM cross-target observation",
    "status": "completed",
    "conclusion": "success"
  }
]
```

Command:

```bash
gh api repos/maldrakar/swift-text-engine/branches/main/protection
```

Exit status: `1`.

```text
legacy_branch_protection_status=1
gh: Branch not protected (HTTP 404)
```

Legacy branch protection was read only; this slice did not modify it.

## Ruleset Mutation

Before mutation command:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-18-ruleset-before.json
jq '{id,name,target,enforcement,conditions,bypass_actors,rule_types:[.rules[].type],required_status_checks:([.rules[] | select(.type=="required_status_checks")][0] // null)}' /private/tmp/slice-18-ruleset-before.json
```

Exit status: `0`.

```json
{
  "id": 17656807,
  "name": "Main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "exclude": [],
      "include": [
        "~DEFAULT_BRANCH"
      ]
    }
  },
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ],
  "rule_types": [
    "deletion",
    "non_fast_forward",
    "creation",
    "update",
    "pull_request",
    "required_deployments"
  ],
  "required_status_checks": null
}
```

Payload validation command:

```bash
jq -e '
  .name == "Main"
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
' /private/tmp/slice-18-ruleset-payload.json
```

Exit status: `0`.

Mutation command:

```bash
gh api --method PUT repos/maldrakar/swift-text-engine/rulesets/17656807 --input /private/tmp/slice-18-ruleset-payload.json
```

Exit status: `0`.

## Final Ruleset Readback

Command:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 --jq '{id,name,target,enforcement,conditions,bypass_actors,rules}' > /private/tmp/slice-18-ruleset-after.json
jq '{id,name,target,enforcement,conditions,bypass_actors,rule_types:[.rules[].type],required_status_checks:([.rules[] | select(.type=="required_status_checks")][0] // null)}' /private/tmp/slice-18-ruleset-after.json
```

Exit status: `0`.

```json
{
  "id": 17656807,
  "name": "Main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "exclude": [],
      "include": [
        "~DEFAULT_BRANCH"
      ]
    }
  },
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ],
  "rule_types": [
    "deletion",
    "non_fast_forward",
    "creation",
    "update",
    "pull_request",
    "required_deployments",
    "required_status_checks"
  ],
  "required_status_checks": {
    "parameters": {
      "do_not_enforce_on_create": false,
      "required_status_checks": [
        {
          "context": "Host tests and benchmark gate"
        },
        {
          "context": "iOS cross-target compile"
        },
        {
          "context": "WASM cross-target observation"
        }
      ],
      "strict_required_status_checks_policy": true
    },
    "type": "required_status_checks"
  }
}
```

Command:

```bash
gh api repos/maldrakar/swift-text-engine/rules/branches/main > /private/tmp/slice-18-branch-rules-after.json
jq '[.[] | select(.type=="required_status_checks")]' /private/tmp/slice-18-branch-rules-after.json
```

Exit status: `0`.

```json
[
  {
    "type": "required_status_checks",
    "parameters": {
      "strict_required_status_checks_policy": true,
      "do_not_enforce_on_create": false,
      "required_status_checks": [
        {
          "context": "Host tests and benchmark gate"
        },
        {
          "context": "iOS cross-target compile"
        },
        {
          "context": "WASM cross-target observation"
        }
      ]
    },
    "ruleset_source_type": "Repository",
    "ruleset_source": "maldrakar/swift-text-engine",
    "ruleset_id": 17656807
  }
]
```

Independent Task 5 review confirmed the saved evidence and read-only live
readbacks: one repository ruleset, one required status checks rule, strict
policy enabled, expected contexts, and unchanged bypass actor shape.

## Scope Proof

Command:

```bash
git diff --name-only HEAD~4..HEAD -- Sources Tests Package.swift
```

Exit status: `0`; no output.

Tracked changes across the final slice commits are limited to:

```text
.github/scripts/detect-docs-only-pr.sh
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md
```

No Swift source, tests, benchmark code, or `Package.swift` changed.
