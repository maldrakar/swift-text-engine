import TextEngineCore

enum MemoryShapeProviderKind {
    case synthetic
    case largeText

    var outputName: String {
        switch self {
        case .synthetic:
            return "synthetic"
        case .largeText:
            return "large_text"
        }
    }
}

struct MemoryShapeScenario {
    let name: String
    let providerKind: MemoryShapeProviderKind
    let lineCount: Int
    let lineBytes: Int?
    let lineHeight: Double
    let viewportHeight: Double
    let overscanBefore: Int
    let overscanAfter: Int
}

struct MemoryShapeTraversalResult {
    let lineCount: Int
    let missingCount: Int
    let checksum: Int
}

struct MemoryShapeSummary {
    let providerName: String
    let scenarioName: String
    let lineCount: Int
    let documentBytes: Int?
    let visibleLines: Int
    let bufferedLines: Int
    let geometryLines: Int
    let providerLines: Int
    let missingLines: Int
    let coreOwnedBytes: Int
    let providerOwnedBytes: Int
    let benchmarkOwnedBytes: Int
    let baseInvariantPasses: Bool
    let checksum: Int
}

func memoryShapeScenarios() -> [MemoryShapeScenario] {
    [
        MemoryShapeScenario(
            name: "100k_lines_80_visible_overscan_5",
            providerKind: .synthetic,
            lineCount: 100_000,
            lineBytes: nil,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5
        ),
        MemoryShapeScenario(
            name: "1m_lines_80_visible_overscan_5",
            providerKind: .synthetic,
            lineCount: 1_000_000,
            lineBytes: nil,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5
        ),
        MemoryShapeScenario(
            name: "100k_lines_10mb_text",
            providerKind: .largeText,
            lineCount: 100_000,
            lineBytes: 112,
            lineHeight: 16.0,
            viewportHeight: 80.0 * 16.0,
            overscanBefore: 5,
            overscanAfter: 5
        )
    ]
}

func memoryShapeScrollOffset(lineCount: Int, lineHeight: Double, viewportHeight: Double) -> Double {
    let documentHeight = Double(lineCount) * lineHeight
    let maxOffset = documentHeight > viewportHeight ? documentHeight - viewportHeight : 0.0
    let middleOffset = Double(lineCount / 2) * lineHeight

    if middleOffset > maxOffset {
        return maxOffset
    }

    return middleOffset
}

func coreOwnedBytesEstimate() -> Int {
    MemoryLayout<VirtualRange>.size
        + MemoryLayout<LineGeometryCursor>.size
        + MemoryLayout<Int>.size * 2
}

func variableCoreOwnedBytesEstimate() -> Int {
    MemoryLayout<VirtualRange>.size
        + MemoryLayout<VariableLineGeometryCursor<UniformLineMetrics>>.size
        + MemoryLayout<Int>.size * 2
}

struct VariableMemoryShapeSummary {
    let scenarioName: String
    let lineCount: Int
    let bufferedLines: Int
    let geometryLines: Int
    let coreOwnedBytes: Int
    let traversalPasses: Bool
    let checksum: Int
}

func expectedMemoryShapeVisibleLines(_ scenario: MemoryShapeScenario) -> Int {
    if scenario.lineCount <= 0 || scenario.lineHeight <= 0.0 || scenario.viewportHeight <= 0.0 {
        return 0
    }

    let visibleLines = Int((scenario.viewportHeight / scenario.lineHeight).rounded(.up))
    return min(scenario.lineCount, visibleLines)
}

func expectedMemoryShapeBufferedLines(_ scenario: MemoryShapeScenario) -> Int {
    let visibleLines = expectedMemoryShapeVisibleLines(scenario)
    return min(scenario.lineCount, visibleLines + scenario.overscanBefore + scenario.overscanAfter)
}

func memoryShapeRangeIsOrderedAndBounded(_ range: VirtualRange, lineCount: Int) -> Bool {
    0 <= range.bufferStart
        && range.bufferStart <= range.visibleStart
        && range.visibleStart <= range.visibleEndExclusive
        && range.visibleEndExclusive <= range.bufferEndExclusive
        && range.bufferEndExclusive <= lineCount
}

