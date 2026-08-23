# Calibration-Chain Hardening (wrap benchmark timing shape + harvester provenance) Design

- **Slice:** 54 — soft-wrap arc, **no map node** (de-risking work for criterion 4)
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md)
- **Brief:** [`docs/wrap-project-brief.md`](../../wrap-project-brief.md)
- **Ledger items:** D-23 (P2), D-7 (P2)

## Status

Proposed. Brainstormed 2026-08-23; this document is the ratified design. Four
decisions were taken with the user during brainstorming: the repair shape for the
timing defect (a shared helper, not the shared summary machinery); the rejection of
`conclusion`-based filtering in favour of a **per-row verdict** axis; recording the
verdict in the corpus and filtering at **read** time rather than at harvest; and
keeping both items in one slice rather than splitting along the
produce/consume seam.

Two of those came from the user correcting the design mid-brainstorm, and both
corrections are load-bearing rather than cosmetic — they are recorded as Decisions
5 and 6 with the evidence that settled them.

**Amended 2026-08-23 after a design review**, before any plan was written. Every
factual claim in Source Context, Problem and Audit was re-verified against live data
and reproduced; the amendments are two gaps and four corrections, not a change of
direction:

- **Decision 4 is new** — `--wrap-compute`'s drain measurement consumes the range
  the compute measurement produces, so "both via the helper" had three possible
  meanings that measure different things. Ratified rather than left to the plan.
- **Decision 7 gains the `failures=` rule** — the reject set as first written was
  blind to a degenerate measurement on any line printed without `--gate`, which is
  exactly node 6's bootstrap case, the one this slice exists to protect.
- **Decision 3** no longer offers magnitude as the reason `reindex_ns` is exempt
  (it does not discriminate: `drain` is equally far above tick granularity), and now
  also repairs the measurement site's missing dead-code guard and duplicated O(N)
  construction.
- **Problem's before-claim became structural** (integer tick multiples, N of N)
  rather than a transcribed pair of numbers, which a re-run had already falsified.
- **Audit** names its join key, which is not the one the obvious command returns.
- **Documentation Updates** was aimed at two `AGENTS.md` passages that do not exist;
  the real contradictions are named instead.

## Source Context

