# Slice 17 Post-Slice Review

Date: 2026-06-15

## Scope Reviewed

This review covers Slice 17: variable-height mutation / indexed provider. It was
merged through PR #16 (`slice-17-variable-height-mutation`) into `main` as merge
commit `829845ed1b4eec7f4570834b003e6ab6e5963f7e`
(`Merge pull request #16 from maldrakar/slice-17-variable-height-mutation`).
The follow-up docs-only verification refresh landed directly on `main` as
`fe3ed83` (`docs: record variable-height mutation post-merge run`).

Reviewed artifacts:

- `docs/superpowers/specs/2026-06-14-variable-height-mutation-design.md`
- `docs/superpowers/plans/2026-06-14-variable-height-mutation.md`
- `docs/superpowers/verification/2026-06-14-variable-height-mutation.md`
- `docs/superpowers/reviews/2026-06-14-slice-16-post-slice-review.md`
- `AGENTS.md` / `CLAUDE.md` as current repository conventions
- PR #16 metadata, final PR-head hosted run, merge commit, post-merge push run,
  and the docs-only post-merge verification commit
- Slice 17 implementation diff (`1944c67..a9e291b`)
- Post-merge verification-doc refresh (`829845e..fe3ed83`)
- Fresh local host tests, release builds, benchmark gates, memory diagnostics,
  Foundation-free scans, cross-target helper self-test, local iOS/WASM helper
  runs, and direct local WASM builds for `TextEngineReferenceProviders`

This is a functional provider/benchmark slice. It deliberately leaves
`Sources/TextEngineCore` and `Tests/TextEngineCoreTests` unchanged.

## Product Brief Alignment

Slice 17 matches the brief's core boundary:

- `TextEngineCore` is untouched: the stateless `ViewportVirtualizer` and
  variable-height geometry cursor remain headless, Foundation-free, and generic
  over `LineMetricsSource`.
- The new O(N) state belongs to `TextEngineReferenceProviders`, outside the
  core. That provider-owned memory is document metrics, not core-owned layout
  cache.
- `FenwickLineMetrics` provides O(log N) `offset(ofLine:)` and O(log N)
  `setHeight(ofLine:to:)`, proving cheap single-line re-measurement without a
  core specialization.
- The core memory invariant remains clean: `--memory-shape` still reports
  `invariant=pass` for all rows.
- Foundation scans are clean for both `Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders`.

The one important scope boundary: hosted cross-target CI still compiles only
`TextEngineCore`. The new provider target is host-built and locally WASM /
embedded-WASM compiled in this review, but it is not yet part of the hosted
cross-target helper surface.

## Delivered Design

Merged PR diff (`1944c67..a9e291b`):

```text
 .github/workflows/swift-ci.yml                     |    4 +
 AGENTS.md                                          |   30 +-
 Package.swift                                      |   11 +-
 Sources/TextEngineReferenceProviders/FenwickLineMetrics.swift |  82 ++
 Sources/TextEngineReferenceProviders/PrefixSumLineMetrics.swift | 24 +
 Sources/ViewportBenchmarks/BenchmarkOptions.swift  |   11 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift  |    2 +
 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift | 2 +
 Sources/ViewportBenchmarks/VariableHeightBenchmark.swift | 20 +-
 Sources/ViewportBenchmarks/VariableHeightMutationBenchmark.swift | 149 +++
 Tests/TextEngineReferenceProvidersTests/FenwickLineMetricsTests.swift | 240 ++++
 docs/superpowers/plans/2026-06-14-variable-height-mutation.md | 1175 ++++++++++++++++++++
 docs/superpowers/specs/2026-06-14-variable-height-mutation-design.md | 325 ++++++
 docs/superpowers/verification/2026-06-14-variable-height-mutation.md | 218 ++++
 14 files changed, 2259 insertions(+), 34 deletions(-)
```

### Reference Provider Target

`Package.swift` now exposes `TextEngineReferenceProviders` as a library product
and target depending on `TextEngineCore`. `ViewportBenchmarks` depends on both
libraries, and `TextEngineReferenceProvidersTests` depends directly on both so it
can test provider behavior and core re-layout composition.

`PrefixSumLineMetrics` moved from the benchmark executable into the provider
library and is now public. That preserves the static O(1)-query / O(N)-rebuild
oracle while making it reusable by benchmarks and provider tests.

### Fenwick Provider

