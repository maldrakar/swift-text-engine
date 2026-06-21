# Bulk Structural Edits Verification

Date: 2026-06-21

## Summary

Slice 25 adds true-bulk `insertLines(at:heights:)` and
`removeLines(at:count:)` to `BalancedTreeLineMetrics`, proves them with array
oracle and virtualizer integration tests, adds a local
`--bulk-structural-mutation` benchmark gate, and documents the new command in
`AGENTS.md`.

Local verification below was run at implementation head
`6e780d5bd6585ac73488ee7b5ab0a3b31466fc40` before this verification artifact
and checklist update were committed. Hosted PR-head proof for the full
implementation branch and the post-merge push proof are both recorded below.

## Local State

Command:

```bash
git status --short --branch
```

Exit status: `0`.

```text
## slice-25-bulk-structural-edits
```

Command:

```bash
git log --oneline --decorate cb12fd9..HEAD
```

Exit status: `0`.

```text
6e780d5 (HEAD -> slice-25-bulk-structural-edits) docs: document --bulk-structural-mutation gate command
c7a4bf4 feat: add --bulk-structural-mutation benchmark with local gate
d80e955 test: cover mixed bulk/single edits and bulk re-layout composition
2d085ac feat: add O(k + log N) bulk removeLines with slot recycling
e5fc080 feat: add O(k + log N) bulk insertLines to BalancedTreeLineMetrics
082df56 docs: add bulk structural edits implementation plan
44f7c26 docs: address spec review for bulk structural edits
f2789b5 docs: add bulk structural edits design
```

Command:

```bash
git diff --stat cb12fd9..HEAD
git diff --name-only cb12fd9..HEAD
```

Exit status: `0`.

```text
 AGENTS.md                                          |  13 +-
 .../BalancedTreeLineMetrics.swift                  | 160 ++++
 Sources/ViewportBenchmarks/BenchmarkOptions.swift  |  11 +-
 Sources/ViewportBenchmarks/BenchmarkProgram.swift  |   2 +
 .../BulkStructuralMutationBenchmark.swift          | 187 ++++
 .../ViewportBenchmarks/SyntheticBenchmarks.swift   |   2 +
 .../BalancedTreeLineMetricsTests.swift             | 289 +++++++
 .../plans/2026-06-20-bulk-structural-edits.md      | 948 +++++++++++++++++++++
 .../2026-06-20-bulk-structural-edits-design.md     | 435 ++++++++++
 9 files changed, 2041 insertions(+), 6 deletions(-)
```

```text
AGENTS.md
Sources/TextEngineReferenceProviders/BalancedTreeLineMetrics.swift
Sources/ViewportBenchmarks/BenchmarkOptions.swift
Sources/ViewportBenchmarks/BenchmarkProgram.swift
Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift
Sources/ViewportBenchmarks/SyntheticBenchmarks.swift
Tests/TextEngineReferenceProvidersTests/BalancedTreeLineMetricsTests.swift
docs/superpowers/plans/2026-06-20-bulk-structural-edits.md
docs/superpowers/specs/2026-06-20-bulk-structural-edits-design.md
```

`SyntheticBenchmarks.swift` changed only to add the exhaustive
`.bulkStructuralMutation` precondition branch required after adding the new enum
case.

## Tests And Builds

Command:

```bash
swift test
```

Exit status: `0`.

```text
Test Suite 'BalancedTreeLineMetricsTests' passed
    Executed 32 tests, with 0 failures
Test Suite 'SwiftTextEnginePackageTests.xctest' passed
    Executed 107 tests, with 0 failures
Test Suite 'All tests' passed
    Executed 107 tests, with 0 failures
Swift Testing: 0 tests in 0 suites passed
```

Command:

```bash
swift build -c release
```

Exit status: `0`.

```text
Build complete! (0.08s)
```

Command:

```bash
swift build -c release --target TextEngineReferenceProviders
```

Exit status: `0`.

```text
Build of target: 'TextEngineReferenceProviders' complete! (0.06s)
```

## Benchmark Gates

Command:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Exit status: `0`.

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 p95_ns=1208 p99_ns=1266 gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 p95_ns=4815 p99_ns=4932 gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 p95_ns=15890 p99_ns=16569 gate=pass
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Exit status: `0`.

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 p95_ns=209 p99_ns=237 gate=pass
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 p95_ns=671 p99_ns=703 gate=pass
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 p95_ns=2048 p99_ns=2104 gate=pass
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Exit status: `0`.

```text
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 p95_ns=387 p99_ns=429 gate=pass
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 p95_ns=1541 p99_ns=1619 gate=pass
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 p95_ns=4850 p99_ns=4995 gate=pass
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```

Exit status: `0`.

```text
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 p95_ns=1651 p99_ns=1742 gate=pass
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 p95_ns=7585 p99_ns=7763 gate=pass
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 p95_ns=33741 p99_ns=34898 gate=pass
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
```

Exit status: `0`.

```text
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 p95_ns=3417 p99_ns=3497 gate=pass
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 p95_ns=11086 p99_ns=11259 gate=pass
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 p95_ns=50222 p99_ns=51877 gate=pass
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 p95_ns=66877 p99_ns=69096 gate=pass
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 p95_ns=162018 p99_ns=168570 gate=pass
```

No local budget calibration was needed.

## Diagnostics

Command:

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

Exit status: `0`.

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 invariant=pass
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 invariant=pass
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text invariant=pass
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 invariant=pass
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 invariant=pass
```

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore
rg -n "Foundation" Sources/TextEngineReferenceProviders
```

