import Testing
@testable import SSHConfigKit

struct LineDiffTests {
    let old = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"

    @Test func identicalTextsHaveNoHunks() {
        #expect(LineDiff.hunks(old: old, new: old).isEmpty)
    }

    @Test func singleChangeWithThreeLinesOfContext() throws {
        let new = old.replacingOccurrences(of: "line 5\n", with: "line five\n")
        let hunks = LineDiff.hunks(old: old, new: new)
        let hunk = try #require(hunks.first)
        #expect(hunks.count == 1)
        #expect(hunk.header == "@@ -2,7 +2,7 @@")
        #expect(hunk.lines.map(\.kind) == [.context, .context, .context, .removed, .added, .context, .context, .context])
        #expect(hunk.lines[3].text == "line 5")
        #expect(hunk.lines[4].text == "line five")
        #expect(hunk.lines[3].oldNumber == 5)
        #expect(hunk.lines[4].newNumber == 5)
    }

    @Test func insertionAtTop() throws {
        let hunk = try #require(LineDiff.hunks(old: "a\nb\n", new: "x\na\nb\n").first)
        #expect(hunk.header == "@@ -0,0 +1,3 @@" || hunk.header == "@@ -1,2 +1,3 @@")
        #expect(hunk.lines.filter { $0.kind == .added }.map(\.text) == ["x"])
    }

    @Test func distantChangesProduceTwoHunks() {
        let new = old
            .replacingOccurrences(of: "line 1\n", with: "LINE 1\n")
            .replacingOccurrences(of: "line 10\n", with: "LINE 10\n")
        #expect(LineDiff.hunks(old: old, new: new).count == 2)
    }

    @Test func nearbyChangesMergeIntoOneHunk() {
        let new = old
            .replacingOccurrences(of: "line 4\n", with: "x\n")
            .replacingOccurrences(of: "line 7\n", with: "y\n")
        #expect(LineDiff.hunks(old: old, new: new).count == 1)
    }

    @Test func lineEndingChangeIsVisible() {
        let diff = LineDiff.lines(old: "a\nb\n", new: "a\r\nb\n")
        #expect(diff.map(\.kind) == [.removed, .added, .context])
    }

    @Test func deletionOnly() {
        let diff = LineDiff.lines(old: "a\nb\nc\n", new: "a\nc\n")
        #expect(diff.map(\.kind) == [.context, .removed, .context])
        #expect(diff[1].oldNumber == 2)
        #expect(diff[1].newNumber == nil)
    }
}
