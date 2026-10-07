import Foundation

public struct IncludedHost: Identifiable, Equatable, Sendable {
    public let file: URL
    public let entry: HostEntry
    public var id: String { "\(file.path)#\(entry.headerLine)" }
}

/// Follows `Include` directives the way ssh does: relative paths resolve against `~/.ssh`
/// (even when the root config lives elsewhere), `~` expands to home, globs are sorted.
public struct IncludeResolver: Sendable {
    public let homeDirectory: URL
    public let maxDepth: Int

    public var sshDirectory: URL { homeDirectory.appending(path: ".ssh", directoryHint: .isDirectory) }

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, maxDepth: Int = 16) {
        self.homeDirectory = homeDirectory
        self.maxDepth = maxDepth
    }

    public func includedHosts(of document: ConfigDocument, rootFile: URL?) -> [IncludedHost] {
        var visited = Set<String>()
        if let rootFile { visited.insert(rootFile.resolvingSymlinksInPath().path) }
        var result: [IncludedHost] = []
        collect(document, depth: 0, visited: &visited, into: &result)
        return result
    }

    private func collect(_ document: ConfigDocument, depth: Int, visited: inout Set<String>, into result: inout [IncludedHost]) {
        guard depth < maxDepth else { return }
        for include in document.includes {
            for pattern in include.paths {
                for file in expand(pattern) {
                    guard visited.insert(file.resolvingSymlinksInPath().path).inserted,
                          let data = try? Data(contentsOf: file),
                          let text = String(validating: data, as: UTF8.self)
                    else { continue }
                    let included = ConfigDocument(parsing: text)
                    result += included.hosts.map { IncludedHost(file: file, entry: $0) }
                    collect(included, depth: depth + 1, visited: &visited, into: &result)
                }
            }
        }
    }

    private func expand(_ pattern: String) -> [URL] {
        let path: String
        if pattern == "~" {
            path = homeDirectory.path
        } else if pattern.hasPrefix("~/") {
            path = homeDirectory.appending(path: String(pattern.dropFirst(2))).path
        } else if pattern.hasPrefix("/") {
            path = pattern
        } else {
            path = sshDirectory.appending(path: pattern).path
        }

        var matches = glob_t()
        defer { globfree(&matches) }
        guard glob(path, 0, nil, &matches) == 0 else { return [] }
        return (0..<Int(matches.gl_pathc)).compactMap { index in
            guard let cString = matches.gl_pathv[index] else { return nil }
            let url = URL(filePath: String(cString: cString))
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
            return url
        }
    }
}
