import Foundation

// MARK: - Model

enum FileStatus {
    case added, deleted, modified, renamed, copied, typeChanged

    init(code: String) {
        switch code.first {
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        default:  self = .modified
        }
    }

    var letter: String {
        switch self {
        case .added: return "A"
        case .deleted: return "D"
        case .modified: return "M"
        case .renamed: return "R"
        case .copied: return "C"
        case .typeChanged: return "T"
        }
    }
}

struct ChangedFile {
    let status: FileStatus
    let oldPath: String
    let newPath: String

    var displayPath: String { newPath.isEmpty ? oldPath : newPath }
}

enum RowKind {
    case context
    case addition
    case deletion
    case modification
    case message      // e.g. "Binary files differ"
}

struct DiffLine {
    let number: Int          // 1-based line number in its file
    let text: String         // tab-expanded display text
    let highlight: Range<Int>?  // intra-line changed character range (in display text)
}

struct DiffRow {
    let kind: RowKind
    let left: DiffLine?
    let right: DiffLine?
}

struct FileDiff {
    let file: ChangedFile
    let rows: [DiffRow]
    let changeBlocks: [Int]  // row index where each change block starts
    let additions: Int
    let deletions: Int
    let isBinary: Bool
    let maxLeftColumns: Int
    let maxRightColumns: Int
    let maxLineNumber: Int
}

// MARK: - Diff engine

enum DiffEngine {

    static func makeFileDiff(file: ChangedFile, oldContent: Data, newContent: Data) -> FileDiff {
        if isBinary(oldContent) || isBinary(newContent) {
            let row = DiffRow(kind: .message,
                              left: DiffLine(number: 0, text: "Binary files differ", highlight: nil),
                              right: DiffLine(number: 0, text: "Binary files differ", highlight: nil))
            return FileDiff(file: file, rows: [row], changeBlocks: [], additions: 0, deletions: 0,
                            isBinary: true, maxLeftColumns: 24, maxRightColumns: 24, maxLineNumber: 0)
        }

        let oldLines = splitLines(String(decoding: oldContent, as: UTF8.self))
        let newLines = splitLines(String(decoding: newContent, as: UTF8.self))
        let edits = diff(oldLines, newLines)
        return assembleRows(file: file, oldLines: oldLines, newLines: newLines, edits: edits)
    }

    static func isBinary(_ data: Data) -> Bool {
        data.prefix(8000).contains(0)
    }

