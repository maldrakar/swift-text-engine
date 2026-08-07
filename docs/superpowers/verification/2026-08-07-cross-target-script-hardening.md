# Slice 51 verification — cross-target script hardening (D-1, D-3, D-6) + D-2 plan-assertion conventions

Branch `slice-51-cross-target-script-hardening`. `git merge-base main HEAD`
resolves to `927251e` (the tip of `main` at slice-51 selection time, the
`slice-50-post-slice-review` merge). Commits on this branch since that point,
in order:

- `1926275` — docs: record slice 51 selection (debt route: D-1/D-2/D-3/D-6; D-7 stays deferred)
- `bc12f21` — docs: slice 51 design — cross-target script hardening (D-1/D-3/D-6 + D-2)
- `09d223d` — docs: revise slice 51 design per spec review (3 P1s, 6 P2s, polish)
- `e5335da` — docs: name the string-literal residual in the slice 51 coverage check
- `7a3e80b` — docs: slice 51 design — second review round (rule-2 verification block + 6 polish)
- `d461783` — docs: correct detect-docs-only-pr citations and record its cleanup in slice 51 design
- `0ec3d01` — docs: slice 51 TDD plan (6 tasks, mutation-validated assertion sites) — **last commit before Task 1**
- `ddad0bc` — test: make cross-target self-test failures propagate (subshell status + dispatcher) (Task 1)
- `81ddb58` — test: enforce every script self-test from swift test, share process helpers (Task 2)
- `369311a` — fix: give each SDK install attempt its own log and print every tail (Task 3)
- `3b40302` — docs: correct swift_sdk_install_retry's coverage comment (Task 3 fix round)
- `1c08782` — fix: report asymmetric SDK drift truthfully instead of a second failed install (Task 4)
- `ebb6dd1` — test: pin the self-test coverage/exemption classification for every function (Task 5)

This task (Task 6) adds the plan-assertion conventions to `AGENTS.md`, records
that all four scripts' `--self-test` are now enforced by `swift test`, appends
ledger row D-14, corrects the falsified `WASM_BUNDLE_FAILED_REASON` clause in
`docs/superpowers/arcs/wrap.md`, and writes this verification record — no
source changes of its own. **Step 6 (push branch, open PR, harvest hosted
evidence) is explicitly out of scope for this task** and is not attempted
here; there is no hosted-CI section below because none was run.

`.github/scripts/cross-target-compile.sh` now defines **45 functions**,
partitioned by the Task 5 classification enforcement into **8 harness**
functions (dispatcher/orchestration, unclassified by design) + **27 covered**
(exercised by `--self-test`) + **10 exempt** (named-and-justified, each
touching a toolchain the self-test cannot run without: `xcodebuild`,
`xcrun`, `swift sdk list`, or the real SDK install/compile path).

---

## 1. Full local verification block (Step 4)

All commands run via `bash -c '...'` per the environment note (the outer
shell is zsh, which reserves `status` as read-only and glob-aborts on
no-match; `bash -c` avoids both).

### 1a. `swift test`, `swift build -c release`, `swift run -- --gate`

```
$ bash -c '
swift test 2>&1 | tail -5; test_status=${PIPESTATUS[0]}
swift build -c release 2>&1 | tail -3; build_status=${PIPESTATUS[0]}
swift run -c release ViewportBenchmarks -- --gate 2>&1 | tail -3; gate_status=${PIPESTATUS[0]}
echo "test=$test_status build=$build_status gate=$gate_status"
'
	 Executed 361 tests, with 0 failures (0 unexpected) in 5.377 (5.400) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
[4/5] Compiling TextEngineCore DocumentLineCursor.swift
[5/6] Compiling ViewportBenchmarks BenchmarkModels.swift
Build complete! (1.89s)
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1286 p99_ns=1448 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=16.3x headroom_p99=29.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1151.0x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5197 p99_ns=5319 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=16.2x headroom_p99=32.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=313.3x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17208 p99_ns=17467 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=16.3x headroom_p99=32.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=95.4x gate=pass checksum=18852477646272000
test=0 build=0 gate=0
```