The calibration chain has three links. The **benchmark** produces numbers; the
**harvester** (`.github/scripts/harvest-gate-corpus.sh`) turns hosted CI logs into
corpus rows; the **derivation** (`.github/scripts/derive-gate-budgets.sh`, plus
`GateFloorTests`' Swift reader) turns corpus rows into the twelve blocking gates'
budgets. `AGENTS.md` binds all three together as one recipe, and the wrap brief's
criterion 4 binds **future wrap gates** to that same recipe by reference.

Map node 6 will promote the wrap benchmark modes to blocking gates through
`harvest → derive`. That path **never re-measures and never re-authenticates**: it
reads whatever the log said. Both defects this slice repairs are therefore
repairable only *before* node 6's first harvest, not after.

Neither defect has a live inhabitant today. That is not a reason to defer them; it
is the reason their proof has to be synthetic, and it is the shape of the failure
this repository has shipped before — slices 27/31/33/35/37 shipped budgets that
could not fail, and nobody noticed for five slices because `gate=pass` prints
convincingly.

## Problem

**D-23 — the wrap benchmarks measure the clock, not the operation.**
`WrapRowQueryBenchmark.swift:66-71` and `WrapComputeBenchmark.swift:80-92` wrap a
**single** operation in `clock.measure` and record the raw elapsed nanoseconds.
Every gated mode instead runs `operationsPerSample = 256` operations under one
clock read and divides (`LineQueryBenchmark.swift:73-89`). Measured locally in
release, **every** value the two modes print lands within 1 ns of an integer
multiple of the host clock tick (≈41.667 ns on Apple silicon; 13 of 13 values over
one sweep), while the gated siblings this query belongs beside measure 17-94 ns —
below one tick. A budget derived from these numbers would be a budget on clock
overhead.

The falsifiable before-claim is that **structural** one — integer tick multiples —
and not any particular pair of numbers. Which scenario happens to collapse to
`p95 == p99` moves between sweeps: the slice-53 review recorded `uniform_1k` doing
so; a re-run while fixing this design had `uniform_1k` at 167/208 and
`clamped_100k` at 83/84 instead. Both observations are the same defect, but only
the tick-multiple property is stable enough to assert in a document. Per this
repository's own lesson that a transcribed measurement rots, the sweep's actual
numbers belong in the verification record, not here.

**D-7 — the harvester authenticates nothing.** Run selection is
`gh run list --workflow swift-ci.yml --limit N --json databaseId`
(`harvest-gate-corpus.sh:139-142`) — the run id and nothing else. There is no check
that the run came from this repository rather than a fork, and the `--runs id,id`
entry path bypasses even the workflow filter.

**A second hole, found while reading for D-7 and not recorded in the ledger.** A
failing gate prints its summary line **before** the verdict is checked
(`LineQueryBenchmark.swift:141` then `:143`; the same shape in all twelve modes),
so a line reading `gate=fail reason=budget_exceeded` reaches the log. The
harvester's parser reads only `mode`, `scenario`, `p95_ns`, `p99_ns`
(`harvest-gate-corpus.sh:210-219`) and the corpus schema has no column for a
verdict, so a regression sample is stored as evidence of normal cost,
indistinguishable from a healthy one. The derivation's `3 x max` term is governed
by a **single** value, so one such row can set a budget by itself — and
`testEveryCommittedBudgetReproducesFromCorpus` then *requires* the loosened budget
to be committed for `swift test` to go green. The mechanism that enforces "derived,
never hand-typed" becomes the mechanism that delivers the loosening.

`AGENTS.md` makes it worse by instruction, not by accident:

> A post-harvest `GateFloorTests` failure is `budget_stale`, not an engine
> regression: the new samples raised a floor under an unchanged budget. Re-derive
> that scenario; **do not go hunting for a slowdown in the core.**

That is correct for its intended case and indistinguishable from contamination,
because nothing downstream reads the verdict.

## Audit (run 2026-08-23, before the design was fixed)

The scope of both items was settled against live data rather than argument. All
279 workflow runs the API still carries were joined against the 81 run ids in the
committed corpus.

**The join key is the host job's conclusion, not the run's**, and the two disagree
— so re-running this audit with the obvious command gets a different table.
`gh run list --json conclusion` returns the *run* conclusion and yields 14
`failure` / 3 `cancelled`. The table below is keyed on

```
gh api repos/{owner}/{repo}/actions/runs/{id}/jobs \
  --jq '.jobs[] | select(.name == "Host tests and benchmark gate") | .conclusion'
```

because that is the only job printing harvestable lines. The two WASM-red runs have
a **green** host job and sit in row 1; one run that is `cancelled` at run level has
a failed host job and sits in row 3. Recorded so the audit is re-runnable rather
than merely asserted.

| host job conclusion | runs | corpus rows |
|---|---|---|
| `success` (run red on WASM) | 2 | **92** (46 + 46), one inside the active N=20 window |
| `cancelled` | 2 | **21** (12 + 9), both outside the window |
| `failure` | 13 | **0** — all from the 27.4M era, older than the harvest recipe itself |

Three results, each of which changed the design:

1. **The corpus is clean.** No row traces to a `gate=fail reason=budget_exceeded`
   line. The thirteen runs with a failed host job contributed nothing, because they
   predate the recipe. So there is nothing to clean, and the append-only dilemma
   never arises.
2. **No fork has ever run CI** — 279 of 279 runs are `maldrakar/swift-text-engine`.
   D-7 is latent exactly as the ledger says.
3. **A `conclusion` filter would have been destructive**, not merely coarse: it
   would have discarded 92 sound rows over a WASM SDK failure, including one of the
   twenty runs in the active window.

## Scope

In: the two wrap benchmark modes' timing shape, including the reindex measurement
site's dead-code guard and its duplicated construction (Decision 3) and the two
node-6 tokens `--wrap-compute` is missing; the harvester's run-source check; the
corpus's sixth column and the parser that writes it; the read-time verdict filter
in both consumers; the third cross-language pin; the `AGENTS.md` recipe.

Out: any change to the twelve gated modes' measurement loops; any change to any
budget; any corpus row rewriting or deletion; making a wrap mode gateable; the
window-selection logic.

## Goals

1. Both wrap benchmark modes report numbers that resolve the operation rather than
   the host clock tick, and the shape is readable from the output line itself.
2. The harvester admits rows only from runs whose code is this repository's, and
   fails closed when it cannot tell.
3. The corpus records each row's own gate verdict, so a slow sample is
   distinguishable from a healthy one for the first time.
4. The derivation refuses samples whose own line says the measurement was slow or
   degenerate, in **both** consumers, pinned against each other.
5. Every one of those guards has recorded evidence that it can fail, since reality
   supplies no positive instances.
6. No budget moves. The derivation output is byte-identical before and after.

## Non-Goals

- **Migrating the twelve gated modes onto the shared timing helper.** Any change
  to their measurement loop can shift their numbers, and a shift drags a budget
  re-derivation under the headroom-ceiling rule. The helper serves the wrap modes
  only; consolidation is a separate decision if it is ever wanted.
- **Making the wrap modes gateable or wiring them into CI.** That is map node 6.
  This slice deliberately leaves them absent from `swift-ci.yml` and inert to the
  harvester by output shape.
- **Cleaning the corpus.** The audit found nothing to clean. Even had it not, the
  corpus is append-only and deleting rows would break an invariant worth more than
  this repair.
- **An escape hatch for the provenance rule** (`--allow-failed` or similar). An
  optional policy is not a policy.

## Decisions

### Decision 1 — The timing repair is a shared helper, not the shared summary machinery

Three shapes were considered. **Minimal**: fix the two loops in place, keeping two
hand-rolled measurement bodies — rejected because two hand-rolled loops drifting
apart is exactly how this defect arose. **Structural**: route the wrap modes
through `BenchmarkSummary` + `formatSummary` with a token-prefix parameter —
rejected because `formatSummary` is the printer for twelve blocking gates, pinned
by `WorkflowShapeTests` and the checksum tests, and because it would put
harvestability one wrong default away.

Chosen: a single `amortisedSamples(iterations:operationsPerSample:body:)` in
`BenchmarkSupport.swift`, beside `nanoseconds`, `percentile`, `deterministicIndex`
and `formatSummary`. The wrap modes keep their own `print` statements and their
prefixed tokens. The measurement shape then lives in exactly one place and can be
tested there, and nothing the gates depend on is touched.

### Decision 2 — The division is extracted so that losing it is catchable

`ContinuousClock` cannot be substituted in a unit test, so a test can pin the
loop's **structure** (the body runs `iterations * operationsPerSample` times;
exactly `iterations` samples come back) but not its **arithmetic**. A dropped
division would leave both of those true and silently restore the defect.

