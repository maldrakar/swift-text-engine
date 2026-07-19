# Slice 45 Post-Slice Review

The one gated mode CI never ran with `--gate` now does. Slice 45 promotes the
realistic 100k-line / 10 MB viewport-compute benchmark (`--realistic-provider`,
scenario `100k_lines_10mb_text`) to the **twelfth** merge-blocking regression gate,
wiring `swift run … ViewportBenchmarks -- --realistic-provider --gate` into
`swift-ci.yml` as a standard blocking step and **removing** the old PR-only,
`continue-on-error`, base-vs-head relative-observation step (plus its now-orphaned
327-line `.github/scripts/realistic-relative-observation.sh`). It is a
**zero-engine-behavior-change** slice: `runRealisticProviderBenchmarks(enforceGate:)`
already honoured `--gate` and already carried committed, corpus-derived budgets, so
nothing algorithmic, no budget literal, no corpus row, and no derivation script
moved — the whole change is CI wiring, one standing-guard extension
(`WorkflowShapeTests` generalized from a single point-geometry pin into a two-entry
`{point-geometry, realistic}` table with six table-iterating invariants), narrative
de-rotting, and a single comment-only edit in `RealisticProviderBenchmark.swift`.

This is the same "observation → Nth blocking gate" shape the repo has shipped seven
times before (Slices 24/26/28/32/34/36/38/40), and it is the single most
brief-aligned gate available: criterion #1 («стабильный scroll performance на
документах 100k+ строк / >10 MB») × the last criterion («регрессионные бенчмарки
блокируют merge при деградации») — a merge-blocking regression gate on the actual
headline workload rather than a synthetic proxy. Merged as `413390d` (PR #102); the
AC7 hosted proof was discharged post-merge in the docs-only follow-up `3a6e98c`
(PR #103, merged as `26befe9` = current HEAD). This review was written after
independently re-running the local verification on the merged tree
(`slice-45-post-slice-review` @ `26befe9`, which **is** merged `main`),
re-reproducing the guard-is-live break→red→revert→green cycle for the **new**
realistic pin, and spot-checking both hosted runs at job **and** step level against
the AC7 record.

## Scope Reviewed

- `.github/workflows/swift-ci.yml` — the new `Run realistic provider benchmark gate`
  step (added after `--point-geometry-query --gate`, before `Run memory shape
  diagnostic`); the deletion of the `Observe realistic provider relative
  performance` step and its `REALISTIC_RELATIVE_OBSERVATION_THRESHOLD`/`BASE_SHA`/
  `HEAD_SHA` env.
- `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` — the generalization from
  a single pinned gate into the `pinnedGateSteps` table (line 51) and the six
  invariants (`testExactlyOneStepRunsEachPinnedGate` … `testEachPinnedGateSitsBetweenItsAnchors`,
  lines 209–302), all iterating the table; the rewritten header note (lines 8–22)
  and the parser comment (lines 104–119).
- `Sources/ViewportBenchmarks/RealisticProviderBenchmark.swift` — the comment-only
  rewrite of the `realisticProviderScenarios()` note (lines 83–96), now describing
  the standard shape-1 gate route.
- `.github/scripts/realistic-relative-observation.sh` — deleted.
- `AGENTS.md` — four passages: Commands list, CI chain + gate count (eleven →
  twelve), the Gate-budgets realistic paragraph, and the Package-layout
  `WorkflowShapeTests` description.
- The spec, plan, and verification record for the slice; the AC7 hosted-proof edit.

Out of review scope, because the slice did not touch them (confirmed by
`git diff --name-only 88a4bcd 413390d -- Sources/TextEngineCore
Sources/TextEngineReferenceProviders .github/scripts/derive-gate-budgets.sh
.github/scripts/harvest-gate-corpus.sh
docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` → **empty**):
`Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`, every budget
literal under `Sources/ViewportBenchmarks/`, the corpus TSV,
`derive-gate-budgets.sh`, and `harvest-gate-corpus.sh`. The whole changed set is
exactly `swift-ci.yml`, `WorkflowShapeTests.swift`, `AGENTS.md`, the comment-only
`RealisticProviderBenchmark.swift` edit, the deleted observation script, and the
three slice docs (spec, plan, verification).

## Product Brief Alignment

This slice adds **no engine surface**, moves **no measured latency**, and touches
**no public API**. The hard constraints hold trivially, and the brief's perf
invariant is the one thing it directly strengthens.

- **Foundation-free core** — no core file changed; `rg -n Foundation
  Sources/TextEngineCore` is empty (re-run for this review, exit=1). The lone Swift
  edit is a comment in `Sources/ViewportBenchmarks/`, not the core, and the
  `WorkflowShapeTests` `import Foundation` is pre-existing in the test target (it is
  how the file reads the workflow off disk).
- **Swift Embedded / iOS+WASM** — no engine surface touched; both cross-target jobs
  are green on both hosted runs.
- **Zero-dependency** — no package added; the guard extension is stdlib-only, and a
  327-line shell script was *removed*.
- **Memory / virtualization invariants** — unchanged; not in scope.
- **Perf invariant (the brief's «блокируют merge при деградации» / «60 FPS»)** —
  *directly advanced*. The realistic 100k/10MB scroll workload — the truest
  realization of «превратить 60 FPS в измеримый headless budget» — was, until this
  slice, the **sole** gateable mode CI never ran with `--gate`. It now blocks merge
  on both the windowed-corpus regression budget (p95 97 µs / p99 200 µs) **and**,
  being frame-hot-path, the fixed 1.67 ms 60-FPS absolute ceiling
  (`budget_absolute_p99_ns=1666666`, present on the gate line). Of the twelve
  gateable modes, twelve now block merge; the last exception is closed.

The one honest cost, stated plainly in the spec (Decision 1 / "Accepted
trade-off"): promotion retires the sensitive `1.22×` base-vs-head relative detector,
which could catch sub-8× realistic regressions the coarser absolute budget cannot.
That detector was deliberately observational and `continue-on-error` (it never
blocked a merge), and its sanctioned replacement — the absolute gate over the
windowed corpus — is the mechanism the other eleven gates already trust. A correct
trade: a real blocking gate over a toothless observation.

## Delivered Design

### The promotion is a well-worn playbook, executed cleanly

The "observation → Nth blocking gate" move is the eighth of its kind
(Slices 24/26/28/32/34/36/38/40). The mode was already `isGateable` and already
`isFrameHotPath`, `runRealisticProviderBenchmarks(enforceGate:)` already implemented
the gate, and the budget was already committed and `GateFloorTests`-enforced. So the
Swift surface genuinely did not need to change — the spec's "zero-engine-behavior-
change, not zero-Swift-file-change" framing is exactly right, and the confinement
diff (empty for engine/provider/budget/corpus/script) proves it.

### One step, one summary line — the harvest-double-count hazard is respected

Decision 1 **replaces** the observation step rather than keeping both. This is the
load-bearing correctness call: if the gate step (shape 1: one
`mode=realistic_provider … p95_ns=…` line) and the observation step (shape 2: the
`mode=realistic_relative_observation` line the harvester reads as 8 rows) both ran on
a PR, a single run would contribute 1 + 8 rows for the same
`realistic_provider|100k_lines_10mb_text` key, **double-weighting** it in
`median()`/`max()` — the exact "exactly one CI step may print a mode's summary lines"
hazard `AGENTS.md` warns about. I verified the invariant holds on the merged tree:
the host-job log of the post-merge push run prints `mode=realistic_provider`
**once** as a gate line and `mode=realistic_relative_observation` **zero** times, and
the `Observe realistic provider relative performance` step is absent from both hosted
runs.

### Generalize-at-the-second-instance: the two-entry table

Rather than copy-paste ~120 lines to pin a second gate, Slice 45 lifted the six
`WorkflowShapeTests` invariants to iterate a `pinnedGateSteps: [GateStepSpec]` table
(`{point-geometry, realistic}`), each row carrying `(flag, stepName, command,
afterStepName, beforeStepName)`. This is the right moment to generalize — the second
instance is when a table pays for itself — and it deliberately stops **short** of
Option D (a full `BenchmarkMode → flag` map + exhaustive exemption registry), for the
still-valid reason that `.pipeline` has no flag and there is no flag-mapping. The
position invariant now pins the full tail order
`point-query < point-geometry < realistic < memory-shape`.

### The six invariants are genuinely non-vacuous

The key protection is the `steps(for:)` helper (line 196): it filters the workflow's
steps by the spec's flag and asserts the match set is **non-empty**
(`XCTAssertFalse(matches.isEmpty, …"the gate is gone")`) *before* any per-step
assertion. So a deleted or renamed gate reddens rather than passing vacuously — the
failure mode a naive `for step in matches { … }` over an empty set would hide. Each
invariant then asserts real content: exactly-one-step (1), exact whitespace-joined
command equality (2, which subsumes the `--gate` check and forecloses a double
invocation or trailing `|| true` inside one block scalar), not-`continue-on-error`
(3), the docs-only guard (4), the exact step name (5), and contiguous position
between named anchors (6, which additionally `XCTFail`s if either anchor step is
missing). I proved invariant 3 **live** directly (below); the other five share the
same non-empty guard. The one residual — a gate silently *un-pinned* by deleting its
table row — is the documented, conscious tradeoff of the explicit-table design (the
header note says "a gate joins this table by hand when it is promoted"; Option D is
what would close it), not a defect.

### Narrative de-rotting was thorough

The gate-count went eleven → twelve in the CI chain; the Commands list gained the
`--realistic-provider --gate` line; the Gate-budgets paragraph that flatly asserted
`--realistic-provider` "is the one gated mode CI never runs with `--gate`" was
rewritten to describe the standard shape-1 route (while correctly preserving the
*historical* explanation for pre-slice readers); and the source comment above
`realisticProviderScenarios()` was rewritten the same way. The rewrite also
**incidentally resolved** a standing P3 (see P3 #6 below): the pre-slice
`WorkflowShapeTests` comment cited `swift-ci.yml:145-148` by line range; the rewrite
dropped that drift-prone pointer entirely.

## Verification Evidence Reviewed

### Fresh local checks on the merged tree (`26befe9`)

| Check | Result |
|---|---|
| `swift build -c release` | clean (`Build complete!`) |
| `swift test` | **311 tests, 0 failures** (matches the recorded count) |
| `swift run … -- --realistic-provider --gate` | `gate=pass`, `p95_ns=5331 p99_ns=5614`, `headroom_p95=18.2x headroom_p99=35.6x`, `budget_absolute_p99_ns=1666666`, `headroom_absolute_p99=296.9x`, `checksum=756321289736960` |
| `swift run … -- --gate \| grep -c gate=pass` | **3** (the three synthetic pipeline scenarios) |
| `rg -n Foundation Sources/TextEngineCore ; echo exit=$?` | empty, **exit=1** |
| confinement diff (`88a4bcd..413390d`, engine/provider/derive-script/harvest-script/corpus) | **empty** |
| whole-slice changed set (`88a4bcd..413390d`) | only `swift-ci.yml`, `WorkflowShapeTests.swift`, `AGENTS.md`, `RealisticProviderBenchmark.swift`, the deleted observation script, and the three slice docs |
| one-step-per-mode invariant | exactly one `mode=realistic_provider` gate printer; zero `mode=realistic_relative_observation` (both hosted logs) |
| guard-is-live (inject `continue-on-error` → red → revert → green) | reproduced independently; RED naming the realistic step, clean revert matching HEAD, back to GREEN |
| tree after revert | **byte-clean** — `git status --short` empty, no `.bak`, revert byte-matches `HEAD:swift-ci.yml` |

The local realistic `checksum=756321289736960` is byte-identical to both hosted runs
(the fold hashes byte offsets/lengths/content, not timing), so it is deterministic
across platform and run.

### Guard-is-live, independently reproduced (the NEW realistic pin)

A guard over already-satisfied state is green on introduction, so it must be proven
live for the *new* pin specifically — the point-geometry pin's liveness proves
nothing about the realistic entry. I reproduced the break on the merged tree, not
trusting the recorded transcript: a `.bak`-backed `perl` injection of
`continue-on-error: true` immediately under the `Run realistic provider benchmark
gate` step's `if:` guard (a one-line diff) turned
`WorkflowShapeTests.testNoPinnedGateIsContinueOnError` **red** with exactly

```
WorkflowShapeTests.swift:242: error: … testNoPinnedGateIsContinueOnError :
XCTAssertNil failed: "true" - Run realistic provider benchmark gate: carries
continue-on-error: true — a continue-on-error step cannot be a gate; it swallows
budget misses, correctness failures and crashes alike
```

Exactly one of the six methods failed — `testNoPinnedGateIsContinueOnError`, naming
the realistic step by its exact name — while the other five passed (none concerns
`continue-on-error`). Reverting from the backup restored GREEN
(`Executed 6 tests, with 0 failures`), the reverted file byte-matched
`git show HEAD:.github/workflows/swift-ci.yml`, and `git status --short` came back
empty (no stray `.bak`, no residual diff). The break was never committed. The new
pin is live.

### Hosted runs (spot-checked at job *and* step level against the AC7 record)

The verification doc's `## Hosted CI — Discharged (AC7)` section records both runs
read at step level (per the Slice 16 dead-step-trap rule — a `continue-on-error`
step can conclude a job green while its own step failed). I confirmed job
conclusions with `gh run view … --json jobs` **and** re-pulled the host-job logs to
read the realistic line and the whole-run tally at step level.

- **PR-head run `29692848870`** (commit `144e08e`, `pull_request`, branch
  `slice-45-realistic-provider-ci-gate-promotion`): all three required jobs
  `success` (Host, iOS, WASM); realistic step `mode=realistic_provider … p95_ns=13157
  p99_ns=13462 … budget_absolute_p99_ns=1666666 headroom_absolute_p99=123.8x
  gate=pass checksum=756321289736960`; whole-run tally **46 `gate=pass`, 0 fail**;
  no `mode=realistic_relative_observation` line; the removed observation step absent.
- **Post-merge `push` run `29694705807`** (merge `413390d`, `push` to `main`): all
  three required jobs `success`; realistic step `… p95_ns=13079 p99_ns=13445 …
  headroom_absolute_p99=124.0x gate=pass checksum=756321289736960`; identical tally
  **46 `gate=pass`, 0 fail**; observation step and its summary line absent. The
  merged-code push run anchors the proof.

Both runs' realistic `checksum=756321289736960` byte-matches the local run. Hosted
p95 (~13 µs) is ~2.4× the local p95 (~5.3 µs), consistent with `AGENTS.md`'s "hosted
Linux x86_64 runs 2–3× slower" calibration note; hosted regression headroom is
7.4×/14.9× (in-band) and absolute headroom ~124× (far under the 1.67 ms ceiling).
The recorded `checksum` and the `46 gate=pass / 0 fail` tally are accurate.

## Git History

Three implementation commits on top of two pre-committed design/plan docs, cleanly
separated by concern and following the slice lifecycle: `f53b43a` (docs: design) →
`8a33638` (docs: refine spec) → `17383e7` (docs: plan) → `9630bfb` (ci: wire the
gate, generalize `WorkflowShapeTests`, delete the orphaned script) → `c229bb7`
(docs: retire the observation-only narrative — the comment/doc de-rotting) →
`144e08e` (docs: local verification) → merged as `413390d` (PR #102). The AC7 hosted
proof lives in the docs-only follow-up `3a6e98c` (PR #103, merged as `26befe9`),
matching the established pattern of discharging step-level hosted proof after merge.
Conventional-commit prefixes are correct; the `ci`/`docs` split matches the work
(one wiring commit, the rest docs), and the code-and-test change rides in the single
`ci:` commit — appropriate, since the test *is* the wiring's guard.

## Code Review Findings

### P0 / Release Blockers

**None.** The slice is merged; all twelve gates are green on the merged commit at
step level on both the PR-head and post-merge push runs; both hard constraints hold
(Foundation-free, zero engine/provider/script/corpus diff); the realistic gate
prints `gate=pass` hosted with in-band headroom under both the regression and
absolute ceilings; and the new `WorkflowShapeTests` pin is demonstrably live
(break→red→revert→green re-reproduced for this review).

### P1 / Must Fix Before Merge

**None.** The gate is a real blocking step (not `continue-on-error`, carries the
docs-only guard, exact command equality pinned); the harvest-double-count invariant
is preserved (one printer, zero observation lines); the guard-is-live break was
reproduced independently; and the hard constraints plus the checksum byte-identity
are re-verified.

### P2 / Production Readiness

**P2 #3 (carried from Slice 42→44): harvester provenance gap — CARRIES, and
Slice 45 raises its stakes.** `harvest-gate-corpus.sh` still selects rows by run id
alone (no `conclusion`/`event`/fork check), so a fork PR's CI run could in principle
print fabricated `p95_ns=` lines a later harvest would ingest into the corpus. This
remains the **only unverified link in the calibration chain**: Slice 44 proved
budgets derive faithfully *from* the corpus, but nothing authenticates what enters
it. Slice 45 does not change the *class* of exposure — the other eleven budgets
already block merge on the same unguarded ingestion — but it **extends it to a
twelfth budget and elevates the consequence**: the headline realistic workload is now
merge-blocking, and (per the spec's own "Relation to the Slice 44 recommendation")
its calibration provenance is the *thinnest* of the twelve, having only ever arrived
via the retired shape-2 line. The spec explicitly names provenance hardening as "the
recommended immediate follow-on, now covering 12 blocking budgets instead of 11."
Untouched this slice; the leading Slice 46 candidate.

**P2 #1 (carried from Slice 43→44): bulk-edit absolute backstop.**
`bulk_structural_mutation` is exempt from the absolute product ceiling, so slow drift
in bulk-edit latency is caught only by its median-anchored regression budget.
Correct *scope* (a multi-line paste is not a scroll frame), but a real recorded gap.
Untouched this slice; carries. The strongest *product* candidate for Slice 46 (needs
a product-target decision first).

**P2 #4 (carried from Slice 41/42→44): p95 thin axis / thin realistic calibration.**
Under the trailing N=20 window, the sub-µs `line`/`column`/`point` cluster sits
closest to the starvation floor. Slice 45 adds a mode-specific wrinkle worth naming:
realistic's corpus rows historically came *only* via shape 2, so during the ~20-run
transition the window mixes shape-2 (8 rows/run) and shape-1 (1 row/run), briefly
over-weighting the older shape-2 rows in `median()`. This **self-heals** as shape-1
rows accumulate to identical provenance as the other eleven gates, and any
`budget_stale` that surfaces during the transition is a re-derive, not an engine
regression (`GateFloorTests`/the reason string will name it). Monitor; carries.

### P3 / Minor But Valid

**P3 #6 (carried from Slice 41/42→44): `WorkflowShapeTests` cited `swift-ci.yml` by
line range — ✅ RESOLVED by this slice.** The pre-slice file (line 98) read
"`swift-ci.yml:145-148` is a …" — a pointer that drifts if that YAML is edited above
it. The Slice 45 comment rewrite dropped the line-range citation entirely (grep of
the current file for any `swift-ci.yml:NNN` / `lines N-M` pointer → **none**). A
clean incidental fold of exactly the "fold rotting quotes in the file you touch"
lesson. Closed.

**Standing item RESOLVED: realistic-provider observation PR-only
`continue-on-error`.** Prior reviews (through Slice 44) listed under "standing items
unchanged": "realistic-provider observation PR-only `continue-on-error`." Slice 45
**deleted** that step and its script, so the standing item is resolved — the last
`continue-on-error` benchmark step on the host job is gone, and the realistic
workload is now a real blocking gate. Worth recording as a genuine strength.

**P3 #1 (carried from Slice 43→44): frozen `580 µs / 2.87×` figures — two sites
still carry, unchanged.** `Sources/ViewportBenchmarks/BenchmarkModels.swift:145`
("regression p99 budget is <= 580us < the 1.67ms ceiling") and `AGENTS.md:336`
("binding scenario `structural_mutation|1m`, 580 µs, 2.87× under") both still quote
the frozen number, falsified by the next re-derivation that raises the
`structural_mutation|1m` p99 budget (while staying under the ceiling). Slice 45 did
edit `AGENTS.md`, but not that section (its edits were the Commands list, the CI
chain, the Gate-budgets realistic paragraph, and the Package-layout bullet), so the
"fold it in the file you touch" opportunity did not present on line 336. Unchanged;
carries. (`StructuralMutationBenchmark.swift:38`'s `580_000` is the live budget
*literal*, correct to keep.) Both remaining sites cite `GateFloorTests` as the
enforcing mechanism, so the load-bearing claim doesn't depend on the number.

**P3 #3 (carried from Slice 44): the parser `derivedBudgets(fromScriptOutput:)` has
no isolated fixture unit test.** Untouched this slice (out of scope); carries. Its
skip-on-missing-token behavior is correct by inspection and backstopped by the
bijective cardinality check, but never demonstrated by a synthetic fixture. Low
urgency.

**P3 #5 (carried, recurring): plan checkboxes left unchecked.** All 20 steps in the
committed plan are `- [ ]` (0 checked) though the work shipped; the commit messages
are the completion evidence. Recurring cosmetic paper-trail nit, unchanged from prior
slices.

**P3 #7 (NEW, from the slice's own SDD reviews): the realistic entry's
`afterStepName` literal duplicates the point-geometry `stepName` literal.** In
`pinnedGateSteps` (`WorkflowShapeTests.swift:62`), the realistic row's
`afterStepName: "Run point geometry query benchmark gate"` repeats, as a second bare
string, the point-geometry row's own `stepName: "Run point geometry query benchmark
gate"` (line 54). A future rename of the point-geometry step needs two synced edits.
**Mitigating — it fails loudly, not silently:** if the point-geometry name changes
but the realistic `afterStepName` is not synced, invariant 6
(`testEachPinnedGateSitsBetweenItsAnchors`) resolves
`stepNamed("Run point geometry query benchmark gate", …)` to `nil` and `XCTFail`s
with "missing … the ordering anchors … are gone." It is also the plan's own
specified table shape. A small DRY nit (the `afterStepName`/`beforeStepName` anchors
could reference other rows' `stepName`s or a shared constant), not a correctness
hole. Low urgency.

**P3 #8 (NEW): `AGENTS.md:402` "a `realistic_provider` run contributes 8" is now
stale for new runs.** Post-Slice-45 a realistic run contributes **1** corpus row
(shape 1), not 8 (shape 2). The claim is still true of the *historical* shape-2 rows
in the append-only corpus, and it mirrors the deliberately-retained harvester comment
(`harvest-gate-corpus.sh:37`, same "contributes 8"), so it is defensible while
pre-Slice-45 logs remain in retention. It should be retired **together with** the
harvester's shape-2 read-branch once those logs age out — the same follow-up the spec
scoped out (Non-goals: "Harvester shape-2 cleanup"). Recorded so the two stale sites
are cleaned as a pair, not forgotten. Minor.

**P3 #9 (NEW, trivial): the verification doc has no explicit `## Summary` heading.**
The plan named a "Summary" section; the verification doc opens with the equivalent
prose (lines 1–21) but without the heading. Content is present; purely cosmetic.

**Non-finding (recorded for completeness):** the `swift-ci.yml` deletion removed the
*trailing* rather than the leading blank line of the removed step. The final file is
byte-correct — `WorkflowShapeTests` parses it, `swift test` is green, and the
guard-is-live revert byte-matched `HEAD`. No action.

## Risks And Gaps

- **Harvester provenance (P2 #3)** — the corpus's *ingestion* is unauthenticated
  (run-id-only selection), now under **twelve** blocking budgets including the
  headline realistic workload. The single unverified link in an otherwise
  fully-pinned calibration chain; the natural tooling/security successor and the
  spec's own named follow-on.
- **Bulk-edit absolute backstop (P2 #1)** — the frame path is guarded on both the
  regression and absolute axes; bulk on regression alone, by deliberate scope. The
  strongest *product* successor once a bulk-appropriate target is chosen.
- **Realistic shape-2 → shape-1 transition (P2 #4)** — the N=20 window briefly mixes
  provenance shapes; self-heals; a `budget_stale` during the transition is a
  re-derive, not a regression.
- **Explicit-table un-pinning gap** — `pinnedGateSteps` is hand-maintained, so a gate
  can be silently un-pinned by deleting its row (no test catches that). Documented
  tradeoff of the design; Option D (full `BenchmarkMode → flag` map + exemption
  registry) is what closes it.
- **Two frozen-number sites (P3 #1)** — `BenchmarkModels.swift:145`, `AGENTS.md:336`;
  a rotting comment, not a defect.
- **Two paired stale "contributes 8" sites (P3 #8)** — `AGENTS.md:402`,
  `harvest-gate-corpus.sh:37`; retire with the shape-2 branch when the logs age out.
- **Standing items unchanged** — WASM observational; the `Main` ruleset keeps its
  documented bypass-actor shape.

## Lessons For The Next Slice

- **The "observation → blocking gate" promotion is now a low-risk playbook — but
  Slice 45 was the last easy one.** This is its eighth application, and it closed the
  final gateable mode that wasn't blocking. There is no twelfth-style "promote an
  existing observation" left; the honest next moves are the *input-trust* gap
  (harvester provenance) or the *product* axis (bulk-edit budget), not more of the
  same.
- **Generalize at the second instance.** Lifting the six `WorkflowShapeTests`
  invariants into a two-entry table the moment a second gate needed pinning avoided a
  ~120-line copy-paste and left the invariants ready to absorb the next promotion by
  adding one row. The non-empty `steps(for:)` guard is what keeps the table-iterating
  tests non-vacuous — pin that property whenever a test quantifies over a filtered
  set.
- **A rewrite naturally sheds rotting pointers — use that.** The comment rewrite
  incidentally resolved P3 #6 (a `swift-ci.yml:145-148` line-range citation) simply
  because a value-free rewrite doesn't reintroduce line numbers. The same discipline
  is why P3 #1's two frozen-`580 µs` sites *didn't* get folded: the slice didn't
  rewrite those exact lines. Fold rotting quotes when you're already in the lines.
- **Retire a read-branch only after its inputs age out.** Keeping the harvester's
  shape-2 branch (and its "contributes 8" comment) while pre-slice-45 logs remain in
  GitHub's retention window is correct — deleting it now would mis-harvest those
  logs. Scope the paired cleanup (branch + the two "contributes 8" prose sites) as a
  follow-up gated on log expiry.
- **Prove the new pin live, not the old one.** The point-geometry pin's prior
  liveness proof says nothing about the realistic entry; the break→red→revert→green
  cycle was re-run specifically for the realistic step, and this review re-reproduced
  it on the merged tree rather than trusting the transcript.

## Slice 46 Candidate Options

Slice 45 took a direction (promoting the realistic gate) that was **not** among the
Slice 44 review's recommendations — those (harvester provenance / bulk-edit absolute
budget) remain open and are the leading Slice 46 candidates. Slice 45's own spec
names harvester provenance as the recommended immediate follow-on.

### Option A: harvester provenance hardening (P2 #3) — recommended

Filter harvested runs by `conclusion=success` / expected event / non-fork before
ingesting their `p95_ns=` lines, closing the injection surface. This is now the
**only unverified link in the calibration chain**, and Slice 45 *raised its stakes*:
the headline realistic workload is now merge-blocking on the same unguarded
ingestion, with the thinnest provenance of the twelve budgets. It is small,
self-contained, security-shaped, needs **no product decision**, and has an existing
self-test seam (`harvest-gate-corpus.sh --self-test`) to hang a standing test on. It
finishes the "trust the budgets" story by finally trusting their source.

### Option B: bulk-edit absolute budget anchored to a bulk-appropriate target (P2 #1)

Give `bulk_structural_mutation` its own absolute ceiling ("a 4096-line paste in ≤ N
frames"), closing the deliberate residual Slice 43 recorded. This is the strongest
*product* step — it advances the brief's «60 FPS» north star a concrete step beyond
the frame-hot-path ceiling. But it needs a **product-target decision** (N frames for
a bulk paste) before the ceiling can be a fixed constant, so it should open with a
short brainstorm/product call rather than be executed cold.

### Option C: harvester shape-2 retirement (the spec's own scoped-out follow-up)

Remove the `mode=realistic_relative_observation` read-branch in
`harvest-gate-corpus.sh` and its paired "contributes 8" prose (P3 #8), once
pre-slice-45 run logs age out of GitHub's retention window. **Not yet actionable** —
those logs still exist and still need the branch to harvest correctly. Premature this
slice; revisit later.

### Option D: residual fold + `WorkflowShapeTests` full generalization

Fold the two frozen-`580 µs` sites (P3 #1), add an isolated parser fixture test
(P3 #3), tidy the `afterStepName` duplication (P3 #7), check the plan boxes (P3 #5),
and/or generalize `WorkflowShapeTests` to every gated mode (the deferred Option D
from prior slices). Standing infra / low-value cleanup; best folded opportunistically
into a larger slice.

## Recommended Slice 46 Selection

**Option A — harvester provenance hardening (P2 #3).** With Slice 45 closing the last
non-blocking gateable mode, twelve budgets now block merge — every one of them
resting on a corpus whose *ingestion* nothing authenticates. That makes provenance
the single highest-leverage remaining item: it is the root-of-trust gap under the
entire pinned chain Slices 41–44 built, Slice 45 elevated its consequence (the
headline workload now blocks on the thinnest provenance), it is small and
self-contained (a `conclusion`/`event`/fork filter in `harvest-gate-corpus.sh` plus a
standing test on the existing `--self-test` seam), and — unlike the product option —
it needs no external decision to start. It is also the slice's *own* named follow-on.

**Option B (bulk-edit absolute budget)** is the strongest *product* alternative and
the direct completion of Slice 43's recorded residual; prefer it if the user would
rather advance the product axis than finish hardening the pipeline — but it must open
with a product-target decision (N frames for a bulk paste), so it is a product call,
not a cold-start engineering slice. Honestly weighed: with the last observation gate
now promoted, the product axis is where the *project* ultimately wants to go, but the
provenance gap is cheaper, decision-free, more urgent (a live trust gap, not a
deferred feature), and now guards twelve blocking budgets — so it leads, with the
product call as the clear follow-on once the user sets a bulk target. Fold the
trivial P3s (two `580 µs` sites, `afterStepName` DRY, plan checkboxes, and — when the
retention window clears — Option C's shape-2 retirement with its paired "contributes
8" prose) opportunistically if Slice 46 touches those files.

## Slice 45 Review Conclusion

Slice 45 does exactly what its spec asked, with no scope creep: it promotes the
realistic 100k/10MB scroll-compute benchmark to the twelfth merge-blocking gate,
closing the one gateable mode CI never ran with `--gate` — the truest realization of
the brief's «превратить 60 FPS в измеримый headless budget», now enforced on the
headline workload rather than a synthetic proxy and held under both the windowed
regression budget and the fixed 1.67 ms absolute ceiling. The execution is clean: the
mode already honoured `--gate`, so no engine/provider/budget/corpus/derive-script byte
moved (confinement diff empty; the only Swift edit is a comment); the observation
step was *replaced*, not duplicated, preserving the one-printer-per-mode
harvest-double-count invariant (verified: one `mode=realistic_provider` line, zero
`mode=realistic_relative_observation`); `WorkflowShapeTests` was generalized into a
two-entry table with six genuinely non-vacuous invariants rather than copy-pasted; and
the narrative de-rotting was thorough, incidentally resolving the standing P3 #6
line-range citation. The merged commit is green across all twelve blocking gates at
step level on both the PR-head and post-merge push runs (**46 `gate=pass`, 0 fail**,
host tests **311/0**, realistic `checksum=756321289736960` byte-identical across local
and both hosted runs). The new gate's `WorkflowShapeTests` pin was proven live
(break→red→revert→green re-reproduced for this review) and the tree left byte-clean.
**P3 #6 (line-range citation) and the standing "realistic observation PR-only
continue-on-error" item are resolved; P2 #1 (bulk-edit backstop), P2 #3 (harvester
provenance — now elevated), P2 #4 (p95 thin axis), P3 #1 (two frozen-`580 µs` sites),
P3 #3 (parser fixture), and P3 #5 (plan checkboxes) carry; three minor NEW items
(P3 #7 `afterStepName` DRY, P3 #8 paired "contributes 8" staleness, P3 #9 missing
Summary heading) are all low-urgency.** No P0, no P1. **READY — merged and verified;
Slice 46 = harvester provenance hardening (Option A, decision-free and now the slice's
own named follow-on), or a bulk-edit absolute budget (Option B) to advance the product
story once a bulk target is chosen.**
