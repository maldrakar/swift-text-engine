# Variable-Height CI Gate Promotion Design

Date: 2026-06-12

## Status

Approved design. Slice 15 promotes the variable-height benchmark from hosted
observation to a hosted CI-failing gate and folds in the Slice 14 post-slice
review's P3 cleanup for memory-shape diagnostics. The slice does not change
`TextEngineCore` public API or variable-height layout behavior.

## Source Context

This design is Slice 15 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slice 14 delivered the static variable-height layout foundation:

- `LineMetricsSource`, `UniformLineMetrics`, and `VariableViewportInput`;
- `ViewportVirtualizer.compute(_:metrics:)` for variable-height ranges;
- `VariableLineGeometryCursor` for buffered per-line geometry;
- direct fixed-vs-variable equivalence tests for uniform metrics;
- deterministic query-count tests for O(log N) range compute and O(buffer)
  geometry traversal;
- a local `--variable-height --gate` benchmark mode;
- hosted variable-height benchmark observation in Swift CI;
- variable-height memory-shape scenarios for `variable_uniform`.

Slice 14 intentionally kept the hosted variable-height benchmark
observation-only. The approved Slice 14 design states that CI-failing promotion
should be a follow-up slice after hosted behavior has been observed. The Slice
14 post-slice review recommends that Slice 15 promote the variable-height CI
gate and fold in the only confirmed cleanup finding: `VariableMemoryShapeSummary`
duplicates the existing `MemoryShapeSummary` reporting path.

## Goal

Make variable-height performance regressions fail Swift CI, using the existing
in-code benchmark budgets, and normalize variable-height memory-shape diagnostics
onto the same summary and formatter used by the fixed-height diagnostics.

The result should give the variable-height path the same safety shape as the
fixed synthetic gate: unit tests, local benchmark gate, and hosted CI-failing
gate.

## Non-Goals

- No `TextEngineCore` public API changes.
- No changes to `LineMetricsSource`, variable range computation, or variable
  geometry behavior.
- No provider-side mutation, Fenwick tree, B-tree, or localized update structure.
- No collapsed or hidden zero-height line support.
- No hosted WASM promotion.
- No repository ruleset or branch-protection change.

## Hosted Evidence Before Promotion

The current budgets in `VariableHeightBenchmark.swift` are intentionally broad:

| Scenario | p95 budget | p99 budget |
| --- | ---: | ---: |
| `1k_lines_20_visible_overscan_0` | 50,000 ns | 100,000 ns |
| `100k_lines_80_visible_overscan_5` | 100,000 ns | 200,000 ns |
| `1m_lines_200_visible_overscan_50` | 250,000 ns | 500,000 ns |

Hosted Swift CI has already observed the variable-height benchmark across
successful runs after the step landed:

| Run | Event | Head | Worst p99 |
| --- | --- | --- | ---: |
| `27385494123` | pull_request | `4a55aee` | 10,782 ns |
| `27403925248` | pull_request | `fbe6d81` | 4,980 ns |
| `27404861416` | push | `7f7df2f` | 9,884 ns |
| `27405729750` | push | `1da34c8` | 3,368 ns |
| `27430943082` | push | `d5964a1` | 3,775 ns |

`4a55aee` is the pre-review head of PR #9. It is kept as conservative hosted
evidence because it ran the same variable-height benchmark scenarios and budgets
(`VariableHeightBenchmark.swift` is unchanged across `4a55aee..fbe6d81`); the
final reviewed head `fbe6d81` also stayed far under budget. The spread across
runs (`3,368` ↔ `10,782 ns`) is treated as hosted-runner variance for promotion
purposes, not as a reason to retune budgets.

The worst recorded hosted p99 is the 1M scenario at `10,782 ns`, against a
`500,000 ns` p99 budget — about 2.2 percent of budget, a ~46x margin. The other
scenarios have similarly large margins. This supports promoting the existing
budgets without retuning.

## Key Decisions

### Decision 1: Promote the existing variable-height gate in CI

The benchmark executable already supports `--variable-height --gate`. Slice 15
should use that exact path in CI rather than adding another budget source or
special workflow-only logic.

Workflow change:

- Rename `Run variable-height benchmark observation` to
  `Run variable-height benchmark gate`.
- Remove `continue-on-error: true`.
- Change the command from
  `swift run -c release ViewportBenchmarks -- --variable-height`
  to
  `swift run -c release ViewportBenchmarks -- --variable-height --gate`.

