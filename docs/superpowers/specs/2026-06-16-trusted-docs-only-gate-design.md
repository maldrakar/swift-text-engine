# Trusted Docs-Only Required-Check Gate Design

Date: 2026-06-16

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 19 of SwiftTextEngine, following the Slice 18 post-slice review:

```text
docs/superpowers/reviews/2026-06-16-slice-18-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires the headless
`TextEngineCore` contract to be protected by regression benchmarks and
cross-target compile checks. Slice 18 moved that protection into repository
policy by requiring these three GitHub Actions job contexts for PRs targeting
`main`:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

Slice 18 also kept fully docs-only PRs mergeable by removing PR-level workflow
`paths-ignore` and adding a lightweight docs-only path inside each required job.
The post-slice review found one confirmed P1 issue: each job checks out the PR
merge tree, then executes `./.github/scripts/detect-docs-only-pr.sh` from that
checkout. Because the detector is loaded from the PR workspace, a PR can modify
the helper to write `docs_only_pr=true` and skip the heavy Swift/test/compile
steps while still producing green required contexts.

GitHub Actions documentation says `pull_request` workflows operate on the PR
merge branch by default, while `pull_request_target` runs in the base context
and must be used carefully because building or running untrusted PR code from
that event can be unsafe:

- <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request>
- <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request_target>
- <https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#mitigating-the-risks-of-untrusted-code-checkout>

Slice 19 therefore keeps the current `pull_request` jobs for heavy Swift CI, but
makes the docs-only classifier execute from a trusted copy of the base commit
rather than from the PR checkout.

## Problem

The repository now requires the right Swift CI contexts, but the docs-only
exception is still decided by PR-owned executable code. That makes the required
contexts weaker than they look:

- a PR can alter `.github/scripts/detect-docs-only-pr.sh`;
- the altered helper can emit `docs_only_pr=true`;
- all three required jobs can take the lightweight path;
- Swift tests, benchmark gates, iOS compile, and WASM observation can be skipped
  even when the PR changes non-doc files.

The fix must close that trust boundary without broadening Slice 19 into a
benchmark, source, or repository-ruleset redesign.

## Scope

Slice 19 changes the docs-only PR classification path used by Swift CI.

It is a workflow-helper, workflow-YAML, documentation, and verification slice.
It does not change Swift source, public API, tests, benchmark modes, benchmark
budgets, package metadata, or the set of required GitHub status contexts.

## Goals

- Preserve the three existing required job contexts exactly:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- Ensure the docs-only classifier executed by each required job comes from the
  PR base commit, not from the PR workspace.
- Keep the detector CLI compatible with Slice 18:
  `--base SHA --head SHA [--github-output FILE]`.
- Keep docs-only PRs on the lightweight path when the diff is truly limited to
  `docs/**` and `**/*.md`.
- Make `.github/workflows/**`, `.github/scripts/**`, Swift source, tests,
  package metadata, and all other non-doc paths ineligible for the lightweight
  path.
- Fail closed when classification cannot prove a non-empty docs-only PR diff.
- Preserve the `push` docs-only `paths-ignore` behavior, because PR required
  checks are the merge gate.
- Update `AGENTS.md` so the operational guide records the trusted-base detector
  boundary accurately.
- Record local and hosted evidence, including a docs-only PR proof after the
  trusted detector path is available on `main`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No benchmark budget changes.
- No promotion of `--variable-height-mutation` to a hosted blocking gate.
- No cross-target provider coverage expansion.
- No ruleset mutation; Slice 18 already configured the required contexts.
- No new required GitHub check context.
- No `pull_request_target` workflow that checks out or builds PR code.
- No GitHub App, external service, third-party action, or API-based status
  aggregator.
- No removal of admin bypass actors.
- No destructive merge-rejection test.

## Decisions

### Decision 1 - Keep the existing required job contexts

Slice 19 keeps the repository policy shape created by Slice 18. The active
ruleset should still require the three Swift CI job contexts listed above with
strict required-status-check policy.

Changing the ruleset to require an aggregate trusted status is rejected for this
slice because it would add asynchronous status-writing behavior and move merge
policy away from the concrete jobs that already carry the brief's test,
benchmark, iOS, and WASM proof.

### Decision 2 - Run the classifier from the base commit

Each required job will materialize the PR base commit outside the PR workspace
with `git worktree`, for example:

```text
git worktree add --detach "$RUNNER_TEMP/trusted-ci" "$BASE_SHA"
```

The job will execute:

```text
$RUNNER_TEMP/trusted-ci/.github/scripts/detect-docs-only-pr.sh
```

instead of:

```text
./.github/scripts/detect-docs-only-pr.sh
```

The detector still reads Git metadata from the PR workspace and compares
`BASE_SHA...HEAD_SHA`, but the executable code deciding `docs_only_pr` comes
from the base tree.

This is intentionally specified as `git worktree` or an equivalent Git
materialization outside the PR workspace. The implementation must not rely on
`actions/checkout` with `path: $RUNNER_TEMP/trusted-ci`, because
`actions/checkout` treats `path` as relative to `$GITHUB_WORKSPACE`, which would
place the trusted tree under the PR workspace.

This preserves the current three-job flow and avoids using `pull_request_target`
to build or test PR code.

### Decision 3 - Keep detector CLI compatibility

The detector keeps the current Slice 18 command-line contract:

```text
detect-docs-only-pr.sh --base SHA --head SHA [--github-output FILE]
detect-docs-only-pr.sh --self-test
```

Keeping this interface is important for bootstrapping Slice 19. While the Slice
19 PR is running, the trusted helper checked out from `main` is still the Slice
18 version. The workflow changes must therefore be able to call the base helper
successfully.

Internal detector behavior can tighten, but the public helper interface should
remain compatible.

### Decision 4 - Empty runtime diffs fail closed

Slice 18's pure classifier self-test treats empty input as docs-only. Slice 19
tightens real `--base/--head` runs: if `git diff --name-only BASE...HEAD`
returns no changed paths for a PR classification, the detector should report an
infrastructure failure instead of emitting `docs_only_pr=true`.

Reason: a non-empty docs-only diff is the proof that the lightweight path is
safe. An empty runtime diff can come from stale event data, an unexpected
merge-base state, a fetch problem, or another CI setup issue. It should not be
allowed to skip required heavy work.

The self-test may still exercise empty input as a pure unit test of
`classify_paths`, but the executable `--base/--head` path must fail closed.

### Decision 5 - Policy-sensitive paths are never docs-only

The docs-only whitelist remains narrow:

```text
docs/**
**/*.md
```

Everything else is non-doc, including:

```text
.github/workflows/**
.github/scripts/**
Sources/**
Tests/**
Package.swift
```

Therefore, PRs that modify workflow YAML, CI helpers, Swift source, tests, or
package metadata must run the heavy Swift/test/compile path.

### Decision 6 - Hosted docs-only proof is required after merge

The Slice 18 post-slice review noted that the fully docs-only hosted path was
locally tested but not separately live-proven. Slice 19 verification must record
hosted proof after the trusted detector path exists on `main`.

The preferred proof is a tiny docs-only PR that changes only a file under
`docs/**` or a Markdown-only path and shows all three required contexts complete
through the lightweight `mode=docs_only_pr ... result=success` path.

## Implementation Architecture

### Trusted Worktree

Each required job keeps the normal PR checkout with `fetch-depth: 0` so the
heavy path continues to test the PR merge tree.

Each job also materializes the base commit into a separate trusted path outside
`$GITHUB_WORKSPACE`, using Git directly from the PR workspace:

```text
git cat-file -e "${BASE_SHA}^{commit}"
rm -rf "$RUNNER_TEMP/trusted-ci"
git worktree add --detach "$RUNNER_TEMP/trusted-ci" "$BASE_SHA"
```

`BASE_SHA` must come from `github.event.pull_request.base.sha`. The job must
fail if the base commit cannot be resolved, the worktree cannot be created, or
the trusted worktree does not contain the detector helper.

An equivalent Git materialization outside the PR workspace is acceptable, but
`actions/checkout path:` is not acceptable for this trusted tree because the
action resolves `path` under `$GITHUB_WORKSPACE`.

### Change-Scope Step

The `Detect PR change scope` step keeps its non-PR behavior:

```text
docs_only_pr=false
mode=docs_only_pr event=<event> result=not_pull_request docs_only_pr=false
```

For PRs, the step:

1. marks the PR workspace as a Git safe directory;
2. verifies `BASE_SHA` and `HEAD_SHA` are present;
3. verifies the trusted detector file exists and is executable or runnable by
   `bash`;
4. invokes the trusted detector with the existing CLI;
5. lets detector failures fail the job.

The step must not invoke `./.github/scripts/detect-docs-only-pr.sh` from the PR
workspace.

### Detector Helper

The detector stays Bash-only and dependency-free. It keeps:

- `--self-test`;
- path whitelist logic;
- Git commit availability checks;
- `$GITHUB_OUTPUT` support;
- stable `mode=docs_only_pr` output lines.

Slice 19 adds runtime empty-diff failure on the executable `--base/--head` path.

### Documentation

`AGENTS.md` should describe the updated CI trust boundary:

- required PR jobs still emit the three Swift CI contexts;
- docs-only PRs use a lightweight success path;
- the classifier is executed from the base commit/trusted worktree;
- PR-owned workflow/helper changes are not docs-only and must run heavy checks;
- docs-only pushes to `main` may still be skipped through `push.paths-ignore`;
- bypass-capable actors can still override the ruleset.

## Testing And Verification

### Local Checks

The implementation plan should require:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test
bash -n .github/scripts/detect-docs-only-pr.sh
rg -n "Foundation" Sources/TextEngineCore
```

It should also include workflow-shape checks proving:

- no `pull_request.paths-ignore`;
- `push.paths-ignore` remains;
- all three jobs still have the same names;
- all three jobs create a trusted base worktree before classification;
- all three jobs invoke the detector from the trusted worktree path;
- no job invokes `./.github/scripts/detect-docs-only-pr.sh` from the PR
  workspace.

Detector scenario checks should cover:

- docs-only diff -> `docs_only_pr=true`;
- mixed docs + source diff -> `docs_only_pr=false`;
- workflow/helper diff -> `docs_only_pr=false`;
- empty runtime diff -> infrastructure failure;
- missing base/head commit -> infrastructure failure.

Because this slice does not change Swift source, tests, benchmarks, package
metadata, or benchmark budgets, full local `swift test`, release build, and
benchmark commands are not required locally. Hosted non-doc PR CI must still run
the heavy path before merge.

### Hosted Checks

Before merge, the Slice 19 PR should record a final PR-head Swift CI run where
the heavy path executes for all three required jobs and succeeds. This proves
that trusted classification does not accidentally skip a non-doc workflow/helper
PR.

After merge, verification should record:

- post-merge push run for the Slice 19 merge commit;
- live ruleset readback showing the same three strict required contexts;
- a small docs-only PR run proving the trusted lightweight path emits all three
  required contexts successfully.

### Scope Proof

Verification should record that Slice 19 does not change Swift source or package
metadata:

```bash
git diff --name-only <base>...<head> -- Sources Tests Package.swift
```

Expected output: empty.

## Risks And Mitigations

### Base-helper bootstrap

The Slice 19 PR will execute the detector from the current `main` base commit.
The workflow changes must therefore call the existing helper CLI, not a new
required flag added only in the PR.

Mitigation: keep the helper interface compatible and test the new workflow shape
against the current base helper behavior before merge.

### Duplicate checkouts add workflow complexity

Each required job gains a second checkout. That is small overhead compared with
the heavy Swift work and still cheaper than running macOS/iOS compile for every
docs-only PR.

Mitigation: keep the trusted worktree step identical across jobs and verify the
shape with grep/structural checks.

### Workflow YAML changes remain policy-sensitive

This slice prevents PR-owned helper code from deciding the docs-only shortcut.
It does not introduce a broader repository policy for all future workflow
changes.

Mitigation: classify `.github/workflows/**` and `.github/scripts/**` as non-doc
so those PRs do not take the lightweight path, and record the remaining bypass
actor caveat in `AGENTS.md`.

## Acceptance Criteria

- A PR cannot get `docs_only_pr=true` by modifying
  `.github/scripts/detect-docs-only-pr.sh` in the PR workspace.
- A PR touching `.github/workflows/**` or `.github/scripts/**` runs heavy Swift
  CI instead of the lightweight docs-only path.
- A truly docs-only PR still emits all three required job contexts successfully
  without running heavy Swift/test/compile steps.
- The three required status contexts remain unchanged.
- The detector fails closed on missing commits, diff failure, and empty runtime
  PR diffs.
- `AGENTS.md` describes the trusted-base docs-only classifier accurately.
- Verification records local detector/workflow checks, hosted non-doc PR proof,
  post-merge proof, live ruleset readback, and a hosted docs-only PR proof.
