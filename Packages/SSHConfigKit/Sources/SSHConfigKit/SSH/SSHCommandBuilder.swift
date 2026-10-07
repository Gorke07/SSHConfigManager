import Foundation

/// Builds ssh argument lists and shell command lines for the active config file.
/// A non-default config file is passed with `-F`; the alias always follows `--`.
public struct SSHCommandBuilder: Equatable, Sendable {
    public let configFile: URL
    public let homeDirectory: URL

    public init(configFile: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.configFile = configFile
        self.homeDirectory = homeDirectory
    }

    public var usesDefaultConfig: Bool {
        let defaultConfig = homeDirectory.appending(path: ".ssh/config")
        return configFile.resolvingSymlinksInPath().standardizedFileURL.path
            == defaultConfig.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public var configArguments: [String] {
        usesDefaultConfig ? [] : ["-F", configFile.path]
    }

    public func sshArguments(options: [String] = [], alias: String) -> [String] {
        configArguments + options + ["--", alias]
    }

    public func shellCommand(alias: String) -> String {
        (["ssh"] + sshArguments(alias: alias).map(Self.shellQuote)).joined(separator: " ")
    }

    private static let safeScalars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-".unicodeScalars)

    /// Leaves values made only of safe characters as-is; single-quotes everything else.
    public static func shellQuote(_ value: String) -> String {
        if !value.isEmpty && value.unicodeScalars.allSatisfy(safeScalars.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
