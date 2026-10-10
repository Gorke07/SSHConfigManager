import Foundation
import Darwin
import Testing
@testable import SSHConfigKit

struct IncludeResolverTests {
    @Test func relativeIncludesResolveAgainstDotSSHInGlobOrder() throws {
        let home = try TempDir()
        try home.file(".ssh/config.d/b.conf", "Host b\n")
        try home.file(".ssh/config.d/a.conf", "Host a\n  User u\n")
        let resolver = IncludeResolver(homeDirectory: home.url)
        let hosts = resolver.includedHosts(of: ConfigDocument(parsing: "Include config.d/*.conf\n"), rootFile: nil)
        #expect(hosts.map(\.entry.alias) == ["a", "b"])
        #expect(hosts.first?.entry.value(for: "User") == "u")
        #expect(hosts.first?.file.lastPathComponent == "a.conf")
    }

    @Test func fifoInAnIncludeGlobIsSkippedWithoutBlocking() throws {
        let home = try TempDir()
        try home.file(".ssh/config.d/a.conf", "Host a\n")
        #expect(Darwin.mkfifo(home.url.appending(path: ".ssh/config.d/b.conf").path, 0o600) == 0)
        try home.file(".ssh/config.d/c.conf", "Host c\n")
        let resolver = IncludeResolver(homeDirectory: home.url)
        let doc = ConfigDocument(parsing: "Include config.d/*.conf\n")
        #expect(resolver.includedHosts(of: doc, rootFile: nil).map(\.entry.alias) == ["a", "c"])
        #expect(resolver.includedDocuments(for: doc.includes[0]).count == 2)
        let states = resolver.includeFileStates(of: doc, rootFile: nil)
        #expect(states.count == 3)
        #expect(states.filter { $0.text == nil }.count == 1)
    }

    @Test func tildeAndAbsolutePaths() throws {
        let home = try TempDir()
        let absolute = try home.file("elsewhere/x", "Host abs\n")
        try home.file("work/ssh", "Host tilde\n")
        let doc = ConfigDocument(parsing: "Include ~/work/ssh \(absolute.path)\n")
        let hosts = IncludeResolver(homeDirectory: home.url).includedHosts(of: doc, rootFile: nil)
        #expect(hosts.map(\.entry.alias) == ["tilde", "abs"])
    }

    @Test func nestedIncludesAndCyclesTerminate() throws {
        let home = try TempDir()
        try home.file(".ssh/one", "Host one\nInclude two\n")
        try home.file(".ssh/two", "Host two\nInclude one\n")
        let hosts = IncludeResolver(homeDirectory: home.url)
            .includedHosts(of: ConfigDocument(parsing: "Include one\n"), rootFile: nil)
        #expect(hosts.map(\.entry.alias) == ["one", "two"])
    }

    @Test func rootFileIsNotListedAgain() throws {
        let home = try TempDir()
        let root = try home.file(".ssh/config", "Host root\nInclude config\n")
        let doc = ConfigDocument(parsing: try home.read(".ssh/config"))
        #expect(IncludeResolver(homeDirectory: home.url).includedHosts(of: doc, rootFile: root).isEmpty)
    }

    @Test func depthLimitStopsRecursion() throws {
        let home = try TempDir()
        for i in 0..<5 { try home.file(".ssh/f\(i)", "Host h\(i)\nInclude f\(i + 1)\n") }
        let hosts = IncludeResolver(homeDirectory: home.url, maxDepth: 3)
            .includedHosts(of: ConfigDocument(parsing: "Include f0\n"), rootFile: nil)
        #expect(hosts.map(\.entry.alias) == ["h0", "h1", "h2"])
    }

    @Test func missingAndNonUTF8FilesAreSkipped() throws {
        let home = try TempDir()
        let bad = home.url.appending(path: ".ssh/bad")
        try FileManager.default.createDirectory(at: bad.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x48, 0x6F, 0x73, 0x74, 0x20, 0xFF, 0xFE]).write(to: bad)
        let hosts = IncludeResolver(homeDirectory: home.url)
            .includedHosts(of: ConfigDocument(parsing: "Include missing bad\n"), rootFile: nil)
        #expect(hosts.isEmpty)
    }
}
