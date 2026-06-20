import TextEngineCore

/// Read-only reference provider backed by a balanced order-statistics tree over
/// per-line heights. The provider owns O(N) line metrics outside the core;
/// offset queries walk O(log N) tree nodes.
public struct BalancedTreeLineMetrics: LineMetricsSource {
    private struct Node {
        var height: Double
        var left: Int
        var right: Int
        var subtreeCount: Int
        var subtreeHeightSum: Double
    }

    private var nodes: [Node]
    private var root: Int
    private var freeList: [Int]

    public private(set) var lastMutationNodeVisits: Int

    public init(heights: [Double]) {
        for height in heights {
            precondition(
                height.isFinite && height > 0.0,
                "BalancedTreeLineMetrics requires finite, positive heights"
            )
        }

        self.nodes = []
        self.nodes.reserveCapacity(heights.count)
        self.root = -1
        self.freeList = []
        self.lastMutationNodeVisits = 0

        if !heights.isEmpty {
            self.root = buildBalanced(heights, 0, heights.count)
        }
    }

    public var lineCount: Int { nodeCount(root) }

    public func offset(ofLine index: Int) -> Double {
        var remaining = index
        var current = root
        var sum = 0.0

        while current != -1 {
            let node = nodes[current]
            let leftCount = nodeCount(node.left)
            if remaining < leftCount {
                current = node.left
            } else if remaining == leftCount {
                return sum + nodeSum(node.left)
            } else {
                sum += nodeSum(node.left) + node.height
                remaining -= leftCount + 1
                current = node.right
            }
        }

        return sum
    }

    // MARK: - Height mutation

    // Sets the line at `index` to `newHeight` and adds the height delta to
    // subtreeHeightSum along the ancestor path on the way back up. No structural
    // change, no rebalance. Returns the node-visit count. O(log N).
    @discardableResult
    public mutating func setHeight(ofLine index: Int, to newHeight: Double) -> Int {
        precondition(
            index >= 0 && index < lineCount,
            "BalancedTreeLineMetrics.setHeight index out of range"
        )
        precondition(
            newHeight.isFinite && newHeight > 0.0,
            "BalancedTreeLineMetrics.setHeight requires a finite, positive height"
        )
        lastMutationNodeVisits = 0
        _ = updateHeight(root, index, newHeight)
        return lastMutationNodeVisits
    }

    private mutating func updateHeight(_ t: Int, _ index: Int, _ newHeight: Double) -> Double {
        lastMutationNodeVisits += 1
        let leftCount = nodeCount(nodes[t].left)
        let delta: Double
        if index < leftCount {
            delta = updateHeight(nodes[t].left, index, newHeight)
        } else if index > leftCount {
            delta = updateHeight(nodes[t].right, index - leftCount - 1, newHeight)
        } else {
            delta = newHeight - nodes[t].height
            nodes[t].height = newHeight
        }
        nodes[t].subtreeHeightSum += delta
        return delta
    }

    private func nodeCount(_ index: Int) -> Int {
        index == -1 ? 0 : nodes[index].subtreeCount
    }

    private func nodeSum(_ index: Int) -> Double {
        index == -1 ? 0.0 : nodes[index].subtreeHeightSum
    }

    private mutating func pull(_ index: Int) {
        let node = nodes[index]
        nodes[index].subtreeCount = 1 + nodeCount(node.left) + nodeCount(node.right)
        nodes[index].subtreeHeightSum = node.height + nodeSum(node.left) + nodeSum(node.right)
    }

    private mutating func buildBalanced(_ heights: [Double], _ start: Int, _ end: Int) -> Int {
        if start >= end {
            return -1
        }

        let middle = start + (end - start) / 2
        let index = nodes.count
        nodes.append(Node(
            height: heights[middle],
            left: -1,
            right: -1,
            subtreeCount: 1,
            subtreeHeightSum: heights[middle]
        ))

        let left = buildBalanced(heights, start, middle)
        let right = buildBalanced(heights, middle + 1, end)
        nodes[index].left = left
        nodes[index].right = right
        pull(index)
        return index
    }

    internal func treeHeight() -> Int {
        if root == -1 {
            return 0
        }

        var maxHeight = 0
        var stack: [(index: Int, height: Int)] = [(root, 1)]
        while let entry = stack.popLast() {
            if entry.height > maxHeight {
                maxHeight = entry.height
            }

            let node = nodes[entry.index]
            if node.left != -1 {
                stack.append((node.left, entry.height + 1))
            }
            if node.right != -1 {
                stack.append((node.right, entry.height + 1))
            }
        }
        return maxHeight
    }
}
