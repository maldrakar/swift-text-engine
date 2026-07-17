# Slice 40 verification — `--point-geometry-query` promoted to the eleventh blocking CI gate

Branch `slice-40-point-geometry-query-ci-gate-promotion`. Base commit `59bc8bd`
(spec/plan reconciliation). Task commits on top: `2fc6ac8` (Decision 2
relocation: one-printing-step + continue-on-error-is-not-a-gate rules),
`8124983` (workflow-shape test + step collapse), `51ed096` (harvest +
re-derive), `adbdd5b` (AGENTS.md graduation). This record's own commit is
Task 5.

**Verification is evidence, not assertion.** Everything below is raw command
output, either re-run directly by this task or preserved verbatim from the
prior tasks' `/tmp` artifacts (cited by path). Nothing here is prose standing
in for a number.

> **Hosted proof filled post-merge.** The `## Hosted Proof` section below was
> completed by the docs-only follow-up PR after PR #87 merged (merge commit
> `bff3268`), citing the PR-head run `29579314733` and the post-merge `push` run
> `29606487287`. AC11 is discharged there.

---

## 1. The workflow-shape test's red-before state

Command (run by Task 2, **before** editing `.github/workflows/swift-ci.yml`):

```
swift test --filter WorkflowShapeTests 2>&1 | tee /tmp/workflow-shape-red.txt | grep -E "error:|failed|Executed [0-9]+ tests"
```

Full verbatim contents of `/tmp/workflow-shape-red.txt` (42 lines, file preserved on disk):

