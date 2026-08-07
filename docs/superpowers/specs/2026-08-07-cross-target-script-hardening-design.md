# Cross-Target Script Hardening (D-1 / D-3 / D-6, + D-2) Design

- **Slice:** 51 — debt route (no wrap-arc criterion, no map node)
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md) (selection recorded
  in its decision log, 2026-08-06)
- **Ledger:** [`docs/superpowers/debt-ledger.md`](../debt-ledger.md) — D-1, D-2,
  D-3, D-6 are `scheduled(slice-51)`

## Status

Proposed. Brainstormed 2026-08-06/07; this document is the ratified design.
Three questions were decided with the user during brainstorming (self-test
enforcement location, D-6 pin strictness, D-3 testability seam) and are recorded
as Decisions 5/6/7.

**Revised 2026-08-07 after the user's spec review**, which found three P1s in the
first draft. All are folded in, and each changed a load-bearing part of the
design rather than its wording:

1. **The first draft's central construct could not fail.** `assert_equal` exits
   `1` (`:233-239`) and the script runs under `set -uo pipefail` with **no
   `set -e`** (`:2`), so an `exit 1` inside the mandated `( … )` stub subshell
   kills only that subshell — the parent would sail on and print `self_test=pass`
   with status 0. The XCTest asserting "exit 0 and `self_test=pass`" would have
   been green with a failed assertion inside, and this landed on AC2, the
   heaviest guarantee in the slice. Fixed by Decision 5 (status propagation),
   Decision 6 (a third XCTest assertion), and a **meta-mutation** in Testing
   Strategy that proves the construct itself.
2. **The coverage check was leaky in two ways, both live in this file today.**
   A substring scan counts `resolve_wasm_sdk_id` as covered because
   `resolve_wasm_sdk_id_from_list` appears four times — the repo's own
   `--variable-height` / `--variable-height-mutation` token-not-substring lesson.
   And function names appear inside `run_self_test`'s **comments** (`:370-378`
   names `count_blocking_failures`, `wasm_kind_blocking`, `wasm_skip_result`), so
   for 3 of 15 covered helpers the "delete the call" mutation would not have
   reddened. Decision 8 now carries four anti-tautology rules, not two.
3. **AC5 was false as written.** `repositoryRoot()` lives in *two* files —
   `GateFloorTests.swift:38` and `WorkflowShapeTests.swift:93`, the latter
   labelled "Twin of `repositoryRoot()` in GateFloorTests.swift". Lifting only
   one copy would leave the AC unmet; Decision 6 now absorbs both twins.

The review's P2s and polish items are folded in as Decisions 3, 6 (four-script
table), 8 (bash 3.2), 9 (temp files), 10 (`$SCRATCH` rule, D-2 home), the AC8
observable facts, and new debt row D-14.

**Second review round, same day.** It re-checked the revision mechanically and
found no surviving P1. One P2: the **Verification block violated Decision 10
rule 2 in the document that introduces it** — three of its commands were
inverted or inert at exactly the point where the invariant lives (measured; see
Verification). Folded in there and in AC8. The remaining items are absorbed
above: Goal 3's "genuinely exercised" overclaim (now "referenced"), Decision 7's
"three declared sets" wording, the self-test's own scenario functions landing
inside the partition, the Testing Strategy row mislabelled D-3 instead of D-1,
the `git` dependency the fourth table row adds to `swift test`, and the
`--self-test` dispatcher's masking `exit 0`. The round also independently
reproduced three measured claims (all four self-tests green, the four scripts'
identical `self_test=` tokens, the 11 surviving occurrences of the old global
name) and resolved a latent hazard in Decision 9's favour — the bash 3.2 EXIT
trap does not fire on subshell exit, now recorded there.

The next step after sign-off is the TDD implementation plan (`writing-plans`),
which is itself the first artifact written under the Decision 10 conventions.

## Source Context

Slice 50 closed wrap node 2 and its post-slice review ran the outer-loop
checklist, which forced a schedule-or-defer call on two P2s born in the slice 47
review and now three completed slices old (48, 49, 50). The user chose the debt
route over the topological node-3 lean. Scope was fixed at selection time: the
three `cross-target-compile.sh` items (D-1, D-3, D-6) plus D-2, which is a
plan-writing convention rather than code. D-7 stays `deferred(user, …)` — a
different surface (`harvest-gate-corpus.sh` + corpus policy) deserving its own
spec. D-13 (core binary-search triplication) and D-10/D-11 (repo-policy pins)
are out of scope by the concern-separation rule in `AGENTS.md`.

