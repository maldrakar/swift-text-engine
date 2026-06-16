# Swift CI Required Checks Design

Date: 2026-06-16

## Status

Approved direction, written for user review.

## Source Context

This is Slice 18 of SwiftTextEngine, following the Slice 17 post-slice review.
The project brief in `docs/initial-project-brief.md` requires regression
benchmarks and cross-target compile checks to protect the headless
`TextEngineCore` contract. The repository already has a `Swift CI` workflow that
exercises those checks:

- `Host tests and benchmark gate`
- `iOS cross-target compile`
- `WASM cross-target observation`

Slice 16 moved host and WASM work to hosted Linux while keeping iOS on hosted
macOS. Slice 17 added the variable-height mutation benchmark as hosted
observation and local gate, then recorded a clean post-merge run. The remaining
governance gap is that CI success is still advisory unless GitHub repository
policy requires the relevant checks before `main` is updated.

Slice 6 previously designed a main-branch ruleset while the repository was
private and GitHub rulesets were unavailable. That design is stale in two ways:
the repository is now public, and an active ruleset already exists.

Live preflight on 2026-06-16 against `maldrakar/swift-text-engine` showed:

- repository visibility: public
- default branch: `main`
- legacy branch protection for `main`: absent
- active repository ruleset: `Main`, id `17656807`
- ruleset target: branch, condition: `~DEFAULT_BRANCH`
- rules currently present: `creation`, `update`, `deletion`,
  `non_fast_forward`, `pull_request`, and empty `required_deployments`
- rules currently absent: `required_status_checks`
- current user can bypass the ruleset through the existing bypass actor
- last relevant post-merge Swift CI run: `27533521987`, head
  `829845ed1b4eec7f4570834b003e6ab6e5963f7e`, conclusion `success`
- successful check-run names on that commit: `Host tests and benchmark gate`,
  `iOS cross-target compile`, and `WASM cross-target observation`

`AGENTS.md` is also stale: it still says the repository is private and without
branch protection / required checks. Its practical warning that a bypass actor
can update `main` remains true, but it must be described precisely rather than as
"private repo without required checks".

## Problem

The Swift CI workflow has accumulated meaningful blocking checks inside the
workflow, but GitHub does not yet require those checks at the repository-policy
layer. A pull request can show a red status, but the active `Main` ruleset does
not contain `required_status_checks`, so the policy does not encode "these Swift
CI jobs must be green".

That weakens future slices:

- benchmark gates only become merge policy when their job context is required;
- iOS compile failures are visible but not repository-required;
- `AGENTS.md` gives agents stale guidance about the repository being private;
- future post-slice reviews must keep restating the same governance caveat.

## Scope

Update repository policy and durable documentation so Swift CI checks are
repository-required for `main`.

This is an operational configuration and documentation slice. It does not change
Swift source, public API, tests, benchmarks, package metadata, or workflow YAML
unless preflight proves that the required check contexts cannot be used without a
workflow correction.

## Goals

- Reuse the existing active `Main` ruleset instead of creating a second
  overlapping ruleset.
- Add a `required_status_checks` rule with strict status-check policy.
- Require the three current Swift CI job contexts:
  - `Host tests and benchmark gate`
  - `iOS cross-target compile`
  - `WASM cross-target observation`
- Preserve the existing ruleset shape that is outside this slice's ownership:
  branch condition, PR path, non-fast-forward/deletion/update/creation rules,
  empty deployment rule, allowed merge methods, zero required approvals, and
  current bypass actors.
- Update `AGENTS.md` to describe the current public repository, active ruleset,
  required checks, docs-only CI skip behavior, and admin/bypass limitation
  accurately.
- Record verification evidence from GitHub API readback and local git state.

## Non-Goals

- No `TextEngineCore` changes.
- No `TextEngineReferenceProviders` changes.
- No benchmark budget changes.
- No promotion of `--variable-height-mutation` from observation to hosted
  blocking gate.
- No workflow topology changes.
- No hosted WASM SDK provisioning.
- No legacy branch protection changes.
- No creation of a new overlapping ruleset.
- No removal or tightening of existing bypass actors.
- No human-review, code-owner, merge-queue, signed-commit, linear-history,
  deployment, actor-restriction, force-push, or deletion-policy redesign beyond
  preserving the currently active rules.
- No destructive live merge-rejection test.

## Decisions

### Decision 1 - Reuse ruleset `Main`

The live repository already has one active default-branch ruleset named `Main`
with id `17656807`. Slice 18 updates that ruleset in place.

Creating a second ruleset such as `Swift CI required on main` is rejected because
it would duplicate policy on the same branch and make future readback harder.
The implementation must stop before mutation if the `Main` ruleset cannot be
read, no longer targets the default branch, or has changed in a way that makes an
in-place update ambiguous.

### Decision 2 - Require all three Swift CI job contexts

Slice 18 requires the three current job-level check contexts emitted by the
`Swift CI` workflow:

```text
Host tests and benchmark gate
iOS cross-target compile
WASM cross-target observation
```

