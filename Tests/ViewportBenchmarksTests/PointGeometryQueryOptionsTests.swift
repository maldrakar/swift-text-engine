import XCTest
@testable import ViewportBenchmarks

final class PointGeometryQueryOptionsTests: XCTestCase {
    // BenchmarkOptions.parse takes an UNLABELLED [String] and returns
    // BenchmarkOptionParse (.run / .help / .failure) — see BenchmarkOptions.swift:82.
    func testFlagSelectsTheMode() {
        guard case let .run(options) = BenchmarkOptions.parse(["--point-geometry-query"]) else {
            return XCTFail("--point-geometry-query must select a runnable mode")
        }
        XCTAssertEqual(options.mode.outputName, "point_geometry_query")
        XCTAssertFalse(options.enforceGate)
    }

    // Until this mode's budgets are DERIVED from hosted evidence, --gate must be
    // refused: a gate with no budget is either a crash or an invitation to type a
    // placeholder, and the placeholder is the bug Slice 38 spent a whole slice
    // removing. Task 6 of the plan flips this expectation once the corpus carries
    // the mode's rows.
    func testGateIsRejectedUntilBudgetsAreDerived() {
        guard case let .failure(message) = BenchmarkOptions.parse(
            ["--point-geometry-query", "--gate"]) else {
            return XCTFail("--gate must be rejected while the scenarios carry nil budgets")
        }
        XCTAssertTrue(message.contains("point_geometry_query"), "message should name the mode: \(message)")
    }

    func testEveryScenarioStartsWithoutABudget() {
        for scenario in pointGeometryQueryScenarios() {
            XCTAssertNil(scenario.p95BudgetNanoseconds, "\(scenario.name) must not carry a hand-typed budget")
            XCTAssertNil(scenario.p99BudgetNanoseconds, "\(scenario.name) must not carry a hand-typed budget")
        }
    }
}
