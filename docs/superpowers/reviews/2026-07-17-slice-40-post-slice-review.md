# Slice 40 Post-Slice Review

`--point-geometry-query` promoted to the **eleventh** blocking CI latency gate.
Zero `TextEngineCore` change; the slice is CI/infra + budget-calibration work
plus one new test file. Merged as `bff3268` (PR #87); AC11 discharged by the
docs-only hosted-proof follow-up **PR #88** (merged as `ba395f9`).

This review was written after independently re-running the local verification on
the merged tree and re-reading both hosted runs at step level via `gh`. Where a
finding was carried into this review from the implementer's own end-of-branch
self-review, it was re-checked against the code before being recorded — one such
carried finding (`isComment` "dead code") did **not** survive that check and is
corrected below.

## Scope Reviewed

- `.github/workflows/swift-ci.yml` — the point-geometry two-step → one-step
  collapse (lines 130–132 of the merged file).
- `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` — the new hand-rolled
  workflow-shape regression guard (six invariants, +6 tests, 290 → 296).
- The budget re-derivation: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
  (append-only) and the budget literals under `Sources/ViewportBenchmarks/`.
- `AGENTS.md` — graduation to eleven blocking gates + Decision 2 rule relocation.
- The spec, plan, and verification record for the slice, plus the Slice 39
  post-slice review that scoped it.

Out of review scope, because the slice did not touch them (confirmed by
`git diff --name-only bff3268^1...bff3268^2`): `Sources/TextEngineCore`,
`Sources/TextEngineReferenceProviders`, and any benchmark **workload**.

## Product Brief Alignment

The brief's hard constraints are untouched and, on the perf invariant,
strengthened:

- **Foundation-free core** — no core file changed; `rg -n Foundation
  Sources/TextEngineCore` is empty (re-run for this review). `WorkflowShapeTests`
  imports Foundation, but it is a **test-target** import (like `GateFloorTests`),
  which the XCTest runtime links anyway and which cannot leak into the shipped
  core.
- **Zero-dependency** — the new test hand-rolls a narrow `swift-ci.yml` reader
  precisely *because* there is no YAML parser in reach and none may be added.
- **Memory / virtualization invariants** — unchanged; not in scope.
- **Perf invariant** — this is the slice's contribution: `--point-geometry-query
  --gate` now fails the job on a regression instead of swallowing it under
  `continue-on-error`. Eleven of the engine's query/mutation paths are now
  budget-blocking in CI.

## Delivered Design

### The two-step → one-step collapse

Slice 39 shipped point-geometry as a **pair** of steps — a bare correctness run
(blocking, output to a temp file so it did not double-weight future harvests) and
a `continue-on-error` gated run (budget observational). That split was correct
scaffolding: one step cannot be both budget-blind and failure-blocking, and the
budget could not go blocking until it was derived from real hosted evidence.
Slice 40 collapses them into a single blocking step that gates on **both**
correctness (`failures != 0`) and budget, now that the budget exists. The
surviving step is a plain sibling of the other ten gates — same
`--scratch-path`, same docs-only guard, same shape.

### `WorkflowShapeTests` — the regression guard

Nothing else in the repo reads `swift-ci.yml`. Without this test, the collapse
would be verified exactly once, by hand, into the verification record — the very
failure mode `GateFloorTests` was created to end (a green job hiding a dead
step). The test pins six invariants for `--point-geometry-query`: exactly one
step carries the flag; that step's `run:` payload **equals** the expected gated
command (exact equality, not a `contains("--gate")` probe — which is what
forecloses a double invocation inside one `|` block scalar and a trailing
`|| true`); it is not `continue-on-error`; it carries the literal docs-only
guard; it is named `Run point geometry query benchmark gate`; and it sits
between the point-query gate and the memory-shape diagnostic.

The design choices are sound and well-justified in-file: the reader is scoped to
the **host job region** (four step names repeat verbatim across the three jobs,
so a whole-file split would make name lookups ambiguous); it compares
whitespace-separated **tokens**, never substrings (`--variable-height` is a
prefix of `--variable-height-mutation`); and it is scoped to one mode rather than
`BenchmarkMode.allCases where isGateable` (that quantifier is false for 3 of the
12 gateable modes today, so a test written against it would be red for reasons
unrelated to this slice — and `swift test` is itself a blocking gate).

The red-before/green-after discipline is documented with the full 42-line failing
output in the verification record (§1): 4 of 6 methods failed pre-collapse
(5 assertion failures, because the name check emits one failure per matched
step), the two shape-independent methods passed in both states, and all six pass
after. Re-confirmed for this review: `swift test` → **296 tests, 0 failures**.

### The budget re-derivation — every mode, not just this one

The harvest appended fresh hosted rows (append-only; `git numstat` = `257 0`,
including the mandatory Slice 39 post-merge run `29426572267`) and re-derived
**all** 46 gated budgets. This is the correct discipline and the half Slice 39
got wrong: a harvest raises `max(hosted)` and can move the median for scenarios
the slice never touched, so all modes must be swept. Re-verified for this review
by running `derive-gate-budgets.sh <corpus>` with no mode argument and diffing
its output against every committed literal: **all 49 committed scenario rows
reproduce byte-for-byte, 0 mismatches** — the "derived, never hand-typed"
invariant holds across the whole suite, not just point-geometry.

Nine scenarios moved, every one **looser** (e.g. point-geometry `uniform_100k`
640/1300 → 910/1900; `prefixsum_100k` 730/1500 → 1100/2200), and four of the nine
belong to modes this slice never touched. A looser re-derived budget is a correct
result to commit — the recipe is median-governed and the median rose — not a
regression to chase; hand-editing one back down would be the hand-typed-budget
prohibition. Section on this in Risks below.

### `AGENTS.md` and the relocated rules

Both durable Decision 2 rules were moved into `AGENTS.md` **before** their only
copies (in the deleted workflow comment) were removed: the one-printing-step rule
into `## Gate budgets`, and the `continue-on-error`-cannot-be-a-gate rule into
`## CI`. Neither is phrased in terms of point-geometry. `AGENTS.md` now describes
the mode as the eleventh blocking gate and counts eleven. Verified present.

## Verification Evidence Reviewed

### Fresh local checks on the merged tree (`bff3268`)

| Check | Result |
|---|---|
| `swift test` | 296 tests, 0 failures (incl. all 6 `WorkflowShapeTests`, `GateFloorTests`) |
| `--point-geometry-query --gate` | 4/4 `gate=pass`, `failures=0`, headroom 15–36× local |
| all 46 budgets reproduce from corpus | 0 mismatches across 49 scenario rows |
| `rg -n Foundation Sources/TextEngineCore` | empty |
| point-geometry step is not `continue-on-error` | confirmed (line 130–132 is a lone blocking step; the only `continue-on-error` in the host job is the PR-only realistic-provider observation, line 144, by design) |

### Hosted runs (verified at step level, not job conclusion)

Read at step level per the standing rule — a `continue-on-error` step can
conclude a job green while its own step failed.

- **PR-head run `29579314733`** (head `4dd7bf9`): three required jobs `success`;
  the blocking point-geometry step ran and reported 4/4 `gate=pass` (hosted p95
  117–200 ns, headroom 6.5–8.1× p95 / 11.1–13.3× p99). Tightest observed:
  `prefixsum_1m` 6.5× p95.
- **Post-merge `push` run `29606487287`** (merge commit `bff3268`; second parent
  `4dd7bf9`): three required jobs `success`; the point-geometry step ran (not
  skipped, not `continue-on-error`), 4/4 `gate=pass` (hosted p95 63–75 ns);
  whole-run tally **45 `gate=pass`, 0 `gate=fail`** across all eleven blocking
  gates. The four checksums are **bit-identical** to the PR-head run and to the
  local runs — the workload is unchanged across host, PR-head, and merged commit.

AC11 is discharged in the verification record's `## Hosted Proof` section, added
by PR #88.

## Git History

Eleven commits, cleanly separated by concern and following the slice lifecycle:
design (`3c9ee8f`) → rescope to a bare promotion, splitting ratchet repair to
Slice 41 (`c5c8f77`) → plan (`4472934`) → spec-review + guard tightening
(`d4c48d8`) → plan/spec reconciliation (`59bc8bd`) → Decision 2 rule relocation
(`2fc6ac8`) → test + collapse (`8124983`) → harvest + re-derive (`51ed096`) →
`AGENTS.md` graduation (`adbdd5b`) → verification record (`c1c9f46`) → review-fix
to the record (`4dd7bf9`). Prefixes are correct (`docs:`/`ci:`/`feat:`). The
post-merge proof lives in PR #88 (`f464e2a`), matching the Slices 24–39 pattern.

One process nit: the plan's checkbox steps are all left `- [ ]` even though the
work landed and the commit messages match the plan's task blocks verbatim
(P3 below).

## Code Review Findings

### P0 / Release Blockers

**None.** The slice is merged, all eleven gates are green on the merged commit at
step level, and both hard constraints (Foundation-free, additive/no-core diff)
hold.

### P1 / Must Fix Before Merge

**None.** The one new test is red-before/green-after with recorded evidence, the
budgets reproduce byte-for-byte from the committed corpus, and the workflow
collapse is pinned by six invariants.

### P2 / Production Readiness

**P2 #1 — The ratchet repair was split to Slice 41 against the Slice 39 review's
explicit "do not defer" instruction, and the near-floor cluster it was meant to
fix is still live.** The Slice 39 review recommended Slice 40 = *promotion **and**
ratchet repair, bundled*, warning in as many words: "do not let the fix slip to a
Slice 41 that may never come." The user then re-decided and split the work — the
rescope is documented in the spec's provenance and restores the one-concern-per-
slice convention, so this is a **deliberate, authorized deviation, not a defect**.
But the debt it defers is real and now sits entirely on a Slice 41 that does not
yet exist: several budgets across unrelated modes sit at **exactly the 3.0× floor**
(re-measured this review: `line_query|uniform_100k` p95, `line_query|uniform_1k`
p95, `column_query|uniform_100k` p99, `line_geometry_query|uniform_1k` p99,
`line_geometry_query|uniform_1m` p99). Because `GateFloorTests` re-reads the
committed corpus on every `swift test` (a blocking gate), a single future hosted
sample raising one of those maxima by ~1 ns flips the assertion red on a clean
tree with no code change. This is not a spontaneous flake *today* (the corpus is
committed), but it is a latent one-way ratchet, and the reason the Slice 39 review
wanted it fixed in the slice that was already harvesting. **Slice 41 must not slip
it again** — see the recommendation, which also right-sizes it against the fact
that Slice 40's harvest already relieved point-geometry.

**P2 #2 — The promoted gate is genuinely failable, thinnest-evidence in the
suite, and this slice made it looser, not safer.** `point_geometry_query` carries
the fewest corpus runs (n=11), and the harvest **loosened** its budget rather than
tightening it: `prefixsum_100k` went 730 → 1100 ns p95 (headroom 3.16× → 4.8×),
because the *median* rose 91 → 130 ns while the worst hosted sample (231/252 ns)
did not move. So the widening is the median-governed recipe working as designed
and authorized by `AGENTS.md` — but it runs **opposite to the spec's own Risks
prediction** that this slice would not widen the margin, and it means the safety
margin against the *worst* observed sample is unchanged, not improved. This is a
monitoring item, not a defect: the watch scenario is `point_geometry_query|
prefixsum_100k` (tightest by both floor margin and corpus headroom), and it is the
first place to look if the gate ever reddens in CI. Strict required checks mean a
flaking gate blocks every PR, so the thin evidence base is worth noting on the
record.

### P3 / Minor But Valid

**P3 #1 — `AGENTS.md`'s `Tests/ViewportBenchmarksTests` description omits two of
the five test files.** `PointGeometryChecksumTests.swift` and
`PointGeometryQueryOptionsTests.swift` (both introduced by Slice 39) get **zero**
mentions in `AGENTS.md` (verified). The package-layout paragraph describes
`GateLogicTests`, `GateFloorTests`, and now `WorkflowShapeTests` as "the third
guard" — accurate as a count of *described* guards, but the directory holds five
files. This is a **pre-existing Slice 39 omission**; Slice 40's plan (gap #6)
explicitly chose not to silently fold a fix for it into an unrelated slice and
flagged it for this review instead — the right call. Record it so the next docs
pass closes it.

**P3 #2 — `WorkflowShapeTests`' comment-exclusion rationale points at an artifact
this slice deleted (correcting the self-review's "dead code" claim).** The
end-of-branch self-review flagged `isComment` as dead code with a false
"load-bearing" rationale. **That is not accurate** — `isComment` is used in three
places and at least two are load-bearing: it skips comment lines inside a `|`
block-scalar payload (else they tokenize into `runTokens`) and when finding the
host-job boundary. What *is* fair: the in-file comment (lines 89–97) justifies the
exclusion by naming "the rationale comment this slice deletes [that] sits inside
the point-query gate's block … says the words 'continue-on-error' twice." That
specific 14-line block is now gone. A different comment containing
"continue-on-error" still lives in the host job (the realistic-provider step,
line 148), so the guard remains justified — just not for the reason its comment
now states. Minor doc drift, cf. `[[measured-values-in-comments-rot]]`; the one
genuinely redundant line is the top-of-loop `if isComment(line) { continue }` in
`parseStep`, which the subsequent exact-key `value(of:)` reads already can't match
against a comment. Harmless; tidy opportunistically.

**P3 #3 — The shape guard is scoped to the host job while the harvester reads
across all jobs.** `WorkflowShapeTests` reads only the host-job region;
`harvest-gate-corpus.sh` reads every `p95_ns=` line in a run's log regardless of
job. Generalizing the guard to every gated mode needs a `flagName` property, a
named-and-justified exemption set (`.pipeline` has no flag; `.realisticProvider`
is deliberately never `--gate`d), and a test pinning the two together — a design
of its own, correctly not attempted here. Natural home: a standing-infra slice.

**P3 #4 — Plan checkboxes left unchecked.** Every step in the committed plan is
`- [ ]` though the work shipped; the commit messages are the actual evidence of
completion. Cosmetic paper-trail nit.

**P3 #5 — Verification record's two small seams.** Cross-target compile was not
run (defensible and worth stating: no `TextEngineCore`/`TextEngineReferenceProviders`
file changed, so the iOS/WASM surface is untouched — but the record does not state
that rationale for skipping it). And the harvest command's own execution is not
pasted; only its *result* (corpus provenance) is verified. Neither weakens the
merged-code proof.

## Risks And Gaps

- **The 3× floor / near-floor cluster (P2 #1)** — the live carried debt; Slice 41.
- **Point-geometry thin evidence + looser budget (P2 #2)** — monitor
  `prefixsum_100k`; re-derive from fresh evidence in-PR if it ever reddens (never
  restore `continue-on-error`, never hand-widen).
- **Harvester provenance gap (known, unmitigated, roadmap).**
  `harvest-gate-corpus.sh` selects rows by run id alone — no
  `conclusion`/`event`/`actor`/`headRepository` check — so a fork PR could in
  principle inject fabricated `p95_ns=` lines into a future harvest. The durable
  fix is a harvester change, which this slice's Non-Goals forbade; recorded here
  as a security-shaped roadmap item.
- **Budgets still anchored to a moving median** — no absolute/product budget
  exists (Slice 38 Option C, still unclaimed). Legitimate slow drift can be
  re-derived green forever; the product line is the eventual backstop.
- **Standing items unchanged** — WASM observational; realistic-provider
  observation PR-only `continue-on-error`; the `Main` ruleset keeps its
  bypass-actor shape.

## Lessons For The Next Slice

- **A harvest re-derives *every* mode — Slice 40 got this right.** Sweeping all 46
  budgets (not just point-geometry) is what kept the "derived, never hand-typed"
  invariant intact this time, unlike Slice 39's partial sweep. Keep sweeping.
- **"The budget got looser" is a valid derived outcome.** When the median governs
  and rises, the recipe produces a looser budget by construction; committing it is
  correct, and a post-harvest `GateFloorTests` failure is `budget_stale`, not an
  engine regression.
- **Re-verify carried findings against code.** The `isComment` "dead code" item
  arrived from the branch self-review and did not survive a firsthand check.
  Self-reviews are a starting point, not evidence.

## Slice 41 Candidate Options

### Option A: the ratchet repair (the carried debt) — recommended, but re-scoped

Stop the `3× max` floor over an append-only corpus from being a one-way ratchet.
The mechanism the Slice 39/40 paper trail already sketched is a two-lever fix:
a **trailing window** (derive from the most recent N runs, not all history) plus
**outlier rejection**, or a documented **curation/retirement** policy for old
rows. The concrete target is the at-floor cluster measured in P2 #1
(`line_query`, `line_geometry_query`, `column_query` uniform scenarios).

### Option B: the absolute (product) budget (Slice 38 Option C, still unclaimed)

A fixed product ceiling (e.g. the 1 µs line every scenario's hosted p99 already
clears) that does not move with the median. Best added **after** Option A stops
the upward drift, not before.

### Option C: harvester provenance hardening

Filter harvested runs by `conclusion=success` / non-fork / expected event, closing
the injection gap in Risks. Security-shaped; small.

### Option D: generalize `WorkflowShapeTests` to every gated mode

Add the `flagName` mapping + exemption set so all eleven gates are shape-pinned,
not just point-geometry. Standing infra.

## Recommended Slice 41 Selection

**Option A — the ratchet repair — but scoped against fresh evidence, not the
original brief.** It is the one item the Slice 39 review explicitly asked not to
let slip, and this slice deferred it, so it has first claim. The one caveat that
must shape it: **Slice 40's harvest already relieved the pressure it was
originally scoped against** — point-geometry moved off the floor (margin +5.34% →
+58.7%). So Slice 41 should begin by re-measuring which budgets are *still* at the
3.0× floor after this slice's harvest, confirm the cluster is real, and pick the
**lightest** lever that stops the one-way ratchet — quite possibly a documented
trailing-window in `derive-gate-budgets.sh` alone, rather than the full two-lever
mechanism. This honors the Slice 39 review's intent (fix it, do not let it vanish)
while right-sizing it to the now-relieved state, keeping the one-concern-per-slice
discipline the rescope restored. Fold in the trivial P3 #1 (`AGENTS.md` test-file
description) and P3 #2 (comment tidy) opportunistically, since Slice 41 will be
editing `AGENTS.md`'s `## Gate budgets` anyway.

## Slice 40 Review Conclusion

Slice 40 does exactly what its rescoped spec set out to do, and does it cleanly:
one blocking gate replaces two, pinned by a genuinely adversarial workflow-shape
test; every budget in the suite re-derives byte-for-byte from a correctly-swept
corpus; no core, provider, or workload byte moved; and the merged commit is green
across all eleven blocking gates at step level. No P0, no P1. The single
substantive carry-forward is the ratchet repair the Slice 39 review wanted here —
deferred by an explicit, documented user decision, now Slice 41's to finish and
not defer again. **READY — merged and verified; Slice 41 = ratchet repair,
scoped against fresh evidence.**
