# Slice 44 Post-Slice Review

The "derived, never hand-typed" rule becomes **build-enforced**. Slices 41–42
pinned the corpus *window* (the constant, the Swift selection, the shell
selection); Slice 43 added the fixed absolute *product* ceiling. Slice 44 closes
the last within-band residual those left open: the derivation **arithmetic** itself
(`8×median`, `3×max`, `round_up_2sf`, plus the p99 `2×budget_p95` floor). One
standing XCTest — `testEveryCommittedBudgetReproducesFromCorpus` in
`Tests/ViewportBenchmarksTests/GateFloorTests.swift` — shells out once (all modes)
to `.github/scripts/derive-gate-budgets.sh` over the committed corpus and asserts
every committed gate budget literal (p95 **and** p99) byte-equals the re-derived
`budget_p95`/`budget_p99`, with a loud `XCTFail` on launch/exit failure (never a
skip), a non-vacuity guard, and a bijective `derived.count ==
everyGatedBudget().count` cardinality check that also catches reverse drift. It is
the arithmetic analog of the two window **selection** pins. Purely additive: all 46
committed budgets already reproduce, so **zero** engine / provider / budget /
corpus / script change. Merged as `ec265d3` (PR #99); AC7 hosted proof discharged
in the docs-only follow-up `efdd421` (PR #100, merged as `0483a1c`).

This is the Slice 43 review's recommended **Option A** and the spec's own Next
Step, delivered exactly as scoped — and it completes the calibration/tooling thesis
that Slices 41–44 have been building. This review was written after independently
re-running the local verification on the merged tree (`main` @ `0483a1c`),
re-reproducing the guard-is-live break→red→revert→green cycle, and spot-checking
both hosted runs' job conclusions against the AC7 record.

## Scope Reviewed

- `Tests/ViewportBenchmarksTests/GateFloorTests.swift` — the file-private parser
  `derivedBudgets(fromScriptOutput:)` (line 128) and the standing test
  `testEveryCommittedBudgetReproducesFromCorpus` (line 393), sitting with the other
  cross-language derive-script pins; plus the P3 #1 comment softening above
  `testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling`.
- `AGENTS.md` — the new `## Gate budgets` "Every committed budget is now
  build-enforced to reproduce" paragraph (line 430), the reproduction-test sentence
  in the `GateFloorTests` package-layout bullet (line 135), and the "two → three
  failure reasons" correction (line 446).
- The spec, plan, and verification record for the slice; the AC7 hosted-proof edit
  in PR #100.

Out of review scope, because the slice did not touch them (confirmed by
`git diff --name-only 06a1358 0483a1c -- Sources/TextEngineCore
Sources/TextEngineReferenceProviders .github/scripts/derive-gate-budgets.sh
docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` → **empty**, and
no budget literal / workflow path in the whole-slice stat): `Sources/TextEngineCore`,
`Sources/TextEngineReferenceProviders`, every budget literal under
`Sources/ViewportBenchmarks/`, the corpus, `derive-gate-budgets.sh`, and
`.github/workflows/swift-ci.yml`. The whole changed set is exactly `AGENTS.md`,
`GateFloorTests.swift`, and the three slice docs (spec, plan, verification).

## Product Brief Alignment

This slice is **pure tooling** — it adds no engine surface, moves no measured
latency, and touches no public API. The brief's hard constraints hold trivially,
and the "keep budgets honest" machinery the brief's perf invariant depends on is
strengthened.

- **Foundation-free core** — no core file changed; `rg -n Foundation
  Sources/TextEngineCore` is empty (re-run for this review, exit=1). The new test's
  `import Foundation` (for `Process`/`URL`) is pre-existing in this test target — it
  is how the file already reads the corpus and drives `--window-run-ids`; nothing
  crosses into the core.
- **Swift Embedded / iOS+WASM** — no engine surface touched; the whole diff is
  confined to a test file and docs. Both cross-target jobs are green on both hosted
  runs.
- **Zero-dependency** — no package added; the guard is one shell-out plus a
  ~15-line stdlib string parser.
- **Memory / virtualization invariants** — unchanged; not in scope.
- **Perf invariant (the brief's «блокируют merge при деградации» / «60 FPS»)** —
  *reinforced, not changed*. No budget or ceiling moved. What changed is that "every
  gate budget is derived from hosted evidence, never hand-typed" — the discipline
  the whole gate rests on, and the exact discipline Slices 27/31/33/35/37 violated
  for five slices with copy-pasted starter budgets — is now a standing `swift test`
  assertion rather than a per-slice human check. The 46-literal byte-reproduction is
  the proof the addition changed no calibration: every committed budget still
  reproduces from the committed corpus.

## Delivered Design

### One invocation, all modes, keyed lookup

The test shells out **once** (`bash derive-gate-budgets.sh <corpus>` with no mode
argument), so the script emits all 46 gated scenarios in a single run, and the test
does a keyed `derived[budget.key]` lookup per registered budget. The key spelling
(`"\(mode.outputName)|\(scenarioName)"`) is identical to the corpus/derive-output
key, so the join is exact. Running the script once rather than per-mode is both
faster and — more importantly — exercises the real all-modes output path CI depends
on, not a per-mode subset.

### Shell out, don't re-implement — the load-bearing architecture choice

The test asserts against the **actual stdout** of `derive-gate-budgets.sh`, the one
sanctioned source of a budget, instead of re-implementing `8×median` / `3×max` /
`round_up_2sf` in Swift. This is the correct call and it is what makes the guard
strong: a Swift re-implementation would pin the literals against a *second copy* of
the recipe that could itself drift from the shell script (and would have to be
maintained in lockstep). By driving the real script, the test transitively guards
the script's `awk` arithmetic and its output token shape on **both** BSD-awk (local)
and Linux-awk (CI) — the same "pin the real thing, not a model of it" discipline the
`WorkflowShapeTests` hand-rolled reader and the `--window-run-ids` selection pin
already use.

### Skip-on-missing-token turns a format rename into a loud failure

The parser skips any line missing a `budget_p95=` / `budget_p99=` token (it only
records a key once **both** are found). On its own that would be a silent-pass risk
— a renamed token would yield an empty map. But combined with the test's "every
gated key must be present" assertion and the bijective cardinality check, a
token/format rename becomes a **missing-key / wrong-count loud failure**, not a
vacuous green. So the test pins the script's *output shape* as well as its
arithmetic. This is a genuinely nice property, correct by inspection — see the P3
finding below on its one gap (no isolated fixture demonstrates it).

### Bijective cardinality catches reverse drift

The cardinality check is `XCTAssertEqual(derived.count, budgets.count)` — equality,
not `>=`. Forward drift (a registered gated budget the script no longer emits) is
caught by the per-budget `guard let d = derived[budget.key]` → `XCTFail`. Reverse
drift (a scenario that entered the corpus/derivation but was never registered as a
gated budget) is caught **only** by the equality cardinality check. Together with
the non-vacuity `XCTAssertFalse(derived.isEmpty)` guard, the two directions and the
"not empty" floor make the bijection complete. The comment correctly documents the
one conscious escape hatch (relax to `>=` only if a non-gated observation-only row
is ever deliberately added to the corpus).

### Loud on failure, never a skip

A launch or exit-code failure is an `XCTAssertEqual(result.exitCode, 0, …stderr…)`
with the stderr inlined — never a `throw XCTSkip`. This matters: a skip-on-tooling-
failure would let a broken script silently disarm the whole guard on any host where
`bash`/`awk` misbehaved. The failure message on a stale literal names the exact
scenario, both values, and the correct disposition (`budget_stale`, not an engine
regression — re-derive and re-commit), so a red here is self-explaining.

## Verification Evidence Reviewed

### Fresh local checks on the merged tree (`main` @ `0483a1c`)

| Check | Result |
|---|---|
| `swift test` | **311 tests, 0 failures** (= Slice 43's 310 + the one new reproduction test) |
| `swift build -c release` | clean (`Build complete! (1.47s)`) |
| `rg -n Foundation Sources/TextEngineCore` | empty (`exit=1`) |
| `--gate` (synthetic) | 3 × `gate=pass` (each also carrying `budget_absolute_p99_ns=1666666`) |
| whole-slice engine/provider/script/corpus diff (`06a1358..0483a1c`) | **empty** — zero `TextEngineCore` / `TextEngineReferenceProviders` / `derive-gate-budgets.sh` / corpus paths |
| whole-slice changed set | only `AGENTS.md`, `GateFloorTests.swift`, and the three slice docs |
| guard-is-live (budget `440 → 450` → red → revert → green) | reproduced independently; RED with the exact message, clean revert, back to PASS |
| tree after revert | **byte-clean** — `git status --short` empty, no `.bak`, `git diff --stat` empty |

### Guard-is-live, independently reproduced

A guard over already-satisfied state is green on introduction, so it must be proven
live. I reproduced the break on the merged tree (not trusting the recorded
transcript): a `.bak`-backed `sed` bump of `line_query|uniform_1k`'s p99 budget
`440 → 450` (still clearing the floor and `p99 ≥ 2×p95`, so **only** the
reproduction test should redden) turned
`testEveryCommittedBudgetReproducesFromCorpus` **red** with exactly

```
line_query|uniform_1k: committed p99 budget 450 != 440 re-derived from the corpus
— the literal no longer reproduces (budget_stale, not an engine regression).
Re-derive with .github/scripts/derive-gate-budgets.sh and re-commit.
```

Reverting from `.bak` restored PASS (0.091 s), and the tree returned byte-clean
(empty `git status --short`, no stray `.bak`, empty `git diff --stat`). The break
was never committed. The guard is live: a stale literal fails `swift test` with a
message naming the scenario, both values, and the correct disposition.

### Hosted runs (spot-checked at job level against the AC7 step-level record)

The verification doc's "## Hosted CI — Discharged" section records both runs read
**at step level** (per the Slice 16 dead-step-trap rule — a `continue-on-error` step
can conclude a job green while its own step failed). I spot-checked the job
conclusions with `gh run view … --json jobs`; both agree with the recorded tallies.

- **PR-head run `29679693875`** (commit `2b5e132`): three required jobs `success`
  (Host `88173481190`, iOS `88173481198`, WASM `88173481185`); eleven blocking gate
  **steps** ✓; whole-run tally **45 `gate=pass`, 0 fail** (40 hot-path @
  `budget_absolute_p99_ns=1666666`, 5 bulk `=exempt`); host tests **311/0**;
  `testEveryCommittedBudgetReproducesFromCorpus` **passed** (0.068 s).
- **Post-merge `push` run `29680120202`** (merge `ec265d3`): three required jobs
  `success` (Host `88174634071`, iOS `88174634067`, WASM `88174634069`); eleven gate
  steps ✓; identical tally **45 `gate=pass`, 0 fail**, 40 × `1666666` + 5 ×
  `exempt`; host tests **311/0**; the new test **passed** (0.067 s). The 53
  `checksum=` lines (45 gated + 5 `memory_shape` + 3 `memory_observation`) are
  byte-identical to the PR-head run and to the local checksum set (== Slice 43
  baseline). The realistic-provider observation step is PR-only **and** writes to a
  temp file, so it emits no `checksum=` in the log — correctly not part of this
  proof.

The merged-code `push` run anchors the proof, matching the Slices 24–43 pattern of
anchoring in the post-merge run rather than the PR-head run alone.

## Git History

Four implementation commits on top of two pre-committed design/plan docs, cleanly
separated by concern and following the slice lifecycle: `168392d` (docs: design) →
`ce5755d` (docs: plan) → `b456272` (test: the reproduction test) → `5940f06` (docs:
record the guard in `AGENTS.md`, fold P3 #1/#2) → `2b5e132` (docs: local
verification) → merged as `ec265d3` (PR #99). The AC7 hosted proof lives in the
docs-only follow-up `efdd421` (PR #100, merged as `0483a1c`), matching the
established pattern of discharging step-level hosted proof after merge. Conventional-
commit prefixes are correct; the `test`/`docs` split matches the work (one code
commit carrying the test, the rest docs).

## Code Review Findings

### P0 / Release Blockers

**None.** The slice is merged; all eleven gates are green on the merged commit at
step level on both the PR-head and post-merge runs; both hard constraints hold
(Foundation-free, zero engine/provider/script/corpus diff); the 46 committed budgets
byte-reproduce from the committed corpus; and the new guard is demonstrably live
(break→red→revert→green re-reproduced for this review).

### P1 / Must Fix Before Merge

**None.** The test asserts real behavior (exact byte-equality on both statistics,
non-vacuity, bijective cardinality with a loud message on every branch); the guard-
is-live break was reproduced independently; and the two hard constraints and the
checksum byte-identity are re-verified.

### P2 / Production Readiness

**P2 #2 (carried from Slice 42→43): the derivation arithmetic residual —
✅ RESOLVED by this slice.** This is precisely what Slice 44 closes.
`testEveryCommittedBudgetReproducesFromCorpus` re-derives every budget from the
windowed corpus and asserts byte-equality with the committed literals, so a
within-band-looser arithmetic drift (invisible to `GateFloorTests`' floor whenever
the `8×median` term governs, since the floor sees only `3×max`) now reddens
`swift test`. "Every budget is derived, never hand-typed" is a build-enforced
invariant. Confirmed closed; removed from the carry-forward list.

**P2 #1 (carried from Slice 43): bulk-edit absolute backstop.**
`bulk_structural_mutation` is exempt from the absolute product ceiling (Slice 43
Decision 2), so slow drift in bulk-edit latency is caught only by its median-anchored
regression budget — the very blind spot the frame path now closes on both the
regression *and* absolute axes. Correct *scope* (a multi-line paste is not a scroll
frame), but a real recorded gap. Untouched this slice; carries. This is Slice 43's
Option B and the leading *product* candidate for Slice 45 (needs a product-target
decision first).

**P2 #3 (carried from Slice 42→43): harvester provenance gap.**
`harvest-gate-corpus.sh` still selects rows by run id alone (no
`conclusion`/`event`/fork check), so a fork PR's CI run could in principle print
fabricated `p95_ns=` lines that a later harvest would ingest into the corpus. This
is now the **only unverified link in the calibration chain**: Slice 44 proves budgets
derive faithfully *from* the corpus, but nothing guards what enters the corpus.
Untouched this slice; carries. A security-shaped, self-contained slice candidate.

**P2 #4 (carried from Slice 41/42→43): p95 thin axis / `point_geometry_query` thin
evidence.** Under the trailing window, the sub-µs `line`/`column`/`point` cluster
sits closest to the starvation floor and is where a hosted `budget_stale` would
surface first — and it is exactly what the new reproduction test would flag (as
`budget_stale`, correctly). This slice moves no budget; monitor p95 and re-derive on
any hosted `budget_stale`. Carries.

### P3 / Minor But Valid

**P3 #2 (from Slice 43): the "two failure reasons" clause undercounted — ✅
RESOLVED.** `AGENTS.md`'s closing "opposite instructions" paragraph now reads **"The
three failure reasons are distinct instructions"** and documents
`budget_absolute_exceeded` ("fix the code/architecture, never loosen the ceiling")
alongside `budget_exceeded` / `budget_stale`. Grep confirms **no lingering "two
failure reasons" text** anywhere in `AGENTS.md`. Closed.

**P3 #1 (from Slice 43): frozen `580 µs / 2.87×` figures — only PARTIALLY folded;
two sites still carry.** Slice 44 Task 2 softened the **`GateFloorTests.swift`** site
only (grep confirms no `580`/`2.87` remains in that file — it now reads "the slowest
frame-hot-path p99 budget (currently structural_mutation|1m); its live margin under
the ceiling is what this test enforces"). But two sites **still quote the frozen
number**, verified for this review:
  - `Sources/ViewportBenchmarks/BenchmarkModels.swift:145` — the `gateFailureReason`
    comment still says "every regression p99 budget is <= 580us < the 1.67ms
    ceiling".
  - `AGENTS.md:334` — the Slice 43 absolute-ceiling subsection still says "binding
    scenario `structural_mutation|1m`, 580 µs, 2.87× under".

  Both figures are falsified by the next re-derivation that raises the
  `structural_mutation|1m` p99 budget (while staying under the ceiling) — the exact
  `measured-values-in-comments-rot` anti-pattern. (`2.87` now appears **only** in
  `AGENTS.md`; the `580_000` at `StructuralMutationBenchmark.swift:38` is the live
  budget *literal*, not a rotting quote — correct to keep.) **Mitigating:** both
  remaining sites cite `GateFloorTests` as the enforcing mechanism, so the load-
  bearing claim doesn't depend on the number; and the number is accurate today.
  Recorded as a partial fold — the two remaining sites are a clean opportunistic
  softening for any future slice touching `BenchmarkModels.swift` or `AGENTS.md`
  (keep the structural claim, drop the frozen number, exactly as the
  `GateFloorTests` site was done).

**P3 #3 (new, from the whole-branch SDD review): the parser
`derivedBudgets(fromScriptOutput:)` has no isolated fixture unit test.** It is
exercised only transitively through the real shell-out, so its skip-on-missing-token
behavior — the format-rename protection described above — is correct by inspection
but never *demonstrated* by a test over a synthetic fixture (e.g. a line missing
`budget_p99=`, a malformed integer, a blank line). A worthwhile P3 hardening: a
handful of fixture assertions would pin the parser's contract independent of the
live script. **Mitigant:** the bijective cardinality check is a second, independent
loud-failure path — a token rename that empties the map fails the count assertion
even with the parser untested — so the guard as a whole is not silently defeatable.
Low urgency.

**P3 #4 (new, from the SDD review): verification doc §5 uses `grep -E 'mode=|checksum='`
where the plan's Step 5 specifies `grep -o 'checksum=[0-9a-fx]*'`.** Harmless
cosmetic divergence — the doc's variant captures more context (the `mode=`/`scenario=`
prefix) and its checksum values match the baseline regardless. No action.

**P3 #5 (from Slice 43): plan checkboxes left unchecked.** All 22 steps in the
committed plan are `- [ ]` though the work shipped (0 checked); the commit messages
are the completion evidence. Recurring cosmetic paper-trail nit, unchanged from prior
slices.

**P3 #6 (carried from Slice 41/42→43): `WorkflowShapeTests` comment cites
`swift-ci.yml` by line range** — a pointer that drifts if that YAML is edited above
it. Correctly out of scope (this slice does not touch `WorkflowShapeTests.swift`).
Carries.

## Risks And Gaps

- **Bulk-edit absolute backstop (P2 #1)** — the frame path is guarded on both the
  regression and absolute axes; bulk is guarded only on regression, by deliberate
  scope. The natural *product* successor if a bulk-edit latency guarantee is ever
  needed.
- **Harvester provenance (P2 #3)** — the corpus's *ingestion* is unauthenticated
  (run-id-only selection). Now the single unverified link in the otherwise fully-
  pinned calibration chain; the natural *tooling/security* successor.
- **p95 thin axis / point-geometry thin evidence (P2 #4)** — re-derive on any hosted
  `budget_stale`; the new reproduction test will name it precisely when it happens.
- **Partial P3 #1 fold** — two frozen-number sites (`BenchmarkModels.swift`,
  `AGENTS.md`) remain; a rotting comment, not a defect.
- **Parser has no isolated test (P3 #3)** — the format-rename protection is
  inspection-verified, not test-demonstrated (cardinality check is the backstop).
- **Standing items unchanged** — WASM observational; realistic-provider observation
  PR-only `continue-on-error`; the `Main` ruleset keeps its documented bypass-actor
  shape.

## Lessons For The Next Slice

- **Pin the real thing, not a model of it.** The reason this guard is strong is that
  it drives the *actual* `derive-gate-budgets.sh` rather than re-deriving the recipe
  in Swift — so it cannot diverge from a second copy, and it transitively covers the
  script's `awk` and output shape on both awks. This is the same discipline behind
  `WorkflowShapeTests` (reads the real YAML) and the `--window-run-ids` pin (drives
  the real selection). Prefer pinning the artifact over pinning a duplicate of it.
- **The calibration thesis is complete — the next step is a pivot, not more of the
  same.** Slices 41 (window), 42 (shell selection), 43 (absolute product ceiling),
  and 44 (arithmetic reproduction) have now pinned the window's constant, its Swift
  and shell selection, the product backstop, and the derivation arithmetic. Every
  *within-band* calibration residual the recipe's own docs called out is closed.
  Continuing to harden the same machinery is diminishing returns; the honest next
  moves are the product axis (bulk-edit budget) or the one remaining *input*-trust
  gap (harvester provenance), not a fifth calibration pin.
- **A guard over already-satisfied state must be proven live.** As in Slices 42–43,
  the break→red→revert→green cycle is load-bearing (a test that is green on
  introduction proves nothing until you make it red); this review re-reproduced it on
  the merged tree rather than trusting the transcript.
- **Fold rotting quotes in the same file you touch.** The P3 #1 partial fold is the
  standing lesson in miniature: the `GateFloorTests` site was softened because the
  slice touched that file; the `BenchmarkModels.swift` and `AGENTS.md` sites were not
  softened because Task 2 didn't need to edit those exact lines. The cheapest time to
  drop a rotting number is when you're already in the file.

## Slice 45 Candidate Options

The calibration/tooling thesis (Slices 41–44) is complete, so Slice 45 is a genuine
choice of direction, not a continuation.

### Option A: harvester provenance hardening (P2 #3) — recommended

Filter harvested runs by `conclusion=success` / expected event / non-fork before
ingesting their `p95_ns=` lines, closing the injection surface. This is now the
**only unverified link in the calibration chain**: Slice 44 proves budgets derive
faithfully *from* the corpus, but nothing authenticates what enters it — a fork PR's
CI run could in principle print fabricated latency lines a later harvest would trust.
It is small, self-contained, security-shaped, needs **no product decision**, and has
an existing self-test seam (`harvest-gate-corpus.sh --self-test`) to hang a standing
test on. It closes the "trust the corpus" assumption that every one of Slices 41–44
implicitly rests on.

### Option B: bulk-edit absolute budget anchored to a bulk-appropriate target (P2 #1)

Give `bulk_structural_mutation` its own absolute ceiling ("a 4096-line paste in ≤ N
frames"), closing the deliberate residual Slice 43 recorded. This is the strongest
*product* step — it advances the brief's «60 FPS» north star a second concrete step
beyond Slice 43's frame-hot-path ceiling. But it needs a **product-target decision**
(N frames for a bulk paste) before the ceiling can be a fixed constant, so it should
open with a short brainstorm/product call rather than be executed cold.

### Option C: isolated parser fixture test + fold the remaining P3 #1 sites

Add a handful of fixture assertions pinning `derivedBudgets(fromScriptOutput:)`'s
skip-on-missing-token and malformed-integer behavior directly (P3 #3), and soften the
two remaining frozen-`580 µs` sites (P3 #1) while in `BenchmarkModels.swift` /
`AGENTS.md`. Small hardening of this slice's own residuals; low-value on its own but
a clean fold if a larger slice touches those files.

### Option D: generalize `WorkflowShapeTests` to every gated mode (P3 #6)

Add a `flagName` mapping + a named-and-justified exemption set + a test pinning the
two together, so all eleven gate steps are shape-pinned, not just point-geometry.
Standing infra; folds P3 #6.

## Recommended Slice 45 Selection

**Option A — harvester provenance hardening (P2 #3).** With Slice 44 closing the last
within-band calibration residual, the calibration machinery now *faithfully derives
every budget from the corpus* — but nothing guards **what enters the corpus**. That
makes provenance the single highest-leverage remaining item: it is the root-of-trust
gap under the entire pinned chain Slices 41–44 built, it is small and self-contained
(a `conclusion`/`event`/fork filter in `harvest-gate-corpus.sh` plus a standing test
on the existing `--self-test` seam), and — unlike the product option — it needs no
external decision to start. It finishes the "trust the budgets" story by finally
trusting their source.

**Option B (bulk-edit absolute budget)** is the strongest *product* alternative and
the direct completion of Slice 43's own recorded residual; prefer it if the user
would rather advance the product axis than finish hardening the pipeline — but it
must open with a product-target decision (N frames for a bulk paste), so it is really
a product call, not a cold-start engineering slice. Honestly weighed: with tooling
complete, the product axis is where the *project* ultimately wants to go, but the
provenance gap is the cheaper, decision-free, and more urgent (it is a live
trust gap, not a deferred feature) next step — so it leads, with the product call as
the clear follow-on once the user sets a bulk target. Fold the trivial P3 #1 (two
remaining `580 µs` sites), P3 #3 (parser fixture), P3 #5 (plan checkboxes), and P3 #6
(WorkflowShapeTests anchor) opportunistically if Slice 45 touches those files.

## Slice 44 Review Conclusion

Slice 44 does exactly what the Slice 43 review and the spec asked for, with no scope
creep: one standing test now build-enforces that every committed gate budget
reproduces byte-for-byte from the committed corpus, closing the last within-band
residual in the calibration recipe — the *arithmetic* analog of the two window
*selection* pins — and completing the calibration/tooling thesis Slices 41–44 built.
The design is right where it counts: it shells out to the real derivation script
rather than re-implementing it, so it transitively guards the script's arithmetic and
output shape on both awks; skip-on-missing-token plus a bijective cardinality check
turns a format rename into a loud failure rather than a silent pass; and a launch/exit
failure is a loud `XCTFail`, never a skip. No core, provider, budget, corpus, or
script byte moved (all 46 literals reproduce; all 53 hosted checksums byte-identical
to the Slice 43 baseline); the merged commit is green across all eleven blocking gates
at step level on both the PR-head and post-merge push runs, with host tests **311/0**
and the new test passing hosted (0.067 s). The guard-is-live break was re-reproduced
for this review and the tree left byte-clean. **P2 #2 (arithmetic residual) and P3 #2
(the "two failure reasons" undercount) are resolved; P3 #1 is partially folded (two
frozen-`580 µs` sites carry).** No P0, no P1. The substantive carry-forwards are the
deliberate bulk-edit residual (P2 #1), the harvester provenance gap (P2 #3), and the
p95 thin axis (P2 #4). **READY — merged and verified; Slice 45 = harvester provenance
hardening (Option A, no decision needed), or a bulk-edit absolute budget (Option B) to
advance the product story once a bulk target is chosen.**