So the arithmetic is a separate pure function,
`amortise(elapsedNanoseconds:operationsPerSample:)`, pinned by exact equality.
Removing the division from `amortisedSamples` then reddens a unit test rather than
merely inflating a number nobody re-reads.

### Decision 3 — `reindex_ns` stays unamortised, and says so in the output

`--wrap-compute` times three different things per width. `compute` and `drain` are
repeatable operations and are amortised. `reindex_ns` is a **one-shot O(N) setup**
over 100 000 lines — it is the width-change cost the mode exists to demonstrate,
and averaging it over repetitions would destroy its meaning.

Magnitude is deliberately **not** offered as the discriminator, because it does not
discriminate: measured locally, `drain` runs 4.75-16.4 us — 114-393 ticks, as far
above tick granularity as `reindex_ns` is. What separates them is that one is a
repeatable operation and the other is a setup. Amortising `drain` therefore buys
almost nothing in resolution (one clock read is ~0.3% of a 16 us measurement); it is
amortised for **uniformity of shape**, so node 6 promotes one shape rather than two
and no future reader has to guess why two measurements in one mode are built
differently. Stating this here matters because the rejected rationale is the
plausible one: a reader who believes magnitude is the rule will eventually
"consolidate" `drain` back to a single measurement, or amortise `reindex_ns`.

Because "make every measurement amortised" is a plausible future tidy-up, the
exemption is recorded twice: a comment at the measurement site, and an explicit
token in the printed line, so the shape is visible to a reader of the log rather
than only to a reader of the source. Every measurement names its own count, and
the exemption is a value rather than an absence — `compute_operations_per_sample=256`,
`drain_operations_per_sample=16`, `reindex_operations_per_sample=1`. A missing token
would read as an oversight; a token reading `1` reads as a decision. `drain` walks
the whole buffer per operation, hence the smaller count, following the precedent in
`BulkStructuralMutationBenchmark.swift:66-77`, where the heavy scenarios already use
one.

**Two defects at the reindex measurement site are repaired while it is open.**
`WrapComputeBenchmark.swift:69-72` times `clock.measure { _ = BenchmarkWrapLayout(...) }`,
**discards** the result, and then constructs the same layout a second time for use:
two O(N) passes per width, and the discarded one carries no guard against dead-code
elimination while the far cheaper `drain` immediately below it does carry one
(`if sink == Int.min { print("") }`). The mode's headline measurement is its least
protected. Binding the timed construction and reusing it fixes both in one change —
the second pass disappears and the measured work becomes observably live. This is
in scope precisely because this slice is the one that ratifies keeping `reindex_ns`
unamortised: leaving the measurement unguarded while writing down why it is special
would be the weakest possible combination.

### Decision 4 — Drain's ranges are built outside the clock

`--wrap-compute` measures `compute` and `drain` in the same iteration, and the
`drain` body consumes the `VirtualRange` the `compute` measurement just produced
(`WrapComputeBenchmark.swift:83-94`). `amortisedSamples` hands its body only a
sample index, so routing both through the helper leaves an unstated question with
three answers that measure different things — it is ratified here rather than left
to the plan to discover.

Rejected: computing the range **inside** the drain body. `drain` would then measure
`compute + drain`, contradicting the two independent tokens it prints, and node 6
would gate on the wrong quantity. Rejected: one helper call producing both series —
the signature carries one clock, and widening it to two would put the gates' shape
one parameter away again (Decision 1).

Chosen: the ranges are built into an array **before** the timed loop, and the drain
body indexes it by global operation index. This is not merely the cheapest fit; it
is a repair. Today's drain sample is contaminated by whatever the `compute` call
immediately before it left in cache and branch predictors, while the two tokens
claim to be independent measurements. After this they are.

The array is sized independently of `operationsPerSample`, so a drain sample never
replays one range sixteen times; `deterministicScrollOffset` supplies the offsets,
so the inputs are unchanged and still deterministic.

**This one is reviewed, not machine-checked**, and that is named in Risks: no unit
test can see that the drain body performs no `compute`. What it does get is the
recorded before/after drain numbers, where the contamination it removes is visible.

