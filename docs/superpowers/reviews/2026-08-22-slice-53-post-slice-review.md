# Slice 53 — post-slice review (wrap node 3: `visualRowAt`, the y→row query)

**Scope reviewed.** Branch `slice-53-wrap-row-query`, [PR #126](https://github.com/maldrakar/swift-text-engine/pull/126)
(merge `c2e6b37`), plus the docs-only hosted-proof [PR #127](https://github.com/maldrakar/swift-text-engine/pull/127)
(merge `53dcbfc`). 23 files, +4354/−38, of which 3 640 lines are the spec, plan and
verification record. Implemented via subagent-driven development from
`docs/superpowers/plans/2026-08-09-wrap-row-query.md` (8 tasks + a fix wave), with one
post-review coverage fold-in the user found after the record was first written.

**Verdict: READY. No P0, no P1.** Two P2s and two P3s, all forward-looking — none
blocks the merge that already happened, and both P2s are fold-in candidates for the
next slice rather than slices of their own.

---

## What shipped

`ViewportVirtualizer.visualRowAt(y:layout:)` — the wrap-aware `lineAt` analog over the
visual-row axis. It runs `compute(_:layout:)`'s layout ladder through the *same*
extracted helper (so the two entry points accept and reject identical layouts by
construction, not by inspection), delegates the row-axis search to `lineAt` over
`UniformLineMetrics(totalRows, rowHeight)`, and names the located row in **both**
coordinate systems: `globalRow` (the index space `compute(_:layout:)` ranges over) plus
`logicalLine`/`rowInLine` (what `VisualRow` and `DocumentVisualRowCursor` speak).

Three structural facts worth restating because they are the design, not incidentals:

- **It adds no new search.** One row-axis search, one `logicalLine(containingVisualRow:)`
  search, one O(1) `firstVisualRow` probe — `<= ceilLog2(lineCount) + 4` on the layout
  axis, O(1) core memory.
- **Clamped queries take no special case.** Unlike the no-wrap axis, where
  `LineAtQueryCountTests.testClampBranchesDoNotSearch` pins a two-probe constant, both
  edges here flow through the same provider calls as an in-range hit — so a clamped
  query *does* search, and a test says so rather than leaving a reader to carry the
  no-wrap constant across.
- **The generic enum was renamed** `VisualRowQuery<Metrics>` → `VisualRowPackingQuery<Metrics>`
  to free the unadorned name for this slice's position query, keeping the axis-query
  family consistent (`LineQuery`, `ColumnQuery`, `PointQuery`, `VisualRowQuery`).

Plus the observational, non-gateable `--wrap-row-query` benchmark mode (4 scenarios), an
∞-width equivalence oracle against `lineAt`, a round-trip oracle against node 1's packer
driven by node 2's cursor, and a layout-axis probe-count pin.

---

## Acceptance-criteria status

All thirteen discharged. The ones where "discharged" required more than a green build:

| AC | Status | Evidence |
|---|---|---|
| 3 (rename, incl. both non-compiler-checked prose sites) | ✅ | `WrapTestSupport.swift:4` and `AGENTS.md:111` both carry the new name; `grep -rn "VisualRowQuery<" Sources/ Tests/` is empty. A green build was never evidence for either — which is why the spec enumerated them by path |
| 4 (shared ladder; three node-2 suites pass **untouched**) | ✅ | `git diff --name-only c3e5fe5^ c2e6b37 \| grep -i WrapCompute` → empty. The only test edit outside the new suites is the mechanical rename in `WrapValidationTests.swift` |
| 8 (probe bound is logarithmic) | ✅ **strengthened post-review** | Bound unchanged at `ceilLog2(lineCount) + 4`; the fold-in below adds the `totalRows >> lineCount` regime the original fixture could not see |
| 9/10 (inert to CI and to the harvester) | ✅ | 0 occurrences in `swift-ci.yml`; on the hosted logs, 0 `wrap_row_query` lines in all three jobs, 0 `query_p95_ns=`, exactly 46 harvestable ` p95_ns=` rows |
| 12 (six falsifiability drills) | ✅ | §9 of the verification record; two further drills sit beside them, labelled as not being among the six |
| 13 (hosted proof, both halves, step level) | ✅ | §10.1 run `32594785647` (head `2d7e817`), §10.2 run `32595528239` (merge `c2e6b37`) |

---

## Strengths

**The round-trip oracle is the load-bearing test, and the suite knows it.** Every other
suite compares `visualRowAt` against arithmetic restated in the test file, so a
coherent-but-wrong row model could satisfy all of them at once.
`WrapRowQueryRoundTripTests` instead compares it against node 1's independently-written
greedy packer, driven across lines by node 2's cursor over a real `compute` range, and
probes both the row boundary and the row interior — closing the class of compensating
errors where a shifted boundary and a shifted index cancel on boundary samples alone.
That the file's own doc comment states this hierarchy is worth as much as the test.

**The ladder extraction is proved by absence, not by assertion.** AC4's evidence is that
all three node-2 wrap-compute suites pass with **zero** edits. Drill 6 then closes the
half that parity structurally cannot see: parity proves the two entry points agree, and
per-error-case suites prove each check is still *present*, because a check deleted from
the shared helper keeps parity green.

**Both coordinate systems are returned, not just the convenient one.** `globalRow` alone
would force every caller to re-derive `(logicalLine, rowInLine)` — which is exactly the
`logicalLine(containingVisualRow:)` search the core just did. Returning all three is
what makes node 4 a composition rather than a re-derivation.

**The observational mode was built inert on purpose, three ways over.** Absent from CI,
latency tokens prefixed (`query_p95_ns=`) so the harvester's exact-key extraction yields
nothing even if a line reached a hosted log, and a checksum folding all three returned
fields under distinct multipliers so a release build cannot delete the work and still
print a plausible number. `PointGeometryChecksumTests` exists because that reversion once
passed silently; here the lesson was applied up front.

---

## Issues

### P0 / P1

None.

### P2 #1 — `--wrap-row-query`'s timing shape cannot support budget derivation at node 6

The mode times **one** query per `clock.measure` over 2 000 samples. Every gated mode
amortises instead: `operationsPerSample = 256`, dividing the elapsed time by it
(`LineQueryBenchmark.swift:73-89`). At this operation's size the difference is not a
detail — it is the whole measurement. Observed locally, release build:

```
mode=wrap_row_query scenario=uniform_1k   query_p95_ns=167 query_p99_ns=167
mode=wrap_row_query scenario=uniform_100k query_p95_ns=250 query_p99_ns=292
mode=wrap_row_query scenario=narrow_100k  query_p95_ns=250 query_p99_ns=292
mode=wrap_row_query scenario=clamped_100k query_p95_ns=83  query_p99_ns=84

mode=line_query provider=uniform       scenario=uniform_100k       ... p95_ns=17 p99_ns=20
mode=line_query provider=balanced_tree scenario=balanced_tree_100k ... p95_ns=94 p99_ns=110
```

Every wrap number is a multiple of ≈41.7 ns — the host clock tick (83 = 2 ticks, 167 = 4,
250 = 6, 292 = 7) — and `uniform_1k` collapses to `p95 == p99`, the signature of a
distribution quantised onto a single tick. The mode's siblings live at 17–94 ns, i.e.
**below** one tick. So these numbers do not resolve the operation; they resolve the clock.

Why it is P2 rather than cosmetic: node 6 promotes wrap modes to blocking gates through
`harvest → derive`, and the recipe never re-measures — it derives budgets from whatever
the hosted log printed. Deriving from a tick-quantised sample produces a budget anchored
to clock overhead, which is precisely the "gate that cannot fail" failure this repo
shipped five times (slices 27/31/33/35/37) and spent slice 38 undoing. The fix belongs
*before* the first wrap harvest, not after.

Scope: `--wrap-compute` (slice 50) has the same single-op shape, so this is one repair
covering both, not two. Neither mode reaches CI today, so nothing is currently wrong —
this is a trap laid for node 6, disarmed cheaply now.

→ ledger **D-23**.

### P2 #2 — the row axis's "provider-overridable" hook is pinned by nothing

`logicalLine(containingVisualRow:)` is documented — in `AGENTS.md`, in the protocol, and
in `visualRowAt`'s own doc comment — as "provider-overridable, binary-search default".
Drilled during this review:

> **Drill C.** Replaced `layout.logicalLine(containingVisualRow: globalRow)` in
> `WrapPositionQuery.swift` with a direct call to `binarySearchLogicalLine(...)`,
> bypassing the protocol dispatch entirely.
> **Observed: `Executed 397 tests, with 0 failures`.** The whole suite is blind.

Nothing anywhere overrides the hook — `grep -rn "func logicalLine(containingVisualRow"`
returns exactly two hits, the protocol requirement and the default extension. Contrast
the line axis, where `BalancedTreeLineMetrics` overrides the native hooks and three test
files (`ComputeNativePrefixSearchTests`, `LineAtQueryCountTests`,
`LineGeometryAtQueryCountTests`) exercise the override path.

Today nothing breaks, because no provider overrides it. The failure lands the moment one
does: its O(log N) descent becomes dead code, the cost class silently degrades to the
default, and no test notices — the repo's recurring
"a pin is only as strong as what it models" lesson, on a new axis. The fix is small
enough to fold in: one test-only conformer that overrides the hook and asserts it was
called.

→ ledger **D-24**. Natural home: node 4, which composes over this exact query.

### P3 #1 — the second probe-count test's bound is decorative

`WrapRowQueryCountTests.testProbeCountDoesNotGrowLinearlyWithTheDocument` asserts
`totalCalls < lineCount / 10` = **102**, while its sibling asserts `<= 14` on the same
fixture. The parked framing of this finding ("no implementation can pass one and fail
the other") is *slightly* overstated — the two tests probe different `y`, so they are not
formally nested — but the practical claim holds and the record confirms it: under
drill 5 Form A the 102 bound fired only *alongside* its sibling (`1004` vs `102`,
`704` vs `14`). It has no recorded independent failure mode, and its bound sits 7×
looser than the structural one. Redundant rather than un-failable. Either tighten it to
say something the sibling does not, or fold it in.

→ ledger **D-25**.

### P3 #2 — D-21 is no longer a prediction

Drill B (below) flipped `wrapRowQuery` into `isGateable`'s true arm. `GateFloorTests`
caught it immediately via `testEveryGateableModeIsRegistered` — but **nothing** checked
the mode's `AbsoluteCeiling` class. `GateLogicTests` stayed 27/27 green. That is D-21
("a new gateable mode landing in the `.scrollFrame` arm trips no pin") and D-20 (the
non-gateable modes' class is unpinned) observed live rather than reasoned about, and it
confirms the trigger both rows name: the inertness ends at node 6. No new row — the
evidence is appended to D-21 instead.

---

### Process observations

**The user found the coverage gap the whole in-slice drill sequence missed, and it was
the third recurrence of one lesson.** `WrapRowQueryCountTests` built every fixture at
`wrapWidth: .infinity` — one row per line, `totalRows == lineCount` — so a cost term
proportional to rows *within* a line was invisible **by construction**. Six drills, an
SDD fix wave and a whole-branch review all ran against that fixture without noticing that
the query's headline regime (`totalRows >> lineCount`) was pinned only by an
observational benchmark's latency.

The fold-in (`countingMultiRow()`, 1024 lines × 8 rows) closes it at the **unchanged**
bound — measured 13 / 13 / 14 against `ceilLog2(1024) + 4 = 14`, so the new regime costs
no slack, and the bound stays keyed to `lineCount` rather than `totalRows` (which would
have allowed 17 and handed a regression three probes of room). Drill 7 shows the gap
instead of asserting it: a per-`rowInLine` mutation leaves all three infinity-fixture
tests green and reddens the new test twice (16 > 14 in range, 21 > 14 clamped).

This is the same lesson as the fix wave's own catch (the counter tracked only
`firstVisualRowCalls`, so a scan through `visualRowCount` passed) — **twice in one
slice**, on the same test file. The generalisable form, worth carrying into node 4:
*a probe-count harness must be built on a fixture where the axes it separates actually
differ.* A fixture where two quantities coincide cannot distinguish cost terms in them.

**Recording hosted proof on a non-docs-only PR is inherently iterative, and that is now
written down.** Each docs commit moves the PR head, and because the full `BASE...HEAD`
diff was not docs-only, each push triggered another full run. §10.1 cuts the regress
explicitly: it pins the newest run that tested the *code*, keeps the superseded green
runs in a table rather than dropping them, and hands the definitive claim to §10.2's
post-merge run. Worth reusing verbatim.

**Three branches of the docs-only detector were observed live in one slice** —
`not_docs_only` (PR #126, 23 files / 17 non-doc), `not_pull_request` (the push to `main`,
where no base exists to diff so the shortcut is unavailable by construction), and
`docs_only` (PR #127, 1 file / 0 non-doc, all three required contexts emitted with the
heavy steps skipped). The first two are recorded in §10; the third is not, deliberately —
recording it inside PR #127 would have moved its own head again.

---

# Recommendation (skill Mode 2)

Map pass: node 3 is `done`. The map's nodes 4–9 and fork V stand unrevised — nothing
this slice taught invalidates them. Next step is **topological**, not a fork; the first
genuine fork remains node 8 (host order) / fork V.

### Scoreboard delta

| # | Criterion | Was | Now | Evidence |
|---|---|---|---|---|
| 3 | Wrap-aware equivalents of existing queries; ∞ width equals no-wrap | partial | **partial** (advanced) | y→row analog shipped: [PR #126](https://github.com/maldrakar/swift-text-engine/pull/126) `c2e6b37`, `WrapRowQueryEquivalenceTests` (∞ and any width no line exceeds, bit-identical to `lineAt` over a uniform axis), post-merge run `32595528239`. **Remaining: the point→(row, cell) analog (node 4)** — the last item on this criterion's own list |

No other criterion moved, and none should have: this slice touched no memory diagnostic
(2), no gate (4), no edit path (5), no host (6), and criterion 1's remaining half is the
veneer fork, not a query analog.

Still open or partial: **1** (partial — needs fork V), **2** (open, *no evidence at
all*), **3** (partial — one analog left), **4** (open), **5** (open), **6** (open).

### Debt ledger delta

**Added this review:**

| id | severity | statement | status |
|---|---|---|---|
| D-23 | P2 | Both wrap benchmark modes time a single operation per `clock.measure` where every gated mode amortises over `operationsPerSample = 256`; measured output is quantised to the host clock tick (≈41.7 ns; `p95 == p99` on `uniform_1k`) while gated siblings measure 17–94 ns. Node 6 derives budgets from hosted output without re-measuring, so promoting either mode on this shape anchors a budget to clock overhead — the slice-27/31/33/35/37 failure. Repair covers `--wrap-compute` and `--wrap-row-query` together | open |
| D-24 | P2 | `logicalLine(containingVisualRow:)`'s documented "provider-overridable" contract is pinned by nothing: no conformer anywhere overrides it, and replacing the dispatch with a direct `binarySearchLogicalLine` call leaves all 397 tests green (drill C). A future overriding provider's descent would become dead code silently. Contrast the line axis, pinned by `BalancedTreeLineMetrics` + three count-test conformers | open |
| D-25 | P3 | `testProbeCountDoesNotGrowLinearlyWithTheDocument`'s bound (102) is 7× looser than its sibling's structural bound (14) and has no recorded independent failure mode — under drill 5 Form A it fires only alongside the sibling. Redundant rather than un-failable | open |

**Amended:** D-21 gains live evidence (drill B: flipping `wrapRowQuery` gateable reddens
the registry pin but no absolute-ceiling class pin; `GateLogicTests` 27/27 green).
D-20's trigger is likewise confirmed reachable.

**Added during the slice** (already in the ledger): **D-22** (uniform-axis inverse hooks
unimplemented, both paths costed). D-20 widened four → five non-gateable modes.

**Counts:** open P2 = 3 (D-17, D-23, D-24); open P3 = 11; deferred(user) = 3 (D-5 P3,
D-7 P2, D-9 P2); accepted-risk = 2; discharged = 6.

**Escalation check.** Two open P2s have origins ≥ 3 completed slices back — **D-7**
(harvester provenance, born slice 46) and **D-9** (p95 thin axis, born slice 46). Both
already carry `deferred(user, …)`, so neither is in the silent state the rule forbids;
both are named under Candidate options below for re-affirmation rather than being
re-litigated. **D-17** (`${PIPESTATUS[0]}` un-failable under zsh, born slice 52) is one
completed slice old and does not escalate — it was mitigated again this slice by a
plan-level instruction, and `AGENTS.md:642` still recommends the broken idiom by name.

### Falsifiability audit

Guarantees this slice added, and the evidence each can fail:

| guarantee | evidence it can fail |
|---|---|
| Half-open row boundary; `rowInLine` subtraction | Drills 1, 2 — recorded reds |
| ∞-width equivalence oracle | Drill 3 (clamp forced to `.inRange`) — recorded red |
| Ladder parity between `compute` and `visualRowAt` | Drill 4 (parity sees divergence) + drill 6 (parity is **blind** to absence; presence pinned separately) — three recorded outcomes |
| Layout-axis probe-count bound | Drill 5, both forms — 704/1004/1026 vs 14/102; form B added after the fix wave found form A's counter blind |
| Probe bound in the `totalRows >> lineCount` regime | **Drill 7** (this slice's post-review fold-in): 16 > 14 and 21 > 14, with all three infinity-fixture tests staying green |
| Anti-dead-code checksum (`WrapRowQueryChecksumTests`) | **Was un-drilled.** Drilled in this review — **drill A**: multiplier 131 → 31 reddens `testFieldsAreNotInterchangeable` (191 == 191) and `testKnownValue` (160 ≠ 360), while `testFoldsAllThreeFields` stays green, confirming which of the three carries the distinctness property |
| Non-gateability + option rejection (`WrapRowQueryOptionsTests`, registry pin) | **Was un-drilled.** Drilled in this review — **drill B**: flipping `isGateable` reddens `testGateIsRejected`, `testIsNotGateable`, and `GateFloorTests.testEveryGateableModeIsRegistered` with a message naming the fix |
| Row-axis provider dispatch ("provider-overridable") | **No guarantee exists.** Drill C: bypassing the hook leaves 397/397 green → mandatory candidate option, discharged by D-24 inside Option A |

Two guarantees entered this review un-drilled and now carry recorded reds; one turned out
not to be a guarantee at all. All drills reverted, `git status` clean, suite 397/0 after
each revert.

### Candidate options

**Option A — node 4: `pointAt`'s wrap analog, point→(row, cell)** *(lean)*
Advances criterion 3 and finishes its enumerated list, so the criterion can finally leave
`partial` on the strength of evidence rather than waiting behind another node. Composes
`visualRowAt` with the existing within-row column query exactly as `pointAt` composes
`lineAt` with `columnAt` — a composition, not a new search, because slice 53 returns both
coordinate systems. Folds in **D-24** (the row-axis dispatch pin belongs in the slice that
leans hardest on that dispatch) and is the natural home for **D-25** (same test file) and
plausibly **D-13**. Map position: node 4, topological.

**Option B — node 5: extend `--memory-shape` to the wrap path**
Advances criterion **2**, the only wrap criterion with *no evidence at all* — and a
criterion that restates one of the initial brief's hard constraints (core memory must not
grow linearly with the document). Against it: the diagnostic should cover the whole wrap
query surface, and that surface is one node short; doing it now means extending it twice.
Map position: node 5, topological, independent of node 4.

**Option C — D-23 repair: put both wrap benchmark modes on the amortised timing shape**
Small, infrastructural, and strictly *before* node 6's first harvest. Discharges D-23,
touches no core code, moves no criterion by itself. Against it as a standalone slice: it
is a fold-in, not a slice — better carried by whichever slice next touches the benchmark
target, or by node 6's own first task.

**Lean: Option A**, and the reasoning is not "it neighbours the last diff": criterion 3
is the only criterion where one named deliverable stands between `partial` and a
completed list, D-24 is cheapest to discharge in exactly that slice, and B's
`--memory-shape` extension is strictly better done once the wrap query surface is
complete. C rides along with whoever touches the benchmark target next.

**Routing.** This is a topological step, so it is a **selection**, not a product call —
but two things do want a user decision, and neither is the slice choice:

1. **D-7 and D-9** are both `deferred(user, …)` P2s older than three slices. Re-affirm
   the defer, or schedule either.
2. **D-23** is a fold-in with a deadline (node 6's first harvest). Fold into Option A, or
   leave it for node 6's first task.