`test=0 build=0 gate=0` — all three green. 361 tests / 0 failures (up from
Slice 50's 359, plus the two new `ScriptSelfTestTests` cases from Task 2 —
no other test count moved this slice, since Tasks 1/3/4/5 only touch the
shell script and its own `--self-test`). All three synthetic `--gate`
scenarios `gate=pass` with checksums byte-identical to prior slices'
(`1319670707200` / `570448232307200` / `18852477646272000`) — this slice adds
no new gated benchmark mode and touches no Swift source under `Sources/`.

### 1b. Script self-test

```
$ bash -c '
out="$(./.github/scripts/cross-target-compile.sh --self-test)"; rc=$?
if [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -q "self_test=pass" \
  && ! printf "%s\n" "$out" | grep -q "self_test=fail"; then echo "self-test OK"
else echo "UNEXPECTED rc=$rc"; printf "%s\n" "$out"; fi
'
warn=sdk_install_attempt_failed attempt=1/3
warn=sdk_install_attempt_failed attempt=2/3
self-test OK
```

The two `warn=sdk_install_attempt_failed` lines are expected stderr noise
from `scenario_ladder_recovers_after_two_failures` (Task 3): that scenario's
call site redirects only stdout, not stderr, so the two deliberately-failing
stub attempts before the ladder's successful third attempt print their
warning to the terminal. This is the same noise recorded in the Task 3 and
Task 5 reports and is not a failure signal — `self_test=fail` never appears
and the exit code is 0.

### 1c. Foundation-free scan + Sources untouched

```
$ bash -c '
if [ -z "$(rg -n "Foundation" Sources/TextEngineCore)" ]; then echo "foundation-free OK"
else echo "UNEXPECTED: Foundation in the core"; rg -n "Foundation" Sources/TextEngineCore; fi
if git diff --quiet main -- Sources/; then echo "sources untouched OK"
else echo "UNEXPECTED: Sources changed"; git diff --stat main -- Sources/; fi
'
foundation-free OK
sources untouched OK
```

Both hold: `Sources/TextEngineCore` remains Foundation-free, and `Sources/`
carries zero diff against `main` — consistent with this slice touching only
`.github/scripts/cross-target-compile.sh`, its Swift test enforcement in
`Tests/ViewportBenchmarksTests/`, and docs.

### 1d. iOS cross-target compile

```
$ bash -c '
./.github/scripts/cross-target-compile.sh --targets ios 2>&1 | tail -6
ios_status=${PIPESTATUS[0]}
if [ "$ios_status" -eq 0 ]; then echo "ios compile OK"; else echo "UNEXPECTED ios status=$ios_status"; fi
'
cross_target_command target=ios_simulator scheme=TextEngineReferenceProviders cmd="xcodebuild build -scheme TextEngineReferenceProviders -destination 'generic/platform=iOS Simulator'"
mode=cross_target_compile target=ios_simulator package=providers result=pass reason=none blocking=true
mode=cross_target_compile target=wasm package=providers result=skipped reason=not_requested blocking=false
mode=cross_target_compile target=wasm_embedded package=providers result=skipped reason=not_requested blocking=false
mode=cross_target_compile_summary package=providers ios_device=pass ios_simulator=pass wasm=skipped wasm_embedded=skipped
mode=cross_target_compile_overall blocking_failures=0 exit=0
ios compile OK
```

This environment does have Xcode (`Xcode 26.3;Build version 17C529`,
iPhoneOS/iPhoneSimulator SDK `26.2`), so the iOS path ran for real, not a
skip: both `TextEngineCore` and `TextEngineReferenceProviders` compiled clean
for `ios_device` and `ios_simulator` (`mode=cross_target_compile_overall
blocking_failures=0 exit=0`). This exercises the Task 3/4 changes
(per-attempt logfiles, `WASM_BUNDLE_STATE`, `run_swift_sdk_install` seam)
indirectly, in that the same script file now compiles and runs cleanly under
`bash` outside `--self-test` too — the WASM targets were not requested in
this run (`reason=not_requested`, as documented in AGENTS.md's "Local WASM
build" note) and are unaffected by this slice's scope (D-1/D-3/D-6 are all
inside the WASM install/retry path, exercised by `--self-test`, not by the
iOS compile path).

