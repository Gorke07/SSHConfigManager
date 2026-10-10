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
    /// A message from ssh, the OS or the terminal, shown as is.
    case failed(String)
    /// The script or program path contains characters that are not safe to type into a shell.
    case unsafePath
    /// The launch script could not be written.
    case scriptWriteFailed(Int32)   // errno, kept for the log
    /// The AppleScript could not be compiled.
    case appleScriptUnavailable
    /// `open` exited with this status.
    case openFailed(Int32)

    private static func openMessage(_ status: Int32) -> String {
        let code = String(status)
        return String(localized: "connect.error.open \(code)")
    }

    /// The text shown to the user; nil for `automationDenied`, which has its own explanation.
    var userMessage: String? {
        switch self {
        case .automationDenied: nil
        case .failed(let detail): detail
        case .unsafePath: String(localized: "connect.error.unsafePath")
        case .scriptWriteFailed: String(localized: "connect.error.scriptWrite")
        case .appleScriptUnavailable: String(localized: "connect.error.appleScript")
        case .openFailed(let status): Self.openMessage(status)
        }
    }
}

/// `launch` suspends until the terminal was asked to open; it never blocks the main thread.
@MainActor
protocol TerminalLaunching {
    func launch(_ request: LaunchRequest) async throws
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
    /// `open -n -b com.mitchellh.ghostty --args -e /usr/bin/ssh …` (`-n` opens a new instance; `-b` is the same
    /// bundle id `isInstalled` checks, so a renamed or relocated Ghostty still opens).
    static func openArguments(for request: LaunchRequest) -> [String] {
        // Only ssh keeps its old argv. Other programs (ssh-copy-id) print a result the user must be able to
        // read: --wait-after-command keeps the window open until a keypress (Ghostty 1.2.2 docs).
        let wait = request.program == "/usr/bin/ssh" ? [] : ["--wait-after-command=true"]
        return ["-n", "-b", TerminalChoice.ghostty.bundleIdentifier, "--args"] + wait + ["-e", request.program] + request.sshArguments
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
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.writeFailed(errno) }
                written += count
            }
        } catch {
            unlink(url.path)
            throw error
        }
        return url
    }

    /// Script file names are `sshcm-<UUID>.sh`; anything else in the directory is not ours.
    static func isOwnScriptName(_ name: String) -> Bool {
        guard name.hasPrefix("sshcm-"), name.hasSuffix(".sh") else { return false }
        return UUID(uuidString: String(name.dropFirst(6).dropLast(3))) != nil
    }

    /// A script that never ran (the terminal accepted the Apple Event but the shell did not execute it) stays
    /// behind; deletes our own regular files, owned by this user, last modified before `now - age`.
    /// Returns how many were removed. Never follows symlinks.
    @discardableResult
    static func sweepStale(in directory: URL, olderThan age: TimeInterval = 600, now: Date = Date()) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where isOwnScriptName(name) {
            let path = directory.appending(path: name).path
            var info = stat()
            guard lstat(path, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_uid == getuid() else { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            guard now.timeIntervalSince(modified) > age else { continue }
            if unlink(path) == 0 { removed += 1 }
        }
        return removed
    }
}
