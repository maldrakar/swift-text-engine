# Variable-Height Mutation Verification

Date: 2026-06-15

## Scope

Slice 17 adds `TextEngineReferenceProviders`, moves `PrefixSumLineMetrics`
there, adds `FenwickLineMetrics`, proves O(log N) mutation/query behavior, adds
the local `--variable-height-mutation` benchmark gate, and observes that
benchmark in CI.

Raw local command captures are under
`/tmp/swift-text-engine-slice17-verification/`.

## Local Verification

### swift test

```bash
swift test
```

Exit: 0.

```text
Test Suite 'FenwickLineMetricsTests' passed ...
     Executed 8 tests, with 0 failures (0 unexpected)
Test Suite 'SwiftTextEnginePackageTests.xctest' passed ...
     Executed 75 tests, with 0 failures (0 unexpected)
Test Suite 'All tests' passed ...
     Executed 75 tests, with 0 failures (0 unexpected)
Test run with 0 tests in 0 suites passed
```

### Release builds

```bash
swift build -c release
```

Exit: 0.

```text
Build complete! (0.08s)
```

```bash
swift build -c release --target TextEngineReferenceProviders
```

Exit: 0.

```text
Build of target: 'TextEngineReferenceProviders' complete! (0.06s)
```

### Synthetic benchmark gate

```bash
swift run -c release ViewportBenchmarks -- --gate
```

Exit: 0.

```text
mode=pipeline scenario=1k_lines_20_visible_overscan_0 ... p95_ns=1221 p99_ns=1262 ... gate=pass
mode=pipeline scenario=100k_lines_80_visible_overscan_5 ... p95_ns=4847 p99_ns=5016 ... gate=pass
mode=pipeline scenario=1m_lines_200_visible_overscan_50 ... p95_ns=16185 p99_ns=16953 ... gate=pass
```

### Variable-height benchmark gate

```bash
swift run -c release ViewportBenchmarks -- --variable-height --gate
```

Exit: 0.

```text
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 ... p95_ns=205 p99_ns=231 ... gate=pass
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 ... p95_ns=670 p99_ns=697 ... gate=pass
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 ... p95_ns=2052 p99_ns=2092 ... gate=pass
```

### Variable-height mutation observation and gate

Ungated observation:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation
```

Exit: 0.

```text
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 ... p95_ns=372 p99_ns=388 failures=0
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 ... p95_ns=1496 p99_ns=1554 failures=0
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 ... p95_ns=4643 p99_ns=4746 failures=0
```

The original placeholder budgets were tightened during Task 8 after local
observation showed hundreds of times more headroom than a useful local gate
needs. Final local-gate budgets are:

```text
1k:  p95=5_000,  p99=10_000
100k: p95=20_000, p99=25_000
1m:  p95=60_000, p99=75_000
```

Gated run:

```bash
swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
```

Exit: 0.

```text
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 ... p95_ns=390 p99_ns=423 ... budget_p95_ns=5000 budget_p99_ns=10000 gate=pass
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 ... p95_ns=1577 p99_ns=1647 ... budget_p95_ns=20000 budget_p99_ns=25000 gate=pass
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 ... p95_ns=4954 p99_ns=5057 ... budget_p95_ns=60000 budget_p99_ns=75000 gate=pass
```

### Memory diagnostics

```bash
swift run -c release ViewportBenchmarks -- --memory-shape
```

Exit: 0.

```text
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text ... invariant=pass
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 ... invariant=pass
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 ... invariant=pass
```

```bash
swift run -c release ViewportBenchmarks -- --memory-observation
```

Exit: 0.

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 ... observation=pass
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 ... observation=pass
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text ... observation=pass
```

### Foundation-free scans

```bash
rg -n "Foundation" Sources/TextEngineCore
```

Exit: 1, no matches.

```bash
rg -n "Foundation" Sources/TextEngineReferenceProviders
```

Exit: 1, no matches.

### Workflow/helper checks

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/swift-ci.yml'); puts 'yaml_ok'"
```

Exit: 0.

```text
yaml_ok
```

```bash
./.github/scripts/cross-target-compile.sh --self-test
```

Exit: 0.

```text
self_test=pass
```

```bash
git diff --check
```

Exit: 0, no output.

## Hosted Evidence

PR run: TODO after PR is opened.

Post-merge push run on `main`: TODO after merge. Per AGENTS.md, final merged
code proof should be anchored on this post-merge push run.
