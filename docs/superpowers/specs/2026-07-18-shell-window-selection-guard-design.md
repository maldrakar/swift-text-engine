# Shell Window-Selection Standing Guard Design

Slice 42. Date: 2026-07-18.

## Status

Design. Supersedes no prior spec. Consumes the **Slice 41 post-slice review's P2 #1**
(the shell window-selection logic has no standing automated guard — only a manual
`--self-test`) and delivers that review's recommended **Option A**, in its stronger of
the two floated shapes: a Swift cross-language pin that ties the shell selector to the
Swift selector, rather than a new CI step that runs the shell self-test in isolation.

## Source Context

Slice 41 made the `3× max` gate-budget floor **two-way** by deriving `median`/`max` over
a trailing window of the most-recent **N=20 distinct hosted runs** instead of all corpus
history. The window is computed by two independent consumers:

- **Shell** — `.github/scripts/derive-gate-budgets.sh`, function `window_run_ids()` =
  `tail -n +2 | cut -f1 | sort -rnu | head -n N`, fed to the awk derivation as a
  process-substitution first file (`FNR==NR { KEEP[$1]=1 }`).
- **Swift** — `Tests/ViewportBenchmarksTests/GateFloorTests.swift`, function
  `mostRecentRunIDs(_:limit:)` = `Set(Set(ids).sorted(by:>).prefix(limit))`, used by
  `corpusExtremes(from:windowSize:)` to fold only in-window rows into the extremes the
  floor test holds every budget to.

The central risk of that slice — that these two silently diverge — was closed on **two**
axes, but only two of the three it needed:

1. The **N constant** is pinned across languages by
   `testWindowConstantMatchesDeriveScript`, which reads the `WINDOW=` line out of the
   shell script and asserts it equals the Swift `windowSize`.
2. The **Swift selection logic** is exercised in CI on every `swift test`
   (`testMostRecentRunIDsKeepsTopNByValue`, `testWindowedExtremesDropAnAgedOutFreak`, and
   the whole floor suite reads through `corpusExtremes`).
3. The **shell selection logic** is exercised only by `derive-gate-budgets.sh
   --self-test` — which nothing invokes. A repo-wide grep confirms zero references to it
   in CI or any test target; it is a manual dev-tool, in the same manual-self-test
   convention as `harvest-gate-corpus.sh` and `cross-target-compile.sh`.

## Problem

The brief's success criterion is *«Регрессионные бенчмарки блокируют merge при деградации
производительности»*. Slice 41 rests its whole thesis on "the two consumers must not
diverge," yet leaves one half of that invariant — the shell selector — guarded only by a
self-test that no automated context runs.

### The uncaught direction

The gap is not symmetric. A well-meaning edit can change the **shell** selection so it no
longer matches the Swift one — someone drops the `-u` from `sort -rnu` (so duplicate run
ids stop collapsing and `head -n N` now keeps a *different* set of distinct runs), or
changes the `head` semantics. Such a drift shifts which runs the derivation reads, and
therefore the `median`/`max` it derives budgets from. Of the two directions the drift can
take, one is caught outright and the other only once it grows gross enough to trip the
runtime ceiling:

- If the shell now derives a budget **tighter** than the correct Swift window would,
  `GateFloorTests` catches it: the committed budget can fall below `3× (Swift-windowed
  max)`, and the floor test — computing its extremes through the *correct*
  `mostRecentRunIDs` — reddens.
- If the shell now derives a budget **looser** than the correct Swift window would, only a
  *gross* overshoot is caught — **within-band loosening is not**:
  - **`GateFloorTests` still passes** — a looser (larger) budget clears `3×
    windowedMax` with room.
  - **`testWindowConstantMatchesDeriveScript` still passes** — the N *constant* is
    unchanged; only the *selection logic* around it drifted.
  - **The runtime `--gate` catches only *gross* loosening.** Its ceiling
    (`headroom_p95 ≤ 50×`, `headroom_p99 ≤ 100×`, checked against this run's live latency,
    failing `budget_stale`) reddens only if the mis-derived budget is loose *enough* to push
    headroom past the ceiling. It is otherwise corpus-blind: it cannot tell a budget merely
    looser than the correct Swift window from a correctly-sized one, as long as both stay
    inside the band. With current hosted headroom near 5×, that leaves a ~10× span of
    loosening — wider than the correct window, still under the 50× ceiling — it does not see.

