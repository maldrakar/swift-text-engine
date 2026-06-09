# Cross-Target CI For TextEngineCore Design

Date: 2026-06-09

## Status

Approved design.

## Source Context

This design is Slice 13 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slices 1 through 12 built the current fixed-height proof envelope:

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
- hosted-runner evidence that an absolute realistic-provider gate is too close
  to runner variance for direct CI enforcement;
- a PR-only nonblocking hosted baseline-relative realistic-provider observation
  (Slice 12).

The brief requires `TextEngineCore` to compile for iOS and WASM without source
changes. Every slice since Slice 1 has proven this locally with the same four
checks against `TextEngineCore`:

```text
swift build --swift-sdk swift-6.2.1-RELEASE_wasm --target TextEngineCore
swift build --swift-sdk swift-6.2.1-RELEASE_wasm-embedded --target TextEngineCore
xcrun swiftc -target arm64-apple-ios17.0 -sdk <iphoneos-sdk> -parse-as-library -emit-module <core files> -module-name TextEngineCore -o ...
xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk <iphonesimulator-sdk> -parse-as-library -emit-module <core files> -module-name TextEngineCore -o ...
```

That portability is therefore proven only on the maintainer's local machine. The
Slice 11 and Slice 12 reviews both recommend landing cross-target CI before the
next public core API change. Variable-height layout is that change, so Slice 13
moves the portability checks into GitHub Actions first, as the infrastructure
precursor to variable-height layout.

Slice 13 deliberately delivers a partial cross-target CI guarantee, not the full
brief criterion in one step: a blocking, continuously enforced iOS compile proof
plus a best-effort WASM probe. The WASM probe converts the WASM portability
signal from local-only toward CI, but because it may be skipped when a matching
SDK cannot be provisioned, Slice 13 does not yet claim continuous CI proof for
WASM. Promoting the WASM probe to enforced proof is left to a later slice.

This slice also responds to a measured toolchain asymmetry. Slice 12 hosted
samples ran `Apple Swift version 6.1.2` under `Xcode 16.4` on the `macos15`
runner image, while the local checks use Swift 6.2.1 / Xcode 26.3 and a
version-locked `swift-6.2.1-RELEASE_wasm` SDK. The WASM SDK must match the
toolchain that builds with it, so the hosted WASM checks must be derived from the
runner's own Swift version, not the local one.

## Scope

Add a separate GitHub Actions job that compiles `TextEngineCore` for non-host
targets:

- iOS device (`arm64-apple-ios`) and iOS simulator, as blocking compile checks
  driven through the Swift package graph;
- WASM and embedded WASM, as best-effort observational compile checks using a
  Swift SDK matched to the runner's own toolchain.

The job runs on both `pull_request` and `push` to `main`, because it compiles
the current tree and needs no base/head pair.

## Non-Goals

Slice 13 does not:

- change `TextEngineCore` source or public API;
- change `Tests` or `ViewportBenchmarks`;
- change `Package.swift`, including adding a `platforms:` declaration; if the iOS
  build genuinely requires platform metadata, that is surfaced as an explicit
  decision in implementation, not a silent manifest change;
- change the existing `Host tests and benchmark gate` job, its steps, or its
  budgets;
- change the Slice 12 realistic relative observation or its threshold;
- promote the WASM or embedded-WASM checks to blocking;
- add repository rulesets, legacy branch protection, or required status checks
  (still externally blocked for this private repository);
- add variable-height layout, localized invalidation, storage adapters, shaping,
  rasterization, or UI integration;
- add RSS, heap, malloc, allocation-count, or peak-memory budgets.

## Selected Approach

Add a parallel job named `Cross-target compile` on `macos-latest`, alongside the
existing `Host tests and benchmark gate` job, which remains untouched. The new
job invokes a repo-owned helper, `.github/scripts/cross-target-compile.sh`, that
runs each target compile and prints one stable key-value line per target.

The helper keeps the testable shell discipline established by the Slice 12
observation helper: pure functions, a `--self-test` mode that runs without any
toolchain, and stable machine-readable output.

### Alternatives Considered

#### Steps In The Existing Job

Append iOS and WASM steps to `Host tests and benchmark gate`.

Rejected. It serializes cross-target compiles after the tests and benchmark
gate, lengthens that job, and mixes the portability concern with the
benchmark-gate concern. The Slice 11 review explicitly warns against bundling
unrelated CI concerns in one place.

#### Matrix Job Per Target

Use a build matrix with one parallel leg per target.

Rejected for Slice 13. It gives the most granular per-target status but costs
four runner allocations per event and more YAML. A single job that compiles all
targets sequentially and reports per-target lines is simpler and sufficient for
the first cross-target slice. A later slice may split into a matrix if per-leg
status becomes valuable.

#### Explicit iOS File List Or Glob With `xcrun swiftc`

