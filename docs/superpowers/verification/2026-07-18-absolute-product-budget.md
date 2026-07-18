# Slice 43 verification — absolute product budget

Branch `slice-43-absolute-product-budget`, HEAD `987568d` (`docs: document the
absolute product ceiling in AGENTS.md`), on top of `main` at `62500fc` (merge
of PR #95, Slice 42 post-slice review). Commits on this branch (Tasks 1-6, all
already landed before this task): `a77747e` (feat: add `GateLimits` frame +
absolute p99 ceiling constants), `4dc9c87` (feat: fail gate on frame-hot-path
absolute p99 ceiling breach), `7d1c9dd` (feat: emit absolute-ceiling gate
tokens, exempt marker for bulk), `f6b710e` (test: pin every frame-hot-path
budget under the absolute ceiling), `987568d` (docs: document the absolute
product ceiling in AGENTS.md). This record is Task 7: local verification +
guard-is-live demonstration + 45-checksum byte-identity proof, captured
directly against the current tree.

This slice added a **fixed absolute product ceiling** (`GateLimits.absoluteP99Nanoseconds
= 1_666_666` ns, 10% of a 60 FPS frame budget) as a second, distinct failure
condition folded into the existing `--gate` machinery, applied to every
**frame-hot-path** gated scenario (`BenchmarkMode.isFrameHotPath`, false only
for `bulk_structural_mutation`, which is exempt and prints
`budget_absolute_p99_ns=exempt`). No engine or provider file changed — see
Section 4 below.

---

## 1. `swift test` — full suite, 310 tests, 0 failures

```
$ swift test 2>&1 | tail -5
	 Executed 310 tests, with 0 failures (0 unexpected) in 4.017 (4.036) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

310 = Slice 42's 300-test baseline + 10 new tests from this slice's Tasks 1-5
(`isFrameHotPath` pin, gate-precedence/non-masking tests, token-format tests,
and the `GateFloorTests` standing invariant that every frame-hot-path
regression p99 budget sits under the absolute ceiling). The trailing "0 tests
in 0 suites" line is the empty Swift Testing harness, not a failure, per
`AGENTS.md`'s package-layout note.

## 2. `swift build -c release`

```
$ swift build -c release 2>&1 | tail -3
Building for production...
[0/2] Write swift-version-58A378E29CF047B.txt
Build complete! (0.10s)
```

Clean release build, no warnings surfaced in the tail.

## 3. Foundation-free scan — empty

```
$ rg -n "Foundation" Sources/TextEngineCore ; echo "exit=$?"
exit=1
```

`rg` found no matches (exit code 1 = no matches, per ripgrep convention);
`Sources/TextEngineCore` remains Foundation-free.

## 4. Zero engine/provider diff vs `main`

```
$ git diff --name-only main -- Sources/TextEngineCore Sources/TextEngineReferenceProviders
$
```

Empty output. This slice's absolute-budget ceiling lives entirely in
`Sources/ViewportBenchmarks/` (`BenchmarkModels.swift`, `BenchmarkOptions.swift`)
and its test target — zero change to the core engine or the reference
providers, confirming AC7's "no core/provider change" clause.

## 5. Frame-hot-path gate loop — all `gate=pass`, `budget_absolute_p99_ns=1666666`

Ran via `swift run -c release ViewportBenchmarks -- <mode> --gate` against the
release build above, filtered through `grep -E "mode=|gate="`, for every mode
in the brief's frame-hot-path loop (pipeline via no flag, `--realistic-provider`,
`--variable-height`, `--variable-height-mutation`, `--structural-mutation`,
`--line-query`, `--line-geometry-query`, `--column-query`,
`--column-geometry-query`, `--point-query`, `--point-geometry-query`):

```
### --gate
mode=pipeline scenario=1k_lines_20_visible_overscan_0 iterations=10000 operations_per_sample=256 p95_ns=1481 p99_ns=1593 failures=0 budget_p95_ns=21000 budget_p99_ns=42000 headroom_p95=14.2x headroom_p99=26.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1046.2x gate=pass checksum=1319670707200
mode=pipeline scenario=100k_lines_80_visible_overscan_5 iterations=10000 operations_per_sample=256 p95_ns=6081 p99_ns=6309 failures=0 budget_p95_ns=84000 budget_p99_ns=170000 headroom_p95=13.8x headroom_p99=26.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=264.2x gate=pass checksum=570448232307200
mode=pipeline scenario=1m_lines_200_visible_overscan_50 iterations=10000 operations_per_sample=256 p95_ns=20206 p99_ns=21127 failures=0 budget_p95_ns=280000 budget_p99_ns=560000 headroom_p95=13.9x headroom_p99=26.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=78.9x gate=pass checksum=18852477646272000

