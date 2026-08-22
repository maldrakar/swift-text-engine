# Slice 53 — wrap y→row query (`visualRowAt`) — verification record

This slice shipped `ViewportVirtualizer.visualRowAt(y:layout:)` — the wrap-aware
`lineAt` analog over the visual-row axis (wrap node 3) — plus its four test suites
(mapping, validation/parity, infinite-width equivalence, round-trip + probe-count
bound) and the observational, non-gateable `--wrap-row-query` benchmark mode. It
touches no gated code path: no gate budget, no gate scenario, and no CI workflow file
changed. Sections 1-9 record the local sweep this task ran directly. Section 10 records the
hosted CI evidence: its PR-head half (10.1) is filled in from the real logs of run
`31361526438`; its post-merge half (10.2) stays pending until the branch merges.

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

## 9. The six falsifiability drills, plus Task 2 Step 4's refactor-safety check

Task 2 Step 4's check is recorded first and separately — it is **not** one of the six
numbered drills; it is a refactor-safety mutation drill on the shared ladder
extraction itself, run before any of `visualRowAt`'s own tests existed.

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

## 10. Hosted CI proof

Two halves, and only one of them can exist before merge. **10.1 (PR-head) is
recorded below, from the real logs.** **10.2 (post-merge push) remains PENDING** — it
is the one open item in AC13.

Everything below is read at **step level**, not job-conclusion level: a green job can
hide a dead `continue-on-error` step (the Slice 16 trap). The step inventory was
pulled first, then the printed lines were extracted from the downloaded logs:

```bash
gh run view 31361526438 --json jobs \
  --jq '.jobs[] | {name, conclusion, steps: [.steps[] | {n: .number, name, conclusion}]}'
gh run view -R maldrakar/swift-text-engine --job <job-id> --log > <job>.log
```

### 10.1 PR-head run — RECORDED

