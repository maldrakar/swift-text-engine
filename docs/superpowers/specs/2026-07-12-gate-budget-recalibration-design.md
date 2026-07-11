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

The brief's success criterion is explicit: *«Регрессионные бенчмарки блокируют merge при
деградации производительности»*. Today that criterion is met only nominally — the query
gates run, go green, and **cannot fail**. This slice is what turns the checkmark back
into a check.

### The three tiers

Measured hosted-Linux headroom (`budget_p95 ÷ median observed p95`), from **575**
gate-line samples harvested across **every one of the 20 hosted runs** that carry gate
lines (2026-06-30 – 2026-07-11; see Evidence for the harvest command):

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

**Catching a 2× constant-factor regression.** Hosted run-to-run p95 varies by up to
**2.71×** on an unchanged binary (see Evidence). A p95 gate on a shared runner
therefore cannot resolve a 2× regression from noise, at any budget that does not
flake. This slice buys detection of **≥8× regressions** — the linear-scan,
lost-`O(log N)`, allocation-in-hot-path class — and says so plainly rather than
implying more.

**The product budget.** The brief asks for a second thing this slice does not deliver:
turning “60 FPS” into a measurable headless budget. Every number derived here is a
*regression* budget — anchored to the scenario's own hosted median, not to the 16.7 ms
frame. Nothing in this design detects slow drift that a future recalibration
**legitimises**: if the engine becomes 2× slower and the budgets are re-derived against
the new medians, every gate stays green and no check ever consults the frame. Closing
that gap needs a second, *absolute* threshold per scenario that is never recalibrated
(order of magnitude: any query < 1 µs, a viewport compute < 1 ms ≈ 6 % of a frame),
which changes what a gate *means* and deserves its own slice. Recorded here so the gap
is on the record rather than implied away.

## Decisions

### Decision 1 — Hosted Linux x86_64 is the calibration authority

Budgets are derived from hosted Linux, not local macOS. Hosted is **2–3× slower**
(e.g. `line_query|uniform_1m`: local p95 = 18 ns, hosted median = 43 ns), so it is
the binding constraint; a budget that holds on hosted holds locally with extra
headroom, and the reverse is false.

This **retires the standing "budgets are macOS-calibrated" caveat** for the 27
recalibrated scenarios. `AGENTS.md` must be updated accordingly — the caveat remains
true only for the untouched 15.

### Decision 2 — The budget recipe

For a scenario being calibrated, over **≥5 hosted runs**, with the 3× floor applied to
**each statistic** — the gate can fail on either, so a guarantee that covers only p95
covers only half the failures:

```
budget_p95 = round_up_2sf(max(8 × median(hosted p95), 3 × max(hosted p95)))
budget_p99 = round_up_2sf(max(2 × budget_p95, 8 × median(hosted p99), 3 × max(hosted p99)))
```

The floor is folded **into** the formula rather than left as a check performed afterwards,
because on the full corpus it genuinely binds. With `max()` doing the work, the ≥3× margin
is guaranteed by construction for *any* factor — so the factor's job is not to protect the
margin but to decide **which term governs**, and `8×` is the point at which the two terms
meet in the noisiest family (`line_query` over `UniformLineMetrics`, where the operation
costs ~20–40 ns and runner noise, not the algorithm, sets the tail):

| Scenario | median | worst | `8 × median` | `3 × worst` | governed by |
| --- | --- | --- | --- | --- | --- |
| `line_query\|uniform_1m` | 41 | 109 (**2.66×** over median) | 328 | 327 | median, by 1 ns |
| `line_query\|uniform_100k` | 34 | 92 (**2.71×**) | 272 | 276 | **floor** |

Above 8× the median term governs everywhere and the floor is decorative; below it the
floor progressively takes over and the budgets stop being "8× median" in any meaningful
sense. 8× is therefore the largest factor that still buys ~8× headroom on the quiet
scenarios while letting the floor — not an arbitrary multiplier — set the budget exactly
where noise makes the median untrustworthy. Both noisy scenarios land at **3.0×** over
their worst observation, which is the floor doing its job.

`p99 = 2 × p95` survives as a **floor**, not as the definition it used to be. The gate
fails on p99 as well as p95, yet the earlier draft derived the p99 budget entirely from
the p95 series — no p99 observation entered the calculation, so the design's 3× guarantee
simply did not cover the statistic on which half its failures can occur.

