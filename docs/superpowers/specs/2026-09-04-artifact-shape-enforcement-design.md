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
| D-34 | plan documents | D-2's four conventions are prose; nothing executes them | Slice 55a's plan shipped **4** defective checks *after* an explicit self-audit in its own preamble. **None of the four is shape-detectable** — §2.1 |
| D-35 | spec drill lists | a closed list read as authority against an AC that says "every standing guarantee" | Slice 55b: **4** guarantees shipped undrilled, caught by two later passes |
| D-17 | `AGENTS.md` rule 1 | the recommended idiom inverts to a pass under this repo's shell | **10 live usages**, every one inside a `bash` fence and all in slice 51's plan; under zsh `${PIPESTATUS[0]}` expands empty and `[ "" -eq 0 ]` is true. A raw grep counts 22 occurrences over 21 lines in 5 plans; the other 11 lines are **mentions, not usages** — which is why R1 is fence-scoped (D56-7) |
| D-37 | verification records | "a record cannot carry facts about its own branch" is unwritten | 3 instances of the fix (slices 54, 55a, 55b), 0 written rules; 55b's record stated its own commit count wrong twice |
| D-39 | `docs/superpowers/debt-ledger.md` | table shape unchecked; `\|` in a code span splits the cell | D-9's **status** column — the one the escalation rule reads — rendered as the tail of a code span instead of `scheduled(slice-56)` |

### 2.1 What the linter catches, and what D-34 is doing in that table

Checked defect by defect: **none of R1–R4 would have caught any of D-34's four measured
defects** — a regex that could not match, a check inverted under an ordering the plan
itself permits, a count not scoped to its job, and a Python loop that never rebinds its
scenario variable. All four are semantic, and one is not shell at all. D-34 belongs in
the table as the **control experiment** — prose, plus attention, plus an explicit
self-audit, still produced four defects — not as a set of findings R1–R4 answer.

