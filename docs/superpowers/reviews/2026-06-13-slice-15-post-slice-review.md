# Slice 15 Post-Slice Review

Date: 2026-06-13

## Scope Reviewed

This review covers Slice 15: variable-height CI gate promotion and memory-shape
diagnostic consolidation, merged through PR #11
(`slice-15-variable-height-ci-gate`) into `main` as merge commit
`cbb50364ddd0fb47b3805659074e04b1800943a4`.

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-12-variable-height-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-06-12-variable-height-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-06-12-variable-height-ci-gate-promotion.md`
- `docs/superpowers/reviews/2026-06-12-slice-14-post-slice-review.md` (the
  predecessor review whose P3 finding this slice resolves)
- `AGENTS.md` / `CLAUDE.md` as current repository conventions
- PR #11 metadata, hosted pull-request CI runs, merge commit, and the
  post-merge push runs on `main`
- Slice 15 source/CI/guide diff (`d5964a1..657b322`)
- Fresh local host tests, release build, synthetic gate, variable-height gate,
  memory-shape diagnostic, RSS memory observation, cross-target compile helper,
  Foundation-free scan, and `git diff --check`

This is an infrastructure/evidence slice: it changes the CI gate posture and a
benchmark-side diagnostic. It deliberately does not touch `TextEngineCore`,
`Tests/TextEngineCoreTests`, `Package.swift`, the variable-height public API, or
benchmark budgets.

## Product Brief Alignment

Slice 15 strengthens the safety envelope around the already-merged
variable-height layout path without expanding functional scope:

- `TextEngineCore` is untouched, so the core stays headless, Foundation-free,
  zero-dependency, and Embedded/cross-target compatible by construction.
- The variable-height benchmark, previously hosted-observation-only, becomes a
  blocking CI gate, giving the variable path the same enforcement shape as the
  fixed synthetic gate (unit proof, local gate, hosted-failing gate).
- Memory-shape diagnostics are normalized onto one `MemoryShapeSummary` model and
  one formatter for fixed, large-text, and variable-uniform scenarios, while
  preserving the variable-specific core-owned-byte estimate and a per-provider
  cross-row consistency check.

The slice deliberately does not change budgets, promote hosted WASM, add
mutation/localized-update structure, or alter repository branch protection.

## Delivered Design

The merged Slice 15 source/CI/guide diff is:

```text
 .github/workflows/swift-ci.yml                                  |  5 +-
 AGENTS.md                                                       |  5 +-
 Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift         | 70 +++++------
 3 files changed, 35 insertions(+), 45 deletions(-)
```

The slice also adds design, plan, and verification documentation, and — during
the review cleanup described under Git History — folds in the Slice 14
post-slice review file so the predecessor review is preserved on `main`.

### CI Gate Promotion (Decision 1/2)

`.github/workflows/swift-ci.yml` renames the variable-height step from
`Run variable-height benchmark observation` to
`Run variable-height benchmark gate`, removes `continue-on-error: true`, and
changes the command to
`swift run -c release ViewportBenchmarks -- --variable-height --gate`. The step
stays in the `host-tests-and-benchmark-gate` job after the synthetic gate and
before memory diagnostics, so a variable-height regression fails the job before
later diagnostics run. Budgets are unchanged, matching Decision 2 and the wide
hosted margins recorded in the design (worst hosted p99 ~2.2% of the 1M p99
budget).

`AGENTS.md` is updated so the durable, per-session CI paragraph describes
`--variable-height --gate` as blocking and states that the synthetic and
variable-height gates both fail the job on perf regression. Because `CLAUDE.md`
imports `AGENTS.md`, this keeps the per-session source of truth from going stale.

### Memory-Shape Consolidation (Decision 3)

`MemoryShapeDiagnostics.swift` deletes the parallel `VariableMemoryShapeSummary`
type, the `formatVariableMemoryShapeSummary` formatter, and the separate variable
print/invariant loop. `runVariableMemoryShapeScenario(lineCount:)` now returns the
shared `MemoryShapeSummary`, populated exactly as the design specifies:
`providerName = "variable_uniform"`, `documentBytes = nil`,
`providerLines = bufferedLines`, `missingLines = 0`, `providerOwnedBytes = 0`,
`benchmarkOwnedBytes = 0`, `coreOwnedBytes = variableCoreOwnedBytesEstimate()`,
and `baseInvariantPasses` carrying the prior `traversalPasses` condition (range
ordered/bounded, visible/buffered counts match expectations, geometry lines equal
buffered lines).

The cross-row `coreOwnedBytes` consistency check is preserved with explicit
**per-provider** reference selection in `runMemoryShapeDiagnostics`:

- `synthetic` rows compare against the first `synthetic` `coreOwnedBytes`;
- `variable_uniform` rows compare against the first `variable_uniform`
  `coreOwnedBytes`;
- `large_text` is skipped.

This is correct: a single shared reference would falsely fail a healthy
`variable_uniform` row (estimate `90`) against the synthetic reference (`74`),
because `variableCoreOwnedBytesEstimate()` measures
`VariableLineGeometryCursor<UniformLineMetrics>` while `coreOwnedBytesEstimate()`
measures `LineGeometryCursor`. The check stays outside per-row
`baseInvariantPasses`, since it is a cross-row invariant. Verified by reading the
merged code: the duplicate types are gone and the three required names
(`variableCoreOwnedBytesEstimate()`, `comparisonVariableCoreOwnedBytes`,
`variableUniformMemoryShapeProviderName`) are present.

This directly resolves the only confirmed Slice 14 finding (P3 duplication in
`MemoryShapeDiagnostics.swift`).

## Verification Evidence Reviewed

Fresh local verification for this review on 2026-06-13, against the merged `main`
content (`be7ad01`):

```text
swift test
```

Result: pass, 67 XCTest tests, 0 failures. The Swift Testing harness separately
reports `0 tests in 0 suites`, expected for this XCTest-only package.

```text
swift build -c release
```

Result: pass.

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass — three `mode=pipeline` rows, each `failures=0 gate=pass`.

```text
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Result: pass — three `mode=variable_height` rows, each `failures=0 gate=pass`
(1M scenario `p95_ns=2090 p99_ns=2220` against `250000`/`500000` budgets).

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass — every row `invariant=pass`, including two normalized
`provider=variable_uniform` rows carrying the full column set
(`visible_lines`, `touched_lines`, `provider_lines`, `missing_lines=0`,
`provider_owned_bytes=0`, `benchmark_owned_bytes=0`) with `core_owned_bytes=90`
versus `core_owned_bytes=74` for the synthetic/large-text rows.

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass for all three RSS observation scenarios.

