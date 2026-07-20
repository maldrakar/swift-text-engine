# WASM Required-Check Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the CI job and required-status-check context `WASM cross-target observation` → `WASM cross-target compile` together with the `Main` ruleset, pin all three job `name:` fields to their contexts, and fold in Slice 46's five P3 residuals.

**Architecture:** A test-first rename — the new pin is written expecting the *new* name, fails against the current workflow, and the rename makes it pass. The ruleset half cannot be tested locally and is executed as an explicit, confirmed `gh api` sequence with three recorded snapshots. Two shell fixes harden `cross-target-compile.sh`'s unknown-kind and bundle-failure paths behind `--self-test`.

**Tech Stack:** GitHub Actions YAML, Bash (`set -uo pipefail`), Swift/XCTest, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-07-20-wasm-required-check-rename-design.md`

## Global Constraints

- **No Foundation in `Sources/TextEngineCore`.** `rg -n "Foundation" Sources/TextEngineCore` must be empty, `exit=1`.
- **No engine, provider, budget, corpus, or calibration-script change.** `Sources/TextEngineCore`, `Sources/TextEngineReferenceProviders`, every budget literal, the corpus TSV, `derive-gate-budgets.sh`, and `harvest-gate-corpus.sh` must all diff **empty** at the end.
- **The only `Sources/` edit in this slice is one comment** in `Sources/ViewportBenchmarks/BenchmarkModels.swift` (Task 7). Gate checksums must stay byte-identical to the Task 1 baseline.
- **`cross-target-compile.sh` runs `set -uo pipefail` with NO `set -e`.** A non-zero exit from a function called inside `$(...)` is **swallowed**. Never express a safety decision as an exit code inside a command substitution.
- **Conventional commits**, one logical step per commit: `feat:`, `test:`, `refactor:`, `docs:`, `ci:`, `fix:`.
- **Branch:** `slice-47-wasm-required-check-rename` (already created; spec committed at `9df29a6`).
- **Ruleset id:** `Main`, `17656807`, repo `maldrakar/swift-text-engine`.

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `.github/workflows/swift-ci.yml` | The three stale-name sites; line 217 is the contract | 2, 3 |
| `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` | The new `name:` ↔ context pin; `wasmJobKey` constant | 2, 3 |
| `.github/scripts/cross-target-compile.sh` | Unknown-kind fail-closed (D4); bundle-failure precheck (D5/D6) | 5, 6 |
| `AGENTS.md` | Job description, required-check policy, guard enumeration, Commands caveat, frozen `580 µs` | 4, 7 |
| `Sources/ViewportBenchmarks/BenchmarkModels.swift` | Frozen `580 µs` comment (comment only) | 7 |
| `docs/superpowers/verification/2026-07-20-wasm-required-check-rename.md` | Evidence record | 8, 9, 10 |

**Task ordering rationale:** Task 1 must run **before any edit** (it captures the byte-identity baseline). Tasks 2–7 are local and independently reviewable. Tasks 8–10 are the outward-facing sequence and must run in order.

---

### Task 1: Capture the pre-change baseline

**Why first:** AC9 asserts gate checksums are byte-identical. The remembered "45" predates Slice 45's twelfth gate and no verification record since re-confirms it, so the baseline must be **measured**, not recalled — and it must be measured before the first edit.

**Files:**
- Create: `/private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/7a551b6e-04d6-459e-b196-deeaae6a72d7/scratchpad/baseline-checksums.txt`
- Create: `/private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/7a551b6e-04d6-459e-b196-deeaae6a72d7/scratchpad/baseline-preconditions.txt`

**Interfaces:**
- Produces: `baseline-checksums.txt` (sorted `checksum=` lines) and its line count, consumed by Task 8's AC9 comparison.

- [ ] **Step 1: Confirm the tree is clean and on the right commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git status --short          # expect empty
git log --oneline -1        # expect 9df29a6 docs: correct Decision 4's fail-open fix...
```

- [ ] **Step 2: Record the no-open-PRs precondition**

```bash
{
  echo "=== gh pr list --state open @ $(git rev-parse --short HEAD) ==="
  gh pr list --state open
  echo "(empty above means the precondition holds)"
} > "$SCRATCH/baseline-preconditions.txt"
cat "$SCRATCH/baseline-preconditions.txt"
```

Where `SCRATCH=/private/tmp/claude-501/-Users-aabanschikov-swift-text-engine/7a551b6e-04d6-459e-b196-deeaae6a72d7/scratchpad`.

Expected: no PR rows. If any PR is listed, **stop** — Decision 1's window is only zero-blast-radius while nobody else has a PR open. Report to the user before continuing.

- [ ] **Step 3: Capture the gate-checksum baseline**

```bash
cd /Users/aabanschikov/swift-text-engine
swift build -c release
for flag in "" "--variable-height" "--variable-height-mutation" "--structural-mutation" \
            "--bulk-structural-mutation" "--line-query" "--line-geometry-query" \
            "--column-query" "--column-geometry-query" "--point-query" \
            "--point-geometry-query" "--realistic-provider"; do
  swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks \
    -- $flag --gate
done | rg -o 'scenario=\S+ .*checksum=\S+' | sort > "$SCRATCH/baseline-checksums.txt"
wc -l < "$SCRATCH/baseline-checksums.txt"
```

Expected: a non-zero line count. **Record that number** — it, not "45", is what Task 8 compares against.

- [ ] **Step 4: Record the gate=pass tally**

```bash
cd /Users/aabanschikov/swift-text-engine
for flag in "" "--variable-height" "--variable-height-mutation" "--structural-mutation" \
            "--bulk-structural-mutation" "--line-query" "--line-geometry-query" \
            "--column-query" "--column-geometry-query" "--point-query" \
            "--point-geometry-query" "--realistic-provider"; do
  swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks \
    -- $flag --gate
done | rg -c 'gate=pass' | tee -a "$SCRATCH/baseline-preconditions.txt"
```

