# GitHub Main Ruleset Design

Date: 2026-06-06

## Status

Approved design, written for user review.

## Source Context

This design is Slice 6 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slice 1 delivered fixed-height viewport range calculation and buffered geometry
traversal. Slice 2 delivered the generic document/source provider contract and
buffered document line cursor. Slice 3 delivered the release-mode synthetic
benchmark gate for the fixed-height headless pipeline. Slice 4 added an opt-in
realistic large-text provider benchmark outside `TextEngineCore`. Slice 5 added
the `Swift CI` GitHub Actions workflow that runs host tests and the synthetic
benchmark gate on pull requests and pushes to `main`.

The Slice 5 post-slice review confirmed that the workflow passed on the first
observed pull request run and post-merge push run. It also identified the
remaining operational gap: the workflow only blocks merges if GitHub repository
settings require its check for `main`.

This slice closes that operational gap by configuring and verifying a GitHub
repository ruleset for `main`.

## Scope

Configure and verify one GitHub repository ruleset that applies to
`refs/heads/main` and requires:

- changes to reach `main` through a pull request;
- the `Host tests and benchmark gate` check to pass before `main` is updated;
- strict status-check policy, so pull requests targeting `main` are tested with
  the latest target-branch code.

The intended ruleset name is:

```text
Swift CI required on main
```

Implementation uses GitHub API access through `gh api`.

## Goals

- Make the existing `Swift CI` workflow repository-enforced for `main`.
- Require the existing `Host tests and benchmark gate` check context.
- Require a pull-request path for updates to `main`.
- Keep the policy narrow: PR path plus the existing Swift CI job only.
- Verify the resulting GitHub settings through API readback.
- Record exact verification evidence in a committed verification document.
- Leave Swift source, tests, benchmark code, and workflow YAML unchanged.

## Non-Goals

- Changing `TextEngineCore`.
- Changing `ViewportBenchmarks`.
- Changing `.github/workflows/swift-ci.yml`.
- Changing benchmark budgets.
- Adding realistic-provider budgets to `--gate`.
- Running realistic-provider benchmarks in CI.
- Adding memory, allocation, or resident-memory profiling.
- Adding cross-target CI for iOS, WASM, or embedded WASM.
- Requiring human approval reviews.
- Requiring code owner review.
- Requiring review-thread resolution.
- Adding merge queue, signed commits, linear history, deployment gates, branch
  locks, actor restrictions, force-push policy, or deletion policy.
- Performing a destructive live merge-rejection test.
- Rewriting unrelated existing GitHub rulesets or legacy branch protection.

## Architecture

Slice 6 is an operational configuration slice. The source-controlled project
artifacts are documentation only:

```text
docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md
docs/superpowers/plans/2026-06-06-github-main-ruleset.md
docs/superpowers/verification/2026-06-06-github-main-ruleset.md
```

The external artifact is one repository ruleset in GitHub:

```text
name: Swift CI required on main
target: branch
enforcement: active
condition: refs/heads/main
rules:
  - pull_request
  - required_status_checks
```

GitHub's rulesets API is the primary mechanism because rulesets are named,
queryable policy objects and avoid rewriting broad legacy branch-protection
state. Legacy branch protection is inspected for context but not modified in
this slice.

The ruleset applier is idempotent:

- if an equivalent active ruleset already exists, record it and do not mutate;
- if a same-name ruleset exists with the expected narrow ownership, update that
  ruleset to the desired state;
- if no equivalent or same-name ruleset exists, create a new narrow ruleset;
- if a same-name ruleset exists with unexpected broader policy, stop before
  overwriting it.

## Desired Ruleset Shape

The desired ruleset payload is conceptually:

```json
{
  "name": "Swift CI required on main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          {
            "context": "Host tests and benchmark gate"
          }
        ]
      }
    }
  ]
}
```

The `pull_request` rule uses zero required approvals because this slice is about
requiring the pull-request path and the Swift CI check, not adding human review
policy.

The `required_status_checks` rule uses the existing GitHub Actions job name as
the required status-check context. Slice 5 intentionally named the job:

```text
Host tests and benchmark gate
```

The implementation plan should verify this exact context from recent GitHub
Actions runs before applying the ruleset.

## Components

### Preflight Inspector

Responsibilities:

- confirm `gh` is installed and authenticated;
- confirm the authenticated account can read and write repository settings;
- resolve the repository as `arthurbanshchikov/swift-text-engine`;
- confirm the target branch is `main`;
- list recent `Swift CI` workflow runs;
- verify the recent successful job/check context is
  `Host tests and benchmark gate`;
- list repository rulesets;
- read existing branch protection for `main`, if any, as context only.

If repository identity, branch, access, or check context cannot be confirmed,
the slice stops before mutating GitHub settings.

### Ruleset Applier

Responsibilities:

- create or update only the `Swift CI required on main` ruleset;
- avoid touching unrelated repository rulesets;
- avoid touching legacy branch protection;
- avoid broadening repository policy beyond PR path plus required Swift CI;
- stop on ambiguous existing policy instead of guessing.

