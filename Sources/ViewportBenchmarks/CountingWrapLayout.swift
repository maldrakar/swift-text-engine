import TextEngineCore

/// Probe counters for one measured operation. A CLASS so a non-mutating protocol witness
/// can record: `VisualRowLayoutSource`'s requirements are all non-mutating, and the
/// wrapper is a struct held by value inside the core's generic machinery, so a value-type
/// counter would record into copies nobody reads. This is the shape
/// `WrapComputeDrainTests` already used (slice 55a); it is generalized here rather than
/// copied (spec Decision 6).
final class WrapProbeCounter {
    var columnCount = 0
    var columnOffset = 0
    var canBreak = 0
    var visualRowCount = 0
    var firstVisualRow = 0
    var logicalLine = 0

    /// The BY-ARGUMENT counter. `firstVisualRow(ofLine: lineCount)` is the total-rows
    /// probe every `compute(_:layout:)` makes and the drain path structurally never does,
    /// so "the drain performs no compute" (D-29) is a statement about THIS number, not
    /// about `firstVisualRow`. Six per-hook totals cannot express it, which is why the
    /// generalization keeps it (spec Decision 6).
    var firstVisualRowAtLineCount = 0

    /// The six hooks. Deliberately excludes `firstVisualRowAtLineCount`, which is a
    /// subset of `firstVisualRow` and would double-count.
    var total: Int {
        columnCount + columnOffset + canBreak + visualRowCount + firstVisualRow + logicalLine
    }
}

/// Counts every call the core makes into a `VisualRowLayoutSource`.
///
/// The observable of `--memory-shape`'s wrap half (spec Decision 1): every wrap entry
/// point returns fixed-size values, so a core that started walking the document would
/// show up here and nowhere else.
///
/// **Precondition: `Base` must not override `logicalLine(containingVisualRow:)`.** This
/// wrapper is transparent on five of the six hooks and deliberately is NOT on that one:
/// it answers from the core's binary-search default so the search's `firstVisualRow`
/// probes land in this counter (see the attribution note on the method). For a base that
/// overrides the hook natively -- which the protocol allows, and which a balanced-tree
/// wrap provider would do -- wrapping it would silently measure a DIFFERENT algorithm,
/// and could return a different index if the two disagree. `BenchmarkWrapLayout`, this
/// type's only base today, declares no override; a provider that does needs a counting
/// wrapper that forwards the hook and attributes its probes some other way.
struct CountingWrapLayout<Base: VisualRowLayoutSource>: VisualRowLayoutSource {
    let base: Base
    let counter: WrapProbeCounter

    var lineCount: Int { base.lineCount }
    var rowHeight: Double { base.rowHeight }
    var wrapWidth: Double { base.wrapWidth }

    func columnCount(inLine line: Int) -> Int {
        counter.columnCount += 1
        return base.columnCount(inLine: line)
    }

    func columnOffset(inLine line: Int, column: Int) -> Double {
        counter.columnOffset += 1
        return base.columnOffset(inLine: line, column: column)
    }

    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
        counter.canBreak += 1
        return base.canBreak(beforeColumn: column, inLine: line)
    }

    func visualRowCount(inLine line: Int) -> Int {
        counter.visualRowCount += 1
        return base.visualRowCount(inLine: line)
    }

    func firstVisualRow(ofLine line: Int) -> Int {
        counter.firstVisualRow += 1
        if line == base.lineCount { counter.firstVisualRowAtLineCount += 1 }
        return base.firstVisualRow(ofLine: line)
    }

    /// ATTRIBUTION, and the one place a forwarding wrapper would silently lie.
    ///
    /// `base.logicalLine(containingVisualRow:)` would run the core's default binary
    /// search against the UNWRAPPED base, so every `firstVisualRow` probe that search
    /// makes -- O(log lineCount) of them, the dominant term this mode measures -- would
    /// go uncounted, and every probe count in `--memory-shape` would understate by
    /// exactly the quantity the mode exists to watch.
    ///
    /// Swift gives a type no way to call the protocol-extension default it shadows, and
    /// `binarySearchLogicalLine` is internal to `TextEngineCore`, so the search cannot be
    /// invoked directly and must not be copied (that would be D-13's fourth copy, in the
    /// benchmark target). `DefaultLogicalLineProbe` closes it: it does not declare the
    /// requirement, so the core's default applies to IT, and its `firstVisualRow`
    /// forwards here, where the probes are counted.
    func logicalLine(containingVisualRow g: Int) -> Int {
        counter.logicalLine += 1
        return DefaultLogicalLineProbe(inner: self).logicalLine(containingVisualRow: g)
    }
}

/// A layout that deliberately does NOT declare `logicalLine(containingVisualRow:)`, so
/// the core's binary-search default is its witness. Exists only for the attribution
/// argument on `CountingWrapLayout.logicalLine`; it terminates because the default calls
/// `firstVisualRow`, never `logicalLine`.
private struct DefaultLogicalLineProbe<Inner: VisualRowLayoutSource>: VisualRowLayoutSource {
    let inner: Inner

    var lineCount: Int { inner.lineCount }
    var rowHeight: Double { inner.rowHeight }
    var wrapWidth: Double { inner.wrapWidth }
    func columnCount(inLine line: Int) -> Int { inner.columnCount(inLine: line) }
    func columnOffset(inLine line: Int, column: Int) -> Double {
        inner.columnOffset(inLine: line, column: column)
    }
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool {
        inner.canBreak(beforeColumn: column, inLine: line)
    }
    func visualRowCount(inLine line: Int) -> Int { inner.visualRowCount(inLine: line) }
    func firstVisualRow(ofLine line: Int) -> Int { inner.firstVisualRow(ofLine: line) }
}

/// The vertical-axis counterpart, for the variable half's `touched_lines` repair
/// (spec §4B). `distinctLines` is what replaces `providerLines: bufferedLines`: the set
/// of lines the core actually resolved. It records EVERY index, boundary probes included;
/// the caller intersects with the buffer range for the printed `touched_lines`, because
/// the cursor legitimately reads one offset past the buffer to size the last row -- and
/// asserts the RAW count against `bufferedLines + 1` beside it, because the intersected
/// number is bounded above by construction and could not report an over-walk.
/// Benchmark-owned, not core-owned.
final class LineProbeCounter {
    var offset = 0
    var distinctLines: Set<Int> = []
}

struct CountingLineMetrics<Base: LineMetricsSource>: LineMetricsSource {
    let base: Base
    let counter: LineProbeCounter

    var lineCount: Int { base.lineCount }

    func offset(ofLine index: Int) -> Double {
        counter.offset += 1
        counter.distinctLines.insert(index)
        return base.offset(ofLine: index)
    }

    // The two inverse hooks are deliberately NOT declared: `UniformLineMetrics` overrides
    // neither, so the core's binary-search defaults apply here and their probes land in
    // `offset` above. Forwarding them would lose the same attribution
    // `CountingWrapLayout.logicalLine` protects.
}