Expected: `46` (Slice 46's review records this tally). If it differs, record the actual number and use it in Task 8 — do not assume.

- [ ] **Step 5: Record the baseline test count**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test 2>&1 | rg 'Executed .* tests' | tail -2 | tee -a "$SCRATCH/baseline-preconditions.txt"
```

Expected: `314` tests, `0` failures (plus the empty Swift Testing harness line, which is not a failure).

- [ ] **Step 6: No commit**

This task writes only to the scratchpad. Nothing to commit.

---

### Task 2: Pin job names to required-check contexts, and rename the context

**Files:**
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift:25-26` (constants), plus a new test method
- Modify: `.github/workflows/swift-ci.yml:217` (`name:` — the contract line only)

**Interfaces:**
- Produces: `requiredCheckContexts: [(jobKey: String, context: String)]` and `iosJobKey`, both read by Task 3.
- Consumes: `jobLevelValue(of:jobKey:)` (Slice 46; reads 4-space job-level keys) and `workflowPath`.

- [ ] **Step 1: Add the job-key constants and the context table**

In `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift`, replace lines 25-26:

```swift
private let hostJobKey = "host-tests-and-benchmark-gate"
private let wasmJobKey = "wasm-cross-target-observation"
```

with:

```swift
private let hostJobKey = "host-tests-and-benchmark-gate"
private let iosJobKey = "ios-cross-target-compile"
private let wasmJobKey = "wasm-cross-target-observation"

// Each job's `name:` IS its required-status-check context in ruleset `Main`
// (id 17656807) on maldrakar/swift-text-engine. GitHub matches required checks by that
// exact string, and the ruleset lives OUTSIDE this repository -- so renaming a job here
// without a matching `gh api` update leaves every open PR waiting forever on a context
// no run will ever report. `swift test` has no network, so this pin canNOT prove the
// two agree; it makes the repository half LOUD, and carries the ruleset id and the
// update command in its failure message so whoever trips it knows what else to change.
// Slice 47 renamed the WASM context and this table together.
private let requiredCheckContexts: [(jobKey: String, context: String)] = [
    (hostJobKey, "Host tests and benchmark gate"),
    (iosJobKey, "iOS cross-target compile"),
    (wasmJobKey, "WASM cross-target compile"),
]
```

Note `wasmJobKey` still holds the **old** job key here — the job key is renamed in Task 3. Only the *context* (the `name:` value in the table) is the new string, so this step's failure is a clean name mismatch rather than a "job not found" error.

- [ ] **Step 2: Write the failing test**

Add this method to the test class, immediately after `testWasmContainerVersionMatchesPinnedSdkURL`:

```swift
    // The `name:` of each job is the exact string GitHub matches required status checks
    // against. Nothing in this repo enforced that until Slice 47, so a rename could
    // silently orphan a required context -- the hazard Slice 47 itself had to sequence
    // around. All three required jobs are pinned, not just WASM: the coupling is
    // identical for all three and nobody will think about job renames again for many
    // slices.
    func testJobNamesMatchRequiredCheckContexts() throws {
        for (jobKey, context) in requiredCheckContexts {
            guard let name = try jobLevelValue(of: "name", jobKey: jobKey) else {
                XCTFail("\(workflowPath): no name: key in job \(jobKey)")
                continue
            }
            XCTAssertEqual(
                name, context,
                "\(workflowPath): job \(jobKey) is named \"\(name)\", but ruleset Main "
                    + "(id 17656807) on maldrakar/swift-text-engine requires the "
                    + "status-check context \"\(context)\". GitHub matches required "
                    + "checks by this exact string, and the ruleset lives outside this "
                    + "repository -- so renaming a job without updating the ruleset "
                    + "wedges every open PR on a context nothing reports. Change BOTH, "
                    + "in the same slice: this table, and the ruleset via\n"
                    + "  gh api repos/maldrakar/swift-text-engine/rulesets/17656807 "
                    + "--method PUT --input <edited.json>\n"
                    + "See docs/superpowers/specs/"
                    + "2026-07-20-wasm-required-check-rename-design.md for the safe "
                    + "drop-rename-readd sequence.")
        }
    }
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter testJobNamesMatchRequiredCheckContexts 2>&1 | tail -20
```

Expected: **FAIL**, on the WASM row only, with `is named "WASM cross-target observation", but ruleset Main (id 17656807) ... requires ... "WASM cross-target compile"`. The host and iOS rows must pass — if either fails, the expected context strings in the table are wrong; re-read them from the live ruleset before continuing.

- [ ] **Step 4: Rename the contract line in the workflow**

In `.github/workflows/swift-ci.yml`, change line 217 only:

```yaml
    name: WASM cross-target observation
```

to:

```yaml
    name: WASM cross-target compile
```

Do **not** touch the job key (line 216) or the echo (line 271) yet — those are Task 3.

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test --filter testJobNamesMatchRequiredCheckContexts 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 6: Run the full suite**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test 2>&1 | rg 'Executed .* tests' | tail -2
```

Expected: `315` tests, `0` failures (314 + 1 new).

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift .github/workflows/swift-ci.yml
git commit -m "$(cat <<'EOF'
test: pin job names to their required-check contexts, and rename WASM's

Each job's name: is the exact string GitHub matches required status checks
against, and nothing enforced that. A rename could silently orphan a required
context -- the hazard this slice has to sequence around. All three required
jobs are pinned; the failure message carries ruleset Main's id and the gh api
command so whoever trips it knows the ruleset must move too.

The WASM job's name: becomes "WASM cross-target compile", which is what the
new pin demanded. The ruleset still requires the old string at this commit --
that is expected, and is sequenced deliberately in the slice plan.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Rename the remaining two workflow sites

**Files:**
- Modify: `.github/workflows/swift-ci.yml:216` (job key), `:271` (docs-only echo)
- Modify: `Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift` (`wasmJobKey` constant)

**Interfaces:**
- Consumes: `wasmJobKey` from Task 2.

These three lines must change in one commit: `wasmJobKey` is how `jobLines` finds the job, so renaming the job key without the constant breaks every WASM test in the file.

- [ ] **Step 1: Rename the job key in the workflow**

Line 216: `  wasm-cross-target-observation:` → `  wasm-cross-target-compile:`

- [ ] **Step 2: Rename the echo's job value**

Line 271:

```yaml
        run: echo "mode=docs_only_pr job=wasm-cross-target-observation result=success"
```

to:

```yaml
        run: echo "mode=docs_only_pr job=wasm-cross-target-compile result=success"
```

- [ ] **Step 3: Update the test constant**

```swift
private let wasmJobKey = "wasm-cross-target-compile"
```

- [ ] **Step 4: Run the full suite**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test 2>&1 | rg 'Executed .* tests' | tail -2
```

Expected: `315` tests, `0` failures. A "no job keyed …" failure means one of the three sites was missed.

- [ ] **Step 5: Verify no stale name remains in the workflow or tests**

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n --hidden -U 'wasm-cross-target-observation|WASM cross-target\s+observation' \
  --glob '!docs/**' --glob '!.git/**' .
```

Expected: only `AGENTS.md` rows remain (lines 261, 273–274, 288) — those are Task 4. `.github/` and `Tests/` must be clean. `--hidden` is required or `.github/` is silently skipped; `-U` is required or the wrapped `AGENTS.md:273-274` occurrence is missed.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add .github/workflows/swift-ci.yml Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift
git commit -m "$(cat <<'EOF'
ci: rename the WASM job key and its docs-only echo

The job key is not a required-check context and no needs: references it, but
leaving it stale re-seeds exactly the rot this slice removes. wasmJobKey moves
in the same commit because jobLines() finds the job by that key.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Update AGENTS.md for the rename

**Files:**
- Modify: `AGENTS.md:141-146` (guard enumeration), `:261` (job description), `:273-278` (Known wart, deleted), `:288` (policy paragraph), `:312` (Last verified)

- [ ] **Step 1: Rename the job description heading**

Line 261: `- **WASM cross-target observation** on \`ubuntu-latest\` with` → `- **WASM cross-target compile** on \`ubuntu-latest\` with`

- [ ] **Step 2: Delete the "Known wart" block**

Remove these six lines (273–278) entirely:

```
  **Known wart**: the job/context is still *named* `WASM cross-target
  observation` even though it now blocks — renaming it (and updating the `Main`
  ruleset's required-check context to match) is deliberately deferred to a
  follow-up repo-policy slice, so the required-check context does not move out
  from under an in-flight PR. Do not rename it as a drive-by edit.
```

(plus the blank-line handling needed to leave one blank line before the following `A \`continue-on-error\` step cannot be a gate.` paragraph).

- [ ] **Step 3: Update the required-check policy paragraph**

Line 288: `gate\`, \`iOS cross-target compile\`, and \`WASM cross-target observation\`.` → `gate\`, \`iOS cross-target compile\`, and \`WASM cross-target compile\`.`

- [ ] **Step 4: Update the Last verified line**

Line 312 currently reads:

```
Last verified: 2026-06-16 via `gh api`; see
`docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`.
```

Replace with:

```
The WASM context was renamed from `WASM cross-target observation` in Slice 47;
the ruleset was updated in the same slice, via a drop-rename-readd sequence
(the context is the job's `name:`, and the ruleset lives outside the repo, so
the two cannot land atomically). `WorkflowShapeTests`'s
`testJobNamesMatchRequiredCheckContexts` pins each job's `name:` to its context
at `swift test` time — it cannot reach the ruleset, so it makes the repository
half loud rather than proving the pair agrees.
Last verified: 2026-07-20 via `gh api`; see
`docs/superpowers/verification/2026-07-20-wasm-required-check-rename.md` and
`docs/superpowers/verification/2026-06-16-swift-ci-required-checks.md`.
```

- [ ] **Step 5: Document the new pin in the guard enumeration**

In the `WorkflowShapeTests.swift` description (around lines 141–146), after the sentence ending `…and it sits between its ordering anchors (the tail order is point-query < point-geometry < realistic < memory-shape).`, insert:

```
  It also carries `testJobNamesMatchRequiredCheckContexts`, a pin of a different
  *class* from the rest of the file: every other guard here compares the workflow
  against something else in the repository, but this one pins each job's `name:`
  to its required-status-check context in the `Main` ruleset — GitHub
  configuration that lives **outside** the repo and that `swift test` cannot
  reach. So it does not prove the pair agrees; it makes the repository half
  loud, and its failure message carries the ruleset id and the `gh api` command
  because the realistic drift (rename job + table together, forget the ruleset)
  is exactly what it cannot catch.
```

- [ ] **Step 6: Verify AC1 — no stale name anywhere outside `docs/`**

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n --hidden -U 'wasm-cross-target-observation|WASM cross-target\s+observation' \
  --glob '!docs/**' --glob '!.git/**' .
echo "exit=$?"
```

Expected: no output, `exit=1`. Historical slice docs under `docs/` keep the old name deliberately — they record when it was true.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add AGENTS.md
git commit -m "$(cat <<'EOF'
docs: retire the WASM 'observation' name from AGENTS.md

Renames the job description and the required-check policy paragraph, deletes
the Known wart block the rename discharges, and documents the new
testJobNamesMatchRequiredCheckContexts pin in the guard enumeration -- that
block is the map agents read instead of the file, and this pin is the first
that reaches outside the repository to GitHub configuration.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Fail closed on an unknown WASM kind (Decision 4)

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh:168-180` (`wasm_kind_blocking`), `:512-521` and `:530-533` (the two `case "$kind"` dispatches), `run_self_test` (~line 337)

**Interfaces:**
- Produces: `wasm_kind_blocking` remains `(kind) -> "true"|"false"` — **total**, never erroring. Task 6 does not depend on it.

**Critical context:** the script is `set -uo pipefail` with **no `set -e`**, and the only caller is `LAST_BLOCKING="$(wasm_kind_blocking "$kind")"` at `:529`. A non-zero exit there is swallowed: `LAST_BLOCKING` becomes `""`, `wasm_skip_result` (`:187-196`) reads it as non-blocking and yields `"skipped"`, and `count_blocking_failures` (`:73-83`) counts only `blocking == "true"` — so the target silently un-blocks and the script exits 0. That is why the default returns a **value**, and the hard exit lives at the dispatch sites, whose call sites (`:579`, `:588`, `:610`, `:611`) are plain statements where an `exit` actually propagates.

- [ ] **Step 1: Write the failing self-test assertion**

In `run_self_test`, immediately after the `embedded_ladder_demotes_to_observational` assertion (~line 338), add:

```bash
  # Slice 47 (P3 #3) — an unknown kind must fail CLOSED. This is asserted as a VALUE,
  # not an exit code, and deliberately so: assert_equal runs its argument in a command
  # substitution, and with no `set -e` an erroring helper would yield "" here and pass
  # this assertion silently -- while also un-blocking the target at runtime.
  assert_equal "true" "$(wasm_kind_blocking bogus_kind 2>/dev/null)" "unknown_kind_blocks"
```

- [ ] **Step 2: Run the self-test to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
./.github/scripts/cross-target-compile.sh --self-test
```

Expected: **FAIL** on `unknown_kind_blocks` — got `false`, want `true`.

- [ ] **Step 3: Make the pure helper total and fail-closed**

Replace `wasm_kind_blocking`'s `*)` arm (currently returning `false`) so the function reads:

```bash
wasm_kind_blocking() {
  case "$1" in
    wasm) printf 'true' ;;
    wasm_embedded)
      if [[ "${CROSS_TARGET_WASM_EMBEDDED_BLOCKING:-true}" == "false" ]]; then
        printf 'false'
      else
        printf 'true'
      fi
      ;;
    *)
      # Fail CLOSED. Returning a non-zero exit instead would be WORSE than the `false`
      # this replaces: the sole caller is `LAST_BLOCKING="$(wasm_kind_blocking "$kind")"`
      # and this script has no `set -e`, so the error is swallowed and LAST_BLOCKING
      # becomes "" -- which wasm_skip_result reads as non-blocking ("skipped") and
      # count_blocking_failures never counts. `false` at least PRINTS blocking=false in
      # the target line; "" prints an empty field and is equally uncounted. The hard
      # exit for an unknown kind lives at the dispatch sites below, where it is not
      # inside a command substitution and can actually propagate.
      echo "warn=unknown_wasm_kind fn=wasm_kind_blocking kind=$1 defaulting=blocking" >&2
      printf 'true'
      ;;
  esac
}
```

- [ ] **Step 4: Add the hard-exit default to `prepare_wasm_sdk`'s dispatch**

The trailing `case "$kind"` in `prepare_wasm_sdk` (`:512-521`) has **no** `*)` arm today, so an unknown kind falls through with empty globals. Add:

```bash
    *)
      echo "error=unknown_wasm_kind fn=prepare_wasm_sdk kind=${kind}" >&2
      exit 1
      ;;
