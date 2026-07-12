# Gate-Budget Recalibration Verification

Date: 2026-07-12
Branch: `slice-38-gate-budget-recalibration`
Local verification HEAD: `be5f7e4` (`be5f7e4c062a604f28d42b81fb1c7b497a56d9bf`)
Merge base with `main`: `5e2abf7` (`5e2abf7a3f9ca4769857c77d1b33d78c1c74992e`)

Spec: `docs/superpowers/specs/2026-07-12-gate-budget-recalibration-design.md`
Plan: `docs/superpowers/plans/2026-07-12-gate-budget-recalibration.md`
Corpus: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
Derivation script: `.github/scripts/derive-gate-budgets.sh`

Commits on branch (base `5e2abf7` ← `main`):

```
be5f7e4 docs: correct stale local-gate labels in AGENTS.md Commands section
a99f2d1 fix: correct false floor claim in point-query provenance comment
91ebf84 docs: reflect --point-query CI promotion in AGENTS.md
afd8044 ci: promote --point-query to the tenth blocking gate
0676492 docs: append the first hosted point-query samples to the budget corpus
4a041f2 docs: write down the gate-budget calibration rule
a010098 feat: recalibrate pipeline 1m_lines_200_visible_overscan_50 budget above the 3x floor
c1a0b3f ci: observe point-query latency on hosted Linux before gating it
350156a docs: correct calibration numbers in maxHeadroomP95 comment + pin p99 coupling + test zero-latency formatting
4af9438 feat: add a p99 headroom ceiling alongside the p95 gate check
bc524ce feat: fail the gate when its own budget goes stale
77352b0 feat: recalibrate the query and variable-height gate budgets
aaefdd8 docs: commit the hosted gate-budget corpus and its derivation script
5db92c7 docs: add slice 38 gate-budget recalibration plan
7f4ae54 docs: fold the floor into the budget recipe and cover p99
56449d9 docs: add gate-budget recalibration design
```

**What this slice fixes.** Slice 27 shipped "starter budgets" whose calibration
step never happened. Five slices inherited them. The result: query-gate budgets
sat up to **12,631× above observed p99** — no constant-factor regression could
ever have failed a gate. This slice recalibrates 28 scenarios from a committed
corpus of real hosted-CI samples via a committed derivation script, teaches
`--gate` to **reject its own stale budgets**, and promotes `--point-query` to the
tenth blocking gate.

Source changes are confined to `Sources/ViewportBenchmarks` (budgets + gate
logic), `Tests/ViewportBenchmarksTests` (new), `Package.swift` (test target),
`.github/workflows/swift-ci.yml` (gate promotion), and
`.github/scripts/derive-gate-budgets.sh` (new). **No `Sources/TextEngineCore`
change** — see §7.

## The calibration rule

Both statistics, floor folded into the formula (not applied afterwards), because
the gate can fail on either:

```
budget_p95 = round_up_2sf( max( 8 × median(p95), 3 × max(p95) ) )
budget_p99 = round_up_2sf( max( 2 × budget_p95, 8 × median(p99), 3 × max(p99) ) )
```

And **two** runtime ceilings, both enforced by `--gate` with
`gate=fail reason=budget_stale`:

```
headroom_p95 ≤ 50×      headroom_p99 ≤ 100×   (= 2 × maxHeadroomP95, by construction)
```

## 1. Corpus provenance

```text
$ C=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
$ head -1 $C
run_id	mode	scenario	p95_ns	p99_ns

$ echo "rows=$(( $(wc -l < $C) - 1 ))"
rows=565
$ awk -F'\t' 'NR>1{print $1}' $C | sort -u | wc -l
22
$ awk -F'\t' 'NR>1{print $2"|"$3}' $C | sort -u | wc -l
41
```

**565 sample rows, 22 distinct hosted runs, 41 distinct scenarios.** Every row is
a real hosted-Linux-x86_64 CI observation; nothing is synthetic or macOS-derived.

Rows per contributing run — the row count grows as each slice added gates
(22 → 27 → 32 → 37), and the last three runs are this slice's own point-query
observation runs (4 rows each):

```text
$ awk -F'\t' 'NR>1{c[$1]++} END{for(r in c) printf "run_id=%s rows=%d\n", r, c[r]}' $C | sort
run_id=28236592208 rows=22      run_id=28893267949 rows=32
run_id=28264342225 rows=22      run_id=28956968583 rows=32
run_id=28334474924 rows=22      run_id=29108998305 rows=37
run_id=28371455301 rows=22      run_id=29110714042 rows=37
run_id=28473489678 rows=22      run_id=29145425255 rows=37
run_id=28587326869 rows=22      run_id=29150235152 rows=37
run_id=28646126162 rows=27      run_id=29150501304 rows=37
run_id=28698965663 rows=27      run_id=29183582406 rows=4
run_id=28713959866 rows=27      run_id=29184456256 rows=4
run_id=28716790653 rows=27      run_id=29184686762 rows=4
run_id=28818762407 rows=32
run_id=28819411144 rows=32
```

### Per-scenario `n` — the sample base behind each budget

The spec's Risks section requires this: a thin sample base hides tails, and a
budget is only as trustworthy as the `n` it was cut from.

```text
$ awk -F'\t' 'NR>1{c[$2"|"$3]++} END{for(k in c) printf "%-46s n=%d\n", k, c[k]}' $C | sort
bulk_structural_mutation|100k_lines_batch_4096            n=19
bulk_structural_mutation|100k_lines_batch_64             n=19
bulk_structural_mutation|1k_lines_batch_64               n=19
bulk_structural_mutation|1m_lines_batch_4096             n=19
bulk_structural_mutation|1m_lines_batch_64               n=19
column_geometry_query|prefixsum_100k                     n=5
column_geometry_query|prefixsum_1m                       n=5
column_geometry_query|uniform_100k                       n=5
column_geometry_query|uniform_1k                         n=5
column_geometry_query|uniform_1m                         n=5
column_query|prefixsum_100k                              n=9
column_query|prefixsum_1m                                n=9
column_query|uniform_100k                                n=9
column_query|uniform_1k                                  n=9
column_query|uniform_1m                                  n=9
line_geometry_query|balanced_tree_100k                   n=13
line_geometry_query|balanced_tree_1m                     n=13
line_geometry_query|uniform_100k                         n=13
line_geometry_query|uniform_1k                           n=13
line_geometry_query|uniform_1m                           n=13
line_query|balanced_tree_100k                            n=19
line_query|balanced_tree_1m                              n=19
line_query|uniform_100k                                  n=19
line_query|uniform_1k                                    n=19
line_query|uniform_1m                                    n=19
pipeline|100k_lines_80_visible_overscan_5                n=19
pipeline|1k_lines_20_visible_overscan_0                  n=19
pipeline|1m_lines_200_visible_overscan_50                n=19
point_query|prefixsum_100k                               n=3
point_query|prefixsum_1m                                 n=3
point_query|uniform_100k                                 n=3
point_query|uniform_1m                                   n=3
structural_mutation|100k_lines_80_visible_overscan_5     n=19
structural_mutation|1k_lines_20_visible_overscan_0       n=19
structural_mutation|1m_lines_200_visible_overscan_50     n=19
variable_height_mutation|100k_lines_80_visible_overscan_5 n=19
variable_height_mutation|1k_lines_20_visible_overscan_0  n=19
variable_height_mutation|1m_lines_200_visible_overscan_50 n=19
variable_height|100k_lines_80_visible_overscan_5         n=19
variable_height|1k_lines_20_visible_overscan_0           n=19
variable_height|1m_lines_200_visible_overscan_50         n=19
```

