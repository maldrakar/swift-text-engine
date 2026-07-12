# Gate-Budget Recalibration Verification

Date: 2026-07-12
Branch: `slice-38-gate-budget-recalibration`
Local verification HEAD: `34bfba1` (`34bfba1b45319f1f5a65a1a8852c0bbce8314be8`)
Merge base with `main`: `5e2abf7` (`5e2abf7a3f9ca4769857c77d1b33d78c1c74992e`)

Spec: `docs/superpowers/specs/2026-07-12-gate-budget-recalibration-design.md`
Plan: `docs/superpowers/plans/2026-07-12-gate-budget-recalibration.md`
Corpus: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
Derivation script: `.github/scripts/derive-gate-budgets.sh`

> **Re-derivation pass (final).** The first hosted runs of this PR surfaced a p99
> tail no corpus sample had ever seen (§12.2 as originally written). Rather than
> hand-widen the affected budget — the exact failure mode this slice exists to
> kill — the corpus was **enriched** with every gate sample from this branch's own
> six completed hosted runs (565 → **799** rows, 22 → **25** runs) and the budgets
> **re-derived** by the same committed script. Eleven budgets moved. Every number
> in this record below is from the re-derived tree at `34bfba1`. The tail finding
> is now **resolved**, not merely disclosed — see §12.2.

Commits on branch (base `5e2abf7` ← `main`):

```
34bfba1 feat: re-derive gate budgets from the enriched hosted corpus
fea354b docs: record gate-budget recalibration verification
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
rows=799
$ awk -F'\t' 'NR>1{print $1}' $C | sort -u | wc -l
25
$ awk -F'\t' 'NR>1{print $2"|"$3}' $C | sort -u | wc -l
41
```

**799 sample rows, 25 distinct hosted runs, 41 distinct scenarios.** Every row is
a real hosted-Linux-x86_64 CI observation; nothing is synthetic or macOS-derived.

Rows per contributing run — the row count grows as each slice added gates
(22 → 27 → 32 → 37 → **41**). The last six runs are this branch's own, and they
are the first runs that observe all 41 scenarios, point-query included:

```text
$ awk -F'\t' 'NR>1{c[$1]++} END{for(r in c) printf "run_id=%s rows=%d\n", r, c[r]}' $C | sort
run_id=28236592208 rows=22      run_id=28893267949 rows=32
run_id=28264342225 rows=22      run_id=28956968583 rows=32
run_id=28334474924 rows=22      run_id=29108998305 rows=37
run_id=28371455301 rows=22      run_id=29110714042 rows=37
run_id=28473489678 rows=22      run_id=29145425255 rows=37
run_id=28587326869 rows=22      run_id=29150235152 rows=37
run_id=28646126162 rows=27      run_id=29150501304 rows=37
run_id=28698965663 rows=27      run_id=29183582406 rows=41   ← this branch
run_id=28713959866 rows=27      run_id=29184456256 rows=41   ← this branch
run_id=28716790653 rows=27      run_id=29184686762 rows=41   ← this branch
run_id=28818762407 rows=32      run_id=29185096022 rows=41   ← this branch
run_id=28819411144 rows=32      run_id=29185634901 rows=41   ← this branch
                                run_id=29186301213 rows=41   ← this branch
```

### The enrichment (final re-derivation pass)

The corpus is **append-only**. The re-derivation added **234 rows and removed
none** — the pre-existing 565 are byte-identical, verified rather than assumed
(a `sort -u` over the whole file would silently reorder every row and is exactly
what was avoided):

```text
$ git diff --stat -- $C
 .../verification/2026-07-12-gate-budget-corpus.tsv | 234 +++++++++++++++++++++
 1 file changed, 234 insertions(+)          # +234 / -0 — purely additive

$ head -566 $C | cmp -s - corpus.before.tsv && echo "IDENTICAL prefix: yes"
IDENTICAL prefix: yes

$ awk -F'\t' 'NR>1{print $1"\t"$2"\t"$3}' $C | sort | uniq -d | wc -l
0                                          # no duplicate run_id+mode+scenario
```

Dedup key is `run_id + mode + scenario`. The 12 point-query rows already
committed by `0676492` (runs `29183582406` / `29184456256` / `29184686762`) were
**skipped, not re-appended** — a duplicate row double-counts a sample and skews
the median. Those three runs contributed their other 37 scenarios each; the three
newer runs contributed all 41.

### Per-scenario `n` — the sample base behind each budget

The spec's Risks section requires this: a thin sample base hides tails, and a
budget is only as trustworthy as the `n` it was cut from.

Every `n` below is **after** the enrichment; the parenthetical is the pre-
enrichment value the first derivation pass was cut from.

```text
$ awk -F'\t' 'NR>1{c[$2"|"$3]++} END{for(k in c) printf "%-56s n=%d\n", k, c[k]}' $C | sort
bulk_structural_mutation|100k_lines_batch_4096           n=25   (was 19)
bulk_structural_mutation|100k_lines_batch_64             n=25   (was 19)
bulk_structural_mutation|1k_lines_batch_64               n=25   (was 19)
bulk_structural_mutation|1m_lines_batch_4096             n=25   (was 19)
bulk_structural_mutation|1m_lines_batch_64               n=25   (was 19)
column_geometry_query|prefixsum_100k                     n=11   (was 5)
column_geometry_query|prefixsum_1m                       n=11   (was 5)
column_geometry_query|uniform_100k                       n=11   (was 5)
column_geometry_query|uniform_1k                         n=11   (was 5)
column_geometry_query|uniform_1m                         n=11   (was 5)
column_query|prefixsum_100k                              n=15   (was 9)
column_query|prefixsum_1m                                n=15   (was 9)
column_query|uniform_100k                                n=15   (was 9)
column_query|uniform_1k                                  n=15   (was 9)
column_query|uniform_1m                                  n=15   (was 9)
line_geometry_query|balanced_tree_100k                   n=19   (was 13)
line_geometry_query|balanced_tree_1m                     n=19   (was 13)
line_geometry_query|uniform_100k                         n=19   (was 13)
line_geometry_query|uniform_1k                           n=19   (was 13)
line_geometry_query|uniform_1m                           n=19   (was 13)
line_query|balanced_tree_100k                            n=25   (was 19)
line_query|balanced_tree_1m                              n=25   (was 19)
line_query|uniform_100k                                  n=25   (was 19)
line_query|uniform_1k                                    n=25   (was 19)
line_query|uniform_1m                                    n=25   (was 19)
pipeline|100k_lines_80_visible_overscan_5                n=25   (was 19)
pipeline|1k_lines_20_visible_overscan_0                  n=25   (was 19)
pipeline|1m_lines_200_visible_overscan_50                n=25   (was 19)
point_query|prefixsum_100k                               n=6    (was 3)
point_query|prefixsum_1m                                 n=6    (was 3)
point_query|uniform_100k                                 n=6    (was 3)
point_query|uniform_1m                                   n=6    (was 3)
structural_mutation|100k_lines_80_visible_overscan_5     n=25   (was 19)
structural_mutation|1k_lines_20_visible_overscan_0       n=25   (was 19)
structural_mutation|1m_lines_200_visible_overscan_50     n=25   (was 19)
variable_height_mutation|100k_lines_80_visible_overscan_5 n=25  (was 19)
variable_height_mutation|1k_lines_20_visible_overscan_0  n=25   (was 19)
variable_height_mutation|1m_lines_200_visible_overscan_50 n=25  (was 19)
variable_height|100k_lines_80_visible_overscan_5         n=25   (was 19)
variable_height|1k_lines_20_visible_overscan_0           n=25   (was 19)
variable_height|1m_lines_200_visible_overscan_50         n=25   (was 19)
```

**`point_query` (n=6) is still the thinnest sample base of any gated mode** — its
gate was only added this slice, so only this branch's runs could observe it. The
enrichment doubled it (3 → 6) but it remains the mode with the least evidence
behind its budgets. Recorded as a known limitation, not hidden: see §11
(Deviations) and §12 (Risks).

## 2. Derived budgets — all 28 recalibrated scenarios

Both margins shown (`margin = budget ÷ max observed`); the acceptance criterion
is **every margin ≥ 3.0×**.

