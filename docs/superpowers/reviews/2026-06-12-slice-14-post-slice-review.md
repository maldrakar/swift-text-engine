# Slice 14 Post-Slice Review

Date: 2026-06-12

## Scope Reviewed

This review covers Slice 14: variable-height layout foundation, merged through
PR #9 (`slice-14-variable-height-layout-foundation`) into `main`.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `AGENTS.md` and `CLAUDE.md` as current repository conventions. These were
  added after Slice 14 by PR #10, so they are review context, not part of the
  Slice 14 diff.
- `docs/superpowers/reviews/2026-06-10-slice-13-post-slice-review.md`
- `docs/superpowers/specs/2026-06-10-variable-height-layout-foundation-design.md`
- `docs/superpowers/plans/2026-06-11-variable-height-layout-foundation.md`
- `docs/superpowers/verification/2026-06-11-variable-height-layout-foundation.md`
- PR #9 metadata, comments/reviews, final PR CI run, merge commit, and
  post-merge push run
- Slice 14 code diff from `67320f0` to `fbe6d81`
- The follow-up evidence-only commit `1da34c8`
- Fresh local host tests, release build, synthetic gate, variable-height gate,
  memory-shape diagnostic, RSS memory observation, cross-target compile helper,
  Foundation-free scan, and `git diff --check`

The code-review panel used six lenses: architecture, code quality, simplicity,
integration, QA, and security. Five lenses found no production-relevant issues.
The simplifier raised one P3 cleanup finding, independently fact-checked and
recorded below.

## Product Brief Alignment

Slice 14 is the first functional expansion after the fixed-height proof
envelope and cross-target CI work. It adds exact variable-height viewport
virtualization while preserving the brief's hard constraints:

- `TextEngineCore` remains headless: no rendering, shaping, rasterization, UI, or
  provider storage enters the core.
- Per-line height data stays outside the core behind `LineMetricsSource`.
- The core owns no per-line state, so core-owned memory remains O(1) with
  document size.
- Variable viewport compute uses provider offset queries and binary search:
  O(log N) offset queries for range compute and O(buffer) queries for geometry.
- The fixed-height API and behavior remain intact; the variable path is
  additive, except for the documented additive `invalidLineMetrics` enum case.
- The core remains Foundation-free and dependency-free.
- iOS portability is continuously checked in hosted CI; WASM portability is
  locally proven and still skipped on the hosted Swift 6.1.2 runner.

The slice deliberately does not solve mutation, localized height-index updates,
collapsed/hidden zero-height lines, real measurement from shaping/rasterization,
storage adapters, WASM CI promotion, branch protection, or CI-failing promotion
of the new variable-height benchmark step.

## Delivered Design

The merged Slice 14 code diff from `67320f0` to `fbe6d81` is:

```text
 .github/workflows/swift-ci.yml                     |   4 +
 .gitignore                                         |   1 +
 Sources/TextEngineCore/LineMetricsSource.swift     |  34 ++++
 Sources/TextEngineCore/VariableLineGeometryCursor.swift | 40 ++++
 Sources/TextEngineCore/VariableViewportVirtualizer.swift | 120 ++++++++++++
 Sources/TextEngineCore/ViewportTypes.swift         |  20 ++
 Sources/TextEngineCore/ViewportVirtualizer.swift   |  74 ++++---
 Sources/ViewportBenchmarks/BenchmarkOptions.swift  |  61 ++----
 Sources/ViewportBenchmarks/BenchmarkProgram.swift  |   2 +
 Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift | 102 ++++++++++
 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift | 2 +
 Sources/ViewportBenchmarks/VariableHeightBenchmark.swift | 189 ++++++++++++++++++
 Tests/TextEngineCoreTests/...                      | 592 +++++++++++++++++++++
 19 files changed, 1175 insertions(+), 66 deletions(-)
```

The slice also adds 2935 lines of design, plan, and verification documentation.

### Core API

`LineMetricsSource` is the new provider-owned vertical metrics boundary:
`lineCount` plus `offset(ofLine:)` over `0...lineCount`. Its contract states that
offsets must be stable for one layout operation and strictly increasing for
positive line heights. The core performs only O(1) checks it can afford
(`offset(0) == 0`, finite/positive total height), and treats mid-document
contract violations as provider precondition failures.

