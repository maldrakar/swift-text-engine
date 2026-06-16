# Slice 18 Post-Slice Review

Date: 2026-06-16

## Scope Reviewed

This review covers Slice 18: Swift CI required checks / docs-only PR policy.
It was merged through PR #18 (`slice-18-swift-ci-required-checks`) into `main`
as merge commit `d6998ded0c20c3b967bd7519905a3fce9f7c7ec7`
(`Merge pull request #18 from maldrakar/slice-18-swift-ci-required-checks`).

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-16-swift-ci-required-checks-design.md`
- `docs/superpowers/plans/2026-06-16-swift-ci-required-checks.md`
- `docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`
- `docs/superpowers/reviews/2026-06-15-slice-17-post-slice-review.md`
- `AGENTS.md` / `CLAUDE.md` as current repository conventions
- PR #18 metadata, final PR-head hosted run, merge commit, post-merge push run,
  and live GitHub ruleset readback
- Slice 18 diff (`641755d..c5b7f53`)
- Fresh local workflow/helper checks and Foundation-free scan
- GitHub Actions `pull_request` event documentation for merge-branch checkout
  semantics:
  <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request>

This is a policy/workflow/documentation slice. It deliberately leaves
`Sources/**`, `Tests/**`, benchmark code, and `Package.swift` unchanged.

Review used the code-review-team flow with independent reviewer lenses:
`architect-reviewer`, `code-reviewer`, `code-simplifier`,
`fullstack-developer`, `qa-expert`, and `security-auditor`.

## Product Brief Alignment

Slice 18 targets the brief's governance requirement that regression benchmarks
and cross-target compile checks protect the core contract at merge time. It does
not change the headless layout engine, virtualization math, provider boundary,
or benchmark budgets.

The slice closes the old advisory-CI gap at the repository policy layer:

- active ruleset `Main` now has `required_status_checks`;
- strict required-status-check policy is enabled;
- the required contexts are exactly:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- `AGENTS.md` now describes the public repository, ruleset id, required
  contexts, docs-only PR behavior, and bypass caveat.

However, the docs-only skip path introduced by the slice is not yet a trusted
merge gate. A PR can change the helper that decides whether heavy required jobs
run. That leaves a real policy-bypass defect even though the ruleset readback is
correct.

## Delivered Design

Merged PR diff (`641755d..c5b7f53`):

```text
 .github/scripts/detect-docs-only-pr.sh             |  190 ++++
 .github/workflows/swift-ci.yml                     |   80 +-
 AGENTS.md                                          |   32 +-
 .../plans/2026-06-16-swift-ci-required-checks.md   | 1019 ++++++++++++++++++++
 .../2026-06-16-swift-ci-required-checks-design.md  |  350 +++++++
 .../2026-06-16-swift-ci-required-checks.md         |  636 ++++++++++++
 6 files changed, 2291 insertions(+), 16 deletions(-)
```

### Docs-Only Detector

`.github/scripts/detect-docs-only-pr.sh` classifies the full PR diff via
`git diff --name-only BASE...HEAD`. It treats only `docs/**` and `**/*.md` as
docs-only, writes `docs_only_pr=true|false` to `$GITHUB_OUTPUT`, and fails closed
when required commits or the diff are unavailable.

The helper includes self-tests for docs-only, mixed, empty, GitHub output, and
non-configured uppercase `.MD` behavior. Local self-test and `bash -n` pass.

### Workflow Wiring

`.github/workflows/swift-ci.yml` now starts on every PR, preserving docs-only
`paths-ignore` only for pushes to `main`. Each required job:

- checks out with `fetch-depth: 0`;
- runs `Detect PR change scope`;
- marks the workspace as a Git safe directory before the detector;
- emits a lightweight `Complete docs-only PR` success line when
  `docs_only_pr=true`;
- gates heavy Swift/test/compile work when `docs_only_pr=true`.

The hosted PR run initially reproduced a Linux container safe-directory failure,
then commit `47baa8a` fixed it by configuring `safe.directory` before invoking
the detector in each job.

### Ruleset And Docs

The existing active ruleset `Main` (`17656807`) was updated in place. Existing
conditions, non-status rules, and bypass actor shape were preserved. A new
`required_status_checks` rule was added with strict policy enabled.

`AGENTS.md` now records the three-job CI topology, required-check policy,
docs-only PR lightweight path, docs-only push skip, and bypass caveat.

## Verification Evidence Reviewed

Fresh local checks during this review:

- `./.github/scripts/detect-docs-only-pr.sh --self-test` -> `self_test=pass`
- `bash -n .github/scripts/detect-docs-only-pr.sh` -> no output
- `git diff --check 641755d..c5b7f53` -> no output
- `rg -n "Foundation" Sources/TextEngineCore` -> no matches
- `git diff --name-only 641755d..c5b7f53 -- Sources Tests Package.swift` ->
  no output

Live ruleset readback during this review:

```json
{
  "id": 17656807,
  "name": "Main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "exclude": [],
      "include": ["~DEFAULT_BRANCH"]
    }
  },
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ],
  "required_status_checks": [
    "Host tests and benchmark gate",
    "iOS cross-target compile",
    "WASM cross-target observation"
  ],
  "strict_required_status_checks_policy": true
}
```

Final PR-head run:

- PR #18 final head `c5b7f531184ed2d4348b031115788074cd407a45`
- run `27635972517`
- all three jobs `success`

Post-merge push run:

- merge commit `d6998ded0c20c3b967bd7519905a3fce9f7c7ec7`
- run `27638034327`
- all three jobs `success`

The verification record correctly says `swift test` and benchmark commands were
not required for Slice 18 because Swift source, benchmarks, tests, and package
metadata did not change. Hosted CI still ran the heavy jobs for the non-doc PR
and post-merge push.

## Git History

Reviewed Slice 18 commit range:

```text
87a0475 docs: design swift ci required checks
36df4c7 docs: address docs-only required check policy
868b69c ci: add docs-only PR detector
c942cde ci: keep required checks present for docs-only PRs
a38fa74 docs: document required Swift CI policy
d0051f9 docs: record Swift CI required checks verification
47baa8a ci: mark workspace safe before PR scope detection
6b8d7ec docs: record hosted Swift CI follow-up
e0e1d6d docs: track Swift CI required checks plan
c5b7f53 docs: record final Slice 18 CI evidence
d6998de Merge pull request #18 from maldrakar/slice-18-swift-ci-required-checks
```

The commits are bisectable and use conventional prefixes. The later documentation
commits refresh the evidence trail after hosted CI and plan-tracking follow-up.

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix

#### P1 - Docs-only skip is controlled by PR-owned code

File: `.github/workflows/swift-ci.yml:46`, repeated at lines `153` and `199`.

The workflow checks out the PR merge tree and then executes
`./.github/scripts/detect-docs-only-pr.sh`; that script writes the
`docs_only_pr` output used to skip all heavy work in the required jobs:

```yaml
./.github/scripts/detect-docs-only-pr.sh --base "$BASE_SHA" --head "$HEAD_SHA" --github-output "$GITHUB_OUTPUT"

