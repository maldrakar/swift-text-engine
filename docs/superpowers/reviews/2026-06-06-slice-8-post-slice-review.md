# Slice 8 Post-Slice Review

Date: 2026-06-06

## Scope Reviewed

This review covers Slice 8: viewport benchmark executable decomposition.

Reviewed artifacts:

- `docs/initial-project-brief.md`
- `docs/superpowers/reviews/2026-06-06-slice-7-post-slice-review.md`
- `docs/superpowers/specs/2026-06-06-viewport-benchmarks-decomposition-design.md`
- `docs/superpowers/plans/2026-06-06-viewport-benchmarks-decomposition.md`
- `Sources/ViewportBenchmarks/*.swift`
- `docs/superpowers/verification/2026-06-06-viewport-benchmarks-decomposition.md`
- local git commit history for Slice 8

No `AGENTS.md`, `CLAUDE.md`, or top-level `README.md` project-conventions file
is present in the repository, so review uses the product brief, existing slice
documents, and universal review heuristics.

## Product Brief Alignment

The product brief asks for a headless text rendering engine core with stable
scroll performance on 100k+ lines and >10 MB documents, strict virtualization,
external document storage, bounded core-owned memory, iOS/WASM source
compatibility, and regression benchmarks that block merge when performance
degrades.

Slice 8 is not a new product-capability slice. It is a behavior-preserving
maintainability slice for the host-only benchmark executable. That still matters
for the product brief because the remaining proof work is concentrated in
`ViewportBenchmarks`: allocator/RSS observation, realistic-provider budget
calibration, hosted-runner variance samples, and additional diagnostics would
all be harder and riskier if they continued to accumulate in one 1,000-line
entrypoint.

Slice 8 directly addresses these project needs:

- `Sources/ViewportBenchmarks/main.swift` is reduced from the overgrown
  benchmark harness to a 10-line process entrypoint.
- CLI parsing, process dispatch, shared models, shared benchmark mechanics,
  synthetic benchmarks, realistic-provider benchmarks, and memory-shape
  diagnostics now have separate files.
- Existing benchmark modes, invalid flag behavior, output keys, scenario names,
  budgets, checksums, and process exit behavior are preserved by the recorded
  command matrix.
- `TextEngineCore`, `Tests`, `Package.swift`, and `.github/workflows/swift-ci.yml`
  are unchanged by the source refactor.
- The Slice 7 maintainability finding is resolved before adding another
  benchmark or diagnostic mode.

Slice 8 does not yet prove these brief requirements:

- RSS, heap, malloc, allocation-count, or peak-memory budgets.
- Repository settings that require `Swift CI` before `main` can change.
- Realistic-provider p95/p99 budgets.
- Hosted-runner variance for realistic-provider or memory observations.
- Cross-target CI for iOS, WASM, or embedded WASM.
- File-backed, memory-mapped, rope, piece-table, or editor-buffer storage.
- Variable-height layout, localized invalidation, text shaping, rasterization,
  or UI-framework integration.

Those remain out of scope for Slice 8.

## Delivered Design

The executable remains one SwiftPM target, but its internal shape is now
concern-based:

- `main.swift`: macOS availability check, process entry, non-zero exit.
- `BenchmarkOptions.swift`: mode enum, CLI parsing, usage text, invalid flag
  combinations.
- `BenchmarkProgram.swift`: parse and dispatch from CLI arguments to runners.
- `BenchmarkModels.swift`: shared scenario and summary value types.
- `BenchmarkSupport.swift`: shared timing, percentile, deterministic offset,
  provider traversal, and summary formatting helpers.
- `SyntheticBenchmarks.swift`: synthetic line source, synthetic scenarios,
  pipeline and range-only benchmark runners.
- `RealisticProviderBenchmark.swift`: deterministic large-text storage/source
  and realistic-provider benchmark runner.
- `MemoryShapeDiagnostics.swift`: memory-shape scenarios, traversal counts,
  invariant checks, formatting, and diagnostic runner.

The resulting file sizes are:

```text
      52 Sources/ViewportBenchmarks/BenchmarkModels.swift
      95 Sources/ViewportBenchmarks/BenchmarkOptions.swift
      26 Sources/ViewportBenchmarks/BenchmarkProgram.swift
      98 Sources/ViewportBenchmarks/BenchmarkSupport.swift
     360 Sources/ViewportBenchmarks/MemoryShapeDiagnostics.swift
     193 Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift
     171 Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
      10 Sources/ViewportBenchmarks/main.swift
    1005 total
```

This is an exact concern split rather than a size reduction of the target as a
whole. That is the right outcome for Slice 8: the total benchmark behavior did
not shrink or expand, but future changes can land in smaller files.

The caller-facing command surface is unchanged:

```text
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
```

## Verification Evidence Reviewed

