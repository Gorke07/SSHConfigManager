struct LaunchRequest: Equatable, Sendable {
    /// ssh argv after the program name (Ghostty passes these without a shell).
    let sshArguments: [String]
    /// Shell-quoted command line (Terminal / iTerm2 type it into a shell).
    let shellCommand: String
}

enum LaunchError: Error, Equatable {
    /// macOS refused to let this app control the terminal (Apple Events, error -1743).
    case automationDenied
    case failed(String)
}

@MainActor
protocol TerminalLaunching {
    func launch(_ request: LaunchRequest) throws
}

enum AppleScriptBuilder {
    /// An AppleScript string literal; only backslash and double quote need escaping.
    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func terminal(command: String) -> String {
        """
        tell application id "com.apple.Terminal"
            activate
            do script \(quoted(command))
        end tell
        """
    }

    static func iTerm(command: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow to write text \(quoted(command))
        end tell
        """
    }
}

enum GhosttyArguments {
    /// `open -na Ghostty.app --args -e /usr/bin/ssh …` (verified with Ghostty 1.2.2; `-n` opens a new instance).
    static func openArguments(for request: LaunchRequest) -> [String] {
        ["-na", "Ghostty.app", "--args", "-e", "/usr/bin/ssh"] + request.sshArguments
    }
}
