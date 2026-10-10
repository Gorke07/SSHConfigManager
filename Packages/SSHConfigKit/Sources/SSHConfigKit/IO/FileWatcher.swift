import CoreServices
import Foundation

/// Watches a directory with FSEvents (file-level events), so both in-place writes and
/// atomic rename-replacements of files inside it are reported. Callers filter by
/// comparing fingerprints; this class only says "something changed".
public final class FileWatcher: @unchecked Sendable {
    /// Kept alive by the FSEvents stream (retain/release context callbacks), so the
    /// callback never touches `FileWatcher` itself.
    private final class CallbackBox: @unchecked Sendable {
        let onChange: @Sendable () -> Void
        init(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    }

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "SSHConfigKit.FileWatcher")

    /// Returns nil when the FSEvents stream cannot be created or started.
    public init?(directory: URL, latency: TimeInterval = 0.2, onChange: @escaping @Sendable () -> Void) {
        let box = CallbackBox(onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<CallbackBox>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        let path = directory.resolvingSymlinksInPath().path
        // FSEvents retains the box via the context; keep it alive until then.
        let maybeCreated = withExtendedLifetime(box) {
            FSEventStreamCreate(
                nil, callback, &context, [path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        }
        guard let created = maybeCreated else { return nil }

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return nil
        }
        stream = created
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        queue.sync {}  // drain in-flight callbacks; never runs on `queue` (callback doesn't reference self)
        FSEventStreamRelease(stream)
    }
}

/// Watches the directory a file lives in and, when the file is a symlink, the directory it
/// resolves to. `refresh()` re-resolves the link and restarts the watchers when the target
/// directory moved, so replacing the symlink (or moving its target) does not leave the
/// stores watching a stale directory. Used from one actor (the stores' main actor).
final class FileWatcherGroup {
    private let file: URL
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    private var watched: [String] = []
    private var watchers: [FileWatcher] = []

    /// Returns nil when no directory could be watched.
    init?(file: URL, latency: TimeInterval = 0.2, onChange: @escaping @Sendable () -> Void) {
        self.file = file
        self.latency = latency
        self.onChange = onChange
        rebuild(directories: Self.directories(of: file))
        if watchers.isEmpty { return nil }
    }

    /// The link's own directory first, then the resolved target's, without duplicates.
    static func directories(of file: URL) -> [String] {
        var result: [String] = []
        for url in [file.deletingLastPathComponent(), file.resolvingSymlinksInPath().deletingLastPathComponent()] {
            let path = url.resolvingSymlinksInPath().path
            if !result.contains(path) { result.append(path) }
        }
        return result
    }

    var watchedDirectories: [String] { watched }

    func refresh() {
        let current = Self.directories(of: file)
        guard current != watched else { return }
        rebuild(directories: current)
    }

    private func rebuild(directories: [String]) {
        // Create the new watchers before dropping the old ones: no gap in coverage.
        let created = directories.compactMap { FileWatcher(directory: URL(filePath: $0), latency: latency, onChange: onChange) }
        watchers = created
        watched = directories
    }
}
