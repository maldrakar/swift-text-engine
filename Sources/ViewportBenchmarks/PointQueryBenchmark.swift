import TextEngineCore
import TextEngineReferenceProviders

struct PointQueryScenario {
    let name: String
    let providerName: String
    let lineCount: Int
    let useVariableHeights: Bool     // true -> PrefixSumLineMetrics, false -> UniformLineMetrics
    let p95BudgetNanoseconds: Int64
    let p99BudgetNanoseconds: Int64
}

// Horizontal provider is UniformColumnMetrics in every scenario: line-agnostic,
// O(1) memory, valid for every located line, still O(log M) search per line.
// Only the VERTICAL provider varies, and neither uniform provider overrides its
// native inverse hook, so all four scenarios take the generic binary-search
// fallback on both axes; the vertical variation is in how offset(ofLine:) is
// answered (arithmetic vs prefix-sum array read). Provider-native descent stays
// gated by --line-query (balanced tree) and variable horizontal advances by
// --column-query; the point gate's unique job is composition overhead (sum of the
// two 1D queries).
private let pointColumnsPerLine = 256
private let pointColumnWidth = 8.0
private let pointLineHeight = 16.0

func pointQueryScenarios() -> [PointQueryScenario] {
    [
        PointQueryScenario(name: "uniform_100k", providerName: "uniform",
                           lineCount: 100_000, useVariableHeights: false,
                           p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        PointQueryScenario(name: "uniform_1m", providerName: "uniform",
                           lineCount: 1_000_000, useVariableHeights: false,
                           p95BudgetNanoseconds: 240_000, p99BudgetNanoseconds: 480_000),
        PointQueryScenario(name: "prefixsum_100k", providerName: "prefixsum",
                           lineCount: 100_000, useVariableHeights: true,
                           p95BudgetNanoseconds: 120_000, p99BudgetNanoseconds: 240_000),
        PointQueryScenario(name: "prefixsum_1m", providerName: "prefixsum",
                           lineCount: 1_000_000, useVariableHeights: true,
                           p95BudgetNanoseconds: 240_000, p99BudgetNanoseconds: 480_000),
    ]
}

@inline(never)
func runPointQueryOperation<V: LineMetricsSource, H: LineHorizontalMetricsSource>(
    x: Double, y: Double, lineMetrics: V, columnMetrics: H
) -> BenchmarkOperationResult {
    switch ViewportVirtualizer.pointAt(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics) {
    case let .point(location):
        var checksum = location.line.lineIndex
        switch location.line.clamp {
        case .inRange: checksum &+= 1
        case .clampedToTop: checksum &+= 2
        case .clampedToBottom: checksum &+= 3
        }
        switch location.column {
        case let .cell(cell):
            checksum &+= cell.columnIndex
            switch cell.clamp {
            case .inRange: checksum &+= 10
            case .clampedToLeft: checksum &+= 20
            case .clampedToRight: checksum &+= 30
            }
        case .blankLine:
            checksum &+= 7
        }
        return BenchmarkOperationResult(checksum: checksum, failureCount: 0)
    case .empty, .failure:
        return BenchmarkOperationResult(checksum: -1, failureCount: 1)
    }
}

@inline(never)
@available(macOS 13.0, *)
func runPointQueryScenarioCore<V: LineMetricsSource>(
    _ scenario: PointQueryScenario,
    lineMetrics: V,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    let columnMetrics = UniformColumnMetrics(columnsPerLine: pointColumnsPerLine, columnWidth: pointColumnWidth)
    let totalHeight = lineMetrics.offset(ofLine: lineMetrics.lineCount)
    let width = Double(pointColumnsPerLine) * pointColumnWidth
    let clock = ContinuousClock()
    var samples: [Int64] = []
    samples.reserveCapacity(iterations)
    var checksum = 0
    var failureCount = 0

    for iteration in 0..<iterations {
        let start = clock.now
        for operation in 0..<operationsPerSample {
            let sample = iteration * operationsPerSample + operation
            let y: Double
            let x: Double
            switch sample % 8 {
            case 0:
                y = -1.0 - Double(sample % 1_000)            // above the document
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            case 1:
                y = totalHeight + Double(sample % 1_000)     // past the document end
                x = width + Double(sample % 1_000)           // right of the line end
            case 2:
                y = deterministicScrollOffset(sample: sample, maxOffset: totalHeight)
                x = -1.0 - Double(sample % 1_000)            // left of the line
            default:
                y = deterministicScrollOffset(sample: sample, maxOffset: totalHeight)
                x = deterministicScrollOffset(sample: sample, maxOffset: width)
            }
            let result = runPointQueryOperation(x: x, y: y, lineMetrics: lineMetrics, columnMetrics: columnMetrics)
            checksum &+= result.checksum
            failureCount &+= result.failureCount
        }
        let elapsed = start.duration(to: clock.now)
        samples.append(nanoseconds(elapsed) / Int64(operationsPerSample))
    }

    samples.sort()

    return BenchmarkSummary(
        mode: .pointQuery,
        providerName: scenario.providerName,
        scenarioName: scenario.name,
        iterations: iterations,
        operationsPerSample: operationsPerSample,
        lineCount: lineMetrics.lineCount,
        documentBytes: nil,
        lineBytes: nil,
        p95Nanoseconds: percentile(samples, numerator: 95, denominator: 100),
        p99Nanoseconds: percentile(samples, numerator: 99, denominator: 100),
        checksum: checksum,
        failureCount: failureCount,
        p95BudgetNanoseconds: scenario.p95BudgetNanoseconds,
        p99BudgetNanoseconds: scenario.p99BudgetNanoseconds
    )
}

@available(macOS 13.0, *)
func runPointQueryScenario(
    _ scenario: PointQueryScenario,
    iterations: Int,
    operationsPerSample: Int
) -> BenchmarkSummary {
    if scenario.useVariableHeights {
        let lineMetrics = PrefixSumLineMetrics(heights: variableHeights(lineCount: scenario.lineCount))
        return runPointQueryScenarioCore(scenario, lineMetrics: lineMetrics,
                                         iterations: iterations, operationsPerSample: operationsPerSample)
    } else {
        let lineMetrics = UniformLineMetrics(lineCount: scenario.lineCount, lineHeight: pointLineHeight)
        return runPointQueryScenarioCore(scenario, lineMetrics: lineMetrics,
                                         iterations: iterations, operationsPerSample: operationsPerSample)
    }
}

@available(macOS 13.0, *)
func runPointQueryBenchmarks(enforceGate: Bool) -> Bool {
    let iterations = 5_000
    let operationsPerSample = 256
    var passed = true

    for scenario in pointQueryScenarios() {
        let summary = runPointQueryScenario(
            scenario,
            iterations: iterations,
            operationsPerSample: operationsPerSample
        )
        print(formatSummary(summary, includeGate: enforceGate))

        if enforceGate && !summary.passesGate {
            passed = false
        } else if !enforceGate && summary.failureCount != 0 {
            passed = false
        }
    }

    return passed
}
