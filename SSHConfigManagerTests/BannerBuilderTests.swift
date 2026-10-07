import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct BannerBuilderTests {
    @Test func missingFile() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp)
        #expect(BannerBuilder.banners(for: app.store) == [.missingFile, .notWatching])
    }

    @Test func notUTF8() throws {
        let tmp = try TempDir()
        try FileManager.default.createDirectory(at: tmp.url.appending(path: ".ssh"), withIntermediateDirectories: true)
        try Data([0x48, 0xFF]).write(to: tmp.url.appending(path: ".ssh/config"))
        let app = makeTestModel(tmp)
        #expect(BannerBuilder.banners(for: app.store).first == .notUTF8)
    }

    @Test func byteOrderMark() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "\u{FEFF}Host a\n")
        #expect(BannerBuilder.banners(for: app.store) == [.byteOrderMark, .notWatching])
    }

    @Test func externalChangeAppearsWithUnsavedEdits() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try app.store.apply { _ = try $0.addHost(HostDraft(patterns: ["b"])) }
        try tmp.file(".ssh/config", "Host z\n")
        // Simulate the watcher callback the same way ConfigStore does internally: a conflicting save.
        do { try await app.store.save() } catch {}
        #expect(BannerBuilder.banners(for: app.store).contains(.externalChange))
    }

    @Test func cleanLoadedFileWithWatcherHasNoBanners() throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/config", "Host a\n")
        let app = AppModel(settings: AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url),
                           backupRoot: tmp.url.appending(path: "Backups")) { url, backups, kind in
            ConfigStore(fileURL: url, writer: SafeFileWriter(backups: backups),
                        validator: ConfigValidator(runner: FixedRunner.valid),
                        includeResolver: IncludeResolver(homeDirectory: tmp.url), watchForChanges: true, backupKind: kind)
        }
        #expect(BannerBuilder.banners(for: app.store).isEmpty)
    }
}