```

as the final arm, before the closing `esac`.

- [ ] **Step 5: Add the hard-exit default to `compile_wasm_package_for_kind`'s dispatch**

Same for the `case "$kind"` at `:530-533` (also has no `*)` today):

```bash
    *)
      echo "error=unknown_wasm_kind fn=compile_wasm_package_for_kind kind=${kind}" >&2
      exit 1
      ;;
```

- [ ] **Step 6: Run the self-test to verify it passes**

```bash
cd /Users/aabanschikov/swift-text-engine
./.github/scripts/cross-target-compile.sh --self-test
bash -n .github/scripts/cross-target-compile.sh && echo "syntax ok"
```

Expected: `self_test=pass`, and `syntax ok`.

- [ ] **Step 7: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add .github/scripts/cross-target-compile.sh
git commit -m "$(cat <<'EOF'
fix: fail closed on an unknown WASM kind

wasm_kind_blocking's *) arm returned false -- fail-open inside a fail-closed
design (Slice 46 review P3 #3). It now returns true and warns.

Deliberately a value, not an exit code. The script is set -uo pipefail with no
set -e and the sole caller is a command substitution, so an erroring helper
would leave LAST_BLOCKING="", which wasm_skip_result reads as non-blocking and
count_blocking_failures never counts -- quieter than the bug it replaces. The
hard exit goes at the two dispatch sites instead, neither of which had a *)
arm at all, and whose call sites are plain statements where exit propagates.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Short-circuit the drift path with its own reason (Decisions 5 & 6)

**Files:**
- Modify: `.github/scripts/cross-target-compile.sh` — new pure helper near `wasm_skip_result` (~`:196`); `WASM_BUNDLE_INSTALL_FAILED` declaration (`:368`); `prepare_wasm_sdk`'s install branch (`:490-510`); `run_self_test`

**Interfaces:**
- Produces: `wasm_install_precheck(url, recorded_reason) -> "" | "sdk_unavailable" | "<recorded_reason>"`.
- Renames the global `WASM_BUNDLE_INSTALL_FAILED` (`"true"`/`""`) → `WASM_BUNDLE_FAILED_REASON` (the skip reason, or `""`).

**Context:** `prepare_wasm_sdk` runs per kind, and both kinds come from one bundle. Slice 46 short-circuited the *install-failure* path but not the sibling `sdk_unresolved_after_install` (drift) path, so the second kind re-runs a full bounded-retry ladder against an already-installed SDK. What it then reports is not established by any record — the fix is the same either way, and the pure helper pins the desired behavior independent of what real `swift sdk install` does.

- [ ] **Step 1: Write the failing self-test assertions**

In `run_self_test`, after the `skip_on_observational_is_skip` assertion, add:

```bash
  # Slice 47 (P3 #2, #4) — the shared-bundle precheck, now a PURE helper so the
  # short-circuit is reachable from --self-test at all. Slice 46 could only exercise it
  # by a live run with a bogus URL.
  assert_equal "sdk_unavailable" "$(wasm_install_precheck "" "")" "precheck_no_url"
  assert_equal "" "$(wasm_install_precheck http://b "")" "precheck_proceeds"
  assert_equal "sdk_install_failed" \
    "$(wasm_install_precheck http://b sdk_install_failed)" \
    "precheck_short_circuits_install_failure"
  # The P3 #2 fix proper: the DRIFT path short-circuits with ITS OWN reason. Before
  # this, the second kind re-ran the whole ladder and could report a different reason
  # than the first, reading as two unrelated faults instead of one.
  assert_equal "sdk_unresolved_after_install" \
    "$(wasm_install_precheck http://b sdk_unresolved_after_install)" \
    "precheck_short_circuits_drift_with_same_reason"
  # No URL wins over a recorded failure: with nothing configured to install, the
  # actionable reason is the missing configuration.
  assert_equal "sdk_unavailable" \
    "$(wasm_install_precheck "" sdk_install_failed)" "precheck_no_url_precedence"
