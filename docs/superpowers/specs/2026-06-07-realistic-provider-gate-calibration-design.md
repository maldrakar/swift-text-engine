# Realistic Provider Gate Calibration Design

Date: 2026-06-07

## Status

Approved design, written for user review.

## Source Context

This design is Slice 10 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slices 1 through 9 built and verified the current fixed-height proof envelope:

- fixed-height viewport virtualization;
- external document/source provider traversal;
- synthetic p95/p99 benchmark gate;
- realistic large-text provider benchmark;
- GitHub Actions host tests and synthetic benchmark gate;
- documented GitHub ruleset blocker for the current private repository state;
- deterministic core-owned memory-shape diagnostic and CI wiring;
- concern-based decomposition of `ViewportBenchmarks`;
- host-only RSS memory observation diagnostic and CI wiring.

The product brief requires stable scroll performance on 100,000+ lines and
documents larger than 10 MB. The current synthetic gate is merge-blocking in
the workflow, and the realistic-provider path measures a deterministic
100,000-line, 11.2 MB fixture. That realistic-provider benchmark is still
observational because `--realistic-provider --gate` is currently invalid and
no p95/p99 budgets are attached to the large-text scenario.

Slice 9's post-slice review recommends realistic-provider budget calibration as
the next low-risk proof slice. Slice 10 follows that recommendation.

## Scope

Calibrate and, if safe, enforce p95/p99 budgets for the existing realistic
large-text provider benchmark.

The primary target is:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

The command should become valid, print budget and gate fields, and exit
non-zero when the realistic-provider benchmark exceeds its calibrated budgets
or reports traversal failures.

The workflow should run this gate as a separate merge-blocking step only if
fresh calibration shows enough margin for reliable hosted-runner enforcement.
If hosted-runner samples are unavailable or too noisy, Slice 10 should still
ship the local gateable CLI and record why CI enforcement remains deferred.

## Goals

- Keep `swift run -c release ViewportBenchmarks -- --realistic-provider`
  observational by default.
- Make `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`
  valid.
- Attach calibrated p95 and p99 budgets to the existing
  `100k_lines_10mb_text` realistic-provider scenario.
- Print `budget_p95_ns`, `budget_p99_ns`, and `gate=pass|fail` for
  `--realistic-provider --gate`.
- Exit non-zero when realistic-provider gate output fails its budgets or has
  provider traversal failures.
- Run repeated local calibration samples before selecting final budgets.
- Attempt hosted-runner calibration when the existing GitHub Actions setup can
  expose enough data without committing noisy enforcement.
- Add a GitHub Actions realistic-provider gate step only when calibration
  supports it.
- Preserve existing synthetic gate budgets and output.
- Preserve existing memory-shape and RSS observation output.
- Record verification evidence for calibration, CLI behavior, workflow wiring
  if edited, and non-goal source boundaries.

## Non-Goals

Slice 10 does not:

- change `TextEngineCore` source or public API;
- change `Tests`;
- change `Package.swift`;
- add storage adapters such as memory-mapped files, ropes, piece tables, or
  editor buffers;
- add variable-height layout, localized invalidation, shaping, rasterization,
  or UI integration;
- add RSS, heap, malloc, allocation-count, or peak-memory hard budgets;
- change the existing synthetic benchmark budgets;
- add checked-in baseline comparison;
- require GitHub rulesets or legacy branch protection;
- add iOS, WASM, or embedded WASM CI;
- make `ViewportBenchmarks` portable outside the existing host-only benchmark
  target.

## Selected Approach

Use `--realistic-provider --gate` as the gateable command, with CI fallback.

The command is already semantically clear: `--realistic-provider` selects the
large-text provider scenario, and `--gate` requests budget enforcement. Making
that combination valid keeps the CLI small and aligns with the existing
synthetic path, where `--gate` means p95/p99 enforcement.

The workflow should include a separate realistic-provider gate step only after
calibration supports it. The design intentionally allows a safe fallback: if
hosted-runner variance is too high or sample collection cannot be completed,
Slice 10 still lands the local gateable CLI and records CI enforcement as
deferred. That avoids turning an unstable benchmark into a noisy merge blocker.

### Alternatives Considered

#### Local Gate Only

Add `--realistic-provider --gate` and calibrated local budgets, but never wire
the command into GitHub Actions in this slice.

