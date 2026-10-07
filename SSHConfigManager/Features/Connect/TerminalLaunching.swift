import Foundation

struct LaunchRequest: Equatable, Sendable {
    /// ssh argv after the program name (Ghostty passes these without a shell).
    let sshArguments: [String]
    /// Shell-quoted command line, for display and validation only: no launcher types it into a shell.
    let shellCommand: String
    /// Absolute path of the program to run: ssh, or ssh-copy-id for "Upload to Server".
    var program = "/usr/bin/ssh"
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

    /// Runs the launch script in a new Terminal window. Only the script's path is typed into the
    /// user's shell (whatever it is: zsh, fish, tcsh…); it must pass `LaunchScript.isSafePath`.
    static func terminal(scriptPath: String) -> String {
        """
        tell application id "com.apple.Terminal"
            activate
            do script \(quoted(scriptPath))
        end tell
        """
    }

    static func iTerm(scriptPath: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow to write text \(quoted(scriptPath))
        end tell
        """
    }
}

enum GhosttyArguments {
    /// `open -na Ghostty.app --args -e /usr/bin/ssh …` (verified with Ghostty 1.2.2; `-n` opens a new instance).
    static func openArguments(for request: LaunchRequest) -> [String] {
        // Only ssh keeps its old argv. Other programs (ssh-copy-id) print a result the user must be able to
        // read: --wait-after-command keeps the window open until a keypress (Ghostty 1.2.2 docs).
        let wait = request.program == "/usr/bin/ssh" ? [] : ["--wait-after-command=true"]
        return ["-na", "Ghostty.app", "--args"] + wait + ["-e", request.program] + request.sshArguments
    }
}

/// Terminal and iTerm2 can only type text into the user's interactive shell, whose quoting rules are
/// unknown (fish and csh treat `\\` and `!` inside single quotes specially). So no user data is typed:
/// ssh is started by a private `/bin/sh` script, and only the script's path is typed.
enum LaunchScript {
    enum Failure: Error, Equatable {
        case unsafePath(String)
        case writeFailed(Int32)
    }

    /// `#!/bin/sh`, delete itself, then `exec <program>` with every argument single-quoted for sh.
    static func content(sshArguments: [String], program: String = "/usr/bin/ssh") -> String {
        let arguments = sshArguments.map(singleQuoted).joined(separator: " ")
        return "#!/bin/sh\nrm -f -- \"$0\"\nexec \(program) \(arguments)\n"
    }

    /// sh single quotes: nothing inside is special; a `'` becomes `'\''`.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let safePathScalars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._-".unicodeScalars)

    /// An absolute path made only of `[A-Za-z0-9/._-]`: means the same thing typed into any shell.
    static func isSafePath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.unicodeScalars.allSatisfy(safePathScalars.contains)
    }

    /// Writes `sshcm-<UUID>.sh` (mode 0700, never following or replacing an existing file) into
    /// `directory`, which must be private to the user (the default is the per-user temporary directory).
    static func write(sshArguments: [String], program: String = "/usr/bin/ssh", in directory: URL) throws -> URL {
        guard isSafePath(program) else { throw Failure.unsafePath(program) }
        let url = directory.appending(path: "sshcm-\(UUID().uuidString).sh")
        guard isSafePath(url.path) else { throw Failure.unsafePath(url.path) }
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o700)
        guard descriptor >= 0 else { throw Failure.writeFailed(errno) }
        defer { close(descriptor) }
        do {
            guard fchmod(descriptor, 0o700) == 0 else { throw Failure.writeFailed(errno) }   // the umask may have narrowed it
            let bytes = Array(content(sshArguments: sshArguments, program: program).utf8)
            var written = 0
            while written < bytes.count {
                let count = bytes[written...].withUnsafeBytes { Foundation.write(descriptor, $0.baseAddress, $0.count) }
                guard count > 0 else { throw Failure.writeFailed(errno) }
                written += count
            }
        } catch {
            unlink(url.path)
            throw error
        }
        return url
    }
}