```
[0/1] Planning build
Building for debugging...
[0/6] Write sources
[1/6] Write swift-version-58A378E29CF047B.txt
[3/6] Emitting module ViewportBenchmarksTests
[4/6] Compiling ViewportBenchmarksTests WorkflowShapeTests.swift
[5/7] Compiling ViewportBenchmarksTests GateFloorTests.swift
[5/7] Write Objects.LinkFileList
[6/7] Linking SwiftTextEnginePackageTests
Build complete! (0.90s)
Test Suite 'Selected tests' started at 2026-07-17 13:40:14.764.
Test Suite 'SwiftTextEnginePackageTests.xctest' started at 2026-07-17 13:40:14.765.
Test Suite 'WorkflowShapeTests' started at 2026-07-17 13:40:14.765.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testExactlyOneStepRunsThePointGeometryQueryBenchmark]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:191: error: -[ViewportBenchmarksTests.WorkflowShapeTests testExactlyOneStepRunsThePointGeometryQueryBenchmark] : XCTAssertEqual failed: ("2") is not equal to ("1") - .github/workflows/swift-ci.yml: 2 steps run --point-geometry-query, want exactly 1 — ["Run point geometry query benchmark (correctness; blocking)", "Point-geometry query benchmark gate (budget observational until Slice 40)"]
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testExactlyOneStepRunsThePointGeometryQueryBenchmark]' failed (0.091 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepCarriesTheDocsOnlyGuard]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepCarriesTheDocsOnlyGuard]' passed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepIsNamedForItsSiblings]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:238: error: -[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepIsNamedForItsSiblings] : XCTAssertEqual failed: ("Run point geometry query benchmark (correctness; blocking)") is not equal to ("Run point geometry query benchmark gate") - step running --point-geometry-query is named "Run point geometry query benchmark (correctness; blocking)", want "Run point geometry query benchmark gate"
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:238: error: -[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepIsNamedForItsSiblings] : XCTAssertEqual failed: ("Point-geometry query benchmark gate (budget observational until Slice 40)") is not equal to ("Run point geometry query benchmark gate") - step running --point-geometry-query is named "Point-geometry query benchmark gate (budget observational until Slice 40)", want "Run point geometry query benchmark gate"
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepIsNamedForItsSiblings]' failed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepIsNotContinueOnError]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:216: error: -[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepIsNotContinueOnError] : XCTAssertNil failed: "true" - Point-geometry query benchmark gate (budget observational until Slice 40): carries continue-on-error: true — a continue-on-error step cannot be a gate; it swallows budget misses, correctness failures and crashes alike
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepIsNotContinueOnError]' failed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepRunsExactlyTheExpectedCommand]' started.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:204: error: -[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepRunsExactlyTheExpectedCommand] : XCTAssertEqual failed: ("| out="${RUNNER_TEMP:-/tmp}/point-geometry-correctness.txt" if swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query > "$out" 2>&1; then echo "point_geometry_query correctness=pass (summary lines withheld from the log by design)" else echo "point_geometry_query correctness=fail; benchmark output follows" cat "$out" exit 1 fi") is not equal to ("swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate") - Run point geometry query benchmark (correctness; blocking): run payload is not the expected single gated command.
  want: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate
  got:  | out="${RUNNER_TEMP:-/tmp}/point-geometry-correctness.txt" if swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query > "$out" 2>&1; then echo "point_geometry_query correctness=pass (summary lines withheld from the log by design)" else echo "point_geometry_query correctness=fail; benchmark output follows" cat "$out" exit 1 fi
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepRunsExactlyTheExpectedCommand]' failed (0.001 seconds).
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic]' started.
Test Case '-[ViewportBenchmarksTests.WorkflowShapeTests testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic]' passed (0.001 seconds).
Test Suite 'WorkflowShapeTests' failed at 2026-07-17 13:40:14.861.
	 Executed 6 tests, with 5 failures (0 unexpected) in 0.095 (0.096) seconds
Test Suite 'SwiftTextEnginePackageTests.xctest' failed at 2026-07-17 13:40:14.861.
	 Executed 6 tests, with 5 failures (0 unexpected) in 0.095 (0.096) seconds
Test Suite 'Selected tests' failed at 2026-07-17 13:40:14.861.
	 Executed 6 tests, with 5 failures (0 unexpected) in 0.095 (0.097) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

**4 of 6 test methods failed, 2 passed — 5 assertion failures total, because
`testThePointGeometryStepIsNamedForItsSiblings` loops over both matched
(pre-collapse) steps and emits one `XCTAssertEqual` failure per step (2), while
the other three failing methods emit exactly one each** (`testExactlyOne...` = 1,
`testIsNotContinueOnError` = 1, `testRunsExactly...` = 1): 2 + 1 + 1 + 1 = 5,
matching the suite summary's `Executed 6 tests, with 5 failures`.

`testThePointGeometryStepCarriesTheDocsOnlyGuard` and
`testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic`
**passed in both the red-before and green-after state.** This is expected, not a
gap in the test's coverage: both pre-collapse steps (the bare correctness step
and the `continue-on-error` gate step) already carried
`if: steps.change-scope.outputs.docs_only_pr != 'true'`, and the two-step region
already sat between the point-query gate and the memory-shape diagnostic — the
collapse changed step *count*, *name*, *payload*, and *`continue-on-error`*, not
step *position* or the *docs-only guard*. A test that stayed red on those two
invariants across the collapse would indicate it was testing something the
collapse never touched, not that the collapse was incomplete.

This is exactly what makes the test a genuine failing-first anchor rather than a
tautology written after the fact: it failed for the four reasons the collapse
was designed to fix (step count, step name, `run:` payload, `continue-on-error`),
and passed for the two invariants the collapse was never going to change.

## 2. The green-after state

Command (run by Task 2, immediately after collapsing the two steps into one):

```
swift test --filter WorkflowShapeTests 2>&1 | grep -E "failed|Executed [0-9]+ tests"
```

Output:

```
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.004 (0.005) seconds
```

The six invariants `WorkflowShapeTests.swift` pins, all green:

1. `testExactlyOneStepRunsThePointGeometryQueryBenchmark` — exactly one step invokes `--point-geometry-query`.
2. `testThePointGeometryStepCarriesTheDocsOnlyGuard` — that step carries the `docs_only_pr` guard.
3. `testThePointGeometryStepIsNamedForItsSiblings` — it is named `Run point geometry query benchmark gate`, matching sibling gate step naming.
4. `testThePointGeometryStepIsNotContinueOnError` — it does not carry `continue-on-error: true`.
5. `testThePointGeometryStepRunsExactlyTheExpectedCommand` — its `run:` payload equals exactly `swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate` (no wrapper, no redirect, no fallback tail).
6. `testThePointGeometryStepSitsBetweenThePointQueryGateAndTheMemoryShapeDiagnostic` — step ordering.

## 3. Workflow text proof (AC1, AC2)

Re-run directly by this task against the current tree (`adbdd5b`):

```
$ grep -c -- '--point-geometry-query' .github/workflows/swift-ci.yml
1
$ grep -c -- '--point-geometry-query --gate' .github/workflows/swift-ci.yml
1
$ grep -c '^        continue-on-error:' .github/workflows/swift-ci.yml
1
$ rg -n "observational|Slice 40|correctness" .github/workflows/swift-ci.yml || echo "no stale two-step text OK"
no stale two-step text OK
```

Exactly one `continue-on-error:` key survives in the whole workflow, and it
belongs to the `realistic-provider` PR-only observation step — untouched by this
slice.

The collapsed step itself, re-read from the current tree:

```
$ rg -n -B1 -A3 "Run point geometry query benchmark gate" .github/workflows/swift-ci.yml
129-
130:      - name: Run point geometry query benchmark gate
131-        if: steps.change-scope.outputs.docs_only_pr != 'true'
132-        run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate
133-
```

## 4. Corpus provenance (AC5)

Re-run directly by this task against `/tmp/corpus-before.tsv` (Task 3's pre-harvest
snapshot) and the current committed corpus:

```
$ wc -l /tmp/corpus-before.tsv docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
    1692 /tmp/corpus-before.tsv
    1949 docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
$ tail -n +2 /tmp/corpus-before.tsv | wc -l
    1691
$ tail -n +2 docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | wc -l
    1948
$ tail -n +2 /tmp/corpus-before.tsv | cut -f1 | sort -u | wc -l
      42
$ tail -n +2 docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | cut -f1 | sort -u | wc -l
      47