**`point_query` (n=3) is the thinnest sample base of any gated mode** — its gate
was only added this slice, so only three hosted runs could observe it. This is
recorded as a known limitation, not hidden: see §11 (Deviations) and §12 (Risks).

## 2. Derived budgets — all 28 recalibrated scenarios

Both margins shown (`margin = budget ÷ max observed`); the acceptance criterion
is **every margin ≥ 3.0×**.

### 2a. The 23 query + variable-height scenarios (Task 2)

```text
$ ./.github/scripts/derive-gate-budgets.sh $C line_query line_geometry_query column_query column_geometry_query variable_height
column_geometry_query|prefixsum_100k   n=5   p95[med=104    max=116   ] p99[med=134    max=150   ] budget_p95=840     budget_p99=1700    margin_p95=7.2x margin_p99=11.3x
column_geometry_query|prefixsum_1m     n=5   p95[med=89     max=143   ] p99[med=130    max=176   ] budget_p95=720     budget_p99=1500    margin_p95=5.0x margin_p99=8.5x
column_geometry_query|uniform_100k     n=5   p95[med=43     max=46    ] p99[med=74     max=76    ] budget_p95=350     budget_p99=700     margin_p95=7.6x margin_p99=9.2x
column_geometry_query|uniform_1k       n=5   p95[med=32     max=34    ] p99[med=63     max=65    ] budget_p95=260     budget_p99=520     margin_p95=7.6x margin_p99=8.0x
column_geometry_query|uniform_1m       n=5   p95[med=48     max=52    ] p99[med=79     max=84    ] budget_p95=390     budget_p99=780     margin_p95=7.5x margin_p99=9.3x
column_query|prefixsum_100k            n=9   p95[med=57     max=89    ] p99[med=94     max=121   ] budget_p95=460     budget_p99=920     margin_p95=5.2x margin_p99=7.6x
column_query|prefixsum_1m              n=9   p95[med=71     max=121   ] p99[med=110    max=163   ] budget_p95=570     budget_p99=1200    margin_p95=4.7x margin_p99=7.4x
column_query|uniform_100k              n=9   p95[med=37     max=55    ] p99[med=67     max=173   ] budget_p95=300     budget_p99=600     margin_p95=5.5x margin_p99=3.5x
column_query|uniform_1k                n=9   p95[med=24     max=26    ] p99[med=43     max=58    ] budget_p95=200     budget_p99=400     margin_p95=7.7x margin_p99=6.9x
column_query|uniform_1m                n=9   p95[med=40     max=54    ] p99[med=72     max=77    ] budget_p95=320     budget_p99=640     margin_p95=5.9x margin_p99=8.3x
line_geometry_query|balanced_tree_100k n=13  p95[med=368    max=380   ] p99[med=376    max=532   ] budget_p95=3000    budget_p99=6000    margin_p95=7.9x margin_p99=11.3x
line_geometry_query|balanced_tree_1m   n=13  p95[med=418    max=430   ] p99[med=442    max=528   ] budget_p95=3400    budget_p99=6800    margin_p95=7.9x margin_p99=12.9x
line_geometry_query|uniform_100k       n=13  p95[med=44     max=73    ] p99[med=74     max=110   ] budget_p95=360     budget_p99=720     margin_p95=4.9x margin_p99=6.5x
line_geometry_query|uniform_1k         n=13  p95[med=33     max=57    ] p99[med=62     max=84    ] budget_p95=270     budget_p99=540     margin_p95=4.7x margin_p99=6.4x
line_geometry_query|uniform_1m         n=13  p95[med=47     max=73    ] p99[med=79     max=82    ] budget_p95=380     budget_p99=760     margin_p95=5.2x margin_p99=9.3x
line_query|balanced_tree_100k          n=19  p95[med=209    max=240   ] p99[med=225    max=313   ] budget_p95=1700    budget_p99=3400    margin_p95=7.1x margin_p99=10.9x
line_query|balanced_tree_1m            n=19  p95[med=251    max=257   ] p99[med=263    max=288   ] budget_p95=2100    budget_p99=4200    margin_p95=8.2x margin_p99=14.6x
line_query|uniform_100k                n=19  p95[med=34     max=92    ] p99[med=66     max=110   ] budget_p95=280     budget_p99=560     margin_p95=3.0x margin_p99=5.1x
line_query|uniform_1k                  n=19  p95[med=23     max=45    ] p99[med=53     max=64    ] budget_p95=190     budget_p99=430     margin_p95=4.2x margin_p99=6.7x
line_query|uniform_1m                  n=19  p95[med=40     max=61    ] p99[med=71     max=79    ] budget_p95=320     budget_p99=640     margin_p95=5.2x margin_p99=8.1x
variable_height|100k_lines_80_visible_overscan_5 n=19 p95[med=1731 max=2013] p99[med=1834 max=2105] budget_p95=14000 budget_p99=28000 margin_p95=7.0x margin_p99=13.3x
variable_height|1k_lines_20_visible_overscan_0   n=19 p95[med=501  max=654 ] p99[med=548  max=729 ] budget_p95=4100  budget_p99=8200  margin_p95=6.3x margin_p99=11.2x
variable_height|1m_lines_200_visible_overscan_50 n=19 p95[med=5504 max=6649] p99[med=5649 max=6751] budget_p95=45000 budget_p99=90000 margin_p95=6.8x margin_p99=13.3x
```

### 2b. The 4 point-query scenarios (Task 5)

```text
$ ./.github/scripts/derive-gate-budgets.sh $C point_query
point_query|prefixsum_100k  n=3   p95[med=112    max=132   ] p99[med=149    max=159   ] budget_p95=900     budget_p99=1800    margin_p95=6.8x margin_p99=11.3x
point_query|prefixsum_1m    n=3   p95[med=133    max=171   ] p99[med=159    max=202   ] budget_p95=1100    budget_p99=2200    margin_p95=6.4x margin_p99=10.9x
point_query|uniform_100k    n=3   p95[med=96     max=97    ] p99[med=132    max=133   ] budget_p95=770     budget_p99=1600    margin_p95=7.9x margin_p99=12.0x
point_query|uniform_1m      n=3   p95[med=96     max=96    ] p99[med=128    max=129   ] budget_p95=770     budget_p99=1600    margin_p95=8.0x margin_p99=12.4x
```

### 2c. `pipeline|1m_lines_200_visible_overscan_50` (the 28th)

