public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, added, removed }
    public let kind: Kind
    public let text: String
    /// 1-based line numbers; nil when the line does not exist on that side.
    public let oldNumber: Int?
    public let newNumber: Int?
    /// True only for the last line of text that does NOT end with "\n" (and is non-empty).
    public let missingNewline: Bool
}

public struct DiffHunk: Equatable, Sendable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public var header: String { "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@" }
}

/// LCS-based line diff. Common prefix/suffix are trimmed first, so the quadratic
/// table only covers the edited region (edits in this app are local).
public enum LineDiff {
    private struct LineInfo: Equatable, Sendable {
        let text: String
        let missingNewline: Bool
    }

    public static func lines(old: String, new: String) -> [DiffLine] {
        let a = split(old)
        let b = split(new)

        var prefix = 0
        while prefix < a.count && prefix < b.count && same(a[prefix], b[prefix]) { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix && suffix < b.count - prefix
            && same(a[a.count - 1 - suffix], b[b.count - 1 - suffix]) { suffix += 1 }

        let am = Array(a[prefix..<(a.count - suffix)])
        let bm = Array(b[prefix..<(b.count - suffix)])
        let n = am.count
        let m = bm.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = same(am[i], bm[j]) ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        var result: [DiffLine] = []
        var oldNo = 1
        var newNo = 1
        func context(_ line: LineInfo) {
            result.append(DiffLine(kind: .context, text: line.text, oldNumber: oldNo, newNumber: newNo, missingNewline: line.missingNewline))
            oldNo += 1
            newNo += 1
        }

        for k in 0..<prefix { context(a[k]) }
        var i = 0
        var j = 0
        while i < n || j < m {
            if i < n && j < m && same(am[i], bm[j]) {
                context(am[i]); i += 1; j += 1
            } else if i < n && (j == m || dp[i + 1][j] >= dp[i][j + 1]) {
                result.append(DiffLine(kind: .removed, text: am[i].text, oldNumber: oldNo, newNumber: nil, missingNewline: am[i].missingNewline))
                oldNo += 1; i += 1
            } else {
                result.append(DiffLine(kind: .added, text: bm[j].text, oldNumber: nil, newNumber: newNo, missingNewline: bm[j].missingNewline))
                newNo += 1; j += 1
            }
        }
        for k in (a.count - suffix)..<a.count { context(a[k]) }
        return result
    }

    public static func hunks(old: String, new: String, context: Int = 3) -> [DiffHunk] {
        let all = lines(old: old, new: new)
        let changed = all.indices.filter { all[$0].kind != .context }
        guard !changed.isEmpty else { return [] }

        var ranges: [ClosedRange<Int>] = []
        for index in changed {
            let lo = max(0, index - context)
            let hi = min(all.count - 1, index + context)
            if let last = ranges.last, lo <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, hi)
            } else {
                ranges.append(lo...hi)
            }
        }

        return ranges.map { range in
            let slice = Array(all[range])
            let before = all[..<range.lowerBound]
            let oldCount = slice.filter { $0.kind != .added }.count
            let newCount = slice.filter { $0.kind != .removed }.count
            let oldBefore = before.filter { $0.kind != .added }.count
            let newBefore = before.filter { $0.kind != .removed }.count
            return DiffHunk(
                oldStart: oldCount == 0 ? oldBefore : oldBefore + 1,
                oldCount: oldCount,
                newStart: newCount == 0 ? newBefore : newBefore + 1,
                newCount: newCount,
                lines: slice)
        }
    }

    private static func split(_ text: String) -> [LineInfo] {
        var parts = text.utf8
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        let endsWithNewline = parts.last == ""
        if endsWithNewline { parts.removeLast() }

        return parts.enumerated().map { (i, text) in
            LineInfo(text: text, missingNewline: !endsWithNewline && i == parts.count - 1)
        }
    }

    private static func same(_ a: LineInfo, _ b: LineInfo) -> Bool {
        a.text.utf8.elementsEqual(b.text.utf8) && a.missingNewline == b.missingNewline
    }
}