```

- [ ] **Step 2: Run the self-test to verify it fails**

```bash
cd /Users/aabanschikov/swift-text-engine
./.github/scripts/cross-target-compile.sh --self-test
```

Expected: **FAIL** — `wasm_install_precheck: command not found`, or an `assert_equal` mismatch on `precheck_no_url`.

- [ ] **Step 3: Add the pure helper**

Immediately after `wasm_skip_result`'s closing `}` (~line 196):

```bash
# Decide what prepare_wasm_sdk should do for a kind BEFORE touching the network.
# Prints one of:
#   ""                    -> proceed to a real install attempt
#   "sdk_unavailable"     -> no URL configured; nothing to install
#   "<recorded reason>"   -> the shared bundle already failed definitively; short-
#                            circuit with the SAME reason the first kind reported
#
# Both WASM kinds come from ONE swift.org bundle and prepare_wasm_sdk runs per kind.
# Once that bundle has definitively failed -- whether the install failed or it installed
# but yielded no resolvable id -- the second kind must not burn a second bounded-retry
# ladder against it, and must report the same reason, so the log reads as one fault.
wasm_install_precheck() {
  local url="$1" recorded_reason="$2"
  if [[ -z "$url" ]]; then
    printf 'sdk_unavailable'
  elif [[ -n "$recorded_reason" ]]; then
    printf '%s' "$recorded_reason"
  fi
}
```

- [ ] **Step 4: Rename the state global**

Line 368: `WASM_BUNDLE_INSTALL_FAILED=""` → `WASM_BUNDLE_FAILED_REASON=""`

- [ ] **Step 5: Rewrite `prepare_wasm_sdk`'s install branch**

Add `precheck` to the function's `local` list:

```bash
  local kind="$1" logfile="$2" sdk_id="" url checksum skip="" precheck