PR [#126](https://github.com/maldrakar/swift-text-engine/pull/126), head
`d17d7092f190a519f2e5440b6cb9189a64b1ad3b`, run
[`31361526438`](https://github.com/maldrakar/swift-text-engine/actions/runs/31361526438),
event `pull_request`, started `2026-08-10T06:19:19Z`, finished
`2026-08-10T06:24:14Z`, run conclusion `success`. All three required contexts green.

`d17d709` is the **code-complete** head: the last commit of the implementation, and
the tree every line below was measured against. The commit that writes this section
necessarily moves the PR head (AGENTS.md's D-2 rule 3 — a record cannot assert its own
HEAD), and because the full `BASE...HEAD` diff is not docs-only, that push starts
another full run rather than a docs-only shortcut. Recording *that* run would move the
head again, so the regress is cut here: this section pins the run that tested the
code, and the definitive proof of the merged tree is 10.2's post-merge push run.

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

#### Host tests and benchmark gate (job `93371182818`)

`Run host tests` step, tail (the second line is the empty Swift Testing harness, not
a failure — see AGENTS.md):

```
Executed 396 tests, with 0 failures (0 unexpected) in 6.563 (6.563) seconds
Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

396 tests, 0 failures — the same count as the local sweep in section 1, so nothing
landed on `main` between the local run and the hosted one that changed the suite size.

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
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1898 p99_ns=1969 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=11.1x headroom_p99=21.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=846.5x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=7952 p99_ns=8075 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=10.6x headroom_p99=21.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=206.4x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=25500 p99_ns=26195 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=11.0x headroom_p99=21.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=63.6x gate=pass checksum=18852477646272000
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=547 p99_ns=583 failures=0 budget_p95_ns=4100 budget_p99_ns=8200 headroom_p95=7.5x headroom_p99=14.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=2858.8x gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=2135 p99_ns=2179 failures=0 budget_p95_ns=14000 budget_p99_ns=28000 headroom_p95=6.6x headroom_p99=12.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=764.9x gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=6991 p99_ns=7086 failures=0 budget_p95_ns=46000 budget_p99_ns=92000 headroom_p95=6.6x headroom_p99=13.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=235.2x gate=pass checksum=3536425156727040
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1019 p99_ns=1090 failures=0 budget_p95_ns=6600 budget_p99_ns=14000 headroom_p95=6.5x headroom_p99=12.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1529.1x gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=3842 p99_ns=4180 failures=0 budget_p95_ns=24000 budget_p99_ns=48000 headroom_p95=6.2x headroom_p99=11.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=398.7x gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=12722 p99_ns=13317 failures=0 budget_p95_ns=82000 budget_p99_ns=170000 headroom_p95=6.4x headroom_p99=12.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=125.2x gate=pass checksum=3571078666132451
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=2021 p99_ns=2098 failures=0 budget_p95_ns=16000 budget_p99_ns=32000 headroom_p95=7.9x headroom_p99=15.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=794.4x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=8653 p99_ns=8917 failures=0 budget_p95_ns=71000 budget_p99_ns=150000 headroom_p95=8.2x headroom_p99=16.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=186.9x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=30232 p99_ns=31320 failures=0 budget_p95_ns=290000 budget_p99_ns=580000 headroom_p95=9.6x headroom_p99=18.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=53.2x gate=pass checksum=3379593298396981
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=6299 p99_ns=6442 failures=0 budget_p95_ns=51000 budget_p99_ns=110000 headroom_p95=8.1x headroom_p99=17.1x budget_absolute_p99_ns=16666666 headroom_absolute_p99=2587.2x gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=15554 p99_ns=15749 failures=0 budget_p95_ns=130000 budget_p99_ns=260000 headroom_p95=8.4x headroom_p99=16.5x budget_absolute_p99_ns=16666666 headroom_absolute_p99=1058.3x gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=39962 p99_ns=42143 failures=0 budget_p95_ns=450000 budget_p99_ns=900000 headroom_p95=11.3x headroom_p99=21.4x budget_absolute_p99_ns=16666666 headroom_absolute_p99=395.5x gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=158980 p99_ns=175823 failures=0 budget_p95_ns=1400000 budget_p99_ns=2800000 headroom_p95=8.8x headroom_p99=15.9x budget_absolute_p99_ns=16666666 headroom_absolute_p99=94.8x gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=189314 p99_ns=197417 failures=0 budget_p95_ns=3000000 budget_p99_ns=6000000 headroom_p95=15.8x headroom_p99=30.4x budget_absolute_p99_ns=16666666 headroom_absolute_p99=84.4x gate=pass checksum=82203678997143
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=44 p99_ns=56 failures=0 budget_p95_ns=190 budget_p99_ns=440 headroom_p95=4.3x headroom_p99=7.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=29761.9x gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=64 p99_ns=79 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=4.4x headroom_p99=7.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=21097.0x gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=64 p99_ns=78 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=5.0x headroom_p99=8.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=21367.5x gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=141 p99_ns=150 failures=0 budget_p95_ns=1700 budget_p99_ns=3400 headroom_p95=12.1x headroom_p99=22.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=11111.1x gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=174 p99_ns=188 failures=0 budget_p95_ns=2100 budget_p99_ns=4200 headroom_p95=12.1x headroom_p99=22.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=8865.2x gate=pass checksum=639841547520
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=54 p99_ns=73 failures=0 budget_p95_ns=250 budget_p99_ns=500 headroom_p95=4.6x headroom_p99=6.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=22831.0x gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=80 p99_ns=94 failures=0 budget_p95_ns=340 budget_p99_ns=680 headroom_p95=4.3x headroom_p99=7.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=17730.5x gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=105 p99_ns=115 failures=0 budget_p95_ns=380 budget_p99_ns=760 headroom_p95=3.6x headroom_p99=6.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=14492.7x gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=324 p99_ns=348 failures=0 budget_p95_ns=3000 budget_p99_ns=6000 headroom_p95=9.3x headroom_p99=17.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=4789.3x gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=382 p99_ns=405 failures=0 budget_p95_ns=3400 budget_p99_ns=6800 headroom_p95=8.9x headroom_p99=16.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=4115.2x gate=pass checksum=852321495040
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=45 p99_ns=59 failures=0 budget_p95_ns=200 budget_p99_ns=440 headroom_p95=4.4x headroom_p99=7.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=28248.6x gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=66 p99_ns=86 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=4.2x headroom_p99=6.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=19379.8x gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=64 p99_ns=79 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=5.0x headroom_p99=8.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=21097.0x gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=109 p99_ns=126 failures=0 budget_p95_ns=500 budget_p99_ns=1000 headroom_p95=4.6x headroom_p99=7.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=13227.5x gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=114 p99_ns=134 failures=0 budget_p95_ns=600 budget_p99_ns=1200 headroom_p95=5.3x headroom_p99=9.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=12437.8x gate=pass checksum=639841560320
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=59 p99_ns=76 failures=0 budget_p95_ns=260 budget_p99_ns=520 headroom_p95=4.4x headroom_p99=6.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=21929.8x gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=80 p99_ns=98 failures=0 budget_p95_ns=350 budget_p99_ns=700 headroom_p95=4.4x headroom_p99=7.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=17006.8x gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=78 p99_ns=90 failures=0 budget_p95_ns=390 budget_p99_ns=780 headroom_p95=5.0x headroom_p99=8.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=18518.5x gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=111 p99_ns=123 failures=0 budget_p95_ns=820 budget_p99_ns=1700 headroom_p95=7.4x headroom_p99=13.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=13550.1x gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=125 p99_ns=145 failures=0 budget_p95_ns=690 budget_p99_ns=1400 headroom_p95=5.5x headroom_p99=9.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=11494.2x gate=pass checksum=839521520640
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=142 p99_ns=179 failures=0 budget_p95_ns=760 budget_p99_ns=1600 headroom_p95=5.4x headroom_p99=8.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=9311.0x gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=112 p99_ns=128 failures=0 budget_p95_ns=680 budget_p99_ns=1400 headroom_p95=6.1x headroom_p99=10.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=13020.8x gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=135 p99_ns=153 failures=0 budget_p95_ns=920 budget_p99_ns=1900 headroom_p95=6.8x headroom_p99=12.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=10893.2x gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=152 p99_ns=165 failures=0 budget_p95_ns=1100 budget_p99_ns=2200 headroom_p95=7.2x headroom_p99=13.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=10101.0x gate=pass checksum=640022228480
mode=point_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=117 p99_ns=133 failures=0 budget_p95_ns=980 budget_p99_ns=2000 headroom_p95=8.4x headroom_p99=15.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=12531.3x gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=110 p99_ns=123 failures=0 budget_p95_ns=990 budget_p99_ns=2000 headroom_p95=9.0x headroom_p99=16.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=13550.1x gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=164 p99_ns=173 failures=0 budget_p95_ns=1200 budget_p99_ns=2400 headroom_p95=7.3x headroom_p99=13.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=9633.9x gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=184 p99_ns=203 failures=0 budget_p95_ns=1300 budget_p99_ns=2600 headroom_p95=7.1x headroom_p99=12.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=8210.2x gate=pass checksum=5915921755926273280
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=9553 p99_ns=9683 failures=0 budget_p95_ns=98000 budget_p99_ns=200000 headroom_p95=10.3x headroom_p99=20.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=172.1x gate=pass checksum=756321289736960
```

Every one is in band on both statistics and under its class ceiling
(`budget_absolute_p99_ns=1666666` for the eleven `.scrollFrame` modes,
`16666666` for `bulk_structural_mutation`, the only `.discreteAction` one — the
distinction slice 52 introduced, visible here on hosted evidence).

The two non-gate diagnostic steps also ran green: `--memory-shape` printed 5
`invariant=pass` lines and `--memory-observation` 3 `observation=pass` lines.

#### iOS cross-target compile (job `93371182803`)

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

#### WASM cross-target compile (job `93371182811`)

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
hosted.

Corroborating D-18 in passing: `grep -o 'checksum=' | wc -l` over this job log yields
**54**, i.e. 46 + 5 `memory_shape` + 3 `memory_observation` — the exact arithmetic
D-18 records for why a literal `extract_checksums` count is 54 and not 46.

### 10.2 Post-merge push run — PENDING

Cannot exist yet: the branch is not merged. Once PR #126 merges, the post-merge
`push` run on `main` must be recorded here to the same depth as 10.1 — step
inventory, the `swift test` tail, the 46 `gate=pass` lines, the iOS job's four
`blocking=true` lines and the WASM job's four. Per the repo convention, proof that the
**merged** code is green is anchored in that push run, not in this PR-head run, and it
is normally recorded in a follow-up docs-only PR.

Run IDs, timestamps, and printed lines in this section are extracted from the real
hosted logs, never transcribed by hand and never fabricated.

---

## Summary

| Check | Result |
|---|---|
| `swift test` (full suite) | green, 396 tests, 0 failures (baseline before this slice: 362) |
| `swift build -c release` | green |
| Foundation-free scan | PASS (empty) |
| 12 blocking gates | 12/12 `gate=pass`, no scenario failures, all headroom in band |
| `--wrap-row-query` | 4/4 scenarios, non-zero checksums, both barriers hold |
| `--wrap-compute` | smoke run only, not extraction evidence (three reasons recorded) |
| `--memory-shape` | 5/5 `invariant=pass` |
| `cross-target-compile.sh --self-test` | `self_test=pass`, exit 0 — shell logic only, not portability evidence |
| 6 falsifiability drills + Task 2's refactor-safety check | all reproduced their predicted red, all cleanly reverted |
| Hosted CI proof — PR-head (section 10.1) | green at step level: 396/0, 46 `gate=pass` / 0 `gate=fail` across 12 gate steps, 4 iOS + 4 WASM `blocking=true` |
| Hosted CI proof — post-merge (section 10.2) | PENDING — branch not merged yet |

No gate moved. No test regressed. No `.swift` file, `Package.swift`, or
`.github/**` file changed in this task — this is a documentation-only commit.
