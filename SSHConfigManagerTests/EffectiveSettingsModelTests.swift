import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct EffectiveSettingsModelTests {
    @Test func sourcesComeFromTheResolverAndValuesFromSshG() throws {
        let doc = ConfigDocument(parsing: "Host *\n  User star\nHost web\n  HostName Example.COM\n  Port 2222\n")
        let resolved = ConfigResolver.resolve(alias: "web", document: doc, targetHeader: 2, includes: { _ in [] })
        let options = EffectiveOptions(parsing: "user star\nhostname example.com\nport 2222\nforwardagent no\nidentityfile ~/.ssh/id_rsa\n")
        let rows = EffectiveSettingsBuilder.rows(alias: "web", options: options, resolved: resolved, home: URL(filePath: "/h"), showAll: false)
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
        #expect(byKey["user"]?.source == .otherHost(["*"]))
        #expect(byKey["hostname"]?.source == .thisBlock)
        #expect(byKey["port"]?.source == .thisBlock)
        #expect(byKey["forwardagent"]?.source == .defaultValue)
        #expect(byKey["identityfile"]?.source == .defaultValue)
    }

    @Test func mismatchesWithAMatchBlockAreUncertain() {
        let doc = ConfigDocument(parsing: "Host web\n  Port 22\nMatch exec true\n  User m\n")
        let resolved = ConfigResolver.resolve(alias: "web", document: doc, targetHeader: 0, includes: { _ in [] })
        let options = EffectiveOptions(parsing: "port 2200\nuser m\n")
        let rows = EffectiveSettingsBuilder.rows(alias: "web", options: options, resolved: resolved, home: URL(filePath: "/h"), showAll: false)
        #expect(rows.first { $0.key == "port" }?.source == .uncertain)
        #expect(rows.first { $0.key == "user" }?.source == .uncertain)
    }

    @Test func identityFilesCompareAfterTildeExpansion() {
        let doc = ConfigDocument(parsing: "Host web\n  IdentityFile ~/.ssh/k\n")
        let resolved = ConfigResolver.resolve(alias: "web", document: doc, targetHeader: 0, includes: { _ in [] })
        let options = EffectiveOptions(parsing: "identityfile /h/.ssh/k\n")
        let row = EffectiveSettingsBuilder.rows(alias: "web", options: options, resolved: resolved, home: URL(filePath: "/h"), showAll: false).first { $0.key == "identityfile" }
        #expect(row?.source == .thisBlock)
    }

    @Test func showAllAddsTheRemainingKeysSorted() {
        let options = EffectiveOptions(parsing: "hostname h\nzz z\naa a\n")
        let rows = EffectiveSettingsBuilder.rows(alias: "w", options: options, resolved: ResolvedConfig(), home: URL(filePath: "/h"), showAll: true)
        #expect(rows.map(\.key).suffix(2) == ["aa", "zz"])
    }

    @Test func appResolvesSavedHostsFollowingIncludes() throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/extra.conf", "Host inc\n  Port 2201\n")
        let app = makeTestModel(tmp, config: "Include extra.conf\nHost web\n  User u\n")
        let web = try #require(app.resolvedConfig(forSavedAlias: "web"))
        #expect(web.first("user")?.source == .thisBlock)
        let inc = try #require(app.resolvedConfig(forSavedAlias: "inc"))
        #expect(inc.first("port")?.value == "2201")
        #expect(app.resolvedConfig(forSavedAlias: "missing") == nil)
    }
}
