import TextEngineCore

/// Mutable indexed metrics provider backed by a balanced order-statistics tree
/// over per-line heights. The provider owns O(N) line metrics outside the core;
/// offset queries and structural mutations walk O(log N) tree nodes.
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

    // Test-only white-box diagnostics (reached via @testable import; NOT public
    // API). Expose only arena slot bookkeeping, never the tree shape.
    internal var arenaNodeCount: Int { nodes.count }
    internal var freeSlotCount: Int { freeList.count }

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

    public func lineIndex(containingOffset y: Double) -> Int {
        lineIndexAndVisitCount(containingOffset: y).lineIndex
    }

    internal func lineIndexAndVisitCount(containingOffset y: Double) -> (lineIndex: Int, visits: Int) {
        precondition(root != -1, "BalancedTreeLineMetrics.lineIndex requires a non-empty tree")

        var current = root
        var baseIndex = 0
        var remaining = y
        var visits = 0

        while current != -1 {
            visits += 1
            let node = nodes[current]
            let leftSum = nodeSum(node.left)
            if remaining < leftSum {
                current = node.left
                continue
            }

            remaining -= leftSum
            let leftCount = nodeCount(node.left)
            if remaining < node.height {
                return (baseIndex + leftCount, visits)
            }

            remaining -= node.height
            baseIndex += leftCount + 1
            current = node.right
        }

        preconditionFailure("BalancedTreeLineMetrics.lineIndex search exhausted")
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

    // MARK: - Structural mutation: insert

    // Inserts a new line of `height` so it lands at in-order position `index`.
    // O(log N): descend to the leaf insertion point, splice in a node, fix
    // aggregates, and rebalance. Returns node visits.
    @discardableResult
    public mutating func insertLine(at index: Int, height: Double) -> Int {
        precondition(
            index >= 0 && index <= lineCount,
            "BalancedTreeLineMetrics.insertLine index out of range"
        )
        precondition(
            height.isFinite && height > 0.0,
            "BalancedTreeLineMetrics.insertLine requires a finite, positive height"
        )
        lastMutationNodeVisits = 0
        let newNode = allocateNode(height: height)
        root = insert(root, index, newNode)
        return lastMutationNodeVisits
    }

    private mutating func allocateNode(height: Double) -> Int {
        let node = Node(
            height: height, left: -1, right: -1,
            subtreeCount: 1, subtreeHeightSum: height
        )
        if let slot = freeList.popLast() {
            nodes[slot] = node
            return slot
        }

        nodes.append(node)
        return nodes.count - 1
    }

    private mutating func insert(_ t: Int, _ index: Int, _ newNode: Int) -> Int {
        lastMutationNodeVisits += 1
        if t == -1 {
            return newNode
        }

        let leftCount = nodeCount(nodes[t].left)
        let goLeft = index <= leftCount
        if goLeft {
            let updated = insert(nodes[t].left, index, newNode)
            nodes[t].left = updated
        } else {
            let updated = insert(nodes[t].right, index - leftCount - 1, newNode)
            nodes[t].right = updated
        }
        pull(t)
        return maintain(t, leftGrew: goLeft)
    }

    // MARK: - Structural mutation: remove

    // Removes the line at `index`. O(log N): descend to the target, remove it
    // (in-order successor swap when it has two children), recycle its slot, fix
    // aggregates, rebalance. Returns node visits.
    @discardableResult
    public mutating func removeLine(at index: Int) -> Int {
        precondition(
            index >= 0 && index < lineCount,
            "BalancedTreeLineMetrics.removeLine index out of range"
        )
        lastMutationNodeVisits = 0
        root = remove(root, index)
        return lastMutationNodeVisits
    }

    private mutating func remove(_ t: Int, _ index: Int) -> Int {
        lastMutationNodeVisits += 1
        let leftCount = nodeCount(nodes[t].left)
        if index < leftCount {
            let updated = remove(nodes[t].left, index)
            nodes[t].left = updated
            pull(t)
            return maintain(t, leftGrew: false) // left shrank -> right may be too big
        } else if index > leftCount {
            let updated = remove(nodes[t].right, index - leftCount - 1)
            nodes[t].right = updated
            pull(t)
            return maintain(t, leftGrew: true)  // right shrank -> left may be too big
        } else {
            let l = nodes[t].left
            let r = nodes[t].right
            if l == -1 {
                freeList.append(t)
                return r
            } else if r == -1 {
                freeList.append(t)
                return l
            } else {
                // Two children: copy the in-order successor's height into this
                // node, then delete the successor (the min of the right subtree).
                let removed = removeMin(r)
                nodes[t].height = removed.height
                nodes[t].right = removed.root
                pull(t)
                return maintain(t, leftGrew: true) // right shrank -> left may be too big
            }
        }
    }

    // Removes the leftmost node of subtree `t`, recycles its slot, and returns
    // the new subtree root plus the removed node's height.
    private mutating func removeMin(_ t: Int) -> (root: Int, height: Double) {
        lastMutationNodeVisits += 1
        if nodes[t].left == -1 {
            let r = nodes[t].right
            let height = nodes[t].height
            freeList.append(t)
            return (r, height)
        }
        let removed = removeMin(nodes[t].left)
        nodes[t].left = removed.root
        pull(t)
        let rebalanced = maintain(t, leftGrew: false) // left shrank -> right may be too big
        return (rebalanced, removed.height)
    }

    // MARK: - Bulk structural mutation

    @discardableResult
    public mutating func insertLines(at index: Int, heights: [Double]) -> Int {
        precondition(
            index >= 0 && index <= lineCount,
            "BalancedTreeLineMetrics.insertLines index out of range"
        )
        for height in heights {
            precondition(
                height.isFinite && height > 0.0,
                "BalancedTreeLineMetrics.insertLines requires finite, positive heights"
            )
        }
        lastMutationNodeVisits = 0
        if heights.isEmpty {
            return 0
        }
        let middle = buildBalancedRun(heights)
        let (left, right) = split(root, at: index)
        root = join2(join2(left, middle), right)
        return lastMutationNodeVisits
    }

    // Pushes every node slot in subtree `t` onto freeList so a later insert reuses
    // them. Iterative (explicit stack) to avoid recursion depth on large ranges.
    // O(size of t).
    private mutating func recycleSubtree(_ t: Int) {
        if t == -1 {
            return
        }
        var stack = [t]
        while let node = stack.popLast() {
            lastMutationNodeVisits += 1
            let left = nodes[node].left
            let right = nodes[node].right
            freeList.append(node)
            if left != -1 { stack.append(left) }
            if right != -1 { stack.append(right) }
        }
    }

    // Removes the `count` lines starting at in-order position `index`. Validates
    // before mutating (atomic). O(count + log N): split out the range, recycle its
    // slots, join the remainder. Returns node visits. The bound is written as
    // `count <= lineCount - index` (not `index + count <= lineCount`) so an
    // adversarial near-Int.max input cannot trap on overflow before the
    // precondition message fires.
    @discardableResult
    public mutating func removeLines(at index: Int, count: Int) -> Int {
        precondition(
            index >= 0 && index <= lineCount && count >= 0 && count <= lineCount - index,
            "BalancedTreeLineMetrics.removeLines range out of bounds"
        )
        lastMutationNodeVisits = 0
        if count == 0 {
            return 0
        }
        let (left, rest) = split(root, at: index)
        let (middle, right) = split(rest, at: count)
        recycleSubtree(middle)
        root = join2(left, right)
        return lastMutationNodeVisits
    }

    private mutating func buildBalancedRun(_ heights: [Double]) -> Int {
        buildBalancedRun(heights, 0, heights.count)
    }

    private mutating func buildBalancedRun(_ heights: [Double], _ start: Int, _ end: Int) -> Int {
        if start >= end {
            return -1
        }

        let middle = start + (end - start) / 2
        lastMutationNodeVisits += 1
        let index = allocateNode(height: heights[middle])
        let left = buildBalancedRun(heights, start, middle)
        let right = buildBalancedRun(heights, middle + 1, end)
        nodes[index].left = left
        nodes[index].right = right
        pull(index)
        return index
    }

    private func canRoot(_ L: Int, _ R: Int) -> Bool {
        let cL = nodeCount(L)
        let cR = nodeCount(R)
        return cL >= nodeCount(leftChild(R)) && cL >= nodeCount(rightChild(R))
            && cR >= nodeCount(leftChild(L)) && cR >= nodeCount(rightChild(L))
    }

    private mutating func join3(_ L: Int, _ m: Int, _ R: Int) -> Int {
        lastMutationNodeVisits += 1
        if canRoot(L, R) {
            nodes[m].left = L
            nodes[m].right = R
            pull(m)
            return m
        }

        if nodeCount(L) > nodeCount(R) {
            nodes[L].right = join3(nodes[L].right, m, R)
            pull(L)
            return maintain(L, leftGrew: false)
        } else {
            nodes[R].left = join3(L, m, nodes[R].left)
            pull(R)
            return maintain(R, leftGrew: true)
        }
    }

    private mutating func join2(_ L: Int, _ R: Int) -> Int {
        if L == -1 { return R }
        if R == -1 { return L }

        let detached = detachMin(R)
        return join3(L, detached.node, detached.root)
    }

    private mutating func detachMin(_ t: Int) -> (root: Int, node: Int) {
        lastMutationNodeVisits += 1
        if nodes[t].left == -1 {
            let detached = t
            let newRoot = nodes[t].right
            nodes[detached].left = -1
            nodes[detached].right = -1
            return (newRoot, detached)
        }

        let result = detachMin(nodes[t].left)
        nodes[t].left = result.root
        pull(t)
        let rebalanced = maintain(t, leftGrew: false)
        return (rebalanced, result.node)
    }

    private mutating func split(_ t: Int, at index: Int) -> (left: Int, right: Int) {
        lastMutationNodeVisits += 1
        if t == -1 {
            return (-1, -1)
        }

        let leftCount = nodeCount(nodes[t].left)
        if index <= leftCount {
            let (LL, LR) = split(nodes[t].left, at: index)
            let right = join3(LR, t, nodes[t].right)
            return (LL, right)
        } else {
            let (RL, RR) = split(nodes[t].right, at: index - leftCount - 1)
            let left = join3(nodes[t].left, t, RL)
            return (left, RR)
        }
    }

    // MARK: - SBT balance

    private func leftChild(_ index: Int) -> Int { index == -1 ? -1 : nodes[index].left }

    private func rightChild(_ index: Int) -> Int { index == -1 ? -1 : nodes[index].right }

    private mutating func rotateRight(_ x: Int) -> Int {
        let y = nodes[x].left
        let yRight = nodes[y].right
        nodes[x].left = yRight
        nodes[y].right = x
        pull(x)
        pull(y)
        return y
    }

    private mutating func rotateLeft(_ x: Int) -> Int {
        let y = nodes[x].right
        let yLeft = nodes[y].left
        nodes[x].right = yLeft
        nodes[y].left = x
        pull(x)
        pull(y)
        return y
    }

    private mutating func maintain(_ t: Int, leftGrew: Bool) -> Int {
        if t == -1 {
            return -1
        }

        lastMutationNodeVisits += 1
        var t = t
        if leftGrew {
            let l = nodes[t].left
            if nodeCount(leftChild(l)) > nodeCount(nodes[t].right) {
                t = rotateRight(t)
            } else if nodeCount(rightChild(l)) > nodeCount(nodes[t].right) {
                let rotated = rotateLeft(l)
                nodes[t].left = rotated
                t = rotateRight(t)
            } else {
                return t
            }
        } else {
            let r = nodes[t].right
            if nodeCount(rightChild(r)) > nodeCount(nodes[t].left) {
                t = rotateLeft(t)
            } else if nodeCount(leftChild(r)) > nodeCount(nodes[t].left) {
                let rotated = rotateRight(r)
                nodes[t].right = rotated
                t = rotateLeft(t)
            } else {
                return t
            }
        }

        let newLeft = maintain(nodes[t].left, leftGrew: true)
        nodes[t].left = newLeft
        let newRight = maintain(nodes[t].right, leftGrew: false)
        nodes[t].right = newRight
        t = maintain(t, leftGrew: true)
        t = maintain(t, leftGrew: false)
        return t
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
