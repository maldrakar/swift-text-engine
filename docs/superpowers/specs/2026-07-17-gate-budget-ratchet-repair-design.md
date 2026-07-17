# Gate Budget Ratchet Repair Design

Slice 41. Date: 2026-07-17.

## Status

Design. Supersedes no prior spec. Consumes the **Slice 40 post-slice review's P2 #1**
(the `3× max` floor over an append-only corpus is a latent one-way ratchet) and the
**Slice 39 review's** explicit instruction not to let that fix slip — deferred by an
authorized user decision from Slice 40 to here, with the standing condition that it be
"scoped against fresh evidence, not the original brief."

## Source Context

Slice 38 recalibrated every gate budget from hosted evidence, folding a `3× max` floor
**into** the derivation recipe so a gate can no longer be born inert. Slice 40 promoted
the last query gate (`--point-geometry-query`) to blocking and, in doing so, re-derived
every budget from a freshly harvested corpus.

That harvest exposed the defect this slice repairs. The corpus
(`docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`) is **append-only** —
the run id is its dedup key and rows are never removed. `GateFloorTests` and
`derive-gate-budgets.sh` both compute `max(hosted)` over the **entire** corpus. In an
append-only corpus, `max` can only ever rise. A budget derived from it can therefore only
ever loosen. Left alone, this walks the whole suite back toward the 815×–3,000× inert
state Slice 38 cured — slowly, one freak runner-noise sample at a time.

## Problem

The brief's success criterion is *«Регрессионные бенчмарки блокируют merge при деградации
производительности»*. A gate that can only loosen eventually blocks nothing. This slice
stops the loosening from being **one-way**.

### The mechanism

Two distinct red conditions depend on `max(hosted)`, and they are not the same failure:

- **Runtime `--gate` flake** — the CI gate step compares the committed budget against
  *this* run's live p95/p99. It reddens if the run is slower than the budget. Protection:
  keep the budget comfortably above the worst plausible single-run sample. Higher floor =
  safer.
- **`GateFloorTests` flake** — `swift test` (itself a blocking gate) re-reads the
  committed corpus and asserts `budget ≥ 3 × max(corpus)`. It reddens when a **harvest**
  appends a sample worse than the committed budget ÷ 3. Because the corpus never forgets,
  the only cure under today's rule is to raise the budget — permanently.

The floor is doing real work for the first condition: these are sub-100 ns operations on a
shared CI runner, and their p99 tails are set by scheduling preemption, not by the
algorithm. A spike **will** recur, so the gate genuinely needs headroom above it. The
defect is not that the floor exists — it is that, anchored to the all-time worst sample,
the floor **only ratchets up**. Budgets can never come back down when the noise subsides.

### Current evidence — the at-floor cluster

Re-measured for this design from the committed corpus (47 runs). Five gated scenarios sit
at **exactly the 3.0× floor**, each pinned by a single freak spike that dwarfs its own
median:

| Scenario | Stat | median → **max** | budget | margin | freak-run recency |
| --- | --- | --- | --- | --- | --- |
| `line_query\|uniform_100k` | p95 | 34 → **92** | 280 | 3.0× | rank 38/47 (old) |
| `line_query\|uniform_1k` | p95 | 24 → **73** | 220 | 3.0× | rank 18/47 (mid) |
| `line_geometry_query\|uniform_1k` | p99 | 62 → **330** | 990 | 3.0× | rank 22/47 (mid) |
| `line_geometry_query\|uniform_1m` | p99 | 79 → **265** | 800 | 3.0× | rank 22/47 (same run) |
| `column_query\|uniform_100k` | p99 | 67 → **204** | 620 | 3.0× | rank 6/47 (recent) |

On a clean tree these pass (both budget and corpus are committed). The latent flake is:
the next harvest that raises any of these maxima by ~1 ns flips `GateFloorTests` red with
no code change, and the only sanctioned response — re-derive — makes the budget looser,
never tighter. That is the one-way ratchet, made concrete.

The freak spikes are **not** all old: one is at recency rank 6 of 47. That single fact
rules out "just re-derive once and move on" — the ratchet is structural and must be fixed
in the mechanism, not the numbers.