Four facts measured while exploring, all load-bearing:

- **No script self-test runs automatically.** Four scripts implement
  `--self-test` (`cross-target-compile.sh`, `derive-gate-budgets.sh`,
  `harvest-gate-corpus.sh`, `detect-docs-only-pr.sh`). The flag is documented in
  `AGENTS.md:248/251` and recorded in verification documents, but
  `swift-ci.yml` invokes a script exactly five times — the docs-only detector
  from the trusted worktree (`:68/:193/:264`) and the compile helper
  (`:214/:287`) — and **never with `--self-test`**. Every assertion in all four
  is currently a check that cannot fail the build.
- **All four self-tests pass today** (measured: exit 0, `self_test=pass`), so
  enforcing them costs nothing to adopt and reddens nothing on arrival.
- **All 15 helpers in the script's "Pure helpers" section are already exercised
  inside `run_self_test`** (hit counts 1–7). The file defines 32 functions: 15
  covered helpers, 5 harness functions (`assert_*`, `run_self_test`), 12 impure.
  A strict coverage pin therefore passes without writing coverage for existing
  code.
- **`/usr/bin/env bash` on the development host is 3.2.57** (macOS system bash),
  while the hosted Linux container ships bash 5. Anything the self-test uses must
  be bash 3.2-compatible or it splits red-locally/green-hosted (Decision 8).

## Problem

Three recorded defects in one file, and one process gap:

1. **D-1 (P2) — asymmetric-SDK-drift misdiagnosis.** Both WASM kinds come from
   one swift.org bundle. `WASM_BUNDLE_FAILED_REASON` records **failure states
   only**; nothing records that the shared bundle installed successfully. So
   when kind `wasm` installs the bundle and resolves, and kind `wasm_embedded`
   then fails to resolve, `wasm_install_precheck` returns `""` — "proceed" — and
   the script burns a second full bounded-retry ladder against an
   already-installed bundle, finally reporting `sdk_install_failed` when the
   truth is `sdk_unresolved_after_install`. Slice 47 fixed only the sibling half
   (`:569-574`). Latent under the current 6.2.1 pin, which provides both ids.
2. **D-3 (P3) — retry logfile overwrite.** `swift_sdk_install_retry` writes every
   attempt to the same `"$logfile"` (`:524`), so `print_log_tail` shows only the
   last attempt. The bounded-retry ladder itself is covered by nothing.
3. **D-6 (P3) — unpinned exemption set.** "Which functions are covered by
   `--self-test`" exists as one section header (`:42`) and two prose comments.
   Nothing fails when a function is added uncovered and unlisted. The `flagName`
   named-and-justified exemption-set pattern in `WorkflowShapeTests.swift` is the
   model to copy.
4. **D-2 (P2) — plan-assertion executability.** Slice 47's plan carried 16 of 29
   assertion sites that could not fail and 4 that could not pass, including
   `$SCRATCH` used at 23 command sites while assigned in none (review `:173`).

## Scope

**In scope**

- `.github/scripts/cross-target-compile.sh` — state model, retry ladder,
  classification arrays, new `--self-test` cases.
- `Tests/ViewportBenchmarksTests/` — one new table-driven test that drives
  `--self-test` for all four scripts, and the extraction of the process helpers
  it shares with `GateFloorTests` **and** `WorkflowShapeTests`.
- `AGENTS.md` — the four plan-assertion conventions (D-2) and a line recording
  that the script self-tests are enforced by `swift test`.
- The slice's own plan, which must obey those conventions.

**Out of scope**

- `Sources/**` — no core, provider, or benchmark change. No budget, corpus, or
  gate-registry change; committed budgets and their checksums stay byte-identical.
- `.github/workflows/swift-ci.yml` — untouched. Enforcement lands in `swift
  test`, which the host job already runs, so no workflow step, docs-only guard,
  or ordering anchor moves.
- The **bodies** of the other three self-tested scripts. They are driven, not
  edited; no classification arrays are added to them (Decision 8's residual,
  logged as D-14).
- D-7, D-13, D-10, D-11.
- Any change to what the script does on the happy path. A successful run must be
  observably identical (AC8 names the observables).

## Goals

1. The asymmetric-drift path reports the true reason, prints a truthful log
   line, and performs no second install against a bundle this script installed.