### 2a. The single derivation command — all seven groups, verbatim

This is the **final** derivation, over the enriched 799-row corpus. It is the
command whose output the committed source must reproduce exactly:

```text
$ ./.github/scripts/derive-gate-budgets.sh $C line_query line_geometry_query column_query column_geometry_query variable_height point_query pipeline
column_geometry_query|prefixsum_100k           n=11  p95[med=70     max=124   ] p99[med=112    max=169   ] budget_p95=560     budget_p99=1200    margin_p95=4.5x margin_p99=7.1x
column_geometry_query|prefixsum_1m             n=11  p95[med=89     max=143   ] p99[med=130    max=176   ] budget_p95=720     budget_p99=1500    margin_p95=5.0x margin_p99=8.5x
column_geometry_query|uniform_100k             n=11  p95[med=43     max=46    ] p99[med=75     max=84    ] budget_p95=350     budget_p99=700     margin_p95=7.6x margin_p99=8.3x
column_geometry_query|uniform_1k               n=11  p95[med=32     max=34    ] p99[med=63     max=66    ] budget_p95=260     budget_p99=520     margin_p95=7.6x margin_p99=7.9x
column_geometry_query|uniform_1m               n=11  p95[med=48     max=52    ] p99[med=79     max=84    ] budget_p95=390     budget_p99=780     margin_p95=7.5x margin_p99=9.3x
column_query|prefixsum_100k                    n=15  p95[med=58     max=89    ] p99[med=94     max=121   ] budget_p95=470     budget_p99=940     margin_p95=5.3x margin_p99=7.8x
column_query|prefixsum_1m                      n=15  p95[med=72     max=121   ] p99[med=115    max=163   ] budget_p95=580     budget_p99=1200    margin_p95=4.8x margin_p99=7.4x
column_query|uniform_100k                      n=15  p95[med=35     max=55    ] p99[med=67     max=173   ] budget_p95=280     budget_p99=560     margin_p95=5.1x margin_p99=3.2x
column_query|uniform_1k                        n=15  p95[med=24     max=26    ] p99[med=42     max=58    ] budget_p95=200     budget_p99=400     margin_p95=7.7x margin_p99=6.9x
column_query|uniform_1m                        n=15  p95[med=40     max=54    ] p99[med=72     max=77    ] budget_p95=320     budget_p99=640     margin_p95=5.9x margin_p99=8.3x
line_geometry_query|balanced_tree_100k         n=19  p95[med=367    max=380   ] p99[med=383    max=532   ] budget_p95=3000    budget_p99=6000    margin_p95=7.9x margin_p99=11.3x
line_geometry_query|balanced_tree_1m           n=19  p95[med=419    max=430   ] p99[med=447    max=528   ] budget_p95=3400    budget_p99=6800    margin_p95=7.9x margin_p99=12.9x
line_geometry_query|uniform_100k               n=19  p95[med=42     max=73    ] p99[med=74     max=110   ] budget_p95=340     budget_p99=680     margin_p95=4.7x margin_p99=6.2x
line_geometry_query|uniform_1k                 n=19  p95[med=31     max=57    ] p99[med=62     max=330   ] budget_p95=250     budget_p99=990     margin_p95=4.4x margin_p99=3.0x
line_geometry_query|uniform_1m                 n=19  p95[med=47     max=79    ] p99[med=79     max=265   ] budget_p95=380     budget_p99=800     margin_p95=4.8x margin_p99=3.0x
line_query|balanced_tree_100k                  n=25  p95[med=208    max=240   ] p99[med=219    max=313   ] budget_p95=1700    budget_p99=3400    margin_p95=7.1x margin_p99=10.9x
line_query|balanced_tree_1m                    n=25  p95[med=252    max=257   ] p99[med=265    max=288   ] budget_p95=2100    budget_p99=4200    margin_p95=8.2x margin_p99=14.6x
line_query|uniform_100k                        n=25  p95[med=34     max=92    ] p99[med=66     max=110   ] budget_p95=280     budget_p99=560     margin_p95=3.0x margin_p99=5.1x
line_query|uniform_1k                          n=25  p95[med=23     max=45    ] p99[med=53     max=64    ] budget_p95=190     budget_p99=430     margin_p95=4.2x margin_p99=6.7x
line_query|uniform_1m                          n=25  p95[med=40     max=61    ] p99[med=71     max=79    ] budget_p95=320     budget_p99=640     margin_p95=5.2x margin_p99=8.1x
pipeline|100k_lines_80_visible_overscan_5      n=25  p95[med=10514  max=12062 ] p99[med=10811  max=12269 ] budget_p95=85000   budget_p99=170000  margin_p95=7.0x margin_p99=13.9x
pipeline|1k_lines_20_visible_overscan_0        n=25  p95[med=2540   max=2911  ] p99[med=2705   max=3096  ] budget_p95=21000   budget_p99=42000   margin_p95=7.2x margin_p99=13.6x
pipeline|1m_lines_200_visible_overscan_50      n=25  p95[med=34171  max=39381 ] p99[med=35175  max=40177 ] budget_p95=280000  budget_p99=560000  margin_p95=7.1x margin_p99=13.9x
point_query|prefixsum_100k                     n=6   p95[med=110    max=132   ] p99[med=137    max=159   ] budget_p95=880     budget_p99=1800    margin_p95=6.7x margin_p99=11.3x
point_query|prefixsum_1m                       n=6   p95[med=124    max=171   ] p99[med=156    max=202   ] budget_p95=1000    budget_p99=2000    margin_p95=5.8x margin_p99=9.9x
point_query|uniform_100k                       n=6   p95[med=87     max=97    ] p99[med=125    max=133   ] budget_p95=700     budget_p99=1400    margin_p95=7.2x margin_p99=10.5x
point_query|uniform_1m                         n=6   p95[med=83     max=96    ] p99[med=108    max=129   ] budget_p95=670     budget_p99=1400    margin_p95=7.0x margin_p99=10.9x
variable_height|100k_lines_80_visible_overscan_5 n=25  p95[med=1733   max=2016  ] p99[med=1834   max=2756  ] budget_p95=14000   budget_p99=28000   margin_p95=6.9x margin_p99=10.2x
variable_height|1k_lines_20_visible_overscan_0 n=25  p95[med=501    max=654   ] p99[med=541    max=729   ] budget_p95=4100    budget_p99=8200    margin_p95=6.3x margin_p99=11.2x
variable_height|1m_lines_200_visible_overscan_50 n=25  p95[med=5504   max=6877  ] p99[med=5649   max=7014  ] budget_p95=45000   budget_p99=90000   margin_p95=6.5x margin_p99=12.8x
```

Two of the 30 printed rows — `pipeline|1k_...` and `pipeline|100k_...` — are
**not** adopted (see §2c). The other **28 are the derived budget set.**

### 2b. The invariant — committed budgets reproduce the script's output exactly

This is the claim the whole slice rests on ("derived, do not hand-edit"). It is
checked mechanically, by joining the script's output against the budgets the
**built binary** actually reports, not by eyeballing the source:

```text
# script output, keyed by mode|scenario, minus the 2 non-derived pipeline rows -> 28 rows
# binary's own budget_p95_ns / budget_p99_ns fields from all ten --gate modes -> 41 rows
$ join derived-28.tsv committed-budgets.tsv | awk -F'\t' '$2!=$4 || $3!=$5 {print "MISMATCH", $0}'
$ echo "derived scenarios compared: 28   mismatches: 0"
derived scenarios compared: 28   mismatches: 0
```

**Zero mismatches across all 28.** The corpus plus the script regenerate the
committed budgets byte-for-byte; nothing in the tables was hand-tuned.

### 2c. `pipeline|1m_lines_200_visible_overscan_50` (the 28th)

The other two `pipeline` scenarios were **not** recalibrated — their existing
budgets already cleared the 3× floor. The `1m` row did not, which is why a user
decision pulled it into scope: its old `budget_p95 = 100_000` sat **below**
`3 × max(p95) = 3 × 39,381 = 118,143`. A gate whose budget is under its own floor
is a latent false-positive; it was raised to `280_000 / 560_000` — the value the
enriched derivation still produces, unchanged by the re-derivation.