```text
rg -n "Foundation" Sources/TextEngineCore
```

Result: no output. The core remains Foundation-free.

```text
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/cross-target-compile.sh
```

Result: `self_test=pass`; full compile passes iOS device and iOS simulator
(blocking) and, on the local Swift 6.2.1 toolchain, WASM and embedded WASM
(non-blocking): `blocking_failures=0 exit=0`.

```text
git diff --check
```

Result: no output.

### Hosted Evidence

- Pull-request CI runs `27443136804` (head `c06c6d1`) and `27443429128` (head
  `60983bc`) both concluded `success`, with the variable-height step running as a
  blocking gate and printing three `mode=variable_height ... gate=pass` rows. The
  1M scenario reported hosted `p99_ns=13841` against the `500000` budget.
- PR #11 merged as `cbb5036`.
- **The post-merge push runs did not produce hosted gate evidence.** Push run
  `27444745973` (merge commit `cbb5036`) and `27444934531` (`be7ad01`) both
  concluded `failure` with zero workflow steps executed and no downloadable log.
  The GitHub check-run annotation on both jobs was:

  ```text
  The job was not started because recent account payments have failed or your
  spending limit needs to be increased. Please check the 'Billing & plans'
  section in your settings
  ```

  This is not a benchmark, test, or cross-target failure. The hosted runners
  never started because the GitHub Actions account spending limit was reached.
  The last green hosted push run on `main` is `27430943082` (`d5964a1`), which
  predates the Slice 15 merge.

The strongest hosted evidence for merged Slice 15 code is therefore the two green
pull-request runs plus the fully green fresh local verification above. The
post-merge push run — normally the strongest evidence per the workflow
conventions — is blocked by the billing exhaustion described under Risks.

## Git History

Slice 15's reviewed commit range on `origin/main` is:

```text
af620de docs: design variable-height ci gate promotion
f00ad83 docs: plan variable-height ci gate promotion
b7ab1c9 refactor: consolidate memory-shape summaries
147429d ci: promote variable-height benchmark gate
c06c6d1 docs: record variable-height ci gate verification
60983bc docs: record variable-height ci gate pr run
657b322 docs: record slice 14 post-slice review
cbb5036 Merge pull request #11 from arthurbanshchikov/slice-15-variable-height-ci-gate
be7ad01 docs: record variable-height ci gate post-merge run
```

The implementation is two logical code commits — `b7ab1c9` (diagnostics
consolidation) and `147429d` (CI + AGENTS.md promotion) — surrounded by design,
plan, and verification docs.

