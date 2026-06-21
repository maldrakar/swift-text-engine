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

Captured after the `deterministicIndex` refactor. All eight `checksum=` values
match the pre-hardening baseline above byte-for-byte; p95/p99 timing differences
are measurement noise and are not part of the equality assertion.

Structural check:
```bash
rg -n "&\* (2_654_435_761|40_503)" Sources/ViewportBenchmarks/
```
Exit status: `1`; no matches.

### `--bulk-structural-mutation --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
```
Exit status: `0`.

```text
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3587 p99_ns=4719 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=11852 p99_ns=12138 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=53016 p99_ns=54747 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=65684 p99_ns=68151 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=164841 p99_ns=174843 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

Checksum comparison against baseline:

```text
1k_lines_batch_64: checksum=82740062444 match
100k_lines_batch_64: checksum=36564666309410 match
1m_lines_batch_64: checksum=1317343499882000 match
100k_lines_batch_4096: checksum=2285022074625 match
1m_lines_batch_4096: checksum=82203678997143 match
```

### `--structural-mutation --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```
Exit status: `0`.

```text
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1751 p99_ns=1832 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=8305 p99_ns=8534 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=35595 p99_ns=36918 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

Checksum comparison against baseline:

```text
1k_lines_20_visible_overscan_0: checksum=200106952336 match
100k_lines_80_visible_overscan_5: checksum=89494497658324 match
1m_lines_200_visible_overscan_50: checksum=3379593298396981 match
```

## Local Gate Sweep

All local checks below were re-run after the workflow hardening landed. Hosted
evidence remains pending until the PR/head and post-merge runs exist.

The eight mutation `checksum=` values from this sweep match the
pre-hardening baseline via the post-hardening equality proof above:
- five bulk-structural-mutation checksums match the baseline byte-for-byte;
- three structural-mutation checksums match the baseline byte-for-byte.

### `swift test`

Command:
```bash
swift test
```
Exit status: `0`.

Representative output:
```text
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-21 11:23:35.141.
	 Executed 107 tests, with 0 failures (0 unexpected) in 1.903 (1.909) seconds
Test Suite 'All tests' passed at 2026-06-21 11:23:35.141.
	 Executed 107 tests, with 0 failures (0 unexpected) in 1.903 (1.909) seconds
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

### `swift run -c release ViewportBenchmarks -- --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --gate
```
Exit status: `0`.

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1281 p99_ns=1516 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4956 p99_ns=5359 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16054 p99_ns=16680 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

### `swift run -c release ViewportBenchmarks -- --variable-height --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```
Exit status: `0`.

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=220 p99_ns=248 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=784 p99_ns=833 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2144 p99_ns=2259 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

### `swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```
Exit status: `0`.

```text
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=390 p99_ns=439 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1596 p99_ns=1936 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5170 p99_ns=5414 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
```

### `swift run -c release ViewportBenchmarks -- --structural-mutation --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```
Exit status: `0`.

```text
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1793 p99_ns=2160 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=8419 p99_ns=8795 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=35796 p99_ns=36902 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

### `swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate`

Command:
```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
```
Exit status: `0`.

```text
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3703 p99_ns=4628 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=11965 p99_ns=12238 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=53535 p99_ns=55278 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=67044 p99_ns=69992 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=167463 p99_ns=177234 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

### `git diff --check`

Command:
```bash
git diff --check
```
Exit status: `0`.

Representative output: none.

### `rg -n "Foundation" Sources/TextEngineCore`

Command:
```bash
rg -n "Foundation" Sources/TextEngineCore
```
Exit status: `1`.

Representative output: none.

### `ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"`

Command:
```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
```
Exit status: `0`.

```text
yaml_ok
```

### Workflow Step Assertion Re-Run

Command:
```bash
ruby -ryaml -e '
  wf = YAML.load_file(".github/workflows/swift-ci.yml")
  steps = wf["jobs"]["host-tests-and-benchmark-gate"]["steps"]
  names = steps.map { |s| s["name"] }
  bulk = steps.find { |s| s["name"] == "Run bulk structural mutation benchmark gate" }
  raise "missing bulk gate step" unless bulk
  raise "bulk gate not invoking --bulk-structural-mutation --gate" unless bulk["run"].include?("--bulk-structural-mutation --gate")
  raise "bulk gate must not be continue-on-error" if bulk["continue-on-error"]
  i_struct = names.index("Run structural mutation benchmark gate")
  i_bulk   = names.index("Run bulk structural mutation benchmark gate")
  i_mem    = names.index("Run memory shape diagnostic")
  raise "bad gate ordering" unless i_struct && i_bulk && i_mem && i_struct < i_bulk && i_bulk < i_mem
  puts "workflow_assertions_ok"
'
```
Exit status: `0`.

```text
workflow_assertions_ok
```

## Hosted Evidence

_Filled in the post-merge follow-up (PR-head run, post-merge push run)._ Pending.
