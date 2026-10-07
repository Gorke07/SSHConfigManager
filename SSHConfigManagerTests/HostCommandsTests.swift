import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct HostCommandsTests {
    @Test func uniqueAliases() {
        let doc = ConfigDocument(parsing: "Host new-host\nHost new-host-2\nHost web\n")
        #expect(HostCommands.uniqueAlias("new-host", in: doc) == "new-host-3")
        #expect(HostCommands.uniqueAlias("other", in: doc) == "other")
        #expect(HostCommands.uniqueAlias("WEB", in: doc) == "WEB-2")   // ssh compares case-insensitively
    }

    @Test func addHostGoesBeforeHostStar() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n\nHost *\n  User d\n")
        let item = try HostCommands.addHost(to: app.store)
        #expect(item == .host(alias: "new-host", occurrence: 0))
        #expect(app.store.document.render() == "Host a\n\nHost new-host\n\nHost *\n  User d\n")
    }

    @Test func duplicateAndDelete() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n  User u\n")
        let copy = try #require(try HostCommands.duplicate(.host(alias: "web", occurrence: 0), in: app.store))
        #expect(copy == .host(alias: "web-copy", occurrence: 0))
        #expect(app.store.document.hosts.map(\.alias) == ["web", "web-copy"])

        try HostCommands.delete(.host(alias: "web", occurrence: 0), in: app.store)
        #expect(app.store.document.hosts.map(\.alias) == ["web-copy"])
        #expect(try HostCommands.duplicate(.match(index: 0), in: app.store) == nil)
    }

    @Test func sshCommandUsesBuilder() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n")
        #expect(HostCommands.sshCommand(for: .host(alias: "web", occurrence: 0), document: app.store.document, builder: app.commandBuilder) == "ssh -- web")
        #expect(HostCommands.sshCommand(for: .match(index: 0), document: app.store.document, builder: app.commandBuilder) == nil)
    }
}