This is safer operationally, but it leaves the product brief's merge-blocking
performance requirement weaker than necessary if hosted-runner variance is
acceptable.

#### Separate Gate Mode

Add a separate flag such as `--realistic-provider-gate`.

This avoids changing the existing `--realistic-provider --gate` invalid
combination, but it grows the CLI with a redundant mode. The existing option
model can express the intended behavior without a new top-level mode.

#### Immediate CI Enforcement Without Calibration

Pick budgets from old local verification documents and add the workflow step
directly.

This is rejected. Historical local values are useful context, but a
merge-blocking gate needs fresh calibration and, ideally, hosted-runner
evidence from the same workflow environment.

## Architecture

`ViewportBenchmarks` remains one host-only executable target.

Expected file-level responsibilities:

- `BenchmarkOptions.swift` allows `--realistic-provider --gate` and keeps
  unrelated invalid combinations unchanged.
- `BenchmarkProgram.swift` passes `BenchmarkOptions` into realistic-provider
  dispatch.
- `BenchmarkModels.swift` adds realistic-provider budget fields if the
  scenario model needs them.
- `RealisticProviderBenchmark.swift` owns realistic-provider budgets, summary
  construction, gate printing, and pass/fail aggregation.
- `.github/workflows/swift-ci.yml` gains a separate realistic-provider gate
  step only if calibration supports hosted-runner enforcement.
- `docs/superpowers/verification/2026-06-07-realistic-provider-gate-calibration.md`
  records calibration and verification evidence.

No implementation work should move realistic-provider storage fixtures into
`TextEngineCore`. The large 11.2 MB byte payload remains benchmark-owned
provider storage.

## Components

### BenchmarkOptions

Current behavior rejects:

```text
--realistic-provider --gate
```

Slice 10 changes only that part of the parse contract. The following
combinations remain invalid:

```text
--range-only --gate
--range-only --realistic-provider
--range-only --memory-shape
--range-only --memory-observation
--realistic-provider --memory-shape
--realistic-provider --memory-observation
--memory-shape --gate
--memory-shape --memory-observation
--memory-observation --gate
```

The usage text should describe `--realistic-provider` without saying gate
enforcement is impossible.

### RealisticProviderScenario

The existing scenario remains:

```text
provider=large_text
scenario=100k_lines_10mb_text
line_count=100000
document_bytes=11200000
line_bytes=112
visible_lines=80
overscan_before=5
overscan_after=5
```

The scenario should carry calibrated p95 and p99 budgets, either directly as
fields on `RealisticProviderScenario` or through a small scenario-budget helper
near the realistic-provider runner. Direct fields match the current synthetic
`BenchmarkScenario` pattern and are the preferred shape unless implementation
finds a cleaner local convention.

### Realistic Provider Runner

`runRealisticProviderBenchmarks` should accept the parsed gate choice, likely:

```text
runRealisticProviderBenchmarks(enforceGate: Bool) -> Bool
```

When `enforceGate` is false, output remains observational and omits budget
fields.

When `enforceGate` is true, output includes budget fields and `gate=pass|fail`.
The runner returns `false` if any summary fails its gate.

### Benchmark Summary

The existing `BenchmarkSummary` and `formatSummary` already support optional
budget fields and `passesGate`. Slice 10 should reuse that machinery rather
than adding a separate formatter.

## Calibration Policy

Budget values must be selected from fresh Slice 10 evidence, not copied blindly
from older documents.

The implementation plan should gather:

- repeated local `swift run -c release ViewportBenchmarks -- --realistic-provider`
  samples;
- repeated local `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`
  samples after candidate budgets are added;
- hosted-runner samples if the existing GitHub Actions workflow can expose
  enough output safely.

Historical local realistic-provider values provide context:

```text
p95_ns observed range: about 5240 to 6042
p99_ns observed range: about 5405 to 6541
```

Those values came from earlier local verification and review documents. They
are not sufficient by themselves for CI enforcement.

Budget selection rules:

1. Use the highest fresh observed p95 and p99 values as the calibration
   baseline.
2. Choose conservative absolute budgets with clear margin above the observed
   maxima.
3. Keep the budgets loose enough to catch accidental O(total document size)
   work without failing on normal runner variance.
