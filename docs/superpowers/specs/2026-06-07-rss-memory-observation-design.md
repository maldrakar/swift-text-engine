# RSS Memory Observation Design

Date: 2026-06-07

## Status

Approved design, written for user review.

## Source Context

This design is Slice 9 of the headless Swift text engine described in
`docs/initial-project-brief.md`.

Slices 1 through 8 built and verified the current fixed-height path:

- fixed-height viewport virtualization;
- document/source provider traversal;
- synthetic pipeline benchmark gate;
- realistic large-text provider benchmark;
- GitHub Actions wiring for host tests and the synthetic benchmark gate;
- deferred GitHub ruleset configuration for `main`;
- deterministic core-owned memory-shape diagnostic and CI wiring;
- concern-based decomposition of the `ViewportBenchmarks` executable.

The product brief requires memory owned by the layout and virtualization core
to avoid linear growth with document size. Slice 7 created deterministic
memory-shape evidence, but it intentionally did not observe process memory.
Slice 8 made the benchmark target safe to extend again. Slice 9 adds the first
host-side RSS observation layer while keeping hard memory budgets out of scope.

## Scope

Add a host-only RSS observation diagnostic mode to `ViewportBenchmarks`.

The diagnostic records process RSS snapshots around representative fixed-height
viewport operations and prints line-oriented summaries. It reuses the existing
memory-shape scenario boundaries so the output can be interpreted next to the
deterministic Slice 7 model.

The mode runs in GitHub Actions as an observational command. It fails only when
the diagnostic cannot collect usable RSS data or deterministic traversal
invariants fail. It does not fail because RSS grows by some numeric amount.

RSS has much lower resolution than the fixed-height core-owned byte model. On
Apple Silicon macOS, resident size is page-granular; the local page size used
during design review was 16,384 bytes. That is much larger than the current
`core_owned_bytes` model value from `--memory-shape`. Slice 9 should therefore
treat RSS as weak synthetic-scenario evidence: useful for catching accidental
page-scale or document-sized allocations, not for validating a tens-of-bytes
core model.

## Goals

- Add a new CLI mode: `swift run -c release ViewportBenchmarks -- --memory-observation`.
- Keep the existing `--memory-shape` output unchanged.
- Collect RSS snapshots for synthetic 100,000-line and 1,000,000-line
  scenarios with matching viewport shape.
- Collect RSS snapshots for the existing 100,000-line, >10 MB realistic
  provider scenario.
- Report provider-owned document bytes separately from process RSS snapshots.
- Report the bounded core-owned byte model beside RSS fields for context.
- Record RSS before provider setup, after provider setup, and after one
  deterministic core operation.
- Keep RSS values observational in Slice 9, with no hard memory budgets.
- Run the diagnostic in `.github/workflows/swift-ci.yml` after the existing
  memory-shape diagnostic.
- Record local verification output for the new mode, invalid CLI behavior, and
  CI workflow wiring.

## Non-Goals

Slice 9 does not:

- add RSS, heap, malloc, or allocation-count hard budgets;
- make RSS growth a merge-blocking threshold;
- present RSS deltas as exact proof of core-owned byte counts;
- add realistic-provider latency budgets or `--realistic-provider --gate`;
- change `TextEngineCore` source or public API;
- move benchmark storage fixtures into `TextEngineCore`;
- add production storage adapters such as memory-mapped files, ropes, piece
  tables, or editor buffers;
- start variable-height layout, localized invalidation, shaping, rasterization,
  or UI integration;
- retry GitHub rulesets or legacy branch protection;
- make `ViewportBenchmarks` compile for iOS, WASM, or embedded WASM.

## Selected Approach

Use a separate `--memory-observation` mode.

The main alternative was extending `--memory-shape` with RSS fields. That would
keep the CLI smaller, but it would mix deterministic model evidence with noisy
process-level observation. The existing `--memory-shape` mode should remain a
stable invariant diagnostic.

Another alternative was a narrower `--rss-observation` mode for only the
realistic-provider scenario. That would be smaller, but it would not compare
100,000-line and 1,000,000-line synthetic scenarios with the same viewport
shape, which is the clearest fixed-height evidence that core operation shape is
bounded by visible viewport plus overscan rather than total document line
count.

