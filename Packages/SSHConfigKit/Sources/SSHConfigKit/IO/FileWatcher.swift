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
        guard let created = FSEventStreamCreate(
            nil, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return nil }

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