So a shell selector that silently derives *within-band* looser than the Swift selector slips
past every existing guard: `GateFloorTests` (computing its extremes through the *correct*
Swift window) clears the larger budget, the constant pin is unmoved, and the runtime ceiling
only bites once the loosening exceeds 50×/100×. That is the precise blind spot — not that the
runtime gate is blind to *all* mis-derivation (its ceiling does backstop a wildly loose
budget), but that it is blind to the *corpus*, so within-band loosening wider than the correct
window is invisible to it, to the constant pin, and to the floor test alike. The cross-check
closes it by failing on **any** shell/Swift selection divergence — set inequality is
direction-blind, so it covers the uncaught within-band looser case and the already-caught
tighter case together. This is the same class of hole `GateFloorTests` itself was built to
close: an invariant left to a one-time or manual check instead of a standing one.

### Why the manual self-test is not enough

`derive-gate-budgets.sh --self-test` *does* assert the shell selector against hardcoded
expectations (it would catch a dropped `-u`, because its fixture has run 305 twice and
expects `305\n210`, not `305\n305`). The defect is not that the self-test is wrong — it
is that **nothing runs it**, so it cannot fail a build. An assertion that no CI or test
target invokes protects nothing. And even run, it checks the shell against *its own copy*
of the spec, not against the Swift consumer the budgets are actually verified through.

## Scope

**In scope** — the calibration tooling only:

- `.github/scripts/derive-gate-budgets.sh` — add a `--window-run-ids [N]` subcommand
  (beside the existing `--self-test` guard) that reads a corpus on stdin and prints the
  windowed run ids by delegating to the **existing** `window_run_ids` function. This
  exposes for isolated invocation the exact function the derivation already uses via
  `<(window_run_ids < "$corpus")`; no selection logic is duplicated. N defaults to
  `$WINDOW` when the argument is omitted.
- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` — a new standing test,
  `testWindowSelectionMatchesDeriveScript`, that runs the script's `--window-run-ids N`
  over a fixture corpus via a small subprocess helper and asserts the shell's chosen
  run-id **set** equals `mostRecentRunIDs(sameIDs, limit: N)` — the very function the
  floor test relies on. The cross-language analog of the existing *constant* pin, now for
  the *selection logic*.
- Fold the Slice 41 review's trivial **P3 #1** while in that shell file: a `trap 'rm -f
  "$fixture"' EXIT` in `run_self_test` so a red assertion no longer orphans its `mktemp`.
- `AGENTS.md` — one or two sentences noting the shell selector is now pinned to the Swift
  selector by `testWindowSelectionMatchesDeriveScript` (mirroring the constant pin), and
  recording the `--window-run-ids` subcommand.

**Not in scope:**

- **Any change to `Sources/TextEngineCore` or `Sources/TextEngineReferenceProviders`.**
  Zero engine or provider behavior changes. Expected diff there: **zero lines**.
- **Any change to a budget literal, the corpus, or any benchmark workload.** No harvest,
  no re-derivation. All eleven gate checksums stay byte-identical to the Slice 41
  baseline; that byte-identity is the proof the slice moved no measured path.
