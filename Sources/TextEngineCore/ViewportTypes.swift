public struct ViewportInput: Equatable {
    public let lineCount: Int
    public let lineHeight: Double
    public let scrollOffsetY: Double
    public let viewportHeight: Double
    public let overscanLinesBefore: Int
    public let overscanLinesAfter: Int

    public init(
        lineCount: Int,
        lineHeight: Double,
        scrollOffsetY: Double,
        viewportHeight: Double,
        overscanLinesBefore: Int,
        overscanLinesAfter: Int
    ) {
        self.lineCount = lineCount
        self.lineHeight = lineHeight
        self.scrollOffsetY = scrollOffsetY
        self.viewportHeight = viewportHeight
        self.overscanLinesBefore = overscanLinesBefore
        self.overscanLinesAfter = overscanLinesAfter
    }
}

public struct VirtualRange: Equatable {
    public let visibleStart: Int
    public let visibleEndExclusive: Int
    public let bufferStart: Int
    public let bufferEndExclusive: Int
    public let isAtTop: Bool
    public let isAtBottom: Bool

    public var isEmpty: Bool {
        visibleStart == visibleEndExclusive && bufferStart == bufferEndExclusive
    }

    public init(
        visibleStart: Int,
        visibleEndExclusive: Int,
        bufferStart: Int,
        bufferEndExclusive: Int,
        isAtTop: Bool,
        isAtBottom: Bool
    ) {
        self.visibleStart = visibleStart
        self.visibleEndExclusive = visibleEndExclusive
        self.bufferStart = bufferStart
        self.bufferEndExclusive = bufferEndExclusive
        self.isAtTop = isAtTop
        self.isAtBottom = isAtBottom
    }
}

public struct LineGeometry: Equatable {
    public let lineIndex: Int
    public let y: Double
    public let height: Double

    public init(lineIndex: Int, y: Double, height: Double) {
        self.lineIndex = lineIndex
        self.y = y
        self.height = height
    }
}

public enum ViewportValidationError: Equatable {
    case negativeLineCount
    case nonFiniteValue
    case nonPositiveLineHeight
    case negativeViewportHeight
    case negativeOverscan
    case invalidLineMetrics
    case negativeColumnCount
    case invalidColumnMetrics
    case nonPositiveWrapWidth
    case nonPositiveRowHeight
    case invalidVisualRowLayout
}

public enum ViewportComputation: Equatable {
    case success(VirtualRange)
    case failure(ViewportValidationError)
}

public struct VariableViewportInput: Equatable {
    public let scrollOffsetY: Double
    public let viewportHeight: Double
    public let overscanLinesBefore: Int
    public let overscanLinesAfter: Int

    public init(
        scrollOffsetY: Double,
        viewportHeight: Double,
        overscanLinesBefore: Int,
        overscanLinesAfter: Int
    ) {
        self.scrollOffsetY = scrollOffsetY
        self.viewportHeight = viewportHeight
        self.overscanLinesBefore = overscanLinesBefore
        self.overscanLinesAfter = overscanLinesAfter
    }
}

public enum LineQuery: Equatable {
    case line(LineLocation)
    case empty
    case failure(ViewportValidationError)
}

public struct LineLocation: Equatable {
    public let lineIndex: Int
    public let clamp: Clamp

    public init(lineIndex: Int, clamp: Clamp) {
        self.lineIndex = lineIndex
        self.clamp = clamp
    }

    public enum Clamp: Equatable {
        case inRange
        case clampedToTop
        case clampedToBottom
    }
}

public enum LineGeometryQuery: Equatable {
    case geometry(LineGeometryLocation)
    case empty
    case failure(ViewportValidationError)
}

public struct LineGeometryLocation: Equatable {
    /// The located line's box: lineIndex, top y, height.
    public let geometry: LineGeometry
    /// Where `y` falls within the line: `0.0` at the line top and when clamped to
    /// top; `(y - geometry.y) / geometry.height` in `[0, 1)` for an in-range
    /// query; `1.0` when clamped to bottom.
    public let fractionInLine: Double
    /// Whether the query landed inside the document or past an edge (from `lineAt`).
    public let clamp: LineLocation.Clamp

    public init(geometry: LineGeometry, fractionInLine: Double, clamp: LineLocation.Clamp) {
        self.geometry = geometry
        self.fractionInLine = fractionInLine
        self.clamp = clamp
    }
}

public enum ColumnQuery: Equatable {
    case column(ColumnLocation)           // a real cell was located
    case empty                            // blank line: columnCount(inLine:) == 0
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct ColumnLocation: Equatable {
    public let columnIndex: Int
    public let clamp: Clamp

    public init(columnIndex: Int, clamp: Clamp) {
        self.columnIndex = columnIndex
        self.clamp = clamp
    }

    public enum Clamp: Equatable {
        case inRange          // x was inside [0, lineWidth)
        case clampedToLeft    // x < 0;          resolved to cell 0
        case clampedToRight   // x >= lineWidth;  resolved to last cell
    }
}

public struct ColumnGeometry: Equatable {
    public let columnIndex: Int
    public let x: Double        // cell left edge (columnOffset of columnIndex)
    public let width: Double    // advance width (columnOffset(i+1) - columnOffset(i))