```

**1,691 → 1,948 data rows (257 added); 42 → 47 distinct runs (5 new runs).**
(The raw `wc -l` figures, 1692/1949, include the `run_id  mode  scenario  p95_ns
p99_ns` header line — the data-row counts above exclude it.)

Append-only prefix proof:

```
$ head -n $(wc -l < /tmp/corpus-before.tsv) docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | cmp - /tmp/corpus-before.tsv && echo "OLD CORPUS IS BYTE-EXACT PREFIX"
OLD CORPUS IS BYTE-EXACT PREFIX
```

```
$ git diff --numstat main -- docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
257	0	docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
```

257 lines added, 0 deleted — pure append, no reordering, no `sort -u` collapse.

AC5's mandatory run, present in the committed corpus:

```
$ grep -c '^29426572267' docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
45
```

`point_geometry_query`'s post-harvest run count:

```
$ grep 'point_geometry_query' docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | cut -f1 | sort -u | wc -l
      11
```

**`point_geometry_query`: 6 → 11 distinct hosted runs.** The spec's Risks
section carried a residual-risk note against "still under ~10 runs" at the time
of Slice 39's merge; at 11 runs this crosses that line, so the risk noted there
is **retired**, not merely carried forward.

## 5. The derivation sweep (AC6)

Re-run directly by this task, `derive-gate-budgets.sh` with **no mode
argument** (every gated scenario, from the current committed corpus):

```
$ ./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
bulk_structural_mutation|100k_lines_batch_4096 n=45  p95[med=169660 max=246428] p99[med=181983 max=306895] budget_p95=1400000 budget_p99=2800000 margin_p95=5.7x margin_p99=9.1x
bulk_structural_mutation|100k_lines_batch_64   n=45  p95[med=15802  max=23479 ] p99[med=16870  max=25701 ] budget_p95=130000  budget_p99=260000  margin_p95=5.5x margin_p99=10.1x
bulk_structural_mutation|1k_lines_batch_64     n=45  p95[med=6314   max=7431  ] p99[med=6592   max=9850  ] budget_p95=51000   budget_p99=110000  margin_p95=6.9x margin_p99=11.2x
bulk_structural_mutation|1m_lines_batch_4096   n=45  p95[med=361549 max=550231] p99[med=399530 max=570623] budget_p95=2900000 budget_p99=5800000 margin_p95=5.3x margin_p99=10.2x
bulk_structural_mutation|1m_lines_batch_64     n=45  p95[med=55802  max=80812 ] p99[med=57955  max=85411 ] budget_p95=450000  budget_p99=900000  margin_p95=5.6x margin_p99=10.5x
column_geometry_query|prefixsum_100k           n=31  p95[med=74     max=142   ] p99[med=112    max=169   ] budget_p95=600     budget_p99=1200    margin_p95=4.2x margin_p99=7.1x
column_geometry_query|prefixsum_1m             n=31  p95[med=94     max=162   ] p99[med=133    max=182   ] budget_p95=760     budget_p99=1600    margin_p95=4.7x margin_p99=8.8x
column_geometry_query|uniform_100k             n=31  p95[med=43     max=81    ] p99[med=75     max=98    ] budget_p95=350     budget_p99=700     margin_p95=4.3x margin_p99=7.1x
column_geometry_query|uniform_1k               n=31  p95[med=32     max=59    ] p99[med=63     max=75    ] budget_p95=260     budget_p99=520     margin_p95=4.4x margin_p99=6.9x
column_geometry_query|uniform_1m               n=31  p95[med=48     max=86    ] p99[med=80     max=107   ] budget_p95=390     budget_p99=780     margin_p95=4.5x margin_p99=7.3x
column_query|prefixsum_100k                    n=35  p95[med=58     max=134   ] p99[med=94     max=280   ] budget_p95=470     budget_p99=940     margin_p95=3.5x margin_p99=3.4x
column_query|prefixsum_1m                      n=35  p95[med=72     max=153   ] p99[med=114    max=163   ] budget_p95=580     budget_p99=1200    margin_p95=3.8x margin_p99=7.4x
column_query|uniform_100k                      n=35  p95[med=35     max=72    ] p99[med=67     max=204   ] budget_p95=280     budget_p99=620     margin_p95=3.9x margin_p99=3.0x
column_query|uniform_1k                        n=35  p95[med=24     max=50    ] p99[med=43     max=64    ] budget_p95=200     budget_p99=400     margin_p95=4.0x margin_p99=6.2x
column_query|uniform_1m                        n=35  p95[med=40     max=85    ] p99[med=72     max=111   ] budget_p95=320     budget_p99=640     margin_p95=3.8x margin_p99=5.8x
line_geometry_query|balanced_tree_100k         n=39  p95[med=365    max=387   ] p99[med=383    max=532   ] budget_p95=3000    budget_p99=6000    margin_p95=7.8x margin_p99=11.3x
line_geometry_query|balanced_tree_1m           n=39  p95[med=419    max=457   ] p99[med=438    max=665   ] budget_p95=3400    budget_p99=6800    margin_p95=7.4x margin_p99=10.2x
line_geometry_query|uniform_100k               n=39  p95[med=42     max=83    ] p99[med=74     max=110   ] budget_p95=340     budget_p99=680     margin_p95=4.1x margin_p99=6.2x
line_geometry_query|uniform_1k                 n=39  p95[med=31     max=60    ] p99[med=62     max=330   ] budget_p95=250     budget_p99=990     margin_p95=4.2x margin_p99=3.0x
line_geometry_query|uniform_1m                 n=39  p95[med=47     max=89    ] p99[med=79     max=265   ] budget_p95=380     budget_p99=800     margin_p95=4.3x margin_p99=3.0x
line_query|balanced_tree_100k                  n=45  p95[med=207    max=240   ] p99[med=216    max=421   ] budget_p95=1700    budget_p99=3400    margin_p95=7.1x margin_p99=8.1x
line_query|balanced_tree_1m                    n=45  p95[med=251    max=264   ] p99[med=262    max=307   ] budget_p95=2100    budget_p99=4200    margin_p95=8.0x margin_p99=13.7x
line_query|uniform_100k                        n=45  p95[med=34     max=92    ] p99[med=66     max=110   ] budget_p95=280     budget_p99=560     margin_p95=3.0x margin_p99=5.1x
line_query|uniform_1k                          n=45  p95[med=24     max=73    ] p99[med=53     max=84    ] budget_p95=220     budget_p99=440     margin_p95=3.0x margin_p99=5.2x
line_query|uniform_1m                          n=45  p95[med=40     max=89    ] p99[med=71     max=109   ] budget_p95=320     budget_p99=640     margin_p95=3.6x margin_p99=5.9x
pipeline|100k_lines_80_visible_overscan_5      n=47  p95[med=10483  max=12062 ] p99[med=10817  max=12481 ] budget_p95=84000   budget_p99=170000  margin_p95=7.0x margin_p99=13.6x
pipeline|1k_lines_20_visible_overscan_0        n=47  p95[med=2542   max=2911  ] p99[med=2713   max=4291  ] budget_p95=21000   budget_p99=42000   margin_p95=7.2x margin_p99=9.8x
pipeline|1m_lines_200_visible_overscan_50      n=47  p95[med=34148  max=39381 ] p99[med=35175  max=41429 ] budget_p95=280000  budget_p99=560000  margin_p95=7.1x margin_p99=13.5x
point_geometry_query|prefixsum_100k            n=11  p95[med=130    max=231   ] p99[med=146    max=252   ] budget_p95=1100    budget_p99=2200    margin_p95=4.8x margin_p99=8.7x
point_geometry_query|prefixsum_1m              n=11  p95[med=156    max=235   ] p99[med=178    max=254   ] budget_p95=1300    budget_p99=2600    margin_p95=5.5x margin_p99=10.2x
point_geometry_query|uniform_100k              n=11  p95[med=113    max=184   ] p99[med=147    max=199   ] budget_p95=910     budget_p99=1900    margin_p95=4.9x margin_p99=9.5x
point_geometry_query|uniform_1m                n=11  p95[med=109    max=156   ] p99[med=133    max=208   ] budget_p95=880     budget_p99=1800    margin_p95=5.6x margin_p99=8.7x
point_query|prefixsum_100k                     n=26  p95[med=112    max=164   ] p99[med=137    max=195   ] budget_p95=900     budget_p99=1800    margin_p95=5.5x margin_p99=9.2x
point_query|prefixsum_1m                       n=26  p95[med=124    max=174   ] p99[med=152    max=211   ] budget_p95=1000    budget_p99=2000    margin_p95=5.7x margin_p99=9.5x
point_query|uniform_100k                       n=26  p95[med=87     max=134   ] p99[med=126    max=156   ] budget_p95=700     budget_p99=1400    margin_p95=5.2x margin_p99=9.0x
point_query|uniform_1m                         n=26  p95[med=83     max=145   ] p99[med=112    max=201   ] budget_p95=670     budget_p99=1400    margin_p95=4.6x margin_p99=7.0x
realistic_provider|100k_lines_10mb_text        n=264 p95[med=12109  max=18298 ] p99[med=12449  max=21752 ] budget_p95=97000   budget_p99=200000  margin_p95=5.3x margin_p99=9.2x
structural_mutation|100k_lines_80_visible_overscan_5 n=46  p95[med=8540   max=15600 ] p99[med=8893   max=18488 ] budget_p95=69000   budget_p99=140000  margin_p95=4.4x margin_p99=7.6x
structural_mutation|1k_lines_20_visible_overscan_0 n=46  p95[med=1981   max=3044  ] p99[med=2065   max=3114  ] budget_p95=16000   budget_p99=32000   margin_p95=5.3x margin_p99=10.3x
structural_mutation|1m_lines_200_visible_overscan_50 n=46  p95[med=34565  max=49935 ] p99[med=35988  max=58240 ] budget_p95=280000  budget_p99=560000  margin_p95=5.6x margin_p99=9.6x
variable_height_mutation|100k_lines_80_visible_overscan_5 n=47  p95[med=2939   max=4406  ] p99[med=3033   max=4654  ] budget_p95=24000   budget_p99=48000   margin_p95=5.4x margin_p99=10.3x
variable_height_mutation|1k_lines_20_visible_overscan_0 n=47  p95[med=810    max=1032  ] p99[med=854    max=1269  ] budget_p95=6500    budget_p99=13000   margin_p95=6.3x margin_p99=10.2x
variable_height_mutation|1m_lines_200_visible_overscan_50 n=47  p95[med=10032  max=14487 ] p99[med=10574  max=14631 ] budget_p95=81000   budget_p99=170000  margin_p95=5.6x margin_p99=11.6x
variable_height|100k_lines_80_visible_overscan_5 n=47  p95[med=1732   max=2043  ] p99[med=1833   max=2756  ] budget_p95=14000   budget_p99=28000   margin_p95=6.9x margin_p99=10.2x
variable_height|1k_lines_20_visible_overscan_0 n=47  p95[med=501    max=654   ] p99[med=546    max=879   ] budget_p95=4100    budget_p99=8200    margin_p95=6.3x margin_p99=9.3x
variable_height|1m_lines_200_visible_overscan_50 n=47  p95[med=5521   max=6942  ] p99[med=5681   max=7204  ] budget_p95=45000   budget_p99=90000   margin_p95=6.5x margin_p99=12.5x
```

Committed-budgets-vs-freshly-derived diff at the current tree (`adbdd5b`,
carried unmodified through this task — no Sources file touched):

```
=== check 1: budgets reproduce ===
ALL 46 BUDGETS REPRODUCE
```

This task independently confirmed the `PointGeometryQueryBenchmark.swift`
literals still match the freshly-derived post-harvest values byte-for-byte:

```
$ rg -n "p95BudgetNanoseconds|p99BudgetNanoseconds" Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift
47:                                   p95BudgetNanoseconds: 910, p99BudgetNanoseconds: 1_900),
50:                                   p95BudgetNanoseconds: 880, p99BudgetNanoseconds: 1_800),
53:                                   p95BudgetNanoseconds: 1_100, p99BudgetNanoseconds: 2_200),
```

`910/1_900`, `880/1_800`, `1_100/2_200` match `derive-gate-budgets.sh`'s
`uniform_100k`, `uniform_1m`, `prefixsum_100k` rows above exactly (`prefixsum_1m`
= `1_300/2_600`, on the line the `rg` window above did not capture but present
in the same file).

**Every budget the harvest moved, with direction** (committed-before-harvest → derived-after-harvest; from Task 3's Step 4, `derive-gate-budgets.sh` with no mode argument):

| scenario | p95 | dir | p99 | dir |
| --- | --- | --- | --- | --- |
| `column_geometry_query\|prefixsum_100k` | 560 → 600 | **up** | 1200 → 1200 | unchanged |
| `column_geometry_query\|prefixsum_1m` | 720 → 760 | **up** | 1500 → 1600 | **up** |
| `column_query\|prefixsum_1m` | 570 → 580 | **up** | 1200 → 1200 | unchanged |
| `point_geometry_query\|uniform_100k` | 640 → 910 | **up** | 1300 → 1900 | **up** |
| `point_geometry_query\|uniform_1m` | 740 → 880 | **up** | 1500 → 1800 | **up** |
| `point_geometry_query\|prefixsum_100k` | 730 → 1100 | **up** | 1500 → 2200 | **up** |
| `point_geometry_query\|prefixsum_1m` | 780 → 1300 | **up** | 1600 → 2600 | **up** |
| `point_query\|uniform_1m` | 650 → 670 | **up** | 1300 → 1400 | **up** |
| `variable_height_mutation\|1m_lines_200_visible_overscan_50` | 80000 → 81000 | **up** | 160000 → 170000 | **up** |

**9 scenarios moved (18 literals), every one upward (looser). None was hand-typed** —
Task 3's Step 5 edit was verified byte-identical to this sweep's output (Step 4's
diff was the edit, no more, no less; re-confirmed above). **4 of the 9 belong to
modes this slice never touched** (`column_geometry_query` ×2, `column_query` ×1,
`variable_height_mutation` ×1) — the harvest raised `max(hosted)` and the median
for those scenarios too, which is precisely why the sweep takes no mode argument:
deriving only `point_geometry_query` would have left those four silently *not*
reproducing from the committed corpus.

## 6. `point_geometry_query`'s post-harvest evidence base

Per-scenario data (from Section 5's sweep, `n=11` for all four):

| scenario | n | budget p95/p99 | 3×max floor margin (p95 / p99) | tightest hosted headroom (p95 / p99) |
| --- | --- | --- | --- | --- |
| `prefixsum_100k` | 11 | 1100 / 2200 | +58.7% (1100/693) / +191.0% (2200/756) | **4.8x** / 8.7x |
| `prefixsum_1m` | 11 | 1300 / 2600 | +84.4% (1300/705) / +241.2% (2600/762) | 5.5x / 10.2x |
| `uniform_100k` | 11 | 910 / 1900 | +64.9% (910/552) / +218.3% (1900/597) | 4.9x / 9.5x |
| `uniform_1m` | 11 | 880 / 1800 | +88.0% (880/468) / +188.5% (1800/624) | 5.6x / 8.7x |

("3×max floor margin" = `budget / (3 x max(hosted))`, expressed as headroom
above the `GateFloorTests` 3x floor; "tightest hosted headroom" =
`budget / max(hosted)`, the number `derive-gate-budgets.sh` prints as
`margin_p95`/`margin_p99` — the same figure the Slice 38 spec's residual-risk
language and this section's pre-harvest baseline both use.)

**Post-harvest tightest headroom: 4.8x p95 on `point_geometry_query|prefixsum_100k`.**

Compared against the **pre-harvest baseline** (Slice 39's plan, `n=6`): tightest
hosted headroom was **3.16x p95** on the same scenario (231 ns on run
`29280327104` vs a 730 ns budget), sitting **+5.34%** above its `3×max` floor
(730 vs 693 = `3 x 231`), median-governed (`8 x 91 = 728 > 3 x 231 = 693`).

Verbatim `derive-gate-budgets.sh` row for that scenario at each state (from
`/tmp/derive-before.txt` and this task's re-run of the current corpus):

```
# pre-harvest (n=6):
point_geometry_query|prefixsum_100k            n=6   p95[med=91     max=231   ] p99[med=141    max=252   ] budget_p95=730     budget_p99=1500    margin_p95=3.2x margin_p99=6.0x

