import XCTest
@testable import ViewportBenchmarks

final class WrapPointQueryOptionsTests: XCTestCase {
    func testFlagSelectsTheMode() {
        guard case let .run(options) = BenchmarkOptions.parse(["--wrap-point-query"]) else {
            return XCTFail("--wrap-point-query must select a runnable mode")
        }
        XCTAssertEqual(options.mode.outputName, "wrap_point_query")
        XCTAssertFalse(options.enforceGate)
    }

    // Gate promotion for wrap modes is map node 6, and it is not one step: un-prefix the
    // latency keys, run a hosted step WITHOUT --gate so a verdict-less line bootstraps the
    // corpus, harvest, derive, and only then add the gate step. Until a hosted budget
    // exists, --gate must be REJECTED rather than accepted against a hand-typed number.
    func testGateIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(["--wrap-point-query", "--gate"]) else {
            return XCTFail("--gate must be rejected for a non-gateable mode")
        }
        XCTAssertTrue(message.contains("wrap_point_query"), "message should name the mode: \(message)")
    }

    func testCombiningWithAnEarlierModeFlagIsRejected() {
        guard case let .failure(message) = BenchmarkOptions.parse(["--wrap-row-query", "--wrap-point-query"]) else {
            return XCTFail("two mode flags must be rejected")
        }
        XCTAssertTrue(message.contains("--wrap-point-query"), "message should name the flag: \(message)")
    }

    func testIsNotGateable() {
        XCTAssertFalse(BenchmarkMode.wrapPointQuery.isGateable)
    }

    /// Spec Benchmark Mode / CI: `.scrollFrame` is a DECISION here, not a default
    /// inherited by proximity — a hit test is on the frame path because a drag-select
    /// performs one per frame, and the demanding caller sets the class. The value is inert
    /// until node 6 makes the mode gateable (D-20), which is exactly why it is written
    /// down where a reader can find it.
    func testAbsoluteCeilingIsTheScrollFrameClass() {
        XCTAssertEqual(BenchmarkMode.wrapPointQuery.absoluteCeiling, .scrollFrame)
    }
}
