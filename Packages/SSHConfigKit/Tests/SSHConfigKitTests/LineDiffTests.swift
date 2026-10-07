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
        #expect(hunk.lines[7].oldNumber == 8)
        #expect(hunk.lines[7].newNumber == 8)
    }

    @Test func insertionAtTop() throws {
        let hunk = try #require(LineDiff.hunks(old: "a\nb\n", new: "x\na\nb\n").first)
        #expect(hunk.header == "@@ -1,2 +1,3 @@")
        #expect(hunk.lines.filter { $0.kind == .added }.map(\.text) == ["x"])
    }

    @Test func distantChangesProduceTwoHunks() throws {
        let new = old
            .replacingOccurrences(of: "line 1\n", with: "LINE 1\n")
            .replacingOccurrences(of: "line 10\n", with: "LINE 10\n")
        let hunks = LineDiff.hunks(old: old, new: new)
        #expect(hunks.count == 2)
        #expect(hunks[0].header == "@@ -1,4 +1,4 @@")
        #expect(hunks[1].header == "@@ -7,4 +7,4 @@")
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

    @Test func trailingNewlineOnlyDifference() {
        let diff = LineDiff.lines(old: "a", new: "a\n")
        #expect(diff.map(\.kind) == [.removed, .added])
        #expect(diff[0].text == "a")
        #expect(diff[0].missingNewline == true)
        #expect(diff[1].text == "a")
        #expect(diff[1].missingNewline == false)
    }

    @Test func identicalTextWithoutTrailingNewline() {
        let hunks = LineDiff.hunks(old: "a\nb", new: "a\nb")
        #expect(hunks.isEmpty)
    }

    @Test func hunksIdenticalWithoutTrailingNewline() {
        let diff = LineDiff.lines(old: "a\nb", new: "a\nb")
        #expect(diff.map(\.kind) == [.context, .context])
        #expect(diff[1].missingNewline == true)
    }

    @Test func emptyOld() throws {
        let hunk = try #require(LineDiff.hunks(old: "", new: "a\n").first)
        #expect(hunk.header == "@@ -0,0 +1,1 @@")
    }

    @Test func emptyNew() throws {
        let hunk = try #require(LineDiff.hunks(old: "a\n", new: "").first)
        #expect(hunk.header == "@@ -1,1 +0,0 @@")
    }

    @Test func contextZeroWithChange() throws {
        let new = old.replacingOccurrences(of: "line 5\n", with: "line five\n")
        let hunks = LineDiff.hunks(old: old, new: new, context: 0)
        #expect(hunks.count == 1)
        let hunk = try #require(hunks.first)
        #expect(hunk.header == "@@ -5,1 +5,1 @@")
        #expect(hunk.lines.count == 2)
    }

    @Test func canonicalEquivalence() {
        let diff = LineDiff.lines(old: "Host \u{E9}\n", new: "Host e\u{301}\n")
        #expect(diff.map(\.kind) == [.removed, .added])
    }
}