```

Replace the `if [[ -z "$url" ]] … else … fi` block (`:490-510`) with:

```bash
    url="${CROSS_TARGET_WASM_SDK_URL:-}"
    checksum="${CROSS_TARGET_WASM_SDK_CHECKSUM:-}"
    precheck="$(wasm_install_precheck "$url" "$WASM_BUNDLE_FAILED_REASON")"
    if [[ -n "$precheck" ]]; then
      skip="$precheck"
      if [[ "$precheck" != "sdk_unavailable" ]]; then
        echo "cross_target_sdk_install_skipped target=${kind}" \
          "reason=bundle_install_already_failed prior_reason=${precheck}"
      fi
    else
      echo "cross_target_command target=${kind} cmd=\"swift $(sdk_install_display "$url" "$checksum")\""
      if ! swift_sdk_install_retry "$url" "$checksum" "${logfile}.install"; then
        skip="sdk_install_failed"
        WASM_BUNDLE_FAILED_REASON="sdk_install_failed"
        print_log_tail "${kind}-sdk-install" "${logfile}.install"
      elif ! sdk_id="$(resolve_wasm_sdk_id "$SWIFT_VERSION" "$kind")"; then
        skip="sdk_unresolved_after_install"
        # Slice 47 (P3 #2): record THIS reason too. Slice 46 recorded only the
        # install failure, so the drift path let the second kind re-run a full
        # ladder against an already-installed SDK and report a different reason.
        WASM_BUNDLE_FAILED_REASON="sdk_unresolved_after_install"
      fi
    fi
```

- [ ] **Step 6: Update the stale comment inside `prepare_wasm_sdk`**

In the comment block at `:483-489`, replace the sentence naming the old global:

```
    # Failure path: if the shared install genuinely fails, WASM_BUNDLE_INSTALL_FAILED
    # (set below) short-circuits the second kind straight to the same failure
    # reason instead of burning a second full bounded-retry ladder against a
    # host that just failed the first one.
```

with:

```
    # Failure path: once the shared bundle fails definitively -- install failure OR
    # installed-but-unresolvable -- WASM_BUNDLE_FAILED_REASON (set below) short-
    # circuits the second kind to the SAME reason via wasm_install_precheck, instead
    # of burning a second full bounded-retry ladder against a host that just failed
    # the first one.
```

- [ ] **Step 7: Verify no reference to the old global survives**

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n 'WASM_BUNDLE_INSTALL_FAILED' .github/scripts/cross-target-compile.sh
echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 8: Run the self-test to verify it passes**

```bash
cd /Users/aabanschikov/swift-text-engine
./.github/scripts/cross-target-compile.sh --self-test
bash -n .github/scripts/cross-target-compile.sh && echo "syntax ok"
```

Expected: `self_test=pass`, `syntax ok`.

- [ ] **Step 9: Prove the short-circuit live (P3 #4's residual gap)**

```bash
cd /Users/aabanschikov/swift-text-engine
CROSS_TARGET_WASM_SDK_URL=https://example.invalid/nope.tar.gz \
CROSS_TARGET_WASM_SDK_CHECKSUM=deadbeef \
CROSS_TARGET_SDK_INSTALL_ATTEMPTS=2 \
CROSS_TARGET_SDK_INSTALL_BACKOFF=1 \
  ./.github/scripts/cross-target-compile.sh --targets wasm 2>&1 | tail -30