The other two `pipeline` scenarios were **not** recalibrated — their existing
budgets already cleared the 3× floor. The `1m` row did not, which is why a user
decision pulled it into scope: its old `budget_p95 = 100_000` sat **below**
`3 × max(p95) = 3 × 39,381 = 118,143`. A gate whose budget is under its own floor
is a latent false-positive; it was raised to `280_000 / 560_000`.

```text
$ ./.github/scripts/derive-gate-budgets.sh $C pipeline
pipeline|100k_lines_80_visible_overscan_5  n=19  p95[med=10554  max=12062 ] p99[med=10857  max=12269 ] budget_p95=85000   budget_p99=170000  margin_p95=7.0x margin_p99=13.9x
pipeline|1k_lines_20_visible_overscan_0    n=19  p95[med=2542   max=2911  ] p99[med=2744   max=3096  ] budget_p95=21000   budget_p99=42000   margin_p95=7.2x margin_p99=13.6x
pipeline|1m_lines_200_visible_overscan_50  n=19  p95[med=34237  max=39381 ] p99[med=35175  max=40177 ] budget_p95=280000  budget_p99=560000  margin_p95=7.1x margin_p99=13.9x
```

Only the `1m` row's derived value was adopted (`280_000 / 560_000`). The `1k` and
`100k` rows keep their existing `20_000/50_000` and `50_000/100_000` — both
already above `3 × max` (8,733 and 36,186 respectively) and inside the ceiling.

### 2d. Floor check — every margin ≥ 3.0×

Minimum across all 28 recalibrated scenarios:

- `margin_p95` minimum = **3.0×** (`line_query|uniform_100k`)
- `margin_p99` minimum = **3.5×** (`column_query|uniform_100k`)

Both clear the 3.0× floor. **Acceptance criterion 5 met.**

### 2e. Which term binds?

The formula takes `max(8 × median, 3 × max)`. Computed per scenario from the
corpus, the `3 × max` floor binds in **exactly one** scenario out of 41:

```text
line_query|uniform_100k   n=19   8*med=272   3*max=276   -> 3*max (FLOOR binds)
```

Everywhere else `8 × median` binds. This is the one scenario where a single
outlier run (p95 = 92 against a median of 34) pulled the floor above the median
term — precisely the case the floor exists to catch. It is also why
`line_query|uniform_100k` is the tightest-margin scenario at exactly 3.0×.

## 3. `swift test` — 249 tests, 0 failures

```text
$ swift test 2>&1 | tail -6
Test Suite 'All tests' passed at 2026-07-12 11:20:37.265.
	 Executed 249 tests, with 0 failures (0 unexpected) in 2.254 (2.266) seconds
◇ Test run started.
↳ Testing Library Version: 6.2.1 (c9d57c83568b06d)
↳ Target Platform: arm64-apple-macosx
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

**249 tests** = 232 (Slice 37 baseline) + **17** new gate-logic tests in the new
`Tests/ViewportBenchmarksTests/GateLogicTests.swift` target. 0 failures. The
"0 tests in 0 suites" line is the expected empty Swift Testing harness.

```text
$ swift build -c release 2>&1 | tail -2
[0/2] Write swift-version--2EFC8FE404102F05.txt
Build complete! (0.09s)
```

## 4. All ten gates, locally — 41 scenarios, 41 `gate=pass`

Every gate run at `be5f7e4`, macOS arm64. Note the new `headroom_p95=` and
`headroom_p99=` fields, which the gate now emits and checks.

```text
$ swift run -c release ViewportBenchmarks -- --gate
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1245 p99_ns=1292 failures=0 budget_p95_ns=20000 budget_p99_ns=50000 headroom_p95=16.1x headroom_p99=38.7x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5068 p99_ns=5170 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 headroom_p95=9.9x headroom_p99=19.3x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=16660 p99_ns=16930 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=16.8x headroom_p99=33.1x gate=pass checksum=18852477646272000
EXIT:0

$ swift run -c release ViewportBenchmarks -- --variable-height --gate
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=207 p99_ns=222 failures=0 budget_p95_ns=4100 budget_p99_ns=8200 headroom_p95=19.8x headroom_p99=36.9x gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=667 p99_ns=696 failures=0 budget_p95_ns=14000 budget_p99_ns=28000 headroom_p95=21.0x headroom_p99=40.2x gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2005 p99_ns=2045 failures=0 budget_p95_ns=45000 budget_p99_ns=90000 headroom_p95=22.4x headroom_p99=44.0x gate=pass checksum=3536425156727040
EXIT:0

$ swift run -c release ViewportBenchmarks -- --variable-height-mutation --gate
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=393 p99_ns=414 failures=0 budget_p95_ns=5000 budget_p99_ns=10000 headroom_p95=12.7x headroom_p99=24.2x gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1554 p99_ns=1623 failures=0 budget_p95_ns=20000 budget_p99_ns=25000 headroom_p95=12.9x headroom_p99=15.4x gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4814 p99_ns=4941 failures=0 budget_p95_ns=60000 budget_p99_ns=75000 headroom_p95=12.5x headroom_p99=15.2x gate=pass checksum=3571078666132451
EXIT:0

$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=959 p99_ns=992 failures=0 budget_p95_ns=20000 budget_p99_ns=40000 headroom_p95=20.9x headroom_p99=40.3x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5071 p99_ns=5242 failures=0 budget_p95_ns=80000 budget_p99_ns=120000 headroom_p95=15.8x headroom_p99=22.9x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=20526 p99_ns=21377 failures=0 budget_p95_ns=250000 budget_p99_ns=400000 headroom_p95=12.2x headroom_p99=18.7x gate=pass checksum=3379593298396981
EXIT:0

$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2703 p99_ns=2764 failures=0 budget_p95_ns=60000 budget_p99_ns=120000 headroom_p95=22.2x headroom_p99=43.4x gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=8102 p99_ns=8410 failures=0 budget_p95_ns=150000 budget_p99_ns=250000 headroom_p95=18.5x headroom_p99=29.7x gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=32885 p99_ns=36788 failures=0 budget_p95_ns=400000 budget_p99_ns=600000 headroom_p95=12.2x headroom_p99=16.3x gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=60018 p99_ns=61143 failures=0 budget_p95_ns=1500000 budget_p99_ns=2500000 headroom_p95=25.0x headroom_p99=40.9x gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=121257 p99_ns=130252 failures=0 budget_p95_ns=2500000 budget_p99_ns=4000000 headroom_p95=20.6x headroom_p99=30.7x gate=pass checksum=82203678997143
EXIT:0

$ swift run -c release ViewportBenchmarks -- --line-query --gate
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=11 p99_ns=14 failures=0 budget_p95_ns=190 budget_p99_ns=430 headroom_p95=17.3x headroom_p99=30.7x gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=15 p99_ns=15 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=18.7x headroom_p99=37.3x gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=18 p99_ns=19 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=17.8x headroom_p99=33.7x gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=90 p99_ns=93 failures=0 budget_p95_ns=1700 budget_p99_ns=3400 headroom_p95=18.9x headroom_p99=36.6x gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=113 p99_ns=125 failures=0 budget_p95_ns=2100 budget_p99_ns=4200 headroom_p95=18.6x headroom_p99=33.6x gate=pass checksum=639841547520
EXIT:0

