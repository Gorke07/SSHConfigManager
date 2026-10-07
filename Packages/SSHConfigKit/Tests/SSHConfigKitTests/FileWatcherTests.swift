import Foundation
import Testing
@testable import SSHConfigKit

struct FileWatcherTests {
    /// Waits up to `timeout` for the stream to yield once.
    private func firstEvent(_ stream: AsyncStream<Void>, timeout: Duration = .seconds(5)) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test func reportsInPlaceWrites() async throws {
        let tmp = try TempDir()
        let file = try tmp.file("config", "a")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let watcher = FileWatcher(directory: tmp.url.resolvingSymlinksInPath()) { continuation.yield() }
        try await Task.sleep(for: .milliseconds(300))

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("b".utf8))
        try handle.close()

        #expect(await firstEvent(stream))
        withExtendedLifetime(watcher) {}
    }

    @Test func reportsAtomicReplacement() async throws {
        let tmp = try TempDir()
        let file = try tmp.file("config", "a")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let watcher = FileWatcher(directory: tmp.url.resolvingSymlinksInPath()) { continuation.yield() }
        try await Task.sleep(for: .milliseconds(300))

        try Data("b".utf8).write(to: file, options: .atomic)

        #expect(await firstEvent(stream))
        withExtendedLifetime(watcher) {}
    }
}
