# Point-Geometry-Query CI Gate Promotion Design

Date: 2026-07-16

## Status

Approved design direction, written for user review. Revised twice:

1. After the first spec review (see `## Provenance` below): the ratchet repair this
   slice originally bundled was split out into Slice 41.
2. After a second review (2026-07-17), which raised seven findings, all verified
   against the repo and all taken. Six were text defects — a stale Source Context,
   a "single PR" scope that contradicted the post-merge proof AC11 demands, a
   `repositoryRoot()` choice one arm of which AC8 forbade, `29426572267`
   miscalled the first unharvested run, and Slice 41 described as both settled and
   un-prejudged. One changed a decision: **Decision 6's `run:` assertion is now
   exact equality**, because a step-level token count left a double invocation and
   a trailing `|| true` both green. The review's one security finding (the
   harvester filters runs by id alone) was verified true but is recorded as a known
   gap under Risks rather than actioned here — the durable fix is a harvester
   change, which Non-Goals forbids.

## Source Context

This is Slice 40 of SwiftTextEngine, following the Slice 39 post-slice review:

```text
docs/superpowers/reviews/2026-07-15-slice-39-post-slice-review.md
```

That review is in `main` (commit `dc29e14`, merged as `9522224` via PR #86) and in
this branch, which is rebased on top of it. Read it in place. (The `Main` ruleset
enables strict required status checks, so this branch must in any case carry the
latest base-branch state before it can merge.)

The project brief in `docs/initial-project-brief.md` requires regression
benchmarks to block merge when performance regresses
(*"Регрессионные бенчмарки блокируют merge при деградации производительности"*).
That requirement already holds for **ten** blocking latency gates in the hosted
`Host tests and benchmark gate` job: synthetic, static variable-height,
variable-height-mutation, structural-mutation, bulk-structural-mutation,
line-query, line-geometry-query, column-query, column-geometry-query, and
point-query. It does **not** yet hold for the geometry-bearing 2D point query
`pointGeometryAt` introduced in Slice 39. Closing that gap is the whole of this
slice.

Slice 39 added the public stateless query
`ViewportVirtualizer.pointGeometryAt(x:y:lineMetrics:columnMetrics:) ->
PointGeometryQuery` — the geometry-bearing companion to Slice 37's `pointAt`,
which composes `lineGeometryAt` with `columnGeometryAt` to return both axes'
boxes, within-box fractions, and clamp flags. Unlike every prior functional
capability slice, Slice 39 was the **first to mint a gated budget under Slice
38's derived-budget rules** — no hand-typed placeholder is legal any more — so it
shipped its budget through the corpus derivation and landed the CI gate in a
**not-yet-blocking** shape (Slice 39 design Decision 5) — which that slice's first
review round then split into **two steps** (commit `5042747`, *"ci: keep
point-geometry correctness blocking, budget observational"*), because Decision 5 as
written specified a single `continue-on-error` step and wrongly assumed it would
still block on correctness:

- a bare `--point-geometry-query` step **without** `continue-on-error`, blocking
  on **correctness** (`failureCount != 0` fails the job), writing its benchmark
  output to a temp file so it does not double-weight future harvests;
- a `--point-geometry-query --gate` step **with** `continue-on-error`,
  **observational on latency** — its budget is enforced by the script but a
  budget miss cannot fail the job yet.

The Slice 39 post-slice review recommends Slice 40 as:

```text
Option A: promote --point-geometry-query to the eleventh blocking gate — and
repair the ratchet
```

### Provenance — why this slice is a bare promotion

The review's Option A folded in **Slice 38's still-open P2 #2** (the `3×max`
floor over an append-only corpus as a one-way ratchet), on the reasoning that
Slice 40 must harvest and re-derive anyway. The user selected Option A and, for
the ratchet repair, the **trailing-window** mechanism.

A spec review of the bundled design (2026-07-17) measured the proposed mechanism
against the committed corpus and found it did not deliver what the bundle claimed:

- **The window is inert for `point_geometry_query`.** The mode has 6 corpus runs;
  at N = 20 a per-key trailing window uses all of them — identical to today. The
  bundle's claimed synergy with the promotion was nil.
- **The window cannot repair the near-floor cluster**, which was the bundle's
  stated motivation. Whenever the `3×max` term governs,
  `budget = round_up_2sf(3×max)` lands just above its own floor **by construction,
  at any N** — a fact `AGENTS.md` already states — so lowering `max` merely re-pins
  the budget and returns the margin to the same sliver. That accounts for five of
  the six cluster members. The sixth,
  `point_geometry_query|prefixsum_100k`, is near-floor for a *different* reason: it
  is **median-governed** (8 × 91 = 728 > 3 × 231 = 693) and only lands near its
  floor by coincidence. Near-floor is an **implication** of floor-governance, not an
  equivalence. At N = 20, five of the six cluster members' margins were
  byte-identical before and after, and no cluster member's budget moved at all.
- **One cluster member is unreachable by any trailing window.**
  `column_query|uniform_100k` holds its p99 max (204 ns) on run `29285933609` —
  the newest run in the entire corpus.

The user therefore split the work: **Slice 40 is the promotion alone**, and the
ratchet repair becomes **Slice 41** with a two-lever mechanism chosen against that
evidence (see `## Recommended Next Step`). This restores the standing
one-concern-per-slice convention rather than bending it.

### Relationship to the prior gate work (Slices 5, 15, 21, 24, 26, 28, 32, 34, 36, 38)

This slice lands the **eleventh** blocking gate: Slice 5 wired the first (the
synthetic `--gate`) into CI, and Slices 15/21/24/26/28/32/34/36/38 added the next
nine. Unlike Slice 26 (which folded in `deterministicIndex` overflow hardening)
and Slice 38 (which recalibrated every budget before promoting `--point-query`) —
it is a **bare promotion**: one concern, no bundled machinery change.

Unlike Slices 28/32/34/36 (pure zero-Swift promotions of a never-hosted
benchmark), the `--point-geometry-query` benchmark **already runs in hosted CI**
since Slice 39 — bare (correctness) and gated (observational). So this promotion
is the **flip-an-existing-observation-to-blocking** shape (like Slices 15 and
21), with prior hosted Linux evidence in hand and more accumulating on every run
since the Slice 39 merge.

### Current corpus and calibration shape (relevant facts)

- Corpus:
  `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`, **append-only**,
  header `run_id  mode  scenario  p95_ns  p99_ns`, 1,691 data rows from 42
  distinct runs at the time of writing. The run id is the harvester's dedup key
  (`gh run list --json databaseId`), so it is GitHub's **globally monotonic**
  run database id.
- Per-key run counts range **6 → 42**: the oldest modes (`pipeline`,
  `variable_height`, `variable_height_mutation`) have 42 runs; `point_geometry_query`
  (newest, Slice 39) has 6; `realistic_provider` has 29 and — being the one gated
  mode CI never runs with `--gate` — reaches the corpus only through the PR-only
  `mode=realistic_relative_observation` line, so it appears only in PR runs.
- **All 46 committed gated budgets are recipe-derived and reproduce byte-for-byte
  from `derive-gate-budgets.sh` against the committed corpus at HEAD.** There are
  **no carve-outs**. Slice 38 had deliberately left 13 scenarios at hand budgets,
  but **Slice 39 retired that carve-out**: its harvest moved the corpus under them,
  and commit `a23e559` re-derived every budget that no longer reproduced — 19 of
  the 42 pre-existing budgets, including all 13 (Slice 39 verification record
  §6b). Any design that still speaks of a 13-scenario carve-out is one slice out
  of date.
- One row per run per key, **except** `realistic_provider|100k_lines_10mb_text`,
  which carries 8 rows per run (232 rows from 29 runs). The `n=` field
  `derive-gate-budgets.sh` prints is therefore a **row** count, not a run count.
- The recipe (`derive-gate-budgets.sh`, Slice 38 Decision 2) is unchanged by this
  slice:

  ```text
  budget_p95 = round_up_2sf(max(8 * median(p95), 3 * max(p95)))
  budget_p99 = round_up_2sf(max(2 * budget_p95, 8 * median(p99), 3 * max(p99)))
  ```

## Problem

**The point-geometry-query path's latency is not blocking.** Its `--gate` step
carries `continue-on-error`, so a budget miss cannot fail the job. The brief's
"benchmark gates block merge" principle is not yet true for the geometry-bearing
2D point query — the only mode CI runs **with `--gate`** for which it is not.

(`realistic_provider` is also a gated mode — `isGateable`, and registered in
`everyGatedBudget()` with a corpus-derived budget — but CI deliberately never runs
it with `--gate` at all: its step is a PR-only, `continue-on-error` relative
observation (`AGENTS.md:340`). That is a standing exception, not a gap this slice
closes, which is why the Slice 39 gate sweep counts 45 `gate=pass` — 46 gated
budgets minus `realistic_provider`.)

The two-step split was correct while the budget was observational, but it is
load-bearing scaffolding, not a destination: `continue-on-error` swallows *every*
non-zero exit, so a lone gated step under it would also swallow `failureCount != 0`
and crashes (the Slice 16 dead-step trap). Slice 39 built the split precisely so
Slice 40 could remove both halves at once.

## Scope

Slice 40, in a single implementation PR (plus the standing post-merge evidence
follow-up — see `### Verification record`):

- harvests fresh hosted runs and **re-derives every gated mode** from the enlarged
  corpus, re-committing every budget the recipe now produces differently (all 46
  are recipe-derived; there is no exempt set);
- collapses the point-geometry-query two-step CI wiring into **one blocking step**
  (correctness + budget), making it the eleventh blocking latency gate;
- **relocates** the mode-independent "exactly one CI step may print a mode's
  summary lines" invariant into `AGENTS.md` before its only two copies are deleted
  by that collapse (Decision 2);
- adds an executable **workflow-shape assertion** so the collapsed wiring has a
  regression guard rather than a one-time hand check (Decision 6);
- updates `AGENTS.md` (the CI section, the architecture paragraph, and the
  Commands block graduate point-geometry-query from "gateable, not yet blocking"
  to blocking).

Expected implementation surface:

- `.github/workflows/swift-ci.yml` (collapse the two point-geometry-query steps;
  delete the now-false rationale comment)
- `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (new; the workflow-shape
  assertion)
- `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` (append-only:
  new harvested rows)
- the benchmark scenario budget tables under `Sources/ViewportBenchmarks` that the
  re-derivation changes
- `AGENTS.md`
- `docs/superpowers/verification/2026-07-16-point-geometry-query-ci-gate-promotion.md`

Expected paper trail: this design spec; a task-by-task TDD plan after approval; a
verification record with local + hosted evidence and hosted run IDs; a post-slice
review after implementation and merge.

## Non-Goals

- No `TextEngineCore` changes. No public API change. No `pointGeometryAt` /
  `pointAt` / query-type change.
- No `TextEngineReferenceProviders` changes.
- No benchmark **workload** change: no scenario added/removed, no viewport
  parameter, provider, `lineCount`, or sampler edit. Only budget **literals** move,
  and only where the re-derivation moves them. Every `point_geometry_query`
  checksum must stay byte-identical to Slice 39's.
- **No ratchet repair.** No trailing window, no outlier rejection, no floor-factor
  change, no recipe change of any kind. That is Slice 41. This slice does not
  **implement** the levers the user has already selected for it, and does not fix
  Slice 41's window size, constants, or derivation details — those are its design's
  to settle (see `## Recommended Next Step`).
- No corpus rewrite, row deletion, or `sort -u`: the corpus stays strictly
  append-only.
- No harvester change (`harvest-gate-corpus.sh` and its idempotent `--corpus`
  dedup are untouched).
- No absolute/product budget (Slice 38 Option C) — still the strongest open
  roadmap idea, and best added after the ratchet stops pushing budgets upward.
- No provider-native horizontal `columnIndex` descent (Slice 39 Option C/D).
- No ruleset mutation, required-context rename, docs-only-detector change, WASM
  promotion, or bypass-actor policy change.

## Decisions

### Decision 1 — Collapse the two point-geometry-query CI steps into one blocking step

Delete the bare `Run point geometry query benchmark (correctness; blocking)` step
(`swift-ci.yml:144-154`) **and** the `continue-on-error: true` on the
`Point-geometry query benchmark gate (budget observational until Slice 40)` step
(`swift-ci.yml:156-159`) **together**, leaving a single step, renamed to match its
ten siblings and to drop the now-false observational qualifier:

```yaml
- name: Run point geometry query benchmark gate
  if: steps.change-scope.outputs.docs_only_pr != 'true'
  run: swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate
```

positioned after the point-query gate and before the memory-shape diagnostic.

Deleting only one half is the trap: keeping the bare step alone would double-run
the mode (and double-weight it in every future harvest of that run); keeping
`continue-on-error` alone would swallow correctness failures too.

The 14-line rationale comment at `swift-ci.yml:130-143` describes the two-step
design and says "*until Slice 40, which deletes this step and the
`continue-on-error` on that one together*". It must be **deleted with the step it
explains** — but not before its durable half is relocated (Decision 2).

### Decision 2 — Relocate two durable rules before deleting their only copies

Two permanent, **mode-independent** rules currently live *only* inside text this
slice deletes. Both must be re-stated as general rules first, or the slice loses
them:

1. **Exactly one CI step may print a mode's summary lines.**
   `harvest-gate-corpus.sh` harvests every `p95_ns=`/`p99_ns=` line in a run's
   log, so a second printing step puts two rows per scenario into every future
   harvest of that run and **double-weights it in `median()`** — the term that
   governs most budgets. Its only two copies are `swift-ci.yml:130-143` (the
   comment) and `AGENTS.md:206-213` (the two-step description); Decision 1 and the
   CI rewrite delete both.
2. **The Slice 16 dead-step trap.** `continue-on-error` swallows *every* non-zero
   exit, so a gated step under it also swallows `failureCount != 0` and crashes —
   which is exactly why the correctness half could not simply live under the gated
   step. `AGENTS.md` states this lesson in **two** places, and this slice's
   documentation plan deletes **both**: `AGENTS.md:105-106` (architecture
   paragraph — "*One step cannot be both: `continue-on-error` swallows every
   non-zero exit, budget and correctness alike*") and `AGENTS.md:207-209` (CI
   section — the only site that names it the Slice 16 dead-step trap).

Relocations:

- Rule 1 → `AGENTS.md` `## Gate budgets`, where the harvester's other rules
  already live:

  > Exactly one CI step may print a given mode's benchmark summary lines. The
  > harvester reads every `p95_ns=` line in a run's log, so a second printing step
  > puts two rows per scenario into every future harvest of that run and
  > double-weights it in `median()`.

  This is distinct from the existing idempotent-harvest rule at `AGENTS.md:292-297`
  (re-harvesting the *same run* into the corpus twice) and the append-only/dedup-key
  paragraph at `AGENTS.md:329-333`; both stay as-is.

- Rule 2 → `AGENTS.md` `## CI`, detached from point-geometry-query and stated for
  any future gate:

  > A `continue-on-error` step cannot be a gate. It swallows every non-zero exit —
  > budget misses, correctness failures, and crashes alike (the Slice 16 dead-step
  > trap). An observational benchmark step and a blocking correctness step must
  > therefore be separate steps until the budget itself goes blocking, at which
  > point one step is both.

This decision is itself an instance of the failure it prevents: the bundled design
directed deleting both copies of rule 1, while its own workflow-invariant
assertions grepped for the literal `--point-geometry-query` — which appears
nowhere in that comment block — so nothing it specified would have caught the loss.

### Decision 3 — Re-derive every gated mode from the fresh harvest; there is no exempt set

Per `AGENTS.md`, a harvest re-derives every mode. After appending the fresh
harvested rows, run `derive-gate-budgets.sh <corpus>` (no mode arg → all modes)
and re-commit every budget the recipe now produces differently, so the "derived,
never hand-typed" invariant reproduces from the committed corpus + script.

All 46 gated budgets are recipe-derived and reproduce at HEAD; **Slice 39 retired
the Slice 38 13-scenario carve-out** (`a23e559`). This slice therefore applies one
uniform rule with no exemption, and the verification record checks all 46.

**A re-derived budget may move in either direction.** A harvest can raise or lower
a key's median, and the `8×median` term governs most budgets, so a *looser*
re-derived budget is a correct result to commit, not a derivation bug to chase.
Hand-editing one back down is the hand-typed-budget prohibition.

**The append and the re-derivation are one commit.** `GateFloorTests` reads the
*committed* corpus, and `swift test` is a blocking CI step (`swift-ci.yml:86-88`),
so a commit that appends rows without re-deriving in the same commit can leave the
tree red on `budget_stale`. With six budgets within ~5% of their floor and one at
0.0%, that is likely rather than hypothetical. Slice 39 landed them together
(`a23e559`); so does this slice.

### Decision 4 — Keep the host job order and the required contexts

The surviving point-geometry-query gate stays where the gated step is today —
after the point-query gate, before the memory-shape diagnostic — keeping all
eleven blocking latency gates contiguous. The three required job contexts
(`Host tests and benchmark gate`, `iOS cross-target compile`,
`WASM cross-target observation`) are unchanged. Docs-only detector, ruleset, and
bypass shape are unchanged; this PR changes workflow YAML, so it is never
docs-only and runs the full heavy path.

### Decision 5 — Treat a first-run hosted budget miss as evidence, not a thing to hide

If the promotion's hosted PR-head run fails because the re-derived budget does not
fit hosted Linux, **stop** and re-derive from the fresh hosted evidence in this
same PR (the standing rule). Do not restore `continue-on-error`, add a
workflow-only threshold, or hand-widen a budget.

### Decision 6 — Give the collapsed wiring a regression guard, not a one-time hand check

The workflow shape this slice creates is exactly the shape the Slice 16 dead-step
trap destroyed once already, and nothing in the repo reads `swift-ci.yml` to
defend it. Verifying it once, by hand, into the verification record is the failure
mode `GateFloorTests` was created to end ("*until this test existed the floor was
verified exactly once, by hand … and a corpus append or one mistyped constant
could undo it with nothing objecting*").

Add `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`, which reads
`.github/workflows/swift-ci.yml` from `repositoryRoot()` (the pattern
`GateFloorTests` already uses to read the corpus; the test target already links
Foundation) and asserts, **for `--point-geometry-query`**:

- exactly one step's `run:` payload carries the `--point-geometry-query` token;
- that step's whitespace-normalized `run:` payload **equals**, exactly, the single
  expected command:
  `swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate`;
- that step carries no `continue-on-error`;
- that step's `if:` is the **literal** `steps.change-scope.outputs.docs_only_pr != 'true'`
  — asserted as a literal, *not* by comparing against a sibling step's `if:`, so no
  other step's shape can flip this test red or green;
- that step is named `Run point geometry query benchmark gate`;
- that step sits after the point-query gate step and before the memory-shape step.

The last two pin AC1's name and ordering clauses, which would otherwise revert to
a one-time hand check.

**Why exact equality rather than "carries `--gate`".** Counting *steps* that carry
a token leaves two ways to disarm the gate with all six assertions green, both of
which live inside a single step's payload where a step-level count cannot see them:
a `|` block scalar that invokes the benchmark **twice** (one step, two runs,
double-weighting the mode in every future harvest of that run — the exact defect
Decision 2's rule 1 exists to prevent), and a trailing **`|| true`**, which is
`continue-on-error` by another spelling and would sail past an assertion that only
checks the flag key. Equality against one expected command closes both and subsumes
the `--gate` check. It does **not** subsume invariant 1: equality constrains the
matched step, not the existence of a second one, so the "exactly one step" count
stays and the two are complementary.

This makes the string in `swift-ci.yml` and the string in the test a matched pair —
a deliberate, cheap coupling. Changing the scratch path or the flag order is then a
two-line edit with a test naming the mismatch, which is the intended behavior for a
step whose exact shape *is* the invariant.

**Parsing contract** (there is no YAML parser — the package is zero-dependency and
Foundation ships none, so this is hand-rolled and must be specified, not left to
the implementer):

- **Scope to the host job first.** `swift-ci.yml` defines **three** jobs whose
  steps all indent identically at `      - name:`, and four step names
  (`Check out repository`, `Detect PR change scope`, `Complete docs-only PR`,
  `Show toolchain`) repeat verbatim in all three — so a whole-file split makes
  every name lookup ambiguous by construction (30 steps file-wide vs the host
  job's 20). Take the region from `  host-tests-and-benchmark-gate:` to the next
  line at indent ≤ 2, and split on `^      - name:` **within** it.
- **Match flags against the `run:` payload only**, with `#` comment lines
  excluded — the rationale comment this slice deletes names `continue-on-error`
  twice *inside* a step block, so a naive block scan would misread it.
- Read `continue-on-error` from the block's own keys and the guard from its `if:`.
- Compare **whitespace-separated tokens**, never substrings.

`repositoryRoot()` is `private` to `GateFloorTests.swift`. **Duplicate it** into
`WorkflowShapeTests.swift` with a comment naming its twin; do not hoist it into a
shared helper. Hoisting would edit `GateFloorTests.swift` and add a file, both
outside AC8's allowlist — this spec offering the choice at all was a defect. Three
duplicated lines are the smaller cost, and Slice 42 (which needs a shared reader
anyway) is where a helper belongs.

**Why one mode, and not `BenchmarkMode.allCases where mode.isGateable`.** That
quantifier is false today for **3 of the 12** gateable modes, so a test written
against it would be red for reasons unrelated to this slice — and since
`swift test` is a blocking CI step (`swift-ci.yml:86-88`), it would fail the
required job and take AC10/AC11 with it:

- **`.pipeline` has no flag.** It is the default mode, invoked as bare
  `ViewportBenchmarks -- --gate` (`swift-ci.yml:90-92`); `--pipeline` is not a
  valid argument and appears nowhere in the repo. Zero steps would match, not one.
- **`.realisticProvider` is deliberately never run with `--gate` in CI**
  (`AGENTS.md:340`); its step is PR-only and `continue-on-error`, and its samples
  reach the corpus through the `mode=realistic_relative_observation` line. Three of
  the four assertions would contradict this slice's own Standing items.
- **`--variable-height` is a prefix of `--variable-height-mutation`**
  (`swift-ci.yml:96` and `:100`), and no `BenchmarkMode`→flag mapping exists —
  `BenchmarkMode` exposes only snake_case `outputName`, while the flags live as
  hand-written `case` labels inside `BenchmarkOptions.parse`.

Generalizing the guard to every CI-gated mode is worthwhile, but it needs a
`flagName` property on `BenchmarkMode`, a named-and-justified exemption set, and a
test pinning the registry to `isGateable` — a design of its own (see
`## Recommended Next Step`). Bundling it here would repeat the very mistake this
slice was split to avoid.

This is the only Swift this slice adds, and it is a genuine failing-first anchor:
today two steps carry the `--point-geometry-query` token (`swift-ci.yml:148` and
`:159`) and one is `continue-on-error`, so the test is red before the collapse and
green after — with no other mode implicated in either state.

## Implementation Architecture

### Harvest + re-derive

```bash
# append fresh hosted samples (idempotent via --corpus; preview with --dry-run)
./.github/scripts/harvest-gate-corpus.sh --limit 40 \
  --corpus docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
  >> docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv

# re-derive ALL modes and re-commit what changed
./.github/scripts/derive-gate-budgets.sh \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
```

The Slice 39 post-merge push run (`29426572267`) is the most valuable sample in
this harvest: it is this mode's only evidence that is **not** from the Slice 39 PR
head. It is *not* the first unharvested run, and the design must not say so —
verified 2026-07-17 against `gh run list` and the committed corpus:

| run | event / branch | carries benchmark rows? |
|---|---|---|
| `29430079405` | PR `slice-39-post-slice-review` | no — docs-only shortcut |
| `29427177229` | PR `slice-39-post-merge-hosted-proof` | no — docs-only shortcut |
| **`29426572267`** | **push `main`** | **yes** |
| `29364862813`, `29313228902`, `29311831585`, `29311125509` | PR `slice-39-point-geometry-query` | yes |

So it is the **first benchmark-bearing candidate in newest-first harvest order**,
while four *older* unharvested PR-head runs also carry rows. Both facts matter:

- The two newer docs-only runs are why AC5 names a run id rather than "the newest
  run" — a docs-only run is harvested as a no-op, not an error.
- The four older runs are why Decision 3's sweep is not optional. The harvest takes
  `point_geometry_query` from **6 runs to ~11**, which is what moves the mode across
  the "~10 runs" line the Risks section carries its residual risk against. Confirm
  the post-harvest count rather than assuming it: the four PR-head runs are the
  reason it clears, and the Risks section's judgement changes if any of them turns
  out to be docs-only.

**`--limit` is a most-recent-N window, not a reach-back guarantee.** With no
`--runs`, the harvester asks `gh run list --workflow swift-ci.yml --limit N` for the
N most recent runs, so too small a limit silently drops the run AC5 requires.
Verified 2026-07-17: `29426572267` sits inside the `--limit 40` window (which then
spans `29430079405` … `29111247857`) — but every push to this branch shifts that
window. So run `--dry-run` **first** and assert `plan=harvest run=29426572267`
appears, widening `--limit` until it does. Do **not** fall back to
`--runs 29426572267`: that harvests one run and silently skips every other
unharvested one, contradicting Decision 3's sweep.

### Documentation (`AGENTS.md`)

- **Architecture paragraph** (`AGENTS.md:94-106`) — the `pointGeometryAt`
  sentence currently says `--point-geometry-query` is "derived-budget gateable"
  and CI runs it as **two steps** (bare-blocking + `continue-on-error`
  observational). Rewrite: it is a blocking host-job CI gate (the eleventh). Drop
  the two-step description.
- **CI section** (`AGENTS.md:197-213`) — change the point-geometry-query wiring to
  `→ --point-geometry-query --gate (blocking)`; update the blocking-gate count
  from ten to **eleven** and add point-geometry-query to the enumerated blocking
  gates; delete the "Slice 40 promotes the mode by deleting the bare step and the
  `continue-on-error` together" note (now done). **Add** the relocated
  `continue-on-error`-cannot-be-a-gate rule (Decision 2, rule 2) — the deleted
  block is `AGENTS.md`'s only record of the Slice 16 lesson, so it must be
  re-stated mode-independently, not merely "kept".
- **`## Gate budgets`** — add the relocated one-printing-step rule (Decision 2,
  rule 1).
- **Commands** (`AGENTS.md:153`) — drop the "gateable, not yet blocking in CI"
  qualifier from the `--point-geometry-query --gate` line.
- **Package layout** (`AGENTS.md:119-130`) — add `WorkflowShapeTests.swift` beside
  `GateLogicTests.swift` / `GateFloorTests.swift` as the third *described* guard.
  Note the bullet describes only the two `Gate*` files while the directory already
  holds four — Slice 39 added `PointGeometryChecksumTests.swift` and
  `PointGeometryQueryOptionsTests.swift` without documenting them. That omission is
  pre-existing, out of scope here, and a candidate for the post-slice review; do not
  silently fold it in.

### Verification record

Create
`docs/superpowers/verification/2026-07-16-point-geometry-query-ci-gate-promotion.md`
with exact commands, exit statuses, and representative output. At minimum:

- `swift test` passes, including the new `WorkflowShapeTests` (and its
  demonstrated red-before state).
- **All 46** committed budgets reproduce from `derive-gate-budgets.sh <corpus>`
  (paste the sweep); every budget the harvest moved is listed committed→derived,
  with direction, and none is hand-edited.
- All eleven latency gates pass locally, including `--point-geometry-query --gate`
  with all four `gate=pass`; the four `point_geometry_query` checksums are
  byte-identical to Slice 39's (proving the workload is unchanged).
- `point_geometry_query`'s post-harvest evidence base is reported explicitly: run
  count, per-scenario budget, `3×max` floor margin, and tightest hosted headroom —
  the numbers Decision 5's re-derive rule keys on (see Risks).
- Foundation-free scans empty for both `Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders`.
- **Hosted**, at **step** level (a green job can hide a dead `continue-on-error`
  step): final PR-head Swift CI run id; all three required jobs `success`; the
  point-geometry-query gate step `gate=pass` ×4 with hosted p95/p99 and
  per-scenario headroom; proof the step is not `continue-on-error`; and the
  **post-merge push** run id on the merge commit as the merged-code anchor (this
  PR changes YAML, so the merge is not docs-only).

  **This half ships as `## Hosted Proof — Pending`** in the implementation PR and is
  filled by a docs-only follow-up PR after merge (AC11). Neither run id is stable
  while the head is still moving, and the push run does not exist until the merge
  does — writing either one early is precisely the stale-evidence defect the
  project has already hit (Slice 25 P2). Name the watch scenario in the placeholder:
  `point_geometry_query|prefixsum_100k`, the tightest of this mode's four.

## Acceptance Criteria

1. `.github/workflows/swift-ci.yml` has exactly **one** `--point-geometry-query`
   step, invoking `--point-geometry-query --gate`, with **no**
   `continue-on-error: true` and no separate bare correctness step; it carries the
   `docs_only_pr` guard and sits after the point-query gate and before the
   memory-shape diagnostic; it is named `Run point geometry query benchmark gate`,
   carrying no "observational"/"until Slice 40" qualifier.
2. The rationale comment at `swift-ci.yml:130-143` is gone, and no text in the
   workflow describes a bare correctness step or an observational point-geometry
   budget.
3. `WorkflowShapeTests` asserts all six Decision 6 invariants for
   `--point-geometry-query` (including the step's name and its position between the
   point-query gate and the memory-shape diagnostic, which is what pins AC1's name
   and ordering clauses, and the exact-equality of its `run:` payload, which is what
   forecloses a double invocation or a `|| true` inside one step); it is red
   against the pre-collapse workflow — with its
   red assertion message recorded in the verification record — green after, and it
   runs in `swift test`. No other mode's CI shape can turn it red or green.
   (Invariant 6 necessarily looks up the point-query gate and memory-shape steps
   **by name** as ordering anchors; that is positional bookkeeping, not an
   assertion about those modes.)
4. Both Decision 2 rules survive the deletion as mode-independent prose: the
   one-printing-step rule is in `AGENTS.md` `## Gate budgets`, and the
   `continue-on-error`-cannot-be-a-gate (Slice 16 dead-step) rule is in
   `AGENTS.md` `## CI`. Neither relies on the deleted workflow comment or the
   deleted two-step CI description, and neither is phrased in terms of
   point-geometry-query.
5. The corpus file gains only appended rows (append-only; no deletion, no
   reorder), and the appended rows **include run `29426572267`** — the Slice 39
   post-merge push run, this mode's first non-PR-head sample. The verification
   record states `point_geometry_query`'s post-harvest run count, since Decision 5
   and the Risks section key on it.
6. **Every one of the 46** committed gated budgets reproduces byte-for-byte from
   `derive-gate-budgets.sh <corpus>`; no scenario is exempted; no budget is
   hand-edited.
7. The three required job context names are unchanged.
8. No `TextEngineCore` / `TextEngineReferenceProviders` / benchmark **workload**
   change; the four `point_geometry_query` checksums equal Slice 39's; `git diff`
   for the PR touches only `swift-ci.yml`, `WorkflowShapeTests.swift`, the corpus,
   budget tables, `AGENTS.md`, and `docs/**`.
9. `AGENTS.md` describes `--point-geometry-query` as the eleventh blocking
   host-job gate, counts eleven blocking gates, and no longer describes the
   two-step / not-yet-blocking wiring anywhere.
10. Local: all eleven latency gates pass, `--point-geometry-query --gate` is
    `gate=pass` ×4, `swift test` green, both Foundation scans empty.
11. **(Lifecycle criterion, not an implementation-PR one.)** Hosted PR-head CI runs
    the single blocking point-geometry-query gate step and succeeds, with recorded
    Linux per-scenario p95/p99 and headroom; post-merge push CI on `main` anchors
    the merged behavior — both verified at step level.

    AC1-AC10 are what the implementation PR must satisfy to merge. AC11 cannot be:
    the push run does not exist until the merge commit does, and the PR-head run id
    is not stable until the head stops moving. The implementation PR therefore ships
    its verification record with an explicit `## Hosted Proof — Pending` section, and
    a docs-only follow-up PR fills in both run ids afterward — the same shape Slice
    39 used (PR #84 → PR #85) and the convention Slice 36's design already spelled
    out ("*record the PR-head proof only in the post-merge follow-up where the final
    head SHA is stable*"). The slice is not done until AC11 is discharged; the
    implementation PR is.

## Risks And Gaps

### The gate is genuinely failable — and this slice does not widen its margin

`point_geometry_query` is the thinnest-evidence mode in the corpus (6 runs, all
from the Slice 39 PR) and sits inside the suite's tight cluster: its tightest
hosted headroom is **3.16× p95** (run `29280327104`: 231 ns observed vs a 730 ns
budget; next-tightest 3.24× on run `29285933609`) — **6th-tightest of the 92 gated
statistics**, with five pre-existing statistics tighter still (3.00×–3.04×). And
`point_geometry_query|prefixsum_100k` sits **+5.34%** above its `3×max` floor
(budget 730 vs floor 693).

That is a gate working as designed — a gate that cannot fail is not a gate — but
strict required checks mean a flaking gate blocks every PR in the repo. **Nothing
in this slice widens that margin.** The only things acting on it are:

- the fresh harvest, which broadens the mode's evidence base (the Slice 39
  post-merge run is its first non-PR-head sample) and may move the budget either
  way;
- Decision 5, which re-derives in-PR from hosted evidence if the first hosted run
  misses.

The ratchet repair does **not** mitigate this and never could: a trailing window
over 6 runs is a no-op. Nor is this mode's thin margin a ratchet symptom — its
budget is **median-governed** (8 × 91 = 728 > 3 × 231 = 693) and simply lands 5%
above its floor. Slice 41's recipe-side floor factor is what actually lifts it
(3.3 × 231 = 762 > 728 flips it to floor-governance, taking the budget to 770 and
the margin to +11%). If the post-harvest run count leaves this mode under ~10 runs,
that residual risk is carried knowingly.

### Hosted Linux variance vs the re-derived budgets

The re-derived budgets rest on hosted evidence, and the PR-head run is more hosted
evidence; if it misses, re-derive in-PR (Decision 5), do not hide it.

### Carried debt — the ratchet and the near-floor cluster (Slice 41)

Slice 38's P2 #2 remains open and is now scheduled as Slice 41. Six budgets sit
within ~5% of their `3×max` floor, worst case `line_geometry_query|uniform_1k` p99
at **0.0%** margin. Two clarifications the spec review established, so Slice 41
does not re-litigate them:

- Near-floor margin is **not** evidence the ratchet is biting. It is what
  `round_up_2sf(3×max)` produces whenever the `3×max` term governs — `AGENTS.md`
  already documents it as normal by construction — and that is five of the six
  members. (The sixth, `point_geometry_query|prefixsum_100k`, is median-governed
  and merely lands near its floor; near-floor implies neither floor-governance nor
  a ratchet.) The real ratchet symptom is **floor-governance**: one noisy sample,
  not the algorithm, setting the budget.
- Near-floor margin is also **not** a spontaneous CI flake risk: `GateFloorTests`
  reads the *committed* corpus, so a noisy hosted run cannot raise a floor until a
  harvest commit appends it — and `AGENTS.md` already prescribes the response
  (`budget_stale` → re-derive). It costs a re-derive on every harvest that touches
  those keys, which is real but bounded.

### The harvester does not filter runs by provenance (known gap, not this slice)

`harvest-gate-corpus.sh:141-142` selects runs by `gh run list --workflow
swift-ci.yml --limit N --json databaseId` alone — no `conclusion`, `event`,
`actor`, or `headRepository` check. Two consequences, both verified 2026-07-17:

- **Cancelled runs contribute partial rows.** Runs `29184350098` (9 rows) and
  `29185490595` (12 rows), both `conclusion=cancelled` on
  `slice-38-gate-budget-recalibration`, are already in the corpus against a typical
  22-46. This is **benign**: they are genuine measurements from this repo that were
  interrupted mid-table, not bad data. It is evidence of the missing filter, not of
  contamination.
- **The repo is public**, so a fork PR's run appears in this run list, and for
  `pull_request` events the workflow file comes from the PR merge commit — a fork
  could in principle print fabricated `p95_ns=` lines that a blind harvest would
  append, loosening budgets.

That second path is **not** mitigated here, knowingly. It requires a maintainer to
both approve the fork run and harvest it without looking, to achieve nothing but
weakened perf gates. More to the point, the durable fix is a **harvester filter**,
which Non-Goals forbids this slice from touching — and a one-time manual audit of
the harvest window would leave nothing behind for the next harvest, which is the
`GateFloorTests` lesson in reverse. Recorded here as a roadmap item; the natural
home is Slice 41, which already opens the derivation path
(`--json conclusion,event,headRepository` + a rejection rule, with the corpus
carrying provenance so the filter is auditable rather than implicit).

### The regression budgets are still anchored to a moving median

No *absolute* product budget exists: legitimate slow drift can still be re-derived
green. That is Slice 38 Option C, groundworked by §8 of the Slice 39 **verification
record** (every hosted `point_geometry_query` p99 clears a 1 µs product line by
4.0×–6.4×). Note the groundwork is scoped to that mode: other modes' hosted p99 do
not clear 1 µs at all, and some derived budgets already exceed it — reconciling the
absolute line with the derived regression budgets is exactly the work Option C owes.
It remains the strongest open roadmap item and is best added after Slice 41 stops
the upward drift.

### Standing items

WASM remains observational; the realistic-provider observation remains PR-only
`continue-on-error`; the `Main` ruleset keeps its documented bypass-actor shape.
None change here.

## Recommended Next Step

The Slice 40 implementation plan (TDD) is written and committed:
`docs/superpowers/plans/2026-07-16-point-geometry-query-ci-gate-promotion.md`. It
was drafted against the pre-review text of this spec, so it is a **draft until
reconciled** with the revisions above — the exact-equality invariant (Decision 6)
and the `29426572267` characterization are the two that reach its task steps.

The failing-first anchor is `WorkflowShapeTests` — red against today's two-step,
`continue-on-error` wiring, green only after the collapse. Sequence: write the
workflow-shape test (red) → relocate the one-printing-step invariant → collapse
the CI wiring (green) → harvest → re-derive-all + re-commit → `AGENTS.md` →
hosted PR run → post-merge proof (the follow-up PR that discharges AC11).

After Slice 40 the eleven-gate blocking suite is complete: **every mode CI runs
with `--gate` blocks merge on latency regression**, discharging the brief's
regression-benchmark requirement for the whole gated surface CI exercises.
`realistic_provider` remains the standing exception — a gated budget CI never runs
with `--gate` (PR-only relative observation, `AGENTS.md:340`), which is why the
gate sweep counts 45 `gate=pass`, i.e. 46 gated budgets minus that one.

### Slice 41 — ratchet repair, two levers

The user selected a **two-lever** mechanism, because the spec review established
that the bundle's single lever addressed two orthogonal problems and solved only
one of them. Slice 41 should be specced against this measured evidence. The
constants below are **evidence-backed starting points, not settled values** — the
measurements say `N = 20` is inert and `N ≤ 16` is not, which bounds the choice
without making it; Slice 41's design owns the final numbers:

| Lever | Fixes | Evidence |
|---|---|---|
| Per-key trailing window, **N ≤ 16** | The ratchet itself: gives `max()` a reverse gear, retiring aged-out spikes and closing the 50×-ceiling deadlock | At N = 20 both `line_geometry_query` spikes (rank 17 of 34) stay in-window and nothing moves; N ≤ 16 retires both (`uniform_1k` p99 990 → 500). The corpus's two most recent harvest bursts are **16 and 7 runs** (~11/slice), not the ~3–4 the bundled design assumed — so N = 20 is ~1–2 slices of history, not 5–6 |
| Recipe-side **floor factor** (derive at `3.3×max`, keep `GateFloorTests` at `3×max`) | The near-floor cluster: guarantees every `3×max`-governed budget clears its floor by ≥10% by construction | Reaches all six cluster members, including `column_query|uniform_100k`, whose max sits on the newest run in the corpus and is therefore unreachable by any window. One constant |

Facts Slice 41's design must carry, all measured against the committed corpus:

- The window is **not** monotone for budgets. `max(window) ≤ max(corpus)`, so the
  `3×max` **floor** can only fall or hold (verified: 0 of 46 floors rise, 0
  budgets fall below the windowed floor — so landing the window cannot redden
  `GateFloorTests`). But `median(window)` is unbounded by `median(corpus)`, so a
  windowed re-derivation **can loosen** a median-governed budget: at N = 20, 7 of
  46 budgets move, 5 tighten and **2 loosen**
  (`bulk_structural_mutation|1m_lines_batch_64` +2.2%,
  `variable_height_mutation|1k_lines_20_visible_overscan_0` +1.5%/+7.7%).
- The window must be over **distinct `run_id`s, never rows**.
  `realistic_provider|100k_lines_10mb_text` carries 8 rows per run, so a last-N-rows
  window would calibrate it on 2.5 runs. The `n=` field the script prints today is
  a row count; a windowed script should print `runs=` alongside it.
- Both enforcers must read the identical sample set, and the shared constant must
  be **pinned by a test, not a comment**: drift is invisible in one direction
  (if `N_swift < N_awk` then `floor_swift ≤ floor_awk ≤ budget`, so a typo'd
  `windowRuns = 2` disarms the floor test with everything green).
- Outlier rejection was the other candidate and does work (dropping run
  `29185634901` takes `line_geometry_query|uniform_1k` p99 from 990 → 500, margin
  3.0× → 6.0×), but it requires a curation policy and cuts against the "corpus is
  the evidence" ethos. The two-lever choice reaches the same scenarios without
  deleting evidence.

### Slice 42 (candidate) — generalize the workflow-shape guard to every CI-gated mode

Decision 6 guards only the mode this slice promotes. Extending it to all of them
is the check that would stop a *future* gate being added observationally and
forgotten — but it is a design, not a loop, and the groundwork is already
measured:

- `BenchmarkMode` needs a `flagName: String?` as an exhaustive switch beside
  `outputName`/`isGateable` (`nil` for `.pipeline`), so a new mode is a compile
  error rather than a second hand-maintained list — `everyGatedBudget()`'s comment
  ("*do not grow a second copy*") is the standing warning here. A test should pin
  `flagName` to `BenchmarkOptions.parse`, or the two drift.
- Two gateable modes need a **named, justified exemption**: `.pipeline` (flagless
  default, run as bare `--gate`) and `.realisticProvider` (deliberately never run
  with `--gate` in CI, `AGENTS.md:340`). The exemption set must be a decision in
  the design, not an omission in the test.
- Flag→step matching must be token-based: `--variable-height` is a prefix of
  `--variable-height-mutation`.
- 12 gateable modes vs 11 CI-gated steps is the arithmetic that makes all of the
  above necessary.