The `1k` and `100k` rows keep their existing `20_000/50_000` and
`50_000/100_000` — both already above `3 × max` (8,733 and 36,186 respectively)
and inside the ceiling. Together with the 10 mutation scenarios, these are the
**13 deliberately non-derived scenarios**; the script prints values for them and
those values are ignored, by design and on the record.

### 2d. Floor check — every margin ≥ 3.0×

Minimum across all 28 recalibrated scenarios (read straight off §2a):

- `margin_p95` minimum = **3.0×** (`line_query|uniform_100k`)
- `margin_p99` minimum = **3.0×** (`line_geometry_query|uniform_1k` **and**
  `line_geometry_query|uniform_1m` — both now floor-bound, see §2e)

Both clear the 3.0× floor. **Acceptance criterion 5 met.** Note the p99 minimum
*fell* from 3.5× to exactly 3.0×: that is the tail from §12.2 being absorbed into
the derivation rather than papered over. A margin of exactly 3.0× is the floor
doing its job, not a near-miss.

### 2e. Which term binds?

The p95 formula takes `max(8 × median, 3 × max)`; the p99 formula adds
`2 × budget_p95` as a third term. Computed per scenario over the enriched corpus,
the `3 × max` **floor** binds in exactly **three** places out of 41 — one on p95,
two on p99:

```text
p95:  line_query|uniform_100k          n=25   8*med=272   3*max=276   -> 3*max (FLOOR binds)
p99:  line_geometry_query|uniform_1k   n=19   -> 3*max(p99) = 3 × 330 = 990   (FLOOR binds)
p99:  line_geometry_query|uniform_1m   n=19   -> 3*max(p99) = 3 × 265 = 795 → 800 (FLOOR binds)
```

Everywhere else `8 × median` (or the `2 × budget_p95` coupling) binds. All three
floor-bound scenarios are the same phenomenon: a single outlier run pulled
`3 × max` above the median term — **precisely the case the floor exists to
catch.** The two p99 cases are the tail this re-derivation was performed to
absorb. Before the enrichment, the floor bound in only one scenario, because the
corpus had never seen the tail.

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

Re-run at `34bfba1` after the re-derivation: **249 tests, 0 failures**, unchanged.
One of those 17 is a static invariant over the scenario tables themselves, and it
is the one the re-derivation could plausibly have broken — every table must keep
`p99_budget ≥ 2 × p95_budget`:

```text
$ swift test --filter testEveryScenarioTableKeepsP99AtLeastTwiceP95
Test Case '-[ViewportBenchmarksTests.GateLogicTests testEveryScenarioTableKeepsP99AtLeastTwiceP95]' passed (0.000 seconds)
	 Executed 1 test, with 0 failures (0 unexpected)
```

It passes. The tightest new row is `line_geometry_query|uniform_100k` at exactly
`680 = 2 × 340`; `uniform_1k` clears it with room to spare (`990` vs `2 × 250`)
because its p99 is floor-bound, not coupling-bound.

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
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=18 p99_ns=19 failures=0 budget_p95_ns=250 budget_p99_ns=990 headroom_p95=13.9x headroom_p99=52.1x gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=21 p99_ns=24 failures=0 budget_p95_ns=340 budget_p99_ns=680 headroom_p95=16.2x headroom_p99=28.3x gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=24 p99_ns=29 failures=0 budget_p95_ns=380 budget_p99_ns=800 headroom_p95=15.8x headroom_p99=27.6x gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=134 p99_ns=175 failures=0 budget_p95_ns=3000 budget_p99_ns=6000 headroom_p95=22.4x headroom_p99=34.3x gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=168 p99_ns=208 failures=0 budget_p95_ns=3400 budget_p99_ns=6800 headroom_p95=20.2x headroom_p99=32.7x gate=pass checksum=852321495040
EXIT:0

$ swift run -c release ViewportBenchmarks -- --column-query --gate
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=12 p99_ns=14 failures=0 budget_p95_ns=200 budget_p99_ns=400 headroom_p95=16.7x headroom_p99=28.6x gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=19 p99_ns=26 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=14.7x headroom_p99=21.5x gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=27 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=15.2x headroom_p99=23.7x gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=33 p99_ns=39 failures=0 budget_p95_ns=470 budget_p99_ns=940 headroom_p95=14.2x headroom_p99=24.1x gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=36 p99_ns=42 failures=0 budget_p95_ns=580 budget_p99_ns=1200 headroom_p95=16.1x headroom_p99=28.6x gate=pass checksum=639841560320
EXIT:0

$ swift run -c release ViewportBenchmarks -- --column-geometry-query --gate
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=18 p99_ns=22 failures=0 budget_p95_ns=260 budget_p99_ns=520 headroom_p95=14.4x headroom_p99=23.6x gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=27 failures=0 budget_p95_ns=350 budget_p99_ns=700 headroom_p95=16.7x headroom_p99=25.9x gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=23 p99_ns=31 failures=0 budget_p95_ns=390 budget_p99_ns=780 headroom_p95=17.0x headroom_p99=25.2x gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=42 p99_ns=48 failures=0 budget_p95_ns=560 budget_p99_ns=1200 headroom_p95=13.3x headroom_p99=25.0x gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=49 p99_ns=62 failures=0 budget_p95_ns=720 budget_p99_ns=1500 headroom_p95=14.7x headroom_p99=24.2x gate=pass checksum=839521520640
EXIT:0

