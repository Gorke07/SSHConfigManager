import Foundation
import Testing
@testable import SSHConfigKit

struct KnownHostsDocumentTests {
    static let ed = "AAAAC3NzaC1lZDI1NTE5AAAAIPfUPYg1znbIXwm8qtmbk2fUgbpCS0X0aPBTqX90D7ND"
    static let ec = "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMZEF0uxfT/j/MUTD4m4qPdo0bZqQHln5x4cWOV5M4UIXrnccLQ7LCTyysxdMNqMwzrFAmCYRtST3B8qXQZPwx8="

    static let mixed = """
    # comment line
    example.com,192.0.2.1 ssh-ed25519 \(ed) laptop key
    \t[git.example.com]:2222 ecdsa-sha2-nistp256 \(ec)

    |1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 \(ed)
    @cert-authority *.example.com ssh-ed25519 \(ed)
    @revoked bad.example.com ssh-ed25519 \(ed)
    this line is not understood
    """

    @Test(arguments: [
        mixed,
        mixed + "\n",
        mixed.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n",
        "",
        "\n\n",
        "\u{FEFF}example.com ssh-ed25519 \(ed)\n",
        "a ssh-ed25519 \(ed)\r\nb ssh-ed25519 \(ed)",
    ])
    func roundTripIsByteIdentical(_ text: String) {
        #expect(KnownHostsDocument(parsing: text).render().utf8.elementsEqual(text.utf8))
    }

    @Test func parsesEntries() throws {
        let doc = KnownHostsDocument(parsing: Self.mixed)
        let entries = doc.entries
        #expect(entries.count == 5)

        #expect(entries[0].lineIndex == 1)
        #expect(entries[0].names == [
            .plain(KnownHostAddress(host: "example.com", port: 22, isPattern: false)),
            .plain(KnownHostAddress(host: "192.0.2.1", port: 22, isPattern: false)),
        ])
        #expect(entries[0].keyType == "ssh-ed25519")
        #expect(entries[0].keyBase64 == Self.ed)
        #expect(entries[0].comment == "laptop key")
        #expect(entries[0].marker == nil)

        #expect(entries[1].names == [.plain(KnownHostAddress(host: "git.example.com", port: 2222, isPattern: false))])
        #expect(entries[1].comment == nil)

        #expect(entries[2].isHashed)
        let salt = try #require(Data(base64Encoded: "TcU4u9vtVk+qrVRu5kObX1YkHxo="))
        let hash = try #require(Data(base64Encoded: "Xvpl/HIOfbtSWof7EwQayR7aF/k="))
        #expect(entries[2].names == [.hashed(salt: salt, hash: hash)])

        #expect(entries[3].marker == .certAuthority)
        #expect(entries[3].names == [.plain(KnownHostAddress(host: "*.example.com", port: 22, isPattern: true))])
        #expect(entries[4].marker == .revoked)

        #expect(doc.unparsableLines.map(\.index) == [7])
        #expect(doc.unparsableLines.map(\.text) == ["this line is not understood"])
    }

    @Test(arguments: [
        "\u{FEFF}example.com ssh-ed25519 \(ed)",          // BOM: OpenSSH cannot read it
        "example.com ssh-ed25519",                          // no key
        "example.com ssh-ed25519 not*base64",               // key is not base64
        "@unknown example.com ssh-ed25519 \(ed)",           // unknown marker
        "|1|abc ssh-ed25519 \(ed)",                         // malformed hash
        "|1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k=,other ssh-ed25519 \(ed)",
        "a,,b ssh-ed25519 \(ed)",                           // empty name
        "[host]:notaport ssh-ed25519 \(ed)",
        "[host]:70000 ssh-ed25519 \(ed)",
        "[]:22 ssh-ed25519 \(ed)",
        "[host]:+22 ssh-ed25519 \(ed)",
    ])
    func malformedLinesAreUnparsable(_ line: String) {
        let doc = KnownHostsDocument(parsing: line + "\n")
        #expect(doc.entries.isEmpty)
        #expect(doc.unparsableLines.map(\.index) == [0])
    }

    @Test func negatedAndWildcardNamesArePatterns() {
        let doc = KnownHostsDocument(parsing: "!bad.example.com,host?.example.com,good.example.com ssh-ed25519 \(Self.ed)\n")
        #expect(doc.entries.first?.names.map { name -> Bool in
            if case .plain(let address) = name { return address.isPattern }
            return false
        } == [true, true, false])
    }

    @Test func removingLinesKeepsEveryOtherByte() {
        let text = Self.mixed.replacingOccurrences(of: "\n", with: "\r\n")
        var doc = KnownHostsDocument(parsing: text)
        doc.remove(lines: [1, 7])
        var expected = text.components(separatedBy: "\r\n")
        expected.remove(at: 7)
        expected.remove(at: 1)
        // The old line 6 keeps its "\r\n" although it is now the last line.
        #expect(doc.render().utf8.elementsEqual((expected.joined(separator: "\r\n") + "\r\n").utf8))
        #expect(doc.entries.map(\.lineIndex) == [1, 3, 4, 5])
    }

    @Test func removingTheLastLineWithoutNewlineLeavesThePreviousTerminator() {
        var doc = KnownHostsDocument(parsing: "a ssh-ed25519 \(Self.ed)\nb ssh-ed25519 \(Self.ed)")
        doc.remove(lines: [1])
        #expect(doc.render() == "a ssh-ed25519 \(Self.ed)\n")
    }

    @Test func removingUnknownIndicesIsANoOp() {
        var doc = KnownHostsDocument(parsing: "a ssh-ed25519 \(Self.ed)\n")
        doc.remove(lines: [5, -1])
        #expect(doc.render() == "a ssh-ed25519 \(Self.ed)\n")
    }

    @Test func unparsableTextHasNoCarriageReturnInCRLFDocuments() {
        let doc = KnownHostsDocument(parsing: "garbage here\r\nmore garbage\r\n")
        #expect(doc.unparsableLines.map(\.text) == ["garbage here", "more garbage"])
        #expect(KnownHostsDocument.content(of: "abc\r\n") == "abc")
        #expect(KnownHostsDocument.content(of: "abc\n") == "abc")
        #expect(KnownHostsDocument.content(of: "abc") == "abc")
    }

    @Test func loneCarriageReturnRoundTrips() {
        let text = "a\rb ssh-ed25519 \(Self.ed)\nx\r\ny\r"
        #expect(KnownHostsDocument(parsing: text).render().utf8.elementsEqual(text.utf8))
    }

    @Test func nonASCIICommentIsKept() {
        let text = "example.com ssh-ed25519 \(Self.ed) tr: g\u{FC}venli \u{11F}\u{FC}\u{15F}\u{131}\u{F6}\u{E7}\n"
        let doc = KnownHostsDocument(parsing: text)
        #expect(doc.render() == text)
        #expect(doc.entries.first?.comment == "tr: g\u{FC}venli \u{11F}\u{FC}\u{15F}\u{131}\u{F6}\u{E7}")
    }

    @Test func whitespaceOnlyLinesAreBlank() {
        let doc = KnownHostsDocument(parsing: "   \n\t\t\n \t \r\n")
        #expect(doc.lines.map(\.kind) == [.blank, .blank, .blank])
    }

    @Test func commentWithCombiningMarkAfterHashIsAComment() {
        let doc = KnownHostsDocument(parsing: "#\u{301} x\n")
        #expect(doc.lines.map(\.kind) == [.comment])
    }
}
