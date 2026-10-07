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
        let state = RunState()

        // Drain with readability handlers (not blocking reads): a grandchild that inherits
        // the pipe can keep it open forever, so EOF alone must never gate completion.
        for (pipe, isOut) in [(out, true), (err, false)] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    state.eof(isOut)
                } else {
                    state.append(data, isOut)
                }
            }
        }
        let handles = Unchecked([out.fileHandleForReading, err.fileHandleForReading])
        state.onFinish = { for h in handles.value { h.readabilityHandler = nil } }

        process.terminationHandler = { proc in
            state.markExited(status: proc.terminationStatus)
            // Grace period: a grandchild may still hold the pipes open.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { state.finish(.grace) }
        }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            for h in handles.value { h.readabilityHandler = nil }
            throw error
        }

        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            guard box.value.isRunning else { return }
            state.markTimedOut()
            box.value.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if box.value.isRunning { kill(box.value.processIdentifier, SIGKILL) }
            }
        }
        // Hard deadline: never hang, whatever the child or its descendants do.
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds + 3) { state.finish(.hard) }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProcessResult, Never>) in
                state.install(continuation)
            }
        } onCancel: {
            if box.value.isRunning { box.value.terminate() }
        }
    }
}

/// All mutable run state behind one lock. The continuation is resumed exactly once.
private final class RunState: Sendable {
    enum Mode { case normal, grace, hard }

    private struct Inner {
        var stdout = Data()
        var stderr = Data()
        var outEOF = false
        var errEOF = false
        var exited = false
        var status: Int32 = -1
        var timedOut = false
        var forced = false
        var hard = false
        var finished = false
        var continuation: CheckedContinuation<ProcessResult, Never>?
    }

    private let inner = Mutex(Inner())
    nonisolated(unsafe) var onFinish: (@Sendable () -> Void)?

    func append(_ data: Data, _ isOut: Bool) {
        inner.withLock { if isOut { $0.stdout.append(data) } else { $0.stderr.append(data) } }
    }

    func eof(_ isOut: Bool) {
        inner.withLock { if isOut { $0.outEOF = true } else { $0.errEOF = true } }
        finish(.normal)
    }

    func markExited(status: Int32) {
        inner.withLock { $0.exited = true; $0.status = status }
        finish(.normal)
    }

    func markTimedOut() { inner.withLock { $0.timedOut = true } }

    func install(_ continuation: CheckedContinuation<ProcessResult, Never>) {
        inner.withLock { $0.continuation = continuation }
        finish(.normal)
    }

    func finish(_ mode: Mode) {
        let resume: (CheckedContinuation<ProcessResult, Never>, ProcessResult)? = inner.withLock { s in
            if mode == .grace { s.forced = true }
            if mode == .hard { s.hard = true }
            guard !s.finished, let continuation = s.continuation else { return nil }
            guard s.hard || (s.exited && ((s.outEOF && s.errEOF) || s.forced)) else { return nil }
            s.finished = true
            s.continuation = nil
            let result = ProcessResult(
                exitCode: s.exited ? s.status : -1,
                stdout: String(decoding: s.stdout, as: UTF8.self),
                stderr: String(decoding: s.stderr, as: UTF8.self),
                timedOut: s.timedOut)
            return (continuation, result)
        }
        guard let (continuation, result) = resume else { return }
        onFinish?()
        continuation.resume(returning: result)
    }
}

/// Foundation's Process/FileHandle are thread-safe for the calls used here but not marked Sendable.
private final class Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
