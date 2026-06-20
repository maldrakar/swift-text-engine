# Structural-Mutation CI Gate Promotion Verification

Date: 2026-06-20

## Scope

Slice 24 adds the existing `--structural-mutation --gate` benchmark path as a new
blocking step in the required `Host tests and benchmark gate` job.

Changed files:

- `.github/workflows/swift-ci.yml`
- `AGENTS.md`
- `docs/superpowers/specs/2026-06-20-structural-mutation-ci-gate-promotion-design.md`
- `docs/superpowers/plans/2026-06-20-structural-mutation-ci-gate-promotion.md`
- `docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md`

No Swift source, tests, package metadata, benchmark workloads, benchmark budgets,
required status context names, docs-only detector logic, or ruleset settings
changed in this slice.

## Pre-Implementation Red Proof

Before the workflow edit, the host job had no structural-mutation step; the
memory-shape diagnostic immediately followed the variable-height mutation gate:

```text
structural_step_absent
variable_height_mutation_index=7
memory_shape_index=8
steps_between_vh_mutation_and_memory_shape=0
```

The future-state workflow assertion failed before implementation:

```text
structural mutation gate step is absent
future_state_assertion_status=1
```

## Local Benchmark Gates

Command:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Status: `0`

Representative output:

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.09s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1204 p99_ns=1250 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4898 p99_ns=5093 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16398 p99_ns=17051 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
synthetic_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Status: `0`

Representative output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=210 p99_ns=225 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=681 p99_ns=699 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2115 p99_ns=2163 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
variable_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Status: `0`

Representative output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=413 p99_ns=433 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1625 p99_ns=1731 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5073 p99_ns=5293 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
vh_mutation_gate_status=0
```

Command:

```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```

Status: `0`

Representative output:

```text
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1703 p99_ns=1760 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=7653 p99_ns=7800 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=33682 p99_ns=34687 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
structural_gate_status=0
```

The structural output includes `mode=structural_mutation provider=balanced_tree`, `budget_p95_ns=`, `budget_p99_ns=`, and `gate=pass` for all three scenarios.

## Workflow Shape

Command:

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
```

Status: `0`

Output:

```text
yaml_ok
yaml_status=0
```

Workflow assertion:

```text
required_contexts=Host tests and benchmark gate|iOS cross-target compile|WASM cross-target observation
structural_gate_step=ok
structural_order=after_vh_mutation_before_memory_shape
workflow_shape_status=0
```

This proves:

- the three required job contexts are unchanged;
- the structural step is named `Run structural mutation benchmark gate`;
- the structural step invokes `--structural-mutation --gate`;
- the structural step has no `continue-on-error`;
- the structural step sits after the variable-height mutation gate and before the memory-shape diagnostic.

## Durable Guidance

`AGENTS.md` scan:

```text
73:swift run -c release ViewportBenchmarks -- --structural-mutation --gate   # structural insert/delete local gate
101:  (blocking) → `--structural-mutation --gate` (blocking) → `--memory-shape`
104:  variable-height, and structural-mutation gates **fail the job on perf
105:  regression**. Benchmark budgets
agents_scan_status=0
```

## Scope And Hygiene

Command:

```bash
git diff --check
```

Status: `0`

Output:

```text
diff_check_status=0
```

Command:

```bash
git diff --name-only main...HEAD
```

Status: `0`

Output:

```text
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/plans/2026-06-20-structural-mutation-ci-gate-promotion.md
docs/superpowers/specs/2026-06-20-structural-mutation-ci-gate-promotion-design.md
docs/superpowers/verification/2026-06-20-structural-mutation-ci-gate-promotion.md
branch_scope_status=0
```

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore
```

Status: `1`

Output:

```text
foundation_scan_status=1
```

Exit `1` is expected because `rg` found no `Foundation` matches in `Sources/TextEngineCore`.

Command:

```bash
git diff --name-only main...HEAD -- Sources Tests Package.swift
```

Status: `0`

Output:

```text
source_scope_status=0
```

## Hosted PR-Head Evidence

PR:

```text
PR #37: https://github.com/maldrakar/swift-text-engine/pull/37
head SHA: b9725eed2339ac79d995a4bbe53a3fd205ebad7e
Swift CI run: 27869783512
event=pull_request status=completed conclusion=success
```

Required job conclusions from the PR-head Swift CI run:

```text
Host tests and benchmark gate=success
iOS cross-target compile=success
WASM cross-target observation=success
```

Host job structural gate step:

```text
Run structural mutation benchmark gate=success
Host tests and benchmark gate	Run structural mutation benchmark gate	2026-06-20T11:31:42.3171755Z ##[group]Run swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate
Host tests and benchmark gate	Run structural mutation benchmark gate	2026-06-20T11:31:42.3172751Z swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate
Host tests and benchmark gate	Run structural mutation benchmark gate	2026-06-20T11:32:52.8587175Z mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=3002 p99_ns=3112 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
Host tests and benchmark gate	Run structural mutation benchmark gate	2026-06-20T11:32:52.8622993Z mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=12493 p99_ns=13130 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
Host tests and benchmark gate	Run structural mutation benchmark gate	2026-06-20T11:32:52.8625926Z mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=45106 p99_ns=46888 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

The PR-head workflow at `b9725eed2339ac79d995a4bbe53a3fd205ebad7e` contains the structural step with no `continue-on-error` on that step:

```text
pr_head_structural_gate_step=ok
```

## Post-Merge Push Evidence

Post-merge evidence is added after the Slice 24 PR is merged and the `main` push Swift CI run for the merge commit completes.

Required evidence:

- merge commit SHA;
- push run ID;
- all three required jobs `success`;
- host job structural gate step `success`;
- hosted structural rows include `gate=pass` and budget fields.
