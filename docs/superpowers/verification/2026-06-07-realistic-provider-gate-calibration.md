# Realistic Provider Gate Calibration Verification

Date: 2026-06-07

## Scope

Slice 10 makes `swift run -c release ViewportBenchmarks -- --realistic-provider --gate` valid with calibrated p95/p99 budgets for the existing 100,000-line, 11.2 MB realistic-provider benchmark.

The slice does not change `TextEngineCore`, `Tests`, or `Package.swift`. It does not add memory budgets, storage adapters, variable-height layout, branch protection, rulesets, or cross-target CI.

## Budget Decision

Selected local gate budgets:

```text
budget_p95_ns=20000
budget_p99_ns=50000
```

Local pre-implementation calibration samples:

```text
sample=1 p95_ns=5402 p99_ns=5635
sample=2 p95_ns=5398 p99_ns=5610
sample=3 p95_ns=5482 p99_ns=5720
sample=4 p95_ns=5487 p99_ns=5836
sample=5 p95_ns=5422 p99_ns=5607
max_local_p95_ns=5487
max_local_p99_ns=5836
decision=local_gate_supported
```

## Hosted-Runner Decision

Hosted-runner enforcement was deferred:

```text
ci_enforcement=deferred
reason=hosted-samples-unavailable
hosted_branch=realistic-provider-gate-calibration
workflow_access=available
temporary_workflow_step_commit=2cf4b62 ci: run realistic provider benchmark gate
defer_commit=0e5ef82 ci: defer realistic provider benchmark gate
gh_run_list_branch_command=gh run list --workflow "Swift CI" --branch "realistic-provider-gate-calibration" --limit 10 --json databaseId,status,conclusion,headBranch,headSha
gh_run_list_branch_result=[]
hosted_gate_samples_recorded=0
at_least_3_hosted_gate_samples_recorded=false
workflow_step_final_state=not_added
```

GitHub access existed and the branch was pushed, but branch-specific Swift CI run queries returned no runs, so no hosted gate samples could be collected.

The workflow trigger in `.github/workflows/swift-ci.yml` is `pull_request` and `push` to `main`, so the pushed feature branch did not produce Swift CI samples.

A failing workflow step is not described as merge-blocking because repository policy controls required status checks.

## Verification Commands

### Host Tests

Command:

```text
swift test
```

Result: pass, 39 XCTest tests, 0 failures.

### Release Build

Command:

```text
swift build -c release
```

Result: pass.

### Default Pipeline Benchmark

Command:

```text
swift run -c release ViewportBenchmarks
```

Result: pass, three `mode=pipeline` rows.

### Range-Only Benchmark

Command:

```text
swift run -c release ViewportBenchmarks -- --range-only
```

Result: pass, three `mode=range_only` rows.

### Synthetic Benchmark Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --gate
```

Result: pass, three `mode=pipeline` rows with `gate=pass`.

### Realistic Provider Benchmark

Command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider
```

Result: pass.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5284 p99_ns=5416 failures=0 checksum=756321289736960
no_budget_gate_fields=true
```

### Realistic Provider Benchmark Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Result: pass.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5368 p99_ns=5508 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

### Realistic Provider Gate Failure Check

Temporary budgets:

```text
budget_p95_ns=1
budget_p99_ns=1
```

Command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Result: expected non-zero exit with `gate=fail`.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5277 p99_ns=5452 failures=0 budget_p95_ns=1 budget_p99_ns=1 gate=fail checksum=756321289736960
exit=1
```

The temporary override was restored before final verification.

### Restored Realistic Provider Benchmark Gate

Command:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

Result: pass.

```text
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5365 p99_ns=5512 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=756321289736960
```

### Memory-Shape Diagnostic

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-shape
```

Result: pass, three `mode=memory_shape` rows with `invariant=pass`.

### RSS Memory Observation Diagnostic

Command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Result: pass, three `mode=memory_observation` rows with `observation=pass`.

## Invalid CLI Matrix

The following commands exited non-zero with the expected `error=` messages:

```text
swift run -c release ViewportBenchmarks -- --range-only --gate -> error=--range-only cannot be combined with --gate
swift run -c release ViewportBenchmarks -- --range-only --realistic-provider -> error=--realistic-provider cannot be combined with --range-only
swift run -c release ViewportBenchmarks -- --realistic-provider --memory-shape -> error=--realistic-provider cannot be combined with --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider -> error=--memory-observation cannot be combined with --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape --gate -> error=--memory-shape cannot be combined with --gate
swift run -c release ViewportBenchmarks -- --memory-observation --gate -> error=--memory-observation cannot be combined with --gate
swift run -c release ViewportBenchmarks -- --unknown -> error=unknown argument --unknown
```

`--realistic-provider --gate` is no longer part of the invalid CLI matrix.

## Workflow Wiring

Workflow enforcement was deferred, so the final workflow does not include the realistic-provider gate step:

```text
Run realistic provider benchmark gate: not added
```

Workflow edit status:

```text
temporary_workflow_step_commit=2cf4b62 ci: run realistic provider benchmark gate
defer_commit=0e5ef82 ci: defer realistic provider benchmark gate
workflow_step_final_state=not_added
```

## Non-Goal Checks

Command:

```text
git diff "$(git log --format=%H --grep='docs: plan realistic provider gate calibration' -n 1)"..HEAD -- Sources/TextEngineCore Tests Package.swift
```

Result: no output.
