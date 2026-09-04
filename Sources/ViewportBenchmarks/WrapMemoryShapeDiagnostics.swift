import TextEngineCore

// The wrap half of --memory-shape (spec §4A). Its own file and its own scenario list:
// MemoryObservationDiagnostics.swift:151 calls memoryShapeScenarios(), so appending wrap
// scenarios there would silently extend --memory-observation too (spec Decision 5).

let wrapMemoryShapeCells = 80
let wrapMemoryShapeAdvance = 1.0
let wrapMemoryShapeRowHeight = 16.0

/// `x` for the point query, measured from the located ROW's left edge. In range at all
/// three widths: the narrowest row spans 10 layout units (spec Decision 9).
let wrapMemoryShapePointX = 5.0

/// The layout-probe count `compute(_:layout:)` makes, MEASURED in Task 1 Step 8, not
/// predicted. `validateVisualRowLayout` probes `firstVisualRow(ofLine: 0)` and
/// `firstVisualRow(ofLine: lineCount)`; the boundary searches that follow run over
/// `UniformLineMetrics` and touch the layout not at all.
let wrapMemoryShapeComputeProbes = 2

/// The `<= 32` shape bound of spec Decision 2. A SHAPE bound, not a budget: not
/// corpus-derived, not recalibrated, and if it fires the answer is to read the code.
let wrapMemoryShapeProbeShapeBound = 32

struct WrapMemoryShapeScenario {
    let name: String
    let lineCount: Int
    let wrapWidth: Double
    let widthLabel: String
}

func wrapMemoryShapeScenarios() -> [WrapMemoryShapeScenario] {
    var scenarios: [WrapMemoryShapeScenario] = []
    for (sizeLabel, lineCount) in [("100k", 100_000), ("1m", 1_000_000)] {
        for (widthLabel, width) in [("inf", Double.infinity), ("40", 40.0), ("10", 10.0)] {
            scenarios.append(WrapMemoryShapeScenario(
                name: "\(sizeLabel)_lines_width_\(widthLabel)",
                lineCount: lineCount,
                wrapWidth: width,
                widthLabel: widthLabel))
        }
    }
    return scenarios
}

struct WrapMemoryShapeSummary {
    let scenarioName: String
    let lineCount: Int
    let widthLabel: String
    let totalRows: Int
    let visibleRows: Int
    let bufferedRows: Int
    let streamedRows: Int
    let pointRowInLine: Int
    let pointClamp: String
    let computeProbes: Int
    let drainProbes: Int
    let rowQueryProbes: Int
    let pointQueryProbes: Int
    let coreOwnedBytes: Int
    let providerOwnedBytes: Int
    let rangeIsOrderedAndBounded: Bool
    let baseInvariantPasses: Bool
    let checksum: Int
}

/// Continuity with the mode's two existing byte estimators, and evidence of nothing:
/// `MemoryLayout<T>.size` reports the INLINE footprint, so a cursor that captured an
/// array would report a pointer. The wrap half's evidence is the probe counts beside it
/// (spec Decision 1); this token exists so the wrap lines carry the same columns as their
/// siblings.
func wrapCoreOwnedBytesEstimate() -> Int {
    MemoryLayout<VirtualRange>.size
        + MemoryLayout<DocumentVisualRowCursor<BenchmarkWrapLayout>>.size
        + MemoryLayout<Int>.size * 2
}

private func wrapMemoryShapeFailureSummary(
    _ scenario: WrapMemoryShapeScenario, totalRows: Int
) -> WrapMemoryShapeSummary {
    WrapMemoryShapeSummary(
        scenarioName: scenario.name, lineCount: scenario.lineCount,
        widthLabel: scenario.widthLabel, totalRows: totalRows,
        visibleRows: 0, bufferedRows: 0, streamedRows: 0,
        pointRowInLine: -1, pointClamp: "unknown",
        computeProbes: 0, drainProbes: 0, rowQueryProbes: 0, pointQueryProbes: 0,
        coreOwnedBytes: wrapCoreOwnedBytesEstimate(), providerOwnedBytes: 0,
        rangeIsOrderedAndBounded: false, baseInvariantPasses: false, checksum: -1)
}

