# Slice 54 — calibration-chain hardening (D-23 + D-7) — verification record

This slice repairs the two unsound links the calibration chain carried into node 6's
first wrap harvest: D-23 (both wrap benchmark modes timed one operation per
`clock.measure`, quantised to the host clock tick, not the operation) and D-7 (the
harvester authenticated no run's source, so a fork's fabricated `p95_ns=` lines could
in principle enter the corpus). A third hole, found while reading for D-7, is closed
in the same slice: the corpus gains a sixth **verdict** column, and both budget
consumers reject `{budget_exceeded, budget_absolute_exceeded, operation_failures}` at
read time. Eleven falsifiability drills — the spec's seven, plus drill 8 from the whole-branch
review, plus drills 9-11 from a post-implementation validation pass — are the whole
proof for both guards; neither has ever fired against a real contaminated run. The
last three matter disproportionately: drills 1-8 all target a decision *function*,
and the validation pass asked what happens when the function survives and its **call
site** does not. On the harvester, the answer was that every automated check stayed
green while a fork's rows entered the corpus (Section 6).

Thirteen commits on `slice-54-calibration-chain-hardening`, in order:
`31c23e1` (amortised measurement helper), `3d67c93` (`--wrap-row-query` onto the
amortised shape), `03881ba` (`--wrap-compute` amortised, drain de-contaminated,
reindex repaired), `6652d9e` (Swift corpus reader learns the sixth verdict column),
`112815c` (derivation applies the reject set, third cross-language pin), `7ffbd95`
(`extract_rows()` extracted, writes the verdict column), `8ced3e1` (run-source
provenance, failing closed), `4c042ad` (fix: provenance capture gated on `gh api`'s
real exit status, not stdout emptiness — see the note at the end of section 8),
`7d3e082` (docs: the `AGENTS.md` `budget_stale` paragraph stated the wrong mechanism
— a review correction), and the whole-branch-review fix wave, which carries this
sentence and therefore cannot list its own sha. That last commit adds drill 8
(section 6), moves the derivation's `dropped=` reporting ahead of its
`no_corpus_rows` exit, and corrects four comments and one test name; its full
inventory is in
`.superpowers/sdd/2026-08-23-calibration-chain-hardening/final-fix-report.md`.