Checked against the corpus, the `2 × budget_p95` convention *does* clear the p99 floor
everywhere; the tightest is `column_query|uniform_100k` at **3.5×** (max hosted p99 =
173 ns vs a 600 ns budget — a 2.6× tail spike over its own 67 ns median, the largest in
the corpus). So this change does not rescue a broken budget. It makes a guarantee that is
currently **lucky** into one that is **checked**: p99 is measured, its own floor is
enforced, and the next gate cannot inherit an unverified p99 by copy-paste the way the
last five inherited an unverified p95.

### Decision 3 — The headroom band invariant

Every gated scenario must satisfy **3× ≤ hosted headroom ≤ 50×**.

- The **lower bound** is what prevents flakes. It is not machine-checkable (the budget
  *is* the latency bound); it is enforced by the Decision 2 floor checks — **both** of
  them, p95 and p99 — at calibration time.
- The **upper bound** is machine-checkable and becomes an executable gate check
  (Decision 4). Headroom is defined on p95; the p99 budget is held in band by its own
  floor plus the `budget_p99 ≥ 2 × budget_p95` invariant, which a test pins (Testing
  Strategy), since the ceiling alone would not notice an inflated p99 budget.

Scenarios already inside the band are not touched.

### Decision 4 — Emit headroom; fail the gate above the ceiling

`BenchmarkSummary` gains a computed `headroomP95` (`budget_p95 ÷ p95`). Every **gate**
summary line — i.e. every line that already carries `budget_p95_ns`, since budgets are
optional on `BenchmarkSummary` — gains a `headroom_p95=N.Nx` field. Under `--gate`,
`passesGate` gains a third condition: **`headroom_p95 ≤ 50×`**.

The gate thus polices its own meaningfulness. Today's 3,000× budgets would fail on the
first run.

**`gate=fail` must also say why.** The two failure causes demand opposite responses, and
collapsing them into one boolean throws away the only bit that matters to whoever reads
the red CI:

- `reason=budget_exceeded` — the measured p95/p99 broke the budget. *The code got
  slower; fix the code.*
- `reason=budget_stale` — headroom is above the ceiling. *The budget no longer reflects
  reality; re-derive it from fresh hosted evidence.*

**The ceiling is enforced on every run, local and hosted alike.** One code path, no
mode-dependent gate semantics. Two consequences are accepted deliberately, not
overlooked:

- A machine materially faster than the calibration hardware can trip the ceiling on a
  clean tree (local headroom lands at 12×–23×, so it takes roughly 2.2× more speed).
- **A legitimate optimization trips it too** — this is not hypothetical. Slices 29/30 cut
  `lineAt` from `O(log²N)` to `O(log N)` on the balanced-tree provider, and the roadmap's
  native column inverse would do the same to `columnAt`. The *next* optimization slice
  can therefore open with a red gate.

Both are the **correct** signal (`reason=budget_stale`: the budget is stale), and the
response is always the same — re-derive the budget from fresh hosted evidence, in the
same PR that caused the shift. `AGENTS.md` states this as policy, so the next agent
raises the *budget* and never the *ceiling*.

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

### Decision 5 — `--point-query` observes on hosted before it gates

`--point-query` has **zero** hosted samples (it is not in CI), so its median cannot be
computed from history. Deriving it by scaling local numbers with an assumed
hosted/local ratio would be an *inference*, and this project's standing convention is
that verification is evidence, not assertion.

Sequence within the slice — note that **no gate and no ceiling exemption is involved in
the harvesting step**. `formatSummary` prints `p95_ns`/`p99_ns` unconditionally and emits
`budget_*` / `gate=` *only* under `--gate` (`BenchmarkSummary`'s budgets are optional;
`BenchmarkSupport.swift:89-102`), so hosted latency can be observed without asserting
anything about it:

1. Add a **non-gate** step to the host CI job — `ViewportBenchmarks -- --point-query`,
   no `--gate`. It prints hosted p95/p99 for the four point scenarios **for the first
   time** and cannot fail on latency, so no exemption mechanism has to exist.
2. Accumulate ≥3 hosted samples (each push to the PR branch yields one).
3. Set the budgets by Decision 2. On a 3-sample base the **floors** bind, not the median
   terms. Cross-check against the additivity prediction below.
