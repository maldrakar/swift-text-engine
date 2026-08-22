import XCTest
@testable import ViewportBenchmarks

final class WrapRowQueryOptionsTests: XCTestCase {
    func testFlagSelectsTheMode() {
        guard case let .run(options) = BenchmarkOptions.parse(["--wrap-row-query"]) else {
            return XCTFail("--wrap-row-query must select a runnable mode")
        }
        XCTAssertEqual(options.mode.outputName, "wrap_row_query")
        XCTAssertFalse(options.enforceGate)
    }

    // Gate promotion for wrap modes is map node 6. Until a hosted budget exists, --gate
    // must be REJECTED rather than silently accepted against a hand-typed number - the
    // failure mode AGENTS.md records in bold for slices 27/31/33/35/37.
    func testGateIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(["--wrap-row-query", "--gate"]) else {
            return XCTFail("--gate must be rejected for a non-gateable mode")
        }
        XCTAssertTrue(message.contains("wrap_row_query"), "message should name the mode: \(message)")
    }

    func testCombiningWithAnEarlierModeFlagIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(
            ["--wrap-compute", "--wrap-row-query"]) else {
            return XCTFail("two mode flags must be rejected")
        }
        XCTAssertTrue(message.contains("--wrap-row-query"), "message should name the flag: \(message)")
    }

    func testIsNotGateable() {
        XCTAssertFalse(BenchmarkMode.wrapRowQuery.isGateable)
    }
}
