# Gate Budget Recalibration Design

Slice 38. Date: 2026-07-12.

## Status

Design. Supersedes no prior spec. Consumes the Slice 37 post-slice review's **P2 #1**
(the `--point-query` gate is inert as a regression detector) and the user's
2026-07-11 decision that gate-budget calibration warrants a dedicated slice.

## Source Context

The Slice 37 review recorded that the new `--point-query` gate passes with ~4,000×
headroom, and that the same looseness affects every query gate. It recommended this
slice (**Option C**) *before* the mechanical promotion of `--point-query` (**Option
A**), on the grounds that promoting a gate that cannot fail buys a green checkmark,
not protection.

Investigation for this design confirmed the review's diagnosis, found its **root
cause**, and found **one gate the review did not name**.

## Problem

### The three tiers

Measured hosted-Linux headroom (`budget_p95 ÷ median observed p95`), from 190
gate-line samples harvested across 25 hosted runs between 2026-07-04 and 2026-07-11:

| Gate group | Scenarios | Hosted headroom | Verdict |
| --- | --- | --- | --- |
| 4 query gates in CI + `--point-query` | 20 (+4 point, no hosted history) | **815× – 3,000×** | inert |
| `--variable-height` | 3 | **45× – 98×** | inflated |
| `--gate`, `--variable-height-mutation`, `--structural-mutation`, `--bulk-structural-mutation`, `--realistic-provider` | 15 | **3× – 10×** | correctly calibrated |

Forty-two gated scenarios in total: 27 are out of band, 15 are correct.

The correctly-calibrated tier is the proof that this project *can* set meaningful
budgets, and it supplies the target: a latency gate is worth its CI step when its
budget sits within a small multiple of observed latency.

### Root cause

The query-gate budgets were never calibrated. Slice 27's plan
(`docs/superpowers/plans/2026-06-21-vertical-position-query.md:629`) introduced them
as:

```swift
// Starter budgets (macOS-calibrated in Step 6). ...
p95BudgetNanoseconds: 30_000, p99BudgetNanoseconds: 60_000),
```

Step 6 of that plan is *"Run the tests to confirm they pass"*. **No calibration step
ever existed.** The starter numbers — which are compute-scale, borrowed from gates
whose unit of work is a whole viewport computation costing thousands of nanoseconds —
shipped verbatim for a query whose unit of work costs ~20 ns. They were then
copy-pasted into Slices 31, 33, 35, and 37, each new gate inheriting the previous
gate's inflated scale.

`--variable-height` (Slice 14) has the same disease in milder form: prefix-sum
variable-height compute is roughly an order of magnitude cheaper than the synthetic
pipeline compute, but it was given pipeline-scale budgets.

So this is not five independent mistakes. It is **one unredeemed placeholder,
propagated by copy-paste**, plus one earlier instance of the same reasoning error.

### What the inert gates fail to catch

At 1,000×+ headroom, a `--column-query` gate would still report `gate=pass` if
`binarySearchColumnIndex` were replaced by a **linear scan over all 256 cells**. The
gates today guard correctness-under-load and determinism (via `failures=0` and the
checksum), but not latency in any practical sense.

## Scope

**In scope** — 6 gates, 27 scenarios (23 calibrated from hosted history, 4 point
scenarios calibrated in-slice per Decision 5):

- Recalibrate the 5 query gates (`--line-query`, `--line-geometry-query`,
  `--column-query`, `--column-geometry-query`, `--point-query`) — 20 existing
  scenarios + 4 point scenarios.
- Recalibrate `--variable-height` — 3 scenarios.
- Add headroom reporting and an anti-inflation ceiling to the gate.
- Promote `--point-query` to the **tenth blocking hosted gate**.
- Document the calibration rule so the next gate cannot repeat the mistake.

**Not in scope:**

- **Any change to `Sources/TextEngineCore`.** This slice changes no engine behavior.
  Expected core diff: **zero lines**.
- The 15 already-calibrated scenarios (3×–10× hosted headroom). Applying the new
  recipe to them would *loosen* `pipeline|1m` from 3× to 8×. They are correct; leave
  them. They remain subject to the new ceiling, which they clear comfortably.
- Changing the gate statistic. p95/p99 stay. (A median/low-percentile gate would be
  more noise-robust and permit tighter budgets, but it changes gate semantics and the
  output contract; explicitly deferred.)
- New benchmark scenarios, new providers, new modes.
- The Slice 37 review's other findings (P2 #2 core-supplied `inLine`; the P3s). They
  belong to the `pointGeometryAt` slice.