func runWrapMemoryShapeScenario(_ scenario: WrapMemoryShapeScenario) -> WrapMemoryShapeSummary {
    // Built here and released when this function returns: the prefix array is 8 MB at 1M
    // lines, and the six scenarios must not be resident at once (spec §4A).
    let base = BenchmarkWrapLayout(
        lineCount: scenario.lineCount, cells: wrapMemoryShapeCells,
        advance: wrapMemoryShapeAdvance, rowHeight: wrapMemoryShapeRowHeight,
        wrapWidth: scenario.wrapWidth)
    let totalRows = base.firstVisualRow(ofLine: base.lineCount)

    // Decision 9: the middle line's first row, plus three. Rows-per-line is uniform, so
    // the within-line phase is identical at every document size, and the `+ 3` puts the
    // query off a row-start so the within-line walk is exercised.
    let offsetRow = base.firstVisualRow(ofLine: scenario.lineCount / 2) + 3
    let scrollOffsetY = wrapMemoryShapeRowHeight * Double(offsetRow)
    let input = VariableViewportInput(
        scrollOffsetY: scrollOffsetY,
        viewportHeight: Double(memoryShapeViewportRows) * wrapMemoryShapeRowHeight,
        overscanLinesBefore: memoryShapeOverscanBefore,
        overscanLinesAfter: memoryShapeOverscanAfter)

    // One counter per entry point: the four numbers are separate observables, and summing
    // them would hide which one grew.
    let computeCounter = WrapProbeCounter()
    guard case let .success(range) = ViewportVirtualizer.compute(
        input, layout: CountingWrapLayout(base: base, counter: computeCounter)) else {
        return wrapMemoryShapeFailureSummary(scenario, totalRows: totalRows)
    }

    let drainCounter = WrapProbeCounter()
    var cursor = ViewportVirtualizer.visualRowGeometry(
        for: range, layout: CountingWrapLayout(base: base, counter: drainCounter))
    var streamedRows = 0
    var checksum = 0
    while let geometry = cursor.next() {
        streamedRows += 1
        checksum &+= geometry.row.endColumn &* 3
    }

    let rowCounter = WrapProbeCounter()
    let rowQuery = ViewportVirtualizer.visualRowAt(
        y: scrollOffsetY, layout: CountingWrapLayout(base: base, counter: rowCounter))
    if case let .row(located) = rowQuery {
        checksum &+= located.globalRow &* 5
        checksum &+= located.logicalLine &* 7
        checksum &+= located.rowInLine &* 13
    }

    let pointCounter = WrapProbeCounter()
    let pointQuery = ViewportVirtualizer.visualPointAt(
        x: wrapMemoryShapePointX, y: scrollOffsetY,
        layout: CountingWrapLayout(base: base, counter: pointCounter))
    var pointRowInLine = -1
    var pointClamp = "unknown"
    if case let .point(location) = pointQuery {
        pointRowInLine = location.row.rowInLine
        switch location.column {
        case let .cell(cell):
            switch cell.clamp {
            case .inRange: pointClamp = "none"
            case .clampedToLeft: pointClamp = "left"
            case .clampedToRight: pointClamp = "right"
            }
            checksum &+= cell.columnIndex &* 11
        case .blankLine:
            pointClamp = "blank_line"
        }
    }

    let visibleRows = range.visibleEndExclusive - range.visibleStart
    let bufferedRows = range.bufferEndExclusive - range.bufferStart
    // Measured against an independently derived expectation, the way providerBytesPasses
    // already works on the fixed half -- not `lineCount * size`, which the array's own
    // +1 entry would falsify (spec §4A invariant 7).
    let providerOwnedBytes = base.firstRow.count * MemoryLayout<Int>.size
    let expectedProviderBytes = (scenario.lineCount + 1) * MemoryLayout<Int>.size
    let rangePasses = memoryShapeRangeIsOrderedAndBounded(range, lineCount: totalRows)

    let baseInvariantPasses = rangePasses
        && visibleRows == memoryShapeViewportRows
        && bufferedRows == expectedMemoryShapeWindow
        && streamedRows == bufferedRows
        && computeCounter.total == wrapMemoryShapeComputeProbes
        && (scenario.wrapWidth > 10.0 || pointRowInLine > 0)
        && pointClamp == "none"
        && providerOwnedBytes == expectedProviderBytes

    return WrapMemoryShapeSummary(
        scenarioName: scenario.name, lineCount: scenario.lineCount,
        widthLabel: scenario.widthLabel, totalRows: totalRows,
        visibleRows: visibleRows, bufferedRows: bufferedRows, streamedRows: streamedRows,
        pointRowInLine: pointRowInLine, pointClamp: pointClamp,
        computeProbes: computeCounter.total, drainProbes: drainCounter.total,
        rowQueryProbes: rowCounter.total, pointQueryProbes: pointCounter.total,
        coreOwnedBytes: wrapCoreOwnedBytesEstimate(), providerOwnedBytes: providerOwnedBytes,
        rangeIsOrderedAndBounded: rangePasses, baseInvariantPasses: baseInvariantPasses,
        checksum: checksum)
}