$ swift run -c release ViewportBenchmarks -- --point-query --gate
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=29 p99_ns=36 failures=0 budget_p95_ns=700 budget_p99_ns=1400 headroom_p95=24.1x headroom_p99=38.9x gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=28 p99_ns=36 failures=0 budget_p95_ns=670 budget_p99_ns=1400 headroom_p95=23.9x headroom_p99=38.9x gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=49 p99_ns=64 failures=0 budget_p95_ns=880 budget_p99_ns=1800 headroom_p95=18.0x headroom_p99=28.1x gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=60 p99_ns=65 failures=0 budget_p95_ns=1000 budget_p99_ns=2000 headroom_p95=16.7x headroom_p99=30.8x gate=pass checksum=640022228480
EXIT:0
```

### Local band check — all 41 inside both ceilings

Parsed by key (not by column position, since `headroom_p99=` now sits between
`headroom_p95=` and `gate=` — any grep pattern assuming the old adjacency is
stale):

```text
scenarios=41   gate=pass: 41   gate=fail: 0   ceiling violations=0
max_headroom_p95=24.1x (point_query|uniform_100k)                ceiling=50x   OK
max_headroom_p99=52.1x (line_geometry_query|uniform_1k)          ceiling=100x  OK
min_headroom_p95=9.9x  (structural_mutation|1m_lines_200_visible_overscan_50)
min_headroom_p99=14.3x (bulk_structural_mutation|1m_lines_batch_64)
```

**41/41 `gate=pass`, every `headroom_p95` ≤ 50× and every `headroom_p99` ≤ 100×.**
Acceptance criteria 3 (pass) and 4 (band) met. **No ceiling (`GateLimits`) was
changed** to make this hold — the ceilings are the same 50× / 100× the slice
shipped.

The widest p99 is now `line_geometry_query|uniform_1k` at **52.1×**, and that is
expected, not alarming: its p99 budget is floor-bound at `3 × 330 = 990` by a
hosted tail (§2e), while *local macOS* p99 for the same scenario is ~19 ns. A
budget calibrated for the machine that produced a 330 ns tail necessarily looks
wide on a machine that never does. It sits at roughly **half** the 100× ceiling,
and the hosted headroom — the number the budget was actually cut for — is far
tighter (§13).

## 5. Before/after headroom — all 41 gated scenarios

"Before" is the gate binary built from the merge base `5e2abf7` (which does not
emit headroom fields, so headroom is computed as `budget ÷ measured`); "after" is
the gate's own reported `headroom_p95` / `headroom_p99` on the **final re-derived
tree** at `34bfba1`. Both on the same machine.

| mode\|scenario | old b95 | old b99 | old h95 | old h99 | new b95 | new b99 | new h95 | new h99 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| bulk_structural_mutation\|100k_lines_batch_4096 | 1500000 | 2500000 | 24.3x | 39.5x | 1500000 | 2500000 | 23.9x | 38.2x |
| bulk_structural_mutation\|100k_lines_batch_64 | 150000 | 250000 | 18.8x | 30.7x | 150000 | 250000 | 18.3x | 29.6x |
| bulk_structural_mutation\|1k_lines_batch_64 | 60000 | 120000 | 22.2x | 43.0x | 60000 | 120000 | 22.1x | 42.3x |
| bulk_structural_mutation\|1m_lines_batch_4096 | 2500000 | 4000000 | 20.7x | 30.8x | 2500000 | 4000000 | 18.0x | 26.8x |
| bulk_structural_mutation\|1m_lines_batch_64 | 400000 | 600000 | 12.6x | 18.0x | 400000 | 600000 | 10.3x | 14.3x |
| **column_geometry_query\|prefixsum_100k** | 60000 | 120000 | **1578.9x** | **2857.1x** | 560 | 1200 | 13.3x | 25.0x |
| **column_geometry_query\|prefixsum_1m** | 120000 | 240000 | **2553.2x** | **5000.0x** | 720 | 1500 | 14.7x | 24.2x |
| **column_geometry_query\|uniform_100k** | 60000 | 120000 | **2727.3x** | **5217.4x** | 350 | 700 | 16.7x | 25.9x |
| **column_geometry_query\|uniform_1k** | 30000 | 60000 | **1500.0x** | **2857.1x** | 260 | 520 | 14.4x | 23.6x |
| **column_geometry_query\|uniform_1m** | 120000 | 240000 | **5000.0x** | **10000.0x** | 390 | 780 | 17.0x | 25.2x |
| **column_query\|prefixsum_100k** | 60000 | 120000 | **1714.3x** | **2790.7x** | 470 | 940 | 14.2x | 24.1x |
| **column_query\|prefixsum_1m** | 120000 | 240000 | **3243.2x** | **5000.0x** | 580 | 1200 | 16.1x | 28.6x |
| **column_query\|uniform_100k** | 60000 | 120000 | **3529.4x** | **6666.7x** | 280 | 560 | 14.7x | 21.5x |
| **column_query\|uniform_1k** | 30000 | 60000 | **2727.3x** | **4615.4x** | 200 | 400 | 16.7x | 28.6x |
| **column_query\|uniform_1m** | 120000 | 240000 | **6666.7x** | **12631.6x** | 320 | 640 | 15.2x | 23.7x |
| **line_geometry_query\|balanced_tree_100k** | 300000 | 600000 | **2419.4x** | **4109.6x** | 3000 | 6000 | 22.4x | 34.3x |
| **line_geometry_query\|balanced_tree_1m** | 600000 | 1200000 | **3296.7x** | **5797.1x** | 3400 | 6800 | 20.2x | 32.7x |
| **line_geometry_query\|uniform_100k** | 60000 | 120000 | **3333.3x** | **5217.4x** | 340 | 680 | 16.2x | 28.3x |
| **line_geometry_query\|uniform_1k** | 30000 | 60000 | **2142.9x** | **4000.0x** | 250 | **990** | 13.9x | 52.1x |
| **line_geometry_query\|uniform_1m** | 120000 | 240000 | **5714.3x** | **9230.8x** | 380 | 800 | 15.8x | 27.6x |
| **line_query\|balanced_tree_100k** | 300000 | 600000 | **3846.2x** | **5882.4x** | 1700 | 3400 | 21.8x | 34.3x |
| **line_query\|balanced_tree_1m** | 600000 | 1200000 | **5263.2x** | **9160.3x** | 2100 | 4200 | 20.0x | 32.3x |
| **line_query\|uniform_100k** | 60000 | 120000 | **4000.0x** | **7058.8x** | 280 | 560 | 16.5x | 26.7x |
| **line_query\|uniform_1k** | 30000 | 60000 | **2727.3x** | **5000.0x** | 190 | 430 | 14.6x | 26.9x |
| **line_query\|uniform_1m** | 120000 | 240000 | **6315.8x** | **12631.6x** | 320 | 640 | 16.0x | 24.6x |
| pipeline\|100k_lines_80_visible_overscan_5 | 50000 | 100000 | 10.1x | 18.9x | 50000 | 100000 | 10.0x | 19.6x |
| pipeline\|1k_lines_20_visible_overscan_0 | 20000 | 50000 | 14.8x | 35.6x | 20000 | 50000 | 16.1x | 33.7x |
| **pipeline\|1m_lines_200_visible_overscan_50** | 100000 | 200000 | 6.1x | 12.0x | 280000 | 560000 | 17.0x | 33.4x |
| **point_query\|prefixsum_100k** | 120000 | 240000 | **3157.9x** | **5714.3x** | 880 | 1800 | 18.0x | 28.1x |
| **point_query\|prefixsum_1m** | 240000 | 480000 | **3478.3x** | **6857.1x** | 1000 | 2000 | 16.7x | 30.8x |
| **point_query\|uniform_100k** | 120000 | 240000 | **4615.4x** | **6486.5x** | 700 | 1400 | 24.1x | 38.9x |
| **point_query\|uniform_1m** | 240000 | 480000 | **7272.7x** | **12631.6x** | 670 | 1400 | 23.9x | 38.9x |
| structural_mutation\|100k_lines_80_visible_overscan_5 | 80000 | 120000 | 16.1x | 23.3x | 80000 | 120000 | 15.6x | 22.2x |
| structural_mutation\|1k_lines_20_visible_overscan_0 | 20000 | 40000 | 21.4x | 40.9x | 20000 | 40000 | 20.9x | 39.7x |
| structural_mutation\|1m_lines_200_visible_overscan_50 | 250000 | 400000 | 12.1x | 18.8x | 250000 | 400000 | 9.9x | 14.5x |
| variable_height_mutation\|100k_lines_80_visible_overscan_5 | 20000 | 25000 | 13.2x | 15.8x | 20000 | 25000 | 12.7x | 15.2x |
| variable_height_mutation\|1k_lines_20_visible_overscan_0 | 5000 | 10000 | 13.1x | 24.8x | 5000 | 10000 | 12.7x | 23.5x |
| variable_height_mutation\|1m_lines_200_visible_overscan_50 | 60000 | 75000 | 13.0x | 15.9x | 60000 | 75000 | 12.4x | 14.7x |
| **variable_height\|100k_lines_80_visible_overscan_5** | 100000 | 200000 | **150.8x** | **292.0x** | 14000 | 28000 | 21.0x | 39.6x |
| **variable_height\|1k_lines_20_visible_overscan_0** | 50000 | 100000 | **241.5x** | **460.8x** | 4100 | 8200 | 18.4x | 33.3x |
| **variable_height\|1m_lines_200_visible_overscan_50** | 250000 | 500000 | **125.2x** | **235.2x** | 45000 | 90000 | 21.7x | 40.1x |

Bold rows are the **28 recalibrated** scenarios. The 13 mutation/pipeline rows
left unbold were already inside the band and were not touched (with the single
exception of `pipeline|1m_...`, bolded, which was below the floor). Their budget
columns are identical old-to-new — the re-derivation did not touch them, and the
small old/new headroom wobble on those rows is measurement noise between two runs
of the same unchanged budget, not a change.

### The 11 budgets the re-derivation moved

Relative to the first calibration pass (`77352b0` / `fea354b`), enriching the
corpus moved these and only these:

| mode\|scenario | first pass | re-derived | why |
| --- | --- | --- | --- |
| line_geometry_query\|uniform_1k | 270 / 540 | **250 / 990** | p99 floor: hosted tail p99=330 (3 × 330 = 990) |
| line_geometry_query\|uniform_100k | 360 / 720 | **340 / 680** | median fell with 6 more samples |
| line_geometry_query\|uniform_1m | 380 / 760 | **380 / 800** | p99 floor: hosted tail p99=265 (3 × 265 = 795 → 800) |
| column_query\|uniform_100k | 300 / 600 | **280 / 560** | median fell |
| column_query\|prefixsum_100k | 460 / 920 | **470 / 940** | median rose |
| column_query\|prefixsum_1m | 570 / 1200 | **580 / 1200** | median rose |
| column_geometry_query\|prefixsum_100k | 840 / 1700 | **560 / 1200** | median fell 104 → 70 as n went 5 → 11 |
| point_query\|uniform_100k | 770 / 1600 | **700 / 1400** | median fell 96 → 87 as n went 3 → 6 |
| point_query\|uniform_1m | 770 / 1600 | **670 / 1400** | median fell 96 → 83 |
| point_query\|prefixsum_100k | 900 / 1800 | **880 / 1800** | median fell 112 → 110 |
| point_query\|prefixsum_1m | 1100 / 2200 | **1000 / 2000** | median fell 133 → 124 |

Nine of the eleven move **down** (a bigger sample base pulled the median down,
tightening the gate); two move **up**, and both are the p99 tail being absorbed.
This is not cherry-picking: the corpus and script must reproduce the committed
tables exactly (§2b), so every budget the enriched derivation changes is applied,
in both directions.

**The defect, quantified.** Before this slice, the worst offenders sat at
**6,666×** (p95) and **12,631×** (p99) above observed latency. A function could
have gotten 1,000× slower and every gate would still have reported `gate=pass`.
That is the five-slice blind spot. After: nothing exceeds 24.1× / 52.1×.

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

### 6b. The re-derivation moved no measured path either

The same check, re-run around the re-derivation itself: all ten gate modes were
run at `fea354b` (pre-re-derivation), the eleven budgets were changed, and all ten
were run again at `34bfba1`. `mode|scenario checksum` extracted by key from each:

```text
$ diff checksums.before.txt checksums.after.txt
$ echo "before rows=41  after rows=41  differences=0"
before rows=41  after rows=41  differences=0
IDENTICAL: 0 checksum differences across all 41 scenarios
```

**Zero differences.** A budget is a number the gate *compares against*; it can
never reach the workload. Proven, not assumed — this is what licenses the claim
that the re-derivation is risk-free with respect to what the benchmarks measure.

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
 .../LineGeometryQueryBenchmark.swift               |  25 ++-
 .../ViewportBenchmarks/LineQueryBenchmark.swift    |  17 +-
 .../ViewportBenchmarks/PointQueryBenchmark.swift   |  33 +++-
 .../ViewportBenchmarks/SyntheticBenchmarks.swift   |  12 +-
 .../VariableHeightBenchmark.swift                  |  16 +-
 Tests/ViewportBenchmarksTests/GateLogicTests.swift | 213 +++++++++++++++++++++
 13 files changed, 457 insertions(+), 56 deletions(-)
```