Three further commits come from a post-implementation validation pass: `c940e41`
(test: the harvest loop is driven end to end, so a lost call site reddens),
`66bbd6e` (refactor: one source for the corpus verdict column, pinned across both
readers), and `4e700b0` (docs: the call-site drills, the `--dry-run` caveat, and
D-26's Swift half). They add drills 9-11 and take the suite 407 -> 408; no budget,
corpus, or engine code is touched, and AC13 was re-checked after them.

---

## 1. Scope and acceptance criteria

| AC | Disposition | Evidence |
|---|---|---|
| 1 | PASS — the twelve gated modes' measurement loops are unchanged; `BenchmarkSupport.swift` is purely additive | Section 5 |
| 2 | PASS — `amortise` is a separate pure function pinned by exact equality; drill 1 records its red | Section 6 (Drill 1) |
| 3 | PASS — `reindex_ns` stays a single unamortised measurement, marked as such in source and output; the layout is constructed once (`WrapComputeBenchmark.swift:123`) and reused four times | Section 3 |
| 4 | PASS — every measurement prints its own `*_operations_per_sample=` token (`query_`/`compute_`/`drain_` > 1, `reindex_` = 1); before/after outputs recorded | Section 3 |
| 5 | PASS (diff read, not machine-checked, by design) — drain ranges are built before the timed loop; the drain body performs no `compute` | Section 4 |
| 6 | PASS — `--wrap-compute` prints `scenario=` and `drain_p99_ns=`; both modes keep prefixed latency tokens (no bare `p95_ns=`/`p99_ns=`) | Section 3 |
| 7 | PASS — `harvest-gate-corpus.sh` rejects a non-source-repo run, fails closed when the source cannot be read, and the `--runs` path obeys the same check. **The call site is guarded too**, not only the decision function: `--self-test` drives the whole script through a stubbed `gh` (drills 9-10) | Section 6 (Drills 2, 9, 10), Section 8 |
| 8 | PASS — the parser is extracted into `extract_rows()`, its truth table passes under `--self-test`, driven by `swift test` | Section 9 |
| 9 | PASS — the harvester writes a sixth verdict column on every emitted row; both readers additionally accept legacy five-column rows, which is what the committed corpus consists entirely of | Section 6 (Drill 5), Section 10 |
| 10 | PASS — a row whose `failures=` is non-zero is recorded as `operation_failures` regardless of its verdict, including a line with no `gate=` at all; drill 7 records the red | Section 6 (Drill 7) |
| 11 | PASS — `derive-gate-budgets.sh` and `GateFloorTests` apply the identical reject set, pinned by `testAdmissibleRowsMatchDeriveScript`; drills 3 and 4 record reds in both directions, and drill 8 (added in review) records the red of the **production** filter, which the seam-based pin does not reach | Section 6 (Drills 3, 4, 8) |
| 12 | PASS — the Swift reader accepts five-or-six-column rows; drill 5 records the red that proves it | Section 6 (Drill 5) |
| 13 | PASS — `derive-gate-budgets.sh` output over the committed corpus is byte-identical before and after, all 46 budgets reproduce, the committed corpus file is untouched | Section 7, Section 10 |
| 14 | PASS — neither wrap mode is gateable (`isGateable`'s `false` arm) or appears in `swift-ci.yml` | Section 10 |
| 15 | PASS — `AGENTS.md`'s harvest-admissibility sentence and the `budget_stale` paragraph no longer describe a harvest the script refuses; the harvester's usage header carries the sixth column | AGENTS.md edits (this task, Steps 3-6) |
| 16 | PASS — all seven spec drills recorded with observed red output, plus drill 8 from the whole-branch review and drills 9-11 from the post-implementation validation pass (the two harvester CALL SITES and the Swift reader divergence) | Section 6 |
| 17 | PASS — step-level proof on **both** halves. PR-head: run `32658632217` (`4e700b0`). Post-merge: push run `32660537137` on `e97791f`, the merge commit of PR #129. Each: three jobs, twelve gates, **46 `gate=pass` / 0 `gate=fail`**, 408/0, `invariant=pass`, `blocking_failures=0`, zero failure tokens; the merged tree is verified to carry the slice's artifacts | Section 11 |

---

## 2. Baseline

`swift test` (full suite), captured before any Task 1 code change, `/tmp/slice54-baseline.txt`:

```
Executed 397 tests, with 0 failures (0 unexpected) in 5.293 (5.318) seconds
```

Current (post-Task-7, re-confirmed in Section 9 below): **407 tests, 0 failures** — ten
net new tests across the slice (5 `AmortisedSamplesTests` + 2 `WrapBenchmarkLineShapeTests`
+ 2 `GateFloorTests` verdict tests + 1 `testAdmissibleRowsMatchDeriveScript`).

---

## 3. D-23 before/after

### Before (Task 1, pre-repair shape)

`--wrap-row-query` (`/tmp/slice54-before-wrap-row-query.txt`):

```
mode=wrap_row_query scenario=uniform_1k total_rows=1000 query_p95_ns=167 query_p99_ns=167 checksum=31968000
mode=wrap_row_query scenario=uniform_100k total_rows=100000 query_p95_ns=250 query_p99_ns=250 checksum=3198048000
mode=wrap_row_query scenario=narrow_100k total_rows=400000 query_p95_ns=250 query_p99_ns=292 checksum=3495461000
mode=wrap_row_query scenario=clamped_100k total_rows=400000 query_p95_ns=83 query_p99_ns=84 checksum=3500361000
```

`--wrap-compute` (`/tmp/slice54-before-wrap-compute.txt`):

```
mode=wrap_compute width=inf total_rows=100000 compute_p95_ns=167 compute_p99_ns=208 drain_p95_ns=15125 reindex_ns=16819042
mode=wrap_compute width=40 total_rows=200000 compute_p95_ns=208 compute_p99_ns=209 drain_p95_ns=9250 reindex_ns=17972958
mode=wrap_compute width=10 total_rows=800000 compute_p95_ns=209 compute_p99_ns=209 drain_p95_ns=4875 reindex_ns=24144791
```

### After (Tasks 2/3, repaired shape)

`--wrap-row-query` (`/tmp/slice54-after-wrap-row-query.txt`):

```
mode=wrap_row_query scenario=uniform_1k total_rows=1000 query_operations_per_sample=256 query_p95_ns=113 query_p99_ns=132 checksum=20459520000
mode=wrap_row_query scenario=uniform_100k total_rows=100000 query_operations_per_sample=256 query_p95_ns=204 query_p99_ns=249 checksum=2047976320000
mode=wrap_row_query scenario=narrow_100k total_rows=400000 query_operations_per_sample=256 query_p95_ns=210 query_p99_ns=255 checksum=2240234540000
mode=wrap_row_query scenario=clamped_100k total_rows=400000 query_operations_per_sample=256 query_p95_ns=29 query_p99_ns=35 checksum=2240231040000
```

`--wrap-compute` (`/tmp/slice54-after-wrap-compute.txt`):

```
mode=wrap_compute scenario=width_inf width=inf total_rows=100000 compute_operations_per_sample=256 compute_p95_ns=87 compute_p99_ns=98 drain_operations_per_sample=16 drain_p95_ns=14421 drain_p99_ns=15171 reindex_operations_per_sample=1 reindex_ns=29959125
mode=wrap_compute scenario=width_40 width=40 total_rows=200000 compute_operations_per_sample=256 compute_p95_ns=64 compute_p99_ns=74 drain_operations_per_sample=16 drain_p95_ns=8856 drain_p99_ns=9171 reindex_operations_per_sample=1 reindex_ns=16653875
mode=wrap_compute scenario=width_10 width=10 total_rows=800000 compute_operations_per_sample=256 compute_p95_ns=64 compute_p99_ns=79 drain_operations_per_sample=16 drain_p95_ns=4968 drain_p99_ns=5359 reindex_operations_per_sample=1 reindex_ns=23781750
```

AC4/AC6 confirmed directly from the after-output above: every line carries its own
`*_operations_per_sample=` token (`query_operations_per_sample=256`;
`compute_operations_per_sample=256`, `drain_operations_per_sample=16`,
`reindex_operations_per_sample=1`), `--wrap-compute` now carries `scenario=` and
`drain_p99_ns=`, and every latency key stays prefixed (`query_`/`compute_`/`drain_`/
`reindex_` — no bare `p95_ns=`/`p99_ns=`).

AC3 evidence (`Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`): the layout is
bound once — `let layout = BenchmarkWrapLayout(...)` at line 123, timed between
`reindexStart` (line 122) and `reindexElapsed` (line 126) — and reused, not
reconstructed, at every downstream site: `:128` (`layout.firstVisualRow(...)`), `:142`
(compute body), `:157` (drain-range pre-build loop), `:169` (drain body). There is
exactly one live `BenchmarkWrapLayout(...)` construction call in the file; the second
apparent match a naive grep reports is inside an explanatory comment quoting the old,
removed code (`WrapComputeBenchmark.swift:117`), not a second construction.

### Tick-multiple checks

**Denominator derivation, before side:** `--wrap-row-query` prints 2 latency values
per scenario (`query_p95_ns`, `query_p99_ns`) over 4 scenarios = 8; `--wrap-compute`
prints 4 per width (`compute_p95_ns`, `compute_p99_ns`, `drain_p95_ns`, `reindex_ns`)
over 3 widths = 12. Total = 8 + 12 = **20**.

`/tmp/slice54-before-ticks.txt` (host: Apple silicon, 24 MHz mach timebase, tick =
41.666... ns):

```
printed values: 20 (expected 20)
within 1 ns of an integer tick multiple: 20 of 20
   query_p95_ns          167  ticks=4.008
   query_p99_ns          167  ticks=4.008
   query_p95_ns          250  ticks=6.000
   query_p99_ns          250  ticks=6.000
   query_p95_ns          250  ticks=6.000
   query_p99_ns          292  ticks=7.008
   query_p95_ns           83  ticks=1.992
   query_p99_ns           84  ticks=2.016
   compute_p95_ns        167  ticks=4.008
   compute_p99_ns        208  ticks=4.992
   drain_p95_ns        15125  ticks=363.000
   reindex_ns       16819042  ticks=403657.008
   compute_p95_ns        208  ticks=4.992
   compute_p99_ns        209  ticks=5.016
   drain_p95_ns         9250  ticks=222.000
   reindex_ns       17972958  ticks=431350.992
   compute_p95_ns        209  ticks=5.016
   compute_p99_ns        209  ticks=5.016
   drain_p95_ns         4875  ticks=117.000
   reindex_ns       24144791  ticks=579474.984
```

Ratio (before): **20/20 = 100%** of printed wrap latency values landed on an integer
tick multiple — the D-23 defect as a number.

**Denominator derivation, after side:** `--wrap-row-query` is unchanged in shape (still
2 per scenario x 4 scenarios = 8). `--wrap-compute`'s repaired line now prints **5**
latency-bearing values per width (`compute_p95_ns`, `compute_p99_ns`, `drain_p95_ns`,
`drain_p99_ns`, `reindex_ns` — `drain_p99_ns` is new, per AC6) over 3 widths = 15.
Total = 8 + 15 = **23**.

`/tmp/slice54-after-ticks.txt`:

```
printed values: 23 (expected 23)
within 1 ns of an integer tick multiple: 4 of 23
   query_p95_ns            113  ticks=2.712
   query_p99_ns            132  ticks=3.168
   query_p95_ns            204  ticks=4.896
   query_p99_ns            249  ticks=5.976
   query_p95_ns            210  ticks=5.040
   query_p99_ns            255  ticks=6.120
   query_p95_ns             29  ticks=0.696
   query_p99_ns             35  ticks=0.840
   compute_p95_ns           87  ticks=2.088
   compute_p99_ns           98  ticks=2.352
   drain_p95_ns          14421  ticks=346.104
   drain_p99_ns          15171  ticks=364.104
   reindex_ns         29959125  ticks=719019.000
   compute_p95_ns           64  ticks=1.536
   compute_p99_ns           74  ticks=1.776
   drain_p95_ns           8856  ticks=212.544
   drain_p99_ns           9171  ticks=220.104
   reindex_ns         16653875  ticks=399693.000
   compute_p95_ns           64  ticks=1.536
   compute_p99_ns           79  ticks=1.896
   drain_p95_ns           4968  ticks=119.232
   drain_p99_ns           5359  ticks=128.616
   reindex_ns         23781750  ticks=570762.000
```

Ratio (after): **4/23 ≈ 17.4%**. Of those four hits, three are the three `reindex_ns`
values (`29959125`, `16653875`, `23781750`, each an exact integer tick multiple — diff
0.0000 ns) and the fourth is `query_p99_ns=249` sitting exactly at the ±1 ns tolerance
boundary (`249 / 41.666... ≈ 5.976`, nearest multiple `6 x 41.667 = 250`, diff exactly
1.0000 ns) — a single coincidental near-hit on an already-amortised value (`wrap_row_query`
has measured on the amortised shape since Task 2), not a systematic pattern. **Net: of
the 20 formerly-defective (non-`reindex_ns`) values, effectively 0 remain
tick-quantised** after the repair.

**`reindex_ns` remaining a tick multiple is expected, not a residual defect.** It is a
single-clock-read, one-shot O(N) setup measurement by explicit decision (AC3): nothing
amortises a one-shot construction, so it is naturally quantised to the host tick the
same way any single `clock.measure` call is — that quantisation is not evidence of the
D-23 defect, which was specifically about *repeatable per-operation* measurements
resolving the clock instead of the operation.

The host for both captures is Apple silicon (24 MHz mach timebase, tick ≈ 41.666... ns),
confirmed identically in both captures' `ticks=` column arithmetic; no re-derivation
against a different granularity was needed.

---

## 4. Decision 4 evidence (AC5 — diff read, not a test)

**AC5 has no unit test and cannot get one.** `amortisedSamples`' structural test pins
the body's call count, and a body that computed a range inside itself would satisfy
that pin unchanged. The only guards are a diff read of the source and the recorded
before/after `drain_p95_ns` values — this is stated explicitly in the spec's Risks
section, and this record repeats it rather than implying a green test covers it.

**Diff read** (`Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`, from Task 3's
report): the drain scroll ranges are built at `:154-163` —
`var drainRanges: [VirtualRange] = []` through the `preconditionFailure` case —
entirely outside any timing construct. The timed drain measurement begins at `:165`
(`let drainMeasured = amortisedSamples(...)`), strictly after `drainRanges` is fully
populated. `amortisedSamples` starts its own clock inside its own body (per Task 1's
`amortise`/`amortisedSamples` contract), which only runs once this call site is
reached, so no part of range construction falls inside the timed region. The drain
body itself performs no `compute` call — it walks `layout` (the bound-and-reused
construction from Section 3) via `visualRowGeometry`, not `compute(_:layout:)`.

**`drain_p95_ns` before vs. after:**

| scenario | before `drain_p95_ns` | after `drain_p95_ns` | delta |
|---|---:|---:|---:|
| width_inf | 15125 | 14421 | -4.7% |
| width_40  | 9250  | 8856  | -4.3% |
| width_10  | 4875  | 4968  | +1.9% |

The values stay in the same order of magnitude — drain still walks the whole buffer,
so its absolute cost is dominated by buffer size, not by contamination — but two of
three scenarios drop modestly after de-contamination and one rises slightly within
noise. This is the expected shape of removing cache/branch-predictor pollution from an
interleaved compute-then-drain loop on an already-large O(buffer) walk: a small,
directional shift, not a dramatic one. The far more dramatic before/after shift is on
`compute_p95_ns`/`compute_p99_ns` (167-209 ns unamortised before, resolving the host
tick, -> 64-98 ns amortised after, resolving the true sub-tick per-operation cost) —
exactly the D-23 defect Tasks 2/3 exist to repair, evidenced already in Section 3.

---

## 5. AC1 diff proof

```
$ BASE="$(git merge-base HEAD main)"
$ git diff --name-only "$BASE"...HEAD -- Sources/ViewportBenchmarks
benchmark files changed on this branch:
Sources/ViewportBenchmarks/BenchmarkSupport.swift
Sources/ViewportBenchmarks/WrapComputeBenchmark.swift
Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift
AC1 PASS: no gated benchmark file and no BenchmarkModels.swift touched
AC1 PASS: BenchmarkSupport.swift is purely additive (no deleted lines)
```

Exactly the three files the slice touches in `Sources/ViewportBenchmarks` — none of
the twelve gated benchmark files or `BenchmarkModels.swift` — and `BenchmarkSupport.swift`
carries zero deleted lines against the branch point (a pure insertion of `amortise`
and `amortisedSamples`).

---

## 6. The drills — seven from the spec, drill 8 from the whole-branch review, drills 9-11 from the validation pass

### Drill 1 — `amortise`'s division (AC2)

Mutation (`Sources/ViewportBenchmarks/BenchmarkSupport.swift`, inside `amortise`'s
body, line 43):

```
s|    return elapsedNanoseconds / Int64(operationsPerSample)|    return elapsedNanoseconds|
```

Observed red (`swift test --filter AmortisedSamplesTests`, `/tmp/slice54-drill1-red.txt`):

```
testAmortiseDividesByOperationsPerSample: XCTAssertEqual failed: ("2560") is not equal to ("10")
testAmortiseTruncatesRatherThanRounds: XCTAssertEqual failed: ("255") is not equal to ("0")
testAmortiseTruncatesRatherThanRounds: XCTAssertEqual failed: ("511") is not equal to ("1")
testAmortiseTruncatesRatherThanRounds: XCTAssertEqual failed: ("767") is not equal to ("2")
```

Restored; `swift test --filter AmortisedSamplesTests` returned to green
(`/tmp/slice54-drill1-restored.txt`), and `git diff` after restore showed only the
intended additive insertion — no residual mutation.

**This drill's target is `amortise`'s body, not its call site.** Deleting the *call*
inside `amortisedSamples` (i.e., folding the raw elapsed nanoseconds into `samples`
directly instead of routing through `amortise`) would **not** redden any test in this
suite — none of the five `AmortisedSamplesTests` exercises that call site's wiring
independently of `amortise`'s own correctness. That call-site residual has no unit-test
pin; it is covered by evidence instead — dropping the call would multiply every printed
wrap value by `operationsPerSample`, restoring the tick-multiple signature Section 3's
before-evidence captured (20/20), which the recorded before/after comparison in this
same record would catch. Recording this honestly rather than claiming a pin the suite
does not have, per the brief's explicit instruction.

### Drill 2 — the source-repo check (AC7)

Mutation (`.github/scripts/harvest-gate-corpus.sh`, inside `admissible_source`):

```
s|  elif [[ "$observed" != "$expected" ]]; then|  elif false; then|
```

Observed red (`./.github/scripts/harvest-gate-corpus.sh --self-test`):

```
self_test=fail label=admissible_source rejects a fork's run and names the source it saw
  expected: [skip=foreign_repo run=555 source=attacker/swift-text-engine]
  actual:   [plan=harvest run=555]
```

Restored; `--self-test` returned to `self_test=pass`, and `diff` against the pre-drill
backup was byte-identical (no residual mutation).

### Drill 3 — under-filtering, shell reject set (AC11, direction 1)

Mutation: removed `budget_exceeded` from `REJECTED_VERDICTS` in
`derive-gate-budgets.sh`.

Observed red (`swift test --filter "GateFloorTests/testAdmissibleRowsMatchDeriveScript"`):
raw-row equality failed (shell now admits the `budget_exceeded` row the Swift side
still rejects); row-count assertion failed (shell produced 6 rows, not 5); the
non-vacuity assertion for the reject direction failed directly (shell's row set
contained a row ending `\tbudget_exceeded`).

Restored from backup; confirmed byte-identical to the pre-drill working state.

### Drill 4 — over-filtering, shell reject set (AC11, direction 2)

Mutation: added `budget_stale` to the shell's `REJECTED_VERDICTS`.

Observed red: raw-row equality failed (shell now drops the `budget_stale` row Swift
still admits); row-count assertion failed (shell produced 4 rows, not 5); the
assertion `shellRows.contains { $0.hasSuffix("\tbudget_stale") }` — with the message
"`budget_stale` must be ADMITTED: its prescribed fix is to re-derive from it" — failed
directly, pinning specifically the row whose own fix requires it to be harvested.

Restored from backup; confirmed byte-identical.

### Drill 5 — five-or-six column guard (AC9, AC12)

Mutation (`Tests/ViewportBenchmarksTests/GateFloorTests.swift`):

```
s#        guard columns.count == 5 || columns.count == 6,#        guard columns.count == 6,#
```

Observed red (`swift test --filter "GateFloorTests/testSixColumnRowsAreReadAndFilteredByVerdict"`):

```
GateFloorTests.swift:113: error: -[...testSixColumnRowsAreReadAndFilteredByVerdict] :
failed - malformed corpus row 8: 50	line_query	uniform_1k	28	56
```

The failing row is exactly the legacy five-column fixture row (no verdict column) —
requiring exactly six columns reddens on the one row that has only five, directly
proving the back-compatibility claim is under test.

Restored; `git diff --stat` on the file showed only the intended Step-1/3 additions (104
insertions, 1 deletion), no residue of the drill mutation; `swift test --filter
GateFloorTests` returned to green (12/0 at that point in the branch's history).

### Drill 6 — laundered regression, end-to-end (AC13)

See Section 7 for the full control/treatment/clean comparison. Summary: injecting an
absurd-latency synthetic row (`999999` ns) with `verdict=pass` inflates
`line_query|uniform_1k`'s budget to `budget_p95=3000000 budget_p99=6000000`; the
identical row with `verdict=budget_exceeded` is rejected, reproducing the clean-corpus
budget up to the expected N=20 window shift (the new run id ages out the oldest run on
both the treatment and the clean-corpus sides identically — `n` drops from 20 to 19 for
every scenario, not just the injected one). `dropped=budget_exceeded rows=1` printed on
the treatment's stderr. Committed corpus confirmed untouched throughout.

### Drill 7 — `failures=` outranks the verdict (AC10)

Mutation (`.github/scripts/harvest-gate-corpus.sh`, inside `extract_rows`'s `verdict()`
awk function):

```
s|      if (f != "" \&\& f + 0 != 0) return "operation_failures"|      if (0) return "operation_failures"|
```

Observed red (`./.github/scripts/harvest-gate-corpus.sh --self-test`), exactly the two
rows the mutation targets, nothing else changed:

- expected `999	column_query	uniform_100k	41	71	operation_failures` vs. actual
  `999	column_query	uniform_100k	41	71	none` — the ungated `failures=3` line (the
  node-6 bootstrap-hole shape) silently downgraded to `none` once the `failures=`
  short-circuit was disabled.
- expected `999	point_query	uniform_1k	42	72	operation_failures` vs. actual
  `999	point_query	uniform_1k	42	72	pass` — the `gate=pass failures=2` line laundered
  through as `pass` once `failures=` no longer outranked the gate verdict.

Restored from backup; `diff` against the pre-drill backup was empty (byte-identical),
confirmed independently of "the self-test passes again" (which alone would not rule out
a different still-mutated file).

### Drill 8 — the PRODUCTION verdict filter (AC11, added by the whole-branch review)

Not one of the spec's seven. The review demonstrated that the reject rule is written
**twice** in `derive-gate-budgets.sh` — in `admissible_rows()` (the `--admissible-rows`
seam) and in the main awk that actually derives budgets — and that **the derivation
never calls `admissible_rows`**. Deleting only the production line left every
automated check in the repository green: `--self-test` exercised the seam, the
cross-language pin passed because the seam was still correct, and
`testEveryCommittedBudgetReproducesFromCorpus` passed because the committed corpus is
entirely five-column so output was byte-identical — while a laundered row loosened a
budget by four orders of magnitude. Drills 3 and 4 pin the seam; nothing pinned the
filter that runs.

The fix is a `run_self_test()` case that drives the **full derivation** (`"$0"
"$production_fixture"`, the way an operator invokes it — deliberately **not**
`--admissible-rows`) over a six-column fixture whose fourth row is
`804 line_query uniform_1k 1000000 2000000 budget_exceeded`. The three admitted rows
give `8 * median(20, 24, 30) = 192 > 3 * max = 90`, so `budget_p95 = 200`; admitting
the fourth makes `3 * max` govern at `3 000 000`. The case asserts the derived
**budget**, not a zero exit, and asserts the `dropped=` stderr line names its reason.

Mutation (delete the production filter line from the main awk):

```
  if ($6 != "" && index(rejected, " " $6 " ") > 0) { dropped[$6]++; next }
```

Observed red (`./.github/scripts/derive-gate-budgets.sh --self-test`, exit 1):

```
self_test=fail label=the derivation ITSELF drops budget_exceeded (admitting it would read 3000000)
  expected: [200]
  actual:   [3000000]
```

Restored from `/tmp/slice54-fix/derive-backup.sh`; `diff` against that backup was
empty (byte-identical), and the self-test then printed `self_test=pass` (exit 0). The
15 000x gap between expected and actual is the point: no rounding or near-miss can
make this case pass with the filter gone.

The **residual is recorded rather than removed** (ledger D-26b): the rule still lives
in two awk programs sharing only `REJECTED_VERDICTS`. Collapsing them — feeding the
main awk from `<(admissible_rows < "$corpus")` — was the review's preferred fix and
was rejected as too invasive for a branch whose value rests on AC13 byte-identity,
with one scoped re-review remaining.

---

### Drills 9-11 — the CALL SITES (added by the post-implementation validation pass)

Drills 1-8 all target a decision *function*. A validation pass asked the next question —
what happens if the function survives and its **call site** does not — and found the
harvester answered it badly.

**Drill 9 — delete the `admissible_source` call site** from the harvest loop (the five
lines between the log fetch and the dedup skip). Observed **before** the repair:

```
$ bash .github/scripts/harvest-gate-corpus.sh --self-test
self_test=pass
$ swift test
Executed 407 tests, with 0 failures
$ PATH="<stub gh>:$PATH" bash .github/scripts/harvest-gate-corpus.sh --limit 3
1001<TAB>line_query<TAB>uniform_1k<TAB>24<TAB>54<TAB>pass      <- this repository
1002<TAB>line_query<TAB>uniform_1k<TAB>24<TAB>54<TAB>pass      <- A FORK
1003<TAB>line_query<TAB>uniform_1k<TAB>24<TAB>54<TAB>pass      <- provenance UNREADABLE
```

Every automated check in the repository green, and a fork's numbers in the corpus that
carries twelve blocking budgets. This is the seam-versus-production divergence D-26(b)
records for the derivation's awk filter — the one the whole-branch review caught and fixed
with drill 8 — recurring one script over, on the axis where the failure is *silent*: losing
`extract_rows`' call site emits zero rows, losing this one emits **more**.

**The repair** is drill 8's move on the harvest side: a `--self-test` case that invokes the
script the way an operator does, with a stubbed `gh` serving one admissible run, one fork,
and one 404 (JSON body on stdout, non-zero exit, as real `gh api` does), asserting the rows
that reach stdout. The same log is served for all three runs on purpose, so a passing
assertion can only mean a run was refused, never that the logs differed.

Observed **after** the repair:

| drill | mutation | result |
|---|---|---|
| 9  | delete the `admissible_source` call site | `self_test=fail label=the harvest LOOP emits rows for the admissible run only (the CALL SITE, not just the function)`, exit 1 |
| 10 | delete the `extract_rows` call site (pipe the log to `/dev/null`) | same label, exit 1 — one case covers both call sites |

**Drill 11 — the Swift analog.** The two Swift readers extracted the verdict column
independently and disagreed on the column-count rule (`>= 6` in `admissibleCorpusRows`, the
seam the cross-language pin drives; `== 6` in `corpusExtremes`, what the floor check reads).
Unreachable today — a harvest writes exactly six columns — and unreachable is not pinned.
`corpusVerdict` is now the single source. Mutating one reader to stop reading the column:

```
Executed 408 tests, with 3 failures
  testTheTwoCorpusReadersAdmitTheSameRows: ("Optional(5)") is not equal to ("Optional(8)")
  testTheTwoCorpusReadersAdmitTheSameRows: ("8") is not equal to ("5")
  testAdmissibleRowsMatchDeriveScript:     the shell admitted 5, Swift 8
```

Green tree after all three repairs: `swift test` **408/0**, all four `--self-test` exit 0,
the 46 committed budgets still byte-identical over the committed corpus.

---

## 7. Drill 6 end-to-end (AC13)

```
$ CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
$ cp "$CORPUS" /tmp/slice54-drill6-control.tsv
$ cp "$CORPUS" /tmp/slice54-drill6-treatment.tsv
$ printf '99999999999\tline_query\tuniform_1k\t999999\t999999\tpass\n'            >> /tmp/slice54-drill6-control.tsv
$ printf '99999999999\tline_query\tuniform_1k\t999999\t999999\tbudget_exceeded\n' >> /tmp/slice54-drill6-treatment.tsv
```

**Control** (verdict=pass — the laundered row IS counted):

```
line_query|balanced_tree_100k                  n=19  p95[med=208    max=244   ] p99[med=223    max=283   ] budget_p95=1700    budget_p99=3400    gov_p95=median margin_p95=7.0x margin_p99=12.0x
line_query|balanced_tree_1m                    n=19  p95[med=251    max=257   ] p99[med=261    max=290   ] budget_p95=2100    budget_p99=4200    gov_p95=median margin_p95=8.2x margin_p99=14.5x
line_query|uniform_100k                        n=19  p95[med=34     max=87    ] p99[med=66     max=99    ] budget_p95=280     budget_p99=560     gov_p95=median margin_p95=3.2x margin_p99=5.7x
line_query|uniform_1k                          n=20  p95[med=23     max=999999] p99[med=54     max=999999] budget_p95=3000000 budget_p99=6000000 gov_p95=max    margin_p95=3.0x margin_p99=6.0x
line_query|uniform_1m                          n=19  p95[med=40     max=75    ] p99[med=71     max=88    ] budget_p95=320     budget_p99=640     gov_p95=median margin_p95=4.3x margin_p99=7.3x
```

**Treatment** (verdict=budget_exceeded — rejected):

```
line_query|balanced_tree_100k                  n=19  p95[med=208    max=244   ] p99[med=223    max=283   ] budget_p95=1700    budget_p99=3400    gov_p95=median margin_p95=7.0x margin_p99=12.0x
line_query|balanced_tree_1m                    n=19  p95[med=251    max=257   ] p99[med=261    max=290   ] budget_p95=2100    budget_p99=4200    gov_p95=median margin_p95=8.2x margin_p99=14.5x
line_query|uniform_100k                        n=19  p95[med=34     max=87    ] p99[med=66     max=99    ] budget_p95=280     budget_p99=560     gov_p95=median margin_p95=3.2x margin_p99=5.7x
line_query|uniform_1k                          n=19  p95[med=23     max=51    ] p99[med=54     max=68    ] budget_p95=190     budget_p99=440     gov_p95=median margin_p95=3.7x margin_p99=6.5x
line_query|uniform_1m                          n=19  p95[med=40     max=75    ] p99[med=71     max=88    ] budget_p95=320     budget_p99=640     gov_p95=median margin_p95=4.3x margin_p99=7.3x
```

**Treatment stderr:**

```
dropped=budget_exceeded rows=1
```

Control vs. treatment: **differ, as required** — the control's `line_query|uniform_1k`
row is wildly inflated (`budget_p95=3000000`, `budget_p99=6000000`, `gov_p95=max`); the
treatment's is not.

Treatment vs. clean (`derive-gate-budgets.sh "$CORPUS" line-query` over the untouched
committed corpus): **DRILL 6 PARTIAL**, and the diff is explained entirely by the
window shift, not by the injected row's latency leaking through:

```
--- /tmp/slice54-drill6-clean.txt
+++ /tmp/slice54-drill6-treatment.txt
@@ -1,5 +1,5 @@
-line_query|balanced_tree_100k                  n=20  ...
-line_query|balanced_tree_1m                    n=20  ...
-line_query|uniform_100k                        n=20  ...
-line_query|uniform_1k                          n=20  ...
-line_query|uniform_1m                          n=20  ...
+line_query|balanced_tree_100k                  n=19  ...
+line_query|balanced_tree_1m                    n=19  ...
+line_query|uniform_100k                        n=19  ...
+line_query|uniform_1k                          n=19  ...
+line_query|uniform_1m                          n=19  ...
```

Every one of `line_query`'s five scenarios drops from `n=20` to `n=19` uniformly — the
new synthetic run id occupies one N=20 window slot, aging the oldest run out for all
five scenarios equally (the window is keyed on run id, not per-scenario). This is the
documented, expected window-shift effect (`AGENTS.md`'s "hosted is a trailing window"
section), not a laundering leak: every numeric field for `line_query|uniform_1k`
itself (`med=23 max=51`, `budget_p95=190`, `budget_p99=440`) is identical between
treatment and clean, aside from the shared `n` shift. This is the acceptable-PARTIAL
outcome the brief anticipates.

`git diff --quiet` on the committed corpus: **committed corpus untouched**.

---

## 8. Live network exercise (AC7)

From Task 7 (`gh auth status` confirmed logged in as `arthurbanshchikov` before any
network call).

**First candidate** (the literal `gh run list ... --limit 1` at the time of the task):

```
$ gh run list -R maldrakar/swift-text-engine --workflow swift-ci.yml --limit 1 --json databaseId --jq '.[].databaseId'
32596471964
$ gh api repos/maldrakar/swift-text-engine/actions/runs/32596471964 --jq '.head_repository.full_name'
maldrakar/swift-text-engine
$ ./.github/scripts/harvest-gate-corpus.sh --runs 32596471964 --corpus docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
```

Result: exit 0, empty stdout, empty stderr. This run (a `slice-53-post-slice-review`
PR) took the docs-only fast path in CI, so its benchmark job legitimately printed zero
`p95_ns=` lines — the source check passed silently, the log was fetched (373 lines
scanned), and correctly nothing was emitted. Corpus confirmed untouched (checksum
identical before/after, `git status --porcelain` empty for the corpus path).

**Second candidate**, chosen to get a substantive positive result from the wired
network path (`slice-53-wrap-row-query`, run `32591420156`, not previously harvested):

```
$ gh api repos/maldrakar/swift-text-engine/actions/runs/32591420156 --jq '.head_repository.full_name'
maldrakar/swift-text-engine
$ ./.github/scripts/harvest-gate-corpus.sh --runs 32591420156 --corpus docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
```

Result: exit 0, empty stderr, **46 six-column rows** on stdout, e.g.:

```
32591420156	pipeline	1k_lines_20_visible_overscan_0	2566	2720	pass
32591420156	pipeline	100k_lines_80_visible_overscan_5	10644	11065	pass
32591420156	pipeline	1m_lines_200_visible_overscan_50	34495	35404	pass
32591420156	variable_height	1k_lines_20_visible_overscan_0	507	593	pass
32591420156	variable_height	100k_lines_80_visible_overscan_5	1770	1840	pass
```

Column count of the first row: 6, as required. Corpus confirmed untouched after this
call too (checksum unchanged, `git diff --quiet` true, `git status --porcelain` empty
for the corpus path). Both live calls prove the provenance check executes and admits a
genuine same-repo run without printing a `skip=` line — silence on success, by design.
Neither `skip=foreign_repo` nor `skip=provenance_unknown` was exercised live (that
would require a run whose head repository truly differs or is unreadable); both are
covered deterministically by the `--self-test` truth table instead, which is why
`admissible_source` is kept network-free and pure.

**Fix round 1 (`4c042ad`), for the record.** The initial `admissible_source` wiring
(`8ced3e1`) captured `gh api`'s output with `... || true`, inferring failure from
stdout emptiness. A review reproduced live that `gh api` writes its JSON error body
(e.g. `{"message":"Not Found",...,"status":"404"}`) to **stdout** on a non-2xx
response, bypassing `--jq` — so that JSON blob sat in `$source_repo` looking
non-empty and non-null, and a 404 / expired-log / rate-limited call against a
*legitimate same-repo* run was misreported as `skip=foreign_repo` (with the JSON
blob printed as the "source") instead of the contracted `skip=provenance_unknown`.
The security property already held either way (`foreign_repo` also short-circuits
before the log fetch), but the diagnostic contract was wrong. The fix replaces the
`|| true` idiom with an explicit exit-status capture:

```bash
if ! source_repo="$(gh api "repos/$repo/actions/runs/$id" \
     --jq '.head_repository.full_name' < /dev/null 2>/dev/null)"; then
  source_repo=""
fi
```

and `admissible_source` itself gained a defense-in-depth `owner/name` shape check, so a
malformed `observed` value maps to `provenance_unknown` rather than being compared to
`expected` as a foreign name. **`admissible_source`'s truth table now has five cases,
not four** — the fifth, added in `4c042ad`, uses the real 404 body as its literal input:

```bash
assert_equal "skip=provenance_unknown run=1" \
  "$(admissible_source 1 '{"message":"Not Found",...,"status":"404"}' 'maldrakar/swift-text-engine')" \
  "admissible_source treats a malformed (non owner/name) source as unknown, not as a foreign name"
```

Reproduced live against the real nonexistent run id the review used:

```
$ gh api "repos/maldrakar/swift-text-engine/actions/runs/1" --jq '.head_repository.full_name' < /dev/null
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/actions/workflow-runs#get-a-workflow-run","status":"404"}
exit=1
```

With the fixed capture-and-decide sequence: `captured source_repo (fixed wiring): []`
followed by `skip=provenance_unknown run=1` — the contracted outcome, not
`skip=foreign_repo`. The fail-closed mechanism is exit-status capture, not stdout
emptiness; this is stated here precisely because Task 7's own first-pass report
described the fail-closed behavior in terms of the (then-buggy) stdout-emptiness
assumption, and that description would otherwise be smoothed over by omission.

---

## 9. Full sweep

```
$ swift test > /tmp/slice54-final-test.txt 2>&1
suite green
Executed 407 tests, with 0 failures (0 unexpected) in 5.266 (5.292) seconds
Executed 407 tests, with 0 failures (0 unexpected) in 5.266 (5.293) seconds

$ swift build -c release
release build green

$ rg -n 'Foundation' Sources/TextEngineCore
PASS: TextEngineCore Foundation-free

$ rg -n 'Foundation' Sources/ViewportBenchmarks
Sources/ViewportBenchmarks/WrapComputeBenchmark.swift:185:        // No Foundation in this target: `String(format:)` is unavailable, so format the
Sources/ViewportBenchmarks/WrapComputeBenchmark.swift:186:        // (always-integral) finite widths via `Int(_:)` rather than importing Foundation.
Sources/ViewportBenchmarks/BenchmarkSupport.swift:130:// One decimal place, without Foundation: `String(format:)` would drag Foundation
```

**Note on the `ViewportBenchmarks` Foundation scan.** The literal `rg` check reports
non-empty output, which the brief's script would print as `FAIL:`. Investigated rather
than accepted at face value: all three hits are pre-existing **comments** *explaining
the deliberate absence* of Foundation (`String(format:)` is unavailable without it),
not `import Foundation` statements. Confirmed both that `rg -n '^import Foundation'
Sources/ViewportBenchmarks` returns no matches, and — independently — that both
comment lines already existed at the branch's merge-base with `main`
(`WrapComputeBenchmark.swift:98-99` and `BenchmarkSupport.swift:72` pre-slice; Task 1's
insertion of `amortise`/`amortisedSamples` shifted the latter down to line 130, and
Task 3's rewrite of `runWrapComputeBenchmarks` shifted the former down to 185-186 — no
new text). This is not a defect this slice introduced; it is the same false-positive
Tasks 1 and 3 independently documented and correctly interpreted as clean.
`Sources/ViewportBenchmarks` remains genuinely Foundation-free.

```
$ for s in cross-target-compile.sh derive-gate-budgets.sh harvest-gate-corpus.sh detect-docs-only-pr.sh; do
    "./.github/scripts/$s" --self-test
  done
self_test=pass: cross-target-compile.sh
self_test=pass: derive-gate-budgets.sh
self_test=pass: harvest-gate-corpus.sh
self_test=pass: detect-docs-only-pr.sh
```

**Twelve gates:**

```
gate=pass: default
gate=pass: --realistic-provider
gate=pass: --variable-height
gate=pass: --variable-height-mutation
gate=pass: --structural-mutation
gate=pass: --bulk-structural-mutation
gate=pass: --line-query
gate=pass: --line-geometry-query
gate=pass: --column-query
gate=pass: --column-geometry-query
gate=pass: --point-query
gate=pass: --point-geometry-query
total gate=pass lines across the twelve modes: 46 (expect 46)
```

Per-mode scenario counts summing to 46: default/pipeline 3, `--realistic-provider` 1,
`--variable-height` 3, `--variable-height-mutation` 3, `--structural-mutation` 3,
`--bulk-structural-mutation` 5, `--line-query` 5, `--line-geometry-query` 5,
`--column-query` 5, `--column-geometry-query` 5, `--point-query` 4,
`--point-geometry-query` 4 = 46. Every scenario line's `headroom_p95`/`headroom_p99`
sits comfortably inside the 3x-100x band (observed range across all 46 lines:
roughly 12.9x-26.2x on p95, 23.9x-45.7x on p99), and every `headroom_absolute_p99`
clears its class ceiling by two to five orders of magnitude — no budget in this sweep
moved, and none sits newly close to a boundary.

**`--memory-shape`:**

```
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 ... invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 ... invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text ... invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 ... invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 ... invariant=pass checksum=765061875
```

All five scenarios: `invariant=pass`.

---

## 10. AC13 (final re-check against the committed corpus)

```
$ CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
$ BASE="$(git merge-base HEAD main)"
$ git show "$BASE:.github/scripts/derive-gate-budgets.sh" > /tmp/slice54-derive-base.sh
$ bash /tmp/slice54-derive-base.sh "$CORPUS" > /tmp/slice54-final-derive-base.txt 2>/dev/null
$ bash ./.github/scripts/derive-gate-budgets.sh "$CORPUS" > /tmp/slice54-final-derive-head.txt 2>/tmp/slice54-final-derive-head.err
$ diff -u /tmp/slice54-final-derive-base.txt /tmp/slice54-final-derive-head.txt
AC13 PASS: derivation output byte-identical to the branch point
stderr from the head derivation (expect empty): []
AC13 PASS: corpus file untouched
AC14 PASS: swift-ci.yml untouched
```

`derive-gate-budgets.sh` at `HEAD` (with the reject-set logic added) produces
byte-identical output over the committed corpus as `derive-gate-budgets.sh` at the
branch point (`main`) — because the committed corpus is entirely legacy five-column
rows, so the sixth-column filter has nothing to reject and dropped-row reporting is
empty. The committed corpus file is untouched by `git diff` across the whole branch,
and `swift-ci.yml` is untouched.

**`isGateable` (AC14, wrap modes stay non-gateable):** the brief's literal grep
one-liner (`rg wrapCompute|wrapRowQuery | rg isGateable|true`) returns empty on this
codebase — an artifact of `rg`'s per-line matching over Swift's multi-line `case` list
formatting, not a finding. Confirmed instead by directly reading
`Sources/ViewportBenchmarks/BenchmarkOptions.swift:72-94`: `.wrapCompute` and
`.wrapRowQuery` are both members of the `case .rangeOnly, .memoryShape,
.memoryObservation, .wrapCompute, .wrapRowQuery: return false` arm of `isGateable`.
Neither wrap mode is gateable.

---

## 11. Hosted proof (AC17)

**DISCHARGED at step level — both halves.**

AC17 asks for step-level proof on **both** the PR-head run and the post-merge run. Those
are two different claims — the first says the branch is green, the second says the code
that actually landed on `main` is green — and only the second can be made after the merge,
which is why this record was written in two passes. Both are now recorded with their
evidence below.

### Why there are two PR-head runs

The branch was pushed once at the end of implementation and once again after a
post-implementation validation pass found and fixed three call-site gaps (drills 9-11,
Section 6). Both runs are recorded: the first is the tree the implementation ended on, the
second is the last tree carrying **non-documentation** changes. **The second is the binding
one** — the first is kept because dropping it would hide that the branch changed after its
first green run, which is exactly the kind of omission this record exists to prevent.

Commits after `4e700b0` are this section itself, and they cannot name the run of the commit
that contains them — the same regress the commit list at the top of this record notes. It
terminated in the post-merge section below, written from a branch cut after the merge, which
names the merged tree's push run from outside it. In this table "binding" therefore means
the last commit that changed **code**, not the tip of the branch.

| | run 1 | run 2 (binding) |
|---|---|---|
| run id | `32654599644` | `32658632217` |
| head sha | `a1593d1` | `4e700b0` |
| created | 2026-08-23T17:22:03Z | 2026-08-23T18:37:38Z |
| event | `pull_request` (PR #129) | `pull_request` (PR #129) |
| conclusion | success | success |

### Step-level evidence

Job conclusions are recorded but are **not** the proof — a green job can hide a dead
`continue-on-error` step (the slice-16 trap). The claims below are read out of the step
logs.

```
$ gh run view 32658632217 --json jobs --jq '.jobs[] | .name+" -> "+.conclusion'
Host tests and benchmark gate -> success
WASM cross-target compile -> success
iOS cross-target compile -> success

$ gh run view <id> --log > run.log
$ echo "gate_pass=$(grep -c 'gate=pass' run.log)  gate_fail=$(grep -c 'gate=fail' run.log)"
$ grep -oE "Executed [0-9]{3,} tests, with [0-9]+ failures" run.log | sort -u
$ grep -o "invariant=[a-z]*" run.log | sort -u
$ grep -oE "mode=cross_target_compile_overall .*" run.log | sort -u
$ grep -oE "mode=docs_only_pr result=[a-z_]+ docs_only_pr=[a-z]+ file_count=[0-9]+ non_doc_count=[0-9]+" run.log | sort -u
```

| claim | run 1 (`a1593d1`) | run 2 (`4e700b0`) |
|---|---|---|
| twelve blocking gates | `gate_pass=46  gate_fail=0` | `gate_pass=46  gate_fail=0` |
| host suite | `Executed 407 tests, with 0 failures` | `Executed 408 tests, with 0 failures` |
| `--memory-shape` | `invariant=pass` | `invariant=pass` |
| cross-target | `blocking_failures=0 exit=0` | `blocking_failures=0 exit=0` |
| docs-only guard | `result=not_docs_only docs_only_pr=false file_count=14 non_doc_count=8` | identical |

The suite goes 407 -> 408 between the runs: that is
`testTheTwoCorpusReadersAdmitTheSameRows`, added by the validation pass. **AC13 is
unaffected and was re-checked** — the 46 committed budgets still re-derive byte-identically
over the untouched committed corpus, which matters because the validation pass edited
`GateFloorTests`, a corpus consumer.

Every requested cross-target line is `result=pass reason=none blocking=true` across both
kinds and both packages (`ios_device`, `ios_simulator`, `wasm`, `wasm_embedded` x
`core`, `providers`). The `result=skipped reason=not_requested blocking=false` lines that
also appear are each job declining the *other* job's targets, and are explicitly
non-blocking. One token in the log reads `mode=docs_only_pr result=infrastructure_failure`
and is **not** a result: it is the step's own source being echoed by the runner
(`reason=$1` is unexpanded), and the decision line two rows above it is
`result=not_docs_only`.

### The guard added this slice ran hosted

`swift test` drives `harvest-gate-corpus.sh --self-test`
(`ScriptSelfTestTests.swift`), so the new harvest-loop case — the one that reddens when a
call site is deleted — executed on hosted Linux x86_64, not only on the local macOS host.
The three tests the validation pass touched or added are visible by name in run 2's log:
`testTheTwoCorpusReadersAdmitTheSameRows`, `testAdmissibleRowsMatchDeriveScript`,
`testEveryScriptSelfTestPasses`.

### Post-merge push run — the merged code

A PR-head run proves the branch is green. This one proves that what actually landed on
`main` is, which is the claim AC17 exists for and the only one a reader can act on.

| | value |
|---|---|
| run id | `32660537137` |
| event | `push` (branch `main`) |
| head sha | `e97791fb6f4303a6fbba8a09844c7810a5aee7c9` — the merge commit of PR #129 |
| created | 2026-08-23T19:13:03Z |
| conclusion | success |

```
$ gh run view 32660537137 --json headSha,event,conclusion,jobs \
    --jq '"sha=\(.headSha) event=\(.event) conclusion=\(.conclusion)", (.jobs[] | "  \(.name) -> \(.conclusion)")'
sha=e97791fb6f4303a6fbba8a09844c7810a5aee7c9 event=push conclusion=success
  WASM cross-target compile -> success
  Host tests and benchmark gate -> success
  iOS cross-target compile -> success
```

Step-level readings, by the same commands used on the PR-head runs:

| claim | reading |
|---|---|
| twelve blocking gates | `gate_pass=46  gate_fail=0` |
| host suite | `Executed 408 tests, with 0 failures` |
| `--memory-shape` | `invariant=pass` |
| cross-target | `mode=cross_target_compile_overall blocking_failures=0 exit=0` |
| failure tokens anywhere in the log | `0` (`self_test=fail`, `gate=fail`, `error:`, `XCTAssert… failed`) |

The docs-only detector correctly declines to short-circuit a push:

```
mode=docs_only_pr event=push result=not_pull_request docs_only_pr=false
```

emitted by all three jobs. That is the intended shape — the detector's fast path is a
*PR* concern, and `push` runs the heavy path unconditionally. (`AGENTS.md` notes that
docs-only pushes to `main` may skip Swift CI entirely via `push.paths-ignore`; this push
carried Swift and script changes, so the workflow started and the detector then declined
the short-circuit on event grounds.)

### The proof is anchored to the merged tree, not to the branch

A green push run is necessary but not sufficient: it proves *some* tree is green. These
checks read the slice's own artifacts out of `origin/main` itself, so the run above is
anchored to code that is demonstrably present:

```
$ git show origin/main:.github/scripts/harvest-gate-corpus.sh \
    | grep -c "admissible_source\|the harvest LOOP emits rows"
17
$ git show origin/main:Tests/ViewportBenchmarksTests/GateFloorTests.swift \
    | grep -c "corpusVerdict\|testTheTwoCorpusReadersAdmitTheSameRows"
5
$ git show origin/main:Sources/ViewportBenchmarks/BenchmarkSupport.swift \
    | grep -c "amortisedSamples\|func amortise"
3
```

And the three tests the validation pass added or touched are visible **by name in the push
run's log**, so the guards did not merely land — they executed on hosted Linux x86_64
against the merged tree: `testTheTwoCorpusReadersAdmitTheSameRows`,
`testAdmissibleRowsMatchDeriveScript`, `testEveryScriptSelfTestPasses`. The first of those
is what carries the suite from 407 to 408 across the four runs below.

AC13 holds across the merge: the merge commit touches no corpus row
(`git diff --quiet e97791f~1 e97791f -- <corpus>` exits 0).

### The four runs

| run | sha | event | jobs | gates | suite |
|---|---|---|---|---|---|
| `32654599644` | `a1593d1` | pull_request | 3/3 | 46 pass / 0 fail | 407 / 0 |
| `32658632217` | `4e700b0` | pull_request | 3/3 | 46 pass / 0 fail | 408 / 0 |
| `32659890321` | `16da857` | pull_request | 3/3 | 46 pass / 0 fail | 408 / 0 |
| `32660537137` | `e97791f` | **push (main)** | 3/3 | 46 pass / 0 fail | 408 / 0 |

All four: `invariant=pass`, `blocking_failures=0 exit=0`, zero failure tokens. AC17 is
now fully discharged, and the sha regress noted above terminates here — this section is
written from a branch cut *after* the merge, so it can name the merged tree's run without
containing it.
