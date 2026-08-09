# Gate Recalibration + Bulk Absolute Ceiling (D-9 / D-8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh every gated budget from hosted evidence that includes the last ten
slices, and replace the frame-hot-path exemption with a total two-class absolute
product ceiling so `bulk_structural_mutation` gains a fixed one-frame ceiling.

**Architecture:** Three phases in a fixed order (spec Decision 1). Phase 0 adds a
`gov_p95` reporting token to `derive-gate-budgets.sh` so the Phase 1 sweep already
carries the evidence. Phase 1 is data only — capture a pre-harvest budget baseline,
append hosted runs to the corpus, re-derive all modes, update every budget literal
(one commit, Decision 3). Phase 2 replaces `BenchmarkMode.isFrameHotPath: Bool` with
a total `BenchmarkMode.absoluteCeiling: AbsoluteCeiling` classification and lands
against the already-fresh budgets, so its floor pin is correct on arrival.

**Tech Stack:** Swift 6.0 (SwiftPM, XCTest), Bash + awk (`.github/scripts`), `gh` CLI
for hosted log access. No new dependencies.

**Spec:** [`docs/superpowers/specs/2026-08-08-gate-recalibration-and-bulk-ceiling-design.md`](../specs/2026-08-08-gate-recalibration-and-bulk-ceiling-design.md)

## Global Constraints

- **No engine or provider source changes.** `Sources/TextEngineCore` and
  `Sources/TextEngineReferenceProviders` are untouched. All 46 benchmark checksums
  must come out byte-identical (spec Non-Goals, AC9).
- **No `.github/workflows/swift-ci.yml` change.** Bulk already runs as a blocking
  `--gate` step; no CI step is added and `WorkflowShapeTests` is not touched.
- **One script may change:** `.github/scripts/derive-gate-budgets.sh`, and only the
  `gov_p95` token plus its self-test (spec Decision 12/13). No change to the recipe,
  the window, the `--window-run-ids` seam, or the existing fixtures' run ids.
- **The corpus is append-only.** `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv`
  gains rows; no existing row is edited, reordered, or de-duplicated.
- **Absolute ceiling values are FIXED**, derived from `GateLimits.frameNanoseconds`,
  never corpus-derived: `.scrollFrame` = `frameNanoseconds / 10` = `1_666_666`,
  `.discreteAction` = `frameNanoseconds` = `16_666_666`.
- **TDD.** Every code task writes the failing test first and runs it to observe the
  red before implementing.
- **One logical step per commit**, conventional prefixes (`feat:`, `test:`,
  `refactor:`, `docs:`, `ci:`). Exception: Phase 1's corpus rows and budget literals
  are ONE commit (spec Decision 3) — splitting them leaves a tree where
  `testEveryCommittedBudgetReproducesFromCorpus` is red.
- **Plan-assertion conventions** (`AGENTS.md`, from slice 51): no check on the left of
  a pipe; no `echo "…=$?"` after a status-insensitive command; every variable used in
  a command block is assigned in that same block.
- Branch: `slice-52-gate-recalibration-and-bulk-ceiling` (already checked out).

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `.github/scripts/derive-gate-budgets.sh` | Modify | `gov_p95` token in the per-scenario line + two self-test assertions |
| `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` | Append | Hosted samples newer than run id `29606487287` |
| `Sources/ViewportBenchmarks/BenchmarkModels.swift` | Modify | `AbsoluteCeiling` enum; remove `GateLimits.absoluteP99Nanoseconds`; gate check reads the class |
| `Sources/ViewportBenchmarks/BenchmarkOptions.swift` | Modify | `isFrameHotPath: Bool` → `absoluteCeiling: AbsoluteCeiling` (exhaustive switch) |
| `Sources/ViewportBenchmarks/BenchmarkSupport.swift` | Modify | Every gated line prints a numeric ceiling + headroom; `exempt` deleted |
| `Sources/ViewportBenchmarks/*Benchmark.swift` | Modify | Budget literals only, where the re-derivation differs |
| `Tests/ViewportBenchmarksTests/GateLogicTests.swift` | Modify | Paired bulk tests, class-membership pin, frame-math pin, output-line tests |
| `Tests/ViewportBenchmarksTests/GateFloorTests.swift` | Modify | Floor pin de-filtered + failure message rewritten to carry the doctrine |
| `AGENTS.md` | Modify | Four absolute-ceiling touch points (`:413`, `:417`, `:420-431`, `:548`) + `gov_p95` + baseline sentences |
| `docs/superpowers/arcs/wrap.md` | Modify | 2026-08-08 decision-log entry |
| `docs/superpowers/debt-ledger.md` | Modify | D-8 → discharged; D-9 statement amended |
| `docs/superpowers/verification/2026-08-08-gate-recalibration-and-bulk-ceiling.md` | Create | Recorded commands, outputs, drills, hosted run ids |

---

### Task 1: `gov_p95` reporting token (Phase 0)

**Files:**
- Modify: `.github/scripts/derive-gate-budgets.sh` (fixture ~`:57-71`, assertions before
  `echo "self_test=pass"` ~`:73`, `b95` computation `:143`, `printf` `:149-151`)
- Modify: `AGENTS.md` — the `## Gate budgets` thin-axis sentence
- Test: the script's own `--self-test`, driven by `swift test` via
  `Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift` (already enrolled — no
  change needed there)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: every per-scenario line of `derive-gate-budgets.sh <corpus>` gains a
  `gov_p95=median|max` field, positioned between `budget_p99=` and `margin_p95=`.
  Task 2 reads it. `derivedBudgets(fromScriptOutput:)` in `GateFloorTests` is
  prefix-scanning (`field.hasPrefix("budget_p95=")`, `omittingEmptySubsequences: true`),
  so an extra padded field passes through untouched — verified, no Swift change.

**Context the implementer needs:** `run_self_test` currently holds exactly two
assertions, both on `window_run_ids` fixtures. The budget arithmetic has **no**
self-test coverage today, so these two assertions are the first standing check on it.
The derivation lives in the `awk` program *below* the `--self-test` dispatch and is
not reachable as a function, so the assertions re-invoke the script (`"$0" "$fixture"`)
— a form this file has never used.

- [ ] **Step 1: Write the failing assertions and the second fixture scenario**

In `run_self_test`, after the existing `printf '99\tline_query\tuniform_1k\t22\t52\n'`
line, add the outlier scenario:

```bash
  # Second scenario, deliberately carrying an outlier: p95 med=10, max=100, so
  # 3*max (300) beats 8*med (80) and the MAX term governs. The first scenario is
  # median-governed (8*24=192 vs 3*30=90), so the two cover both branches of gov_p95.
  # Reuses the four run ids above on purpose: adding a new one would change the
  # window_run_ids assertions above.
  printf '305\tcolumn_query\toutlier\t10\t20\n'  >> "$fixture"
  printf '210\tcolumn_query\toutlier\t10\t20\n'  >> "$fixture"
  printf '100\tcolumn_query\toutlier\t10\t20\n'  >> "$fixture"
  printf '99\tcolumn_query\toutlier\t100\t200\n' >> "$fixture"
```

Then, immediately before the closing `echo "self_test=pass"`, add:

```bash
  # gov_p95 lives in the awk program BELOW the --self-test dispatch, so it is not
  # reachable as a function: re-invoke the script itself. `local` on its own line --
  # `local x="$(cmd)"` would take the builtin's status, masking a failing child.
  local derived
  derived="$("$0" "$fixture")" || {
    echo "self_test=fail label=gov_p95_derivation_exited status=$?"
    exit 1
  }

  gov_of() { printf '%s\n' "$derived" | awk -v k="$1" '$1 == k {
    for (i = 1; i <= NF; i++) if ($i ~ /^gov_p95=/) { split($i, a, "="); print a[2] } }'; }

  assert_equal "median" "$(gov_of 'line_query|uniform_1k')" \
    "gov_p95=median when 8*med >= 3*max"
  assert_equal "max" "$(gov_of 'column_query|outlier')" \
    "gov_p95=max when 3*max > 8*med"
```

- [ ] **Step 2: Run the self-test to verify it fails**

```bash
./.github/scripts/derive-gate-budgets.sh --self-test
```

Expected: exit 1, with

```
self_test=fail label=gov_p95=median when 8*med >= 3*max
  expected: [median]
  actual:   []
```

(The token does not exist yet, so `gov_of` extracts nothing.)

- [ ] **Step 3: Add the token to the derivation**

In the `awk` `END` block, immediately after the `b95 = ru2(...)` line at `:143`, add:

```awk
    # `>=`, NOT the `>` on the line above, and the asymmetry is deliberate. Up there a
    # tie is harmless: both terms yield the same number, so either branch is correct.
    # Here a tie is MEANINGFUL -- the token answers "is this budget resting on the
    # median term alone?", and on a tie it is. Harmonizing the two operators would
    # silently change the rule.
    gov95 = (8 * m95 >= 3 * x95) ? "median" : "max"
```

Change the `printf` format string to insert `gov_p95=%-6s ` between `budget_p99=%-7d `
and `margin_p95=`, and add `gov95` to the argument list between `b99` and `b95 / x95`:

```awk
    printf "%-46s n=%-3d p95[med=%-6d max=%-6d] p99[med=%-6d max=%-6d] budget_p95=%-7d budget_p99=%-7d gov_p95=%-6s margin_p95=%.1fx margin_p99=%.1fx\n", \
           k, cnt, m95, x95, m99, x99, b95, b99, gov95, b95 / x95, b99 / x99
```

- [ ] **Step 4: Run the self-test to verify it passes**

```bash
./.github/scripts/derive-gate-budgets.sh --self-test
```

Expected: `self_test=pass`, exit 0.

- [ ] **Step 5: Verify the token against the real corpus and confirm the expected distribution**

