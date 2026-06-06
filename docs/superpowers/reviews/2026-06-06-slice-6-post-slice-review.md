# Slice 6 Post-Slice Review

Date: 2026-06-06

## Scope Reviewed

This review covers Slice 6: GitHub main ruleset operational hardening.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-06-slice-5-post-slice-review.md`
- `docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md`
- `docs/superpowers/plans/2026-06-06-github-main-ruleset.md`
- local git commit history
- fresh local source/workflow diff check
- fresh local host tests
- fresh local synthetic benchmark gate

## Product Brief Alignment

The product brief asks for a headless text rendering engine core with stable
scroll performance, strict virtualization, external document storage, iOS/WASM
source compatibility, and regression benchmarks that block merge when
performance degrades.

Slice 6 targeted the remaining operational part of that merge-blocking
requirement: requiring the Slice 5 `Swift CI` job for updates to `main`.

The chosen policy was intentionally narrow:

```text
Swift CI required on main
```

It would have required:

- changes to reach `main` through a pull request;
- the `Host tests and benchmark gate` check to pass;
- strict status-check policy against the latest `main`.

Execution was blocked by GitHub repository capability, not by Swift code. The
repository is currently private, and the GitHub rulesets API returned:

```text
Upgrade to GitHub Pro or make this repository public to enable this feature.
```

The final Slice 6 state is therefore a documented deferral. For the current
solo-maintainer phase, the accepted repository state remains the Slice 5
`Swift CI` workflow running on pull requests and pushes to `main`.

Slice 6 directly addresses these brief requirements:

- It identifies the exact repository policy needed to turn the existing CI
  check into a repository-required check.
- It records the external blocker that prevents configuring that policy now.
- It keeps Swift source, tests, benchmarks, package definition, and workflow
  YAML unchanged.
- It avoids pretending the benchmark gate is repository-enforced when GitHub
  settings cannot currently prove that.

Slice 6 does not prove these brief requirements:

- GitHub rulesets require the `Host tests and benchmark gate` check for `main`.
- Legacy branch protection requires the `Host tests and benchmark gate` check
  for `main`.
- A pull request is rejected when the check fails.
- Allocation, peak-memory, or resident-memory budgets are measured.
- Cross-target CI verifies iOS, WASM, or embedded WASM on every PR.
- Realistic-provider p95/p99 budgets are enforced.
- File-backed, memory-mapped, rope, piece-table, or editor-buffer storage works
  with the provider contract.
- Variable-height layout, text shaping, rasterization, or UI-framework
  integration.

Those remain out of scope for Slice 6 or blocked by the GitHub repository
capability.

## Delivered Design

The Slice 6 design and plan are both present:

```text
docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md
docs/superpowers/plans/2026-06-06-github-main-ruleset.md
```

Both artifacts now state that the slice is deferred. That is the right final
shape for a failed operational precondition: the desired ruleset remains
auditable, but the repository does not claim a configuration that GitHub did
not allow.

The design preserves a useful future implementation path:

- resolve repository identity as `arthurbanshchikov/swift-text-engine`;
- confirm target branch `main`;
- confirm the recent `Swift CI` job context
  `Host tests and benchmark gate`;
- inspect existing rulesets and legacy branch protection;
- create or update only the narrow ruleset `Swift CI required on main`;
- read the ruleset back through the GitHub API;
- record exact verification evidence.

The plan also contains a clear stop condition:

```text
Do not execute this plan unless Slice 6 is explicitly resumed.
```

That stop condition matters because the GitHub API failure means any continued
work would either require a repository plan change, making the repository
public, or redesigning the enforcement mechanism.

## Implementation Assessment

Slice 6 is not a completed GitHub configuration. It is a completed
decision-and-deferral slice.

Strengths:

- The approved ruleset shape is precise and narrow.
- The required status-check context matches the Slice 5 job name:
  `Host tests and benchmark gate`.
- The ruleset would not add human review policy, code owner review, merge
  queue, signed commits, deployment gates, branch locks, or actor
  restrictions.
- The plan avoids mutating unrelated rulesets or legacy branch protection.
- The final design and plan make the GitHub rulesets blocker visible at the
  top of each document.
- No Swift source, tests, benchmark code, package definition, or workflow YAML
  changed.

Important design choices:

- Rulesets were preferred over legacy branch protection because named rulesets
  are queryable, scoped, and easier to update idempotently.
- The slice did not switch to legacy branch protection after the rulesets API
  failed. That is conservative: changing enforcement mechanisms would have
  been a new design decision, not an implementation detail.
- The accepted current state is explicit: solo-maintainer operation with
  `Swift CI` visible on PRs and pushes, but not repository-required by a
  verified ruleset.

Those choices fit the evidence. The product brief's merge-blocking requirement
is still not fully satisfied, but the project now has a clear reason and a
reusable implementation path for when GitHub rulesets become available.

## Test And Verification Assessment

There is no Slice 6 verification record under:

```text
docs/superpowers/verification/2026-06-06-github-main-ruleset.md
```

That absence is correct for the final deferred state. The slice did not create
or verify a ruleset, so a success-shaped verification record would be
misleading.

Fresh local verification was run for this review on 2026-06-06.

Source and workflow non-goal check:

```text
git diff -- Sources Tests Package.swift .github/workflows/swift-ci.yml
```

Result: no output.

Host tests:

```text
swift test
```

Result: pass, 39 XCTest tests, 0 failures.

Synthetic benchmark gate:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass.

Fresh synthetic gate output:

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1339 p99_ns=1439 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5074 p99_ns=5245 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17073 p99_ns=18942 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

The fresh synthetic gate still has substantial headroom:

- `1k_lines_20_visible_overscan_0`: p95 is about 6.7% of budget; p99 is about
  2.9% of budget.
- `100k_lines_80_visible_overscan_5`: p95 is about 10.1% of budget; p99 is
  about 5.2% of budget.
- `1m_lines_200_visible_overscan_50`: p95 is about 17.1% of budget; p99 is
  about 9.5% of budget.

This verification supports the Slice 6 non-goal claim: the documentation-only
deferral did not disturb the current host test suite or synthetic performance
gate.

## Commit History Notes

The Slice 6 history on `main` is:

- `docs: design github main ruleset`
- `docs: plan github main ruleset`
- `docs: defer github main ruleset slice`

The final diff from the Slice 5 implementation branch head to current `main`
contains:

```text
docs/superpowers/specs/2026-06-06-github-main-ruleset-design.md
docs/superpowers/plans/2026-06-06-github-main-ruleset.md
docs/superpowers/reviews/2026-06-06-slice-5-post-slice-review.md
```

The design -> plan ordering is clean. The deferral commit also adds the Slice 5
post-slice review, which is a minor process ordering blemish: that review
belongs to the previous slice, even though the final artifact is useful and now
tracked.

No product source files changed in Slice 6.

## Risks And Gaps

### Merge-Blocking Is Still Not Repository-Proven

The `Swift CI` workflow still runs on pull requests and pushes to `main`, but
Slice 6 did not prove that GitHub settings require the check before `main` can
change.

This is now an external platform/account limitation. It should not continue to
consume source-code slices unless the repository becomes public, GitHub Pro
rulesets become available, or a different enforcement mechanism is selected.

### Legacy Branch Protection Remains A Separate Design Decision

Slice 6 deliberately did not fall back to legacy branch protection after the
rulesets API failed. That keeps the slice honest, but it leaves one possible
operational alternative unexplored.

If branch protection is worth pursuing without rulesets, it should be designed
as its own small operational slice with explicit API readback and with the same
care around not overwriting unrelated repository settings.

### Memory Is Still The Largest Source-Controlled Product Gap

The core design is bounded by construction for the current fixed-height path:
range computation is scalar, geometry traversal streams buffered ranges, and
document storage is caller-owned through the provider boundary.

That is still mostly a design and test argument. The project has not yet added
a focused measurement or diagnostic proving that core-owned memory does not
grow linearly with total document size.

### Cross-Target CI Is Still Deferred

Earlier slices locally verified host, iOS, WASM, and embedded WASM library
targets. CI still only runs host tests and the host benchmark executable. This
is acceptable while no public core API changes are being made, but it remains a
risk for future API slices.

### Realistic Provider Remains Observational

The realistic-provider benchmark proves an 11.2 MB payload shape locally, but
it has no hard p95/p99 budget and is not part of CI. That is acceptable until
memory shape and runner variance are better understood.

### Variable-Height Layout Remains Deferred

The fixed-height path is now well covered. Variable-height layout is still the
largest functional expansion, with new indexing, invalidation, and measurement
risks.

## Lessons For Slice 7

1. Do not spend the next slice retrying blocked GitHub rulesets.

The ruleset design is ready, but the current repository capability blocks it.
Retrying the same API path without an account or repository-state change would
not improve the product.

2. Prefer source-controlled product proof next.

After Slice 6, the best available progress is a proof that can live in the
repository: tests, benchmark diagnostics, or verification documents tied to
local commands.

3. Measure memory shape before making broader layout changes.

The product brief explicitly says core-owned memory must not grow linearly with
document size. The current architecture is designed for that, but the next
slice should turn the claim into evidence before variable-height layout adds
more data structures.

4. Keep memory proof separate from hard CI policy.

A first memory slice should establish a stable measurement or diagnostic
surface. It should not also add CI enforcement, realistic-provider latency
budgets, or variable-height layout.

5. Preserve the provider boundary.

Any memory proof must separate caller-owned document storage from core-owned
range, geometry, cursor, and traversal work. Otherwise the measurement will
confuse the product requirement.

## Slice 7 Candidate Options

### Option A: Core-Owned Memory Shape Verification

Add a focused host-side memory/allocation proof for the current fixed-height
pipeline and provider traversal.

Suggested scope:

- Define what counts as core-owned memory for the fixed-height pipeline.
- Measure or count per-operation core work for 100k-line and 1m-line
  scenarios.
- Include a realistic-provider scenario while explicitly excluding the
  caller-owned document payload from core-owned memory.
- Record results in a verification document.
- Keep GitHub rulesets, branch protection, variable-height layout, and hard
  memory CI budgets out of scope.

This is the strongest Slice 7 candidate because it closes the largest remaining
source-controlled product-brief gap.

### Option B: Legacy Branch Protection Instead Of Rulesets

Design and verify a narrow legacy branch protection rule for `main`, if GitHub
allows that feature for the current private repository.

Suggested scope:

- Inspect current branch protection through the GitHub API.
- Require the existing `Host tests and benchmark gate` context.
- Require pull requests only if that is accepted repository policy.
- Record API readback.
- Keep Swift source, tests, benchmarks, workflow YAML, and rulesets unchanged.

This could close the operational enforcement gap, but it is less attractive as
Slice 7 because Slice 6 just found a platform/account blocker on the preferred
ruleset path.

### Option C: Cross-Target CI For `TextEngineCore`

Add continuous compatibility checks for the core library beyond host tests.

Suggested scope:

- Add the cheapest reliable iOS compile check in GitHub Actions.
- Investigate whether WASM and embedded WASM Swift SDK setup is reproducible on
  hosted runners.
- Keep `ViewportBenchmarks` out of cross-target jobs.
- Do not change public core API in the same slice.

This improves compatibility confidence, but it is less urgent than memory
proof because no new public core API is currently being introduced.

### Option D: Realistic Provider Budget Calibration

Calibrate p95/p99 budgets for the realistic-provider benchmark.

Suggested scope:

- Run repeated local realistic-provider samples.
- Optionally gather hosted-runner samples through a manual workflow or
  temporary diagnostic run.
- Decide whether `--realistic-provider --gate` should become valid.
- Keep memory proof and variable-height layout out of scope.

This strengthens Slice 4, but latency budgets for realistic payloads are easier
to set after memory shape is understood.

### Option E: Variable-Height Layout Foundation

Start the next major core capability: variable-height line indexing and
localized invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the fixed-height fast path.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests.
- Repeat cross-target verification for any public core API changes.

This moves functionality forward, but it should wait until the current
fixed-height pipeline has stronger memory evidence.

## Recommended Slice 7 Selection

Recommended: Option A, core-owned memory shape verification.

Reasoning:

- Slice 6 closes the branch-protection question for now: rulesets are blocked
  by current GitHub repository capability.
- The product brief still has an explicit memory requirement that has not been
  measured directly.
- The current fixed-height architecture is stable enough to measure without
  mixing in variable-height layout.
- A memory proof can be source-controlled, reproducible, and useful even while
  repository settings remain externally constrained.
- It gives future CI, realistic-provider budget, and variable-height slices a
  clearer baseline.

Defer Option B until GitHub branch protection is selected explicitly as a
replacement for rulesets. Defer Option C until the next public core API change
or until CI setup cost is lower. Defer Option D until memory shape and runner
variance are clearer. Defer Option E until the fixed-height path has direct
memory evidence.

## Slice 6 Review Conclusion

Slice 6 is a clean deferral of the GitHub main ruleset hardening work. It
identified the desired repository policy, prepared a narrow design and plan,
then stopped when GitHub rulesets were unavailable for the current private
repository state.

That is not a completed merge-blocking enforcement slice, and the review should
not treat it as one. The important outcome is that the project avoided an
unverified claim and preserved the implementation path for later.

The next slice should move back to source-controlled product evidence. Slice 7
should verify core-owned memory shape for the fixed-height pipeline and
provider traversal.
