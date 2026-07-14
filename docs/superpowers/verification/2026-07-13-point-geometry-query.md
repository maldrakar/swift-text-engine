# Slice 39 — `pointGeometryAt` — Verification Record

Branch: `slice-39-point-geometry-query` · PR: [#84](https://github.com/maldrakar/swift-text-engine/pull/84)
Plan: `docs/superpowers/plans/2026-07-13-point-geometry-query.md`
Spec: `docs/superpowers/specs/2026-07-13-point-geometry-query-design.md`

> **Status: COMPLETE except for the post-merge `push` run.** This file was committed early on
> purpose and filled incrementally: budgets here may only be **derived** from hosted Linux CI
> samples of this PR's own runs, and each push to the PR minted one such run, so the record was
> both the evidence trail and the vehicle that produced the evidence. Every section is now filled
> from real commands and real hosted runs. The one remaining *pending* item is §9's post-merge
> `push` run id, which cannot exist before the user merges PR #84.

---

## 1. Pre-registered prediction (recorded BEFORE the evidence was complete)

The design's Decision 6 predicts that each `point_geometry_query` scenario's median p95 will sit
**above** its `point_query` counterpart (it does strictly more work — four extra constant probes)
and **within roughly 30 %** of it (it adds no search and no new arithmetic, so it must not cost a
different *class*). A prediction that is only reported when it succeeds is not a prediction, so it
is written down here, ahead of the full six-run harvest, and §7 reports the outcome either way.

Baseline — today's committed `point_query` medians (n=6), from
`./.github/scripts/derive-gate-budgets.sh <corpus> point-query`:

| scenario | `point_query` med p95 | predicted `point_geometry_query` med p95 band (+0 %…+30 %) |
|---|---|---|
| uniform_100k | 87 | 87 – 113 |
| uniform_1m | 83 | 83 – 108 |
| prefixsum_100k | 110 | 110 – 143 |
| prefixsum_1m | 124 | 124 – 161 |

**Falsification rule, fixed in advance:** a scenario landing far outside the band (say 2×) is a
*code* finding — a lost specialization, a re-probe, an allocation — and must be investigated, not
budgeted around.

First hosted data point (run `29279467574`, n=1, single sample vs. a 6-run median, so indicative
only — the real test is §7 at n≥6):

| scenario | p95_ns | p99_ns | vs. `point_query` med p95 |
|---|---|---|---|
| uniform_100k | 118 | 153 | +36 % |
| uniform_1m | 109 | 133 | +31 % |
| prefixsum_100k | 145 | 176 | +32 % |
| prefixsum_1m | 159 | 218 | +28 % |

Sitting at the band's edge, not beyond it, and nowhere near 2×.

---

## 2. Cross-target compile — `./.github/scripts/cross-target-compile.sh`

Run locally on macOS (arm64), 2026-07-13. Exit code **0**. A matching WASM Swift SDK was
installed, so the observational targets compiled rather than recording a skip.

```
mode=cross_target_compile_summary package=core      ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=pass wasm_embedded=pass
```

All eight compiles pass: iOS device + iOS simulator (**blocking**) and WASM + embedded WASM
(observational), for both `TextEngineCore` and `TextEngineReferenceProviders`. The new core file
`Sources/TextEngineCore/PointGeometryQuery.swift` therefore survives Embedded Swift with no source
changes, as the hard constraint requires.

---

## 3. Hosted run ledger

Budgets are derived from these runs and no others. The harvest dedup key is the **run id**, so a
workflow *re-run* contributes nothing — six runs means six distinct pushes.

| # | run id | head | note |
|---|---|---|---|
| 1 | `29279467574` | `dbb6538` | Task 4: the observational CI step's first run. Four `mode=point_geometry_query` lines confirmed at step level. |
| 2 | `29280327104` | `56cfb49` | Verification-record skeleton + pre-registered prediction. Green. |
| 3 | `29282508259` | `2994781` | §4 local evidence. Green. |
| 4 | `29284799129` | `b1cf819` | §8 absolute check + spread warning. Green. |
| 5 | `29285302031` | `b783208` | §5 full gate sweep (41/41). Green. |
| 6 | `29285933609` | `cc2ef2b` | §5b checksum stability. Green. Completes the six-run harvest base (Task 5). |

---

## 4. Local test suite, release build, Foundation scan

```
$ swift test
	 Executed 274 tests, with 0 failures (0 unexpected) in 2.311 (2.323) seconds
```

274 XCTest tests, **0 failures**. (`swift test` also prints a "0 tests in 0 suites" line for the
empty Swift Testing harness — the documented harmless artifact, not a failure.) The count rose
267 → 271 → 274 across Tasks 1–3: 16 hardcoded-expectation tests, the parity oracles and the
probe-count pin, and the three benchmark-options tests.

```
$ swift build -c release
Build complete!
```

```
$ rg -n "Foundation" Sources/TextEngineCore
$ echo $?
1
```

Empty — exit 1, no matches. The core stays **Foundation-free**, as the hard constraint requires.
The new core file `Sources/TextEngineCore/PointGeometryQuery.swift` imports nothing at all: it is a
pure `extension ViewportVirtualizer`, stdlib-only.

## 5. The full gate sweep — nothing this slice added moved anything that already existed

Local macOS (arm64), release build, at this branch's head. Every pre-existing gated mode, run with
`--gate`:

```
--gate                                 exit=0 gate=pass:3 gate=fail:0
--variable-height --gate               exit=0 gate=pass:3 gate=fail:0
--variable-height-mutation --gate      exit=0 gate=pass:3 gate=fail:0
--structural-mutation --gate           exit=0 gate=pass:3 gate=fail:0
--bulk-structural-mutation --gate      exit=0 gate=pass:5 gate=fail:0
--line-query --gate                    exit=0 gate=pass:5 gate=fail:0
--line-geometry-query --gate           exit=0 gate=pass:5 gate=fail:0
--column-query --gate                  exit=0 gate=pass:5 gate=fail:0
--column-geometry-query --gate         exit=0 gate=pass:5 gate=fail:0
--point-query --gate                   exit=0 gate=pass:4 gate=fail:0
```

3+3+3+3+5+5+5+5+5+4 = **41 gated scenarios, 41 `gate=pass`, 0 `gate=fail`**, every mode exiting 0.
41 is the correct total **for this specific sweep** — the scenarios reachable by running each of
the ten `--gate`-capable CLI modes directly, which is what this section exercises. The slice is
strictly additive to that surface: it adds an eleventh mode, and moves nothing in the other ten.

> **Correction (added after §6/§9, superseding the framing above).** 41 is *not* the total number
> of gated budgets in the repo, and this record should not be read as implying it is. `GateFloorTests`
> holds **42** pre-existing budgets to the 3× floor, not 41: it carries a twelfth pre-existing
> loop over `realistic_provider`'s single scenario, which CI's PR-only observation step runs
> **without** `--gate` (so it never appears in a `--gate` CLI sweep like the one above) but which
> `GateFloorTests` still checks directly against its committed budget. Task 6 found this by direct
> count against `GateFloorTests.everyGatedBudget()`'s loop structure, three independent ways — see
> the new "Scope change" section below. So: **41** = scenarios reachable from the ten CI `--gate`
> modes (this section's number, still correct for what it measures); **42** = every pre-existing
> gated budget including `realistic_provider` (`GateFloorTests`' true pre-slice count); **46** =
> 42 + this slice's 4 new `point_geometry_query` budgets, the true total after this slice.

The eleventh mode, `--point-geometry-query`, is **not** in this list because it is not gateable yet
— `--gate` is refused for it until §6 derives its budgets. Bare, it runs clean:

```
mode=point_geometry_query provider=uniform   scenario=uniform_100k   ... p95_ns=47 p99_ns=52 failures=0 checksum=4687694617200924928
mode=point_geometry_query provider=uniform   scenario=uniform_1m     ... p95_ns=36 p99_ns=37 failures=0 checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k ... p95_ns=53 p99_ns=59 failures=0 checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m   ... p95_ns=61 p99_ns=64 failures=0 checksum=5915921755926273280
```

`failures=0` on all four. Note these are **local** numbers; hosted Linux runs materially slower and
is the calibration authority (§6).

> **Tooling trap, recorded so the next agent does not lose an hour to it.** The plan's Task 6 Step 5
> sweeps the gates with `for m in "--variable-height --gate" ...; do swift run ... -- $m; done`.
> This repo's shell is **zsh**, which — unlike bash — does **not** word-split an unquoted parameter
> expansion. `$m` is passed as one literal argument, the binary rejects it as an unknown flag, and
> the command exits 1 with *no output at all*. The sweep then reports nine of ten gates as
> `exit=1 gate=pass:0`, which is indistinguishable from a catastrophic regression. It is not one.
> Use a function taking `"$@"`, or an array. And when a sweep says "everything broke", reproduce a
> single case directly before believing it.

## 5b. Checksum stability across architectures — the "workload unchanged" anchor, tested

This mode's checksum deliberately folds the **geometry** — both boxes, both fractions — not just the
indices, by reinterpreting each `Double`'s raw IEEE-754 bit pattern and mixing it with a distinct
odd multiplier per field. That design carries two claims worth testing rather than asserting:

1. **A drifted fraction or a swapped axis must change it.** Distinct odd multipliers per field
   (19 / 3 / 5 / 7 for the line, 23 / 11 / 13 / 17 for the cell) mean a purely additive
   cross-field transposition does not cancel — this closes the weakness the Slice 37 review
   recorded as its P3 #5, where an axis swap was invisible to an additive fold.
2. **It must be reproducible across runs and platforms**, or it is useless as an anchor. The
   argument is that Swift does not enable fast-math and `+ - * /` are exactly-rounded under
   IEEE-754, so the bit patterns are stable.

Claim 2 is the falsifiable one, and it holds. Hosted **Linux x86_64** (run `29279467574`) versus
local **macOS arm64** — two different architectures, two different toolchain hosts:

| scenario | hosted Linux x86_64 | local macOS arm64 | |
|---|---|---|---|
| uniform_100k | 4687694617200924928 | 4687694617200924928 | identical |
| uniform_1m | 6036755761047907072 | 6036755761047907072 | identical |
| prefixsum_100k | 1712152282485110528 | 1712152282485110528 | identical |
| prefixsum_1m | 5915921755926273280 | 5915921755926273280 | identical |

**Bit-identical on all four**, across architectures, while the *latencies* on the same runs differ
by 2–3×. That is exactly the separation the anchor needs: the checksum tracks the computed geometry
and is blind to timing, so a future slice can use "checksums unchanged" as genuine evidence that the
measured workload did not move — including the boxes and fractions, which the sibling
`--line-geometry-query` / `--column-geometry-query` folds do not cover at all.

## 6. Harvest + derivation (corpus diff, verbatim `derive-gate-budgets.sh` output)

`./.github/scripts/harvest-gate-corpus.sh --limit 40 --corpus <corpus> --dry-run` against the six
runs listed in §3 confirmed all six `completed`/`success` and planned 24 harvestable runs total
(`--limit 40` scans the 40 most recent hosted `swift-ci.yml` runs **repo-wide**; the corpus's last
harvest predates this slice's own earlier task pushes, so 24 runs — including all six carrying
`point_geometry_query` — planned as new and 13 as already-harvested). Full appended-and-committed
harvest landed in commit `a23e559`.

**Corpus diff**: 928 lines (927 data rows + header) before → 1692 lines after. **+764 insertions,
-0 deletions** (`git diff --cached --stat` on the commit: `764 insertions(+), 1 file changed`).

```
$ grep -c "point_geometry_query" docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
24
```

24 `point_geometry_query` rows = 6 runs × 4 scenarios, confirming the six-run base. No
`plan=`/`skip=` harvester chatter leaked into the file (that goes to stderr) and every row still
carries exactly 5 tab-separated fields.

**Byte-prefix proof** that the harvest only appended — old content is an exact prefix of the new
file, no reordering:

```
$ BEFORE_BYTES=$(wc -c < corpus-before.tsv)   # 56281
$ cmp <(head -c "$BEFORE_BYTES" docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv) corpus-before.tsv
$ echo $?
0
```

`cmp` exits 0 with no output: the first 56,281 bytes of the post-harvest file are byte-identical to
the saved pre-harvest copy. No `sort` of any kind was ever run over the corpus — `sort -u` would
have been wrong here regardless, since the corpus's dedup key is the run id and two genuinely
distinct runs can produce byte-identical rows (see AGENTS.md's `## Gate budgets`).

**Verbatim `derive-gate-budgets.sh` output for `point-geometry-query`** — regenerated directly by
this task, against the committed corpus at this branch's head, to confirm it still reproduces
byte-for-byte what Tasks 5/6 recorded:

```
$ ./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv point-geometry-query
point_geometry_query|prefixsum_100k            n=6   p95[med=91     max=231   ] p99[med=141    max=252   ] budget_p95=730     budget_p99=1500    margin_p95=3.2x margin_p99=6.0x
point_geometry_query|prefixsum_1m              n=6   p95[med=97     max=167   ] p99[med=143    max=218   ] budget_p95=780     budget_p99=1600    margin_p95=4.7x margin_p99=7.3x
point_geometry_query|uniform_100k              n=6   p95[med=80     max=118   ] p99[med=117    max=156   ] budget_p95=640     budget_p99=1300    margin_p95=5.4x margin_p99=8.3x
point_geometry_query|uniform_1m                n=6   p95[med=92     max=126   ] p99[med=132    max=158   ] budget_p95=740     budget_p99=1500    margin_p95=5.9x margin_p99=9.5x
```

These are the four budgets committed in `a23e559` and confirmed live in the hosted PR-head run
(§9). `n=6` — exactly the six-run harvest base, no more, no fewer.

## 6b. Scope change — the harvest re-derived nineteen pre-existing budgets, not just this slice's four

This is the slice's most consequential finding and it must not be read as a footnote to §6.

`harvest-gate-corpus.sh --limit 40` pulls **every** mode's samples out of every unharvested run in
its window — it has no way to harvest only `point_geometry_query` rows out of a run that also
carries `point_query`, `line_query`, etc. rows. So the six-run harvest that produced this slice's
four new budgets (§6) simultaneously enriched the corpus for **every other gated mode** with
whatever samples those same six runs (plus earlier still-unharvested ones swept in by the same
`--limit 40` window) happened to carry for them. Re-running the derivation recipe against the
enlarged corpus therefore moved budgets well outside this slice's own surface.

**Consequence 1 — most pre-existing budgets no longer reproduced from the corpus.** Task 6 ran the
derive recipe against every mode and diffed the result against every committed budget:

- **19 of the 42 pre-existing** gated budgets no longer matched what the corpus now derives, and
  were re-derived to the values the recipe now produces (`pipeline`×2, `realistic_provider`×1,
  `variable_height_mutation`×3, `structural_mutation`×3, `bulk_structural_mutation`×5, `line_query`×1,
  `column_query`×2, `point_query`×2 — full committed→derived table in the Task 6 report). Plus this
  slice's **4 new** `point_geometry_query` budgets. **23 tables edited in total**, all in commit
  `a23e559`; the other **23 pre-existing** budgets reproduced byte-identical and were left untouched.
- The pre-existing per-scenario table already in §5's gate sweep and this record's older sections is
  unaffected in spirit — those runs still all pass — but the specific budget *numbers* behind ten of
  those ten modes are, in places, no longer what they were when Tasks 1–5 of this slice began.

**Consequence 2 — the harvest revealed two pre-existing gates were already below the 3× floor**, i.e.
already capable of flaking red on a clean tree from runner noise alone, independent of anything this
slice added:

- `line_query|uniform_1k`: committed p95 budget was 190, but the floor requires ≥ 3×max(hosted p95) =
  219. Re-derived to 220.
- `column_query|uniform_100k`: committed p99 budget was 560, but the floor requires ≥ 3×max(hosted
  p99) = 612. Re-derived to 620.

`GateFloorTests` (the test that re-reads the corpus on every `swift test` and asserts every gated
budget clears `3×max(hosted)` on both statistics, per AGENTS.md's `## Gate budgets`) caught both.
This is exactly the class of defect that test exists to catch — the half of the band the *runtime*
`--gate` check structurally cannot see, because `--gate` only compares a budget against its own run's
latency, not against the worst hosted sample on record. **The underlying evidence was always true**
(both scenarios' hosted samples already existed before this slice); the harvest did not create the
gap, it only pulled in the samples that expose it.

**Consequence 3 — the resolution chosen was re-derive-all, not cherry-pick.** The alternative —
apply only the 4 new `point_geometry_query` budgets and leave the other 19 as before — was rejected
because it would leave 16 pre-existing budgets (the 19 minus the 2 floor failures, which had to move
regardless) silently **not reproducing** from the committed corpus: running the recipe against
`main` would print different numbers than what's committed, breaking the repo's "derived, do not
hand-edit" invariant for those 16 tables indefinitely, until some unrelated future slice happened to
re-touch them. Re-deriving all 19 (+4 new = 23) keeps the invariant true for every gated budget in
the repo, not just this slice's own four.

**Consequence 4 — corpus and every moved budget landed in one commit.** `a23e559` contains the
764-row corpus append **and** all 23 edited budget tables **and** the `--gate` rejection lift for the
new mode **and** the test-suite changes needed to keep the invariant checks passing — together, so
that the "derived, do not hand-edit" invariant holds at **every** commit in history, not just the
final one. No commit with a red `GateFloorTests` or a corpus that disagrees with its own committed
budgets ever entered the branch.

**Consequence 5 — the re-derivation itself created two comment-rot defects, caught in review and
fixed.** PR #84 review flagged that moving 19 budgets off their old values silently falsified two
comments that predated the derivation recipe:

1. A comment in `GateLogicTests.swift` had explicitly excluded `structuralMutationScenarios()`,
   `variableHeightMutationScenarios()`, and `bulkStructuralMutationScenarios()` from the
   `p99 >= 2×p95` invariant test, on the stated grounds that their budgets "predate the recipe" and
   sit outside its guarantee. After this slice's re-derivation, that claim is false — all three
   tables are now fully recipe-derived — and the exclusion was **silently suppressing test coverage**
   for 11 scenarios that the invariant now genuinely applies to and that a future bad re-derivation
   could violate undetected.
2. A comment in `PointQueryBenchmark.swift` claimed `point_query` "rests on the thinnest corpus base
   of any gated mode" — true when written, stale the moment a newer mode (`point_geometry_query`,
   n=6) landed with thinner evidence than `point_query`'s now n=21.

Both fixed in `3673a43` (comments + the three added `for` loops in `GateLogicTests.swift`; no budget
value or corpus row touched — confirmed via `git diff HEAD~1 -- 'Sources/ViewportBenchmarks/*.swift'`
and `git diff HEAD~1 -- docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`, both empty
of numeric changes).

That fix left a gap of its own: the widened `p99 >= 2×p95` invariant loop covered all eleven
*pre-existing* recipe-derived scenario tables but omitted **this slice's own new twelfth table**,
`pointGeometryQueryScenarios()` — despite it being gated with derived budgets from the exact same
corpus and recipe as all the others. Closed in `a5ff213` (adds the twelfth loop, unwrapping the
`Optional` budgets the same way `GateFloorTests.swift` already does for this table). Verified inline:

```
uniform_100k:    1300 >= 2×640 (1280) ✓
uniform_1m:      1500 >= 2×740 (1480) ✓
prefixsum_100k:  1500 >= 2×730 (1460) ✓
prefixsum_1m:    1600 >= 2×780 (1560) ✓
```

`point_geometry_query` is now covered by **both** guard tests: `GateFloorTests` (3× floor, both
statistics) and `GateLogicTests` (`p99 >= 2×p95`) — the same double coverage every other gated mode
in the repo has.

**Net effect on the record's own numbers.** §5's "41 gated scenarios" is still correct for what it
literally measured (the ten CI `--gate` modes' CLI sweep) — see the correction inserted there — but
must not be read as "the total number of gated budgets in the repo." That total is **46** (42
pre-existing, including `realistic_provider` which CI never runs with `--gate`, + this slice's 4
new), not 45 and not 41+4.

## 7. Spread table + the Decision 6 prediction outcome

### Spread table — `max/median`, and which term governs

`budget_p95 = round_up_2sf(max(8 × median, 3 × max))`; the median term governs while `max ≤ 2.667 ×
median`, otherwise the `3 × max` floor takes over. `budget_p99 = round_up_2sf(max(2 × budget_p95,
8 × median(p99), 3 × max(p99)))` — the p99 recipe has a third candidate term not present in the p95
formula.

| scenario | p95 max/med | 8×med | 3×max | **p95 governs** | p99 max/med | 2×budget_p95 | **p99 governs** |
|---|---|---|---|---|---|---|---|
| prefixsum_100k | **2.538** | 728 | 693 | median (barely — 5% margin) | 1.787 | 1460 | derived (2×budget_p95) |
| prefixsum_1m | 1.722 | 776 | 501 | median (comfortable) | 1.524 | 1560 | derived (2×budget_p95) |
| uniform_100k | 1.475 | 640 | 354 | median (comfortable) | 1.333 | 1280 | derived (2×budget_p95) |
| uniform_1m | 1.370 | 736 | 378 | median (comfortable) | 1.197 | 1480 | derived (2×budget_p95) |

**No scenario in this slice is floor-governed** (`3×max`) on either statistic — all four p95
budgets are set by the median term, and all four p99 budgets are set by the derived `2×budget_p95`
term (itself built from an all-median-governed p95), not by their own p99 median or max.

**`prefixsum_100k` p95 is a near-miss worth naming explicitly.** Its `max/median` ratio is **2.538**
— only ~5% below the 2.667 threshold at which the `3×max` floor would take over (728 vs 693, a gap
of 35 ns of "8×median" headroom). This is the scenario the pre-harvest §8 spread warning called out
in advance: hosted p95 samples of 145 / 231 / 90 across runs 1–3 (raw corpus rows: run `29279467574`
→145, `29280327104`→231, `29282508259`→90). The 231 sample (run `29280327104`) is a genuine outlier
candidate — later runs settled to 70–96. Not floor-governed *today*, but fragile: if one more future
run pushes this scenario's max higher while its median holds still, the budget flips from
median-governed to floor-governed — and under an append-only corpus with a `3×max` floor, that
freezes a single outlier sample into the budget permanently (Slice 38 review, P2 #2, still open,
tracked for Slice 40).

### The Decision 6 prediction — reported both ways, honestly

§1 pre-registered, before the full harvest: each scenario's `point_geometry_query` median p95 sits
**above** its `point_query` counterpart and **within roughly 30%** of it, with a fixed falsification
rule (≈2× would be a code finding, not a budgeting matter).

**View 1 — naive pooled comparison** (this slice's `point_geometry_query` median, n=6, vs. the
harvest's freshly re-derived `point_query` median, n=21 — see §6's sibling derive output above,
i.e. `./.github/scripts/derive-gate-budgets.sh <corpus> point-query`):

| scenario | geom med p95 (n=6) | query med p95 (n=21) | ratio | vs. prediction |
|---|---|---|---|---|
| uniform_100k | 80 | 87 | 0.920 | **below** — contradicts "above" |
| uniform_1m | 92 | 81 | 1.136 | above, within 30% — holds |
| prefixsum_100k | 91 | 112 | 0.813 | **below** — contradicts "above" |
| prefixsum_1m | 97 | 124 | 0.782 | **below** — contradicts "above" |

Taken at face value, **3 of 4 scenarios contradict** the "above" half of the prediction under this
comparison. That would be a genuine, if mild, finding — except this comparison is unsound, and here
is why.

**Why View 1 is unsound.** `point_query`'s n=21 pool includes 15 runs that predate this branch's
`point_geometry_query` work entirely and have **no paired `point_geometry_query` sample** — they
measure a completely different, non-overlapping set of hosted CI jobs. Hosted-runner speed is a
**system-wide per-run state**: a "fast" runner measures every mode in that job faster, a "slow" one
measures every mode slower (§5/§8 already document a ~2× run-to-run swing on this exact machine
population). Pooling medians across two differently-composed run sets can flip a ratio's sign even
when the underlying code relationship between the two modes is perfectly stable — it is comparing
"whatever 21 mostly-different jobs happened to run at" against "these particular 6 jobs," not
`point_geometry_query` against `point_query` under matched conditions.

**View 2 — same-run paired comparison** (both modes measured in the *same* CI job, so runner speed
cancels out). Independently recomputed here, directly from the corpus rows for the six harvested
runs (not merely copied from Task 5's report):

| scenario | run-by-run p95 ratios (geom/query), runs in §3 order | median paired ratio | vs. prediction |
|---|---|---|---|---|
| uniform_100k | 118/84, 113/86, 80/60, 63/46, 80/60, 117/91 → 1.405, 1.314, 1.333, 1.370, 1.333, 1.286 | **1.333** (+33.3%) | above, at band edge — holds |
| uniform_1m | 109/100, 109/91, 86/65, 67/51, 92/65, 126/79 → 1.090, 1.198, 1.323, 1.314, 1.415, 1.595 | **1.318** (+31.8%) | above, at band edge — holds |
| prefixsum_100k | 145/115, 231/113, 90/74, 70/56, 91/112, 225/124 → 1.261, 2.044, 1.216, 1.250, 0.812, 1.815 | **1.255** (+25.5%) | above, within 30% — holds |
| prefixsum_1m | 159/129, 156/128, 96/79, 75/61, 97/77, 167/130 → 1.233, 1.219, 1.215, 1.230, 1.260, 1.285 | **1.231** (+23.1%) | above, within 30% — holds |

(Arithmetic verified independently by this task directly against the corpus's raw `p95_ns` columns
for both modes across all six run ids — not transcribed from Task 5's report — and matches it
exactly.)

Under the paired comparison, **all four scenarios hold**: `point_geometry_query` is consistently
**~23–33% slower** than `point_query` on the same run, matching the predicted direction and sitting
at or inside the ~30% band (two scenarios land right at the edge, ~32–33%, consistent with §1's own
first-hosted-sample readings of +28%..+36%). The one individual outlier pair is `prefixsum_100k` on
run `29280327104` (2.044×, driven by that run's already-flagged 231 ns outlier sample) and run
`29285302031` (0.812×, inverted) — both wash out to 1.255 at the median, and every other run/scenario
pair sits in the tight 1.2–1.4 range. **Nothing in either view approaches the pre-registered 2× "stop
and investigate" threshold** — the widest single-run ratio anywhere is 2.044×, and only because of
one already-identified outlier sample, not a systematic pattern.

**Conclusion: the prediction holds**, under the methodologically sound same-run (paired) test. The
naive pooled comparison disagreeing on 3 of 4 scenarios is a **small-n sampling-composition
artifact** — n=6 vs. n=21 drawn from largely disjoint run sets, under hosted-runner timing that
varies by run as a whole — not a code finding. A future reader must not take View 1 at face value in
isolation; it is reported here specifically so it cannot be quietly rediscovered and mistaken for a
regression. View 2 is the test that actually answers the prediction's question.

## 8. The absolute check — observed hosted p99 vs. the 1 µs product line

An **observation, not a gate**. The project brief's ambition ("turn 60 FPS into a measurable
headless budget") implies an absolute per-query ceiling, which this repo records nowhere else. A
single hit-test at 60 FPS has ~16.6 ms of frame; a **1 µs** ceiling for one point query is three
orders of magnitude inside that, and is the round number used here as the product line.

Every hosted `point_geometry_query` p99 observed so far, across runs 1–3 (ns):

| scenario | run 1 | run 2 | run 3 | worst | vs. 1 µs |
|---|---|---|---|---|---|
| uniform_100k | 153 | 142 | 117 | 153 | **6.5× inside** |
| uniform_1m | 133 | 132 | 120 | 133 | **7.5× inside** |
| prefixsum_100k | 176 | 243 | 122 | 243 | **4.1× inside** |
| prefixsum_1m | 218 | 184 | 129 | 218 | **4.6× inside** |

The geometry-bearing 2D hit-test clears the 1 µs product line by 4–7× on the *slowest* hosted
sample of the *slowest* provider, on a million-line document. That is the number a UI integrator
actually cares about, and it is comfortable.

**These two thresholds are different objects and must not be conflated.** The 1 µs line is an
*absolute product* ceiling. The gate budgets derived in §6 are *regression* budgets — deliberately
loose multiples of observed latency (`max(8 × median, 3 × max)`), whose job is to catch a code
change that makes things slower, not to assert a product requirement. They already exceed 1 µs on
p99 for `point_query` today. A future absolute-budget slice must **reconcile** them, not assume
they agree: a scenario can pass every regression gate while breaching an absolute ceiling, and vice
versa.

### Run-to-run spread — an early warning, before the harvest

Hosted runners vary a lot, and the variance is not noise to be averaged away silently — under an
**append-only** corpus with a `3 × max` floor, one slow sample is frozen into the budget forever
(Slice 38 review, P2 #2, still open). Recorded here while it is still visible:

- Run 3 came in uniformly **fast** (p95 80–96) versus runs 1–2 (p95 109–231). Same code, same
  commit-adjacent tree — this is runner-to-runner variance, roughly a 2× swing.
- `prefixsum_100k` shows the widest spread so far: p95 of **145 / 231 / 90**. The 231 is a genuine
  outlier candidate.

§7 reports, per scenario, whether the median term (`8 × median`) or the `3 × max` floor set the
final budget — because a floor-governed budget is a budget set by one sample, and this record is
the only place that fact is visible before the corpus freezes it.

## 9. Hosted PR-head run, and the post-merge `push` run

The six harvested runs that produced this slice's budgets are listed in §3. This section adds the
run that **exercises those derived budgets under `--gate`** for the first time on hosted Linux —
the previous six ran the mode observationally (bare, no `--gate`), since the budgets didn't exist
yet.

### PR-head run: `29311125509` (head `a5ff213`)

The first hosted run of `--point-geometry-query --gate` — the CI step added in `b378554`, running
under `continue-on-error: true` per the design's "observational until Slice 40 promotes it to
blocking" plan. Read at **step level**, not job conclusion — a `continue-on-error` step can fail
silently while its job still shows green (the Slice 16 lesson, called out in AGENTS.md's memory
notes). Step-level log for `Point-geometry query benchmark gate (observational until Slice 40)`:

```
mode=point_geometry_query provider=uniform   scenario=uniform_100k   ... p95_ns=109 p99_ns=147 failures=0 budget_p95_ns=640 budget_p99_ns=1300 headroom_p95=5.9x headroom_p99=8.8x gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform   scenario=uniform_1m     ... p95_ns=107 p99_ns=133 failures=0 budget_p95_ns=740 budget_p99_ns=1500 headroom_p95=6.9x headroom_p99=11.3x gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k ... p95_ns=146 p99_ns=180 failures=0 budget_p95_ns=730 budget_p99_ns=1500 headroom_p95=5.0x headroom_p99=8.3x gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m   ... p95_ns=235 p99_ns=254 failures=0 budget_p95_ns=780 budget_p99_ns=1600 headroom_p95=3.3x headroom_p99=6.3x gate=pass checksum=5915921755926273280
```

All four `gate=pass`. Checksums match §5b's cross-architecture proof exactly (all four
bit-identical to the hosted-Linux and local-macOS values already recorded there).

**Whole-run tally**, across every gated mode in the job (`gh run view 29311125509 --log | grep -oE
"gate=pass|gate=fail" | sort | uniq -c`):

```
45 gate=pass
```

**45, 0 fail** — matching the "46 total gated budgets" figure from §6b minus `realistic_provider`,
whose PR-only observation step runs bare (never under `--gate`, per AGENTS.md), so it never emits a
`gate=` line at all; 46 − 1 = 45 is exactly what a `--gate`-line grep over this job should show, and
does.

**Watch item.** `prefixsum_1m`'s runtime headroom on this run — **3.3× on p95** — is the tightest
observed anywhere in this mode, genuinely close to the 3× floor `GateFloorTests` enforces
structurally (§6b). This is not a failure and not a bug: it is the gate being *failable*, which is
the entire point of deriving budgets from real evidence instead of hand-typing loose ones (AGENTS.md:
"a gate that cannot fail is not a gate"). But it is the scenario to watch first if a future run turns
this gate red — check `reason=budget_exceeded` (code got slower, fix the code) versus
`reason=budget_stale` (budget needs re-deriving) before assuming either.

### Post-merge `push` run

**Pending.** Proof of merged code is anchored in the post-merge `push` run on `main`, not only the
PR-head run above — a PR run tests the merge commit's *tree*, not necessarily what actually lands on
`main` after the merge. Per the established pattern (Slices 31–38), this is filled in by a small
docs-only follow-up PR once the user merges PR #84, recording the `push`-triggered run id and
confirming its `--point-geometry-query --gate` step also reads `gate=pass` on all four scenarios at
step level.

---

## Notes carried from the task reviews

- The three parity oracles are **not** equal in strength, and this record must not imply they are.
  Oracle 1 (vs. `pointAt`) is fully independent: `pointAt` is a separately-written function, so a
  wrong 2D ordering or a mis-threaded line index diverges from it. Oracles 2 and 3 pin the
  composition's **wiring** (a swapped `x`/`y`, a stale value, an off-by-one `inLine`) but *not* the
  1D geometry arithmetic — they recompute the same 1D function with the test's own known-good
  arguments, so a bug inside `lineGeometryAt`'s math would reproduce on both sides of the assertion
  and never fail there. That arithmetic is covered by Slices 31/35's own suites, correctly out of
  scope here.
- The probe-count pin cannot be fooled by the binary search: the counting wrappers instrument the
  search probes too, but those cancel exactly in the `pointAt`-vs-`pointGeometryAt` difference
  (identical deterministic calls), leaving only the +2 / +2 box probes.