$ swift run -c release ViewportBenchmarks -- --line-geometry-query --gate
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=14 p99_ns=16 failures=0 budget_p95_ns=270 budget_p99_ns=540 headroom_p95=19.3x headroom_p99=33.8x gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=18 p99_ns=20 failures=0 budget_p95_ns=360 budget_p99_ns=720 headroom_p95=20.0x headroom_p99=36.0x gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=21 p99_ns=24 failures=0 budget_p95_ns=380 budget_p99_ns=760 headroom_p95=18.1x headroom_p99=31.7x gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=122 p99_ns=142 failures=0 budget_p95_ns=3000 budget_p99_ns=6000 headroom_p95=24.6x headroom_p99=42.3x gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=161 p99_ns=191 failures=0 budget_p95_ns=3400 budget_p99_ns=6800 headroom_p95=21.1x headroom_p99=35.6x gate=pass checksum=852321495040
EXIT:0

$ swift run -c release ViewportBenchmarks -- --column-query --gate
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=11 p99_ns=14 failures=0 budget_p95_ns=200 budget_p99_ns=400 headroom_p95=18.2x headroom_p99=28.6x gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=15 p99_ns=15 failures=0 budget_p95_ns=300 budget_p99_ns=600 headroom_p95=20.0x headroom_p99=40.0x gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=19 p99_ns=25 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=16.8x headroom_p99=25.6x gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=32 p99_ns=39 failures=0 budget_p95_ns=460 budget_p99_ns=920 headroom_p95=14.4x headroom_p99=23.6x gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=35 p99_ns=46 failures=0 budget_p95_ns=570 budget_p99_ns=1200 headroom_p95=16.3x headroom_p99=26.1x gate=pass checksum=639841560320
EXIT:0

$ swift run -c release ViewportBenchmarks -- --column-geometry-query --gate
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=14 p99_ns=16 failures=0 budget_p95_ns=260 budget_p99_ns=520 headroom_p95=18.6x headroom_p99=32.5x gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=25 failures=0 budget_p95_ns=350 budget_p99_ns=700 headroom_p95=16.7x headroom_p99=28.0x gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=23 failures=0 budget_p95_ns=390 budget_p99_ns=780 headroom_p95=18.6x headroom_p99=33.9x gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=45 p99_ns=50 failures=0 budget_p95_ns=840 budget_p99_ns=1700 headroom_p95=18.7x headroom_p99=34.0x gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=49 p99_ns=58 failures=0 budget_p95_ns=720 budget_p99_ns=1500 headroom_p95=14.7x headroom_p99=25.9x gate=pass checksum=839521520640
EXIT:0

