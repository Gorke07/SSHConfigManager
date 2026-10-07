import Foundation
import Testing
@testable import SSH_Config_Manager

/// The catalog/source rules live in scripts/check-localization.py (no repo file access from the hosted app).
struct LocalizationTests {
    @Test func turkishLocalizationIsCompiledIntoTheApp() throws {
        let path = try #require(Bundle.main.path(forResource: "tr", ofType: "lproj"))
        let turkish = try #require(Bundle(path: path))
        let englishPath = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: englishPath))
        let tr = turkish.localizedString(forKey: "app.title", value: nil, table: nil)
        let en = english.localizedString(forKey: "app.title", value: nil, table: nil)
        #expect(tr != "app.title")
        #expect(en != "app.title")
        #expect(tr != en)
    }

    @Test func automationPromptIsLocalized() throws {
        let key = "NSAppleEventsUsageDescription"
        let turkish = try #require(Bundle.main.path(forResource: "tr", ofType: "lproj").flatMap(Bundle.init(path:)))
        let english = try #require(Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        let tr = turkish.localizedString(forKey: key, value: nil, table: "InfoPlist")
        let en = english.localizedString(forKey: key, value: nil, table: "InfoPlist")
        #expect(tr == "SSH Config Manager, SSH bağlantılarını açmak için Terminal veya iTerm2'yi kontrol eder.")
        #expect(en == "SSH Config Manager opens your terminal and runs ssh for the host you choose.")
    }
}