2. An install failure leaves one log per attempt, all of them printed.
3. A function added to `cross-target-compile.sh` without being classified — or
   classified as covered without being **referenced in `run_self_test`** — fails
   the build. "Referenced", not "exercised": the stronger word would overclaim
   what the check proves (Decision 7, Risks).
4. Those guarantees, and the other three scripts' self-tests, run on every
   `swift test`, locally and hosted, without a workflow edit.
5. The four plan-assertion conventions are written down and demonstrably applied
   to this slice's plan.

## Non-Goals

- Making the script pure or fully self-testable. The exemption set is the honest
  boundary, not a way station.
- Detecting asymmetric drift in a bundle this script did **not** install
  (Decision 2, Risks).
- Classification pins for the other three scripts (D-14).
- Mechanically enforcing the plan conventions (D-5 deliberately defers
  mechanical enforcement of process contracts; D-2's discharge is prose plus
  applied practice, audited by the post-slice review).
- Any hosted-cost or CI-shape change.

## Decisions

### Decision 1 — `WASM_BUNDLE_STATE` replaces `WASM_BUNDLE_FAILED_REASON`

The global is renamed because it no longer stores only failures. The semantic
that makes the fix readable:

> **The state describes the shared bundle; the precheck's return value describes
> the kind being prepared.**

`wasm_install_precheck <url> <state>` — full contract, last row new:

| `url` | recorded `<state>` | returns | meaning |
|---|---|---|---|
| empty | anything | `sdk_unavailable` | nothing to install; precedence over state (unchanged) |
| set | empty | `""` | proceed to a real install — first kind |
| set | `sdk_install_failed` | `sdk_install_failed` | bundle already failed; no second ladder (unchanged) |
| set | `sdk_unresolved_after_install` | `sdk_unresolved_after_install` | same short-circuit (unchanged) |
| set | `bundle_installed_ok` | **`sdk_unresolved_after_install`** | **new**: bundle is installed and this kind's id still does not resolve — report the truth, install nothing |

The function stays pure, so every row is a `--self-test` assertion.

### Decision 2 — `bundle_installed_ok` is recorded only for an install this script performed

`prepare_wasm_sdk` records it on the success path — install succeeded **and**
this kind's id then resolved — where it currently records nothing.

It deliberately does **not** record a state when the first kind resolves without
entering the install branch (a bundle already present on the machine). Claiming
"installed" there would suppress an install that could legitimately supply the
second kind's id: a pre-existing local SDK may be a different bundle than the
pinned URL. The cost is a documented residual (Risks) reachable only locally —
CI containers start clean, so the first kind always installs there.

### Decision 3 — The short-circuit **message** must also tell the truth

`prepare_wasm_sdk:560-561` prints `reason=bundle_already_failed
prior_reason=<state>` on every short-circuit. Under `bundle_installed_ok` the
bundle did not fail, and D-1 exists precisely to stop this path from lying. The
short-circuit therefore gains a second message branch —
`reason=bundle_installed_id_unresolved` — and the self-test asserts the **printed
line**, not only the returned word, because the log line is what a human reads
when diagnosing drift.

### Decision 4 — One logfile per attempt; the ladder owns its diagnostics

Attempt `i` writes `${logfile}.attempt-${i}`. On exhaustion,
`swift_sdk_install_retry` prints one tail per attempt in order, and the single
`print_log_tail` call in `prepare_wasm_sdk` is removed: the function that owns
the ladder owns the evidence about it, and the caller cannot know how many
attempts happened.

The ladder does not know the kind, so it gains a `label` parameter — the caller
passes the `${kind}-sdk-install` label it prints today, and each tail is labelled
`<label>-attempt-<i>`, keeping the hosted log greppable by kind. Attempt paths
come from a pure `attempt_logfile <logfile> <i>` helper, self-tested directly.

### Decision 5 — Stub seams, and subshell status that actually propagates

Two impure leaves become replaceable:

- `run_swift_sdk_install` — **new**, one line, the toolchain invocation, whose
  only purpose is to be replaceable.
- `resolve_wasm_sdk_id` — already a thin wrapper (`:505-509`) over the
  self-tested pure parser; body unchanged.