$ swift run -c release ViewportBenchmarks -- --point-query --gate
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=25 p99_ns=26 failures=0 budget_p95_ns=770 budget_p99_ns=1600 headroom_p95=30.8x headroom_p99=61.5x gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=28 p99_ns=29 failures=0 budget_p95_ns=770 budget_p99_ns=1600 headroom_p95=27.5x headroom_p99=55.2x gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=44 p99_ns=49 failures=0 budget_p95_ns=900 budget_p99_ns=1800 headroom_p95=20.5x headroom_p99=36.7x gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=44 p99_ns=55 failures=0 budget_p95_ns=1100 budget_p99_ns=2200 headroom_p95=25.0x headroom_p99=40.0x gate=pass checksum=640022228480
EXIT:0
```

### Local band check — all 41 inside both ceilings

Parsed by key (not by column position, since `headroom_p99=` now sits between
`headroom_p95=` and `gate=` — any grep pattern assuming the old adjacency is
stale):

```text
scenarios=41 violations=0
max_headroom_p95=30.8x (point_query|uniform_100k)          ceiling=50x   OK
max_headroom_p99=61.5x (point_query|uniform_100k)          ceiling=100x  OK
min_headroom_p95=9.9x  (pipeline|100k_lines_80_visible_overscan_5)
min_headroom_p99=15.2x (variable_height_mutation|1m_lines_200_visible_overscan_50)
```

**41/41 `gate=pass`, every `headroom_p95` ≤ 50× and every `headroom_p99` ≤ 100×.**
Acceptance criteria 3 (pass) and 4 (band) met.

The two widest scenarios are both `point_query|uniform_*` (30.8× / 61.5×). They
are inside the ceiling but are the widest of the 41 — a direct consequence of the
n=3 sample base (see §11, §12).

## 5. Before/after headroom — all 41 gated scenarios

"Before" is the gate binary built from the merge base `5e2abf7` (which does not
emit headroom fields, so headroom is computed as `budget ÷ measured`); "after" is
the gate's own reported `headroom_p95` / `headroom_p99` at `be5f7e4`. Both runs
on the same machine, back to back.

| mode\|scenario | old b95 | old b99 | old h95 | old h99 | new b95 | new b99 | new h95 | new h99 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| bulk_structural_mutation\|100k_lines_batch_4096 | 1500000 | 2500000 | 24.3x | 39.5x | 1500000 | 2500000 | 25.0x | 40.9x |
| bulk_structural_mutation\|100k_lines_batch_64 | 150000 | 250000 | 18.8x | 30.7x | 150000 | 250000 | 18.5x | 29.7x |
| bulk_structural_mutation\|1k_lines_batch_64 | 60000 | 120000 | 22.2x | 43.0x | 60000 | 120000 | 22.2x | 43.4x |
| bulk_structural_mutation\|1m_lines_batch_4096 | 2500000 | 4000000 | 20.7x | 30.8x | 2500000 | 4000000 | 20.6x | 30.7x |
| bulk_structural_mutation\|1m_lines_batch_64 | 400000 | 600000 | 12.6x | 18.0x | 400000 | 600000 | 12.2x | 16.3x |
| **column_geometry_query\|prefixsum_100k** | 60000 | 120000 | **1578.9x** | **2857.1x** | 840 | 1700 | 18.7x | 34.0x |
| **column_geometry_query\|prefixsum_1m** | 120000 | 240000 | **2553.2x** | **5000.0x** | 720 | 1500 | 14.7x | 25.9x |
| **column_geometry_query\|uniform_100k** | 60000 | 120000 | **2727.3x** | **5217.4x** | 350 | 700 | 16.7x | 28.0x |
| **column_geometry_query\|uniform_1k** | 30000 | 60000 | **1500.0x** | **2857.1x** | 260 | 520 | 18.6x | 32.5x |
| **column_geometry_query\|uniform_1m** | 120000 | 240000 | **5000.0x** | **10000.0x** | 390 | 780 | 18.6x | 33.9x |
| **column_query\|prefixsum_100k** | 60000 | 120000 | **1714.3x** | **2790.7x** | 460 | 920 | 14.4x | 23.6x |
| **column_query\|prefixsum_1m** | 120000 | 240000 | **3243.2x** | **5000.0x** | 570 | 1200 | 16.3x | 26.1x |
| **column_query\|uniform_100k** | 60000 | 120000 | **3529.4x** | **6666.7x** | 300 | 600 | 20.0x | 40.0x |
| **column_query\|uniform_1k** | 30000 | 60000 | **2727.3x** | **4615.4x** | 200 | 400 | 18.2x | 28.6x |
| **column_query\|uniform_1m** | 120000 | 240000 | **6666.7x** | **12631.6x** | 320 | 640 | 16.8x | 25.6x |
| **line_geometry_query\|balanced_tree_100k** | 300000 | 600000 | **2419.4x** | **4109.6x** | 3000 | 6000 | 24.6x | 42.3x |
| **line_geometry_query\|balanced_tree_1m** | 600000 | 1200000 | **3296.7x** | **5797.1x** | 3400 | 6800 | 21.1x | 35.6x |
| **line_geometry_query\|uniform_100k** | 60000 | 120000 | **3333.3x** | **5217.4x** | 360 | 720 | 20.0x | 36.0x |
| **line_geometry_query\|uniform_1k** | 30000 | 60000 | **2142.9x** | **4000.0x** | 270 | 540 | 19.3x | 33.8x |
| **line_geometry_query\|uniform_1m** | 120000 | 240000 | **5714.3x** | **9230.8x** | 380 | 760 | 18.1x | 31.7x |
| **line_query\|balanced_tree_100k** | 300000 | 600000 | **3846.2x** | **5882.4x** | 1700 | 3400 | 18.9x | 36.6x |
| **line_query\|balanced_tree_1m** | 600000 | 1200000 | **5263.2x** | **9160.3x** | 2100 | 4200 | 18.6x | 33.6x |
| **line_query\|uniform_100k** | 60000 | 120000 | **4000.0x** | **7058.8x** | 280 | 560 | 18.7x | 37.3x |
| **line_query\|uniform_1k** | 30000 | 60000 | **2727.3x** | **5000.0x** | 190 | 430 | 17.3x | 30.7x |
| **line_query\|uniform_1m** | 120000 | 240000 | **6315.8x** | **12631.6x** | 320 | 640 | 17.8x | 33.7x |
| pipeline\|100k_lines_80_visible_overscan_5 | 50000 | 100000 | 10.1x | 18.9x | 50000 | 100000 | 9.9x | 19.3x |
| pipeline\|1k_lines_20_visible_overscan_0 | 20000 | 50000 | 14.8x | 35.6x | 20000 | 50000 | 16.1x | 38.7x |
| **pipeline\|1m_lines_200_visible_overscan_50** | 100000 | 200000 | 6.1x | 12.0x | 280000 | 560000 | 16.8x | 33.1x |
| **point_query\|prefixsum_100k** | 120000 | 240000 | **3157.9x** | **5714.3x** | 900 | 1800 | 20.5x | 36.7x |
| **point_query\|prefixsum_1m** | 240000 | 480000 | **3478.3x** | **6857.1x** | 1100 | 2200 | 25.0x | 40.0x |
| **point_query\|uniform_100k** | 120000 | 240000 | **4615.4x** | **6486.5x** | 770 | 1600 | 30.8x | 61.5x |
| **point_query\|uniform_1m** | 240000 | 480000 | **7272.7x** | **12631.6x** | 770 | 1600 | 27.5x | 55.2x |
| structural_mutation\|100k_lines_80_visible_overscan_5 | 80000 | 120000 | 16.1x | 23.3x | 80000 | 120000 | 15.8x | 22.9x |
| structural_mutation\|1k_lines_20_visible_overscan_0 | 20000 | 40000 | 21.4x | 40.9x | 20000 | 40000 | 20.9x | 40.3x |
| structural_mutation\|1m_lines_200_visible_overscan_50 | 250000 | 400000 | 12.1x | 18.8x | 250000 | 400000 | 12.2x | 18.7x |
| variable_height_mutation\|100k_lines_80_visible_overscan_5 | 20000 | 25000 | 13.2x | 15.8x | 20000 | 25000 | 12.9x | 15.4x |
| variable_height_mutation\|1k_lines_20_visible_overscan_0 | 5000 | 10000 | 13.1x | 24.8x | 5000 | 10000 | 12.7x | 24.2x |
| variable_height_mutation\|1m_lines_200_visible_overscan_50 | 60000 | 75000 | 13.0x | 15.9x | 60000 | 75000 | 12.5x | 15.2x |
| **variable_height\|100k_lines_80_visible_overscan_5** | 100000 | 200000 | **150.8x** | **292.0x** | 14000 | 28000 | 21.0x | 40.2x |
| **variable_height\|1k_lines_20_visible_overscan_0** | 50000 | 100000 | **241.5x** | **460.8x** | 4100 | 8200 | 19.8x | 36.9x |
| **variable_height\|1m_lines_200_visible_overscan_50** | 250000 | 500000 | **125.2x** | **235.2x** | 45000 | 90000 | 22.4x | 44.0x |

Bold rows are the **28 recalibrated** scenarios. The 13 mutation/pipeline rows
left unbold were already inside the band and were not touched (with the single
exception of `pipeline|1m_...`, bolded, which was below the floor).

**The defect, quantified.** Before this slice, the worst offenders sat at
**6,666×** (p95) and **12,631×** (p99) above observed latency. A function could
have gotten 1,000× slower and every gate would still have reported `gate=pass`.
That is the five-slice blind spot. After: nothing exceeds 30.8× / 61.5×.

## 6. Checksum proof — all 41 byte-identical to the pre-slice baseline

The claim under test: **budgets moved, but no measured path did.** Asserting that
from the diff would be weak. Instead, the merge base was materialized as a real
git worktree, built at `-c release`, and all ten gate modes were run from *that*
binary; the same was done on the branch; and the two checksum sets were diffed.

```text
$ git worktree add "$SCRATCH/baseline-5e2abf7" 5e2abf7
$ swift build --package-path "$SCRATCH/baseline-5e2abf7" -c release
Build complete! (3.83s)

# ten gate modes run against each binary; "mode|scenario checksum" extracted by key
$ diff baseline-ck.txt current-ck.txt
$ echo "DIFF_EXIT=$?"
DIFF_EXIT=0

$ wc -l < baseline-ck.txt ; wc -l < current-ck.txt
41
41

