# Slice 56 — artifact-shape enforcement (design)

- **Date:** 2026-09-04
- **Arc:** soft-wrap ([arc file](../arcs/wrap.md)) — an **infrastructure** slice; it
  consumes no arc node and advances no brief criterion directly.
- **Selected by:** the [slice 55b post-slice review](../reviews/2026-09-03-slice-55b-post-slice-review.md)
  (Option A, topological — not a fork), scope narrowed at the slice-56 brainstorm
  of 2026-09-04.
- **Ledger rows in scope:** D-27, D-34, D-35, D-17, D-37, D-39.
- **Ledger row rehomed:** D-9.

## 1. Scope, and the one row that leaves

The slice-55b review scheduled four P2s here. Three of them — **D-27**, **D-34**,
**D-17** — plus the fold-ins **D-35**, **D-37** and **D-39** are one family: *an
artifact whose shape nothing verifies, or a rule that exists only as prose*. The
fourth, **D-9** (the p95 thin axis), is calibration arithmetic: it edits the budget
recipe, forces a re-derivation of all 46 committed budgets, and lands a budget diff
that no reader can separate from a shape-pin diff in the same PR.

**D-9 is therefore rehomed to node 6** (the wrap gate promotion) by user call of
2026-09-04, with a named home rather than silence: node 6 *is* the next
`harvest → derive` event, it is where the p95 recipe is actually applied, and its
read-set already carries D-20/D-21, D-28, D-30 and D-31 for the same reason —
`harvest → derive` never re-measures, so the recipe must be right **before** that
node's first harvest. The escalation rule is satisfied by the schedule, not by a
sixth surfacing.

**Non-goals.** No change to `Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`,
any benchmark's measured path, any committed budget, the corpus, or the set of
gated modes. No new benchmark mode and no gate promotion.

## 2. The defect class, measured

Every row in scope is the same shape, and each carries evidence rather than a claim:

| Row | The artifact | What is unverified | Measured |
|---|---|---|---|
| D-27 | `.github/workflows/swift-ci.yml` | 10 of 12 blocking gate steps have no shape pin | `pinnedGateSteps` has 2 rows; the file has **12** `--gate` invocations. Drill H (slice 54): `\|\| true` on the `--line-query` step leaves `swift test` green |
| D-34 | plan documents | D-2's four conventions are prose; nothing executes them | Slice 55a's plan shipped **4** defective checks *after* an explicit self-audit in its own preamble |
| D-35 | spec drill lists | a closed list read as authority against an AC that says "every standing guarantee" | Slice 55b: **4** guarantees shipped undrilled, caught by two later passes |
| D-17 | `AGENTS.md` rule 1 | the recommended idiom inverts to a pass under this repo's shell | `${PIPESTATUS[0]}` appears at **22 sites in 5 plans** (3 in the newest); under zsh it expands empty and `[ "" -eq 0 ]` is true |
| D-37 | verification records | "a record cannot carry facts about its own branch" is unwritten | 3 instances of the fix (slices 54, 55a, 55b), 0 written rules; 55b's record stated its own commit count wrong twice |
| D-39 | `docs/superpowers/debt-ledger.md` | table shape unchecked; `\|` in a code span splits the cell | D-9's **status** column — the one the escalation rule reads — rendered as the tail of a code span instead of `scheduled(slice-56)` |

## 3. Decisions

**D56-1 — `BenchmarkMode.flagName: String?`, an exhaustive switch.** Never a
deny-list: a `default` makes the next mode pinned-by-accident or exempt-by-accident,
the discipline already written for `isGateable` and `absoluteCeiling`. `.pipeline`
returns `nil` — it runs as a bare `--gate` and has no flag at all. That `nil` is the
named-and-justified exemption the old `pinnedGateSteps` comment asked for; it is a
case in the switch, not a hole.

**D56-2 — the pinned table is checked against `isGateable` as a bijection.** A
gateable mode with no pinned step fails; a pinned step whose mode is not gateable
fails. Same construction as `GateFloorTests`' pin of `everyGatedBudget()` to
`isGateable`.

