# Verification — Slice 31: geometry-bearing vertical query (`lineGeometryAt`)

Spec: `docs/superpowers/specs/2026-06-29-geometry-bearing-vertical-query-design.md`
Plan: `docs/superpowers/plans/2026-06-29-geometry-bearing-vertical-query.md`
Branch: `slice-31-geometry-bearing-vertical-query`

This slice adds `ViewportVirtualizer.lineGeometryAt(y:metrics:)` (the geometry-bearing
companion to `lineAt`), two public result types (`LineGeometryQuery`,
`LineGeometryLocation`), test coverage, and a **local** `--line-geometry-query --gate`.
No `.github/workflows/swift-ci.yml` change (CI promotion is a follow-up slice).

Commits (branch base `56d4af2` ← `main`):

```
454dedc docs: document lineGeometryAt and --line-geometry-query gate
d468757 feat: add --line-geometry-query benchmark mode and local gate
e62fe45 test: prove balanced-tree lineGeometryAt equals prefix-sum oracle
ada71bd test: prove lineGeometryAt query-count envelope and native dispatch order
c80e227 test: pin lineGeometryAt geometry against uniform oracle and lineAt parity
7e8138e feat: add geometry-bearing lineGeometryAt query
91dbb2e docs: add geometry-bearing vertical query plan
```

## Local verification (run 2026-06-30, macOS, Swift 6.2.1, Xcode 26.3)

### 1. Host tests + release build

```
$ swift test
Test Suite 'All tests' passed ... Executed 160 tests, with 0 failures (0 unexpected) in 2.333 seconds
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.   # empty Swift Testing harness

$ swift build -c release
Build complete!
```

Test count: **160** (Slice 30 baseline 140, +20 new this slice:
`LineGeometryAtTests` 12, `LineGeometryAtEquivalenceTests` 2,
`LineGeometryAtQueryCountTests` 5, plus 1 in `BalancedTreeLineMetricsTests`).

### 2. New gate + all existing gates (all `gate=pass`)

`swift run -c release ViewportBenchmarks -- --line-geometry-query --gate` (new, local):

| scenario | provider | line_count | p95_ns | p99_ns | budget_p95 | budget_p99 | gate |
|---|---|---|---|---|---|---|---|
| uniform_1k | uniform | 1,000 | 20 | 25 | 30,000 | 60,000 | pass |
| uniform_100k | uniform | 100,000 | 18 | 24 | 60,000 | 120,000 | pass |
| uniform_1m | uniform | 1,000,000 | 22 | 27 | 120,000 | 240,000 | pass |
| balanced_tree_100k | balanced_tree | 100,000 | 134 | 167 | 300,000 | 600,000 | pass |
| balanced_tree_1m | balanced_tree | 1,000,000 | 184 | 226 | 600,000 | 1,200,000 | pass |

Checksums (deterministic): uniform_1k=160641440000, uniform_100k=267505512960,
uniform_1m=799841600000, balanced_tree_100k=223985600000,
balanced_tree_1m=852321495040. No budget adjustments were needed.

Existing gates — all `gate=pass`, and **checksums byte-identical to the Slice 30
record** (`docs/superpowers/verification/2026-06-27-compute-native-prefix-search.md`),
confirming this slice touched no shared search/provider path:

- `--gate` (pipeline): 1k=1319670707200, 100k=570448232307200, 1m=18852477646272000 ✓
- `--variable-height --gate`: all pass (prefix_sum)
- `--variable-height-mutation --gate`: all pass (fenwick)
- `--structural-mutation --gate`: all pass (balanced_tree)
- `--bulk-structural-mutation --gate`: all pass (balanced_tree, 5 scenarios)
- `--line-query --gate`: uniform_1k=641440000, uniform_100k=63985556480,
  uniform_1m=639841600000, balanced_tree_100k=63985600000,
  balanced_tree_1m=639841547520 ✓ (identical to Slice 30)

```
$ swift run -c release ViewportBenchmarks -- --memory-shape
... invariant=pass (all scenarios; core_owned_bytes 74/90, missing_lines=0)
```

### 3. Foundation-free scans (no matches → exit 1)

```
$ rg -n "Foundation" Sources/TextEngineCore            # exit 1 (empty)
$ rg -n "Foundation" Sources/TextEngineReferenceProviders   # exit 1 (empty)
```

