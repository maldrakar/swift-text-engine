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