### --realistic-provider --gate
mode=realistic_provider provider=large_text scenario=100k_lines_10mb_text iterations=5000 operations_per_sample=256 line_count=100000 document_bytes=11200000 line_bytes=112 p95_ns=5395 p99_ns=6734 failures=0 budget_p95_ns=97000 budget_p99_ns=200000 headroom_p95=18.0x headroom_p99=29.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=247.5x gate=pass checksum=756321289736960

### --variable-height --gate
mode=variable_height provider=prefix_sum scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=218 p99_ns=247 failures=0 budget_p95_ns=4100 budget_p99_ns=8200 headroom_p95=18.8x headroom_p99=33.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=6747.6x gate=pass checksum=231017730560
mode=variable_height provider=prefix_sum scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=692 p99_ns=728 failures=0 budget_p95_ns=14000 budget_p99_ns=28000 headroom_p95=20.2x headroom_p99=38.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=2289.4x gate=pass checksum=101209179008000
mode=variable_height provider=prefix_sum scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=2110 p99_ns=2185 failures=0 budget_p95_ns=45000 budget_p99_ns=90000 headroom_p95=21.3x headroom_p99=41.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=762.8x gate=pass checksum=3536425156727040

### --variable-height-mutation --gate
mode=variable_height_mutation provider=fenwick scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=385 p99_ns=433 failures=0 budget_p95_ns=6600 budget_p99_ns=14000 headroom_p95=17.1x headroom_p99=32.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=3849.1x gate=pass checksum=196866548667
mode=variable_height_mutation provider=fenwick scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=1566 p99_ns=1626 failures=0 budget_p95_ns=24000 budget_p99_ns=48000 headroom_p95=15.3x headroom_p99=29.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1025.0x gate=pass checksum=88324286099072
mode=variable_height_mutation provider=fenwick scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=4882 p99_ns=5066 failures=0 budget_p95_ns=80000 budget_p99_ns=160000 headroom_p95=16.4x headroom_p99=31.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=329.0x gate=pass checksum=3571078666132451

### --structural-mutation --gate
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=971 p99_ns=1028 failures=0 budget_p95_ns=16000 budget_p99_ns=32000 headroom_p95=16.5x headroom_p99=31.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1621.3x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5166 p99_ns=5445 failures=0 budget_p95_ns=69000 budget_p99_ns=140000 headroom_p95=13.4x headroom_p99=25.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=306.1x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=25114 p99_ns=27039 failures=0 budget_p95_ns=290000 budget_p99_ns=580000 headroom_p95=11.5x headroom_p99=21.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=61.6x gate=pass checksum=3379593298396981

### --line-query --gate
mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=11 p99_ns=14 failures=0 budget_p95_ns=220 budget_p99_ns=440 headroom_p95=20.0x headroom_p99=31.4x budget_absolute_p99_ns=1666666 headroom_absolute_p99=119047.6x gate=pass checksum=641440000
mode=line_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=14 p99_ns=19 failures=0 budget_p95_ns=280 budget_p99_ns=560 headroom_p95=20.0x headroom_p99=29.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=87719.3x gate=pass checksum=63985556480
mode=line_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=17 p99_ns=21 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=18.8x headroom_p99=30.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=79365.0x gate=pass checksum=639841600000
mode=line_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=84 p99_ns=106 failures=0 budget_p95_ns=1500 budget_p99_ns=3000 headroom_p95=17.9x headroom_p99=28.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=15723.3x gate=pass checksum=63985600000
mode=line_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=125 p99_ns=151 failures=0 budget_p95_ns=1700 budget_p99_ns=3400 headroom_p95=13.6x headroom_p99=22.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=11037.5x gate=pass checksum=639841547520