`--self-test` drives three scenarios, each as a named function whose body defines
its own stubs and runs **inside a subshell**, so an override cannot leak into
neighbouring cases: ladder fail-fail-pass, ladder three-fails, and the
**end-to-end asymmetric-drift** case (resolver stub: succeeds for `wasm`, fails
for `wasm_embedded`; install stub: counts invocations). The drift case is what
makes D-1 provable rather than inspected — the new precheck row alone is a
trivially-true pure function, while the actual defect lives in
`prepare_wasm_sdk`'s wiring. Its assertions must run inside the subshell because
`prepare_wasm_sdk` writes globals that do not escape one.
`CROSS_TARGET_SDK_INSTALL_BACKOFF=0` — an existing env override — keeps all of
this instantaneous.

**The status rule, without which none of the above can fail.** `assert_equal`
ends a failure with `exit 1` (`:233-239`), and the script sets `-uo pipefail` but
**not `-e`** (`:2`). An `exit 1` inside `( … )` therefore terminates the subshell
only; an unchecked call site would continue to `self_test=pass` and exit 0. Every
subshell scenario is therefore invoked as:

```bash
( scenario_name ) || exit 1
```

and the plan lands this construct **before** any scenario that depends on it. The
Swift side adds a second, independent net (Decision 6), and Testing Strategy adds
a meta-mutation that proves the construct rather than assuming it.

### Decision 6 — `swift test` enforces all four script self-tests

A new XCTest case is **table-driven over the four scripts** that implement
`--self-test`. Each row runs `/usr/bin/env bash <repo>/.github/scripts/<name>.sh
--self-test` through `Foundation.Process`, exactly as `GateFloorTests` already
drives `derive-gate-budgets.sh` (`:400`), locating the repository root from
`#filePath`. Three assertions per row, none redundant:

1. exit status `0` — catches a hard failure;
2. stdout contains `self_test=pass` — catches a script that degenerated into a
   silent no-op;
3. stdout contains **no** `self_test=fail` — catches a failed assertion whose
   `exit 1` was swallowed by a subshell, i.e. exactly the P1 above. This is the
   same lesson `WorkflowShapeTests` records about step-level counting: a summary
   status cannot see a second, contrary event inside the payload.

On red it attaches the script's full stdout and stderr, and names the script
path, so a missing file is not mistaken for a logic failure. Cost: ~10 lines
beyond a single-script version, and it closes the same
cannot-fail-check defect for three further scripts, the most valuable being
`detect-docs-only-pr.sh` — the trusted docs-only gate.

`runProcess` and `repositoryRoot` move into one internal test-support file, taken
from **both** existing copies (`GateFloorTests.swift:38`,
`WorkflowShapeTests.swift:93`, the latter self-described as a twin); call sites
are unchanged. `runProcess` keeps its sequential read-then-wait, but its deadlock
justification — written for "a handful of run ids" — is rewritten for the new
callers: the self-tests emit at most a few KiB (per-attempt tails are bounded by
`TAIL_LINES`, warnings go to stderr), far below the pipe buffer, and the comment
states the condition under which a future caller must switch to concurrent reads
instead.

### Decision 7 — The D-6 pin classifies by *coverage*, not by "purity"

**Two declared sets plus a derived one.** Only two arrays are hand-maintained,
both at the **top level** of the script; the third set is computed, so it cannot
drift:

- `SELF_TEST_COVERED` — declared; must be referenced in `run_self_test`'s body.
- `SELF_TEST_EXEMPT` — declared; one justification line per entry (toolchain
  call, network, filesystem, orchestration).
- the harness set — **derived** (`assert_*` plus `run_self_test`), never
  hand-listed, so it needs no maintenance and cannot go stale.

`--self-test` asserts:

1. **Partition, both directions.** The union equals the set of functions actually
   defined in the file (`^name() {`). An unclassified new function fails; a
   phantom name left by a rename fails.
2. **Coverage.** Every `SELF_TEST_COVERED` entry is referenced inside
   `run_self_test`'s body.

Classification consequences of Decisions 4–5: `swift_sdk_install_retry`,
`prepare_wasm_sdk`, and the new `attempt_logfile` are covered (the stubs make the
first two drivable); `run_swift_sdk_install` and `resolve_wasm_sdk_id` are exempt
— they *are* the process calls, and they are what the stubs replace. `usage`
becomes covered by one assertion (`usage | grep -q -- '--self-test'`), which also
pins that the flag stays documented; the pipeline's status is the right side's,
which is what the assertion wants. So the exemption set shrinks while the
boundary moves down to the process calls themselves, where it belongs.