func countGeometryLines(range: VirtualRange, lineHeight: Double) -> MemoryShapeTraversalResult {
    var cursor = ViewportVirtualizer.geometry(for: range, lineHeight: lineHeight)
    var lineCount = 0
    var checksum = 0

    while let geometry = cursor.next() {
        lineCount += 1
        checksum &+= geometry.lineIndex
        checksum &+= Int(geometry.y)
        checksum &+= Int(geometry.height)
    }

    return MemoryShapeTraversalResult(
        lineCount: lineCount,
        missingCount: 0,
        checksum: checksum
    )
}

func countProviderLines<Source: DocumentLineSource>(
    range: VirtualRange,
    source: Source,
    foldLineContent: (inout Int, Source.Line) -> Void
) -> MemoryShapeTraversalResult {
    var cursor = ViewportVirtualizer.lines(for: range, in: source)
    var lineCount = 0
    var missingCount = 0
    var checksum = 0

    while let element = cursor.next() {
        switch element {
        case let .line(line):
            lineCount += 1
            checksum &+= line.index
            foldLineContent(&checksum, line.content)
        case let .missing(index):
            missingCount += 1
            checksum &-= index
        }
    }

    return MemoryShapeTraversalResult(
        lineCount: lineCount,
        missingCount: missingCount,
        checksum: checksum
    )
}

func runMemoryShapeScenario(_ scenario: MemoryShapeScenario) -> MemoryShapeSummary {
    let scrollOffset = memoryShapeScrollOffset(
        lineCount: scenario.lineCount,
        lineHeight: scenario.lineHeight,
        viewportHeight: scenario.viewportHeight
    )
    let input = ViewportInput(
        lineCount: scenario.lineCount,
        lineHeight: scenario.lineHeight,
        scrollOffsetY: scrollOffset,
        viewportHeight: scenario.viewportHeight,
        overscanLinesBefore: scenario.overscanBefore,
        overscanLinesAfter: scenario.overscanAfter
    )
    let coreOwnedBytes = coreOwnedBytesEstimate()

    switch ViewportVirtualizer.compute(input) {
    case let .success(range):
        let visibleLines = range.visibleEndExclusive - range.visibleStart
        let bufferedLines = range.bufferEndExclusive - range.bufferStart
        let expectedVisibleLines = expectedMemoryShapeVisibleLines(scenario)
        let expectedBufferedLines = expectedMemoryShapeBufferedLines(scenario)
        let rangePasses = memoryShapeRangeIsOrderedAndBounded(range, lineCount: scenario.lineCount)
        let geometry = countGeometryLines(range: range, lineHeight: scenario.lineHeight)
        let provider: MemoryShapeTraversalResult
        let providerOwnedBytes: Int
        let documentBytes: Int?

        switch scenario.providerKind {
        case .synthetic:
            let source = SyntheticLineSource(lineCount: scenario.lineCount)
            provider = countProviderLines(range: range, source: source) { checksum, content in
                checksum &+= content
            }
            providerOwnedBytes = 0
            documentBytes = nil
        case .largeText:
            guard let lineBytes = scenario.lineBytes else {
                return MemoryShapeSummary(
                    providerName: scenario.providerKind.outputName,
                    scenarioName: scenario.name,
                    lineCount: scenario.lineCount,
                    documentBytes: nil,
                    visibleLines: visibleLines,
                    bufferedLines: bufferedLines,
                    geometryLines: geometry.lineCount,
                    providerLines: 0,
                    missingLines: 1,
                    coreOwnedBytes: coreOwnedBytes,
                    providerOwnedBytes: 0,
                    benchmarkOwnedBytes: 0,
                    baseInvariantPasses: false,
                    checksum: -1
                )
            }

            let storage = RealisticDocumentStorage(lineCount: scenario.lineCount, lineBytes: lineBytes)
            let source = RealisticLineSource(storage: storage)
            provider = countProviderLines(range: range, source: source) { checksum, content in
                checksum &+= content.byteOffset
                checksum &+= content.byteLength
                checksum &+= content.firstByte
                checksum &+= content.middleByte
                checksum &+= content.lastByte
            }
            providerOwnedBytes = storage.documentBytes
            documentBytes = storage.documentBytes
        }

        let expectedProviderBytes: Int
        let providerBytesPasses: Bool
        switch scenario.providerKind {
        case .synthetic:
            expectedProviderBytes = 0
            providerBytesPasses = providerOwnedBytes == expectedProviderBytes && documentBytes == nil
        case .largeText:
            if let lineBytes = scenario.lineBytes {
                expectedProviderBytes = scenario.lineCount * lineBytes
            } else {
                expectedProviderBytes = -1
            }
            providerBytesPasses = providerOwnedBytes == expectedProviderBytes
                && documentBytes == expectedProviderBytes
        }

        let baseInvariantPasses = rangePasses
            && visibleLines == expectedVisibleLines
            && bufferedLines == expectedBufferedLines
            && geometry.lineCount == expectedBufferedLines
            && provider.lineCount == expectedBufferedLines
            && provider.missingCount == 0
            && providerBytesPasses

        var checksum = 0
        checksum &+= scenario.lineCount
        checksum &+= visibleLines
        checksum &+= bufferedLines
        checksum &+= geometry.checksum
        checksum &+= provider.checksum
        checksum &+= coreOwnedBytes
        checksum &+= providerOwnedBytes

        return MemoryShapeSummary(
            providerName: scenario.providerKind.outputName,
            scenarioName: scenario.name,
            lineCount: scenario.lineCount,
            documentBytes: documentBytes,
            visibleLines: visibleLines,
            bufferedLines: bufferedLines,
            geometryLines: geometry.lineCount,
            providerLines: provider.lineCount,
            missingLines: provider.missingCount,
            coreOwnedBytes: coreOwnedBytes,
            providerOwnedBytes: providerOwnedBytes,
            benchmarkOwnedBytes: 0,
            baseInvariantPasses: baseInvariantPasses,
            checksum: checksum
        )
    case .failure:
        return MemoryShapeSummary(
            providerName: scenario.providerKind.outputName,
            scenarioName: scenario.name,
            lineCount: scenario.lineCount,
            documentBytes: nil,
            visibleLines: 0,
            bufferedLines: 0,
            geometryLines: 0,
            providerLines: 0,
            missingLines: 1,
            coreOwnedBytes: coreOwnedBytes,
            providerOwnedBytes: 0,
            benchmarkOwnedBytes: 0,
            baseInvariantPasses: false,
            checksum: -1
        )
    }
}