`UniformLineMetrics` gives the variable path a constant-height provider and acts
as the equivalence oracle against the fixed-height implementation.

`VariableViewportInput` carries scroll offset, viewport height, and overscan; it
intentionally omits `lineCount` and `lineHeight`, because those come from the
metrics source.

`ViewportVirtualizer.compute(_:metrics:)` mirrors the fixed-height path:
validate scalars, validate O(1) metrics contract, clamp scroll offset, binary
search visible start and end, then reuse the extracted `bufferedRange` helper.
The fixed-height compute path now also uses `bufferedRange`, preserving one
overscan implementation for both paths.

`VariableLineGeometryCursor` streams `LineGeometry` over the buffered range by
querying consecutive cumulative offsets. It keeps only the current line index,
the end index, and the previous top offset.

### Tests

The test suite grew to 67 XCTest cases. Slice 14 adds:

- value/API checks for `LineMetricsSource`, `UniformLineMetrics`, and
  `VariableViewportInput`;
- variable compute validation and boundary tests;
- zero-height viewport behavior at exact line tops, mid-line offsets, and
  document end;
- non-uniform visible/buffer range tests;
- direct variable-vs-fixed equivalence for uniform metrics;
- query-count tests proving O(log N) compute and O(buffer) geometry traversal;
- variable geometry cursor tests.

The equivalence oracle is scoped honestly: large `Int.max` coverage is a
clamp-only overflow-safety case because `UniformLineMetrics` is not strictly
increasing near `Int.max` when consecutive `Int` values collapse to the same
`Double`.

### Benchmarks And Diagnostics

`ViewportBenchmarks` now has a `--variable-height` mode backed by
`PrefixSumLineMetrics`, deterministic non-uniform heights, p95/p99 summaries,
and local `--gate` enforcement. CI runs the same benchmark observation-only
without `--gate` and with `continue-on-error: true`, exactly as the design
requires.

`--memory-shape` now includes two `variable_uniform` scenarios. Both 100k and 1M
line cases report `geometry_lines == buffered_lines` and the same
`core_owned_bytes`, proving the variable path's core-owned-memory shape does not
grow with document size for the contract-honoring uniform provider.

## Verification Evidence Reviewed

Fresh local verification for this review on 2026-06-12:

```text
swift test
```

Result: pass, 67 XCTest tests, 0 failures. The Swift Testing harness separately
reports `0 tests in 0 suites`, which is expected for this XCTest-only package.

```text
swift build -c release
```

