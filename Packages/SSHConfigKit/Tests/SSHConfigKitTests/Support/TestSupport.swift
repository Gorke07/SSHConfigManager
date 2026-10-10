import Foundation
import Synchronization
@testable import SSHConfigKit

/// A unique temporary directory that is removed when the object is released.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SSHConfigKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Creates (or overwrites) a file inside the directory and returns its URL.
    @discardableResult
    func file(_ name: String, _ contents: String = "", permissions: Int = 0o600) throws -> URL {
        let target = url.appending(path: name)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        return target
    }

    func read(_ name: String) throws -> String {
        let data = try Data(contentsOf: url.appending(path: name))
        return String(decoding: data, as: UTF8.self)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Deterministic RNG for reproducible randomized tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class TestClock: Sendable {
    private let current: Mutex<Date>
    init(_ start: Date) { current = Mutex(start) }
    var now: Date { current.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 += seconds } }
}

final class FakeRunner: ProcessRunning {
    struct Invocation: Sendable {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
        let timeout: Duration
    }

    struct State {
        var invocations: [Invocation] = []
        var calls: [[String]] = []
        var running = 0
        var maxRunning = 0
    }

    private let state = Mutex(State())
    private let respond: @Sendable ([String]) -> ProcessResult
    private let delay: Duration

    init(delay: Duration = .zero, respond: @escaping @Sendable ([String]) -> ProcessResult) {
        self.delay = delay
        self.respond = respond
    }

    var calls: [[String]] { state.withLock { $0.calls } }
    var invocations: [Invocation] { state.withLock { $0.invocations } }
    var maxConcurrent: Int { state.withLock { $0.maxRunning } }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        state.withLock {
            $0.calls.append(arguments)
            $0.invocations.append(Invocation(executable: executable, arguments: arguments, environment: environment, timeout: timeout))
            $0.running += 1
            $0.maxRunning = max($0.maxRunning, $0.running)
        }
        defer { state.withLock { $0.running -= 1 } }
        if delay > .zero { try await Task.sleep(for: delay) }
        return respond(arguments)
    }
}

/// Always throws, like an ssh that cannot be launched.
struct ThrowingRunner: ProcessRunning {
    struct Failure: Error {}
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        throw Failure()
    }
}

/// Signals when a run starts and keeps it pending until the test calls `release()`.
final class GatedRunner: ProcessRunning {
    let entered: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private let released: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation
    private let calls = Mutex<[[String]]>([])

    init() {
        (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
        (released, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    var arguments: [[String]] { calls.withLock { $0 } }

    /// Suspends until `count` runs have started (one iterator, so entries are never lost between waits).
    /// Callers carry `.timeLimit`, since this waits on an external signal.
    func waitUntilEntered(count: Int = 1) async {
        var seen = 0
        for await _ in entered {
            seen += 1
            if seen >= count { return }
        }
    }

    func release() { releaseContinuation.yield() }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        calls.withLock { $0.append(arguments) }
        enteredContinuation.yield()
        for await _ in released { break }
        return ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
    }
}
