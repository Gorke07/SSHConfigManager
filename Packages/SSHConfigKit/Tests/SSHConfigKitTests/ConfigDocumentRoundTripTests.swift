import Testing
@testable import SSHConfigKit

struct ConfigDocumentRoundTripTests {
    static let samples: [String] = [
        "",
        "\n",
        "\n\n",
        "Host a",
        "Host a\n",
        "Host a\n  HostName b\n",
        "# global\nUser me\n\nHost *\n    ServerAliveInterval 30\n",
        "Host web\r\n\tHostName 10.0.0.1\r\n",
        "Host a\r\n  User x\n  Port 22\r\n",
        "\u{FEFF}Host bom\n  HostName x\n",
        "Host=eq\n  User = me\n  Port=22\n",
        "Host \"quoted name\"\n  IdentityFile \"~/My Keys/id\" # yorum\n",
        "Match exec \"test -f /tmp/x\"\n  User y\n",
        "Include ~/.ssh/config.d/*\n",
        "Host ünicode-çğış\n  User Gökhan\n",
        "=garbage\n   \t  \nHo:st weird\n",
        "Host e\u{301}\n",
        "trailing spaces   \n\t\n",
        "\r\n\r\n",
    ]

    @Test(arguments: samples)
    func renderIsByteIdentical(text: String) {
        let doc = ConfigDocument(parsing: text)
        #expect(Array(doc.render().utf8) == Array(text.utf8))
    }

    @Test func randomMixesRoundTrip() {
        var rng = SplitMix64(seed: 42)
        let pool = [
            "Host a", "  HostName h", "\tUser=u", "# c", "", "   ", "Match all", "Include x/*",
            "=bad", "IdentityFile \"a b\" # k", "Port 22 #x", "\u{FEFF}Host bom", "Host e\u{301}",
        ]
        let endings = ["\n", "\r\n"]
        for _ in 0..<500 {
            let count = Int.random(in: 0...12, using: &rng)
            var text = ""
            for index in 0..<count {
                text += pool.randomElement(using: &rng)!
                if index < count - 1 || Bool.random(using: &rng) {
                    text += endings.randomElement(using: &rng)!
                }
            }
            let rendered = ConfigDocument(parsing: text).render()
            #expect(Array(rendered.utf8) == Array(text.utf8), "girdi: \(text.debugDescription)")
        }
    }

    @Test func lineKinds() {
        let doc = ConfigDocument(parsing: "# c\nUser me\n\nHOST web *.x\n  HostName h\nMatch host x\nInclude a \"b c\"\n=?\n")
        #expect(doc.lines.map(\.kind) == [
            .comment,
            .directive(key: "User", value: "me"),
            .blank,
            .hostStart(patterns: ["web", "*.x"]),
            .directive(key: "HostName", value: "h"),
            .matchStart(criteria: "host x"),
            .include(paths: ["a", "b c"]),
            .unknown,
        ])
    }

    @Test func byteOrderMarkIsKeptAndSeenAsSshSeesIt() {
        var doc = ConfigDocument(parsing: "\u{FEFF}Host bom\n")
        #expect(doc.hasByteOrderMark)
        // OpenSSH rejects "\u{FEFF}Host"; we show the line as not understood instead of hiding the problem.
        #expect(doc.lines.first?.kind == .unknown)

        doc.removeByteOrderMark()

        #expect(!doc.hasByteOrderMark)
        #expect(doc.lines.first?.kind == .hostStart(patterns: ["bom"]))
        #expect(Array(doc.render().utf8) == Array("Host bom\n".utf8))
    }

    @Test func detectsCRLFAndTrailingNewline() {
        #expect(ConfigDocument(parsing: "Host a\r\n").usesCRLF)
        #expect(!ConfigDocument(parsing: "Host a\n").usesCRLF)
        #expect(ConfigDocument(parsing: "Host a\n").hasTrailingNewline)
        #expect(!ConfigDocument(parsing: "Host a").hasTrailingNewline)
        #expect(ConfigDocument(parsing: "").lines.isEmpty)
        #expect(ConfigDocument(parsing: "Host a\r\n").lineEndingSuffix == "\r")
    }
}