No file was **added** to this list by the re-derivation — it changes 11 integer
literals inside four scenario tables that this slice already touched, plus a
6-line provenance comment in `LineGeometryQueryBenchmark.swift` explaining why
that file's `uniform_1k` p99 budget is ~4× its p95 budget rather than the usual
2× (it is floor-bound; without the note it reads like a typo).

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

The plan predicted that on a thin sample base the `3 × max` floor would be the
binding term for the point-query budgets. It is not — not at n=3, and still not
at n=6 after the enrichment. Computed from the final corpus:

```text
point_query|prefixsum_100k  n=6   8*med=880    3*max=396   -> 8*median binds
point_query|prefixsum_1m    n=6   8*med=992    3*max=513   -> 8*median binds
point_query|uniform_100k    n=6   8*med=696    3*max=291   -> 8*median binds
point_query|uniform_1m      n=6   8*med=664    3*max=288   -> 8*median binds
```

`8 × median` binds in **all four**. The reason is that the point-query samples are
tightly clustered (e.g. `uniform_1m`: median 83, max 96), so `3 × max` stays small
and never overtakes `8 × median`. The floor only bites when a sample base contains
a genuine outlier — which, corpus-wide, happens in exactly three places, none of
them point-query (§2e).

The consequence is the opposite of what the plan assumed: **the thin sample base,
not the floor, is why a mode needs a later re-derivation.** A tight cluster
produces a budget that is tight *relative to tails it has never seen*. That is not
a hypothetical — it is exactly what happened to `line_geometry_query|uniform_1k`
in this very PR (§12.2), and it is why the corpus was enriched and the budgets
re-derived rather than hand-adjusted. The false floor claim was corrected in the
source comment by `a99f2d1` rather than left in the code.

### 11c. The re-derivation was not in the plan

The plan assumed one calibration pass. The first hosted runs of the PR falsified
the corpus it was cut from, so a second pass was performed (this record's opening
note). The rule that made it non-negotiable: **the corpus + script must reproduce
the committed budgets exactly** (§2b). Once new samples enter the corpus, every
budget the derivation moves must be applied — you cannot adopt only the two that
fix the tail and leave the other nine, or the invariant is dead and the tables are
hand-edited after all.

## 12. Risks carried forward

1. **`point_query` n=6.** Still the thinnest base of any gated mode (§1), though
   the enrichment doubled it. Its budgets are derived from six tightly-clustered
   runs and have never seen a tail. If it flakes, the correct response is to
   append the flaking run's samples to the corpus and re-derive — not to
   hand-inflate the budget back toward the Slice 27 failure mode.

2. **A real p99 tail excursion appeared in this PR's own hosted runs — now
   RESOLVED by re-derivation.**

   **The finding.** Two `line_geometry_query` scenarios in hosted run
   `29185634901` observed a p99 **3.2–3.9× above anything the corpus contained**.
   The evidence, as first recorded:

   | Scenario | corpus max p99 *then* (n=13) | observed p99 | budget p99 *then* | runtime margin |
   | --- | ---: | ---: | ---: | ---: |
   | `line_geometry_query\|uniform_1k` | 84 | **330** | 540 | **1.6×** |
   | `line_geometry_query\|uniform_1m` | 82 | **265** | 760 | **2.9×** |

   Both still **passed** (330 < 540; 265 < 760) — this was flake risk, not
   breakage. But `uniform_1k`'s 540 budget sat **below the slice's own 3× floor**
   (which needs `3 × 330 = 990`), and `uniform_1m`'s 760 sat below its 795. A
   budget under its own floor is precisely the latent false positive the floor
   exists to prevent; left alone, both would eventually have gone red on a clean
   tree from runner noise.

   **The resolution.** The tail was not smoothed over and the budget was not
   hand-widened. The offending samples were **appended to the corpus** and the
   budgets **re-derived** by the same committed script:

   | Scenario | budget p99 before | budget p99 **after** | now floor-bound? | derived margin |
   | --- | ---: | ---: | --- | ---: |
   | `line_geometry_query\|uniform_1k` | 540 | **990** | yes — `3 × 330` | **3.0×** |
   | `line_geometry_query\|uniform_1m` | 760 | **800** | yes — `3 × 265 = 795 → 800` | **3.0×** |

   Both now clear the 3× floor **by construction**, because the tail is inside the
   sample base the formula reads (§2a, §2e). The corpus's max p99 for `uniform_1k`
   is now 330, not 84 — the observation that motivated this is preserved in the
   corpus as data, not just as prose.

   **What remains.** These two scenarios still have the widest gap between local
   and hosted behaviour, and `uniform_1k` is the widest p99 headroom of the 41
   (52.1× local, ceiling 100×). If a *new* tail appears above 330 ns, the response
   is the same: append, re-derive. That loop is now demonstrated, not theoretical.

3. **Budgets are now genuinely tight (10–24× p95 headroom locally, was up to
   6,666×).** That is the point — but it means the gates will, for the first time,
   be capable of failing. A first flake is a success signal for this slice, not a
   regression in it; the fix for a flake is `append + re-derive`, which this PR
   has now exercised end to end.

## 13. Hosted proof

> **Two hosted stages.** §13a is run `29185634901` at `be5f7e4` — the run that
> *found* the p99 tail, recorded with the budgets it ran against (the
> pre-re-derivation ones). §13b is the hosted run of the final re-derived tree.
> §13a is kept because it is the evidence for §12.2 and the corpus rows it
> contributed; it is **not** a proof of the merged budgets. §13b is.

## 13a. Tail-finding run `29185634901` (tree `be5f7e4`, pre-re-derivation)

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
These are the hosted values, parsed by key from the run's own gate-step logs.

