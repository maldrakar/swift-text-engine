# Slice 56 — artifact-shape enforcement — verification record

- **Spec:** [`docs/superpowers/specs/2026-09-04-artifact-shape-enforcement-design.md`](../specs/2026-09-04-artifact-shape-enforcement-design.md)
- **Plan:** [`docs/superpowers/plans/2026-09-04-artifact-shape-enforcement.md`](../plans/2026-09-04-artifact-shape-enforcement.md)
- **Branch:** `slice-56-artifact-shape-enforcement`, base commit `eacb50d` ("docs: slice
  56 implementation plan (7 tasks, 21 guarantees, 23 drills)").

## 0. Commits, by SHA — not "the current HEAD"

Per the convention this slice itself writes (D-37, `AGENTS.md`'s "A record cannot carry
facts about its own branch"): the commits below are named **by SHA**, oldest first, and
the list is **open at the end** — commits that land after a row is written cannot
falsify a row, but they do falsify any total. No bare commit count is asserted anywhere
in this document, and no commit is called "the current HEAD." Re-derive the current
list with `git log --format='%H %s' --reverse eacb50d..HEAD`; rows 1–11 were confirmed
against it before the table was first written, and rows 12–14 were appended afterwards
by the same command.

| # | SHA (full) | Subject |
|---|---|---|
| 1 | `0da7ea5a9e01b97406a02784cd919987ebeadc4f` | feat: BenchmarkMode.flagName, pinned to BenchmarkOptions.parse |
| 2 | `568b628e85e5fe26d41e5f93cf70be6f40e656be` | test: pin the shape of all twelve gate steps, not two |
| 3 | `3293b8f657ca721f0686fa6b2ff6698c01abe20c` | test: pin the debt ledger's table shape |
| 4 | `4e1e9feceff0964333e4e05402268a600724044e` | test: fix debt ledger shape test's escape parity and empty-set trap |
| 5 | `084a2f2bc27d909a2813689287d78c5849a71843` | feat: lint-plan-assertions.sh — the shape-detectable half of D-2 |
| 6 | `7f1ccf6bb2e81b77e0c7b2d503ce54b851fbb316` | fix: lint-plan-assertions.sh — five false positives/negatives + three minors |
| 7 | `f2a3f7470af85666d8ea9a85bf1cb177edb363f1` | fix: lint-plan-assertions.sh — R2 no longer reads '|' inside a quoted regex as a pipe |
| 8 | `10f671c1df0b025622d13227b36f7184c14132c5` | ci: run the plan linter, and pin its exemption ratchet |
| 9 | `f902749944b5441c4c241bc32e0db3a418f0a7ea` | test: PlanLintTests fix round 1 — measured ratchet claims, close four vacuity gaps |
| 10 | `deaddf058f080c0b328c9a11e54a46cd810c1509` | docs: rewrite D-2 rule 1, add the guarantee-inventory convention, settle the ledger |
| 11 | `6e310fb5328b67250bf1e68e210e40176f2da126` | docs: fix round 1 — narrow rule 1's enforcement claim, correct D-27/D-34/D-9/D-17 |
| 12 | `137397434009eba3721844bacbd8a48b48e29c12` | docs: slice 56 verification record |
| 13 | `5e99b8a27b10ad255cc48f16c7fc19b9160fbe20` | docs: slice 56 verification record fix round 1 — eight re-checkability fixes |
| 14 | `7aa28793751ea3495ed106401e3167904c154746` | fix: slice 56 final fix wave — R4 heading gap, R3 false positive, tautological test |
| 15 | `3d376479f6a67d4d6397069d4f41a596cbd1bbf1` | fix: lint-plan-assertions.sh — R4's heading pattern was inert on the CI awk |
| 16 | `012b99981f9ad38b04404c86ada13e4ef9646013` | test: PlanLintTests — re-derive the exempt split instead of quoting it |

Row 12 was written as *(this commit)* and is now named by its SHA; rows 13–16 landed
after it, and the commit carrying this edit is itself unnamed here for the same
reason row 12 once was. This is the D-37 hazard behaving exactly as the row predicts
— a table entry can only be completed by a later commit, so the section is written to
be *appended to*, never to assert a total.

## 1. Scope recap

Six repository artifacts whose shape nothing verified became verifiable: the twelve
blocking CI gate steps (`WorkflowShapeTests`), plan documents (a new
`lint-plan-assertions.sh` linter, `PlanLintTests`, wired into CI), the debt ledger
(`DebtLedgerShapeTests`), `BenchmarkMode.flagName` (the registry the gate pin needs),
and `AGENTS.md`'s D-2 rule 1 (rewritten to drop the `${PIPESTATUS[0]}` recommendation
that inverts a failed check into a pass under zsh). Nothing measured moves: no core
source, no budget literal, no corpus row, no gated checksum.

## 2. Per-task record

Each task's transcript below is pulled from the implementer's own task report
(`.superpowers/sdd/2026-09-04-artifact-shape-enforcement/task-N-report.md` —
gitignored, not part of the repository, hence transcribed here rather than linked).
Every drill's **recorded RED text** is quoted verbatim from those reports, except
drill (c), which this record reproduces independently (§3).

### Task 1 — `BenchmarkMode.flagName`, pinned to `parse`

Commit `0da7ea5`. Adds `BenchmarkMode.flagName: String?` (exhaustive switch, no
`default:`) to `Sources/ViewportBenchmarks/BenchmarkOptions.swift`, and
`Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift` (4 tests).

**Guarantees added:** G16 (`flagName` round-trips through `parse`), G17
(`.pipeline`'s `nil` is a claim, not a comment).

**Step 2 — red before implementation** (`swift test --filter BenchmarkModeFlagNameTests`):
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift:52:59: error: value of type 'BenchmarkMode' has no member 'flagName'
```
(compilation failure, as the brief predicted).

**Step 4 — green after implementation:**
```
Test Suite 'BenchmarkModeFlagNameTests' passed at 2026-09-04 11:07:50.637.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

**Drill (q) — G16, wrong flag spelling must redden** (`.lineQuery`'s flag temporarily
changed to `"--line-queries"`):
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift:13: error: -[ViewportBenchmarksTests.BenchmarkModeFlagNameTests testEveryFlagNameRoundTripsThroughParse] : failed - line_query: parse rejected its own flagName --line-queries
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift:28: error: -[ViewportBenchmarksTests.BenchmarkModeFlagNameTests testEveryGateableFlagNameAcceptsTheGateFlag] : failed - line_query: parse rejected --line-queries --gate
Test Suite 'BenchmarkModeFlagNameTests' failed at 2026-09-04 11:07:59.534.
	 Executed 4 tests, with 2 failures (0 unexpected) in 0.090 (0.091) seconds
```
Restored by hand; re-run green (`Executed 4 tests, with 0 failures`); `git diff --stat`
showed only the intended +55-line addition.

**Drill (r) — G17, giving `.pipeline` a flag must redden** (`.pipeline`'s case changed
from `return nil` to `return "--pipeline"`; the brief's own multi-line `sed` form does
not work, so this was a hand edit):
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift:13: error: -[ViewportBenchmarksTests.BenchmarkModeFlagNameTests testEveryFlagNameRoundTripsThroughParse] : failed - pipeline: parse rejected its own flagName --pipeline
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift:28: error: -[ViewportBenchmarksTests.BenchmarkModeFlagNameTests testEveryGateableFlagNameAcceptsTheGateFlag] : failed - pipeline: parse rejected --pipeline --gate
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift:53: error: -[ViewportBenchmarksTests.BenchmarkModeFlagNameTests testOnlyThePipelineModeLacksAFlagName] : XCTAssertEqual failed: ("[]") is not equal to ("["pipeline"]") - only the default mode may have no flag; got []
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/BenchmarkModeFlagNameTests.swift:40: error: -[ViewportBenchmarksTests.BenchmarkModeFlagNameTests testPipelineHasNoFlagAndIsSelectedByABareGate] : XCTAssertNil failed: "--pipeline"
Test Suite 'BenchmarkModeFlagNameTests' failed at 2026-09-04 11:08:14.583.
	 Executed 4 tests, with 4 failures (0 unexpected) in 0.035 (0.035) seconds
```
All 4 tests failed, as predicted. Reverted by hand; re-run green; `git diff --stat`
clean of drill residue.

**Whole suite after Task 1:** 484 tests, 0 failures (480 baseline + 4). Foundation
scan empty.

**Commit:** `0da7ea5`, local only.

---

### Task 2 — the gate-step pin, generalized to twelve

Commit `568b628`. Rewrites `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`
only: `pinnedGateSteps` grows from 2 hand-written rows to 12 (one per gateable
`BenchmarkMode`), identification switches from flag-token containment to **exact
payload equality**, the twelve per-row before/after anchor pairs collapse into one
declared total order plus two boundary anchors (`gateBlockAfterStepName`/
`gateBlockBeforeStepName` = "Run host tests" / "Run memory shape diagnostic"), and
four new invariants are added. No workflow, budget, corpus, or checksum file changed.

**Guarantees added:** G1, G2, G3, G4, G5, G6, G7, G18, G19.

**Deviation (Ruling F2, see §7):** the old `testEachPinnedGateSitsBetweenItsAnchors`
(invariant 6) was deleted rather than adapted — the new `GateStepSpec` carries no
`afterStepName`/`beforeStepName` fields — and its content is exactly what the two new
total-order/boundary-anchor tests replace. Net: 10 (baseline) − 1 (deleted) + 4 (new)
= 13 test methods, not the brief's predicted 10.

**Step 3 — file's own tests:**
```
Test Suite 'WorkflowShapeTests' passed at 2026-09-04 11:14:32.042.
	 Executed 13 tests, with 0 failures (0 unexpected) in 0.008 (0.008) seconds
```
Whole suite: **487 tests, 0 failures** (484 + 3 net).

**Drill (c) — G3, all twelve at once (load-bearing).** Recorded independently by this
task (§3 below) rather than reproduced from the Task 2 report, which recorded the
count but not verbatim output. Task 2's own count (**84** resolver-message
occurrences, not the brief's predicted 12, fully explained by 7 test methods × 12
rows) is confirmed and superseded by the independent re-run in §3, which additionally
captures the full **96**-failure transcript (84 + 12 from
`testExactlyOneStepRunsEachPinnedGate`'s own count assertion) and the 12-distinct-
command census on the *final* eleven-commit tree (14 `WorkflowShapeTests` after Task
5 adds a 14th test; the drill's shape is unaffected — see §3).

**Drill (c2) — G3 attribution, one step (`--line-query`) disarmed alone:**
```
.../WorkflowShapeTests.swift:279: error: -[...testEachPinnedGateCarriesTheDocsOnlyGuard] : XCTAssertFalse failed - .github/workflows/swift-ci.yml: no step in host-tests-and-benchmark-gate runs exactly `swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate` — the "Run line query benchmark gate" gate is gone, renamed, or had its payload edited
.../WorkflowShapeTests.swift:294: error: -[...testExactlyOneStepRunsEachPinnedGate] : XCTAssertEqual failed: ("0") is not equal to ("1") - .github/workflows/swift-ci.yml: 0 steps run `swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate`, want exactly 1 — []
```
`Executed 13 tests, with 8 failures (0 unexpected)`. `restored=yes`.

**Drill (d) — G4, duplicated `--point-query` step (renamed "Run spare gate"):**
```
.../WorkflowShapeTests.swift:350: error: -[...testEachPinnedGateIsNamedForItsSiblings] : XCTAssertEqual failed: ("Run spare gate") is not equal to ("Run point query benchmark gate") - step running `swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-query --gate` is named "Run spare gate", want "Run point query benchmark gate"
.../WorkflowShapeTests.swift:423: error: -[...testEveryGateInvocationInTheWorkflowIsPinned] : XCTAssertEqual failed: ("13") is not equal to ("12") - .github/workflows/swift-ci.yml carries 13 `--gate` tokens but 12 steps are pinned. Every gate invocation anywhere in this workflow must be a pinned step: an unpinned one can carry `|| true` or continue-on-error and no test would see it.
.../WorkflowShapeTests.swift:294: error: -[...testExactlyOneStepRunsEachPinnedGate] : XCTAssertEqual failed: ("2") is not equal to ("1") - .github/workflows/swift-ci.yml: 2 steps run `swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-query --gate`, want exactly 1 — ["Run point query benchmark gate", "Run spare gate"]
```
`Executed 13 tests, with 3 failures (0 unexpected)`. `restored=yes`.

**Drill (e) — G5, swapped `--column-query`/`--point-query` step blocks:**
```
.../WorkflowShapeTests.swift:383: error: -[...testGateStepsAppearInTheDeclaredOrder] : XCTAssertLessThan failed: ("14") is not less than ("13") - Run column geometry query benchmark gate sits out of the declared gate order (index 13 after index 14); pinnedGateSteps declares the order the host job must run them in
.../WorkflowShapeTests.swift:383: error: -[...testGateStepsAppearInTheDeclaredOrder] : XCTAssertLessThan failed: ("13") is not less than ("12") - Run point query benchmark gate sits out of the declared gate order (index 12 after index 13); pinnedGateSteps declares the order the host job must run them in
```
`Executed 13 tests, with 2 failures (0 unexpected)` — the **only** failing test is
`testGateStepsAppearInTheDeclaredOrder`, no collateral failures. `restored=yes`.

**Drill (f) — G6, deleted the `if:` guard from the `--structural-mutation` step:**
```
.../WorkflowShapeTests.swift:337: error: -[...testEachPinnedGateCarriesTheDocsOnlyGuard] : XCTAssertEqual failed: ("nil") is not equal to ("Optional("steps.change-scope.outputs.docs_only_pr != 'true'")") - Run structural mutation benchmark gate: does not carry the sibling docs-only guard
```
(Normalized from the source task report's shell-escaped `!= \'true\'` to the literal
`!= 'true'` — confirmed against `WorkflowShapeTests.swift`'s own string, which carries
the unescaped spelling; no other character changed.)
`Executed 13 tests, with 1 failure (0 unexpected)`. `restored=yes`.

**Drill (g) — G7, `continue-on-error: true` on the synthetic gate step:**
```
.../WorkflowShapeTests.swift:323: error: -[...testNoPinnedGateIsContinueOnError] : XCTAssertNil failed: "true" - Run synthetic benchmark gate: carries continue-on-error: true — a continue-on-error step cannot be a gate; it swallows budget misses, correctness failures and crashes alike
```
`Executed 13 tests, with 1 failure (0 unexpected)`. `restored=yes`.

**Drill (t) — G19, a `--gate` step added to the WASM job:**
```
.../WorkflowShapeTests.swift:423: error: -[...testEveryGateInvocationInTheWorkflowIsPinned] : XCTAssertEqual failed: ("13") is not equal to ("12") - .github/workflows/swift-ci.yml carries 13 `--gate` tokens but 12 steps are pinned. Every gate invocation anywhere in this workflow must be a pinned step: an unpinned one can carry `|| true` or continue-on-error and no test would see it.
```
`Executed 13 tests, with 1 failure (0 unexpected)`. `restored=yes`; post-restore
`diff <(git show HEAD:...) swift-ci.yml` byte-identical.

**Drill (a) — G1, deleted `.columnQuery` row from `pinnedGateSteps`:**
```
.../WorkflowShapeTests.swift:422: error: -[...testEveryGateInvocationInTheWorkflowIsPinned] : XCTAssertEqual failed: ("12") is not equal to ("11") - .github/workflows/swift-ci.yml carries 12 `--gate` tokens but 11 steps are pinned. ...
.../WorkflowShapeTests.swift:364: error: -[...testPinnedGateStepsCoverExactlyTheGateableModes] : XCTAssertEqual failed: (missing "column_query") - pinnedGateSteps and BenchmarkMode.isGateable disagree. ...
```
`Executed 13 tests, with 2 failures (0 unexpected)`. Restored via `cp` from a golden
copy (the test file legitimately differs from HEAD in this task; `diff` clean →
`restored=yes`).

**Drill (b) — G2, added a `.wrapRowQuery` row to `pinnedGateSteps`** (not gateable):
```
.../WorkflowShapeTests.swift:280: error: -[...testEachPinnedGateRunsExactlyTheExpectedCommand] : XCTAssertFalse failed - ... no step ... runs exactly `... -- --wrap-row-query --gate` — the "Run wrap row query benchmark gate" gate is gone, renamed, or had its payload edited
.../WorkflowShapeTests.swift:424: error: -[...testEveryGateInvocationInTheWorkflowIsPinned] : XCTAssertEqual failed: ("12") is not equal to ("13") - .github/workflows/swift-ci.yml carries 12 `--gate` tokens but 13 steps are pinned. ...
.../WorkflowShapeTests.swift:366: error: -[...testPinnedGateStepsCoverExactlyTheGateableModes] : XCTAssertEqual failed: (extra "wrap_row_query") - pinnedGateSteps and BenchmarkMode.isGateable disagree. ...
```
`Executed 13 tests, with 10 failures (0 unexpected)` — both
`testPinnedGateStepsCoverExactlyTheGateableModes` **and** the payload resolver fire
(no step runs `--wrap-row-query --gate` since that mode is not gateable), exactly as
the brief predicted. `restored=yes`.

**Drill (s) — G18, all twelve gate blocks moved to sit after `Run memory shape
diagnostic`** (relative order among the twelve preserved):
```
.../WorkflowShapeTests.swift:407: error: -[...testGateBlockSitsBetweenItsBoundaryAnchors] : XCTAssertLessThan failed: ("6") is not less than ("5") - Run synthetic benchmark gate must sit before "Run memory shape diagnostic"
[... one such failure per gate step, 12 total, indices 6 through 17 ...]
```
`Executed 13 tests, with 12 failures (0 unexpected)` — all 12 are
`testGateBlockSitsBetweenItsBoundaryAnchors`. **`testGateStepsAppearInTheDeclaredOrder`
stayed green** — the twelve are still in relative order, only the block as a whole
migrated past the boundary anchor, which is exactly the asymmetry the two mechanisms
exist to catch separately. `restored=yes`; post-restore byte-identical to HEAD.

**Whole suite after Task 2:** 487 tests, 0 failures.

**Commit:** `568b628`, local only.

---

### Task 3 — the debt ledger's table shape

Commits `3293b8f` (initial 4 tests) and `4e1e9fe` (fix round: escape-parity bug +
empty-set trap, 1 more test — 5 total). Adds
`Tests/ViewportBenchmarksTests/DebtLedgerShapeTests.swift`.

**Guarantees added:** G13 (ledger table shape), G21 (id contiguity + table extent).

**Step 2 — pass on the committed (clean) ledger:**
```
Test Suite 'DebtLedgerShapeTests' passed at 2026-09-04 11:29:51.020.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.006 (0.006) seconds
```

**Drill (n) — G13, raw pipe in a code span** (`gov_p95=median\|max` → `gov_p95=median|max`
on D-9's row; the same literal substring also appears on D-39's row, so both reddened,
legitimately):
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/DebtLedgerShapeTests.swift:64: error: -[ViewportBenchmarksTests.DebtLedgerShapeTests testEveryRowHasExactlyFiveColumns] : XCTAssertEqual failed: ("7") is not equal to ("6") - docs/superpowers/debt-ledger.md: row D-9 carries 7 unescaped pipes, want 6 (five columns). A literal `|` inside a code span splits the cell in GFM — write it `\|`. This is not cosmetic: a split row shifts the STATUS column, which the escalation rule reads.
```
`Executed 4 tests, with 2 failures (0 unexpected)`. `restored=yes`.

**Drill (v) — G21, deleted row D-20 (gap check):**
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/DebtLedgerShapeTests.swift:106: error: -[ViewportBenchmarksTests.DebtLedgerShapeTests testRowIdsAreUniqueAndContiguousFromOne] : XCTAssertEqual failed: ("[1, 2, ..., 19, 21, 22, ..., 39]") is not equal to ("[1, 2, ..., 38]") - docs/superpowers/debt-ledger.md: ids must run D-1…D-38 with no gaps and no repeats. The ledger is append-only, so a gap means a row was deleted instead of having its status flipped.
```
`Executed 4 tests, with 1 failure (0 unexpected)` — observed sequence jumps `19 → 21`
exactly as predicted. `restored=yes`.

**Drill (w) — G21, mangled id cell (`D-30` → `X-30`):**
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/DebtLedgerShapeTests.swift:84: error: -[ViewportBenchmarksTests.DebtLedgerShapeTests testTheTableIsHeaderSeparatorAndIdRowsOnly] : XCTAssertTrue failed - docs/superpowers/debt-ledger.md: table body line 32 does not start with `| D-`: | X-30 | ... — a row that stops matching leaves every other check in this file silently, which is exactly how an unchecked row hides
```
**The asymmetry, explicitly recorded:** `testEveryRowHasExactlyFiveColumns` stayed
**green** (the mangled row silently drops out of the `| D-`-filtered population that
test scans — it still carries six unescaped pipes, so even scanned it would look
clean), while `testTheTableIsHeaderSeparatorAndIdRowsOnly` — which walks the table's
full extent rather than pre-filtering — is the only one of the four that catches it.
(`testRowIdsAreUniqueAndContiguousFromOne` also failed as a side effect: removing
`D-30` from the id population produces a `29 → 31` gap.) `Executed 4 tests, with 2
failures (0 unexpected)`. `restored=yes`.

**Fix round (commit `4e1e9fe`).** Two review findings, both in code the brief
specified verbatim:
1. **Escape-parity false negative.** `unescapedPipeCount`/`columns(of:)` looked one
   character back, so `\\|` (an escaped backslash followed by a real separator) was
   miscounted as escaped. Fixed to test the parity of the run of backslashes
   immediately preceding each `|`. Covering test
   `testEscapeParityHandlesRunsOfBackslashes` (RED before: `unescapedPipeCount("a\\|b")`
   returned `0` instead of `1`; GREEN after).
2. **Trap instead of fail on an empty id set.**
   `XCTAssertEqual(numbers, Array(1...numbers.count))` traps (`Array(1...0)` is a
   Swift fatal error) when `numbers` is empty — this would abort the whole `swift
   test` binary rather than report one clean red. Drilled by repointing `ledgerPath`
   at a scratch fixture with a header/separator but zero `| D-` rows:
   ```
   Swift/arm64e-apple-macos.swiftinterface:6974: Fatal error: Range requires lowerBound <= upperBound
   ```
   (no "Executed N tests" summary line ever printed — confirmed crash, not a clean
   red). Guarded with `guard !numbers.isEmpty else { return XCTFail(...) }`; re-run
   on the same fixture produced a clean `Executed 1 test, with 1 failure`.

**Post-fix, whole suite:** 492 tests, 0 failures (491 + 1 new test).

**Commits:** `3293b8f`, `4e1e9fe`, local only.

---

### Task 4 — the plan linter

Commits `084a2f2` (initial), `7f1ccf6` (fix round 1: 5 false positives/negatives + 3
minors), `f2a3f74` (fix round 2: R2 quoted-alternation false positive). Creates
`.github/scripts/lint-plan-assertions.sh` (mode 755) and enrolls it in
`ScriptSelfTestTests.selfTestScripts`.

**Guarantees added:** G8 (R1), G9 (R2), G10 (R3), G11 (R4), G15 (self-test
enrollment).

**Deviations (see §7 for full text):** Ruling F5 (fence rule must not fire inside a
heredoc body), Ruling F7 (cwd-independent `PLANS_DIR`), and an undocumented third fix
(the self-test's `trap` used single-quoted `$dir` expansion, which fired after
`local dir` went out of scope under `set -u` — fixed to double-quoted expansion at
trap-set time, later replaced by a single global `trap cleanup EXIT`).

**Step 2 — `--self-test`:**
```
$ ./.github/scripts/lint-plan-assertions.sh --self-test; echo "EXIT=$?"
self_test=pass
EXIT=0
```

**Step 3 — repository lint:**
```
$ ./.github/scripts/lint-plan-assertions.sh; echo "EXIT=$?"
lint=pass files=1 violations=0
EXIT=0
```

**Drill (h) — G8, R1 neutralized** (`if ($0 ~ /PIPESTATUS/) {` → `if (0) {`):
```
self_test=fail label=bad_r1_exit
restored=yes
```

**Drill (i) — G9, R2 neutralized** (`if ($0 ~ /echo[^=]*=\$\?/) {` → `if (0) {`):
```
self_test=fail label=bad_r2_exit
restored=yes
```

**Drill (j) — G10, R3 neutralized** (`return` inserted as `close_fence`'s first
statement, before its `for (name in used)` loop):
```
self_test=fail label=bad_r3_exit
restored=yes
```

**Drill (k) — G11, R4 neutralized** (`return` inserted as `check_task`'s first
statement, before its `if (guarantee_line == 0)` check):
```
self_test=fail label=bad_r4_exit
restored=yes
```
Note: the plan's table names two expected labels
(`bad_r4_exit`/`bad_r4-missing_exit`), but `run_self_test`'s loop calls `assert_equal`,
which `exit 1`s on the first mismatch — since `r4` iterates before `r4-missing`, only
`bad_r4_exit` is observed per run. Recorded as the harness's fail-fast behavior, not a
discrepancy: with `check_task` neutralized, both underlying fixtures independently
fail if reached.

**Drill (p) — G15, unenrolled script must redden** (deleted the
`"lint-plan-assertions.sh",` line from `selfTestScripts`):
```
ScriptSelfTestTests.swift:65: error: -[...testTableCoversEveryScriptWithASelfTest] :
XCTAssertEqual failed: ("[..., "lint-plan-assertions.sh"]") is not equal to
("[...]") - enroll every script that has a --self-test in selfTestScripts, or
the new one's assertions cannot fail a build
```
`drill_p=red_as_expected`. Restored; confirmed matches the pre-drill state via `diff`.

**Fix round 1 (`7f1ccf6`) — 5 false positives/negatives + 3 minors, each proven
RED-before/GREEN-after against a dedicated fixture.** Essential evidence (fixture
name, command, RED-before/GREEN-after) is inlined below, rather than pointed at the
gitignored Task 4 report, so this record does not depend on it:

1. **Ruling F5 was undrilled** — the fence-in-heredoc guard
   (`/^```/ && !in_heredoc`) had no fixture proving it load-bearing. Added
   `bad-fence-in-heredoc.md` (a `bash` fence containing a heredoc whose body carries
   one markdown fence delimiter, then a second `bash` fence with a genuine
   unassigned `$SOMETHING`):
   ```
   $ /usr/bin/env bash lint.pre-F5-reverted.sh fixtures/finding1-bad-fence-in-heredoc.md   # guard reverted to /^```/ {
   lint=pass files=1 violations=0
   exit=0                                          # RED -- the miss, confirmed

   $ /usr/bin/env bash lint.pre-fixround1.bak fixtures/finding1-bad-fence-in-heredoc.md    # committed (post-F5) script
   violation=R3 file=fixtures/finding1-bad-fence-in-heredoc.md line=12 detail=$SOMETHING is used in this fence but assigned nowhere in it; each command block is a fresh shell, so it expands empty (D-2 rule 4)
   lint=fail files=1 violations=1
   exit=1                                          # GREEN -- caught
   ```
   Enrolled in `run_self_test` with `expected="R3"`.

2. **R2 read the previous LINE, not the previous COMMAND** — a same-line `;` now
   splits the line and locates the segment immediately preceding the echo match:
   ```
   $ /usr/bin/env bash lint.pre-fixround1.bak fixtures/finding2a-semicolon-fires.md    # same-line ; must fire R2
   lint=pass files=1 violations=0
   exit=0                                          # RED -- missed, prev_shell was empty

   $ .github/scripts/lint-plan-assertions.sh fixtures/finding2a-semicolon-fires.md
   violation=R2 file=fixtures/finding2a-semicolon-fires.md line=6 detail=echo "...=$?" after a command whose exit status is insensitive to the invariant; ...
   lint=fail files=1 violations=1
   exit=1                                          # GREEN -- now fires
   ```
   Regression control (a pipeline on the line ABOVE, a clean `;`-joined command on
   this line, must stay CLEAN):
   ```
   $ /usr/bin/env bash lint.pre-fixround1.bak fixtures/finding2b-semicolon-after-pipe-clean.md
   violation=R2 file=fixtures/finding2b-semicolon-after-pipe-clean.md line=7 detail=... (D-2 rule 2) ...
   lint=fail files=1 violations=1
   exit=1                                          # RED -- false positive, used prev_shell's pipe

   $ .github/scripts/lint-plan-assertions.sh fixtures/finding2b-semicolon-after-pipe-clean.md
   lint=pass files=1 violations=0
   exit=0                                          # GREEN -- now clean
   ```
   Both fixtures (`bad-r2-semicolon.md`, `clean-r2-semicolon-after-pipe.md`) enrolled.

3. **R2 flagged its own prescribed remedy** — `git diff --quiet` + `echo "…=$?"` is
   the exact idiom `AGENTS.md` recommends, and R2 was flagging it:
   ```
   $ /usr/bin/env bash lint.pre-fixround1.bak fixtures/finding3a-diff-quiet-clean.md
   violation=R2 file=fixtures/finding3a-diff-quiet-clean.md line=7 detail=... Assert with [ -z "$(...)" ], git diff --quiet, or an if/else printing both branches
   lint=fail files=1 violations=1
   exit=1                                          # RED -- flags its own prescribed remedy

   $ .github/scripts/lint-plan-assertions.sh fixtures/finding3a-diff-quiet-clean.md
   lint=pass files=1 violations=0
   exit=0                                          # GREEN -- now clean
   ```
   Regression control (plain `git diff --name-only` + `echo "changed=$?"`, must
   still fire): both the pre- and post-fix runs produced `violation=R2 ... lint=fail
   files=1 violations=1` — unaffected by the exclusion, as intended.

4. **F5 traded a noisy corruption for a silent one** — an unterminated heredoc was
   silently swallowed to EOF and read as clean:
   ```
   $ /usr/bin/env bash lint.pre-fixround1.bak fixtures/finding4-unterminated-heredoc.md
   lint=pass files=1 violations=0
   exit=0                                          # RED -- silently swallowed to EOF

   $ .github/scripts/lint-plan-assertions.sh fixtures/finding4-unterminated-heredoc.md
   violation=scanner file=fixtures/finding4-unterminated-heredoc.md line=6 detail=heredoc <<'EOF' opened at line 6 was never terminated; the scan was abandoned at that point, so everything after it in this file went unchecked (Finding 4 -- an unterminated heredoc must not read as a clean plan)
   lint=fail files=1 violations=1
   exit=1                                          # GREEN -- reported and fails
   ```

5. **An unrecognized flag was a vacuous pass / stdin hang:**
   ```
   $ timeout 5 /usr/bin/env bash lint.pre-fixround1.bak --bogus </dev/null
   awk: unknown option --bogus ignored
   lint=pass files=1 violations=0
   exit=0                                          # RED -- vacuous pass on a typo'd flag

   $ timeout 5 .github/scripts/lint-plan-assertions.sh --bogus </dev/null
   unknown option: --bogus
   exit=2                                          # GREEN -- rejects loudly
   ```

   Minors: an awk temp-file leak on every invocation, measured across 15 invocations
   (`before=157 after=172` on the unfixed script vs. `before=157 after=157` on the
   fixed one) — now one `trap cleanup EXIT`; `"${files[@]}"` fatal on an empty array
   under bash 3.2 + `set -u` (guarded, isolated repro confirmed on
   `GNU bash, version 3.2.57(1)-release`); a `<<<` here-string phantom-matched as a
   heredoc opener:
   ```
   $ /usr/bin/env bash lint.pre-fixround1.bak fixtures/minor8-herestring-bad-r3.md
   lint=pass files=1 violations=0
   exit=0                                          # RED -- $SOMETHING swallowed as phantom heredoc body

   $ .github/scripts/lint-plan-assertions.sh fixtures/minor8-herestring-bad-r3.md
   violation=R3 file=fixtures/minor8-herestring-bad-r3.md line=7 detail=$SOMETHING is used in this fence but assigned nowhere in it; ...
   lint=fail files=1 violations=1
   exit=1                                          # GREEN -- now caught
   ```

**Fix round 2 (`f2a3f74`)** — Round 1's same-line `;` fix made a latent defect live:
`is_insensitive_predecessor`'s pipe test read a `|` inside a **quoted regex
alternation** (`rg -n "Foundation|Bar" ...`, this repository's own idiom — including
its own standing Foundation scan) as a shell pipeline, false-positiving R2. Fixed by
stripping single- and double-quoted spans from the predecessor string before the pipe
test:
```
$ SCRATCH=$(mktemp -d)   # outside the repo
$ cp .github/scripts/lint-plan-assertions.sh "$SCRATCH/lint.sh"
$ # reverted, in $SCRATCH/lint.sh only: the two new gsub lines removed

$ /usr/bin/env bash "$SCRATCH/lint.sh" fixtures/good-r2-quoted-alternation.md
violation=R2 file=.../good-r2-quoted-alternation.md line=6 detail=echo "...=$?" after a command whose exit status is insensitive to the invariant; ...
violation=R2 file=.../good-r2-quoted-alternation.md line=7 detail=echo "...=$?" after a command whose exit status is insensitive to the invariant; ...
lint=fail files=1 violations=2
exit=1                                              # RED -- both quoting forms false-positive

$ .github/scripts/lint-plan-assertions.sh fixtures/good-r2-quoted-alternation.md
lint=pass files=1 violations=0
exit=0                                              # GREEN -- clean on the real, fixed script
```
Control fixture (`bad-r2-semicolon-pipe.md`, a genuine same-line pipeline —
`cat file | wc -l ; echo "n=$?"` — must still fire, confirming the quote-stripping
fix does not turn the pipe test blind):
```
$ .github/scripts/lint-plan-assertions.sh fixtures/bad-r2-semicolon-pipe.md
violation=R2 file=.../bad-r2-semicolon-pipe.md line=6 detail=echo "...=$?" after a command whose exit status is insensitive to the invariant; ...
lint=fail files=1 violations=1
exit=1
```
**Measured on the repository's 57-plan corpus** (56 exempt plans + this slice's own,
run through the pre- and post-round-2 script): R2's violation count went **12 → 8**;
all four dropped hits confirmed quoted-alternation false positives, all eight
remaining confirmed genuine (the same measurement is repeated in §7, since it is the
single strongest piece of evidence that this linter's findings are trustworthy rather
than noisy).

All four original rule drills (h/i/j/k) re-run after each fix round with identical
labels — no regression.

**Post-fix-round verification (both rounds):**
```
$ ./.github/scripts/lint-plan-assertions.sh --self-test
self_test=pass
$ ./.github/scripts/lint-plan-assertions.sh
lint=pass files=1 violations=0
$ git diff --quiet -- docs/superpowers/plans/2026-09-04-artifact-shape-enforcement.md && echo plan_untouched=yes
plan_untouched=yes
```

**Whole suite after Task 4 (both fix rounds):** 492 tests, 0 failures (no new test
function — only a `selfTestScripts` table entry).

**Commits:** `084a2f2`, `7f1ccf6`, `f2a3f74`, local only.

---

### Task 5 — the ratchet pin and the CI step

Commits `10f671c` (initial: CI step + `PlanLintTests`, 4 tests) and `f902749` (fix
round 1: measured ratchet claims, closed four vacuity gaps). Adds
`Tests/ViewportBenchmarksTests/PlanLintTests.swift`; wires
`.github/workflows/swift-ci.yml`'s "Lint plan assertions" step (deliberately
**without** the docs-only guard); adds `testPlanLintStepIsBlockingAndUnguarded` to
`WorkflowShapeTests` (13 → 14 tests).

**Guarantees added:** G12 (grandfather ratchet), G14 (CI lint step's shape, guard
absence included), G20 (`--list-exempt` reads the live array).

**Deviations:** Ruling F1 (`runScript`'s tuple label order matches `runProcess`'s
`(stdout:, stderr:, exitCode:)`, not the brief's `(exitCode:, stdout:, stderr:)` —
the brief's order does not type-check); Ruling F8 (added a `files >= 1` assertion to
`testEveryNonExemptPlanLintsClean` to close a vacuous-pass hole the brief's two
checks left open).

**Measured counts:** `PlanLintTests`: 4/0. `WorkflowShapeTests`: 14/0 (not the
brief's predicted 11 — the file already carried 13 before this task). Whole suite:
497/0 (492 + 4 + 1).

**Drill (o) — G14, guarding the lint step must redden** (added
`if: steps.change-scope.outputs.docs_only_pr != 'true'`):
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:577: error: -[ViewportBenchmarksTests.WorkflowShapeTests testPlanLintStepIsBlockingAndUnguarded] : XCTAssertNil failed: "steps.change-scope.outputs.docs_only_pr != 'true'" - Lint plan assertions: must NOT carry the docs-only guard (it carries steps.change-scope.outputs.docs_only_pr != 'true'). A plan is docs/**, so a plan-carrying PR is docs-only; guarding this step switches the linter off for exactly the PRs it exists to check. If you are adding a guard on purpose, change this test in the same commit so the decision is reviewed.
```
`Executed 14 tests, with 1 failure (0 unexpected)`. `restored=yes` (checked against
the staged index).

**Drill (l) — G12/G20, add a same-day plan to the exemption list** (appended
`"2026-09-04-artifact-shape-enforcement.md"` to `EXEMPT_PLANS`, 56 → 57 entries).
**Corrected verbatim** (the round-0 report mis-transcribed this failure; the fix
round reproduced it and recorded the actual text):
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/PlanLintTests.swift:70: error: -[ViewportBenchmarksTests.PlanLintTests testExemptListHasExactlyTheExpectedCount] : XCTAssertEqual failed: ("57") is not equal to ("56") - the exemption list holds 57 entries, want 56. It is a RATCHET: it shrinks only by a deliberate edit that also changes this number, and it must never grow — a new plan is written to the rules.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/PlanLintTests.swift:95: error: -[ViewportBenchmarksTests.PlanLintTests testNoExemptEntryIsDatedOnOrAfterTheCutoff] : XCTAssertTrue failed - 2026-09-04-artifact-shape-enforcement.md is dated on or after 2026-09-04, when the linter landed. Plans from that date on are written to the rules; the exemption set covers only plans written before it existed.
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/PlanLintTests.swift:113: error: -[ViewportBenchmarksTests.PlanLintTests testEveryNonExemptPlanLintsClean] : XCTAssertTrue failed - lint=pass reported files=0 — a zero-file run is a vacuous pass, not evidence the linter actually checked anything
lint=pass files=0 violations=0
```
(The third failure is a direct, incidental consequence of Ruling F8: re-exempting the
one non-exempt plan in the repository leaves zero files for the linter to check.)
`Executed 4 tests, with 3 failures (0 unexpected)`. `restored=yes`.

**Drill (m) — G12, exempt entry naming a plan absent from disk** (appended
`"2026-01-01-nonexistent.md"`):
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/PlanLintTests.swift:84: error: -[ViewportBenchmarksTests.PlanLintTests testEveryExemptEntryExistsOnDisk] : XCTAssertTrue failed - exemption names a plan that does not exist: 2026-01-01-nonexistent.md
```
(`testExemptListHasExactlyTheExpectedCount` also fired, incidentally, on the count
going to 57.) `Executed 4 tests, with 2 failures (0 unexpected)`. `restored=yes`.

**Drill (u) — G12/G20, delete an exempt entry (the swap hole)** (deleted
`"2026-06-13-ci-resource-optimization.md"`, 56 → 55 entries; the displaced plan still
exists on disk):
```
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/PlanLintTests.swift:70: error: -[ViewportBenchmarksTests.PlanLintTests testExemptListHasExactlyTheExpectedCount] : XCTAssertEqual failed: ("55") is not equal to ("56") - the exemption list holds 55 entries, want 56. ...
/Users/aabanschikov/swift-text-engine/Tests/ViewportBenchmarksTests/PlanLintTests.swift:35: error: -[ViewportBenchmarksTests.PlanLintTests testEveryNonExemptPlanLintsClean] : XCTAssertEqual failed: ("1") is not equal to ("0") - .github/scripts/lint-plan-assertions.sh reported violations. Fix the plan, not the rule.
```
(The displaced plan, now in the linted set, produced `lint=fail files=2
violations=18` — 18 R2/R3/R4 violations logged against
`docs/superpowers/plans/2026-06-13-ci-resource-optimization.md`.) `Executed 4 tests,
with 3 failures (0 unexpected)`. `restored=yes`; re-ran the linter afterward to
confirm byte-exact restore (`lint=pass files=1 violations=0`).

**Fix round 1 (`f902749`)** — 2 Important, 4 Minor, all in `PlanLintTests.swift` only.
- **Important 1:** measured the clean/dirty split of the 56 exempt plans
  independently (21 clean, 35 dirty — byte-identical to the reviewer's own split),
  and rewrote the file-header comment to name which of the four checks closes which
  swap direction, explicitly labelled "measured on 2026-09-04, not a stable
  invariant."
- **Important 2:** corrected the drill (l) transcript (above).
- **Minor 3:** `files=` now parsed from the `lint=pass` line specifically, not
  scanned across all of stdout.
- **Minor 4:** added non-vacuous checks (`exitCode == 0`, `!entries.isEmpty`) to two
  tests; drilled by emptying `EXEMPT_PLANS` — both
  `testEveryExemptEntryExistsOnDisk` and `testNoExemptEntryIsDatedOnOrAfterTheCutoff`
  reddened with `"--list-exempt returned no entries — an empty list would pass this
  loop vacuously"`.
- **Minor 5:** added `isDateShaped(_:)` validation before the cutoff compare; drilled
  with a leading-space-prefixed entry name (`" 2026-01-01-space-prefixed.md"`, which
  passed the old lexicographic `<` compare silently) — reddened with `"does not
  start with a YYYY-MM-DD date"`.
- **Minor 6:** added a uniqueness check (`firstDuplicate(in:)`); drilled with a
  duplicate entry (count held at 56, isolating the new assertion) — reddened with
  `"the exemption list contains a duplicate entry"`.

**Post-fix, whole suite:** 497 tests, 0 failures (unchanged by the fix round).

**Commits:** `10f671c`, `f902749`, local only.

---

### Task 6 — the conventions, and the ledger

Commits `deaddf0` (initial) and `6e310fb` (fix round 1: 5 items, 2 Important + 3
Minor, all textual). Rewrites `AGENTS.md` D-2 rule 1, adds the guarantee-inventory
convention and the three record-writing lines (D-37); amends
`docs/superpowers/debt-ledger.md` (5 status flips, 2 in-place statement amendments, 3
new rows D-40/D-41/D-42); one comment fix in `WorkflowShapeTests.swift`.

**Guarantees added:** none (per the brief's own instruction — this task is prose and
ledger bookkeeping, drilled indirectly by Task 3's `DebtLedgerShapeTests` staying
green over the edited ledger).

Full before/after text for every edit site is recorded in the task report; the
sections that matter for a future reader:
- **Status flips:** D-27, D-39, D-37, D-17 → `discharged(link to this record)`; D-9 →
  rehomed `scheduled(node-6)` (was `scheduled(slice-56)`).
- **New rows:** D-40 (three assertion classes stay unmechanized — pipe-position,
  own-HEAD assertion, plan-supplied analysis code), D-41 (`flagName` is a pinned
  third copy of every flag spelling, not a deleted one), D-42 (four residuals
  measured during this slice's own implementation — see §7).
- **D-34/D-35:** amended in place (statement grew a sentence), **status left
  unchanged** per the brief's explicit instruction — D-34 initially misworded as
  `scheduled(slice-56)`-with-narrative in the round-0 commit, corrected to bare
  `open` in the fix round (Important 2) to match D-35 exactly.

**Verification (post-fix-round):**
```
$ swift test --filter DebtLedgerShapeTests
Test Suite 'DebtLedgerShapeTests' passed at 2026-09-04 14:36:31.563.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.008 (0.008) seconds

$ ./.github/scripts/lint-plan-assertions.sh
lint=pass files=1 violations=0

$ rg -n "Foundation" Sources/TextEngineCore > /tmp/foundation_scan2.txt 2>&1; echo "exit=$?"
exit=1
$ wc -l < /tmp/foundation_scan2.txt
       0
```
Ledger row count after Task 6: 42 rows, ids `D-1`…`D-42`, contiguous (confirmed
mechanically by `testRowIdsAreUniqueAndContiguousFromOne`).

**Whole suite after Task 6:** 497 tests, 0 failures (unchanged — no new test
function).

**Commits:** `deaddf0`, `6e310fb`, local only.

## 3. Drill (c) re-run, independently, on the final tree

Task 2's own report recorded drill (c)'s **count** (84 resolver-message occurrences,
96 total failures) but not its verbatim output — the one drill this record was
instructed to reproduce independently rather than transcribe. Re-run here, on the
eleven-commit tree (after `WorkflowShapeTests` grew to 14 tests in Task 5), following
the brief's exact procedure.

**Backup, outside the repository:**
```
$ SCRATCH=/private/tmp/.../scratchpad/slice56-drillc
$ cp .github/workflows/swift-ci.yml "$SCRATCH/swift-ci.yml.bak"
backup_taken=yes
```

**Edit — append ` || true` to all twelve gate steps in one edit:**
```
$ sed -i '' 's/\(ViewportBenchmarks -- .*--gate\)$/\1 || true/' .github/workflows/swift-ci.yml
```
Confirmed all twelve `run:` lines (synthetic, variable-height, variable-height-
mutation, structural-mutation, bulk-structural-mutation, line-query, line-geometry-
query, column-query, column-geometry-query, point-query, point-geometry-query,
realistic-provider) carry the trailing `|| true`, and no other line changed.

**Run:**
```
$ swift test --filter WorkflowShapeTests > "$SCRATCH/drill-c.txt" 2>&1
$ echo "test_exit=$?"
test_exit=1
	 Executed 14 tests, with 96 failures (0 unexpected) in 0.030 (0.032) seconds
```

**Census — total failures, and distinct commands named:**
```
$ grep -c "no step in host-tests-and-benchmark-gate runs exactly" "$SCRATCH/drill-c.txt"
84
$ grep -c "want exactly 1" "$SCRATCH/drill-c.txt"
12
```
`84 + 12 = 96`, matching the `Executed 14 tests, with 96 failures` line exactly.

Distinct commands named in the 84 resolver-message failures, with per-command
multiplicity:
```
$ grep "no step in host-tests-and-benchmark-gate runs exactly" "$SCRATCH/drill-c.txt" \
    | sed -E 's/.*runs exactly `([^`]*)`.*/\1/' | sort | uniq -c
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --bulk-structural-mutation --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-geometry-query --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --column-query --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-geometry-query --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --line-query --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-geometry-query --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --point-query --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --realistic-provider --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --structural-mutation --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height --gate
   7 swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks -- --variable-height-mutation --gate
```
**All twelve distinct commands are present, each named in exactly 7 of the 84
failures.** This is the load-bearing evidence: a bare failure count is consistent
with some rows being silently unbound (e.g. one row producing 84 failures on its own
while the other eleven produce none); the uniform 7× multiplicity across all twelve
distinct commands is what rules that out.

By failing test method:
```
$ grep "error: -\[" "$SCRATCH/drill-c.txt" | grep -oE "\-\[ViewportBenchmarksTests\.WorkflowShapeTests [A-Za-z]+\]" | sort | uniq -c
  12 -[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateCarriesTheDocsOnlyGuard]
  12 -[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateIsNamedForItsSiblings]
  12 -[ViewportBenchmarksTests.WorkflowShapeTests testEachPinnedGateRunsExactlyTheExpectedCommand]
  24 -[ViewportBenchmarksTests.WorkflowShapeTests testExactlyOneStepRunsEachPinnedGate]
  12 -[ViewportBenchmarksTests.WorkflowShapeTests testGateBlockSitsBetweenItsBoundaryAnchors]
  12 -[ViewportBenchmarksTests.WorkflowShapeTests testGateStepsAppearInTheDeclaredOrder]
  12 -[ViewportBenchmarksTests.WorkflowShapeTests testNoPinnedGateIsContinueOnError]
```
Seven distinct test methods fail, six of them 12 times each (once per row) and
`testExactlyOneStepRunsEachPinnedGate` 24 times (its two assertions — `matches`
non-empty, then `matches.count == 1` — both fire per row): `6×12 + 24 = 96`. The
other seven `WorkflowShapeTests` tests (including
`testEveryGateInvocationInTheWorkflowIsPinned`, which does not call the shared
resolver and still sees all twelve `--gate` tokens since `|| true` was appended, not
a token removed) stayed green. This reproduces Task 2's original finding exactly, on
the current tree, with the full verbatim census this record was asked to capture.

**Restore, confirmed:**
```
$ cp "$SCRATCH/swift-ci.yml.bak" .github/workflows/swift-ci.yml
$ if git diff --quiet -- .github/workflows/swift-ci.yml; then echo "restored=yes"; else echo "restored=NO"; fi
restored=yes
$ swift test --filter WorkflowShapeTests 2>&1 | tail -3
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.008 (0.010) seconds
$ git status --short
(clean)
```

## 4. Invariant fingerprint (§7 of the spec, AC16)

```
$ swift build -c release --scratch-path /tmp/text-engine-host-build > build.txt 2>&1
$ echo "build_exit=$?"
build_exit=0
... Build complete! (3.84s)

$ if [ -z "$(rg -n "Foundation" Sources/TextEngineCore)" ]; then echo "foundation_scan=empty"; else echo "foundation_scan=NON_EMPTY"; fi
foundation_scan=empty
```

Twelve gated modes, each run as `swift run -c release --scratch-path
/tmp/text-engine-host-build ViewportBenchmarks -- <flag> --gate`, appended to one log:
```
--gate  --variable-height  --variable-height-mutation  --structural-mutation
--bulk-structural-mutation  --line-query  --line-geometry-query  --column-query
--column-geometry-query  --point-query  --point-geometry-query  --realistic-provider
```
```
$ grep -c 'gate=pass' gates.txt
46
$ grep -c 'gate=fail' gates.txt
0
```
**46 `gate=pass`, 0 `gate=fail`** — matches the expected count exactly.

**Checksum diff against slice 55b's baseline**, using the same D-18 filter and
extraction the prior record used. The baseline's 46 tuples are re-derivable from the
repository alone — extracted from
`docs/superpowers/verification/2026-09-03-wrap-point-query.md`'s own §5 ("The twelve
gates and the checksum baseline diff"), taking that section's **second** fenced block
(the 46-line output, not the twelve invocation commands — the first, third and fourth
blocks are the commands, the `gate_pass`/`gate_fail` summary, and the diff commands
respectively):
```
$ awk '/^## 5\. The twelve gates and the checksum baseline diff$/{p=1} p{print} p && /^## 6\./{exit}' \
    docs/superpowers/verification/2026-09-03-wrap-point-query.md \
    | awk '/^```$/{n++; next} n==3' > baseline-gates-raw.txt
$ sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' baseline-gates-raw.txt \
    | sort -u > checksums-baseline.tsv
$ wc -l checksums-baseline.tsv
      46 checksums-baseline.tsv
```
Local run, same filter and extraction:
```
$ grep -v -e 'mode=memory_shape' -e 'mode=memory_observation' gates.txt \
    | sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9-]+).*/\1|\2\t\3/p' \
    | sort -u > checksums-local.tsv
$ wc -l checksums-local.tsv
      46 checksums-local.tsv
$ DIFF="$(diff checksums-baseline.tsv checksums-local.tsv || true)"
$ if [ -z "$DIFF" ]; then echo "checksum_diff=empty"; else echo "checksum_diff=NON_EMPTY"; fi
checksum_diff=empty
```
**46/46 checksum tuples, byte-identical to slice 55b's.** This slice touches no
gated code path — per `AGENTS.md`, any movement here would be a finding — and none
was observed.

## 5. Test-count pair, delta, and enumeration (AC16)

- **Slice 55b's count (baseline, from its own record):** 480 tests, 0 failures. A
  controller-session run of `swift test` at `eacb50d`, before Task 1 was dispatched,
  agreed (480/0). That run's transcript lives in a session, not in this repository,
  so stating it as "independently re-measured" would be an assertion, not evidence —
  this repository's own rule. It is recorded here as provenance only, not offered as
  the check.
- **Re-checkable substitute, from git alone.** A static count of `func test`
  declarations across `Tests/`, at the base commit and at the last implementation
  commit (`6e310fb`, chosen over a self-referential "HEAD" per §0's convention — it
  is commit #11 in the table above), using `git grep` against a commit argument with
  no checkout needed:
  ```
  $ git grep -o "func test" eacb50d -- Tests | wc -l
       480
  $ git grep -o "func test" 6e310fb -- Tests | wc -l
       497
  ```
  **480 at `eacb50d`, 497 at `6e310fb`** — reproducing the delta of 17 from the
  repository alone, with no historical session run required. Matches the controller
  session's figure exactly; had it not, that would be the signal to investigate
  rather than adjust the prose.
- **This slice's count, measured after Task 6 (the last task that adds or removes a
  test), and re-confirmed after §3's drill restore:** **497 tests, 0 failures.**
- **Delta:** 497 − 480 = **17**.

**Enumeration, matching the delta by different arithmetic than the plan's stated
`4+4+4+4+1=17`** (the plan was not retro-edited — see Deviation F4 in §7 below):

| Task | New test functions | Running total |
|---|---|---|
| 1 | 4 (`BenchmarkModeFlagNameTests`, all new) | 484 |
| 2 | 3 net (`WorkflowShapeTests`: −1 deleted invariant 6 + 4 new invariants) | 487 |
| 3 | 5 (`DebtLedgerShapeTests`: 4 initial + 1 fix-round `testEscapeParityHandlesRunsOfBackslashes`) | 492 |
| 4 | 0 (script enrollment only, no new test function) | 492 |
| 5 | 5 (`PlanLintTests`: 4 new + `WorkflowShapeTests`' `testPlanLintStepIsBlockingAndUnguarded`) | 497 |
| 6 | 0 (prose/ledger edits only) | 497 |

`4 + 3 + 5 + 0 + 5 + 0 = 17`. Matches the measured delta exactly. Every intermediate
running total above (484, 487, 492, 492, 497, 497) matches the whole-suite count
recorded at the end of its own task's section in §2.

Per-task whole-suite tail, for cross-reference:
```
Task 1: Executed 484 tests, with 0 failures (0 unexpected)
Task 2: Executed 487 tests, with 0 failures (0 unexpected)
Task 3: Executed 492 tests, with 0 failures (0 unexpected)   (post fix round)
Task 4: Executed 492 tests, with 0 failures (0 unexpected)   (post both fix rounds)
Task 5: Executed 497 tests, with 0 failures (0 unexpected)   (post fix round)
Task 6: Executed 497 tests, with 0 failures (0 unexpected)   (post fix round)
```
Re-confirmed once more in this task, after the invariant-fingerprint run and the
drill (c) restore:
```
$ swift test --scratch-path /tmp/text-engine-host-build > slice56-t7-suite.txt 2>&1
$ grep -n "Executed .* tests, with .* failures" slice56-t7-suite.txt | tail -2
1232:	 Executed 497 tests, with 0 failures (0 unexpected) in 7.494 (7.527) seconds
1234:	 Executed 497 tests, with 0 failures (0 unexpected) in 7.494 (7.528) seconds
```

## 6. Plan linter output

```
$ ./.github/scripts/lint-plan-assertions.sh
lint=pass files=1 violations=0

$ ./.github/scripts/lint-plan-assertions.sh --self-test
self_test=pass
```
One file linted (this slice's own plan; every other plan of the 56 present on
2026-09-04 is exempt by ratchet), zero violations.

## 7. Deviations from the committed plan

The plan (`docs/superpowers/plans/2026-09-04-artifact-shape-enforcement.md`) was
**deliberately not retro-edited** — a committed plan is a historical argument, and it
is also the one file the linter itself lints, so editing it would change the thing
under test. The full reconciliation lives in
`.superpowers/sdd/2026-09-04-artifact-shape-enforcement/deviations.md`
(gitignored — not part of the repository, hence reproduced here in full so this
record is self-contained).

### Controller rulings made before execution (preflight scan)

**F1 — `PlanLintTests.runScript`'s tuple label order (Task 5).** The plan declares
`-> (exitCode: Int32, stdout: String, stderr: String)` and returns `runProcess(...)`
directly, but `ProcessSupport.runProcess` returns `(stdout: String, stderr: String,
exitCode: Int32)`. Swift treats labelled tuples with different label ORDER as
distinct types, so the plan's text is a compile error. Shipped with `runProcess`'s
label order.

**F2 — `testEachPinnedGateSitsBetweenItsAnchors` deleted (Task 2).** The plan's new
`GateStepSpec` carries only `mode` and `stepName`, but the existing invariant 6 read
`spec.flag`, `spec.afterStepName` and `spec.beforeStepName`. Deleted per spec
decision D56-3 (twelve before/after pairs replaced by one total order plus two
boundary anchors); invariants 1 and 5 now interpolate `spec.command` instead of
`spec.flag`.

**F3 — the plan's predicted `--filter WorkflowShapeTests` counts are wrong (Tasks 2,
5).** The plan predicts 10 after Task 2 and 11 after Task 5. The file already held
ten test functions before the slice, so the real figures are 13 and 14. Measured
numbers were recorded; no test was deleted to match a prediction.

**F4 — the new-test enumeration is 17, by different arithmetic than the plan's.** The
plan computes 4 + 4 + 4 + 4 + 1 = 17. F2's deletion makes Task 2 net +3, and Task 3's
fix round added a fifth test, so the true enumeration is 4 (T1) + 3 (T2) + 5 (T3) +
5 (T5) = 17 — see §5 above. Same total, different terms.

**F5 — the awk fence rule is `/^```/ && !in_heredoc` (Task 4).** As the plan writes
it, the fence rule fires before the heredoc-skip branch, so a markdown fence
delimiter inside a heredoc body toggles `in_fence` and corrupts scanner state,
contradicting the spec's own §4B. The plan itself survives the unguarded form only
because its stray delimiters come in even pairs, so the corruption cancels; the Task
4 review proved the pre-F5 script passes both the self-test and this plan
identically.

**F6 — withdrawn.** A preflight finding that `"${files[@]}"` on an empty array is
fatal under bash 3.2 with `set -u` (this project's macOS default) was tested during
the preflight scan and found not to apply as stated, so it was withdrawn before
execution rather than shipped as a ruling; there is no F6 fix in the tree. The
related empty-array hazard that **is** real — the same construct reachable when
every plan under `PLANS_DIR` is exempt — was found later, by the Task 4 review, and
is recorded there (see the Task 4 minors list in this section, below).

**F7 — `PLANS_DIR` resolves from `${BASH_SOURCE[0]}` (Task 4).** The plan sets it to
the relative literal `docs/superpowers/plans`, but `PlanLintTests` invokes the script
without setting a working directory. Uses the repository's existing idiom
(`detect-docs-only-pr.sh`, `cross-target-compile.sh`).

**F8 — `testEveryNonExemptPlanLintsClean` asserts `files >= 1` (Task 5).** The plan's
two checks (exit 0, `stdout.contains("lint=pass")`) are both satisfied by
`lint=pass files=0 violations=0` — a linter that linted nothing. The added assertion
closes that, and fired for real during drill (l).

**F9 — the plan document was not retro-edited (Task 4).** This document is the
reconciliation instead.

### A defect the implementer found, not the reviews

**The self-test's cleanup trap (Task 4).** The plan writes `trap 'rm -rf "$dir"'
EXIT` inside `run_self_test`, where `dir` is `local`. Single quotes defer expansion
to when the EXIT trap fires — after the function returned and `local dir` went out
of scope — so under `set -u` the script printed `self_test=pass` and THEN exited 1.
Reproduced independently in a five-line script. Shipped double-quoted, later replaced
by a single `trap cleanup EXIT` in `main`.

### Fixes made in review rounds (beyond the plan's text)

**Task 3, one round — two Important.** (1) `unescapedPipeCount`/`columns(of:)`'s
one-character lookback miscounted `\\|` as escaped; replaced with an odd-parity
backslash-run rule. (2) `XCTAssertEqual(numbers, Array(1...numbers.count))` traps on
an empty id set (`Array(1...0)` is a Swift fatal error); guarded. A fifth test,
`testEscapeParityHandlesRunsOfBackslashes`, covers the parity rule.

**Task 4, two rounds — five Important, four Minor.** Full RED-before/GREEN-after
evidence is inlined in §2's Task 4 section above (fence-in-heredoc, same-line `;`,
own-prescribed-remedy, unterminated heredoc, unrecognized flag, here-string) — not
pointed at the gitignored Task 4 report. **Measured on the repository's 57-plan
corpus:** round 2's quote-stripping fix moved R2's violation count from **12 → 8**;
all four dropped hits confirmed quoted-alternation false positives, all eight
remaining confirmed genuine — the strongest single piece of evidence that this
linter's findings are trustworthy rather than noisy.

**Task 5, one round — two Important, four Minor.** Summarized in §2's Task 5 section
above.

**Task 6, one round — two Important, three Minor.** (1) The rewritten D-2 rule 1
claimed the linter "enforces **this rule** mechanically (R1)", but R1 matches only
`PIPESTATUS` — the headline pipe-position ban is not mechanized, and D-40 (added in
the same commit) already says so; narrowed to the `PIPESTATUS` half. (2) D-34's
status still read `**scheduled(slice-56)**` after slice 56 shipped; set to `open` to
match D-35. Minors: D-27's discharge re-attributed to the correct mechanism
(exact-payload-equality catches the "|| true on an existing step" drill; the
whole-file census catches a wholly unpinned thirteenth step — two different holes,
previously conflated); a ledger status-vocabulary line gained `scheduled(node-N)`;
three stale text bits repaired (D-9's stray `\|`, a `median\| max` typo, D-17's stale
`AGENTS.md:639` line reference replaced with a section reference).

### Controller additions to Task 6 (routed from the Task 2 review)

**Addition A.** `AGENTS.md`'s `WorkflowShapeTests.swift` paragraph described the
mechanism Task 2 replaced (the old two-row table, the twelve before/after anchor
pairs) — rewritten to the shipped design, clause-by-clause audited against source.

**Addition B.** A stale comment analogy ("mirrors how a gate joins `pinnedGateSteps`
by hand above") corrected to match Task 2's exact-payload-equality design.

**Addition C.** Ledger row **D-42** (P3), bundling four residuals measured during
this slice's own implementation and laddered explicitly per the spec's own rule for
exactly this situation: (a) the exemption ratchet's cutoff check is a filename
compare, not a date parse — only 21 of 56 exempt plans lint clean on their own, so
for those a swap is caught by the cutoff check alone; (b) R3 does not recognize
`declare -r`, `readonly`, or `VAR+=` as assignments; (c) R2 misses `echo "…=$?"` when
a `;` sits inside a quoted `sed`/`awk` program on the same line (a miss, not a false
positive — the acceptable direction, per the coordinator's explicit "do not trade a
miss for a false positive" instruction in Task 4's fix round 2); (d) gate-block
contiguity is pinned by neither the total order nor the two boundary anchors (the old
per-row anchor form did not pin it either — not a regression, but the retired
comment's "contiguous" claim implied coverage that never existed).

### Post-review findings, addressed in the final fix wave

A whole-branch review returned one Important and six Minor findings against the tree
this record otherwise describes. All seven were addressed in one fix-wave commit; the
two below are additions to artifacts §7 already covers, recorded here rather than
retro-editing the sections above (same rationale as F9: this record does not rewrite
history, it appends the reconciliation).

**R4 was INERT on `## Task N:` headings (Important).** The task-heading pattern
`lint-plan-assertions.sh` used to enter task tracking was `/^### Task [0-9]+:/` —
three hashes only. A plan whose task headings use two hashes never entered task
tracking, `check_task()` was never called, and R4 emitted nothing while the run
reported `lint=pass`. Measured: **31 of the repository's 57 plans use `## Task N:`**.
Widened to `/^#{2,3} Task [0-9]+:/` (two or three hashes; a single `#` stays excluded
as a document title). Drilled with a new `bad-r4-hash2.md` self-test fixture (a
`## Task 1:` section with no `**Guarantees added:**` block, expected rule `R4`),
proven live by reverting the widened pattern on a scratch copy outside the repo and
confirming the committed `--self-test` reddens naming that fixture
(`self_test=fail label=bad_r4-hash2_exit`) before restoring the widened pattern and
seeing `self_test=pass` again. `./.github/scripts/lint-plan-assertions.sh` over the
repository still prints `lint=pass files=1 violations=0` afterward, since this
slice's own plan (the only non-exempt file) already carries `###` headings.

**R3's assignment recognizer was `^`-anchored, producing a false positive on correct
shell (Minor, but load-bearing).** `mkdir -p /tmp/x && SCRATCH=/tmp/x` followed by
`echo "$SCRATCH"` reported `violation=R3`, telling the author their variable expands
empty when it does not. The recognizer now splits each line on `&&`, `||`, `;` and
`(` and re-runs the same anchored pattern against every resulting segment — strictly
additive, never removing a prior match. Covered by a new `good-r3-assignment-after-and.md`
self-test fixture; proven live by reverting the change on a scratch copy and
confirming the fixture then false-positives (`violation=R3`) before the fix restores
a clean lint. `declare -r`, `readonly` and `VAR+=` were deliberately **not** added —
the design document enumerates the recognizer list as closed — and stay recorded as
residual (b), below.

**`testEachPinnedGateRunsExactlyTheExpectedCommand` was tautological (Minor).** It
resolved its step set through `steps(for:in:)`, which already filters on the exact
payload equality the test's own body re-asserted — so the test's own
`XCTAssertEqual` could never fail; any drift reddened via `steps(for:in:)`'s
`XCTAssertFalse(matches.isEmpty)` instead. Rewritten to resolve the step by **name**
against the unfiltered host-job step list (via the existing `stepNamed(_:in:)`
helper), then assert that step's payload equals the expected command — the exact
dual of `testEachPinnedGateIsNamedForItsSiblings` (which resolves by payload and
asserts the name), so together the two pin the name↔payload pairing in both
directions. A missing name now fails with an explicit `XCTFail`, not a silent skip.
Drilled: appended ` || true` to the "Run synthetic benchmark gate" step's `run:`
payload in `swift-ci.yml` (backed up outside the repo first), confirmed the test
reddens from its own assertion with a want/got message, restored from the backup,
confirmed `git diff --quiet -- .github/workflows/swift-ci.yml`, and confirmed
`--filter WorkflowShapeTests` is still 14/0.

**`AGENTS.md`'s `## CI` section never mentioned the plan-lint step (Minor).** The
host-job step list and the docs-only paragraph both predated Task 1's CI wiring.
Added the lint step to the step list (noting it is, uniquely among the host job's
steps, not guarded by `docs_only_pr`) and one sentence to the docs-only paragraph:
a docs-only PR that adds or edits a non-exempt plan can now fail CI on that step
where it previously always passed.

**§7 (this section) skipped F6 with no note (Minor).** See the new F6 entry inserted
between F5 and F7 above: F6 was a preflight finding, about bash 3.2's handling of
`"${files[@]}"` on an empty array, that was tested during the preflight scan and
found not to apply as stated, so it was withdrawn before execution. The related
empty-array hazard that **is** real was found later, by the Task 4 review, and was
already recorded in this section's Task 4 minors list.

**Two further residuals, recorded rather than fixed (Minor):** (e) R1–R3 are scoped
to `bash`/`sh` fences only, so a plan using a `shell`, `zsh` or `console` fence gets
them as a silent no-op — the same shape as the R4 heading defect one level down. Not
widened: the spec's AC7 states the scope explicitly, and a fence-language census over
all 57 plans found none of those spellings in use (bash 1391, swift 443, text 320,
yaml 68, markdown 62, diff 16, json 10, sh 8, awk 5, ruby 4). (f) The spec's §4B R3
allow-list (`$HOME, $PWD, $TMPDIR, $PATH, $USER, $GITHUB_*, $RUNNER_*` plus awk
built-ins) is narrower than what shipped (the script also allows `SHELL`, `IFS`,
`OLDPWD`, `RANDOM`, `SECONDS`, `PIPESTATUS`, and the `BASH_` prefix) — benign and
necessary (`PIPESTATUS` must be allow-listed so R3 does not double-report what R1
reports), but recorded rather than resolved by editing the spec, the slice's binding
authority, written before execution. Both appended to ledger row **D-42**, which read
"Six residuals" at that point and still carried exactly six unescaped pipes (verified
with the same parity rule `DebtLedgerShapeTests` uses). The post-record validation pass
below adds four more, taking the row to "Ten residuals".

After the fix wave: `swift test` — 497 tests, 0 failures;
`./.github/scripts/lint-plan-assertions.sh` — `lint=pass files=1 violations=0`;
`--self-test` — `self_test=pass`; `--filter DebtLedgerShapeTests` — 5/0;
`--filter WorkflowShapeTests` — 14/0. The four original rule drills (h, i, j, k —
G8/R1, G9/R2, G10/R3, G11/R4 neutralized in turn) were re-run against the final tree
and every one reddened as before, since Fixes 1 and 3 edited the very awk rules they
neutralize.

### The first hosted run turned red, and what it caught

The fix wave above widened R4's heading pattern to `/^#{2,3} Task [0-9]+:/` and was
verified on macOS only. **The interval expression `{2,3}` is not honoured by the awk in
the `swift:6.2.1-bookworm` container**, so on the first hosted run the heading matched
nothing at all, `in_task` was never set, `check_task()` was never called, and R4 was
inert for **both** heading forms — the very defect the fix wave existed to repair,
reintroduced one level down and on the other platform.

The failure is isolated by construction, not by inspection: line 185 was the only
interval expression in any of the five scripts, and the heading rule is the only place
`in_task` is assigned 1. The self-test's `bad-r4.md` fixture returned `rc=0` with **zero**
`violation=` lines — no violation at all, not even the "task has no `**Guarantees
added:**` block" branch — which is possible only if `check_task()` never ran.

Hosted reading, run `33882695798` on commit `7aa2879`:
```
ScriptSelfTestTests.testEveryScriptSelfTestPasses: XCTAssertEqual failed: ("1") is not
  equal to ("0") - self-test exited non-zero
  script: .../.github/scripts/lint-plan-assertions.sh
  exit: 1
  self_test=fail label=bad_r4_exit
    expected: [1]
    actual:   [0]
 Executed 497 tests, with 3 failures (0 unexpected)
```

**Two facts worth keeping.** First, the CI step `Lint plan assertions` printed
`lint=pass files=1 violations=0` on that same run — a pass that was VACUOUS for R4. The
only thing that caught the defect was `--self-test` driven from `swift test`
(`ScriptSelfTestTests`), which is precisely the redundancy D56-6 argued for: a linter
that only ever runs as a linter cannot report that one of its rules stopped existing.
Second, R1–R3's fixtures all stayed red on that run; the self-test's rule-by-rule loop is
what made the blast radius readable at a glance.

**Fix.** `#{2,3}` → `###?` — two hashes plus an optional third, plain POSIX ERE, no
interval expression. Locally a no-op (macOS awk honoured both spellings), on the CI awk
the difference between a live rule and a silent one. The file now states the standing
rule beside the pattern: POSIX-portable ERE only, because authoring runs on macOS awk and
enforcement runs on Linux awk, and the two disagree *silently* rather than erroring. The
`bad-r4.md` / `bad-r4-hash2.md` fixture pair is the portability guard — whichever awk runs
the script, a heading spelling it cannot see shows up as a bad-r4 fixture that refuses to
fail. Verified after the fix: `--self-test` → `self_test=pass`; the repository lint →
`lint=pass files=1 violations=0`; `## Task 1:` and `### Task 1:` each still produce
`violation=R4`, `#### Task 1:` and `# Task 1:` still produce none.

**No mechanical guard prevents the next non-portable construct** — laddered as D-42 (g).

### Post-record validation pass — three further residuals

Found while re-checking this record against the tree, and laddered onto D-42 rather than
fixed, since each would change a scanner or recognizer semantics the spec fixes as closed:
(h) `$((1 << BITS))` is read as a heredoc opener with tag `BITS`, abandoning the rest of
the file with a wrong diagnosis (loud, exit 1); (i) the fence-language census behind the
`bash`/`sh` scope omits **unlabelled** fences, of which the corpus carries roughly 205 —
measured impact today is 10, all documentation snippets; (j) R1 fires on a shell *comment*
that merely mentions `PIPESTATUS`.

One measured claim was **corrected, not laddered**: `PlanLintTests.swift`'s header quoted a
"35 of 56 dirty / 21 clean" split of the exempt set and named
`2026-08-09-wrap-row-query.md` as an example of a clean plan. The fix wave's R4 heading
widening — two commits later, on this same branch — moved every exempt plan into the dirty
set; re-measured, the split is **56 dirty, 0 clean**, and the named plan reports eight
violations. The comment now carries the re-deriving command instead of a number, and says
why: this is the same defect class the slice exists to end, committed by the slice itself.

## 8. Hosted evidence — PARTIAL, outstanding

One hosted run exists and is **red**; the green PR-head and post-merge readings AC17 asks
for do not yet exist. The table below is in the "commit → run id" shape the convention this
slice writes (§2 of `AGENTS.md`'s `Conventions that matter`, added by Task 6 / D-37)
requires — a row per head SHA, never a bare run id, never "the current HEAD":

| Commit (SHA) | Context | Run type | Run id | Step-level reading | Notes |
|---|---|---|---|---|---|
| `7aa2879` | Host tests and benchmark gate | PR-head (#138) | 33882695798 | **fail** — `Run host tests`: 497 tests, 3 failures, all `ScriptSelfTestTests.testEveryScriptSelfTestPasses`; `Lint plan assertions`: `lint=pass files=1 violations=0` (vacuous for R4) | the `#{2,3}` interval-regex defect above; no gate step reached |
| `7aa2879` | iOS cross-target compile | PR-head (#138) | 33882695798 | pass | unaffected by the defect |
| `7aa2879` | WASM cross-target compile | PR-head (#138) | 33882695798 | pass | unaffected by the defect |
| *(pending)* | Host tests and benchmark gate | PR-head | | | after the `###?` fix |
| *(pending)* | Host tests and benchmark gate | post-merge push | | | |
| *(pending)* | iOS cross-target compile | post-merge push | | | |
| *(pending)* | WASM cross-target compile | post-merge push | | | |

**AC17 is not discharged.** When the remaining evidence is gathered it belongs on a
separate `slice-56-hosted-proof` branch (per D-37, added by Task 6, discharged by this same
convention) — not appended to this commit — because a record cannot carry facts about its
own branch: the commit that records a fact changes it. The red row above is exempt from
that hazard for the reason the convention gives: it is keyed to a SHA that is already
in the past, so it stays re-checkable no matter what lands after it.
