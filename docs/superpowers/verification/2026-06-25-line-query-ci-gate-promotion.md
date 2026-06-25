# Line-Query CI Gate Promotion Verification

Date: 2026-06-25
Branch: `slice-28-line-query-ci-gate-promotion`
Local verification HEAD: `179a91b`

## Change Scope

`git diff --name-only main...HEAD` - only `.github/workflows/swift-ci.yml`,
`AGENTS.md`, and `docs/**`. No benchmark or core Swift source changed.

Command:

```bash
git diff --name-only main...HEAD
```

Output:

```text
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/plans/2026-06-25-line-query-ci-gate-promotion.md
docs/superpowers/specs/2026-06-25-line-query-ci-gate-promotion-design.md
```

Exit status: `0`

## Workflow-Invariant Assertion

The new step exists, invokes `--line-query --gate`, is not `continue-on-error`,
and is ordered bulk -> line-query -> memory-shape.

Command:

```bash
ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ff85db83-a037-4e01-8c67-32ccd2c40b6b/scratchpad/assert_line_query_gate.rb
```

Output:

```text
workflow_assertions_ok
```

Exit status: `0`

## Line-Query Gate (local)

Command:

```bash
swift run -c release ViewportBenchmarks -- --line-query --gate
```

Output:

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.08s)
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=20 p99_ns=27 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=21 p99_ns=28 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=39 p99_ns=45 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=772 p99_ns=839 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=1336 p99_ns=1491 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
```

Exit status: `0`

## Pre-existing Gates Still Pass

Command:

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1252 p99_ns=1570 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4823 p99_ns=4941 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16062 p99_ns=16554 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

Exit status: `0`

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=210 p99_ns=240 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=674 p99_ns=710 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2068 p99_ns=2128 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

Exit status: `0`

Command:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=378 p99_ns=411 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1537 p99_ns=1619 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4815 p99_ns=4916 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
```

Exit status: `0`

Command:

```bash
swift run -c release ViewportBenchmarks -- --structural-mutation --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1702 p99_ns=1779 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=7717 p99_ns=8031 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=32944 p99_ns=34270 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

Exit status: `0`

Command:

```bash
swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
```

Output:

```text
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3513 p99_ns=3584 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=11161 p99_ns=11350 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=47860 p99_ns=49284 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=65953 p99_ns=67000 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=154385 p99_ns=161940 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

Exit status: `0`

## Host Tests

Command:

```bash
swift test
```

Representative output:

```text
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-06-25 18:58:51.918.
	 Executed 124 tests, with 0 failures (0 unexpected) in 1.989 (1.995) seconds
Test Suite 'All tests' passed at 2026-06-25 18:58:51.918.
	 Executed 124 tests, with 0 failures (0 unexpected) in 1.989 (1.996) seconds
◇ Test run started.
↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
↳ Target Platform: arm64-apple-macosx
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

Exit status: `0`

## Whitespace Check

Command:

```bash
git diff --check
```

Output: empty.

Exit status: `0`

## Foundation-Free Scan

Command:

```bash
rg -n "Foundation" Sources/TextEngineCore; echo "core exit: $?"
```

Output:

```text
core exit: 1
```

Exit status: `0`

## Hosted Proof

Pending - recorded in the post-merge follow-up (Task 4) against the final stable
PR-head SHA and the merge commit, to avoid a stale-on-write hosted record.
