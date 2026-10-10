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

    @Test func dangerousAliasStaysOneArgument() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let alias = #"$(touch${IFS}/tmp/pwned);`id`!\'"#
        let app = makeTestModel(tmp, config: "Host \(alias)\n", launcher: launcher)
        #expect(app.connectableAliases == [alias])
        await app.connect(alias: alias)
        let request = try #require(launcher.requests.first)
        #expect(request.sshArguments == ["--", alias])
        #expect(LaunchScript.content(sshArguments: request.sshArguments).hasSuffix(
            "exec /usr/bin/ssh '--' " + LaunchScript.singleQuoted(alias) + "\n"))
    }

    @Test func connectorFallsBackToTerminal() async {
        let ghostty = RecordingLauncher()
        ghostty.error = .failed("boom")
        let terminal = RecordingLauncher()
        let request = LaunchRequest(sshArguments: ["--", "a"], shellCommand: "ssh -- a")

        let failing = Connector(choice: .ghostty, isInstalled: { _ in true }, makeLauncher: { $0 == .ghostty ? ghostty : terminal })
        #expect(await failing.connect(request) == .fellBack(from: .ghostty))
        #expect(terminal.requests == [request])

        let missing = Connector(choice: .iterm2, isInstalled: { $0 == .terminal }, makeLauncher: { _ in terminal })
        #expect(await missing.connect(request) == .fellBack(from: .iterm2))

        let fine = Connector(choice: .terminal, isInstalled: { _ in true }, makeLauncher: { _ in terminal })
        #expect(await fine.connect(request) == .launched(.terminal))
    }

    @Test func automationDeniedIsReportedNotHidden() async {
        let iterm = RecordingLauncher()
        iterm.error = .automationDenied
        let terminal = RecordingLauncher()
        let request = LaunchRequest(sshArguments: ["--", "a"], shellCommand: "ssh -- a")
        let connector = Connector(choice: .iterm2, isInstalled: { _ in true }, makeLauncher: { $0 == .iterm2 ? iterm : terminal })
        #expect(await connector.connect(request) == .failed(.automationDenied))
        #expect(terminal.requests.isEmpty)
    }

    @Test func terminalFailureWithoutFallback() async {
        let terminal = RecordingLauncher()
        terminal.error = .failed("nope")
        let connector = Connector(choice: .terminal, isInstalled: { _ in true }, makeLauncher: { _ in terminal })
        #expect(await connector.connect(LaunchRequest(sshArguments: [], shellCommand: "ssh")) == .failed(.failed("nope")))
    }

    @Test func modelConnectsResolvesAliasesAndReportsOutcomes() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host web w2\n  HostName h\nHost *.prod\n", launcher: launcher)
        #expect(app.connectableAlias(for: .host(alias: "web", occurrence: 0)) == "web")
        #expect(app.connectableAlias(for: .host(alias: "*.prod", occurrence: 0)) == nil)
        #expect(app.connectableAlias(for: .match(index: 0)) == nil)
        #expect(app.connectableAliases == ["web"])

        app.errorMessage = "stale fallback message"
        #expect(await app.connect(alias: "web") == .launched(.terminal))
        #expect(launcher.requests.first?.shellCommand == "ssh -- web")
        #expect(app.errorMessage == nil)

        launcher.error = .automationDenied
        #expect(await app.connect(alias: "web") == .failed(.automationDenied))
        #expect(app.automationDenied)
    }

    @Test func controlCharactersInAliasAreRejectedBeforeLaunching() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host a\u{1B}x\n", launcher: launcher)
        #expect(app.connectableAliases == ["a\u{1B}x"])
        #expect(await app.connect(alias: "a\u{1B}x") == .failed(.failed("control character")))
        #expect(launcher.requests.isEmpty)
        #expect(app.errorMessage == String(localized: "connect.invalidCommand"))
    }

    @Test func hostAddedButNotSavedCannotBeConnectedOrTested() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host a\n", launcher: launcher)
        try app.store.apply { _ = try $0.addHost(HostDraft(patterns: ["prod"], directives: [DraftDirective(key: "HostName", value: "10.0.0.5")])) }
        let prod = SidebarItem.host(alias: "prod", occurrence: 0)
        #expect(SidebarBuilder.hostEntry(for: prod, in: app.store.document) != nil)

        #expect(app.connectableAliases == ["a"])
        #expect(app.connectableAlias(for: prod) == nil)
        #expect(QuickConnectModel(app: app).entries.map(\.alias) == ["a"])
        #expect(await app.connect(alias: "prod") == .failed(.failed("not in the saved file")))
        #expect(launcher.requests.isEmpty)
        #expect(app.errorMessage == String(localized: "connect.notSaved"))
    }

    @Test func savedHostEditedWithoutSavingConnectsWithTheSavedAlias() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host Web\n  HostName 10.0.0.1\n", launcher: launcher)
        try app.store.apply { doc in
            let entry = doc.hosts[0]
            var draft = HostDraft(entry)
            draft.patterns = ["renamed"]
            try doc.updateHost(at: entry.headerLine, to: draft)
        }
        #expect(app.store.hasUnsavedChanges)
        #expect(app.connectableAlias(for: .host(alias: "renamed", occurrence: 0)) == nil)
        #expect(app.connectableAliases == ["Web"])
        #expect(await app.connect(alias: "web") == .failed(.failed("not in the saved file")))   // exact: ssh does not match web to Web
        #expect(launcher.requests.isEmpty)
        #expect(await app.connect(alias: "Web") == .launched(.terminal))
        #expect(launcher.requests.first?.sshArguments == ["--", "Web"])
    }

    @Test func savingMakesANewHostConnectable() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try app.store.apply { _ = try $0.addHost(HostDraft(patterns: ["b"])) }
        #expect(app.connectableAliases == ["a"])
        try await app.store.save()
        #expect(app.connectableAliases == ["a", "b"])
        #expect(app.connectableAlias(for: .host(alias: "b", occurrence: 0)) == "b")
    }

    @Test func fallbackIsAnInformationalNoticeNotAnError() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host a\n", launcher: launcher, isTerminalInstalled: { $0 == .terminal })
        app.settings.setTerminal(.ghostty)
        app.errorMessage = "stale"
        #expect(await app.connect(alias: "a") == .fellBack(from: .ghostty))
        #expect(app.errorMessage == nil)
        let name = TerminalChoice.ghostty.displayName
        #expect(app.fallbackNotice == String(localized: "connect.fellBack \(name)"))
        #expect(launcher.requests.count == 1)
    }

    @Test func customConfigUsesDashF() async throws {
        let tmp = try TempDir()
        try tmp.file("dot/config", "Host a\n")
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host z\n", launcher: launcher)
        #expect(app.switchConfig(to: tmp.url.appending(path: "dot/config").path) == .switched)
        await app.connect(alias: "a")
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

    @Test func launchScriptAndGhosttyUseTheRequestedProgram() throws {
        let request = LaunchRequest(sshArguments: ["-i", "/k.pub", "--", "a"], shellCommand: "ssh-copy-id -i /k.pub -- a", program: "/usr/bin/ssh-copy-id")
        #expect(LaunchScript.content(sshArguments: request.sshArguments, program: request.program)
                == "#!/bin/sh\nrm -f -- \"$0\"\nexec /usr/bin/ssh-copy-id '-i' '/k.pub' '--' 'a'\n")
        #expect(GhosttyArguments.openArguments(for: request) == ["-n", "-b", "com.mitchellh.ghostty", "--args", "--wait-after-command=true", "-e", "/usr/bin/ssh-copy-id", "-i", "/k.pub", "--", "a"])
        #expect(LaunchRequest(sshArguments: [], shellCommand: "ssh").program == "/usr/bin/ssh")
    }

    @Test func anUnsafeProgramPathIsRefused() throws {
        let tmp = try TempDir()
        let launcher = AppleScriptLauncher(makeSource: AppleScriptBuilder.terminal(scriptPath:), scriptDirectory: tmp.url)
        #expect(throws: LaunchError.self) {
            try launcher.prepare(LaunchRequest(sshArguments: [], shellCommand: "x", program: "/usr/bin/ssh; rm"))
        }
    }

    @Test func aSecondConnectWhileOneIsInFlightIsIgnored() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        var release: CheckedContinuation<Void, Never>?
        launcher.gate = { await withCheckedContinuation { release = $0 } }
        let app = makeTestModel(tmp, config: "Host a\n", launcher: launcher)
        let first = Task { await app.connect(alias: "a") }
        while release == nil { await Task.yield() }
        #expect(app.launchInFlight)
        #expect(await app.connect(alias: "a") == nil)
        #expect(await app.uploadKey(publicKey: tmp.url.appending(path: "k.pub"), alias: "a") == nil)
        launcher.gate = nil
        release?.resume()
        #expect(await first.value == .launched(.terminal))
        #expect(!app.launchInFlight)
        #expect(launcher.requests.count == 1)
        #expect(await app.connect(alias: "a") == .launched(.terminal))
    }

    @Test func launchErrorsAreLocalizedExceptOsAndSshMessages() {
        #expect(LaunchError.failed("ssh said no").userMessage == "ssh said no")
        #expect(LaunchError.unsafePath.userMessage == String(localized: "connect.error.unsafePath"))
        #expect(LaunchError.scriptWriteFailed.userMessage == String(localized: "connect.error.scriptWrite"))
        #expect(LaunchError.appleScriptUnavailable.userMessage == String(localized: "connect.error.appleScript"))
        #expect(LaunchError.openFailed(1).userMessage == String(localized: "connect.error.open \("1")"))
        #expect(LaunchError.automationDenied.userMessage == nil)
    }

    @Test func staleScriptSweepRemovesOnlyOldOwnScripts() throws {
        let tmp = try TempDir()
        let now = Date()
        func make(_ name: String, age: TimeInterval) throws -> URL {
            let url = tmp.url.appending(path: name)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        let old = try make("sshcm-\(UUID().uuidString).sh", age: 3600)
        let fresh = try make("sshcm-\(UUID().uuidString).sh", age: 30)
        let foreignOld = try make("other-\(UUID().uuidString).sh", age: 3600)
        let notUUID = try make("sshcm-notes.sh", age: 3600)
        let wrongExtension = try make("sshcm-\(UUID().uuidString).txt", age: 3600)
        // A symlink named like a script is never followed or removed.
        let target = try make("target.txt", age: 3600)
        let link = tmp.url.appending(path: "sshcm-\(UUID().uuidString).sh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        // A directory with a matching name is left alone.
        let dir = tmp.url.appending(path: "sshcm-\(UUID().uuidString).sh", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)

        #expect(LaunchScript.sweepStale(in: tmp.url, olderThan: 600, now: now) == 1)
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: old.path))
        for kept in [fresh, foreignOld, notUUID, wrongExtension, target, dir] { #expect(fm.fileExists(atPath: kept.path)) }
        #expect((try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(LaunchScript.sweepStale(in: tmp.url.appending(path: "missing"), now: now) == 0)
    }

    @Test func testsRunAgainstTheSavedFileOnly() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host Web\n  HostName 10.0.0.1\n")
        await app.test(alias: "web")   // ssh matches exactly: not a saved alias
        #expect(app.connectionTests.results.isEmpty)
        #expect(app.errorMessage == String(localized: "connect.notSaved"))
        app.errorMessage = nil
        await app.test(alias: "Web")
        #expect(app.connectionTests.results["Web"] != nil)
        #expect(app.errorMessage == nil)
    }
}
