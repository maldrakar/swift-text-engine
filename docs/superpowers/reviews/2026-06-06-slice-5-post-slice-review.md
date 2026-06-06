# Slice 5 Post-Slice Review

Date: 2026-06-06

## Scope Reviewed

This review covers Slice 5: CI wiring for the existing synthetic benchmark
gate.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-05-slice-4-post-slice-review.md`
- `docs/superpowers/specs/2026-06-05-ci-benchmark-gate-wiring-design.md`
- `docs/superpowers/plans/2026-06-05-ci-benchmark-gate-wiring.md`
- `.github/workflows/swift-ci.yml`
- `docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md`
- local git commit history
- GitHub Actions run status for the Slice 5 pull request and post-merge push

## Product Brief Alignment

The product brief asks for a headless text rendering engine core with stable
scroll performance, strict virtualization, external document storage, iOS/WASM
source compatibility, and regression benchmarks that block merge when
performance degrades.

Slice 5 narrows that product goal to repository-level enforcement for the
synthetic fixed-height benchmark gate created in Slice 3 and preserved in Slice
4. The slice does not change the core or benchmark semantics; it wires the
existing pass/fail command into GitHub Actions:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Slice 5 directly addresses these brief requirements:

- Host tests run in CI on pull requests and pushes to `main`.
- The synthetic release benchmark gate runs in CI on pull requests and pushes
  to `main`.
- CI fails if `swift test` exits non-zero.
- CI fails if the benchmark gate exits non-zero.
- The first observed PR and post-merge GitHub Actions runs both completed
  successfully.
- `TextEngineCore`, `ViewportBenchmarks`, package definition, and tests remain
  unchanged by this infrastructure slice.

Slice 5 does not yet prove these brief requirements:

- GitHub branch protection or a ruleset requires the `Swift CI` check before
  merging to `main`.
- Realistic-provider p95/p99 budgets are enforced.
- Allocation, peak-memory, or resident-memory budgets are measured.
- Cross-target CI verifies iOS, WASM, or embedded WASM on every PR.
- File-backed, memory-mapped, rope, piece-table, or editor-buffer storage works
  with the provider contract.
- Variable-height layout, text shaping, rasterization, or UI-framework
  integration.

Those remain out of scope for Slice 5.

## Delivered Design

The Slice 5 design added one GitHub Actions workflow:

```text
.github/workflows/swift-ci.yml
```

The workflow behavior is intentionally narrow:

1. Run on `pull_request`.
2. Run on `push` to `main`.
3. Use a hosted `macos-latest` runner.
4. Print Swift, Xcode, and kernel information.
5. Run `swift test`.
6. Run `swift run -c release ViewportBenchmarks -- --gate`.

The workflow does not parse benchmark output. The benchmark executable already
owns scenario definitions, budget comparison, checksum reporting, and process
exit behavior. Keeping that logic in Swift avoids duplicating benchmark policy
inside YAML.

The workflow also avoids `continue-on-error`, realistic-provider execution,
cross-target compile checks, and shell wrapper scripts. That matches the
approved design: Slice 5 should close one enforcement gap without expanding
benchmark scope.

## Implementation Assessment

The implementation matches the approved design and preserves the slice
boundary.

Strengths:

- The workflow has the expected `pull_request` and `push` to `main` triggers.
- The job name, `Host tests and benchmark gate`, is specific enough to require
  later in GitHub branch protection settings.
- `permissions: contents: read` keeps the workflow's token scope narrow.
- `concurrency` cancels stale runs for the same workflow/ref pair.
- The job uses `timeout-minutes: 20`, which bounds stuck CI runs.
- The test and benchmark steps rely on command exit codes.
- The workflow does not introduce a second source of truth for benchmark
  budgets.
- No source, package, or test files changed in the slice.

Important design choices:

- `macos-latest` is pragmatic because `ViewportBenchmarks` imports `Darwin` and
  uses `ContinuousClock`.
- The workflow is a repository-enforceable check, but branch protection remains
  an external GitHub repository setting.
- The slice intentionally gates only the synthetic benchmark, not the
  realistic-provider benchmark.
- Cross-target verification remains recorded locally in earlier slices, not
  automated in this CI workflow.

Those choices fit Slice 5. The slice turns the local synthetic gate into a
remote CI check without changing the product code under measurement.

## Test And Verification Assessment

The saved verification record covers:

- absence of committed CI configuration before Slice 5;
- known GitHub remote URL;
- static workflow checks for triggers, runner, timeout, and commands;
- local `swift test`;
- local synthetic benchmark gate;
- confirmation that realistic-provider and cross-target checks stayed out of
  the workflow;
- the limitation that local verification alone did not prove the first remote
  GitHub Actions run.

Fresh verification was rerun for this review on 2026-06-06:

- `swift test`: pass, 39 XCTest tests, 0 failures.
- `swift run -c release ViewportBenchmarks -- --gate`: pass.
- `rg --files --hidden -g '.github/**'`: finds
  `.github/workflows/swift-ci.yml`.
- Workflow trigger/runner/command scan: pass.
- Out-of-scope workflow command scan for `realistic-provider`,
  `swift build --swift-sdk`, `xcrun swiftc`, and `continue-on-error`: no
  matches.
- `git diff 16550bc..138b037 -- Package.swift Sources Tests`: no diff.

Fresh synthetic gate output:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1350 p99_ns=1527 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5393 p99_ns=5812 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16855 p99_ns=18200 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

The fresh synthetic gate still has substantial headroom:

- `1k_lines_20_visible_overscan_0`: p95 is about 6.8% of budget; p99 is about
  3.1% of budget.
- `100k_lines_80_visible_overscan_5`: p95 is about 10.8% of budget; p99 is
  about 5.8% of budget.
- `1m_lines_200_visible_overscan_50`: p95 is about 16.9% of budget; p99 is
  about 9.1% of budget.

Remote GitHub Actions verification was also checked:

- PR run `27032642312`, event `pull_request`, branch
  `ci-benchmark-gate-wiring`, workflow `Swift CI`: completed with conclusion
  `success` at 2026-06-05T18:27:11Z.
- Post-merge run `27033815208`, event `push`, branch `main`, workflow
  `Swift CI`: completed with conclusion `success` at 2026-06-05T18:51:55Z.
- In both runs, the job `Host tests and benchmark gate` completed with
  conclusion `success`.
- In both runs, the `Run host tests` and `Run synthetic benchmark gate` steps
  completed with conclusion `success`.

This closes the main uncertainty left in the Slice 5 verification record: the
workflow is not only syntactically present and locally reproducible, it has also
passed on GitHub-hosted runners.

## Commit History Notes

The Slice 5 branch history is:

- `docs: plan ci benchmark gate wiring`
- `docs: design ci benchmark gate wiring`
- `docs: plan ci benchmark gate wiring`
- `ci: add swift benchmark gate workflow`
- `docs: record ci benchmark gate verification`

The final implementation diff from the Slice 4 review commit to the Slice 5
branch head contains only:

```text
.github/workflows/swift-ci.yml
docs/superpowers/plans/2026-06-05-ci-benchmark-gate-wiring.md
docs/superpowers/specs/2026-06-05-ci-benchmark-gate-wiring-design.md
docs/superpowers/verification/2026-06-05-ci-benchmark-gate-wiring.md
```

There is one process blemish: the plan commit appears before the design commit,
then the plan is committed again. The final artifacts are coherent, and the
implementation still follows the approved design, but future slices should keep
the visible history closer to design -> plan -> implementation -> verification
when practical.

## Risks And Gaps

### Branch Protection Is Still External

The workflow now creates a real GitHub check, and both PR and post-merge runs
passed. However, a workflow check only blocks merges when GitHub branch
protection or a ruleset requires it.

That repository setting is not represented in `.github/workflows/swift-ci.yml`.
Until it is configured and verified, the product-brief phrase "block merge"
should be interpreted as "the repository has a CI check capable of blocking
merge", not as "the repository settings have been proven to reject a merge when
the check fails".

### Runner Drift Remains A CI Maintenance Risk

`macos-latest` can move to a different macOS/Xcode/Swift toolchain over time.
The workflow logs toolchain information, but it does not pin Xcode or Swift.
This is acceptable for Slice 5, but future failures may come from hosted-runner
movement rather than product regressions.

### Synthetic Gate Is Still The Only CI Performance Gate

The realistic-provider benchmark remains observational. It covers a deterministic
11.2 MB in-memory payload locally, but CI does not run it and no p95/p99 budget
is attached to it.

### Memory Is Still Reasoned More Than Measured

The current core design is memory-conscious: range computation is scalar,
geometry and document-line cursors stream through buffered ranges, and storage
is outside `TextEngineCore`. Slice 5 does not add any measurement that proves
core-owned memory stays bounded as total document size grows.

This is now the largest remaining product-brief gap after CI workflow wiring.

### Cross-Target CI Is Still Deferred

Earlier slices locally verified `TextEngineCore` under host, iOS, WASM, and
embedded WASM library-target checks. Slice 5 does not move those checks into
CI. That is fine because Slice 5 changed no public core API, but future public
API slices should keep cross-target verification visible.

### Variable-Height Layout Is Still Deferred

The fixed-height path now has local and remote synthetic gate coverage.
Variable-height layout remains a separate architectural step with different
data structures, invalidation rules, and performance risks.

## Lessons For Slice 6

1. Decide whether Slice 6 is operational or product-code work.

If GitHub branch protection can be configured now, a short operational slice can
finish the merge-blocking story for the synthetic gate. If repository settings
are not available or not worth spending a whole slice on, the next product-code
slice should target memory measurement.

2. Keep CI policy and benchmark policy separate.

Slice 5 is clean because CI runs the executable and trusts its exit code.
Future gates should preserve that separation: Swift owns benchmark semantics;
YAML owns when to run them.

3. Do not add realistic budgets until variance is understood.

The synthetic gate has large local headroom and now passes on GitHub runners.
The realistic-provider benchmark still needs either repeated runner data or a
separate memory/shape objective before becoming a hard CI gate.

4. Keep source changes out of operational slices.

Slice 5 succeeded because it did not mix infrastructure with benchmark or core
changes. If Slice 6 is branch protection, it should stay documentation/settings
oriented. If it is memory proof, it should not also adjust CI branch rules.

5. Preserve design -> plan -> implementation ordering.

The duplicate Slice 5 plan commit did not damage the final result, but the next
slice should keep the artifacts ordered and easier to audit.

## Slice 6 Candidate Options

### Option A: Require The Swift CI Check In GitHub

Configure and verify GitHub branch protection or a GitHub ruleset that requires
the `Swift CI / Host tests and benchmark gate` check before merging to `main`.

Suggested scope:

- Identify whether this repository uses branch protection rules or rulesets.
- Require the `Host tests and benchmark gate` job for `main`.
- Require pull requests before merge if that is the intended repository policy.
- Verify the configured rule through GitHub API or UI-visible settings.
- Record a verification document with exact rule/check names and the relevant
  GitHub run links.
- Keep workflow YAML, benchmark budgets, source code, and realistic-provider
  behavior unchanged.

This directly closes the remaining operational part of the merge-blocking
performance-gate requirement, but it depends on GitHub repository admin access
and may produce little or no committed source artifact beyond documentation.

### Option B: Memory Or Allocation Verification For The Fixed-Height Pipeline

Add a focused host-side memory proof for the current fixed-height pipeline and
realistic-provider benchmark shape.

Suggested scope:

- Measure or report core-owned memory shape for 100k+ and 1m-line scenarios.
- Separate caller-owned realistic document storage from core-owned per-operation
  work.
- Prove that range computation, geometry traversal, and provider traversal stay
  bounded by visible viewport plus overscan, not total document size.
- Use conservative diagnostics before hard budgets if the measurement mechanism
  is noisy.
- Keep branch protection, realistic-provider p95/p99 budgets, storage adapters,
  and variable-height layout out of scope.

This closes the largest remaining product-brief proof gap in source-controlled
code. It is more valuable than new layout functionality if branch protection is
already handled or cannot be handled inside this work session.

### Option C: Cross-Target CI For `TextEngineCore`

Extend CI beyond host tests so public core compatibility is continuously
checked.

Suggested scope:

- Add the cheapest reliable CI check for iOS simulator or iOS module compile.
- Investigate whether the required WASM and embedded WASM Swift SDKs can be
  installed reproducibly on GitHub runners.
- Keep `ViewportBenchmarks` out of cross-target jobs because it is host-only.
- Do not change public core API in the same slice.

This improves compatibility confidence, but it is less urgent than memory proof
unless the next code slice will change public core API.

### Option D: Realistic Provider Gate Calibration

Calibrate p95/p99 budgets for `--realistic-provider` and decide whether it
should become gateable.

Suggested scope:

- Run repeated realistic-provider samples locally and, if useful, on GitHub
  runners.
- Decide whether `--realistic-provider --gate` should become valid or whether a
  separate flag is clearer.
- Keep budgets conservative and document runner variance.
- Do not add memory proof or variable-height layout in the same slice.

This strengthens the Slice 4 benchmark, but it should wait until either memory
shape is better understood or enough runner variance data exists.

### Option E: Variable-Height Layout Foundation

Begin the next major core capability: variable-height line indexing and
invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the fixed-height fast path.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests.
- Repeat cross-target verification for any public core API changes.

This moves product functionality forward, but it is the highest-risk option and
should wait until the remaining enforcement and memory-proof gaps are smaller.

## Recommended Slice 6 Selection

Recommended: Option A if GitHub repository settings can be changed and verified
now. Slice 5 created the check and proved it passes remotely; requiring that
check for `main` is the smallest remaining step to make the synthetic benchmark
gate truly merge-blocking.

If branch protection cannot be configured in this environment, choose Option B:
memory or allocation verification for the fixed-height pipeline and realistic
provider shape.

Reasoning:

- The product brief explicitly calls for merge-blocking regression benchmarks.
- Slice 5 now has both PR and post-merge GitHub Actions success for `Swift CI`.
- Without a required check, a failing benchmark can be visible but not
  necessarily merge-blocking.
- After the branch-protection question is closed, memory proof is the most
  important unmeasured product-brief requirement.

Defer Option C until the next public core API change or until cross-target CI
tooling is known. Defer Option D until memory/variance assumptions are clearer.
Defer Option E until enforcement and memory proof are stronger.

## Slice 5 Review Conclusion

Slice 5 is a clean completion of CI wiring for the existing synthetic benchmark
gate. It adds a narrow GitHub Actions workflow, runs host tests and the release
benchmark gate on pull requests and pushes to `main`, and preserves all product
source files unchanged.

Fresh local verification passes, and the first observed GitHub-hosted PR and
post-merge workflow runs both completed successfully. That is a material upgrade
from a local-only benchmark gate to a real repository check.

The remaining caveat is operational: the workflow is only truly merge-blocking
if GitHub branch protection or a ruleset requires the `Host tests and benchmark
gate` job. If that setting can be verified now, it should be Slice 6. Otherwise,
Slice 6 should move to the largest remaining source-controlled product proof:
bounded memory or allocation behavior for the fixed-height pipeline and
realistic provider.
