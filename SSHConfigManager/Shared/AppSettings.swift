import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let defaultConfigPath = "~/.ssh/config"
    static let defaultKnownHostsPath = "~/.ssh/known_hosts"
    static let defaultBackupCount = 10
    static let backupCountRange = 1...50

    private enum Keys {
        static let configPath = "configPath"
        static let knownHostsPath = "knownHostsPath"
        static let backupCount = "backupCount"
        static let terminal = "terminal"
        static let appearance = "appearance"
        static let showsInDock = "showsInDock"
    }

    @ObservationIgnored private let defaults: UserDefaults
    var userDefaults: UserDefaults { defaults }
    let homeDirectory: URL
    private(set) var configPath: String
    private(set) var knownHostsPath: String
    private(set) var backupCount: Int
    private(set) var terminal: TerminalChoice
    private(set) var appearance: AppAppearance
    /// Off: menu bar only, no Dock icon even while a window is open.
    private(set) var showsInDock: Bool

    init(defaults: UserDefaults = .standard, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        let stored = defaults.string(forKey: Keys.configPath)
        configPath = stored.flatMap { Self.isValidConfigPath($0) ? $0 : nil } ?? Self.defaultConfigPath
        let storedKnownHosts = defaults.string(forKey: Keys.knownHostsPath)
        knownHostsPath = storedKnownHosts.flatMap { Self.isValidConfigPath($0) ? $0 : nil } ?? Self.defaultKnownHostsPath
        backupCount = Self.clamp(defaults.object(forKey: Keys.backupCount) as? Int ?? Self.defaultBackupCount)
        terminal = TerminalChoice(rawValue: defaults.string(forKey: Keys.terminal) ?? "") ?? .terminal
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        showsInDock = defaults.object(forKey: Keys.showsInDock) as? Bool ?? true
    }

    var configURL: URL { Self.expand(configPath, home: homeDirectory) }

    func setConfigPath(_ path: String) {
        configPath = path
        defaults.set(path, forKey: Keys.configPath)
    }

    var knownHostsURL: URL { Self.expand(knownHostsPath, home: homeDirectory) }

    func setKnownHostsPath(_ path: String) {
        knownHostsPath = path
        defaults.set(path, forKey: Keys.knownHostsPath)
    }

    func setBackupCount(_ count: Int) {
        backupCount = Self.clamp(count)
        defaults.set(backupCount, forKey: Keys.backupCount)
    }

    func setTerminal(_ choice: TerminalChoice) {
        terminal = choice
        defaults.set(choice.rawValue, forKey: Keys.terminal)
    }

    func setAppearance(_ choice: AppAppearance) {
        appearance = choice
        defaults.set(choice.rawValue, forKey: Keys.appearance)
    }

    func setShowsInDock(_ value: Bool) {
        showsInDock = value
        defaults.set(value, forKey: Keys.showsInDock)
    }

    /// Shows paths under the home directory with a leading "~".
    func displayPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Only absolute paths, "~" and "~/..." are accepted; anything else would resolve against the CWD.
    static func isValidConfigPath(_ path: String) -> Bool {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return false }
        return path.hasPrefix("/") || path == "~" || path.hasPrefix("~/")
    }

    static func expand(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))) }
        return URL(filePath: path)
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, backupCountRange.lowerBound), backupCountRange.upperBound)
    }
}
