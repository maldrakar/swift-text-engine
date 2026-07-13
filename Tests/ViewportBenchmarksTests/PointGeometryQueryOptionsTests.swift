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

    func testGateIsAcceptedNowThatBudgetsAreDerived() {
        guard case let .run(options) = BenchmarkOptions.parse(
            ["--point-geometry-query", "--gate"]) else {
            return XCTFail("--gate must be accepted once the scenarios carry derived budgets")
        }
        XCTAssertEqual(options.mode.outputName, "point_geometry_query")
        XCTAssertTrue(options.enforceGate)
    }

    // Every budget in this mode comes from .github/scripts/derive-gate-budgets.sh run
    // against the committed corpus. A nil here would mean a gate that cannot fail;
    // a hand-typed number would mean a gate that never could.
    func testEveryScenarioCarriesADerivedBudget() {
        for scenario in pointGeometryQueryScenarios() {
            XCTAssertNotNil(scenario.p95BudgetNanoseconds, "\(scenario.name) has no p95 budget")
            XCTAssertNotNil(scenario.p99BudgetNanoseconds, "\(scenario.name) has no p99 budget")
        }
    }
}
