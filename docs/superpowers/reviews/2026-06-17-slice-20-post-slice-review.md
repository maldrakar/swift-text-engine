# Slice 20 Post-Slice Review

Date: 2026-06-17

## Scope Reviewed

This review covers Slice 20: policy-sensitive Markdown path hardening for the
trusted docs-only required-check gate.

The slice was delivered through:

- PR #23 (`slice-20-policy-sensitive-markdown-hardening`), merged to `main` as
  `ba4a77c1a8733e1996313df7552ab1b8437aafc0`
  (`Merge pull request #23 from maldrakar/slice-20-policy-sensitive-markdown-hardening`);
- PR #24 (`slice-20-verification-followup`), merged to `main` as
  `fe6e5c2d4e61c0389c0a1e6a76442e83a5c20881`
  (`Merge pull request #24 from maldrakar/slice-20-verification-followup`).

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-17-policy-sensitive-markdown-path-hardening-design.md`
- `docs/superpowers/plans/2026-06-17-policy-sensitive-markdown-path-hardening.md`
- `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md`
- `docs/superpowers/reviews/2026-06-17-slice-19-post-slice-review.md`
- `.github/scripts/detect-docs-only-pr.sh`
- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- PR metadata, hosted run evidence, ruleset readback, and merged Slice 20 diff

The behavioral Slice 20 review range starts after the Slice 19 review artifact
commit in PR #23:

```text
553073200ad43aa8277f7a476ee23765ccae1adb..fe6e5c2d4e61c0389c0a1e6a76442e83a5c20881
```

The full merged PR #23 also includes
`docs/superpowers/reviews/2026-06-17-slice-19-post-slice-review.md`, which is
prior-slice input context rather than a Slice 20 behavior change.

This is a workflow-helper, repository-policy documentation, and verification
slice. It deliberately leaves `Sources/**`, `Tests/**`, `Package.swift`,
benchmark modes, benchmark budgets, workflow topology, job names, and ruleset
settings unchanged.

Review used the code-review-team flow with independent reviewer lenses:
`architect-reviewer`, `code-reviewer`, `code-simplifier`,
`fullstack-developer`, `qa-expert`, and `security-auditor`.

## Product Brief Alignment

Slice 20 continues the governance path from Slices 18 and 19: the brief's
regression tests, benchmark gates, and cross-target compile checks must remain
meaningful at merge time. The slice does not change the headless text engine,
provider boundary, public API, layout math, benchmark budgets, or source-level
portability surface.

The confirmed Slice 19 P2 is closed. Markdown files under
`.github/workflows/**` and `.github/scripts/**` are now classified as non-doc
before the generic Markdown allow rule, so those policy-sensitive paths take
the heavy Swift CI path even when the changed files end in `.md`.

## Delivered Design

Merged Slice 20 behavior diff (`5530732..fe6e5c2`):

```text
 .github/scripts/detect-docs-only-pr.sh             |   21 +-
 AGENTS.md                                          |   18 +-
 ...-17-policy-sensitive-markdown-path-hardening.md | 1281 ++++++++++++++++++++
 ...icy-sensitive-markdown-path-hardening-design.md |  361 ++++++
 ...-17-policy-sensitive-markdown-path-hardening.md | 1000 +++++++++++++++
 5 files changed, 2672 insertions(+), 9 deletions(-)
```

### Detector Hardening

`.github/scripts/detect-docs-only-pr.sh` now rejects policy-sensitive GitHub
workflow/helper directories before applying the generic Markdown allow rule:

```bash
is_docs_only_path() {
  local path="$1"
  case "$path" in
    .github/workflows/*|.github/scripts/*) return 1 ;;
    docs/*|*.md) return 0 ;;
    *) return 1 ;;
  esac
}
```

The helper keeps the Slice 19 CLI and output contract:

```text
detect-docs-only-pr.sh --base SHA --head SHA [--github-output FILE]
detect-docs-only-pr.sh --self-test
```

The self-test now covers both direct path classification and runtime Git diff
classification for:

```text
.github/workflows/README.md
.github/scripts/README.md
```

Both runtime cases expect `docs_only_pr=false`. Existing true docs-only cases
for `docs/**` and root Markdown remain covered.

### Workflow Topology

`.github/workflows/swift-ci.yml` was not changed in Slice 20. The Slice 19
trusted-base execution model remains intact:

- each required PR job materializes the PR base commit into
  `$RUNNER_TEMP/trusted-ci`;
- each job invokes the detector from that trusted base tree;
- the detector compares the full `BASE_SHA...HEAD_SHA` diff from Git metadata;
- PR-owned detector code still does not decide whether heavy Swift work runs.

The three required job names remain:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

### Documentation And Evidence

`AGENTS.md` now states the deny-first exception explicitly: files under
`.github/workflows/**` and `.github/scripts/**` are not docs-only regardless of
extension. The verification record includes local red/green proof, hosted
PR-head heavy-path proof, post-merge proof, ruleset readback, a hosted
policy-sensitive Markdown proof PR, and a hosted true-docs-only proof PR.

## Verification Evidence Reviewed

Fresh local checks during this review:

- `./.github/scripts/detect-docs-only-pr.sh --self-test` -> `self_test=pass`
- `bash -n .github/scripts/detect-docs-only-pr.sh` -> no output
- `git diff --check 5530732..HEAD` -> no output
- `rg -n "Foundation" Sources/TextEngineCore` -> no matches, exit status `1`
- `git diff --name-only 5530732..HEAD -- Sources Tests Package.swift` -> no
  output
- `git diff --name-only 5530732..HEAD -- .github/workflows/swift-ci.yml` -> no
  output

Live PR and run evidence checked during this review:

- PR #23 merged, final head `18118f9c350e832ae493a27da0c342f611021f19`,
  merge commit `ba4a77c1a8733e1996313df7552ab1b8437aafc0`.
- PR #23 final Swift CI run `27704299872`:
  - all three required jobs `success`;
  - `Complete docs-only PR` was skipped in all three jobs;
  - hosted jobs ran host tests, synthetic benchmark gate, variable-height
    benchmark gate, iOS cross-target compile, and WASM observation.
- Post-merge push run `27705132073` on merge commit `ba4a77c...`:
  - all three required jobs `success`;
  - heavy Swift/test/compile/observation steps ran.
- Policy-sensitive Markdown proof PR #25:
  - changed only `.github/scripts/README.md` and
    `.github/workflows/README.md`;
  - run `27706101669` completed with all three required jobs `success`;
  - hosted logs contain heavy Swift/test/compile markers;
  - hosted logs contain no docs-only shortcut success marker.
- True docs-only proof PR #26:
  - changed only a file under `docs/superpowers/verification/**`;
  - run `27706623092` completed with all three required jobs `success`;
  - hosted logs contain docs-only shortcut success markers for all three jobs;
  - hosted logs contain no heavy Swift/test/compile markers.
- PR #24 verification follow-up:
  - head `bddbd114d78df0a84dd039b860b2cceaf8b824cb`;
  - run `27707709614` completed with all three required jobs `success`;
  - the PR was docs-only and correctly used the lightweight required-context
    path.

No post-merge push run exists for `fe6e5c2` in the recent `main` Swift CI run
list. That is consistent with the documented `push.paths-ignore` behavior for
docs-only pushes to `main`; PR required checks remain the merge gate.

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

Reviewed non-merge Slice 20 commits:

```text
0f09fb2 docs: design policy-sensitive markdown hardening
3aeb525 docs: plan policy-sensitive markdown hardening
e9f5b89 ci: harden policy-sensitive docs classification
3bc3d97 docs: clarify policy-sensitive markdown classification
1df7155 docs: record policy-sensitive markdown verification
d589277 docs: expand policy-sensitive markdown command evidence
2bbbe09 docs: clarify red proof provenance
09a6af8 docs: record policy-sensitive markdown PR proof
18118f9 docs: record policy-sensitive markdown PR refresh proof
41d5d77 docs: record policy-sensitive markdown post-merge proof
d87bc22 docs: record policy-sensitive markdown hosted proof
bddbd11 docs: expand hosted proof provenance
```

The commits are bisectable by concern: design, plan, detector behavior,
durable guidance, local verification, PR-head proof, post-merge proof, hosted
proof PRs, and evidence provenance cleanup.

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix

None.

### P2 / Important Production Readiness

None.

### P3 / Minor But Valid

None.

All six independent reviewer lenses returned no production-relevant findings.
The prior Slice 19 P2 was specifically re-checked and is closed by the
deny-first detector rule plus direct and runtime self-test coverage.

## Risks And Gaps

### Bypass Actors Remain

The active ruleset still has one bypass actor shape:

```text
actor_id=5 actor_type=RepositoryRole bypass_mode=always
```

This remains an explicit repository-policy caveat, not a Slice 20 regression.
Required checks are configured and enforced for normal PR flow, while
bypass-capable actors can still override them.

### WASM Remains Observational

The required `WASM cross-target observation` context is emitted and green, but
the helper still records WASM and embedded WASM as non-blocking when a matching
Swift SDK is unavailable. This is existing documented CI semantics, not a
Slice 20 defect.

### Docs-Only Pushes To `main` May Skip Swift CI

PR #24 demonstrates this boundary: the PR had the three required contexts, but
the follow-up merge commit did not produce a new `push` Swift CI run in the
recent run list. That matches the documented `push.paths-ignore` rule. For
source or workflow/helper changes, the PR required checks remain the important
merge-time proof.

### Variable-Height Mutation Is Still Observational In Hosted CI

`--variable-height-mutation` runs in the host job as an observation, not as a
blocking hosted gate. Slice 20 intentionally did not promote it; this remains
the strongest next governance candidate now that the docs-only trust boundary
and policy-sensitive Markdown gap are closed.

## Lessons For The Next Slice

1. The trusted docs-only gate now has two hosted proof paths: policy-sensitive
   Markdown takes heavy CI, and true docs-only changes still emit required
   contexts through the lightweight path.
2. Deny-first classification is the right shape for policy-sensitive
   directories. Broad file-extension allow rules must come after directory
   policy.
3. Verification evidence should distinguish PR-head proof, post-merge proof,
   and proof PRs. Slice 20's follow-up clarified that provenance.
4. Governance work can now move back from skip-boundary hardening to gate
   strength, because the required contexts are less vulnerable to accidental or
   PR-controlled shortcuts.

## Slice 21 Candidate Options

### Option A: Promote `--variable-height-mutation` To A Hosted Blocking Gate

Use the existing mutation benchmark mode and hosted observation evidence to
turn mutation regression detection into a blocking host-job gate. This should
include Linux-hosted evidence before any budget retune.

### Option B: Cross-Target Provider Coverage

Extend cross-target compile coverage to `TextEngineReferenceProviders` if that
target is now considered a supported portable product rather than only a
reference/benchmark support library.

### Option C: Line Insert/Delete Provider Design

Design dynamic `lineCount` changes. This is a larger functional provider step
than height mutation because the current Fenwick array does not cheaply support
mid-document insert/delete.

### Option D: Ruleset Bypass Policy Review

Decide whether the existing bypass actor shape is acceptable long-term. This is
a repository-policy slice, not a code or CI-helper slice, and should be kept
separate from benchmark or provider work.

## Recommended Slice 21 Selection

Recommended: **Option A, promote `--variable-height-mutation` to a hosted
blocking gate.** Slice 20 closes the remaining docs-only policy-sensitive path
gap from Slice 19. The next highest-value governance step is making the
mutation benchmark enforce regressions at the same required-check layer as the
synthetic and variable-height gates.

Choose Option B next only if the reference-provider portability contract is
more urgent than mutation-regression enforcement.

## Slice 20 Review Conclusion

Slice 20 delivered the requested policy-sensitive Markdown hardening. The
detector now rejects `.github/workflows/**` and `.github/scripts/**` before the
generic Markdown allow rule; workflow topology and required job names stayed
unchanged; true docs-only behavior is still proven; policy-sensitive Markdown
is proven to run heavy CI; and the verification artifact now records the
evidence provenance clearly.

The review is clean: no P0, P1, P2, or P3 findings were confirmed. The slice is
ready to stand as the closure of the Slice 19 policy-sensitive Markdown gap.
