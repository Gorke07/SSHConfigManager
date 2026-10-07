import AppKit

struct AppleScriptLauncher: TerminalLaunching {
    let makeSource: (String) -> String

    func launch(_ request: LaunchRequest) throws {
        guard let script = NSAppleScript(source: makeSource(request.shellCommand)) else {
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
        case .terminal: AppleScriptLauncher(makeSource: AppleScriptBuilder.terminal(command:))
        case .iterm2: AppleScriptLauncher(makeSource: AppleScriptBuilder.iTerm(command:))
        case .ghostty: GhosttyLauncher()
        }
    }

    static func isInstalled(_ choice: TerminalChoice) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.bundleIdentifier) != nil
    }
}