- name: Complete docs-only PR
  if: steps.change-scope.outputs.docs_only_pr == 'true'
```

GitHub documents that `pull_request` workflows set `GITHUB_REF` to the PR merge
branch and `actions/checkout` checks out that merge branch by default. That means
the detector file is PR-controlled when the required job runs. A PR can modify
`.github/scripts/detect-docs-only-pr.sh` so it always writes
`docs_only_pr=true`; the required contexts then complete successfully while
tests, benchmark gates, iOS compile, and WASM observation are skipped even if the
same PR changes non-doc files.

Production impact: the ruleset now requires Swift CI contexts, but a PR can make
those contexts green without running the checks those contexts are meant to
represent. That weakens the new merge policy exactly on the path Slice 18 was
meant to harden.

Suggested fix: move docs-only classification out of PR-owned executable code.
The next slice should design a trusted gate, for example a base-context
`pull_request_target` classifier that uses the GitHub API to inspect changed
files without checking out PR code, or another base-trusted mechanism that cannot
be modified by the PR it evaluates. PRs that touch `.github/workflows/**` or
`.github/scripts/detect-docs-only-pr.sh` should never be eligible for the
docs-only lightweight path. If the existing three required job contexts remain
the merge gate, each job must consume only trusted classification output or fail
closed.

Source agents: `security-auditor`.

### P2 / Production Readiness

None.

### P3 / Minor But Valid

None.

One P3 candidate about repeated `Detect PR change scope` wrapper YAML was
reviewed and rejected. The shared helper already removes the main logic
duplication, and the remaining per-job wrapper is tied to three separate required
contexts. Without a current behavior divergence or documented local rule against
this YAML shape, it is not a production-relevant finding.

## Risks And Gaps

### Required Checks Exist, But The Skip Gate Is Not Trusted

The live ruleset is correct, strict, and currently active. The remaining problem
is the trust boundary around the docs-only exception. Until that is fixed, the
repository has required check contexts, but the exception path can be controlled
from the PR being evaluated.

### Bypass Actors Remain

This is by design for Slice 18 and is now documented in `AGENTS.md`: the current
admin user can bypass the ruleset. Required checks are configured for normal PR
flow, not as an absolute barrier for bypass-capable actors.

### Fully Docs-Only PR Path Is Locally Tested, Not Separately Live-Proven

The detector self-test covers docs-only classification, and workflow inspection
shows the lightweight success path. The hosted PR for Slice 18 was not docs-only,
so the review does not have a separate live PR run proving the all-docs shortcut.
This is less important than the P1 trust-boundary issue; once that is fixed, a
small docs-only PR should record hosted proof.

## Lessons For The Next Slice

1. Repository rulesets now encode the three Swift CI contexts, so future hosted
   gates can matter at the merge-policy layer.
2. Required status checks are only as strong as the workflow path that emits
   them. A docs-only shortcut must be evaluated by trusted code, not the PR tree.
3. The evidence trail is stronger than prior slices: the plan is checked off,
   ruleset readback is recorded, final PR-head CI is recorded, and the
   post-merge push run is recorded.
4. The old Slice 17 governance recommendation is partially closed. The next
   governance step is fixing the trusted-skip boundary, not adding more check
   contexts.

## Slice 19 Candidate Options

### Option A: Trusted Docs-Only Required-Check Gate

Redesign the docs-only exception so the classifier is not loaded from the PR
checkout. Use a base-trusted mechanism, fail closed on API/diff uncertainty, and
record a live docs-only PR run after implementation. Also make CI workflow/helper
changes ineligible for the docs-only shortcut.

### Option B: Promote `--variable-height-mutation` To A Hosted Blocking Gate

Use Slice 17's hosted observation and local gate headroom to promote mutation
benchmark regression detection into the host job's blocking path.

### Option C: Cross-Target Provider Coverage

Extend cross-target compile coverage to `TextEngineReferenceProviders` if that
target is now considered a supported portable product rather than only a
reference/benchmark support library.

### Option D: Line Insert/Delete Provider Design

Design the next functional provider step: dynamic `lineCount` changes. This is a
larger data-structure problem than height mutation because a Fenwick array does
not cheaply support mid-document insert/delete.

## Recommended Slice 19 Selection

Recommended: **Option A, trusted docs-only required-check gate.** Slice 18 added
required status checks and corrected pending-check behavior for docs-only PRs,
but the new exception path is controlled by PR-owned code. Fix that before
promoting more gates or extending provider portability coverage.

Choose Option B next only after the CI trust boundary is fixed. Otherwise a new
blocking benchmark gate can still be skipped by the same docs-only detector
trust flaw.

## Slice 18 Review Conclusion

Slice 18 delivered the intended ruleset mutation, updated durable documentation,
removed PR-level path filtering, preserved docs-only push skips, and recorded
both final PR-head and post-merge CI evidence. No Swift source, tests, benchmark
code, or package metadata changed.

The review is not clean: there is one confirmed P1 finding. The docs-only skip
decision is currently produced by a helper from the PR checkout, so the required
Swift CI contexts can be made green without running the heavy checks. The next
slice should fix that trust boundary and then record a live docs-only PR proof.