**The self-test's own new functions are inside the partition, and that is
intended.** `assert_command_success` runs `"$@"` and therefore cannot take a
pipeline, so the `usage` check needs a named wrapper; the three Decision 5
scenarios are named functions too. All of them are top-level definitions that the
partition check sees, the derived harness set (`assert_*` + `run_self_test`) does
not cover, and that therefore land in `SELF_TEST_COVERED` — correctly, since
`run_self_test` invokes each by name. Stated here so the plan does not have to
rediscover it while the partition is failing closed on names it just introduced.

The `# Pure helpers (covered by --self-test …)` header at `:42` is superseded by
the arrays and reworded to point at them, so the file states the fact once.

### Decision 8 — Four anti-tautology rules, and bash 3.2

Check 2 is worthless unless all four hold; the first draft had only the first
two, and the review demonstrated both remaining leaks are live in this file:

1. The arrays live **outside** `run_self_test`.
2. The extracted body **excludes** the array declarations — otherwise a name
   satisfies the check by appearing in the list.
3. The extracted body has **comments stripped**. `run_self_test`'s comments name
   `count_blocking_failures`, `wasm_kind_blocking`, and `wasm_skip_result`
   (`:370-378`); without stripping, deleting those three helpers' actual calls
   would not redden.
4. Matching is by **token, not substring**:
   `(^|[^A-Za-z0-9_])name([^A-Za-z0-9_]|$)`. Otherwise `resolve_wasm_sdk_id`
   counts as covered on the strength of `resolve_wasm_sdk_id_from_list`'s four
   occurrences — the repo's own `--variable-height` /
   `--variable-height-mutation` lesson, recurring.

**Known residual, stated rather than discovered later:** string literals are
*not* stripped, so a function name inside a quoted assertion label would count as
a reference. No label in the file equals a function name today, and a
shell-grade string parser costs more than the leak is worth — while the partition
check still forces every function to be classified either way. If a label ever
collides with a function name, that is the moment to revisit.

**Everything added must be bash 3.2-compatible**, because `/usr/bin/env bash` is
3.2.57 on the macOS development host and 5.x in the hosted container, and a
version-dependent construct splits red-locally/green-hosted — the exact class of
divergence this repository pins everywhere else. Concretely: no `declare -A`, no
`mapfile`/`readarray`, no `${var^^}`. The classification uses parallel arrays or
TAB-separated `name<TAB>justification` strings read with
`while IFS=$'\t' read -r`. No script in the repo uses bash 4+ constructs today;
this decision writes the rule down so the next author does not have to
rediscover it.

### Decision 9 — Temp-file contract for the self-test

Decisions 4–5 make `--self-test` write real per-attempt logs, while the script's
header still promises "no toolchain required" — true, but it now touches the
filesystem, and that needs a stated contract rather than an accident. The
self-test creates **one** `mktemp -d` root and removes it via `trap … EXIT` in
the main shell, following `derive-gate-budgets.sh:49-53` rather than
`harvest-gate-corpus.sh:75,106`, which leaks. Because `assert_*` failures exit
the shell, cleanup must be trap-based, not a trailing `rm` — a failing self-test
must not leave debris either.

The one interaction worth stating, because it is not obvious and the whole
scheme depends on it: **an EXIT trap set in the main shell does not fire when a
`( … )` scenario subshell exits.** Verified on bash 3.2.57 — a scenario that
ends in `exit 1` leaves the root intact, and the root is removed once, when the
script itself exits. Had the trap been inherited, the first scenario would have
deleted the directory the next two still need.

### Decision 10 — D-2 ships as **four** conventions in `AGENTS.md`

The three rules from the slice 47 review, plus a fourth the review's own first
finding demands:

1. Never put a check on the left of a pipe whose right side is
   `tail`/`tee`/`jq`/`wc`/`rg` — the pipeline's status is the right side's, and a
   script's `set -o pipefail` does not reach the invoking shell. Use
   `${PIPESTATUS[0]}`, or do not pipe.
2. Never write `echo "…=$?"` after a command whose exit status is insensitive to
   the invariant (`git diff --name-only`, `git status`, `gh pr list`, `jq`,
   `sed -i`, and every pipeline exit 0 regardless). Assert with `[ -z "$(…)" ]`,
   `git diff --quiet`, or `diff … && echo OK`.
3. A plan must not assert its own HEAD commit, and must not both mandate
   inserting a string and assert zero occurrences of it.