**D56-3 — one total order replaces twelve pairs of anchors.** The sequence of gate
steps found in the host job must equal a declared sequence of modes. Twelve
`after`/`before` pairs express the same constraint more weakly and 24 literals wide.

**D56-4 — no unpinned `--gate` may exist in the host job.** The count of `--gate`
occurrences inside the host job must equal the number of pinned steps. Without this,
a thirteenth step carrying `|| true` is invisible to a per-step pin — the shape of
the hole D-27 names, one level up.

**D56-5 — step names stay literals in the table.** "Run synthetic benchmark gate"
does not derive from any flag, and `--variable-height-mutation` → "Run
variable-height mutation benchmark gate" keeps one hyphen and drops another. A
derived name would pin the derivation, not the file.

**D56-6 — the plan linter is a bash script with `--self-test`, and Swift runs it.**
`.github/scripts/lint-plan-assertions.sh`, enrolled in
`ScriptSelfTestTests.selfTestScripts` (whose `testTableCoversEveryScriptWithASelfTest`
reddens if a script with a self-test is not enrolled). A script because the linter is
an **authoring** tool: it is run while a plan is still being written and not yet
committed, where `swift test` is the wrong hammer. A Swift test alongside it because
authoring discipline that only runs when someone remembers it is the mechanism D-34
already measured as failing.

**D56-7 — four rules ship; two of D-2's are not mechanized, and say so.**

| Rule | Fails when | Convention it enforces |
|---|---|---|
| R1 | the plan contains `PIPESTATUS` anywhere | D-17 |
| R2 | `echo "…=$?"` whose previous non-empty line is a command from a named insensitive list (`git diff`, `git status`, `gh `, `jq`, `sed -i`) or a pipeline | D-2 rule 2 |
| R3 | a `$VAR` used in a `bash` fence is not assigned in that same fence, is not in the environment allow-list, and the fence does not open `: "${VAR:?}"` | D-2 rule 4 |
| R4 | a task section lacks a **Guarantees added** block, or lists guarantees without a drill step for each | D-35 |

D-2 rule 1 (a check on the left of a pipe) and rule 3 (a plan asserting its own HEAD)
are **not** mechanized: both need semantics, not shape, and a heuristic for them would
manufacture false positives in an artifact whose whole purpose is that its checks are
trustworthy. They become a new ledger row rather than an unmentioned gap.

**D56-8 — the grandfather list is a ratchet, pinned by property, not by copy.** All
**56** plans that exist on 2026-09-04 are exempt under one shared justification
("written before the linter existed"). The list lives in the script alone, so a
standalone authoring run honours it. The Swift half pins the ratchet: the script exits
0 over the whole directory; the list holds exactly 56 entries; every entry exists on
disk; **no entry is dated 2026-09-04 or later**. Adding a new plan to the exemption
set fails two of those; removing an old one is a deliberate edit of the count.
Duplicating 56 literals across two languages buys nothing the count and the date rule
do not.

**D56-9 — the linter also runs as a CI step, and it is the one host-job step without
the docs-only guard.** A plan is `docs/**`, so a plan-carrying PR is detected as
docs-only and **skips `swift test`** — the linter would be loud locally and absent in
CI for exactly the PRs that carry plans. The step invokes the bash script directly (no
Swift build, ~1 s). Its shape is pinned beside the gate steps, with its missing guard
recorded as intentional and with an explicit assertion that it is **not** a gate: it
carries no `--gate`, so D56-4's count is unaffected.

**D56-10 — `AGENTS.md` rule 1 is rewritten; the primary idiom is "do not pipe".**
Order: `if ! cmd > /dev/null 2>&1; then … else … fi`; when both output and status are
needed, redirect to a file first and take `$?` on the next line; when a pipeline is
unavoidable, wrap the whole thing in `bash -c 'set -o pipefail; …'` and test that
`bash -c`'s status. One sentence records why the ban is addressed to plans and records
rather than to scripts: agent command blocks run under **zsh**, while all four
committed scripts are bash with a shebang and none uses `PIPESTATUS`.

