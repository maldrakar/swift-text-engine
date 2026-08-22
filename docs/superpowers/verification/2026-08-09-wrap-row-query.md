# Slice 53 — wrap y→row query (`visualRowAt`) — verification record

This slice shipped `ViewportVirtualizer.visualRowAt(y:layout:)` — the wrap-aware
`lineAt` analog over the visual-row axis (wrap node 3) — plus its four test suites
(mapping, validation/parity, infinite-width equivalence, round-trip + probe-count
bound) and the observational, non-gateable `--wrap-row-query` benchmark mode. It
touches no gated code path: no gate budget, no gate scenario, and no CI workflow file
changed. Sections 1-9 record the local sweep this task ran directly. Section 10 records the
hosted CI evidence: its PR-head half (10.1) is filled in from the real logs of run
`32594785647`; its post-merge half (10.2) from run `32595528239` on merge commit `c2e6b37`.

---

## 1. `swift test` — full suite

Baseline, from Task 1 Step 1 (`.superpowers/sdd/2026-08-09-wrap-row-query/task-1-report.md`),
before any of this slice's work:

```
Executed 362 tests, with 0 failures (0 unexpected) in 5.703 (5.723) seconds
```

Command run for this record:

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift test > /tmp/slice53-final-test.txt 2>&1; then echo "SUITE RED"; else echo "suite green"; fi
rg -n "Executed [0-9]+ tests" /tmp/slice53-final-test.txt | tail -2
```

Output:

```
suite green
980:	 Executed 396 tests, with 0 failures (0 unexpected) in 5.304 (5.327) seconds
982:	 Executed 396 tests, with 0 failures (0 unexpected) in 5.304 (5.328) seconds
```

362 → 396 is +34 tests across the slice: Task 3 (9 mapping tests +
`VisualRowLocation`/`VisualRowQuery`), Task 4 (12 validation/parity tests), Task 5 (2
equivalence tests), Task 6 (1 round-trip + 3 probe-count tests), Task 7 (7 benchmark
option/checksum tests — `WrapRowQueryOptionsTests` + `WrapRowQueryChecksumTests`). 0
failures throughout.

### 1.1 Re-run after the post-review coverage fold-in

A review pass found that `WrapRowQueryCountTests` pinned its bound on **one** fixture,
wrapped at `.infinity` — one row per line, `totalRows == lineCount`. Drill 7 (section
9) records the gap and its demonstrated red;
`testProbeCountIsIndependentOfRowsPerLine` closes it. Re-run of the full suite with
that test in place:

```
Executed 397 tests, with 0 failures (0 unexpected) in 5.359 (5.384) seconds
```

396 → 397, +1 test. No `Sources/` file changed for it — `git status --porcelain`
showed exactly one modified path,
`Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift` — so no gate, budget, or
benchmark number in this record is affected by the fold-in, and sections 2-8 stand as
recorded.

## 2. `swift build -c release`

```bash
cd /Users/aabanschikov/swift-text-engine
if ! swift build -c release > /tmp/slice53-final-build.txt 2>&1; then echo "RELEASE BUILD RED"; else echo "release build green"; fi
```

Output: `release build green`.

## 3. Foundation-free scan

```bash
cd /Users/aabanschikov/swift-text-engine
FOUNDATION="$(rg -n 'Foundation' Sources/TextEngineCore || true)"
if [ -z "$FOUNDATION" ]; then echo "PASS: Foundation-free"; else echo "FAIL:"; echo "$FOUNDATION"; fi
```

Output: `PASS: Foundation-free`.

## 4. All twelve blocking gates

This slice touches no gated code path — `visualRowAt`, `VisualRowLocation`,
`VisualRowQuery`, and `--wrap-row-query` are all new surface, and the shared ladder
extraction (Task 2) only reshapes `compute(_:layout:)`'s own validation into a
callable helper without changing its behavior (see Task 2's own refactor-safety drill
in section 9). Any gate movement here would be a genuine finding.

```bash
cd /Users/aabanschikov/swift-text-engine
for flag in "" "--realistic-provider" "--variable-height" "--variable-height-mutation" \
            "--structural-mutation" "--bulk-structural-mutation" "--line-query" \
            "--line-geometry-query" "--column-query" "--column-geometry-query" \
            "--point-query" "--point-geometry-query"; do
  if ! swift run -c release ViewportBenchmarks -- $flag --gate > "/tmp/slice53-gate$(echo "$flag" | tr -d ' -').txt" 2>&1; then
    echo "GATE RED: ${flag:-default}"
  else
    echo "gate=pass: ${flag:-default}"
  fi
done
swift run -c release ViewportBenchmarks -- --memory-shape
```

Exit-status summary (all twelve):

```
gate=pass: default
gate=pass: --realistic-provider
gate=pass: --variable-height
gate=pass: --variable-height-mutation
gate=pass: --structural-mutation
gate=pass: --bulk-structural-mutation
gate=pass: --line-query
gate=pass: --line-geometry-query
gate=pass: --column-query
gate=pass: --column-geometry-query
gate=pass: --point-query
gate=pass: --point-geometry-query
```

Full `mode=` summary lines, one block per flag (every scenario printed `gate=pass`,
`failures=0`, and both headroom figures inside the calibrated band):

```
=== default (synthetic pipeline) ===
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1221 p99_ns=1274 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=17.2x headroom_p99=33.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1308.2x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5167 p99_ns=5508 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=16.3x headroom_p99=30.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=302.6x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=17269 p99_ns=17906 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=16.2x headroom_p99=31.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=93.1x gate=pass checksum=18852477646272000

=== --realistic-provider ===
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5687 p99_ns=5996 failures=0 budget_p95_ns=98000 budget_p99_ns=200000 headroom_p95=17.2x headroom_p99=33.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=278.0x gate=pass checksum=756321289736960

=== --variable-height ===
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=228 p99_ns=254 failures=0 budget_p95_ns=4100 budget_p99_ns=8200 headroom_p95=18.0x headroom_p99=32.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=6561.7x gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=701 p99_ns=745 failures=0 budget_p95_ns=14000 budget_p99_ns=28000 headroom_p95=20.0x headroom_p99=37.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=2237.1x gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2294 p99_ns=2497 failures=0 budget_p95_ns=46000 budget_p99_ns=92000 headroom_p95=20.1x headroom_p99=36.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=667.5x gate=pass checksum=3536425156727040

=== --variable-height-mutation ===
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=420 p99_ns=469 failures=0 budget_p95_ns=6600 budget_p99_ns=14000 headroom_p95=15.7x headroom_p99=29.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=3553.7x gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1671 p99_ns=1782 failures=0 budget_p95_ns=24000 budget_p99_ns=48000 headroom_p95=14.4x headroom_p99=26.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=935.3x gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5439 p99_ns=5722 failures=0 budget_p95_ns=82000 budget_p99_ns=170000 headroom_p95=15.1x headroom_p99=29.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=291.3x gate=pass checksum=3571078666132451

=== --structural-mutation ===
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1037 p99_ns=1126 failures=0 budget_p95_ns=16000 budget_p99_ns=32000 headroom_p95=15.4x headroom_p99=28.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1480.2x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=6140 p99_ns=6899 failures=0 budget_p95_ns=71000 budget_p99_ns=150000 headroom_p95=11.6x headroom_p99=21.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=241.6x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=31547 p99_ns=32846 failures=0 budget_p95_ns=290000 budget_p99_ns=580000 headroom_p95=9.2x headroom_p99=17.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=50.7x gate=pass checksum=3379593298396981

=== --bulk-structural-mutation ===
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3011 p99_ns=3276 failures=0 budget_p95_ns=51000 budget_p99_ns=110000 headroom_p95=16.9x headroom_p99=33.6x budget_absolute_p99_ns=16666666 headroom_absolute_p99=5087.5x gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=10336 p99_ns=12212 failures=0 budget_p95_ns=130000 budget_p99_ns=260000 headroom_p95=12.6x headroom_p99=21.3x budget_absolute_p99_ns=16666666 headroom_absolute_p99=1364.8x gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=47260 p99_ns=50181 failures=0 budget_p95_ns=450000 budget_p99_ns=900000 headroom_p95=9.5x headroom_p99=17.9x budget_absolute_p99_ns=16666666 headroom_absolute_p99=332.1x gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=73544 p99_ns=83528 failures=0 budget_p95_ns=1400000 budget_p99_ns=2800000 headroom_p95=19.0x headroom_p99=33.5x budget_absolute_p99_ns=16666666 headroom_absolute_p99=199.5x gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=165226 p99_ns=182523 failures=0 budget_p95_ns=3000000 budget_p99_ns=6000000 headroom_p95=18.2x headroom_p99=32.9x budget_absolute_p99_ns=16666666 headroom_absolute_p99=91.3x gate=pass checksum=82203678997143