---

## 2. Plan defects found during implementation

This slice exists to make plan assertions falsifiable (D-2). In the course of
executing this plan's own six tasks, three of its assertion sites and one
procedural step were found defective — recorded here factually, as the
sharpest available evidence for whether the D-2 conventions need a fifth
rule. (Per the controller's instruction, no fifth convention is added to
`AGENTS.md` by this task; that call belongs to the post-slice review.)

### 2a. Task 3 Step 1 — an always-2 `grep -c` count

The plan's `scenario_ladder_exhausts_and_prints_every_tail` (and the
task-3-brief transcribing it) contains:

```bash
assert_equal "1" "$(printf '%s\n' "$out" | grep -c 'exhaust-attempt-2 log tail')" \
    "ladder_exhaust_attempt2_label"
```

`print_log_tail` emits a matching open/close banner pair
(`----- <label> log tail (last N lines) -----` and
`----- end <label> log tail -----`), and both lines contain the unanchored
substring `<label> log tail`. `grep -c` counts matching lines, so this
assertion's count is **2 for any single `print_log_tail` call, regardless of
implementation** — it can never equal `1`. Confirmed directly (Task 3 report):

```
$ bash -c '
label="exhaust-attempt-2"; TAIL_LINES=40
out="$(echo "----- ${label} log tail (last ${TAIL_LINES} lines) -----"; echo "stub failure 2"; echo "----- end ${label} log tail -----")"
printf "%s\n" "$out" | grep -c "exhaust-attempt-2 log tail"
'
2
```

Fixed by anchoring the pattern on the opening banner only —
`'exhaust-attempt-2 log tail (last'` — which reproduces the plan's own
expected value (`"1"`) unchanged; the sibling assertion two lines above it in
the same scenario already used this anchor style for its count of 3 across
three attempts. This bug is present in the plan document itself
(`docs/superpowers/plans/2026-08-07-cross-target-script-hardening.md:524`),
not only in the task-3 brief transcription — it is upstream in the plan.

### 2b. Task 4 Step 1 — a subshell that discards the assertion's own precondition

The plan's `scenario_asymmetric_drift_reports_truth` captures the second
`prepare_wasm_sdk` call as:

```bash
out="$(prepare_wasm_sdk wasm_embedded "${SELF_TEST_TMP_ROOT}/drift-embedded.log" 2>&1)"
assert_equal "sdk_unresolved_after_install" "$WASM_SKIP_WASM_EMBEDDED" "drift_second_kind_reason"
```

`out="$(...)"` is a command substitution, and command substitution **always
forks a subshell** in bash. `prepare_wasm_sdk` communicates its result via
the global `WASM_SKIP_WASM_EMBEDDED`; when the call runs inside `$(...)`,
that global's update happens in the forked subshell and is discarded when
the subshell exits, so the very next assertion always compares against the
variable's untouched initial value — **independent of whether the underlying
D-1 fix is correct**. Confirmed with an isolated two-line repro on the host's
bash 3.2.57 (a function that sets a global and echoes, called bare vs. via
`$(...)`: the global update is visible after the bare call and silently lost
after the `$(...)` call). Fixed by capturing via a temp file inside
`SELF_TEST_TMP_ROOT` instead of command substitution, so the call runs in the
current shell and the global side effect survives:

```bash
prepare_wasm_sdk wasm_embedded "${SELF_TEST_TMP_ROOT}/drift-embedded.log" \
  > "${SELF_TEST_TMP_ROOT}/drift-embedded.out" 2>&1
out="$(cat "${SELF_TEST_TMP_ROOT}/drift-embedded.out")"
```