- WASM blocking; arm64 runner migration; budgets for non-gate diagnostics.

## Goals

1. Every gated scenario's hosted headroom lands inside a documented band.
2. The gate detects its own inflation, so this defect class cannot silently return.
3. `--point-query` becomes blocking **with an honest budget**, not an inert one.
4. No engine behavior changes; every checksum stays byte-identical.

## Non-Goals

Catching a 2× constant-factor regression. Hosted run-to-run p95 varies by up to
**2.71×** on an unchanged binary (see Evidence). A p95 gate on a shared runner
therefore cannot resolve a 2× regression from noise, at any budget that does not
flake. This slice buys detection of **≥8× regressions** — the linear-scan,
lost-`O(log N)`, allocation-in-hot-path class — and says so plainly rather than
implying more.

## Decisions

### Decision 1 — Hosted Linux x86_64 is the calibration authority

Budgets are derived from hosted Linux, not local macOS. Hosted is **2–3× slower**
(e.g. `line_query|uniform_1m`: local p95 = 18 ns, hosted median = 43 ns), so it is
the binding constraint; a budget that holds on hosted holds locally with extra
headroom, and the reverse is false.

This **retires the standing "budgets are macOS-calibrated" caveat** for the 23
recalibrated scenarios. `AGENTS.md` must be updated accordingly — the caveat remains
true only for the untouched 14.

### Decision 2 — The budget recipe

For a scenario being calibrated:

```
budget_p95 = round_up_2sf(8 × median(hosted p95, over ≥5 hosted runs))
budget_p99 = 2 × budget_p95
```

with a **mandatory floor check**: `budget_p95 ≥ 3 × max(observed hosted p95)`.

`8×` is not arbitrary: it is the **smallest uniform factor that keeps ≥3× margin over
every one of the 190 observed hosted samples**. The binding scenario is
`line_query|uniform_100k`, whose observed p95 ranges 34–92 ns (a 2.71× spread on an
unchanged binary); 8 × its 34 ns median = 272 → 280 ns, exactly 3.0× its worst
observation.

`p99 = 2 × p95` preserves the existing convention in every benchmark file.

### Decision 3 — The headroom band invariant

Every gated scenario must satisfy **3× ≤ hosted headroom ≤ 50×**.

- The **lower bound** is what prevents flakes. It is not machine-checkable (the budget
  *is* the latency bound); it is enforced by the Decision 2 floor check at calibration
  time.
- The **upper bound** is machine-checkable and becomes an executable gate check
  (Decision 4).

Scenarios already inside the band are not touched.

### Decision 4 — Emit headroom; fail the gate above the ceiling

`BenchmarkSummary` gains a computed `headroomP95` (`budget_p95 ÷ p95`). Every summary
line gains a `headroom_p95=N.Nx` field. Under `--gate`, `passesGate` gains a third
condition: **`headroom_p95 ≤ 50×`**.

The gate thus polices its own meaningfulness. Today's 3,000× budgets would fail on the
first run.

Ceiling safety, verified against the fastest machine available (local macOS arm64,
which runs 2–3× faster than hosted and therefore shows the *highest* headroom):

| Scenario group | Local headroom under new budgets | Margin to ceiling |
| --- | --- | --- |
| 23 recalibrated from history | 12× – 23× | ≥ 2.2× |
| 15 untouched | 3.2× – 20.0× | ≥ 2.5× |

Worst case is `bulk_structural_mutation|1k_lines_batch_64` at 20.0× local. A 50×
ceiling leaves every scenario at least 2.2× of margin on the fastest hardware in play.

Degenerate case: if `p95_ns == 0` (a workload too cheap for the clock), headroom is
unbounded and the gate **fails**. That is the correct signal — a scenario measuring
zero guards nothing.

The ceiling is checked only under `--gate`, and only for scenarios that carry budgets.

### Decision 5 — `--point-query` promotion uses two hosted rounds

`--point-query` has **zero** hosted samples (it is not in CI), so its median cannot be
computed from history. Deriving it by scaling local numbers with an assumed
hosted/local ratio would be an *inference*, and this project's standing convention is
that verification is evidence, not assertion.

Sequence within the slice:

1. Add the `--point-query --gate` step to the host CI job, budgets **unchanged**
   (still the inflated 120k/240k), and temporarily exempt it from the Decision 4
   ceiling.
2. The PR's hosted run prints `--point-query` hosted p95/p99 **for the first time**.
   Accumulate ≥3 hosted samples (each push to the PR branch yields one).