Exit status: `1` for each command; no output for either command.

Command:

```bash
./.github/scripts/cross-target-compile.sh --self-test
```

Exit status: `0`.

```text
self_test=pass
```

Command:

```bash
git diff --check cb12fd9..HEAD
```

Exit status: `0`; no output.

## CLI Checks

Command:

```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --structural-mutation
```

Exit status: `1` (expected mutual-exclusion failure).

```text
error=--structural-mutation cannot be combined with another mode
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --help
```

Exit status: `0`.

```text
Usage: ViewportBenchmarks [--range-only] [--gate] [--realistic-provider] [--variable-height] [--variable-height-mutation] [--structural-mutation] [--bulk-structural-mutation] [--memory-shape] [--memory-observation] [--help]
--bulk-structural-mutation  Run bulk insert/delete-range+recompute benchmark (balanced-tree provider). Combine with --gate to enforce budgets.
```

## Hosted PR-Head Proof

PR: `#41` (`slice-25-bulk-structural-edits` -> `main`)

Implementation head verified by hosted CI:
`ebb8424b7d5a3e4326ff8f4a93690daa68cb9c4e`

Workflow run: `27895095147`

Command:

```bash
gh pr view 41 --json mergeStateStatus,statusCheckRollup,headRefOid
```

Exit status: `0`.

```text
headRefOid=ebb8424b7d5a3e4326ff8f4a93690daa68cb9c4e
mergeStateStatus=CLEAN
Host tests and benchmark gate: SUCCESS
iOS cross-target compile: SUCCESS
WASM cross-target observation: SUCCESS
```

The host job completed `Run host tests`, synthetic gate, variable-height gate,
variable-height mutation gate, structural mutation gate, memory-shape diagnostic,
RSS memory observation, and PR-only realistic-provider relative observation
successfully. iOS and WASM cross-target jobs also completed successfully.

**Correction (added by the Slice 25 post-slice review, 2026-06-21).** The block
above records the proof against head `ebb8424` / run `27895095147`, but
committing this verification doc produced a **new** PR head
`2f738cddef9ae944551eda2070d2036a3ed4403c` — the head that was actually merged —
which triggered a fresh CI run `27895264320`. PR #41 carries Swift source, so its
full base→head diff is **never** docs-only; the earlier claim that the final head
"received the required contexts through the trusted docs-only shortcut" was
incorrect. Run `27895264320` on `2f738cd` ran the **full heavy path** (all three
required jobs `success`):

```bash
gh run view 27895264320 --json jobs \
  --jq '.jobs[] | select(.name=="Host tests and benchmark gate")
        | .steps[] | "\(.number)\t\(.conclusion)\t\(.name)"'
```

Exit status: `0`.

```text
4   success  Detect PR change scope
5   skipped  Complete docs-only PR          (real source PR, not docs-only)
7   success  Run host tests
8   success  Run synthetic benchmark gate
9   success  Run variable-height benchmark gate
10  success  Run variable-height mutation benchmark gate
11  success  Run structural mutation benchmark gate
12  success  Run memory shape diagnostic
13  success  Run RSS memory observation diagnostic
14  success  Observe realistic provider relative performance
```

So the true merged PR head is `2f738cd`, verified heavy-path by run
`27895264320`; the `ebb8424` / `27895095147` evidence above remains valid for
that earlier commit. The merged-code evidence anchor is the post-merge push proof
recorded below.

## Post-Merge Push Proof

PR `#41` merged to `main` as merge commit
`0db88f5876fa25f76822afb8ffaf60bfbef85042` at `2026-06-21T06:43:28Z`. The merge
brings the bulk-structural-edits implementation onto `main`, so this push run is
the merged-code evidence anchor for Slice 25.

Post-merge push workflow run: `27896284202` (event `push`, branch `main`,
head `0db88f5876fa25f76822afb8ffaf60bfbef85042`).

Command:

```bash
gh run view 27896284202 --json conclusion,event,headSha
gh run view 27896284202 --json jobs --jq '.jobs[] | {name, conclusion}'
```

Exit status: `0`.

```text
conclusion=success event=push headSha=0db88f5876fa25f76822afb8ffaf60bfbef85042
Host tests and benchmark gate: success
WASM cross-target observation: success
iOS cross-target compile: success
```

Step-level conclusions for the `Host tests and benchmark gate` job (verified at
step level, not just the job rollup, per the standing "a green job can hide a
dead continue-on-error step" lesson):

Command:

```bash
gh run view 27896284202 --json jobs \
  --jq '.jobs[] | select(.name=="Host tests and benchmark gate")
        | .steps[] | "\(.number)\t\(.conclusion)\t\(.name)"'
```

Exit status: `0`.

```text
7   success  Run host tests
8   success  Run synthetic benchmark gate
9   success  Run variable-height benchmark gate
10  success  Run variable-height mutation benchmark gate
11  success  Run structural mutation benchmark gate
12  success  Run memory shape diagnostic
13  success  Run RSS memory observation diagnostic
5   skipped  Complete docs-only PR        (real source PR, not docs-only)
14  skipped  Observe realistic provider relative performance  (PR-only)
```

The four blocking latency gates (synthetic, variable-height, variable-height
mutation, structural mutation) plus the memory-shape and RSS diagnostics all ran
`success` on the merge commit, with iOS (blocking) and WASM (observational)
cross-target jobs also `success`. Consistent with this slice's Non-Goals, the new
`--bulk-structural-mutation` gate is **not** wired into CI — it remains a local
gate, with hosted promotion deferred to Slice 26.
