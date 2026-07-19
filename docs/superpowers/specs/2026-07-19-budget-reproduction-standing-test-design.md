# Budget Reproduction Standing Test Design

Slice 44. Date: 2026-07-19.

## Status

Design. Supersedes no prior spec. Consumes the **Slice 43 post-slice review's P2 #2**
(carried from Slice 42 P2 #1) — the derivation *arithmetic* residual — and delivers that
review's recommended **Option A**: a standing test that re-derives every gate budget from
the windowed corpus and asserts byte-equality with the committed literals, making "every
budget is derived, never hand-typed" a build-enforced invariant instead of a per-slice
human discipline.

## Source Context

Gate budgets are committed as literals in the `ViewportBenchmarks` scenario tables
(`p95BudgetNanoseconds` / `p99BudgetNanoseconds`, one pair per gated scenario). AGENTS.md
`## Gate budgets` states, as an invariant, that each one is produced by a single sanctioned
recipe run over a corpus of hosted-CI samples:

```
budget_p95 = round_up_2sf(max(8 * median(hosted p95), 3 * max(hosted p95)))
budget_p99 = round_up_2sf(max(2 * budget_p95, 8 * median(p99), 3 * max(p99)))
```

`hosted` is a trailing window: the most-recent **N=20 distinct runs**, keyed on integer
run id. The recipe is a committed script, `.github/scripts/derive-gate-budgets.sh` — "the
only sanctioned source of a budget."

Slices 41–42 hardened the **window** on all three axes of "both consumers agree": the N
constant is cross-language pinned (`testWindowConstantMatchesDeriveScript`), the Swift
selection logic is CI-exercised (the whole floor suite reads through `corpusExtremes`), and
the shell selection logic is cross-pinned to Swift (`testWindowSelectionMatchesDeriveScript`
via the `--window-run-ids` seam). Slice 43 added the orthogonal **absolute product ceiling**.

What none of those closed is the **derivation *arithmetic* itself** (`8×median`, `3×max`,
`round_up_2sf`, and the p99 `2×budget_p95` floor). The Slice 42 spec named this exact gap
and named this exact slice as its closer:

> Closing it (a standing "reproduce every committed literal" test) pins selection **and**
> arithmetic together and couples to the budget-literal representation, which is why it is a
> separate slice, not folded in.

## Problem

The brief's success criterion is *«Регрессионные бенчмарки блокируют merge при деградации
производительности»*. That gate is only as trustworthy as the budgets it enforces, and a
budget is only trustworthy if it is *derived*, not typed. Today the "derived, never
hand-typed" invariant is guarded on the **tight** side and by **manual** discipline on the
loose side — the same asymmetric hole Slice 42 closed for the window *selection*, still open
for the derivation *arithmetic*.

### The uncaught direction

Consider a committed budget that drifts *looser* than the recipe would currently produce —
because a past harvest slid the window (an old freak sample aged out, lowering `max` or the
`median`) and the mode was never re-derived, or because a starter budget was hand-typed
loose (Slices 27/31/33/35/37 shipped exactly this, 815×–3000× loose, unfailable for five
slices). Of the two directions such a drift can take, one is caught and the other is not:

- A budget derived **tighter** than it should be is caught by `GateFloorTests`: it can fall
  below `3× (windowed max)` and the floor test reddens.
- A budget **looser** than the current recipe would produce — but still inside the band —
  slips past every standing guard:
  - **`GateFloorTests` passes** — a looser (larger) budget clears `3× windowedMax` with
    room.
  - **`testWindowConstantMatchesDeriveScript` / `testWindowSelectionMatchesDeriveScript`
    pass** — the *window* is unchanged; only the committed *number* is stale relative to
    what the window now derives.
  - **The runtime `--gate` catches only *gross* loosening.** Its ceilings (`headroom_p95 ≤
    50×`, `headroom_p99 ≤ 100×`, checked against this run's live latency, failing
    `budget_stale`) redden only if the stale budget is loose *enough* to push headroom past
    the ceiling. It is otherwise corpus-blind: within-band looser is invisible to it.

So a committed budget that is *within-band looser than the recipe now produces* is invisible
to the floor test, the window pins, and — below its 50×/100× ceiling — the runtime gate. That
is the precise blind spot. It is the same class of hole `GateFloorTests` itself was built to
close (an invariant left to a one-time or manual check instead of a standing one), and the
same direction Slice 42 closed for the selector.

### Why the manual check is not enough

AGENTS.md already mandates the fix by hand: "A harvest re-derives every mode, not the one you
came for… After harvesting, **sweep every mode** and re-commit every budget the recipe now
produces differently." Slice 39's review records that this was learned "the hard way" —
deriving only the touched mode left the others silently not-reproducing from the committed
corpus. The defect is not that the rule is wrong; it is that **nothing enforces it**, so a
forgotten mode stays stale until some unrelated slice happens to re-touch it. A discipline
that no build checks protects nothing.

## Scope

**In scope** — the calibration tooling only:

- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` — one new standing test,
  `testEveryCommittedBudgetReproducesFromCorpus`, that runs the sanctioned derivation script
  over the committed corpus and asserts every committed budget literal (via the existing
  `everyGatedBudget()` registry) byte-equals the script's derived `budget_p95` / `budget_p99`
  for its scenario. Reuses the file's existing `runProcess`, `repositoryRoot`, `corpusPath`,
  and `everyGatedBudget()`; introduces no new helper of substance beyond a small stdout
  parser.
- `AGENTS.md` — record that reproduction of every committed budget literal is now
  build-enforced (in `## Gate budgets`) and add the new test to the `GateFloorTests.swift`
  package-layout bullet.
- **Opportunistic P3 folds** (only because this slice already edits these two files):
  - **P3 #2** — the `## Gate budgets` "The two failure reasons are opposite instructions"
    clause now undercounts; a third reason (`budget_absolute_exceeded`, Slice 43) exists.
    One-clause fix to say three.
  - **P3 #1 (partial)** — soften the frozen `580 µs / 2.87×` figure in the
    `GateFloorTests.swift` comment on `testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling`
    (keep the structural claim, drop the number that rots per
    `measured-values-in-comments-rot`). The `BenchmarkModels.swift` and `AGENTS.md` copies
    stay out of scope — this slice does not otherwise touch that source file, and the
    AGENTS.md copy is illustrative prose the reproduction test does not falsify.

**Not in scope:**

- **Any change to `Sources/TextEngineCore` or `Sources/TextEngineReferenceProviders`.** Zero
  engine or provider behavior. Expected diff there: **zero lines**.
- **Any change to a budget literal, the corpus, `derive-gate-budgets.sh`, or any workload.**
  No harvest, no re-derivation — confirmed unnecessary: all **46 committed budgets** (a
  p95/p99 pair per gated scenario) already reproduce exactly from the current corpus
  (Testing Strategy step 1). All eleven gate
  checksums stay byte-identical to the Slice 43 baseline; that byte-identity is the proof the
  slice moved no measured path.
- **Removing or weakening `GateFloorTests`' floor/window tests.** They stay; the reproduction
  test is additive and gives distinct diagnostics (see Decision 4).
- **A bulk-edit absolute budget** (Slice 43 Option B), **harvester provenance hardening**
  (Option C), and **generalizing `WorkflowShapeTests`** (Option D). Separate concerns,
  separate slices.

## Goals

1. The derivation **arithmetic** gains a **standing** guard that fails a build (locally and
   in CI's host job) whenever a committed budget literal no longer reproduces from the
   windowed corpus — the fourth and last axis of "every budget is derived, never hand-typed,"
   joining the pinned constant, the CI-exercised Swift window, and the cross-pinned shell
   window.
2. The guard cross-checks the committed literal against the *sanctioned script's own output*,
   not against a Swift re-implementation of the recipe — so it also transitively guards the
   script, and cannot itself drift from the one source a human is told to run.
3. No engine, provider, workload, budget, corpus, or script change; every gate checksum
   stays byte-identical.

## Non-Goals

**Replacing the floor or window tests.** `testEveryGatedBudgetClearsTheFloorOnBothStatistics`
and the two window pins stay. On a clean tree the reproduction equality is strictly stronger
than the floor (a reproduced budget contains the `3×max` term by construction, so
`committed == derived ⇒ committed ≥ 3×max`), but the floor test gives a sharper, more
targeted diagnostic for the specific "too close to the worst sample" failure, and the window
pins isolate the *selection* with a discriminating fixture. Keeping all of them preserves
distinct failure messages for distinct causes.

**Re-implementing the recipe in Swift.** Rejected — see Decision 1. A Swift copy of
`round_up_2sf` / `median` / `3×max` would be a second arithmetic that could drift from the
shell (the exact anti-pattern Slice 42 fought), and would then itself need a cross-language
pin. Shelling out to the one sanctioned script is strictly less surface and a stronger
guarantee.

## Brief Alignment

This slice touches no engine latency and no budget number, so it cannot weaken or strengthen
any measured gate. What it hardens is the *machinery that keeps the budgets honest* — the
last manual-only axis of it. A committed budget looser than the recipe now produces is a
budget that blocks less than it should; a standing guard against that is a **more**
trustworthy regression gate, which is exactly what the brief's «блокируют merge при
деградации» criterion depends on. No Foundation enters the core (the subprocess and its
`Process` use live in the test target, which already imports Foundation to read the corpus,
and already launches bash for `testWindowSelectionMatchesDeriveScript`). No Embedded/iOS/WASM
surface is touched.

## Decisions

### Decision 1 — Shell out to the full derivation script, do not re-implement the arithmetic

The test must assert *committed literal == what the sanctioned derivation produces*. The
sanctioned derivation is `.github/scripts/derive-gate-budgets.sh`; AGENTS.md calls it "the
only sanctioned source of a budget." Shelling out to it pins the strongest available thing:
the committed number against the exact output a human is instructed to run. It also
transitively guards the script — if the awk `ru2` / `med` logic drifts, the committed
literals stop reproducing and this test reddens.

A Swift re-implementation would pin only `committed == swiftArithmetic`, leaving `script ==
swiftArithmetic` as a fresh, unpinned drift surface — and would duplicate the recipe, the
precise mistake Slice 42's whole thesis is against. It is strictly more code and a weaker
guarantee. Rejected.

This reuses the established seam: `GateFloorTests` already launches bash via `runProcess` for
`testWindowSelectionMatchesDeriveScript` (Slice 42), so no new dependency, environment
assumption, or first-in-target risk is introduced.

### Decision 2 — One invocation over all modes, keyed lookup

Run `derive-gate-budgets.sh <corpus>` **once with no mode argument** — the script derives
every scenario in the corpus and prints one line per `mode|scenario` key. The test parses
that into `[key: (p95, p99)]` and looks up each `everyGatedBudget()` entry by its `key`. This
is one subprocess launch (not one per mode), the output is keyed identically to
`everyGatedBudget()` (`mode.outputName|scenario`, corpus spelling), and extra derived keys
(if the corpus ever carried a non-gated scenario) are simply not looked up — the assertion is
one-directional: *every committed literal reproduces*, which is the invariant.

The script emits, per line: `<key>  n=… p95[…] p99[…] budget_p95=<int> budget_p99=<int>
margin…`. The parser splits on whitespace, takes field 0 as the key, and reads the integers
off the `budget_p95=` / `budget_p99=` tokens. The key never contains whitespace; the `%-46s`
left-pad never truncates a longer key (confirmed against the 52-char
`structural_mutation|100k_lines_80_visible_overscan_5`).

**Bonus — the test also transitively pins the script's output *shape*, not just its
arithmetic.** Because the parser skips any line whose `budget_p95=` / `budget_p99=` token is
absent, and Decision 3 requires *every* gated key to be present in the parsed map, a rename or
removal of those output tokens (or a per-line format change that drops them) produces a **loud
red** — the affected keys go missing and the `XCTAssertNotNil` fails — not a silent pass. The
guard therefore protects the `formatSummary`/derive-output contract as well as the recipe.

### Decision 3 — Non-vacuity and bijective cardinality are asserted explicitly

A guard that silently checks nothing is worse than none. The test asserts the derived map is
**non-empty**, and — because it iterates `everyGatedBudget()` and requires a derived entry
for every key — it fails loudly if any gated scenario is missing from the script output
(`XCTFail` naming the key), not just if a value mismatches. `everyGatedBudget()` is itself
kept exhaustive by the existing `testEveryGateableModeIsRegistered` /
`testNoUngateableModeIsRegistered` pins, so "every gated budget" is a trustworthy universe. A
subprocess launch failure or non-zero exit is a loud `XCTFail` carrying captured stderr,
never a skip.

The forward direction above (every committed budget reproduces) is made **bijective** with a
cardinality assertion — `XCTAssertEqual(derived.count, everyGatedBudget().count)` — so the
guard also catches the *reverse* drift: a scenario that enters the corpus and derivation but
was never registered as a gated budget. This holds with zero cost today
(`derived.count == 46 == everyGatedBudget().count`, verified during design). The honest
trade-off: it forbids the corpus from carrying a scenario no gate registers — which the
one-directional lookup of Decision 2 otherwise tolerates. That is the intended, stricter
posture; the assertion carries a comment to **relax it to `derived.count >=
everyGatedBudget().count`** if a non-gated scenario is ever *consciously* introduced into the
corpus (e.g. an observation-only row), rather than silently.

### Decision 4 — What reproduction catches that the floor test cannot

The headline reason the reproduction test is not redundant with the floor test is the case
where the **`8×median` term governs the recipe, not `3×max`** — i.e. `8×median > 3×max`, so
the correct budget is `round_up_2sf(8×median)`. There, a committed budget that has drifted
*looser* than the recipe now produces (say `≈10×median`) still clears `3×max` with room, so the
**floor test — which only sees the `3×max` term — is blind to it**. The reproduction test
catches it, because `committed ≠ round_up_2sf(8×median)`. That within-band-looser,
median-governed drift *is* the residual this slice closes; it is the same shape the Problem
section describes ("a looser budget clears `3×max` with room"), and the floor test structurally
cannot see it.

Secondarily, on a clean tree `committed == derived` also implies `committed ≥ 3×max` (the
derivation's own `3×max` term), so the reproduction test is *logically* stronger than the floor
test there. That is why both are kept rather than the floor test being the primary guard — but
"strictly stronger on a clean tree" is the weaker framing; the load-bearing justification is the
median-governed blind spot above.

The floor test is nonetheless retained, for three reasons: (a) distinct diagnostics — the floor
test says "below 3× the worst sample, will flake on a clean tree," the reproduction test says
"no longer reproduces, re-derive"; (b) the floor test is the load-bearing documentation of "the
half the runtime gate cannot see" and is referenced across AGENTS.md; (c) defence in depth —
should the reproduction test ever be weakened or the script change shape, the floor test still
independently backstops the flake-on-clean-tree failure mode. No test is removed.

### Decision 5 — Subprocess launch is safe in this test target (unchanged from Slice 42)

`ViewportBenchmarksTests` runs `swift test` only in the host job (Linux,
`swift:6.2.1-bookworm`, bash present) and locally on macOS; it never runs on iOS/WASM (those
jobs only *compile* the core/providers). `Foundation.Process` launching bash is therefore
available wherever this test executes, exactly as it already is for
`testWindowSelectionMatchesDeriveScript`. Nothing crosses into the Foundation-free core.

## Implementation Architecture

### `Tests/ViewportBenchmarksTests/GateFloorTests.swift`

One new test method plus a tiny parser, both file-scoped beside the existing corpus/window
machinery:

- A parser `derivedBudgets(fromScriptOutput:) -> [String: (p95: Int64, p99: Int64)]` (or an
  inline equivalent): for each non-empty stdout line, split on whitespace; field 0 is the
  key; scan the remaining tokens for `budget_p95=` / `budget_p99=` prefixes and parse the
  trailing integer. A line missing either token is skipped (defensive; the derivation always
  emits both for a real scenario line).
- `testEveryCommittedBudgetReproducesFromCorpus`:
  1. Resolve the script and corpus paths via `repositoryRoot()` + `corpusPath`.
  2. Launch `/usr/bin/env bash <script> <corpusAbsolutePath>` via the existing `runProcess`
     with empty stdin; `XCTAssertEqual(exitCode, 0)` carrying stderr on failure.
  3. Parse stdout; `XCTAssertFalse(derived.isEmpty)` (non-vacuity) and
     `XCTAssertEqual(derived.count, everyGatedBudget().count)` (bijective cardinality, with the
     relax-to-`>=` comment) — both Decision 3.
  4. For every `budget` in `everyGatedBudget()`: `XCTAssertNotNil(derived[budget.key])`
     (missing scenario → loud fail), then assert `derived[budget.key]!.p95 == budget.p95` and
     `.p99 == budget.p99`, with a message pointing at
     `.github/scripts/derive-gate-budgets.sh` and framing a mismatch as `budget_stale`
     (re-derive), never an engine regression.

The test reuses `runProcess` and `repositoryRoot` unchanged; it adds no new Foundation
surface beyond what the file already imports.

### Documentation

- `AGENTS.md` `## Gate budgets`: a sentence recording that
  `testEveryCommittedBudgetReproducesFromCorpus` now re-derives every committed budget from
  the windowed corpus and fails the build if any literal no longer reproduces — so "every
  budget is derived, never hand-typed" is build-enforced, not a per-slice discipline. Fold
  **P3 #2** in the same section: correct "The two failure reasons are opposite instructions"
  to reflect the three reasons (`budget_exceeded` / `budget_stale` / `budget_absolute_exceeded`).
- `AGENTS.md` package-layout `GateFloorTests.swift` bullet: add the reproduction test to the
  enumerated guards.
- `GateFloorTests.swift` (P3 #1 partial): soften the `580 µs / 2.87×` figure in the
  `testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling` comment.

### Verification record

`docs/superpowers/verification/2026-07-19-budget-reproduction-standing-test.md` — the new
test's green run inside full `swift test`; the **guard-is-live demonstration** (perturb one
committed budget literal by one 2sf step, show the reproduction test red with the
re-derive/`budget_stale` message, revert, show green); the pre-existing all-reproduce check
(Testing Strategy step 1) captured as evidence; the synthetic `--gate` still `gate=pass`; the
Foundation-free scan empty; `git diff --name-only` showing zero
`Sources/TextEngineCore`/`Sources/TextEngineReferenceProviders`/budget-literal/corpus/script
paths; all eleven `--gate` modes `gate=pass` locally with checksums byte-identical to the
Slice 43 baseline; and the hosted PR-head and post-merge push run IDs read at step level.

## Testing Strategy

TDD, per the project norm. This is a guard test: it is green the moment it exists, because
every committed literal already reproduces. "Red-first" for a guard means proving the guard
*can* fail — the established pattern in this repo (Slices 41–43 each demonstrated their guard
live).

1. **Pre-condition check (evidence, not a test):** run
   `derive-gate-budgets.sh <corpus>` and confirm all 46 committed budgets (a p95/p99 pair per
   gated scenario) already reproduce exactly, and that `everyGatedBudget().count == 46 ==` the
   distinct-key count the script emits — so the slice is purely additive, needs no
   re-derivation, and the bijective cardinality assertion (Decision 3) holds on introduction.
   (Established during design — the twelve gated scenario functions return 3+1+3+3+3+5+5+5+5+5+4+4
   = 46, matching the corpus exactly; re-captured in the verification record.)
2. **`testEveryCommittedBudgetReproducesFromCorpus`** — written first, watched go green.
3. **Guard-is-live demonstration** — temporarily edit one committed budget literal (e.g. bump
   a `p99BudgetNanoseconds` to the next 2sf value) and confirm the new test goes **red** with
   the re-derive message; revert and confirm green. Recorded in the verification doc, not
   committed. This proves the assertion is real, not vacuously satisfied.
4. **Full `swift test`** — all prior tests plus the new one pass, green on hosted Linux, not
   only locally.
5. **Byte-identity** — all eleven `--gate` checksums identical to the Slice 43 baseline; the
   Foundation-free scan empty; zero engine/provider/budget/corpus/script diff.

## Acceptance Criteria

1. `testEveryCommittedBudgetReproducesFromCorpus` runs `derive-gate-budgets.sh <corpus>`
   (no mode argument, over the committed corpus) and asserts every `everyGatedBudget()`
   literal byte-equals the script's derived `budget_p95` / `budget_p99` for its key, on both
   statistics.
2. The test is demonstrably **live**: a one-step perturbation of any committed budget literal
   reddens it (shown in the verification record). A subprocess launch failure or non-zero
   exit is a loud `XCTFail` carrying captured stderr, never a skip; the derived map is
   asserted non-empty, its cardinality is asserted equal to `everyGatedBudget().count`
   (bijective), and every gated key is asserted present, so the guard cannot silently no-op.
3. `swift test` passes in full (existing suite + the new test), green on hosted Linux.
4. `git diff --name-only` shows **no path under `Sources/TextEngineCore` or
   `Sources/TextEngineReferenceProviders`**, and no budget-literal, corpus, or
   `derive-gate-budgets.sh` change.
5. All eleven `--gate` modes report `gate=pass` locally, and all query/mutation checksums are
   byte-identical to the Slice 43 baseline.
6. `AGENTS.md` records the reproduction guard (in `## Gate budgets` and the `GateFloorTests`
   bullet); the P3 #2 "two failure reasons" clause is corrected to three; the P3 #1
   `580 µs / 2.87×` figure in the `GateFloorTests.swift` comment is softened.
7. Hosted: the three required jobs and all eleven blocking gates green on the PR head and on
   the post-merge push run, read at **step level** (a `continue-on-error` step can conclude a
   job green while its own step failed).

## Risks And Gaps

### The reproduction test reddens after a harvest until re-derivation — by design

Once this lands, any future harvest that shifts a median/max enough to move a 2sf-rounded
budget makes `swift test` red (`budget_stale`) until that mode is re-derived and re-committed.
This is the enforced teeth, not a defect: it mechanically realizes AGENTS.md's existing
"sweep every mode after a harvest" rule, and it exactly mirrors the floor test's already-
documented post-harvest behavior (a `GateFloorTests` failure after a harvest is `budget_stale`,
not an engine regression). The `round_up_2sf` rounding gives natural hysteresis — most small
median/max moves round to the same 2sf value and do not trip the test. AGENTS.md will state
this explicitly so a post-harvest red is diagnosed as re-derive, not as a slowdown.

### Runtime coupling to bash and the corpus file

The test launches bash and reads the committed corpus on every `swift test`. Already true for
`testWindowSelectionMatchesDeriveScript`; same host-only (Linux CI + local macOS) environment,
same `runProcess` helper, no new dependency. A launch/exit failure is a loud `XCTFail` with
captured stderr, never a skip. The hosted PR-head and post-merge runs (AC7) are the proof it
runs green on Linux, not only locally.

### The test's correctness crosses the BSD-awk(local) / Linux-awk(CI) boundary

This is the first standing test that runs the derivation *arithmetic* (`ru2` / `med`, in awk)
inside `swift test` and compares its output byte-for-byte with a Swift literal — where prior
tests compared only the window *selection* (run ids), this compares the derived *numbers*.
Locally that awk is BSD awk (`awk version 20200816`); in CI it is Linux awk. The values are
integers within double-exact range (all `≤ ~5.8M`, far under 2^53), so BSD awk, gawk, and mawk
compute identical results — but the spec's guarantee that they agree rests, ultimately, on
**AC7 (hosted-green)**: the reproduction test passing on Linux CI *is* the proof BSD-awk and
Linux-awk agree on these committed budgets. As a bonus, this test is the first thing to
exercise `derive-gate-budgets.sh`'s awk on **both** platforms at all — the derivation's
arithmetic was previously covered by no test on either — so it hardens the script itself, not
only the literals.

### Interaction with a concurrently-merged harvest

If another slice harvests and re-derives (moving a budget) and merges first, this slice's
reproduction test could go red on rebase — the committed literals here would no longer match a
corpus the base branch has since changed. This is caught, not by anything in this slice, but by
the repo's **strict required-status-checks** policy (AGENTS.md: "PRs must be tested with the
latest base branch state"): a PR is re-tested against the updated base before it can merge, so a
stale reproduction cannot land. The remedy is the ordinary one — rebase and re-derive.

### The floor test becomes a strict corollary on a clean tree

`committed == derived ⇒ committed ≥ 3×max`, so on a clean tree a passing reproduction test
implies a passing floor test. Kept anyway (Decision 4) for distinct diagnostics and defence
in depth. Not a gap — a deliberate, documented redundancy.

### Harvester provenance and p95 thin axis unchanged

`harvest-gate-corpus.sh` still selects by run id alone (Slice 42 P2 #3, a separate slice), and
the sub-µs `line`/`column`/`point` cluster remains the thin p95 axis to watch on any hosted
`budget_stale` (Slice 41/42 P2 #4). Untouched here; carried forward.

### Standing items unchanged

WASM stays observational; the realistic-provider observation stays PR-only
`continue-on-error`; the `Main` ruleset keeps its documented bypass-actor shape.

## Recommended Next Step

With the reproduction test landing, "every budget is derived, never hand-typed" is fully
build-enforced and the *calibration-tooling* story that ran from Slice 38 through 44 is
closed on every axis (constant, Swift selection, shell selection, absolute ceiling, and now
derivation arithmetic). The natural successors are **product** or **functional**, not more
tooling:

- **Slice 43 Option B — a bulk-edit absolute budget** anchored to a bulk-appropriate target
  ("a 4096-line paste in ≤ N frames"), closing the one deliberate residual the absolute
  ceiling left open. Advances the *product* story; needs a product decision on N first.
- **A return to engine capability** (static since Slice 39's `pointGeometryAt`) — e.g.
  selection/range geometry: given a text range, compute the highlight rectangles. A genuinely
  new public-API surface and the brief's actual heart, deferred through the recent
  infra-hardening run.

Harvester provenance hardening (Option C) and generalizing `WorkflowShapeTests` (Option D)
remain smaller infra alternatives.
