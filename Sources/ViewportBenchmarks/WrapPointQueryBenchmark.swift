import TextEngineCore

struct WrapPointQueryScenario {
    let name: String
    let lineCount: Int
    let wrapWidth: Double
    let cells: Int
    let advance: Double
    /// Per-scenario, NOT one constant for the mode: 256 is right for the five logarithmic
    /// scenarios and wrong for `long_line_deep_row`, whose per-operation cost is linear in
    /// the line's cells. At 256 x thousands of cells that scenario either runs for minutes
    /// or gets its line quietly shortened until the term it exists to expose is invisible
    /// -- and the shortening is the failure mode, because it looks like a passing
    /// benchmark. Precedent: WrapComputeBenchmark's drain (16), itself after
    /// BulkStructuralMutationBenchmark.
    let operationsPerSample: Int
    /// The located line FITS the wrap width, so the query scans no columns at all.
    ///
    /// PRINTED rather than inferred, because `rows_per_line == 1` does NOT imply it: a
    /// line with no break opportunities and `total > wrapWidth` packs to exactly one
    /// OVERFLOW row and still takes the walk. It also deliberately does not track
    /// Decision 12's other O(1) case -- `long_line_deep_row` is `false` even though its
    /// own final `greedyEnd` returns immediately -- because the token names the cost class
    /// of the WHOLE operation, which is what a budget is derived from.
    let fastPath: Bool
    /// Non-nil only where the sampling rule FIXES the walk depth, so the printed number
    /// means one thing. The other scenarios sample the row axis uniformly and their depth
    /// genuinely varies, so the token is omitted there rather than filled with an average.
    let rowInLine: Int?
    let clampY: Bool
    let clampX: Bool
}

/// A top-level value so `WrapBenchmarkLineShapeTests` can pin the parameters under
/// `@testable import` without running the benchmark. The pin asserts PARAMETERS, never
/// timings.
let wrapPointQueryScenarios: [WrapPointQueryScenario] = [
    // ∞ width -> one row per line, the packer short-circuits, the query is genuinely
    // logarithmic.
    WrapPointQueryScenario(name: "uniform_1k", lineCount: 1_000, wrapWidth: .infinity,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: true, rowInLine: nil, clampY: false, clampX: false),
    WrapPointQueryScenario(name: "uniform_100k", lineCount: 100_000, wrapWidth: .infinity,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: true, rowInLine: nil, clampY: false, clampX: false),
    // Narrow -> 4 rows per line; every located row but the last pays the walk.
    WrapPointQueryScenario(name: "narrow_100k", lineCount: 100_000, wrapWidth: 40.0,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: false, rowInLine: nil, clampY: false, clampX: false),
    // node 3's single clamped_100k SPLITS IN TWO here: the two axes clamp through
    // different branches, and averaging them would hand node 6 a budget for an operation
    // that does not exist. A clamped y still runs both provider searches on the layout
    // axis; a clamped x skips the column hook entirely.
    WrapPointQueryScenario(name: "clamped_y_100k", lineCount: 100_000, wrapWidth: 40.0,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: false, rowInLine: nil, clampY: true, clampX: false),
    WrapPointQueryScenario(name: "clamped_x_100k", lineCount: 100_000, wrapWidth: 40.0,
                           cells: 20, advance: 8.0, operationsPerSample: 256,
                           fastPath: false, rowInLine: nil, clampY: false, clampX: true),
    // The only non-logarithmic term this query has, measured instead of averaged away:
    // 400 rows per line, queried at the LAST row, so the within-line walk is visible.
    // Hiding it from the one mode that measures this query would leave node 6 deriving a
    // budget for a cost class it never saw.
    WrapPointQueryScenario(name: "long_line_deep_row", lineCount: 1_000, wrapWidth: 40.0,
                           cells: 2_000, advance: 8.0, operationsPerSample: 16,
                           fastPath: false, rowInLine: 399, clampY: false, clampX: false),
]

/// Single-line char-wrap metrics for packing the one representative line.
private struct SingleLinePointWrap: WrapMetricsSource {
    let cells: Int
    let advance: Double
    func columnCount(inLine line: Int) -> Int { cells }
    func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * advance }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { column > 0 && column < cells }
}

