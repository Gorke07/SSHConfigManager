import AppKit

/// Terminal / iTerm2: writes a launch script and asks the terminal (Apple Events) to run its path.
struct AppleScriptLauncher: TerminalLaunching {
    /// Builds the AppleScript from the script's path; never sees the ssh arguments.
    let makeSource: (String) -> String
    /// Private per-user directory for launch scripts (tests pass a temporary one).
    var scriptDirectory: URL = FileManager.default.temporaryDirectory

    /// Writes the launch script and returns it with the AppleScript that runs it.
    func prepare(_ request: LaunchRequest) throws -> (script: URL, source: String) {
        let script: URL
        do {
            script = try LaunchScript.write(sshArguments: request.sshArguments, program: request.program, in: scriptDirectory)
        } catch LaunchScript.Failure.unsafePath {
            throw LaunchError.unsafePath
        } catch LaunchScript.Failure.writeFailed(let code) {
            throw LaunchError.scriptWriteFailed(code)
        } catch {
            throw LaunchError.scriptWriteFailed(0)
        }
        guard LaunchScript.isSafePath(script.path) else {
            try? FileManager.default.removeItem(at: script)
            throw LaunchError.unsafePath
        }
        return (script, makeSource(script.path))
    }

    func launch(_ request: LaunchRequest) async throws {
        LaunchScript.sweepStale(in: scriptDirectory)
        let (scriptURL, source) = try prepare(request)
        do {
            try await AppleScriptExecutor.run(source)
        } catch {
            // The script deletes itself when it runs; it never ran.
            try? FileManager.default.removeItem(at: scriptURL)
            throw error
        }
    }
}

/// Runs AppleScript off the main thread (the first Apple Event may wait on the Automation permission prompt).
/// It stays in this process on purpose: macOS ties that permission to the calling app, so the prompt and the
/// Settings entry keep naming SSH Config Manager (an `osascript` child would be a different, unexplained
/// requester). `NSAppleScript` is not thread-safe, so every script is created and run on this one serial queue.
enum AppleScriptExecutor {
    private static let queue = DispatchQueue(label: "app.sshconfigmanager.applescript", qos: .userInitiated)

    static func run(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: LaunchError.appleScriptUnavailable)
                    return
                }
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                guard let error else {
                    continuation.resume()
                    return
                }
                let number = error[NSAppleScript.errorNumber] as? Int
                if number == -1743 {
                    continuation.resume(throwing: LaunchError.automationDenied)
                } else {
                    // -1712 (errAETimeout: the app did not answer the Apple Event in time, e.g. while the
                    // permission prompt waits) arrives here as a plain failure; Connector then falls back to
                    // Terminal for iTerm2, and reports it for Terminal itself.
                    let message = error[NSAppleScript.errorMessage] as? String
                    continuation.resume(throwing: LaunchError.failed(message ?? number.map { "AppleScript \($0)" } ?? "AppleScript"))
                }
            }
        }
    }
}

struct GhosttyLauncher: TerminalLaunching {
    func launch(_ request: LaunchRequest) async throws {
        guard LaunchScript.isSafePath(request.program) else { throw LaunchError.unsafePath }
        let status = try await OpenCommand.run(GhosttyArguments.openArguments(for: request))
        guard status == 0 else { throw LaunchError.openFailed(status) }
    }
}

/// `/usr/bin/open`, awaited with a termination handler (no thread waits for it).
enum OpenCommand {
    static func run(_ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = arguments
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: LaunchError.failed(error.localizedDescription))
            }
        }
    }
}

@MainActor
enum LiveTerminals {
    static func launcher(for choice: TerminalChoice) -> any TerminalLaunching {
        switch choice {
        case .terminal: AppleScriptLauncher(makeSource: AppleScriptBuilder.terminal(scriptPath:))
        case .iterm2: AppleScriptLauncher(makeSource: AppleScriptBuilder.iTerm(scriptPath:))
        case .ghostty: GhosttyLauncher()
        }
    }

    static func isInstalled(_ choice: TerminalChoice) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.bundleIdentifier) != nil
    }
}
