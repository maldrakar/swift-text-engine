# Slice 38 Post-Slice Review

Date: 2026-07-12

## Scope Reviewed

This review covers Slice 38: **gate-budget recalibration, and the promotion of
`--point-query` to the tenth blocking CI gate**.

It is the slice the Slice 37 review recommended (**Option C**) and the user
independently decided on 2026-07-11 deserved dedicated treatment: the query gates ran,
went green, and **could not fail**. Slice 37's review measured the new `--point-query`
gate at ~4,000x headroom and warned that promoting it as-is would "enshrine an inert
gate in required CI." Slice 38 accepted that sequencing — recalibrate first, promote
second — and did both in one slice.

The investigation behind the design found the **root cause**, and it is worth stating
plainly because it is the whole reason this slice exists: Slice 27's plan introduced
`p95BudgetNanoseconds: 30_000` as a *"starter budget (macOS-calibrated in Step 6)"*, and
**Step 6 of that plan was "run the tests to confirm they pass." The calibration step
never existed.** Compute-scale numbers, borrowed from gates whose unit of work is a whole
viewport computation costing thousands of nanoseconds, shipped verbatim for a query whose
unit of work costs ~20 ns — and were then copy-pasted into Slices 31, 33, 35, and 37.
This was never five independent mistakes. It was **one unredeemed placeholder, propagated
by copy-paste**, and it meant no query gate could fail for five consecutive slices.

The slice shipped through **two** PRs, both merged:

- **PR #80** (`slice-38-gate-budget-recalibration`), verified head
  `8e7c062e1236431f93116b91ed5c379e5941a91f` (`8e7c062`), merged as
  `2bc290e` — the recalibration, the two scripts, the corpus, the ceiling, the failure
  reasons, the new test target, the workflow promotion, `AGENTS.md`, and the docs.
- **PR #81** (`slice-38-post-merge-hosted-proof`), verified head `798b444`, merged as
  `1eab4df` (current `main` HEAD) — a genuinely docs-only follow-up filling in the real
  post-merge run ID.

Merge parentage confirmed: `2bc290e^2 == 8e7c062` and `1eab4df^2 == 798b444`. Both
proofs anchor the actually-merged code.

Reviewed artifacts: the design, plan and verification records; the merged diff
(`5e2abf7..1eab4df`); both new scripts; both new test files; the gate-logic changes in
`BenchmarkModels.swift` / `BenchmarkSupport.swift`; all eleven scenario tables; the
workflow; `AGENTS.md`; and the hosted runs at **step** level.

## Product Brief Alignment

The brief's success criterion is explicit: *«Регрессионные бенчмарки блокируют merge при
деградации производительности»* — regression benchmarks block merge on performance
degradation. Before this slice that criterion was met only nominally. It is now met in
substance, and the difference is measurable: hosted headroom across the whole gated suite
moved from **815x–3,000x** to **4.4x–12.5x**.

Every hard constraint holds and was re-verified. **The core diff is zero lines**
(`git diff --name-only 5e2abf7..1eab4df -- Sources/TextEngineCore` is empty), both
Foundation-free scans are empty, no dependency was added, and every gate checksum is
byte-identical to the Slice 37 baseline.

## Delivered Design

### The recipe is executable, not a table

The single most important judgment in this slice: the budgets are not written down
anywhere as authority. They are **derived**, by a committed script, from a committed
corpus of hosted samples:

```
budget_p95 = round_up_2sf(max(8 x median(hosted p95), 3 x max(hosted p95)))
budget_p99 = round_up_2sf(max(2 x budget_p95, 8 x median(p99), 3 x max(p99)))
```

The 3x floor is folded *into* the formula rather than checked afterwards, and it covers
**both** statistics — because the gate fails on either, so a guarantee covering only p95
covers only half the failures. The design's own evidence table carries a
**"SUPERSEDED — do not copy these numbers"** banner pointing at the script instead. That
is the correct instinct in a slice whose root cause was someone copying a budget out of a
document.

### The gate now polices its own meaningfulness

`BenchmarkSummary` gains `headroomP95` / `headroomP99` (`budget / observed`), and
`passesGate` gains a ceiling term. A budget more than **50x** above observed p95 (or
**100x** on p99) now **fails the gate**. The two failure causes are reported separately,
because they are opposite instructions to whoever reads the red CI:

- `reason=budget_exceeded` — the code got slower. **Fix the code.**
- `reason=budget_stale` — the budget no longer reflects reality. **Re-derive it.**

Two details are better than they had to be. `maxHeadroomP99` is written as
`2 * maxHeadroomP95` — **derived from the p95 ceiling, not chosen independently**, so the
two cannot silently drift apart. And the degenerate `p95_ns == 0` case (a workload too
cheap for the clock) yields `.infinity`, which is above every ceiling, so the gate fails —
correctly, since a scenario measuring zero guards nothing.

### `GateFloorTests` is the structurally right answer

The ceiling is only half the band, and the runtime gate **structurally cannot** check the
other half: `--gate` compares a budget against *this* run's latency, so it catches a
budget that is too loose but is blind to one sitting too close to the worst hosted sample —
and that is precisely the budget that goes red on a clean tree from runner noise alone.

`Tests/ViewportBenchmarksTests/GateFloorTests.swift` closes that gap by re-reading the
committed corpus on every `swift test` and holding **every** gated scenario to
`budget >= 3 x max(hosted)` on **both** statistics — plus failing if a gated scenario has
**no hosted evidence at all**. That second test is what caught `--realistic-provider`,
the one gate the design's own investigation missed: a gated mode the corpus had never
seen, whose budget nothing could re-derive, because CI never runs it with `--gate`.

### Package layout

`Package.swift` gains the benchmark target's **first** test target. The gate logic
(`passesGate`, `formatSummary`) previously had **no test coverage at all** — no test
target depended on `ViewportBenchmarks` — which is exactly why an uncalibrated
placeholder could propagate through five slices with nothing objecting. Nineteen new
tests now cover it (232 → 251).

## Verification Evidence Reviewed

### Fresh local checks during this review (merged tree at `1eab4df`)

I did not take the slice's central claim on trust. I re-ran the derivation myself and
compared it against the shipped constants:

