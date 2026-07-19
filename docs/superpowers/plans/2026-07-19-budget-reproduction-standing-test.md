# Budget Reproduction Standing Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one standing test that re-derives every gate budget from the windowed corpus via `derive-gate-budgets.sh` and asserts byte-equality with the committed literals, making "every budget is derived, never hand-typed" build-enforced.

**Architecture:** A new `XCTest` method in `Tests/ViewportBenchmarksTests/GateFloorTests.swift` shells out (once, all modes) to the sanctioned derivation script over the committed corpus, parses its `budget_p95=`/`budget_p99=` output, and cross-checks each value against the committed literal from the existing `everyGatedBudget()` registry. It reuses the file's existing `runProcess`, `repositoryRoot`, `corpusPath`, and `everyGatedBudget()` — no new helper of substance beyond a small stdout parser. Purely additive: all 46 committed budgets already reproduce, so no engine/provider/budget/corpus/script change.

**Tech Stack:** Swift 6.0, XCTest, `Foundation.Process` (already imported and used in this test file for `testWindowSelectionMatchesDeriveScript`), bash + POSIX `awk`/`sort`/`cut`/`tail`/`head` (the derivation script).

## Global Constraints

Copied verbatim from the spec; every task's requirements implicitly include these.

- **No change to `Sources/TextEngineCore` or `Sources/TextEngineReferenceProviders`.** Expected diff there: **zero lines**. Verify with `git diff --name-only main -- Sources/TextEngineCore Sources/TextEngineReferenceProviders` → empty.
- **No change to any budget literal, the corpus, or `.github/scripts/derive-gate-budgets.sh`.** No harvest, no re-derivation.
- **All eleven `--gate` checksums stay byte-identical** to the Slice 43 baseline recorded in `docs/superpowers/verification/2026-07-18-absolute-product-budget.md`.
- **Foundation-free core preserved:** `rg -n "Foundation" Sources/TextEngineCore` must be empty. The test-target `import Foundation` is pre-existing (this file already imports it to read the corpus); nothing crosses into the core.
- **Test co-located in `GateFloorTests.swift`**, reusing `runProcess`, `repositoryRoot()`, `corpusPath`, and `everyGatedBudget()` — do not duplicate them, do not de-privatize.
- **Conventional-commit prefixes** (`test:`, `docs:`); one logical step per commit.
- **Branch:** `slice-44-budget-reproduction-standing-test` (already created; the design commit `168392d` is on it).

---

### Task 1: The reproduction standing test

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (add one file-private parser function and one `XCTestCase` method; no existing code changes)

**Interfaces:**
- Consumes (all already defined in this file):
  - `runProcess(_ executableURL: URL, _ arguments: [String], stdin: String) throws -> (stdout: String, stderr: String, exitCode: Int32)`
  - `repositoryRoot() -> URL`
  - `corpusPath` = `"docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv"` (file-private `let`)
  - `everyGatedBudget() -> [GatedBudget]`, where `struct GatedBudget { let key: String; let mode: BenchmarkMode; let p95: Int64; let p99: Int64 }` and `key == "\(mode.outputName)|\(scenarioName)"` (identical to the corpus/derive-output key spelling)
- Produces: nothing consumed by later tasks (a standalone test).

- [ ] **Step 1: Capture the pre-condition (evidence the slice is purely additive)**

Run from the repo root:

```bash
./.github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv | wc -l
```

Expected: `46` (one line per gated scenario). This confirms the script emits exactly the 46 gated scenarios, so the bijective cardinality assertion below holds and no re-derivation is needed. Keep this output for the verification record (Task 3).

- [ ] **Step 2: Add the stdout parser**

Add this file-private function to `GateFloorTests.swift`, placed just above the `struct GatedBudget` declaration (near the other corpus helpers):

```swift
// Parse derive-gate-budgets.sh stdout into key -> (p95, p99). Each scenario line is
// `<key>  n=... p95[...] p99[...] budget_p95=<int> budget_p99=<int> margin...` (the key is
// %-46s-padded, so field 0 is the key with no embedded spaces, and the two budgets are
// whitespace-delimited `budget_p9x=<int>` tokens). A line missing either token is skipped:
// combined with the "every gated key must be present" assertion in the test, that turns any
// rename/removal of those output tokens into a loud missing-key failure, not a silent pass --
// so the test transitively pins the derive script's output shape as well as its arithmetic.
private func derivedBudgets(fromScriptOutput output: String) -> [String: (p95: Int64, p99: Int64)] {
    var result: [String: (p95: Int64, p99: Int64)] = [:]
    for line in output.split(separator: "\n") {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let key = fields.first else { continue }
        var p95: Int64?
        var p99: Int64?
        for field in fields {
            if field.hasPrefix("budget_p95=") {
                p95 = Int64(field.dropFirst("budget_p95=".count))
            } else if field.hasPrefix("budget_p99=") {
                p99 = Int64(field.dropFirst("budget_p99=".count))
            }
        }
        if let p95, let p99 {
            result[String(key)] = (p95: p95, p99: p99)
        }
    }
    return result
}
```