=== --line-query ===
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=12 p99_ns=15 failures=0 budget_p95_ns=190 budget_p99_ns=440 headroom_p95=15.8x headroom_p99=29.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=111111.1x gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=16 p99_ns=19 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=17.5x headroom_p99=29.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=87719.3x gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=21 p99_ns=29 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=15.2x headroom_p99=22.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=57471.2x gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=85 p99_ns=104 failures=0 budget_p95_ns=1700 budget_p99_ns=3400 headroom_p95=20.0x headroom_p99=32.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=16025.6x gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=117 p99_ns=139 failures=0 budget_p95_ns=2100 budget_p99_ns=4200 headroom_p95=17.9x headroom_p99=30.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=11990.4x gate=pass checksum=639841547520

=== --line-geometry-query ===
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=18 p99_ns=21 failures=0 budget_p95_ns=250 budget_p99_ns=500 headroom_p95=13.9x headroom_p99=23.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=79365.0x gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=19 p99_ns=23 failures=0 budget_p95_ns=340 budget_p99_ns=680 headroom_p95=17.9x headroom_p99=29.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=72463.7x gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=23 p99_ns=28 failures=0 budget_p95_ns=380 budget_p99_ns=760 headroom_p95=16.5x headroom_p99=27.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=59523.8x gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=139 p99_ns=171 failures=0 budget_p95_ns=3000 budget_p99_ns=6000 headroom_p95=21.6x headroom_p99=35.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=9746.6x gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=182 p99_ns=224 failures=0 budget_p95_ns=3400 budget_p99_ns=6800 headroom_p95=18.7x headroom_p99=30.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=7440.5x gate=pass checksum=852321495040

=== --column-query ===
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=15 p99_ns=18 failures=0 budget_p95_ns=200 budget_p99_ns=440 headroom_p95=13.3x headroom_p99=24.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=92592.6x gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=16 p99_ns=18 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=17.5x headroom_p99=31.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=92592.6x gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=21 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=15.2x headroom_p99=30.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=79365.0x gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=31 p99_ns=32 failures=0 budget_p95_ns=500 budget_p99_ns=1000 headroom_p95=16.1x headroom_p99=31.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=52083.3x gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=39 p99_ns=44 failures=0 budget_p95_ns=600 budget_p99_ns=1200 headroom_p95=15.4x headroom_p99=27.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=37878.8x gate=pass checksum=639841560320

=== --column-geometry-query ===
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=20 p99_ns=24 failures=0 budget_p95_ns=260 budget_p99_ns=520 headroom_p95=13.0x headroom_p99=21.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=69444.4x gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=19 p99_ns=24 failures=0 budget_p95_ns=350 budget_p99_ns=700 headroom_p95=18.4x headroom_p99=29.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=69444.4x gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=22 p99_ns=24 failures=0 budget_p95_ns=390 budget_p99_ns=780 headroom_p95=17.7x headroom_p99=32.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=69444.4x gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=34 p99_ns=35 failures=0 budget_p95_ns=820 budget_p99_ns=1700 headroom_p95=24.1x headroom_p99=48.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=47619.0x gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=54 p99_ns=57 failures=0 budget_p95_ns=690 budget_p99_ns=1400 headroom_p95=12.8x headroom_p99=24.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=29239.8x gate=pass checksum=839521520640

=== --point-query ===
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=29 p99_ns=38 failures=0 budget_p95_ns=760 budget_p99_ns=1600 headroom_p95=26.2x headroom_p99=42.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=43859.6x gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=32 p99_ns=35 failures=0 budget_p95_ns=680 budget_p99_ns=1400 headroom_p95=21.3x headroom_p99=40.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=47619.0x gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=40 p99_ns=45 failures=0 budget_p95_ns=920 budget_p99_ns=1900 headroom_p95=23.0x headroom_p99=42.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=37037.0x gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=41 p99_ns=41 failures=0 budget_p95_ns=1100 budget_p99_ns=2200 headroom_p95=26.8x headroom_p99=53.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=40650.4x gate=pass checksum=640022228480

=== --point-geometry-query ===
mode=point_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=42 p99_ns=43 failures=0 budget_p95_ns=980 budget_p99_ns=2000 headroom_p95=23.3x headroom_p99=46.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=38759.7x gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=56 p99_ns=60 failures=0 budget_p95_ns=990 budget_p99_ns=2000 headroom_p95=17.7x headroom_p99=33.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=27777.8x gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=46 p99_ns=56 failures=0 budget_p95_ns=1200 budget_p99_ns=2400 headroom_p95=26.1x headroom_p99=42.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=29761.9x gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=69 p99_ns=82 failures=0 budget_p95_ns=1300 budget_p99_ns=2600 headroom_p95=18.8x headroom_p99=31.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=20325.2x gate=pass checksum=5915921755926273280
```

Twelve for twelve, `gate=pass` on every scenario, all headroom figures inside the
3x-100x band and every `headroom_absolute_p99` comfortably above 1x. No gate moved.
This slice's claim that it touches no gated code path holds by observation, not just
by inspection of the diff.

## 5. `--wrap-row-query` — all four scenarios

```bash
cd /Users/aabanschikov/swift-text-engine
swift run -c release ViewportBenchmarks -- --wrap-row-query
```

Output:

```
mode=wrap_row_query scenario=uniform_1k total_rows=1000 query_p95_ns=167 query_p99_ns=167 checksum=31968000
mode=wrap_row_query scenario=uniform_100k total_rows=100000 query_p95_ns=250 query_p99_ns=250 checksum=3198048000
mode=wrap_row_query scenario=narrow_100k total_rows=400000 query_p95_ns=292 query_p99_ns=334 checksum=3495461000
mode=wrap_row_query scenario=clamped_100k total_rows=400000 query_p95_ns=84 query_p99_ns=84 checksum=3500361000
```

All four checksums non-zero and match Task 7's own run byte-for-byte
(`31968000`, `3198048000`, `3495461000`, `3500361000`) — only the latency figures
differ between the two runs, as expected of unpinned timing on a shared host.

Both barrier assertions (Task 7's Step 7), re-run for this record:

```bash
cd /Users/aabanschikov/swift-text-engine
CI_HIT="$(rg -n 'wrap-row-query|wrap_row_query' .github/workflows/swift-ci.yml || true)"
if [ -z "$CI_HIT" ]; then
  echo "PASS: absent from swift-ci.yml"
else
  echo "FAIL: mode reached CI:"; echo "$CI_HIT"
fi
BARE="$(swift run -c release ViewportBenchmarks -- --wrap-row-query | rg -o '(^| )p95_ns=[0-9]+' || true)"
if [ -z "$BARE" ]; then
  echo "PASS: no bare p95_ns= token — harvester emits no row"
else
  echo "FAIL: bare latency token present:"; echo "$BARE"