### --line-geometry-query --gate
mode=line_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=16 p99_ns=23 failures=0 budget_p95_ns=250 budget_p99_ns=500 headroom_p95=15.6x headroom_p99=21.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=72463.7x gate=pass checksum=160641440000
mode=line_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=20 p99_ns=24 failures=0 budget_p95_ns=340 budget_p99_ns=680 headroom_p95=17.0x headroom_p99=28.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=69444.4x gate=pass checksum=267505512960
mode=line_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=24 p99_ns=29 failures=0 budget_p95_ns=380 budget_p99_ns=760 headroom_p95=15.8x headroom_p99=26.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=57471.2x gate=pass checksum=799841600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=127 p99_ns=159 failures=0 budget_p95_ns=2400 budget_p99_ns=4800 headroom_p95=18.9x headroom_p99=30.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=10482.2x gate=pass checksum=223985600000
mode=line_geometry_query provider=balanced_tree scenario=balanced_tree_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=176 p99_ns=220 failures=0 budget_p95_ns=3400 budget_p99_ns=6800 headroom_p95=19.3x headroom_p99=30.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=7575.8x gate=pass checksum=852321495040

### --column-query --gate
mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=12 p99_ns=13 failures=0 budget_p95_ns=200 budget_p99_ns=400 headroom_p95=16.7x headroom_p99=30.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=128205.1x gate=pass checksum=641440000
mode=column_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=15 p99_ns=20 failures=0 budget_p95_ns=280 budget_p99_ns=620 headroom_p95=18.7x headroom_p99=31.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=83333.3x gate=pass checksum=63985556480
mode=column_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=19 p99_ns=25 failures=0 budget_p95_ns=320 budget_p99_ns=640 headroom_p95=16.8x headroom_p99=25.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=66666.6x gate=pass checksum=639841600000
mode=column_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=32 p99_ns=33 failures=0 budget_p95_ns=470 budget_p99_ns=940 headroom_p95=14.7x headroom_p99=28.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=50505.0x gate=pass checksum=63985600000
mode=column_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=43 p99_ns=51 failures=0 budget_p95_ns=570 budget_p99_ns=1200 headroom_p95=13.3x headroom_p99=23.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=32679.7x gate=pass checksum=639841560320

### --column-geometry-query --gate
mode=column_geometry_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=17 p99_ns=21 failures=0 budget_p95_ns=260 budget_p99_ns=520 headroom_p95=15.3x headroom_p99=24.8x budget_absolute_p99_ns=1666666 headroom_absolute_p99=79365.0x gate=pass checksum=160641440000
mode=column_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 p95_ns=20 p99_ns=24 failures=0 budget_p95_ns=350 budget_p99_ns=700 headroom_p95=17.5x headroom_p99=29.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=69444.4x gate=pass checksum=267505512960
mode=column_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 p95_ns=22 p99_ns=25 failures=0 budget_p95_ns=400 budget_p99_ns=800 headroom_p95=18.2x headroom_p99=32.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=66666.6x gate=pass checksum=799841600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 p95_ns=39 p99_ns=48 failures=0 budget_p95_ns=730 budget_p99_ns=1500 headroom_p95=18.7x headroom_p99=31.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=34722.2x gate=pass checksum=223985600000
mode=column_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 p95_ns=47 p99_ns=59 failures=0 budget_p95_ns=760 budget_p99_ns=1600 headroom_p95=16.2x headroom_p99=27.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=28248.6x gate=pass checksum=839521520640