/// This mode's own layout: an O(lineCount + cells) construction, where re-packing every
/// line would be O(lineCount x cells).
///
/// `BenchmarkWrapLayout` is NOT touched, and not merely by preference: its init
/// deliberately re-packs EVERY line, because that init IS `--wrap-compute`'s measured
/// reindex. Editing it would move another mode's measured quantity. A QUERY mode measures
/// no reindex and has no use for that property.
///
/// What this uses instead: every line in these fixtures is identical by construction, so
/// it packs ONE line and fills the prefix sum by multiplication -- O(lineCount + cells)
/// against the re-packing form's O(lineCount x cells). Asymptotically better, and that is
/// the whole claim: no timing is quoted here, because a comment naming a measured number
/// is falsified by the next machine that runs it.
///
/// Packing one line is O(cells), NOT O(cells x rows): `greedyEnd` breaks at the FIRST
/// legal end that overflows the width, so each row's scan is bounded by its own cells and
/// the scans partition the line. So the re-packing form is merely more expensive here, not
/// pathological -- an earlier draft of this comment claimed otherwise.
///
/// The shortcut is valid because of the FIXTURE, not the type, so the two constructions'
/// agreement is asserted element for element on a small shape in
/// `WrapBenchmarkLineShapeTests`.
struct WrapPointQueryLayout: VisualRowLayoutSource {
    let lineCount: Int
    let rowHeight: Double
    let wrapWidth: Double
    let cells: Int
    let advance: Double
    let rowsPerLine: Int

    init(lineCount: Int, cells: Int, advance: Double, rowHeight: Double, wrapWidth: Double) {
        self.lineCount = lineCount
        self.rowHeight = rowHeight
        self.wrapWidth = wrapWidth
        self.cells = cells
        self.advance = advance
        var packed = 0
        if case .rows(var cursor) = ViewportVirtualizer.visualRows(
            inLine: 0, wrapWidth: wrapWidth, metrics: SingleLinePointWrap(cells: cells, advance: advance)
        ) {
            while cursor.next() != nil { packed += 1 }
        }
        self.rowsPerLine = packed
    }

    func columnCount(inLine line: Int) -> Int { cells }
    func columnOffset(inLine line: Int, column: Int) -> Double { Double(column) * advance }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool { column > 0 && column < cells }
    func visualRowCount(inLine line: Int) -> Int { rowsPerLine }
    func firstVisualRow(ofLine line: Int) -> Int { line * rowsPerLine }
    // logicalLine(containingVisualRow:) is deliberately NOT overridden: the default
    // binary search is what BenchmarkWrapLayout uses, and this mode must measure the same
    // dispatch.
}

private func wrapPointVerticalClampCode(_ clamp: LineLocation.Clamp) -> Int {
    switch clamp {
    case .inRange: return 1
    case .clampedToTop: return 2
    case .clampedToBottom: return 3
    }
}

private func wrapPointHorizontalClampCode(_ clamp: ColumnLocation.Clamp) -> Int {
    switch clamp {
    case .inRange: return 1
    case .clampedToLeft: return 2
    case .clampedToRight: return 3
    }
}

/// Folds every NON-DUPLICATED returned field under distinct multipliers -- both indices of
/// the row, both ends of the span, the span's width, the cell, and BOTH clamp flags.
/// `rowSpan.logicalLine` and `rowSpan.rowInLine` are the two deliberate omissions: they
/// duplicate `row.logicalLine` / `row.rowInLine`, which ARE folded, and agree with them by
/// construction, because both come from the same cursor walk. Folding one index
/// would let a release build delete the rest and still print a plausible number;
/// `PointGeometryChecksumTests` exists because exactly that reversion once passed
/// silently. `width` is a Double, folded through its bit pattern with
/// `Int(truncatingIfNeeded:)` -- `Int(bitPattern: UInt(...))` traps where Int is 32-bit,
/// and although this target is not cross-compiled today the idiom costs nothing. A blank
/// line folds a distinct sentinel, so `.blankLine` and cell 0 cannot collide. Clamp codes
/// start at 1, so `.inRange` still contributes. Pinned by `WrapPointQueryChecksumTests`.
func wrapPointQueryChecksum(_ location: VisualPointLocation) -> Int {
    var value = 0
    value = value &+ location.row.globalRow &* 1
    value = value &+ location.row.logicalLine &* 31
    value = value &+ location.row.rowInLine &* 131
    value = value &+ wrapPointVerticalClampCode(location.row.clamp) &* 1_009
    value = value &+ location.rowSpan.startColumn &* 3_571
    value = value &+ location.rowSpan.endColumn &* 7_919
    value = value &+ Int(truncatingIfNeeded: location.rowSpan.width.bitPattern) &* 17
    switch location.column {
    case .blankLine:
        value = value &+ 104_729
    case .cell(let cell):
        value = value &+ cell.columnIndex &* 15_485_863
        value = value &+ wrapPointHorizontalClampCode(cell.clamp) &* 32_452_843
    }
    return value
}

