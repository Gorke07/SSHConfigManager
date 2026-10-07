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

    /// Every resolvable IdentityFile of the given hosts, once.
    public static func identityFiles(of hosts: [HostEntry], home: URL) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for host in hosts {
            for value in host.values(for: "IdentityFile") {
                guard let url = resolve(value, home: home), seen.insert(canonicalPath(url)).inserted else { continue }
                result.append(url)
            }
        }
        return result
    }

    /// Host labels (patterns joined by a space, file order) whose IdentityFile names `key`.
    public static func hosts(using key: URL, in hosts: [HostEntry], home: URL) -> [String] {
        let target = canonicalPath(key)
        var result: [String] = []
        for host in hosts {
            let uses = host.values(for: "IdentityFile").contains { value in
                resolve(value, home: home).map { canonicalPath($0) == target } ?? false
            }
            let label = host.patterns.joined(separator: " ")
            if uses && !result.contains(label) { result.append(label) }
        }
        return result
    }
}