**D56-11 — the per-task guarantee inventory is the authority; a spec's drill list is a
lower bound.** Written into `AGENTS.md` with its mechanism, which is the content of
D-35: TDD writes a test red-first when the test **specifies** behaviour, but a cost
pin, a probe-count bound, or a fixture that must separate two indices **measures** the
implementation — so it is written green from birth and nothing forces the question
"can this pin fail?" at the moment it is written. **This spec obeys the rule it
introduces**: §6 below is a lower bound, and the plan's per-task inventory governs.

**D56-12 — the ledger guard is a Swift test, not a linter rule.** Different artifact,
different editing moment: the ledger is edited at review time, not while authoring a
plan, and it needs no standalone authoring tool.

## 4. Contracts

### A. Gate-step shape pin (D-27)

`BenchmarkMode` gains `flagName: String?`. `WorkflowShapeTests` replaces the two-row
`pinnedGateSteps` with one row per gateable mode (12), each carrying the step name and
the ordering position. For each pinned step the existing assertions hold unchanged —
exactly one step carries the flag; its whitespace-joined `run:` payload **equals**
`gateCommand(flag)` (and, for `.pipeline`, the same command with the flag omitted —
`… ViewportBenchmarks -- --gate`); it is not `continue-on-error`; it carries the docs-only guard —
and three new ones apply across the set: the bijection (D56-2), the total order
(D56-3), and the `--gate` count (D56-4).

### B. Plan linter (D-34, D-17, D-35)

`lint-plan-assertions.sh [--self-test] [--list-exempt] [<path>…]`. With no path
argument it lints every `docs/superpowers/plans/*.md` not in the exemption list. Exit 0
on clean, 1 on any violation; every violation prints `violation=<rule> file=<path>
line=<n>` on stdout so failures are readable in a CI log. `--self-test` drives each of
R1–R4 over a known-bad fixture and a known-good fixture, printing `self_test=pass` /
`self_test=fail` in the house style. `--list-exempt` is the seam the Swift ratchet pin
reads, mirroring `derive-gate-budgets.sh --window-run-ids`.

`PlanLintTests` (new, `Tests/ViewportBenchmarksTests`) runs the script over the
repository and asserts exit 0, then pins the ratchet per D56-8.

### C. `AGENTS.md` conventions (D-17, D-35, D-37)

Rule 1 rewritten per D56-10. A fifth convention added per D56-11. Three lines added
beside the existing "anchor proof in the post-merge `push` run" bullet: the post-merge
proof lands on a separate `slice-N-hosted-proof` branch (three instances, zero written
rules), and a fact a record states about its own branch must be phrased **re-checkably**
— a per-head run table, "nineteen by SHA plus this one" rather than a bare count —
because the commit that records the fact changes it. The `Commands` block gains the new
script beside its four siblings.

### D. Ledger shape guard (D-39)

`DebtLedgerShapeTests` (new): every line beginning `| D-` carries exactly six
unescaped pipes; ids are unique; the status column is non-empty and begins with one of
`open`, `discharged(`, `scheduled(`, `deferred(`, `accepted-risk`.

### E. CI wiring (D56-9)

One step in the host job, placed after change-scope detection and before the docs-only
completion step, running `./.github/scripts/lint-plan-assertions.sh`, with **no**
docs-only guard and no `continue-on-error`. Its shape is pinned in `WorkflowShapeTests`
including the deliberate absence of the guard, so a later "quieting" edit that adds one
reddens rather than passing silently.

## 5. Acceptance criteria

1. `BenchmarkMode.flagName` exists as an exhaustive switch; `.pipeline` is `nil` with
   its justification in a comment.
2. Every gateable mode has exactly one pinned gate step, and every pinned gate step's
   mode is gateable (bijection).
3. Each of the 12 gate steps' `run:` payload equals the expected gated command, is not
   `continue-on-error`, and carries the docs-only guard.
4. The gate steps' order in the file equals the declared total order.
5. The host job contains no `--gate` invocation outside the pinned set.
6. `lint-plan-assertions.sh` implements R1–R4, exits non-zero on violation, prints one
   `violation=` line per finding, and passes `--self-test`.
