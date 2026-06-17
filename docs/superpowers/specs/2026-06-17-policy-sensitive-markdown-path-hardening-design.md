# Policy-Sensitive Markdown Path Hardening Design

Date: 2026-06-17

## Status

Approved design direction, written for user review.

## Source Context

This is Slice 20 of SwiftTextEngine, following the Slice 19 post-slice review:

```text
docs/superpowers/reviews/2026-06-17-slice-19-post-slice-review.md
```

The project brief in `docs/initial-project-brief.md` requires the headless
`TextEngineCore` contract to be protected by regression benchmark gates and
cross-target compile checks. Slices 18 and 19 moved that protection into a
required-check policy with a trusted docs-only shortcut:

- the public repository requires these three Swift CI job contexts for PRs
  targeting `main`:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- docs-only PRs still emit those contexts through a lightweight path;
- the docs-only classifier is executed from the PR base commit under
  `$RUNNER_TEMP/trusted-ci`, not from PR-owned code;
- workflow/helper changes under `.github/workflows/**` and
  `.github/scripts/**` are documented as policy-sensitive and must run the
  heavy Swift/test/compile path.

Slice 19 closed the major trust-boundary defect, but its post-slice review found
one confirmed P2 gap: the detector's generic Markdown allow rule still
classifies Markdown files under policy-sensitive `.github` directories as
docs-only.

Current detector logic:

```bash
is_docs_only_path() {
  local path="$1"
  case "$path" in
    docs/*|*.md) return 0 ;;
    *) return 1 ;;
  esac
}
```

Because Bash `case` pattern `*.md` matches paths containing `/`, a diff that
touches only `.github/workflows/README.md` and `.github/scripts/README.md`
currently returns:

```text
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

That contradicts the Slice 19 acceptance criterion that any PR touching
`.github/workflows/**` or `.github/scripts/**` must run heavy Swift CI.

## Problem

The trusted-base execution model is correct, but the path classifier is too
permissive. It allows a narrow class of policy-sensitive changes to take the
lightweight docs-only path:

- `.github/workflows/README.md`
- `.github/scripts/README.md`
- any future Markdown file under those two directories

Production impact: a PR can change documentation colocated with CI workflow or
helper code and still skip the heavy Swift/test/compile path, even though the
repository guidance treats those directories as categorically non-doc for merge
policy. This is narrower than executing PR-owned helper code, but it leaves the
Slice 19 contract incomplete.

## Scope

Slice 20 hardens docs-only path classification for policy-sensitive Markdown
files.

It is a workflow-helper, documentation, and verification slice. It is expected
to modify:

- `.github/scripts/detect-docs-only-pr.sh`
- `AGENTS.md`
- `docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md`

It will not change Swift source, public API, provider code, benchmark modes,
benchmark budgets, package metadata, required GitHub status contexts, or the
trusted-base workflow topology.

## Goals

- Classify `.github/workflows/**` and `.github/scripts/**` as non-doc before
  applying the generic Markdown allow rule.
- Keep the detector CLI compatible:
  `--base SHA --head SHA [--github-output FILE]` and `--self-test`.
- Preserve the trusted-base execution boundary introduced in Slice 19.
- Preserve lightweight docs-only behavior for true docs-only changes under
  `docs/**` and Markdown files outside policy-sensitive directories.
- Add self-test coverage for policy-sensitive Markdown at both path-helper and
  runtime Git diff levels.
- Update `AGENTS.md` so it no longer reads as if every `**/*.md` path is
  eligible for the lightweight path.
- Record local red/green evidence and hosted proof that the policy-sensitive
  Markdown path takes heavy CI after the fix is available on `main`.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No benchmark budget changes.
- No promotion of `--variable-height-mutation` to a hosted blocking gate.
- No cross-target provider coverage expansion.
- No ruleset mutation.
- No new required GitHub check context.
- No workflow job rename.
- No `pull_request_target` migration.
- No broader docs classifier redesign beyond the two policy-sensitive
  directories.
- No new third-party action, dependency, or status aggregator.
- No removal of bypass actors.

## Decisions

### Decision 1 - Use deny-first classification in the detector

`is_docs_only_path` should reject policy-sensitive directories before the
generic Markdown allow rule:

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

This is the smallest change that satisfies the Slice 19 contract. It keeps the
classifier centralized in the trusted detector and avoids duplicating path
policy in all three workflow jobs.

### Decision 2 - Keep the workflow topology unchanged

The existing `.github/workflows/swift-ci.yml` shape should remain:

- `pull_request` stays unfiltered so required PR contexts are emitted;
- docs-only `paths-ignore` remains only under `push`;
- each required job executes the detector from `$RUNNER_TEMP/trusted-ci`;
- the three job names remain unchanged.

Changing workflow YAML is not necessary for this slice unless implementation
verification finds that the current workflow no longer matches the Slice 19
trusted-base design.

### Decision 3 - Test the bug before fixing it

The implementation plan must follow TDD:

1. Add direct self-test assertions proving
   `.github/workflows/README.md` and `.github/scripts/README.md` are non-doc.
2. Add runtime Git diff self-test branches for Markdown-only changes under
   `.github/workflows/**` and `.github/scripts/**`, both expecting
   `docs_only_pr=false`.
3. Run `./.github/scripts/detect-docs-only-pr.sh --self-test` and record the
   red failure.
4. Apply the deny-first classifier change.
5. Re-run self-test and record green output.

The pre-change external reproduction from this design should also be recorded
in verification:

```text
detector_status=0
mode=docs_only_pr result=docs_only docs_only_pr=true file_count=2 non_doc_count=0
```

### Decision 4 - Keep true docs-only behavior intact

The fix must not make all Markdown non-doc. These paths should continue to be
docs-only:

```text
docs/guide.md
docs/assets/diagram.png
README.md
docs/superpowers/specs/example.md
```

The existing uppercase `.MD` behavior remains unchanged: uppercase Markdown is
not currently a configured docs-only pattern.

### Decision 5 - Documentation must describe the exception precisely

`AGENTS.md` currently says that a full PR diff limited to `docs/**` or
`**/*.md` takes the lightweight path, then separately says PR-owned
workflow/helper changes are not docs-only. Slice 20 should make that wording
unambiguous:

- `docs/**` remains docs-only;
- `**/*.md` remains docs-only only outside policy-sensitive directories;
- `.github/workflows/**` and `.github/scripts/**` are deny-first and must run
  heavy CI regardless of file extension.

## Implementation Architecture

### Detector Helper

The detector remains a Bash script with no third-party dependencies. The only
behavior change is path classification order inside `is_docs_only_path`.

The helper keeps:

- `--self-test`;
- `--base SHA --head SHA [--github-output FILE]`;
- missing-base/head failure behavior;
- empty runtime diff failure behavior;
- `mode=docs_only_pr` output format;
- `$GITHUB_OUTPUT` support.

### Self-Test Coverage

Direct path-level self-tests should include:

```text
workflow_markdown_is_policy_sensitive
helper_markdown_is_policy_sensitive
```

Runtime Git diff self-tests should create Markdown-only changes under:

```text
.github/workflows/README.md
.github/scripts/README.md
```

Both runtime cases should expect:

```text
status=0
docs_only_pr=false
github_output=docs_only_pr=false
```

### Documentation

`AGENTS.md` should be updated in the CI section only. The update should not
restate the whole workflow; it should correct the docs-only classifier wording
so future agents do not reintroduce a broad `*.md` allow before
policy-sensitive denies.

### Verification Artifact

The verification record should be:

```text
docs/superpowers/verification/2026-06-17-policy-sensitive-markdown-path-hardening.md
```

It should record exact commands, outputs, and numeric exit statuses.

## Testing And Verification

### Local Checks

Required local checks:

```bash
./.github/scripts/detect-docs-only-pr.sh --self-test
bash -n .github/scripts/detect-docs-only-pr.sh
rg -n "Foundation" Sources/TextEngineCore
git diff --name-only <base>...<head> -- Sources Tests Package.swift
```

The plan should also include:

- pre-change runtime reproduction showing the policy-sensitive Markdown gap;
- red self-test output after adding failing coverage;
- green self-test output after the deny-first fix;
- workflow-shape checks proving job names and trusted detector invocation remain
  unchanged if workflow YAML is untouched;
- `git diff --check` for the slice diff.

Because this slice does not change Swift source, package metadata, benchmark
code, or workflow heavy-path commands, full local `swift test`, release build,
and benchmark commands are not required locally. Hosted CI must still run the
heavy path for the Slice 20 PR because the PR changes the detector helper.

### Hosted Checks

Before merge, verification should record the final Slice 20 PR-head Swift CI run
where all three required jobs succeed through the heavy path. The hosted logs
should contain heavy step markers such as:

```text
Run host tests
Run synthetic benchmark gate
Compile TextEngineCore for iOS targets
Observe TextEngineCore for WASM targets
```

After merge, verification should record:

- a post-merge push run for the Slice 20 merge commit;
- live ruleset readback showing the same three strict required contexts;
- a hosted policy-sensitive Markdown proof PR, based on fixed `main`, whose diff
  touches only Markdown under `.github/workflows/**` and/or
  `.github/scripts/**` and still takes the heavy path;
- a hosted true-docs-only proof PR, based on fixed `main`, showing the
  lightweight path still emits all three required contexts successfully.

Proof PRs may be closed unmerged if they exist only to produce hosted evidence.

## Risks And Mitigations

### Broad Markdown behavior regresses

Risk: changing the classifier could accidentally make normal Markdown-only PRs
run heavy CI.

Mitigation: preserve direct and runtime self-test coverage for root Markdown and
`docs/**`, and record a hosted true-docs-only proof after merge.

### Policy-sensitive proof is not visible during the Slice 20 PR

Risk: the Slice 20 PR itself changes `.github/scripts/detect-docs-only-pr.sh`,
so it will take the heavy path even before the Markdown-specific fix is present
on `main`. That does not prove Markdown-only policy-sensitive diffs are fixed.

Mitigation: create a separate hosted proof PR after merge, when the trusted base
detector includes the Slice 20 fix.

### Future policy-sensitive directories appear

Risk: more CI or repository-policy directories may later need deny-first
handling.

Mitigation: keep this slice narrow. Future directories should be added through
their own spec or through an explicit classifier policy expansion.

## Acceptance Criteria

- `is_docs_only_path .github/workflows/README.md` fails in self-test.
- `is_docs_only_path .github/scripts/README.md` fails in self-test.
- Runtime `BASE...HEAD` diff touching only policy-sensitive Markdown returns
  `docs_only_pr=false` with `non_doc_count` equal to the number of changed
  policy-sensitive files.
- Runtime true docs-only diffs still return `docs_only_pr=true`.
- Detector CLI and output shape remain compatible with Slice 19.
- The three required GitHub job contexts remain unchanged.
- Workflow trusted-base detector invocation remains unchanged.
- `AGENTS.md` accurately documents deny-first policy-sensitive directories.
- Verification records local red/green proof, shell syntax proof,
  Foundation-free scan, no Swift/package diff, PR-head heavy hosted proof,
  post-merge proof, ruleset readback, policy-sensitive Markdown hosted proof,
  and true-docs-only hosted proof.