```bash
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
SWEEP="$(mktemp)"
./.github/scripts/derive-gate-budgets.sh "$CORPUS" > "$SWEEP" \
  || { echo 'sweep failed'; rm -f "$SWEEP"; exit 1; }
MED="$(grep -c 'gov_p95=median' "$SWEEP")"
MAX="$(grep -c 'gov_p95=max' "$SWEEP")"
TOTAL="$(wc -l < "$SWEEP")"
echo "median=$MED max=$MAX total=$TOTAL"
[ "$MED" -eq 45 ] && [ "$MAX" -eq 1 ] && [ "$TOTAL" -eq 46 ] \
  || { echo "unexpected distribution -- spec Source Context says 45/1/46"; rm -f "$SWEEP"; exit 1; }
grep 'gov_p95=max' "$SWEEP" || { echo 'no max line found'; rm -f "$SWEEP"; exit 1; }
rm -f "$SWEEP"
```

Expected: `median=45 max=1 total=46`, and the single `max` line is
`line_query|uniform_1k` (`med=24 max=73`: `8×24=192` vs `3×73=219`).

This is the pre-harvest measurement AC3 compares against. It is asserted, not
eyeballed: the distribution is the spec's own load-bearing claim.

- [ ] **Step 6: Confirm the budget parser is unaffected**

```bash
swift test --filter GateFloorTests
```

Expected: PASS, including `testEveryCommittedBudgetReproducesFromCorpus` — the extra
field must not disturb the prefix-scanning parser.

- [ ] **Step 7: Document the token in `AGENTS.md`**

In `## Gate budgets`, the paragraph ending "p95 carries only the median term as
backup, so it is the thin axis to watch." Replace that closing sentence with:

```markdown
p95 carries only the median term as backup, so it is the thin axis — and
`derive-gate-budgets.sh` now prints `gov_p95=median|max` beside every budget, so
which term governs is read rather than recomputed. A budget is median-governed
exactly when `max / med <= 2.67`, which is why nearly every one of them is; the
current count belongs in a verification record, not here, since the next harvest
moves it. The value is in the **flip**, and the two directions differ:
`median -> max` means a freak sample took over the floor and the budget LOOSENED
(the runtime gate catches that loudly, as `budget_stale`), while `max -> median`
means the freak aged out and the budget TIGHTENED — the direction that reddens a
clean tree, and the one nothing else catches before a hosted run.
```

- [ ] **Step 8: Run the full suite**

```bash
swift test
```

Expected: PASS. `ScriptSelfTestTests` drives `--self-test` for all four scripts, so
Step 4's guarantee is build-failing from its first day.

- [ ] **Step 9: Commit**

