import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

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
}