    static func splitLines(_ s: String) -> [String] {
        if s.isEmpty { return [] }
        var lines = s.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }  // trailing newline
        return lines
    }

    static func expandTabs(_ s: String) -> String {
        guard s.contains("\t") else { return s }
        var out = ""
        out.reserveCapacity(s.count + 16)
        var col = 0
        for ch in s {
            if ch == "\t" {
                let spaces = 4 - (col % 4)
                out += String(repeating: " ", count: spaces)
                col += spaces
            } else {
                out.append(ch)
                col += 1
            }
        }
        return out
    }

    // MARK: Myers diff

    enum Edit {
        case equal(Int, Int)   // (old index, new index)
        case delete(Int)       // old index
        case insert(Int)       // new index
    }

    /// Line-based diff. Falls back to whole-file replace if the edit distance
    /// exceeds a cap (keeps worst-case time/memory bounded).
    static func diff(_ a: [String], _ b: [String]) -> [Edit] {
        // Map lines to integers for fast comparison.
        var table: [String: Int] = [:]
        func id(_ s: String) -> Int {
            if let v = table[s] { return v }
            let v = table.count
            table[s] = v
            return v
        }
        let aIDs = a.map(id)
        let bIDs = b.map(id)

        // Trim common prefix/suffix.
        var start = 0
        while start < aIDs.count && start < bIDs.count && aIDs[start] == bIDs[start] { start += 1 }
        var endA = aIDs.count
        var endB = bIDs.count
        while endA > start && endB > start && aIDs[endA - 1] == bIDs[endB - 1] {
            endA -= 1
            endB -= 1
        }

        var edits: [Edit] = []
        edits.reserveCapacity(aIDs.count + bIDs.count)
        for i in 0..<start { edits.append(.equal(i, i)) }

        let midA = Array(aIDs[start..<endA])
        let midB = Array(bIDs[start..<endB])
        if let mid = myers(midA, midB) {
            for e in mid {
                switch e {
                case .equal(let x, let y): edits.append(.equal(x + start, y + start))
                case .delete(let x): edits.append(.delete(x + start))
                case .insert(let y): edits.append(.insert(y + start))
                }
            }
        } else {
            // Too different: treat middle as full replacement.
            for i in start..<endA { edits.append(.delete(i)) }
            for j in start..<endB { edits.append(.insert(j)) }
        }

        let tail = aIDs.count - endA
        for t in 0..<tail { edits.append(.equal(endA + t, endB + t)) }
        return edits
    }

    /// Standard Myers O(ND) with trace backtracking. Returns nil if D exceeds cap.
    private static func myers(_ a: [Int], _ b: [Int]) -> [Edit]? {
        let n = a.count
        let m = b.count
        if n == 0 && m == 0 { return [] }
        if n == 0 { return (0..<m).map { .insert($0) } }
        if m == 0 { return (0..<n).map { .delete($0) } }

        let maxD = min(n + m, 2000)
        let offset = maxD
        var v = [Int](repeating: 0, count: 2 * maxD + 2)
        var trace: [[Int]] = []
        var foundD = -1

        outer: for d in 0...maxD {
            trace.append(v)
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = v[offset + k + 1]
                } else {
                    x = v[offset + k - 1] + 1
                }
                var y = x - k
                while x < n && y < m && a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = x
                if x >= n && y >= m {
                    foundD = d
                    break outer
                }
                k += 2
            }
        }
        if foundD < 0 { return nil }

        var edits: [Edit] = []
        var x = n
        var y = m
        var d = trace.count - 1
        while d >= 0 {
            let vd = trace[d]
            let k = x - y
            let prevK: Int
            if k == -d || (k != d && vd[offset + k - 1] < vd[offset + k + 1]) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }
            let prevX = vd[offset + prevK]
            let prevY = prevX - prevK
            while x > prevX && y > prevY {
                edits.append(.equal(x - 1, y - 1))
                x -= 1
                y -= 1
            }
            if d > 0 {
                if x == prevX {
                    edits.append(.insert(y - 1))
                    y -= 1
                } else {
                    edits.append(.delete(x - 1))
                    x -= 1
                }
            }
            d -= 1
        }
        return edits.reversed()
    }

    // MARK: Row assembly

    private static func assembleRows(file: ChangedFile, oldLines: [String], newLines: [String],
                                     edits: [Edit]) -> FileDiff {
        var rows: [DiffRow] = []
        var blocks: [Int] = []
        var additions = 0
        var deletions = 0
        var pendingDel: [Int] = []
        var pendingIns: [Int] = []
        var maxLeft = 0
        var maxRight = 0

        let oldDisplay = oldLines.map(expandTabs)
        let newDisplay = newLines.map(expandTabs)

        func flushPending() {
            guard !pendingDel.isEmpty || !pendingIns.isEmpty else { return }
            blocks.append(rows.count)
            let count = max(pendingDel.count, pendingIns.count)
            for i in 0..<count {
                let oldIdx = i < pendingDel.count ? pendingDel[i] : nil
                let newIdx = i < pendingIns.count ? pendingIns[i] : nil
                var leftHL: Range<Int>? = nil
                var rightHL: Range<Int>? = nil
                if let o = oldIdx, let n = newIdx {
                    (leftHL, rightHL) = intralineRanges(oldDisplay[o], newDisplay[n])
                }
                let kind: RowKind
                if !pendingDel.isEmpty && !pendingIns.isEmpty {
                    kind = .modification
                } else if oldIdx != nil {
                    kind = .deletion
                } else {
                    kind = .addition
                }
                let left = oldIdx.map { DiffLine(number: $0 + 1, text: oldDisplay[$0], highlight: leftHL) }
                let right = newIdx.map { DiffLine(number: $0 + 1, text: newDisplay[$0], highlight: rightHL) }
                if let l = left { maxLeft = max(maxLeft, l.text.count) }
                if let r = right { maxRight = max(maxRight, r.text.count) }
                rows.append(DiffRow(kind: kind, left: left, right: right))
            }
            deletions += pendingDel.count
            additions += pendingIns.count
            pendingDel.removeAll()
            pendingIns.removeAll()
        }

        for edit in edits {
            switch edit {
            case .equal(let o, let n):
                flushPending()
                let left = DiffLine(number: o + 1, text: oldDisplay[o], highlight: nil)
                let right = DiffLine(number: n + 1, text: newDisplay[n], highlight: nil)
                maxLeft = max(maxLeft, left.text.count)
                maxRight = max(maxRight, right.text.count)
                rows.append(DiffRow(kind: .context, left: left, right: right))
            case .delete(let o):
                pendingDel.append(o)
            case .insert(let n):
                pendingIns.append(n)
            }
        }
        flushPending()

        if rows.isEmpty {
            rows.append(DiffRow(kind: .message,
                                left: DiffLine(number: 0, text: "Files are identical", highlight: nil),
                                right: DiffLine(number: 0, text: "Files are identical", highlight: nil)))
        }

        return FileDiff(file: file, rows: rows, changeBlocks: blocks,
                        additions: additions, deletions: deletions, isBinary: false,
                        maxLeftColumns: maxLeft, maxRightColumns: maxRight,
                        maxLineNumber: max(oldLines.count, newLines.count))
    }

    /// Character ranges that differ between two lines (common prefix/suffix trimmed).
    static func intralineRanges(_ old: String, _ new: String) -> (Range<Int>?, Range<Int>?) {
        let a = Array(old)
        let b = Array(new)
        var p = 0
        while p < a.count && p < b.count && a[p] == b[p] { p += 1 }
        var s = 0
        while s < a.count - p && s < b.count - p && a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        let leftRange = p..<(a.count - s)
        let rightRange = p..<(b.count - s)
        return (leftRange.isEmpty ? nil : leftRange, rightRange.isEmpty ? nil : rightRange)
    }
}