# post-harvest (n=11):
point_geometry_query|prefixsum_100k            n=11  p95[med=130    max=231   ] p99[med=146    max=252   ] budget_p95=1100    budget_p99=2200    margin_p95=4.8x margin_p99=8.7x
```

`prefixsum_100k` remains the tightest of the four scenarios post-harvest — its
worst hosted `p95`/`p99` samples (231 ns / 252 ns) did not move between the two
snapshots (no new run beat the existing worst case on this scenario), but its
budget widened from 730/1500 to 1100/2200 because the *median* rose (91 → 130),
which is what the `8 x median` recipe term is governed by. **The headroom
picture improved, not narrowed**: 3.16x → 4.8x p95. The mode's evidence base
also crossed the spec's "~10 runs" residual-risk threshold (6 → 11, Section 4
above), so that risk is retired rather than merely carried into this slice.

## 7. Local gates (AC10)

All eleven CI gates re-run directly by this task at the current tree (`adbdd5b`),
`swift build -c release` immediately preceding:

```
$ swift build -c release
Building for production...
Build complete! (0.09s)
```

`--gate` (synthetic pipeline + realistic-provider), `--variable-height --gate`,
`--variable-height-mutation --gate`, `--structural-mutation --gate`,
`--bulk-structural-mutation --gate`, `--line-query --gate`,
`--line-geometry-query --gate`, `--column-query --gate`,
`--column-geometry-query --gate`, `--point-query --gate`, and
`--point-geometry-query --gate` — 46 gated-scenario summary lines total (41 from
the eleven-mode loop + 5 from `--memory-shape`'s separate, non-gated
`invariant=pass` lines counted apart, see below):

```
$ for m in --gate --realistic-provider --variable-height --variable-height-mutation \
           --structural-mutation --bulk-structural-mutation --line-query --line-geometry-query \
           --column-query --column-geometry-query --point-query --point-geometry-query; do
    swift run -c release ViewportBenchmarks -- "$m" --gate
  done | tee /tmp/task5-full-gate-sweep.txt