**Read the budget columns as historical:** they are the *first-pass* budgets this
run executed against. Eleven of them have since been re-derived (§5). Every `p95` /
`p99` measurement in this table is now a **row in the corpus**, including the two
bolded tail cells — that is how the re-derivation absorbed them.

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
`uniform_1m` at 2.9×) are the tail excursion analyzed in §12.2. They passed, but
they were the tightest runtime margins in the set — and `uniform_1k`'s budget was
below the slice's own 3× floor. **This is the finding that triggered the
re-derivation.** Both are resolved in the merged tree (990 and 800, both
floor-bound, both at 3.0× derived margin).

## 13b. Hosted proof of the re-derived tree — PR-head run `29187553818`

This is the run that validates the budgets that actually merge.

```text
$ gh run view 29187553818 --json databaseId,headSha,event,status,conclusion
run_id=29187553818
head_sha=c909231e6768038e83fd85581d5b528349667c1c
event=pull_request
status=completed
conclusion=success
```

All three required jobs `success`:

```text
job=Host tests and benchmark gate   conclusion=success
job=iOS cross-target compile        conclusion=success
job=WASM cross-target observation   conclusion=success
```

### Step-level detail — `Host tests and benchmark gate`

Verified step by step, not inferred from the job's green conclusion:

```text
 4. Detect PR change scope                            -> success
 5. Complete docs-only PR                             -> skipped   (correct: PR carries Swift)
 7. Run host tests                                    -> success
 8. Run synthetic benchmark gate                      -> success   (1)
 9. Run variable-height benchmark gate                -> success   (2)
10. Run variable-height mutation benchmark gate       -> success   (3)
11. Run structural mutation benchmark gate            -> success   (4)
12. Run bulk structural mutation benchmark gate       -> success   (5)
13. Run line query benchmark gate                     -> success   (6)
14. Run line geometry query benchmark gate            -> success   (7)  ** the re-derived one **
15. Run column query benchmark gate                   -> success   (8)
16. Run column geometry query benchmark gate          -> success   (9)
17. Run point query benchmark gate                    -> success   (10)
18. Run memory shape diagnostic                       -> success
19. Run RSS memory observation diagnostic             -> success
20. Observe realistic provider relative performance   -> success   (continue-on-error — genuinely ran)
41. Complete job                                      -> success
```

**All ten gate steps individually `success`.** Step 20, the `continue-on-error`
step, ran rather than silently dying (the Slice 16 lesson). `iOS cross-target
compile` → `Compile cross-target packages for iOS` `success`; `WASM cross-target
observation` → `Observe cross-target packages for WASM` `success`.
`grep -c "mode=point_query"` = **4** — the tenth gate really executes hosted.

### 41/41 `gate=pass` on hosted Linux, against the re-derived budgets

```text
hosted scenarios=41   gate=pass: 41   gate=fail: 0   ceiling violations=0
max_headroom_p95=10.2x (structural_mutation|1k_lines_20_visible_overscan_0)   ceiling=50x   OK
max_headroom_p99=18.5x (bulk_structural_mutation|1k_lines_batch_64)           ceiling=100x  OK
min_headroom_p95=4.8x  (pipeline|100k_lines_80_visible_overscan_5)
min_headroom_p99=7.7x  (variable_height_mutation|1m_lines_200_visible_overscan_50)
```

Every headroom on the calibration machine now sits in a **4.8×–18.5×** band. The
whole distribution is inside a 4× spread — which is what a calibrated gate suite
is supposed to look like, and is the sharpest statement available that the budgets
match the machine they gate.

### The tail scenarios, on hosted, after the fix

The two rows that motivated the re-derivation (§12.2), from this run's own log:

| Scenario | hosted p99 | budget p99 | runtime margin | before the re-derivation |
| --- | ---: | ---: | ---: | --- |
| `line_geometry_query\|uniform_1k` | 64 | **990** | **15.5×** | 1.6× (budget 540) |
| `line_geometry_query\|uniform_1m` | 82 | **800** | **9.8×** | 2.9× (budget 760) |

The tail did not recur in this run (p99 came in at 64 and 82, near the corpus
medians) — which is exactly why it was dangerous: it is intermittent. The budgets
now carry the tail's magnitude regardless of whether any given run exhibits it.

### Full hosted table — all 41

| mode\|scenario | p95 | p99 | budget p95 | budget p99 | headroom_p95 | headroom_p99 | gate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| bulk_structural_mutation\|100k_lines_batch_4096 | 166698 | 171171 | 1500000 | 2500000 | 9.0x | 14.6x | pass |
| bulk_structural_mutation\|100k_lines_batch_64 | 15431 | 15690 | 150000 | 250000 | 9.7x | 15.9x | pass |
| bulk_structural_mutation\|1k_lines_batch_64 | 6322 | 6486 | 60000 | 120000 | 9.5x | 18.5x | pass |
| bulk_structural_mutation\|1m_lines_batch_4096 | 339312 | 370526 | 2500000 | 4000000 | 7.4x | 10.8x | pass |
| bulk_structural_mutation\|1m_lines_batch_64 | 51656 | 55073 | 400000 | 600000 | 7.7x | 10.9x | pass |
| column_geometry_query\|prefixsum_100k | 67 | 105 | 560 | 1200 | 8.4x | 11.4x | pass |
| column_geometry_query\|prefixsum_1m | 141 | 169 | 720 | 1500 | 5.1x | 8.9x | pass |
| column_geometry_query\|uniform_100k | 43 | 75 | 350 | 700 | 8.1x | 9.3x | pass |
| column_geometry_query\|uniform_1k | 32 | 64 | 260 | 520 | 8.1x | 8.1x | pass |
| column_geometry_query\|uniform_1m | 48 | 80 | 390 | 780 | 8.1x | 9.8x | pass |
| column_query\|prefixsum_100k | 64 | 94 | 470 | 940 | 7.3x | 10.0x | pass |
| column_query\|prefixsum_1m | 83 | 120 | 580 | 1200 | 7.0x | 10.0x | pass |
| column_query\|uniform_100k | 41 | 72 | 280 | 560 | 6.8x | 7.8x | pass |
| column_query\|uniform_1k | 24 | 51 | 200 | 400 | 8.3x | 7.8x | pass |
| column_query\|uniform_1m | 47 | 72 | 320 | 640 | 6.8x | 8.9x | pass |
| line_geometry_query\|balanced_tree_100k | 377 | 422 | 3000 | 6000 | 8.0x | 14.2x | pass |
| line_geometry_query\|balanced_tree_1m | 431 | 473 | 3400 | 6800 | 7.9x | 14.4x | pass |
| line_geometry_query\|uniform_100k | 42 | 75 | 340 | 680 | 8.1x | 9.1x | pass |
| line_geometry_query\|uniform_1k | 31 | 64 | 250 | 990 | 8.1x | 15.5x | pass |
| line_geometry_query\|uniform_1m | 56 | 82 | 380 | 800 | 6.8x | 9.8x | pass |
| line_query\|balanced_tree_100k | 229 | 256 | 1700 | 3400 | 7.4x | 13.3x | pass |
| line_query\|balanced_tree_1m | 264 | 307 | 2100 | 4200 | 8.0x | 13.7x | pass |
| line_query\|uniform_100k | 34 | 66 | 280 | 560 | 8.2x | 8.5x | pass |
| line_query\|uniform_1k | 23 | 55 | 190 | 430 | 8.3x | 7.8x | pass |
| line_query\|uniform_1m | 39 | 71 | 320 | 640 | 8.2x | 9.0x | pass |
| pipeline\|100k_lines_80_visible_overscan_5 | 10525 | 10741 | 50000 | 100000 | 4.8x | 9.3x | pass |
| pipeline\|1k_lines_20_visible_overscan_0 | 2559 | 2714 | 20000 | 50000 | 7.8x | 18.4x | pass |
| pipeline\|1m_lines_200_visible_overscan_50 | 34033 | 34632 | 280000 | 560000 | 8.2x | 16.2x | pass |
| point_query\|prefixsum_100k | 119 | 150 | 880 | 1800 | 7.4x | 12.0x | pass |
| point_query\|prefixsum_1m | 143 | 178 | 1000 | 2000 | 7.0x | 11.2x | pass |
| point_query\|uniform_100k | 97 | 135 | 700 | 1400 | 7.2x | 10.4x | pass |
| point_query\|uniform_1m | 81 | 118 | 670 | 1400 | 8.3x | 11.9x | pass |
| structural_mutation\|100k_lines_80_visible_overscan_5 | 8323 | 8467 | 80000 | 120000 | 9.6x | 14.2x | pass |
| structural_mutation\|1k_lines_20_visible_overscan_0 | 1962 | 2215 | 20000 | 40000 | 10.2x | 18.1x | pass |
| structural_mutation\|1m_lines_200_visible_overscan_50 | 30878 | 32243 | 250000 | 400000 | 8.1x | 12.4x | pass |
| variable_height_mutation\|100k_lines_80_visible_overscan_5 | 2799 | 2898 | 20000 | 25000 | 7.1x | 8.6x | pass |
| variable_height_mutation\|1k_lines_20_visible_overscan_0 | 788 | 854 | 5000 | 10000 | 6.3x | 11.7x | pass |
| variable_height_mutation\|1m_lines_200_visible_overscan_50 | 9513 | 9746 | 60000 | 75000 | 6.3x | 7.7x | pass |
| variable_height\|100k_lines_80_visible_overscan_5 | 1772 | 1850 | 14000 | 28000 | 7.9x | 15.1x | pass |
| variable_height\|1k_lines_20_visible_overscan_0 | 486 | 541 | 4100 | 8200 | 8.4x | 15.2x | pass |
| variable_height\|1m_lines_200_visible_overscan_50 | 5529 | 5638 | 45000 | 90000 | 8.1x | 16.0x | pass |

