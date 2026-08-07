# Cross-Target Script Hardening (D-1 / D-3 / D-6, + D-2) Design

- **Slice:** 51 — debt route (no wrap-arc criterion, no map node)
- **Arc:** [`docs/superpowers/arcs/wrap.md`](../arcs/wrap.md) (selection recorded
  in its decision log, 2026-08-06)
- **Ledger:** [`docs/superpowers/debt-ledger.md`](../debt-ledger.md) — D-1, D-2,
  D-3, D-6 are `scheduled(slice-51)`

## Status

Proposed. Brainstormed 2026-08-06/07; this document is the ratified design.
Three questions were decided with the user during brainstorming and are recorded
as Decisions 4/5/6 below (self-test enforcement location, D-6 pin strictness,
D-3 testability seam). The next step after sign-off is the TDD implementation
plan (`writing-plans`), which is itself the first artifact written under the
Decision 7 conventions.

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

Two facts discovered while exploring, both load-bearing for this design:

- **`cross-target-compile.sh --self-test` runs nowhere automatically.**
  `.github/workflows/swift-ci.yml` invokes the script only as `--targets ios`
  (`:214`) and `--targets wasm` (`:287`). The string `--self-test` appears only
  in verification records — it was run by hand during slices 46/47. Any
  assertion added to it today is a check that cannot fail the build, which is
  precisely the failure mode this repository documents about itself.
- **All 15 helpers in the script's "Pure helpers" section are already exercised
  inside `run_self_test`** (measured hit counts 1–7). The file defines 32
  functions: 15 covered helpers, 5 harness functions (`assert_*`,
  `run_self_test`), 12 impure. So a strict coverage pin passes today without
  writing a single new coverage case for existing code.

## Problem

Three recorded defects in one file, and one process gap:

1. **D-1 (P2) — asymmetric-SDK-drift misdiagnosis.** Both WASM kinds come from
   one swift.org bundle. `WASM_BUNDLE_FAILED_REASON` records **failure states
   only**; nothing records that the shared bundle installed successfully. So
   when kind `wasm` installs the bundle and resolves, and kind `wasm_embedded`
   then fails to resolve (the bundle lacks its id), `wasm_install_precheck`
   returns `""` — "proceed" — and the script burns a second full bounded-retry
   ladder against an already-installed bundle, finally reporting
   `sdk_install_failed` when the truth is `sdk_unresolved_after_install`. Slice
   47 fixed only the sibling half (it records `sdk_unresolved_after_install`
   when *this* kind hits that path, `:569-574`). Latent under the current 6.2.1
   pin, which provides both ids.
2. **D-3 (P3) — retry logfile overwrite.** `swift_sdk_install_retry` writes
   every attempt to the same `"$logfile"` (`:524`), so `print_log_tail` shows
   only the last attempt when diagnosing an install failure. The bounded-retry
   ladder itself is covered by nothing.
3. **D-6 (P3) — unpinned exemption set.** "Which functions are covered by
   `--self-test`" exists as one section header (`:42`) and two prose comments.
   Nothing fails when a new function is added to the file uncovered and
   unlisted. The `flagName` named-and-justified exemption-set pattern in
   `WorkflowShapeTests.swift` is the model to copy.
4. **D-2 (P2) — plan-assertion executability.** Slice 47's plan carried 16 of 29
   assertion sites that could not fail and 4 that could not pass. The repo has a
   mature discipline for making *runtime* checks fail loudly and no equivalent
   discipline for its own plans.

## Scope

**In scope**

- `.github/scripts/cross-target-compile.sh` — the state model, the retry ladder,
  the classification arrays, and the new `--self-test` cases.
- `Tests/ViewportBenchmarksTests/` — one new test that drives `--self-test`, and
  the extraction of the two process helpers it shares with `GateFloorTests`.
- `AGENTS.md` — the plan-assertion conventions (D-2) and a line recording that
  the script's self-test is now enforced by `swift test`.
- The slice's own plan, which must obey those conventions.

**Out of scope**

- `Sources/**` — no core, provider, or benchmark change. No budget, corpus, or
  gate-registry change; the 46 committed budgets and their checksums stay
  byte-identical.