## Scope

**In scope** — the calibration machinery only:

- `derive-gate-budgets.sh` — derive `median`/`max` over a **trailing window** of the most
  recent N runs, not all history; add a `--self-test` for the window selection.
- `GateFloorTests.swift` — apply the **identical** window when computing the corpus
  extremes it holds budgets to; extract a testable window-selection helper with a fixture
  unit test.
- Harvest Slice 40's post-merge push run into the corpus (fresh evidence), then
  **re-derive every budget** under the window and commit the re-derived literals.
- `AGENTS.md` `## Gate budgets` — document the window and its rationale; update the
  `GateFloorTests` description.
- Fold in the two trivial opportunistic items the Slice 40 review flagged for a docs pass
  that touches `## Gate budgets` (P3 #1, P3 #2 below), since this slice edits those files.

**Not in scope:**

- **Any change to `Sources/TextEngineCore` or `Sources/TextEngineReferenceProviders`.**
  This slice changes no engine or provider behavior. Expected diff there: **zero lines**.
- **Outlier rejection** (drop samples beyond `k × median`). It would clear the at-floor
  cluster regardless of recency, but by lowering the floor below the worst observed sample
  it reintroduces the runtime `--gate` flake the floor exists to prevent (these p99 tails
  recur). Considered and rejected — see Decision 2.
- **A corpus retirement/curation column.** Heavier, per-row human judgment, and a standing
  invitation to hand-retire inconvenient samples — the exact discipline this machinery
  exists to enforce. Rejected as the heaviest lever for the lightest need.
- **The absolute/product budget** (Slice 38 Option C, still unclaimed). It is the eventual
  backstop against *legitimate* slow drift, and is best added **after** this slice stops
  the upward drift, not before. A later slice.
- **Harvester provenance hardening** and **generalizing `WorkflowShapeTests`** to every
  gated mode (Slice 40 review Options C, D). Separate concerns, separate slices.
- Changing the gate statistic (p95/p99 stay), the recipe factors (`8×`, `3×`, `2×` stay),
  new scenarios, new modes, new providers.

## Goals

1. The floor becomes **two-way**: an old freak sample ages out of the window, so a
   scenario's budget can *tighten* again once the noise that inflated it subsides.
2. `derive-gate-budgets.sh` and `GateFloorTests` compute their sample set by the **same
   documented rule**, pinned by a test so they cannot drift.
3. Every gated budget re-derives byte-for-byte from the windowed corpus — the
   "derived, never hand-typed" invariant is preserved across the whole suite.
4. No engine or provider behavior changes; every gate checksum stays byte-identical.

## Non-Goals

**Forcing every scenario off the 3.0× floor.** The window ages out the *old* freaks (3 of
the 5 above), but the recent `column_query|uniform_100k` spike (rank 6) legitimately stays
inside any reasonable window and **correctly** holds that budget up — the runtime gate
must survive a spike observed six runs ago. The deliverable is a floor that *can* release,
not one that is forced low. Whether a given scenario reads 3.0× or 6.8× on the day is a
consequence of its recent evidence, which is exactly what a regression floor should track.

**Eliminating the `GateFloorTests` red-on-harvest entirely.** A harvest that appends a
sample worse than everything in the current window still, correctly, reddens the test —
that is the test reporting "the committed budget no longer clears recent worst-case,
re-derive." The change makes that signal **self-healing** (the budget comes back down when
the spike leaves the window) rather than a permanent ratchet. It does not, and should not,
silence it.

## Decisions

### Decision 1 — Trailing window over the most recent N runs

Both consumers restrict their sample set to the **N most recent distinct run ids** in the
corpus, then compute `median` and `max` over only the rows belonging to those runs.

The chronological key is the **run id itself**. GitHub's `databaseId` is monotonic with
run creation time, so "most recent N" is `sort -rnu | head -N` — pure integer arithmetic,
no timestamps, nothing that touches Foundation or strains Embedded Swift. The corpus's
physical row order (harvest-batch order) is irrelevant; only the run-id ranking matters, so
the two languages that read the corpus (awk, Swift) reach the identical window without
sharing code.

