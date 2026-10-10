import Foundation

public struct IncludedHost: Identifiable, Equatable, Sendable {
    public let file: URL
    public let entry: HostEntry

    public init(file: URL, entry: HostEntry) {
        self.file = file
        self.entry = entry
    }
    public var id: String { "\(file.path)#\(entry.headerLine)" }
}

/// One file an Include chain reads: its standardized path and text (nil when unreadable or not UTF-8).
public struct IncludeFileState: Equatable, Sendable {
    public let path: String
    public let text: String?
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
        traverse(document, rootFile: rootFile).hosts
    }

    /// Every file the Include chain of `document` reads, in order, with its text: changes to any of
    /// them (global lines, Match blocks, hosts) change the result of resolving through them.
    public func includeFileStates(of document: ConfigDocument, rootFile: URL?) -> [IncludeFileState] {
        traverse(document, rootFile: rootFile).states
    }

    /// One walk of the Include chain: its hosts and its file states.
    public func traverse(_ document: ConfigDocument, rootFile: URL?) -> (hosts: [IncludedHost], states: [IncludeFileState]) {
        var visited = Set<String>()
        if let rootFile { visited.insert(rootFile.resolvingSymlinksInPath().path) }
        var hosts: [IncludedHost] = []
        var states: [IncludeFileState] = []
        collect(document, depth: 0, visited: &visited, hosts: &hosts, states: &states)
        return (hosts, states)
    }

    /// Reads a config file; nil for anything but a readable regular UTF-8 file (a FIFO is skipped, never waited on).
    private func readText(_ file: URL) -> String? {
        (try? RegularFile.read(file, limit: nil)).flatMap { String(validating: $0, as: UTF8.self) }
    }

    /// The files one Include directive names, parsed, in ssh's (sorted glob) order.
    public func includedDocuments(for include: IncludeDirective) -> [(file: URL, document: ConfigDocument)] {
        include.paths.flatMap(expand).compactMap { file in
            guard let text = readText(file) else { return nil }
            return (file, ConfigDocument(parsing: text))
        }
    }

    private func collect(_ document: ConfigDocument, depth: Int, visited: inout Set<String>,
                         hosts: inout [IncludedHost], states: inout [IncludeFileState]) {
        guard depth < maxDepth else { return }
        for include in document.includes {
            for pattern in include.paths {
                for file in expand(pattern) {
                    guard visited.insert(file.resolvingSymlinksInPath().path).inserted else { continue }
                    let text = readText(file)
                    states.append(IncludeFileState(path: file.standardizedFileURL.path, text: text))
                    guard let text else { continue }
                    let included = ConfigDocument(parsing: text)
                    hosts += included.hosts.map { IncludedHost(file: file, entry: $0) }
                    collect(included, depth: depth + 1, visited: &visited, hosts: &hosts, states: &states)
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