$ git worktree remove "$SCRATCH/baseline-5e2abf7"
```

**`diff` is empty across all 41 scenarios — exit 0.** Every checksum produced by
the `5e2abf7` binary is byte-identical to the one produced by the `be5f7e4`
binary, across all ten gate modes. The benchmark workloads, providers, and search
paths are untouched; only the budgets and the gate's pass/fail arithmetic changed.
**Acceptance criterion 3 met.**

(The `--point-query` gate already existed at `5e2abf7` as a local gate from
Slice 37, so all 41 scenarios — not just 37 — are directly comparable.)

## 7. Core diff — empty

```text
$ git diff --name-only main -- Sources/TextEngineCore
$ echo "core_files_changed=$(git diff --name-only main -- Sources/TextEngineCore | wc -l)"
core_files_changed=0
```

**Zero files changed under `Sources/TextEngineCore`.** This slice is a
benchmark/CI-governance slice; the engine is untouched. **Acceptance criterion 2
met.** The only `Package.swift` change is the added `ViewportBenchmarksTests`
target:

```text
$ git diff --stat 5e2abf7..HEAD -- Sources Tests Package.swift .github
 .github/scripts/derive-gate-budgets.sh             |  57 ++++++
 .github/workflows/swift-ci.yml                     |   4 +
 Package.swift                                      |   4 +
 Sources/ViewportBenchmarks/BenchmarkModels.swift   |  73 ++++++-
 Sources/ViewportBenchmarks/BenchmarkSupport.swift  |  21 +-
 .../ColumnGeometryQueryBenchmark.swift             |  23 ++-
 .../ViewportBenchmarks/ColumnQueryBenchmark.swift  |  15 +-
 .../LineGeometryQueryBenchmark.swift               |  18 +-
 .../ViewportBenchmarks/LineQueryBenchmark.swift    |  17 +-
 .../ViewportBenchmarks/PointQueryBenchmark.swift   |  33 +++-
 .../ViewportBenchmarks/SyntheticBenchmarks.swift   |  12 +-
 .../VariableHeightBenchmark.swift                  |  16 +-
 Tests/ViewportBenchmarksTests/GateLogicTests.swift | 213 +++++++++++++++++++++
 13 files changed, 450 insertions(+), 56 deletions(-)
```

## 8. Foundation-free scans

```text
$ rg -n "Foundation" Sources/TextEngineCore; echo "core exit=$?"
core exit=1

$ rg -n "Foundation" Sources/TextEngineReferenceProviders; echo "refprov exit=$?"
refprov exit=1

$ rg -n "Foundation" Sources/ViewportBenchmarks; echo "benchmarks exit=$?"
Sources/ViewportBenchmarks/BenchmarkSupport.swift:72:// One decimal place, without Foundation: `String(format:)` would drag Foundation
benchmarks exit=0
```

Core and reference providers: **no matches** (exit 1). The benchmark target has
exactly **one** match, and it is a **comment explaining the deliberate
avoidance** — the new `formatHeadroom` helper is hand-rolled precisely so that
`String(format:)` does not pull Foundation into a target that has none:

```swift
// One decimal place, without Foundation: `String(format:)` would drag Foundation
// into a target that has none, and the benchmark target must stay free of it.
// Returns the complete field value, `x` suffix included, so the unbounded case
// reads `inf` rather than `infx`.
func formatHeadroom(_ headroom: Double) -> String {
```

The invariant that actually matters — no `import Foundation` anywhere in
`Sources/` — holds:

```text
$ rg -n "^\s*import Foundation" Sources/; echo "exit=$?"
exit=1
```

(Recorded honestly rather than reported as a bare "clean": a naive
`rg Foundation` over the benchmark target returns exit 0, and a future reader
grepping for that would otherwise think the invariant had broken.)

## 9. Cross-target compile self-test

```text
$ ./.github/scripts/cross-target-compile.sh --self-test
self_test=pass
EXIT:0
```

## 10. THE DEMONSTRATION — the Slice 27 defect is now a gate failure

This is the load-bearing proof of the whole slice. Acceptance criterion 6 says
reverting a recalibrated budget must make `--gate` **fail** — demonstrated, not
asserted.

`line_query|uniform_1m`'s real recalibrated budget is `320 / 640`. It was
temporarily reverted to the old inflated placeholder `120_000 / 240_000` — the
exact class of value Slice 27 shipped.

**First, proof the substitution actually landed** (a `sed` that silently matches
nothing would make this whole demonstration vacuous — and the value in the plan's
illustrative table was *not* the value in the source; see §11):

```text
$ git diff --unified=0 Sources/ViewportBenchmarks/LineQueryBenchmark.swift | grep -E '^[+-]\s+p95Budget'
-                          p95BudgetNanoseconds: 320, p99BudgetNanoseconds: 640),
+                          p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
substitution_landed=yes
```

Then the gate:

```text
$ swift run -c release ViewportBenchmarks -- --line-query --gate
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=13 p99_ns=16 failures=0 budget_p95_ns=190 budget_p99_ns=430 headroom_p95=14.6x headroom_p99=26.9x gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=14 p99_ns=18 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=20.0x headroom_p99=31.1x gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=17 p99_ns=23 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 headroom_p95=7058.8x headroom_p99=10434.8x gate=fail reason=budget_stale checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=83 p99_ns=105 failures=0 budget_p95_ns=1700 budget_p99_ns=3400 headroom_p95=20.5x headroom_p99=32.4x gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=108 p99_ns=124 failures=0 budget_p95_ns=2100 budget_p99_ns=4200 headroom_p95=19.4x headroom_p99=33.9x gate=pass checksum=639841547520
exit=1
```

The failing line, verbatim:

```
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=17 p99_ns=23 failures=0 budget_p95_ns=120000 budget_p99_ns=240000 headroom_p95=7058.8x headroom_p99=10434.8x gate=fail reason=budget_stale checksum=639841600000
```

`gate=fail reason=budget_stale`, `headroom_p95=7058.8x` (ceiling 50×),
`headroom_p99=10434.8x` (ceiling 100×), process **exit=1**. The other four
scenarios still pass, so the failure is precisely attributed to the one reverted
budget — it is not a blanket failure.

Note the checksum is **unchanged** (`639841600000`) even in the failing run:
the workload ran identically; only the pass/fail verdict changed. That is the
cleanest possible statement of what this slice does and does not touch.

Restored:

```text
$ git diff --exit-code Sources/ViewportBenchmarks/LineQueryBenchmark.swift && echo "RESTORED CLEAN"
RESTORED CLEAN