Reproduce the local `xcrun swiftc -emit-module` command, either with the
enumerated core files or a `Sources/TextEngineCore/*.swift` glob.

Rejected. The explicit list silently drops coverage when a core file is added,
which directly undermines the goal of de-risking the next API change. A glob
fixes that but still bypasses the package graph. Driving the iOS build through
the Swift package graph tracks the `TextEngineCore` target definitively and
covers new files automatically.

## Workflow Architecture

The final `Swift CI` workflow keeps its existing job unchanged:

- `Host tests and benchmark gate` (host tests, synthetic gate, memory-shape
  diagnostic, RSS observation, and the PR-only realistic relative observation).

Slice 13 adds a second job:

```yaml
  cross-target-compile:
    name: Cross-target compile
    runs-on: macos-latest
    timeout-minutes: 20
    steps:
      - name: Check out repository
        uses: actions/checkout@v4
      - name: Show toolchain
        run: |
          swift --version
          xcodebuild -version
          uname -a
      - name: Compile TextEngineCore for non-host targets
        run: ./.github/scripts/cross-target-compile.sh
```

Both jobs run on `pull_request` and `push` to `main`. They run in parallel, so
the cross-target job does not extend total wall-clock for the existing job. The
new job does its own checkout and toolchain echo.

## Helper Contract

`.github/scripts/cross-target-compile.sh` responsibilities:

- compile `TextEngineCore` for iOS device and iOS simulator through the package
  graph;
- attempt to provision and compile the WASM and embedded-WASM targets matched to
  the runner's Swift version;
- print exactly one stable key-value line per target;
- set the process exit code from the blocking (iOS) results only;
- support `--self-test` for logic that does not require a toolchain.

Per-target output shape:

```text
mode=cross_target_compile target=<ios_device|ios_simulator|wasm|wasm_embedded> result=<pass|fail|skipped> reason=<short_reason_or_none> blocking=<true|false>
```

`blocking=true` for the two iOS targets and `blocking=false` for the two WASM
targets. After all targets run, the helper prints a final summary line:

```text
mode=cross_target_compile_summary ios_device=<...> ios_simulator=<...> wasm=<...> wasm_embedded=<...> blocking_failures=<n> exit=<0|1>
```

### iOS Compilation (Blocking)

Drive the iOS build through the package graph with `xcodebuild`, scheme-scoped to
`TextEngineCore` so the `ViewportBenchmarks` executable is not built:

```text
xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS'
xcodebuild build -scheme TextEngineCore -destination 'generic/platform=iOS Simulator'
```

This command pair was design-verified locally on Xcode 26.3 during
brainstorming: `xcodebuild -list` reported a `TextEngineCore` scheme, and both
destinations returned `** BUILD SUCCEEDED **`, compiling `TextEngineCore` for
`arm64-apple-ios` (defaulting to a baseline deployment target because no
`platforms:` is declared). That local proof is on Xcode 26.3 only; the CI runner
ran `Xcode 16.4` in Slice 12, where `xcodebuild` package-scheme resolution and
the empty-`platforms:` warning may behave differently. The exact runner command
is therefore treated as **requiring verified discovery on the CI runner**, per
the brief's experimental-API rule, not as an assumed-good architecture.

The package-graph mechanism is mandatory. There is no fallback to a non-graph
compile: this slice keeps a single coherent iOS mechanism so the scope and
acceptance "through the Swift package graph" requirement is unambiguous.
Verified command discovery operates only within that mechanism and is a
first-class deliverable, captured in Acceptance, not an implementation aside:

- Implementation must resolve the real scheme via `xcodebuild -list` rather than
  assuming the name.
- Robustness against runner-Xcode differences stays inside the package graph: if
  the runner's default-selected Xcode mis-resolves the package scheme or the
  destination, implementation may select a different installed Xcode (via
  `DEVELOPER_DIR` or `xcode-select`) and record which one worked. It must not
  switch to a non-graph compile.
- If no installed runner Xcode can build the package-graph iOS destinations,
  that is surfaced as a blocking finding for an explicit decision (the same way
  a required `platforms:` declaration would be), not silently degraded.
- The `swift build` with `-Xswiftc -target`/`-Xswiftc -sdk` injection is
  explicitly **rejected**: design verification showed it leaks the macOS sysroot
  (`using sysroot for 'MacOSX' but targeting 'iPhone'`), so it does not truly
  compile against the iOS SDK.
- The verification document must record the exact working `xcodebuild` command,
  the selected runner Xcode version, and the resolved SDK.

Other notes:

- The `generic/platform=...` destinations avoid pinning a concrete simulator
  runtime and match the local device + simulator coverage.
- SDKs come from the runner's selected Xcode; do not hardcode local SDK paths.
- A nonzero exit for either iOS destination (after discovery selects the working
  command) makes the target `result=fail blocking=true` and the helper exits
  nonzero, failing the job.

### WASM Compilation (Observational)