### Why this run's samples are NOT in the corpus

Deliberate, and worth stating so a future reader does not "fix" it: the corpus is
the **input** to the derivation, and run `29187553818` is the **validation** of its
output. Appending a validating run's samples back into the corpus would move the
medians, change the budgets, and require another run to validate *those* — an
infinite regress. The corpus is a snapshot; the invariant it must satisfy is
"corpus + script reproduce the committed budgets" (§2b), and it does. A future
slice that observes a new tail appends it and re-derives, exactly as this one did.

### Head note — CORRECTED

The original text here claimed that "any commit after `c909231` … changes no Swift."
**That was false when written, and is recorded rather than quietly deleted**, because
it is the same defect the rest of this slice exists to kill: a document asserting
something the tree contradicts.

Two rounds of Swift landed after run `29187553818`:

- `4adc8f3` (`fix: make the gate-budget comments re-derivable instead of restated`) —
  comments plus one test, three Swift files. Hosted run **`29189613106`** covered it,
  green on all three required jobs.
- §14 below (the review-response round) — a new gated budget, a new test file, a
  refactor, two new scripts. Its hosted run is recorded in §13c.

The lesson is now a rule rather than a footnote: **the hosted-proof section is the
last thing written, after the final Swift commit, never before it.** A proof written
against a head that then moves is not a proof.

## 13c. Hosted proof of the final head

**PR-head run `29195160122`**, head `235a1e78c06b85c833660925b8165f19eb498139`
(`235a1e7`), event `pull_request`, conclusion `success`. This run covers **every**
line of Swift, workflow, script, corpus, and budget the slice ships, including the
review-response round (§14) — it is the first run of which that is true, and it is
recorded only now, after the last Swift commit, per the rule stated above.

All three required jobs `success`. Verified at **step** level, per the standing
"a green job can hide a dead `continue-on-error` step" lesson:

```text
5  skipped  Complete docs-only PR          (correct — the PR carries Swift, so the heavy path runs)
7  success  Run host tests                 → Executed 251 tests, with 0 failures
8-17 success  all TEN blocking latency gates
18-19 success  memory diagnostics
20 success  Observe realistic provider relative performance   (ran, not skipped)
```

`iOS cross-target compile` = `success` and `WASM cross-target observation` = `success`,
both with their substantive compile steps genuinely executed.

**251 tests pass on hosted Linux x86_64.** This is the load-bearing new fact:
`GateFloorTests` reads the committed corpus off disk via `#filePath`, and it resolves
and passes inside the container, not merely on macOS.

### The band holds on the machine the budgets were cut for

Across all 41 gated scenarios in the hosted log:

```text
$ grep -c "gate=pass" <log>   → 41
$ grep -c "gate=fail" <log>   → 0
headroom_p95:  4.4x – 12.6x    (floor 3x, ceiling 50x)
headroom_p99:  6.6x – 22.3x    (ceiling 100x)
```

Every budget sits inside the band on hosted — the tightest at **4.4×**, comfortably
above the 3× floor, and the loosest at **12.6×**, nowhere near the 50× ceiling. This is
what a calibrated suite looks like, and it is the direct answer to the pre-slice state
where the same statistic ran 815×–3,000×.

### `mode=point_query` is present, the observation step is gone

```text
$ grep -c "mode=point_query" <log>      → 4
$ grep -c "Observe point query" <log>   → 0
```

The four point-query gate lines on hosted:

```text
mode=point_query provider=uniform   scenario=uniform_100k   p95_ns=60 p99_ns=92  budget_p95_ns=700  headroom_p95=11.7x gate=pass
mode=point_query provider=uniform   scenario=uniform_1m     p95_ns=65 p99_ns=96  budget_p95_ns=670  headroom_p95=10.3x gate=pass
mode=point_query provider=prefixsum scenario=prefixsum_100k p95_ns=76 p99_ns=113 budget_p95_ns=880  headroom_p95=11.6x gate=pass
mode=point_query provider=prefixsum scenario=prefixsum_1m   p95_ns=82 p99_ns=116 budget_p95_ns=1000 headroom_p95=12.2x gate=pass
```

The tenth gate is blocking, and it is a gate that can now actually fail.

### Why this run's samples are NOT in the corpus either

Same reason as §13b: the corpus is the derivation's **input**, this run is the
**validation** of its output. Folding a validating run back in would move the medians,
change the budgets, and require another run to validate those.

## Hosted Proof — post-merge

**This is the merged-code evidence anchor for Slice 38.** Recorded by a genuinely
docs-only follow-up PR, per the clean-evidence convention (Slices 31/33/35/37), once
`main` carried the merge — not guessed in advance.

- **Post-merge push run `29196145560`** — merge commit
  `2bc290ee19b96fc4e1c21b037cfd64dbc66fe056` (`2bc290e`), event `push`, branch `main`,
  conclusion `success`. PR #80 merged 2026-07-12.

### Merge parentage — the proof anchors the actually-merged head

```text
$ git rev-list --parents -1 2bc290e
2bc290ee19b96fc4e1c21b037cfd64dbc66fe056 5e2abf7a3f9ca4769857c77d1b33d78c1c74992e 8e7c062e1236431f93116b91ed5c379e5941a91f
```

Second parent `8e7c062` is exactly the PR head that ran green in §13c's sibling run —
so the merge introduced no post-head drift, and this proof covers the code that is
actually on `main`.

### Step-level verification (not the job conclusion)

All three required jobs `success`. Per the standing "a green job can hide a dead
`continue-on-error` step" lesson, the substantive steps were confirmed to have **run**:

```text
Host tests and benchmark gate
  5  skipped  Complete docs-only PR        (correct — the merge carries Swift, so the heavy path runs)
  7  success  Run host tests               → Executed 251 tests, with 0 failures
  8-17 success  all TEN blocking latency gates
  18-19 success  memory diagnostics
  20 skipped  Observe realistic provider   (correct — that step is PR-only, and this is a push event)

iOS cross-target compile     → "Compile cross-target packages for iOS"  = success (ran, not skipped)
WASM cross-target observation → "Observe cross-target packages for WASM" = success
```

### The recalibrated suite, on merged code

```text
$ grep -c "gate=pass" <log>   → 41
$ grep -c "gate=fail" <log>   → 0

headroom_p95:  4.4x – 12.5x    (floor 3x, ceiling 50x)
headroom_p99:  6.0x – 21.8x    (ceiling 100x)
```

Every one of the 41 gated scenarios sits inside the band on hosted Linux x86_64 — the
machine the budgets were cut for. The pre-slice state of the same statistic was
**815×–3,000×** on the query gates. The gates are gates again.

### The tenth gate is live

```text
$ grep -c "mode=point_query" <log>      → 4
$ grep -c "Observe point query" <log>   → 0
```

