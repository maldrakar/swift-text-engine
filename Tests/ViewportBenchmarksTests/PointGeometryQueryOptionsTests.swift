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

    // "Only one mode flag at a time" (AGENTS.md, ## Commands) is enforced by a guard per
    // flag, and nothing tested any of them. A dropped guard would not fail loudly: the
    // binary would silently run whichever mode won the argument scan, so a gate step could
    // measure the wrong workload and still report gate=pass.
    func testCombiningWithAnEarlierModeFlagIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(
            ["--point-query", "--point-geometry-query"]) else {
            return XCTFail("two mode flags must be rejected, not silently resolved")
        }
        XCTAssertTrue(message.contains("--point-geometry-query"), message)
    }

    func testCombiningWithALaterModeFlagIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(
            ["--point-geometry-query", "--memory-shape"]) else {
            return XCTFail("two mode flags must be rejected, not silently resolved")
        }
        XCTAssertTrue(message.contains("--memory-shape"), message)
    }
}