4. **Replace** the observation step with `--point-query --gate`. The final PR run
   validates all ten gates, ceiling included, on the real budgets.

This is strictly better than shipping the gate first with its inflated budgets and a
temporary ceiling exemption: an inert gate never enters CI even for one commit, and the
codebase never grows an exemption field that someone must remember to delete. The
acceptance criteria require that the non-gate observation step does **not** survive to
`main`.

**Additivity cross-check for the thin sample base.** `pointAt` is proven pure
composition — `lineAt ∘ columnAt`, no new search (Slice 37). Its hosted median must
therefore land near the sum of the corresponding 1D medians, both of which are known from
the 575-sample corpus (e.g. `uniform_1m`: `line_query` 41 ns + `column_query` 40 ns
≈ 81 ns). If the harvested point median comes in materially above that sum, the thin base
is not the problem — the composite is doing work it should not, and that is a finding in
its own right, not a budget to be widened around.

### Decision 6 — Order of work: recalibrate first, promote second

The 23 recalibrated budgets land and go green on hosted **before** the point gate is
promoted. If a tightened budget turns out to flake, that must be discovered while it
affects one PR — not while it is simultaneously blocking a promotion.

## Implementation Architecture

### Swift (benchmark target only)

- `Sources/ViewportBenchmarks/BenchmarkModels.swift` — add `headroomP95`; add the
  ceiling term and the failure `reason` to `passesGate`; add `headroom_p95` (and
  `reason=` on failure) to `formatSummary`.
- `Sources/ViewportBenchmarks/{LineQuery,LineGeometryQuery,ColumnQuery,ColumnGeometryQuery,PointQuery,VariableHeight}Benchmark.swift`
  — replace the budget constants in the scenario tables. **No logic changes.**

### Package

`Package.swift` gains the benchmark target's **first** test target — the gate logic this
slice hardens (`passesGate`, `formatSummary`) currently has **no test coverage at all**,
because no test target depends on `ViewportBenchmarks`:

```swift
.testTarget(name: "ViewportBenchmarksTests", dependencies: ["ViewportBenchmarks"])
```

A test target may depend on an *executable* target under swift-tools 6.0, and
`@testable import ViewportBenchmarks` was compile-verified for this package on macOS
arm64, Linux aarch64, and Linux x86_64 (the CI architecture) in the `swift:6.2.1-bookworm`
image — so no library extraction is needed and the "gates live in `ViewportBenchmarks`,
not the core" layout is preserved. This is the only `Package.swift` change; the core and
provider targets are untouched.

Re-verified end-to-end on macOS arm64 while validating this spec: with the test target
added, `swift build --build-tests` links and `swift test` **executes** a `@testable`
test against `BenchmarkSummary.passesGate` — so the executable's `main.swift` does not
collide with the test bundle's entry point, which is the failure mode that would have
sunk this approach. Hosted Linux x86_64 is proven by the PR's own `swift test` step.
Fallback if it disagrees: extract the gate types into a small `BenchmarkKit` library
target that both the executable and the tests depend on. That is a mechanical change, and
it is the reason this risk is acceptable rather than blocking.

### Workflow

`.github/workflows/swift-ci.yml` — one new step after the column-geometry-query gate,
matching the shape of the nine existing gate steps. It lands as the **non-gate**
observation step of Decision 5 and is replaced, in the same PR, by the blocking `Run
point query benchmark gate`. Required-context names are unchanged, so the `Main` ruleset
needs no edit.

### Documentation

`AGENTS.md` — the calibration recipe and the headroom band become a stated rule (this
is the durable, non-obvious fact the repo currently lacks); the CI section gains the
tenth blocking gate; the `--point-query` "local (not-yet-CI)" label is removed; the
"macOS-calibrated" caveat is scoped to the untouched gates; the Package layout section
gains the new test target; and the stale-budget policy is stated: **an optimization that
lifts a scenario's headroom above the ceiling re-derives that budget in the same PR — the
budget moves, never the ceiling.**

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

New tests go into a **new** test target (`Tests/ViewportBenchmarksTests`, wired in
Package). They are the **first tests the gate logic has ever had**: `passesGate` and
`formatSummary` are today reachable from no test target at all, which is precisely why an
uncalibrated placeholder could propagate through five slices without anything objecting.
Test-first, per the project's TDD norm:

1. `passesGate` is **false** when `headroom_p95 > 50×`, even with `failures == 0` and
   both latency budgets met. This is the test that would have caught the original bug.
2. `passesGate` is **true** at the band edges (headroom just under the ceiling).
3. `headroomP95` is computed as `budget ÷ p95`, and the degenerate `p95 == 0` case
   fails the gate rather than dividing by zero.
4. `formatSummary` emits `headroom_p95` only when a budget exists (budgets are optional
   on `BenchmarkSummary`; non-gate output must stay unchanged).
5. A failing gate reports the **cause**: `reason=budget_exceeded` when latency broke the
   budget, `reason=budget_stale` when only the ceiling was breached.
6. Every gated scenario table satisfies `budget_p99 ≥ 2 × budget_p95` — a static
   invariant over the tables themselves, since the p95-only ceiling cannot see an
   inflated p99 budget.

## Acceptance Criteria

1. `swift test` — 232 existing tests pass, plus the new gate-logic tests in the new
   `ViewportBenchmarksTests` target (green on hosted Linux, not only locally).
2. `git diff --name-only` shows **no path under `Sources/TextEngineCore`**, and the only
   `Package.swift` change is the added test target.
3. All ten gates report `gate=pass` locally, and all query/mutation checksums are
   byte-identical to the Slice 37 baseline.
4. Every gated scenario prints `headroom_p95` ≤ 50× locally.
5. Every recalibrated budget clears **both** floors — `budget_p95 ≥ 3 × max(hosted p95)`
   **and** `budget_p99 ≥ 3 × max(hosted p99)` — against the recorded sample corpus, shown
   per scenario in the verification record.
6. Reverting any single recalibrated budget to its old value makes `--gate` **fail**
   with `reason=budget_stale` — demonstrated and recorded, not asserted.
7. Hosted: all ten gates green on the PR head and on the post-merge push run, with
   `mode=point_query` **present** in the hosted log (the inverse of the Slice 37 check),
   and **no non-gate point-query observation step** left in the workflow on `main`.
8. `AGENTS.md` states the calibration rule (both statistics), the band, the stale-budget
   policy, and the tenth blocking gate.

## Risks And Gaps

### A tightened blocking gate can flake, and strict checks make that expensive

The repository's `Main` ruleset enables strict required status checks, so a flaking
gate blocks *every* PR, not just one. This is the slice's principal risk.

Mitigation is the Decision 2 floors — **both** of them: every budget clears the **worst**
of the 575 observed samples by ≥3× on p95 *and* on p99, not merely the median, and not on
p95 alone. Worst margins in the corpus: **3.0×** on p95 (`line_query|uniform_1m` and
`|uniform_100k`) and **3.5×** on p99 (`column_query|uniform_100k`). The spread on an
unchanged binary tops out at 2.71×, so a flake requires a runner roughly 3× worse than
anything seen in 20 runs. Residual risk is accepted, and the response is documented: a
flake is evidence that the floor is too thin for that scenario, and the budget is raised
with the new sample recorded — never silently widened back toward inertness.

**The margin is thinner than the first harvest suggested.** That harvest read 12 runs per
scenario; 20 were available, and the extra 8 contained the worst tails in the corpus
(`line_query|uniform_1m` max p95: 61 → **109 ns**; `|uniform_1k`: 43 → **59 ns**). The 8×
factor survives — but only just, and the sampled maximum is exactly the statistic the
floor rests on. Calibration must therefore harvest **every** available hosted run, not a
convenient subset, and the verification record must state how many runs each scenario's
numbers came from.

### The point gate's sample base is thin

Three hosted samples cannot characterize a tail the way twenty can — and the corpus shows
exactly what a thin base hides: going from 12 to 20 runs raised `line_query|uniform_1m`'s
worst p95 from 61 ns to 109 ns. Decision 5's floor (`≥ 3 × max observed`) is therefore the
binding term for the point gate by design, and the additivity cross-check is its second
opinion. Its budget remains the one most likely of the 27 to need an upward revision, and
that revision is expected, not a failure of the recipe.

### The ceiling fires on speed-ups, not only on slow-downs

Two distinct events push headroom past 50× and turn the gate red, and neither is a
regression:

