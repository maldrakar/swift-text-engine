// Foundation is imported HERE, in the test target, purely to read the corpus file
// off disk. Sources/ViewportBenchmarks stays Foundation-free; a test-target import
// cannot change that, and the XCTest runtime already links Foundation anyway.
import Foundation
import XCTest
@testable import ViewportBenchmarks

// The 3x floor is the half of the band the runtime gate CANNOT check: the gate sees
// only budget vs. THIS run's latency, so it catches an inflated budget (headroom above
// the ceiling) but is blind to a budget that sits too close to the worst hosted sample.
// That blindness is what makes a blocking gate go red on a clean tree from runner noise.
// Until this test existed the floor was verified exactly once, by hand, into a table in
// the verification record -- and a corpus append or one mistyped constant could undo it
// with nothing objecting. AGENTS.md "## Gate budgets" states the band; this pins it.
private let floorFactor: Int64 = 3

private let corpusPath = "docs/superpowers/verification/2026-07-12-gate-budget-corpus.tsv"

private struct CorpusExtremes {
    var maxP95: Int64 = 0
    var maxP99: Int64 = 0
    var sampleCount = 0
}

private func repositoryRoot() -> URL {
    // .../Tests/ViewportBenchmarksTests/GateFloorTests.swift -> repo root
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

// key -> "<mode>|<scenario>", matching the derivation script's grouping exactly.
private func loadCorpus() throws -> [String: CorpusExtremes] {
    let url = repositoryRoot().appendingPathComponent(corpusPath)
    let text = try String(contentsOf: url, encoding: .utf8)

    var extremes: [String: CorpusExtremes] = [:]
    for (index, line) in text.split(separator: "\n").enumerated() {
        if index == 0 { continue }  // header
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count == 5,
              let p95 = Int64(columns[3]),
              let p99 = Int64(columns[4]) else {
            XCTFail("malformed corpus row \(index + 1): \(line)")
            continue
        }

        let key = "\(columns[1])|\(columns[2])"
        var entry = extremes[key] ?? CorpusExtremes()
        entry.maxP95 = max(entry.maxP95, p95)
        entry.maxP99 = max(entry.maxP99, p99)
        entry.sampleCount += 1
        extremes[key] = entry
    }
    return extremes
}

private struct GatedBudget {
    let key: String
    let p95: Int64
    let p99: Int64
}

// Every scenario any --gate mode enforces. The mode key comes from BenchmarkMode's own
// outputName, so it cannot drift from what the benchmark prints and the corpus records.
private func everyGatedBudget() -> [GatedBudget] {
    var budgets: [GatedBudget] = []
    func add(_ mode: BenchmarkMode, _ name: String, _ p95: Int64, _ p99: Int64) {
        budgets.append(GatedBudget(key: "\(mode.outputName)|\(name)", p95: p95, p99: p99))
    }

    for s in benchmarkScenarios() {
        add(.pipeline, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in realisticProviderScenarios() {
        add(.realisticProvider, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in variableHeightScenarios() {
        add(.variableHeight, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in variableHeightMutationScenarios() {
        add(.variableHeightMutation, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in structuralMutationScenarios() {
        add(.structuralMutation, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in bulkStructuralMutationScenarios() {
        add(.bulkStructuralMutation, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in lineQueryScenarios() {
        add(.lineQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in lineGeometryQueryScenarios() {
        add(.lineGeometryQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in columnQueryScenarios() {
        add(.columnQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in columnGeometryQueryScenarios() {
        add(.columnGeometryQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    for s in pointQueryScenarios() {
        add(.pointQuery, s.name, s.p95BudgetNanoseconds, s.p99BudgetNanoseconds)
    }
    return budgets
}

final class GateFloorTests: XCTestCase {

    // A budget with no hosted evidence behind it is a hand-typed budget, whatever else
    // it is. --realistic-provider was exactly that until its samples were harvested:
    // a gated mode the corpus had never seen, whose budget nothing could re-derive.
    func testEveryGatedScenarioHasCorpusEvidence() throws {
        let corpus = try loadCorpus()
        let budgets = everyGatedBudget()
        XCTAssertFalse(budgets.isEmpty)

        for budget in budgets {
            XCTAssertNotNil(
                corpus[budget.key],
                "\(budget.key): gated, but the corpus carries no hosted sample for it — "
                    + "harvest it with .github/scripts/harvest-gate-corpus.sh and re-derive")
        }
    }

    // The floor covers BOTH statistics because the gate fails on either one. A budget
    // that clears 3x on p95 and 1.5x on p99 flakes just as reliably as the reverse.
    func testEveryGatedBudgetClearsTheFloorOnBothStatistics() throws {
        let corpus = try loadCorpus()

        for budget in everyGatedBudget() {
            guard let observed = corpus[budget.key] else {
                continue  // reported by testEveryGatedScenarioHasCorpusEvidence
            }

            XCTAssertGreaterThanOrEqual(
                budget.p95, floorFactor * observed.maxP95,
                "\(budget.key): p95 budget \(budget.p95) is below \(floorFactor)x the worst "
                    + "hosted p95 (\(observed.maxP95), n=\(observed.sampleCount)) — it will go "
                    + "red on a clean tree; re-derive with .github/scripts/derive-gate-budgets.sh")

            XCTAssertGreaterThanOrEqual(
                budget.p99, floorFactor * observed.maxP99,
                "\(budget.key): p99 budget \(budget.p99) is below \(floorFactor)x the worst "
                    + "hosted p99 (\(observed.maxP99), n=\(observed.sampleCount)) — it will go "
                    + "red on a clean tree; re-derive with .github/scripts/derive-gate-budgets.sh")
        }
    }
}