- [ ] **Step 3: Add the failing/guard test method**

Add this method inside `final class GateFloorTests: XCTestCase`, immediately after `testWindowSelectionMatchesDeriveScript` (so it sits with the other cross-language derive-script pins):

```swift
// The arithmetic analog of the two window pins. Those cross-check the window SELECTION
// (which run ids) against Swift; this cross-checks the DERIVATION ARITHMETIC (8xmedian /
// 3xmax / round_up_2sf, plus the p99 2xbudget_p95 floor) by asserting every committed budget
// literal byte-equals what derive-gate-budgets.sh -- "the only sanctioned source of a budget"
// -- actually emits from the committed corpus. It closes the last within-band-looser residual
// in the regression recipe: a budget that has drifted looser than the recipe now produces is
// invisible to the floor test whenever the 8xmedian term governs (the floor sees only 3xmax),
// but reddens here. Shells out rather than re-implementing the recipe, so it also transitively
// guards the script's awk and its output format on both BSD-awk(local) and Linux-awk(CI).
func testEveryCommittedBudgetReproducesFromCorpus() throws {
    let scriptURL = repositoryRoot()
        .appendingPathComponent(".github/scripts/derive-gate-budgets.sh")
    let corpusURL = repositoryRoot().appendingPathComponent(corpusPath)
    let env = URL(fileURLWithPath: "/usr/bin/env")

    // The script reads the corpus from its file argument, not stdin; empty stdin is inert.
    let result = try runProcess(env, ["bash", scriptURL.path, corpusURL.path], stdin: "")
    XCTAssertEqual(
        result.exitCode, 0,
        "derive-gate-budgets.sh exited \(result.exitCode); stderr: \(result.stderr)")

    let derived = derivedBudgets(fromScriptOutput: result.stdout)
    let budgets = everyGatedBudget()

    // Non-vacuity + bijective cardinality (Decision 3). Equality (not >=) also catches the
    // REVERSE drift: a scenario that entered the corpus/derivation but is not a registered
    // gated budget. Relax to `derived.count >= budgets.count` only if a non-gated
    // (e.g. observation-only) row is ever CONSCIOUSLY added to the corpus.
    XCTAssertFalse(derived.isEmpty)
    XCTAssertEqual(
        derived.count, budgets.count,
        "derive-gate-budgets.sh emitted \(derived.count) scenarios but everyGatedBudget() "
            + "registers \(budgets.count) — a corpus scenario is unregistered (or vice versa). "
            + "If a non-gated observation row was added on purpose, relax this to >=.")

    for budget in budgets {
        guard let d = derived[budget.key] else {
            XCTFail("\(budget.key): gated, but derive-gate-budgets.sh emitted no budget for it")
            continue
        }
        XCTAssertEqual(
            d.p95, budget.p95,
            "\(budget.key): committed p95 budget \(budget.p95) != \(d.p95) re-derived from the "
                + "corpus — the literal no longer reproduces (budget_stale, not an engine "
                + "regression). Re-derive with .github/scripts/derive-gate-budgets.sh and re-commit.")
        XCTAssertEqual(
            d.p99, budget.p99,
            "\(budget.key): committed p99 budget \(budget.p99) != \(d.p99) re-derived from the "
                + "corpus — the literal no longer reproduces (budget_stale, not an engine "
                + "regression). Re-derive with .github/scripts/derive-gate-budgets.sh and re-commit.")
    }
}
```

- [ ] **Step 4: Run the new test — expect PASS (budgets already reproduce)**

Run:

```bash
swift test --filter GateFloorTests/testEveryCommittedBudgetReproducesFromCorpus 2>&1 | tail -20
```

Expected: the test **passes** (`Test Case '-[ViewportBenchmarksTests.GateFloorTests testEveryCommittedBudgetReproducesFromCorpus]' passed`). A guard over already-satisfied state is green on introduction; Step 5 proves it is not vacuously green.

- [ ] **Step 5: Prove the guard is live (break → red → revert → green)**

This is the red-first evidence for a guard test. Temporarily perturb one committed budget so the literal no longer reproduces:

```bash
# Bump line_query uniform_1k p99 budget 440 -> 450 (still clears the floor and p99>=2*p95,
# so ONLY the reproduction test should redden -- isolating it as the live guard).
sed -i.bak 's/p95BudgetNanoseconds: 220, p99BudgetNanoseconds: 440/p95BudgetNanoseconds: 220, p99BudgetNanoseconds: 450/' Sources/ViewportBenchmarks/LineQueryBenchmark.swift
swift test --filter GateFloorTests/testEveryCommittedBudgetReproducesFromCorpus 2>&1 | tail -25
```

Expected: **FAIL**, with the message `line_query|uniform_1k: committed p99 budget 450 != 440 re-derived from the corpus …`. Then revert and confirm green:

```bash
mv Sources/ViewportBenchmarks/LineQueryBenchmark.swift.bak Sources/ViewportBenchmarks/LineQueryBenchmark.swift
swift test --filter GateFloorTests/testEveryCommittedBudgetReproducesFromCorpus 2>&1 | tail -5
```

Expected: **PASS**, and `git status` shows the tree clean under `Sources/ViewportBenchmarks/` (the `.bak` was renamed back over the original). Record the RED and GREEN transcripts for Task 3; do not commit the break.

- [ ] **Step 6: Run the full test file to confirm nothing else moved**

Run:

```bash
swift test --filter GateFloorTests 2>&1 | tail -8
```

Expected: all `GateFloorTests` pass (the prior suite plus the one new test). No other test reddened by the addition.

- [ ] **Step 7: Commit**

