# Bulk-Structural-Mutation CI Gate Promotion Verification

Date: 2026-06-21
Slice: 26
Branch: slice-26-bulk-structural-mutation-ci-gate-promotion

## Pre-Hardening Checksum Baseline (pre-edit tree)

Captured before the `deterministicIndex` refactor, to prove behavior preservation.

### `--bulk-structural-mutation --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
```
Exit status: `0`.

```text
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3587 p99_ns=3837 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=12112 p99_ns=12500 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=53949 p99_ns=55653 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=66666 p99_ns=70335 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=167132 p99_ns=179971 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

### `--structural-mutation --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```
Exit status: `0`.

```text
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1792 p99_ns=1930 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=8568 p99_ns=8905 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=35961 p99_ns=37217 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

## Post-Hardening Checksum Equality

_Filled in Task 2._

## Local Gate Sweep

_Filled in Task 5._

## Hosted Evidence

_Filled in the post-merge follow-up (PR-head run, post-merge push run)._ Pending.