    public init(columnIndex: Int, x: Double, width: Double) {
        self.columnIndex = columnIndex
        self.x = x
        self.width = width
    }
}

public enum ColumnGeometryQuery: Equatable {
    case geometry(ColumnGeometryLocation) // a real cell was located, with its box
    case empty                            // blank line: columnCount(inLine:) == 0
    case failure(ViewportValidationError) // invalid input / metrics
}

public struct ColumnGeometryLocation: Equatable {
    /// The located cell's box: columnIndex, left x, advance width.
    public let geometry: ColumnGeometry
    /// Where `x` falls within the cell: `0.0` at the cell left edge and when clamped
    /// to left; `(x - geometry.x) / geometry.width` in `[0, 1)` for an in-range
    /// query; `1.0` when clamped to right.
    public let fractionInColumn: Double
    /// Whether the query landed inside the line or past an edge (from `columnAt`).
    public let clamp: ColumnLocation.Clamp

    public init(geometry: ColumnGeometry, fractionInColumn: Double, clamp: ColumnLocation.Clamp) {
        self.geometry = geometry
        self.fractionInColumn = fractionInColumn
        self.clamp = clamp
    }
}

/// One visual row of a soft-wrapped logical line: a half-open cell span
/// `[startColumn, endColumn)` with its advance-sum width, in visual order.
/// Horizontal only — vertical stacking (y/height) is a later node.
public struct VisualRow: Equatable {
    public let logicalLine: Int   // the logical line this row belongs to
    public let rowInLine: Int     // 0-based index of this row within logicalLine
    public let startColumn: Int   // inclusive
    public let endColumn: Int     // exclusive — half-open [startColumn, endColumn)
    public let width: Double      // columnOffset(endColumn) − columnOffset(startColumn)

    public init(logicalLine: Int, rowInLine: Int, startColumn: Int, endColumn: Int, width: Double) {
        self.logicalLine = logicalLine
        self.rowInLine = rowInLine
        self.startColumn = startColumn
        self.endColumn = endColumn
        self.width = width
    }
}

/// One visual row of a soft-wrapped document, placed on the vertical axis: node 1's
/// horizontal `VisualRow` span plus its top `y` and `height`. Mirrors `LineGeometry`
/// but composes `VisualRow` rather than re-declaring its fields. `y == globalVisualRow *
/// rowHeight`; `height == rowHeight` (uniform this slice).
public struct VisualRowGeometry: Equatable {
    public let row: VisualRow
    public let y: Double
    public let height: Double

    public init(row: VisualRow, y: Double, height: Double) {
        self.row = row
        self.y = y
        self.height = height
    }
}

/// Result of `ViewportVirtualizer.visualRows`. Generic — its `.rows` payload is the
/// provider-holding `VisualRowCursor<Metrics>`, so this is the project's first
/// generic query enum. NOT `Equatable` (the cursor is mutable, non-`Equatable`);
/// tests pattern-match and compare the drained `[VisualRow]`.
public enum VisualRowQuery<Metrics: WrapMetricsSource> {
    case rows(VisualRowCursor<Metrics>)      // one or more rows (a blank line ⇒ one)
    case failure(ViewportValidationError)    // invalid wrapWidth or malformed metrics
}

public enum PointQuery: Equatable {
    case point(PointLocation)             // a line was located (cell may be blank)
    case empty                            // empty document: lineCount == 0
    case failure(ViewportValidationError) // vertical or horizontal validation failure
}

public struct PointLocation: Equatable {
    /// The located line (index + vertical clamp). Always a real line.
    public let line: LineLocation
    /// The located cell within that line, or `.blankLine` if the line has no cells.
    public let column: ColumnResolution

    public init(line: LineLocation, column: ColumnResolution) {
        self.line = line
        self.column = column
    }
}

public enum ColumnResolution: Equatable {
    case cell(ColumnLocation)             // a real cell was located (index + horizontal clamp)
    case blankLine                        // located line has no cells (columnCount(inLine:) == 0)
}

/// The geometry-bearing 2D result: `pointGeometryAt`'s answer.
///
/// `PointQuery`'s shape with each component swapped for its geometry-bearing
/// counterpart — `LineLocation` -> `LineGeometryLocation`, `ColumnLocation` ->
/// `ColumnGeometryLocation`.
public enum PointGeometryQuery: Equatable {
    case geometry(PointGeometryLocation)  // a line was located (its cell may be blank)
    case empty                            // empty document: lineCount == 0
    case failure(ViewportValidationError) // vertical or horizontal validation failure
}

public struct PointGeometryLocation: Equatable {
    /// The located line's box + within-line fraction + vertical clamp, verbatim
    /// from `lineGeometryAt`. Always a real line — carried even when the cell is
    /// `.blankLine`, because the caret box of an empty line is exactly what a
    /// consumer needs there.
    public let line: LineGeometryLocation
    /// The located cell's box + within-cell fraction + horizontal clamp, or
    /// `.blankLine` if the located line has no cells.
    public let column: ColumnGeometryResolution

    public init(line: LineGeometryLocation, column: ColumnGeometryResolution) {
        self.line = line
        self.column = column
    }
}

public enum ColumnGeometryResolution: Equatable {
    case cell(ColumnGeometryLocation)     // a real cell was located, with its box
    case blankLine                        // located line has no cells (columnCount(inLine:) == 0)
}
