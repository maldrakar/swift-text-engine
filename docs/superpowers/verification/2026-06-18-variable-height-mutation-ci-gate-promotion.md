# Variable-Height Mutation CI Gate Promotion Verification

Date: 2026-06-18

## Scope

Slice 21 promotes the existing `--variable-height-mutation --gate` benchmark path from hosted observation to a blocking step in the required `Host tests and benchmark gate` job.

Changed files:
- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/verification/2026-06-18-variable-height-mutation-ci-gate-promotion.md`

No Swift source, tests, package metadata, benchmark workloads, benchmark budgets, required status context names, docs-only detector logic, or ruleset settings changed.

## Pre-Implementation Red Proof

The pre-Task-2 workflow state was captured from commit `24fed3533d0f505ced7a41377f56b8a95142b8bc`.

Command:

```bash
git show 24fed3533d0f505ced7a41377f56b8a95142b8bc:.github/workflows/swift-ci.yml > /private/tmp/slice-21-pre-workflow.yml
```

Old mutation step extraction:

```text
Observe variable-height mutation benchmark
continue_on_error_present
swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation
pre_workflow_extract_status=0
```

Future-state assertion against the old workflow:

```text
mutation step is not named as a gate
future_state_assertion_status=1
```

This proves the old workflow observed the mutation benchmark with `continue-on-error` and without `--gate`, and it failed the future blocking-gate shape assertion.

## Local Benchmark Gates

Command:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Output:

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.08s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1174 p99_ns=1297 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4820 p99_ns=4968 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=15893 p99_ns=16362 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
synthetic_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=208 p99_ns=236 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=673 p99_ns=705 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2065 p99_ns=2137 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
variable_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=385 p99_ns=408 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1599 p99_ns=1656 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5033 p99_ns=5370 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
mutation_gate_status=0
```

The mutation output includes `budget_p95_ns=`, `budget_p99_ns=`, and `gate=pass` for all three scenarios. The synthetic, variable-height, and mutation gates all exited with status `0`.

## Workflow Shape

YAML parse output:

```text
yaml_ok
yaml_status=0
```

Workflow assertion output:

```text
required_contexts=Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation
mutation_gate_step=ok
mutation_gate_command=swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation --gate
mutation_gate_continue_on_error=absent
workflow_shape_status=0
```

This proves required job contexts are unchanged, the mutation step is named `Run variable-height mutation benchmark gate`, the command includes `--variable-height-mutation --gate`, and the mutation gate step has no `continue-on-error`.

## Durable Guidance

AGENTS scan output:

```text
70:swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate   # mutate+recompute local gate
97:  → `--variable-height --gate` (blocking) → `--variable-height-mutation --gate`
100:  variable-height, and mutation variable-height gates **fail the job on perf
101:  regression**. Benchmark budgets
agents_scan_status=0
```

## Scope And Hygiene

Command:

```bash
git diff --check
```

Output:

```text
diff_check_status=0
```

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore
```

Output:

```text
foundation_scan_status=1
```

Command:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Output:

```text
source_scope_status=0
```

## Hosted PR-Head Evidence

This section must be completed after the PR-head Swift CI run exists. Required future evidence:

- PR number and head SHA.
- Swift CI run ID.
- All three required jobs report `success`: `Host tests and benchmark gate`, `iOS cross-target compile`, and `WASM cross-target observation`.
- The host job step `Run variable-height mutation benchmark gate` reports `success`.
- Hosted mutation rows include `budget_p95_ns=`, `budget_p99_ns=`, and `gate=pass`.
- The committed PR-head workflow has no `continue-on-error` on the mutation step.

## Post-Merge Push Evidence

This section must be completed after the Slice 21 PR is merged and the default-branch push run exists. Required future evidence:

- Merge commit SHA.
- Push run ID.
- All three required jobs report `success`: `Host tests and benchmark gate`, `iOS cross-target compile`, and `WASM cross-target observation`.
- The host job mutation gate step reports `success`.
- Hosted mutation rows include `gate=pass` and the budget fields.
