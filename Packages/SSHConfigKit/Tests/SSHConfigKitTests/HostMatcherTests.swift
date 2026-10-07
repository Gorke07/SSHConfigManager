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
        ("[example.com]:22", "example.com"),
        ("192.0.2.1", "192.0.2.1"),
        ("::1", "::1"),
        ("  example.com  ", "example.com"),
    ])
    func queriesThatLookLikeHosts(_ query: String, _ expected: String) {
        #expect(HostMatcher.lookupName(forQuery: query) == expected)
    }

    @Test(arguments: ["", "two words", "*.example.com", "example.com:abc", "[example.com", "a/b", "SHA256:abc", "..."])
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
}