The Slice 8 verification document records passing results for:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-shape --gate
```

It also records the full invalid CLI matrix:

```text
swift run -c release ViewportBenchmarks -- --range-only --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --range-only --realistic-provider
swift run -c release ViewportBenchmarks -- --range-only --memory-shape
swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape
swift run -c release ViewportBenchmarks -- --unknown
```

Each invalid command exits non-zero with the expected existing error text.

The recorded workflow scan confirms the status check and benchmark commands are
unchanged:

```text
18:    name: Host tests and benchmark gate
35:      - name: Run synthetic benchmark gate
38:      - name: Run memory shape diagnostic
39:        run: swift run -c release ViewportBenchmarks -- --memory-shape
```

The recorded non-goal diff check has no output for:

```text
git diff -- Sources/TextEngineCore Tests Package.swift .github/workflows/swift-ci.yml
```

## Git History

The Slice 8 commit sequence is:

```text
bffa944 docs: design viewport benchmarks decomposition
35dc8c7 docs: plan viewport benchmarks decomposition
1554b1d refactor: split viewport benchmark executable
c971853 docs: record viewport benchmark decomposition verification
```

The source refactor commit changes only `Sources/ViewportBenchmarks` and is a
pure split by line count:

```text
8 files changed, 995 insertions(+), 995 deletions(-)
```

Current `main` also contains a later `docs: add slice 7 post-slice review`
commit above the Slice 8 verification commit. That is a documentation ordering
blemish: it makes the slice chronology harder to read, but it does not alter
the Slice 8 source scope or benchmark behavior.

## Code Review Findings

No confirmed P0/P1/P2/P3 code findings were found for Slice 8.

The implementation matches the approved behavior-preserving design:

- `main.swift` contains only process entry responsibilities.
- CLI parsing remains centralized and keeps the existing invalid-combination
  errors.
- Mode dispatch is small and explicit.
- Shared helpers are not exposed outside the executable target.
- Synthetic, realistic-provider, and memory-shape concerns no longer share one
  large file.
- No public `TextEngineCore` API, tests, package manifest, or workflow YAML
  changed.

## Risks And Gaps

### Slice 8 Is Structural, Not Product Proof

The slice improves the benchmark harness, but it does not add a new measurement
or product capability. It should be counted as paying down a confirmed
maintainability finding, not as closing a product-brief proof gap.

### Allocator-Level Memory Evidence Is Still Missing

Slice 7 created deterministic memory-shape evidence. Slice 8 preserved and
isolated it. The project still lacks RSS, heap, malloc, allocation-count, or
peak-memory observation.

That is now the most natural source-controlled product-proof candidate because
the benchmark executable is ready for another focused diagnostic without
returning to a 1,000-line `main.swift`.

### Realistic Provider Budgets Still Need Variance Data

The realistic-provider benchmark proves a deterministic 100k-line, 11.2 MB
payload path, but it is not gateable and has no p95/p99 budgets. Hard budgets
should wait until local and hosted-runner variance are sampled enough to avoid
noise-driven failures.

### Cross-Target CI Still Does Not Run On GitHub

Earlier slices locally verified iOS, WASM, and embedded WASM compatibility for
`TextEngineCore`. Slice 8 correctly skipped cross-target verification because
core source did not change. Continuous cross-target CI remains useful, but it
is less urgent until the next public core API or portability-sensitive change.

### Merge Blocking Remains Repository-Setting Dependent

The workflow exists and includes the synthetic benchmark gate plus
memory-shape diagnostic. Slice 6 showed that GitHub rulesets were blocked for
the current private repository state. Slice 8 does not change that operational
gap.

### Variable-Height Layout Remains The Largest Functional Expansion

The fixed-height path now has better benchmark infrastructure, latency gates,
realistic-provider coverage, and deterministic memory-shape evidence.
Variable-height layout is the next meaningful engine capability, but it will
add new state, invalidation behavior, and likely public API decisions. It
should be a deliberate slice with cross-target verification, not mixed with
memory observation or budget calibration.

## Lessons For Slice 9

1. Use the decomposed benchmark target instead of adding another large
entrypoint block.

Any Slice 9 benchmark or diagnostic work should land in the matching concern
file or add one new focused file. `main.swift` should remain process entry only.

2. Treat deterministic memory shape as the baseline for real memory
observation.

The existing memory-shape fields are useful because they separate core-owned
state from provider-owned document bytes. An allocator/RSS slice should reuse
that separation and avoid confusing caller storage with core memory.

3. Keep first allocator/RSS work observational unless variance is understood.

Hard memory budgets in CI are attractive, but noisy memory mechanisms can
create false failures. The first slice should record stable fields and tool
limitations before deciding whether any threshold belongs in CI.

4. Do not retry rulesets without a repository-state change.

Rulesets are still an external blocker. A branch-protection slice is only worth
choosing if repository policy or available GitHub features have changed, or if
the user explicitly selects legacy branch protection as the next priority.

5. Choose variable-height layout only if functional expansion is now more
important than finishing the fixed-height proof envelope.

Variable-height layout is valuable, but it should bring its own design,
localized invalidation tests, fixed-height compatibility checks, and host/iOS/
WASM verification strategy.

## Slice 9 Candidate Options

### Option A: Allocation Or RSS Observation

Add a host-side observational memory diagnostic beyond the deterministic
memory-shape model.

Suggested scope:

- Add a new focused diagnostic in `ViewportBenchmarks`, either in
  `MemoryShapeDiagnostics.swift` if small or in a separate memory-observation
  file if it needs host-specific APIs.
- Measure RSS, peak RSS, malloc statistics, allocation counts, or another
  clearly documented host-side signal.
- Reuse the Slice 7 memory-shape scenarios where possible:
  `100k_lines_80_visible_overscan_5`, `1m_lines_80_visible_overscan_5`, and
  `100k_lines_10mb_text`.
- Keep provider-owned document payload separate from core-owned traversal and
  geometry work.
- Keep hard CI budgets out of scope unless the selected signal is stable enough
  across repeated samples.
- Preserve existing benchmark output and invalid CLI behavior.
- Keep production storage adapters, realistic-provider latency budgets,
  variable-height layout, and GitHub branch protection out of scope.

This is the strongest Slice 9 candidate if product-proof completeness remains
the priority. It builds directly on Slice 7 and is now safer because Slice 8
split the benchmark executable.

### Option B: Variable-Height Layout Foundation

Start the next major core capability: variable-height line indexing and
localized invalidation.

Suggested scope:

- Define the smallest height-index or measurement-cache boundary.
- Preserve the fixed-height fast path and existing public behavior.
- Add offset-to-line and line-to-offset tests.
- Add localized invalidation tests for height changes.
- Repeat host, iOS, WASM, and embedded WASM verification for any public core API
  or portability-sensitive source changes.
- Keep allocator/RSS observation, realistic-provider budgets, and branch
  protection out of scope.

This is the strongest Slice 9 candidate if functional expansion is now more
important than finishing the memory-proof envelope. It is higher risk than
Option A because it touches core behavior and likely public API shape.

### Option C: Realistic Provider Budget Calibration

Calibrate p95/p99 budgets for the realistic-provider benchmark.

Suggested scope:

- Run repeated local realistic-provider samples.
- Optionally gather hosted-runner samples through a temporary diagnostic
  workflow or manual runs.
- Decide whether `--realistic-provider --gate` should become valid, or whether
  a separate gate flag is clearer.
- Keep budgets conservative and document variance.
- Keep allocator/RSS observation and variable-height layout out of scope.

This strengthens the Slice 4 large-text benchmark, but it is less important
than allocator/RSS observation if memory proof remains the main product gap.

### Option D: Cross-Target CI For `TextEngineCore`

Move existing local compatibility checks into GitHub Actions where runner
support is reliable.

Suggested scope:

- Add the cheapest reliable iOS compile check for `TextEngineCore`.
- Investigate hosted-runner support for WASM and embedded WASM Swift SDKs.
- Keep `ViewportBenchmarks` host-only.
- Do not change public core API in the same slice.

This improves continuous portability confidence, but it is best timed with the
next public core API change or when CI setup cost is known to be low.

### Option E: Legacy Branch Protection Instead Of Rulesets

Design and verify a narrow legacy branch-protection rule for `main`, if GitHub
allows it for the current private repository.

Suggested scope:

- Inspect current branch protection through the GitHub API.
- Require the existing `Host tests and benchmark gate` context.
- Require pull requests only if that matches repository policy.
- Record API readback.
- Keep Swift source, benchmark code, workflow YAML, and rulesets unchanged.

This could close the operational merge-blocking gap, but it should only be
chosen if repository enforcement is explicitly the next priority.

## Recommended Slice 9 Selection

Recommended: Option A, allocation or RSS observation.

Reasoning:

- The product brief still contains an explicit memory requirement that is only
  structurally modelled, not allocator- or process-observed.
- Slice 7 gave a deterministic ownership baseline; Slice 8 made the benchmark
  target safe to extend without growing `main.swift` again.
- Allocator/RSS observation is a source-controlled product proof and does not
  depend on external GitHub repository capabilities.
- It should provide useful data before realistic-provider hard budgets or
  variable-height layout introduce more variance and state.
- It can remain observational first, which reduces the risk of noisy CI
  failures while still improving the evidence base.

If the project goal has shifted from proof envelope to functionality, choose
Option B instead and start variable-height layout with a strict design and
cross-target verification plan.

Defer Option C until memory observation or runner variance is clearer. Defer
Option D until the next public core API change or until GitHub runner setup is
known. Defer Option E until repository enforcement is explicitly selected again
or GitHub repository capabilities change.

## Slice 8 Review Conclusion

Slice 8 cleanly completes its approved scope. It resolves the Slice 7
maintainability finding by decomposing `ViewportBenchmarks/main.swift` into
focused files without changing benchmark behavior, core source, tests, package
manifest, or workflow YAML.

The slice should not be treated as closing a new product-brief proof gap. It is
the enabling cleanup that makes the next product-proof slice safer. Slice 9
should usually be allocator/RSS observation unless the user deliberately chooses
to shift priority to variable-height layout.