1. Read the runner Swift version from `swift --version`.
2. Attempt to install the WASM and embedded-WASM Swift SDKs matching that exact
   version via `swift sdk install`.
3. Resolve the installed SDK ids via `swift sdk list`.
4. For each available SDK, run:

```text
swift build --swift-sdk <resolved-wasm-sdk-id> --target TextEngineCore
swift build --swift-sdk <resolved-wasm-embedded-sdk-id> --target TextEngineCore
```

Outcomes:

- SDK cannot be provisioned for the runner's Swift version: `result=skipped
  reason=sdk_unavailable blocking=false`, contributes nothing to the exit code.
- SDK provisioned and compile succeeds: `result=pass blocking=false`.
- SDK provisioned but compile fails: `result=fail blocking=false`. This is
  printed and visible but does not fail the job in Slice 13.

The exact `swift sdk install` source (download URL or bundle identifier for the
runner's Swift version) and the resolved SDK ids are **doubtful and must be
confirmed by compile verification**; the helper must resolve ids from
`swift sdk list` rather than assuming the local `swift-6.2.1-RELEASE_wasm` ids.

## Error Handling

- iOS targets are blocking. Any iOS compile failure makes the job fail.
- WASM and embedded-WASM targets are observational. Provisioning failure yields
  `skipped`; a real compile failure yields `fail` but never fails the job in
  Slice 13.
- Genuine infrastructure failures in the iOS path (for example `xcodebuild`
  missing or scheme unresolved) must fail the job rather than be silently
  swallowed, because iOS is the blocking contract. The helper distinguishes a
  clean compile failure from an unresolved-scheme infrastructure failure in its
  reason field.
- The helper never changes repository source; it only compiles existing source.

## Promotion Note

WASM and embedded-WASM are introduced as observational in Slice 13, mirroring the
project's observe-before-enforce discipline (Slices 11 and 12). A later slice may
promote them to blocking once hosted evidence shows the SDK provisioning and
compile are reliable across runs. Slice 13 freezes no automatic promotion.

## Testing And Verification

Local verification for Slice 13 should include:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
.github/scripts/cross-target-compile.sh --self-test
```

These mirror every check the existing `Host tests and benchmark gate` job runs
on `push`, so the stable gates are confirmed green before and after the
cross-target work.

The existing stable gates must remain green. If the local machine has the iOS
and WASM toolchains, the maintainer may also run the helper end-to-end locally,
but the authoritative evidence is the hosted run.

`--self-test` must cover the toolchain-independent helper logic, for example:

- parsing a Swift version string into the SDK-matching key;
- classifying a target line as `pass`, `fail`, or `skipped`;
- computing `blocking_failures` and the exit code from per-target results
  (iOS failures count, WASM failures do not);
- summary-line assembly.

Hosted verification must record:

- the run ID, attempt, run URL, event, and head SHA;
- runner image, CPU model, `swift --version`, `xcodebuild -version`, and
  `uname -a`;
- the resolved iOS SDK, the selected Xcode, and the exact selected iOS compile
  commands and results;
- whether the runner-matched WASM and embedded-WASM SDKs were provisioned, their
  resolved ids if any, and each compile result or skip reason;
- the full per-target lines and the summary line;
- job duration and timeout headroom;
- the post-merge `push` run on `main`;
- a non-goal diff check proving `Sources/TextEngineCore`,
  `Sources/ViewportBenchmarks`, `Tests`, and `Package.swift` are unchanged.

## Acceptance Criteria

Slice 13 is complete when:

- a separate `Cross-target compile` job exists in `Swift CI` and runs on both
  `pull_request` and `push` to `main`;
- the existing `Host tests and benchmark gate` job is unchanged;
- iOS device and iOS simulator compile checks run through the Swift package graph
  and are blocking;
- the exact working iOS compile command is discovered and verified on the CI
  runner within the package-graph mechanism (resolving the scheme via
  `xcodebuild -list`, and if needed selecting a compatible installed Xcode), and
  the working `xcodebuild` command, selected runner Xcode version, and resolved
  SDK are recorded in the verification document;
- WASM and embedded-WASM checks use a Swift SDK matched to the runner's own
  toolchain, are observational, and report `pass`, `fail`, or `skipped` without
  failing the job;
- the helper prints stable per-target lines and a summary line, and its exit
  code reflects only the blocking iOS results;
- `.github/scripts/cross-target-compile.sh --self-test` passes;
- local stable gates pass (including `--gate`, `--memory-shape`, and
  `--memory-observation`) and `Sources/TextEngineCore`,
  `Sources/ViewportBenchmarks`, `Tests`, and `Package.swift` are unchanged;
- hosted verification records the iOS pass evidence, the WASM provisioning
  outcome (compiled or skipped with reason), job duration, and the post-merge
  push run;
- the verification record states that WASM remains observational and can be
  promoted to blocking only by a later slice.
