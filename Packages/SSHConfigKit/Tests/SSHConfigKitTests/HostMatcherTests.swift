import Foundation
import Testing
@testable import SSHConfigKit

struct HostMatcherTests {
    static let ed = KnownHostsDocumentTests.ed
    static let ec = KnownHostsDocumentTests.ec
    static let hashedExample = "|1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 \(ed)"
    static let hashedGit = "|1|2e88F0oZhjdk7AYBjB2yWxNkEpg=|+36JR+hdplXSdtbGuVpYTEQw0rw= ecdsa-sha2-nistp256 \(ec)"

    @Test func fingerprintsMatchSshKeygen() {
        #expect(Fingerprint.sha256(base64Key: Self.ed) == "SHA256:la2oUdtS09OZ69kPsktdpFX2ayEAR71pQfHiCfcmpwQ")
        #expect(Fingerprint.sha256(base64Key: Self.ec) == "SHA256:kmAs9qUu4Gav2S0iGxToGYV07zWdavw1l3vPHLV1Jdw")
        #expect(Fingerprint.sha256(base64Key: "not base64!") == nil)
    }

    @Test func lookupNameUsesSshForm() {
        #expect(HostMatcher.lookupName(host: "Example.COM", port: 22) == "example.com")
        #expect(HostMatcher.lookupName(host: "git.example.com", port: 2222) == "[git.example.com]:2222")
    }

    @Test(arguments: [
        ("example.com", "example.com"),
        ("Example.COM", "example.com"),
        ("example.com:22", "example.com"),
        ("example.com:2222", "[example.com]:2222"),
        ("[example.com]:2222", "[example.com]:2222"),
        ("[example.com]:22", "[example.com]:22"),
        ("192.0.2.1", "192.0.2.1"),
        ("::1", "::1"),
        ("2001:DB8::1", "2001:db8::1"),
        ("fe80::1:2", "fe80::1:2"),
        ("  example.com  ", "example.com"),
    ])
    func queriesThatLookLikeHosts(_ query: String, _ expected: String) {
        #expect(HostMatcher.lookupName(forQuery: query) == expected)
    }

    @Test(arguments: ["", "two words", "*.example.com", "example.com:abc", "[example.com", "a/b", "SHA256:abc", "...", "a:b:c", "1:2:3", "host:80:90", "::g"])
    func queriesThatDoNotLookLikeHosts(_ query: String) {
        #expect(HostMatcher.lookupName(forQuery: query) == nil)
    }

    @Test func hashedNamesMatchLikeSshKeygenF() {
        let doc = KnownHostsDocument(parsing: Self.hashedExample + "\n" + Self.hashedGit + "\n")
        #expect(HostMatcher.entries(in: doc, matchingAny: ["example.com"]).map(\.lineIndex) == [0])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["[git.example.com]:2222"]).map(\.lineIndex) == [1])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["git.example.com"]).isEmpty)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["example.org"]).isEmpty)
    }

