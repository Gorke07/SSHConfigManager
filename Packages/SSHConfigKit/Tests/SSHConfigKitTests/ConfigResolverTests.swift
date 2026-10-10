import Foundation
import Testing
@testable import SSHConfigKit

struct ConfigResolverTests {
    func resolve(_ text: String, _ alias: String, target: Int? = nil,
                 includes: @escaping (IncludeDirective) -> [(file: URL, document: ConfigDocument)] = { _ in [] }) -> ResolvedConfig {
        let doc = ConfigDocument(parsing: text)
        let header = target ?? doc.hosts.first { $0.alias == alias }?.headerLine
        return ConfigResolver.resolve(alias: alias, document: doc, targetHeader: header, includes: includes)
    }

    @Test(arguments: [
        ("*", "anything", true), ("web-*", "web-01", true), ("web-?", "web-1", true), ("web-?", "web-10", false),
        ("*.example.com", "a.example.com", true), ("WEB", "web", false), ("info*", "INFO-db", false),
    ])
    func wildcards(_ pattern: String, _ text: String, _ expected: Bool) {
        #expect(ConfigResolver.wildcardMatch(pattern, text) == expected)
    }

    @Test func negationExcludesAndNeedsAPositive() {
        #expect(ConfigResolver.hostLineMatches(["*", "!bastion"], alias: "web"))
        #expect(!ConfigResolver.hostLineMatches(["*", "!bastion"], alias: "bastion"))
        #expect(!ConfigResolver.hostLineMatches(["!bastion"], alias: "web"))
    }

    @Test func firstObtainedValueWinsAndSourcesAreReported() {
        let config = resolve("""
        User global-user
        Host *
          User star-user
          Port 2200
        Host web
          User web-user
          HostName 10.0.0.1
        Host web-*
          ForwardAgent yes

        """, "web")
        #expect(config.first("user") == ResolvedValue(value: "global-user", source: .global))
        #expect(config.first("port") == ResolvedValue(value: "2200", source: .otherHost(patterns: ["*"])))
        #expect(config.first("hostname") == ResolvedValue(value: "10.0.0.1", source: .thisBlock))
        #expect(config.first("forwardagent") == nil)
    }

    @Test func hostStarBeforeTheBlockWins() {
        let config = resolve("Host *\n  Port 22\nHost web\n  Port 2222\n", "web")
        #expect(config.first("port")?.source == .otherHost(patterns: ["*"]))
        #expect(config.first("port")?.value == "22")
    }

    @Test func multiValueKeysAccumulateInOrder() {
        let config = resolve("Host web\n  IdentityFile ~/.ssh/a\nHost *\n  IdentityFile ~/.ssh/b\n  LocalForward 8080 localhost:80\n", "web")
        #expect(config.options["identityfile"]?.map(\.value) == ["~/.ssh/a", "~/.ssh/b"])
        #expect(config.options["localforward"]?.count == 1)
    }

    @Test func matchBlocksAreSkippedButRecorded() {
        let config = resolve("Host web\n  User a\nMatch exec \"true\"\n  Port 99\n", "web")
        #expect(config.first("port") == nil)
        #expect(config.hasMatchBlocks)
    }

    @Test func includesAreProcessedInPlaceAndRestoreTheParentState() {
        let included = ConfigDocument(parsing: "Host web\n  User from-include\nHost other\n  Port 1\n")
        let file = URL(filePath: "/h/.ssh/conf.d/a")
        let config = resolve("Host web\n  HostName h\nInclude conf.d/*\n  Port 2\n", "web") { _ in [(file, included)] }
        #expect(config.first("user") == ResolvedValue(value: "from-include", source: .include(file: file, patterns: ["web"])))
        // After the Include, the parent's "Host web" block is active again: Port 2 applies.
        #expect(config.first("port")?.value == "2")
        #expect(config.first("port")?.source == .thisBlock)
    }

    @Test func turkishLocaleDoesNotAffectMatching() {
        #expect(ConfigResolver.wildcardMatch("İnfo", "info") == false)   // non-ASCII is compared exactly
        #expect(!ConfigResolver.wildcardMatch("INFO", "info"))
        #expect(ConfigResolver.wildcardMatch("info", "info"))
        #expect(!ConfigResolver.wildcardMatch("WEB", "web"))
    }

    @Test func setEnvIsSingleValued() {
        let config = resolve("Host web\n  SetEnv FOO=1\nHost *\n  SetEnv BAR=3\n", "web")
        #expect(config.options["setenv"]?.map(\.value) == ["FOO=1"])
    }

    @Test func selfIncludeTerminatesAndCountsOnce() {
        let file = URL(filePath: "/h/.ssh/conf.d/loop")
        let loop = ConfigDocument(parsing: "IdentityFile ~/.ssh/k\nInclude conf.d/loop\n")
        let config = resolve("Host web\n  Include conf.d/loop\n", "web") { _ in [(file, loop)] }
        #expect(config.options["identityfile"]?.count == 1)
    }

    @Test func includeInsideABlockInheritsItsPatterns() {
        let file = URL(filePath: "/h/.ssh/conf.d/a")
        let included = ConfigDocument(parsing: "User u\n")
        let config = resolve("Host web\n  Include conf.d/a\n", "web") { _ in [(file, included)] }
        #expect(config.first("user")?.source == .include(file: file, patterns: ["web"]))
        let top = resolve("Include conf.d/a\nHost web\n  Port 1\n", "web") { _ in [(file, included)] }
        #expect(top.first("user")?.source == .include(file: file, patterns: []))
    }

    @Test func identityFilesDeduplicate() {
        let config = resolve("Host web\n  IdentityFile ~/.ssh/a\nHost *\n  IdentityFile ~/.ssh/a\n  IdentityFile ~/.ssh/b\n", "web")
        #expect(config.options["identityfile"]?.map(\.value) == ["~/.ssh/a", "~/.ssh/b"])
    }

    @Test func sendEnvDashRemovesEarlierMatches() {
        let config = resolve("Host web\n  SendEnv LANG LC_ALL\n  SendEnv FOO\n  SendEnv -LC_*\n", "web")
        #expect(config.options["sendenv"]?.map(\.value).contains("-LC_*") == false)
    }

    @Test func sendEnvDashPatternRemovesAccumulatedValue() {
        let config = resolve("Host web\n  SendEnv LC_A\n  SendEnv FOO\n  SendEnv -LC_*\n", "web")
        #expect(config.options["sendenv"]?.map(\.value) == ["FOO"])
    }
}
