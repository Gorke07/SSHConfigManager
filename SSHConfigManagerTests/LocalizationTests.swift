import Foundation
import Testing
@testable import SSH_Config_Manager

/// Reads the String Catalog and the app's Swift sources straight from the repository.
enum LocalizationCatalog {
    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()   // SSHConfigManagerTests
        .deletingLastPathComponent()   // repo root
    static let sourcesRoot = repoRoot.appending(path: "SSHConfigManager")
    static let catalogURL = sourcesRoot.appending(path: "Shared/Localization/Localizable.xcstrings")

    /// key → language → (state, value)
    static func entries() throws -> [String: [String: (state: String, value: String)]] {
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        var result: [String: [String: (state: String, value: String)]] = [:]
        for (key, raw) in strings {
            let entry = raw as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any] ?? [:]
            var languages: [String: (state: String, value: String)] = [:]
            for (language, value) in localizations {
                let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any]
                languages[language] = (unit?["state"] as? String ?? "", unit?["value"] as? String ?? "")
            }
            result[key] = languages
        }
        return result
    }

    static func swiftSources() throws -> [(URL, String)] {
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        return try enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { ($0, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Keys used via `String(localized: "…")`, with `\(identifier)` interpolations turned into `%@`.
    static func sourceKeys() throws -> Set<String> {
        let pattern = /String\(localized:\s*"((?:[^"\\]|\\.)*)"/
        var keys = Set<String>()
        for (_, text) in try swiftSources() {
            for match in text.matches(of: pattern) {
                let key = String(match.1).replacing(/\\\([A-Za-z_][A-Za-z0-9_]*\)/, with: "%@")
                keys.insert(key)
            }
        }
        return keys
    }
}

struct LocalizationTests {
    @Test func catalogHasSourceLanguageEnglish() throws {
        let data = try Data(contentsOf: LocalizationCatalog.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en")
    }

    @Test func everyKeyHasTranslatedEnglishAndTurkish() throws {
        let entries = try LocalizationCatalog.entries()
        #expect(!entries.isEmpty)
        for (key, languages) in entries {
            for language in ["en", "tr"] {
                let unit = languages[language]
                #expect(unit?.state == "translated", "\(key) [\(language)] çevrilmemiş")
                #expect(!(unit?.value.isEmpty ?? true), "\(key) [\(language)] boş")
            }
        }
    }

    @Test func everySourceKeyIsInCatalogAndNoKeyIsUnused() throws {
        let catalogKeys = Set(try LocalizationCatalog.entries().keys)
        let sourceKeys = try LocalizationCatalog.sourceKeys()
        #expect(sourceKeys.subtracting(catalogKeys).isEmpty, "katalogda eksik: \(sourceKeys.subtracting(catalogKeys).sorted())")
        #expect(catalogKeys.subtracting(sourceKeys).isEmpty, "kullanılmayan: \(catalogKeys.subtracting(sourceKeys).sorted())")
    }

    @Test func interpolationsAreSimpleIdentifiers() throws {
        let localized = /String\(localized:\s*"((?:[^"\\]|\\.)*)"/
        let simple = /\\\([A-Za-z_][A-Za-z0-9_]*\)/
        for (url, text) in try LocalizationCatalog.swiftSources() {
            for match in text.matches(of: localized) {
                let body = String(match.1)
                let stripped = body.replacing(simple, with: "")
                #expect(!stripped.contains("\\("), "\(url.lastPathComponent): karmaşık interpolasyon: \(body)")
            }
        }
    }

    @Test func viewInitializersNeverTakeStringLiterals() throws {
        let literal = /\b(Text|Button|Label|Section|Toggle|TextField|Picker|Menu|LabeledContent)\(\s*"/
        for (url, text) in try LocalizationCatalog.swiftSources() {
            #expect(text.firstMatch(of: literal) == nil, "\(url.lastPathComponent): görünüm başlatıcısında string literal")
        }
    }

    @Test func turkishLocalizationIsCompiledIntoTheApp() throws {
        let path = try #require(Bundle.main.path(forResource: "tr", ofType: "lproj"))
        let turkish = try #require(Bundle(path: path))
        let entries = try LocalizationCatalog.entries()
        let title = try #require(entries["app.title"]?["tr"]?.value)
        #expect(turkish.localizedString(forKey: "app.title", value: nil, table: nil) == title)
    }
}