- `.github/workflows/swift-ci.yml` — untouched. Enforcement lands in `swift
  test`, which the host job already runs (Decision 4), so no workflow step,
  docs-only guard, or ordering anchor moves.
- D-7, D-13, D-10, D-11 — other surfaces, other slices.
- Any change to what the script *does* on the happy path. The install/compile
  behaviour of a successful run must be observably identical.

## Goals

1. The asymmetric-drift path reports the true reason and performs no second
   install attempt against a bundle this script already installed.
2. An install failure leaves one log per attempt, all of them printed.
3. A function added to `cross-target-compile.sh` without being classified —
   or classified as covered without being exercised — fails the build.
4. Those three guarantees run on every `swift test`, locally and in the hosted
   host job, without a workflow edit.
5. The three plan-assertion conventions are written down and demonstrably
   applied to this slice's plan.

## Non-Goals

- Making the whole script pure or fully self-testable. The exemption set is the
  honest boundary, not a temporary state to be eliminated.
- Detecting asymmetric drift in a bundle this script did **not** install (see
  Decision 2 and Risks).
- Mechanically enforcing the plan conventions (D-5 deliberately defers
  mechanical enforcement of process contracts; D-2's discharge is prose plus
  applied practice, and the review audits it).
- Any hosted-cost or CI-shape change.

## Decisions

### Decision 1 — `WASM_BUNDLE_STATE` replaces `WASM_BUNDLE_FAILED_REASON`

The global is renamed because it no longer stores only failures. The semantic
that makes the whole fix readable:

> **The state describes the shared bundle; the precheck's return value describes
> the kind being prepared.**

`wasm_install_precheck <url> <state>` — full contract, the last row new:

| `url` | recorded `<state>` | returns | meaning |
|---|---|---|---|
| empty | anything | `sdk_unavailable` | nothing to install; takes precedence over state (unchanged) |
| set | empty | `""` | proceed to a real install — this is the first kind |
| set | `sdk_install_failed` | `sdk_install_failed` | bundle already failed; do not burn a second ladder (unchanged) |
| set | `sdk_unresolved_after_install` | `sdk_unresolved_after_install` | same short-circuit (unchanged) |
| set | `bundle_installed_ok` | **`sdk_unresolved_after_install`** | **new**: the bundle is installed and this kind's id still does not resolve — report the truth, install nothing |

The function stays pure (arguments in, one word out), so every row above is a
`--self-test` assertion.

### Decision 2 — `bundle_installed_ok` is recorded only for an install this script performed

`prepare_wasm_sdk` records `bundle_installed_ok` on the success path — install
succeeded **and** this kind's id then resolved — where it currently records
nothing.

It deliberately does **not** record a state when the first kind resolves without
entering the install branch (a bundle already present on the machine). Claiming
"installed" there would suppress an install that could legitimately supply the
second kind's id: a pre-existing local SDK may be a different bundle than the
pinned URL. The cost is a documented residual (Risks) reachable only locally —
CI containers start clean, so the first kind always installs there.

### Decision 3 — One logfile per attempt; the ladder owns its own diagnostics

Attempt `i` writes `${logfile}.attempt-${i}`. On exhaustion,
`swift_sdk_install_retry` itself prints one tail per attempt in order, and the
single `print_log_tail` call in `prepare_wasm_sdk` is removed: the function that
owns the ladder owns the evidence about it, and the caller cannot know how many
attempts happened.

The ladder does not know the kind, so it gains a `label` parameter — the caller
passes `${kind}-sdk-install` (the label it prints today) and each tail is
labelled `<label>-attempt-<i>`, keeping the log greppable by kind.

Attempt filenames come from a pure `attempt_logfile <logfile> <i>` helper, so the
naming is self-tested rather than inlined in a loop.

### Decision 4 — `--self-test` is enforced by `swift test`, via a stub seam for the ladder

Two halves, both chosen with the user:

- **Enforcement.** A new XCTest case runs `/usr/bin/env bash
  <repo>/.github/scripts/cross-target-compile.sh --self-test` through
  `Foundation.Process`, exactly as `GateFloorTests` already drives
  `derive-gate-budgets.sh` (`GateFloorTests.swift:400`), locating the repository
  root from `#filePath`. It asserts **both** a zero exit status **and** the
  presence of `self_test=pass` in stdout. Each covers what the other cannot: the
  exit code alone would pass for a script that degenerated into a no-op; the
  string alone would pass for a script that printed it and then failed. On red
  it attaches the script's full stdout and stderr to the failure message.
  No workflow edit: the host job already runs `swift test`.