`FenwickLineMetrics` stores `heights` plus a 1-based Binary Indexed Tree. Build
is O(N); `offset(ofLine:)` walks set bits downward; `setHeight(ofLine:to:)`
computes an absolute-height delta from `heights[index]`, updates the line, then
walks `i += i & -i`. Preconditions reject non-finite / non-positive heights and
out-of-range mutation indexes with static messages.

The public `lastUpdateWriteCount` / return value from `setHeight` is honest
instrumentation: it counts real BIT writes and is used by tests and benchmarks
to prove localized work. It is intentionally scoped to the reference provider,
not the core.

### Tests

`FenwickLineMetricsTests` adds 8 tests:

- build offsets equal `PrefixSumLineMetrics`
- first / last / interior / repeated mutation stays equal to a fresh oracle
- offsets remain strictly increasing after mutation
- update write counts are exact for small cases and logarithmic for 1k / 100k /
  1M
- prefix-query walk bound is logarithmic by set-bit count
- re-layout after mutation matches fresh-oracle range and geometry
- core query count stays bounded after mutation

The full suite now reports 75 XCTest tests, up from 67.

### Benchmark And CI

`--variable-height-mutation` is wired through option parsing, dispatch, help
text, and summary formatting. The benchmark mutates one `FenwickLineMetrics`
instance in place, avoids no-op updates, runs `setHeight` -> `compute` -> full
geometry traversal, and consumes mutation/query results in the checksum.

Local gate budgets were tightened during implementation to:

```text
1k:   p95=5_000,  p99=10_000
100k: p95=20_000, p99=25_000
1m:   p95=60_000, p99=75_000
```

CI observes the new mode after the blocking variable-height gate with
`continue-on-error: true` and no `--gate`, matching the Slice 14 -> Slice 15
pattern for introducing a benchmark before promoting it to a hosted gate.

## Verification Evidence Reviewed

Fresh local verification on 2026-06-15:

- `swift test` -> pass, **75 XCTest tests, 0 failures**. The empty Swift Testing
  harness line remains expected.
- `swift build -c release` -> `Build complete!`.
- `swift build -c release --target TextEngineReferenceProviders` -> provider
  target builds in isolation.
- `swift run -c release ViewportBenchmarks -- --gate` -> `gate=pass` for all
  three synthetic rows. Local 1M: `p95_ns=16370 p99_ns=17083`.
- `swift run -c release ViewportBenchmarks -- --variable-height --gate` ->
  `gate=pass` for all three rows. Local 1M: `p95_ns=2138 p99_ns=2274`.
- `swift run -c release ViewportBenchmarks -- --variable-height-mutation` ->
  observation pass. Local 1M: `p95_ns=5165 p99_ns=5368`.
- `swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate`
  -> `gate=pass` for all three rows. Local 1M:
  `p95_ns=5174 p99_ns=5351`, budgets `60000` / `75000`.
- `swift run -c release ViewportBenchmarks -- --memory-shape` -> every row
  `invariant=pass`.
- `swift run -c release ViewportBenchmarks -- --memory-observation` -> every row
  `observation=pass`.
- `rg -n "Foundation" Sources/TextEngineCore` -> no matches.
- `rg -n "Foundation" Sources/TextEngineReferenceProviders` -> no matches.
- `./.github/scripts/cross-target-compile.sh --self-test` -> `self_test=pass`.
- `./.github/scripts/cross-target-compile.sh --targets ios` -> iOS device and
  simulator `result=pass blocking=true`.