echo "exit=$?"
```

Expected: exactly **2** `warn=sdk_install_attempt_failed` lines (one ladder, not two), a
`cross_target_sdk_install_skipped … reason=bundle_install_already_failed prior_reason=sdk_install_failed`
line for the second kind, four `blocking=true` failures, and `exit=1`. Fail-closed must survive the speed-up.

- [ ] **Step 10: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add .github/scripts/cross-target-compile.sh
git commit -m "$(cat <<'EOF'
fix: short-circuit the SDK drift path with its own reason

Slice 46 recorded only the install-failure outcome, so the sibling
sdk_unresolved_after_install path left the flag empty and the second kind
re-entered a full bounded-retry ladder against an already-installed SDK.

Replaces the boolean WASM_BUNDLE_INSTALL_FAILED with WASM_BUNDLE_FAILED_REASON
carrying the reason itself, so the second kind short-circuits with the SAME
reason and the log reads as one fault. The branch decision moves into a pure
wasm_install_precheck helper, which makes the short-circuit reachable from
--self-test -- previously it could only be exercised by a live run.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: De-rot the two frozen `580 µs` sites and the Commands caveat

**Files:**
- Modify: `AGENTS.md:196` (Commands caveat), `:365` (frozen number)
- Modify: `Sources/ViewportBenchmarks/BenchmarkModels.swift:145` (comment only)

This is the only `Sources/` edit in the slice, and it is comment-only.

- [ ] **Step 1: Add the Commands-block caveat (P3 #6)**

Line 196:

```
./.github/scripts/cross-target-compile.sh --targets wasm     # WASM-only compile path (blocking, since Slice 46)
```

→

```
./.github/scripts/cross-target-compile.sh --targets wasm     # WASM-only compile path (blocking; exits 1 without a pinned SDK — see below)
```

- [ ] **Step 2: Remove the frozen number from AGENTS.md (P3 #7)**

Line 364-366 currently reads:

```
regression p99 budget stays under the absolute ceiling** (binding scenario
`structural_mutation|1m`, 580 µs, 2.87× under) — so the runtime absolute gate can never
redden a clean tree.
```

Replace with:

```
regression p99 budget stays under the absolute ceiling** — read the binding scenario
and its margin from that test against the committed budgets, not from a number quoted
here, which the next re-derivation falsifies. So the runtime absolute gate can never
redden a clean tree.
```

- [ ] **Step 3: Remove the frozen number from the source comment (P3 #7)**

`Sources/ViewportBenchmarks/BenchmarkModels.swift:143-146` currently reads:

```swift
        // budgetExceeded and budgetStale on purpose: across the frame-hot-path set every
        // regression p99 budget is <= 580us < the 1.67ms ceiling (GateFloorTests pins
        // this), so exceeding the ceiling always also exceeds the regression budget and a
        // plain regression already reported budget_exceeded above. This therefore fires
```

Replace with:

```swift
        // budgetExceeded and budgetStale on purpose: across the frame-hot-path set every
        // regression p99 budget sits under the 1.67ms ceiling (GateFloorTests pins this
        // against the committed budgets -- read the binding scenario and its margin from
        // that test, not from a number frozen into this comment), so exceeding the
        // ceiling always also exceeds the regression budget and a
        // plain regression already reported budget_exceeded above. This therefore fires
```

- [ ] **Step 4: Verify no frozen `580` survives**

```bash
cd /Users/aabanschikov/swift-text-engine
rg -n '580' AGENTS.md Sources/ViewportBenchmarks/BenchmarkModels.swift
echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 5: Verify the comment-only edit changed no behavior**

```bash
cd /Users/aabanschikov/swift-text-engine
swift build -c release && swift test 2>&1 | rg 'Executed .* tests' | tail -2
```

Expected: `Build complete!`, `315` tests, `0` failures.

- [ ] **Step 6: Commit**

```bash
cd /Users/aabanschikov/swift-text-engine
git add AGENTS.md Sources/ViewportBenchmarks/BenchmarkModels.swift
git commit -m "$(cat <<'EOF'
docs: stop quoting a frozen 580us, and caveat the bare wasm command

Both sites quoted a benchmark value measured three slices ago; a comment
quoting a measured number is falsified by the next re-derivation. Points at
GateFloorTests and the committed budgets instead, where the live value is.

Also flags in the Commands block that a bare --targets wasm exits 1 without
the env pin and a version-matching installed SDK. The prose two sections down
already said so, but the command list is the part people copy.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Full local verification, then open the PR and record the wedge

**Files:**
- Create: `docs/superpowers/verification/2026-07-20-wasm-required-check-rename.md` (started here, completed in Tasks 9–10)

**Do not delegate this task's PR step to a subagent** — it opens a PR against a live repository.

- [ ] **Step 1: Run the full local verification suite**

```bash
cd /Users/aabanschikov/swift-text-engine
swift test 2>&1 | rg 'Executed .* tests' | tail -2
swift build -c release
./.github/scripts/cross-target-compile.sh --self-test
bash -n .github/scripts/cross-target-compile.sh && echo "syntax ok"
rg -n "Foundation" Sources/TextEngineCore; echo "foundation_scan_exit=$?"
```

Expected: `315`/`0`; `Build complete!`; `self_test=pass`; `syntax ok`; empty scan with `foundation_scan_exit=1`.

- [ ] **Step 2: Prove the new pin is live (AC2)**

```bash
cd /Users/aabanschikov/swift-text-engine
# Break it: revert the WASM job's name only.
sed -i '' 's/    name: WASM cross-target compile/    name: WASM cross-target observation/' \
  .github/workflows/swift-ci.yml
swift test --filter WorkflowShapeTests 2>&1 | rg -E 'error:|Executed .* tests' | tail -5
```

Expected: exactly **one** failing method — `testJobNamesMatchRequiredCheckContexts` — and its message must contain both `17656807` and the `gh api` command (AC2 requires the message be self-servicing, not merely a mention of the ruleset).

```bash
git checkout .github/workflows/swift-ci.yml
swift test --filter WorkflowShapeTests 2>&1 | rg 'Executed .* tests' | tail -2
git status --short          # expect empty — tree byte-clean
```

Expected: green again, tree clean.

- [ ] **Step 3: Verify AC9 confinement and checksum byte-identity**

```bash
cd /Users/aabanschikov/swift-text-engine
git diff be763dc..HEAD --name-only -- \
  Sources/TextEngineCore Sources/TextEngineReferenceProviders \
  docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv \
  .github/scripts/derive-gate-budgets.sh .github/scripts/harvest-gate-corpus.sh
echo "confinement_exit=$? (expect empty output above)"