func formatMemoryShapeSummary(_ summary: MemoryShapeSummary, invariantPasses: Bool) -> String {
    var output = "mode=\(BenchmarkMode.memoryShape.outputName)"
    output += " provider=\(summary.providerName)"
    output += " scenario=\(summary.scenarioName)"
    output += " line_count=\(summary.lineCount)"
    if let documentBytes = summary.documentBytes {
        output += " document_bytes=\(documentBytes)"
    }
    output += " visible_lines=\(summary.visibleLines)"
    output += " buffered_lines=\(summary.bufferedLines)"
    output += " touched_lines=\(summary.providerLines)"
    output += " geometry_lines=\(summary.geometryLines)"
    output += " provider_lines=\(summary.providerLines)"
    output += " missing_lines=\(summary.missingLines)"
    output += " core_owned_bytes=\(summary.coreOwnedBytes)"
    output += " provider_owned_bytes=\(summary.providerOwnedBytes)"
    output += " benchmark_owned_bytes=\(summary.benchmarkOwnedBytes)"
    output += " invariant=\(invariantPasses ? "pass" : "fail")"
    output += " checksum=\(summary.checksum)"
    return output
}

func runVariableMemoryShapeScenario(lineCount: Int) -> VariableMemoryShapeSummary {
    let lineHeight = 16.0
    let viewportHeight = 80.0 * lineHeight
    let overscanBefore = 5
    let overscanAfter = 5
    let metrics = UniformLineMetrics(lineCount: lineCount, lineHeight: lineHeight)
    let totalHeight = metrics.offset(ofLine: lineCount)
    let maxOffset = totalHeight > viewportHeight ? totalHeight - viewportHeight : 0.0
    let middleOffset = Double(lineCount / 2) * lineHeight
    let scrollOffsetY = middleOffset > maxOffset ? maxOffset : middleOffset
    let input = VariableViewportInput(
        scrollOffsetY: scrollOffsetY,
        viewportHeight: viewportHeight,
        overscanLinesBefore: overscanBefore,
        overscanLinesAfter: overscanAfter
    )
    let coreOwnedBytes = variableCoreOwnedBytesEstimate()
    let scenarioName = "\(lineCount)_lines_80_visible_overscan_5"

    switch ViewportVirtualizer.compute(input, metrics: metrics) {
    case let .success(range):
        let visibleLines = range.visibleEndExclusive - range.visibleStart
        let bufferedLines = range.bufferEndExclusive - range.bufferStart
        let expectedVisibleLines = min(lineCount, Int((viewportHeight / lineHeight).rounded(.up)))
        let expectedBufferedLines = min(lineCount, expectedVisibleLines + overscanBefore + overscanAfter)
        let rangePasses = memoryShapeRangeIsOrderedAndBounded(range, lineCount: lineCount)
        var cursor = ViewportVirtualizer.geometry(for: range, metrics: metrics)
        var geometryLines = 0
        var checksum = 0
        while let geometry = cursor.next() {
            geometryLines += 1
            checksum &+= geometry.lineIndex
            checksum &+= Int(geometry.y)
            checksum &+= Int(geometry.height)
        }

        return VariableMemoryShapeSummary(
            scenarioName: scenarioName,
            lineCount: lineCount,
            bufferedLines: bufferedLines,
            geometryLines: geometryLines,
            coreOwnedBytes: coreOwnedBytes,
            traversalPasses: rangePasses
                && visibleLines == expectedVisibleLines
                && bufferedLines == expectedBufferedLines
                && geometryLines == bufferedLines,
            checksum: checksum
        )
    case .failure:
        return VariableMemoryShapeSummary(
            scenarioName: scenarioName,
            lineCount: lineCount,
            bufferedLines: 0,
            geometryLines: 0,
            coreOwnedBytes: coreOwnedBytes,
            traversalPasses: false,
            checksum: -1
        )
    }
}