The separate mode is the best fit after Slice 8 because the benchmark target
now has focused files and a small dispatcher. It lets RSS observation evolve
without expanding `main.swift` or changing the deterministic memory-shape
contract.

## Architecture

`ViewportBenchmarks` remains one host-only executable target.

Expected file-level changes:

- `BenchmarkMode` gains `.memoryObservation` with output name
  `memory_observation`.
- `BenchmarkOptions` gains `--memory-observation` in usage text and parse
  rules.
- `BenchmarkProgram` dispatches `.memoryObservation` to
  `runMemoryObservationDiagnostics()`.
- A new `MemoryObservationDiagnostics.swift` owns the RSS collection,
  scenarios, summaries, formatting, and diagnostic runner.
- `.github/workflows/swift-ci.yml` gains one observational step after
  `Run memory shape diagnostic`.

`main.swift` remains process entry only. `TextEngineCore`, tests, and
`Package.swift` should stay unchanged unless implementation finds an actual
compatibility issue.

RSS collection is explicitly host-specific. The implementation should use a
Darwin/macOS process RSS source available to the benchmark target and should
document what it represents. The snapshot helper should return `Int?`, where
`nil` means collection is unavailable. If RSS cannot be collected, the
diagnostic should print a failure summary and exit non-zero.

## Components

### BenchmarkMode

Add:

- `memoryObservation`

Its output name is:

```text
memory_observation
```

### BenchmarkOptions

Add:

```text
--memory-observation  Run host RSS observation diagnostics.
```

The new flag is mutually exclusive with:

- `--gate`;
- `--range-only`;
- `--realistic-provider`;
- `--memory-shape`.

The usage text should keep the existing options and append the new one without
changing unrelated error behavior.

### MemoryObservationScenario

Executable-only scenario metadata for RSS observations.

Required scenarios:

- `100k_lines_80_visible_overscan_5`, synthetic provider;
- `1m_lines_80_visible_overscan_5`, synthetic provider;
- `100k_lines_10mb_text`, realistic large-text provider.

The synthetic comparison scenarios must use the same visible and overscan
shape. The realistic scenario should use the existing 100,000-line, 112 bytes
per line storage fixture so `provider_owned_bytes` remains `11200000`.

The runner must keep this order:

1. synthetic `100k_lines_80_visible_overscan_5`;
2. synthetic `1m_lines_80_visible_overscan_5`;
3. realistic `100k_lines_10mb_text`.

The realistic scenario runs last so its >10 MB storage allocation cannot
pollute synthetic baselines. If later work adds scenarios after a realistic
provider scenario, the runner must either release the realistic storage before
capturing the next baseline or document that the next baseline intentionally
includes retained provider storage.

### RSS Snapshot Provider

Add a small benchmark-target helper that returns the current process resident
set size in bytes.

Expected behavior:

- return a positive byte count on supported macOS hosts;
- return `nil` if collection is unavailable;
- document the page size used to interpret resident-size granularity;
- avoid Foundation in `TextEngineCore`; host-only imports are acceptable in
  `ViewportBenchmarks`.

The helper does not estimate core-owned memory. It reports process-level RSS.

### MemoryObservationSummary

One summary per scenario should include:

- provider name;
- scenario name;
- line count;
- optional document bytes;
- visible line count;
- buffered line count;
- geometry line count;
- provider line count;
- missing line count;
- `core_owned_bytes_model`;
- `provider_owned_bytes`;
- `rss_baseline_bytes`;
- `rss_after_provider_setup_bytes`;
- `rss_after_core_operation_bytes`;
- `rss_page_size_bytes`;
- `rss_provider_delta_bytes`;
- `rss_core_operation_delta_bytes`;
- observation result;
- checksum.

The summary should be formatted as one key-value line per scenario.

The field name `core_owned_bytes_model` is intentional. It should reuse the
existing `coreOwnedBytesEstimate()` logic from memory-shape diagnostics, but it
uses a distinct output key from `core_owned_bytes` to make clear that this mode
is reporting an existing deterministic model beside process-level RSS
observation.

## Data Flow

Per scenario:

1. Capture `rss_baseline_bytes`.
2. Create synthetic source metadata or realistic provider storage.
3. Capture `rss_after_provider_setup_bytes`.
4. Build a deterministic `ViewportInput` using the same middle-of-document
   offset strategy as memory-shape diagnostics.