Result: pass.

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass.

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 ... p95_ns=1496 p99_ns=1591 ... gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 ... p95_ns=5461 p99_ns=5674 ... gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 ... p95_ns=17368 p99_ns=18776 ... gate=pass
```

```text
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Result: pass.

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 ... p95_ns=229 p99_ns=257 ... gate=pass
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 ... p95_ns=706 p99_ns=752 ... gate=pass
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 ... p95_ns=2596 p99_ns=2703 ... gate=pass
```

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass, including:

```text
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 ... buffered_lines=90 geometry_lines=90 core_owned_bytes=90 invariant=pass
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 ... buffered_lines=90 geometry_lines=90 core_owned_bytes=90 invariant=pass
```

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass for all three RSS observation scenarios.

```text
rg -n "Foundation" Sources/TextEngineCore
```

Result: no output, exit code `1`. The core remains Foundation-free.

```text
./.github/scripts/cross-target-compile.sh --self-test
```

Result: `self_test=pass`.

```text
./.github/scripts/cross-target-compile.sh
```

Result: pass on the local Swift 6.2.1 / Xcode 26.3 setup:

```text
mode=cross_target_compile target=ios_device result=pass reason=none blocking=true
mode=cross_target_compile target=ios_simulator result=pass reason=none blocking=true
mode=cross_target_compile target=wasm result=pass reason=none blocking=false
mode=cross_target_compile target=wasm_embedded result=pass reason=none blocking=false
mode=cross_target_compile_summary ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass blocking_failures=0 exit=0
```

```text
git diff --check 67320f0d01f830fdff75d49208aee4b87575253b..fbe6d8149a27774ddbf9b98fd6ca2e423120647d
```

Result: no output.

Hosted PR and merge evidence:

- Final PR #9 run `27403925248` at head
  `fbe6d8149a27774ddbf9b98fd6ca2e423120647d` concluded `success`.
  The run checked out PR merge ref `770b29f` and both jobs passed:
  `Host tests and benchmark gate` and `Cross-target compile`.
- The final PR run's hosted cross-target job passed iOS device and iOS simulator
  as blocking targets; hosted WASM and embedded WASM skipped with
  `reason=sdk_unavailable`, same as Slice 13.
- PR #9 merged as `7f7df2f8df9ccc78d3a5e5544bbee715d9632649`.
- Post-merge push run `27404861416` on merge commit `7f7df2f` concluded
  `success`; both jobs passed.
- The verification document was amended in `1da34c8` to record the post-merge
  push run. That commit is documentation-only.

The post-merge push run is the strongest hosted evidence for the merged code.
It reports 67 tests passing, synthetic gate passing, variable-height observation
passing with p99 under 10us for the 1M scenario, variable memory-shape invariant
passing, and iOS cross-target compiles passing.

## Git History

Slice 14's reviewed commit range is:

```text
1881b1e docs: design variable-height layout foundation
7d53e81 docs: harden variable-height layout design after review
431e6fa docs: refine variable-height layout design after second review
bdddbe5 docs: tighten variable-height stability scope and benchmark scaling wording
7ec4fa8 docs: resolve variable-height equivalence finding to direct comparison
97f75d6 docs: plan variable-height layout foundation
c0ed230 docs: address spec/plan review for variable-height layout
550a7b4 docs: fix plan commit hygiene and YAML check
a437f26 docs: complete plan verification set to match spec
b9aa2aa docs: incorporate spec/plan improvements (S1-S6)
ec5a5cd docs: revise variable-height layout planning
559e053 feat: add LineMetricsSource protocol and UniformLineMetrics
cf65225 feat: add VariableViewportInput and invalidLineMetrics error case
a9a0d57 refactor: extract shared bufferedRange helper in ViewportVirtualizer
f44ce21 feat: add variable-height ViewportVirtualizer.compute
fc6d3ec test: prove variable compute matches fixed path for uniform metrics
455895b feat: add VariableLineGeometryCursor
a990078 test: pin variable-height query counts
2c019f7 feat: add --variable-height benchmark mode and local gate
f3cc9fc ci: observe variable-height benchmark after synthetic gate
4a55aee feat: add variable-height memory-shape scenario
d9ecf74 docs: record variable-height layout verification
fbe6d81 Address PR review comments
```

The implementation commits are logically separated: API surface, compute,
equivalence tests, geometry cursor, query-count tests, benchmark mode, CI
observation, memory-shape diagnostics, and review-comment cleanup. The final
`Address PR review comments` commit changes only core helper factoring and the
memory-shape diagnostic, and is covered by the final hosted PR run and
post-merge push run.

After the PR merge:

```text
7f7df2f Merge pull request #9 from arthurbanshchikov/slice-14-variable-height-layout-foundation
1da34c8 docs: record variable-height layout post-merge run
d5964a1 Merge pull request #10 from arthurbanshchikov/docs/agents-md-claude-import
```

`1da34c8` is part of the Slice 14 evidence trail. PR #10 is a repository-guidance
change (`AGENTS.md`, `CLAUDE.md`) and is not part of the Slice 14 implementation.

## Code Review Findings

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None.

### P2 / Production Readiness

None.

### P3 / Minor But Valid

#### P3 - `Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift:110`

`VariableMemoryShapeSummary` duplicates the existing memory-shape result model
for the same diagnostic family. Slice 14 adds a second summary type, a second
formatter, and a second invariant/print loop:

```swift
struct VariableMemoryShapeSummary {
    let scenarioName: String
    let lineCount: Int
    let bufferedLines: Int
    let geometryLines: Int
```

The fact-check read the surrounding code and confirmed that
`runVariableMemoryShapeScenario` already computes enough data to populate most of
the existing `MemoryShapeSummary`: `providerName = "variable_uniform"`,
`documentBytes = nil`, `providerOwnedBytes = 0`, `benchmarkOwnedBytes = 0`,
`missingLines = 0`, `visibleLines` (already computed locally), and the current
traversal invariant in `baseInvariantPasses`. Routing the variable scenarios
through the existing `formatMemoryShapeSummary` and pass loop would keep variable
height as another memory-shape scenario instead of a parallel reporting path.

Production impact is small but real: future changes to memory-shape output
fields or pass/fail logic now have to be mirrored in two paths, which increases
the chance that fixed-height and variable-height diagnostics drift or report
inconsistent evidence.

Suggested fix: delete `VariableMemoryShapeSummary` and
`formatVariableMemoryShapeSummary`; make `runVariableMemoryShapeScenario` return
`MemoryShapeSummary`, then append those summaries to the existing
`runMemoryShapeDiagnostics` formatting and invariant loop.

Two details to scope the fix, both surfaced during independent fact-check:

- `MemoryShapeSummary` has a `providerLines` field that the variable path never
  computes (there is no `DocumentLineSource` traversal on the variable side), so
  the consolidation must pick an explicit value for it — `0`, or alias it to
  `bufferedLines`.
- `formatMemoryShapeSummary` prints a *superset* of the current variable output:
  it adds `visible_lines`, `touched_lines`, `provider_lines`, `missing_lines`,
  `provider_owned_bytes`, and `benchmark_owned_bytes`. Folding the variable
  scenarios into it normalizes them to the full column set (an improvement, not a
  regression) but changes the `--memory-shape` output lines for
  `variable_uniform`, so the verification record's memory-shape evidence must be
  re-captured as part of the cleanup.

Source: `code-simplifier`; verified independently.

## Risks And Gaps

### Variable-Height CI Gate Is Still Observation-Only

This is intentional and matches Decision 6. Local
`--variable-height --gate` enforces the budgets, while hosted CI only observes
`swift run -c release ViewportBenchmarks -- --variable-height` with
`continue-on-error: true`.

The hosted data is encouraging: the post-merge run reports the 1M scenario at
`p95_ns=6456` and `p99_ns=9884`, far below the local gate budget
(`250000` / `500000`). But one or two hosted samples are not the same as a
calibrated CI gate. Promotion should stay a separate slice, as the design says.

### WASM Hosted CI Still Skips

Hosted `macos-latest` ran Swift 6.1.2, so the cross-target helper again skipped
WASM and embedded WASM with `reason=sdk_unavailable`. Local Swift 6.2.1 builds
for both `wasm` and `wasm-embedded` pass, so WASM portability is still proven
locally, not continuously in hosted CI.

This is unchanged from Slice 13. The engineering path is still to pin/provision
a Swift toolchain with matching WASM SDKs, or wait for the hosted image to move
to a matching Swift version.

### Static Query Half Only

Slice 14 intentionally ships only the static query side of variable-height
layout. It does not add a mutable indexed metrics provider, localized height
updates, or any story for line-height mutation after measurement. The stateless
core shape is correct, but the next functional step needs a provider-side
update structure and tests proving cheap re-layout after a single height change.

### Zero-Height Lines Are Explicitly Unsupported

The `LineMetricsSource` contract requires strictly increasing offsets. Collapsed
or hidden lines would require non-decreasing offsets plus a precise tie-break
for equal-offset runs. This is correctly out of scope for Slice 14, but it is a
product capability decision to revisit if hidden/collapsed lines become a real
requirement.

### Repository Policy Still Cannot Require The Check

The synthetic gate, iOS cross-target job, and any future variable-height CI gate
can fail the GitHub check status, but the private repository still cannot
require that check before merge without the branch-protection/ruleset capability
identified in Slice 6. This remains an external policy blocker, not a Slice 14
implementation defect.

## Lessons For Slice 15

1. The variable-height core API is now in place and covered by unit tests,
   deterministic query-count tests, local benchmarks, hosted observation, and
   memory-shape diagnostics.

2. The only confirmed code cleanup is in benchmark diagnostics, not in the core.
   It is safe to fold into the next low-risk infrastructure slice.

3. The new observation-only variable-height benchmark should not stay
   observation-only indefinitely. If hosted margins remain as wide as the
   observed samples, promotion to a CI-failing gate is a small, focused slice.

4. The next major functional value is provider-side mutation/localized update,
   not more core state. The core should remain stateless unless a future
   benchmark proves that anchored/galloping search is needed.

5. Hosted WASM is still a portability-evidence gap. It is independent from the
   variable-height core design and should be scheduled only if the project wants
   hosted portability closure ahead of further functional work.

## Slice 15 Candidate Options

### Option A: Promote Variable-Height CI Gate

Collect a handful of hosted variable-height samples, set the CI budget from the
larger of local/hosted numbers with explicit headroom, and switch the hosted
step from observation-only to `--variable-height --gate` if the margin remains
wide. Fold the P3 memory-shape summary cleanup into this slice because it is the
same benchmark/diagnostic area and does not touch public core API. Note that the
cleanup normalizes the `variable_uniform` lines to the full memory-shape column
set, so plan for re-capturing the `--memory-shape` verification evidence as part
of the same change (see the P3 finding for the `providerLines` and output-superset
details).

This is the cleanest immediate follow-up: Slice 14 deliberately deferred CI
enforcement, and the observed hosted numbers show enough headroom to justify a
focused calibration slice.

### Option B: Variable-Height Mutation / Indexed Provider

Add a reference indexed metrics provider whose single-line height change is a
localized update, with tests proving correct and cheap re-layout after mutation.
The likely shape is provider-side O(log N) updates and O(log N) offset queries
(for example a Fenwick tree or similar cumulative-height index), leaving
`TextEngineCore` stateless.

This is the strongest functional-value follow-up. Choose it if product
capability matters more than first closing the new CI-gate deferral.

### Option C: Complete WASM Hosted CI

Pin or provision a runner Swift toolchain with matching WASM and embedded WASM
SDKs, then turn the hosted WASM skips into real compiles. Keep it observational
until it is stable across hosted runs.

This completes the portability-evidence story, but it is independent of the
variable-height implementation and lower functional value than Option B.

### Option D: Collapsed / Hidden Lines Contract

Relax the metrics contract from strictly increasing to non-decreasing and define
equal-offset-run tie-breaking, with tests. This should wait until hidden or
collapsed lines are a concrete requirement; otherwise it adds ambiguity to a
currently clean contract.

## Recommended Slice 15 Selection

Recommended: Option A, promote the variable-height CI gate, and fold in the P3
memory-shape summary cleanup.

Reasoning:

- Slice 14 intentionally separated feature delivery from CI enforcement. The
  feature is now merged, and the hosted samples show wide margin.
- This is a small, low-risk slice with no public core API changes, so it is the
  right place to tidy the benchmark diagnostic duplication before more
  diagnostics depend on it.
- After Option A, the variable-height path will have the same basic shape as the
  fixed synthetic gate: unit proof, local gate, and hosted CI-failing gate. That
  gives the next functional slice, provider-side mutation/localized update, a
  cleaner performance safety net.

Choose Option B instead if the project wants to keep momentum on functional
capability and accepts leaving the variable-height hosted benchmark
observation-only for one more slice. Choose Option C if hosted WASM proof is now
more important than variable-height depth.

## Slice 14 Review Conclusion

Slice 14 cleanly delivers the variable-height layout foundation. The core stays
stateless, headless, Foundation-free, and provider-driven; the fixed-height path
is preserved; the variable path is covered by direct behavior tests,
equivalence tests, query-count tests, benchmarks, memory-shape diagnostics, local
WASM builds, local cross-target compile, final PR CI, and post-merge push CI.

The only confirmed code finding is a P3 benchmark-diagnostic duplication in
`MemoryShapeDiagnostics.swift`. It does not block the merged slice, but it should
be cleaned up before adding more memory-shape output or promoting related
diagnostics.

Count Slice 14 as complete for the static variable-height query foundation. Do
not count it as localized height mutation, zero-height/collapsed-line support,
hosted WASM proof, or a CI-failing variable-height benchmark gate; those remain
explicit follow-up slices.
