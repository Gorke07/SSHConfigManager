import Foundation
import Testing
@testable import SSHConfigKit

struct EffectiveOptionsTests {
    @Test func parsesSshGOutputIncludingRepeatedKeys() {
        let options = EffectiveOptions(parsing: """
        user ubuntu
        hostname 10.0.1.12
        port 2222
        identityfile ~/.ssh/a
        identityfile ~/.ssh/b
        proxyjump admin@bastion:2200,jump2
        sendenv LANG
        sendenv LC_*

        """)
        #expect(options.first("user") == "ubuntu")
        #expect(options.values["identityfile"] == ["~/.ssh/a", "~/.ssh/b"])
        #expect(options.jumpHops == [JumpHop(user: "admin", host: "bastion", port: 2200), JumpHop(user: nil, host: "jump2", port: nil)])
    }

    @Test(arguments: [
        ("none", [JumpHop]()),
        ("", []),
        ("bastion", [JumpHop(user: nil, host: "bastion", port: nil)]),
        ("ssh://me@h.example.com:22", [JumpHop(user: "me", host: "h.example.com", port: 22)]),
        ("[::1]:2200", [JumpHop(user: nil, host: "::1", port: 2200)]),
        ("me@[fe80::1]", [JumpHop(user: "me", host: "fe80::1", port: nil)]),
    ])
    func parsesJumpLists(_ value: String, _ expected: [JumpHop]) {
        #expect(JumpHop.parseList(value) == expected)
    }
}