- **Wiring `--self-test` into CI** (Option A's other floated shape). Rejected — see
  Decision 3. The `--window-run-ids` subcommand and Swift pin subsume it.
- **The absolute/product budget** (Slice 38 Option C), **harvester provenance hardening**
  (Slice 41 review Option C), and **generalizing `WorkflowShapeTests`** to every gated
  mode (Option D). Separate concerns, separate slices.
- **P3 #3** (the `WorkflowShapeTests` comment's `swift-ci.yml:145-148` line-range anchor).
  It lives in a file this slice does not otherwise touch; folding it would widen the diff
  past one concern. Left as a recorded carry-forward.

## Goals

1. The shell window-**selection logic** gains a **standing** guard that fails a build
   (locally and in CI's host job) when it diverges from the Swift selection logic — the
   third and last axis of the "both consumers agree" invariant, joining the pinned
   constant and the CI-exercised Swift logic.
2. The guard is a *cross-check against the Swift consumer*, not a re-assertion of the
   shell against its own expectations — so it closes the specific within-band looser-shell-
   window direction that slips past `GateFloorTests`, the constant pin, and — below its
   50×/100× ceiling — the runtime gate.
3. No engine, provider, workload, budget, or corpus change; every gate checksum stays
   byte-identical.

## Non-Goals

**Replacing the shell `--self-test`.** It stays — it independently checks newest-first
*ordering* and its own hardcoded recency expectations, which the set-equality cross-check
deliberately does not (see Decision 2). The new test adds the cross-language pin; it does
not subsume the self-test's ordering coverage.

**Pinning the awk `KEEP` filter separately.** `window_run_ids` is the selection; the awk
`FNR==NR { KEEP[$1]=1 }` pass is pure set-membership over its output. Pinning the
selector's output set is what matters to the derivation; a correct window fed to a
membership filter cannot select the wrong rows. The cross-check targets the selector.

## Brief Alignment

This slice touches no engine latency and no budget number, so it cannot weaken or
strengthen any measured gate. What it hardens is the *machinery that keeps the budgets
honest* — specifically the Slice 41 mechanism that stopped budgets from ratcheting
loose. A budget derived by a silently-looser shell window is a budget that blocks less
than it should; a standing guard against that is a **more** trustworthy regression gate,
which is exactly what the brief's «блокируют merge при деградации» criterion depends on.
No Foundation enters the core (the subprocess helper and its `Process` use live in the
test target, which already imports Foundation to read the corpus). No Embedded/iOS/WASM
surface is touched.

## Decisions

### Decision 1 — A `--window-run-ids` subcommand is the right seam

The Swift test must invoke the *script's own* `window_run_ids`, not a re-implementation
of it (a re-implementation would pin the test to a copy of the logic, not to the shell
consumer). But `window_run_ids` is a shell function inside a script whose main body runs
on load; it cannot be called in isolation without either sourcing the script (which runs
`corpus="${1:?...}"` and exits) or a fragile function-extraction hack.

A thin `--window-run-ids [N]` subcommand, placed beside the existing `--self-test`
guard, exposes the function cleanly: it reads the corpus on stdin and prints
`window_run_ids "$N"`. It duplicates no selection logic (it *delegates* to the one
function), it is self-documenting, and it composes with the script's established
subcommand-guard pattern. It also happens to make the window manually inspectable
(`echo corpus | derive-gate-budgets.sh --window-run-ids 20`), a minor operator bonus.

Rejected alternatives: sourcing the script (needs a `return`-guard refactor of the main
body — more invasive); a `sed`/`eval` extraction of the function body (fragile, couples
the test to the script's text layout); driving the *whole* derivation and comparing
budgets (pins selection **and** arithmetic together — heavier, conflates concerns, and
the arithmetic is already covered by the floor test plus the per-slice
reproduce-every-literal check).

### Decision 2 — Compare as sets, not ordered lists

`window_run_ids` prints run ids newest-first; `mostRecentRunIDs` returns a `Set`. The
comparison is **set-equality**, because that is what the *consumer* cares about: the awk
`FNR==NR { KEEP[$1]=1 }` filter and the Swift `window.contains(row.runID)` fold both use
membership, so the order in which the window is emitted never reaches the derivation.
Comparing sets pins exactly the property that matters (which runs are in the window) and
nothing that does not (the order they are listed).

Ordering is not left unguarded: the shell `--self-test` already asserts newest-first
output against hardcoded expectations. The two tests are complementary — the self-test
covers ordering and the shell's self-consistency; the new pin covers *shell ≡ Swift*
membership. Neither subsumes the other.

### Decision 3 — Swift cross-language pin, not a CI self-test step

Option A had two shapes. A CI step running `derive-gate-budgets.sh --self-test` is
rejected in favor of the Swift pin for three reasons:

- **It would be the first self-test in CI.** No shell self-test in this repo
  (`derive`, `harvest`, `detect-docs-only-pr`, `realistic-relative-observation`,
  `cross-target-compile`) is invoked by CI; they are a deliberate manual convention. A
  self-test CI step would break that convention for one script only.
- **It checks the shell against its own expectations, not against the Swift consumer.**
  The whole point of the guard is *shell ≡ Swift*. The self-test asserts *shell ≡
  shell's-hardcoded-table*. It cannot catch a case where both the shell logic and its
  self-test expectations were edited consistently but away from the Swift consumer.
- **It runs only in CI, not on local `swift test`.** The Swift pin runs wherever the rest
  of the floor suite runs — locally and in the host job — for fast feedback, with no new
  CI step and no `WorkflowShapeTests` interaction.

### Decision 4 — Subprocess launch is safe in this test target

`ViewportBenchmarksTests` runs `swift test` only in the host job (Linux,
`swift:6.2.1-bookworm`, bash at `/bin/bash`) and locally on macOS. It never runs on iOS
device/simulator or WASM — those jobs only *compile* `TextEngineCore` and
`TextEngineReferenceProviders`. So `Foundation.Process` launching bash is available on
every context where this test executes. The test target already imports Foundation (to
read the corpus off disk), so no new dependency is introduced, and nothing crosses into
the Foundation-free core. A launch failure or non-zero exit is an `XCTFail` carrying the
captured stderr — not a skip — so the guard cannot silently no-op.

## Implementation Architecture

### `.github/scripts/derive-gate-budgets.sh`

A new subcommand guard beside `--self-test`:

```sh
if [[ "${1:-}" == "--window-run-ids" ]]; then
  window_run_ids "${2:-$WINDOW}" # reads corpus on stdin, prints windowed run ids
  exit 0
fi
```

It delegates to the unchanged `window_run_ids` function — the identical code path the
derivation uses via `<(window_run_ids < "$corpus")`. The `set -euo pipefail`
pipeline-under-`head` behavior is already proven safe by the committed `--self-test`,
which exercises the same function. Update the script's `# Usage:` header comment to list
`--window-run-ids [N]` beside `<corpus.tsv>` / `--self-test`, so the subcommand is
discoverable from the file itself, not only from `AGENTS.md`.

P3 #1 fold: in `run_self_test`, immediately after `fixture="$(mktemp)"`, add
`trap 'rm -f "$fixture"' EXIT` so the fixture is cleaned on the `exit 1` red path as well
as normal completion. The trailing `rm -f "$fixture"` may stay or go; the trap makes it
redundant but harmless.

### `Tests/ViewportBenchmarksTests/GateFloorTests.swift`

A subprocess helper and the pin test:

- `runDeriveScript(windowRunIDsFor:limit:) -> Set<Int64>` (or an inline equivalent):
  resolves the script path via the existing `repositoryRoot()` helper, launches
  `/usr/bin/env bash <script> --window-run-ids <N>` with `Foundation.Process`, writes the
  fixture corpus to the process's stdin `Pipe` **and closes it**, then drains stdout with
  `readDataToEndOfFile` before `waitUntilExit`, asserts exit status 0 (else `XCTFail` with
  stderr), and parses stdout lines into `Set<Int64>`. The write-fully-then-drain order
  matters: the output is tiny (≤N id lines, well under one pipe buffer) so it cannot
  deadlock, but this is the target's first subprocess launch, so it sets the safe pattern
  rather than relying on a lucky buffer size.
- `testWindowSelectionMatchesDeriveScript`: builds a fixture run-id list exercising the
  discriminating cases —
  - duplicate run ids across rows (a run contributes many rows),
  - out-of-chronological physical row order (ranking, not row order, decides recency),
  - one N that drops runs (`N` < distinct count) **and** one N that is a no-op (`N` ≥
    distinct count),
  synthesizes a fixture corpus TSV string (header + rows), and for each N asserts
  `runDeriveScript(...) == mostRecentRunIDs(fixtureIDs, limit: N)`.

  The fixture is not arbitrary: a duplicate run id must sit **at the dropping-N boundary**,
  so that removing `-u` from `sort -rnu` keeps the duplicate under `head -N` and pushes a
  distinct id out of the window — changing the emitted *set*, not merely the line count.
  Without that placement the guard-is-live break (drop `-u`) would leave the set unchanged
  and the test green, i.e. a guard that cannot fail. The demonstration (Testing Strategy
  step 2) confirms the break actually reddens *this* fixture; it is not assumed.

The test lives beside `testWindowConstantMatchesDeriveScript` and reuses `repositoryRoot()`
and `mostRecentRunIDs`; it introduces the target's first subprocess launch.

### Documentation

`AGENTS.md` — in the `GateFloorTests` package-layout description (the bullet that
enumerates its guards), note that the shell selector is now pinned to the Swift selector by
`testWindowSelectionMatchesDeriveScript` (the selection-logic analog of the constant pin);
add a matching sentence to the `## Gate budgets` window paragraph; and record the
`--window-run-ids` subcommand alongside the existing `--self-test` in the `## Commands`
list.

### Verification record

`docs/superpowers/verification/2026-07-18-shell-window-selection-guard.md` — the new
test's green run in full `swift test` output; the **guard-is-live demonstration** (break
the shell selector, e.g. drop `-u` or change `head`, show the new test red, revert, show
green); `derive-gate-budgets.sh --self-test` still `self_test=pass` (with the trap fold);
a sample `--window-run-ids` invocation; the Foundation-free scan empty; `git diff
--name-only` showing zero `Sources/TextEngineCore`/`TextEngineReferenceProviders` paths;
all eleven `--gate` modes `gate=pass` locally with checksums byte-identical to the Slice
41 baseline; and the hosted PR-head and post-merge push run IDs read at step level.

## Testing Strategy

TDD, per the project norm. This is a guard test: it is green the moment it exists, because
the two selectors already agree. "Red-first" for a guard means proving the guard *can*
fail — the established pattern in this repo (Slice 41 demonstrated its constant pin live
with a temporary `WINDOW=21`).

1. **`testWindowSelectionMatchesDeriveScript`** — written first. It requires the
   `--window-run-ids` subcommand to exist to pass, so the honest sequence is: add the
   subcommand, add the test, watch it go green.
2. **Guard-is-live demonstration** — temporarily break the shell selector (drop `-u` from
   `sort -rnu`, and/or a `head` change) and confirm the new test goes **red**; revert and
   confirm green. This doubles as proof the fixture's dropping-N boundary genuinely
   distinguishes `-u` from no-`-u` (a duplicate at the window edge) — if the break does not
   redden it, the fixture, not the guard, is wrong. Recorded in the verification doc, not
   committed.
3. **`derive-gate-budgets.sh --self-test`** — still `self_test=pass` after the subcommand
   and trap-fold edits.
4. **Full `swift test`** — all prior tests plus the new one pass, green on hosted Linux,
   not only locally.
5. **Byte-identity** — all eleven `--gate` checksums identical to the Slice 41 baseline;
   the Foundation-free scan empty; zero engine/provider diff.

## Acceptance Criteria

1. `.github/scripts/derive-gate-budgets.sh --window-run-ids N` reads a corpus on stdin and
   prints the same run ids `window_run_ids N` would, by delegating to it; `--window-run-ids`
   with no N defaults to `$WINDOW`.
2. `testWindowSelectionMatchesDeriveScript` asserts, over a fixture exercising duplicate
   ids, out-of-order rows, and both a dropping-N and a no-op-N, that the shell selector's
   output set equals `mostRecentRunIDs` on the same ids — and is demonstrably **live** (a
   temporary break in the shell selector reddens it, shown in the verification record). A
   subcommand launch failure or non-zero exit is a loud `XCTFail` carrying captured stderr,
   never a skip, so the guard cannot silently no-op.
3. `swift test` passes in full (existing suite + the new test), green on hosted Linux.
4. `git diff --name-only` shows **no path under `Sources/TextEngineCore` or
   `Sources/TextEngineReferenceProviders`**, and no budget-literal or corpus change.
5. All eleven `--gate` modes report `gate=pass` locally, and all query/mutation checksums
   are byte-identical to the Slice 41 baseline.
6. `derive-gate-budgets.sh --self-test` still passes; its `mktemp` fixture is cleaned on
   the red path too (P3 #1 fold).
7. `AGENTS.md` records the selection-logic pin and the `--window-run-ids` subcommand.
8. Hosted: the three required jobs and all eleven blocking gates green on the PR head and
   on the post-merge push run, read at **step level** (a `continue-on-error` step can
   conclude a job green while its own step failed).

## Risks And Gaps

### The subprocess helper is the target's first process launch

If `Process`/bash behaves differently on hosted Linux than local macOS, the test could
pass locally and flake in CI (or vice versa). Mitigation: the invocation is a plain
`bash <script> --window-run-ids N` with stdin/stdout pipes — the most portable shape;
bash and `Foundation.Process` are present in both contexts (Decision 4); and a launch/exit
failure is a loud `XCTFail` with captured stderr, never a skip. The hosted PR-head and
post-merge runs (AC8) are the proof it runs green on Linux, not only locally.

### The self-test remains manual

This slice pins the shell *selection logic* to Swift but does not wire the shell
`--self-test` (which additionally covers newest-first *ordering*) into any automated
context. Ordering divergence between the shell output and its own expectations would
still only be caught by a human running `--self-test`. Judged acceptable: ordering does
not affect the derivation (Decision 2), and the membership property — the one the budgets
actually depend on — is now standing-guarded. Recorded, not closed.

### The derivation *arithmetic* keeps a symmetric residual

This slice standing-guards the *selection* logic, not the derivation *arithmetic* (`8×median`,
`3×max`, `round_up_2sf`). By the same argument that motivates the slice, that arithmetic is
itself only partially standing-guarded: `GateFloorTests` catches an arithmetic drift that makes
a budget *too tight* (below `3×` windowed max), and the runtime ceiling catches one *gross
enough* to exceed 50×/100× — but a *within-band looser* arithmetic drift is caught only by the
manual per-slice "reproduce every literal" check. That is the same direction and the same
manual-only weakness this slice closes for the selector. Decision 1 rejects driving the whole
derivation partly on the grounds that the arithmetic is "already covered by the floor test plus
the reproduce check"; that coverage is the *tight* side plus a *manual* check, so the symmetric
loose-side gap is a deliberate, documented residual here — not a closed one. Closing it (a
standing "reproduce every committed literal" test) pins selection **and** arithmetic together
and couples to the budget-literal representation, which is why it is a separate slice, not
folded in. Recorded, not closed.

### P3 #3 carry-forward

The `WorkflowShapeTests` comment's `swift-ci.yml:145-148` line-range anchor (Slice 41 P3
#3) will drift if that YAML is edited above it. Out of scope here (different file, one
concern); carried forward for a slice that touches `WorkflowShapeTests`.

### Standing items unchanged

WASM stays observational; the realistic-provider observation stays PR-only
`continue-on-error`; the harvester still selects by run id alone (provenance hardening is
a separate slice); the `Main` ruleset keeps its documented bypass-actor shape.

## Recommended Next Step

With all three axes of the "both consumers agree" invariant now standing-guarded (constant
pinned, Swift logic CI-exercised, shell logic cross-pinned), the calibration machinery is
closed. The natural successor returns to the **product** story: **Slice 38 Option C — the
absolute product budget**, a fixed per-scenario ceiling (the brief's "60 FPS → measurable
headless budget", e.g. the 1 µs line every query scenario's p99 already clears) that never
recalibrates and catches the *legitimate* slow drift a median-anchored regression budget
can always re-derive around. It is now well-timed: Slice 41 stopped the upward drift and
this slice hardened the tooling under it, so an absolute backstop composes cleanly rather
than fighting a moving median. Harvester provenance hardening (Option C) and generalizing
`WorkflowShapeTests` (Option D) remain available as smaller infra alternatives.