- **All 29 recalibrated budgets reproduce *exactly* from the committed corpus.** I ran
  `./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
  and diffed its output against the budgets the running binary actually prints. The 29
  recalibrated scenarios match **byte-for-byte**. The 13 that differ are precisely the
  ones the design deliberately left alone (see P3 #1). Nothing was hand-typed. This is
  the property the slice exists to establish, and it holds.
- `swift test` → **251 tests, 0 failures** (+19 over Slice 37's 232, exactly the plan's
  delta).
- `swift build -c release` → `Build complete!`
- **All eleven gate modes run locally: 42 gated scenarios, `gate=pass`, `failures=0`,
  zero `gate=fail`.** Local headroom p95 **8.7x – 23.4x**, p99 max **49.5x** — inside the
  50x / 100x band on the fastest machine in play.
- `rg -n "Foundation" Sources/TextEngineCore` → empty. Same for
  `Sources/TextEngineReferenceProviders`. (`GateFloorTests` imports Foundation to read the
  corpus off disk, but it is a *test* target; the benchmark and core targets stay clean.)
- The four `--point-query` checksums (`64166237440`, `640022280960`, `64166280960`,
  `640022228480`) are **byte-identical** to those the Slice 37 review recorded — the
  recalibration moved no measured path.

### The guards genuinely bite (mutation-tested, not assumed)

A test that passes proves nothing until you watch it fail. I broke the tree twice:

1. **Reverted `line_query|uniform_1m` to its old `120_000/240_000` budget** →
   `headroom_p95=5000.0x ... gate=fail reason=budget_stale`, and the **process exits `1`**,
   so CI genuinely goes red. That single line is also the cleanest possible statement of
   what the old budgets were worth: 5,000x headroom locally.
2. **Dropped `column_query|uniform_1k`'s p95 budget to 70 ns** (below the `3 x 26 = 78` ns
   floor) → `GateFloorTests` fails with:
   *"p95 budget 70 is below 3x the worst hosted p95 (26, n=15) — it will go red on a clean
   tree; re-derive with .github/scripts/derive-gate-budgets.sh"*

Both guards work, and both error messages tell the next agent exactly what to do. Tree
restored clean afterwards.

### Hosted runs (verified at step level, not job conclusion)

Per the project's standing "a green job can hide a dead `continue-on-error` step" lesson:

- **PR #80 head run `29195471678`** (head `8e7c062`, event `pull_request`): all three
  required jobs `success`.
- **Post-merge push run `29196145560`** on merge commit `2bc290e` (event `push`, branch
  `main`): all three required jobs `success`. **This is the merged-code evidence anchor.**
  Step-level: the docs-only skip step = `skipped` (the heavy path really ran); `swift test`
  = **251 tests, 0 failures** on merged code; **step 17 "Run point query benchmark gate" =
  `success`** — the tenth gate is live; iOS compile and WASM observation genuinely *ran*.
- **`mode=point_query` appears in the hosted log with `gate=pass`, 4 times** — the exact
  **inverse** of the Slice 37 review's check (which confirmed `grep -c` returned `0`).
  The promotion is a verified fact.
- Hosted: **41 `gate=pass`, 0 `gate=fail`** (41, not 42, because `--realistic-provider` is
  the one gated mode CI never runs with `--gate`).
- **Hosted headroom: p95 max `12.5x` (ceiling 50x), p99 max `21.8x` (ceiling 100x).** The
  whole suite lands at 4.4x–12.5x — every gate is now genuinely failable, and nothing came
  close to tripping its own ceiling.
- **No non-gate observation step survives on `main`.** The design required the temporary
  `--point-query` (no `--gate`) harvesting step to be replaced in the same PR. `git show
  1eab4df:.github/workflows/swift-ci.yml` carries exactly one `point` step, and it is the
  gate. Verified.

### The additivity cross-check held

Decision 5 predicted that because `pointAt` is proven pure composition, its hosted median
must land near the **sum** of the two 1D medians — and said that if it came in materially
above, "the composite is doing work it should not, and that is a finding in its own right."
It did not: `point_query|uniform_1m` hosted median p95 = **83 ns** against
`line_query|uniform_1m` 40 ns + `column_query|uniform_1m` 40 ns = **80 ns**. The composite
costs what it should. A prediction that could have failed, and didn't, is worth more than a
budget that was merely accepted.

## Git History

Thirty-one non-merge commits, correct conventional-commit prefixes, spec → plan → tests →
implementation ordering. The sequence tells an honest story, including four self-corrections
made *during* the slice:

```text
56449d9 docs: add gate-budget recalibration design
7f4ae54 docs: fold the floor into the budget recipe and cover p99      <- design corrected itself
5db92c7 docs: add slice 38 gate-budget recalibration plan
aaefdd8 docs: commit the hosted gate-budget corpus and its derivation script
77352b0 feat: recalibrate the query and variable-height gate budgets
bc524ce feat: fail the gate when its own budget goes stale
4af9438 feat: add a p99 headroom ceiling alongside the p95 gate check
c1a0b3f ci: observe point-query latency on hosted Linux before gating it   <- observe...
a010098 feat: recalibrate pipeline 1m... budget above the 3x floor
0676492 docs: append the first hosted point-query samples to the budget corpus
afd8044 ci: promote --point-query to the tenth blocking gate               <- ...then gate
a99f2d1 fix: correct false floor claim in point-query provenance comment
34bfba1 feat: re-derive gate budgets from the enriched hosted corpus
e60e9f5 ci: fail the budget derivation on a mode with no corpus rows
4e4fefa ci: commit the hosted-corpus harvester
8fb157e feat: re-derive the realistic-provider budget from hosted evidence  <- the gate nobody named
257d551 test: pin the 3x floor over the committed corpus
2ed1a1b refactor: compute headroom once and evaluate the gate decision once
8e9ba2b fix: correct the gate comments that misdescribe their own tables
7440f96 docs: stop restating measured values in the budget comments
```

Three things stand out. **Decision 5's observe-then-gate sequence was actually executed**
(`c1a0b3f` adds a non-gate observation step; `afd8044` replaces it with the gate), so the
point budget rests on real hosted evidence rather than an inference from local numbers —
and an inert gate never entered CI, not even for one commit. **`--realistic-provider` was
found and fixed mid-slice** — the one gated mode with no corpus evidence, which the design's
own investigation had missed, and which `GateFloorTests` now makes impossible to repeat.
And `7440f96` removes measured values from the budget comments, because a comment quoting a
benchmark number is falsified by the next re-derivation.

## Code Review Findings

Reviewed across derivation correctness, gate logic, test integrity, the hard constraints,
CI wiring, and the durability of the new machinery. Every finding below was verified
against the code or reproduced by hand.

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The recalibration is correct, reproducible from committed evidence, and proven not to
have moved any measured path.

### P2 / Production Readiness

**1. The documented re-derivation loop is not idempotent: `harvest ... >> corpus.tsv`
re-appends runs the corpus already has.**
`AGENTS.md:256-258` prescribes
`./.github/scripts/harvest-gate-corpus.sh --limit 40 >> docs/.../2026-07-12-gate-budget-corpus.tsv`.
The harvester emits rows for whatever runs `gh run list` returns; it has **no awareness of
what is already in the corpus**, and there is no dedup step anywhere in the loop.

Reproduced: running `harvest-gate-corpus.sh --limit 10` today emits **9 runs, of which 2
are already in the committed corpus**. At the documented `--limit 40`, most of the window
would be re-appended. Duplicate rows **double-weight** those runs in `median()` — the term
that governs most budgets (`8 x median`) — and inflate the reported `n`, so the evidence
base looks stronger than it is. The corpus is the single source of truth `GateFloorTests`
enforces against, so silently corrupting it silently corrupts every budget derived
afterwards.

The **committed corpus is currently clean** — 927 rows resolve to 815 distinct
`(run, mode, scenario)` keys, and the 112-row difference is exactly the legitimate
`realistic_provider` structure (8 repetition rows per run × 16 runs). So this is a **trap
laid for the next agent**, not present corruption. But the next agent to hit
`reason=budget_stale` will follow the `AGENTS.md` recipe verbatim, and it will spring.

Note that `sort -u` is **not** a safe fix: two legitimate `realistic_provider` repetitions
with identical p95/p99 values would collapse into one, discarding a real sample. The right
fix is to make the harvester skip run IDs already present in the corpus (it can take the
corpus path as an argument), or to state the dedup step explicitly in `AGENTS.md`.

**2. The corpus is append-only and the floor is `3 x max()`, so budgets ratchet upward
monotonically — one noisy hosted sample permanently loosens a budget, and the floor test
then *enforces* the outlier.**

`line_geometry_query|uniform_1k` has a hosted p99 **median of 62 ns** and a single **330 ns**
sample — a 5.3x tail spike, almost certainly runner noise. The floor term `3 x max` therefore
sets its budget at **990 ns, which is 16x its median**, twice the 8x the recipe intends. Two
other scenarios are in the same position (`line_geometry_query|uniform_1m` at 10x median;
`column_query|uniform_100k`). All three are **floor-governed**, meaning a single bad sample —
not the algorithm — sets the budget.

The mechanism has no reverse gear:

- `max()` over an append-only corpus is **monotonically non-decreasing**. Budgets can only
  grow.
- `GateFloorTests` asserts `budget >= 3 x max(corpus)`, so the outlier is **load-bearing**:
  you *cannot* ship a tighter budget while that row exists. The only remedy is deleting the
  sample — i.e. curating the evidence — which is undocumented and cuts against the slice's
  own "the corpus is the evidence" ethos.
- Follow it to its end: a bad enough sample ratchets a budget past the 50x ceiling, the gate
  reports `budget_stale`, the agent dutifully re-derives — and the script returns a budget
  that **still violates the ceiling**, because the outlier is still in the corpus. That is a
  deadlock with no documented escape.

This is not imminent: it needs an outlier roughly 2x worse than any yet observed. But the
margin is already the thinnest in the suite — that same scenario shows **49.5x local p99
headroom against a 100x ceiling**, the closest anything comes to tripping its own ceiling,
and it got there on one noisy sample. The mechanism deserves an explicit decision (outlier
rejection, a trailing window of the last N runs, or a written curation policy) rather than
being left to accumulate.

### P3 / Minor But Valid

**1. The "13 scenarios must NOT be recipe-derived" carve-out lives only in prose.** The
design deliberately left 13 already-calibrated scenarios (`pipeline` ×2, `structural_mutation`
×3, `variable_height_mutation` ×3, `bulk_structural_mutation` ×5) at their pre-slice-38
budgets, because re-deriving them would *loosen* several. I confirmed this: the derive script
disagrees with all 13 shipped budgets, and would loosen 7 of them (e.g. `structural_mutation|1m`
250,000 → 280,000; `variable_height_mutation|1m` 60,000 → 81,000). All 13 clear the 3x floor,
and `GateFloorTests` enforces that.

But **`AGENTS.md` never says so.** Its recipe reads as universal. A future agent hitting
`reason=budget_stale` on `--structural-mutation` would follow the documented loop, run the
script for that mode, paste the output, and silently loosen it — and nothing would object,
because the looser budget still clears the floor and the ceiling. The consequence is bounded
(budgets stay in-band), so this is P3, not P2. But it is *precisely* the failure this slice
exists to repair — a budget convention that lives only in prose, defeated by copy-paste — and
it deserves one sentence in `AGENTS.md`. The `GateLogicTests` comment ("Do NOT 'complete' this
list") is the right instinct in the wrong file: it protects the *test*, not the *tables*.

**2. The corpus filename is date-stamped but is now a permanent, growing artifact.**
`docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` is hard-coded at
`GateFloorTests.swift:17` and is appended to by every future recalibration. The dated name
follows the verification-doc convention, but this file is not a record of one day's evidence —
it is the living evidence base. A future agent following the dated-artifact convention may
create a *new* dated corpus and silently orphan the floor test's inputs.

**3. `--point-query` has the thinnest sample base (n=6), and its budget is governed by the
median term, not the floor — contrary to what the design predicted.** Decision 5 reasoned that
"on a 3-sample base the **floors** bind, not the median terms." With 6 samples, `8 x median`
exceeds `3 x max` for all four point scenarios, so the budget rests on a median the design
itself warns is unstable on a thin base (it documented `column_geometry_query|prefixsum_100k`
moving its median 104 → 70 ns when one run dropped out). Hosted headroom is healthy
(10.3x–12.5x), so no action is needed — but this remains, as the design said, the budget most
likely to need revision, and the *reason* differs from the one recorded.

**4. `--realistic-provider` now has the most corpus evidence and the least enforcement.** It
contributes **128 of 927 corpus rows** — by far the largest `n`, because each hosted
observation line carries 8 repetition values — and its rows deliberately mix base-tree and
head-tree samples (documented in the harvester). Yet it is the one gated mode CI never runs
with `--gate`, so its recalibrated budget is enforced only by `GateFloorTests`' floor check
and by local runs. Sound as far as it goes; worth knowing that the mode with the richest
evidence is the one whose gate never fires in CI.

**5. `GateLogicTests`' exclusion list is a maintenance seam that inverts on first use.** The
`p99 >= 2 x p95` invariant is asserted over the recipe-derived tables only, with an explicit
"Do NOT complete this list" comment. Correct today. But the moment any excluded table *is*
re-derived, the instruction becomes wrong, and the comment does not say what to do then.

**6. Carried / standing items.** WASM remains observational; the realistic-provider
observation remains PR-only `continue-on-error`; the `Main` ruleset keeps its documented
bypass-actor shape. The Slice 37 P2 #2 (the core supplies an `inLine` a horizontal source
cannot bound-check, so a mismatched source pairing traps rather than returning `.failure`)
was **correctly deferred** here — it belongs to the `pointGeometryAt` slice, which inherits
the seam verbatim.

No P3 changes whether the merged result is correct.

## Risks And Gaps

### The gap the design named itself, and did not close

The design is unusually honest about what it does **not** buy, and this deserves to survive
into the roadmap rather than being quietly forgotten:

> Nothing in this design detects slow drift that a future recalibration **legitimises**: if
> the engine becomes 2x slower and the budgets are re-derived against the new medians, every
> gate stays green and no check ever consults the frame.

Every number this slice produces is a **regression** budget, anchored to the scenario's own
hosted median. There is still no **absolute** budget anywhere in the project — nothing that
turns the brief's "60 FPS" into a headless threshold that is *never* recalibrated. The gates
now catch a >=8x step change. They would not catch the engine getting 2x slower, twice, across
four slices, with each budget dutifully re-derived along the way. Combined with P2 #2's upward
ratchet, the system has a structural bias toward *drifting looser over time* — slowly, legally,
and with every gate green.

That is not a defect in Slice 38. It is the next question, and the design wrote it down rather
than implying it away.

### Noise, honestly bounded

The design refuses to claim it can catch a 2x regression, and it is right to: hosted p95 varies
by up to **2.71x** on an unchanged binary. A p95 gate on a shared runner cannot resolve a 2x
regression from noise at any budget that does not flake. What was bought is detection of the
**>=8x class** — linear scan, lost `O(log N)`, allocation in the hot path — and the slice says
so plainly instead of implying more. The residual flake risk is real (strict required checks
mean a flaking gate blocks *every* PR), and is mitigated by the 3x floor over the **worst** of
the corpus's 927 samples, not the median.

### The ceiling will fire on a legitimate optimization

Local headroom sits at 8.7x–23.4x, so a ~2.2x speed-up on a hot path pushes a scenario past the
50x ceiling and opens the next optimization slice with a **red gate on its own win**. This has
direct precedent — Slices 29/30 cut `lineAt` from O(log²N) to O(log N), and the roadmap's native
column inverse would do the same to `columnAt`. The design accepts this deliberately in exchange
for one code path and a ceiling nobody can quietly bypass, and `AGENTS.md` states the policy:
**raise the budget, never the ceiling**, in the same PR that caused the shift. Worth flagging so
the next agent recognizes `reason=budget_stale` on a green-looking optimization as *the ceiling
working*, not a bug.

## Lessons For The Next Slice

1. **A placeholder with no redemption step is a permanent decision.** Slice 27 wrote "starter
   budgets (macOS-calibrated in Step 6)" and Step 6 was "run the tests." That parenthetical
   promise cost five slices of inert gates. If a value is provisional, the step that makes it
   real must exist *in the plan*, with its own checkbox — otherwise the word "starter" is
   decoration.
2. **Make the derivation executable, not a table.** The design's own evidence table now carries
   a "SUPERSEDED — do not copy these numbers" banner pointing at the script. A committed script
   plus a committed corpus can be re-run by a skeptic; a table in a document can only be trusted
   or copied — and copying is how this bug spread.
3. **Test the half of the invariant the runtime cannot see.** The gate can detect a budget that
   is too loose; it is structurally blind to one that is too tight. `GateFloorTests` exists for
   exactly that blind half. When a check can only see one side of a band, something else has to
   watch the other.
4. **Watch what a monotone rule does over time.** `3 x max()` over an append-only corpus can
   only ratchet upward, so one noisy sample loosens a budget permanently — and the floor test
   then makes that outlier load-bearing. A rule that is right on today's data can still be wrong
   as a *process*. Ask what it converges to.
5. **The prediction that could have failed is the one worth making.** Decision 5 committed, in
   advance, to a falsifiable claim: the point-query median must land near the sum of the two 1D
   medians, and if it didn't, "that is a finding in its own right, not a budget to be widened
   around." It came in at 83 ns against a predicted 80 ns. Cross-checks that *could* fail are
   what make a thin sample base defensible.

## Slice 39 Candidate Options

### Option A: `pointGeometryAt(x:y:)` — the geometry-bearing 2D composite

Compose `lineGeometryAt` ∘ `columnGeometryAt` into a 2D result carrying each axis's box +
fraction + clamp: the primitive a click-to-caret / caret-snapping consumer actually wants, and
the explicit deferral from Slice 37's scoping. It is this design's own Recommended Next Step,
and the natural home for Slice 37's still-open **P2 #2** — deciding what a mismatched
line/column source pairing should do now that the *core* supplies the `inLine` index (today it
traps). The gate machinery is now trustworthy enough that a new gate is worth minting.

### Option B: harden the calibration loop (P2 #1 + P2 #2)

Make the harvest idempotent (skip run IDs already in the corpus) and settle the outlier ratchet
(rejection, a trailing window, or a written curation policy). Small, mechanical, and it protects
the machinery every future slice now depends on. P2 #1 in particular is a trap that springs on
whoever next re-derives — which could be Option A, if it trips the ceiling.

### Option C: the absolute (product) budget

The gap the design named and left open: a second, *never-recalibrated* threshold per scenario
(any query < 1 µs; a viewport compute < 1 ms ≈ 6% of a frame), so that legitimate slow drift
cannot be laundered green by successive re-derivations. The intellectually strongest of the
three — it closes the one hole this slice's own machinery cannot — but it changes what a gate
*means* and deserves its own design.

### Option D / E: horizontal native descent; standing infra

Native `columnIndex` overrides for the two horizontal providers; or WASM-blocking / arm64 runner
migration (which, per the design, would itself require a full re-baseline and would trip the
ceiling by design).

## Recommended Slice 39 Selection

Recommended Slice 39 is **Option A — `pointGeometryAt(x:y:)`** — with **Option B folded in as a
precursor commit or a small companion**, not as its own slice.

The reasoning: the project's functional → promotion rhythm has been interrupted for one slice by
necessary governance work, and that work is now done and *proven* done — the gates went from
"cannot fail" to failable, and I verified both new guards by breaking the tree. The product arc
should resume, and `pointGeometryAt` is both the design's own recommendation and the natural home
for Slice 37's open P2 #2. Meanwhile P2 #1 (the non-idempotent harvest) is small, and it is a trap
laid directly in the path of whoever next re-derives a budget — which Option A may well do if it
shifts a hot path. Fixing a two-line script hazard inside the next slice is cheaper than
discovering it as a silently-skewed corpus.

**Option C is the one to keep on the roadmap and not lose.** It is the only candidate that closes
the structural hole this slice's own design named: regression budgets anchored to a moving median
can be re-derived into permanent looseness, and combined with the P2 #2 ratchet the system drifts
looser over time with every gate green. That is a real, if slow, failure mode — and it is exactly
the kind that this project has now twice proven it will otherwise discover five slices late.

Per the standing convention, keep functional/capability work and CI/infra work in separate
slices — Option B is admitted as a companion only because it is a script hazard measured in lines,
not a governance slice.

## Slice 38 Review Conclusion

Slice 38 repaired the defect that mattered most in this project: **the regression gates could not
fail.** For five slices the brief's blocking-benchmark criterion was satisfied on paper and empty
in practice, because Slice 27's "starter budget (macOS-calibrated in Step 6)" was never
calibrated in a Step 6 that did not exist, and four subsequent slices copy-pasted it. Hosted
headroom across the gated suite has moved from **815x–3,000x to 4.4x–12.5x**, and `--point-query`
is now the **tenth blocking hosted gate** with an honest budget rather than an inert one.

The review found **no P0 and no P1**, and — unusually — I was able to verify the slice's central
claim rather than accept it: **all 29 recalibrated budgets reproduce byte-for-byte** when I re-ran
the committed derivation script against the committed corpus, and the 13 that differ are exactly
the ones the design deliberately left alone. Nothing was hand-typed. The core diff is **zero
lines**, both Foundation scans are empty, and every gate checksum is byte-identical to Slice 37 —
so the recalibration provably moved no measured path. I mutation-tested both new guards rather
than trusting them: reverting one budget to its old value produces
`headroom_p95=5000.0x gate=fail reason=budget_stale` and exit code `1`, and dropping a budget
below the 3x floor makes `GateFloorTests` fail with an actionable message. Hosted proof is
anchored on merged code at step level (push run `29196145560`, merge `2bc290e`, second parent
`8e7c062`), where `mode=point_query` now appears **with `gate=pass`** — the exact inverse of the
check the Slice 37 review ran. Decision 5's observe-then-gate sequence was genuinely executed, so
an inert gate never entered CI even for a single commit, and the falsifiable additivity prediction
it rested on **held** (83 ns observed against 80 ns predicted).

Two **P2**s are forward-looking, and both concern the durability of the new machinery rather than
its correctness today. The documented re-derivation loop is **not idempotent** — `harvest >> corpus`
re-appends runs the corpus already has (2 of 9 at `--limit 10`), which will silently skew the
median for whoever next follows the recipe; the committed corpus is clean, so this is a trap, not
damage. And the `3 x max()` floor over an append-only corpus is a **one-way ratchet**: one noisy
330 ns sample has already pinned `line_geometry_query|uniform_1k`'s p99 budget at 16x its median
instead of 8x, `GateFloorTests` now *enforces* that outlier, and there is no documented way to
retire it. Six P3s are minor, the sharpest being that the "13 scenarios must not be recipe-derived"
carve-out lives only in prose — the very failure mode this slice exists to repair.

The most valuable thing in the slice is not a budget. It is that the budgets are now **derived by a
committed script from committed evidence**, that the gate **detects its own inflation**, and that
`GateFloorTests` watches the half of the band the runtime gate structurally cannot see. A gate that
cannot fail is not a gate; ten of them now can. What remains open — and the design says so itself,
plainly, rather than implying it away — is that every budget here is a *regression* budget anchored
to a moving median, so legitimate slow drift can still be re-derived green. That is the hole worth
closing next, and it is on the record.
