import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct KnownHostsModelTests {
    static let ed = "AAAAC3NzaC1lZDI1NTE5AAAAIPfUPYg1znbIXwm8qtmbk2fUgbpCS0X0aPBTqX90D7ND"
    static let ec = "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMZEF0uxfT/j/MUTD4m4qPdo0bZqQHln5x4cWOV5M4UIXrnccLQ7LCTyysxdMNqMwzrFAmCYRtST3B8qXQZPwx8="
    static let file = """
    web.example.com,192.0.2.10 ssh-ed25519 \(ed) deploy
    [db.example.com]:2222 ecdsa-sha2-nistp256 \(ec)
    |1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 \(ed)
    @cert-authority *.corp.example ssh-ed25519 \(ed)
    garbage

    """

    func make(_ tmp: TempDir) -> KnownHostsModel {
        _ = try? tmp.file(".ssh/known_hosts", Self.file)
        return KnownHostsModel(app: makeTestModel(tmp))
    }

    @Test func rowsShowEveryEntryAndUnparsableLine() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        #expect(model.rows.map(\.id) == [0, 1, 2, 3, 4])
        #expect(model.rows[0].hosts == "web.example.com, 192.0.2.10")
        #expect(model.rows[0].ports == "22")
        #expect(model.rows[0].fingerprint == "SHA256:la2oUdtS09OZ69kPsktdpFX2ayEAR71pQfHiCfcmpwQ")
        #expect(model.rows[0].comment == "deploy")
        #expect(model.rows[1].hosts == "db.example.com")
        #expect(model.rows[1].ports == "2222")
        #expect(model.rows[2].isHashed)
        #expect(model.rows[2].hosts == String(localized: "knownHosts.hashed"))
        #expect(model.rows[3].marker == "@cert-authority")
        #expect(model.rows[4].isUnparsable)
        #expect(model.rows[4].hosts == "garbage")
    }

    @Test func plainSearchIsASubstringMatch() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.searchText = "WEB."
        #expect(model.rows.map(\.id) == [0])
        model.searchText = "corp"
        #expect(model.rows.map(\.id) == [3])
        model.searchText = "192.0.2"
        #expect(model.rows.map(\.id) == [0])
        model.searchText = "SHA256:kmAs9"
        #expect(model.rows.map(\.id) == [1])
    }

    @Test func aHostLikeQueryAlsoFindsHashedEntries() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.searchText = "Example.COM"
        #expect(model.rows.map(\.id) == [0, 1, 2])   // web + db substring hits, and the hashed "example.com" ("*.corp.example" has no ".com")
        model.searchText = "example.com:22"
        #expect(model.rows.map(\.id) == [2])
        model.searchText = "example.com:2222"
        #expect(model.rows.isEmpty)
    }

    @Test func removalAsksThenDeletesTheSelectedLines() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [0, 4]
        model.requestRemoveSelection()
        #expect(model.pendingRemoval?.map(\.id) == [0, 4])
        model.confirmRemoval()
        #expect(model.pendingRemoval == nil)
        #expect(model.selection.isEmpty)
        let text = try tmp.read(".ssh/known_hosts")
        #expect(!text.contains("web.example.com"))
        #expect(!text.contains("garbage"))
        #expect(text.contains("db.example.com"))
        #expect(model.errorMessage == nil)
    }

    @Test func aReloadBetweenRequestAndConfirmDeletesNothing() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [0]
        model.requestRemoveSelection()
        try tmp.file(".ssh/known_hosts", "new.example.com ssh-ed25519 \(Self.ed)\n" + Self.file)
        model.app.knownHosts.load()   // what the file watcher does
        model.confirmRemoval()
        #expect(try tmp.read(".ssh/known_hosts").hasPrefix("new.example.com"))
        #expect(try tmp.read(".ssh/known_hosts").contains("web.example.com"))
        #expect(model.errorMessage == String(localized: "knownHosts.staleSelection"))
    }

    @Test func cancelKeepsTheFile() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [1]
        model.requestRemoveSelection()
        model.cancelRemoval()
        #expect(model.pendingRemoval == nil)
        #expect(try tmp.read(".ssh/known_hosts") == Self.file)
    }

    @Test func switchingTheFileBetweenRequestAndConfirmDeletesNothing() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        let otherURL = try tmp.file("other_known_hosts", Self.file)
        model.selection = [0]
        model.requestRemoveSelection()
        #expect(model.app.switchKnownHosts(to: otherURL.path))
        model.confirmRemoval()
        #expect(try tmp.read(".ssh/known_hosts") == Self.file)
        #expect(try String(contentsOf: otherURL, encoding: .utf8) == Self.file)
        #expect(model.errorMessage == String(localized: "knownHosts.staleSelection"))
        #expect(model.selection.isEmpty)
    }

    @Test func aReloadClearsTheSelectionSoNothingIsRequested() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [0]
        try tmp.file(".ssh/known_hosts", "new.example.com ssh-ed25519 \(Self.ed)\n" + Self.file)
        model.app.knownHosts.load()   // line 0 is now another host
        #expect(model.selection.isEmpty)
        model.requestRemoveSelection()
        #expect(model.pendingRemoval == nil)
        #expect(try tmp.read(".ssh/known_hosts").hasPrefix("new.example.com"))
    }

    @Test func onlyVisibleSelectedRowsAreRequested() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [0, 1]
        model.searchText = "web."
        model.requestRemoveSelection()
        #expect(model.pendingRemoval?.map(\.id) == [0])
        model.confirmRemoval()
        let text = try tmp.read(".ssh/known_hosts")
        #expect(!text.contains("web.example.com"))
        #expect(text.contains("[db.example.com]:2222"))
    }

    @Test func aStoreSwapClearsTheSelection() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        let otherURL = try tmp.file("other_known_hosts", Self.file)
        model.selection = [0, 1]
        #expect(model.selection == [0, 1])
        #expect(model.app.switchKnownHosts(to: otherURL.path))
        #expect(model.selection.isEmpty)
        model.requestRemoveSelection()
        #expect(model.pendingRemoval == nil)
    }

    @Test func theConfirmationListsHostsAndKeyTypes() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [0, 1, 4]
        model.requestRemoveSelection()
        #expect(model.pendingSummary == "web.example.com, 192.0.2.10  ssh-ed25519\ndb.example.com  ecdsa-sha2-nistp256\ngarbage")
    }

    @Test func aHostPortQueryFindsPlainBracketedEntries() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.searchText = "db.example.com:2222"
        #expect(model.rows.map(\.id) == [1])
        model.searchText = "[db.example.com]:2222"
        #expect(model.rows.map(\.id) == [1])
        model.searchText = "db.example.com:22"
        #expect(model.rows.isEmpty)
    }
}
