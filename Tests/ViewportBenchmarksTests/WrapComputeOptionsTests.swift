import XCTest
@testable import ViewportBenchmarks

final class WrapComputeOptionsTests: XCTestCase {
    func testWrapComputeSelectsMode() {
        guard case .run(let opts) = BenchmarkOptions.parse(["--wrap-compute"]) else { return XCTFail() }
        XCTAssertEqual(opts.mode, .wrapCompute)
        XCTAssertFalse(opts.enforceGate)
    }
    func testWrapComputeRejectsGate() {
        guard case .failure(let msg) = BenchmarkOptions.parse(["--wrap-compute", "--gate"]) else { return XCTFail() }
        XCTAssertTrue(msg.contains("wrap_compute"))
    }
    func testWrapComputeRejectsSecondMode() {
        guard case .failure = BenchmarkOptions.parse(["--wrap-compute", "--line-query"]) else { return XCTFail() }
    }
    func testWrapComputeIsNotGateable() {
        XCTAssertFalse(BenchmarkMode.wrapCompute.isGateable)
    }
}
