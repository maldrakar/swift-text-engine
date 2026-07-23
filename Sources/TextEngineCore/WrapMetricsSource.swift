/// Provider contract for soft-wrap: the horizontal cell advances (inherited from
/// `LineHorizontalMetricsSource`) plus the line's break opportunities. The core
/// packs advances into visual rows; it owns no Unicode tables, shaping, or font
/// knowledge — the density of break opportunities is entirely the provider's call
/// (word-wrap ⇒ breaks only after spaces; char-wrap ⇒ breaks at every boundary).
public protocol WrapMetricsSource: LineHorizontalMetricsSource {
    /// Is a soft-break legal immediately before `column` (i.e. after cell
    /// `column - 1`)? Interior boundaries are `1..<columnCount(inLine:)`. The core
    /// additionally treats `columnCount(inLine:)` (the line end) as an implicit
    /// legal end and never queries `canBreak` at `0` or at `columnCount`.
    ///
    /// No default: this is the one thing a wrap provider must supply beyond the
    /// inherited horizontal metrics.
    func canBreak(beforeColumn column: Int, inLine line: Int) -> Bool
}