This is the lightest lever that makes the floor two-way: as new runs are appended, the
oldest run leaves the window, and if it held the current max, the windowed max **drops** —
which no all-history rule can ever do.

### Decision 2 — Why the window, not outlier rejection or retirement

Outlier rejection was the tempting alternative because it clears all five at-floor
scenarios at once. It is rejected because it **erodes gate safety**. The corpus stores one
`(p95, p99)` pair per run — each already a within-run tail statistic. A p99 of 330 ns
means that run's 99th-percentile iteration genuinely took 330 ns under scheduling
interference. That interference recurs (~1 in 40 runs here). If the budget is derived by
*rejecting* that sample, a future run reproducing it trips the runtime `--gate` — the flake
the floor exists to prevent. With strict required checks, a flaking gate blocks every PR.
The floor's headroom above the worst *observed* sample is load-bearing; the window bounds
how far back "observed" reaches without ever pretending a real spike did not happen.

Retirement (a `retired` column + policy) is rejected as the heaviest option for the
lightest need, and because per-row human curation is a backdoor to hand-tuning budgets.

### Decision 3 — The window is applied in lockstep, and the review's "derive alone" is corrected

The Slice 40 review floated "a documented trailing-window in `derive-gate-budgets.sh`
alone." That is not sufficient. `GateFloorTests` **independently** recomputes `max` over
the corpus and asserts `budget ≥ 3 × max`. If only the derive script windows, it produces
a *tighter* budget that the still-un-windowed floor test then **rejects**. The window must
live in **both** consumers, computed identically.

The asymmetry of a constant mismatch is worth stating: if the test's N were ever larger
than the derive script's N, the test's max would be `≥` the derive script's, and the test
would fail **loudly** — caught. If smaller, it passes silently with a budget looser than
the test verifies. So the pairing is partially self-guarding but not fully; the mitigation
is a single documented N in `AGENTS.md` that both sites cite, plus the verification record
showing (a) `derive` reproduces every committed literal and (b) `GateFloorTests` is green —
which can both hold only if the two windows agree.

### Decision 4 — N = 20

Twenty most-recent runs. Rationale, all verified against the committed corpus:

- **No mode is starved of evidence.** At N=20 every mode keeps ≥ 11 distinct runs
  (`point_geometry_query` has only 11 runs in all of history, all recent, so it is fully
  retained; everything else keeps 20). At N=15 the minimum is still 11. There is no window
  in play that drops a gated scenario to zero corpus rows.
- **Statistically ample.** Twenty samples per scenario (eleven for the newest mode) is a
  stable base for a lower-median and a max.
- **Recent enough to release.** Twenty runs is roughly the last ~15 slices of hosted
  evidence. It ages out the two mid-rank freaks (rank 22: `line_geometry_query`
  `uniform_1k`/`uniform_1m`) and the old one (rank 38: `line_query|uniform_100k`),
  relieving three of the five at-floor scenarios; it retains the rank-18 and rank-6 freaks,
  which is correct (recent evidence).

N is a documented, re-tunable constant, not a magic number. It is stated once in
`AGENTS.md` and cited by both consumers.

The measured effect of N=20 on the cluster (current committed corpus, before this slice's
own harvest of run `29606487287`; illustrative — the shipped literals are re-derived after
that harvest):

| Scenario (stat) | all-history margin | N=20 margin | what changed |
| --- | --- | --- | --- |
| `line_geometry_query\|uniform_1k` (p99) | 3.0× | **6.2×** | 330 (rank 22) ages out; budget 990 → 500 |
| `line_geometry_query\|uniform_1m` (p99) | 3.0× | **6.8×** | 265 (rank 22) ages out; budget 800 → 760 |
| `line_query\|uniform_100k` (p95) | 3.0× | **3.7×** | 92 (rank 38) ages out |
| `line_query\|uniform_1k` (p95) | 3.0× | 3.0× | 73 (rank 18) still in window — persists |
| `column_query\|uniform_100k` (p99) | 3.0× | 3.0× | 204 (rank 6) recent — correctly holds |

### Decision 5 — Harvest fresh evidence first, then window, then re-derive every mode