This changes only how output is captured, not the assertion or the fix's
logic. The underlying D-1 fix was independently verified correct by sourcing
the function definitions and calling `prepare_wasm_sdk wasm_embedded` bare
(not substituted), which correctly produced
`WASM_SKIP_WASM_EMBEDDED=sdk_unresolved_after_install`, `counter=1` (no
second install), and
`reason=bundle_installed_id_unresolved prior_state=bundle_installed_ok`.

### 2c. Task 5 Step 7 — a mutation target that reddens for the wrong reason, on a false premise

The plan's Step 7 instructs commenting out the bare `mark_not_requested`
call and claims "`mark_not_requested` is the only covered helper with
exactly one reference [in the self-test region]... the others have 2-6."

Both halves are wrong:

- **The premise is false.** Measuring every `SELF_TEST_COVERED` name's
  reference count inside `self_test_body`'s output (comments and definition
  lines already stripped, using `body_references_function`'s own
  word-boundary pattern) found **nine** names with exactly one reference:
  `mark_not_requested`, `usage`, `defined_functions`, `is_harness_function`,
  `self_test_body`, `body_references_function`,
  `scenario_ladder_recovers_after_two_failures`,
  `scenario_ladder_exhausts_and_prints_every_tail`, and
  `scenario_asymmetric_drift_reports_truth` — not one.
- **The mutation reddens for the wrong reason.** `mark_not_requested`'s sole
  call site (in `run_self_test`) is immediately followed by three assertions
  that check *its own side effects* (`not_requested_result`,
  `not_requested_reason`, `not_requested_blocking`), and those run earlier in
  `run_self_test`'s linear body than the classification block (which sits at
  the very end, right before `self_test=pass`). Commenting out the call
  leaves `LAST_RESULT` at its initial `""`, so `not_requested_result`'s
  `assert_equal` fires and exits immediately — the self-test never reaches
  the classification block for this mutation. Confirmed directly (Task 5
  report):

  ```
  UNEXPECTED rc=1
  self_test=fail label=not_requested_result expected=skipped actual=
  reverted
  ```

  The redness is real, but it exercises "removing an executed call breaks
  something" (true of almost any call in the file), not the
  "comments-are-not-references" classification mechanism Step 7 exists to
  prove.

Substituted `scenario_ladder_recovers_after_two_failures` as the mutation
target (comment out its `run_scenario scenario_ladder_recovers_after_two_failures`
call): its sole reference has no assertion depending on its side effects
between the call site and the classification block, so it cleanly exercises
comment-stripping and lands the expected
`covered_but_unreferenced fn=scenario_ladder_recovers_after_two_failures`:

```
RED CONFIRMED (comment stripping, corrected target)
reverted
```

A reviewer confirmed this substitute's redness is attributable to
comment-stripping and nothing else. No permanent script change resulted from
this deviation — both the literal and the corrected mutation were reverted
with `git checkout --` before commit; only the choice of which mutation to
run during verification changed.

### 2d. Procedural gap — `git checkout --` before staging reverts uncommitted plan work

Also surfaced during Task 5 Step 5: the plan's mutate → assert RED →
`git checkout --` → assert reverted drill assumes the file already has a
committed baseline to fall back to. When a task's own Steps 1-3 work is still
unstaged and uncommitted at the moment a mutation drill's `git checkout --`
runs, that command falls through to `HEAD` (the pre-task baseline) rather
than to an index entry, silently wiping the task's own in-progress work along
with the mutation. This happened once during Task 5 (recovered by re-applying
Steps 1-3 and staging with `git add` before running any mutation drill) and
is not written down anywhere in the plan or brief. The operational fix —
stage the task's own work before running any mutation drill that ends in
`git checkout --` — is not itself one of the four assertion-executability
conventions (it is about drill *ordering*, not assertion *shape*), but the
plan should say so explicitly for any future task reusing this pattern.

---

## 3. Diff scope vs `main`

