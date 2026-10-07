import Foundation

public enum SafeFileWriterError: Error, Equatable, Sendable {
    /// The file on disk no longer matches what was loaded.
    case conflict
    case backupFailed(String)
    case writeFailed(String)
}

/// Conflict check → backup → temp file in the same directory → fsync → rename(2).
/// Symlinks are resolved so the real file is replaced and the link is kept.
public struct SafeFileWriter: Sendable {
    public let backups: BackupManager?

    public init(backups: BackupManager?) {
        self.backups = backups
    }

    public func write(
        _ text: String,
        to url: URL,
        expected: FileFingerprint?,
        ignoreConflict: Bool = false,
        backupKind: String
    ) throws {
        let fm = FileManager.default
        let target = url.resolvingSymlinksInPath()

        if !ignoreConflict {
            let current: FileFingerprint?
            do { current = try FileFingerprint.of(fileAt: target) }
            catch { throw SafeFileWriterError.writeFailed(error.localizedDescription) }
            guard current == expected else { throw SafeFileWriterError.conflict }
        }

        let exists = fm.fileExists(atPath: target.path)
        if exists, let backups {
            do { try backups.backup(fileAt: target, kind: backupKind) }
            catch { throw SafeFileWriterError.backupFailed(error.localizedDescription) }
        }

        let permissions = exists
            ? ((try? fm.attributesOfItem(atPath: target.path)[.posixPermissions]) as? Int ?? 0o600)
            : 0o600
        let temp = target.deletingLastPathComponent()
            .appending(path: ".\(target.lastPathComponent).tmp-\(UUID().uuidString)")

        do {
            guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: permissions]) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temp.path])
            }
            let handle = try FileHandle(forWritingTo: temp)
            do {
                try handle.write(contentsOf: Data(text.utf8))
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            // createFile's mode is filtered by umask; set it explicitly.
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
            guard rename(temp.path, target.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw SafeFileWriterError.writeFailed(error.localizedDescription)
        }
    }
}
