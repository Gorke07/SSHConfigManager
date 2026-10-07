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
        } catch {
            throw LaunchError.failed(String(describing: error))
        }
        guard LaunchScript.isSafePath(script.path) else {
            try? FileManager.default.removeItem(at: script)
            throw LaunchError.failed("unsafe script path")
        }
        return (script, makeSource(script.path))
    }

    func launch(_ request: LaunchRequest) throws {
        let (scriptURL, source) = try prepare(request)
        do {
            try run(source)
        } catch {
            // The script deletes itself when it runs; it never ran.
            try? FileManager.default.removeItem(at: scriptURL)
            throw error
        }
    }

    private func run(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw LaunchError.failed("AppleScript")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            if number == -1743 { throw LaunchError.automationDenied }
            throw LaunchError.failed(error[NSAppleScript.errorMessage] as? String ?? String(describing: number))
        }
    }
}

struct GhosttyLauncher: TerminalLaunching {
    func launch(_ request: LaunchRequest) throws {
        guard LaunchScript.isSafePath(request.program) else { throw LaunchError.failed("unsafe program path") }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = GhosttyArguments.openArguments(for: request)
        do {
            try process.run()
        } catch {
            throw LaunchError.failed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LaunchError.failed("open \(process.terminationStatus)") }
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