5. Compute the `VirtualRange`.
6. Traverse buffered geometry and provider lines.
7. Fold traversal results into a checksum that is printed in the summary.
8. Capture `rss_after_core_operation_bytes` while the provider, source, range,
   and traversal results are still alive.
9. Derive visible and buffered line counts.
10. Compute `rss_provider_delta_bytes` as provider setup RSS minus baseline RSS.
11. Compute `rss_core_operation_delta_bytes` as post-operation RSS minus
    post-provider RSS.
12. Report deterministic model fields beside observed RSS fields.
13. Validate traversal invariants.
14. Print one summary line.

Scenarios run sequentially in one process. Each scenario's baseline is the RSS
snapshot captured immediately before that scenario's provider setup, not a
fresh-process baseline. RSS deltas are signed values because the allocator and
operating system may reuse or release memory between snapshots.

Release builds must keep measured objects alive through the post-operation RSS
snapshot. The implementation should use `withExtendedLifetime` or an equivalent
explicit lifetime boundary around the provider storage/source, computed range,
and checksum-producing traversal state. The post-operation snapshot must be
taken inside that lifetime boundary, after the checksum has been computed and
before the summary returns.

The realistic-provider storage may dominate RSS because it allocates the
existing large text fixture. That allocation is provider-owned evidence, not
core-owned evidence.

RSS is process-level evidence. It includes allocator behavior and unrelated
process state. Slice 9 records it for trend and review evidence; it does not
interpret exact RSS deltas as ownership proof.

For synthetic scenarios, RSS adds only weak evidence beyond the deterministic
memory-shape model because the modeled core-owned value is far below one RSS
page. A zero RSS delta does not prove zero allocation, and a one-page RSS jump
does not imply the core owns a page of document-related state.

`core_owned_bytes_model` should reuse the same estimate as the existing
memory-shape diagnostic rather than introducing a second model.

## Output Format

Output stays line-oriented and grep-friendly.

Example shape:

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=12582912 rss_after_provider_setup_bytes=12582912 rss_after_core_operation_bytes=12582912 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=0 observation=pass checksum=220776509
mode=memory_observation provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=0 rss_baseline_bytes=12582912 rss_after_provider_setup_bytes=12582912 rss_after_core_operation_bytes=12599296 rss_page_size_bytes=16384 rss_provider_delta_bytes=0 rss_core_operation_delta_bytes=16384 observation=pass checksum=2206176509
mode=memory_observation provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes_model=74 provider_owned_bytes=11200000 rss_baseline_bytes=12599296 rss_after_provider_setup_bytes=23805952 rss_after_core_operation_bytes=23822336 rss_page_size_bytes=16384 rss_provider_delta_bytes=11206656 rss_core_operation_delta_bytes=16384 observation=pass checksum=596788650
```

The RSS numbers above are illustrative. Verification must record actual local
output.

Failure lines should keep the same key-value shape where possible and include a
reason field:

```text
mode=memory_observation provider=synthetic scenario=100k_lines_80_visible_overscan_5 observation=fail reason=rss_unavailable checksum=-1
```

## CLI Behavior

Valid command:

```text
swift run -c release ViewportBenchmarks -- --memory-observation
```

Invalid combinations:

```text
swift run -c release ViewportBenchmarks -- --memory-observation --gate
swift run -c release ViewportBenchmarks -- --memory-observation --range-only
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-observation --memory-shape
```

Unknown flags keep the existing `error=<message>` plus usage behavior.

Existing commands keep their current behavior:

```text
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
```

## Workflow Integration

Add one step after `Run memory shape diagnostic`:

```yaml
- name: Run RSS memory observation diagnostic
  run: swift run -c release ViewportBenchmarks -- --memory-observation
