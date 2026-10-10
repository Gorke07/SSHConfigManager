import Foundation

/// A one-shot SSH_ASKPASS helper (spec §8.3, §12.3), written per operation into a private 0700
/// directory. The script holds no secret: the passphrase is passed only in the child's environment.
/// It answers once; a second prompt (wrong passphrase) fails, so ssh-add stops asking.
struct AskPass {
    let directory: URL
    var helper: URL { directory.appending(path: "askpass") }
    var stateFile: URL { directory.appending(path: "answered") }

    static let script = """
    #!/bin/sh
    if [ -e "$SSHCM_ASKPASS_STATE" ]; then exit 1; fi
    : > "$SSHCM_ASKPASS_STATE"
    printf '%s\\n' "$SSHCM_ASKPASS_SECRET"

    """

    static func make(in parent: URL) throws -> AskPass {
        let fm = FileManager.default
        let directory = parent.appending(path: "sshcm-askpass-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let askPass = AskPass(directory: directory)
        guard fm.createFile(atPath: askPass.helper.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700]) else {
            askPass.remove()
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: askPass.helper.path])
        }
        do {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askPass.helper.path)   // umask may have narrowed it
        } catch {
            askPass.remove()
            throw error
        }
        return askPass
    }

    func environment(secret: String) -> [String: String] {
        [
            "SSH_ASKPASS": helper.path,
            "SSH_ASKPASS_REQUIRE": "force",
            "SSHCM_ASKPASS_STATE": stateFile.path,
            "SSHCM_ASKPASS_SECRET": secret,
        ]
    }

    var wasAsked: Bool { FileManager.default.fileExists(atPath: stateFile.path) }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
