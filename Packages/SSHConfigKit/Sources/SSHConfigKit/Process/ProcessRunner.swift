import Foundation
import Synchronization

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult
}

/// Runs a process with stdin from /dev/null, `LC_ALL=C`, and a hard timeout
/// (SIGTERM, then SIGKILL after one second). Never logs arguments or environment:
/// they may contain passphrases.
public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env.merge(environment) { _, new in new }
        env["LC_ALL"] = "C"
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let box = Unchecked(process)
        let stdout = Buffer()
        let stderr = Buffer()
        let timedOut = Flag()
        let group = DispatchGroup()

        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            group.leave()
            throw error
        }

        // Drain both pipes concurrently so a full pipe buffer never blocks the child.
        for (pipe, buffer) in [(out, stdout), (err, stderr)] {
            group.enter()
            let reader = Unchecked(pipe.fileHandleForReading)
            DispatchQueue.global().async {
                buffer.set(reader.value.readDataToEndOfFile())
                group.leave()
            }
        }

        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            guard box.value.isRunning else { return }
            timedOut.set()
            box.value.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if box.value.isRunning { kill(box.value.processIdentifier, SIGKILL) }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { continuation.resume() }
        }

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout.string,
            stderr: stderr.string,
            timedOut: timedOut.isSet)
    }
}

/// `Mutex` is non-copyable and cannot be captured by escaping closures; wrap it in a class.
private final class Flag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
}

private final class Buffer: Sendable {
    private let data = Mutex(Data())
    func set(_ new: Data) { data.withLock { $0 = new } }
    var string: String { data.withLock { String(decoding: $0, as: UTF8.self) } }
}

/// Foundation's Process/FileHandle are thread-safe for the calls used here but not marked Sendable.
private final class Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
