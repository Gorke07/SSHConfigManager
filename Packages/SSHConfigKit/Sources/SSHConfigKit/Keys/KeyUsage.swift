import Foundation

/// Which hosts use a key: IdentityFile values resolved the way they name files at connect time.
public enum KeyUsage {
    /// `~/…` and `%d/…` → home; a relative path → home-relative (ssh is started from the home
    /// directory). nil for other `%` tokens or `~user` forms, which cannot be resolved here.
    public static func resolve(_ value: String, home: URL) -> URL? {
        var path = value
        if path == "~" || path.hasPrefix("~/") {
            path = home.path + path.dropFirst(1)
        } else if path.hasPrefix("%d/") {
            path = home.path + path.dropFirst(2)
        }
        guard !path.contains("%"), !path.hasPrefix("~") else { return nil }
        let url = path.hasPrefix("/") ? URL(filePath: path) : home.appending(path: path)
        return url.standardizedFileURL
    }

    public static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// A stable key for "the same file": `device:inode` (stat follows symlinks and `..`, and is exact on
    /// case-insensitive volumes) when the file exists, else the canonical path.
    public static func identity(_ url: URL) -> String {
        var info = stat()
        if stat(url.path, &info) == 0 { return "\(info.st_dev):\(info.st_ino)" }
        return canonicalPath(url)
    }

    public static func sameFile(_ a: URL, _ b: URL) -> Bool {
        identity(a) == identity(b)
    }

    /// Host labels by the identity of each resolvable IdentityFile they name.
    public static func hostLabelsByIdentity(in hosts: [HostEntry], home: URL) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for host in hosts {
            let label = host.patterns.joined(separator: " ")
            for value in host.values(for: "IdentityFile") {
                guard let url = resolve(value, home: home) else { continue }
                let key = identity(url)
                if !(result[key]?.contains(label) ?? false) { result[key, default: []].append(label) }
            }
        }
        return result
    }

    /// Every resolvable IdentityFile of the given hosts, once.
    public static func identityFiles(of hosts: [HostEntry], home: URL) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for host in hosts {
            for value in host.values(for: "IdentityFile") {
                guard let url = resolve(value, home: home), seen.insert(identity(url)).inserted else { continue }
                result.append(url)
            }
        }
        return result
    }

    /// Host labels (patterns joined by a space, file order) whose IdentityFile names `key`.
    public static func hosts(using key: URL, in hosts: [HostEntry], home: URL) -> [String] {
        hostLabelsByIdentity(in: hosts, home: home)[identity(key)] ?? []
    }
}