Slice 40's post-merge push run `29606487287` — the authoritative merged-code proof,
bit-identical checksums per the Slice 40 review — is **not yet in the corpus** (the corpus
newest is `29426572267`, Slice 39's post-merge run). Per the standing "anchor proof in the
post-merge push run" discipline and the "scope against fresh evidence" instruction, this
slice harvests it (idempotently, via `--corpus`) before deriving.

Then **every** budget is re-derived under the window and re-committed, not just the five in
the cluster. A mechanism change to the sample set moves `median`/`max` for scenarios this
slice never reasoned about; deriving only the cluster would leave the rest silently *not
reproducing* from the committed corpus — the exact "derived, never hand-typed" breakage the
Slice 39 partial sweep caused. Sweep all modes; commit whatever `derive` prints.

## Implementation Architecture

### `derive-gate-budgets.sh`

The awk program gains a first pass that ranks distinct run ids and keeps the top N, and its
main pass skips rows outside that set. N is a shell variable (`WINDOW=20`) with a comment
pointing at `AGENTS.md`. A `--self-test` mode (mirroring `harvest-gate-corpus.sh`'s) drives
the selection over a fixture corpus with runs of known recency and asserts the kept set —
no network, runnable in CI or locally.

### `GateFloorTests.swift`

`loadCorpus()` gains a window step: collect distinct run ids (parsed as `Int64`), sort
descending, keep the first N, and fold only rows in that set into `CorpusExtremes`. The
selection is extracted into a free function — `mostRecentRunIDs(_ ids:, limit:) -> Set<Int64>`
or equivalent — so a new fixture-based unit test can exercise it directly (ranking, the
`limit ≥ count` no-op case, ties are impossible since ids are distinct). `windowSize = 20`
is a named constant with the same `AGENTS.md` pointer. Foundation stays a test-target-only
import, as today.

### Budgets (data, not logic)

`Sources/ViewportBenchmarks/*Benchmark.swift` budget literals are replaced with the
windowed re-derivation's output. **No logic changes** in `ViewportBenchmarks` — `passesGate`,
`formatSummary`, the ceiling, the scenario tables' shapes are all untouched. The runtime
`--gate` step reads these literals exactly as before; only the numbers move, and they move
because the evidence rule changed, not by hand.

### Documentation

`AGENTS.md` `## Gate budgets` — the recipe gains the window definition ("`hosted` = the
most recent N=20 distinct runs, keyed on run id") and the rationale (stop the one-way
ratchet; both consumers apply it identically). The `GateFloorTests` description in the
package-layout section is updated to say it holds budgets to `3× the windowed max`. P3
folds: correct the `Tests/ViewportBenchmarksTests` file list to include
`PointGeometryChecksumTests.swift` and `PointGeometryQueryOptionsTests.swift` (P3 #1), and
tidy the `WorkflowShapeTests` comment whose "continue-on-error"-rationale now points at a
deleted block (P3 #2).

### Verification record

`docs/superpowers/verification/2026-07-17-gate-budget-ratchet-repair.md` — the corpus
append (numstat + the harvested run id), the full before/after budget table under the
window, the `derive` reproduces-every-literal check, `swift test` output including the new
window unit test red→green, all eleven gates green locally, and the hosted PR-head and
post-merge push run IDs read at step level.

## Testing Strategy

This slice changes no engine code, so the existing tests must pass **unchanged** and every
gate checksum must be **byte-identical** to the Slice 40 baseline. That byte-identity is
the proof that the calibration change moved no measured path.

Test-first, per the project's TDD norm:

1. **Window selection unit test** (new, in `ViewportBenchmarksTests`). Over a fixture set
   of run ids with known recency: `mostRecentRunIDs` keeps exactly the top N; keeps all
   when `limit ≥ count`; keeps N when there are more. Red before the helper exists / before
   `loadCorpus` calls it, green after. This is the guard that the two consumers' windows
   agree in shape.
2. **`derive-gate-budgets.sh --self-test`** — the shell mirror of (1): the awk window keeps
   the same set the Swift helper does, over the same fixture recency. Red before the window
   pass is added, green after.
3. **`GateFloorTests` passes against the windowed budgets** — every gated scenario clears
   `3 ×` the **windowed** max on both statistics. This is the existing floor test, now
   reading the windowed corpus; it must stay green after re-derivation.
4. **`derive` reproduces every committed literal** — run with no mode argument over the
   post-harvest corpus; diff against every budget constant; zero mismatches (recorded, not
   asserted).

## Acceptance Criteria

1. `swift test` — all existing tests pass, plus the new window-selection unit test, green
   on hosted Linux, not only locally.
2. `git diff --name-only` shows **no path under `Sources/TextEngineCore` or
   `Sources/TextEngineReferenceProviders`**.
3. `derive-gate-budgets.sh --self-test` passes; the derive script and `GateFloorTests` use
   the same documented N, and every committed budget re-derives byte-for-byte from the
   windowed corpus (shown in the verification record).
4. All eleven `--gate` modes report `gate=pass` locally, and all query/mutation checksums
   are byte-identical to the Slice 40 baseline.
5. The corpus carries Slice 40's post-merge push run `29606487287`; the append is shown as
   an append-only numstat in the verification record.
6. **The floor is demonstrably two-way**: with a synthetic freak sample appended to the
   corpus fixture, `GateFloorTests`/`derive` compute the *inflated* max, and once that run
   falls outside the N-window the computed max **drops back** — shown, not asserted.
7. `AGENTS.md` states the window (N=20, run-id key), its rationale, that both consumers
   apply it identically, and carries the two P3 doc corrections.
8. Hosted: all eleven gates green on the PR head and on the post-merge push run, read at
   step level (a `continue-on-error` step can conclude a job green while its own step
   failed).

## Risks And Gaps

### The two N constants can drift across languages

N lives once in awk and once in Swift; no single source pins them. Mitigated by Decision 3's
asymmetric self-guard (a test-N larger than derive-N fails loudly), the single documented
value in `AGENTS.md`, and the AC3 requirement that both the reproduce-every-literal check
and `GateFloorTests` be green — which can only co-hold if the windows agree. A test that
reads `WINDOW=` out of the shell script (à la `WorkflowShapeTests`) would close it fully;
recorded as an option the plan may take if it proves cheap, not mandated, to keep the slice
light.

### A window still reddens `GateFloorTests` on a genuinely-worse harvest

By design (Non-Goals). The difference from today is that the red is now **self-healing**:
re-derive, and when the spike ages out the budget tightens again, instead of ratcheting up
forever. The slow-drift backstop — an absolute product budget that never recalibrates —
remains unbuilt (Slice 38 Option C), and is the correct next lever *after* this one.

### N could age out evidence for a mode that stops being exercised

If a gated mode were dropped from CI, a recency window would eventually starve it of corpus
rows and `testEveryGatedScenarioHasCorpusEvidence` would fire. Today every gated mode runs
on every hosted run, so no scenario is within an order of magnitude of starvation at N=20
(min 11 runs). Recorded as a property to preserve: adding a gate without running it every
hosted run would surface here first — which is the test doing its job.

### Standing items unchanged

WASM stays observational; the realistic-provider observation stays PR-only
`continue-on-error`; the harvester still selects by run id alone (provenance hardening is a
separate slice); the `Main` ruleset keeps its documented bypass-actor shape.

## Evidence

At-floor cluster and freak-run recency: measured for this design with
`derive-gate-budgets.sh` over the committed corpus and a run-id recency ranking (§Problem
tables). No-starvation and N=20 windowed-budget figures: computed by a windowed variant of
the derive recipe over the same corpus (§Decision 4 table). All figures are reproducible
from the committed corpus; the **shipped** budgets are whatever
`./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
(windowed) prints after Slice 40's post-merge run is harvested, and `GateFloorTests` fails
the build if any table drifts from that evidence.

## Recommended Next Step

With the upward drift stopped, the natural successor is **Slice 38 Option C — the absolute
product budget**: a fixed per-scenario ceiling (the brief's "60 FPS → measurable headless
budget", e.g. the 1 µs line every query scenario's p99 already clears) that never
recalibrates, catching the *legitimate* slow drift a median-anchored regression budget can
always re-derive around. It is explicitly best done after this slice, and closes the last
gap the Slice 38 design left on the record.