fi
```

Output:

```
PASS: absent from swift-ci.yml
PASS: no bare p95_ns= token — harvester emits no row
```

## 6. `--wrap-compute` — smoke run only

```bash
cd /Users/aabanschikov/swift-text-engine
swift run -c release ViewportBenchmarks -- --wrap-compute
```

Output:

```
mode=wrap_compute width=inf total_rows=100000 compute_p95_ns=208 compute_p99_ns=209 drain_p95_ns=15875 reindex_ns=17357791
mode=wrap_compute width=40 total_rows=200000 compute_p95_ns=209 compute_p99_ns=209 drain_p95_ns=9000 reindex_ns=18016916
mode=wrap_compute width=10 total_rows=800000 compute_p95_ns=209 compute_p99_ns=250 drain_p95_ns=4917 reindex_ns=24455000
```

This is **not** evidence about Task 2's shared-ladder extraction (Decision 5). Three
reasons, copied from the spec:

1. `total_rows` is read straight off the provider at `WrapComputeBenchmark.swift:73` —
   it never touches the extracted `validateVisualRowLayout` / `compute(_:layout:)`
   path this slice changed, so a passing run here says nothing about the ladder.
2. Drained rows are never printed — `WrapComputeBenchmark.swift:92` fires only on
   `Int.min`, a sentinel that never occurs in this smoke run, so the drain loop's
   correctness is not observable from this output.
3. `.failure` is silent because `WrapComputeBenchmark.swift:85` has no `else` — a
   validation failure produces no printed line at all, indistinguishable from the mode
   simply not being invoked.

The three non-`inf` lines run without error and print plausible numbers, which is the
extent of what this smoke run demonstrates.

## 7. `--memory-shape`

```bash
cd /Users/aabanschikov/swift-text-engine
swift run -c release ViewportBenchmarks -- --memory-shape
```

Output:

```
mode=memory_shape provider=synthetic scenario=100k_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=220776509
mode=memory_shape provider=synthetic scenario=1m_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=2206176509
mode=memory_shape provider=large_text scenario=100k_lines_10mb_text line_count=100000 document_bytes=11200000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=74 provider_owned_bytes=11200000 benchmark_owned_bytes=0 invariant=pass checksum=596788650
mode=memory_shape provider=variable_uniform scenario=100000_lines_80_visible_overscan_5 line_count=100000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=76561875
mode=memory_shape provider=variable_uniform scenario=1000000_lines_80_visible_overscan_5 line_count=1000000 visible_lines=80 buffered_lines=90 touched_lines=90 geometry_lines=90 provider_lines=90 missing_lines=0 core_owned_bytes=90 provider_owned_bytes=0 benchmark_owned_bytes=0 invariant=pass checksum=765061875
```

All five scenarios: `invariant=pass`.

## 8. `./.github/scripts/cross-target-compile.sh --self-test`

```bash
cd /Users/aabanschikov/swift-text-engine
./.github/scripts/cross-target-compile.sh --self-test
```

Output:

```
warn=sdk_install_attempt_failed attempt=1/3
warn=sdk_install_attempt_failed attempt=2/3
self_test=pass
```

Exit status `0`. The two `warn=` lines are the self-test deliberately exercising the
bounded-retry failure path (no toolchain/SDK is provisioned in this environment); they
are expected self-test output, not a fault. This is a **shell-logic self-test only** —
it compiles nothing and is **not** portability evidence for iOS or WASM. That evidence
comes from the hosted cross-target compile jobs, recorded (pending) in section 10.

## 9. The falsifiability drills, plus Task 2 Step 4's refactor-safety check

AC12's **six** numbered drills are recorded below unchanged. Two further mutation
drills sit beside them and are labelled as such: Task 2 Step 4's refactor-safety check
(first, because it ran before any of `visualRowAt`'s own tests existed) and Drill 7
(last, because it ran after them, in review). Neither is one of AC12's six; AC12 is
satisfied by drills 1-6 exactly as specified.

### Task 2 Step 4 — refactor-safety mutation (not one of the six drills)

Mutation: final line of `validateVisualRowLayout` changed from
`return .rows(totalRows)` to `return .rows(totalRows + 1)`.

Observed:

```
EXPECTED: validation suite still GREEN (error cases all resolve)
EXPECTED RED: success-path suite caught it
18:/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapComputeTests.swift:36: error: -[TextEngineCoreTests.WrapComputeTests testScrollToBottomIsInVisualRows] : XCTAssertEqual failed: ("9") is not equal to ("8")
```

Validation suite stayed green (error cases all resolve before reaching the mutated
line); the success-path suite (`WrapComputeTests`) went red with exactly one failing
assertion — the off-by-one surfacing as a wrong visual-row index. Reverted; re-run
confirmed `PASS: all three wrap-compute suites green after revert`.

### Drill 1 — half-open boundary (`WrapRowQueryTests`)

Mutated `Sources/TextEngineCore/LineMetricsSource.swift`'s `binarySearchLineIndex`:
`metrics.offset(ofLine: mid) <= target` → `< target`.

Observed (`EXPECTED RED`), `testExactRowTopBelongsToThatRow`, 5 sub-assertions, every
exact row-top `y` shifted the located row down by one:

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryTests.swift:71: error: -[TextEngineCoreTests.WrapRowQueryTests testExactRowTopBelongsToThatRow] : XCTAssertEqual failed: ("0") is not equal to ("1") - y == 1 * rowHeight
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryTests.swift:71: error: -[TextEngineCoreTests.WrapRowQueryTests testExactRowTopBelongsToThatRow] : XCTAssertEqual failed: ("1") is not equal to ("2") - y == 2 * rowHeight
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryTests.swift:71: error: -[TextEngineCoreTests.WrapRowQueryTests testExactRowTopBelongsToThatRow] : XCTAssertEqual failed: ("2") is not equal to ("3") - y == 3 * rowHeight
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryTests.swift:71: error: -[TextEngineCoreTests.WrapRowQueryTests testExactRowTopBelongsToThatRow] : XCTAssertEqual failed: ("3") is not equal to ("4") - y == 4 * rowHeight
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryTests.swift:71: error: -[TextEngineCoreTests.WrapRowQueryTests testExactRowTopBelongsToThatRow] : XCTAssertEqual failed: ("4") is not equal to ("5") - y == 5 * rowHeight
```

`Executed 1 test, with 5 failures (0 unexpected)`. Reverted (`<` → `<=`); `git diff`
on the mutated file empty after revert.

### Drill 2 — `rowInLine` subtraction (`WrapRowQueryTests`)

Mutated `Sources/TextEngineCore/WrapPositionQuery.swift`:
`globalRow - layout.firstVisualRow(ofLine: logicalLine)` → `... + 1`.

Observed (`EXPECTED RED`), full suite `Executed 9 tests, with 11 failures`, including
both tests the brief named:

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryTests.swift:47: error: -[TextEngineCoreTests.WrapRowQueryTests testInteriorOfAMultiRowLine] : XCTAssertEqual failed: ("3") is not equal to ("2")
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryTests.swift:60: error: -[TextEngineCoreTests.WrapRowQueryTests testEverySingleRowRoundTripsItsOwnIndices] : XCTAssertEqual failed: ("1") is not equal to ("0") - globalRow 0
```

(plus collateral in `testClampedToTop`, `testClampedToBottomNamesTheLastRowOfTheLastLine`,
`testBlankLineIsAddressable`, `testLastInteriorYIsStillInRange`, expected since every
located branch computes `rowInLine` through the same mutated line). Reverted (`+ 1`
removed); `swift test --filter WrapRowQueryTests` re-run: `GREEN CONFIRMED` (9/9). `git
diff` on both touched source files empty before commit.

### Drill 3 — clamp forced to `.inRange` (`WrapRowQueryEquivalenceTests`)

Mutated `Sources/TextEngineCore/WrapPositionQuery.swift`: replaced `clamp:
location.clamp` with `clamp: .inRange` in the `.row(VisualRowLocation(...))`
construction inside `visualRowAt`.

Observed (`EXPECTED RED`), `Executed 2 tests, with 8 failures (0 unexpected)`, all 8 at
the clamped boundary `y` samples for both `width=inf` and `width=1000.0`:

```
WrapRowQueryEquivalenceTests.swift:61: error: ... XCTAssertEqual failed: ("inRange") is not equal to ("clampedToTop") - y=-100.0 width=inf
WrapRowQueryEquivalenceTests.swift:61: error: ... XCTAssertEqual failed: ("inRange") is not equal to ("clampedToTop") - y=-0.001 width=inf
WrapRowQueryEquivalenceTests.swift:61: error: ... XCTAssertEqual failed: ("inRange") is not equal to ("clampedToBottom") - y=60.0 width=inf
WrapRowQueryEquivalenceTests.swift:61: error: ... XCTAssertEqual failed: ("inRange") is not equal to ("clampedToBottom") - y=160.0 width=inf
WrapRowQueryEquivalenceTests.swift:61: error: ... XCTAssertEqual failed: ("inRange") is not equal to ("clampedToTop") - y=-100.0 width=1000.0
WrapRowQueryEquivalenceTests.swift:61: error: ... XCTAssertEqual failed: ("inRange") is not equal to ("clampedToTop") - y=-0.001 width=1000.0
WrapRowQueryEquivalenceTests.swift:61: error: ... XCTAssertEqual failed: ("inRange") is not equal to ("clampedToBottom") - y=60.0 width=1000.0
WrapRowQueryEquivalenceTests.swift:61: error: ... XCTAssertEqual failed: ("inRange") is not equal to ("clampedToBottom") - y=160.0 width=1000.0
```

(`testNarrowWidthIsNotEquivalent` unaffected — it never inspects `clamp`.) Reverted;
`git diff` empty, `git status` showed only the new untracked test file. Re-run after
revert: `PASS`, `Executed 2 tests, with 0 failures (0 unexpected)`.

### Drill 4 — parity sees divergence (`WrapRowQueryValidationTests`)

Swapped the first two checks in `visualRowAt`
(`Sources/TextEngineCore/WrapPositionQuery.swift`) so `!y.isFinite` ran before
`layout.lineCount < 0`.

Observed (`EXPECTED RED`):

```
/Users/aabanschikov/swift-text-engine/Tests/TextEngineCoreTests/WrapRowQueryValidationTests.swift:115: error: -[TextEngineCoreTests.WrapRowQueryValidationTests testLadderParityWithCompute] : XCTAssertEqual failed: ("Optional(TextEngineCore.ViewportValidationError.negativeLineCount)") is not equal to ("Optional(TextEngineCore.ViewportValidationError.nonFiniteValue)") - negativeLineCount (badValue: true): compute and visualRowAt disagree
```

`compute` still answers `.negativeLineCount`; `visualRowAt` (with the swapped head)
now answers `.nonFiniteValue` — the `negativeLineCount (badValue: true)` parity cell
diverges. Reverted immediately; `git diff` on the mutated file confirmed empty.

### Drill 5 — linear scan replacing the provider-native inverse (`WrapRowQueryCountTests`)

This drill exists in **two forms**, run against two different shapes of
`ProbeCounter`. Form A is the original drill, recorded at implementation time. Form
B is a second scan shape the fix-wave review (post-slice-53 whole-branch review)
identified as **invisible to Form A's counter** — that gap, not a new drill, is what
motivated widening `ProbeCounter` to sum `firstVisualRowCalls +
visualRowCountCalls` (`totalCalls`) rather than track `firstVisualRowCalls` alone.

**Form A — linear scan reading `firstVisualRow(ofLine:)` per step** (the scan
originally shipped in this drill). Mutated
`Sources/TextEngineCore/WrapPositionQuery.swift`, replacing the
`logicalLine(containingVisualRow:)` call with a linear scan.

Observed (`EXPECTED RED`), all three `WrapRowQueryCountTests` tests failed, probe
counts far past the bound of 14:

```
WrapRowQueryCountTests.swift:105: testClampedQueriesStillSearchTheLayoutAxis
  XCTAssertLessThanOrEqual failed: ("1026") is greater than ("14") - y=16385.0