```bash
git add .github/scripts/derive-gate-budgets.sh AGENTS.md
git commit -m "feat: gov_p95 token names which term governs each p95 budget

The thin axis D-9 records has been a watch-by-hand instruction since slice 41.
derive-gate-budgets.sh now prints gov_p95=median|max beside every budget, so the
observation is a property of every re-derivation rather than a one-off transcription.

Tie rule is median at 8*med == 3*max (the token asks 'resting on the median term
alone?', and on a tie it is), so it reads >= where the b95 line beside it reads > --
commented, since harmonizing the operators would silently change the rule.

run_self_test gains a second fixture scenario carrying an outlier plus one assertion
per branch. Those are the first standing checks on the budget arithmetic at all: both
existing assertions cover window_run_ids only. They reach the derivation by
re-invoking the script, since it lives below the --self-test dispatch.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Harvest, re-derive, and update every budget literal (Phase 1)

**Files:**
- Modify: `docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv` (append only)
- Modify: `Sources/ViewportBenchmarks/*Benchmark.swift` (budget literals only)
- Modify: `AGENTS.md` — one sentence on the pre-harvest baseline
- Test: `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (standing, unchanged)

**Interfaces:**
- Consumes: Task 1's `gov_p95` token.
- Produces: a corpus whose N=20 window holds no pre-slice-45 run, and 46 budget
  literals that reproduce from it. Task 5's floor pin is written against these.

**Preconditions:** `gh` authenticated with read access to `maldrakar/swift-text-engine`.
This task makes network calls; the rest of the plan does not.

**Why one commit:** `testEveryCommittedBudgetReproducesFromCorpus` compares every
committed literal against a re-derivation from the committed corpus. Appending rows in
one commit and updating literals in the next leaves an intermediate tree where that
test is red (spec Decision 3).

- [ ] **Step 1: Record AC2's pre-work red — the window check fails today**

```bash
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
WORK="$(mktemp -d)"
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo 'temp root unavailable'; exit 1; }
echo "WORK=$WORK   # reuse this path for the rest of Task 2"
./.github/scripts/derive-gate-budgets.sh --window-run-ids 20 < "$CORPUS" > "$WORK/window-before.txt" \
  || { echo 'derive --window-run-ids failed'; exit 1; }
awk -F'\t' 'NR==FNR {win[$1]; next}
            $2 == "realistic_provider" && ($1 in win) {n[$1]++}
            END {for (r in n) if (n[r] > 1) print r, n[r]}' \
    "$WORK/window-before.txt" "$CORPUS" > "$WORK/offenders-before.txt" \
  || { echo 'offender scan failed'; exit 1; }
OFF="$(wc -l < "$WORK/offenders-before.txt")"
echo "pre-work offenders: $OFF"
[ "$OFF" -eq 16 ] || { echo "expected 16 offending runs before the harvest, got $OFF"; exit 1; }
cat "$WORK/offenders-before.txt"
```

Expected: 16 runs, each contributing 8 `realistic_provider` rows (`29280327104 8`,
`29205750443 8`, …). **Record this output verbatim in the verification document** — it
is AC2's falsifiability evidence, and the only guarantee in this slice whose red is
the pre-work state rather than a manufactured mutation (AC8).

- [ ] **Step 2: Provenance-check the two run-level failures by hand (AC1)**

```bash
for run in 29701333581 29701547123; do
  host="$(gh run view "$run" --json jobs \
          --jq '.jobs[] | select(.name == "Host tests and benchmark gate") | .conclusion')"
  echo "run $run host job = ${host:-missing}"
  [ "$host" = "success" ] || { echo "run $run is NOT admissible"; exit 1; }
done
```

Expected: `success` for both. A run is admissible when its **host** job passed; a host
job that failed *on its budget* carries exactly the slow samples that would loosen the
budget they broke. Both of these failed only their WASM job (slice 46's promotion).
Record the output — while D-7 stays deferred this hand check is the only provenance
control in the chain.

- [ ] **Step 3: Capture the pre-harvest budget baseline**

This must happen **before** the append: afterwards the old budgets are unrecoverable
from the corpus and the diff compares against itself.

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
budget_columns() {
  awk '{ p95 = ""; p99 = ""
         for (i = 1; i <= NF; i++) {
           if ($i ~ /^budget_p95=/) { split($i, a, "="); p95 = a[2] }
           if ($i ~ /^budget_p99=/) { split($i, a, "="); p99 = a[2] } }
         if (p95 != "" && p99 != "") print $1, p95, p99 }' "$1" | sort
}
./.github/scripts/derive-gate-budgets.sh "$CORPUS" > "$WORK/sweep-old.txt" \
  || { echo 'pre-harvest sweep failed'; exit 1; }
budget_columns "$WORK/sweep-old.txt" > "$WORK/old-budgets.txt"
OLD_N="$(wc -l < "$WORK/old-budgets.txt")"
[ "$OLD_N" -eq 46 ] || { echo "pre-harvest baseline holds $OLD_N budgets, want 46"; exit 1; }
echo "baseline captured: $OLD_N budgets"
```

- [ ] **Step 4: Preview the harvest plan (`--dry-run`)**

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
./.github/scripts/harvest-gate-corpus.sh --limit 100 --corpus "$CORPUS" --dry-run \
  > "$WORK/harvest-plan.txt" 2>&1 \
  || { echo 'harvest --dry-run failed'; cat "$WORK/harvest-plan.txt"; exit 1; }
# The two decision prefixes are `plan=harvest run=<id>` and
# `skip=already_harvested run=<id>` -- verified against plan_runs, because a grep for a
# prefix the script never emits matches nothing and reads as a clean plan.
PLANNED="$(grep -c '^plan=harvest ' "$WORK/harvest-plan.txt" || true)"
SKIPPED="$(grep -c '^skip=already_harvested ' "$WORK/harvest-plan.txt" || true)"
echo "planned=$PLANNED skipped=$SKIPPED"
[ "$PLANNED" -ge 20 ] || {
  echo "only $PLANNED runs planned; the window needs 20 sample-carrying runs to flush"
  echo 'the pre-slice-45 tail. Raise --limit and re-run (spec Risks) before appending.'
  exit 1
}
```

`|| true` on the two counts is required: `grep -c` exits 1 when the count is 0, so
without it a legitimately empty skip set would abort the block. The assertion is on
`$PLANNED`, not on grep's status. The `>= 20` floor is conservative — roughly half the
62 candidates are docs-only runs that print no `p95_ns=` lines and contribute no rows,
so planned runs are an upper bound on sample-carrying ones; Step 7 is what actually
proves the window flushed.

`2>&1` is required, not cosmetic: the script writes decisions with
`echo "$decision" >&2`, so a bare `> file` records an empty plan and reads as a clean
one. `--limit 100` is deliberate (spec Decision 2) — the default 40 lands roughly on
the 20-run boundary, and one extra docs-only run would leave the pre-slice-45 tail in
place and silently fail Goal 2. Record this plan in the verification document.

- [ ] **Step 5: Append to the corpus**

```bash
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
./.github/scripts/harvest-gate-corpus.sh --limit 100 --corpus "$CORPUS" >> "$CORPUS" \
  || { echo 'harvest failed; corpus may hold a partial append -- inspect before committing'; exit 1; }
```

`--corpus` makes this idempotent: already-harvested run ids are skipped *before* their
logs are fetched, so a double harvest cannot double-weight a run in `median()`.

- [ ] **Step 6: Assert the corpus is append-only**

```bash
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
DEL="$(git diff --numstat -- "$CORPUS" | awk '{print $2}')"
echo "lines removed from corpus: ${DEL:-<none>}"
[ "$DEL" = "0" ] || { echo 'corpus lost lines -- append-only violated'; exit 1; }
```

`git diff` exits 0 whether or not there are changes, so its status proves nothing —
the check is on the deletion count. An empty `$DEL` (git failed, or no diff at all)
also fails, which is correct: this step must observe an append.

- [ ] **Step 7: AC2 — assert the window is flushed**

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
./.github/scripts/derive-gate-budgets.sh --window-run-ids 20 < "$CORPUS" > "$WORK/window.txt" \
  || { echo 'derive --window-run-ids failed'; exit 1; }
IDS="$(wc -l < "$WORK/window.txt")"
[ "$IDS" -eq 20 ] || { echo "window holds $IDS run ids, want 20"; exit 1; }

# PRIMARY -- the invariant itself. A post-slice-45 run prints exactly ONE
# realistic_provider summary line, so no window run may contribute more than one row.
OFFENDERS="$(awk -F'\t' 'NR==FNR {win[$1]; next}
                         $2 == "realistic_provider" && ($1 in win) {n[$1]++}
                         END {for (r in n) if (n[r] > 1) print r, n[r]}' \
             "$WORK/window.txt" "$CORPUS")"
[ -z "$OFFENDERS" ] || { printf 'shape-2 rows still in window:\n%s\n' "$OFFENDERS"; exit 1; }

# CORROBORATION -- a proxy, second signal only. Run ids order RUNS, not workflow
# versions, so a branch cut before slice 45 merged could carry the old shape at a
# higher id. This cannot stand alone.
OLD="$(awk '$1 < 29692848870' "$WORK/window.txt")"
[ -z "$OLD" ] || { printf 'window carries pre-slice-45 runs:\n%s\n' "$OLD"; exit 1; }
echo 'AC2: window flushed'
```

If offenders remain, the response is a **wider `--limit` and a re-run**, never a
weakened criterion (spec Risks).

- [ ] **Step 8: Sweep every mode and record the `gov_p95` distribution (AC3)**

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
CORPUS=docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv
./.github/scripts/derive-gate-budgets.sh "$CORPUS" > "$WORK/sweep.txt" \
  || { echo 'sweep failed'; exit 1; }
SWEPT="$(wc -l < "$WORK/sweep.txt")"
[ "$SWEPT" -eq 46 ] || { echo "sweep produced $SWEPT lines, want 46"; exit 1; }
MED="$(grep -c 'gov_p95=median' "$WORK/sweep.txt")"
echo "median-governed: $MED of 46"
[ "$MED" -ge 1 ] || { echo 'no gov_p95=median lines -- token missing from the sweep?'; exit 1; }
grep 'gov_p95=max' "$WORK/sweep.txt" || true   # an empty max set is a legitimate outcome
```

The `|| true` is required on the last line and only there: `grep` exits 1 on **no**
match, so without it the legitimate "everything is median-governed" outcome would read
as a failure (plan-assertion rule 2). Record the full sweep verbatim.

Pre-harvest this was 45 of 46. A result anywhere near that is the expected outcome and
not a finding; a sharp move in either direction is.

- [ ] **Step 9: Directional budget diff (AC4) — the tightening watch-list**

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
budget_columns() {
  awk '{ p95 = ""; p99 = ""
         for (i = 1; i <= NF; i++) {
           if ($i ~ /^budget_p95=/) { split($i, a, "="); p95 = a[2] }
           if ($i ~ /^budget_p99=/) { split($i, a, "="); p99 = a[2] } }
         if (p95 != "" && p99 != "") print $1, p95, p99 }' "$1" | sort
}
budget_columns "$WORK/sweep.txt" > "$WORK/new-budgets.txt"
NEW_N="$(wc -l < "$WORK/new-budgets.txt")"
[ "$NEW_N" -eq 46 ] || { echo "post-harvest sweep holds $NEW_N budgets, want 46"; exit 1; }

# join drops keys present on only one side, which would hide a scenario that appeared
# or vanished. This slice changes no scenario, so assert the join is total.
join "$WORK/old-budgets.txt" "$WORK/new-budgets.txt" > "$WORK/budget-diff.txt"
JOINED="$(wc -l < "$WORK/budget-diff.txt")"
[ "$JOINED" -eq 46 ] || { echo "join matched $JOINED of 46 keys -- scenario set moved"; exit 1; }

awk '$2 != $4 || $3 != $5 {
       dir = ($2 > $4 || $3 > $5) ? "TIGHTENED" : "loosened"
       printf "%-10s %-46s p95 %s->%s  p99 %s->%s\n", dir, $1, $2, $4, $3, $5 }' \
    "$WORK/budget-diff.txt" > "$WORK/moved.txt" || { echo 'movement scan failed'; exit 1; }
awk '$2 > $4 || $3 > $5 { print $1 }' "$WORK/budget-diff.txt" > "$WORK/tightened.txt" \
  || { echo 'tightening scan failed'; exit 1; }
echo "moved: $(wc -l < "$WORK/moved.txt") of 46,  tightened: $(wc -l < "$WORK/tightened.txt")"
cat "$WORK/moved.txt"
```

**This is evidence, not an assertion.** A tightening is legitimate — it is exactly what
slice 41's window was built to allow — so failing here would redden the block for
correct behaviour. Record the full movement list and call out the tightened set: it is
the watch-list for Task 8's hosted PR-head run, which is the only *empirical* control
on the one direction Phase 1's arithmetic cannot catch.

- [ ] **Step 10: Decision 10 halt check — does bulk reach its future ceiling?**

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
grep 'bulk_structural_mutation|1m_lines_batch_4096' "$WORK/sweep.txt" \
  || { echo 'binding bulk scenario missing from the sweep'; exit 1; }
BULK99="$(awk '$1 == "bulk_structural_mutation|1m_lines_batch_4096" {
                 for (i = 1; i <= NF; i++)
                   if ($i ~ /^budget_p99=/) { split($i, a, "="); print a[2] } }' "$WORK/sweep.txt")"
echo "bulk 1m batch_4096 budget_p99 = ${BULK99:-<unparsed>}"
[ -n "$BULK99" ] || { echo 'could not read the bulk p99 budget'; exit 1; }
[ "$BULK99" -lt 16666666 ] || {
  echo 'HALT (spec Decision 10): the re-derived bulk p99 budget has reached the'
  echo 'one-frame ceiling. Do NOT proceed to Phase 2. Read the governing term off'
  echo 'the sweep line and return to the user with the diagnosis attached:'
  echo '  (a) the MEDIAN moved   -> genuine drift; fix the code/architecture, never'
  echo '      the ceiling. Different slice, different spec.'
  echo '  (b) the median is where it was and 3*max governs alone -> one anomalous'
  echo '      hosted sample. The freak ages out of the N=20 window, but it cannot'
  echo '      ship red meanwhile. USER decision, not an author decision.'
  exit 1
}
echo "bulk clears the future ceiling with $(( 16666666 * 100 / BULK99 ))% margin ratio"
```

Pre-harvest this budget is `5_800_000` (2.87× under the ceiling), governed by
`16 × median(p95)`; the median would have to nearly triple. Low likelihood — but a
response decided under pressure is what naming both branches in advance prevents.

- [ ] **Step 11: Verify no frame-hot-path budget crossed the *existing* ceiling**

Phase 2 has not landed yet, so the existing pin still filters bulk out and still checks
the other 41 against `1_666_666`.

```bash
swift test --filter testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling
```

Expected: PASS. If red, a frame-hot-path budget tripled — stop and escalate; that is
not a transcription error and Phase 2 must not be written on top of it.

- [ ] **Step 12: Update every budget literal the recipe now produces differently**

For each line of `$WORK/moved.txt`, edit the matching `p95BudgetNanoseconds` /
`p99BudgetNanoseconds` literal in `Sources/ViewportBenchmarks/<Mode>Benchmark.swift`.
Map scenario key → file by the mode prefix, e.g.
`bulk_structural_mutation|1m_lines_batch_4096` →
`Sources/ViewportBenchmarks/BulkStructuralMutationBenchmark.swift`. Swift literals use
`_` separators (`2_900_000`); the sweep prints bare digits (`2900000`).

Sanity: the number of literals you touch must equal the number of lines in
`$WORK/moved.txt`. If `moved.txt` is empty, change nothing — `round_up_2sf` hysteresis
means most small median/max moves round to the same budget, and that is a legitimate
finding, not an empty slice.

- [ ] **Step 13: Run the arbiter**

```bash
swift test --filter GateFloorTests
```

Expected: PASS, in particular `testEveryCommittedBudgetReproducesFromCorpus`. This test
is the arbiter of whether the re-derivation was transcribed correctly — a red here is a
transcription error, not an engine regression.

- [ ] **Step 14: Run the full suite**

```bash
swift test
```

Expected: PASS.

- [ ] **Step 15: Document the baseline practice in `AGENTS.md`**

In `## Gate budgets`, immediately after the two-command recipe block, add:

```markdown
**Take a budget baseline before the harvest, and diff the directions afterwards.**
Run the sweep once against the corpus *before* appending and keep its
`budget_p95`/`budget_p99` per scenario; after re-deriving, compare. A budget that
**loosened** is harmless — the runtime gate compares against this run's latency and
says `budget_stale` if it drifts too far. A budget that **tightened** is the one that
reddens a clean tree: an old freak sample aged out of the window (exactly what the
window is for), and the new budget may sit closer to observed latency than a noisy
runner can reliably clear. Nothing in the arithmetic catches that — no re-derivation
runs the benchmark — so the tightened set is the watch-list for the hosted PR-head
run, and the baseline is unrecoverable once the corpus is appended.
```

- [ ] **Step 16: Commit corpus and literals together (Decision 3)**

```bash
git add docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
        Sources/ViewportBenchmarks AGENTS.md
git commit -m "feat: recalibrate every gate budget against post-slice-45 hosted evidence

The corpus had not been appended since 2026-07-18, so the N=20 window held zero
post-slice-45 runs and every one of the twelve blocking budgets rested on
pre-slice-45 evidence. realistic_provider was the sharp case: its window carried 8
shape-2 rows per run across 16 runs, deriving a budget from a statistic the mode no
longer prints.

Harvested every hosted run newer than run id 29606487287 (--limit 100 --corpus, so
the append is idempotent), swept all modes, and updated every literal the recipe now
produces differently. Corpus rows and literals are ONE commit: split, the intermediate
tree fails testEveryCommittedBudgetReproducesFromCorpus.

D-9's shape-transition half is now discharged by fact rather than by prediction -- no
window run contributes more than one realistic_provider row.

AGENTS.md gains the pre-harvest baseline practice: the tightening direction is the one
the arithmetic cannot catch, and the baseline is unrecoverable after the append.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `AbsoluteCeiling` classification and bulk's own ceiling (Phase 2a)

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift` (`GateLimits` comment block
  `:59-77`, `headroomAbsoluteP99` `:119-125`, gate check `:142-155`)
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (add `absoluteCeiling` after
  `isFrameHotPath` at `:104-125`)
- Test: `Tests/ViewportBenchmarksTests/GateLogicTests.swift`

**Interfaces:**
- Consumes: Task 2's fresh budgets (nothing structural).
- Produces: `enum AbsoluteCeiling { case scrollFrame, discreteAction }` with
  `var p99Nanoseconds: Int64`, and `BenchmarkMode.absoluteCeiling: AbsoluteCeiling`.
  Tasks 4 and 5 consume both. `isFrameHotPath` and `GateLimits.absoluteP99Nanoseconds`
  still exist after this task — Task 5 removes them, which keeps every intermediate
  tree compiling.

- [ ] **Step 1: Write the failing test**

Add to `GateLogicTests.swift`, directly after `testAbsoluteCeilingDoesNotFireForBulkMode`:

```swift
    // D-8's substance: bulk gets an absolute ceiling of its own -- one whole 60 FPS
    // frame -- and blowing it is reported even though the regression budget passes.
    //
    // The literal is deliberate and must NOT become
    // `AbsoluteCeiling.discreteAction.p99Nanoseconds + 1`. Written symbolically the
    // observation would track the ceiling, so raising the ceiling would raise the
    // observation with it and this test could never fail. Its job in Decision 8's
    // bracket is exactly to fail if the ceiling rises above 16_666_667 or disappears.
    func testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling() {
        let obsP99: Int64 = 16_666_667  // one ns over one whole 60 FPS frame
        let s = summary(
            mode: .bulkStructuralMutation,
            p95: 100_000, p99: obsP99,
            budgetP95: 300_000, budgetP99: obsP99 + 100_000)  // regression budget passes
        XCTAssertEqual(s.gateFailureReason, .budgetAbsoluteExceeded)
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --filter testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling
```

Expected: FAIL — `XCTAssertEqual failed: ("nil") is not equal to ("Optional(budgetAbsoluteExceeded)")`.
Under the old model `isFrameHotPath` is `false` for bulk, so the absolute check is
skipped entirely; headroom is 3.0 (p95) and ~1.006 (p99), both far under the 50×/100×
stale ceilings, so the reason is `nil`.

- [ ] **Step 3: Add the `AbsoluteCeiling` enum**

In `BenchmarkModels.swift`, replace the `static let absoluteP99Nanoseconds` line's
trailing comment block and add the enum immediately after the closing brace of
`GateLimits` (keep `absoluteP99Nanoseconds` itself for now — Task 5 removes it):

```swift
// Which absolute PRODUCT ceiling a mode is held to. Two classes, total by
// construction: an exhaustive switch on BenchmarkMode forces a newly added mode to
// classify itself, so it can neither silently inherit a ceiling nor silently escape
// one. There is no exempt case -- a branch with no inhabitants is the same defect as
// a gate that cannot fail.
//
// FIXED, both of them: never recalibrated, never corpus-derived. On breach the
// response is to fix the code/architecture, NEVER to loosen the ceiling (contrast
// budget_stale, which says re-derive the budget).
enum AbsoluteCeiling: Equatable {
    // A scroll frame must not drop, so every participant is rationed and the headless
    // core's ration is a tenth: the other 90% belongs to shaping, rasterization, and
    // UI outside it.
    case scrollFrame

    // A discrete action -- a bulk multi-line paste or range delete -- is one the user
    // has already accepted a perceptible pause for, so it MAY cost a dropped frame.
    // The core's budget for the action it triggered is that whole frame's worth of
    // work. Note this is NOT "the core may consume 100% of a live frame": the frame in
    // question is one the product has agreed to drop.
    case discreteAction

    var p99Nanoseconds: Int64 {
        switch self {
        case .scrollFrame:
            return GateLimits.frameNanoseconds / 10   // 1_666_666
        case .discreteAction:
            return GateLimits.frameNanoseconds        // 16_666_666
        }
    }
}
```

- [ ] **Step 4: Classify every mode**

In `BenchmarkOptions.swift`, add after `isFrameHotPath`:

```swift
    // Which absolute product ceiling this mode is held to. Exhaustive, never a
    // deny-list -- the same discipline as isGateable.
    //
    // The four non-gateable modes (rangeOnly, memoryShape, memoryObservation,
    // wrapCompute) must classify under a total function but never reach the gate, so
    // their value is inert. Worth knowing: the class-membership pin filters on
    // isGateable and therefore does NOT cover them. Their class is a compile-time
    // obligation, not a pinned one -- do not expect a test to catch a wrong choice here.
    var absoluteCeiling: AbsoluteCeiling {
        switch self {
        case .bulkStructuralMutation:
            return .discreteAction
        case .pipeline,
             .rangeOnly,
             .realisticProvider,
             .variableHeight,
             .variableHeightMutation,
             .structuralMutation,
             .lineQuery,
             .lineGeometryQuery,
             .columnQuery,
             .columnGeometryQuery,
             .pointQuery,
             .pointGeometryQuery,
             .memoryShape,
             .memoryObservation,
             .wrapCompute:
            return .scrollFrame
        }
    }
```

- [ ] **Step 5: Point the gate check and the headroom at the class**

In `BenchmarkModels.swift`, replace the `headroomAbsoluteP99` body:

```swift
    var headroomAbsoluteP99: Double {
        BenchmarkSummary.headroom(
            budget: mode.absoluteCeiling.p99Nanoseconds, observed: p99Nanoseconds)
    }
```

and the gate check inside `gateFailureReason`:

```swift
        if p99Nanoseconds > mode.absoluteCeiling.p99Nanoseconds {
            return .budgetAbsoluteExceeded
        }
```

The `mode.isFrameHotPath,` guard is gone: the classification is total, so every mode is
compared against its own ceiling.

- [ ] **Step 6: Run the new test and its bracket partner**

```bash
swift test --filter testAbsoluteCeiling
```

Expected: PASS for all of `testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling`,
`testAbsoluteCeilingDoesNotFireForBulkMode` (1_666_667 is far below bulk's 16.67 ms
ceiling — the assertion survives, its meaning changes), `testAbsoluteCeilingFiresForFrameHotPathMode`,
`testAbsoluteCeilingDoesNotMaskStaleBudget`, `testAbsoluteCeilingIsTenPercentOfFrame`.

- [ ] **Step 7: Run the full suite**

```bash
swift test
```

Expected: PASS. `BenchmarkSupport` still prints `exempt` for bulk and
`testGateOutputMarksBulkExempt` still passes — Task 4 changes that.

- [ ] **Step 8: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkModels.swift \
        Sources/ViewportBenchmarks/BenchmarkOptions.swift \
        Tests/ViewportBenchmarksTests/GateLogicTests.swift
git commit -m "feat: two-class absolute ceiling; bulk gets one whole 60 FPS frame

D-8, open since slice 43 for want of a product target. AbsoluteCeiling classifies
every mode as .scrollFrame (frameNanoseconds / 10) or .discreteAction
(frameNanoseconds), and the gate compares each mode against its own class rather than
skipping the check for the one exempt mode.

A scroll frame must not drop, so the core is rationed to a tenth of it. A discrete
bulk edit is one the user has already accepted a pause for, so it may cost a dropped
frame and the core's budget is that whole frame's work.

The new paired test uses the literal 16_666_667, not the symbolic ceiling + 1: written
symbolically the observation would track the ceiling and the test could never fail,
which is precisely the job it has in the bracket.

isFrameHotPath and GateLimits.absoluteP99Nanoseconds still exist and are removed next,
so every intermediate tree compiles.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Every gated line publishes a numeric ceiling (Phase 2b)

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkSupport.swift:124-131`
- Test: `Tests/ViewportBenchmarksTests/GateLogicTests.swift:298-307`

**Interfaces:**
- Consumes: `BenchmarkMode.absoluteCeiling` and `AbsoluteCeiling.p99Nanoseconds` from Task 3.
- Produces: every gated summary line carries a numeric `budget_absolute_p99_ns` and a
  `headroom_absolute_p99`. The `exempt` token no longer exists anywhere. Task 7's AC5
  count assertions read this.

- [ ] **Step 1: Invert the output-line test**

Replace `testGateOutputMarksBulkExempt` entirely:

```swift
    // Bulk publishes its own ceiling like every other gated mode. Both assertions
    // inverted from the exemption era: the line carries a NUMBER, and it carries the
    // headroom token it previously omitted. 16_666_666 / 900_000 = 18.5x.
    func testGateOutputCarriesDiscreteActionCeilingForBulk() {
        let line = formatSummary(
            summary(mode: .bulkStructuralMutation, p95: 400_000, p99: 900_000,
                    budgetP95: 2_900_000, budgetP99: 5_800_000),
            includeGate: true)
        XCTAssertTrue(line.contains(" budget_absolute_p99_ns=16666666"), line)
        XCTAssertTrue(line.contains(" headroom_absolute_p99=18.5x"), line)
        XCTAssertTrue(line.contains(" gate=pass"), line)
    }
```

The budget arguments are synthetic inputs to the `summary` helper, not reads from the
registry, so Task 2's re-derivation does not affect them.

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --filter testGateOutputCarriesDiscreteActionCeilingForBulk
```

Expected: FAIL — the line still reads `budget_absolute_p99_ns=exempt` and carries no
`headroom_absolute_p99`.

- [ ] **Step 3: Collapse the branch**

In `BenchmarkSupport.swift`, replace the `if summary.mode.isFrameHotPath { … } else { … }`
block with:

```swift
        output += " budget_absolute_p99_ns=\(summary.mode.absoluteCeiling.p99Nanoseconds)"
        output += " headroom_absolute_p99=\(formatHeadroom(summary.headroomAbsoluteP99))"
```

- [ ] **Step 4: Run it to verify it passes**

```bash
swift test --filter testGateOutput
```

Expected: PASS for `testGateOutputCarriesDiscreteActionCeilingForBulk`,
`testGateOutputCarriesAbsoluteCeilingForFrameHotPath` (still `1666666` / `8.3x`, and
its field-ordering assertions still hold), and `testNonGateOutputHasNoAbsoluteToken`
(non-gate output is a separate contract and still carries neither token).

- [ ] **Step 5: Confirm `exempt` is gone from the emitted token**

```bash
if rg -n 'budget_absolute_p99_ns=exempt' Sources Tests; then
  echo 'FAIL: the exempt token survives'; exit 1
else
  echo 'OK: no exempt token in Sources or Tests'
fi
```

An `if`/`else` rather than a bare `rg`: `rg` exits 1 on **no** match, so the desired
outcome would read as a failure (plan-assertion rule 2). The English word "exempt"
legitimately survives in `GateLogicTests`' registry comment and `WorkflowShapeTests`'
exemption-set comment — this matches the emitted **token**, never the word.

- [ ] **Step 6: Run the full suite**

```bash
swift test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ViewportBenchmarks/BenchmarkSupport.swift \
        Tests/ViewportBenchmarksTests/GateLogicTests.swift
git commit -m "refactor: every gated summary publishes its absolute ceiling

The exempt marker existed to make a deliberate non-application visible. With the
classification total there is no non-application left to mark, so bulk prints its own
16666666 and the headroom token it previously omitted -- its live margin under the
product ceiling becomes visible on every hosted run for the first time.

Both assertions of the old output test inverted.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Remove the old model and re-pin the guarantees (Phase 2c)

**Files:**
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift` (remove `absoluteP99Nanoseconds`;
  rewrite the `GateLimits` comment block and the comment inside `gateFailureReason`)
- Modify: `Sources/ViewportBenchmarks/BenchmarkOptions.swift` (remove `isFrameHotPath` and
  its comment; the `:91` comment naming the removed symbol goes with it)
- Modify: `Tests/ViewportBenchmarksTests/GateLogicTests.swift` (`:217`, `:227-228`,
  `:235`, `:246`, `:257`, and two test names)
- Modify: `Tests/ViewportBenchmarksTests/GateFloorTests.swift` (`:404-425`)
- Modify: `AGENTS.md` (`:413`, `:417`, `:420-431`, `:548`)

**Interfaces:**
- Consumes: `AbsoluteCeiling` / `absoluteCeiling` from Task 3.
- Produces: `isFrameHotPath` and `GateLimits.absoluteP99Nanoseconds` no longer exist.
  `testEveryGatedBudgetIsUnderItsClassCeiling` covers all 46 budgets.

**The load-bearing part is a failure message, not a rename.** Spec Decision 9
establishes that the floor pin — not the runtime reason — is where the product target
is actually enforced: under the pin, any p99 above a class ceiling is also above that
mode's regression budget, and `budgetExceeded` is evaluated first, so the
`budgetAbsoluteExceeded` branch has no reachable inhabitant. The pin's red *is* the
ceiling firing, so its text is the only place the doctrine reaches whoever tripped it.
The current message offers two remediations this task invalidates.

- [ ] **Step 1: Write the failing pins**

Replace `testFrameHotPathExclusionsAreExactlyDocumented` in `GateLogicTests.swift`:

```swift
    // Pin the discrete-action class so it cannot silently widen. The exhaustive switch
    // forces a new mode to classify itself; this asserts the only GATED mode choosing
    // the one-frame ceiling is bulk_structural_mutation. Non-gateable modes are out of
    // scope here by construction -- see the note on absoluteCeiling.
    func testDiscreteActionClassIsExactlyDocumented() {
        let discrete = Set(
            BenchmarkMode.allCases
                .filter { $0.isGateable && $0.absoluteCeiling == .discreteAction }
                .map(\.outputName))
        XCTAssertEqual(discrete, ["bulk_structural_mutation"])
    }
```

Replace `testAbsoluteCeilingIsTenPercentOfFrame`:

```swift
    // Both ceilings are data, not logic: pin them to the frame math so neither can be
    // silently changed or accidentally corpus-derived. FIXED, never recalibrated.
    func testAbsoluteCeilingsArePinnedToTheFrameMath() {
        XCTAssertEqual(GateLimits.frameNanoseconds, 1_000_000_000 / 60)
        XCTAssertEqual(GateLimits.frameNanoseconds, 16_666_666)
        XCTAssertEqual(AbsoluteCeiling.scrollFrame.p99Nanoseconds, GateLimits.frameNanoseconds / 10)
        XCTAssertEqual(AbsoluteCeiling.scrollFrame.p99Nanoseconds, 1_666_666)
        XCTAssertEqual(AbsoluteCeiling.discreteAction.p99Nanoseconds, GateLimits.frameNanoseconds)
        XCTAssertEqual(AbsoluteCeiling.discreteAction.p99Nanoseconds, 16_666_666)
    }
```

Replace `testEveryFrameHotPathBudgetIsUnderTheAbsoluteCeiling` in `GateFloorTests.swift`
(comment block included — the old one describes a filter that no longer exists):

```swift
    // THIS TEST IS THE PRODUCT GATE. Under it, the runtime budget_absolute_exceeded
    // branch is unreachable: a budget below its class ceiling means any p99 above the
    // ceiling is also above the budget, and budgetExceeded is evaluated first. So the
    // moment slow drift finally produces a re-derived budget at or above a class
    // ceiling, THIS is what goes red -- at swift test time, before the gate steps in
    // the same host job ever run. The runtime reason is defense-in-depth for a tree
    // where this pin has been removed or budgets were edited without running the suite.
    //
    // Read the binding scenario and its margin from the assertion, never from a number
    // written here: the next re-derivation falsifies it.
    func testEveryGatedBudgetIsUnderItsClassCeiling() {
        let budgets = everyGatedBudget()
        XCTAssertFalse(budgets.isEmpty)

        for budget in budgets {
            let ceiling = budget.mode.absoluteCeiling
            XCTAssertLessThan(
                budget.p99, ceiling.p99Nanoseconds,
                "\(budget.key): regression p99 budget \(budget.p99) is at or above its "
                    + "\(ceiling) ceiling of \(ceiling.p99Nanoseconds) ns. This test is the "
                    + "product gate and this red IS the 60 FPS ceiling firing: fix the code "
                    + "or the architecture — NEVER loosen the ceiling, and never corpus-derive "
                    + "it (contrast budget_stale, which does say re-derive). The only other "
                    + "legitimate response is moving this mode to the other AbsoluteCeiling "
                    + "class, which is a product decision needing its own argument.")
        }
    }
```

- [ ] **Step 2: Run them to verify they fail to compile against the old symbols**

```bash
swift test --filter GateLogicTests
```

Expected: FAIL — compile errors on the remaining `isFrameHotPath` /
`GateLimits.absoluteP99Nanoseconds` references at `GateLogicTests.swift:235`, `:246`,
`:257` and `GateFloorTests.swift`. In Swift a red that is a compile failure is still a
red; the next step resolves it.

- [ ] **Step 3: Update the five remaining test-body references**

In `GateLogicTests.swift`, replace each `GateLimits.absoluteP99Nanoseconds` in a test
**body** with the class it actually means:

- `testAbsoluteCeilingFiresForFrameHotPathMode` (was `:235`) →
  `let obsP99 = AbsoluteCeiling.scrollFrame.p99Nanoseconds + 1`
- `testAbsoluteCeilingDoesNotFireForBulkMode` (was `:246`) →
  `let obsP99 = AbsoluteCeiling.scrollFrame.p99Nanoseconds + 1`
- `testBudgetExceededOutranksAbsoluteCeiling` (was `:257`) →
  `let obsP99 = AbsoluteCeiling.scrollFrame.p99Nanoseconds + 1`

`testAbsoluteCeilingDoesNotFireForBulkMode` stays **symbolic** on purpose, unlike its
new partner: pinned to the *scroll-frame* ceiling it reddens exactly when bulk is
reclassified downward, which is its half of Decision 8's bracket. Re-comment it:

```swift
    // The scroll-frame ceiling must NOT reach bulk. Same latency/budget shape as the
    // frame-hot-path test above; under the two-class model 1.67 ms is far below bulk's
    // own 16.67 ms ceiling, so the assertion survives while its meaning changes: not
    // "bulk has no ceiling" but "bulk is not held to the SCROLL-FRAME ceiling".
    //
    // Symbolic on purpose, where its partner uses a literal: pinned to scrollFrame it
    // is what reddens if bulk is ever dragged back onto the tenth-of-a-frame ceiling.
```

Rename `testGateOutputCarriesAbsoluteCeilingForFrameHotPath` →
`testGateOutputCarriesScrollFrameCeiling` (assertions unchanged: `1666666` and `8.3x`
stay correct for a `.scrollFrame` mode; only the name referenced a classification that
no longer exists).

- [ ] **Step 4: Remove the old symbols**

In `BenchmarkOptions.swift`, delete the whole `var isFrameHotPath: Bool { … }` block and
the comment above it (including the `:91` line naming `GateLimits.absoluteP99Nanoseconds`).

In `BenchmarkModels.swift`, delete `static let absoluteP99Nanoseconds` and rewrite the
two comment blocks:

The block above `GateLimits.frameNanoseconds` — drop the "Applies to frame-hot-path
modes only … are exempt" paragraph and point at the classification instead:

```swift
    // The absolute PRODUCT ceiling -- a distinct axis from the regression band above.
    // The brief's success criterion is 60 FPS, "p95/p99 latency для пересчёта viewport".
    // Every mode is held to one of two ceilings derived from this frame constant; which
    // one is AbsoluteCeiling, chosen per mode by BenchmarkMode.absoluteCeiling. There is
    // no exemption.
    //
    // FIXED: never recalibrated, never corpus-derived. A regression budget is anchored to
    // a moving median and can be legitimately re-derived looser slice by slice; these
    // ceilings are the fixed product targets that catch the slow drift a regression budget
    // re-derives around. On breach the response is to fix the code/architecture, NEVER to
    // loosen the ceiling (contrast budget_stale, which says re-derive the budget). See
    // AGENTS.md "## Gate budgets".
    static let frameNanoseconds: Int64 = 1_000_000_000 / 60          // 16_666_666 (60 FPS)
```

The block inside `gateFailureReason`:

```swift
        // The absolute PRODUCT ceiling, per class (AbsoluteCeiling). Position between
        // budgetExceeded and budgetStale is deliberate but, on a healthy tree,
        // unobservable: GateFloorTests pins every gated budget UNDER its class ceiling,
        // so any p99 above a ceiling is also above that mode's regression budget and the
        // branch above already returned budgetExceeded. This branch therefore has no
        // reachable inhabitant while that pin holds -- which is the design, not an
        // oversight. It is defense-in-depth for a tree where the pin has been removed or
        // budgets edited without running the suite; the product target itself is enforced
        // by testEveryGatedBudgetIsUnderItsClassCeiling, at swift test time. Do not go
        // looking for a hosted budget_absolute_exceeded: the pin fires first, by design.
        //
        // The ordering still matters for that degraded tree: inverted, a blown frame
        // would be reported as a stale budget. It never masks budgetStale, which needs a
        // tiny observed (huge headroom) where this check is silent.
```

- [ ] **Step 5: Run the full suite**

```bash
swift test
```

Expected: PASS, including the three renamed/rewritten pins.

- [ ] **Step 6: AC5 — assert the old model is gone from source and docs**

```bash
if rg -n 'isFrameHotPath|absoluteP99Nanoseconds' Sources Tests AGENTS.md; then
  echo 'FAIL: the removed identifiers survive'; exit 1
else
  echo 'OK: no isFrameHotPath / absoluteP99Nanoseconds in Sources, Tests, AGENTS.md'
fi
```

This will FAIL at this point — `AGENTS.md` still carries them. That is expected; Step 7
fixes it and Step 8 re-runs the scan. `docs/superpowers/**` is deliberately out of
scope: verification records are append-only history and must keep the `exempt` lines
they recorded when they were true.

- [ ] **Step 7: Rewrite the four `AGENTS.md` touch points**

- **`:413`** — replace "It is `GateLimits.absoluteP99Nanoseconds = 1_000_000_000 / 60 / 10
  = 1_666_666` ns (10% of a 60 FPS frame)" with the two-class derivation: both ceilings
  come from `GateLimits.frameNanoseconds` (16_666_666), `.scrollFrame` at a tenth of it
  and `.discreteAction` at the whole frame.
- **`:417`** — "(a passing p99 implies a passing p95 under a uniform ceiling)". True
  *within* one mode, false across modes once two ceilings exist. Tighten to say so.
- **`:420-431`** — the whole "applies to **frame-hot-path** modes only … is **exempt** …
  prints `budget_absolute_p99_ns=exempt`" paragraph, through its closing sentence "So the
  runtime absolute gate can never redden a clean tree." (line 431, **not** 427 — the four
  lines in between are the sentence about the filter, which the new model changes most).
  Replace the whole paragraph with:

  ```markdown
  It applies to **every** gated mode — there is no exemption. Each classifies itself
  through the exhaustive `BenchmarkMode.absoluteCeiling` switch into one of two classes:
  `.scrollFrame` (a tenth of a frame) for viewport compute, incremental recompute after a
  single edit, and every position/geometry query; `.discreteAction` (a whole frame) for
  `bulk_structural_mutation`. A scroll frame must not drop, so the headless core is
  rationed to a tenth of it and the rest belongs to shaping, rasterization, and UI. A bulk
  multi-line paste or range delete is a discrete action the user has already accepted a
  pause for, so it may cost a dropped frame, and the core's budget for it is that whole
  frame's work. Every gated line prints its own `budget_absolute_p99_ns` and
  `headroom_absolute_p99`.

  **The product target is enforced statically, and knowing where matters.**
  `GateFloorTests` pins every gated regression p99 budget UNDER its class ceiling, and
  `GateLogicTests` pins the `.discreteAction` set to exactly `{bulk_structural_mutation}`
  plus both ceilings to the frame math. Because that floor pin holds, any p99 above a
  class ceiling is also above that mode's regression budget, and `budget_exceeded` is
  evaluated first — so the runtime `budget_absolute_exceeded` branch has no reachable
  inhabitant on a healthy tree. That is the design: when slow drift finally produces a
  re-derived budget at or above a ceiling, the **floor pin** goes red at `swift test`
  time, before the gate steps in the same job run, and that red IS the ceiling firing.
  The runtime reason is defense-in-depth for a tree where the pin was removed or budgets
  were edited without running the suite. Do not go hunting for a hosted
  `budget_absolute_exceeded`; read the binding scenario and its margin from the pin
  against the committed budgets, not from a number quoted here, which the next
  re-derivation falsifies.
  ```
- **`:548`** — "`reason=budget_absolute_exceeded` means a frame-hot-path op blew the fixed
  60 FPS ceiling". Generalize to both classes. The three reasons themselves do not change.

Describe the **current** state without naming the removed identifiers — Step 8 scans for
them. The history belongs in the spec and the verification record, both under `docs/`.

- [ ] **Step 8: Re-run the AC5 scans**

```bash
if rg -n 'isFrameHotPath|absoluteP99Nanoseconds' Sources Tests AGENTS.md; then
  echo 'FAIL: the removed identifiers survive'; exit 1
else
  echo 'OK: identifiers gone'
fi
if rg -n 'budget_absolute_p99_ns=exempt' Sources Tests AGENTS.md; then
  echo 'FAIL: the exempt token survives'; exit 1
else
  echo 'OK: exempt token gone'
fi
```

Expected: both `OK`.

- [ ] **Step 9: Release build and the Foundation-free scan**

```bash
swift build -c release || exit 1
if rg -n 'Foundation' Sources/TextEngineCore; then
  echo 'FAIL: Foundation leaked into the core'; exit 1
else
  echo 'OK: core is Foundation-free'
fi
```

- [ ] **Step 10: Commit**

```bash
git add Sources/ViewportBenchmarks Tests/ViewportBenchmarksTests AGENTS.md
git commit -m "refactor: remove isFrameHotPath; the class-ceiling pin is the product gate

Deletes GateLimits.absoluteP99Nanoseconds and BenchmarkMode.isFrameHotPath. With two
ceilings in play a bare 'the absolute ceiling' is no longer a well-formed reference, so
every call site names the class it means.

The floor pin loses its filter and rises from 41 budgets to all 46. Its failure message
is rewritten, not relabelled: this test IS the enforcement point for the product target
-- under it the runtime budget_absolute_exceeded branch has no reachable inhabitant,
since any p99 over a class ceiling is also over that mode's regression budget and
budgetExceeded is checked first. The old message advised 'reclassify the mode as not
frame-hot-path' (a state this slice deletes) and 'raise the ceiling fraction' (the one
response the doctrine forbids).

Exclusion pin becomes a class-membership pin. Frame-math pin covers both ceilings.
AGENTS.md's four touch points now describe the two-class model and say which check
actually enforces it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Execute and record the seven drills (AC8)

**Files:**
- Create: `docs/superpowers/verification/2026-08-08-gate-recalibration-and-bulk-ceiling.md`
  (drills section; the rest is written in Task 7)

**Interfaces:**
- Consumes: the finished Phase 2 model.
- Produces: seven recorded reds. Nothing else depends on this task.

**Method for every drill:** apply the mutation, run the named command, paste the failure
output **verbatim** into the verification document, then `git checkout --` the mutated
file(s) and confirm the tree is clean before the next drill.

```bash
# after each drill, before starting the next:
git checkout -- Sources Tests .github/scripts
if git diff --quiet; then echo 'tree clean'; else echo 'FAIL: mutation survives'; exit 1; fi
```

`git diff --quiet` exits non-zero when there *are* changes, so this is status-sensitive
to the invariant — unlike `git diff`, which exits 0 either way.

- [ ] **Drill 1 — bulk has an absolute ceiling at all (D-8's substance)**

Mutation, in `BenchmarkModels.swift`'s `gateFailureReason`:

```swift
        if mode.absoluteCeiling == .scrollFrame, p99Nanoseconds > mode.absoluteCeiling.p99Nanoseconds {
```

Run: `swift test --filter testAbsoluteCeilingFiresForBulkModeAtItsOwnCeiling`
Expected red: `XCTAssertEqual failed: ("nil") is not equal to ("Optional(budgetAbsoluteExceeded)")`

- [ ] **Drill 2 — the bulk ceiling is one frame, not a tenth**

Mutation, in `BenchmarkOptions.swift`: move `.bulkStructuralMutation` from the
`.discreteAction` arm into the `.scrollFrame` arm.

Run: `swift test --filter testAbsoluteCeilingDoesNotFireForBulkMode`
Expected red: `XCTAssertNil failed: "budgetAbsoluteExceeded"`

Drills 1 and 2 are Decision 8's bracket and are **not** interchangeable: each mutation
reddens exactly one of the two tests. Drill 2's mutation looks like it should redden
Drill 1's test — it does not, because at `p99 = 16_666_667` a 1.67 ms ceiling is
breached just as a 16.67 ms one is, and the reason is `.budgetAbsoluteExceeded` either
way. A drill recorded against the wrong test would look like evidence and be none.

- [ ] **Drill 3 — class membership is pinned**

Mutation, in `BenchmarkOptions.swift`: move `.structuralMutation` into the
`.discreteAction` arm.

Run: `swift test --filter testDiscreteActionClassIsExactlyDocumented`
Expected red: `XCTAssertEqual failed` naming a two-element set containing
`structural_mutation`.

- [ ] **Drill 4 — every budget is under its class ceiling (with expected collateral)**

Mutation: raise `1m_lines_batch_4096`'s `p99BudgetNanoseconds` in
`BulkStructuralMutationBenchmark.swift` above `16_666_666` (e.g. `20_000_000`).

Run: `swift test --filter testEveryGatedBudgetIsUnderItsClassCeiling`
Expected red: `XCTAssertLessThan failed: ("20000000") is not less than ("16666666")`
followed by the rewritten doctrine message.

Then run `swift test` and record `testEveryCommittedBudgetReproducesFromCorpus` going
red as **expected collateral** — raising a committed literal also stops it reproducing
from the corpus. Record both, labelled: an unexplained second failure in a drill log is
indistinguishable from a drill that hit the wrong thing.

- [ ] **Drill 5 — ceiling values are pinned to the frame math (with expected collateral)**

Mutation, in `BenchmarkModels.swift`: `case .scrollFrame: return 1_666_667` (a bare
literal differing from the frame math).

Run: `swift test --filter testAbsoluteCeilingsArePinnedToTheFrameMath`
Expected red: `XCTAssertEqual failed: ("1666667") is not equal to ("1666666")`

Then run `swift test` and record `testGateOutputCarriesScrollFrameCeiling` going red as
expected collateral (its line now reads `budget_absolute_p99_ns=1666667`). Note that
the two bracket tests still pass here — both use `scrollFrame.p99Nanoseconds + 1`, which
moves with the mutation — which is why this drill needs its own target.

- [ ] **Drill 6 — `exempt` is gone from the output**

Mutation, in `BenchmarkSupport.swift`: restore the `if summary.mode.absoluteCeiling ==
.scrollFrame { … } else { output += " budget_absolute_p99_ns=exempt" }` branch.

Run: `swift test --filter testGateOutputCarriesDiscreteActionCeilingForBulk`
Expected red: `XCTAssertTrue failed` on the line missing `budget_absolute_p99_ns=16666666`.

- [ ] **Drill 7 — `gov_p95` names the right term**

Mutation, in `.github/scripts/derive-gate-budgets.sh`: flip the token's `>=` to `<`
(`gov95 = (8 * m95 < 3 * x95) ? "median" : "max"`).

Run: `./.github/scripts/derive-gate-budgets.sh --self-test`
Expected red (verified during planning — record verbatim):

```
self_test=fail label=gov_p95=median when 8*med >= 3*max
  expected: [median]
  actual:   [max]
```

Then run `swift test --filter ScriptSelfTestTests` and record it carrying that into a
red `swift test`.

- [ ] **Step: Confirm the tree is clean and commit the drill record**

```bash
if git diff --quiet -- Sources Tests .github/scripts; then
  echo 'tree clean: every mutation reverted'
else
  echo 'FAIL: a drill mutation survives'; git diff --stat -- Sources Tests .github/scripts; exit 1
fi
swift test || exit 1
git add docs/superpowers/verification/2026-08-08-gate-recalibration-and-bulk-ceiling.md
git commit -m "docs: seven recorded drill reds for the new and changed guarantees

One per guarantee this slice adds or changes, each executed, recorded verbatim, and
reverted. Drills 4 and 5 carry expected collateral reds, labelled as such.

Drills 1 and 2 are Decision 8's bracket and are not interchangeable: each mutation
reddens exactly one of the two bulk tests, and the mutation that looks like it should
redden the new one reddens the old one instead.

AC2's window check needs no drill -- its red is the pre-work state, recorded before the
harvest rather than manufactured after it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Verification record, paper trail, and PR

**Files:**
- Modify: `docs/superpowers/verification/2026-08-08-gate-recalibration-and-bulk-ceiling.md`
- Modify: `docs/superpowers/arcs/wrap.md` (decision log)
- Modify: `docs/superpowers/debt-ledger.md` (D-8, D-9)

**Interfaces:**
- Consumes: everything above.
- Produces: the local half of AC9's checksum evidence, which Task 8 compares against.

- [ ] **Step 1: Run every gated mode locally and capture the gate lines**

```bash
WORK="$(mktemp -d)"
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo 'temp root unavailable'; exit 1; }
echo "WORK=$WORK   # reuse for the remaining steps"
for mode in "" --realistic-provider --variable-height --variable-height-mutation \
            --structural-mutation --bulk-structural-mutation --line-query \
            --line-geometry-query --column-query --column-geometry-query \
            --point-query --point-geometry-query; do
  # $mode is UNQUOTED on purpose and must stay that way: the first element is the empty
  # string (the default pipeline mode takes no flag), and "$mode" would pass a literal
  # empty argument instead of passing none. Every element is a single fixed token, so
  # word-splitting is safe here. The explicit exit is what keeps the loop from
  # swallowing a failing gate.
  swift run -c release ViewportBenchmarks -- $mode --gate >> "$WORK/local-gate.txt" || exit 1
done
LINES="$(grep -c 'gate=pass' "$WORK/local-gate.txt")"
[ "$LINES" -eq 46 ] || { echo "expected 46 gate=pass lines, got $LINES"; exit 1; }
echo "local: 46 scenarios, all gate=pass"
```

- [ ] **Step 2: AC5's output half — assert both tokens on all 46 lines**

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
N="$(grep -c 'budget_absolute_p99_ns=[0-9]' "$WORK/local-gate.txt")"
[ "$N" -eq 46 ] || { echo "numeric budget_absolute_p99_ns on $N lines, want 46"; exit 1; }
N="$(grep -c 'headroom_absolute_p99=' "$WORK/local-gate.txt")"
[ "$N" -eq 46 ] || { echo "headroom_absolute_p99 on $N lines, want 46"; exit 1; }
N="$(grep -c 'budget_absolute_p99_ns=16666666' "$WORK/local-gate.txt")"
[ "$N" -eq 5 ] || { echo "expected 5 bulk lines at the one-frame ceiling, got $N"; exit 1; }
echo 'AC5 output half: 46 numeric ceilings, 46 headrooms, 5 at 16666666'
```

The AC5 scans prove the *old* tokens are gone; these prove the new ones arrived. Counts,
not bare greps — `grep` exits 1 on no match, so a failing case would read as the desired
one.

- [ ] **Step 3: Extract the local checksum tuples (AC9 internal half)**

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
N="$(grep -c 'checksum=' "$WORK/local-gate.txt")"
[ "$N" -eq 46 ] || { echo "expected 46 checksum lines, got $N"; exit 1; }

# Extract (mode|scenario, checksum) and NOTHING else. Two traps:
#   * a greedy `.*checksum=` drags p95_ns/p99_ns/headroom_* along, and those MUST differ
#     local vs hosted (hosted runs 2-3x slower -- the calibration-authority rule), so
#     such a tuple could never diff empty.
#   * scenario alone is not a key: uniform_1m, uniform_100k,
#     1k_lines_20_visible_overscan_0, 100k_lines_80_visible_overscan_5 and
#     1m_lines_200_visible_overscan_50 each appear in SIX modes.
extract_checksums() {
  sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9]+).*/\1|\2\t\3/p' "$1" | sort -u
}
extract_checksums "$WORK/local-gate.txt" > "$WORK/local.txt"
KEYS="$(cut -f1 "$WORK/local.txt" | sort -u | wc -l)"
[ "$KEYS" -eq 46 ] || { echo "expected 46 distinct mode|scenario keys, got $KEYS"; exit 1; }
```

- [ ] **Step 4: Compare against the 46-value cross-slice anchor**

```bash
: "${WORK:?set WORK to the mktemp -d path echoed in Step 1}"
extract_checksums() {
  sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9]+).*/\1|\2\t\3/p' "$1" | sort -u
}
extract_checksums docs/superpowers/verification/2026-07-18-absolute-product-budget.md \
  > "$WORK/anchor.txt"