`657b322 docs: record slice 14 post-slice review` is a review-time correction.
The Slice 14 post-slice review had been committed only to local `main`
(`bb983d5`) and never pushed; the spec's Risk section flagged it. During this
review it was cherry-picked onto the open Slice 15 PR branch and merged through
PR #11, so the Slice 14 review (`docs/superpowers/reviews/2026-06-12-slice-14-post-slice-review.md`)
is now preserved on `origin/main`. This is acceptable but mixed concerns into the
Slice 15 PR; future post-slice reviews should land on their own
`slice-N-post-slice-review` branch (as this Slice 15 review does).

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None.

### P2 / Production Readiness

None in the slice's source diff. The post-merge hosted-evidence gap is a process
risk, not a code defect; it is tracked under Risks And Gaps.

### P3 / Minor But Valid

#### P3 - Output schema carries duplicate `touched_lines` / `provider_lines`

`formatMemoryShapeSummary` emits both `touched_lines` and `provider_lines` from
the same `summary.providerLines` field, so the two columns are always identical
on every row (now including the variable rows). This is pre-existing behavior
inherited by the consolidation, not introduced by Slice 15, and the design
explicitly chose `providerLines = bufferedLines` for the variable path. It is a
harmless redundancy in the diagnostic output. If a future slice touches this
formatter, consider dropping one column or documenting why both exist. No action
required for Slice 15.

#### Observation - Asymmetric failure-path `missingLines`

The variable failure branch sets `missingLines = 0` while the fixed failure
branch uses `missingLines = 1` as a sentinel. This matches the approved spec
patch and is unreachable for the shipped uniform scenarios, so it is recorded as
an observation, not a finding.

## Risks And Gaps

### Hosted CI Is Blocked By Actions Billing Exhaustion (New, High Priority)

This is the most important finding of the review and it is a process blocker, not
a Slice 15 code defect. The GitHub Actions account spending limit / included
minutes were exhausted, so the Slice 15 post-merge push runs (and any subsequent
push) fail to start. Root cause analysis performed during this review:

- Both CI jobs run on `macos-latest`, which bills at a **10x** multiplier against
  the account's 2000 included minutes (GitHub Free).
- Across the 43 hosted runs (05–12 June), actual macOS wall-clock time was only
  ~145 minutes, but the 10x multiplier inflated that to ~1780 quota-minutes —
  about 89% of the 2000-minute quota from this repository alone, before any other
  private-repo usage.
- The `Host tests and benchmark gate` job dominates: ~1550 of ~1780 quota-minutes
  (~87%). The `Cross-target compile` job is ~230. At least 12 runs were triggered
  by docs-only commits.

Consequence: the repository can no longer produce its strongest hosted evidence
(post-merge push run on `main`) until billing is restored or CI cost is cut. This
makes CI resource optimization the urgent next slice (see candidates below).

### Variable-Height Gate Is Blocking But Currently Un-runnable Hosted

Slice 15 correctly makes the variable-height benchmark a blocking gate, but until
the billing issue is resolved the hosted gate cannot execute. The gate is proven
locally and was proven on the pre-merge PR runs; enforcement value resumes once
hosted runners can start again.

### Repository Policy Still Cannot Require The Check

Unchanged from prior slices: even with the variable-height gate now blocking the
check status, the private repo cannot *require* the check before merge without
the branch-protection/ruleset capability identified in Slice 6. PR #11 was in
fact merged while a green check existed; this is policy, not a Slice 15 defect.

### WASM Hosted CI Still Skips

Unchanged: hosted WASM/embedded WASM remain observational skips when no matching
Swift SDK is provisioned. Both build locally on Swift 6.2.1.

### Local `main` Divergence (Housekeeping)

Local `main` still points at the unpushed `bb983d5`, whose content now lives on
`origin/main` as `657b322`. Local `main` should be reset to `origin/main` to avoid
confusion; no remote impact.

## Lessons For Slice 16

1. The variable-height path now has the full safety shape: unit proof,
   deterministic query-count tests, local gate, blocking hosted gate (when
   runners can start), and normalized memory-shape diagnostics. The Slice 14 P3
   is resolved.

2. CI cost is now a first-order constraint, not a background concern. The 10x
   macOS multiplier silently converted a tiny amount of real compute into a
   quota wall that blocks the project's own post-merge verification workflow.

3. Most of the macOS spend is on work that does not need macOS. Only the iOS
   cross-target compile genuinely requires Xcode/macOS; host tests, benchmark
   gates, and memory diagnostics are Linux-capable Swift.

4. Docs-only commits should not trigger the full macOS CI matrix.

## Slice 16 Candidate Options

### Option A: CI Resource Optimization (Recommended)

Cut GitHub Actions consumption so the project can run hosted CI again under the
2000-minute Free quota, by combining the two highest-leverage levers:

1. Move the `host-tests-and-benchmark-gate` job off `macos-latest` to a Linux
   host (`runs-on: ubuntu-latest`, the only Linux GitHub-hosted option; Debian is
   not a hosted-runner OS). Use the official Swift container
   (`container: swift:6.x-bookworm`, Debian 12) for a reproducible toolchain at
   the **1x** billing rate. Keep the `cross-target-compile` job on `macos-latest`,
   because iOS `xcodebuild` requires it. Expected effect: the dominant
   ~1550 quota-minute job drops to ~155.
2. Skip CI on docs-only changes (`paths-ignore: ['docs/**', '**/*.md']`) and add
   `concurrency` with `cancel-in-progress: true` so rapid pushes to a branch do
   not stack runs.

Open risks the Slice 16 spec must resolve, surfaced during this review:

- **Benchmark budgets are nanosecond budgets calibrated on macOS.** A Linux
  container runner has a different absolute-timing and variance profile. Current
  hosted margins are ~2% of budget, so the gates very likely still pass, but the
  slice must re-baseline (and possibly retune) the synthetic and variable-height
  budgets on the new runner rather than assume the macOS numbers transfer.
- **`--memory-observation` reads RSS via host-specific APIs** (the local run
  reports `rss_page_size_bytes=16384`, an Apple-silicon/macOS page size). On Linux
  the RSS source and page size differ (typically 4096, `/proc/self/statm`). The
  observation step must either gain a Linux code path or stay on macOS. The
  Foundation-free core is unaffected; this is benchmark-executable concern only.
- The brief's iOS-blocking and WASM-observational contracts must be preserved on
  the macOS cross-target job.

This is the recommended slice: it is presently a blocker for the project's
verification workflow, it is low-risk to the core (no `TextEngineCore` change),
and it follows the user's selected direction. The runner choice is "Ubuntu host
at 1x with a Debian (`bookworm`) Swift container," which gives the requested
Debian environment without a billing penalty.

### Option B: Variable-Height Mutation / Indexed Provider

The strongest functional-value follow-up, deferred since Slice 14: a reference
indexed metrics provider whose single-line height change is a localized O(log N)
update (e.g. a Fenwick/cumulative-height index), with tests proving cheap
re-layout, leaving `TextEngineCore` stateless. Choose this if functional capability
outranks unblocking hosted CI — but note hosted enforcement is currently dark, so
landing more functional work without hosted CI weakens the evidence trail.

### Option C: Self-Hosted Runner

The previously deferred self-hosted CI direction (CI on an old Mac). This removes
GitHub-hosted minute consumption entirely and natively hosts the macOS/iOS jobs,
fully resolving the billing blocker. Heavier setup than Option A and a larger
operational commitment; Option A is the faster path to a runnable CI.

### Option D: Complete WASM Hosted CI

Provision a runner Swift toolchain with matching WASM SDKs to turn the hosted WASM
skips into real compiles. Independent of the billing blocker and lower priority
while hosted minutes are exhausted.

## Recommended Slice 16 Selection

Recommended: **Option A, CI resource optimization.** It is now a blocker for the
project's own post-merge verification (hosted runners cannot start under the
exhausted Free quota), it does not touch `TextEngineCore`, and it implements the
two levers the user selected: move the host/benchmark job to a 1x Linux host with
a Debian Swift container, and stop spending macOS minutes on docs-only commits.
The slice must include a re-baseline of the nanosecond benchmark budgets on the
new runner and a decision on the host-specific `--memory-observation` step.

Choose Option C instead if the project prefers to invest once in self-hosted
infrastructure that also fixes the billing wall; choose Option B only if
functional momentum outranks restoring hosted CI evidence.

## Slice 15 Review Conclusion

Slice 15 cleanly delivers its two goals: it promotes the variable-height
benchmark to a blocking CI gate and consolidates variable-height memory-shape
diagnostics onto the shared `MemoryShapeSummary` model and formatter, preserving
the variable core-owned-byte estimate and per-provider cross-row consistency. It
fully implements the approved design and plan, makes no `TextEngineCore` change,
and resolves the single confirmed Slice 14 P3 finding. Fresh local verification
is entirely green.

There are no P0/P1/P2 code findings. The one material gap is external: the
post-merge hosted push run could not execute because the GitHub Actions account
hit its spending limit, driven by the 10x macOS multiplier. This makes CI
resource optimization (Slice 16, Option A) the recommended and time-sensitive
next slice.

Count Slice 15 as complete for variable-height CI-gate promotion and
memory-shape diagnostic consolidation. Do not count it as hosted post-merge
proof (billing-blocked), variable-height mutation, hosted WASM closure, or any
CI cost reduction; those remain follow-up work, with CI cost reduction now the
recommended next slice.