### Verification Record

The verification record should be written to:

```text
docs/superpowers/verification/2026-06-06-github-main-ruleset.md
```

It should record:

- repository identity and target branch;
- recent successful `Swift CI` run and job/check name;
- preflight ruleset and branch-protection state;
- whether the slice created, updated, or reused an existing equivalent ruleset;
- final ruleset id, name, API URL, and HTML URL when available;
- final readback proving active enforcement on `refs/heads/main`;
- final readback proving `pull_request`;
- final readback proving `required_status_checks`;
- final readback proving context `Host tests and benchmark gate`;
- final readback proving strict status-check policy;
- local git diff evidence proving no source, tests, benchmark, or workflow YAML
  changed;
- the limitation that this slice verifies configuration state and does not run
  a destructive live merge-rejection test.

## Data Flow

1. Resolve GitHub repository identity.
2. Confirm the target branch is `main`.
3. Confirm `gh` authentication and repository settings write capability.
4. Query recent `Swift CI` workflow runs.
5. Confirm the required check context is `Host tests and benchmark gate`.
6. Query current repository rulesets.
7. Query current legacy branch protection for `main`, if available.
8. Decide whether to reuse, update, or create the narrow ruleset.
9. Apply the ruleset through GitHub API.
10. Read the resulting ruleset back through GitHub API.
11. Query active branch rules for `main` when useful to confirm the rules apply.
12. Record verification output.
13. Confirm the slice did not modify source, tests, benchmark code, or workflow
    YAML.

## Error Handling

If `gh` is missing, unauthenticated, or lacks settings write permission, the
slice stops with a documented blocker. It should not silently fall back to UI
instructions or partial policy.

If repository identity or `main` cannot be confirmed, the slice stops before
mutating GitHub settings.

If the `Host tests and benchmark gate` context cannot be confirmed from recent
remote workflow data, the slice stops rather than requiring a guessed status
check name.

If an equivalent active ruleset already exists, the slice records it and does
not create a duplicate.

If a same-name ruleset exists and appears to be the narrow Slice 6 policy, the
slice may update it to the desired state.

If a same-name ruleset exists with unexpected broader policy, the slice stops
before overwriting it.

If unrelated rulesets or legacy branch protection exist, the slice leaves them
untouched and records them as context.

If GitHub rejects the ruleset payload, the slice records the exact API response
and stops. It should not switch to legacy branch protection in the same slice
without returning to design review.

## Testing And Verification

Implementation should verify the slice in these layers.

First, preflight local and remote identity:

```text
gh --version
gh auth status
gh repo view arthurbanshchikov/swift-text-engine --json nameWithOwner,defaultBranchRef
```

Second, confirm the existing remote workflow/check context:

```text
gh run list --repo arthurbanshchikov/swift-text-engine --workflow "Swift CI" --limit 5
gh run view <run-id> --repo arthurbanshchikov/swift-text-engine --json databaseId,event,headBranch,conclusion,jobs,url
```

Expected: at least one recent successful run exists, and its jobs include
`Host tests and benchmark gate`.

Third, inspect current policy state:

```text
gh api repos/arthurbanshchikov/swift-text-engine/rulesets
gh api repos/arthurbanshchikov/swift-text-engine/branches/main/protection
gh api repos/arthurbanshchikov/swift-text-engine/rules/branches/main
```

The branch-protection command may return `404` if legacy branch protection is
not configured. That is acceptable when the ruleset path is used.

Fourth, apply the desired ruleset through `gh api` using `POST` or `PUT` based
on preflight state.

Fifth, read back the resulting ruleset and active branch rules:

```text
gh api repos/arthurbanshchikov/swift-text-engine/rulesets/<ruleset-id>
gh api repos/arthurbanshchikov/swift-text-engine/rules/branches/main
```

Expected readback:

- ruleset `name` is `Swift CI required on main`;
- `target` is `branch`;
- `enforcement` is `active`;
- conditions include `refs/heads/main`;
- rules include `pull_request`;
- rules include `required_status_checks`;
- required status checks include context `Host tests and benchmark gate`;
- strict required status-check policy is `true`.

Sixth, confirm source-controlled non-goals:

```text
git diff -- Sources Tests Package.swift .github/workflows/swift-ci.yml
swift test
swift run -c release ViewportBenchmarks -- --gate
```

The diff command should produce no output. Host tests and the existing
synthetic gate should still pass.

## Success Criteria

- GitHub API readback proves `main` has an active ruleset requiring PR updates.
- GitHub API readback proves `main` requires `Host tests and benchmark gate`.
- GitHub API readback proves strict required-status-check policy is enabled.
- Recent successful `Swift CI` remote run is recorded with job/check evidence.
- Verification record is committed.
- Swift source, tests, benchmark code, and workflow YAML remain unchanged.

## References

- GitHub REST API endpoints for repository rulesets:
  `https://docs.github.com/en/rest/repos/rules`
- GitHub REST API endpoints for branch protection:
  `https://docs.github.com/en/rest/branches/branch-protection`