### --point-query --gate
mode=point_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=26 p99_ns=36 failures=0 budget_p95_ns=690 budget_p99_ns=1400 headroom_p95=26.5x headroom_p99=38.9x budget_absolute_p99_ns=1666666 headroom_absolute_p99=46296.3x gate=pass checksum=64166237440
mode=point_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=34 p99_ns=39 failures=0 budget_p95_ns=650 budget_p99_ns=1300 headroom_p95=19.1x headroom_p99=33.3x budget_absolute_p99_ns=1666666 headroom_absolute_p99=42735.0x gate=pass checksum=640022280960
mode=point_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=39 p99_ns=48 failures=0 budget_p95_ns=900 budget_p99_ns=1800 headroom_p95=23.1x headroom_p99=37.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=34722.2x gate=pass checksum=64166280960
mode=point_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=57 p99_ns=63 failures=0 budget_p95_ns=940 budget_p99_ns=1900 headroom_p95=16.5x headroom_p99=30.2x budget_absolute_p99_ns=1666666 headroom_absolute_p99=26455.0x gate=pass checksum=640022228480

### --point-geometry-query --gate
mode=point_geometry_query provider=uniform scenario=uniform_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=47 p99_ns=61 failures=0 budget_p95_ns=880 budget_p99_ns=1800 headroom_p95=18.7x headroom_p99=29.5x budget_absolute_p99_ns=1666666 headroom_absolute_p99=27322.4x gate=pass checksum=4687694617200924928
mode=point_geometry_query provider=uniform scenario=uniform_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=62 p99_ns=75 failures=0 budget_p95_ns=860 budget_p99_ns=1800 headroom_p95=13.9x headroom_p99=24.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=22222.2x gate=pass checksum=6036755761047907072
mode=point_geometry_query provider=prefixsum scenario=prefixsum_100k iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=64 p99_ns=81 failures=0 budget_p95_ns=960 budget_p99_ns=2000 headroom_p95=15.0x headroom_p99=24.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=20576.1x gate=pass checksum=1712152282485110528
mode=point_geometry_query provider=prefixsum scenario=prefixsum_1m iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=74 p99_ns=84 failures=0 budget_p95_ns=1200 budget_p99_ns=2400 headroom_p95=16.2x headroom_p99=28.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=19841.3x gate=pass checksum=5915921755926273280
```

**Every one of these 31 frame-hot-path scenario rows across the 11 modes above
prints `gate=pass failures=0` and carries `budget_absolute_p99_ns=1666666`** —
the fixed 10%-of-60-FPS-frame ceiling (`1_666_666` ns), independent of the
scenario's own regression budget. Observed `headroom_absolute_p99` ranges from
~61.6x (`structural_mutation|1m_lines`, the tightest — largest local p99 in the
suite, ~27µs) up to ~119,047.6x (`line_query|uniform_1k`, ~14ns), confirming the
ceiling is comfortably above every current measurement while still being a real,
fixed number a slow-drifting engine could eventually breach.

## 6. Bulk mode — exempt from the absolute ceiling, still `gate=pass`

```
$ swift run -c release ViewportBenchmarks -- --bulk-structural-mutation --gate 2>&1 | grep -E "mode=|gate="
mode=bulk_structural_mutation provider=balanced_tree scenario=1k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000 p95_ns=2701 p99_ns=2787 failures=0 budget_p95_ns=50000 budget_p99_ns=100000 headroom_p95=18.5x headroom_p99=35.9x budget_absolute_p99_ns=exempt gate=pass checksum=82740062444
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=100000 p95_ns=8175 p99_ns=8529 failures=0 budget_p95_ns=130000 budget_p99_ns=260000 headroom_p95=15.9x headroom_p99=30.5x budget_absolute_p99_ns=exempt gate=pass checksum=36564666309410
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_64 iterations=2000 operations_per_sample=256 line_count=1000000 p95_ns=45240 p99_ns=49206 failures=0 budget_p95_ns=470000 budget_p99_ns=940000 headroom_p95=10.4x headroom_p99=19.1x budget_absolute_p99_ns=exempt gate=pass checksum=1317343499882000
mode=bulk_structural_mutation provider=balanced_tree scenario=100k_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=100000 p95_ns=63005 p99_ns=65815 failures=0 budget_p95_ns=1500000 budget_p99_ns=3000000 headroom_p95=23.8x headroom_p99=45.6x budget_absolute_p99_ns=exempt gate=pass checksum=2285022074625
mode=bulk_structural_mutation provider=balanced_tree scenario=1m_lines_batch_4096 iterations=2000 operations_per_sample=16 line_count=1000000 p95_ns=137393 p99_ns=149744 failures=0 budget_p95_ns=2900000 budget_p99_ns=5800000 headroom_p95=21.1x headroom_p99=38.7x budget_absolute_p99_ns=exempt gate=pass checksum=82203678997143
```

All 5 `bulk_structural_mutation` scenarios print `budget_absolute_p99_ns=exempt`
(bulk edits are not a per-frame operation, so `isFrameHotPath` is `false` for
exactly this mode per Spec Decision 2 / Task 1's pinned switch) and still
`gate=pass` — the regression budget alone continues to govern bulk, confirming
the absolute ceiling composes without masking the pre-existing check.

## 7. Guard-is-live demonstration: lowered ceiling reddens, revert restores green

Per the brief, the ceiling was temporarily lowered via `sed -i.bak` on
`Sources/ViewportBenchmarks/BenchmarkModels.swift`, run against
`--structural-mutation --gate`, then fully reverted from the `.bak` backup.

**Divisor chosen: `/ 1000`** (as suggested by the brief). Rationale: the local
observed `structural_mutation|1m_lines_200_visible_overscan_50` p99 is
**~27,039-27,612 ns** across runs in this session (see Section 5 and the
re-confirmation run below) — the largest p99 in the frame-hot-path suite.
`frameNanoseconds / 1000` = `16_666_666 / 1000` = **16,666 ns** (Int64 truncating
division), which sits below that scenario's p99 while remaining above the
smaller `1k`/`100k` scenarios' p99 (1,028-1,473 ns and 5,445-5,501 ns
respectively) — so exactly the largest scenario reddens, demonstrating the
guard fires precisely on the breaching row, not indiscriminately.

### 7a. Apply the edit

```
$ sed -i.bak 's#frameNanoseconds / 10 #frameNanoseconds / 1000 #' Sources/ViewportBenchmarks/BenchmarkModels.swift
$ git diff Sources/ViewportBenchmarks/BenchmarkModels.swift
diff --git a/Sources/ViewportBenchmarks/BenchmarkModels.swift b/Sources/ViewportBenchmarks/BenchmarkModels.swift
index c819bcd..6a000c2 100644
--- a/Sources/ViewportBenchmarks/BenchmarkModels.swift
+++ b/Sources/ViewportBenchmarks/BenchmarkModels.swift
@@ -74,7 +74,7 @@ enum GateLimits {
     // pins this frame math; GateFloorTests pins that every frame-hot-path regression p99
     // budget stays under this ceiling.
     static let frameNanoseconds: Int64 = 1_000_000_000 / 60          // 16_666_666 (60 FPS)
-    static let absoluteP99Nanoseconds: Int64 = frameNanoseconds / 10 // 1_666_666 (10% of a frame)
+    static let absoluteP99Nanoseconds: Int64 = frameNanoseconds / 1000 // 1_666_666 (10% of a frame)
 }