The linter's load-bearing justification is therefore **D-17** (10 live sites that invert
a failed assertion into a pass) and **D-2 rule 4** (slice 47's `$SCRATCH`, 23 sites),
both shape-detectable; **D-35** rides along as a structural prompt (R4), and §8 is
explicit that R4 buys a prompt rather than a proof. Saying so here is the point: a spec
claiming R1–R4 close D-34 would be an unfalsifiable claim about enforcement, which is the
exact defect class this slice exists to end.

One consequence of the exemption list belongs here rather than in a footnote: **all 10
live `PIPESTATUS` sites are in slice 51's plan, which is grandfathered**, so R1 fires on
nothing in today's tree. Its value is prospective, and the evidence that it is
load-bearing anyway is that `AGENTS.md` recommended the idiom **by name** until this
slice (D56-10) while the four most recent plans each hand-wrote a prohibition against it
in their own preamble — authors reaching for the rule precisely because nothing enforced
it.

## 3. Decisions

**D56-1 — `BenchmarkMode.flagName: String?`, an exhaustive switch.** Never a
deny-list: a `default` makes the next mode pinned-by-accident or exempt-by-accident,
the discipline already written for `isGateable` and `absoluteCeiling`. `.pipeline`
returns `nil` — it runs as a bare `--gate` and has no flag at all. That `nil` is the
named-and-justified exemption the old `pinnedGateSteps` comment asked for; it is a
case in the switch, not a hole.

**D56-1a — `flagName` is a *pinned* third copy, not a deleted one.**
`BenchmarkOptions.parse` already carries every flag spelling as a hand-written
`case "--line-query":` label, and `swift-ci.yml` carries it a second time; a `flagName`
switch makes three, pinned pairwise only between the property and the workflow. So the
slice adds a round-trip pin: for every mode whose `flagName` is non-`nil`, parsing
`["--", flagName, "--gate"]` yields that mode with the gate enabled, and parsing
`["--", "--gate"]` yields `.pipeline` — which is what turns `.pipeline`'s `nil` from a
comment into a verified claim. **Rejected alternative:** having `parse` derive its cases
from `flagName` deletes the copy instead of pinning it, and is strictly better, but it
rewrites the per-flag "cannot be combined with another mode" messages and their tests —
option-parsing surgery inside a slice whose fingerprint (§7) is "nothing measured moves".
It becomes a ledger row (§8).

**D56-2 — the pinned table is checked against `isGateable` as a bijection.** A
gateable mode with no pinned step fails; a pinned step whose mode is not gateable
fails. Same construction as `GateFloorTests`' pin of `everyGatedBudget()` to
`isGateable`.

**D56-3 — one total order replaces twelve pairs of anchors.** The sequence of gate
steps found in the host job must equal a declared sequence of modes. Twelve
`after`/`before` pairs express the same constraint more weakly and 24 literals wide.
The order alone does not pin the block's **boundaries** — all twelve could migrate past
the diagnostics together and still be in order — so exactly two anchors survive the
collapse: the run sits after `Run host tests` and before `Run memory shape diagnostic`.
Two literals, not 24.

**D56-4 — no unpinned `--gate` may exist anywhere in the workflow.** Every `--gate`
occurrence in the file must sit inside the host job *and* inside a pinned step, and the
count must equal the number of pinned steps (12 today). Scoping the count to the host
job — the narrower rule — leaves the hole one job over: a thirteenth gate step added to
the iOS or WASM job is a gate nothing pins. Without the rule at all, a thirteenth step
carrying `|| true` is invisible to a per-step pin — the shape of the hole D-27 names,
one level up.

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

**D56-7 — four rules ship; three classes are not mechanized, and say so.**

| Rule | Fails when | Convention it enforces |
|---|---|---|
| R1 | a `bash` or `sh` fence contains `PIPESTATUS` (prose and other fence languages are exempt) | D-17 |
| R2 | `echo "…=$?"` whose previous non-empty line is a command from a named insensitive list (`git diff`, `git status`, `gh `, `jq`, `sed -i`) or a pipeline | D-2 rule 2 |
| R3 | a `$VAR` used in a `bash`/`sh` fence is not assigned in that same fence, is not in the environment allow-list, and the fence does not open `: "${VAR:?}"` | D-2 rule 4 |
| R4 | a task section lacks a **Guarantees added** block, or lists guarantees without a drill step for each | D-35 |

**R1 is fence-scoped on evidence, not caution.** Fence-classified 2026-09-04, the 22
raw `PIPESTATUS` occurrences under `docs/superpowers/plans/` fall over 21 lines and split
cleanly: **10 are live usages, every one inside a `bash` fence, and all 10 are in slice
51's plan**. The other 11 lines are **mentions** — 8 in prose in the four most recent
plans (four of them the "do NOT use `${PIPESTATUS[0]}`" preamble line itself, one per
plan, and four more in those plans' own self-review sections), plus 3 in slice 51's plan
(2 in prose, 1 inside a fenced `markdown` block). An anywhere-match would therefore
redden the four most compliant plans *for carrying the prohibition*, in a tool whose
whole value is that its findings are trustworthy. Fence scope is also what R3 needs.

Three classes are **not** mechanized. D-2 rule 1 (a check on the left of a pipe) and
rule 3 (a plan asserting its own HEAD) need semantics, not shape, and a heuristic for
them would manufacture false positives. The third is not named by D-2 at all:
plan-supplied **analysis code** — slice 55a's `predict.py`, whose `compute_*` checks sat
inside a loop that never rebound its scenario variable, so nine reported lines were one
scenario evaluated three times. D-2's four rules are about shell; that defect is not
shell. All three become one new ledger row rather than an unmentioned gap.

**D56-8 — the grandfather list is a ratchet, pinned by property, not by copy.** All
**56** plans that exist on 2026-09-04 are exempt under one shared justification
("written before the linter existed"). The list lives in the script alone, so a
standalone authoring run honours it. The Swift half pins the ratchet: the script exits
0 over the whole directory; the list holds exactly 56 entries; every entry exists on
disk; **no entry is dated 2026-09-04 or later**. Adding a new plan to the exemption
set fails two of those; removing an old one is a deliberate edit of the count. The
checks are tighter jointly than severally: *swapping* a new plan in for an old one keeps
the count at 56 and every entry on disk, but drops a pre-linter plan into the linted set,
where it fails — so the script's own exit 0 over the whole directory closes the swap.
That is why 56 literals are not duplicated into Swift.

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
the ordering position. `gateCommand` takes a `String?` so `.pipeline` is the same helper
with a `nil` — `… ViewportBenchmarks -- --gate` — rather than a second literal.

**The identifying predicate changes, and must.** Today a step is found by "exactly one
step carries the flag"; for `.pipeline` the flag *is* `--gate`, which all twelve steps
carry, so that probe is false by construction for the new row. Identification is by
**exact payload** instead: exactly one step in the host job whose whitespace-joined
`run:` equals the expected command. The predicate is then uniform across all twelve and
strictly stronger than the flag probe it replaces — a token probe cannot see a second
invocation inside one block scalar, and payload equality can.

For each pinned step the remaining assertions hold unchanged — it is not
`continue-on-error`; it carries the docs-only guard — and **four** new ones apply across
the set: the bijection (D56-2), the total order plus its two boundary anchors (D56-3),
the whole-file `--gate` scope (D56-4), and the `flagName` ↔ `parse` round trip (D56-1a).

### B. Plan linter (D-34, D-17, D-35)

`lint-plan-assertions.sh [--self-test] [--list-exempt] [<path>…]`. With no path
argument it lints every `docs/superpowers/plans/*.md` not in the exemption list. Exit 0
on clean, 1 on any violation; every violation prints `violation=<rule> file=<path>
line=<n>` on stdout so failures are readable in a CI log. `--self-test` drives each of
R1–R4 over a known-bad fixture and a known-good fixture, printing `self_test=pass` /
`self_test=fail` in the house style. `--list-exempt` is the seam the Swift ratchet pin
reads, mirroring `derive-gate-budgets.sh --window-run-ids`.

Two implementation constraints the plan must not re-decide.

**The exemption list is one array, and `--list-exempt` prints that array.** A seam that
restates its subject rather than reading it is the two-awk-programs residual (D-26) in a
new place, and it would make the Swift ratchet pin vacuous — the pin would prove the seam
agrees with itself.

**R3's recognizers are named here** so they are not invented rule-by-rule. Scope:
`bash` **and `sh`** fences. Measured over the plans on 2026-09-04 — 1 357 `bash`, 434
`swift`, 320 `text`, 67 `yaml`, 58 `markdown`, 16 `diff`, 10 `json`, **8 `sh`**, 5 `awk`,
4 `ruby`, and **no `python` fence at all**: a `bash`-only scan would skip eight shell
blocks, and the `python` fence the earlier draft named does not exist, because
plan-supplied Python arrives **heredoc'd inside a bash fence** (slice 55a's
`cat > /tmp/slice55a-predict.py <<'PY'`).

**Heredoc bodies are skipped at the scanner, for every fence-scoped rule** — R1 and R2
as much as R3, not as a per-rule courtesy. Two reasons, and the second is load-bearing:
an unskipped heredoc makes R3 analyse Python as shell, a false-positive factory in the
one tool that must not have one; and a plan that *builds* a shell tool carries that
tool's source, including its own known-bad fixtures, inside heredocs. This slice's plan
is the first instance — it writes the linter via `cat > … <<'SCRIPT'`, and that body
necessarily contains `PIPESTATUS` and `echo "…=$?"`. A rule scoped per-line rather than
per-heredoc would make the linter unable to be built by a compliant plan.

**R3's names are `SCREAMING_SNAKE` only.** A variable counts as assigned by `VAR=`,
`export VAR=`, `for VAR in`, `read [-r] VAR`, `local VAR`, or an opening
`: "${VAR:?}"`; a use is `$VAR` or `${VAR…}` where the name matches `[A-Z][A-Z0-9_]*`.
Lower-case names are excluded because a bash fence routinely embeds an `awk` or `sed`
program whose `$i`, `$1` and `$NF` are not shell variables at all — and the defect the
rule exists for, slice 47's `$SCRATCH`, is upper-case, as is every plan variable in this
repository. `$?`, `$#`, `$@` and `$1`…`$9` fall outside the name pattern by construction.
The allow-list is `$HOME`, `$PWD`, `$TMPDIR`, `$PATH`, `$USER`, `$GITHUB_*`, `$RUNNER_*`,
plus the awk built-ins `NF`, `NR`, `FS`, `OFS`, `ORS`, `RS`, `FILENAME`, `SUBSEP`.

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

`DebtLedgerShapeTests` (new): every line beginning `| D-` carries exactly six unescaped
pipes (five columns — `\|` inside a code span is the *correct* escape and is not counted);
ids are unique **and contiguous** from `D-1`; the status column is non-empty and begins
with one of `open`, `discharged(`, `scheduled(`, `deferred(`, `accepted-risk`.

The guard also pins the table's **extent** — the body is exactly the header row, the
separator row, and N id rows, and every body line matches `^| D-` — because a row whose
*id cell* is mangled stops matching `| D-` and would otherwise leave the checked set
silently, which is the same one-level-up hole D56-4 closes for gate steps.

Measured 2026-09-04 against the committed ledger: 39 rows, ids `D-1`…`D-39` contiguous,
all 39 carrying exactly six unescaped pipes, and no body line outside those three shapes.
So this is a **ratchet over a clean artifact**: AC13 needs no repair commit. (D-39's two
broken rows were repaired in the slice-55b review's own commit; what was missing, and is
what this guard supplies, is the check.)

### E. CI wiring (D56-9)

One step in the host job, placed after change-scope detection and before the docs-only
completion step, running `./.github/scripts/lint-plan-assertions.sh`, with **no**
docs-only guard and no `continue-on-error`. Its shape is pinned in `WorkflowShapeTests`
including the deliberate absence of the guard, so a later "quieting" edit that adds one
reddens rather than passing silently.

Placement is early on purpose: every other heavy step is individually guarded, so the
linter would run correctly anywhere unguarded — but a plan-lint failure ought to surface
in seconds rather than after twelve gates. It adds no new trust exposure: a PR touching
`.github/scripts/**` is rejected as docs-only by `detect-docs-only-pr.sh` before the
Markdown allow rule, so such a PR already runs the full heavy path from its own checkout.

## 5. Acceptance criteria

1. `BenchmarkMode.flagName` exists as an exhaustive switch; `.pipeline` is `nil` with
   its justification in a comment.
2. For every mode whose `flagName` is non-`nil`, `BenchmarkOptions.parse` maps that flag
   back to that mode with `--gate` accepted, and `["--", "--gate"]` parses to `.pipeline`
   (D56-1a).
3. Every gateable mode has exactly one pinned gate step, and every pinned gate step's
   mode is gateable (bijection).
4. Each of the 12 gate steps is identified by **exact payload equality**, is not
   `continue-on-error`, and carries the docs-only guard.
5. The gate steps' order in the file equals the declared total order, and the run sits
   after `Run host tests` and before `Run memory shape diagnostic`.
6. The workflow contains no `--gate` invocation outside the pinned set, **in any job**.
7. `lint-plan-assertions.sh` implements R1–R4, exits non-zero on violation, prints one
   `violation=` line per finding, and passes `--self-test`; R1 and R3 match only inside
   `bash`/`sh` fences, with heredoc bodies excluded.
8. The script is enrolled in `ScriptSelfTestTests.selfTestScripts`.
9. The exemption list is a single array in the script, `--list-exempt` prints that array,
   and it holds exactly the 56 plans present on 2026-09-04; the Swift ratchet pin (count,
   on-disk existence, no entry dated ≥ 2026-09-04, script exit 0 over the whole directory)
   passes.
10. This slice's own plan is **not** exempt and passes the linter.
11. `AGENTS.md` rule 1 no longer names `${PIPESTATUS[0]}` as a remedy and gives the
    three replacement idioms with the zsh rationale.
12. `AGENTS.md` carries the guarantee-inventory convention (D56-11) and the three
    record-writing lines (D-37).
13. `DebtLedgerShapeTests` passes over the committed ledger, pinning pipe count, id
    uniqueness and contiguity, the status vocabulary, and the table's extent.
14. The CI step exists per §4E and its shape — including the intentional absence of the
    docs-only guard — is pinned.
15. Every standing guarantee this slice adds carries a **recorded red**; §6 is a lower
    bound and the plan's per-task inventory is the authority.
16. Invariant fingerprint (§7) holds.
17. Hosted proof at step level on both the PR head and the post-merge `push` run,
    recorded from a separate `slice-56-hosted-proof` branch.

## 6. Guarantee inventory and drill list (lower bound)

| # | Guarantee | Drill |
|---|---|---|
| G1 | a gateable mode without a pinned step reddens | (a) delete one table row |
| G2 | a pinned step whose mode is not gateable reddens | (b) add a row for `.wrapRowQuery` |
| G3 | each of the 12 gate steps' payload equality, and every table row is live | (c) append `\|\| true` to **all twelve at once** in one edit, and record that exactly 12 distinct failures are reported. One run, and *stronger* than twelve single-step runs: a per-row loop that catches one row catches all of them, but only a simultaneous drill proves no row is silently unbound. Then (c2) one single-step edit, for per-step attribution |
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
| G16 | `flagName` round-trips through `parse` (D56-1a) | (q) change one `flagName` literal to a flag `parse` does not accept |
| G17 | `.pipeline`'s `nil` is a claim, not a comment | (r) give `.pipeline` a flag name |
| G18 | the gate block's boundary anchors (D56-3) | (s) move all twelve after `Run memory shape diagnostic`, order preserved |
| G19 | a `--gate` step outside the host job reddens (D56-4) | (t) add one to the WASM job |
| G20 | `--list-exempt` reads the live array, not a copy | (u) delete one entry from the array and confirm the seam's output changes with it |
| G21 | ledger id contiguity and table extent | (v) delete a middle row; (w) mangle a row's id cell so it no longer matches `\| D-` |

## 7. Invariant fingerprint

Nothing measured moves. Specifically: the 46 gated scenario checksums are
byte-identical; no `p95BudgetNanoseconds` / `p99BudgetNanoseconds` literal changes; the
corpus is untouched; `rg -n "Foundation" Sources/TextEngineCore` stays empty; the three
required-check job names are unchanged.

The test count is recorded as a **before/after pair with the delta**, and the delta must
equal the number of test functions this slice adds. "Grows only by the new tests" is not
a checkable form — it names no number, so no reader can falsify it, which is the defect
class §2 tabulates.

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
- **R4 buys a prompt, not a proof.** A task satisfies it with an empty **Guarantees
  added** block, or with a drill step that names a drill it does not perform. The linter
  checks document structure; only a reader checks that a drill drills. Accepted and named
  rather than implied: R4's value is that the question is *asked at authoring time*, which
  is precisely what D-35 measured as missing.
- **R1's measured base is entirely exempt.** Its 10 live sites sit in a grandfathered
  plan, so R1 is a recurrence guard, not a cleanup, and it will pass on day one having
  found nothing. That is the expected shape, not a defect — but a reader who mistakes it
  for "the linter cleaned up 10 sites" would be wrong.
- **The linter answers D-17 and D-2 rule 4, not D-34** (§2.1). D-34's four measured
  defects stay unmechanized.
- **`flagName` is a pinned third copy, not a deleted one** (D56-1a). Deriving `parse`
  from it removes the copy and is the better fix; it is out of scope for a slice whose
  fingerprint is "nothing measured moves".
- **New ledger row(s).** D-2 rules 1 and 3 remain prose, plus the analysis-code class
  (D56-7) and the `parse` derivation above — laddered explicitly rather than left
  unmentioned.

## 9. Out of scope

D-9 (rehomed to node 6). Any engine, provider, budget, corpus or gate-set change. Node
5 (`--memory-shape` over the wrap path, criterion 2) remains the next **feature** node
and is untouched here.