- **Faster hardware.** A runner materially faster than the current local macOS arm64
  clears the ceiling on an unchanged binary. The arm64-Linux-runner migration already on
  the roadmap is the likely trigger, and it was always going to require a re-baseline.
- **Faster code.** Local headroom sits at 12×–23×, so a ~2.2×–4× optimization is enough.
  This has direct precedent: Slices 29/30 took `lineAt` from `O(log²N)` to `O(log N)` on
  the balanced-tree provider, and the roadmap's native column inverse would do the same
  for `columnAt`. **The next optimization slice can open with a red gate on its own
  win.**

Both are *correct* failures — `reason=budget_stale` — but they arrive as red CI, possibly
on a PR whose author did not expect to touch calibration. The design accepts this in
exchange for one code path and a ceiling that cannot be quietly bypassed, and it is
handled by policy rather than by machinery: the PR that shifts the headroom re-derives
that budget, in that PR, with fresh hosted evidence. Stated in `AGENTS.md` so the next
agent raises the budget rather than the ceiling.

Degenerate corner of the same class: an operation fast enough to measure `p95_ns == 0`
(integer division by `operationsPerSample`) fails the gate. Today's cheapest scenario
measures ~11 ns locally, so there is room, but an `O(1)` native inverse would narrow it.

### The new field does not break the log consumers

Verified, not assumed: `.github/scripts/realistic-relative-observation.sh` parses
benchmark output **by key** (`extract_field`, `tr ' ' '\n'` + `awk -F=`), not by column
position, and it only ever reads `mode=realistic_provider` lines, which carry no budgets
and therefore no `headroom_p95`. Adding a field to gate lines cannot break it.

### Standing items unchanged

WASM stays observational; the realistic-provider observation stays PR-only
`continue-on-error`; the ruleset keeps its documented bypass-actor shape.

## Evidence

Harvested 2026-07-12 from **every** hosted run that carries gate lines — 20 runs, **575
samples**, 5–20 runs per scenario (the count differs per gate because the gates were
promoted at different slices). Reproduce with:

```bash
gh run list -R maldrakar/swift-text-engine --workflow swift-ci.yml --limit 40 \
  --json databaseId --jq '.[].databaseId' \
| while read -r id; do
    gh run view "$id" -R maldrakar/swift-text-engine --log < /dev/null \
      | grep -E 'p95_ns=[0-9]+ p99_ns=[0-9]+' | sed "s/^/run=$id /"
  done
```

The raw sample corpus is committed with the verification record, so the derivation below
can be re-run rather than taken on trust.

### Hosted p95/p99 (ns) and resulting budgets

Budgets by the Decision 2 formula; margins are over the **worst** observed sample, which
is the quantity the 3× floor protects.