$ grep -c '^mode=' /tmp/task5-full-gate-sweep.txt
46
$ grep -c 'gate=pass' /tmp/task5-full-gate-sweep.txt
46
$ grep -c 'gate=fail' /tmp/task5-full-gate-sweep.txt
0
```

`--point-geometry-query --gate` alone, all four scenarios `gate=pass` with
per-scenario headroom, checksums pinned identical to Slice 39's:

```
mode=point_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=58 p99_ns=66 failures=0 budget_p95_ns=910 budget_p99_ns=1900 headroom_p95=15.7x headroom_p99=28.8x gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=55 p99_ns=61 failures=0 budget_p95_ns=880 budget_p99_ns=1800 headroom_p95=16.0x headroom_p99=29.5x gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=65 p99_ns=73 failures=0 budget_p95_ns=1100 budget_p99_ns=2200 headroom_p95=16.9x headroom_p99=30.1x gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=53 p99_ns=54 failures=0 budget_p95_ns=1300 budget_p99_ns=2600 headroom_p95=24.5x headroom_p99=48.1x gate=pass checksum=5915921755926273280
```

Checksum identity vs. the pinned Slice 39 values:

| scenario | pinned | observed (this run) | match |
| --- | --- | --- | --- |
| uniform_100k | 4687694617200924928 | 4687694617200924928 | yes |
| uniform_1m | 6036755761047907072 | 6036755761047907072 | yes |
| prefixsum_100k | 1712152282485110528 | 1712152282485110528 | yes |
| prefixsum_1m | 5915921755926273280 | 5915921755926273280 | yes |

`--memory-shape` (not gateable, run separately per AGENTS.md's rejected-mode list):

```
$ swift run -c release ViewportBenchmarks -- --memory-shape
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
```

Five `invariant=pass` lines — this is what raises "46 gate=pass" (the eleven
gated modes' 41 scenarios) to the "46-scenario sweep" language elsewhere in this
record, which additionally counts these five memory-shape scenarios' checksum
identity (Section 8) even though `--memory-shape` itself carries no
`gate=`/`budget_` fields to fail on.

## 8. Checksum identity across the whole sweep

Diff between `/tmp/checksums-before.txt` (pre-harvest, pre-collapse) and
`/tmp/checksums-after.txt` (post-harvest, post-collapse), both 46 lines, one
line per gated + memory-shape scenario:

```
$ diff /tmp/checksums-before.txt /tmp/checksums-after.txt && echo "CHECKSUMS IDENTICAL (diff empty, 46 lines each)"
CHECKSUMS IDENTICAL (diff empty, 46 lines each)
```

No measured path moved across the whole slice: not the workflow collapse, not
the harvest/re-derivation, not the AGENTS.md rewrite. Every checksum — synthetic
pipeline, realistic-provider, variable-height, variable-height-mutation,
structural-mutation, bulk-structural-mutation, line-query, line-geometry-query,
column-query, column-geometry-query, point-query, and point-geometry-query — is
byte-identical before and after.

## 9. `swift test`

Re-run directly by this task at the current tree (`adbdd5b`):

```
$ swift test 2>&1 | tail -6
Test Suite 'All tests' passed at 2026-07-17 14:36:04.479.
	 Executed 296 tests, with 0 failures (0 unexpected) in 3.665 (3.679) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