$ git status --short
(empty)
```

**A budget that drifts 2,400–12,631× above reality is now a build failure, not a
silent no-op.** The regression that could hide behind the old budgets cannot hide
behind these.

## 11. Deviations from the plan

Recorded because a verification record that hides them is not evidence.

### 11a. The plan's illustrative budget table was wrong for two rows

The plan carried an illustrative table of expected budgets. The **script's output
governed**, and it landed one rounding step **tighter** than the table in two
`line_query` rows:

| Scenario | Plan's table | Script's actual output | Committed |
| --- | --- | --- | --- |
| `line_query\|uniform_1k` | 200 / 440 | **190 / 430** | 190 / 430 |
| `line_query\|uniform_1m` | 330 / 660 | **320 / 640** | 320 / 640 |

The committed source follows the script, not the table. This matters
operationally: the Task 7 brief's demonstration `sed` was written against the
table's `330 / 660` and **would have matched nothing**, silently producing a
"passing" gate run that proved nothing at all. The demonstration in §10 targets
the real committed value and explicitly verifies the substitution landed before
drawing any conclusion.

### 11b. The 3× floor does **not** bind for point-query — `8 × median` does

The plan predicted that on a 3-sample base the `3 × max` floor would be the
binding term for the point-query budgets. It is not. Computed from the corpus:

```text
point_query|prefixsum_100k  n=3   8*med=896    3*max=396   -> 8*median binds
point_query|prefixsum_1m    n=3   8*med=1064   3*max=513   -> 8*median binds
point_query|uniform_100k    n=3   8*med=768    3*max=291   -> 8*median binds
point_query|uniform_1m      n=3   8*med=768    3*max=288   -> 8*median binds
```

`8 × median` binds in **all four**. The reason is that with n=3 the three samples
are tightly clustered (e.g. `uniform_1m`: median 96, max 96), so `3 × max` stays
small and never overtakes `8 × median`. The floor only bites when a sample base
contains a genuine outlier — which, corpus-wide, happens in exactly one scenario
(`line_query|uniform_100k`, §2e).

The consequence is the opposite of what the plan assumed: **the thin sample base,
not the floor, is why point-query is the likeliest mode to need a later upward
re-derivation.** A tight n=3 cluster produces a budget that is tight *relative to
tails it has never seen*. This was corrected in the source comment by `a99f2d1`
("fix: correct false floor claim in point-query provenance comment") rather than
left as a false claim in the code.

## 12. Risks carried forward

1. **`point_query` n=3.** Thinnest base of any gated mode (§1). Its budgets are
   derived from three tightly-clustered runs and have never seen a tail. If it
   flakes, the correct response is to append the flaking run's samples to the
   corpus and re-derive — not to hand-inflate the budget back toward the Slice 27
   failure mode.

2. **A real p99 tail excursion already appeared, in this very PR's hosted run.**
   Two `line_geometry_query` scenarios in hosted run `29185634901` observed a p99
   **3.2–3.9× above anything in the corpus**:

   | Scenario | corpus max p99 (n=13) | observed p99 | budget p99 | runtime margin |
   | --- | ---: | ---: | ---: | ---: |
   | `line_geometry_query\|uniform_1k` | 84 | **330** | 540 | 1.6× |
   | `line_geometry_query\|uniform_1m` | 82 | **265** | 760 | 2.9× |

   Both still **passed** (330 < 540; 265 < 760), and neither is a gate violation —
   the 3× rule is a *derivation-time* floor on the budget, not a runtime check on
   the observation. But these two are now the closest of all 41 scenarios to a
   false-positive failure, and the n=13 corpus did not contain this tail. They,
   not point-query, are the most likely source of the first gate flake. If either
   flakes, append and re-derive.

   This is recorded rather than smoothed over: it is direct evidence for the
   spec's own "a thin sample base hides tails" risk, found by the first hosted run
   after calibration.

3. **Budgets are now genuinely tight (7–30× headroom, was up to 12,631×).** That
   is the point — but it means the gates will, for the first time, be capable of
   failing. A first flake is a success signal for this slice, not a regression in
   it.

## 13. Hosted proof — PR-head run `29185634901`

Verified at **step** level, not job conclusion: a green job can hide a dead
`continue-on-error` step (the standing lesson from Slice 16).

```text
$ gh run view 29185634901 --json databaseId,headSha,event,status,conclusion
run_id=29185634901
head_sha=be5f7e4c062a604f28d42b81fb1c7b497a56d9bf
event=pull_request
status=completed
conclusion=success
```

The run's head `be5f7e4` **is** this document's local verification HEAD — the
hosted evidence and the local evidence describe the same code.

All three required jobs `success`:

```text
job=Host tests and benchmark gate   conclusion=success
job=iOS cross-target compile        conclusion=success
job=WASM cross-target observation   conclusion=success
```

### Step-level detail — `Host tests and benchmark gate`

```text
1. Set up job                                        -> success
2. Initialize containers                             -> success
3. Check out repository                              -> success
4. Detect PR change scope                            -> success
5. Complete docs-only PR                             -> skipped   (correct: PR carries Swift)
6. Show toolchain                                    -> success
7. Run host tests                                    -> success   ** Executed 249 tests, with 0 failures **
8. Run synthetic benchmark gate                      -> success   (1)
9. Run variable-height benchmark gate                -> success   (2)
10. Run variable-height mutation benchmark gate      -> success   (3)
11. Run structural mutation benchmark gate           -> success   (4)
12. Run bulk structural mutation benchmark gate      -> success   (5)
13. Run line query benchmark gate                    -> success   (6)
14. Run line geometry query benchmark gate           -> success   (7)
15. Run column query benchmark gate                  -> success   (8)
16. Run column geometry query benchmark gate         -> success   (9)
17. Run point query benchmark gate                   -> success   (10) ** NEW — tenth blocking gate **
18. Run memory shape diagnostic                      -> success
19. Run RSS memory observation diagnostic            -> success
20. Observe realistic provider relative performance  -> success   (PR-only, continue-on-error — genuinely ran)
39. Post Check out repository                        -> success
40. Stop containers                                  -> success
41. Complete job                                     -> success
```

**All ten gate steps individually `success`** — checked one by one, not inferred
from the job's green conclusion. Step 20, the `continue-on-error` observation
step, genuinely ran (`success`, not `skipped`) — the exact step class that Slice
16 found silently dead.

`iOS cross-target compile`: step 6 `Compile cross-target packages for iOS` →
`success` (ran, not skipped).
`WASM cross-target observation`: step 7 `Observe cross-target packages for WASM` →
`success`.

### `mode=point_query` is now PRESENT in the hosted log

The inverse of the Slice 37 check, which required **0**:

```text
$ gh run view 29185634901 --log | grep -c "mode=point_query"
4
```

**4** — one line per point-query scenario. The gate is really executing on hosted
Linux, not merely wired up.

### The temporary observation step did NOT survive

An explicit acceptance criterion: the non-gate point-query observation step added
by `c1a0b3f` (to collect the corpus samples) had to be **removed** once the gate
was promoted by `afd8044`. It was:

```text
$ gh run view 29185634901 --log | grep -c "Observe point query"
0
```

**0.** No `Observe point query benchmark latency` step exists in this run. The
scaffolding is gone; only the blocking gate remains.

### Every hosted headroom — the band holds on the machine the budgets were cut for

Local macOS numbers do not validate budgets calibrated from hosted Linux x86_64.
These are the hosted values, parsed by key from the run's own gate-step logs:

| mode\|scenario | p95 | p99 | budget p95 | budget p99 | headroom_p95 | headroom_p99 | gate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| bulk_structural_mutation\|100k_lines_batch_4096 | 164363 | 174346 | 1500000 | 2500000 | 9.1x | 14.3x | pass |
| bulk_structural_mutation\|100k_lines_batch_64 | 16751 | 18593 | 150000 | 250000 | 9.0x | 13.4x | pass |
| bulk_structural_mutation\|1k_lines_batch_64 | 6255 | 6472 | 60000 | 120000 | 9.6x | 18.5x | pass |
| bulk_structural_mutation\|1m_lines_batch_4096 | 332342 | 355267 | 2500000 | 4000000 | 7.5x | 11.3x | pass |
| bulk_structural_mutation\|1m_lines_batch_64 | 56646 | 57859 | 400000 | 600000 | 7.1x | 10.4x | pass |
| column_geometry_query\|prefixsum_100k | 69 | 105 | 840 | 1700 | 12.2x | 16.2x | pass |
| column_geometry_query\|prefixsum_1m | 82 | 125 | 720 | 1500 | 8.8x | 12.0x | pass |
| column_geometry_query\|uniform_100k | 43 | 74 | 350 | 700 | 8.1x | 9.5x | pass |
| column_geometry_query\|uniform_1k | 33 | 66 | 260 | 520 | 7.9x | 7.9x | pass |
| column_geometry_query\|uniform_1m | 48 | 79 | 390 | 780 | 8.1x | 9.9x | pass |
| column_query\|prefixsum_100k | 60 | 97 | 460 | 920 | 7.7x | 9.5x | pass |
| column_query\|prefixsum_1m | 81 | 120 | 570 | 1200 | 7.0x | 10.0x | pass |
| column_query\|uniform_100k | 35 | 66 | 300 | 600 | 8.6x | 9.1x | pass |
| column_query\|uniform_1k | 24 | 53 | 200 | 400 | 8.3x | 7.5x | pass |
| column_query\|uniform_1m | 40 | 71 | 320 | 640 | 8.0x | 9.0x | pass |
| line_geometry_query\|balanced_tree_100k | 367 | 383 | 3000 | 6000 | 8.2x | 15.7x | pass |
| line_geometry_query\|balanced_tree_1m | 425 | 451 | 3400 | 6800 | 8.0x | 15.1x | pass |
| line_geometry_query\|uniform_100k | 42 | 73 | 360 | 720 | 8.6x | 9.9x | pass |
| line_geometry_query\|uniform_1k | 57 | **330** | 270 | 540 | 4.7x | **1.6x** | pass |
| line_geometry_query\|uniform_1m | 79 | **265** | 380 | 760 | 4.8x | **2.9x** | pass |
| line_query\|balanced_tree_100k | 210 | 219 | 1700 | 3400 | 8.1x | 15.5x | pass |
| line_query\|balanced_tree_1m | 256 | 273 | 2100 | 4200 | 8.2x | 15.4x | pass |
| line_query\|uniform_100k | 34 | 65 | 280 | 560 | 8.2x | 8.6x | pass |
| line_query\|uniform_1k | 25 | 54 | 190 | 430 | 7.6x | 8.0x | pass |
| line_query\|uniform_1m | 39 | 70 | 320 | 640 | 8.2x | 9.1x | pass |
| pipeline\|100k_lines_80_visible_overscan_5 | 10396 | 10598 | 50000 | 100000 | 4.8x | 9.4x | pass |
| pipeline\|1k_lines_20_visible_overscan_0 | 2480 | 2653 | 20000 | 50000 | 8.1x | 18.8x | pass |
| pipeline\|1m_lines_200_visible_overscan_50 | 33821 | 34653 | 280000 | 560000 | 8.3x | 16.2x | pass |
| point_query\|prefixsum_100k | 116 | 144 | 900 | 1800 | 7.8x | 12.5x | pass |
| point_query\|prefixsum_1m | 133 | 165 | 1100 | 2200 | 8.3x | 13.3x | pass |
| point_query\|uniform_100k | 87 | 125 | 770 | 1600 | 8.9x | 12.8x | pass |
| point_query\|uniform_1m | 87 | 114 | 770 | 1600 | 8.9x | 14.0x | pass |
| structural_mutation\|100k_lines_80_visible_overscan_5 | 9081 | 9863 | 80000 | 120000 | 8.8x | 12.2x | pass |
| structural_mutation\|1k_lines_20_visible_overscan_0 | 1984 | 2059 | 20000 | 40000 | 10.1x | 19.4x | pass |
| structural_mutation\|1m_lines_200_visible_overscan_50 | 36443 | 37179 | 250000 | 400000 | 6.9x | 10.8x | pass |
| variable_height_mutation\|100k_lines_80_visible_overscan_5 | 2802 | 2888 | 20000 | 25000 | 7.1x | 8.7x | pass |
| variable_height_mutation\|1k_lines_20_visible_overscan_0 | 782 | 847 | 5000 | 10000 | 6.4x | 11.8x | pass |
| variable_height_mutation\|1m_lines_200_visible_overscan_50 | 10032 | 10193 | 60000 | 75000 | 6.0x | 7.4x | pass |
| variable_height\|100k_lines_80_visible_overscan_5 | 2016 | 2098 | 14000 | 28000 | 6.9x | 13.3x | pass |
| variable_height\|1k_lines_20_visible_overscan_0 | 542 | 704 | 4100 | 8200 | 7.6x | 11.6x | pass |
| variable_height\|1m_lines_200_visible_overscan_50 | 6877 | 7014 | 45000 | 90000 | 6.5x | 12.8x | pass |

```text
hosted scenarios=41   gate=pass: 41   ceiling violations=0
max_headroom_p95=12.2x (column_geometry_query|prefixsum_100k)   ceiling=50x   OK
max_headroom_p99=19.4x (structural_mutation|1k_lines_20_visible_overscan_0)  ceiling=100x  OK
```

**41/41 `gate=pass` on hosted Linux x86_64, and every headroom is inside both
ceilings** — with far more margin than locally (max 12.2× hosted vs 30.8× local),
because the budgets were calibrated for this machine and macOS arm64 is simply
faster on these workloads.

The two bolded p99 cells (`line_geometry_query|uniform_1k` at 1.6×,
`uniform_1m` at 2.9×) are the tail excursion analyzed in §12.2 — they passed, but
they are the tightest runtime margins in the set and the most likely first flake.

### Head note

The only commit after `be5f7e4` on this branch is **this verification record
itself**, which is documentation and changes no measured behavior. Run
`29185634901` therefore covers every line of Swift, workflow, and budget that this
slice ships.

## Hosted Proof — Pending

The post-merge `push` run against the stable merge commit is **not yet available**
and is deliberately **not guessed here**. Per the project's clean-evidence
convention (Slices 31/33/35/37) and the standing stale-on-write lesson, it will be
recorded by a genuinely docs-only follow-up PR once `main` carries the merge:

- **Post-merge push run: _pending_** — merge commit _pending_, event `push`,
  branch `main`. To be verified at step level (all three required jobs; all ten
  gate steps `success`; `grep -c "mode=point_query"` non-zero; no
  `Observe point query` step) and recorded here. **This is the merged-code
  evidence anchor for Slice 38.**

Merge parentage (`git rev-list --parents -1 <merge>` → `<merge> 5e2abf7 <pr-head>`)
will be recorded alongside it to confirm the proof anchors the actually-merged head.

## Working tree

`git status --short` was **empty** before and after every command above (verified
after the §10 demonstration restore). No source, test, benchmark, or CI file was
left modified. The only file this task adds is this record.