ANCHOR_N="$(wc -l < "$WORK/anchor.txt")"
[ "$ANCHOR_N" -eq 46 ] || { echo "anchor is $ANCHOR_N tuples, not 46"; exit 1; }
diff "$WORK/anchor.txt" "$WORK/local.txt" \
  || { echo 'checksums drifted since slice 43 -- a workload moved'; exit 1; }
echo 'AC9 cross-slice half: 46 tuples identical to slice 43'
```

Slice 43's document holds 54 raw `checksum=` lines; `sort -u` collapses them to 46
because every repetition agrees. That collapse is what makes the count assertion
meaningful — a document recording two *different* checksums for one `(mode, scenario)`
would yield 47+ and fail here, which is why the count is asserted before the diff.

- [ ] **Step 5: Write the verification document**

Sections, in order, each with the command and its verbatim output:

1. Pre-work state — AC2's 16 offenders (Task 2 Step 1), and the pre-harvest `gov_p95`
   distribution (Task 1 Step 5: 45 median / 1 max).
2. Provenance — the two `gh run view` host-job checks (Task 2 Step 2).
3. Harvest — the `--dry-run` plan, the append, the append-only `git diff --numstat`.
4. AC2 — window flushed: 20 ids, zero offenders, zero pre-`29692848870` ids.
5. AC3 — the full swept output with `gov_p95`, and the median/max counts.
6. AC4 — the directional budget diff, with the tightened set called out as the
   watch-list for the hosted run.
7. Decision 10 — the bulk `budget_p99` and its margin under `16_666_666`.
8. Local gate run — 46 `gate=pass`, the AC5 counts, the 5 bulk lines at `16666666`.
9. AC9 local half — the 46 `(mode|scenario, checksum)` tuples and the empty anchor diff.
10. Drills — the seven recorded reds (already committed in Task 6; cross-reference).
11. `swift test` and `swift build -c release` output.

Leave a stub section 12 for Task 8's hosted evidence.

- [ ] **Step 6: Arc decision-log entry**

Append to `docs/superpowers/arcs/wrap.md`:

```markdown
- 2026-08-08 — **Slice 52 selected and shipped: the calibration route.** The slice-51
  review's lean was Option A (map node 3, y→row); the **user chose Option C** after
  live evidence at selection time showed the calibration base was ten slices stale —
  the corpus unappended since 2026-07-18, zero post-slice-45 runs in the N=20 window.
  The same call gave **D-8** the product target it had waited on since slice 43 (one
  whole 60 FPS frame for a discrete action), converting it from "cannot be scheduled"
  into ordinary work. Slice 52 advances **no wrap criterion** and consumes **no map
  node**, like slices 48 and 51 — but it is not housekeeping: the wrap brief's fourth
  criterion binds future wrap gates to *this* recipe («по существующему рецепту
  калибровки (harvest → derive)») and to the absolute 60 FPS ceiling, so a stale
  evidence base and a pre-wrap boolean were both de-risking work for a named criterion.
  After it, a future `wrap_compute` gate calibrates against evidence including the last
  ten slices, and a future wrap mode classifies itself into a ceiling class rather than
  inheriting a flag designed before wrap existed. **Node 3 (y→row) remains the lean**
  for the next feature slice.