290 (pre-slice baseline) → **296** (290 + `WorkflowShapeTests`'s 6 new test
methods), 0 failures. (The "0 tests in 0 suites" line is the empty Swift
Testing harness, not a failure — documented in `AGENTS.md`'s package-layout
section.)

## 10. Foundation scans

Re-run directly by this task:

```
$ rg -n "Foundation" Sources/TextEngineCore; echo "core scan exit=$?"
core scan exit=1
$ rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "provider scan exit=$?"
provider scan exit=1
```

Both silent, both `exit=1` (no matches). `Sources/ViewportBenchmarks` also
carries no `import Foundation` (confirmed in Task 2's report; unchanged by
Tasks 3-5, which touched only budget literals, the corpus TSV, and docs).

## 11. Scope proof (AC7, AC8)

```
$ git diff --check
(empty, exit=0)
$ git diff --name-only main
.github/workflows/swift-ci.yml
AGENTS.md
Sources/ViewportBenchmarks/ColumnGeometryQueryBenchmark.swift
Sources/ViewportBenchmarks/ColumnQueryBenchmark.swift
Sources/ViewportBenchmarks/PointGeometryQueryBenchmark.swift
Sources/ViewportBenchmarks/PointQueryBenchmark.swift
Sources/ViewportBenchmarks/VariableHeightMutationBenchmark.swift
Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
docs/superpowers/plans/2026-07-16-point-geometry-query-ci-gate-promotion.md
docs/superpowers/reviews/2026-07-15-slice-39-post-slice-review.md
docs/superpowers/specs/2026-07-16-point-geometry-query-ci-gate-promotion-design.md
docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
```