WrapRowQueryCountTests.swift:78: testInRangeQueryIsLogarithmicOnTheLayoutAxis
  XCTAssertLessThanOrEqual failed: ("704") is greater than ("14")
WrapRowQueryCountTests.swift:87: testProbeCountDoesNotGrowLinearlyWithTheDocument
  XCTAssertLessThan failed: ("1004") is not less than ("102")
```

Observed probe counts under Form A: **704, 1004, 1026** (the clamp case at 1026
sits slightly above the predicted ~700-1000 band — it walks from a boundary near
`lineCount` rather than from 0). Contrast run under the same still-in-place mutation:
`WrapRowQueryRoundTripTests` (1/1) and the three other mapping suites
(`WrapRowQueryTests`, `WrapRowQueryValidationTests`, `WrapRowQueryEquivalenceTests`,
4/4 total) all stayed **GREEN** — the linear scan is correct, only slow, so only the
probe-count pin can see the regression. Reverted; `git diff` on the mutated file
confirmed empty, `git status --porcelain` showed only the two new test files
untracked. Re-run post-revert: `PASS` on both `WrapRowQueryRoundTripTests` and
`WrapRowQueryCountTests`.

**Form B — linear scan reading `visualRowCount(inLine:)` per step** (added in the
post-slice-53 fix wave). Mutated the same call site in `WrapPositionQuery.swift`
to a scan of the same shape, but walking `visualRowCount(inLine:)` per line
examined instead of `firstVisualRow(ofLine:)`:

```swift
var scanLine = 0
var scanCumulative = 0
while true {
    let rowsInScanLine = layout.visualRowCount(inLine: scanLine)
    if scanCumulative + rowsInScanLine > globalRow { break }
    scanCumulative += rowsInScanLine
    scanLine += 1
}
let logicalLine = scanLine
```

First, reproduced the gap the review reported: with `CountingVisualRowLayout`
still forwarding `visualRowCount(inLine:)` **uncounted** (the shape shipped at
Task 8, `Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift` before this
fix wave), all three `WrapRowQueryCountTests` stayed **GREEN** under the Form B
mutation:

```
Executed 3 tests, with 0 failures (0 unexpected) in 0.004 seconds
```

and the observed total for `testInRangeQueryIsLogarithmicOnTheLayoutAxis`,
forced out via a temporary failing assertion, was exactly **3**
(`firstVisualRowCalls=3 visualRowCountCalls=0 total=3`) — the 2 ladder probes plus
the 1 final `rowInLine` probe, with the entire scan itself invisible because
nothing counts `visualRowCount(inLine:)` calls. This confirms the review's finding:
the old counter cannot see this scan shape at any document size.

Then, with `ProbeCounter` widened to `totalCalls = firstVisualRowCalls +
visualRowCountCalls` (this fix wave's change) and the same Form B mutation still in
place, all three `WrapRowQueryCountTests` went **RED**:

```
WrapRowQueryCountTests.swift:123: testClampedQueriesStillSearchTheLayoutAxis
  XCTAssertLessThanOrEqual failed: ("1027") is greater than ("14") - y=16385.0
WrapRowQueryCountTests.swift:96: testInRangeQueryIsLogarithmicOnTheLayoutAxis
  XCTAssertLessThanOrEqual failed: ("704") is greater than ("14")
WrapRowQueryCountTests.swift:105: testProbeCountDoesNotGrowLinearlyWithTheDocument
  XCTAssertLessThan failed: ("1004") is not less than ("102")
```

Observed probe counts under Form B with the widened counter: **704, 1004, 1027**
(the clamp case at 1027 differs from Form A's 1026 by one probe — a shape artifact
of the two scans' loop bounds, not a discrepancy worth chasing). Contrast run under
the same still-in-place Form B mutation: `WrapRowQueryTests` (2/2),
`WrapRowQueryValidationTests` (12/12), `WrapRowQueryEquivalenceTests` (9/9), and
`WrapRowQueryRoundTripTests` (1/1) all stayed **GREEN** — same story as Form A, the
scan is correct, only slow. Reverted both the source mutation and the temporary
uncounted-forwarding probe; `git diff` on `WrapPositionQuery.swift` confirmed empty
before commit; `swift test --filter WrapRowQueryCountTests` re-run post-revert:
`PASS`, `Executed 3 tests, with 0 failures (0 unexpected)`.

**Net effect**: Form A was always visible to the counter (it reads
`firstVisualRow`, the one field the original `ProbeCounter` tracked). Form B was
invisible to that same counter — a scan can walk the document via either provider
call, and a counter that only watches one of them has a blind spot exactly the size
of the other. Widening `ProbeCounter` to sum both closes it: both forms now redden
identically (modulo the one-probe shape difference above).

### Drill 6 — parity is blind to absence (`WrapViewportVirtualizer.swift`)

Deleted the `wrapWidth` check (and its comment) from the shared helper
`validateVisualRowLayout`. Three commands, three separate expected outcomes, all
matched — this drill produces THREE observed lines, all required:

```
EXPECTED GREEN: parity is blind to absence (this is the point)
EXPECTED RED: visualRowAt side caught it
EXPECTED RED: compute side caught it
```

1. `WrapRowQueryValidationTests.testLadderParityWithCompute` — **green**
   (`Executed 1 test, with 0 failures (0 unexpected)`): both callers accept the
   now-under-validated `wrapWidth` identically, so parity cannot see a change that
   lands on both sides the same way.
2. `WrapRowQueryValidationTests.testNonPositiveWrapWidth` — **red**, 4 failures:
   ```
   WrapRowQueryValidationTests.swift:44: error: ... XCTAssertEqual failed:
   ("row(TextEngineCore.VisualRowLocation(globalRow: 0, logicalLine: 0, rowInLine: 0, clamp: TextEngineCore.LineLocation.Clamp.inRange))")
   is not equal to
   ("failure(TextEngineCore.ViewportValidationError.nonPositiveWrapWidth)")
   Executed 1 test, with 4 failures (0 unexpected)
   ```
3. `WrapComputeValidationTests.testNonPositiveWrapWidth` — **red**, 4 failures:
   ```
   WrapComputeValidationTests.swift:33: error: ... XCTAssertEqual failed:
   ("success(TextEngineCore.VirtualRange(visibleStart: 0, visibleEndExclusive: 2, bufferStart: 0, bufferEndExclusive: 2, isAtTop: true, isAtBottom: true))")
   is not equal to
   ("failure(TextEngineCore.ViewportValidationError.nonPositiveWrapWidth)")
   Executed 1 test, with 4 failures (0 unexpected)
   ```

Reverted; `git diff` on the mutated file confirmed empty. Post-revert re-run:
`PASS post-revert (row) -> Executed 12 tests, with 0 failures (0 unexpected)`,
`PASS post-revert (compute) -> Executed 11 tests, with 0 failures (0 unexpected)`.

### Drill 7 — a per-`rowInLine` cost term (post-review fold-in; `WrapPositionQuery.swift`)

Not one of AC12's six. This is the falsifiability evidence for the coverage fold-in
recorded in section 1.1, run when the gap was found in review.

**The gap.** `WrapRowQueryCountTests` built every fixture through one helper,
`counting()`, at `wrapWidth: .infinity` with a single 8.0 advance per line — so every
line packs to exactly one row and `totalRows == lineCount == 1024`. At one row per
line there is nothing for a per-row term to be proportional to, so that counter is
blind to one **by construction**, not by oversight. The `totalRows >> lineCount`
regime was pinned by nothing in the suite — only by the observational
`--wrap-row-query` benchmark's latency, which is not a gate and cannot fail a build.

**The fixture that closes it.** `countingMultiRow()`: the same 1024 lines, but eight
cells of advance 8.0 with a break opportunity before each, at `wrapWidth: 8.0` — one
cell per row, 8 rows per line, `totalRows = 8192`. `lineCount` is held fixed and only
the row axis is multiplied, which is the only arrangement in which the counter can
tell a per-line term from a per-row one. Measured probe counts (temporary
instrumentation, removed before commit):

```
PROBE infinity-clamp  y=-1.0       calls=13
PROBE infinity-clamp  y=16385.0    calls=14
PROBE multirow-inrange            calls=13   firstVisualRow=13  visualRowCount=0
PROBE multirow-clamp  y=-1.0       calls=13
PROBE multirow-clamp  y=131073.0   calls=14
```

The bound is unchanged and unwidened: `expectedMax = ceilLog2(1024) + 4 = 14`, keyed
to `lineCount`, **not** to `totalRows` (`ceilLog2(8192) + 4 = 17` would have handed a
regression three probes of slack). The eight-fold longer row axis costs zero extra
provider calls, so the new regime is bought for free. `visualRowCount = 0` is worth
recording too: `visualRowAt` never calls that hook at all — the counter sums both
provider calls precisely so a scan cannot hide in the one it would otherwise ignore.

**Mutation** — a cost term proportional to rows *within* the line, inserted after the
`rowInLine` subtraction:

```swift
let rowInLine = globalRow - layout.firstVisualRow(ofLine: logicalLine)
// DRILL 7 MUTATION — a cost term proportional to rows WITHIN the line.
var drill = 0
for _ in 0..<rowInLine { drill &+= layout.firstVisualRow(ofLine: logicalLine) }
_ = drill
```

**Observed** (`swift test --filter WrapRowQueryCountTests`):

```
Test Case '…testClampedQueriesStillSearchTheLayoutAxis]' passed (0.002 seconds).
Test Case '…testInRangeQueryIsLogarithmicOnTheLayoutAxis]' passed (0.001 seconds).
Test Case '…testProbeCountDoesNotGrowLinearlyWithTheDocument]' passed (0.001 seconds).
WrapRowQueryCountTests.swift:179: error: …testProbeCountIsIndependentOfRowsPerLine] :
  XCTAssertLessThanOrEqual failed: ("16") is greater than ("14")
