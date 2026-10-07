import Foundation

public struct Backup: Equatable, Sendable {
    public let url: URL
    public let date: Date
    public let originalName: String
}

/// Keeps timestamped copies under `<root>/<kind>/yyyyMMdd-HHmmss[_n]-<name>`.
public struct BackupManager: Sendable {
    public static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/SSHConfigManager/Backups", directoryHint: .isDirectory)

    public let rootDirectory: URL
    public var keep: Int
    private let now: @Sendable () -> Date

    public init(rootDirectory: URL, keep: Int = 10, now: @escaping @Sendable () -> Date = { Date() }) {
        self.rootDirectory = rootDirectory
        self.keep = keep
        self.now = now
    }

    @discardableResult
    public func backup(fileAt url: URL, kind: String) throws -> URL {
        let fm = FileManager.default
        let directory = rootDirectory.appending(path: kind, directoryHint: .isDirectory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let stamp = Self.makeFormatter().string(from: now())
        let name = url.lastPathComponent
        var target = directory.appending(path: "\(stamp)-\(name)")
        var counter = 2
        while fm.fileExists(atPath: target.path) {
            target = directory.appending(path: "\(stamp)_\(counter)-\(name)")
            counter += 1
        }

        // Copy bytes (not the item): copyItem would copy a symlink as a symlink.
        let data = try Data(contentsOf: url)
        guard fm.createFile(atPath: target.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
        }
        try prune(kind: kind)
        return target
    }

    public func list(kind: String) throws -> [Backup] {
        let directory = rootDirectory.appending(path: kind, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .compactMap(Self.parse)
            .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    public func prune(kind: String) throws {
        for old in try list(kind: kind).dropFirst(max(keep, 1)) {
            try FileManager.default.removeItem(at: old.url)
        }
    }

    public func contents(of backup: Backup) throws -> String {
        let data = try Data(contentsOf: backup.url)
        guard let text = String(validating: data, as: UTF8.self) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    static func parse(_ url: URL) -> Backup? {
        let name = url.lastPathComponent
        guard name.count > 16, let date = makeFormatter().date(from: String(name.prefix(15))) else { return nil }
        var rest = name.dropFirst(15)
        if rest.hasPrefix("_") { rest = rest.drop(while: { $0 != "-" }) }
        guard rest.hasPrefix("-"), rest.count > 1 else { return nil }
        return Backup(url: url, date: date, originalName: String(rest.dropFirst()))
    }

    static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }
}
