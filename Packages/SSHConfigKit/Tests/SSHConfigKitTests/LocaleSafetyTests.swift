import Foundation
import Testing

struct LocaleSafetyTests {
    @Test func sourcesAvoidLocaleSensitiveCaseAPIs() throws {
        let sources = URL(filePath: #filePath)
            .deletingLastPathComponent()          // SSHConfigKitTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // SSHConfigKit
            .appending(path: "Sources/SSHConfigKit")
        let forbidden = [
            "localizedCaseInsensitive", "caseInsensitiveCompare", "lowercased(with",
            "uppercased(with", "localizedLowercase", "localizedUppercase", ".caseInsensitive",
        ]
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for api in forbidden {
                #expect(!text.contains(api), "\(file.lastPathComponent) içinde yasak API: \(api)")
            }
        }
    }
}