/// The wrap half's cross-scenario invariants (spec §4A, 8-12). Pure, for the same reason
/// `memoryShapeComparisonFailures` is. Every comparison is either against a DECLARED
/// constant or between a named PAIR -- never against `summaries.first`.
func wrapMemoryShapeCrossScenarioFailures(
    _ summaries: [WrapMemoryShapeSummary]
) -> [String] {
    var failed: Set<String> = []

    // (8) flatness, and (10) the width-independent window: both against constants.
    for summary in summaries {
        if summary.computeProbes != wrapMemoryShapeComputeProbes {
            failed.insert(summary.scenarioName)
        }
        if summary.bufferedRows != expectedMemoryShapeWindow
            || summary.streamedRows != expectedMemoryShapeWindow {
            failed.insert(summary.scenarioName)
        }
    }

    // (9) the shape bound and (12) the size half of provider bytes: pair the two sizes at
    // each width. A relational invariant fails BOTH scenarios of its pair -- neither is
    // the baseline for the other.
    for widthLabel in Set(summaries.map(\.widthLabel)).sorted() {
        let atWidth = summaries.filter { $0.widthLabel == widthLabel }
        guard let small = atWidth.min(by: { $0.lineCount < $1.lineCount }),
              let large = atWidth.max(by: { $0.lineCount < $1.lineCount }),
              small.lineCount != large.lineCount else { continue }
        let deltas = [
            large.drainProbes - small.drainProbes,
            large.rowQueryProbes - small.rowQueryProbes,
            large.pointQueryProbes - small.pointQueryProbes,
        ]
        if deltas.contains(where: { $0 > wrapMemoryShapeProbeShapeBound })
            || large.providerOwnedBytes < small.providerOwnedBytes * 9 {
            failed.insert(small.scenarioName)
            failed.insert(large.scenarioName)
        }
    }

    for lineCount in Set(summaries.map(\.lineCount)).sorted() {
        let atSize = summaries.filter { $0.lineCount == lineCount }

        // (11) the walk is a width term: the narrow width costs more point probes than
        // the infinite one, or the counter is not tracking the walk at all.
        if let narrow = atSize.first(where: { $0.widthLabel == "10" }),
           let wide = atSize.first(where: { $0.widthLabel == "inf" }),
           narrow.pointQueryProbes <= wide.pointQueryProbes {
            failed.insert(narrow.scenarioName)
            failed.insert(wide.scenarioName)
        }

        // (12) the width half: one prefix entry per LOGICAL line, so the provider's
        // footprint does not move with the width.
        if Set(atSize.map(\.providerOwnedBytes)).count > 1 {
            for summary in atSize { failed.insert(summary.scenarioName) }
        }
    }

    return failed.sorted()
}

func formatWrapMemoryShapeSummary(
    _ summary: WrapMemoryShapeSummary, invariantPasses: Bool
) -> String {
    var output = "mode=\(BenchmarkMode.memoryShape.outputName)"
    output += " provider=wrap"
    output += " scenario=\(summary.scenarioName)"
    output += " line_count=\(summary.lineCount)"
    output += " wrap_width=\(summary.widthLabel)"
    output += " total_rows=\(summary.totalRows)"
    output += " visible_rows=\(summary.visibleRows)"
    output += " buffered_rows=\(summary.bufferedRows)"
    output += " streamed_rows=\(summary.streamedRows)"
    output += " point_row_in_line=\(summary.pointRowInLine)"
    output += " point_clamp=\(summary.pointClamp)"
    output += " compute_probes=\(summary.computeProbes)"
    output += " drain_probes=\(summary.drainProbes)"
    output += " row_query_probes=\(summary.rowQueryProbes)"
    output += " point_query_probes=\(summary.pointQueryProbes)"
    output += " core_owned_bytes=\(summary.coreOwnedBytes)"
    output += " provider_owned_bytes=\(summary.providerOwnedBytes)"
    output += " invariant=\(invariantPasses ? "pass" : "fail")"
    output += " checksum=\(summary.checksum)"
    return output
}
