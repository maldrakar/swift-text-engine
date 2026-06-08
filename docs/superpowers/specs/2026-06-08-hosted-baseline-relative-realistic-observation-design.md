# Hosted Baseline-Relative Realistic Observation Design

Date: 2026-06-08

## Status

Approved design.

## Source Context

This design is Slice 12 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slices 1 through 11 built the current fixed-height proof envelope:

- fixed-height viewport virtualization;
- external document/source provider traversal;
- synthetic p95/p99 benchmark gate;
- realistic 100,000-line, 11.2 MB provider benchmark;
- GitHub Actions host tests and synthetic benchmark gate;
- documented GitHub ruleset blocker for the current private repository state;
- deterministic core-owned memory-shape diagnostic and CI wiring;
- concern-based decomposition of `ViewportBenchmarks`;
- host-only RSS memory observation diagnostic and CI wiring;
- local `--realistic-provider --gate` support with calibrated local budgets;
- hosted-runner evidence showing the absolute realistic-provider p95 budget is
  too close to `macos-latest` variance for direct CI enforcement.

The product brief requires regression benchmarks that block performance
degradation. Slice 11 showed that an absolute hosted realistic-provider gate is
fragile: three accepted pull-request attempts all passed the current
`20000`/`50000` ns budgets, but the slowest hosted p95 was `19745` ns, leaving
almost no p95 headroom. The local absolute gate remains useful as a developer
smoke check, but it is only a weak backstop for hosted regressions.

Slice 12 starts the hosted baseline-relative path. It compares realistic-provider
base and head measurements in the same hosted job, but it merges as
observational-only. Blocking enforcement is deliberately deferred to a later
slice after enough real pull-request observations exist.

## Scope

Add a pull-request-only hosted observation that compares base and head
realistic-provider benchmark results on the same GitHub-hosted runner job.

Slice 12 must:

- collect at least five accepted independent paired no-op hosted samples before
  choosing the initial observation threshold;
- add a PR-only observation step to `Swift CI`;
- run the existing realistic-provider benchmark command on both base and head:

```text
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
```

- parse p95, p99, budget, and gate fields from both outputs;
- print stable key-value comparison output with base/head SHAs, p95/p99 values,
  ratios, threshold, and observation state;
- exit non-zero only for measurement, checkout, command, or parsing
  infrastructure failures;
- exit zero for measured above-threshold observations in Slice 12;
- freeze the future promotion rule for blocking enforcement.

## Non-Goals

Slice 12 does not:

- make realistic-provider comparison blocking;
- add automatic workflow promotion from observational to blocking;
- change `TextEngineCore` source or public API;
- change fixed-height viewport behavior;
- change synthetic benchmark budgets;
- change existing local realistic-provider absolute budgets;
- add repository rulesets, legacy branch protection, or required status checks;
- add iOS, WASM, or embedded WASM CI;
- add storage adapters such as memory-mapped files, ropes, piece tables, or
  editor buffers;
- add variable-height layout, localized invalidation, shaping, rasterization, or
  UI integration;
- add RSS, heap, malloc, allocation-count, or peak-memory hard budgets.

## Selected Approach

Use a two-phase hosted relative gate:

1. Slice 12 adds an observational PR comparison and records a frozen promotion
   rule.
2. A later slice may enable blocking only after the promotion rule is satisfied
   and verified in its own design, PR, commit, and verification record.

This avoids merging a noisy failing gate while starting real PR data collection
immediately. It also keeps the relative comparison aligned with the product
brief's regression language: head is compared to base under shared runner
conditions instead of against a fixed hosted absolute threshold.

### Alternatives Considered

#### Dedicated Calibration Only

Collect no-op samples and record a threshold decision without adding a permanent
observational PR step.

This has the least workflow risk, but it does not start collecting real PR
traffic for promotion. It leaves the project dependent on future dedicated
sampling.

#### Immediate Blocking After Five No-Op Samples

Enable a failing PR gate after at least five paired no-op samples if the chosen
threshold is less than or equal to `1.50`.

This is rejected. Five no-op samples are enough to start an observational
signal, but not enough to merge a failing hosted benchmark gate.

#### Re-Calibrated Hosted Absolute Budget

Derive wider absolute p95/p99 budgets from hosted evidence and run the existing
absolute gate in CI.

This is cheaper mechanically, but it remains sensitive to runner hardware and
does not distinguish code regressions from globally slow hosted machines.

## Workflow Architecture

The final `Swift CI` workflow keeps its existing stable steps:

- `Run host tests`;
- `Run synthetic benchmark gate`;
- `Run memory shape diagnostic`;
- `Run RSS memory observation diagnostic`.

For `pull_request` events, Slice 12 adds a separate observational step after the
stable gates. The observation step uses:

```text
base_sha=${{ github.event.pull_request.base.sha }}
head_sha=${{ github.event.pull_request.head.sha }}
```

The step must measure both SHAs inside one hosted job. The implementation should
use isolated checkouts or git worktrees for base and head so each benchmark runs
against the intended source tree without fragile checkout mutation.

On `push` to `main`, the relative observation is skipped because there is no PR
base/head pair. The existing stable CI gates still run.

## Data Flow

For each PR observation:

1. Fetch or check out the base SHA and head SHA.
2. Run `swift run -c release ViewportBenchmarks -- --realistic-provider --gate`
   in the base source tree.
3. Parse `p95_ns`, `p99_ns`, `budget_p95_ns`, `budget_p99_ns`, and `gate`.
4. Run the same command in the head source tree.
5. Parse the same fields from head output.
6. Compute:

```text
p95_ratio = head_p95_ns / base_p95_ns
p99_ratio = head_p99_ns / base_p99_ns
max_ratio = max(p95_ratio, p99_ratio)
```

7. Compare `max_ratio` to the observation threshold.
8. Print one stable key-value summary line.

The output shape should be easy to scan and parse:

```text
mode=realistic_relative_observation base_sha=... head_sha=... base_p95_ns=... head_p95_ns=... base_p99_ns=... head_p99_ns=... p95_ratio=... p99_ratio=... max_ratio=... observation_threshold=... observation=clean|above_threshold blocking_ready=false
```

The implementation may keep parsing logic in workflow shell code or a small
repo-owned helper. It must not require the base SHA to contain new Slice 12
helper code, because base may be an earlier commit. The existing
realistic-provider benchmark output already uses stable key-value fields, so no
new benchmark output format is required unless implementation shows the shell
parser is too brittle.

## Error Handling

The observational step exits non-zero for infrastructure failures:

- PR base or head SHA is unavailable on a pull-request event;
- a checkout or worktree cannot be created;
- the benchmark command exits non-zero;
- output is missing required fields;
- parsed p95 or p99 values are zero, negative, or non-numeric;
- ratio computation fails.

The observational step exits zero for measurement outcomes:

- `observation=clean`;
- `observation=above_threshold`.

Above-threshold observations are signal, not enforcement, in Slice 12.

## Threshold Policy

Slice 12 uses a pre-data threshold policy.

Before the observational step can merge, collect at least five accepted
independent paired no-op hosted samples. A no-op sample is accepted only when:

- base and head benchmark-executed source are equivalent for
  `Sources/TextEngineCore` and `Sources/ViewportBenchmarks`;
- any differences in docs, workflow YAML, scripts, tests, or helper tooling are
  recorded and do not affect the benchmark command being measured;
- any `Package.swift` difference is recorded and accepted only if it does not
  change the `ViewportBenchmarks` target, its dependencies, or compilation
  settings;
- base and head are measured in the same hosted job;
- the sample is from a fresh hosted workflow run or rerun, not merely another
  loop iteration inside the same job;
- both base and head benchmark commands exit successfully;
- both outputs expose required p95/p99 and gate fields.

For each accepted no-op sample, compute `max_ratio`. The initial threshold is:

```text
candidate_threshold = max_noop_ratio + 0.05
observation_threshold = min(candidate_threshold, 1.50)
```

If `candidate_threshold <= 1.50`, the threshold is considered eligible for
future blocking evaluation. If `candidate_threshold > 1.50`, Slice 12 may still
merge the nonblocking observation using `observation_threshold=1.50`, but the
verification record must state that the threshold is not safe for blocking.

The `1.50` ceiling is a hard pre-data cap. A higher threshold would weaken the
hosted relative gate too much, especially because the local absolute gate is
only a weak hosted-regression backstop.

## Promotion Policy

Blocking enforcement is not part of Slice 12.

The future promotion rule is frozen here:

- no workflow counter or automatic transition may enable blocking;
- a later slice must enable blocking through its own design, PR, commit, and
  verification record;
- the later slice may enable blocking only after at least 10 consecutive clean
  observational runs on real pull requests;
- those 10 runs must come from actual PR traffic, not solely dedicated reruns;
- any no-op flake or unexplained above-threshold observation resets the
  clean-run argument and may require threshold recalibration;
- the blocking threshold must remain less than or equal to `1.50`.

## Testing And Verification

Local verification for Slice 12 should include:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
```

If comparison or parsing logic is implemented in Swift, add focused unit tests
for:

- extracting required fields from benchmark output;
- rejecting missing or malformed fields;
- ratio calculation;
- `clean` versus `above_threshold` classification;
- infrastructure failures versus nonblocking measurement outcomes.

Hosted verification must record:

- accepted no-op sample count;
- each accepted run ID, attempt, run URL, event type, head branch, base SHA, and
  head SHA;
- base and head realistic-provider output lines for each sample;
- parsed p95/p99 values and ratios for each sample;
- `max_noop_ratio`;
- `candidate_threshold`;
- `observation_threshold`;
- whether the threshold is eligible for future blocking;
- final workflow state;
- final observational PR run metadata and output;
- source-boundary checks proving `TextEngineCore` behavior was not changed.

## Acceptance Criteria

Slice 12 is complete when:

- at least five accepted independent paired no-op hosted samples are recorded;
- an initial observation threshold is selected by the pre-data rule;
- `Swift CI` includes a PR-only realistic relative observation step;
- the step exits zero for `clean` and `above_threshold` measurements;
- the step exits non-zero for infrastructure failures;
- existing stable CI gates remain present and unchanged;
- local verification commands pass;
- hosted verification records the sample evidence and final observational run;
- the verification record explicitly states that blocking remains disabled and
  can be enabled only by a later slice under the frozen promotion rule.