WrapRowQueryCountTests.swift:190: error: …testProbeCountIsIndependentOfRowsPerLine] :
  XCTAssertLessThanOrEqual failed: ("21") is greater than ("14") - y=131073.0
Test Case '…testProbeCountIsIndependentOfRowsPerLine]' failed (0.121 seconds).
	 Executed 4 tests, with 2 failures (0 unexpected) in 0.125 (0.125) seconds
```

This is the drill's whole point, and both halves are required: **all three** tests on
the infinity fixture stayed **green** under the mutation, while the new test caught it
**twice** — at the in-range sample (`rowInLine == 3` → 13 + 3 = 16) and at the bottom
clamp (`rowInLine == 7` → 14 + 7 = 21). The gap is demonstrated, not argued.

Reverted with `git checkout -- Sources/TextEngineCore/WrapPositionQuery.swift`;
`git diff --stat -- Sources/` empty afterwards. Post-revert re-run:
`Executed 4 tests, with 0 failures (0 unexpected)`.

## 10. Hosted CI proof

Two halves, both now recorded from the real logs: **10.1** the PR-head run on the
code-complete branch, **10.2** the post-merge push run on `main`. AC13 is discharged.

Everything below is read at **step level**, not job-conclusion level: a green job can
hide a dead `continue-on-error` step (the Slice 16 trap). The step inventory was
pulled first, then the printed lines were extracted from the downloaded logs:

```bash
gh run view -R maldrakar/swift-text-engine 32594785647 --json jobs \
  --jq '.jobs[] | {name, conclusion, steps: [.steps[] | {n: .number, name, conclusion}]}'
gh run view -R maldrakar/swift-text-engine --job <job-id> --log > <job>.log
```

Every step of all three jobs was checked programmatically for a conclusion outside
`{success, skipped}` — none exists — rather than the three job conclusions being read
off the PR page.

### 10.1 PR-head run — RECORDED

PR [#126](https://github.com/maldrakar/swift-text-engine/pull/126), head
`2d7e8176d9941c111553047976779a12a4c4a3fd`, run
[`32594785647`](https://github.com/maldrakar/swift-text-engine/actions/runs/32594785647),
event `pull_request`, started `2026-08-22T19:48:06Z`, finished
`2026-08-22T19:54:08Z`, run conclusion `success`. All three required contexts green.

`2d7e817` is the **code-complete** head: the last commit that changes anything the
suite or the gates read (the drill-7 coverage fold-in of section 1.1), and the tree
every line below was measured against.

Two earlier runs on this branch were also green and are superseded rather than
retracted — this section names the newest code-complete head, not every run:

| run | head | what it tested | conclusion |
|---|---|---|---|
| [`31361526438`](https://github.com/maldrakar/swift-text-engine/actions/runs/31361526438) | `d17d709` | the implementation before review | `success` (396 tests) |
| [`32591420156`](https://github.com/maldrakar/swift-text-engine/actions/runs/32591420156) | `2333376` | + the first draft of this section | `success` (396 tests) |
| [`32594785647`](https://github.com/maldrakar/swift-text-engine/actions/runs/32594785647) | `2d7e817` | + the drill-7 fold-in — **recorded below** | `success` (397 tests) |

The regress is real and is cut deliberately: the commit that writes this section moves
the PR head (AGENTS.md's D-2 rule 3 — a record cannot assert its own HEAD), and because
the full `BASE...HEAD` diff is not docs-only, that push starts another full run rather
than a docs-only shortcut. So this section pins the newest run that tested the *code*;
the docs commit carrying it is proved by 10.2's post-merge push run, which is the
definitive one.

**Step inventory.** Every step of all three jobs reports `conclusion=success`. The
only `skipped` step in each job is `Complete docs-only PR`, and that is the correct
branch: the detector classified this PR as **not** docs-only in all three jobs, so the
heavy path ran rather than being skipped past.

```
mode=docs_only_pr result=not_docs_only docs_only_pr=false file_count=23 non_doc_count=17
```

No step was skipped other than the docs-only shortcut above, and no step in the
workflow can swallow a failure: `grep -n continue-on-error .github/workflows/swift-ci.yml`
returns nothing (exit 1). Step conclusions alone could not establish that — a
`continue-on-error` step that fails still leaves the job green — so it is checked
against the workflow source, not inferred from the run.

#### Host tests and benchmark gate (job `97083928846`)

`Run host tests` step, tail (the second line is the empty Swift Testing harness, not
a failure — see AGENTS.md):

```
Executed 397 tests, with 0 failures (0 unexpected) in 7.287 (7.287) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

397 tests, 0 failures — matching the local re-run in section 1.1 exactly, so nothing
landed on `main` in between that changed the suite size. The `+1` over the two earlier
runs is the drill-7 fold-in, and it is proved to have *run hosted* rather than merely
to have been committed:

```
Test Case 'WrapRowQueryCountTests.testProbeCountIsIndependentOfRowsPerLine' started at 2026-08-22 19:49:04.505
Test Case 'WrapRowQueryCountTests.testProbeCountIsIndependentOfRowsPerLine' passed (0.017 seconds)
```

That matters more than the count: the fold-in's fixture is built by running node 1's
packer at construction time, so "the test exists" and "the test passed on hosted
Linux x86_64 against a tree built by a different toolchain than the local one" are
different claims, and the second is the one recorded here.

Twelve gate steps ran, all blocking, none `continue-on-error`, printing **46**
`gate=pass` lines and **zero** `gate=fail`:

| gate step | scenarios |
|---|---|
| Run synthetic benchmark gate | 3 |
| Run variable-height benchmark gate | 3 |
| Run variable-height mutation benchmark gate | 3 |
| Run structural mutation benchmark gate | 3 |
| Run bulk structural mutation benchmark gate | 5 |
| Run line query benchmark gate | 5 |
| Run line geometry query benchmark gate | 5 |
| Run column query benchmark gate | 5 |
| Run column geometry query benchmark gate | 5 |
| Run point query benchmark gate | 4 |
| Run point geometry query benchmark gate | 4 |
| Run realistic provider benchmark gate | 1 |
| **total** | **46** |

(The stub this section replaces said "all twelve `gate=pass` lines". Twelve is the
number of gated *modes* and therefore of gate steps; the number of `gate=pass`
**lines** is 46, one per gated scenario — the same 46 that `GateFloorTests` pins.)

All 46, verbatim:

```
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1329 p99_ns=1402 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=15.8x headroom_p99=30.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1188.8x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=5624 p99_ns=5734 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=14.9x headroom_p99=29.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=290.7x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=18566 p99_ns=19027 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=15.1x headroom_p99=29.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=87.6x gate=pass checksum=18852477646272000
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=381 p99_ns=404 failures=0 budget_p95_ns=4100 budget_p99_ns=8200 headroom_p95=10.8x headroom_p99=20.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=4125.4x gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1351 p99_ns=1397 failures=0 budget_p95_ns=14000 budget_p99_ns=28000 headroom_p95=10.4x headroom_p99=20.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1193.0x gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4586 p99_ns=4696 failures=0 budget_p95_ns=46000 budget_p99_ns=92000 headroom_p95=10.0x headroom_p99=19.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=354.9x gate=pass checksum=3536425156727040
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=654 p99_ns=679 failures=0 budget_p95_ns=6600 budget_p99_ns=14000 headroom_p95=10.1x headroom_p99=20.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=2454.6x gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=2630 p99_ns=2687 failures=0 budget_p95_ns=24000 budget_p99_ns=48000 headroom_p95=9.1x headroom_p99=17.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=620.3x gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=8547 p99_ns=8750 failures=0 budget_p95_ns=82000 budget_p99_ns=170000 headroom_p95=9.6x headroom_p99=19.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=190.5x gate=pass checksum=3571078666132451
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1207 p99_ns=1231 failures=0 budget_p95_ns=16000 budget_p99_ns=32000 headroom_p95=13.3x headroom_p99=26.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1353.9x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5061 p99_ns=5212 failures=0 budget_p95_ns=71000 budget_p99_ns=150000 headroom_p95=14.0x headroom_p99=28.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=319.8x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=29573 p99_ns=30675 failures=0 budget_p95_ns=290000 budget_p99_ns=580000 headroom_p95=9.8x headroom_p99=18.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=54.3x gate=pass checksum=3379593298396981
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=3613 p99_ns=3654 failures=0 budget_p95_ns=51000 budget_p99_ns=110000 headroom_p95=14.1x headroom_p99=30.1x budget_absolute_p99_ns=16666666 headroom_absolute_p99=4561.2x gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=9199 p99_ns=9520 failures=0 budget_p95_ns=130000 budget_p99_ns=260000 headroom_p95=14.1x headroom_p99=27.3x budget_absolute_p99_ns=16666666 headroom_absolute_p99=1750.7x gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=50329 p99_ns=51834 failures=0 budget_p95_ns=450000 budget_p99_ns=900000 headroom_p95=8.9x headroom_p99=17.4x budget_absolute_p99_ns=16666666 headroom_absolute_p99=321.5x gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=84943 p99_ns=86076 failures=0 budget_p95_ns=1400000 budget_p99_ns=2800000 headroom_p95=16.5x headroom_p99=32.5x budget_absolute_p99_ns=16666666 headroom_absolute_p99=193.6x gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=339345 p99_ns=349643 failures=0 budget_p95_ns=3000000 budget_p99_ns=6000000 headroom_p95=8.8x headroom_p99=17.2x budget_absolute_p99_ns=16666666 headroom_absolute_p99=47.7x gate=pass checksum=82203678997143
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=14 p99_ns=18 failures=0 budget_p95_ns=190 budget_p99_ns=440 headroom_p95=13.6x headroom_p99=24.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=92592.6x gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=25 p99_ns=35 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=11.2x headroom_p99=16.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=47619.0x gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=25 p99_ns=37 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=12.8x headroom_p99=17.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=45045.0x gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=71 p99_ns=91 failures=0 budget_p95_ns=1700 budget_p99_ns=3400 headroom_p95=23.9x headroom_p99=37.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=18315.0x gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=96 p99_ns=120 failures=0 budget_p95_ns=2100 budget_p99_ns=4200 headroom_p95=21.9x headroom_p99=35.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=13888.9x gate=pass checksum=639841547520
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=17 p99_ns=21 failures=0 budget_p95_ns=250 budget_p99_ns=500 headroom_p95=14.7x headroom_p99=23.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=79365.0x gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=24 p99_ns=31 failures=0 budget_p95_ns=340 budget_p99_ns=680 headroom_p95=14.2x headroom_p99=21.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=53763.4x gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=27 p99_ns=43 failures=0 budget_p95_ns=380 budget_p99_ns=760 headroom_p95=14.1x headroom_p99=17.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=38759.7x gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=111 p99_ns=144 failures=0 budget_p95_ns=3000 budget_p99_ns=6000 headroom_p95=27.0x headroom_p99=41.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=11574.1x gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=183 p99_ns=224 failures=0 budget_p95_ns=3400 budget_p99_ns=6800 headroom_p95=18.6x headroom_p99=30.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=7440.5x gate=pass checksum=852321495040
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=14 p99_ns=15 failures=0 budget_p95_ns=200 budget_p99_ns=440 headroom_p95=14.3x headroom_p99=29.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=111111.1x gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=21 p99_ns=26 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=13.3x headroom_p99=21.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=64102.5x gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=24 p99_ns=30 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=13.3x headroom_p99=21.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=55555.5x gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=36 p99_ns=55 failures=0 budget_p95_ns=500 budget_p99_ns=1000 headroom_p95=13.9x headroom_p99=18.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=30303.0x gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=41 p99_ns=60 failures=0 budget_p95_ns=600 budget_p99_ns=1200 headroom_p95=14.6x headroom_p99=20.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=27777.8x gate=pass checksum=639841560320
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=18 p99_ns=23 failures=0 budget_p95_ns=260 budget_p99_ns=520 headroom_p95=14.4x headroom_p99=22.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=72463.7x gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=24 p99_ns=34 failures=0 budget_p95_ns=350 budget_p99_ns=700 headroom_p95=14.6x headroom_p99=20.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=49019.6x gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=30 p99_ns=44 failures=0 budget_p95_ns=390 budget_p99_ns=780 headroom_p95=13.0x headroom_p99=17.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=37878.8x gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=45 p99_ns=64 failures=0 budget_p95_ns=820 budget_p99_ns=1700 headroom_p95=18.2x headroom_p99=26.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=26041.7x gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=51 p99_ns=67 failures=0 budget_p95_ns=690 budget_p99_ns=1400 headroom_p95=13.5x headroom_p99=20.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=24875.6x gate=pass checksum=839521520640
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=32 p99_ns=52 failures=0 budget_p95_ns=760 budget_p99_ns=1600 headroom_p95=23.8x headroom_p99=30.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=32051.3x gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=35 p99_ns=56 failures=0 budget_p95_ns=680 budget_p99_ns=1400 headroom_p95=19.4x headroom_p99=25.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=29761.9x gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=46 p99_ns=74 failures=0 budget_p95_ns=920 budget_p99_ns=1900 headroom_p95=20.0x headroom_p99=25.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=22522.5x gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=46 p99_ns=62 failures=0 budget_p95_ns=1100 budget_p99_ns=2200 headroom_p95=23.9x headroom_p99=35.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=26881.7x gate=pass checksum=640022228480
mode=point_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=46 p99_ns=67 failures=0 budget_p95_ns=980 budget_p99_ns=2000 headroom_p95=21.3x headroom_p99=29.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=24875.6x gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=50 p99_ns=72 failures=0 budget_p95_ns=990 budget_p99_ns=2000 headroom_p95=19.8x headroom_p99=27.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=23148.1x gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=84 p99_ns=97 failures=0 budget_p95_ns=1200 budget_p99_ns=2400 headroom_p95=14.3x headroom_p99=24.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=17182.1x gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=82 p99_ns=98 failures=0 budget_p95_ns=1300 budget_p99_ns=2600 headroom_p95=15.9x headroom_p99=26.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=17006.8x gate=pass checksum=5915921755926273280
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=6671 p99_ns=7269 failures=0 budget_p95_ns=98000 budget_p99_ns=200000 headroom_p95=14.7x headroom_p99=27.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=229.3x gate=pass checksum=756321289736960
```

Every one is in band on both statistics and under its class ceiling: 41 scenarios
print `budget_absolute_p99_ns=1666666` (the eleven `.scrollFrame` modes) and 5 print
`16666666` (`bulk_structural_mutation`, the only `.discreteAction` one) — the
distinction slice 52 introduced, visible here on hosted evidence.

Two further facts fall out of having a second green run on this branch, and both are
checked rather than assumed. Against run `31361526438` (head `d17d709`), every
`budget_p95_ns`/`budget_p99_ns` pair and **all 46 `checksum=` values are
byte-identical**; only the measured latencies move (e.g. `pipeline|1k` p95 1898 →
1329 ns). So the fold-in changed no budget and perturbed no measured work — the
checksums are the same numbers folded over the same operations — and the run-to-run
latency spread on this runner class is visible in the record instead of being
asserted.

