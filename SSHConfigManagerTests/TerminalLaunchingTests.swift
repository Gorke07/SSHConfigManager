import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct TerminalLaunchingTests {
    @Test func appleScriptQuotingEscapesBackslashAndQuote() {
        #expect(AppleScriptBuilder.quoted(#"ssh -- 'a"b\c'"#) == #""ssh -- 'a\"b\\c'""#)
    }

    @Test func terminalAndITermScripts() {
        let terminal = AppleScriptBuilder.terminal(command: "ssh -- web")
        #expect(terminal.contains(#"tell application id "com.apple.Terminal""#))
        #expect(terminal.contains(#"do script "ssh -- web""#))
        let iterm = AppleScriptBuilder.iTerm(command: "ssh -- web")
        #expect(iterm.contains(#"tell application id "com.googlecode.iterm2""#))
        #expect(iterm.contains(#"write text "ssh -- web""#))
    }

    @Test func ghosttyArgumentsPassSshArgvWithoutAShell() {
        let request = LaunchRequest(sshArguments: ["-F", "/x y/config", "--", "a'b"], shellCommand: "unused")
        #expect(GhosttyArguments.openArguments(for: request) ==
            ["-na", "Ghostty.app", "--args", "-e", "/usr/bin/ssh", "-F", "/x y/config", "--", "a'b"])
    }

    @Test func dangerousAliasStaysOneArgumentInBothPaths() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host x\n", launcher: launcher)
        app.connect(alias: "$(touch /tmp/pwned) \"q\"")
        let request = try #require(launcher.requests.first)
        #expect(request.sshArguments.last == "$(touch /tmp/pwned) \"q\"")
        #expect(request.shellCommand == #"ssh -- '$(touch /tmp/pwned) "q"'"#)
        let script = AppleScriptBuilder.terminal(command: request.shellCommand)
        #expect(script.contains(#"do script "ssh -- '$(touch /tmp/pwned) \"q\"'""#))
    }

    @Test func connectorFallsBackToTerminal() {
        let ghostty = RecordingLauncher()
        ghostty.error = .failed("boom")
        let terminal = RecordingLauncher()
        let request = LaunchRequest(sshArguments: ["--", "a"], shellCommand: "ssh -- a")

        let failing = Connector(choice: .ghostty, isInstalled: { _ in true }, makeLauncher: { $0 == .ghostty ? ghostty : terminal })
        #expect(failing.connect(request) == .fellBack(from: .ghostty))
        #expect(terminal.requests == [request])

        let missing = Connector(choice: .iterm2, isInstalled: { $0 == .terminal }, makeLauncher: { _ in terminal })
        #expect(missing.connect(request) == .fellBack(from: .iterm2))

        let fine = Connector(choice: .terminal, isInstalled: { _ in true }, makeLauncher: { _ in terminal })
        #expect(fine.connect(request) == .launched(.terminal))
    }

    @Test func automationDeniedIsReportedNotHidden() {
        let iterm = RecordingLauncher()
        iterm.error = .automationDenied
        let terminal = RecordingLauncher()
        let request = LaunchRequest(sshArguments: ["--", "a"], shellCommand: "ssh -- a")
        let connector = Connector(choice: .iterm2, isInstalled: { _ in true }, makeLauncher: { $0 == .iterm2 ? iterm : terminal })
        #expect(connector.connect(request) == .failed(.automationDenied))
        #expect(terminal.requests.isEmpty)
    }

    @Test func terminalFailureWithoutFallback() {
        let terminal = RecordingLauncher()
        terminal.error = .failed("nope")
        let connector = Connector(choice: .terminal, isInstalled: { _ in true }, makeLauncher: { _ in terminal })
        #expect(connector.connect(LaunchRequest(sshArguments: [], shellCommand: "ssh")) == .failed(.failed("nope")))
    }

    @Test func modelConnectsResolvesAliasesAndReportsOutcomes() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host web w2\n  HostName h\nHost *.prod\n", launcher: launcher)
        #expect(app.connectableAlias(for: .host(alias: "web", occurrence: 0)) == "web")
        #expect(app.connectableAlias(for: .host(alias: "*.prod", occurrence: 0)) == nil)
        #expect(app.connectableAlias(for: .match(index: 0)) == nil)
        #expect(app.connectableAliases == ["web"])

        #expect(app.connect(alias: "web") == .launched(.terminal))
        #expect(launcher.requests.first?.shellCommand == "ssh -- web")
        #expect(app.errorMessage == nil)

        launcher.error = .automationDenied
        #expect(app.connect(alias: "web") == .failed(.automationDenied))
        #expect(app.automationDenied)
    }

    @Test func customConfigUsesDashF() throws {
        let tmp = try TempDir()
        try tmp.file("dot/config", "Host a\n")
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host z\n", launcher: launcher)
        #expect(app.switchConfig(to: tmp.url.appending(path: "dot/config").path) == .switched)
        app.connect(alias: "a")
        let request = try #require(launcher.requests.first)
        #expect(request.sshArguments.prefix(2) == ["-F", tmp.url.appending(path: "dot/config").path])
    }

    @Test func terminalSettingPersistsAndFallsBack() throws {
        let tmp = try TempDir()
        let settings = AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url)
        #expect(settings.terminal == .terminal)
        settings.setTerminal(.ghostty)
        #expect(AppSettings(defaults: UserDefaults(suiteName: tmp.defaultsSuiteName)!, homeDirectory: tmp.url).terminal == .ghostty)
        tmp.defaults.set("warp", forKey: "terminal")
        #expect(AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).terminal == .terminal)
    }
}