| Scenario | n | p95 med | p95 max | p99 med | p99 max | budget p95 | budget p99 | p95 margin | p99 margin |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `line_query\|uniform_1k` | 20 | 24 | 59 | 54 | 74 | 200 | 440 | 3.4× | 5.9× |
| `line_query\|uniform_100k` | 20 | 34 | 92 | 66 | 110 | 280 | 560 | **3.0×** | 5.1× |
| `line_query\|uniform_1m` | 20 | 41 | 109 | 71 | 128 | 330 | 660 | **3.0×** | 5.2× |
| `line_query\|balanced_tree_100k` | 20 | 208 | 240 | 222 | 313 | 1700 | 3400 | 7.1× | 10.9× |
| `line_query\|balanced_tree_1m` | 20 | 251 | 257 | 262 | 288 | 2100 | 4200 | 8.2× | 14.6× |
| `line_geometry_query\|uniform_1k` | 13 | 33 | 57 | 62 | 84 | 270 | 540 | 4.7× | 6.4× |
| `line_geometry_query\|uniform_100k` | 13 | 44 | 73 | 74 | 110 | 360 | 720 | 4.9× | 6.5× |
| `line_geometry_query\|uniform_1m` | 13 | 47 | 73 | 79 | 82 | 380 | 760 | 5.2× | 9.3× |
| `line_geometry_query\|balanced_tree_100k` | 13 | 368 | 380 | 376 | 532 | 3000 | 6000 | 7.9× | 11.3× |
| `line_geometry_query\|balanced_tree_1m` | 13 | 418 | 430 | 442 | 528 | 3400 | 6800 | 7.9× | 12.9× |
| `column_query\|uniform_1k` | 9 | 24 | 26 | 43 | 58 | 200 | 400 | 7.7× | 6.9× |
| `column_query\|uniform_100k` | 9 | 37 | 55 | 67 | 173 | 300 | 600 | 5.5× | **3.5×** |
| `column_query\|uniform_1m` | 9 | 40 | 54 | 72 | 77 | 320 | 640 | 5.9× | 8.3× |
| `column_query\|prefixsum_100k` | 9 | 57 | 89 | 94 | 121 | 460 | 920 | 5.2× | 7.6× |
| `column_query\|prefixsum_1m` | 9 | 71 | 121 | 110 | 163 | 570 | 1200 | 4.7× | 7.4× |
| `column_geometry_query\|uniform_1k` | 5 | 32 | 34 | 63 | 65 | 260 | 520 | 7.6× | 8.0× |
| `column_geometry_query\|uniform_100k` | 5 | 43 | 46 | 74 | 76 | 350 | 700 | 7.6× | 9.2× |
| `column_geometry_query\|uniform_1m` | 5 | 48 | 52 | 79 | 84 | 390 | 780 | 7.5× | 9.3× |
| `column_geometry_query\|prefixsum_100k` | 5 | 104 | 116 | 134 | 150 | 840 | 1700 | 7.2× | 11.3× |
| `column_geometry_query\|prefixsum_1m` | 5 | 89 | 143 | 130 | 176 | 720 | 1500 | 5.0× | 8.5× |
| `variable_height\|1k` | 20 | 502 | 654 | 550 | 729 | 4100 | 8200 | 6.3× | 11.2× |
| `variable_height\|100k` | 20 | 1732 | 2032 | 1841 | 2123 | 14000 | 28000 | 6.9× | 13.2× |
| `variable_height\|1m` | 20 | 5507 | 6806 | 5653 | 6969 | 45000 | 90000 | 6.6× | 12.9× |

Worst margin anywhere: **3.0×** (p95) and **3.5×** (p99) — both at the floor, both in the
~20–40 ns tier where runner noise, not the algorithm, sets the tail.

**Independent re-derivation (2026-07-12).** The corpus was re-harvested from scratch and
the table recomputed without reference to the numbers above. Every **worst-case** sample —
the statistic the 3× floor actually rests on — reproduced **exactly**, on both statistics,
for all 23 scenarios. Medians moved by at most 2 ns on the query gates, and the resulting
budgets were unchanged except where noted below.

Two cautions this exposed, both of which the plan must honor:

- **The median is unstable on a thin base.** `column_geometry_query|prefixsum_100k`
  (n=5) moved its median from 104 ns to 70 ns when a single run dropped out. Its budget is
  set by `8 × median`, so on the 5-run gates the budget inherits that instability. This is
  the same weakness Decision 5 already calls out for `--point-query`, and it argues for
  re-harvesting at implementation time rather than transcribing this table.
- **`line_query|uniform_1k` sits exactly on a rounding boundary.** Median 24 → `8 × 24` =
  192 → 200; median 23 (what a 19-run corpus yields) → 184 → 190. The table now carries the
  conservative value (200/440). The plan **regenerates every budget from the committed
  corpus** rather than copying this table — which is, after all, the exact failure mode
  this slice exists to repair.

`--point-query` (4 scenarios) is absent by construction: it has no hosted history.
Decision 5 obtains it, and the additivity prediction there gives an independent
cross-check on the resulting budgets.

### Old vs new, illustrative

| Scenario | old p95 budget | hosted median | old headroom | new p95 budget | new headroom |
| --- | --- | --- | --- | --- | --- |
| `column_query\|uniform_1m` | 120,000 | 40 | **3,000×** | 320 | 8× |
| `line_query\|uniform_1m` | 120,000 | 41 | **2,927×** | 330 | 8× |
| `line_geometry_query\|balanced_tree_1m` | 600,000 | 418 | **1,435×** | 3,400 | 8× |
| `variable_height\|1k` | 50,000 | 502 | **100×** | 4,100 | 8× |

## Recommended Next Step

Slice 39 returns to the product arc: **`pointGeometryAt(x:y:)`**, the geometry-bearing
2D composite (the Slice 37 review's Option B), which is also the natural home for that
review's P2 #2 — the decision on what a mismatched line/column source pairing should
do now that the *core* supplies the `inLine` index.
