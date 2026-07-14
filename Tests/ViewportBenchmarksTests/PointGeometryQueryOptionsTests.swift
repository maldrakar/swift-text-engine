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

}