for flag in "" "--variable-height" "--variable-height-mutation" "--structural-mutation" \
            "--bulk-structural-mutation" "--line-query" "--line-geometry-query" \
            "--column-query" "--column-geometry-query" "--point-query" \
            "--point-geometry-query" "--realistic-provider"; do
  swift run -c release --scratch-path /tmp/text-engine-host-build ViewportBenchmarks \
    -- $flag --gate
done | rg -o 'scenario=\S+ .*checksum=\S+' | sort > "$SCRATCH/after-checksums.txt"
diff "$SCRATCH/baseline-checksums.txt" "$SCRATCH/after-checksums.txt" && echo "checksums byte-identical"
wc -l < "$SCRATCH/after-checksums.txt"
```

Expected: empty confinement diff; `checksums byte-identical`; line count equal to Task 1's measured baseline.

- [ ] **Step 4: Record the ruleset "before" snapshot (AC4)**

```bash
cd /Users/aabanschikov/swift-text-engine
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 \
  > "$SCRATCH/ruleset-before.json"
jq -r '.rules[] | select(.type=="required_status_checks")
       | .parameters.required_status_checks[].context' "$SCRATCH/ruleset-before.json"
```

Expected: the three contexts, with `WASM cross-target observation` still present.

- [ ] **Step 5: Re-check the no-open-PRs precondition**

```bash
gh pr list --state open
```

Expected: empty. This is the one precondition that can expire between spec time and now. If any PR is open, **stop and report** — the unrequired window would affect somebody else's PR.

- [ ] **Step 6: Push and open the PR (it will wedge — that is the evidence)**

```bash
cd /Users/aabanschikov/swift-text-engine
git push -u origin slice-47-wasm-required-check-rename
gh pr create --title "Slice 47 — rename the WASM required check, pin names to the ruleset" \
  --body "$(cat <<'EOF'
Renames the CI job and required-status-check context `WASM cross-target
observation` → `WASM cross-target compile`, pins all three job `name:` fields to
their contexts, and folds in Slice 46's five P3 residuals.

**This PR is expected to wedge on open.** The WASM job now reports
`WASM cross-target compile`, while ruleset `Main` still requires
`WASM cross-target observation` — a context no run will report. That is the
order-sensitivity Slice 46's review flagged, deliberately observed rather than
asserted, and it is discharged by the drop-rename-readd sequence in the spec.

See `docs/superpowers/specs/2026-07-20-wasm-required-check-rename-design.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 7: Capture the wedge (AC3)**

Wait for the runs to report, then:

```bash
gh pr checks --json name,state,bucket | jq .
gh pr view --json mergeStateStatus,statusCheckRollup | jq '.mergeStateStatus'
```

Expected: `WASM cross-target observation` shows as required and **not reported**; the PR is blocked. Save this output — it is AC3's evidence.

- [ ] **Step 8: Start the verification record**

Create `docs/superpowers/verification/2026-07-20-wasm-required-check-rename.md` with: the Task 1 baseline numbers, the Step 1–3 local results, the AC2 break→red→revert→green transcript, the `ruleset-before.json` contexts, and the Step 7 wedge capture verbatim.

- [ ] **Step 9: Commit and push the record so far**

```bash
cd /Users/aabanschikov/swift-text-engine
git add docs/superpowers/verification/2026-07-20-wasm-required-check-rename.md
git commit -m "$(cat <<'EOF'
docs: record local verification and the deliberate PR wedge

Captures the pre-change checksum baseline, the pin's break/red/revert/green
cycle, the ruleset before-snapshot, and the PR blocked on a context nothing
reports -- the order-sensitivity this slice sequences around, observed rather
than asserted.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 9: The ruleset sequence

**⚠️ This task mutates live repository configuration and must be executed by the main session, not a subagent. Present each `gh api` mutation to the user and execute only on explicit confirmation.**

- [ ] **Step 1: Build the intermediate ruleset payload (old context removed)**

```bash
cd /Users/aabanschikov/swift-text-engine
jq '(.rules[] | select(.type=="required_status_checks")
     | .parameters.required_status_checks)
    |= map(select(.context != "WASM cross-target observation"))
   | {name, target, enforcement, conditions, rules, bypass_actors}' \
  "$SCRATCH/ruleset-before.json" > "$SCRATCH/ruleset-intermediate.json"
jq -r '.rules[] | select(.type=="required_status_checks")
       | .parameters.required_status_checks[].context' "$SCRATCH/ruleset-intermediate.json"
```

Expected: two contexts (`Host tests and benchmark gate`, `iOS cross-target compile`).

- [ ] **Step 2: Confirm with the user, then apply**

Show the user the payload diff and the exact command. On confirmation:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 \
  --method PUT --input "$SCRATCH/ruleset-intermediate.json"
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 \
  > "$SCRATCH/ruleset-intermediate-applied.json"
```

- [ ] **Step 3: Assert only the context list changed**

```bash
diff <(jq -S 'del(.rules[] | select(.type=="required_status_checks")
              | .parameters.required_status_checks) | del(.updated_at)' \
        "$SCRATCH/ruleset-before.json") \
     <(jq -S 'del(.rules[] | select(.type=="required_status_checks")
              | .parameters.required_status_checks) | del(.updated_at)' \
        "$SCRATCH/ruleset-intermediate-applied.json") \
  && echo "only the context list changed — bypass actors and strict policy intact"
```

Expected: the success message. If anything else differs, **restore from `ruleset-before.json` immediately** and report.

- [ ] **Step 4: Merge the PR (AC5)**

```bash
gh pr checks              # all three reported checks green
gh run view <run-id> --log | rg 'result=(pass|fail)|gate=(pass|fail)|Executed .* tests'
```

Read at **step** level — a green job conclusion proves nothing (this repo's standing rule). Confirm four WASM pairs `blocking=true`, the gate tally from Task 1 Step 4, and `315`/`0`. Then merge:

```bash
gh pr merge --merge
```

- [ ] **Step 5: Confirm the post-merge push run (AC6)**

```bash
cd /Users/aabanschikov/swift-text-engine
git checkout main && git pull
gh run list --branch main --limit 3
gh api repos/maldrakar/swift-text-engine/actions/runs/<run-id> --jq '.status, .conclusion'
gh run view <run-id> --log | rg 'result=(pass|fail)|gate=(pass|fail)|Executed .* tests'
```

Confirm run state from `gh api`, not `gh run watch --exit-status` — Slice 46 recorded that it exits 0 after dying on a network error.

- [ ] **Step 6: Add the new context, then confirm (AC4)**

```bash
jq '(.rules[] | select(.type=="required_status_checks")
     | .parameters.required_status_checks)
    += [{"context": "WASM cross-target compile"}]' \
  "$SCRATCH/ruleset-intermediate-applied.json" \
  | jq '{name, target, enforcement, conditions, rules, bypass_actors}' \
  > "$SCRATCH/ruleset-after-payload.json"