The two non-gate diagnostic steps also ran green: `--memory-shape` printed 5
`invariant=pass` lines and `--memory-observation` 3 `observation=pass` lines.

#### iOS cross-target compile (job `97083928817`)

Both packages, both destinations, all blocking:

```
target=ios_device package=core result=pass reason=none blocking=true
target=ios_simulator package=core result=pass reason=none blocking=true
target=ios_device package=providers result=pass reason=none blocking=true
target=ios_simulator package=providers result=pass reason=none blocking=true
```

The WASM kinds print `result=skipped reason=not_requested blocking=false` in this job
— correct, it runs `--targets ios`; the WASM kinds are proved in their own job below.
Toolchain on this job: Swift 6.3.3 (the `macos-latest` default), against 6.2.1 in the
two container jobs.

#### WASM cross-target compile (job `97083928719`)

All four `result=pass … blocking=true` lines — two kinds x two packages:

```
target=wasm package=core result=pass reason=none blocking=true
target=wasm_embedded package=core result=pass reason=none blocking=true
target=wasm package=providers result=pass reason=none blocking=true
target=wasm_embedded package=providers result=pass reason=none blocking=true
```

SDK provisioning succeeded on the first attempt, and both kinds resolved against the
pinned 6.2.1 bundle:

```
sdk_install_seconds=5 attempts=1
wasm_sdk_id target=wasm package=core id=swift-6.2.1-RELEASE_wasm
wasm_sdk_id target=wasm_embedded package=core id=swift-6.2.1-RELEASE_wasm-embedded
wasm_sdk_id target=wasm package=providers id=swift-6.2.1-RELEASE_wasm
wasm_sdk_id target=wasm_embedded package=providers id=swift-6.2.1-RELEASE_wasm-embedded
```

#### AC9 / AC10 — the harvester-inertness barriers, checked on hosted evidence

The local sweep can only show that `--wrap-row-query` is absent from
`swift-ci.yml`; whether a hosted run emits anything harvestable is a property of the
run. Measured over all three job logs of this run:

| barrier | check | result |
|---|---|---|
| absent from CI | `grep -c wrap_row_query` over all three job logs | 0, 0, 0 |
| (same, for node 2's mode) | `grep -c wrap_compute` | 0 |
| prefixed latency tokens | `grep -c 'query_p95_ns='` | 0 |
| harvestable rows | `grep -o ' p95_ns=' \| wc -l` | 46 — exactly the gated scenarios, no more |

So a harvest of this run would ingest 46 rows and not one wrap row: the mode is inert
to the calibration chain by absence, and its token shape is never even exercised
hosted. All four rows measure identically on run `31361526438` as well, so this is a
property of the branch and not of one run's scheduling.

Corroborating D-18 in passing: `grep -o 'checksum=' | wc -l` over this job log yields
**54**, i.e. 46 + 5 `memory_shape` + 3 `memory_observation` — the exact arithmetic
D-18 records for why a literal `extract_checksums` count is 54 and not 46.

### 10.2 Post-merge push run — RECORDED

Merge commit
[`c2e6b37202a9fb005f835491e5735b78c7ef0b51`](https://github.com/maldrakar/swift-text-engine/commit/c2e6b37202a9fb005f835491e5735b78c7ef0b51)
(PR #126 merged into `main`), run
[`32595528239`](https://github.com/maldrakar/swift-text-engine/actions/runs/32595528239),
event `push`, started `2026-08-22T20:02:56Z`, finished `2026-08-22T20:08:56Z`, run
conclusion `success`.

This is the section that matters: 10.1 proves the branch was green, this one proves
the **merged tree** is. They are not the same claim — the merge commit is a tree no
PR-head run ever built, since `main` can move under a branch between the two.

**Step inventory.** All three jobs `success`, and no step in any of them reports a
conclusion outside `{success, skipped}` (checked programmatically, not read off the
run page): host 24 steps, iOS 8, WASM 10. The only `skipped` step in each job is
`Complete docs-only PR`, and on a `push` event it skips for a different reason than it
did on the PR — the detector short-circuits before the diff logic:

```
mode=docs_only_pr event=push result=not_pull_request docs_only_pr=false
```

`result=not_pull_request` rather than `not_docs_only`: on a push there is no PR base
to diff against, so the docs-only shortcut is unavailable by construction and the
heavy path always runs. That is the fail-closed branch behaving as designed, not a
degraded check.

#### Host tests and benchmark gate (job `97085700212`)

```
Executed 397 tests, with 0 failures (0 unexpected) in 8.275 (8.275) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

397 tests, 0 failures on the merged tree — the same count as 10.1 and as the local
re-run in section 1.1. The drill-7 fold-in is again shown running rather than merely
being present:

```
Test Case 'WrapRowQueryCountTests.testProbeCountIsIndependentOfRowsPerLine' started at 2026-08-22 20:03:57.115
Test Case 'WrapRowQueryCountTests.testProbeCountIsIndependentOfRowsPerLine' passed (0.023 seconds)
```

Twelve gate steps, **46** `gate=pass` lines, **zero** `gate=fail`, in the same
per-step distribution as 10.1 (3/3/3/3/5/5/5/5/5/4/4/1). All 46, verbatim:

```
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=2496 p99_ns=2710 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=8.4x headroom_p99=15.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=615.0x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=10498 p99_ns=10894 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=8.0x headroom_p99=15.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=153.0x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=34000 p99_ns=35144 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=8.2x headroom_p99=15.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=47.4x gate=pass checksum=18852477646272000
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=493 p99_ns=521 failures=0 budget_p95_ns=4100 budget_p99_ns=8200 headroom_p95=8.3x headroom_p99=15.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=3199.0x gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1743 p99_ns=1826 failures=0 budget_p95_ns=14000 budget_p99_ns=28000 headroom_p95=8.0x headroom_p99=15.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=912.7x gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=5775 p99_ns=5963 failures=0 budget_p95_ns=46000 budget_p99_ns=92000 headroom_p95=8.0x headroom_p99=15.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=279.5x gate=pass checksum=3536425156727040
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=809 p99_ns=961 failures=0 budget_p95_ns=6600 budget_p99_ns=14000 headroom_p95=8.2x headroom_p99=14.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1734.3x gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=2829 p99_ns=2904 failures=0 budget_p95_ns=24000 budget_p99_ns=48000 headroom_p95=8.5x headroom_p99=16.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=573.9x gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=10204 p99_ns=10626 failures=0 budget_p95_ns=82000 budget_p99_ns=170000 headroom_p95=8.0x headroom_p99=16.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=156.8x gate=pass checksum=3571078666132451
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1986 p99_ns=2175 failures=0 budget_p95_ns=16000 budget_p99_ns=32000 headroom_p95=8.1x headroom_p99=14.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=766.3x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=8931 p99_ns=9285 failures=0 budget_p95_ns=71000 budget_p99_ns=150000 headroom_p95=7.9x headroom_p99=16.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=179.5x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=35995 p99_ns=36596 failures=0 budget_p95_ns=290000 budget_p99_ns=580000 headroom_p95=8.1x headroom_p99=15.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=45.5x gate=pass checksum=3379593298396981
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=6134 p99_ns=7075 failures=0 budget_p95_ns=51000 budget_p99_ns=110000 headroom_p95=8.3x headroom_p99=15.5x budget_absolute_p99_ns=16666666 headroom_absolute_p99=2355.7x gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=16761 p99_ns=17529 failures=0 budget_p95_ns=130000 budget_p99_ns=260000 headroom_p95=7.8x headroom_p99=14.8x budget_absolute_p99_ns=16666666 headroom_absolute_p99=950.8x gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=57914 p99_ns=59068 failures=0 budget_p95_ns=450000 budget_p99_ns=900000 headroom_p95=7.8x headroom_p99=15.2x budget_absolute_p99_ns=16666666 headroom_absolute_p99=282.2x gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=179867 p99_ns=190269 failures=0 budget_p95_ns=1400000 budget_p99_ns=2800000 headroom_p95=7.8x headroom_p99=14.7x budget_absolute_p99_ns=16666666 headroom_absolute_p99=87.6x gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=430191 p99_ns=441962 failures=0 budget_p95_ns=3000000 budget_p99_ns=6000000 headroom_p95=7.0x headroom_p99=13.6x budget_absolute_p99_ns=16666666 headroom_absolute_p99=37.7x gate=pass checksum=82203678997143
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=24 p99_ns=52 failures=0 budget_p95_ns=190 budget_p99_ns=440 headroom_p95=7.9x headroom_p99=8.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=32051.3x gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=34 p99_ns=65 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=8.2x headroom_p99=8.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=25641.0x gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=39 p99_ns=70 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=8.2x headroom_p99=9.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=23809.5x gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=216 p99_ns=252 failures=0 budget_p95_ns=1700 budget_p99_ns=3400 headroom_p95=7.9x headroom_p99=13.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=6613.8x gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=259 p99_ns=300 failures=0 budget_p95_ns=2100 budget_p99_ns=4200 headroom_p95=8.1x headroom_p99=14.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=5555.6x gate=pass checksum=639841547520
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=32 p99_ns=73 failures=0 budget_p95_ns=250 budget_p99_ns=500 headroom_p95=7.8x headroom_p99=6.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=22831.0x gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=42 p99_ns=72 failures=0 budget_p95_ns=340 budget_p99_ns=680 headroom_p95=8.1x headroom_p99=9.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=23148.1x gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=71 p99_ns=90 failures=0 budget_p95_ns=380 budget_p99_ns=760 headroom_p95=5.4x headroom_p99=8.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=18518.5x gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=376 p99_ns=435 failures=0 budget_p95_ns=3000 budget_p99_ns=6000 headroom_p95=8.0x headroom_p99=13.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=3831.4x gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=428 p99_ns=469 failures=0 budget_p95_ns=3400 budget_p99_ns=6800 headroom_p95=7.9x headroom_p99=14.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=3553.7x gate=pass checksum=852321495040
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=24 p99_ns=54 failures=0 budget_p95_ns=200 budget_p99_ns=440 headroom_p95=8.3x headroom_p99=8.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=30864.2x gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=35 p99_ns=65 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=8.0x headroom_p99=8.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=25641.0x gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=40 p99_ns=71 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=8.0x headroom_p99=9.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=23474.2x gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=58 p99_ns=96 failures=0 budget_p95_ns=500 budget_p99_ns=1000 headroom_p95=8.6x headroom_p99=10.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=17361.1x gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=91 p99_ns=132 failures=0 budget_p95_ns=600 budget_p99_ns=1200 headroom_p95=6.6x headroom_p99=9.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=12626.3x gate=pass checksum=639841560320
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=32 p99_ns=64 failures=0 budget_p95_ns=260 budget_p99_ns=520 headroom_p95=8.1x headroom_p99=8.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=26041.7x gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=43 p99_ns=74 failures=0 budget_p95_ns=350 budget_p99_ns=700 headroom_p95=8.1x headroom_p99=9.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=22522.5x gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=48 p99_ns=79 failures=0 budget_p95_ns=390 budget_p99_ns=780 headroom_p95=8.1x headroom_p99=9.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=21097.0x gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=69 p99_ns=107 failures=0 budget_p95_ns=820 budget_p99_ns=1700 headroom_p95=11.9x headroom_p99=15.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=15576.3x gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=156 p99_ns=189 failures=0 budget_p95_ns=690 budget_p99_ns=1400 headroom_p95=4.4x headroom_p99=7.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=8818.3x gate=pass checksum=839521520640
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=87 p99_ns=128 failures=0 budget_p95_ns=760 budget_p99_ns=1600 headroom_p95=8.7x headroom_p99=12.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=13020.8x gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=95 p99_ns=125 failures=0 budget_p95_ns=680 budget_p99_ns=1400 headroom_p95=7.2x headroom_p99=11.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=13333.3x gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=124 p99_ns=155 failures=0 budget_p95_ns=920 budget_p99_ns=1900 headroom_p95=7.4x headroom_p99=12.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=10752.7x gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=127 p99_ns=154 failures=0 budget_p95_ns=1100 budget_p99_ns=2200 headroom_p95=8.7x headroom_p99=14.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=10822.5x gate=pass checksum=640022228480
mode=point_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=119 p99_ns=155 failures=0 budget_p95_ns=980 budget_p99_ns=2000 headroom_p95=8.2x headroom_p99=12.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=10752.7x gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=111 p99_ns=138 failures=0 budget_p95_ns=990 budget_p99_ns=2000 headroom_p95=8.9x headroom_p99=14.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=12077.3x gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=130 p99_ns=156 failures=0 budget_p95_ns=1200 budget_p99_ns=2400 headroom_p95=9.2x headroom_p99=15.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=10683.8x gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=144 p99_ns=171 failures=0 budget_p95_ns=1300 budget_p99_ns=2600 headroom_p95=9.0x headroom_p99=15.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=9746.6x gate=pass checksum=5915921755926273280
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=12131 p99_ns=12364 failures=0 budget_p95_ns=98000 budget_p99_ns=200000 headroom_p95=8.1x headroom_p99=16.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=134.8x gate=pass checksum=756321289736960
```

Against 10.1's run (`32594785647`), every `budget_p95_ns`/`budget_p99_ns` pair and all
46 `checksum=` values are **byte-identical** — the merge introduced no budget change
and perturbed no measured work; only latencies move, which is what a shared runner
class does. The two non-gate diagnostics also ran green: 5 `invariant=pass`, 3
`observation=pass`.

#### iOS cross-target compile (job `97085700316`)

```
target=ios_device package=core result=pass reason=none blocking=true
target=ios_simulator package=core result=pass reason=none blocking=true
target=ios_device package=providers result=pass reason=none blocking=true
target=ios_simulator package=providers result=pass reason=none blocking=true
```

#### WASM cross-target compile (job `97085700366`)

```
target=wasm package=core result=pass reason=none blocking=true
target=wasm_embedded package=core result=pass reason=none blocking=true
target=wasm package=providers result=pass reason=none blocking=true
target=wasm_embedded package=providers result=pass reason=none blocking=true
```

SDK provisioning again succeeded on the first attempt, both kinds resolving against
the pinned 6.2.1 bundle:

```
sdk_install_seconds=5 attempts=1
wasm_sdk_id target=wasm package=core id=swift-6.2.1-RELEASE_wasm
wasm_sdk_id target=wasm_embedded package=core id=swift-6.2.1-RELEASE_wasm-embedded
wasm_sdk_id target=wasm package=providers id=swift-6.2.1-RELEASE_wasm
wasm_sdk_id target=wasm_embedded package=providers id=swift-6.2.1-RELEASE_wasm-embedded
```

#### Harvester-inertness barriers on the merged tree

The same four checks as 10.1, re-measured over this run's three job logs:
`grep -c wrap_row_query` → 0, 0, 0; `grep -c wrap_compute` → 0;
`grep -c 'query_p95_ns='` → 0; `grep -o ' p95_ns=' | wc -l` → **46**, exactly the
gated scenarios. `grep -o 'checksum=' | wc -l` → **54** (46 + 5 `memory_shape` + 3
`memory_observation`), D-18's arithmetic again. So the mode ships inert: a harvest of
`main` after this merge ingests 46 rows and not one wrap row.

**AC13 is discharged**: hosted proof at step level on both the PR-head and the
post-merge runs, including the iOS job's target compiles and the WASM job's four
`result=pass … blocking=true` lines.

Run IDs, timestamps, and printed lines in this section are extracted from the real
hosted logs, never transcribed by hand and never fabricated.

---

## Summary

| Check | Result |
|---|---|
| `swift test` (full suite) | green, 397 tests, 0 failures (396 before the drill-7 fold-in; baseline before this slice: 362) |
| `swift build -c release` | green |
| Foundation-free scan | PASS (empty) |
| 12 blocking gates | 12/12 `gate=pass`, no scenario failures, all headroom in band |
| `--wrap-row-query` | 4/4 scenarios, non-zero checksums, both barriers hold |
| `--wrap-compute` | smoke run only, not extraction evidence (three reasons recorded) |
| `--memory-shape` | 5/5 `invariant=pass` |
| `cross-target-compile.sh --self-test` | `self_test=pass`, exit 0 — shell logic only, not portability evidence |
| 6 falsifiability drills + Task 2's refactor-safety check + drill 7 | all reproduced their predicted red, all cleanly reverted |
| Post-review coverage fold-in | `testProbeCountIsIndependentOfRowsPerLine` — `totalRows >> lineCount` regime now pinned; suite 396 → 397, no `Sources/` change |
| Hosted CI proof — PR-head (section 10.1) | run `32594785647` green at step level: 397/0, 46 `gate=pass` / 0 `gate=fail` across 12 gate steps, 4 iOS + 4 WASM `blocking=true`; budgets and all 46 checksums byte-identical to the earlier green run |
| Hosted CI proof — post-merge (section 10.2) | run `32595528239` on merge commit `c2e6b37` green at step level: 397/0, 46 `gate=pass` / 0 `gate=fail`, 4 iOS + 4 WASM `blocking=true`; budgets and all 46 checksums byte-identical to 10.1 |

No gate moved. No test regressed. No budget, corpus, `Package.swift`, or
`.github/**` file changed anywhere in this slice. Exactly one `.swift` file changed
after the code was complete — `Tests/TextEngineCoreTests/WrapRowQueryCountTests.swift`,
the drill-7 coverage fold-in — and it adds a test without touching `Sources/`.