### 4. Mode-exclusivity + gate-validity negative checks

```
$ swift run -c release ViewportBenchmarks -- --line-geometry-query --line-query
error=--line-query cannot be combined with another mode        # exit 1

$ swift run -c release ViewportBenchmarks -- --memory-shape --gate
error=--gate cannot be combined with memory_shape mode         # exit 1
```

### 5. Cross-target compile (public-API change)

```
$ ./.github/scripts/cross-target-compile.sh --self-test
self_test=pass

$ ./.github/scripts/cross-target-compile.sh
mode=cross_target_compile_summary package=core      ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass
mode=cross_target_compile_overall blocking_failures=0 exit=0
```

iOS device + simulator are blocking-green for both `TextEngineCore` and
`TextEngineReferenceProviders`. WASM + embedded WASM compiled observationally
(matching Swift SDK `swift-6.2.1-RELEASE_wasm` / `-embedded` present this run).

## Hosted verification

PR-head and post-merge hosted evidence, verified live via `gh` at the **step**
level (per the project lesson that a green job can hide a dead
`continue-on-error` step) on 2026-07-02. All three required Swift CI job contexts
passed on the source-bearing PR head and again on merged code.

- PR: [#59 — Slice 31: geometry-bearing vertical query](https://github.com/maldrakar/swift-text-engine/pull/59) (state `MERGED`)
- Full-code PR head: `dff83f63bf34c3374bddad42b5c2324a86c95a89`
- Swift CI `pull_request` run: `28473489678` (event `pull_request`, branch
  `slice-31-geometry-bearing-vertical-query`, conclusion `success`)

### Host tests and benchmark gate — job `84391993880` (`success`)

Ran the full heavy path on the source-bearing PR (step `Complete docs-only PR`
`skipped`, so the PR is correctly classified as **not** docs-only):

```terminal
Detect PR change scope                            -> success
Complete docs-only PR                             -> skipped
Run host tests                                    -> success
Run synthetic benchmark gate                      -> success
Run variable-height benchmark gate                -> success
Run variable-height mutation benchmark gate       -> success
Run structural mutation benchmark gate            -> success
Run bulk structural mutation benchmark gate       -> success
Run line query benchmark gate                     -> success
Run memory shape diagnostic                       -> success
Run RSS memory observation diagnostic             -> success
Observe realistic provider relative performance   -> success
```

All six blocking latency gates ran and passed on hosted Linux. The new
`--line-geometry-query` gate stays **local only** this slice (CI promotion
deferred to Slice 32, mirroring line-query → Slice 28), so the hosted gate list
is unchanged.

### iOS cross-target compile — job `84391993901` (`success`)

iOS device + simulator compile for `TextEngineCore` and
`TextEngineReferenceProviders` (blocking) passed.

### WASM cross-target observation — job `84391993891` (`success`)

WASM + embedded WASM observation (non-blocking) passed.

### Post-merge anchor

PR #59 was merged to `main` by `maldrakar` at 2026-07-02T11:42:45Z as merge
commit `f364b452603c809611e0657144b826b27e1f179c` (parents `56d4af2` +
the verified PR head `dff83f6`). The merged-code push run is the authoritative
evidence anchor for Slice 31, verified live via `gh` at the **step** level on
2026-07-02.

- Post-merge `push` run: `28587326869` (event `push`, branch `main`, head
  `f364b45`, conclusion `success`)
- All three required jobs `success`: Host tests and benchmark gate
  (`84762068561`), iOS cross-target compile (`84762068516`), WASM cross-target
  observation (`84762068490`)

Host job `84762068561` ran the full heavy path on merged code (step
`Complete docs-only PR` `skipped`; all six blocking latency gates ran; the
PR-only realistic-provider observation step is correctly `skipped` on the `push`
event):

```terminal
Complete docs-only PR                             -> skipped
Run host tests                                    -> success
Run synthetic benchmark gate                      -> success
Run variable-height benchmark gate                -> success
Run variable-height mutation benchmark gate       -> success
Run structural mutation benchmark gate            -> success
Run bulk structural mutation benchmark gate       -> success
Run line query benchmark gate                     -> success
Run memory shape diagnostic                       -> success
Run RSS memory observation diagnostic             -> success
Observe realistic provider relative performance   -> skipped
```