```bash
git add Tests/ViewportBenchmarksTests/GateFloorTests.swift
git commit -m "$(cat <<'EOF'
test: reproduce every committed gate budget from the corpus

Add testEveryCommittedBudgetReproducesFromCorpus: shell out to
derive-gate-budgets.sh over the committed corpus and assert every gated
budget literal byte-equals the re-derived budget_p95/budget_p99. Cross-checks
the derivation ARITHMETIC the way the window pins cross-check the SELECTION,
closing the last within-band-looser residual in the regression recipe. Non-
vacuity + bijective cardinality (46 == everyGatedBudget().count); a launch or
exit failure is a loud XCTFail, never a skip. All 46 literals reproduce today,
so this is purely additive.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Documentation and P3 folds

**Files:**
- Modify: `AGENTS.md` (record the reproduction guard in `## Gate budgets` and the `GateFloorTests` package-layout bullet; fold P3 #2 — the "two failure reasons" clause)
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (fold P3 #1 — soften the frozen `580us / 2.87x` figure in one comment)

**Interfaces:**
- Consumes: the test name `testEveryCommittedBudgetReproducesFromCorpus` from Task 1.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Record the reproduction guard in AGENTS.md `## Gate budgets`**

In `AGENTS.md`, find the paragraph beginning `**Never hand-type a budget.**` (currently line 421). Insert a new paragraph immediately after it (before `**When an optimization trips the ceiling …**`):

```markdown
**Every committed budget is now build-enforced to reproduce.**
`GateFloorTests.testEveryCommittedBudgetReproducesFromCorpus` shells out to
`derive-gate-budgets.sh` over the committed corpus and fails `swift test` if any
committed `p95BudgetNanoseconds` / `p99BudgetNanoseconds` literal no longer byte-equals
the re-derived budget — so "derived, never hand-typed" is a standing invariant, not a
per-slice discipline. This is the arithmetic analog of the two window pins (which
cross-check the *selection*). A red here after a harvest is `budget_stale` — re-derive
that mode and re-commit; it is not an engine regression. `round_up_2sf` gives natural
hysteresis, so most small median/max moves round to the same budget and do not trip it.
```

- [ ] **Step 2: Add the reproduction test to the AGENTS.md `GateFloorTests` bullet**

In `AGENTS.md`, in the `GateFloorTests.swift` package-layout bullet, find the sentence that ends (currently ~line 133-134):

```
  run-id set — so not just the N constant but the selection itself cannot silently
  diverge.
```

Append immediately after it (same bullet, new sentence):

```
  It also carries `testEveryCommittedBudgetReproducesFromCorpus`, the arithmetic analog of
  those two selection pins: it runs `derive-gate-budgets.sh` over the committed corpus and
  asserts every committed budget literal byte-equals the re-derived `budget_p95`/`budget_p99`
  (with a bijective `derived.count == everyGatedBudget().count` cardinality check), so a
  committed budget that no longer reproduces from the corpus fails the build.
```

- [ ] **Step 3: Fold P3 #2 — the "two failure reasons" clause now undercounts**

In `AGENTS.md`, replace the paragraph at (currently) lines 431-434:

```markdown
**The two failure reasons are opposite instructions**, and the gate says
which one applies: `reason=budget_exceeded` means the code got slower — fix
the code. `reason=budget_stale` means the budget no longer reflects reality —
re-derive it.
```

with:

```markdown
**The three failure reasons are distinct instructions**, and the gate says
which one applies: `reason=budget_exceeded` means the code got slower — fix
the code. `reason=budget_stale` means the budget no longer reflects reality —
re-derive it. `reason=budget_absolute_exceeded` means a frame-hot-path op blew
the fixed 60 FPS ceiling — fix the code/architecture, never loosen the ceiling.
```

- [ ] **Step 4: Fold P3 #1 — soften the frozen `580us / 2.87x` figure**

In `Tests/ViewportBenchmarksTests/GateFloorTests.swift`, in the comment above `testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling`, replace (currently lines 362-364):

```swift
    // at runtime, so the two agree. Binding scenario: structural_mutation|1m (580us,
    // 2.87x under). This is the check that would have caught the original
    // bulk_structural_mutation batch_4096 collision (budgets 3ms / 5.8ms > the ceiling).
```

with:

```swift
    // at runtime, so the two agree. The binding scenario is the slowest frame-hot-path p99
    // budget (currently structural_mutation|1m); its live margin under the ceiling is what
    // this test enforces, so read the assertion rather than a number that rots here. This is
    // the check that would have caught the original bulk_structural_mutation batch_4096
    // collision (its budgets exceeded the ceiling).
```

- [ ] **Step 5: Build the test target to confirm the comment edit didn't break compilation**

Run:

```bash
swift build --build-tests 2>&1 | tail -5
```

Expected: builds cleanly (comment-only change to the Swift file; Markdown changes don't affect the build).

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md Tests/ViewportBenchmarksTests/GateFloorTests.swift
git commit -m "$(cat <<'EOF'
docs: record budget-reproduction guard; fold P3 #1/#2

AGENTS.md: document testEveryCommittedBudgetReproducesFromCorpus in
## Gate budgets and the GateFloorTests bullet; correct the "two failure
reasons" clause to three (budget_absolute_exceeded added in Slice 43).
GateFloorTests.swift: soften the frozen 580us/2.87x figure in the
frame-hot-path ceiling comment (keep the structural claim, drop the number
that rots).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Full verification and verification record

**Files:**
- Create: `docs/superpowers/verification/2026-07-19-budget-reproduction-standing-test.md`

**Interfaces:**
- Consumes: the committed work of Tasks 1-2.
- Produces: the verification record; no code consumed by later tasks.

- [ ] **Step 1: Full test suite**

Run:

```bash
swift test 2>&1 | tail -15
```

Expected: all tests pass, count increased by exactly one versus the Slice 43 baseline (Slice 43 recorded **310**; expect **311**). Capture the pass/fail tally line. (Note: `swift test` also prints a "0 tests in 0 suites" line for the empty Swift Testing harness — not a failure.)

- [ ] **Step 2: Release build**

Run:

```bash
swift build -c release 2>&1 | tail -3
```

Expected: `Compiling`/`Build complete` with no errors.

- [ ] **Step 3: Foundation-free scan**

Run:

```bash
rg -n "Foundation" Sources/TextEngineCore; echo "exit=$?"
```

Expected: no matches, `exit=1` (rg exits non-zero when nothing matches) — the core stays Foundation-free.

- [ ] **Step 4: Synthetic gate still passes**

Run:

```bash
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -5
```

Expected: `gate=pass`.

- [ ] **Step 5: Byte-identity of the eleven gate checksums**

Run each gated mode and capture its `checksum=` lines, then compare to the Slice 43 baseline recorded in `docs/superpowers/verification/2026-07-18-absolute-product-budget.md`:

```bash
for mode in "" "--realistic-provider" "--variable-height" "--variable-height-mutation" \
  "--structural-mutation" "--bulk-structural-mutation" "--line-query" "--line-geometry-query" \
  "--column-query" "--column-geometry-query" "--point-query" "--point-geometry-query"; do
  echo "=== ${mode:-default} ==="
  swift run -c release ViewportBenchmarks -- $mode --gate 2>&1 | grep -o 'checksum=[0-9a-fx]*'
done
```

Expected: every `checksum=` value is byte-identical to the Slice 43 baseline (this slice changed no workload). Note: `--realistic-provider --gate` is accepted but CI never runs it with `--gate`; running it locally here is only to confirm its checksum is unchanged.

- [ ] **Step 6: Confirm the diff scope**

Run:

```bash
git diff --name-only main
git diff --name-only main -- Sources/TextEngineCore Sources/TextEngineReferenceProviders \
  .github/scripts/derive-gate-budgets.sh docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
```

Expected: the first lists only `Tests/ViewportBenchmarksTests/GateFloorTests.swift`, `AGENTS.md`, and the three slice docs (spec, plan, verification). The second is **empty** — no engine, provider, script, or corpus path, and no budget literal (budget literals live under `Sources/ViewportBenchmarks/*Benchmark.swift` / `SyntheticBenchmarks.swift` / `BenchmarkModels.swift`, none of which appear in the first list).

- [ ] **Step 7: Write the verification record**

Create `docs/superpowers/verification/2026-07-19-budget-reproduction-standing-test.md` capturing, with actual command output:

- The pre-condition (Task 1 Step 1): the script emits 46 scenarios; all 46 literals reproduce.
- The new test green inside full `swift test` (Step 1), with the 311-tests tally.
- The **guard-is-live** demonstration (Task 1 Step 5): the RED transcript (`line_query|uniform_1k … != 440`), the revert, and the GREEN transcript, with a note that the break was never committed and the tree returned byte-clean.
- `swift build -c release` clean; the Foundation-free scan empty; synthetic `--gate` `gate=pass`.
- The eleven gate checksums byte-identical to the Slice 43 baseline (Step 5), naming the baseline doc.
- The diff scope (Step 6): no engine/provider/script/corpus/budget-literal path.
- A **Hosted CI — Pending** placeholder for the PR-head and post-merge push run IDs, read at step level, to be filled in the AC7 hosted-proof follow-up (matching the Slices 24-43 pattern of anchoring proof in the merged-code `push` run).

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/verification/2026-07-19-budget-reproduction-standing-test.md
git commit -m "$(cat <<'EOF'
docs: record slice 44 local verification

Full swift test (311/0), release build, Foundation-free scan, synthetic gate
pass, eleven gate checksums byte-identical to the Slice 43 baseline, and the
guard-is-live break->red->revert->green demonstration for the reproduction
test. Hosted CI pending (AC7 follow-up).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**

- Reproduction test shelling out to the script (spec Decision 1, AC1) → Task 1 Steps 2-3.
- Non-vacuity + bijective cardinality (spec Decision 3, AC2) → Task 1 Step 3 (`XCTAssertFalse(derived.isEmpty)` + `XCTAssertEqual(derived.count, budgets.count)`).
- One invocation over all modes, keyed lookup (spec Decision 2) → Task 1 Step 3 (single `runProcess` with no mode arg; `derived[budget.key]`).
- Output-format transitive pin (spec Decision 2 bonus) → Task 1 Step 2 parser (skip-on-missing-token) + Step 3 present-key assertion.
- Guard-is-live demonstration (spec Testing Strategy 3, AC2) → Task 1 Step 5.
- Loud `XCTFail` on launch/exit failure, never a skip (spec AC2) → Task 1 Step 3 (`XCTAssertEqual(result.exitCode, 0, …stderr…)`).
- Reproduction ⇒ nothing in the core/provider/budget/corpus/script changed (spec AC4, Global Constraints) → Task 3 Steps 3, 6.
- Byte-identical checksums (spec AC5) → Task 3 Step 5.
- AGENTS.md records the guard (spec AC6) → Task 2 Steps 1-2.
- P3 #2 three failure reasons (spec AC6) → Task 2 Step 3.
- P3 #1 soften 580us figure (spec AC6) → Task 2 Step 4.
- Hosted step-level proof (spec AC7) → Task 3 Step 7 leaves the pending placeholder; the hosted run itself is the post-PR follow-up (out of local-plan scope, as in prior slices).

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". Every code step shows complete code; every command shows expected output. The only intentional placeholder is the "Hosted CI — Pending" line in the verification record, which mirrors the established slice pattern (filled by the AC7 follow-up PR).

**Type consistency:** `derivedBudgets(fromScriptOutput:)` returns `[String: (p95: Int64, p99: Int64)]`; consumed in the test as `derived[budget.key]!.p95 / .p99` against `budget.p95 / budget.p99` (`GatedBudget.p95/p99` are `Int64`) — consistent. `budget.key` is `String`, matching the dictionary key type. `runProcess` signature and `everyGatedBudget()`/`GatedBudget` shape are quoted verbatim from the current `GateFloorTests.swift`.
