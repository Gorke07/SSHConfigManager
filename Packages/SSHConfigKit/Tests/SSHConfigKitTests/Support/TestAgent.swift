import Foundation

/// A private `ssh-agent -D` for tests. Its socket lives under /tmp with a short name (Unix socket
/// paths are limited to ~104 bytes); the process is terminated (by our own PID) on deinit.
final class TestAgent {
    let directory: URL
    let socket: String
    private let process = Process()

    init() throws {
        directory = URL(filePath: "/tmp/sshcm.\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        socket = directory.path + "/a"
        process.executableURL = URL(filePath: "/usr/bin/ssh-agent")
        process.arguments = ["-D", "-a", socket]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: socket) {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard FileManager.default.fileExists(atPath: socket) else {
            // Stop our own process (by handle) and clean up before reporting the failure.
            process.terminate()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: directory)
            throw Failure.socketNeverAppeared(socket)
        }
    }

    enum Failure: Error { case socketNeverAppeared(String) }

    deinit {
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: directory)
    }
}
