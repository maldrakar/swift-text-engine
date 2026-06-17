# Slice 19 Post-Slice Review

Date: 2026-06-17

## Scope Reviewed

This review covers Slice 19: trusted docs-only required-check gate. The slice
was delivered through:

- PR #20 (`slice-19-trusted-docs-only-gate`), merged to `main` as
  `f84651f2d1d5e664d8d420607448d8756a278b5a`
  (`Merge pull request #20 from maldrakar/slice-19-trusted-docs-only-gate`);
- PR #21 (`slice-19-docs-only-proof`), merged as
  `90cd0ca35e556d7d0b2e1990b2117dc0ef5a9b9e`;
- PR #22 (`slice-19-verification-followup`), merged as
  `b6c444b09ac27526727a07a5b51425127c8c8a05`.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-16-trusted-docs-only-gate-design.md`
- `docs/superpowers/plans/2026-06-16-trusted-docs-only-gate.md`
- `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate.md`
- `docs/superpowers/verification/2026-06-16-trusted-docs-only-gate-docs-only-proof.md`
- `docs/superpowers/reviews/2026-06-16-slice-18-post-slice-review.md`
- `.github/scripts/detect-docs-only-pr.sh`
- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- PR metadata, hosted run evidence, ruleset readback, and the merged diff
  `5358e34..b6c444b`

This is a workflow-helper, repository-policy documentation, and verification
slice. It deliberately leaves `Sources/**`, `Tests/**`, and `Package.swift`
unchanged.

Review used the code-review-team flow with independent reviewer lenses:
`architect-reviewer`, `code-reviewer`, `code-simplifier`,
`fullstack-developer`, `qa-expert`, and `security-auditor`.

## Product Brief Alignment

Slice 19 continues the governance work from Slice 18: the brief's regression
tests, benchmark gates, and cross-target compile checks must stay meaningful at
merge time. The slice does not change the headless text engine, provider
boundary, benchmark budgets, public API, or source-level portability surface.

The main trust-boundary defect from Slice 18 is fixed: required PR jobs no
longer execute the docs-only detector from the PR checkout. Each required job
materializes the PR base commit under `$RUNNER_TEMP/trusted-ci`, executes the
base tree's `.github/scripts/detect-docs-only-pr.sh`, and still compares the
full `BASE_SHA...HEAD_SHA` PR diff.

The implementation also tightens empty runtime diffs to fail closed and records
hosted proof for both the non-doc heavy path and the trusted docs-only
lightweight path.

## Delivered Design

Merged Slice 19 diff (`5358e34..b6c444b`):

```text
 .github/scripts/detect-docs-only-pr.sh             |   93 ++
 .github/workflows/swift-ci.yml                     |   81 +-
 AGENTS.md                                          |   19 +-
 .../plans/2026-06-16-trusted-docs-only-gate.md     | 1075 ++++++++++++++++++++
 .../2026-06-16-trusted-docs-only-gate-design.md    |  393 +++++++
 ...06-16-trusted-docs-only-gate-docs-only-proof.md |    9 +
 .../2026-06-16-trusted-docs-only-gate.md           |  593 +++++++++++
 7 files changed, 2254 insertions(+), 9 deletions(-)
```

### Detector Hardening

`.github/scripts/detect-docs-only-pr.sh` keeps the Slice 18 CLI:

```text
detect-docs-only-pr.sh --base SHA --head SHA [--github-output FILE]
detect-docs-only-pr.sh --self-test
```

The real `--base/--head` path now fails closed on empty diffs with:

```text
mode=docs_only_pr result=infrastructure_failure reason=empty_diff docs_only_pr=false
```

The self-test now creates a temporary Git repository and verifies runtime
classification for docs-only, mixed source, workflow YAML, helper script,
missing-base, and empty-diff scenarios.

### Workflow Trust Boundary

Each required job in `.github/workflows/swift-ci.yml` now runs the same trusted
classification shape:

- validate pull-request base/head SHAs;
- mark the PR workspace as a safe Git directory for metadata reads;
- prove both commits exist;
- create `$RUNNER_TEMP/trusted-ci` from the base SHA with `git worktree`;
- verify the trusted detector exists in that base tree;
- invoke `bash "$trusted_detector" --base "$BASE_SHA" --head "$HEAD_SHA"
  --github-output "$GITHUB_OUTPUT"`.

The three required job names are unchanged:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

The workflow still uses `pull_request`, not `pull_request_target`, and keeps
`push.paths-ignore` for docs-only pushes to `main`.

### Documentation And Evidence

`AGENTS.md` now records the trusted-base detector boundary, fail-closed runtime
classification, policy-sensitive non-doc paths, unchanged required contexts, and
the bypass-actor caveat.

The verification record includes local red/green evidence, PR-head heavy hosted
proof, post-merge push proof, live ruleset readback, and a hosted docs-only proof
PR.

## Verification Evidence Reviewed

Fresh local checks during this review:

- `./.github/scripts/detect-docs-only-pr.sh --self-test` -> `self_test=pass`
- `bash -n .github/scripts/detect-docs-only-pr.sh` -> no output
- `git diff --check 5358e34..HEAD` -> no output
- `rg -n "Foundation" Sources/TextEngineCore` -> no matches, exit status `1`
- `git diff --name-only 5358e34..HEAD -- Sources Tests Package.swift` -> no
  output
- workflow inspection -> three trusted worktree additions, three trusted
  detector invocations, no `pull_request_target`, and no PR-workspace detector
  invocation

Live PR and run evidence checked during this review:

- PR #20 merged, head `d8880575707f13e87282eddb4cd2543811972a7e`, merge commit
  `f84651f2d1d5e664d8d420607448d8756a278b5a`.
- PR #20 final Swift CI run `27651866440`:
  - all three required jobs `success`;
  - hosted log contains `Run host tests`, `Run synthetic benchmark gate`,
    `Compile TextEngineCore for iOS targets`, and
    `Observe TextEngineCore for WASM targets`;
  - hosted log contains no `mode=docs_only_pr ... result=success` shortcut.
- Post-merge push run `27652542887` on merge commit `f84651f...`:
  - all three required jobs `success`.
- Docs-only proof PR #21 run `27652778010`:
  - all three required jobs `success`;
  - hosted log contains all three `mode=docs_only_pr ... result=success`
    markers;
  - hosted log contains no heavy Swift/test/compile step markers.
- Verification follow-up PR #22 run `27687908943`:
  - all three required jobs `success`;
  - hosted log contains all three trusted docs-only success markers.

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

## Git History

Reviewed non-merge Slice 19 commits:

```text
8a26a93 docs: design trusted docs-only gate
91876e4 docs: specify trusted docs-only worktree
0c2888c ci: fail closed on empty docs-only diffs
dd5d996 ci: run docs-only detector from trusted base
bab8847 docs: document trusted docs-only gate
a553f1e docs: record trusted docs-only gate verification
26aa3e6 docs: record trusted docs-only gate PR evidence
d888057 docs: refresh trusted docs-only gate PR evidence
105d756 docs: add trusted docs-only gate proof
47d9aab docs: record trusted docs-only gate hosted proof
25a8d40 docs: fix trusted docs-only gate follow-up proof
```

PR #22 includes merge commit `8750410` from `origin/main` into the follow-up
branch before the final merge to `main`.

The commits are bisectable by concern: design, workflow-helper behavior,
workflow trust-boundary wiring, durable guidance, verification evidence, and
docs-only proof artifacts.

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix

None.

### P2 / Important Production Readiness

#### P2 - Markdown under policy-sensitive `.github` paths still takes the docs-only shortcut

Files:

- `docs/superpowers/specs/2026-06-16-trusted-docs-only-gate-design.md:384`
- `.github/scripts/detect-docs-only-pr.sh:83`
- `AGENTS.md:129`

Slice 19's acceptance criteria state:

```text
- A PR touching `.github/workflows/**` or `.github/scripts/**` runs heavy Swift
  CI instead of the lightweight docs-only path.
```

`AGENTS.md` now records the same contract: PR-owned workflow/helper changes under
`.github/workflows/**` or `.github/scripts/**` are not docs-only and must run
the heavy path.

The detector still accepts every Markdown file through the generic `*.md`
whitelist:

```bash
is_docs_only_path() {
  local path="$1"
  case "$path" in
    docs/*|*.md) return 0 ;;
    *) return 1 ;;
  esac
}
```

Fresh fact-check during this review created a temporary repository where the PR
diff touched only:

```text
.github/scripts/README.md
.github/workflows/README.md
```

The current trusted detector classified that diff as docs-only:

```text
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
detector_status=0
```

Production impact: changes under CI policy directories with Markdown filenames
can emit the required Swift CI contexts through the lightweight docs-only path,
contrary to the documented Slice 19 merge-gate contract. This is narrower than
the Slice 18 PR-owned executable-code bypass, but it leaves the
policy-sensitive path rule incomplete.

Verifier evidence:

- `.github/scripts/detect-docs-only-pr.sh:83-88` matches `*.md` before any
  policy-sensitive path exclusion exists.
- `docs/superpowers/specs/2026-06-16-trusted-docs-only-gate-design.md:380-390`
  requires `.github/workflows/**` and `.github/scripts/**` to run heavy CI.
- `AGENTS.md:120-133` documents the same operational rule.
- Temporary runtime reproduction returned `docs_only_pr=true` for Markdown files
  under both policy-sensitive directories.

Suggested fix: make `is_docs_only_path` reject `.github/workflows/*` and
`.github/scripts/*` before the generic `*.md` case, then add self-test/runtime
cases for `.github/workflows/README.md` and `.github/scripts/README.md`
expecting `docs_only_pr=false`.

Source agents: `fullstack-developer`, `qa-expert`, `security-auditor`.

### P3 / Minor But Valid

None.

Two candidates were reviewed and rejected:

- The repeated trusted change-scope shell block in the three required jobs is
  real duplication, but it is tied to preserving three separate required job
  contexts and the trusted-base bootstrap. No reviewer showed a simpler
  same-trust-boundary structure with non-speculative production impact.
- The verification artifact does not record PR #22's own docs-only run. That
  follow-up run is now recorded by this post-slice review; requiring the
  verification artifact to record the CI run of the PR that updates the
  verification artifact would create an unnecessary recursive follow-up.

## Risks And Gaps

### Policy-Sensitive Markdown Gap

The trusted-base execution model is sound, but the path whitelist still has a
documented-contract gap for Markdown files under `.github/workflows/**` and
`.github/scripts/**`. This should be closed before using the trusted docs-only
gate as the foundation for additional policy-sensitive CI work.

### Bypass Actors Remain

The active ruleset still has one bypass actor shape:

```text
actor_id=5 actor_type=RepositoryRole bypass_mode=always
```

This remains an explicit repository-policy caveat, not a Slice 19 regression.
Required checks are enforced for normal PR flow, while bypass-capable actors can
still override them.

### WASM Remains Observational

The required `WASM cross-target observation` context is emitted and green, but
the helper still records WASM and embedded WASM as non-blocking when a matching
Swift SDK is unavailable. This is existing documented CI semantics, not a Slice
19 defect.

## Lessons For The Next Slice

1. The Slice 18 trust-boundary defect is substantially closed: PR-owned detector
   code no longer decides whether heavy required jobs run.
2. Required job contexts can now prove both paths: non-doc workflow/helper PRs
   run heavy CI, while true docs-only PRs emit the same contexts through the
   lightweight trusted path.
3. Path whitelists need explicit deny-first handling for policy-sensitive
   directories. A broad `*.md` allow rule is too permissive when some directories
   are categorically non-doc for merge-policy purposes.
4. The verification trail is stronger after Slice 19: it includes red/green
   detector proof, workflow-shape proof, PR-head heavy run, post-merge push run,
   ruleset readback, and hosted docs-only proof.

## Slice 20 Candidate Options

### Option A: Policy-Sensitive Markdown Path Hardening

Close the residual `.github/**/*.md` gap by rejecting `.github/workflows/**` and
`.github/scripts/**` before the Markdown whitelist, add runtime self-test
coverage for Markdown under both directories, update the verification record,
and prove a non-doc PR still takes the heavy path.

### Option B: Promote `--variable-height-mutation` To A Hosted Blocking Gate

Use the existing hosted observation and local gate headroom to promote mutation
benchmark regression detection into the host job's blocking path.

### Option C: Cross-Target Provider Coverage

Extend cross-target compile coverage to `TextEngineReferenceProviders` if that
target is now considered a supported portable product rather than only a
reference/benchmark support library.

### Option D: Line Insert/Delete Provider Design

Design dynamic `lineCount` changes. This is a larger functional provider step
than height mutation because the current Fenwick array does not cheaply support
mid-document insert/delete.

## Recommended Slice 20 Selection

Recommended: **Option A, policy-sensitive Markdown path hardening.** Slice 19
fixed the major PR-owned detector-code trust flaw, but the documented
`.github/workflows/**` / `.github/scripts/**` heavy-path guarantee still has a
Markdown filename hole. Close that narrow policy gap before promoting more gates
or extending portability coverage.

After Option A is fixed and verified, Option B is the strongest next governance
candidate.

## Slice 19 Review Conclusion

Slice 19 delivered the trusted-base detector execution model, fail-closed empty
runtime diffs, unchanged required contexts, local red/green proof, hosted
non-doc heavy proof, post-merge proof, and hosted docs-only proof. It also kept
Swift source, tests, package metadata, benchmark modes, and benchmark budgets
out of scope.

The review is not completely clean: there is one confirmed P2 finding. Markdown
files under `.github/workflows/**` or `.github/scripts/**` are still classified
as docs-only by the generic `*.md` rule, even though the Slice 19 contract says
those policy-sensitive directories must run heavy Swift CI. The next slice
should close that path-classification gap.
