import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct TextPresentationTests {
    @Test func highlightsDirective() {
        let spans = CodeHighlighter.spans(for: ConfigLine(raw: "  HostName = 10.0.0.1 # prod\r"))
        #expect(spans == [
            HighlightSpan(text: "  ", role: .plain),
            HighlightSpan(text: "HostName", role: .key),
            HighlightSpan(text: " = 10.0.0.1 # prod", role: .value),
        ])
    }

    @Test func highlightsKeywordsCommentsAndUnknown() {
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "Host web *.x")).map(\.role) == [.keyword, .value])
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "match host x")).first?.role == .keyword)
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "Include a/*")).first?.role == .keyword)
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "  # note")) == [HighlightSpan(text: "  # note", role: .comment)])
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "=bad")) == [HighlightSpan(text: "=bad", role: .unknown)])
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "\u{FEFF}Host bom")).first?.role == .unknown)
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "")) == [])
    }

    @Test func rowsCacheReusesRowsForEqualHunksAndReportsWidestText() {
        let cache = DiffRowsCache()
        let hunks = LineDiff.hunks(old: "a\n", new: "a\nlonger line here\n")
        let first = cache.content(for: hunks)
        _ = cache.content(for: hunks)
        #expect(cache.buildCount == 1)
        #expect(first.rows == DiffPresenter.rows(for: hunks))
        #expect(first.minWidth > DiffMetrics.width(of: "longer line here"))
        _ = cache.content(for: LineDiff.hunks(old: "a\n", new: "b\n"))
        #expect(cache.buildCount == 2)
    }

    @Test func cjkAndEmojiLinesMeasureWiderThanAsciiLinesOfTheSameCount() {
        let ascii = String(repeating: "a", count: 20)
        let cjk = String(repeating: "日", count: 20)
        let emoji = String(repeating: "😀", count: 20)
        #expect(ascii.count == cjk.count && ascii.count == emoji.count)
        #expect(DiffMetrics.width(of: cjk) > DiffMetrics.width(of: ascii))
        #expect(DiffMetrics.width(of: emoji) > DiffMetrics.width(of: ascii))
        // The cache picks the wide row even though another row has the same character count.
        let hunks = LineDiff.hunks(old: ascii + "\n", new: cjk + "\n")
        let rows = DiffPresenter.rows(for: hunks)
        #expect(DiffMetrics.minWidth(for: rows) >= DiffMetrics.width(of: cjk))
        #expect(DiffMetrics.width(of: "\tx") > DiffMetrics.width(of: " x"))
    }

    @Test func fiveDigitLineNumbersWidenTheGutter() {
        #expect(DiffMetrics.gutterWidth(maxNumber: 99) == DiffMetrics.minGutter)
        #expect(DiffMetrics.gutterWidth(maxNumber: 12345) > DiffMetrics.minGutter)
    }

    @Test func diffRowsStripCarriageReturnsAndMarkMissingNewline() throws {
        let hunks = LineDiff.hunks(old: "Host a\r\n  User u", new: "Host a\r\n  User v\n")
        let rows = DiffPresenter.rows(for: hunks)
        #expect(rows.first?.kind == .header)
        #expect(rows.first?.text == "@@ -1,2 +1,2 @@")
        #expect(rows.contains { $0.kind == .context && $0.text == "Host a" })
        let removedIndex = try #require(rows.firstIndex { $0.kind == .removed })
        #expect(rows[removedIndex].text == "  User u")
        #expect(rows[removedIndex + 1].kind == .noNewline)
        #expect(rows.contains { $0.kind == .added && $0.text == "  User v" && $0.newNumber == 2 })
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func accessibilityLabelsMentionLineAndText() {
        let rows = DiffPresenter.rows(for: LineDiff.hunks(old: "a\n", new: "b\n"))
        let added = rows.first { $0.kind == .added }
        #expect(added?.accessibilityLabel.contains("1") == true)
        #expect(added?.accessibilityLabel.contains("b") == true)
    }

    @Test func unifiedTextForCopying() {
        let hunks = LineDiff.hunks(old: "a\nb", new: "a\nc\n")
        #expect(DiffPresenter.unifiedText(for: hunks) == "@@ -1,2 +1,2 @@\n a\n-b\n\\ No newline at end of file\n+c\n")
        #expect(DiffPresenter.unifiedText(for: []) == "")
    }

    @Test func flagsOnlyUnknownLines() {
        #expect(CodeHighlighter.isFlagged(ConfigLine(raw: "=bad")))
        #expect(CodeHighlighter.isFlagged(ConfigLine(raw: "\u{FEFF}Host bom")))
        #expect(!CodeHighlighter.isFlagged(ConfigLine(raw: "Host a")))
    }
}