// Pure so WrapBenchmarkLineShapeTests can pin the token shape without running the
// benchmark. The latency tokens stay PREFIXED (`query_p95_ns=`): the harvester matches
// `p95_ns=` as a substring but then requires the EXACT key, so this line emits no corpus
// row. Node 6 un-prefixes them in the same sequence that adds the gate step.
func formatWrapPointQueryLine(
    scenarioName: String,
    totalRows: Int,
    cellsPerLine: Int,
    rowsPerLine: Int,
    fastPath: Bool,
    rowInLine: Int?,
    operationsPerSample: Int,
    p95Nanoseconds: Int64,
    p99Nanoseconds: Int64,
    checksum: Int
) -> String {
    var line = "mode=wrap_point_query scenario=\(scenarioName) total_rows=\(totalRows)"
        + " cells_per_line=\(cellsPerLine)"
        + " rows_per_line=\(rowsPerLine)"
        + " fast_path=\(fastPath)"
    if let rowInLine {
        line += " row_in_line=\(rowInLine)"
    }
    line += " query_operations_per_sample=\(operationsPerSample)"
        + " query_p95_ns=\(p95Nanoseconds)"
        + " query_p99_ns=\(p99Nanoseconds)"
        + " checksum=\(checksum)"
    return line
}

/// Observational only: NOT gateable, NOT wired into CI. Measured on the same amortised
/// shape as every gated mode (`amortisedSamples`), so the numbers resolve the operation
/// rather than the host clock tick (D-23's repair, which this mode is born on). That
/// "same shape as the gated modes" is inherited, not proven here -- D-28 records that
/// `amortisedSamples` and the twelve gated modes' hand-rolled loops are two
/// implementations of one shape with nothing pinning them together, and node 6 must not
/// read the claim as established when it derives budgets that rest on it.
@available(macOS 13.0, *)
func runWrapPointQueryBenchmarks() -> Bool {
    let rowHeight = 16.0
    let iterations = 5_000

    for scenario in wrapPointQueryScenarios {
        let layout = WrapPointQueryLayout(
            lineCount: scenario.lineCount, cells: scenario.cells, advance: scenario.advance,
            rowHeight: rowHeight, wrapWidth: scenario.wrapWidth)
        let totalRows = layout.firstVisualRow(ofLine: layout.lineCount)
        let totalHeight = Double(totalRows) * rowHeight
        // Every row of these char-wrap fixtures is this wide: the scenarios are sized so
        // the line's advance divides by the width exactly, and at ∞ the row IS the line.
        let rowWidth = min(scenario.wrapWidth, Double(scenario.cells) * scenario.advance)

        // `operation` is the GLOBAL operation index, so the input sequence is exactly what
        // a single-operation loop would produce -- only the clock reads are batched.
        let measured = amortisedSamples(
            iterations: iterations, operationsPerSample: scenario.operationsPerSample
        ) { operation in
            let y: Double
            if scenario.clampY {
                let offset = Double(deterministicIndex(sample: operation, multiplier: 2_654_435_761, modulus: 10_000))
                y = operation % 2 == 0 ? -(offset + 1.0) : totalHeight + offset
            } else if let fixedRow = scenario.rowInLine {
                // The sampling rule that makes `row_in_line=` meaningful: the LINE varies,
                // the depth within it does not, so the walk depth is the constant
                // `rows_per_line - 1` on every operation.
                let line = deterministicIndex(sample: operation, multiplier: 2_654_435_761, modulus: layout.lineCount)
                y = Double(line * layout.rowsPerLine + fixedRow) * rowHeight + rowHeight / 2.0
            } else {
                let row = deterministicIndex(sample: operation, multiplier: 2_654_435_761, modulus: totalRows)
                y = Double(row) * rowHeight + rowHeight / 2.0
            }

            let x: Double
            if scenario.clampX {
                x = rowWidth + Double(deterministicIndex(sample: operation, multiplier: 40_503, modulus: 1_000))
            } else {
                x = Double(deterministicIndex(sample: operation, multiplier: 40_503, modulus: Int(rowWidth))) + 0.25
            }

            if case .point(let location) = ViewportVirtualizer.visualPointAt(x: x, y: y, layout: layout) {
                return wrapPointQueryChecksum(location)
            }
            return 0
        }

        var samples = measured.samples
        samples.sort()
        print(formatWrapPointQueryLine(
            scenarioName: scenario.name,
            totalRows: totalRows,
            cellsPerLine: scenario.cells,
            rowsPerLine: layout.rowsPerLine,
            fastPath: scenario.fastPath,
            rowInLine: scenario.rowInLine,
            operationsPerSample: scenario.operationsPerSample,
            p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
            p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
            checksum: measured.checksum))
    }
    return true
}
