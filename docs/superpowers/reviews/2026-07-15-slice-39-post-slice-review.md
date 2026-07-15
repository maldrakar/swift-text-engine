# Slice 39 Post-Slice Review

Date: 2026-07-15

## Scope Reviewed

This review covers Slice 39: **`pointGeometryAt(x:y:lineMetrics:columnMetrics:)`** — the
geometry-bearing companion to `pointAt`, and the primitive a click-to-caret consumer
actually wants: one point in, both axes' boxes, within-box fractions, and clamp flags out.

It is the slice both the Slice 38 review (Option A — "the design's own Recommended Next
Step") and the Slice 37 point-query design ("Geometry-bearing `pointGeometryAt(x:y:)`
(recommended next)") pointed at, resuming the product arc after Slice 38's one-slice
governance detour. It is also the **first functional slice to mint a gated budget under
Slice 38's rules** — no hand-typed placeholder is legal any more — so its central risk was
never the ~12 lines of core composition; it was whether the derived-budget machinery would
hold on first real use.

The slice shipped through **two** PRs, both now merged:

- **PR #84** (`slice-39-point-geometry-query`), reviewed head `6e0f1de`, merged as
  `163f4ad` — the core query, its types, the benchmark mode, the oracle grid, the corpus
  harvest, the derived budgets, the CI steps, `AGENTS.md`, and the docs.
- **PR #85** (`slice-39-post-merge-hosted-proof`), a docs-only follow-up recording the
  post-merge `push` run, merged as `b023b91` (current `main` HEAD).

Merge parentage confirmed by hand: `git rev-parse 163f4ad^2` → `6e0f1de`, the PR-head
commit. The proof anchors the actually-merged code.

Reviewed artifacts: the design, plan, and verification records; the merged diff
(`163f4ad^1..163f4ad`); the two core files; the benchmark mode and its checksum fold; the
2×2 oracle grid; the `isGateable` refactor; all 23 edited scenario tables; the CI workflow;
`AGENTS.md`; and both hosted runs at **step** level.

## Product Brief Alignment

The brief's first line asks for a core that «вычисляет геометрию» — computes geometry. The
design makes the plainest claim available and it is the right one: `pointAt` returns
indices; `pointGeometryAt` returns geometry, so this slice is closer to the literal text of
the brief than the query it extends. The brief's headless / Foundation-free / Embedded /
zero-dependency / sub-linear-memory constraints all hold and were re-verified below.

**The core diff is two files, +98/-0** (`git diff --stat 163f4ad^1 163f4ad --
Sources/TextEngineCore` → `PointGeometryQuery.swift` new, `ViewportTypes.swift` +32,
appended after `ColumnResolution` with nothing above it touched). No existing query,
protocol, provider, or error case is modified — acceptance criterion 3, verified. Both
Foundation-free scans (`Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`)
are empty. No dependency was added.

## Delivered Design

### Composition, not computation

`pointGeometryAt` is Decision 2 verbatim: a `switch` over `lineGeometryAt(y:)` whose
success feeds the located line index into `columnGeometryAt(x:inLine:)`. Vertical runs
first for the forced reason — the horizontal query needs an `inLine`, and only a vertical
success supplies one. It performs **no search of its own** (both inverse searches stay
inside the 1D queries, which dispatch to the provider-native hooks) and **no arithmetic of
its own** — every box and fraction is produced by the single existing implementation on
that axis. Over `pointAt` it adds a constant number of probes (up to four on a located
cell, fewer on a blank line or a failure), so its per-provider cost class **equals
`pointAt`'s**: O(log N) + O(log M) queries, O(1) core memory.

The alternative — composing over `pointAt` and hand-writing the four box probes here —
would have bought 2D-ordering parity with `pointAt` by construction but paid for it with a
third hand-written copy of the fraction rule, whose clamp trap (`fraction` pinned to
`0.0`/`1.0` rather than computed from a coordinate *outside* the box) is exactly where a
copy silently drifts. The chosen side buys the property that cannot be recovered cheaply —
no new arithmetic — and pays with ~12 lines of `switch` that the parity oracles pin
completely.

### The result shape is `PointQuery`'s, one level richer

`PointGeometryQuery` (`.geometry` / `.empty` / `.failure`), `PointGeometryLocation`
(`line: LineGeometryLocation` + `column: ColumnGeometryResolution`), and
`ColumnGeometryResolution` (`.cell` / `.blankLine`) mirror `PointQuery` with each component
swapped for its geometry-bearing counterpart. Two properties this shape buys and I
confirmed in the code: a located line is **never lost to a blank cell** —
`PointGeometryLocation.line` always carries the full `LineGeometryLocation`, even when
`column == .blankLine`, because the caret box of an empty line is exactly what a consumer
needs there — and **no line index is duplicated**, since `LineGeometry`/`ColumnGeometry`
already carry theirs.

### The checksum folds the geometry, not just the indices

This is the sharpest design judgment in the benchmark. `--point-query`'s checksum
accumulates `lineIndex + clamp + columnIndex + clamp`, which is right for a query returning
only indices — but it is the *wrong* anchor here: the entire payload this slice adds (two
boxes, two fractions) would be **absent** from the "workload unchanged" checksum that Slice
40's promotion leans on, so a drifted fraction would leave it byte-identical. The mode folds
`Double.bitPattern` of `y`, `height`, `x`, `width`, and both fractions with **distinct odd
multipliers per field** (19/3/5/7 line, 23/11/13/17 cell), which also closes the Slice 37
P3 #5 weakness where an additive fold made an axis *swap* invisible. I verified the four
checksums are bit-identical across my local macOS arm64 run, the recorded hosted Linux
x86_64 runs, and the post-merge run — the anchor tracks the computed geometry and is blind
to timing, which is exactly the separation it needs.

### Decision 4 closes Slice 37 P2 #2 by decision, not code

The two-source pairing stays a **documented precondition**. The reasoning is structural,
not lazy: `LineHorizontalMetricsSource` deliberately models no line count
(`UniformColumnMetrics.columnCount(inLine:)` ignores its argument, holding O(1) memory for
a document of any size), so the core *cannot* validate the pairing with the information the
protocol exposes. The design walks all three alternatives and rejects each on its merits —
notably the defaulted `lineCountHint`, whose cost it corrects rather than inflates: it
would put a field in the public protocol the core cannot check for honesty, give the
strongest guarantee to the providers that need it least, and enable only a debug-build
`assert` that is compiled out of the release where the trap still fires. This is a sound
call; the residual risk is noted under Risks below.

## Verification Evidence Reviewed

I did not take the slice's claims on trust. Fresh local checks on the merged tree at
`163f4ad`:

- **`swift test` → 290 tests, 0 failures** (plus the documented harmless "0 tests in 0
  suites" Swift Testing line). Matches the record's post-second-round count exactly.
- **`swift build -c release` → `Build complete!`**
- **Foundation-free scan empty** for both the core and the reference-provider library
  (`rg` exit 1, no matches). The new core file imports nothing — a pure
  `extension ViewportVirtualizer`, stdlib-only.
- **The four `point_geometry_query` budgets reproduce byte-for-byte from the committed
  corpus.** I re-ran
  `./.github/scripts/derive-gate-budgets.sh <corpus> point-geometry-query` and it printed
  `budget_p95` 640 / 740 / 730 / 780 and `budget_p99` 1300 / 1500 / 1500 / 1600 — the exact
  literals in `pointGeometryQueryScenarios()`. `n=6`, the six-run harvest base, no more, no
  fewer. Nothing was hand-typed.
- **The two floor-repair budgets reproduce.** `line_query|uniform_1k` p95 → **220** and
  `column_query|uniform_100k` p99 → **620**, matching §6b, and both now clear the `3×max`
  floor they had silently dropped below before the harvest.
- **`--point-geometry-query --gate` passes locally**, all four `gate=pass`, exit 0, local
  headroom 11.8x–19.5x p95 / 20.5x–31.3x p99 (higher than hosted because local macOS is the
  faster machine), with checksums bit-identical to the recorded values.
- **The 23 edited scenario tables are budget-value + comment changes only.** I diffed
  `PointQueryBenchmark.swift` and `StructuralMutationBenchmark.swift`: every scenario's
  `lineCount` / `providerName` / `useVariableHeights` / viewport parameters are unchanged;
  only the budget literals moved. No benchmark or engine logic drifted with the
  recalibration — the harvest moved numbers, not paths.
- **The CI wiring is the two-step shape** Decision 5 / §11.1 require, confirmed in
  `git show 163f4ad:.github/workflows/swift-ci.yml`: a bare `--point-geometry-query` step
  **without** `continue-on-error` (correctness: blocking, output to a temp file so it does
  not double-weight future harvests), then a `--point-geometry-query --gate` step **with**
  `continue-on-error` (budget: observational until Slice 40). One step cannot be both;
  splitting them is correct.
- **The oracle grid is genuine.** `PointGeometryAtOracleTests` lives in
  `TextEngineReferenceProvidersTests` — the one target that can see both the core and the
  shipped `PrefixSum*` providers — and runs all three oracles plus the reconstruction
  property over the full 2×2 pairing grid, with the reconstruction asserting a minimum
  in-range hit count so its clamped-axis skip cannot make it vacuous.

### Hosted runs (verified at step level, not job conclusion)

Per the project's standing "a green job can hide a dead `continue-on-error` step" rule:

- **Six distinct harvested runs** (`29279467574` … `29285933609`) supplied the budget base;
  the harvest dedup key is the run id, so these are six real pushes, not re-runs.
- **Post-merge `push` run `29426572267`** on merge commit `163f4ad`: all three required
  jobs `success`. Step-level: `docs_only_pr=false` (heavy path ran), `swift test` **290/0**
  on merged code, the bare point-geometry correctness step blocking-and-green, the gated
  step `gate=pass` ×4 with checksums bit-identical to every other recording, whole-run tally
  **45 `gate=pass` / 0 fail** (46 gated budgets minus `realistic_provider`, which CI never
  runs with `--gate`), iOS device+simulator `pass` for both products, WASM the expected
  non-blocking `sdk_unavailable` skip. This is the merged-code evidence anchor.

### The two internal review rounds did real work

This branch was not merged on first pass. Two documented review rounds (§10, §11) found and
fixed **ten** distinct issues before merge, and the fixes were mutation-tested, not assumed
— each new guard was broken on purpose and watched go red. Three of those findings are worth
naming because they were genuine defects a lighter review would have shipped:

1. **The CI gate step had gone failure-blind** (§11.1). `b378554` flipped the step to
   `--gate` and left `continue-on-error` on it — which swallows *every* non-zero exit, not
   just a budget one, so nothing blocking executed the point-geometry scenario table at all.
   This is the exact Slice 16 dead-step trap, and Decision 5's own prose described a workflow
   that had stopped existing. Fixed by the two-step split, demonstrated with
   `pointGeometryLineHeight = 0.0` making the bare step exit 1.
2. **Acceptance criterion 1 was unmet while §10 marked it Fixed** (§11.2). The oracles ran
   on two pairings, neither a real provider, and `TextEngineCoreTests` *physically cannot*
   reach `PrefixSum*`. The fix moved them to the reference-providers test target and the
   full 2×2 grid. The honesty of §11 correcting §10's own "Fixed" table is the review
   process working.
3. **`--gate` was an opt-out deny-list while the registry was opt-in** (§11.3), so a new
   mode became gate-accepting the moment it existed — budget-bearing yet invisible to the
   hand-written `everyGatedBudget()`. That drift *actually happened inside this branch*
   (`3673a43` missed the twelfth table; `a5ff213` repaired it). Fixed by the exhaustive
   `isGateable` switch pinned bidirectionally to the registry.

That a rigorous internal pass caught these is a strength of the slice, not a mark against
it — but it is the reason the P-list below is short: the sharpest findings were already
found and fixed on the branch.

## Git History

Twenty-six non-merge commits on PR #84, correct conventional-commit prefixes, spec → plan →
tests → implementation ordering, with the two review rounds visible as honest
self-correction (`5042747` splits the CI step, `74d0107` moves the oracles to the four
pairings, `ef79ebc` makes gate eligibility exhaustive, `6e0f1de` corrects the AC1 claim).
The observe-then-gate sequence Decision 5 prescribes was genuinely executed —
`6e49321`/`dbb6538` ship the mode with `nil`-then-non-`nil` budgets and the observational
step, `a23e559` harvests and enables `--gate` — so an inert gate never entered CI, and no
commit with a red `GateFloorTests` or a corpus disagreeing with its own budgets ever entered
the branch (§6b, Consequence 4).

## Code Review Findings

Reviewed across the core composition's correctness, the result-type shape, the checksum
fold, the derived-budget reproduction, the two-source precondition, the test integrity, the
CI wiring, and the hard constraints. Every finding was verified against the code or
reproduced by hand.

### P0 / Release Blockers

None.

### P1 / Must Fix Before Merge

None. The core is a correct, minimal, allocation-free composition whose every branch is
pinned by the 2×2 oracle grid; the budgets reproduce byte-for-byte from committed evidence;
and both hard constraints (Foundation-free, additive core diff) hold.

### P2 / Production Readiness

**1. The near-floor budget cluster is real, carried, and correctly deferred — but it is now
one nanosecond of runner noise away from reddening `GateFloorTests` on a clean tree, and the
next agent must be told which failure it is.** Six budgets repo-wide sit at or within ~5% of
the `3×max` floor after this slice (§7b), worst case `line_geometry_query|uniform_1k` p99 at
**0.0% margin**. I reproduced the cluster independently: deriving `line-query`,
`line-geometry-query`, and `column-query` against the committed corpus shows three margins
sitting exactly at 3.0x. Because `GateFloorTests` re-reads the corpus on **every** `swift
test` — a blocking step on every PR — a single future hosted sample nudging any of these
scenarios' maxima up by ~1 ns flips the assertion red on a clean tree with no code change,
blocking *all* PRs until the budget is re-derived.

This is **not a Slice 39 defect**: the fact-check in §10 falsified the causal story and
found three of the six rows were already at the floor before this branch existed (armed by
Slice 38's still-open P2 #2 — the `3×max` floor over an append-only corpus is a one-way
ratchet). This slice's marginal contribution is two tightened rows plus one new one, growing
the cluster 3 → 6. The slice paid the right debt: it moved the warning out of the
verification record and into `AGENTS.md`'s `## Gate budgets` (a harvest re-derives *every*
mode; sweep all of them; a post-harvest floor failure is `budget_stale`, not an engine
regression). The repair itself — outlier rejection, a trailing window, or a written curation
policy — belongs to Slice 40, and this mode is the concrete reason it should not slip again.

**2. The two-source pairing is an unbounded precondition that traps in production, and the
core now supplies the index that trips it.** Decision 4 closes the question deliberately: a
mismatched line/column source pairing traps rather than returning `.failure`, because the
horizontal protocol models no line count and the alternatives cost more than the bug. I
agree with the call as shipped — the three rejected options are each worse, and a trap is
Swift's idiom for a wiring mistake. But it is worth stating plainly as a standing risk that
the *core* now threads the vertical query's located index into the horizontal source, so a
consumer who pairs two different documents' sources gets a crash originating *inside* the
core's composition, not at their own call site. The design records the escape hatch: revisit
only if a real consumer ships a lazily-materialized horizontal source, and then the right
shape is a provider-side bounds check, not a core-side hint. No action this slice; flagged so
it is a decision on the record, not a gap rediscovered later.

### P3 / Minor But Valid

**1. The Decision 6 prediction "held" only under a comparison chosen after the pre-registered
one contradicted it.** §1 pre-registered, before the harvest, that each scenario's
`point_geometry_query` median p95 lands *above* its `point_query` counterpart and within
~30%. The naive pooled comparison (§7 View 1) then **contradicts the "above" half on 3 of 4
scenarios**. The record's argument that View 1 is unsound — n=6 vs n=21 drawn from largely
disjoint hosted run sets, under runner speed that varies ~2× per run as a whole — is
methodologically correct, and the paired same-run comparison (View 2) is the right test and
holds cleanly (~23–33% slower, direction and band both right). But the pre-registered
prediction as literally written is confirmed only under the reframed test, and the record
should not be read as a clean prediction pass. It is honest about both views, which is the
point; the falsifiable 2× "stop and investigate" threshold was the real guard, and nothing
approached it (widest single-run ratio 2.044×, from one already-identified outlier sample).

**2. The correlated sampler is carried debt, inherited on purpose.** Five of every eight
operations draw `x` and `y` from the same `deterministicScrollOffset` fraction, so the
workload walks a 1-D diagonal of ~1,000 points rather than the 2-D space (Slice 37 P3 #2).
Kept unchanged deliberately, because Decision 6 predicts this mode's latency against
`point_query`'s row by row and that comparison is only valid if the workload is identical —
decorrelating is a change to *both* modes and belongs to a slice that re-derives both
budgets. Correctly named as carried debt in the source, not an oversight; noting it so it
stays on the roadmap.

**3. The observational CI step spends hosted minutes for a mode that gates nothing yet.** One
benchmark run per CI run, for one slice, until Slice 40 promotes it. Accepted as the price of
a derived budget over a hand-typed one; the alternative (deferring the whole mode to Slice
40) would compress bootstrap + derive + promote into one slice, which is precisely the
compression that hid Slice 27's placeholder for five slices. Fine as shipped.

**4. `point_geometry_query` now carries the thinnest corpus base (n=6), and the design says
its budget is likeliest to need an upward re-derivation.** Healthy hosted headroom
(3.3x–6.9x p95 on the tightest run, `prefixsum_1m`) means no action, but it is the scenario
to watch first if this gate ever reddens — and `prefixsum_100k`'s `max/median` of 2.538 sits
only ~5% below the threshold at which its budget flips from median-governed to floor-governed
by a single outlier sample.

**5. Carried / standing items.** WASM remains observational; the realistic-provider
observation remains PR-only `continue-on-error`; the `Main` ruleset keeps its documented
bypass-actor shape. The absolute (product) budget — Slice 38's Option C, the only idea that
closes the "regression budgets anchored to a moving median can be re-derived green" hole —
remains open and unclaimed, and §8 records the groundwork: every scenario's hosted p99 clears
a 1 µs product line by 4.0×–6.4×, and that absolute ceiling and the derived regression
budgets are **different objects** a future Option C must reconcile, not assume agree.

No P3 changes whether the merged result is correct.

## Risks And Gaps

**The system still drifts looser over time, and this slice is the first to mint a budget
inside that drift.** Slice 38's review named the structural hole and left it open: every
budget here is a *regression* budget anchored to the scenario's own hosted median, so
legitimate slow drift can be re-derived green, and the `3×max` floor over an append-only
corpus can only ratchet upward. Slice 39 is the first functional slice to add a gated budget
under those rules, and it did so cleanly — six distinct runs, a recorded `max/median` spread,
and no floor-governed budget among its own four. But it also grew the near-floor cluster 3 →
6 (P2 #1), which is the ratchet biting in practice. The repair is scheduled (Slice 40), and
the warning is now in the file the next agent loads. That is the right disposition for this
slice; the gap itself is real and belongs to the roadmap, not to a defect list.

**The gate is genuinely failable now, which means it can also flake.** `prefixsum_1m`'s
hosted p95 headroom on the PR-head run was **3.3×** — the tightest anywhere in this mode,
close to the floor `GateFloorTests` enforces. This is the gate working as designed (a gate
that cannot fail is not a gate), not a bug, but strict required checks mean a flaking gate
blocks every PR. The mitigation is the same one the whole suite rests on: the floor sits over
the *worst* of the corpus's samples, not the median, and the mode is still only observational
until Slice 40 makes it blocking.

## Lessons For The Next Slice

1. **A `continue-on-error` step is failure-blind, not merely budget-blind.** `b378554`
   flipped the step to `--gate` and kept the flag, and it swallowed correctness failures
   too — nothing blocking executed the scenario table. This is the third time the project has
   met the Slice 16 dead-step trap. The two-step split (bare-blocking + gated-observational)
   is the durable shape; one step cannot be both.
2. **"Fixed" in a review record is a claim to verify, not a fact to inherit.** §10 marked
   AC1 Fixed; §11 found it was half-fixed and the oracles never met a real provider. The next
   agent would not have re-checked a line under "### Fixed." A review that corrects its own
   prior round is doing its job.
3. **An opt-out gate list plus an opt-in registry will drift, and only an eye catches it.**
   The deny-list made every new mode gateable by default while the checked registry was
   hand-written; the two diverged *inside this branch*. The exhaustive `isGateable` switch
   pinned bidirectionally to the registry turns that drift into a compile error. When two
   lists must agree, make one derive from the other or make disagreement fail to build.
4. **A prediction reframed after it contradicts is weaker evidence than one that passes as
   written.** View 2 is the sound comparison and it holds — but the pre-registered prediction
   was confirmed only after the pooled view failed it. Pre-register the *methodology*, not
   just the number, so the analysis that decides the outcome cannot be chosen after seeing
   the data.

## Slice 40 Candidate Options

### Option A: promote `--point-geometry-query` to the eleventh blocking gate — and repair the ratchet

The slice's own Recommended Next Step and the memory's recorded direction. **Zero Swift**:
harvest the accumulated hosted runs, re-derive, and delete the bare correctness step and the
`continue-on-error` on the gated step *together*, so the one step that survives is blocking
on both correctness and budget. It is also the natural and now-overdue home for **Slice 38's
still-open P2 #2** — the `3×max` floor over an append-only corpus as a one-way ratchet —
which P2 #1 above shows biting in practice (six budgets within ~5% of the floor, three
untouched by Slice 39). Slice 40 should *expect* a `GateFloorTests` failure of the §7b shape
after its own harvest and diagnose it as `budget_stale`, not an engine regression. This is
the one option that pays down live debt rather than opening new surface.

### Option B: the absolute (product) budget (Slice 38 Option C, still unclaimed)

A second, *never-recalibrated* threshold per scenario (§8's 1 µs product line is the
groundwork), so legitimate slow drift cannot be laundered green by successive
re-derivations. Intellectually the strongest open idea — it closes the one hole the whole
gate machinery cannot — but it changes what a gate *means* and deserves its own design and
its own slice, and §8 already flags that it must *reconcile* the absolute ceiling with the
regression budgets, not assume they agree.

### Option C / D: horizontal native descent; standing infra

Provider-native `columnIndex` overrides for the two horizontal providers (expect it to trip
the 50× column-gate ceiling — the ceiling working as designed; re-derive in the same PR); or
WASM-blocking / arm64-runner migration (a full re-baseline that would itself trip ceilings).

## Recommended Slice 40 Selection

Recommended Slice 40 is **Option A — promote `--point-geometry-query` to the eleventh
blocking gate, with the ratchet repair folded in as the same slice's substantive work**, not
deferred again.

The reasoning: the project's functional → promotion rhythm calls for a promotion slice next,
and it is a zero-Swift one exactly as 28/32/34/36 were. But the promotion is no longer the
interesting part — the interesting part is that Slice 39 has now demonstrated Slice 38's P2
#2 biting in practice, on real committed evidence, with a 0.0%-margin budget that a single
noisy sample turns red on a clean tree. That is precisely the class of latent hazard this
project has twice proven it will otherwise discover five slices late (Slice 27's placeholder;
Slice 38's `realistic_provider` gate). Slice 40 harvests and re-derives anyway — it is the
slice most likely to *trigger* the ratchet — so it is the cheapest possible place to also
*fix* it. Bundle the promotion with the curation policy (outlier rejection, a trailing
window, or a documented retirement step), and do not let the fix slip to a Slice 41 that may
never come.

**Option B is the one to keep on the roadmap and not lose.** It has now survived two reviews
as "the strongest open idea," and §8 has quietly built its groundwork (the 1 µs line, the
reconciliation warning). It closes the structural drift the regression budgets cannot, and it
is the natural sequel once the ratchet is repaired — a never-recalibrated floor is far safer
to add *after* the append-only ratchet stops pushing budgets upward.

Per the standing convention, keep functional/capability work and CI/infra work in separate
slices — the ratchet repair is admitted into Option A only because Slice 40 is already a
CI/infra promotion slice that must harvest and re-derive, so the fix lives in the same
concern, not a smuggled-in second one.

## Slice 39 Review Conclusion

Slice 39 resumed the product arc and delivered `pointGeometryAt` — the geometry-bearing 2D
hit-test a click-to-caret consumer actually wants — as a **correct, minimal, allocation-free
composition of the two 1D geometry queries**, with a core diff of exactly two files (+98/-0),
both Foundation scans empty, and no existing query, protocol, provider, or error case
touched. More importantly, it was the **first functional slice to mint a gated budget under
Slice 38's rules**, and it did so without reopening the hole Slice 38 closed: I re-ran the
committed derivation myself and **all four `point_geometry_query` budgets reproduce
byte-for-byte** from six distinct hosted runs of this PR — nothing hand-typed — and the two
floor-repair budgets the same harvest forced (`line_query|uniform_1k` → 220,
`column_query|uniform_100k` p99 → 620) reproduce as well.

The review found **no P0 and no P1**. The sharpest findings had already been found and fixed
*on the branch*: two internal review rounds caught a CI gate step gone failure-blind (the
Slice 16 dead-step trap, back for a third time), an acceptance criterion marked Fixed while
still unmet, and an opt-out gate list drifting from its opt-in registry inside the branch
itself — each fix mutation-tested rather than assumed. That a rigorous pass caught them is
the slice's process working, and the honesty of §11 correcting §10's own "Fixed" table is
worth as much as the fixes.

The one **P2** that carries forward is not this slice's defect and is correctly deferred: the
near-floor budget cluster — six budgets repo-wide within ~5% of the `3×max` floor, worst case
at **0.0% margin** — is Slice 38's still-open ratchet biting in practice, and Slice 39's
contribution is to grow it 3 → 6 and, crucially, to move the warning into `AGENTS.md` where
the next agent will actually read it. The checksum now folds the geometry the mode exists to
measure (bit-identical across two architectures and the merge), the oracle grid meets all
four provider pairings, and the CI step is the correct two-step shape. Hosted proof is
anchored on merged code at step level (push run `29426572267`, merge `163f4ad`, second parent
`6e0f1de`), where the gate passes on all four scenarios and every checksum matches.

What remains open — and both this review and Slice 38's say so plainly — is that the gate
budgets are *regression* budgets anchored to a moving median over an append-only corpus that
can only ratchet looser, and there is still no *absolute* product budget anywhere. Slice 40
is the promotion slice, it will harvest and re-derive, and it is therefore the right and
cheapest place to finally repair the ratchet rather than trigger it once more. The absolute
budget (Slice 38 Option C) stays the strongest idea on the roadmap, and §8 has already laid
its groundwork.