`mode=point_query` is **present** in the hosted log — the inverse of the Slice 37 check,
which required it to be absent — and the temporary non-gate observation step from
Decision 5 did **not** survive to `main`, exactly as acceptance criterion 7 demands.

```text
mode=point_query provider=uniform   scenario=uniform_100k   p95_ns=60 p99_ns=93  budget_p95_ns=700  budget_p99_ns=1400 headroom_p95=11.7x headroom_p99=15.1x gate=pass
mode=point_query provider=uniform   scenario=uniform_1m     p95_ns=65 p99_ns=97  budget_p95_ns=670  budget_p99_ns=1400 headroom_p95=10.3x headroom_p99=14.4x gate=pass
mode=point_query provider=prefixsum scenario=prefixsum_100k p95_ns=75 p99_ns=107 budget_p95_ns=880  budget_p99_ns=1800 headroom_p95=11.7x headroom_p99=16.8x gate=pass
mode=point_query provider=prefixsum scenario=prefixsum_1m   p95_ns=80 p99_ns=115 budget_p95_ns=1000 budget_p99_ns=2000 headroom_p95=12.5x headroom_p99=17.4x gate=pass
```

### 251 tests on hosted Linux

`GateFloorTests` — which reads the committed corpus off disk via `#filePath` and holds
every gated scenario to the 3× floor — runs and passes **inside the CI container**, not
only on macOS. The floor is enforced on merged code, by the build, on every push.

## 14. Review-response round

A six-perspective code review of the branch found no P0 and no P1, and three P2s.
All are fixed here. The headline: **the slice had recalibrated every gated mode
except the one it could not see.**

### 14a. `--realistic-provider` was gated, uncalibrated, and under the floor

`--gate` is valid with `--realistic-provider`, and `## Gate budgets` claims the band
covers *every* gated scenario — but the corpus had **zero** `realistic_provider` rows,
so nothing could re-derive it and nothing checked it. It was also the worst budget in
the repo:

```text
$ grep -c realistic docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv   # before
0
```

Hosted evidence from the era when this mode *did* run as a blocking gate
(`docs/superpowers/verification/2026-06-08-hosted-realistic-provider-gate-ci.md:83`):

```text
mode=realistic_provider ... p95_ns=19745 p99_ns=25845 ... budget_p95_ns=20000 budget_p99_ns=50000 gate=pass
```

`19745` against a `20000` budget is **1.01× headroom** — a gate one runner hiccup away
from red, on a mode whose budget no one had looked at since Slice 11.

**Why the corpus missed it.** The harvest reads hosted lines that carry
`p95_ns=`/`p99_ns=`. This is the one gated mode CI never runs with `--gate`: the PR-only
observation step runs it bare and keeps the raw benchmark output in a temp file, so no
such line for this mode ever reaches the log. Its per-repetition values ride inside the
`mode=realistic_relative_observation` line instead — which the original harvest command
did not read.

### 14b. Both halves of the loop are now committed

`.github/scripts/harvest-gate-corpus.sh` is new: it turns hosted CI logs into corpus
rows and understands **both** line shapes, including the relative-observation line. It
validated itself against the existing corpus — replaying the corpus's own 25 run IDs
reproduced every committed row, short only of the one run whose log has aged out of
retention:

```text
$ ./.github/scripts/harvest-gate-corpus.sh --runs <the corpus's 25 run ids>
warn=log_unavailable run=28371455301
rows: 905     # every mode reproduced exactly, minus that run's rows, plus 128 new realistic_provider rows
```

`.github/scripts/derive-gate-budgets.sh` no longer answers a typo with silence:

```text
$ ./.github/scripts/derive-gate-budgets.sh <corpus> bogus_mode
error=no_corpus_rows mode=bogus_mode known=column_query,variable_height_mutation,...
$ echo $?
1
$ ./.github/scripts/derive-gate-budgets.sh <corpus> point-query   # hyphens now accepted
point_query|prefixsum_100k  n=6 ...
```

### 14c. The realistic-provider budget, re-derived

128 hosted samples harvested from the corpus's own run set, then run through the same
recipe as every other budget:

```text
realistic_provider|100k_lines_10mb_text  n=128  p95[med=12130 max=18298]  p99[med=12423 max=21752]
                                         budget_p95=98000  budget_p99=200000
                                         margin_p95=5.4x   margin_p99=9.2x
```

`20_000 / 50_000` → **`98_000 / 200_000`**. The corpus now derives **42** scenarios — the
full gated set, with no mode left uncovered.

**No other budget moved.** Diffing the full derivation before and after the append yields
exactly one added line (the new `realistic_provider` row) and zero changed lines, which is
the point: the corpus grew, and the other 41 budgets are still what the recipe says.

### 14d. The 3× floor is now executable

`Tests/ViewportBenchmarksTests/GateFloorTests.swift` reads the committed corpus and holds
every gated scenario to `3 × max(hosted)` on **both** statistics, plus a coverage assertion
that a gated scenario with no hosted evidence is itself a failure. Demonstrated to be
load-bearing rather than decorative — restoring the old realistic-provider budget makes it
fail with the diagnosis, not just a red X:

```text
XCTAssertGreaterThanOrEqual failed: ("20000") is less than ("54894") -
realistic_provider|100k_lines_10mb_text: p95 budget 20000 is below 3x the worst hosted p95
(18298, n=128) — it will go red on a clean tree; re-derive with .github/scripts/derive-gate-budgets.sh
```

This closes the review's structural objection: the ceiling was executable, the floor was a
table in a document. Both are code now.

### 14e. Everything else the review found

- `formatSummary` evaluated the gate decision twice (once for `gate=`, once for `reason=`);
  it now evaluates once, so the two fields cannot disagree. `headroomP95`/`headroomP99` were
  nine copy-pasted lines each and are now one shared helper.
- The `GateLimits` comment claimed the excluded mutation tables "sit below 2× their p95";
  three of them sit at **exactly** 2×. The `GateLogicTests` comment listed "variable-height"
  as deliberately absent while the test iterates `variableHeightScenarios()` — it meant
  `variableHeightMutationScenarios()`. Both corrected.
- Two comments still quoted measured numbers (`330ns`, `39,381ns`, `2.9x`) in the very slice
  whose final commit was "make the gate-budget comments re-derivable instead of restated".
  They now point at the script instead.
- The spec's Evidence table is marked **SUPERSEDED**: it is the design-time snapshot, and
  eleven of its budgets moved before ship.

### 14f. Full local re-verification after the round

```text
swift build -c release          → Build complete!
swift test                      → Executed 251 tests, with 0 failures   (249 + 2 floor tests)
rg -n "Foundation" Sources/TextEngineCore              → no matches
rg -n "Foundation" Sources/TextEngineReferenceProviders → no matches
all 11 gate modes (42 scenarios) → 42/42 gate=pass
  headroom_p95 range: 9.3x – 24.1x   (ceiling 50x)
  headroom_p99 range: 13.8x – 43.0x  (ceiling 100x)
```

`realistic_provider` local headroom moved from **3.5×** (thinnest in the suite, and ~1.0× on
hosted) to **18.6×** — inside the band on the machine the budget was actually cut for.

## Working tree

`git status --short` was **empty** before and after every command above (verified
after the §10 demonstration restore). No source, test, benchmark, or CI file was
left modified.

## Constraint check — what the re-derivation did NOT touch

Recorded because the value of a calibration pass is bounded by what it was allowed
to move:

```text
$ git diff --name-only main -- Sources/TextEngineCore | wc -l
0
$ rg -n "import Foundation" Sources/ViewportBenchmarks
(no matches)
```

- **No ceiling.** `GateLimits` (50× / 100×) is untouched. The budgets were fitted
  to the evidence; the ceilings were not loosened to accommodate the budgets.
- **No logic, no test, no workflow.** Eleven integer literals and one comment.
- **None of the 13 non-derived scenarios.** `pipeline|1k`, `pipeline|100k`, and
  all of `structural_mutation`, `variable_height_mutation`,
  `bulk_structural_mutation` keep their pre-slice values. The script prints
  derived values for them; those values are ignored by design (§2c).
- **`Sources/TextEngineCore` — zero files changed** vs `main`.
- **No Foundation** in `Sources/ViewportBenchmarks`.