```
$ git log --oneline main..HEAD
ebb6dd1 test: pin the self-test coverage/exemption classification for every function
1c08782 fix: report asymmetric SDK drift truthfully instead of a second failed install
3b40302 docs: correct swift_sdk_install_retry's coverage comment
369311a fix: give each SDK install attempt its own log and print every tail
81ddb58 test: enforce every script self-test from swift test, share process helpers
ddad0bc test: make cross-target self-test failures propagate (subshell status + dispatcher)
0ec3d01 docs: slice 51 TDD plan (6 tasks, mutation-validated assertion sites)
d461783 docs: correct detect-docs-only-pr citations and record its cleanup in slice 51 design
7a3e80b docs: slice 51 design — second review round (rule-2 verification block + 6 polish)
e5335da docs: name the string-literal residual in the slice 51 coverage check
09d223d docs: revise slice 51 design per spec review (3 P1s, 6 P2s, polish)
bc12f21 docs: slice 51 design — cross-target script hardening (D-1/D-3/D-6 + D-2)
1926275 docs: record slice 51 selection (debt route: D-1/D-2/D-3/D-6; D-7 stays deferred)

$ git diff --stat main HEAD
 .github/scripts/cross-target-compile.sh                                  |  371 +++++-
 Tests/ViewportBenchmarksTests/GateFloorTests.swift                       |   38 -
 Tests/ViewportBenchmarksTests/ProcessSupport.swift                       |   47 +
 Tests/ViewportBenchmarksTests/ScriptSelfTestTests.swift                  |   70 ++
 Tests/ViewportBenchmarksTests/WorkflowShapeTests.swift                   |   11 -
 docs/superpowers/arcs/wrap.md                                            |   20 +
 docs/superpowers/debt-ledger.md                                          |   10 +-
 docs/superpowers/plans/2026-08-07-cross-target-script-hardening.md       | 1324 ++
 docs/superpowers/specs/2026-08-07-cross-target-script-hardening-design.md|  618 ++
 9 files changed, 2433 insertions(+), 76 deletions(-)
```

(Figures above are as measured before this task's own commit; this
verification doc, the `AGENTS.md` edit, the `debt-ledger.md` D-14 row, and
the `arcs/wrap.md` correction are added by this task's commit, immediately
after this listing was captured. This task touches no file under
`Sources/**`, `.github/workflows/**`, `.github/scripts/**`, or any
budget/corpus/gate-registry path.)

```
$ git status --short
 M AGENTS.md
 M docs/superpowers/arcs/wrap.md
 M docs/superpowers/debt-ledger.md
?? docs/superpowers/verification/2026-08-07-cross-target-script-hardening.md
```