4. **A variable used in a plan's command blocks must be assigned in the same
   block, or the block must open with `: "${VAR:?}"`.** Each Bash invocation is a
   fresh shell: slice 47's plan defined `$SCRATCH` in prose and used it at 23
   command sites, where `> "$SCRATCH/after-checksums.txt"` resolves to
   `/after-checksums.txt` for any literal executor (review `:173-176`).

**Home, and the tension.** `AGENTS.md` states that the `choosing-next-slice`
checklist "lives only in the skill — do not restate it here", and plan-writing
conventions are the same class of thing. They go in `AGENTS.md` anyway, and the
choice is deliberate: `writing-plans` is a vendored superpowers skill that this
repository does not own and cannot amend, while `AGENTS.md` is loaded every
session. Recording the tension is part of the decision, so a future reader sees a
considered exception rather than a precedent quietly broken.

Likewise this slice mixes a process artifact (D-2) into a CI/portability slice
under a rule that separates those concerns. The justification is specific rather
than general: D-2's discharge *is* a plan, and the only plan in reach is this
slice's own. Naming it keeps the exception from becoming a habit.

### Decision 11 — Nothing else moves

No `Sources/**` change, no workflow change, no budget/corpus/registry change.
The verification record states the checksum baseline and suite count so
"nothing else moved" is checkable rather than asserted.

## Component Design

`.github/scripts/cross-target-compile.sh`

| Element | Change |
|---|---|
| `WASM_BUNDLE_FAILED_REASON` | renamed `WASM_BUNDLE_STATE`; all references updated |
| `wasm_install_precheck` | new fifth contract row (Decision 1); stays pure |
| `prepare_wasm_sdk` | records `bundle_installed_ok` on the success path; new truthful short-circuit message (Decision 3); drops its `print_log_tail` call |
| `swift_sdk_install_retry` | per-attempt logfiles; new `label` parameter; one tail per attempt on exhaustion; calls the seam |
| `run_swift_sdk_install` | **new**, one line: the toolchain invocation; exempt, and the ladder's stub target |
| `attempt_logfile` | **new**, pure: `<logfile>` + attempt index → path |
| `resolve_wasm_sdk_id` | body unchanged; the drift scenario's stub target; listed exempt |
| `usage` | unchanged; becomes covered by the `--self-test` documentation assertion |
| `SELF_TEST_COVERED` / `SELF_TEST_EXEMPT` | **new** top-level, bash 3.2-compatible, justification per exempt entry |
| `run_self_test` | new cases: precheck row 5, printed short-circuit line, `attempt_logfile`, three subshell scenarios (each `( … ) || exit 1`), partition check, coverage check, `usage` documentation check; one `mktemp -d` root with `trap … EXIT` |
| `--self-test` dispatcher (`:704-707`) | `run_self_test; exit 0` → `run_self_test \|\| exit 1`. The trailing `exit 0` masks any path that *returns* non-zero rather than exiting — a scenario written with `return 1` would pass silently, which is the same defect class as the subshell P1 one level up |
| `:42` section header | reworded to point at the arrays |

`Tests/ViewportBenchmarksTests/`

| Element | Change |
|---|---|
| test-support file | **new**, internal `runProcess` + `repositoryRoot`, with the deadlock justification rewritten for the new callers |
| `GateFloorTests.swift` | private copies deleted; call sites unchanged |
| `WorkflowShapeTests.swift` | twin `repositoryRoot()` deleted; call sites unchanged |
| script self-test case | **new**, table-driven over the four scripts; asserts exit 0, `self_test=pass` present, `self_test=fail` absent; attaches output and script path on failure |

`AGENTS.md` — the four Decision 10 conventions; one line recording that the four
script self-tests are enforced by `swift test`.

## Testing Strategy

Every new guarantee is introduced test-first with a **recorded red**; the plan
orders each red before its fix.