```

- [ ] **Step 7: Ledger updates**

In `docs/superpowers/debt-ledger.md`:

- **D-8** status → `discharged([slice 52](...), [PR #N](...))` with a one-line statement
  of what landed: total two-class `AbsoluteCeiling`, bulk at `frameNanoseconds`, floor
  pin covering all 46.
- **D-9** — amend the statement in place (never silently re-scope; the D-15 precedent
  from slice 51). The shape-transition half is discharged by fact: record that the
  window now holds no pre-slice-45 run. The p95 thin-axis half stays `open`, its
  statement carrying **the rule and the ratio, not a list**: a p95 budget is
  median-governed exactly when `max / med <= 2.67`, which after the harvest is *n* of 46
  — and `gov_p95` now prints it, so the observation is re-derivable rather than
  transcribed. A named list would run to nearly every scenario and be stale on arrival.

- [ ] **Step 8: Full local verification**

```bash
swift test || exit 1
swift build -c release || exit 1
if rg -n 'Foundation' Sources/TextEngineCore; then
  echo 'FAIL: Foundation leaked'; exit 1
else
  echo 'OK: core Foundation-free'
fi
```

- [ ] **Step 9: Commit and open the PR**

```bash
git add docs/superpowers
git commit -m "docs: Slice 52 verification record, arc entry, and ledger updates

D-8 discharged. D-9 amended in place: its shape-transition half is now discharged by
fact (no pre-slice-45 run remains in the window), its p95 thin-axis half stays open
carrying the rule and the ratio rather than a scenario list -- a list would run to
nearly every scenario and be stale at the next re-derivation, and gov_p95 now makes it
re-derivable on demand.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push -u origin slice-52-gate-recalibration-and-bulk-ceiling
gh pr create --title "Slice 52: gate recalibration + bulk absolute ceiling (D-9 / D-8)" \
  --body "$(cat <<'BODY'
Refreshes every gated budget against hosted evidence including the last ten slices, and
replaces the frame-hot-path exemption with a total two-class absolute product ceiling.

**Phase 0** — `derive-gate-budgets.sh` prints `gov_p95=median|max`, with the first
standing self-test on its budget arithmetic.

**Phase 1** — corpus appended (idempotent, provenance-checked by hand while D-7 stays
deferred); all modes re-derived; every changed literal updated in one commit with the
rows, since splitting them reddens `testEveryCommittedBudgetReproducesFromCorpus`.
D-9's shape-transition half is discharged by fact: no window run contributes more than
one `realistic_provider` row.

**Phase 2** — `AbsoluteCeiling { scrollFrame, discreteAction }` replaces
`isFrameHotPath: Bool`; `bulk_structural_mutation` gets one whole 60 FPS frame
(16_666_666 ns), FIXED. The floor pin loses its filter (41 → 46 budgets) and its
failure message is rewritten to carry the doctrine — that test is the enforcement point
for the product target, and the runtime reason is defense-in-depth.

Seven drills recorded verbatim. No engine or provider source changed; 46 benchmark
checksums byte-identical to slice 43's anchor.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

---

### Task 8: Hosted proof at step level (AC9)

**Files:**
- Modify: `docs/superpowers/verification/2026-08-08-gate-recalibration-and-bulk-ceiling.md`
  (section 12) — a docs-only follow-up PR, matching the pattern of slices 44/45/49/50.

**Interfaces:**
- Consumes: Task 7's local checksum set.
- Produces: nothing downstream. This discharges AC9.

**Read step logs, never job conclusions.** A green job can hide a dead
`continue-on-error` step — the slice-16 trap.

- [ ] **Step 1: Record the PR-head run**

Wait for the PR-head run, then read the host job's step output. Confirm and record:
twelve blocking gate steps green; 46 scenario lines reporting `gate=pass`;
`swift test` green; the five bulk lines carrying `budget_absolute_p99_ns=16666666`
where they previously read `exempt`.

**This run is load-bearing, not a formality.** It is the only empirical control on the
tightening risk. Compare a `budget_exceeded` here against Task 2 Step 9's tightened
watch-list before concluding anything: a failure on a scenario in that list is the
window doing its job plus a noisy runner, not an engine regression.

- [ ] **Step 2: Merge, then record the post-merge push run**

Same step-level checks on the post-merge `push` run. Anchor proof of merged code in the
post-merge run, not only the PR run.

- [ ] **Step 3: Three-way checksum diff**

Extract tuples from both hosted logs with the **same** `extract_checksums` function used
locally (a tuple parsed two ways can differ for reasons unrelated to the engine), and
assert the three sets diff empty pairwise:

```bash
WORK="$(mktemp -d)"
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo 'temp root unavailable'; exit 1; }
: "${PR_RUN:?set PR_RUN to the PR-head run id}"
: "${PUSH_RUN:?set PUSH_RUN to the post-merge push run id}"
extract_checksums() {
  sed -nE 's/.*mode=([a-z_]+).*scenario=([^ ]+).*checksum=([0-9]+).*/\1|\2\t\3/p' "$1" | sort -u
}
gh run view "$PR_RUN" --log > "$WORK/pr.log" || { echo 'PR log unavailable'; exit 1; }
gh run view "$PUSH_RUN" --log > "$WORK/push.log" || { echo 'push log unavailable'; exit 1; }
extract_checksums "$WORK/pr.log" > "$WORK/pr.txt"
extract_checksums "$WORK/push.log" > "$WORK/push.txt"
for f in pr push; do
  N="$(wc -l < "$WORK/$f.txt")"
  [ "$N" -eq 46 ] || { echo "$f holds $N tuples, want 46"; exit 1; }
done
diff "$WORK/pr.txt" "$WORK/push.txt" || { echo 'PR-head and push checksums differ'; exit 1; }
echo 'AC9 internal half: three environments agree on all 46 tuples'
```

Record all three sets. The internal diff proves three environments agree — three
identically wrong sets would pass it — so the 46-value cross-slice anchor from Task 7
Step 4 is what actually proves the workload did not drift.

- [ ] **Step 4: Commit the hosted evidence**

```bash
git add docs/superpowers/verification/2026-08-08-gate-recalibration-and-bulk-ceiling.md
git commit -m "docs: AC9 hosted proof at step level for Slice 52

PR-head and post-merge push runs, both green at step level: twelve blocking gate steps,
46 gate=pass lines, swift test green, five bulk lines at budget_absolute_p99_ns=16666666.

Three-way (mode|scenario, checksum) tuple diff empty pairwise across local, PR-head, and
push, and equal to slice 43's 46-value anchor -- so no workload moved.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Acceptance Criteria Coverage

| AC | Discharged by |
|---|---|
| AC1 — idempotent, provenance-checked append | Task 2 Steps 2, 4, 5, 6 |
| AC2 — window flushed, checked directly | Task 2 Steps 1 (pre-work red) and 7 |
| AC3 — thin axis observed mechanically | Task 1 (token + self-test), Task 2 Step 8 |
| AC4 — budgets reproduce + directional diff | Task 2 Steps 9, 13 |
| AC5 — total classification | Task 4 Step 5, Task 5 Steps 6/8, Task 7 Step 2 |
| AC6 — bulk ceiling pinned | Task 5 Step 1 (both pins) |
| AC7 — full-coverage floor pin + doctrine message | Task 5 Step 1 |
| AC8 — seven recorded reds | Task 6 |
| AC9 — hosted proof, step level, checksums | Task 7 Steps 3-4, Task 8 |
| AC10 — paper trail | Task 7 Steps 5-7, Task 8 |

## Halt Conditions

Stop and return to the user, do not work around:

1. **Bulk's re-derived `budget_p99` reaches `16_666_666`** (Task 2 Step 10). Return with
   the diagnosis attached — median moved (genuine drift, fix the code) vs `3 × max`
   governing alone (one anomalous hosted sample, a user decision).
2. **A frame-hot-path budget crosses `1_666_666`** (Task 2 Step 11). Phase 2 must not be
   written on top of it.
3. **The window still holds pre-slice-45 runs after `--limit 100`** (Task 2 Step 7). The
   response is a wider limit and a re-run, never a weakened criterion.
4. **The 46-tuple checksum diff is non-empty** (Task 7 Step 4). A workload moved, which
   this design did not authorize.