    @Test func plainNamesMatchCaseInsensitivelyButPatternsNever() {
        let doc = KnownHostsDocument(parsing: """
        Example.com ssh-ed25519 \(Self.ed)
        *.example.com ssh-ed25519 \(Self.ed)
        !example.com ssh-ed25519 \(Self.ed)
        [example.com]:2222 ssh-ed25519 \(Self.ed)
        @cert-authority example.com ssh-ed25519 \(Self.ed)

        """)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["example.com"]).map(\.lineIndex) == [0])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["[example.com]:2222"]).map(\.lineIndex) == [3])
    }

    @Test func turkishLocaleDoesNotChangeMatching() {
        // "I" must lowercase to "i" (not "ı") whatever the user's locale is.
        #expect(HostMatcher.lookupName(host: "GITHUB.COM", port: 22) == "github.com")
        #expect(HostMatcher.lookupName(forQuery: "INFO.EXAMPLE.COM") == "info.example.com")
    }

    // MARK: - Against the real ssh-keygen, in a temporary directory only.

    @Test func agreesWithSshKeygenOnFreshKeys() async throws {
        let tmp = try TempDir()
        let runner = ProcessRunner()
        let keygen = URL(filePath: "/usr/bin/ssh-keygen")
        let key = tmp.url.appending(path: "k")
        let generated = try await runner.run(keygen, arguments: ["-q", "-t", "ed25519", "-N", "", "-C", "t", "-f", key.path],
                                             environment: [:], timeout: .seconds(30))
        #expect(generated.exitCode == 0)
        let pub = try tmp.read("k.pub").split(separator: " ")
        let type = String(pub[0]), blob = String(pub[1])

        let listed = try await runner.run(keygen, arguments: ["-lf", key.path + ".pub"], environment: [:], timeout: .seconds(30))
        #expect(String(listed.stdout.split(separator: " ")[1]) == Fingerprint.sha256(base64Key: blob))

        let hosts = try tmp.file("known_hosts", "host-a.example.com \(type) \(blob)\n[host-b.example.com]:2200 \(type) \(blob)\n")
        let hashed = try await runner.run(keygen, arguments: ["-H", "-f", hosts.path], environment: [:], timeout: .seconds(30))
        #expect(hashed.exitCode == 0)
        let doc = KnownHostsDocument(parsing: try tmp.read("known_hosts"))
        #expect(doc.entries.allSatisfy { $0.isHashed })
        #expect(HostMatcher.entries(in: doc, matchingAny: ["host-a.example.com"]).count == 1)
        #expect(HostMatcher.entries(in: doc, matchingAny: [HostMatcher.lookupName(host: "host-b.example.com", port: 2200)]).count == 1)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["host-c.example.com"]).isEmpty)
    }

    // Observed with the real ssh-keygen (macOS, temp file): `-F host` finds only the bare `host` line,
    // `-F '[host]:22'` only the literal `[host]:22` line, `-F '[host]:2222'` only that line; `-R` removes
    // exactly the lines `-F` finds. The same holds for hashed lines (`ssh-keygen -H`).
    @Test func bracketedPort22IsADifferentNameFromTheBareHost() {
        let doc = KnownHostsDocument(parsing: """
        host ssh-ed25519 \(Self.ed)
        [host]:22 ssh-ed25519 \(Self.ed)
        [host]:2222 ssh-ed25519 \(Self.ed)

        """)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["host"]).map(\.lineIndex) == [0])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["[host]:22"]).map(\.lineIndex) == [1])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["[host]:2222"]).map(\.lineIndex) == [2])
        // ssh connecting to port 22 looks up the bare name only.
        #expect(HostMatcher.lookupName(host: "host", port: 22) == "host")
    }

    // ssh-keygen -F host: `!host,host` is not found (a matching negation vetoes the line); `host,!other` is.
    @Test func aMatchingNegationOnTheSameLineVetoesIt() {
        let doc = KnownHostsDocument(parsing: """
        !host,host ssh-ed25519 \(Self.ed)
        host,!other ssh-ed25519 \(Self.ed)
        [h2]:2222,![h2]:2222 ssh-ed25519 \(Self.ed)

        """)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["host"]).map(\.lineIndex) == [1])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["other"]).isEmpty)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["[h2]:2222"]).isEmpty)
    }

    /// Real ssh-keygen on a temp file: `-F` reports `# Host x found: line N`; `-R` leaves the other lines.
    @Test func agreesWithSshKeygenOnLinesAndRemovals() async throws {
        let tmp = try TempDir()
        let runner = ProcessRunner()
        let keygen = URL(filePath: "/usr/bin/ssh-keygen")
        func keygenRun(_ args: [String]) async throws -> ProcessResult {
            try await runner.run(keygen, arguments: args, environment: [:], timeout: .seconds(30))
        }
        let key = tmp.url.appending(path: "k")
        #expect(try await keygenRun(["-q", "-t", "ed25519", "-N", "", "-f", key.path]).exitCode == 0)
        let pub = try tmp.read("k.pub").split(separator: " ")
        let line = "\(pub[0]) \(pub[1])"
        let lines = ["host", "[host]:22", "[host]:2222", "!host,host", "other,!gone", "Upper.Example"]
        let original = lines.map { "\($0) \(line)\n" }.joined()
        let queries: [(String, Int?)] = [("host", 1), ("[host]:22", 2), ("[host]:2222", 3), ("other", 5), ("gone", nil), ("upper.example", 6)]

        func check(_ file: URL, label: String) async throws {
            let document = KnownHostsDocument(parsing: try tmp.read(file.lastPathComponent))
            for (query, expectedLine) in queries {
                let found = try await keygenRun(["-F", query, "-f", file.path])
                let reported = found.stdout.split(separator: "\n")
                    .compactMap { $0.firstMatch(of: /found: line (\d+)/).map { Int($0.1)! } }
                #expect(found.exitCode == (expectedLine == nil ? 1 : 0), "\(label) \(query)")
                #expect(reported == expectedLine.map { [$0] } ?? [], "\(label) \(query)")
                let ours = HostMatcher.entries(in: document, matchingAny: [query]).map { $0.lineIndex + 1 }
                #expect(ours == expectedLine.map { [$0] } ?? [], "\(label) \(query)")
            }
        }

        let plain = try tmp.file("kh_plain", original)
        try await check(plain, label: "plain")
        // -R on a copy removes exactly the lines the app would delete.
        for (query, expectedLine) in queries {
            let copy = try tmp.file("kh_copy", original)
            let removed = try await keygenRun(["-R", query, "-f", copy.path])
            let document = KnownHostsDocument(parsing: original)
            let drop = Set(HostMatcher.entries(in: document, matchingAny: [query]).map(\.lineIndex))
            let expectedRemaining = original.split(separator: "\n", omittingEmptySubsequences: false).dropLast().enumerated()
                .filter { !drop.contains($0.offset) }.map { String($0.element) }
            let remaining = try tmp.read("kh_copy").split(separator: "\n").map(String.init)
            #expect(remaining == expectedRemaining, "-R \(query) (exit \(removed.exitCode))")
            #expect(drop.count == (expectedLine == nil ? 0 : 1))
        }

        // Hashed copy: the negation line is dropped by -H's rewrite only if ssh-keygen keeps it; compare -F again.
        let hashedFile = try tmp.file("kh_hashed", original)
        let hashed = try await keygenRun(["-H", "-f", hashedFile.path])
        #expect(hashed.exitCode == 0)
        let hashedDocument = KnownHostsDocument(parsing: try tmp.read("kh_hashed"))
        for (query, expectedLine) in queries where query != "gone" {
            let found = try await keygenRun(["-F", query, "-f", hashedFile.path])
            let reported = found.stdout.split(separator: "\n").compactMap { $0.firstMatch(of: /found: line (\d+)/).map { Int($0.1)! } }
            let ours = HostMatcher.entries(in: hashedDocument, matchingAny: [query]).map { $0.lineIndex + 1 }
            #expect(reported == ours, "hashed \(query) (was line \(String(describing: expectedLine)))")
        }
    }

    @Test func hashedBareAndBracketedPort22AreSeparateLikeSshKeygen() async throws {
        let tmp = try TempDir()
        let runner = ProcessRunner()
        let keygen = URL(filePath: "/usr/bin/ssh-keygen")
        let key = tmp.url.appending(path: "k")
        let made = try await runner.run(keygen, arguments: ["-q", "-t", "ed25519", "-N", "", "-f", key.path], environment: [:], timeout: .seconds(30))
        #expect(made.exitCode == 0)
        let pub = try tmp.read("k.pub").split(separator: " ")
        let line = "\(pub[0]) \(pub[1])"
        let file = try tmp.file("kh", "host \(line)\n[host]:22 \(line)\n[host]:2222 \(line)\n")
        for (query, expected) in [("host", [0]), ("[host]:22", [1]), ("[host]:2222", [2])] {
            let found = try await runner.run(keygen, arguments: ["-F", query, "-f", file.path], environment: [:], timeout: .seconds(30))
            let plain = KnownHostsDocument(parsing: try tmp.read("kh"))
            #expect(found.stdout.contains(query + " "))
            #expect(HostMatcher.entries(in: plain, matchingAny: [query]).map(\.lineIndex) == expected)
        }
        let rehash = try await runner.run(keygen, arguments: ["-H", "-f", file.path], environment: [:], timeout: .seconds(30))
        #expect(rehash.exitCode == 0)
        let hashed = KnownHostsDocument(parsing: try tmp.read("kh"))
        #expect(hashed.entries.allSatisfy { $0.isHashed })
        for (query, expected) in [("host", [0]), ("[host]:22", [1]), ("[host]:2222", [2])] {
            #expect(HostMatcher.entries(in: hashed, matchingAny: [query]).map(\.lineIndex) == expected)
        }
    }
}