7. The script is enrolled in `ScriptSelfTestTests.selfTestScripts`.
8. The exemption list holds exactly the 56 plans present on 2026-09-04; the Swift
   ratchet pin (count, on-disk existence, no entry dated ≥ 2026-09-04) passes.
9. This slice's own plan is **not** exempt and passes the linter.
10. `AGENTS.md` rule 1 no longer names `${PIPESTATUS[0]}` as a remedy and gives the
    three replacement idioms with the zsh rationale.
11. `AGENTS.md` carries the guarantee-inventory convention (D56-11) and the three
    record-writing lines (D-37).
12. `DebtLedgerShapeTests` passes over the committed ledger.
13. The CI step exists per §4E and its shape — including the intentional absence of the
    docs-only guard — is pinned.
14. Every standing guarantee this slice adds carries a **recorded red**; §6 is a lower
    bound and the plan's per-task inventory is the authority.
15. Invariant fingerprint (§7) holds.
16. Hosted proof at step level on both the PR head and the post-merge `push` run,
    recorded from a separate `slice-56-hosted-proof` branch.

## 6. Guarantee inventory and drill list (lower bound)

| # | Guarantee | Drill |
|---|---|---|
| G1 | a gateable mode without a pinned step reddens | (a) delete one table row |
| G2 | a pinned step whose mode is not gateable reddens | (b) add a row for `.wrapRowQuery` |
| G3 | each of the 12 gate steps' payload equality | (c) append `\|\| true` to each of the 12, one at a time — **all twelve recorded** |
| G4 | an unpinned 13th `--gate` step reddens | (d) add one |
| G5 | reordered gate steps redden | (e) swap two |
| G6 | a gate step losing its docs-only guard reddens | (f) delete one guard |
| G7 | `continue-on-error` on a gate step reddens | (g) add one |
| G8 | R1 | (h) fixture containing `PIPESTATUS` |
| G9 | R2 | (i) fixture with `echo "x=$?"` after `git status` |
| G10 | R3 | (j) fixture using `$SCRATCH` unassigned |
| G11 | R4 | (k) fixture task with no drill for a listed guarantee |
| G12 | grandfather ratchet | (l) add a new plan to the list; (m) list an entry absent from disk |
| G13 | ledger table shape | (n) raw `\|` inside a code span in a row |
| G14 | the CI lint step's shape, guard-absence included | (o) add the docs-only guard to it |
| G15 | self-test enrollment | (p) unenroll the script |

## 7. Invariant fingerprint

Nothing measured moves. Specifically: the 46 gated scenario checksums are
byte-identical; no `p95BudgetNanoseconds` / `p99BudgetNanoseconds` literal changes; the
corpus is untouched; `rg -n "Foundation" Sources/TextEngineCore` stays empty; the three
required-check job names are unchanged; `swift test` count grows only by the new tests.

## 8. Risks and residuals

- **R2's heuristic.** Bounded to a named list of insensitive commands plus "the
  previous line is a pipeline". A plan wanting `$?` of a genuinely status-sensitive
  command on the previous line is unaffected. If a false positive appears, the fix is
  to narrow the list, not to disable the rule.
- **The linter is checked out from the PR.** A PR could weaken the linter and pass its
  own lint. That is the standing trust model for every test here, and it is bounded:
  `detect-docs-only-pr.sh` rejects `.github/scripts/**` before the Markdown allow rule,
  so a PR touching the linter runs the full heavy path.
- **The exemption list is a one-time snapshot.** It shrinks only by deliberate edit and
  is never expected to reach zero: historical plans are evidence, and rewriting them to
  satisfy a rule written later would falsify the record.
- **New ledger row.** D-2 rules 1 and 3 remain prose (D56-7), laddered explicitly.

## 9. Out of scope

D-9 (rehomed to node 6). Any engine, provider, budget, corpus or gate-set change. Node
5 (`--memory-shape` over the wrap path, criterion 2) remains the next **feature** node
and is untouched here.