(Captured immediately before staging this task's commit.)

---

## 4. Hosted CI

**Superseded by §6 below.** At the time this section was first written, Step 6
of the task-6 brief (push the branch, open the PR, and harvest hosted CI
evidence) had not been run, and the paragraph below said so. That is no longer
true: the branch has since been pushed, PR #120 opened, and the PR-head
hosted CI run has completed and been verified at step level. See §6 for the
collected evidence. The original paragraph is kept immediately below,
unedited, as the historical record of that earlier decision — it describes a
state that no longer holds and must not be read as current.

> Not run in this task by design. Step 6 of the task-6 brief (push the
> branch, open the PR, and harvest hosted CI evidence — step-level job
> conclusions, the twelve `gate=pass` lines, and the WASM job's
> `cross_target_sdk_install_seconds=... attempts=1` + four
> `result=pass ... blocking=true` lines) is an outward-facing action reserved
> for the human partner to authorize after a final whole-branch review. This
> verification record covers only the local Step 4 block above.

---

## 5. Final whole-branch review — findings and disposition

A final whole-branch code review ran over this branch before merge and
produced three findings, all now closed out. This section records what each
finding was, what was done, and the real command output, without restating
the review itself.

### 5a. Finding 1 (Important, FIXED in-branch) — unchecked `mktemp -d` fails OPEN as root

`run_self_test` created `SELF_TEST_TMP_ROOT` via a bare
`SELF_TEST_TMP_ROOT="$(mktemp -d ...)"` with no failure check. Under this
script's `set -uo pipefail` (no `set -e`), a failing `mktemp -d` silently
leaves `SELF_TEST_TMP_ROOT=""`. On macOS that still fails closed (writes to
`/` are denied), but in a root-run container — the hosted CI image is exactly
this — an empty root resolves to the filesystem root: the reviewer forced the
empty value and observed `exit=0 self_test=pass` plus ten stray files written
under `/` (`/recover.count`, `/exhaust.log.attempt-1`, …). All three ladder/
drift scenarios degrade silently while the build-blocking guard reports
green.

Fixed exactly per the review's prescribed shape in `run_self_test`
(`.github/scripts/cross-target-compile.sh`):

```bash
SELF_TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cross-target-self-test.XXXXXX")" || SELF_TEST_TMP_ROOT=""
[[ -d "$SELF_TEST_TMP_ROOT" ]] || { echo "self_test=fail label=tmp_root_unavailable"; exit 1; }
trap 'rm -rf "$SELF_TEST_TMP_ROOT"' EXIT
```

The explanatory comment directly above these lines was extended to describe
the failure mode and why the `|| SELF_TEST_TMP_ROOT=""` is load-bearing.

**Verified it bites**, by temporarily pointing the `mktemp -d` template at a
nonexistent parent directory (`/nonexistent-dir-for-finding1-drill/...`),
confirming the exact expected failure, then reverting the forcing (never
committed):

```
$ bash -c '
out="$(bash .github/scripts/cross-target-compile.sh --self-test 2>&1)"; rc=$?
printf "%s\n" "$out"
echo "exit=$rc"
'
mktemp: mkdtemp failed on /nonexistent-dir-for-finding1-drill/cross-target-self-test.Wzag36: No such file or directory
self_test=fail label=tmp_root_unavailable
exit=1
```

Reverted immediately after capture; `git diff` against the forcing edit was
confirmed empty before proceeding, and the real fix (the three-line shape
above) was re-verified passing (`self_test=pass exit=0`, see 5d below).

### 5b. Finding 2 (Minor, FIXED in-branch) — two ambient env vars the self-test never pinned

`CROSS_TARGET_SDK_INSTALL_ATTEMPTS=2` in the caller's shell made
`--self-test` fail at `label=ladder_recover_status` (the recover scenario
needs 3 attempts to succeed); `CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false` made
it fail at `label=embedded_blocks_by_default`. No live risk (CI sets neither),
but a developer's shell export could redden a required check.

Fixed by pinning both hermetically at their point of use:

- `CROSS_TARGET_SDK_INSTALL_ATTEMPTS=3` added beside the existing
  `CROSS_TARGET_SDK_INSTALL_BACKOFF=0` line in both
  `scenario_ladder_recovers_after_two_failures` and
  `scenario_ladder_exhausts_and_prints_every_tail`, each with a comment
  explaining that a scenario inheriting an ambient value is not hermetic.
- The `embedded_blocks_by_default` assertion in `run_self_test` now pins
  `CROSS_TARGET_WASM_EMBEDDED_BLOCKING=true` inline on the same command
  substitution the neighbouring `embedded_ladder_demotes_to_observational`
  assertion already uses for its own `=false` pin, with the same rationale
  comment.

**Verified both now pass** with the previously-reddening exports set:

```
$ bash -c '
out="$(CROSS_TARGET_SDK_INSTALL_ATTEMPTS=2 bash .github/scripts/cross-target-compile.sh --self-test)"; rc=$?
printf "%s\n" "$out"; echo "exit=$rc"
'
warn=sdk_install_attempt_failed attempt=1/3
warn=sdk_install_attempt_failed attempt=2/3
self_test=pass
exit=0

$ bash -c '
out="$(CROSS_TARGET_WASM_EMBEDDED_BLOCKING=false bash .github/scripts/cross-target-compile.sh --self-test)"; rc=$?
printf "%s\n" "$out"; echo "exit=$rc"
'
warn=sdk_install_attempt_failed attempt=1/3
warn=sdk_install_attempt_failed attempt=2/3
self_test=pass
exit=0
```

Both scenarios are now hermetic: neither ambient var can move their result.

### 5c. Finding 3 (Minor, RECORDED as ledger debt, not fixed) — dispatcher asymmetry across the four scripts

`derive-gate-budgets.sh:77` and `harvest-gate-corpus.sh:117` still carry the
bare `run_self_test; exit 0` dispatcher shape that Task 1 of this slice
replaced in `cross-target-compile.sh` with `run_self_test || exit 1`.
Confirmed by direct inspection:

```
$ grep -n "run_self_test" .github/scripts/derive-gate-budgets.sh .github/scripts/harvest-gate-corpus.sh .github/scripts/cross-target-compile.sh
.github/scripts/derive-gate-budgets.sh:47:run_self_test() {
.github/scripts/derive-gate-budgets.sh:77:  run_self_test
.github/scripts/harvest-gate-corpus.sh:73:run_self_test() {
.github/scripts/harvest-gate-corpus.sh:117:  run_self_test
.github/scripts/cross-target-compile.sh:509:run_self_test() {
.github/scripts/cross-target-compile.sh:1032:  run_self_test || exit 1
```

This is currently harmless (every `assert_*` in the other two scripts `exit
1`s from function scope and prints `self_test=fail`, which
`ScriptSelfTestTests`' third assertion — `self_test=fail` absent — catches
independently of the dispatcher's own exit status) but undocumented, and out
of this slice's scope to fix (touching those two scripts' dispatchers or
self-test classification was not part of this slice's task list). Per
instruction, this was **not fixed** — instead recorded as new ledger row
**D-15** in `docs/superpowers/debt-ledger.md`, citing this slice's spec, P3,
status `open`, stating the asymmetry, why it is currently harmless, and the
trigger (a future `return`-based failure path in either script) that would
make it bite.

### 5d. Full verification block re-run after all fixes

```
$ bash .github/scripts/cross-target-compile.sh --self-test
warn=sdk_install_attempt_failed attempt=1/3
warn=sdk_install_attempt_failed attempt=2/3
self_test=pass
```
(exit 0; `self_test=pass` present; `self_test=fail` absent.)

```
$ swift test --filter ScriptSelfTestTests
...
Test Suite 'ScriptSelfTestTests' passed at 2026-08-07 21:21:41.648.
	 Executed 2 tests, with 0 failures (0 unexpected) in 1.099 (1.099) seconds
```

```
$ swift test
...
Test Suite 'SwiftTextEnginePackageTests.xctest' passed at 2026-08-07 21:21:54.655.
	 Executed 361 tests, with 0 failures (0 unexpected) in 5.273 (5.295) seconds
```

361 tests, 0 failures — unchanged count from section 1a (this fix wave adds
no new test, only hardens existing script logic + docs).

### 5e. New portability evidence: real CI image + macOS host bash 3.2

This document did not previously carry direct evidence of the self-tests
running inside the actual hosted CI container image, only on the macOS
development host. As part of this final review's disposition, all four
scripts' `--self-test` were run inside `swift:6.2.1-bookworm` (the exact
image `swift-ci.yml`'s host-tests job and WASM job use) via Docker, and
separately confirmed again on the macOS host's bash 3.2.57 (the same
constraint this script's bash-3.2-compatibility requirement targets):

```
$ docker run --rm -v "$PWD/.github/scripts:/scripts:ro" swift:6.2.1-bookworm bash -c '
echo "bash: $BASH_VERSION"
grep --version | head -1
sed --version | head -1
mawk -W version 2>&1 | head -1
echo "---"
for s in cross-target-compile.sh derive-gate-budgets.sh harvest-gate-corpus.sh detect-docs-only-pr.sh; do
  echo "== $s =="
  bash /scripts/$s --self-test
  echo "exit=$?"
done
'
bash: 5.2.15(1)-release
grep (GNU grep) 3.8
sed (GNU sed) 4.9
mawk 1.3.4 20200120
---
== cross-target-compile.sh ==
warn=sdk_install_attempt_failed attempt=1/3
warn=sdk_install_attempt_failed attempt=2/3
self_test=pass
exit=0
== derive-gate-budgets.sh ==
self_test=pass
exit=0
== harvest-gate-corpus.sh ==
self_test=pass
exit=0
== detect-docs-only-pr.sh ==
self_test=pass
exit=0
```

```
$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
$ for s in cross-target-compile.sh derive-gate-budgets.sh harvest-gate-corpus.sh detect-docs-only-pr.sh; do
  echo "== $s =="
  /bin/bash ".github/scripts/$s" --self-test
  echo "exit=$?"
done
== cross-target-compile.sh ==
warn=sdk_install_attempt_failed attempt=1/3
warn=sdk_install_attempt_failed attempt=2/3
self_test=pass
exit=0
== derive-gate-budgets.sh ==
self_test=pass
exit=0
== harvest-gate-corpus.sh ==
self_test=pass
exit=0
== detect-docs-only-pr.sh ==
self_test=pass
exit=0
```

All four scripts' `--self-test` pass on both the real CI image (bash 5.2.15,
GNU grep 3.8, GNU sed 4.9, mawk 1.3.4) and the macOS host's bash 3.2.57 —
independently reproducing the review's two portability claims rather than
merely restating them.

---

## 6. PR-head hosted CI evidence (Step 6)

Step 6 has now run. PR
[#120](https://github.com/maldrakar/swift-text-engine/pull/120) is open on
branch `slice-51-cross-target-script-hardening`, head commit `e6d32ad`. All
facts below were verified at **step level** by the controller from the
downloaded run log — nothing here is re-derived or inferred from job-level
conclusions alone.

- **PR-head run**: `31207266117` (`event=pull_request`), conclusion
  **success**.
- All three required job contexts succeeded: `Host tests and benchmark gate`,
  `iOS cross-target compile`, `WASM cross-target compile`.
- `swift test` on hosted Linux: **361 tests, 0 failures** — matching the local
  count from §1a and §5d.
- Gate lines: **46 `gate=pass`, 0 `gate=fail`**, across the twelve distinct
  gated modes: `pipeline`, `variable_height`, `variable_height_mutation`,
  `structural_mutation`, `bulk_structural_mutation`, `line_query`,
  `line_geometry_query`, `column_query`, `column_geometry_query`,
  `point_query`, `point_geometry_query`, `realistic_provider`.
- **AC8's decisive line**: exactly one
  `cross_target_sdk_install_seconds=5 attempts=1` in the whole run. This is
  what proves the happy path survived the Task 3 ladder rewrite — one
  install, first attempt, no retry.
- Four WASM blocking lines, `result=pass reason=none blocking=true` — two
  kinds x two packages: `target=wasm package=core`,
  `target=wasm package=providers`, `target=wasm_embedded package=core`,
  `target=wasm_embedded package=providers`.
- Four iOS blocking lines, `result=pass reason=none blocking=true`:
  `target=ios_device package=core`, `target=ios_device package=providers`,
  `target=ios_simulator package=core`, `target=ios_simulator package=providers`.
- Both cross-target jobs ended `blocking_failures=0 exit=0`.
- **The new tests ran on hosted Linux and passed**:
  `Test Suite 'ScriptSelfTestTests' passed`, with both
  `ScriptSelfTestTests.testEveryScriptSelfTestPasses` and
  `ScriptSelfTestTests.testTableCoversEveryScriptWithASelfTest`. Worth
  stating explicitly, because this is the first hosted run in which any
  script `--self-test` assertion was capable of failing the build.

**An observation worth recording so a future reader is not misled**: the four
scripts' `self_test=pass` lines do **not** appear in the hosted job log,
because `ScriptSelfTestTests` captures each script's stdout through a pipe and
asserts on it rather than echoing it. Absence of `self_test=pass` in the CI
log is therefore expected and is not evidence the self-tests did not run —
the passing test-suite lines above are the evidence.

### 6a. Still outstanding

This record does not claim the slice is fully closed out:

- The **post-merge `push` run** has not happened. This repo's convention
  anchors proof of merged code in the post-merge run, not the PR-head run
  (see AGENTS.md's "Verification is evidence, not assertion" note) — that
  proof is still pending PR #120's merge.
- The **post-slice review** has not been written.