The step should remain in the existing `host-tests-and-benchmark-gate` job after
the synthetic benchmark gate and before memory diagnostics. A variable-height
regression should fail the job before later diagnostics run.

Rejected alternative: direct YAML budgets. Duplicating budgets in workflow YAML
would create two sources of truth. The existing benchmark model keeps budgets
with the scenario definitions and prints the same `gate=pass|fail` lines locally
and in CI.

### Decision 2: Keep current budgets

The current variable-height budgets are already wide enough for hosted runners.
The largest hosted p99 recorded before promotion is about 2.2 percent of the 1M
scenario p99 budget. Retuning now would add noise without improving the slice's
core purpose.

Future slices can tighten budgets after more hosted history exists, but this
promotion slice should focus on turning regressions into check failures.

### Decision 3: Consolidate memory-shape summaries

Slice 14 added a separate `VariableMemoryShapeSummary`,
`formatVariableMemoryShapeSummary`, and variable-specific print loop. That
duplicates the existing memory-shape model and makes future output or invariant
changes easier to drift.

Slice 15 should remove the variable-specific summary and formatter:

- `runVariableMemoryShapeScenario(lineCount:)` returns `MemoryShapeSummary`.
- `runMemoryShapeDiagnostics()` appends variable summaries to the same
  formatting loop used by fixed-height scenarios.
- `providerName` is `variable_uniform`.
- `scenarioName` keeps the current
  `"<lineCount>_lines_80_visible_overscan_5"` shape.
- `lineCount`, `visibleLines`, `bufferedLines`, and `geometryLines` are populated
  from the variable compute and geometry traversal.
- `documentBytes` is `nil`.
- `providerLines` is `bufferedLines`.
- `missingLines` is `0`.
- `coreOwnedBytes` stays `variableCoreOwnedBytesEstimate()`, not
  `coreOwnedBytesEstimate()`, because the variable row measures
  `VariableLineGeometryCursor<UniformLineMetrics>` and must not silently change
  to the fixed-height cursor estimate during consolidation.
- `providerOwnedBytes` is `0`.
- `benchmarkOwnedBytes` is `0`.
- `baseInvariantPasses` is the existing variable `traversalPasses` condition:
  the range is ordered and bounded, `visibleLines` matches the expected visible
  count, `bufferedLines` matches the expected buffered count, and
  `geometryLines == bufferedLines`.
- `checksum` keeps the current variable geometry checksum.

`providerLines = bufferedLines` is an explicit schema choice. For the
memory-shape diagnostic, `provider_lines` and `touched_lines` represent the
logical line entries traversed for the viewport proof. The variable path has no
`DocumentLineSource` traversal, but the variable geometry traversal represents
exactly the buffered logical lines. This value is not a metrics query-count
claim; query counts remain covered by dedicated variable-height tests.

The normalized `variable_uniform` rows will now print the full column set from
`formatMemoryShapeSummary`: `visible_lines`, `touched_lines`, `provider_lines`,
`missing_lines`, `provider_owned_bytes`, and `benchmark_owned_bytes`.

The consolidation must also preserve the current cross-variable
`coreOwnedBytes` consistency check. Today (`MemoryShapeDiagnostics.swift:424-459`)
the code has two separate branches: synthetic rows compare against the first
synthetic `coreOwnedBytes`, and the variable scenarios compare against
`referenceVariableCoreOwnedBytes`. After consolidation the merged loop must use
explicit **per-provider** reference selection, and the plan must call this out as
a dedicated step:

- `synthetic` → compare against the first `synthetic` `coreOwnedBytes`;
- `variable_uniform` → compare against the first `variable_uniform`
  `coreOwnedBytes`;