| Guarantee | How it is made to fail |
|---|---|
| D-1 precheck row 5 | The new assertion fails before the fix (returns `""`, expected `sdk_unresolved_after_install`) |
| D-1 wiring (the real bug) | The end-to-end drift scenario asserts **exactly one** install invocation across both kinds and `sdk_unresolved_after_install` for the second; before the fix the counter reads 2 and the reason reads `sdk_install_failed` |
| D-1 truthful message | The scenario asserts the printed `reason=bundle_installed_id_unresolved` line; before the fix the line reads `reason=bundle_already_failed` |
| D-3 per-attempt logs | The ladder scenario asserts `.attempt-1`/`.attempt-2` exist with per-attempt content; fails before the fix (one file, last attempt only) |
| D-3 tails on exhaustion | The three-fail scenario asserts one labelled tail per attempt |
| **Subshell construct (meta-mutation)** | Deliberately fail an assertion **inside** a scenario subshell and confirm the script exits non-zero, prints `self_test=fail`, and reddens the XCTest. Without this the whole stub design rests on an untested assumption — it is the first draft's P1 |
| D-6 partition | Add an unclassified function → red; leave a phantom name in an array → red |
| D-6 coverage, token matching | Temporarily classify `resolve_wasm_sdk_id` as covered → must redden despite `resolve_wasm_sdk_id_from_list` appearing four times |
| D-6 coverage, comment stripping | Move a covered helper's sole call into a comment → must redden |
| Swift enforcement | Force one table row's script to exit non-zero → that row reddens with its output attached |

Not tested here: that a real `swift sdk install` behaves as the stub does (that
is what the hosted WASM job exercises), and anything about wrap, budgets, or the
core.

## Documentation Updates

- `AGENTS.md` — the four conventions; the `swift test`-enforces-self-tests line.
- `docs/superpowers/debt-ledger.md` — D-1, D-2, D-3, D-6 → `discharged(<links>)`
  at review time; **new row D-14** (P3): the coverage/exemption classification
  exists for `cross-target-compile.sh` only, while three other scripts carry
  self-tests with no such pin — visible residual rather than a silent one.
- `docs/superpowers/arcs/wrap.md:167` — states as current fact that
  `WASM_BUNDLE_FAILED_REASON` "still stores failures only"; corrected in the same
  slice that falsifies it.
- `docs/superpowers/verification/2026-08-07-cross-target-script-hardening.md` —
  commands, outputs, run ids.

## Verification

Local, recorded verbatim:

```bash
# Exit status is already discriminating here: each fails non-zero on its own fault.
swift test                                                    # suite count recorded
swift build -c release
swift run -c release ViewportBenchmarks -- --gate             # gate=pass, unchanged
./.github/scripts/cross-target-compile.sh --targets ios       # macOS host, real path

# Self-test, asserted the same three ways the XCTest asserts it (Decision 6), so the
# local and enforced checks cannot disagree about what "passing" means.
out="$(./.github/scripts/cross-target-compile.sh --self-test)"; rc=$?
[ "$rc" -eq 0 ] \
  && printf '%s\n' "$out" | grep -q 'self_test=pass' \
  && ! printf '%s\n' "$out" | grep -q 'self_test=fail' \
  && echo OK

# Negative assertions — written under Decision 10 rule 2; see the exit semantics below.
[ -z "$(rg -n 'Foundation' Sources/TextEngineCore)" ] && echo OK
git diff --quiet main -- Sources/ && echo OK
! grep -rq 'WASM_BUNDLE_FAILED_REASON' .github/scripts/ && echo OK
```

**Why the last three are not written as bare commands with an "expect empty"
comment.** Measured on this tree: `git diff --stat` exits **0** whether or not
there is a diff, so the eyeballed form cannot discriminate at all — it is rule
2's own example. `rg` and `grep -r` exit **1** on no match, so the *desired*
outcome looks like a failure to any literal executor or `set -e` block, and the
*undesired* outcome (a match) exits 0. All three are inverted or inert exactly
where the invariant lives, which is what rule 2 exists to prevent. This block
feeds the plan and the verification record nearly verbatim, and D-2's discharge
evidence is that this slice's own artifacts obey the conventions — so the rule
binds here first.

The rename assertion is **scoped to `.github/scripts/`** deliberately: the old
name legitimately survives in 11 places under `docs/` — the slice 47 plan (8),
the slice 47 review (2), and the arc file (1, corrected above). A repo-wide grep
would demand rewriting historical evidence, which the repo's own conventions
forbid.

Hosted, at **step** level: the PR-head run and the post-merge `push` run, all
three required jobs green, twelve gates `gate=pass`, and the **WASM job executing
the modified script for real** — the only proof the happy path survived. AC8
names the observables to read out of that log rather than settling for "green".

## Acceptance Criteria

1. `wasm_install_precheck` implements all five contract rows, each pinned by a
   `--self-test` assertion; the fifth was observed red first.