### Decision 5 — Provenance has two orthogonal axes; `conclusion` is not one of them

The first design filtered runs by conclusion. The user rejected it, and the
objection is the design's foundation, so it is recorded in full:

A gate goes red for **opposite** reasons, and `AGENTS.md` prescribes opposite
responses. `reason=budget_exceeded` means the measurement was slow — the sample
that must not enter the corpus. `reason=budget_stale` means the measurement was
**fast** enough that headroom breached its ceiling, and the prescribed response is
"re-derive the budget", which requires harvesting exactly those samples. A
conclusion filter discards both. It would be a tool that, on `budget_stale`,
instructs the operator to re-derive from fresh evidence and simultaneously refuses
to collect it.

It is also coarse in a way no granularity of *run* can fix: one failing mode out of
twelve fails the job, discarding the other forty-five scenarios' sound rows. The
audit then showed the coarseness is not hypothetical — see Audit above, result 3.

The two axes that survive are orthogonal and are checked at different levels:

- **Source, at run level.** A fork executes its own code and can print
  `gate=pass` beside any number it likes; no per-row check helps. This is D-7 as
  written.
- **Verdict, at row level.** Every summary line carries its own `gate=` and
  `reason=`. Filtering there drops exactly the offending scenario and keeps its
  forty-five siblings.

The row-level rule is **total, not heuristic**, and that was verified: all twelve
CI steps that print harvestable lines run with `--gate` (`swift-ci.yml:92-136`),
and `--memory-shape`/`--memory-observation` print no `p95_ns` at all. Every line
the harvester can take today carries a verdict.

The `conclusion` axis is dropped entirely rather than kept as a third check. After
row-level verdicts it adds nothing — a `swift test` failure means no benchmark
lines were printed at all, and a failed gate step drops its own row — while
costing what the audit measured.

### Decision 6 — The verdict is recorded at harvest and applied at derivation

Two placements were considered. Filtering at harvest keeps the corpus at five
columns and leaves `derive-gate-budgets.sh` untouched, but discards information
permanently: the policy could never be revisited, and an append-only corpus would
silently fail to contain what happened.

Chosen: the harvester writes the verdict as a **sixth column** and the derivation
applies the rule at read time. This is the repository's own established pattern —
the corpus is append-only full history and the N=20 window is applied at read time,
so "what is recorded" and "what is counted" are already separate concepts here.

Migration is seamless in the shell direction: the 3 542 existing rows have no sixth
field, awk reads `$6` as empty, and empty means "legacy, admit".

It is **not** seamless in the Swift direction, and that is a feature.
`GateFloorTests.swift:59-64` reads each row with
`guard columns.count == 5 ... else { XCTFail("malformed corpus row") }`. The moment
a six-column row lands in the corpus, `swift test` goes red. The schema change
therefore *cannot* reach one consumer without the other, and the TDD order is
forced: the Swift reader learns to accept five-or-six columns first, and only then
does the harvester start writing six.

### Decision 7 — The reject set is exactly three reasons

`GateFailureReason` has five cases (`BenchmarkModels.swift:106-112`). They are
classified by what happened to the **measurement**, not by whether the gate passed:

| verdict | measurement | admitted |
|---|---|---|
| `pass` | healthy | yes |
| `budget_exceeded` | slow — the regression-laundering case | **no** |
| `budget_absolute_exceeded` | slow — p99 above the fixed 60 FPS ceiling | **no** |
| `operation_failures` | degenerate — the scenario returned `.empty`/`.failure`, so the timing is of a broken path | **no** |
| `budget_stale` | **fast** — the case whose prescribed response needs this data | **yes** |
| `missing_budget` | valid, merely unjudgeable | yes |
| `none` (line carried no `gate=`) | valid, from a non-gate step | yes |
| absent (legacy five-column row) | unknown | yes |
| `failures=` non-zero, **whatever the verdict says** | degenerate | **no** |

`none` matters beyond back-compatibility: a new mode's **first** hosted evidence
necessarily comes from a step without `--gate`, because its budget does not exist
yet. Admitting verdict-less lines is what lets node 6 bootstrap the wrap gates at
all.

**But degeneracy is read from `failures=`, not from the verdict**, and that closes
a hole the `none` exemption would otherwise open exactly where node 6 lands. A line
printed without `--gate` carries no `gate=`/`reason=` token at all, so a
**degenerate** bootstrap run would be admitted as healthy — and node 6's first
harvest is precisely a bootstrap run. The `operation_failures` row above would
never fire on the one class of line it most needs to.

The signal is already on every line: `formatSummary` prints `failures=N`
unconditionally, **outside** the `includeGate` branch (`BenchmarkSupport.swift:103`).
So `extract_rows()` reads it, and any row whose `failures=` is non-zero is recorded
as `operation_failures` whatever the verdict says. No new vocabulary, no new
consumer logic, and the cross-language pin covers it for free. It agrees with the
gated path by construction: `gateFailureReason` returns `.operationFailures`
whenever `failureCount != 0` and budgets exist.