- **Seam.** The toolchain call moves into a one-line `run_swift_sdk_install`
  whose only purpose is to be replaceable. `--self-test` overrides it **inside a
  subshell** (so the override cannot leak into neighbouring cases) with a stub
  whose output differs per attempt, and drives the ladder twice: fail-fail-pass
  and three-fails. `CROSS_TARGET_SDK_INSTALL_BACKOFF=0` — already an env
  override — keeps this instantaneous. As a side effect the bounded-retry logic
  itself is pinned for the first time.

  The same subshell technique extends one step further, and this is what makes
  D-1 provable rather than inspected: `resolve_wasm_sdk_id` is already a thin
  impure wrapper (`:505-509`) delegating to the self-tested pure parser, so a
  stub that resolves for kind `wasm` and fails for `wasm_embedded` — paired with
  a `run_swift_sdk_install` stub that **counts its invocations** — lets
  `--self-test` drive the whole asymmetric-drift scenario end to end and assert
  both halves of the fix: exactly one install invocation across both kinds, and
  `sdk_unresolved_after_install` as the second kind's reason. Without this, the
  new precheck row is a trivially-true pure function and the actual bug — the
  wiring in `prepare_wasm_sdk` — would rest on inspection alone.

`runProcess` and `repositoryRoot` are currently `private` in
`GateFloorTests.swift`; they move to one internal test-support file used by both
files rather than being copied. (Copying them in a slice whose subject is
duplication debt would be a poor look, and D-13 already tracks one triplication.)

### Decision 5 — The D-6 pin classifies by *coverage*, not by "purity"

Three arrays at the **top level** of the script (not inside `run_self_test`):

- `SELF_TEST_COVERED` — must be referenced in `run_self_test`'s body.
- `SELF_TEST_HARNESS` — the harness itself (`assert_*`, `run_self_test`).
- `SELF_TEST_EXEMPT` — one justification line per entry (toolchain call, network,
  filesystem, orchestration).

`--self-test` asserts:

1. **Partition, both directions.** The union of the three arrays equals the set
   of functions actually defined in the file (`^name() {`). An unclassified new
   function fails; a phantom name left behind by a rename fails.
2. **Coverage.** Every `SELF_TEST_COVERED` entry is referenced inside
   `run_self_test`'s body.

Two rules keep check 2 from becoming a tautology, and they are part of the
design, not implementation trivia: the arrays live outside `run_self_test`, and
the body extracted for the reference scan excludes the array declarations.
Otherwise a name would satisfy the check merely by appearing in the list — the
check-that-cannot-fail this slice exists to remove.

Classification consequences of Decisions 3–4: `swift_sdk_install_retry`,
`prepare_wasm_sdk`, and the new `attempt_logfile` are `SELF_TEST_COVERED` (the
stubs make the first two drivable); the new `run_swift_sdk_install` and the
existing `resolve_wasm_sdk_id` are `SELF_TEST_EXEMPT` — they *are* the toolchain
calls, and they are what the stubs replace. So the exemption set shrinks by one
net function while gaining the two seam wrappers: the boundary moves down to the
process calls themselves, which is where it belongs. The `# Pure helpers
(covered by --self-test …)` section header at `:42` is
superseded by the explicit arrays and is reworded to point at them, so the file
has exactly one statement of the fact.

### Decision 6 — The classification is a partition of names, not proof of quality

The pin proves that every function is *accounted for* and that covered ones are
*reached*. It does not prove an assertion is meaningful, nor that a covered
function's behaviour is fully exercised. That boundary is stated so a future
reader does not over-trust the guarantee — the same honesty
`testJobNamesMatchRequiredCheckContexts` carries about the ruleset half it
cannot reach.

### Decision 7 — D-2 ships as conventions in `AGENTS.md`, applied to this slice's plan

A short subsection records the three rules from the slice 47 review:

1. Never put a check on the left of a pipe whose right side is
   `tail`/`tee`/`jq`/`wc`/`rg` — the pipeline's status is the right side's, and
   the script's own `set -o pipefail` does not reach the invoking shell. Use
   `${PIPESTATUS[0]}`, or do not pipe.
2. Never write `echo "…=$?"` after a command whose exit status is insensitive to
   the invariant (`git diff --name-only`, `git status`, `gh pr list`, `jq`,
   `sed -i`, and every pipeline exit 0 regardless). Assert with `[ -z "$(…)" ]`,
   `git diff --quiet`, or `diff … && echo OK`.
3. A plan must not assert its own HEAD commit, and must not both mandate
   inserting a string and assert zero occurrences of it.

Prose only, no mechanical check (Non-Goals). The discharge evidence is this
slice's own plan: every assertion site in it is written under these rules, and
the post-slice review audits that claim.

### Decision 8 — Nothing else moves

No `Sources/**` change, no workflow change, no budget/corpus/registry change.
The verification record states the checksum baseline and suite count so the
"nothing else moved" claim is checkable rather than asserted.

## Component Design

`.github/scripts/cross-target-compile.sh`

| Element | Change |
|---|---|
| `WASM_BUNDLE_FAILED_REASON` | renamed `WASM_BUNDLE_STATE`; all references updated |
| `wasm_install_precheck` | new fifth contract row (Decision 1); stays pure |
| `prepare_wasm_sdk` | records `bundle_installed_ok` on the success path; drops its `print_log_tail` call (Decision 3) |
| `swift_sdk_install_retry` | per-attempt logfiles; new `label` parameter; prints one tail per attempt on exhaustion; calls the seam |
| `run_swift_sdk_install` | **new**, one line: the toolchain invocation; exempt, and the ladder's stub target |
| `attempt_logfile` | **new**, pure: `<logfile>` + attempt index → path |
| `resolve_wasm_sdk_id` | body unchanged; becomes the drift scenario's stub target and is listed exempt |
| `SELF_TEST_COVERED` / `SELF_TEST_HARNESS` / `SELF_TEST_EXEMPT` | **new** top-level arrays with justifications |
| `run_self_test` | new cases: precheck row 5, the two ladder scenarios, the partition check, the coverage check |
| `:42` section header | reworded to point at the arrays |

`Tests/ViewportBenchmarksTests/`

| Element | Change |
|---|---|
| test-support file | **new**, internal `runProcess` + `repositoryRoot` lifted out of `GateFloorTests.swift` |
| `GateFloorTests.swift` | its two private copies deleted; call sites unchanged |
| cross-target self-test case | **new**: drives `--self-test`, asserts exit status **and** `self_test=pass`, attaches output on failure |

`AGENTS.md` — the Decision 7 conventions, plus one line noting that the script's
`--self-test` is enforced by `swift test` (so the next reader does not
rediscover the gap this design opens with).

## Testing Strategy

Every new guarantee below is introduced test-first and has a **recorded red**;
the plan's steps are ordered so each red is observed before its fix.

| Guarantee | How it is made to fail |
|---|---|
| D-1 fifth precheck row | The new assertion fails before the fix: precheck returns `""` where `sdk_unresolved_after_install` is expected |
| D-1 state recording (the real bug) | The end-to-end drift case (both stubs, Decision 4) asserts exactly **one** install invocation across both kinds and `sdk_unresolved_after_install` for the second; before the fix the counter reads 2 and the reason reads `sdk_install_failed` — the defect reproduced, then fixed |
| D-3 per-attempt logs | The ladder case asserts `.attempt-1`/`.attempt-2` exist with per-attempt content; fails before the fix (one file, last attempt only) |
| D-3 tails on exhaustion | The three-fail case asserts one labelled tail per attempt appears in the output |
| D-6 partition | Mutation: add an unclassified function → red; rename a function leaving a phantom array entry → red |
| D-6 coverage | Mutation: delete an existing helper's invocation from `run_self_test` → red |
| Swift enforcement | Mutation: force `--self-test` to exit non-zero → the XCTest case reddens with the script's output attached |

Not tested here: that a real `swift sdk install` behaves as the stub does (that
is what the hosted WASM job exercises), and anything about wrap, budgets, or the
core.

## Documentation Updates

