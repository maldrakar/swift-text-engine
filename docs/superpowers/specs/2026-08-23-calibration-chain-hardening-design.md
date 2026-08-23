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
4 and 5 with the evidence that settled them.

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
release, the wrap output is quantised to the host clock tick (≈41.7 ns: the
reported 83/167/250/292 ns are 2/4/6/7 ticks) and `uniform_1k` collapses to
`p95 == p99`, while the gated siblings this query belongs beside measure 17-94 ns
— below one tick. A budget derived from these numbers would be a budget on clock
overhead.

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
committed corpus:

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

In: the two wrap benchmark modes' timing shape; the harvester's run-source check;
the corpus's sixth column and the parser that writes it; the read-time verdict
filter in both consumers; the third cross-language pin; the `AGENTS.md` recipe.

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
its magnitude puts it far above tick granularity, and averaging it over repetitions
would destroy its meaning.

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

### Decision 4 — Provenance has two orthogonal axes; `conclusion` is not one of them

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

### Decision 5 — The verdict is recorded at harvest and applied at derivation

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

### Decision 6 — The reject set is exactly three reasons

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

`none` matters beyond back-compatibility: a new mode's **first** hosted evidence
necessarily comes from a step without `--gate`, because its budget does not exist
yet. Admitting verdict-less lines is what lets node 6 bootstrap the wrap gates at
all.

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

### Decision 7 — Window selection stays verdict-blind

`window_run_ids` is `cut -f1 | sort -rnu | head -n 20`
(`derive-gate-budgets.sh:32-34`) — pure id selection, pinned across languages by
`testWindowSelectionMatchesDeriveScript` and pinned by constant by
`testWindowConstantMatchesDeriveScript`. Teaching it verdicts would require the
Swift `mostRecentRunIDs` to learn them too, or those pins go red.

The verdict filter therefore applies to **row admission**, after windowing, and
neither window pin is touched. A run whose rows are all rejected still consumes a
window slot; that costs at most a slightly thinner sample and is worth the two
untouched invariants.

### Decision 8 — The awk parser is extracted so the new rule can fail

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

### Decision 9 — Source lookup is one `gh api` call per candidate

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

### Decision 10 — `--runs` obeys the same policy

The `--runs id,id` path bypasses even the workflow filter today. Under the new
policy it runs the same source check. This is a deliberate behaviour change to a
documented flag, named here so it is not discovered as a surprise: a caller who
passes an inadmissible id gets a loud `skip=`, not a row.

### Decision 11 — Rejections are loud

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
- `compute` at 256 operations per sample, `drain` at 16, both via the helper, each
  printing its own `*_operations_per_sample=` token.
- `reindex_ns` unchanged, with the Decision 3 comment and
  `reindex_operations_per_sample=1` marking it as a deliberate single unamortised
  measurement rather than a forgotten one.

**`.github/scripts/harvest-gate-corpus.sh`**
- `extract_rows()` — the awk program, now a function over stdin, emitting six
  columns.
- `admissible_source()` — pure decision function over (run id, observed repo,
  expected repo), returning `plan=harvest` / `skip=foreign_repo` /
  `skip=provenance_unknown`.
- Network half: one `gh api` per candidate between dedup and log fetch, applied on
  both entry paths.
- `--self-test` gains truth tables for both functions.

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
`none`; a `query_p95_ns=` prefixed wrap line → **no row at all**; a shape-2
relative-observation line → four rows at `none`. Source truth table: same-repo →
`plan=harvest`; foreign repo → `skip=foreign_repo`; empty/unreadable →
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

**Before/after evidence for D-23.** The current
`wrap_row_query|uniform_1k` numbers are integer multiples of the ≈41.7 ns tick with
`p95 == p99`. The repaired shape can print values the old shape is arithmetically
incapable of producing. Both outputs go in the verification record; the exact
post-repair threshold is recorded from the measurement, not predicted here.

## Benchmark Mode / CI

No new mode, no new flag, no CI step. `--wrap-compute` and `--wrap-row-query`
remain non-gateable and absent from `swift-ci.yml`, and their latency tokens remain
prefixed, so they stay inert to the harvester by output shape as well as by
absence. Node 6 flips both of those, and this slice's whole purpose is that when it
does, the shape underneath is already sound.

## Documentation Updates

- `AGENTS.md`, `## Gate budgets`: the rule "harvest EVERY available hosted run, not
  a convenient subset" becomes "every **admissible** run", with admissibility
  defined mechanically (source axis, verdict axis, the reject set, and the explicit
  statement that `conclusion` is **not** a criterion and why). Without this the text
  and the script contradict each other, and the next agent will resolve the
  contradiction in favour of the text.
- `AGENTS.md`, `## Commands`: the corpus schema gains its sixth column.
- The two wrap benchmark entries note the amortised shape.

## Verification

Recorded with actual output in
`docs/superpowers/verification/2026-08-23-calibration-chain-hardening.md`:

- `swift test`, `swift build -c release`, the Foundation-free scan.
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
   as such in both the source and the printed line.
4. Every measurement in both wrap modes prints its own `*_operations_per_sample=`
   token: `query_`, `compute_` and `drain_` greater than 1, and `reindex_` exactly
   1 (Decision 3 — the exemption is stated as a value, not an absence). The
   before/after outputs are recorded.
5. `harvest-gate-corpus.sh` rejects a run whose source repository is not this one,
   fails closed when the source cannot be determined, and applies the same check on
   the `--runs` path.
6. The parser is extracted into `extract_rows()` and its truth table — including
   the previously-unpinned prefixed-token protection — passes under `--self-test`,
   which `swift test` drives.
7. Harvested rows carry a sixth verdict column with the three-way distinction
   (`pass`/reason, `none`, absent-for-legacy).
8. `derive-gate-budgets.sh` and `GateFloorTests` apply the identical reject set
   `{budget_exceeded, budget_absolute_exceeded, operation_failures}`, pinned by
   `testAdmissibleRowsMatchDeriveScript`, with drills 3 and 4 recording reds in
   **both** directions.
9. The Swift reader accepts five-or-six-column rows, with drill 5 recording the red
   that proves it.
10. **No budget moves**: `derive-gate-budgets.sh` output over the committed corpus
    is byte-identical before and after, all 46 budgets reproduce, and the committed
    corpus file is untouched.
11. Neither wrap mode becomes gateable or appears in `swift-ci.yml`; both keep
    prefixed latency tokens.
12. `AGENTS.md` no longer instructs a harvest that the script refuses.
13. All six drills are recorded with observed red output.
14. Hosted proof at step level on both the PR-head and post-merge runs: three jobs,
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

**A run whose rows are all rejected still consumes a window slot** (Decision 7).
Accepted to keep the window pins untouched; the cost is at most a thinner sample in
a pathological case that has never occurred.

**`operation_failures` is rejected on reasoning, not measurement.** No such row
exists to inspect. The argument — that the timing of a degenerate path measures
nothing useful — is sound but unvalidated, and it is flagged here rather than
buried.

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
