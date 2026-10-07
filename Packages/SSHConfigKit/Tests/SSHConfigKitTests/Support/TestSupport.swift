import Foundation
import Synchronization

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