- `./.github/scripts/cross-target-compile.sh --targets wasm` -> local WASM and
  embedded WASM `result=pass blocking=false` for `TextEngineCore`.
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineReferenceProviders`
  -> provider target builds.
- `swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineReferenceProviders`
  -> provider target builds.
- `swift run -c release ViewportBenchmarks -- --memory-shape --gate` -> rejected
  with `error=--gate cannot be combined with memory_shape mode`, as expected.
- `git diff --check` -> no output.

### Hosted Evidence

Final PR-head run:

- PR #16 final head `a9e291bada4c6b2d78c7d57f4cb34aeb0e7b1ec2`
- run `27515537441`
- all three jobs `success`
- host job: `swift test` executed 75 tests / 0 failures; synthetic and
  variable-height gates passed; mutation observation emitted
  `mode=variable_height_mutation` rows, with 1M
  `p95_ns=10563 p99_ns=10939`; memory-shape and memory-observation passed
- realistic relative observation ran under bash and reported
  `p95_ratio=1.002525 p99_ratio=0.973474 observation=clean`
- iOS job: iOS device and simulator `result=pass blocking=true`
- WASM job: hosted WASM and embedded WASM skipped with
  `reason=sdk_unavailable blocking=false`, still observational

Post-merge push run:

- merge commit `829845ed1b4eec7f4570834b003e6ab6e5963f7e`
- run `27533521987`
- all three jobs `success`
- host job: `swift test` executed 75 tests / 0 failures; synthetic and
  variable-height gates passed; mutation observation emitted 1M
  `p95_ns=10397 p99_ns=10620`; memory-shape and memory-observation passed
- iOS job: iOS device and simulator `result=pass blocking=true`
- WASM job: hosted WASM and embedded WASM skipped with
  `reason=sdk_unavailable blocking=false`
- realistic relative observation was correctly skipped on the push event

The docs-only verification refresh `fe3ed83` did not trigger Swift CI, which is
expected under the workflow's `paths-ignore` rules for docs-only pushes.

## Git History

Reviewed Slice 17 commit range:

```text
a5edcb2 docs: design variable-height mutation indexed provider
56860db docs: address spec review for variable-height mutation
1b9555f docs: plan variable-height mutation indexed provider
2d15fb7 docs: use portable YAML check in slice 17 plan
7e57db2 refactor: extract reference providers into a library target
8bfafae feat: add FenwickLineMetrics build and O(log N) offset query
e5170fa feat: add FenwickLineMetrics O(log N) setHeight update
040962d test: pin strictly-increasing offsets through mutation
b25ced0 test: pin logarithmic FenwickLineMetrics update write counts
fb7c340 test: bound FenwickLineMetrics prefix-query walk to O(log N)
10a1b47 test: prove cheap correct re-layout after FenwickLineMetrics mutation
b2cd112 feat: add --variable-height-mutation benchmark mode and local gate
189c8f8 ci: observe variable-height mutation benchmark after variable-height gate
34ec6e5 docs: record variable-height mutation verification
80952b2 docs: record variable-height mutation PR run evidence
a9e291b docs: refresh variable-height mutation PR run evidence
829845e Merge pull request #16 from maldrakar/slice-17-variable-height-mutation
fe3ed83 docs: record variable-height mutation post-merge run
```

The implementation commits are bisectable and use conventional prefixes. The
later verification commits are evidence refreshes caused by the PR-head CI loop:
docs-only commits appended to a PR whose full diff includes code still re-run CI.

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None.

### P2 / Production Readiness

None.

### P3 / Minor But Valid

#### P3 - Slice 17 plan checkboxes still show the whole plan as incomplete

`docs/superpowers/plans/2026-06-14-variable-height-mutation.md` was added with
checkbox tracking and still has **48** open `- [ ]` steps and no `- [x]` entries.
Examples include the first implementation step and the final hosted-evidence
step:

```text
- [ ] **Step 1: Add the library target and product to `Package.swift`**
- [ ] **Step 5: After CI is green, record hosted run IDs**
```

The work is actually complete: implementation commits exist, PR #16 is merged,
local verification passes, and the post-merge push run is recorded. The durable
plan therefore disagrees with the durable verification record. This is not a code
or runtime defect, but it weakens the slice paper trail: a later reviewer cannot
tell from the plan which TDD steps were executed versus skipped.

Suggested fix: add a small docs commit marking the completed Slice 17 plan steps
as `- [x]`, or add an explicit note that the plan intentionally remains an
execution script rather than a status ledger. The Slice 16 branch used the first
pattern (`0d0f0ca docs: mark slice 16 plan steps complete`).

## Risks And Gaps

### Mutation Benchmark Is Still Observational In Hosted CI

This is by design for Slice 17. The local `--variable-height-mutation --gate`
passes with wide headroom, and hosted Linux observation is clean, but CI does not
yet fail the host job on mutation benchmark regression. The natural next
benchmark-hardening slice is to promote this mode to a hosted gate after deciding
whether to use the existing local budgets or retune from hosted Linux x86_64
evidence.

### `TextEngineReferenceProviders` Cross-Target Coverage Is Mostly Local

The provider target is Foundation-free and locally builds for host, WASM, and
embedded WASM. Hosted cross-target CI still invokes
`cross-target-compile.sh --targets ios|wasm`, and that helper compiles
`TextEngineCore`, not `TextEngineReferenceProviders`. This is acceptable for
Slice 17 because the core portability contract remains the blocking CI target and
the spec explicitly avoided claiming provider cross-target proof. If
`TextEngineReferenceProviders` is meant to be a supported portable product rather
than a host-side reference/benchmark helper, extend the helper to cover it.

### CI Is Green But Still Advisory

The repo is now public and `main` has active ruleset `17656807` ("Main"), but the
ruleset has no `required_status_checks` rule. A red Swift CI run still blocks
status, not merge. `AGENTS.md` also still says the repo is private and without
branch protection / required checks; that caveat is stale even though its
practical conclusion remains true today. This is the governance gap carried from
the Slice 16 review, not a Slice 17 implementation defect.

### Hosted WASM Still Skips

Unchanged from Slice 16: hosted WASM and embedded WASM remain
`skipped reason=sdk_unavailable` because the Linux container does not provision
matching Swift SDKs. Local WASM and embedded WASM compile in this environment.

## Lessons For The Next Slice

1. The functional provider path is now real: cheap single-line height mutation
   exists outside the core, and re-layout composition is proven against the
   unchanged stateless core.
2. The Slice 14 -> Slice 15 pattern applies again: a benchmark was introduced as
   hosted observation first, and the next performance-hardening step is
   promotion to a blocking hosted gate.
3. The repository governance gap is still open: green/red CI status is advisory
   until required status checks are added to the active `main` ruleset.
4. The provider library is becoming a reusable product. If that product is meant
   to share the core's portability standard, CI should eventually compile it for
   the same cross-target matrix.

## Slice 18 Candidate Options

### Option A: Repository Policy - Require Swift CI Checks + Correct AGENTS.md

Add required status checks for the three Swift CI jobs to the active `main`
ruleset and update `AGENTS.md` so it describes the current public repo + active
ruleset accurately. This closes the repeated "CI is green but advisory" gap and
makes future benchmark gates meaningful at merge time.

### Option B: Promote `--variable-height-mutation` To A Hosted Blocking Gate

Use the Slice 17 local budgets and hosted Linux observations to add
`--variable-height-mutation --gate` as a blocking host-job step. This mirrors
Slice 15's promotion of the variable-height benchmark after Slice 14 observation.
The hosted PR/post-merge numbers are far below the current local budgets, so the
risk is budget calibration rather than algorithmic uncertainty.

### Option C: Cross-Target Provider Coverage

Extend `cross-target-compile.sh` so it can compile both `TextEngineCore` and
`TextEngineReferenceProviders` for the requested targets, then wire the provider
target into local/hosted verification where appropriate. This turns the local
WASM provider proof from this review into durable CI coverage.

### Option D: Line Insert/Delete Provider Design

Design the next functional provider step: dynamic `lineCount` changes. This is a
larger data-structure problem than height mutation because a Fenwick array does
not cheaply support mid-document insert/delete.

## Recommended Slice 18 Selection

Recommended: **Option A, repository policy + AGENTS.md correction.** Slice 17
delivered the functional provider work cleanly, and both PR and post-merge CI are
green. The remaining blocker to treating future gates as real gates is
governance: required status checks still are not enforced, and the durable guide
still describes the old repository state.

Choose Option B next if benchmark hardening outranks governance. It is the direct
technical continuation of Slice 17. Option C is useful if
`TextEngineReferenceProviders` is promoted from reference/benchmark support into
a supported portable library. Option D should wait until the mutation benchmark
and CI policy surfaces are settled.

## Slice 17 Review Conclusion

Slice 17 cleanly delivers the approved variable-height mutation goal. It adds the
provider library, implements `FenwickLineMetrics`, proves mutation correctness
and logarithmic work with focused tests, adds a calibrated local mutation
benchmark gate, observes the new mode in hosted CI, and records current PR and
post-merge evidence. The core remains unchanged, Foundation-free, and O(1) in
core-owned memory.

There are no P0/P1/P2 code or CI findings. The only confirmed finding is a P3
process issue: the Slice 17 plan checkboxes still show all steps as incomplete
after the slice merged. The larger remaining gaps are follow-up work, not Slice
17 defects: mutation benchmark promotion, provider cross-target CI coverage if
the provider product needs it, hosted WASM SDK provisioning, and repository
policy enforcement for required checks.