Reading `failures=` is also strictly stronger than reading the verdict on this axis,
because the verdict can **mask** degeneracy. `gateFailureReason` returns
`.missingBudget` **before** it tests `failureCount` (`BenchmarkModels.swift`), and
`missing_budget` is admitted — so a row that is both budget-less and degenerate,
which is the closest thing to what a bootstrapping new mode produces, reads as
admissible through the verdict and inadmissible through `failures=`. The reject set
stays exactly three reasons; what changes is that a row can reach
`operation_failures` without a gate having run.

The worry that removing the slow tail biases budgets *tight* does not bite, and the
reason is structural: a row is rejected only if it **breached** a budget that is
already at least `3 x max(recent)`, so a rejected sample is not ordinary runner
noise but an outlier beyond three times the recent maximum. Ordinary noise never
breaches. If such a sample recurs, the correct response is a human decision, which
is what a loud rejection produces.

Rows from **cancelled** runs (21 in the corpus today) are not filtered. The numbers
printed before a cancellation are genuine measurements, and cancellation is a
property of the run, not of the measurement — the same reasoning that removed the
`conclusion` axis.

### Decision 8 — Window selection stays verdict-blind

`window_run_ids` is `cut -f1 | sort -rnu | head -n 20`
(`derive-gate-budgets.sh:32-34`) — pure id selection, pinned across languages by
`testWindowSelectionMatchesDeriveScript` and pinned by constant by
`testWindowConstantMatchesDeriveScript`. Teaching it verdicts would require the
Swift `mostRecentRunIDs` to learn them too, or those pins go red.

The verdict filter therefore applies to **row admission**, after windowing, and
neither window pin is touched. A run whose rows are all rejected still consumes a
window slot; that costs at most a slightly thinner sample and is worth the two
untouched invariants.

### Decision 9 — The awk parser is extracted so the new rule can fail

The parser today sits inside the network branch (`harvest-gate-corpus.sh:184-219`),
where `--self-test` cannot reach it. Putting the verdict rule there as-is would
produce a guard with no way to fail — the defect class this slice exists to
prevent.

The awk program moves into a shell function `extract_rows()` reading a log on
stdin, so the self-test can drive it over a fixture. This retroactively brings the
**existing** five-column parser under test for the first time, including the
prefixed-token protection wrap modes rely on (`WrapRowQueryBenchmark.swift:22-27`),
which nothing on the shell side pins today. `ScriptSelfTestTests.swift` already
runs `--self-test` under `swift test`, so the truth table becomes build-failing
with no new infrastructure.

### Decision 10 — Source lookup is one `gh api` call per candidate

Neither `gh run list --json` nor `gh run view --json` exposes the source
repository; their field lists were checked and it is absent from both. The datum
lives at `gh api repos/{owner}/{repo}/actions/runs/{id}` as
`.head_repository.full_name`.

The alternative — switching candidate selection to
`gh api .../workflows/swift-ci.yml/runs?per_page=N`, which returns ids and source
together in one call — is rejected: it rewrites the selection path wholesale, and
the `--runs` entry path would still need per-run lookups, so the policy would have
two implementations. One call per candidate, at `N <= 40`, is not worth a second
code path.

The call is placed **after** the dedup skip and **before** the log fetch,
preserving the existing property that a run already in the corpus costs no API
calls at all.

One further datum was checked and deliberately **not** used. `gh run list --json`
does expose `event`, and a run appearing in *this* repository's run list with
`event != pull_request` cannot have a foreign head repository — so the `gh api`
probe could be skipped for push and dispatch runs at zero extra cost. It is not
taken: it buys nothing that matters (the `--corpus` dedup already leaves only new
runs to probe, at `N <= 40`) and it would give the policy two code paths, which is
the same objection that rejected the selection-path rewrite above. Recorded so the
next reader does not re-open it.

### Decision 11 — `--runs` obeys the same policy

The `--runs id,id` path bypasses even the workflow filter today. Under the new
policy it runs the same source check. This is a deliberate behaviour change to a
documented flag, named here so it is not discovered as a surprise: a caller who
passes an inadmissible id gets a loud `skip=`, not a row.

### Decision 12 — Rejections are loud

Every rejected candidate and every rejected row prints a `skip=` line on stderr
carrying the reason and, for rows, the mode and scenario. Silent filtering is not
better than silent admission: it produces a corpus that looks complete and is not.
The derivation prints its dropped-row counts by reason for the same reason.

## Component Design

**`Sources/ViewportBenchmarks/BenchmarkSupport.swift`**
- `amortise(elapsedNanoseconds:operationsPerSample:) -> Int64` — pure, pinned by
  exact equality.
- `amortisedSamples(iterations:operationsPerSample:body:) -> (samples: [Int64], checksum: Int)`
  — one clock read per iteration, `operationsPerSample` operations inside, division
  via `amortise`. The body receives the global sample index so the existing
  deterministic input generators carry over unchanged.