3. Set its final budgets by Decision 2, with the floor tightened to `≥ 3 × max
   observed` — which, on a thin 3-sample base, is the binding term, not the median
   term. Remove the ceiling exemption.
4. The final PR run validates every gate, ceiling included, on the real budgets.

The temporary exemption in step 1 exists for exactly one commit and is removed in step
3; the acceptance criteria require that no exemption survives to `main`.

### Decision 6 — Order of work: recalibrate first, promote second

The 23 recalibrated budgets land and go green on hosted **before** the point gate is
promoted. If a tightened budget turns out to flake, that must be discovered while it
affects one PR — not while it is simultaneously blocking a promotion.

## Implementation Architecture

### Swift (benchmark target only)

- `Sources/ViewportBenchmarks/BenchmarkModels.swift` — add `headroomP95`; add the
  ceiling term to `passesGate`; add `headroom_p95` to `formatSummary`.
- `Sources/ViewportBenchmarks/{LineQuery,LineGeometryQuery,ColumnQuery,ColumnGeometryQuery,PointQuery,VariableHeight}Benchmark.swift`
  — replace the budget constants in the scenario tables. **No logic changes.**

### Workflow

`.github/workflows/swift-ci.yml` — one new blocking step, `Run point query benchmark
gate`, placed after the column-geometry-query gate, matching the shape of the nine
existing gate steps. Required-context names are unchanged, so the `Main` ruleset needs
no edit.

### Documentation

`AGENTS.md` — the calibration recipe and the headroom band become a stated rule (this
is the durable, non-obvious fact the repo currently lacks); the CI section gains the
tenth blocking gate; the `--point-query` "local (not-yet-CI)" label is removed; the
"macOS-calibrated" caveat is scoped to the untouched gates.

### Verification record

`docs/superpowers/verification/2026-07-12-gate-budget-recalibration.md` — the
before/after headroom table for all 42 gated scenarios, the local run of all ten
gates, the ceiling-rejects-an-inflated-budget demonstration, and the hosted PR-head
and post-merge run IDs.

## Testing Strategy

This slice changes no engine code, so the existing 232 tests must pass **unchanged**,
and every gate checksum must be **byte-identical** to the Slice 37 baseline. That
byte-identity is the proof that recalibration moved no measured path — the same
strict-additivity argument the last four slices used.

New tests (in the benchmark target's test surface, mirroring how gate logic is
currently covered):

1. `passesGate` is **false** when `headroom_p95 > 50×`, even with `failures == 0` and
   both latency budgets met. This is the test that would have caught the original bug.
2. `passesGate` is **true** at the band edges (headroom just under the ceiling).
3. `headroomP95` is computed as `budget ÷ p95`, and the degenerate `p95 == 0` case
   fails the gate rather than dividing by zero.
4. `formatSummary` emits `headroom_p95` only when a budget exists.

Written test-first, per the project's TDD norm.

## Acceptance Criteria

1. `swift test` — 232 existing tests pass, plus the new gate-logic tests.
2. `git diff --name-only` shows **no path under `Sources/TextEngineCore`**.
3. All ten gates report `gate=pass` locally, and all query/mutation checksums are
   byte-identical to the Slice 37 baseline.
4. Every gated scenario prints `headroom_p95` ≤ 50× locally.
5. Reverting any single recalibrated budget to its old value makes `--gate` **fail**
   on the ceiling — demonstrated and recorded, not asserted.
6. Hosted: all ten gates green on the PR head and on the post-merge push run, with
   `mode=point_query` **present** in the hosted log (the inverse of the Slice 37 check).
7. `AGENTS.md` states the calibration rule, the band, and the tenth blocking gate.

## Risks And Gaps

### A tightened blocking gate can flake, and strict checks make that expensive

The repository's `Main` ruleset enables strict required status checks, so a flaking
gate blocks *every* PR, not just one. This is the slice's principal risk.

Mitigation is the Decision 2 floor: every budget clears the **worst** of 190 observed
samples by ≥3×, not merely the median. The historical spread on an unchanged binary
tops out at 2.71×, so a flake requires a runner roughly 3× worse than anything seen in
25 runs. Residual risk is accepted, and the response is documented: a flake is
evidence that the floor is too thin for that scenario, and the budget is raised with
the new sample recorded — never silently widened back toward inertness.

### The point gate's sample base is thin

