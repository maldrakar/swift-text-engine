# Line-Geometry-Query CI Gate Promotion Verification

Date: 2026-07-03
Branch: `slice-32-line-geometry-query-ci-gate-promotion`
Local benchmark/test verification suite HEAD: `9ff696c`
Branch-scope freshness refresh HEAD: `6102265`

## Change Scope

Branch-scope freshness was refreshed at `6102265` after committing this
verification record. `git diff --name-only main...HEAD` lists only
`.github/workflows/swift-ci.yml`, `AGENTS.md`, and `docs/**`. No benchmark or
core Swift source changed.

```text
$ git rev-parse --short HEAD
6102265
```

```text
$ git diff --name-only main...HEAD
.github/workflows/swift-ci.yml
AGENTS.md
docs/superpowers/plans/2026-07-03-line-geometry-query-ci-gate-promotion.md
docs/superpowers/specs/2026-07-03-line-geometry-query-ci-gate-promotion-design.md
docs/superpowers/verification/2026-07-03-line-geometry-query-ci-gate-promotion.md
```

```text
$ git diff --check
```

`git diff --check` produced no output and exited 0.

## Workflow-Invariant Assertion

The new step exists, invokes `--line-geometry-query --gate`, is not
`continue-on-error`, shares its siblings' docs-only guard, is ordered
line-query -> line-geometry-query -> memory-shape, and the three required job
context names are unchanged.

```text
$ ruby /private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/ec0340fe-af0f-4134-bbba-e6bc467fc71e/scratchpad/assert_line_geometry_query_gate.rb
workflow_assertions_ok
```

## Line-Geometry-Query Gate (local)

The full local benchmark/test verification suite below was run at `9ff696c`,
before committing this verification record. Five local gate rows passed. The
deterministic checksums match the Slice 31 record: `160641440000`,
`267505512960`, `799841600000`, `223985600000`, and `852321495040`.

```text
$ swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
[0/1] Planning build
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.09s)
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=18 p99_ns=23 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=25 p99_ns=30 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=27 p99_ns=32 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=150 p99_ns=188 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=197 p99_ns=247 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=852321495040
```

## Pre-existing Gates Still Pass

```text
$ swift run -c release ViewportBenchmarks -- --line-query --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=13 p99_ns=16 failures=0 budget_p95_ns=30000 budget_p99_ns=60000 gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=17 p99_ns=20 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=24 p99_ns=28 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=94 p99_ns=115 failures=0 budget_p95_ns=300000 budget_p99_ns=600000 gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=121 p99_ns=149 failures=0 budget_p95_ns=600000 budget_p99_ns=1200000 gate=pass checksum=639841547520
```

```text
$ swift run -c release ViewportBenchmarks -- --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1229 p99_ns=1316 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=4946 p99_ns=5076 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16364 p99_ns=16669 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=18852477646272000
```

```text
$ swift run -c release ViewportBenchmarks -- --variable-height --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=216 p99_ns=244 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=671 p99_ns=715 failures=0 budget_p95_ns=100000 budget_p99_ns=200000 gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2070 p99_ns=2160 failures=0 budget_p95_ns=250000 budget_p99_ns=500000 gate=pass checksum=3536425156727040
```

```text
$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=401 p99_ns=454 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1565 p99_ns=1669 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5295 p99_ns=5810 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 gate=pass checksum=3571078666132451
```

```text
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=983 p99_ns=1055 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5134 p99_ns=5448 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=27201 p99_ns=28551 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 gate=pass checksum=3379593298396981
```

```text
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
Building for production...
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build of product 'ViewportBenchmarks' complete! (0.06s)
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2700 p99_ns=2759 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=8117 p99_ns=8236 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=40435 p99_ns=41971 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=61151 p99_ns=62033 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=145604 p99_ns=151309 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 gate=pass checksum=82203678997143
```

## Host Tests

```text
$ swift test
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-07-03 00:57:59.674.
         Executed 160 tests, with 0 failures (0 unexpected) in 2.442 (2.449) seconds
Test Suite 'All tests' passed at 2026-07-03 00:57:59.674.
         Executed 160 tests, with 0 failures (0 unexpected) in 2.442 (2.449) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

## Foundation-Free Scan

```text
$ /bin/zsh -lc 'rg -n "Foundation" Sources/TextEngineCore; printf "core exit: %s\n" "$?"'
core exit: 1
```

## Hosted Proof

Pending - recorded in the post-merge follow-up (Task 4) against the final stable
PR-head SHA and the merge commit, to avoid a stale-on-write hosted record.