```

Show the user, confirm, then:

```bash
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 \
  --method PUT --input "$SCRATCH/ruleset-after-payload.json"
gh api repos/maldrakar/swift-text-engine/rulesets/17656807 > "$SCRATCH/ruleset-after.json"
jq -r '.rules[] | select(.type=="required_status_checks")
       | .parameters.required_status_checks[].context' "$SCRATCH/ruleset-after.json"
```

Expected: the three contexts, with `WASM cross-target compile` in place of the old one.

- [ ] **Step 7: Assert the before→after diff is exactly one context string**

```bash
diff <(jq -S 'del(.updated_at)' "$SCRATCH/ruleset-before.json") \
     <(jq -S 'del(.updated_at)' "$SCRATCH/ruleset-after.json")
```

Expected: exactly one context string differs; `bypass_actors` and
`strict_required_status_checks_policy` byte-identical.

---

### Task 10: Prove enforcement and close out

- [ ] **Step 1: Open the proof PR — after Task 9 Step 6, never before (AC7)**

GitHub labels a context "Required" from the ruleset state at evaluation time, so a PR opened before the re-add can keep showing stale labelling.

```bash
cd /Users/aabanschikov/swift-text-engine
git checkout -b slice-47-post-merge-verification
```

Complete `docs/superpowers/verification/2026-07-20-wasm-required-check-rename.md` with all three ruleset snapshots, the before→after diff, the merge-run and post-merge-run step-level evidence, and the AC coverage table. Then:

```bash
git add docs/superpowers/verification/2026-07-20-wasm-required-check-rename.md
git commit -m "$(cat <<'EOF'
docs: discharge the ruleset sequence and post-merge proof

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin slice-47-post-merge-verification
gh pr create --title "Slice 47 — ruleset sequence and post-merge proof" \
  --body "Docs-only. Completes the verification record and serves as AC7's enforcement proof: this PR's check list must show \`WASM cross-target compile\` as a required, reported context.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 2: Capture the enforcement evidence (AC7)**

```bash
gh pr checks --json name,state,bucket | jq .
```

Expected: `WASM cross-target compile` listed as required **and reported**. If it shows a stale label, push an empty commit (`git commit --allow-empty -m "chore: force check re-evaluation"`) and re-read.

Amend the verification record with this capture, commit, push.

- [ ] **Step 3: Update memory**

Update `slice-46-direction.md` (the deferred wart is discharged) and add `slice-47-direction.md`, plus their `MEMORY.md` index lines.

- [ ] **Step 4: Hand off**

Report to the user: the PR is open for their review and merge — per this repo's standing rule, the assistant does not auto-merge the closing PR. Then invoke `superpowers:finishing-a-development-branch`.

---

## Self-Review

**Spec coverage:**

| Spec item | Task |
|---|---|
| D1 sequence (drop→rename→readd) | 8 (before-snapshot, wedge), 9 (all three mutations) |
| D2 open PR before dropping, to prove the wedge | 8 Steps 6–7 |
| D3 pin all three job names | 2 |
| D4 unknown kind: `true` in helper, hard exit at dispatch | 5 |
| D5 drift path short-circuits with its own reason | 6 |
| D6 pure helper under `--self-test` | 6 Steps 1–3 |
| D7 remove both frozen `580 µs` | 7 |
| Change set §1 workflow (3 sites) | 2 (`name:`), 3 (key, echo) |
| Change set §2 tests | 2, 3 |
| Change set §3 script | 5, 6 |
| Change set §4 AGENTS.md (incl. `WorkflowShapeTests` description) | 4, 7 |
| Change set §5 BenchmarkModels comment | 7 |
| Change set §6 verification record | 8, 9, 10 |
| Change set §7 memory | 10 Step 3 |
| AC1 seven sites, `--hidden -U` | 3 Step 5, 4 Step 6 |
| AC2 pin live, self-servicing message | 8 Step 2 |
| AC3 wedge recorded | 8 Step 7 |
| AC4 three snapshots, one-string diff | 8 Step 4; 9 Steps 2, 3, 6, 7 |
| AC5 merge, step level | 9 Step 4 |
| AC6 post-merge push run | 9 Step 5 |
| AC7 enforcement, PR after step 6 | 10 Steps 1–2 |
| AC8 `--self-test` covers new cases | 5 Step 6, 6 Step 8 |
| AC9 confinement + checksum baseline | 1 Step 3, 8 Step 3 |
| AC10 Foundation scan | 8 Step 1 |
| Precondition: no open PRs | 1 Step 2, 8 Step 5 |

No gaps.

**Placeholder scan:** No "TBD"/"TODO"/"handle edge cases"/"similar to Task N". Every code step carries the actual code. The two `<run-id>` placeholders in Task 9 are runtime values that cannot be known at plan time, and each is preceded by the command that produces it.

**Type consistency:** `wasm_install_precheck(url, recorded_reason)` — same name and argument order in Task 6 Steps 1, 3, 5. `WASM_BUNDLE_FAILED_REASON` — same spelling in Steps 4, 5, 6, 7. `requiredCheckContexts` / `iosJobKey` — defined in Task 2 Step 1, consumed in Task 2 Step 2. `wasmJobKey` — deliberately holds the old value in Task 2 and is updated in Task 3 Step 3, and the plan says so at both sites. `jobLevelValue(of:jobKey:)` matches the existing Slice 46 signature.