func formatVariableMemoryShapeSummary(_ summary: VariableMemoryShapeSummary, invariantPasses: Bool) -> String {
    var output = "mode=\(BenchmarkMode.memoryShape.outputName)"
    output += " provider=variable_uniform"
    output += " scenario=\(summary.scenarioName)"
    output += " line_count=\(summary.lineCount)"
    output += " buffered_lines=\(summary.bufferedLines)"
    output += " geometry_lines=\(summary.geometryLines)"
    output += " core_owned_bytes=\(summary.coreOwnedBytes)"
    output += " invariant=\(invariantPasses ? "pass" : "fail")"
    output += " checksum=\(summary.checksum)"
    return output
}

func runMemoryShapeDiagnostics() -> Bool {
    let summaries = memoryShapeScenarios().map(runMemoryShapeScenario)
    let syntheticCoreOwnedBytes = summaries
        .filter { $0.providerName == MemoryShapeProviderKind.synthetic.outputName }
        .map(\.coreOwnedBytes)
    let comparisonCoreOwnedBytes = syntheticCoreOwnedBytes.first
    var passed = true

    for summary in summaries {
        let comparisonPasses: Bool
        if summary.providerName == MemoryShapeProviderKind.synthetic.outputName,
           let comparisonCoreOwnedBytes {
            comparisonPasses = summary.coreOwnedBytes == comparisonCoreOwnedBytes
        } else {
            comparisonPasses = true
        }

        let invariantPasses = summary.baseInvariantPasses && comparisonPasses
        print(formatMemoryShapeSummary(summary, invariantPasses: invariantPasses))

        if !invariantPasses {
            passed = false
        }
    }

    let variableSummaries = [100_000, 1_000_000].map(runVariableMemoryShapeScenario)
    let referenceVariableCoreOwnedBytes = variableSummaries.first?.coreOwnedBytes
    for summary in variableSummaries {
        let coreBytesMatches = summary.coreOwnedBytes == referenceVariableCoreOwnedBytes
        let invariantPasses = summary.traversalPasses && coreBytesMatches
        print(formatVariableMemoryShapeSummary(summary, invariantPasses: invariantPasses))

        if !invariantPasses {
            passed = false
        }
    }

    return passed
}
