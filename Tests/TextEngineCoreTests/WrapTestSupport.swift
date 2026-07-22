import XCTest
import TextEngineCore

/// Drain a `VisualRowQuery`'s cursor into an array, failing the test if it is
/// `.failure`. Shared by every packing/equivalence test.
func collectRows<M: WrapMetricsSource>(
    _ query: VisualRowQuery<M>,
    file: StaticString = #filePath,
    line: UInt = #line
) -> [VisualRow] {
    guard case .rows(var cursor) = query else {
        XCTFail("expected .rows, got .failure", file: file, line: line)
        return []
    }
    var rows: [VisualRow] = []
    while let row = cursor.next() {
        rows.append(row)
    }
    return rows
}
