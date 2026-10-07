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
}