2. `prepare_wasm_sdk` records `bundle_installed_ok` on the success path, and the
   end-to-end drift scenario asserts exactly one install invocation across both
   kinds plus `sdk_unresolved_after_install` for the second. The pre-fix red
   (count 2, reason `sdk_install_failed`) is recorded.
3. The short-circuit prints `reason=bundle_installed_id_unresolved` under
   `bundle_installed_ok`, asserted on the printed line.
4. `swift_sdk_install_retry` writes one logfile per attempt and prints one
   labelled tail per attempt on exhaustion; the stub override is confined to a
   subshell; every scenario is invoked as `( … ) || exit 1`, and the
   **meta-mutation** proving that construct is recorded.
5. The classification exists at top level, bash 3.2-compatible, with a
   justification per exempt entry; `--self-test` enforces the two-direction
   partition and the coverage check under all four anti-tautology rules; the
   token-matching and comment-stripping mutations were both observed red.
6. A `swift test` case drives `--self-test` for **all four** scripts, asserting
   exit status, `self_test=pass` present, and `self_test=fail` absent; its red
   was observed; `runProcess`/`repositoryRoot` exist in exactly one place, with
   both former twins deleted.
7. `AGENTS.md` carries the four conventions, and this slice's plan obeys them
   (auditable claim, checked in the post-slice review). The self-test leaves no
   temp files behind, including on a failing assertion.
8. Hosted CI green at **step** level on the PR head and the post-merge `push`
   run, with these observables read out of the WASM job's log and quoted in the
   verification record: exactly one `cross_target_sdk_install_seconds=… attempts=1`
   line, and four `result=pass … blocking=true` WASM lines (two kinds × two
   packages). Local: `git diff --quiet main -- Sources/` exits 0, gate output and
   budget checksums unchanged. Every assertion in the verification record carries
   discriminating exit semantics (Decision 10 rule 2), not an "expect empty"
   comment.

## Risks And Gaps

- **The file is on a blocking path.** iOS and WASM compiles both execute this
  script; a mistake reddens CI for every PR. Mitigation: behaviour changes are
  confined to failure/short-circuit branches; the happy path is unchanged by
  construction; both hosted jobs run the modified script before merge. The
  riskiest edit is the mechanical rename — a missed reference is silent — so the
  plan asserts its absence explicitly, scoped as above.
- **Residual: asymmetric drift in a bundle this script did not install**
  (Decision 2). Locally reachable only; the second kind still burns a ladder and
  reports `sdk_install_failed`. Recorded, not papered over.
- **`SELF_TEST_COVERED` means "referenced directly in `run_self_test`", not
  "executed".** After Decision 4, `print_log_tail` genuinely runs during the
  ladder scenarios yet must be listed **exempt**, because its name appears only
  inside `swift_sdk_install_retry` — classifying it covered would fail the
  reference check. The arrays carry this definition in a doc comment so the
  classification does not mislead in the other direction, and Decision 7's
  guarantee is accounting plus reachability, never assertion quality.
- **A leaked stub override** would silently weaken later cases. Contained by the
  subshell; the coverage check cannot detect such a leak, so scenarios are
  ordered last and each is self-contained.
- **`swift test` now depends on `bash`, on four script paths, and — new — on
  `git`.** The first two were already true for one script via `GateFloorTests`;
  the failure message names the path so a missing file is not read as a logic
  failure. The `git` dependency is new and arrives with the fourth table row:
  `detect-docs-only-pr.sh`'s self-test builds a real throwaway repository
  (`git init` / `git commit`, `:167-219`). It is self-contained — it sets its own
  `user.name` / `user.email` locally (`:171-172`), so no global identity is
  required, and `git` is present in `swift:6.2.1-bookworm` (SwiftPM needs it).
  It also cleans up after itself (`rm -rf` `:233`, `rm -f` `:58/:251`; measured:
  zero temp directories before and after a run), so driving it from `swift test`
  does not make the test suite leak another script's debris. All four self-tests
  pass today on the macOS host (measured: exit 0, `self_test=pass`), so adoption
  reddens nothing.
- **D-14 (new):** three scripts gain enforcement but no classification pin. Named
  in the ledger so the half-measure is visible.
- **This slice advances no brief criterion.** Debt paydown chosen over the
  topological node-3 lean; the scoreboard is unchanged by design, and the next
  feature slice is still node 3 (y→row).