```

### 7b. Run the gate — RED

```
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate 2>&1 | grep -E "mode=|gate=|reason="
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=991 p99_ns=1333 failures=0 budget_p95_ns=16000 budget_p99_ns=32000 headroom_p95=16.1x headroom_p99=24.0x budget_absolute_p99_ns=16666 headroom_absolute_p99=12.5x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5195 p99_ns=5451 failures=0 budget_p95_ns=69000 budget_p99_ns=140000 headroom_p95=13.3x headroom_p99=25.7x budget_absolute_p99_ns=16666 headroom_absolute_p99=3.1x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=25197 p99_ns=27088 failures=0 budget_p95_ns=290000 budget_p99_ns=580000 headroom_p95=11.5x headroom_p99=21.4x budget_absolute_p99_ns=16666 headroom_absolute_p99=0.6x gate=fail reason=budget_absolute_exceeded checksum=3379593298396981
```

**Confirmed red**: the `1m_lines_200_visible_overscan_50` row shows
`gate=fail reason=budget_absolute_exceeded` (observed p99 27,088 ns against the
lowered ceiling of 16,666 ns, `headroom_absolute_p99=0.6x` — under 1x, i.e. the
observation exceeds budget). The `1k`/`100k` rows stay `gate=pass` since their
p99 (1,333 ns / 5,451 ns) remains under 16,666 ns — exactly the expected
selective breach.

### 7c. Revert and confirm clean tree

```
$ mv Sources/ViewportBenchmarks/BenchmarkModels.swift.bak Sources/ViewportBenchmarks/BenchmarkModels.swift
$ git diff --stat
$ git status --short
$
```

Both `git diff --stat` and `git status --short` produced **empty output** —
the `.bak` restore fully undid the temporary edit, no `.bak` file remained, and
the tree carried no stray modification.

### 7d. Rebuild and re-confirm GREEN

```
$ swift build -c release 2>&1 | tail -3
[3/5] Write Objects.LinkFileList
[4/5] Linking ViewportBenchmarks
Build complete! (1.57s)
$ swift run -c release ViewportBenchmarks -- --structural-mutation --gate 2>&1 | grep -E "mode=|gate="
mode=structural_mutation provider=balanced_tree scenario=1k_lines_20_visible_overscan_0 iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=1018 p99_ns=1473 failures=0 budget_p95_ns=16000 budget_p99_ns=32000 headroom_p95=15.7x headroom_p99=21.7x budget_absolute_p99_ns=1666666 headroom_absolute_p99=1131.5x gate=pass checksum=200106952336
mode=structural_mutation provider=balanced_tree scenario=100k_lines_80_visible_overscan_5 iterations=5000 operations_per_sample=256 line_count=100000 p95_ns=5206 p99_ns=5470 failures=0 budget_p95_ns=69000 budget_p99_ns=140000 headroom_p95=13.3x headroom_p99=25.6x budget_absolute_p99_ns=1666666 headroom_absolute_p99=304.7x gate=pass checksum=89494497658324
mode=structural_mutation provider=balanced_tree scenario=1m_lines_200_visible_overscan_50 iterations=5000 operations_per_sample=256 line_count=1000000 p95_ns=25495 p99_ns=27612 failures=0 budget_p95_ns=290000 budget_p99_ns=580000 headroom_p95=11.4x headroom_p99=21.0x budget_absolute_p99_ns=1666666 headroom_absolute_p99=60.4x gate=pass checksum=3379593298396981
```

Back to **`gate=pass`** on all three scenarios with the ceiling restored to
`1666666`. The guard is proven live: it fires precisely when the ceiling sits
below an observed p99, and does not fire once restored.

This edit was never committed — only demonstrated and reverted in-place before
any commit was made in this task.

## 8. 45-checksum byte-identity check vs. the Slice 42 baseline

**Method.** Ran every gated mode with `--gate` (pipeline via no flag,
`--realistic-provider`, `--variable-height`, `--variable-height-mutation`,
`--structural-mutation`, `--bulk-structural-mutation`, `--line-query`,
`--line-geometry-query`, `--column-query`, `--column-geometry-query`,
`--point-query`, `--point-geometry-query`), capturing every
`mode=... scenario=... checksum=...` line. Following the Slice 42 baseline's
own convention (`docs/superpowers/verification/2026-07-18-shell-window-selection-guard.md`,
Section 7): `realistic_provider` is registered in `everyGatedBudget()` for
`GateFloorTests` but is never run with `--gate` in CI, so its single row is
excluded from the 45-row comparison set (it is still shown above in Section 5,
proving it too carries the new `budget_absolute_p99_ns=1666666` token and
`gate=pass`). The remaining 11 modes contribute exactly 45 scenario rows
(3+3+3+3+5+5+5+5+5+4+4 = 45).

Both this run's 45 `(mode, scenario, checksum)` triples and the baseline
doc's 45 triples (extracted from Section 7 of the Slice 42 verification
record) were sorted and compared with `diff`:

```
$ diff baseline_checksums_sorted.txt fresh_checksums_sorted.txt
$ echo "diff exit=$?"
diff exit=0
```

**Result: 45/45 identical, diff empty.** Zero drift in any measured checksum —
confirming this slice's gate-token addition (`budget_absolute_p99_ns=`,
`headroom_absolute_p99=`) is purely additive to the printed line and touches no
measured workload, budget literal, corpus, or provider computation. (The full
printed line is *not* byte-identical to the Slice 42 baseline — it now carries
the two new tokens — but that is expected and correct per the task brief; only
the `checksum=` **value** is asserted byte-identical.)

### 45-row table (mode, scenario, checksum)

| Mode | Scenario | Checksum |
|---|---|---|
| pipeline | 1k_lines_20_visible_overscan_0 | 1319670707200 |
| pipeline | 100k_lines_80_visible_overscan_5 | 570448232307200 |
| pipeline | 1m_lines_200_visible_overscan_50 | 18852477646272000 |
| variable_height | 1k_lines_20_visible_overscan_0 | 231017730560 |
| variable_height | 100k_lines_80_visible_overscan_5 | 101209179008000 |
| variable_height | 1m_lines_200_visible_overscan_50 | 3536425156727040 |
| variable_height_mutation | 1k_lines_20_visible_overscan_0 | 196866548667 |
| variable_height_mutation | 100k_lines_80_visible_overscan_5 | 88324286099072 |
| variable_height_mutation | 1m_lines_200_visible_overscan_50 | 3571078666132451 |
| structural_mutation | 1k_lines_20_visible_overscan_0 | 200106952336 |
| structural_mutation | 100k_lines_80_visible_overscan_5 | 89494497658324 |
| structural_mutation | 1m_lines_200_visible_overscan_50 | 3379593298396981 |
| bulk_structural_mutation | 1k_lines_batch_64 | 82740062444 |
| bulk_structural_mutation | 100k_lines_batch_64 | 36564666309410 |
| bulk_structural_mutation | 1m_lines_batch_64 | 1317343499882000 |
| bulk_structural_mutation | 100k_lines_batch_4096 | 2285022074625 |
| bulk_structural_mutation | 1m_lines_batch_4096 | 82203678997143 |
| line_query | uniform_1k | 641440000 |
| line_query | uniform_100k | 63985556480 |
| line_query | uniform_1m | 639841600000 |
| line_query | balanced_tree_100k | 63985600000 |
| line_query | balanced_tree_1m | 639841547520 |
| line_geometry_query | uniform_1k | 160641440000 |
| line_geometry_query | uniform_100k | 267505512960 |
| line_geometry_query | uniform_1m | 799841600000 |
| line_geometry_query | balanced_tree_100k | 223985600000 |
| line_geometry_query | balanced_tree_1m | 852321495040 |
| column_query | uniform_1k | 641440000 |
| column_query | uniform_100k | 63985556480 |
| column_query | uniform_1m | 639841600000 |
| column_query | prefixsum_100k | 63985600000 |
| column_query | prefixsum_1m | 639841560320 |
| column_geometry_query | uniform_1k | 160641440000 |
| column_geometry_query | uniform_100k | 267505512960 |
| column_geometry_query | uniform_1m | 799841600000 |
| column_geometry_query | prefixsum_100k | 223985600000 |
| column_geometry_query | prefixsum_1m | 839521520640 |
| point_query | uniform_100k | 64166237440 |
| point_query | uniform_1m | 640022280960 |
| point_query | prefixsum_100k | 64166280960 |
| point_query | prefixsum_1m | 640022228480 |
| point_geometry_query | uniform_100k | 4687694617200924928 |
| point_geometry_query | uniform_1m | 6036755761047907072 |
| point_geometry_query | prefixsum_100k | 1712152282485110528 |
| point_geometry_query | prefixsum_1m | 5915921755926273280 |

All 45 rows match the Slice 42 baseline
(`docs/superpowers/verification/2026-07-18-shell-window-selection-guard.md`,
Section 7) exactly, including the `point_geometry_query` anchor
(`uniform_100k=4687694617200924928`, `uniform_1m=6036755761047907072`,
`prefixsum_100k=1712152282485110528`, `prefixsum_1m=5915921755926273280`) that
every prior slice's verification record has also carried unchanged since
Slice 40.

## 9. Final clean-tree confirmation

```
$ git status --short
$ git status
On branch slice-43-absolute-product-budget
nothing to commit, working tree clean
```

Confirmed clean immediately before this verification doc was written and
committed. The only file this task adds is this document itself.

---

## Hosted CI — AC8 discharged

**AC8 is discharged on both hosted runs.** PR #96 (`slice-43-absolute-product-budget`)
merged into `main` as merge commit `4a3b83d`. Both runs below were read **at step
level** via `gh run view --log --job=<id>`, never trusting a job-level
`continue-on-error` conclusion (the Slice 16 dead-step-trap rule in `AGENTS.md`).

| | PR-head `29660672085` (`da4c52a`) | Post-merge push `29661132399` (`4a3b83d`) |
|---|---|---|
| Three required jobs | all `success` | all `success` |
| Eleven blocking gate steps | all `success` at step level | all `success` at step level |
| Gate tally | 45 `gate=pass` / 0 `gate=fail` | 45 `gate=pass` / 0 `gate=fail` |
| Host tests | `Executed 310 tests, with 0 failures` | `Executed 310 tests, with 0 failures` |
| `budget_absolute_p99_ns` tokens | 40 × `1666666` + 5 × `exempt` | 40 × `1666666` + 5 × `exempt` |
| `reason=budget_absolute_exceeded` | none (ceiling not breached) | none (ceiling not breached) |
| `point_geometry_query` checksums | baseline-identical | baseline-identical |
| Tightest regression headroom | 6.3× p95 / 7.3× p99 | 6.5× p95 / 10.0× p99 |
| Tightest **absolute** headroom | 44.4× | 44.1× (`structural_mutation|1m`, p99 ≈ 37,821 ns) |
| Realistic-provider observation | ran (PR event, `continue-on-error`) | **skipped** (`push` event skips `if: pull_request`) |
| docs-only completion | skipped (heavy path ran — Swift/test branch) | skipped (heavy path ran) |

- **The new absolute-ceiling axis is live on hosted Linux**: every one of the 40
  frame-hot-path gated rows carries `budget_absolute_p99_ns=1666666` and each of the
  5 `bulk_structural_mutation` rows carries `budget_absolute_p99_ns=exempt`, on both
  runs — the 45-row split confirming the ceiling was applied to exactly the
  frame-hot-path set and deliberately marked exempt for bulk. No row on a clean tree
  reports `reason=budget_absolute_exceeded`.
- **Non-flaky by a wide margin**: the tightest absolute headroom is ~44× on the
  slowest frame-hot-path scenario (`structural_mutation|1m`, hosted p99 ≈ 37,821 ns
  against the 1,666,666 ns ceiling) — an order of magnitude above the ~2.7× hosted
  run-to-run spread, and even looser than the spec's ~28× estimate, so the absolute
  gate cannot redden a clean tree.
- **No measured path moved**: the four `point_geometry_query` checksums
  (`uniform_100k=4687694617200924928`, `uniform_1m=6036755761047907072`,
  `prefixsum_100k=1712152282485110528`, `prefixsum_1m=5915921755926273280`) are
  byte-identical across the local run, both hosted runs, and the Slice 40/41/42
  baseline — consistent with the Section 8 finding that this slice's gate-token
  addition is purely additive.
- The PR-head run ran the realistic-provider observation step (PR event); the
  post-merge `push` run correctly skipped it (`if: pull_request`), matching the
  Slices 24–42 pattern of anchoring proof in the merged-code `push` run.