Requiring only `Host tests and benchmark gate` is rejected because iOS
cross-target compile is the hosted blocking proof for the brief's iOS portability
constraint. `WASM cross-target observation` remains observational inside the job:
the helper may report WASM SDK unavailability as a non-blocking skip, but the
GitHub job itself should still complete successfully. Requiring the job context
does not promote hosted WASM target compilation to a blocking target-level
contract.

### Decision 3 - Strict status checks, no workflow-local budget duplication

The ruleset uses GitHub's strict required-status-check policy so pull requests
targeting `main` are evaluated with the latest base branch state.

The ruleset stores check contexts only. It does not duplicate benchmark budgets,
test commands, or target-specific semantics; those stay in source-controlled
workflow and benchmark files.

### Decision 4 - Preserve existing bypass actors

The current ruleset reports an existing bypass actor and
`current_user_can_bypass=always`. Slice 18 does not remove or tighten this
because that would be a separate governance decision.

`AGENTS.md` and verification must therefore say the precise truth: required
checks are configured in the active ruleset, but users with bypass rights can
still bypass the ruleset. This is stronger and more accurate than the old
"private repo without branch protection" caveat, while not overstating absolute
merge enforcement.

### Decision 5 - Documentation is part of the deliverable

`AGENTS.md` is the operational source loaded every session. The ruleset change
is incomplete unless that guide is updated at the same time. The guide should
describe:

- repository is public;
- active ruleset `Main` protects the default branch;
- required checks are the three Swift CI job contexts above;
- synthetic and variable-height gates fail the host job on regression;
- iOS device and simulator compile remain blocking inside the iOS job;
- WASM remains target-level observational inside a required job;
- docs-only skip behavior still means docs-only commits may have no fresh Swift
  CI check-runs;
- bypass rights can still override the ruleset.

## Implementation Architecture

### Preflight Inspector

Before mutating policy, implementation must read live GitHub state through
`gh api` and confirm:

- repository identity is `maldrakar/swift-text-engine`;
- repository visibility is public;
- default branch is `main`;
- `Swift CI` workflow exists and is active;
- a recent successful Swift CI run exposes the required job names;
- active ruleset `Main` id `17656807` exists and targets `~DEFAULT_BRANCH`;
- the ruleset does not already have conflicting required status checks;
- legacy branch protection on `main` is absent or, if it appears later, is
  recorded as context and not modified.

If any preflight item fails, the slice stops and records the blocker rather than
guessing or creating overlapping policy.

### Ruleset Updater

The updater performs a narrow read-modify-write on ruleset `17656807`:

- preserve existing conditions;
- preserve existing non-status rules and their parameters;
- preserve existing bypass actors;
- add or replace only the `required_status_checks` rule;
- set strict required status checks to true;
- set required status contexts to the three Swift CI job names.

The exact GitHub REST payload shape should be derived from the current readback
and GitHub API contract during implementation. The plan should include a dry
payload inspection step before the write.

### Documentation Update

Update only `AGENTS.md` for the durable operational guide. Slice 18 verification
docs should capture the command outputs and final readback, but the guide itself
should not embed volatile run IDs except as "last verified" context if useful.

## Verification

Verification should record:

- `git status --short --branch`
- repository identity and visibility readback
- active workflow readback
- recent successful Swift CI run and job names
- pre-update ruleset readback
- post-update ruleset readback proving:
  - `enforcement=active`
  - condition includes `~DEFAULT_BRANCH`
  - `pull_request` rule remains present
  - `required_status_checks` rule is present
  - strict policy is true
  - required contexts are exactly the three Swift CI job names
  - existing bypass actor shape is preserved
- `gh api repos/maldrakar/swift-text-engine/rules/branches/main` readback when
  useful to prove the active branch rules include status checks
- `git diff --check`
- local diff summary proving Swift source, tests, benchmark code, package
  metadata, and workflow YAML were not changed

Because this slice is docs/config-only, `swift test` and benchmark commands are
not required for acceptance. Running them would not validate the GitHub ruleset.
The verification record should state this explicitly.

No destructive live merge-rejection test is required. The API readback is the
source of proof.

## Risks And Mitigations

- **Check context drift:** GitHub requires exact context names. Mitigation:
  derive names from a recent successful run immediately before applying the
  ruleset and verify them after readback.
- **Docs-only skip:** Docs-only commits can have no fresh Swift CI check-runs.
  Mitigation: document this in `AGENTS.md` and use a code/workflow-changing run
  as context evidence.
- **Bypass actor overstatement:** Required checks do not stop actors with bypass
  rights. Mitigation: preserve bypass actors and document that limitation
  plainly.
- **API shape drift:** GitHub ruleset payloads can be sensitive to omitted
  fields. Mitigation: update only after a full readback, inspect the outgoing
  payload, and verify final state through API.

## Acceptance Criteria

- Active ruleset `Main` requires the three Swift CI job contexts for the default
  branch with strict required-status-check policy.
- Existing ruleset behavior outside status checks is preserved.
- `AGENTS.md` accurately describes the current repository policy and bypass
  caveat.
- Verification record captures preflight, mutation, and final readback evidence.
- No Swift source, tests, benchmark code, package metadata, or workflow YAML is
  changed.
