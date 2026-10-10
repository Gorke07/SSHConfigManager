import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

struct SidebarBuilderTests {
    let doc = ConfigDocument(parsing: """
    Host web
      HostName 10.0.0.1
      User deploy
    Host web
      HostName 10.0.0.2
    Host db
      HostName db.İstanbul.example
      User Gökhan
    Host *.prod
      User ops
    Match host x
      Port 2200

    """)

    let included = [IncludedHost(
        file: URL(filePath: "/h/.ssh/config.d/work"),
        entry: HostEntry(headerLine: 0, patterns: ["vpn"], directives: [HostDirective(line: 1, key: "HostName", value: "vpn.example")]))]

    @Test func groupsRowsBySection() {
        let sections = SidebarBuilder.sections(document: doc, included: included, search: "")
        #expect(sections.hosts.map(\.item) == [
            .host(alias: "web", occurrence: 0), .host(alias: "web", occurrence: 1), .host(alias: "db", occurrence: 0),
        ])
        #expect(sections.patterns.map(\.title) == ["*.prod"])
        #expect(sections.included.map(\.item) == [.included(id: "/h/.ssh/config.d/work#0")])
        #expect(sections.included.first?.subtitle == "work")
        #expect(sections.matches.map(\.item) == [.match(index: 0)])
        #expect(sections.matches.first?.title == "Match host x")
    }

    @Test func subtitles() {
        let sections = SidebarBuilder.sections(document: doc, included: [], search: "")
        #expect(sections.hosts.map(\.subtitle) == ["deploy@10.0.0.1", "10.0.0.2", "Gökhan@db.İstanbul.example"])
    }

    @Test func duplicateAliasesResolveToTheirOwnBlocks() throws {
        let second = try #require(SidebarBuilder.hostEntry(for: .host(alias: "web", occurrence: 1), in: doc))
        #expect(second.value(for: "HostName") == "10.0.0.2")
        #expect(SidebarBuilder.item(forHeader: second.headerLine, in: doc) == .host(alias: "web", occurrence: 1))
        #expect(SidebarBuilder.hostEntry(for: .host(alias: "web", occurrence: 2), in: doc) == nil)
    }

    @Test(arguments: [
        ("deploy", ["web"]),
        ("10.0.0", ["web", "web"]),
        ("gokhan", ["db"]),          // diacritic-insensitive
        ("istanbul", ["db"]),        // case/diacritic-insensitive on İ
        ("WEB", ["web", "web"]),
        ("   ", ["web", "web", "db"]),
    ])
    func searchFiltersHosts(query: String, expected: [String]) {
        let sections = SidebarBuilder.sections(document: doc, included: [], search: query)
        #expect(sections.hosts.map(\.title) == expected)
    }

    @Test func searchKeepsTheOccurrenceIndexOfTheHostThatSurvives() {
        // "10.0.0.2" only matches the second "web" block; its item must still say occurrence 1.
        let sections = SidebarBuilder.sections(document: doc, included: [], search: "10.0.0.2")
        #expect(sections.hosts.map(\.item) == [.host(alias: "web", occurrence: 1)])
        #expect(sections.hosts.map(\.subtitle) == ["10.0.0.2"])
    }

    @Test func searchAlsoFiltersPatternsIncludedAndMatches() {
        let sections = SidebarBuilder.sections(document: doc, included: included, search: "vpn")
        #expect(sections.hosts.isEmpty)
        #expect(sections.patterns.isEmpty)
        #expect(sections.included.count == 1)
        #expect(sections.matches.isEmpty)
    }

    @Test func lookupHelpers() {
        #expect(SidebarBuilder.includedHost(for: .included(id: "/h/.ssh/config.d/work#0"), in: included)?.entry.alias == "vpn")
        #expect(SidebarBuilder.matchEntry(for: .match(index: 0), in: doc)?.criteria == "host x")
        #expect(SidebarBuilder.matchEntry(for: .match(index: 5), in: doc) == nil)
        #expect(SidebarBuilder.hostEntry(for: .match(index: 0), in: doc) == nil)
    }

    @Test func hostsAreGroupedAlphabeticallyWithUngroupedLast() {
        let doc = ConfigDocument(parsing: "# group: Staging\nHost s1\n# group: Prod\nHost p1\nHost loose\n# group: Prod\nHost p2\nHost *\n")
        let sections = SidebarBuilder.sections(document: doc, included: [], search: "")
        #expect(sections.hostGroups.map(\.name) == ["Prod", "Staging", nil])
        #expect(sections.hostGroups.map { $0.rows.map(\.title) } == [["p1", "p2"], ["s1"], ["loose"]])
        #expect(sections.hosts.count == 4)
        #expect(sections.patterns.map(\.title) == ["*"])
    }

    @Test func noGroupsMeansOneUnnamedGroup() {
        let sections = SidebarBuilder.sections(document: ConfigDocument(parsing: "Host a\nHost b\n"), included: [], search: "")
        #expect(sections.hostGroups.map(\.name) == [nil])
    }
}
