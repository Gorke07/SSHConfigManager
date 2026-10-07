import Foundation
import SSHConfigKit
@testable import SSH_Config_Manager

/// A unique temporary directory that is removed when the object is released.
final class TempDir {
    let url: URL
    /// An absolute-path suite name stores the plist inside the temp directory, not in ~/Library/Preferences.
    var defaultsSuiteName: String { url.appending(path: "defaults").path }

    /// A UserDefaults over a suite living in this temp directory (removed with it).
    lazy var defaults: UserDefaults = UserDefaults(suiteName: defaultsSuiteName)!

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SSHConfigManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ name: String, _ contents: String = "", permissions: Int = 0o600) throws -> URL {
        let target = url.appending(path: name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        return target
    }

    func read(_ name: String) throws -> String {
        String(decoding: try Data(contentsOf: url.appending(path: name)), as: UTF8.self)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// A ProcessRunning that returns a fixed result (lets tests control `ssh -G` validation).
struct FixedRunner: ProcessRunning {
    let result: ProcessResult

    static let valid = FixedRunner(result: ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false))
    static func invalid(_ message: String) -> FixedRunner {
        FixedRunner(result: ProcessResult(exitCode: 255, stdout: "", stderr: message, timedOut: false))
    }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        result
    }
}

/// A ProcessRunning that waits before answering (cancellable), for concurrency tests.
struct DelayedRunner: ProcessRunning {
    let delay: Duration
    let result: ProcessResult

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        try await Task.sleep(for: delay)
        return result
    }
}

/// An AppModel wired to a temporary home, temporary backups and fake ssh validation.
@MainActor
func makeTestModel(_ tmp: TempDir, config: String? = nil, runner: any ProcessRunning = FixedRunner.valid,
                   launcher: RecordingLauncher = RecordingLauncher(),
                   isTerminalInstalled: @escaping @MainActor (TerminalChoice) -> Bool = { _ in true }) -> AppModel {
    if let config { _ = try? tmp.file(".ssh/config", config) }
    let settings = AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url)
    return AppModel(
        settings: settings, backupRoot: tmp.url.appending(path: "Backups"),
        processRunner: runner,
        launcherFactory: { _ in launcher },
        isTerminalInstalled: isTerminalInstalled,
        makeStore: { url, backups, kind in
            ConfigStore(
                fileURL: url,
                writer: SafeFileWriter(backups: backups),
                validator: ConfigValidator(runner: runner),
                includeResolver: IncludeResolver(homeDirectory: tmp.url),
                watchForChanges: false,
                backupKind: kind)
        },
        makeKnownHostsStore: { url, backups, kind in
            KnownHostsStore(fileURL: url, writer: SafeFileWriter(backups: backups), watchForChanges: false, backupKind: kind)
        })
}

/// Records launch requests instead of opening a terminal. Tests must never open real terminals.
@MainActor
final class RecordingLauncher: TerminalLaunching {
    private(set) var requests: [LaunchRequest] = []
    var error: LaunchError?

    func launch(_ request: LaunchRequest) throws {
        if let error { throw error }
        requests.append(request)
    }
}