- `large_text` → skip (no consistency comparison, matching today's behavior).

Both naive shortcuts are wrong, in opposite directions. Reusing the current
synthetic-only branch unchanged does **not** make `variable_uniform` falsely
fail — it silently *drops* the cross-variable consistency check, weakening the
invariant. Conversely, a single shared reference across all providers would
falsely compare a `variable_uniform` row (e.g. `coreOwnedBytes` 90) against the
synthetic reference (e.g. 74) and fail a healthy row, because
`variableCoreOwnedBytesEstimate()` and `coreOwnedBytesEstimate()` measure
different cursor types. Only per-provider references are correct.

This check should remain outside `baseInvariantPasses`, because
`baseInvariantPasses` describes one row, while the consistency check is a
cross-row invariant.

### Decision 4: Keep the cleanup local to benchmarks

The memory-shape cleanup should stay in `Sources/ViewportBenchmarks`. It must
not move diagnostic types into `TextEngineCore`, because the core remains
headless, Foundation-free, and independent of benchmark evidence machinery.

## Implementation Notes

The implementation plan should stay small:

1. Drive the cleanup test-first, but honestly: there is **no Swift unit-test
   harness for `ViewportBenchmarks`** today — `Package.swift` declares only the
   `TextEngineCoreTests` target, and nothing under `Tests/` covers memory-shape
   output. This slice does **not** add a Swift unit test for diagnostic-only
   behavior. Instead, the failing-test-first step is an **executable-output
   acceptance check**: run `--memory-shape` and assert the normalized
   `variable_uniform` fields (`visible_lines`, `touched_lines`, `provider_lines`,
   `missing_lines`, `provider_owned_bytes`, `benchmark_owned_bytes`). Before the
   change those fields are absent (check fails); after the change they are present
   with `invariant=pass` (check passes). The plan and verification must state this
   approach explicitly rather than implying a unit test exists.
2. Update `MemoryShapeDiagnostics.swift` to return one summary type and use one
   formatter, with the explicit per-provider `coreOwnedBytes` reference logic from
   Decision 3.
3. Update `.github/workflows/swift-ci.yml` to make the variable-height step
   blocking with `--gate`.
4. Update documentation and verification with the new `--memory-shape` output
   shape and hosted gate evidence. This includes the `AGENTS.md` CI paragraph
   (`AGENTS.md:90-93`), which currently describes `--variable-height` as
   "observation only, `continue-on-error`": change it to `--variable-height
   --gate` as a failing job step. `CLAUDE.md` imports `AGENTS.md` via `@AGENTS.md`,
   so this paragraph is a per-session source of truth and must not go stale. Keep
   the existing no-branch-protection caveat unchanged — that is independent of
   this slice.

## Testing Strategy

Local verification for the implementation slice must include:

```bash
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --variable-height --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
rg -n "Foundation" Sources/TextEngineCore
./.github/scripts/cross-target-compile.sh --self-test
./.github/scripts/cross-target-compile.sh
git diff --check
```

Expected local results:

- `swift test` passes all XCTest tests. (This slice adds no new XCTest target;
  `ViewportBenchmarks` has none — see Implementation Notes #1.)
- Both benchmark gates print `gate=pass`.
- `--memory-shape` prints normalized `variable_uniform` rows through the common
  formatter and every row has `invariant=pass`. This `--memory-shape` output is
  the executable-output acceptance check: it must show the newly normalized
  `variable_uniform` fields (`visible_lines`, `touched_lines`, `provider_lines`,
  `missing_lines`, `provider_owned_bytes`, `benchmark_owned_bytes`) that were
  absent before the cleanup.
- The Foundation-free scan has no matches.
- Cross-target compile still passes blocking iOS targets. WASM behavior follows
  the existing helper contract.

Hosted verification should record:

- the pull-request Swift CI run where the variable-height benchmark step is
  blocking and passes with `gate=pass`;
- the post-merge push run on `main`;
- the variable-height p95/p99/gate lines from those runs.

The post-merge push run remains the strongest hosted evidence for merged code.

## Risks

### Hosted Benchmark Variance

The hosted samples show very wide margins, but hosted runners are still shared
infrastructure. Keeping generous existing budgets is the risk control. If the
new blocking step flakes despite those margins, the right response is to inspect
the run data before loosening budgets or making the step observational again.

### Output Schema Change

`variable_uniform` memory-shape rows will gain the full normalized column set.
This is intentional, but verification records that quote old rows must be
refreshed. There are no known consumers other than local docs and CI logs.

### Local Main Contains Slice 14 Review Commit

Before this design was written, the staged Slice 14 post-slice review was
preserved as `bb983d5 docs: record slice 14 post-slice review`. Slice 15 should
keep its own commits separate from that review commit.

## Success Criteria

- Swift CI treats the variable-height benchmark as a blocking gate.
- Hosted variable-height benchmark output includes `gate=pass` when under the
  current budgets.
- Memory-shape diagnostics use one summary type and one formatter for fixed,
  large-text, and variable-uniform scenarios, with per-provider `coreOwnedBytes`
  consistency preserved.
- `variable_uniform` memory-shape rows report the full normalized column set.
- The `AGENTS.md` CI paragraph describes `--variable-height --gate` as a blocking
  job step (no longer "observation only").
- All local required checks pass.
- Hosted PR and post-merge push Swift CI runs pass.
