import Foundation
import Testing
@testable import SSHConfigKit

struct SSHCommandBuilderTests {
    @Test func defaultConfigNeedsNoFlag() throws {
        let home = try TempDir()
        let config = try home.file(".ssh/config", "")
        let builder = SSHCommandBuilder(configFile: config, homeDirectory: home.url)
        #expect(builder.usesDefaultConfig)
        #expect(builder.shellCommand(alias: "web") == "ssh -- web")
        #expect(builder.sshArguments(options: ["-T"], alias: "web") == ["-T", "--", "web"])
    }

    @Test func symlinkedDefaultConfigCountsAsDefault() throws {
        let home = try TempDir()
        let real = try home.file("dotfiles/ssh_config", "")
        try FileManager.default.createDirectory(at: home.url.appending(path: ".ssh"), withIntermediateDirectories: true)
        let link = home.url.appending(path: ".ssh/config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(SSHCommandBuilder(configFile: real, homeDirectory: home.url).usesDefaultConfig)
    }

    @Test func customConfigAddsQuotedFlag() {
        let builder = SSHCommandBuilder(
            configFile: URL(filePath: "/Users/x/My Dotfiles/ssh/config"), homeDirectory: URL(filePath: "/Users/x"))
        #expect(!builder.usesDefaultConfig)
        #expect(builder.configArguments == ["-F", "/Users/x/My Dotfiles/ssh/config"])
        #expect(builder.shellCommand(alias: "web") == "ssh -F '/Users/x/My Dotfiles/ssh/config' -- web")
    }

    @Test(arguments: [
        ("web-prod.example", "web-prod.example"),
        ("a'b", "'a'\\''b'"),
        ("$(rm -rf ~)", "'$(rm -rf ~)'"),
        ("a b", "'a b'"),
        ("~/x", "'~/x'"),
        ("", "''"),
        ("-oProxyCommand=x", "-oProxyCommand=x"),
    ])
    func shellQuote(input: String, expected: String) {
        #expect(SSHCommandBuilder.shellQuote(input) == expected)
    }

    @Test func dangerousAliasStaysAfterDoubleDash() {
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        #expect(builder.shellCommand(alias: "-oProxyCommand=touch /tmp/pwned") == "ssh -- '-oProxyCommand=touch /tmp/pwned'")
    }
}