- `AGENTS.md` — Decision 7 conventions; the `swift test`-enforces-`--self-test`
  line.
- `docs/superpowers/debt-ledger.md` — D-1, D-2, D-3, D-6 → `discharged(<links>)`
  at review time.
- `docs/superpowers/arcs/wrap.md` — a decision-log line recording the outcome
  (the selection line is already there).
- `docs/superpowers/verification/2026-08-07-cross-target-script-hardening.md` —
  commands, outputs, run ids.

## Verification

Local, recorded verbatim in the verification document:

```bash
swift test                                                  # full suite, count recorded
./.github/scripts/cross-target-compile.sh --self-test        # self_test=pass, exit 0
swift build -c release
swift run -c release ViewportBenchmarks -- --gate            # gate=pass, unchanged
rg -n "Foundation" Sources/TextEngineCore                    # empty
./.github/scripts/cross-target-compile.sh --targets ios      # macOS host, real path
git diff --stat main -- Sources/                             # empty: nothing in the core moved
```

Hosted, at **step** level (job conclusion is not evidence): the PR-head run and
the post-merge `push` run, both with all three required jobs green, the twelve
gates `gate=pass`, and — the load-bearing one — the **WASM job executing the
modified script for real**, which is the only proof the happy path survived the
refactor. Run ids recorded in the verification document.

## Acceptance Criteria

1. `wasm_install_precheck` implements all five contract rows of Decision 1, each
   pinned by a `--self-test` assertion, and the fifth was observed red first.
2. `prepare_wasm_sdk` records `bundle_installed_ok` on the success path, and the
   end-to-end asymmetric-drift scenario — driven in `--self-test` by the
   resolver and install stubs — asserts **exactly one** install invocation
   across both kinds and `sdk_unresolved_after_install` as the second kind's
   reason. The pre-fix red (count 2, reason `sdk_install_failed`) is recorded.
3. `swift_sdk_install_retry` writes one logfile per attempt and prints one
   labelled tail per attempt on exhaustion; both are asserted through the stub
   seam, and the stub override is confined to a subshell.
4. The three classification arrays exist at top level with a justification per
   exempt entry; `--self-test` enforces the two-direction partition and the
   coverage check; both mutations in Testing Strategy were observed red.
5. A `swift test` case drives `--self-test` and asserts exit status **and**
   `self_test=pass`; its red was observed; `runProcess`/`repositoryRoot` exist in
   exactly one place.
6. `AGENTS.md` carries the three plan-assertion conventions, and this slice's
   plan obeys them (auditable claim, checked in the post-slice review).
7. Local verification commands recorded with outputs; `git diff main --
   Sources/` empty; gate output and budget checksums unchanged.
8. Hosted CI green at **step** level on the PR head and on the post-merge `push`
   run, with the WASM job's real execution of the modified script cited by run
   id.

## Risks And Gaps

- **The file is on a blocking path.** iOS and WASM compiles both execute this
  script; a mistake here reddens CI for every PR. Mitigation: behaviour changes
  are confined to the failure/short-circuit branches, the happy path is
  unchanged by construction, and both hosted jobs run the modified script before
  merge. The riskiest edit is the mechanical rename of the state global — a
  missed reference is silent, so the plan treats "no occurrence of the old name
  remains" as an explicit assertion (written per Decision 7's rules).
- **Residual: asymmetric drift in a bundle this script did not install**
  (Decision 2). Locally reachable only; the second kind still burns a ladder and
  reports `sdk_install_failed`. Recorded rather than papered over; a future slice
  may add a "resolved-without-install" state if the case is ever observed.
- **The D-6 pin proves accounting, not quality** (Decision 6).
- **Stub-override discipline.** A leaked function override would silently
  weaken every later self-test case. Contained by the subshell, and the coverage
  check would not catch such a leak — stated so the plan orders the ladder cases
  last regardless.
- **`swift test` now depends on `bash` and on the script's presence.** Already
  true via `GateFloorTests`; no new class of dependency, but the failure message
  must name the script path so a missing-file failure is not mistaken for a
  logic failure.
- **This slice advances no brief criterion.** It is debt paydown chosen over the
  topological node-3 lean; the arc's scoreboard is unchanged by design, and the
  next feature slice is still node 3 (y→row).
