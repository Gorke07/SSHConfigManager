import Foundation
import SSHConfigKit

/// A unique temporary directory that is removed when the object is released.
final class TempDir {
    let url: URL

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