4. Prefer budgets that remain well below the existing synthetic 100,000-line
   pipeline budgets when the comparison is meaningful.
5. Do not add the CI step if the only defensible budgets would be so loose that
   they no longer prove the intended realistic-provider regression risk.

An initial candidate to evaluate is:

```text
budget_p95_ns=20000
budget_p99_ns=50000
```

These candidate values are intentionally conservative relative to historical
local results. The implementation must confirm or adjust them using fresh
Slice 10 samples before committing source changes.

## Data Flow

Ungated realistic-provider data flow remains unchanged:

1. Build the deterministic 100,000-line, 11.2 MB `RealisticDocumentStorage`
   before timed samples begin.
2. Wrap the storage in `RealisticLineSource`.
3. For each sample, compute a deterministic scroll offset.
4. Build `ViewportInput`.
5. Compute the fixed-height `VirtualRange`.
6. Traverse buffered geometry.
7. Traverse buffered provider lines through `DocumentLineCursor`.
8. Fold line payload fields into the checksum.
9. Record per-operation nanoseconds.
10. Sort samples and compute p95/p99.
11. Print one key-value summary line.

Gated data flow adds:

1. Attach p95/p99 budget values to the summary.
2. Evaluate `summary.passesGate`.
3. Print `gate=pass` or `gate=fail`.
4. Return non-zero from the process if any realistic-provider summary fails.

## Error Handling

`--realistic-provider --gate` should fail only for benchmark gate reasons:

- p95 exceeds budget;
- p99 exceeds budget;
- traversal failures are non-zero.

It should not fail because the realistic-provider document allocates 11.2 MB;
that storage is the intended provider fixture and remains outside
`TextEngineCore`.

Existing invalid CLI combinations should keep clear `error=` output and usage
text. Unknown flags remain invalid.

If hosted-runner calibration is unavailable, that is a slice verification
limitation, not a runtime error in `ViewportBenchmarks`.

## CI Strategy

The preferred workflow shape is:

```text
Run host tests
Run synthetic benchmark gate
Run realistic provider benchmark gate
Run memory shape diagnostic
Run RSS memory observation diagnostic
```

The realistic-provider gate should be a separate step, not folded into the
synthetic gate step. Separate steps make CI failures easier to interpret and
keep the existing synthetic gate output unchanged.

The workflow step should be added only if calibration supports it. If the step
is deferred, the verification document must say why and must show that
`--realistic-provider --gate` passes locally with the selected budgets.

## Verification Plan

Required preflight:

```text
git status --short
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

The last preflight command should initially fail with the existing invalid
combination error. That proves the slice changes the intended CLI behavior.

Required calibration:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Run this command repeatedly enough to record a local p95/p99 range before
choosing final budgets. If hosted-runner calibration is attempted, record the
run IDs or workflow evidence used.

Required final local verification:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

Required invalid CLI verification:

```text
swift run -c release ViewportBenchmarks -- --range-only --gate
swift run -c release ViewportBenchmarks -- --range-only --realistic-provider
swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape --gate
swift run -c release ViewportBenchmarks -- --memory-observation --gate
swift run -c release ViewportBenchmarks -- --unknown
```

Required source-boundary checks:

```text
git diff -- Sources/TextEngineCore Tests Package.swift
rg -n "Run realistic provider benchmark gate|--realistic-provider --gate" .github/workflows/swift-ci.yml
```

The workflow scan is required only if `.github/workflows/swift-ci.yml` is
edited.

## Acceptance Criteria

- `--realistic-provider --gate` is valid.
- Ungated `--realistic-provider` output remains one observational
  `mode=realistic_provider` line without budget fields.
- Gated realistic-provider output includes `budget_p95_ns=`,
  `budget_p99_ns=`, `gate=pass|fail`, and `failures=0` on a passing run.
- Gated realistic-provider output exits non-zero when the summary fails its
  budgets or traversal invariants.
- Existing synthetic gate output and budgets are unchanged.
- Existing memory-shape and RSS observation output are unchanged.
- The final budgets are backed by fresh Slice 10 calibration evidence.
- CI includes the realistic-provider gate only if calibration supports
  reliable enforcement.
- The verification document records whether CI enforcement was added or
  deferred, with the reason.
- `TextEngineCore`, `Tests`, and `Package.swift` remain unchanged.