Three hosted samples cannot characterize a tail the way twelve can. Decision 5's floor
(`≥ 3 × max observed`) is deliberately the binding term there. Its budget is the most
likely of the 23 to need one upward revision.

### The band's upper bound is calibrated to today's hardware

A future runner materially faster than the current local macOS arm64 could push a
scenario's headroom past 50× and fail the ceiling. That is a *correct* failure — it
means the budget no longer reflects reality — but it will arrive as a red CI on an
unrelated PR. The arm64-Linux-runner migration already on the roadmap is the likely
trigger, and it was always going to require a re-baseline.

### Standing items unchanged

WASM stays observational; the realistic-provider observation stays PR-only
`continue-on-error`; the ruleset keeps its documented bypass-actor shape.

## Evidence

Harvested 2026-07-12 from 25 hosted runs (`gh run view --log`), 190 query-gate
samples, 5–12 runs per scenario.

### Hosted p95 (ns) and resulting budgets

| Scenario | n | median | max | spread | new p95 budget | margin over max |
| --- | --- | --- | --- | --- | --- | --- |
| line_query uniform_1k | 12 | 24 | 43 | 1.87× | 200 | 4.7× |
| line_query uniform_100k | 12 | 34 | 92 | **2.71×** | 280 | **3.0×** |
| line_query uniform_1m | 12 | 43 | 61 | 1.56× | 350 | 5.7× |
| line_query balanced_tree_100k | 12 | 210 | 240 | 1.86× | 1700 | 7.1× |
| line_query balanced_tree_1m | 12 | 250 | 257 | 1.29× | 2000 | 7.8× |
| line_geometry_query uniform_1k | 12 | 33 | 57 | 1.84× | 270 | 4.7× |
| line_geometry_query uniform_100k | 12 | 44 | 73 | 1.74× | 360 | 4.9× |
| line_geometry_query uniform_1m | 12 | 47 | 73 | 1.55× | 380 | 5.2× |
| line_geometry_query balanced_tree_100k | 12 | 362 | 380 | 1.58× | 2900 | 7.6× |
| line_geometry_query balanced_tree_1m | 12 | 417 | 430 | 1.38× | 3400 | 7.9× |
| column_query uniform_1k | 9 | 24 | 26 | 1.08× | 200 | 7.7× |
| column_query uniform_100k | 9 | 37 | 55 | 1.57× | 300 | 5.5× |
| column_query uniform_1m | 9 | 40 | 54 | 1.35× | 320 | 5.9× |
| column_query prefixsum_100k | 9 | 57 | 89 | 1.62× | 460 | 5.2× |
| column_query prefixsum_1m | 9 | 71 | 121 | 1.95× | 570 | 4.7× |
| column_geometry_query uniform_1k | 5 | 32 | 34 | 1.06× | 260 | 7.6× |
| column_geometry_query uniform_100k | 5 | 43 | 46 | 1.07× | 350 | 7.6× |
| column_geometry_query uniform_1m | 5 | 48 | 52 | 1.08× | 390 | 7.5× |
| column_geometry_query prefixsum_100k | 5 | 104 | 116 | 1.73× | 840 | 7.2× |
| column_geometry_query prefixsum_1m | 5 | 89 | 143 | 1.93× | 720 | 5.0× |
| variable_height 1k | 5 | 510 | 517 | 1.01× | 4100 | 7.9× |
| variable_height 100k | 5 | 1730 | 1765 | 1.02× | 14000 | 7.9× |
| variable_height 1m | 5 | 5504 | 5579 | 1.01× | 45000 | 8.1× |

`--point-query` (4 scenarios) is absent by construction: it has no hosted history.
Decision 5 obtains it.

### Old vs new, illustrative

| Scenario | old p95 budget | hosted median | old headroom | new p95 budget | new headroom |
| --- | --- | --- | --- | --- | --- |
| column_query uniform_1m | 120,000 | 40 | **3,000×** | 320 | 8× |
| line_query uniform_1m | 120,000 | 43 | **2,857×** | 350 | 8× |
| line_geometry_query balanced_tree_1m | 600,000 | 417 | **1,435×** | 3,400 | 8× |
| variable_height 1k | 50,000 | 510 | **98×** | 4,100 | 8× |

## Recommended Next Step

Slice 39 returns to the product arc: **`pointGeometryAt(x:y:)`**, the geometry-bearing
2D composite (the Slice 37 review's Option B), which is also the natural home for that
review's P2 #2 — the decision on what a mismatched line/column source pairing should
do now that the *core* supplies the `inLine` index.