Matches the plan's expected file set exactly: the workflow, `AGENTS.md`, the
five `Sources/ViewportBenchmarks/*.swift` files whose budget tables the harvest
moved (Section 5), the new `WorkflowShapeTests.swift`, the corpus TSV, and
`docs/**` (the slice's own spec/plan and a carried Slice 39 review file). **No
`Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`, or
`Tests/TextEngineCoreTests`/`Tests/TextEngineReferenceProvidersTests` file
appears** — no core, provider, or public-API change.

Required-check job context names, re-read from the current workflow and
unchanged from `AGENTS.md`'s required-check policy paragraph:

```
$ rg -n 'name:' .github/workflows/swift-ci.yml | rg -i "host tests|ios cross|wasm cross"
21:    name: Host tests and benchmark gate
185:    name: iOS cross-target compile
255:    name: WASM cross-target observation
```

All three match the ruleset's required contexts (`maldrakar/swift-text-engine`,
ruleset `Main`, id `17656807`) verbatim — the collapse renamed a *step* inside
the `Host tests and benchmark gate` job, not the job itself.

## 12. The Decision 2 relocation proof (AC4)

Both rules Task 1 relocated out of the point-geometry-query-specific prose into
mode-independent `AGENTS.md` sections, quoted verbatim from the current file:

`## CI`, lines 227-231:

```
A `continue-on-error` step cannot be a gate. It swallows every non-zero exit —
budget misses, correctness failures, and crashes alike (the Slice 16 dead-step
trap). An observational benchmark step and a blocking correctness step must
therefore be separate steps until the budget itself goes blocking, at which
point one step is both.
```

`## Gate budgets`, lines 341-347:

