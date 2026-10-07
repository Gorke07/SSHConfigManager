import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct TerminalLaunchingTests {
    @Test func appleScriptQuotingEscapesBackslashAndQuote() {
        #expect(AppleScriptBuilder.quoted(#"ssh -- 'a"b\c'"#) == #""ssh -- 'a\"b\\c'""#)
    }

    @Test func terminalAndITermScriptsTypeOnlyTheScriptPath() {
        let terminal = AppleScriptBuilder.terminal(scriptPath: "/tmp/T/sshcm-1.sh")
        #expect(terminal.contains(#"tell application id "com.apple.Terminal""#))
        #expect(terminal.contains(#"do script "/tmp/T/sshcm-1.sh""#))
        let iterm = AppleScriptBuilder.iTerm(scriptPath: "/tmp/T/sshcm-1.sh")
        #expect(iterm.contains(#"tell application id "com.googlecode.iterm2""#))
        #expect(iterm.contains(#"write text "/tmp/T/sshcm-1.sh""#))
    }

    @Test func launchScriptSingleQuotesEveryArgumentForSh() {
        let hostile = #"x\';/tmp/evil;#"#
        let path = #"/Users/a b/c\\d!$HOME`id`;e/config"#
        let content = LaunchScript.content(sshArguments: ["-F", path, "--", hostile])
        #expect(content == #"""
        #!/bin/sh
        rm -f -- "$0"
        exec /usr/bin/ssh '-F' '/Users/a b/c\\d!$HOME`id`;e/config' '--' 'x\'\'';/tmp/evil;#'

        """#)
        #expect(LaunchScript.singleQuoted("a'b") == #"'a'\''b'"#)
        #expect(LaunchScript.singleQuoted("") == "''")
    }

    @Test func safePathCharset() {
        #expect(LaunchScript.isSafePath("/var/folders/ab/x_Y-1/T/sshcm-0A1B.sh"))
        for unsafe in ["relative/sshcm.sh", "/a b/s.sh", "/a'b/s.sh", "/a\\b", "/a;b", "/a$b", "/a!b", "/a`b", "/ä/s.sh", "/a\nb", ""] {
            #expect(!LaunchScript.isSafePath(unsafe), "\(unsafe)")
        }
    }

    @Test func launcherWritesAPrivateScriptAndTypesOnlyItsPath() throws {
        let tmp = try TempDir()
        let aliases = [#"x\';/tmp/evil;#"#, #"a\\b"#, "a!b", "a$(id)b", "a`id`b", "a;b"]
        for makeSource in [AppleScriptBuilder.terminal(scriptPath:), AppleScriptBuilder.iTerm(scriptPath:)] {
            for alias in aliases {
                let launcher = AppleScriptLauncher(makeSource: makeSource, scriptDirectory: tmp.url)
                let configPath = tmp.url.appending(path: "c$f;g!`h`\\'i/config").path
                let arguments = ["-F", configPath, "--", alias]
                let (script, source) = try launcher.prepare(LaunchRequest(sshArguments: arguments, shellCommand: "unused"))

                #expect(script.deletingLastPathComponent().standardizedFileURL == tmp.url.standardizedFileURL)
                #expect(script.lastPathComponent.hasPrefix("sshcm-") && script.pathExtension == "sh")
                #expect(LaunchScript.isSafePath(script.path))
                #expect(source.contains(AppleScriptBuilder.quoted(script.path)))
                #expect(!source.contains(alias))
                #expect(!source.contains(configPath))
                #expect(!source.contains("/usr/bin/ssh") && !source.contains("--"))

                let attributes = try FileManager.default.attributesOfItem(atPath: script.path)
                #expect((attributes[.posixPermissions] as? Int) == 0o700)
                let content = try String(contentsOf: script, encoding: .utf8)
                #expect(content == LaunchScript.content(sshArguments: arguments))
                #expect(content.hasSuffix(" '--' " + LaunchScript.singleQuoted(alias) + "\n"))
            }
        }
    }

    @Test func scriptsInAnUnsafeDirectoryAreRefused() throws {
        let tmp = try TempDir()
        let unsafe = tmp.url.appending(path: "a b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: true)
        let launcher = AppleScriptLauncher(makeSource: AppleScriptBuilder.terminal(scriptPath:), scriptDirectory: unsafe)
        #expect(throws: LaunchError.self) { try launcher.prepare(LaunchRequest(sshArguments: ["--", "a"], shellCommand: "ssh -- a")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: unsafe.path).isEmpty)
    }

    @Test func dangerousAliasStaysOneArgument() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let alias = #"$(touch${IFS}/tmp/pwned);`id`!\'"#
        let app = makeTestModel(tmp, config: "Host \(alias)\n", launcher: launcher)
        #expect(app.connectableAliases == [alias])
        app.connect(alias: alias)
        let request = try #require(launcher.requests.first)
        #expect(request.sshArguments == ["--", alias])
        #expect(LaunchScript.content(sshArguments: request.sshArguments).hasSuffix(
            "exec /usr/bin/ssh '--' " + LaunchScript.singleQuoted(alias) + "\n"))
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

        app.errorMessage = "stale fallback message"
        #expect(app.connect(alias: "web") == .launched(.terminal))
        #expect(launcher.requests.first?.shellCommand == "ssh -- web")
        #expect(app.errorMessage == nil)

        launcher.error = .automationDenied
        #expect(app.connect(alias: "web") == .failed(.automationDenied))
        #expect(app.automationDenied)
    }

    @Test func controlCharactersInAliasAreRejectedBeforeLaunching() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host x\n", launcher: launcher)
        for alias in ["a\nrm -rf ~", "a\u{1B}x"] {
            app.errorMessage = nil
            #expect(app.connect(alias: alias) == .failed(.failed("control character")))
            #expect(launcher.requests.isEmpty)
            #expect(app.errorMessage == String(localized: "connect.invalidCommand"))
        }
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