```

The workflow job name remains `Host tests and benchmark gate`. This preserves
the existing status-check context.

The workflow does not parse RSS output and does not enforce memory budgets.
The executable owns collection failures, deterministic traversal invariants,
and process exit behavior.

## Error Handling

- RSS collection unavailable: print a failure line and return non-zero.
- RSS snapshot is zero or negative: print a failure line and return non-zero.
- Viewport computation failure: print a failure line and return non-zero.
- Missing provider lines inside the buffered range: print a failure line and
  return non-zero.
- Unexpected geometry or provider traversal count: print a failure line and
  return non-zero.
- RSS growth alone: print observed values and still return zero if all
  collection and traversal invariants pass.

## Testing

The benchmark target remains verified primarily through release CLI commands.

No XCTest coverage is required for the first RSS observation implementation
unless implementation extracts pure helpers that are cheap to test. The key
contract is process output and exit behavior.

Existing `TextEngineCore` tests should remain unchanged.

## Verification

Slice 9 verification should record:

```text
swift test
swift build -c release
swift run -c release ViewportBenchmarks
swift run -c release ViewportBenchmarks -- --range-only
swift run -c release ViewportBenchmarks -- --gate
swift run -c release ViewportBenchmarks -- --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-shape
swift run -c release ViewportBenchmarks -- --memory-observation
swift run -c release ViewportBenchmarks -- --memory-observation --gate
swift run -c release ViewportBenchmarks -- --memory-observation --range-only
swift run -c release ViewportBenchmarks -- --memory-observation --realistic-provider
swift run -c release ViewportBenchmarks -- --memory-observation --memory-shape
rg -n "Run memory shape diagnostic|Run RSS memory observation diagnostic|--memory-observation" .github/workflows/swift-ci.yml
git diff -- Sources/TextEngineCore Tests Package.swift
```

All four invalid `--memory-observation` combinations listed in CLI Behavior are
expected to exit non-zero.

Cross-target compile verification for `TextEngineCore` is only required if
Slice 9 changes core source unexpectedly. `ViewportBenchmarks` remains
host-oriented.

## Performance And Memory Expectations

Expected deterministic shape:

- range computation remains O(1) with respect to total document size;
- geometry traversal remains O(buffered line count);
- provider traversal remains O(buffered line count);
- synthetic provider setup should not allocate document-sized storage;
- realistic provider setup allocates the existing >10 MB caller-owned storage;
- one core operation should not scan or copy the full document.

Expected RSS interpretation:

- RSS snapshots may vary by runner, allocator state, and previous scenarios;
- RSS snapshots are expected to be page-granular, so small core-owned model
  values cannot be resolved directly;
- realistic-provider setup may show a large RSS delta;
- synthetic 100,000-line and 1,000,000-line scenarios should make it visible
  that total line count alone does not require document-sized provider storage,
  but they should not be overstated as exact RSS proof of the core byte model;
- core operation RSS deltas are evidence for trend review, not pass/fail
  budgets in Slice 9.

## Acceptance Criteria

Slice 9 is complete when:

- `ViewportBenchmarks` supports `--memory-observation`.
- `--memory-observation` prints one key-value summary line for each required
  scenario.
- The output includes baseline, after-provider, and after-core-operation RSS
  snapshots.
- The output includes provider-owned bytes and the bounded core-owned byte
  model.
- The output includes derived provider and core-operation RSS deltas.
- The diagnostic exits non-zero when RSS collection or deterministic traversal
  invariants fail.
- RSS values are not treated as hard budgets.
- `--memory-observation --gate` exits non-zero with a clear error.
- `--memory-observation --range-only` exits non-zero with a clear error.
- `--memory-observation --realistic-provider` exits non-zero with a clear
  error.
- `--memory-observation --memory-shape` exits non-zero with a clear error.
- `.github/workflows/swift-ci.yml` runs the observational command after
  `--memory-shape`.
- Existing benchmark modes and `--memory-shape` output remain unchanged except
  for natural latency variation.
- `main.swift` remains a small process entry file.
- `TextEngineCore`, `Tests`, and `Package.swift` remain unchanged unless a
  verified compatibility fix is required.
- Verification records host tests, release build, all existing benchmark modes,
  new memory-observation output, invalid CLI behavior, workflow scan, and
  non-goal diff checks.

## Open Decisions For Later Slices

- Whether repeated local and hosted samples are stable enough for RSS budgets.
- Whether allocator-level statistics should supplement RSS.
- Whether realistic-provider latency budgets should become gateable.
- Whether cross-target CI should be added before the next public core API
  change.
- Whether repository settings can enforce the existing `Swift CI` status check.
- When to begin variable-height layout and localized invalidation.