```
**Exactly one CI step may print a given mode's benchmark summary lines.** The
harvester reads every `p95_ns=` line in a run's log, so a second printing step
puts two rows per scenario into every future harvest of that run and
double-weights it in `median()` — the term that governs most budgets. This is a
different rule from the idempotent `--corpus` dedup above (which is about
harvesting the *same run* twice): here one run genuinely carries two rows per
scenario, and no dedup key can tell them apart.
```

Grep confirming neither rule is phrased in terms of `point-geometry-query` (both
read as general CI/harvest rules, not slice-40-specific ones):

```
$ rg -n "continue-on-error.*cannot be a gate|Exactly one CI step may print" AGENTS.md | rg -i "point.geometry" || echo "no point-geometry-query phrasing in either rule OK"
no point-geometry-query phrasing in either rule OK
```

Neither rule depends on the text this slice deleted from the workflow (the
14-line rationale comment, the bare correctness step, and the
`continue-on-error` gate step) — both are general statements that remain fully
true and fully load-bearing after the collapse: the `continue-on-error` rule is
*why* the collapse was safe only once the budget itself went blocking, and the
one-printing-step rule is *why* the bare step's summary lines had to stay out of
the log before this slice, and why a second step is no longer needed now that
there is only one.

## Hosted Proof

AC11 discharged. Both runs are read at **step level**, not job conclusion — the
standing rule of this project, since a `continue-on-error` step can conclude its
job green while the step itself failed (the Slice 16 dead-step trap). The whole
point of this slice is that the point-geometry step is no longer
`continue-on-error`; the step-level reads below confirm it ran, was not skipped,
and gated on both correctness and budget.

### PR-head run: `29579314733` (head `4dd7bf9`)

The run that gated PR #87 before merge. All three required jobs concluded
`success`: `Host tests and benchmark gate`, `iOS cross-target compile`, `WASM
cross-target observation`. The single blocking `Run point geometry query
benchmark gate` step ran (its per-scenario output is present in the log, so it
was not skipped) and reported all four scenarios `gate=pass` at step level:

| scenario | p95_ns | p99_ns | budget_p95 | budget_p99 | headroom_p95 | headroom_p99 |
|---|---|---|---|---|---|---|
| uniform_100k   | 117 | 146 | 910  | 1900 | 7.8x | 13.0x |
| uniform_1m     | 128 | 156 | 880  | 1800 | 6.9x | 11.5x |
| prefixsum_100k | 136 | 166 | 1100 | 2200 | 8.1x | 13.3x |
| prefixsum_1m   | 200 | 235 | 1300 | 2600 | 6.5x | 11.1x |

Tightest observed headroom on this run is `prefixsum_1m` at 6.5x p95 / 11.1x
p99 — inside the 3x–50x/100x band. Whole-run tally: **45 `gate=pass`, 0
`gate=fail`**.

### Post-merge `push` run: `29606487287` (merge commit `bff3268`)

Proof of merged code is anchored here, not only in the PR-head run above — a PR
run tests the merge *preview*, not the commit that landed on `main`. The merge
commit's second parent (`git rev-parse bff3268^2` → `4dd7bf9`) is the PR-head
commit, and the `push`-triggered run on `bff3268` is `29606487287`. All three
required jobs concluded `success`. The `Run point geometry query benchmark gate`
step ran (present in the log, not skipped) and reported all four scenarios
`gate=pass` at step level:

| scenario | p95_ns | p99_ns | budget_p95 | budget_p99 | headroom_p95 | headroom_p99 |
|---|---|---|---|---|---|---|
| uniform_100k   | 63 | 89  | 910  | 1900 | 14.4x | 21.3x |
| uniform_1m     | 67 | 92  | 880  | 1800 | 13.1x | 19.6x |
| prefixsum_100k | 70 | 96  | 1100 | 2200 | 15.7x | 22.9x |
| prefixsum_1m   | 75 | 104 | 1300 | 2600 | 17.3x | 25.0x |

The four checksums (`4687694617200924928`, `6036755761047907072`,
`1712152282485110528`, `5915921755926273280`) are **bit-identical** to the
PR-head run and to the local runs in Sections 7-8, confirming the workload is
unchanged across host, PR-head, and merged commit. Whole-run tally
(`gh run view 29606487287 --log | grep -oE 'gate=pass|gate=fail' | sort | uniq -c`):
**45 `gate=pass`, 0 `gate=fail`** — all eleven blocking latency gates green on
the commit that is now `main`.

**Watch scenario: `point_geometry_query|prefixsum_100k`** — the tightest of
this mode's four scenarios by both floor margin and corpus-level hosted headroom
(Section 6: 4.8x p95 tightest headroom, +58.7% above its 3x floor). Hosted Linux
x86_64 runs 2-3x slower than local macOS (measured 2.1-2.7x per `AGENTS.md`'s
calibration note), so it is the first place to look if `--point-geometry-query
--gate` ever reports `gate=fail` in CI. On these two runs it stayed green with
8.1x (PR-head) and 15.7x (post-merge) p95 headroom.