**`Sources/ViewportBenchmarks/WrapRowQueryBenchmark.swift`**
- Four scenarios move to `iterations = 5_000`, `operationsPerSample = 256`.
- The printed line gains `query_operations_per_sample=`.
- Prefixed latency tokens and the three-field checksum are unchanged.

**`Sources/ViewportBenchmarks/WrapComputeBenchmark.swift`**
- `iterations` stays 2 000; `compute` at 256 operations per sample, `drain` at 16,
  both via the helper, each printing its own `*_operations_per_sample=` token.
- Per Decision 4, a `VirtualRange` array is built **before** the drain loop and
  indexed by global operation index. The drain body performs no `compute`.
- `reindex_ns` stays a single unamortised measurement, with the Decision 3 comment
  and `reindex_operations_per_sample=1` marking it as deliberate rather than
  forgotten — but the timed construction is now **bound and reused** instead of
  discarded and rebuilt, removing the second O(N) pass and making the measured work
  observably live (Decision 3).
- Two tokens are added ahead of node 6, both inert while the latency tokens stay
  prefixed: `scenario=` (the line carries only `width=` today, while both
  `derive-gate-budgets.sh` and `GateFloorTests` group on `mode|scenario`) and
  `drain_p99_ns=` (no gate can be derived from p95 alone). Adding them now lets this
  slice's `extract_rows()` truth table cover the `wrap_compute` line shape end to
  end instead of only its rejection, and reduces node 6's flip to un-prefixing.

**`.github/scripts/harvest-gate-corpus.sh`**
- `extract_rows()` — the awk program, now a function over stdin, emitting six
  columns. It reads `failures=` alongside `gate=`/`reason=` and records
  `operation_failures` whenever `failures=` is non-zero, whatever the verdict says
  (Decision 7).
- `admissible_source()` — pure decision function over (run id, observed repo,
  expected repo), returning `plan=harvest` / `skip=foreign_repo` /
  `skip=provenance_unknown`.
- Network half: one `gh api` per candidate between dedup and log fetch, applied on
  both entry paths.
- `--self-test` gains truth tables for both functions.
- The usage header (lines 14-15) carries the corpus schema and gains the sixth
  column. It is the **only** place the schema is written down — `AGENTS.md` does not
  restate it (see Documentation Updates).

**`.github/scripts/derive-gate-budgets.sh`**
- Main awk skips rows whose `$6` is in the reject set, counting and reporting them.
- New `--admissible-rows` seam, mirroring `--window-run-ids`, printing the rows the
  derivation admits.

**`Tests/ViewportBenchmarksTests/GateFloorTests.swift`**
- The reader accepts five **or** six columns; six-column rows carry a verdict and
  are filtered by the same reject set.
- New `testAdmissibleRowsMatchDeriveScript`, the third cross-language pin.

**`docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`** — untouched
by this slice. No row is rewritten; the column appears only on rows harvested from
now on.

## Testing Strategy

**Timing helper.** Unit tests: the body runs exactly `iterations *
operationsPerSample` times; exactly `iterations` samples are returned; `amortise`
is pinned by exact equality on several pairs, including a case where truncation
matters.

**Harvester self-test.** A fixture log driven through `extract_rows()` must yield:
`gate=pass` → verdict `pass`; `gate=fail reason=budget_exceeded` → that reason;
`gate=fail reason=budget_stale` → that reason; a summary line with no `gate=` →
`none`; a summary line with **no `gate=` and `failures=3`** → `operation_failures`
(the node-6 bootstrap case, Decision 7); a `gate=pass` line carrying `failures=2` →
`operation_failures`, not `pass` (the verdict does not override the count); a
`query_p95_ns=` prefixed wrap line → **no row at all**; a `mode=wrap_compute` line
with its `scenario=` token and prefixed latency tokens → **no row at all**; a
shape-2 relative-observation line → four rows at `none`. Source truth table:
same-repo → `plan=harvest`; foreign repo → `skip=foreign_repo`; empty/unreadable →
`skip=provenance_unknown`.

**Cross-language pin.** `testAdmissibleRowsMatchDeriveScript` drives
`--admissible-rows` over a fixture containing one row of every verdict value —
including a legacy five-column row — and asserts the shell's admitted set equals
the Swift reader's.

**Falsifiability drills, recorded with their observed red.** Reality supplies no
positive instance of either defect, so these are the entire proof:

1. Remove the division from `amortisedSamples` → the `amortise` equality test
   reddens.
2. Remove the source clause from `admissible_source` → the self-test truth table
   reddens.
3. Remove `budget_exceeded` from the reject set → `testAdmissibleRowsMatchDeriveScript`
   reddens.
4. Add `budget_stale` to the reject set → the same pin reddens, proving the rule is
   pinned in both directions rather than only against under-filtering.
5. Make the Swift reader require exactly six columns → the legacy row in the
   fixture reddens, proving the back-compatibility claim is tested rather than
   asserted.
