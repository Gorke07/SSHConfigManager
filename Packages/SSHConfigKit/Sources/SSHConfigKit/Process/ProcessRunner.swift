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
///
/// The child is started with `posix_spawn` as the leader of its own process group, so
/// cancel and timeout signal the whole group (`kill(-pgid, ...)`): grandchildren of a
/// killed `ssh` (ProxyCommand, ControlMaster helpers) do not survive it.
public struct ProcessRunner: ProcessRunning {
    /// How long a SIGTERMed group gets before SIGKILL.
    static let killGrace: Double = 1

    public init() {}

    public func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        var env = ProcessInfo.processInfo.environment
        env.merge(environment) { _, new in new }
        env["LC_ALL"] = "C"

        let state = RunState()
        let pid = try Self.spawn(path: executable.path, arguments: arguments, environment: env, state: state)

        // The leader's pid is the group id. Only this group is ever signalled.
        let signalGroup: @Sendable (Int32) -> Void = { signal in
            guard pid > 1 else { return }
            kill(-pid, signal)
        }
        let escalate: @Sendable () -> Void = {
            guard state.beginTermination() else { return }
            signalGroup(SIGTERM)
            // Unconditional: the leader may be gone while a TERM-ignoring grandchild is not.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGrace) { signalGroup(SIGKILL) }
        }

        // Reap off the main actor.
        DispatchQueue.global().async {
            var status: Int32 = 0
            var result: pid_t
            repeat { result = waitpid(pid, &status, 0) } while result < 0 && errno == EINTR
            let code: Int32
            if result < 0 {
                code = -1
            } else if status & 0x7f == 0 {
                code = (status >> 8) & 0xff   // exited
            } else {
                code = status & 0x7f           // terminated by signal: the signal number, as Process reported
            }
            state.markExited(status: code)
            // Grace period: a grandchild may still hold the pipes open.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { state.finish(.grace) }
        }

        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            guard !state.hasExited else { return }
            state.markTimedOut()
            escalate()
        }
        // Hard deadline: never hang, whatever the child or its descendants do.
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds + 3) { state.finish(.hard) }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProcessResult, Never>) in
                state.install(continuation)
            }
        } onCancel: {
            if !state.hasExited { escalate() }
        }
    }

    /// Starts the child in its own process group with stdin from /dev/null and stdout/stderr
    /// on pipes that `state` drains concurrently. Returns the child's pid.
    private static func spawn(path: String, arguments: [String], environment: [String: String], state: RunState) throws -> pid_t {
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard pipe(&errPipe) == 0 else {
            let code = errno
            close(outPipe[0]); close(outPipe[1])
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        // Darwin has no pipe2(O_CLOEXEC), so FD_CLOEXEC is set right after pipe(). The window is
        // harmless: every child this runner spawns uses POSIX_SPAWN_CLOEXEC_DEFAULT (only the three
        // fds named in the file actions are inherited, whatever their flags), and this runner is the
        // only code in the package that spawns processes.
        // Parent ends: non-blocking (read through dispatch sources).
        for fd in [outPipe[0], errPipe[0], outPipe[1], errPipe[1]] {
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        }
        for fd in [outPipe[0], errPipe[0]] {
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        // New process group (pgid = child's pid); only the three standard fds are inherited;
        // default signal dispositions and an empty mask.
        var defaults = sigset_t()
        sigfillset(&defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        let argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        close(outPipe[1])
        close(errPipe[1])
        guard rc == 0 else {
            close(outPipe[0]); close(errPipe[0])
            throw POSIXError(POSIXErrorCode(rawValue: rc) ?? .EIO)
        }

        // Drain with dispatch sources (not blocking reads): a grandchild that inherits the
        // pipe can keep it open forever, so EOF alone must never gate completion.
        let sources = [(outPipe[0], true), (errPipe[0], false)].map { fd, isOut in
            makeReader(fd: fd, isOut: isOut, state: state)
        }
        let box = Unchecked(sources)
        state.onFinish = { for source in box.value { source.cancel() } }
        for source in sources { source.resume() }
        return pid
    }

    private static func makeReader(fd: Int32, isOut: Bool, state: RunState) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global())
        let weakBox = Unchecked(source)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count > 0 {
                    state.append(Data(buffer[0..<count]), isOut)
                    continue
                }
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) { return }
                weakBox.value.cancel()   // EOF or hard error
                state.eof(isOut)
                return
            }
        }
        source.setCancelHandler { close(fd) }
        return source
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
        var terminating = false
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

    var hasExited: Bool { inner.withLock { $0.exited } }

    /// True for the first caller only: SIGTERM and the SIGKILL escalation are sent once.
    func beginTermination() -> Bool {
        inner.withLock { s in
            if s.terminating { return false }
            s.terminating = true
            return true
        }
    }

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