6. Append a synthetic six-column row with `budget_exceeded` to a **copy** of the
   corpus, re-derive, and record that the budget it would have set does not appear
   — the end-to-end demonstration that the chain now refuses a laundered
   regression. The committed corpus is not touched.
7. Remove the `failures=` clause from `extract_rows()` → the self-test's
   degenerate-ungated-line row reddens. This is the drill that matters most, because
   it is the only guard whose gap sits on node 6's own bootstrap path, where no
   verdict token exists to catch it.

**Before/after evidence for D-23.** The claim recorded is the structural one from
Problem: **every** value the two modes print today lies within 1 ns of an integer
multiple of the host tick, and the repaired shape prints values the old shape is
arithmetically incapable of producing. The check is stated as a ratio ("N of N
values are tick multiples before; M of N after"), not as a list of numbers, because
which scenario collapses to `p95 == p99` varies between sweeps. Both full outputs go
in the verification record; no threshold is predicted here.

**Before/after evidence for Decision 4.** The `drain_p95_ns` numbers are recorded on
both sides as well. The de-contamination is not machine-checkable, but a drain
sample no longer preceded by a `compute` call in the same iteration is visible in
the number, and recording it is what makes the claim reviewable at all.

## Benchmark Mode / CI

No new mode, no new flag, no CI step. `--wrap-compute` and `--wrap-row-query`
remain non-gateable and absent from `swift-ci.yml`, and their latency tokens remain
prefixed, so they stay inert to the harvester by output shape as well as by
absence. Node 6 flips both of those, and this slice's whole purpose is that when it
does, the shape underneath is already sound.

## Documentation Updates

`AGENTS.md`, `## Gate budgets` — three edits, and the targets were **checked, not
assumed**:

- "The harvester reads every `p95_ns=` line in a run's log" (in the "Exactly one CI
  step may print a given mode's benchmark summary lines" paragraph, `AGENTS.md:560`)
  becomes every **admissible** line, with admissibility defined mechanically: the
  source axis, the verdict axis, the reject set, the `failures=` rule, and the
  explicit statement that `conclusion` is **not** a criterion and why. Without this
  the text and the script contradict each other, and the next agent will resolve the
  contradiction in favour of the text.
- "A post-harvest `GateFloorTests` failure is `budget_stale`, not an engine
  regression … **do not go hunting for a slowdown in the core**" gains the
  qualification this slice earns: it holds *because* a slow sample can no longer
  enter the corpus. Until this slice that sentence was indistinguishable from an
  instruction to launder a regression — it is the most dangerous line in the
  section, which is why Problem quotes it, and it must not be left unedited.
- The reject set and the `failures=` rule are stated once beside the recipe, so the
  two consumers and the prose agree.

**Corrections to what this section first claimed.** Two named targets do not exist,
and an acceptance criterion aimed at either would have passed vacuously:

- The rule "harvest EVERY available hosted run, not a convenient subset" is **not**
  in `AGENTS.md`. It is a comment at `harvest-gate-corpus.sh:175` and a line in two
  completed plans. The script comment is updated in place; the plans are history and
  are not rewritten.
- `AGENTS.md`, `## Commands` documents **no** corpus schema — `grep run_id
  AGENTS.md` returns nothing. The schema lives in the harvester's usage header,
  which is where the sixth column is added (see Component Design).

The two wrap benchmark entries in `## Commands` note the amortised shape.

## Verification

Recorded with actual output in
`docs/superpowers/verification/2026-08-23-calibration-chain-hardening.md`:

- `swift test`, `swift build -c release`, the Foundation-free scan.
- The same scan over `Sources/ViewportBenchmarks`, which this slice adds code to.
  Its Foundation-freeness is convention-only: the committed scan covers
  `Sources/TextEngineCore` alone, and `cross-target-compile.sh` does not compile the
  benchmark target (its one mention of `ViewportBenchmarks` is a self-test fixture
  string). Not a new invariant — a one-line check that the new helper does not
  quietly become the first exception.
- All four scripts' `--self-test`.
- `--wrap-row-query` and `--wrap-compute` before and after.
- `derive-gate-budgets.sh <corpus>` before and after, diffed — **must be empty**.
- All twelve `--gate` modes, expecting 46 `gate=pass` and no budget movement.
- The six drills with their observed red.
- Hosted proof at step level on both the PR-head and the post-merge run.

**Plan-assertion note.** Per D-17, `${PIPESTATUS[0]}` must not appear in this
slice's plan: agent command blocks run under zsh, where it expands empty and
`[ "" -eq 0 ]` evaluates **true**, inverting a failed assertion into a pass. Use
`if ! cmd; then` or avoid the pipe.

## Acceptance Criteria

1. `amortisedSamples` exists in `BenchmarkSupport.swift` and both wrap modes use
   it; the twelve gated modes' measurement loops are **unchanged**, verified by
   diff.
2. `amortise` is a separate pure function pinned by exact equality, and drill 1
   records its red.
3. `--wrap-compute`'s `reindex_ns` remains a single unamortised measurement, marked
   as such in both the source and the printed line — and the layout is constructed
   **once**: the timed construction is the one used, so the second O(N) pass is gone
   and the measured work is observably live (Decision 3).
4. Every measurement in both wrap modes prints its own `*_operations_per_sample=`
   token: `query_`, `compute_` and `drain_` greater than 1, and `reindex_` exactly
   1 (Decision 3 — the exemption is stated as a value, not an absence). The
   before/after outputs are recorded.
5. `--wrap-compute` builds its drain ranges **before** the timed loop and the drain
   body performs no `compute` (Decision 4), verified by reading the diff; the
   before/after `drain_p95_ns` numbers are recorded. This criterion is deliberately
   not machine-checked — see Risks.
6. `--wrap-compute` prints `scenario=` and `drain_p99_ns=`, and both modes' latency
   tokens stay prefixed, so neither line yields a corpus row.
7. `harvest-gate-corpus.sh` rejects a run whose source repository is not this one,
   fails closed when the source cannot be determined, and applies the same check on
   the `--runs` path.
8. The parser is extracted into `extract_rows()` and its truth table — including
   the previously-unpinned prefixed-token protection and the `wrap_compute` line
   shape — passes under `--self-test`, which `swift test` drives.
9. The harvester writes a sixth verdict column on **every** row it emits
   (`pass`, a reason, or `none`); the readers additionally accept legacy
   five-column rows, which no harvest produces and which the committed corpus
   consists entirely of (AC13).
10. A row whose `failures=` is non-zero is recorded as `operation_failures`
    regardless of its verdict — including on a line with no `gate=` at all — with
    drill 7 recording the red (Decision 7).
11. `derive-gate-budgets.sh` and `GateFloorTests` apply the identical reject set
    `{budget_exceeded, budget_absolute_exceeded, operation_failures}`, pinned by
    `testAdmissibleRowsMatchDeriveScript`, with drills 3 and 4 recording reds in
    **both** directions.
12. The Swift reader accepts five-or-six-column rows, with drill 5 recording the red
    that proves it.
13. **No budget moves**: `derive-gate-budgets.sh` output over the committed corpus
    is byte-identical before and after, all 46 budgets reproduce, and the committed
    corpus file is untouched.
14. Neither wrap mode becomes gateable or appears in `swift-ci.yml`.
15. `AGENTS.md:560` and the `budget_stale` paragraph no longer describe a harvest the
    script refuses, and the harvester's usage header carries the sixth column. The
    two targets this design originally named do not exist and are not asserted
    against (see Documentation Updates).
16. All seven drills are recorded with observed red output.
17. Hosted proof at step level on both the PR-head and post-merge runs: three jobs,
    twelve gates, 46 `gate=pass`.

## Risks And Gaps

**Both guards are preventive and will stay untested by reality.** No fork has run
CI; no contaminated row exists. Their only evidence is synthetic, which is why the
drills are acceptance criteria rather than implementation detail. If a future
reader wants to know whether these work, the drills are the answer and the corpus
is not.

**The reject set now lives in two languages.** The cross-language pin covers
agreement, not correctness: if both sides gain the same wrong entry, nothing
notices. This is the same residual the two window pins carry and is accepted on the
same terms.

**A run whose rows are all rejected still consumes a window slot** (Decision 8).
Accepted to keep the window pins untouched; the cost is at most a thinner sample in
a pathological case that has never occurred.

**`operation_failures` is rejected on reasoning, not measurement.** No such row
exists to inspect. The argument — that the timing of a degenerate path measures
nothing useful — is sound but unvalidated, and it is flagged here rather than
buried.

**Decision 4 is reviewed, not machine-checked.** No unit test can see that the drain
body performs no `compute`: `amortisedSamples`' structural test pins the body's call
count, and a body that computed a range inside itself would satisfy it. The guards
are a diff read and the recorded before/after `drain_p95_ns`. Named here because
every other guard in this slice has a drill and this one does not.

**A scenario could lose all its in-window evidence.** The verdict filter is applied
after windowing (Decision 8), so if every windowed run's rows for one scenario were
rejected, `GateFloorTests` would fail with "no hosted evidence" — correct behaviour,
but a message that points at the corpus rather than at the rejections that emptied
it. It needs all twenty window runs to fail the same scenario, so it has never been
close to happening; the derivation's per-reason dropped-row counts (Decision 12) are
what would explain it.

**The audit window is what the API still carries** (279 runs). Runs older than that
cannot be checked — but every corpus run is inside it, verified rather than assumed:
the corpus's oldest run id is `28236592208` and the audited range reaches back to
`27032642312`. So the "corpus is clean" result covers the whole corpus, not a
recent slice of it.

## Future Slices (arc map, for reference)

Node 4 (point→(row, cell)) remains the lean for the next feature slice, carrying
D-24 and D-25. Node 6 is the consumer of everything this slice builds: it flips the
prefixed tokens to the bare shape, adds the CI steps, harvests the first wrap rows
— which will arrive with verdicts and provenance — and derives the first wrap
budgets. D-20/D-21 are the rows to read when it does.
