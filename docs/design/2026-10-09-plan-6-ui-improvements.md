# Plan 6 — Arayüz Geliştirmeleri (v1.1): Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Son bağlanılanlar ve favoriler, akıllı arama, klavye kısayolları, bağlanma önizlemesi, etkin ayarlar ve kaynakları, ProxyJump zinciri, uyarı rozetleri, yorum tabanlı gruplar, durum özeti ve boş durum ekranı.

**Architecture:** Dosya formatı ve ssh semantiği bilen saf parçalar pakette: grup satırı okuma/yazma (`ConfigDocument`), ssh'in "ilk değer kazanır" kuralını uygulayan `ConfigResolver`, `ssh -G` çıktısı ve ProxyJump ayrıştırma, `HostLint`. Kullanıcıya dönük ve yerel ayara bağlı parçalar uygulamada: `FuzzyMatcher`, `HostMemory` (UserDefaults), `EffectiveConfigCache` (ssh -G önbelleği), menü/panel, kenar çubuğu, detay ve komut menüsü. Config'e uygulamaya özgü veri yazılmaz; tek istisna ssh'in yorum saydığı `# group:` satırı.

**Tech Stack:** Swift 6.4 (Xcode 27.0), SwiftUI (`CommandMenu`, `DisclosureGroup`, `AttributedString`), Swift Testing, XcodeGen.

**Spec:** `docs/design/2026-10-09-ui-improvements-design.md` (bu planın bağlayıcı kaynağı; ana spec `docs/design/2026-10-07-ssh-config-manager-design.md`).

## Global Constraints

- macOS 26.0; Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`. Yeni bağımlılık yok.
- Kayıpsız düzenleme: grup satırı dışında hiçbir bayt değişmez; `render(parse(x)) == x`.
- Pakette yerel ayara duyarlı büyük/küçük harf API'leri yasak (`LocaleSafetyTests`); ssh karşılaştırmaları ASCII büyük/küçük harf duyarsız. Kullanıcıya dönük arama (uygulamada) `folding([.caseInsensitive, .diacriticInsensitive], locale: .current)`.
- `ssh -G`: `/usr/bin/ssh`, `-F` yalnızca varsayılan dışı config'te, alias `--` sonrasında, 5 sn sınır, aynı anda en fazla 2.
- Connect/Test/önizleme/etkin ayarlar yalnızca **kaydedilmiş** dosyadaki hostlar için (ssh'in okuduğu).
- Kullanıcıya görünen her metin `String(localized:)` + `Localizable.xcstrings` (en + tr, `translated`, `extractionState: manual`); ssh anahtar kelimeleri, alias'lar, dosya yolları, ssh -G değerleri `Text(verbatim:)`. Checker: özellik yolu enterpolasyonu yok, sayılar `String` olarak `%@`.
- **Testler gerçek `~/.ssh`, `~/Library`, `UserDefaults.standard`, agent, keychain, pano, çöp kutusuna dokunmaz; gerçek ssh çalıştırmaz** (ssh -G sahte runner ile).
- **Kullanıcı Ghostty içinde çalışıyor:** terminaller ve pencereleri asla kapatılmaz/öldürülmez; sentetik tuş yok; yalnızca kendi süreçlerin PID ile; izin pencerelerine yanıt yok; uygulama açılmaz.
- Paket testleri `xcrun swift test --package-path Packages/SSHConfigKit`; uygulama `bash scripts/test-app.sh` (xcresult sayısı raporlanır).

## Review Focus

1. **`# group:` satırı Host'tan boş satırla ayrılmış, iki kez yazılmış ya da CRLF dosyada** — yalnızca bitişik bloktaki en yakın satır geçerli; yazma yalnızca o satırı değiştirir (Task 1'de test).
2. **Aynı seçeneği hem `Host *` hem host'un kendi bloğu veriyor; `Host *` önce** — ssh `Host *`'taki değeri kullanır ve kaynak "Host *" gösterilir, kendi bloğu değil (Task 2'de test).
3. **Aramada Türkçe/aksanlı harf ve büyük harf (`İSTANBUL-db`, `ışık`)** — aksan ve büyük/küçük harf duyarsız eşleşir; vurgulanan harfler doğru konumda (Task 4'te test).
4. **Favori/son listesindeki host dosyadan silinir ya da yeniden adlandırılır** — listede görünmez, çökme olmaz; config değişince listeler o dosyaya ait olur (Task 5'te test).
5. **ProxyJump döngüsü (`a → b → a`) ya da 6+ seviye** — zincir sonsuza gitmez, döngü işaretlenir (Task 8'de test).

---

## Dosya yapısı

```
Packages/SSHConfigKit/Sources/SSHConfigKit/
├── Config/HostGroup.swift            group(ofHostAt:), setGroup(ofHostAt:to:)
├── Config/IncludeResolver.swift      + includedDocuments(for:)
├── Resolve/ConfigResolver.swift      desen eşleşmesi, ilk-değer-kazanır, kaynaklar
├── Resolve/EffectiveOptions.swift    ssh -G çıktısı; ProxyJump atlamaları
└── Resolve/HostLint.swift            HostIssue, HostLint
SSHConfigManager/
├── Shared/FuzzyMatcher.swift
├── Shared/HostMemory.swift
├── Shared/EffectiveConfigCache.swift
├── Shared/AppModel.swift             memory, effectiveConfig, statusFilter, setGroup, lint, pendingDelete
├── App/HostCommandMenu.swift         CommandMenu "Host"
├── Features/QuickConnect/…           bölümler, vurgulama, önizleme, ⌥↩, ⌘S
├── Features/HostList/…               gruplar, yıldız, ⚠, grup alanı, durum özeti, boş durum
└── Features/HostDetail/EffectiveSettingsView.swift, ProxyChainModel.swift, ProxyChainView.swift
```

---

### Task 1: Grup satırı okuma ve yazma

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/HostGroup.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/HostGroupTests.swift`

**Interfaces:**
- Consumes: `ConfigDocument` (`lines`, `hostEntry(at:)`, `lineEndingSuffix`), `ConfigLine(raw:)`, `ConfigEditError.hostNotFound/.controlCharacter`, `String.containsControlCharacter`, `asciiLowercased`.
- Produces: `ConfigDocument.group(ofHostAt: Int) -> String?`, `mutating setGroup(ofHostAt: Int, to: String?) throws`, `static groupName(inCommentLine: String) -> String?`.

(Spec §9 `HostEntry.group` der; `HostEntry`'nin public init'ini değiştirmemek için grup belge üzerinden okunur. Bu bilinçli bir sapmadır.)

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct HostGroupTests {
    @Test(arguments: [
        ("# group: Production", "Production"),
        ("#group:prod", "prod"),
        ("   # GROUP :  Prod  ", "Prod"),
        ("# Group: Staging Servers\r", "Staging Servers"),
        ("# group:", ""),
    ])
    func parsesGroupComments(_ line: String, _ expected: String) {
        #expect(ConfigDocument.groupName(inCommentLine: line) == expected)
    }

    @Test(arguments: ["# groups: x", "# my group: x", "Host x", "# group x", ""])
    func ignoresOtherLines(_ line: String) {
        #expect(ConfigDocument.groupName(inCommentLine: line) == nil)
    }

    @Test func readsTheNearestGroupInTheGluedCommentBlock() {
        let doc = ConfigDocument(parsing: """
        # group: Old
        # web servers
        # group: Production
        Host web
          HostName 10.0.0.1

        # group: Detached

        Host db
        # group: Inside
        Host cache

        """)
        #expect(doc.group(ofHostAt: 3) == "Production")
        #expect(doc.group(ofHostAt: 8) == nil)                  // separated by a blank line
        #expect(doc.group(ofHostAt: 10) == "Inside")
    }

    @Test func emptyNameMeansNoGroup() {
        let doc = ConfigDocument(parsing: "# group:\nHost a\n")
        #expect(doc.group(ofHostAt: 1) == nil)
    }

    @Test func settingAddsChangesAndRemovesOnlyTheGroupLine() throws {
        let original = "# keep me\nHost a\n  User u\n\nHost b\n"
        var doc = ConfigDocument(parsing: original)
        try doc.setGroup(ofHostAt: 1, to: "  Prod ")
        #expect(doc.render() == "# keep me\n# group: Prod\nHost a\n  User u\n\nHost b\n")
        try doc.setGroup(ofHostAt: 2, to: "Staging")
        #expect(doc.render() == "# keep me\n# group: Staging\nHost a\n  User u\n\nHost b\n")
        try doc.setGroup(ofHostAt: 2, to: nil)
        #expect(doc.render().utf8.elementsEqual(original.utf8))
        try doc.setGroup(ofHostAt: 1, to: "")                    // no group line and nothing to add
        #expect(doc.render().utf8.elementsEqual(original.utf8))
    }

    @Test func crlfFilesGetCRLFGroupLines() throws {
        var doc = ConfigDocument(parsing: "Host a\r\n  User u\r\n")
        try doc.setGroup(ofHostAt: 0, to: "x")
        #expect(doc.render() == "# group: x\r\nHost a\r\n  User u\r\n")
    }

    @Test func refusesControlCharactersAndNonHosts() {
        var doc = ConfigDocument(parsing: "Host a\nMatch all\n")
        #expect(throws: ConfigEditError.controlCharacter) { try doc.setGroup(ofHostAt: 0, to: "a\nb") }
        #expect(throws: ConfigEditError.hostNotFound(1)) { try doc.setGroup(ofHostAt: 1, to: "x") }
    }

    @Test func removingAHostRemovesItsGroupLine() throws {
        var doc = ConfigDocument(parsing: "# group: g\nHost a\n\nHost b\n")
        try doc.removeHost(at: 1)
        #expect(doc.render() == "Host b\n")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter HostGroupTests`
Expected: FAIL — `no member 'groupName'`.

- [ ] **Step 3: Write minimal implementation**

`Packages/SSHConfigKit/Sources/SSHConfigKit/Config/HostGroup.swift`:

```swift
import Foundation

/// Groups are `# group: <name>` comment lines in the comment block glued to a `Host` line
/// (ssh ignores them). The line nearest to the Host wins.
extension ConfigDocument {
    /// The group name in a comment line, "" for `# group:` with no name, nil if not a group line.
    public static func groupName(inCommentLine raw: String) -> String? {
        var text = Substring(raw)
        if text.hasSuffix("\r") { text = text.dropLast() }
        text = text.drop { $0 == " " || $0 == "\t" }
        guard text.first == "#" else { return nil }
        text = text.dropFirst().drop { $0 == " " || $0 == "\t" }
        guard text.prefix(5).asciiLowercased == "group" else { return nil }
        text = text.dropFirst(5).drop { $0 == " " || $0 == "\t" }
        guard text.first == ":" else { return nil }
        return text.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    /// Index of the group line in the comment block directly above `header`, if any.
    func groupLineIndex(above header: Int) -> Int? {
        var index = header - 1
        while index >= 0, lines[index].kind == .comment {
            if Self.groupName(inCommentLine: lines[index].raw) != nil { return index }
            index -= 1
        }
        return nil
    }

    public func group(ofHostAt header: Int) -> String? {
        guard hostEntry(at: header) != nil, let index = groupLineIndex(above: header),
              let name = Self.groupName(inCommentLine: lines[index].raw), !name.isEmpty else { return nil }
        return name
    }

    /// Adds, replaces or (nil / empty name) removes the Host's group line; no other line changes.
    public mutating func setGroup(ofHostAt header: Int, to name: String?) throws {
        guard hostEntry(at: header) != nil else { throw ConfigEditError.hostNotFound(header) }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        guard !trimmed.containsControlCharacter else { throw ConfigEditError.controlCharacter }
        let line = ConfigLine(raw: "# group: " + trimmed + lineEndingSuffix)
        if let index = groupLineIndex(above: header) {
            if trimmed.isEmpty { lines.remove(at: index) } else { lines[index] = line }
        } else if !trimmed.isEmpty {
            lines.insert(line, at: header)
        }
    }
}
```

(If `ConfigEditError.controlCharacter` has a different shape, check `ConfigDocument+Edit.swift` and use the existing case; adjust the test accordingly. `trimmingCharacters(in: .whitespaces)` is locale-independent.)

- [ ] **Step 4: Run tests**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter HostGroupTests`, then the whole package (incl. round-trip and `LocaleSafetyTests`).
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): read and write '# group:' lines losslessly"
```

---

### Task 2: `ConfigResolver` — ssh'in "ilk değer kazanır" kuralı ve kaynaklar

**Files:**
- Modify: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/IncludeResolver.swift` (`includedDocuments(for:)`)
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Resolve/ConfigResolver.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConfigResolverTests.swift`

**Interfaces:**
- Consumes: `ConfigDocument.lines`, `LineKind`, `ValueFormatter.display(key:rawValue:)`, `IncludeResolver`, `asciiLowercased`.
- Produces:
  - `IncludeResolver.includedDocuments(for: IncludeDirective) -> [(file: URL, document: ConfigDocument)]`
  - `public enum OptionSource: Equatable, Sendable { case thisBlock, otherHost(patterns: [String]), global, include(file: URL, patterns: [String]) }`
  - `public struct ResolvedValue: Equatable, Sendable { value: String; source: OptionSource }`
  - `public struct ResolvedConfig: Equatable, Sendable { options: [String: [ResolvedValue]] (keys ASCII-lowercased); hasMatchBlocks: Bool; func first(_ key: String) -> ResolvedValue? }`
  - `public enum ConfigResolver { static let multiValueKeys: Set<String>; static func wildcardMatch(_:_:) -> Bool; static func hostLineMatches(_ patterns: [String], alias: String) -> Bool; static func resolve(alias:document:targetHeader:includes:) -> ResolvedConfig }` where `includes: (IncludeDirective) -> [(file: URL, document: ConfigDocument)]`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct ConfigResolverTests {
    func resolve(_ text: String, _ alias: String, target: Int? = nil,
                 includes: @escaping (IncludeDirective) -> [(file: URL, document: ConfigDocument)] = { _ in [] }) -> ResolvedConfig {
        let doc = ConfigDocument(parsing: text)
        let header = target ?? doc.hosts.first { $0.alias == alias }?.headerLine
        return ConfigResolver.resolve(alias: alias, document: doc, targetHeader: header, includes: includes)
    }

    @Test(arguments: [
        ("*", "anything", true), ("web-*", "web-01", true), ("web-?", "web-1", true), ("web-?", "web-10", false),
        ("*.example.com", "a.example.com", true), ("WEB", "web", true), ("info*", "INFO-db", true),
    ])
    func wildcards(_ pattern: String, _ text: String, _ expected: Bool) {
        #expect(ConfigResolver.wildcardMatch(pattern, text) == expected)
    }

    @Test func negationExcludesAndNeedsAPositive() {
        #expect(ConfigResolver.hostLineMatches(["*", "!bastion"], alias: "web"))
        #expect(!ConfigResolver.hostLineMatches(["*", "!bastion"], alias: "bastion"))
        #expect(!ConfigResolver.hostLineMatches(["!bastion"], alias: "web"))
    }

    @Test func firstObtainedValueWinsAndSourcesAreReported() {
        let config = resolve("""
        User global-user
        Host *
          User star-user
          Port 2200
        Host web
          User web-user
          HostName 10.0.0.1
        Host web-*
          ForwardAgent yes

        """, "web")
        #expect(config.first("user") == ResolvedValue(value: "global-user", source: .global))
        #expect(config.first("port") == ResolvedValue(value: "2200", source: .otherHost(patterns: ["*"])))
        #expect(config.first("hostname") == ResolvedValue(value: "10.0.0.1", source: .thisBlock))
        #expect(config.first("forwardagent") == nil)
    }

    @Test func hostStarBeforeTheBlockWins() {
        let config = resolve("Host *\n  Port 22\nHost web\n  Port 2222\n", "web")
        #expect(config.first("port")?.source == .otherHost(patterns: ["*"]))
        #expect(config.first("port")?.value == "22")
    }

    @Test func multiValueKeysAccumulateInOrder() {
        let config = resolve("Host web\n  IdentityFile ~/.ssh/a\nHost *\n  IdentityFile ~/.ssh/b\n  LocalForward 8080 localhost:80\n", "web")
        #expect(config.options["identityfile"]?.map(\.value) == ["~/.ssh/a", "~/.ssh/b"])
        #expect(config.options["localforward"]?.count == 1)
    }

    @Test func matchBlocksAreSkippedButRecorded() {
        let config = resolve("Host web\n  User a\nMatch exec \"true\"\n  Port 99\n", "web")
        #expect(config.first("port") == nil)
        #expect(config.hasMatchBlocks)
    }

    @Test func includesAreProcessedInPlaceAndRestoreTheParentState() {
        let included = ConfigDocument(parsing: "Host web\n  User from-include\nHost other\n  Port 1\n")
        let file = URL(filePath: "/h/.ssh/conf.d/a")
        let config = resolve("Host web\n  HostName h\nInclude conf.d/*\n  Port 2\n", "web") { _ in [(file, included)] }
        #expect(config.first("user") == ResolvedValue(value: "from-include", source: .include(file: file, patterns: ["web"])))
        // After the Include, the parent's "Host web" block is active again: Port 2 applies.
        #expect(config.first("port")?.value == "2")
        #expect(config.first("port")?.source == .thisBlock)
    }

    @Test func turkishLocaleDoesNotAffectMatching() {
        #expect(ConfigResolver.wildcardMatch("İnfo", "info") == false)   // non-ASCII is compared exactly
        #expect(ConfigResolver.wildcardMatch("INFO", "info"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter ConfigResolverTests`
Expected: FAIL — `cannot find 'ConfigResolver'`.

- [ ] **Step 3: Write minimal implementation**

`IncludeResolver.swift` — add (reusing the private `expand`):

```swift
    /// The files one Include directive names, parsed, in ssh's (sorted glob) order.
    public func includedDocuments(for include: IncludeDirective) -> [(file: URL, document: ConfigDocument)] {
        include.paths.flatMap(expand).compactMap { file in
            guard let data = try? Data(contentsOf: file), let text = String(validating: data, as: UTF8.self) else { return nil }
            return (file, ConfigDocument(parsing: text))
        }
    }
```

`Packages/SSHConfigKit/Sources/SSHConfigKit/Resolve/ConfigResolver.swift`:

```swift
import Foundation

public enum OptionSource: Equatable, Sendable {
    /// The target host's own block.
    case thisBlock
    /// Another `Host` block of the root file (e.g. `Host *`).
    case otherHost(patterns: [String])
    /// Before the first Host/Match line of the root file.
    case global
    /// A line in an included file (patterns of its Host block; empty outside any block).
    case include(file: URL, patterns: [String])
}

public struct ResolvedValue: Equatable, Sendable {
    public let value: String
    public let source: OptionSource

    public init(value: String, source: OptionSource) {
        self.value = value
        self.source = source
    }
}

public struct ResolvedConfig: Equatable, Sendable {
    /// ASCII-lowercased keys; single-valued options have one entry, multi-valued ones accumulate.
    public var options: [String: [ResolvedValue]] = [:]
    /// Match blocks are not evaluated; their options may still apply at run time.
    public var hasMatchBlocks = false

    public func first(_ key: String) -> ResolvedValue? { options[key.asciiLowercased]?.first }
}

/// Applies ssh_config(5)'s rule for one host: lines are read in order (Includes in place), a
/// `Host` line starts a block that applies when its patterns match, and for each option the first
/// obtained value is used — except options that may be given several times, which accumulate.
public enum ConfigResolver {
    public static let multiValueKeys: Set<String> = [
        "identityfile", "certificatefile", "localforward", "remoteforward", "dynamicforward", "sendenv", "setenv",
    ]

    /// `*` and `?` wildcards, ASCII case-insensitive (ssh lowercases host names).
    public static func wildcardMatch(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.asciiLowercased.unicodeScalars)
        let t = Array(text.asciiLowercased.unicodeScalars)
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count && (p[pi] == "?" || p[pi] == t[ti]) {
                pi += 1; ti += 1
            } else if pi < p.count && p[pi] == "*" {
                star = pi; mark = ti; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ti = mark
            } else {
                return false
            }
        }
        while pi < p.count && p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// A Host line matches when a positive pattern matches and no `!` pattern does.
    public static func hostLineMatches(_ patterns: [String], alias: String) -> Bool {
        var positive = false
        for pattern in patterns {
            if pattern.hasPrefix("!") {
                if wildcardMatch(String(pattern.dropFirst()), alias) { return false }
            } else if wildcardMatch(pattern, alias) {
                positive = true
            }
        }
        return positive
    }

    public static func resolve(
        alias: String,
        document: ConfigDocument,
        targetHeader: Int?,
        includes: (IncludeDirective) -> [(file: URL, document: ConfigDocument)]
    ) -> ResolvedConfig {
        var result = ResolvedConfig()
        walk(document, file: nil, depth: 0, alias: alias, targetHeader: targetHeader,
             active: true, blockSource: .global, includes: includes, into: &result)
        return result
    }

    private static func walk(
        _ document: ConfigDocument, file: URL?, depth: Int, alias: String, targetHeader: Int?,
        active startActive: Bool, blockSource startSource: OptionSource,
        includes: (IncludeDirective) -> [(file: URL, document: ConfigDocument)],
        into result: inout ResolvedConfig
    ) {
        guard depth < 16 else { return }
        var active = startActive
        var source = startSource
        for (index, line) in document.lines.enumerated() {
            switch line.kind {
            case .hostStart(let patterns):
                active = hostLineMatches(patterns, alias: alias)
                if let file {
                    source = .include(file: file, patterns: patterns)
                } else {
                    source = index == targetHeader ? .thisBlock : .otherHost(patterns: patterns)
                }
            case .matchStart:
                result.hasMatchBlocks = true
                active = false
            case .include(let paths):
                guard active else { continue }
                for (includedFile, included) in includes(IncludeDirective(line: index, paths: paths)) {
                    walk(included, file: includedFile, depth: depth + 1, alias: alias, targetHeader: nil,
                         active: true, blockSource: .include(file: includedFile, patterns: []),
                         includes: includes, into: &result)
                }
            case .directive(let key, let rawValue):
                guard active else { continue }
                let lower = key.asciiLowercased
                let value = ResolvedValue(value: ValueFormatter.display(key: key, rawValue: rawValue), source: source)
                if multiValueKeys.contains(lower) {
                    result.options[lower, default: []].append(value)
                } else if result.options[lower] == nil {
                    result.options[lower] = [value]
                }
            case .blank, .comment, .unknown:
                continue
            }
        }
    }
}
```

`IncludeDirective`'s memberwise init is internal to the package, which is fine here (same module). In an included file the walk starts **active** (an `Include` inside a matching block includes unconditionally until the file's own first `Host`), and the parent's `active`/`source` are restored afterwards because they are local to the parent's walk.

- [ ] **Step 4: Run tests**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter ConfigResolverTests`, then the whole package.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): resolve a host's options with their sources (first value wins)"
```

---

### Task 3: `ssh -G` çıktısı, ProxyJump atlamaları ve `HostLint`

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Resolve/EffectiveOptions.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Resolve/HostLint.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/EffectiveOptionsTests.swift`, `HostLintTests.swift`

**Interfaces:**
- Consumes: `KeyUsage.resolve(_:home:)`, `KeyFileInspector`, `KeyEncryption`, `HostEntry`, `IncludedHost`, `ConfigResolver.wildcardMatch`.
- Produces:
  - `public struct EffectiveOptions: Equatable, Sendable { values: [String: [String]]; init(parsing: String); func first(_:) -> String?; var jumpHops: [JumpHop] }`
  - `public struct JumpHop: Equatable, Sendable { user: String?; host: String; port: Int?; static func parseList(_: String) -> [JumpHop] }`
  - `public enum HostIssue: Equatable, Sendable { case missingIdentityFile(String), duplicateAlias(alias: String, isFirst: Bool), unencryptedKey(String) }`
  - `public struct HostLint: Sendable { init(home:fileExists:encryption:); func issues(for: HostEntry, duplicates: [String: Int]) -> [HostIssue]; static func duplicateCounts(document: ConfigDocument, included: [IncludedHost]) -> [String: Int]; static func occurrence(ofHostAt:in:) -> Int }`

- [ ] **Step 1: Write the failing tests**

`EffectiveOptionsTests.swift`:

```swift
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
```

`HostLintTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct HostLintTests {
    let home = URL(filePath: "/h")

    func lint(existing: Set<String> = [], unencrypted: Set<String> = []) -> HostLint {
        HostLint(home: home,
                 fileExists: { existing.contains($0.path) },
                 encryption: { unencrypted.contains($0.path) ? .unencrypted : .encrypted })
    }

    @Test func missingIdentityFilesAreReportedButUnresolvableOnesAreNot() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/gone\n  IdentityFile ~/.ssh/here\n  IdentityFile ~/.ssh/id_%h\n")
        let issues = lint(existing: ["/h/.ssh/here"]).issues(for: doc.hosts[0], duplicates: [:])
        #expect(issues == [.missingIdentityFile("~/.ssh/gone")])
    }

    @Test func unencryptedKeysAreReported() {
        let doc = ConfigDocument(parsing: "Host a\n  IdentityFile ~/.ssh/plain\n")
        let issues = lint(existing: ["/h/.ssh/plain"], unencrypted: ["/h/.ssh/plain"]).issues(for: doc.hosts[0], duplicates: [:])
        #expect(issues == [.unencryptedKey("~/.ssh/plain")])
    }

    @Test func duplicateAliasesAcrossFileAndIncludesCaseInsensitively() {
        let doc = ConfigDocument(parsing: "Host web\n  User a\nHost WEB other\n  User b\nHost *\n")
        let included = [IncludedHost(file: URL(filePath: "/h/.ssh/inc"), entry: ConfigDocument(parsing: "Host web\n").hosts[0])]
        let counts = HostLint.duplicateCounts(document: doc, included: included)
        #expect(counts["web"] == 3)
        #expect(counts["other"] == nil)
        #expect(counts["*"] == nil)
        let first = lint().issues(for: doc.hosts[0], duplicates: counts)
        #expect(first == [.duplicateAlias(alias: "web", isFirst: true)])
        let second = lint().issues(for: doc.hosts[1], duplicates: counts, isFirstOccurrence: false)
        #expect(second == [.duplicateAlias(alias: "WEB", isFirst: false)])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter "EffectiveOptionsTests|HostLintTests"`
Expected: FAIL to build.

- [ ] **Step 3: Write minimal implementation**

`EffectiveOptions.swift`:

```swift
import Foundation

/// `ssh -G` output: one lowercase option name and its value per line; some options repeat.
public struct EffectiveOptions: Equatable, Sendable {
    public let values: [String: [String]]

    public init(parsing output: String) {
        var values: [String: [String]] = [:]
        for line in output.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0]).asciiLowercased, default: []].append(String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
        self.values = values
    }

    public func first(_ key: String) -> String? { values[key.asciiLowercased]?.first }

    public var jumpHops: [JumpHop] { first("proxyjump").map(JumpHop.parseList) ?? [] }
}

/// One `ProxyJump` hop: `[user@]host[:port]`, `ssh://[user@]host[:port]`, IPv6 in brackets.
public struct JumpHop: Equatable, Sendable {
    public let user: String?
    public let host: String
    public let port: Int?

    public init(user: String?, host: String, port: Int?) {
        self.user = user
        self.host = host
        self.port = port
    }

    public static func parseList(_ value: String) -> [JumpHop] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.asciiLowercased != "none" else { return [] }
        return trimmed.split(separator: ",").compactMap { parse(String($0).trimmingCharacters(in: .whitespaces)) }
    }

    static func parse(_ text: String) -> JumpHop? {
        var rest = Substring(text)
        if rest.hasPrefix("ssh://") { rest = rest.dropFirst(6) }
        var user: String?
        if let at = rest.lastIndex(of: "@") {
            user = String(rest[..<at])
            rest = rest[rest.index(after: at)...]
        }
        var host: String
        var port: Int?
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = String(rest[rest.index(after: rest.startIndex)..<close])
            let after = rest[rest.index(after: close)...]
            if after.hasPrefix(":") { port = Int(after.dropFirst()) }
        } else if let colon = rest.lastIndex(of: ":"), rest.filter({ $0 == ":" }).count == 1 {
            host = String(rest[..<colon])
            port = Int(rest[rest.index(after: colon)...])
        } else {
            host = String(rest)
        }
        guard !host.isEmpty else { return nil }
        if let port, !(1...65535).contains(port) { return nil }
        return JumpHop(user: user, host: host, port: port)
    }
}
```

`HostLint.swift`:

```swift
import Foundation

public enum HostIssue: Equatable, Sendable {
    /// The IdentityFile value as written.
    case missingIdentityFile(String)
    /// Several blocks name this alias; ssh uses the first block's values and later ones only add what is missing.
    case duplicateAlias(alias: String, isFirst: Bool)
    case unencryptedKey(String)
}

/// Problems a person would want to see next to a host. File access is injected so tests never
/// touch the disk; the app passes FileManager and KeyFileInspector.
public struct HostLint: Sendable {
    private let home: URL
    private let fileExists: @Sendable (URL) -> Bool
    private let encryption: @Sendable (URL) -> KeyEncryption

    public init(home: URL, fileExists: @escaping @Sendable (URL) -> Bool, encryption: @escaping @Sendable (URL) -> KeyEncryption) {
        self.home = home
        self.fileExists = fileExists
        self.encryption = encryption
    }

    /// Non-pattern aliases (ASCII-lowercased) that appear in more than one Host block.
    public static func duplicateCounts(document: ConfigDocument, included: [IncludedHost]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in document.hosts + included.map(\.entry) {
            let names = Set(entry.patterns.filter { !$0.hasPrefix("!") && !$0.contains("*") && !$0.contains("?") }.map(\.asciiLowercased))
            for name in names { counts[name, default: 0] += 1 }
        }
        return counts.filter { $0.value > 1 }
    }

    public func issues(for entry: HostEntry, duplicates: [String: Int], isFirstOccurrence: Bool = true) -> [HostIssue] {
        var result: [HostIssue] = []
        if !entry.isPattern, duplicates[entry.alias.asciiLowercased] != nil {
            result.append(.duplicateAlias(alias: entry.alias, isFirst: isFirstOccurrence))
        }
        for value in entry.values(for: "IdentityFile") {
            guard let url = KeyUsage.resolve(value, home: home) else { continue }
            if !fileExists(url) {
                result.append(.missingIdentityFile(value))
            } else if encryption(url) == .unencrypted {
                result.append(.unencryptedKey(value))
            }
        }
        return result
    }
}
```

(`isFirstOccurrence` is computed by the caller: the first block with that lowercased alias in file order, then includes.)

- [ ] **Step 4: Run tests**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter "EffectiveOptionsTests|HostLintTests"`, then the whole package.
Expected: PASS. Fix the `HostLintTests.duplicateAliases…` test's first `issues(for:duplicates:)` call to pass `isFirstOccurrence: true` explicitly if the default makes the intent unclear.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): ssh -G options, ProxyJump hops and host lint"
```

---

### Task 4: `FuzzyMatcher` (uygulama)

**Files:**
- Create: `SSHConfigManager/Shared/FuzzyMatcher.swift`
- Test: `SSHConfigManagerTests/FuzzyMatcherTests.swift`

**Interfaces:**
- Produces: `struct FuzzyMatch: Equatable { score: Int; aliasOffsets: [Int] }`; `enum FuzzyMatcher { static func match(query: String, alias: String, others: [String]) -> FuzzyMatch?; static func highlighted(_ alias: String, offsets: [Int]) -> AttributedString }`.

Puanlar (kelime başına): alias tam eşleşme 1000, alias baştan 800, alias kelime başlarından 600, alias dağınık 300 − (aradaki boşluk sayısı, en fazla 200), yalnızca diğer alanlar 100. Sorgunun puanı kelime puanlarının toplamı; bir kelime eşleşmezse `nil`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import SSH_Config_Manager

struct FuzzyMatcherTests {
    @Test func tiersOrderResults() throws {
        let exact = try #require(FuzzyMatcher.match(query: "web", alias: "web", others: []))
        let prefix = try #require(FuzzyMatcher.match(query: "web", alias: "web-01", others: []))
        let wordStart = try #require(FuzzyMatcher.match(query: "pw", alias: "prod-web", others: []))
        let scattered = try #require(FuzzyMatcher.match(query: "prd", alias: "prod-web-01", others: []))
        let other = try #require(FuzzyMatcher.match(query: "10.0", alias: "db", others: ["10.0.0.5"]))
        #expect(exact.score > prefix.score && prefix.score > wordStart.score && wordStart.score > scattered.score && scattered.score > other.score)
    }

    @Test func everyWordMustMatch() {
        #expect(FuzzyMatcher.match(query: "prd web", alias: "prod-web-01", others: []) != nil)
        #expect(FuzzyMatcher.match(query: "prd xyz", alias: "prod-web-01", others: []) == nil)
        #expect(FuzzyMatcher.match(query: "prd ubuntu", alias: "prod-web-01", others: ["ubuntu"]) != nil)
    }

    @Test func offsetsPointAtTheMatchedCharacters() throws {
        #expect(try #require(FuzzyMatcher.match(query: "pw", alias: "prod-web", others: [])).aliasOffsets == [0, 5])
        #expect(try #require(FuzzyMatcher.match(query: "prd", alias: "prod-web-01", others: [])).aliasOffsets == [0, 1, 3])
        #expect(try #require(FuzzyMatcher.match(query: "web", alias: "web-01", others: [])).aliasOffsets == [0, 1, 2])
    }

    @Test func caseAndDiacriticsAreIgnored() throws {
        #expect(FuzzyMatcher.match(query: "istanbul", alias: "İSTANBUL-db", others: []) != nil)
        #expect(FuzzyMatcher.match(query: "isik", alias: "ışık", others: []) != nil)
        let match = try #require(FuzzyMatcher.match(query: "db", alias: "İSTANBUL-db", others: []))
        #expect(match.aliasOffsets == [9, 10])
    }

    @Test func highlightingMakesMatchedCharactersBold() {
        let text = FuzzyMatcher.highlighted("prod", offsets: [0, 3])
        let bold = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(text[$0.range].characters) }
        #expect(bold == ["p", "d"])
    }
}
```

(Turkish dotless `ı` folds to `ı` under `.diacriticInsensitive`, not to `i`; if `isik`/`ışık` does not match after folding, map `ı`→`i` and `İ`→`i` explicitly in `fold` before folding — users type `i` for both — and keep the test.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/FuzzyMatcherTests`
Expected: FAIL to build.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct FuzzyMatch: Equatable {
    let score: Int
    /// Character offsets in the alias that matched (for highlighting).
    let aliasOffsets: [Int]
}

/// User-facing host search (spec v1.1 §3): every word must match the alias fuzzily or another
/// field as a substring; case and diacritics are ignored.
enum FuzzyMatcher {
    /// Folds one character at a time so offsets stay aligned with the original alias.
    static func fold(_ text: String) -> [String] {
        text.map { character -> String in
            switch character {
            case "ı", "I", "İ": "i"
            default: String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            }
        }
    }

    static func match(query: String, alias: String, others: [String]) -> FuzzyMatch? {
        let words = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)).joined() }
        guard !words.isEmpty else { return FuzzyMatch(score: 0, aliasOffsets: []) }
        let folded = fold(alias)
        let foldedOthers = others.map { fold($0).joined() }
        var score = 0
        var offsets = Set<Int>()
        for word in words {
            if let hit = aliasMatch(Array(word), in: folded) {
                score += hit.score
                offsets.formUnion(hit.offsets)
            } else if foldedOthers.contains(where: { $0.contains(word) }) {
                score += 100
            } else {
                return nil
            }
        }
        return FuzzyMatch(score: score, aliasOffsets: offsets.sorted())
    }

    private static func isWordStart(_ index: Int, in folded: [String]) -> Bool {
        guard index > 0 else { return true }
        let previous = folded[index - 1], current = folded[index]
        if ["-", ".", "_", " "].contains(previous) { return true }
        let previousIsDigit = previous.allSatisfy(\.isNumber), currentIsDigit = current.allSatisfy(\.isNumber)
        return previousIsDigit != currentIsDigit
    }

    private static func aliasMatch(_ word: [Character], in folded: [String]) -> (score: Int, offsets: [Int])? {
        let target = folded.joined()
        let characters = folded.map { $0.first ?? " " }
        if target == String(word) { return (1000, Array(folded.indices)) }
        if target.hasPrefix(String(word)), folded.count >= word.count, folded.allSatisfy({ $0.count == 1 }) {
            return (800, Array(0..<word.count))
        }
        // Word starts: each character continues the previous match or jumps to the next word start.
        var offsets: [Int] = []
        var position = 0
        var ok = true
        for (n, character) in word.enumerated() {
            if n > 0, let last = offsets.last, last + 1 < characters.count, characters[last + 1] == character {
                offsets.append(last + 1); position = last + 2; continue
            }
            guard let index = (position..<characters.count).first(where: { characters[$0] == character && isWordStart($0, in: folded) }) else {
                ok = false; break
            }
            offsets.append(index); position = index + 1
        }
        if ok { return (600, offsets) }
        // Scattered: plain subsequence.
        offsets = []
        position = 0
        for character in word {
            guard let index = (position..<characters.count).first(where: { characters[$0] == character }) else { return nil }
            offsets.append(index); position = index + 1
        }
        let gaps = zip(offsets, offsets.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0 - 1) }
        return (300 - min(gaps, 200), offsets)
    }

    static func highlighted(_ alias: String, offsets: [Int]) -> AttributedString {
        var result = AttributedString()
        let wanted = Set(offsets)
        for (index, character) in alias.enumerated() {
            var piece = AttributedString(String(character))
            if wanted.contains(index) { piece.inlinePresentationIntent = .stronglyEmphasized }
            result += piece
        }
        return result
    }
}
```

(The prefix check requires one folded character per original character so offsets stay valid; otherwise the word-start path handles it.)

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/FuzzyMatcherTests`, then `bash scripts/test-app.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat: fuzzy host matching with highlights"
```

---

### Task 5: `HostMemory` — son bağlanılanlar ve favoriler

**Files:**
- Create: `SSHConfigManager/Shared/HostMemory.swift`
- Modify: `SSHConfigManager/Shared/AppSettings.swift` (`userDefaults` accessor), `SSHConfigManager/Shared/AppModel.swift`
- Test: `SSHConfigManagerTests/HostMemoryTests.swift`

**Interfaces:**
- Consumes: `AppSettings` (`defaults`), `AppModel.backupKind(for:home:)`, `connect(alias:)`'s outcome handling (`launch`), `savedAlias(_:)`.
- Produces:
  - `@MainActor @Observable final class HostMemory { init(defaults: UserDefaults, key: String); private(set) var favorites: [String]; private(set) var recents: [String]; func isFavorite(_:) -> Bool; func toggleFavorite(_:); func recordConnection(_:) }`, `static let maxRecents = 5`, `static let maxFavorites = 50`
  - `AppModel.memory: HostMemory` (rebuilt in `switchConfig`), `AppModel.favoriteAliases: [String]` / `recentAliases: [String]` (filtered to saved hosts, written case), `AppModel.toggleFavorite(_ alias: String)`; `connect(alias:)` records `.launched`/`.fellBack`.
  - `AppSettings.userDefaults: UserDefaults`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct HostMemoryTests {
    @Test func recentsAreMostRecentFirstUniqueAndCapped() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "hostMemory.config")
        for alias in ["a", "b", "c", "d", "e", "f", "B"] { memory.recordConnection(alias) }
        #expect(memory.recents == ["B", "f", "e", "d", "c"])
        let reloaded = HostMemory(defaults: tmp.defaults, key: "hostMemory.config")
        #expect(reloaded.recents == memory.recents)
    }

    @Test func favoritesToggleCaseInsensitivelyAndPersist() throws {
        let tmp = try TempDir()
        let memory = HostMemory(defaults: tmp.defaults, key: "k")
        memory.toggleFavorite("Web")
        #expect(memory.isFavorite("web"))
        memory.toggleFavorite("WEB")
        #expect(!memory.isFavorite("web"))
        memory.toggleFavorite("db")
        #expect(HostMemory(defaults: tmp.defaults, key: "k").favorites == ["db"])
    }

    @Test func appModelRecordsSuccessfulConnectsAndHidesUnsavedOrRemovedHosts() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\nHost db\n")
        model.connect(alias: "web")
        model.toggleFavorite("db")
        model.memory.recordConnection("gone")           // e.g. removed from the file later
        #expect(model.recentAliases == ["web"])
        #expect(model.favoriteAliases == ["db"])
    }

    @Test func failedConnectsAreNotRecorded() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        launcher.error = .failed("x")
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher)
        model.connect(alias: "web")
        #expect(model.recentAliases.isEmpty)
    }

    @Test func eachConfigFileHasItsOwnMemory() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n")
        model.toggleFavorite("web")
        try tmp.file("other/config", "Host web\n")
        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path) == .switched)
        #expect(model.favoriteAliases.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/HostMemoryTests`
Expected: FAIL to build.

- [ ] **Step 3: Write minimal implementation**

`SSHConfigManager/Shared/HostMemory.swift`:

```swift
import Foundation
import Observation

/// Recently connected and favorite aliases of one config file, kept in UserDefaults
/// (spec v1.1 §2). Nothing is written to the config file.
@MainActor
@Observable
final class HostMemory {
    static let maxRecents = 5
    static let maxFavorites = 50

    private(set) var favorites: [String]
    private(set) var recents: [String]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
        let stored = defaults.dictionary(forKey: key)
        favorites = stored?["favorites"] as? [String] ?? []
        recents = stored?["recents"] as? [String] ?? []
    }

    func isFavorite(_ alias: String) -> Bool {
        favorites.contains { Self.same($0, alias) }
    }

    func toggleFavorite(_ alias: String) {
        if isFavorite(alias) {
            favorites.removeAll { Self.same($0, alias) }
        } else if favorites.count < Self.maxFavorites {
            favorites.append(alias)
        }
        save()
    }

    func recordConnection(_ alias: String) {
        recents.removeAll { Self.same($0, alias) }
        recents.insert(alias, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        save()
    }

    /// ssh matches host names ASCII case-insensitively.
    static func same(_ a: String, _ b: String) -> Bool {
        a.utf8.count == b.utf8.count && zip(a.unicodeScalars, b.unicodeScalars).allSatisfy { x, y in
            lower(x) == lower(y)
        }
    }

    private static func lower(_ scalar: Unicode.Scalar) -> UInt32 {
        (65...90).contains(scalar.value) ? scalar.value + 32 : scalar.value
    }

    private func save() {
        defaults.set(["favorites": favorites, "recents": recents], forKey: key)
    }
}
```

`AppSettings.swift`: `var userDefaults: UserDefaults { defaults }`.

`AppModel.swift`:

```swift
    private(set) var memory: HostMemory

    static func memoryKey(for url: URL, home: URL) -> String {
        "hostMemory." + backupKind(for: url, home: home)
    }
```

Init (with the other stored properties): `self.memory = HostMemory(defaults: settings.userDefaults, key: Self.memoryKey(for: settings.configURL, home: settings.homeDirectory))`. In `switchConfig` after replacing the store: `memory = HostMemory(defaults: settings.userDefaults, key: Self.memoryKey(for: url, home: settings.homeDirectory))`.

```swift
    /// Favorites that are hosts of the saved file, as written there.
    var favoriteAliases: [String] { memory.favorites.compactMap(savedAlias) }

    /// Recently connected saved hosts, most recent first.
    var recentAliases: [String] { memory.recents.compactMap(savedAlias) }

    func toggleFavorite(_ alias: String) {
        memory.toggleFavorite(savedAlias(alias) ?? alias)
    }
```

In `connect(alias:)`, after `let outcome = launch(request)` (or wherever the outcome is known): on `.launched` or `.fellBack`, `memory.recordConnection(alias)`. `uploadKey` does not record.

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/HostMemoryTests`, then `bash scripts/test-app.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat: remember recent and favorite hosts per config file"
```

---

### Task 6: `EffectiveConfigCache` — ssh -G önbelleği

**Files:**
- Create: `SSHConfigManager/Shared/EffectiveConfigCache.swift`
- Modify: `SSHConfigManager/Shared/AppModel.swift`
- Test: `SSHConfigManagerTests/EffectiveConfigCacheTests.swift`

**Interfaces:**
- Consumes: `EffectiveOptions(parsing:)` (Task 3), `ProcessRunning`, `SSHCommandBuilder.sshArguments(options:alias:)`, `HostMemory.same`.
- Produces: `@MainActor @Observable final class EffectiveConfigCache { init(runner:); func options(for alias: String) -> EffectiveOptions?; func failure(for alias: String) -> String?; func load(_ alias: String, using: SSHCommandBuilder) async; func clear(); static let maxConcurrent = 2 }`; `AppModel.effectiveConfig`, cleared in `savedStateDidChange()` and `switchConfig`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Synchronization
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

/// Counts runs and tracks the peak number running at once.
final class PeakRunner: ProcessRunning, @unchecked Sendable {
    let delay: Duration
    let output: String
    private let state = Mutex((running: 0, peak: 0, runs: 0, lastArguments: [String]()))
    var peak: Int { state.withLock { $0.peak } }
    var runs: Int { state.withLock { $0.runs } }
    var lastArguments: [String] { state.withLock { $0.lastArguments } }
    init(delay: Duration, output: String) { self.delay = delay; self.output = output }
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        state.withLock { $0.running += 1; $0.peak = max($0.peak, $0.running); $0.runs += 1; $0.lastArguments = arguments }
        try? await Task.sleep(for: delay)
        state.withLock { $0.running -= 1 }
        return ProcessResult(exitCode: 0, stdout: output, stderr: "", timedOut: false)
    }
}

@MainActor
struct EffectiveConfigCacheTests {
    let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))

    @Test func loadsOnceAndCachesCaseInsensitively() async {
        let runner = PeakRunner(delay: .milliseconds(10), output: "hostname 10.0.0.1\nport 22\n")
        let cache = EffectiveConfigCache(runner: runner)
        await cache.load("web", using: builder)
        await cache.load("WEB", using: builder)
        #expect(runner.runs == 1)
        #expect(cache.options(for: "Web")?.first("hostname") == "10.0.0.1")
        #expect(runner.lastArguments == ["-G", "--", "web"])
    }

    @Test func atMostTwoRunAtOnceAndConcurrentRequestsShareOneRun() async {
        let runner = PeakRunner(delay: .milliseconds(150), output: "hostname h\n")
        let cache = EffectiveConfigCache(runner: runner)
        await withTaskGroup(of: Void.self) { group in
            for alias in ["a", "b", "c", "d", "a"] { group.addTask { await cache.load(alias, using: builder) } }
        }
        #expect(runner.peak <= 2)
        #expect(runner.runs == 4)
    }

    @Test func clearDropsResultsAndLateAnswers() async {
        let runner = PeakRunner(delay: .milliseconds(200), output: "hostname h\n")
        let cache = EffectiveConfigCache(runner: runner)
        let task = Task { await cache.load("a", using: builder) }
        try? await Task.sleep(for: .milliseconds(50))
        cache.clear()
        await task.value
        #expect(cache.options(for: "a") == nil)
    }

    @Test func failuresAreKept() async {
        let cache = EffectiveConfigCache(runner: FixedRunner.invalid("Bad configuration option: x"))
        await cache.load("a", using: builder)
        #expect(cache.options(for: "a") == nil)
        #expect(cache.failure(for: "a") == "Bad configuration option: x")
    }

    @Test func appModelClearsItWhenTheSavedFileChanges() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n",
                                  runner: FixedRunner(result: ProcessResult(exitCode: 0, stdout: "hostname h\n", stderr: "", timedOut: false)))
        await model.effectiveConfig.load("web", using: model.commandBuilder)
        #expect(model.effectiveConfig.options(for: "web") != nil)
        try tmp.file(".ssh/config", "Host web\n  Port 2\n")
        model.store.load()
        #expect(model.effectiveConfig.options(for: "web") == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/EffectiveConfigCacheTests`
Expected: FAIL to build.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import Observation
import SSHConfigKit

/// `ssh -G` results per alias (spec v1.1 §5–6): at most two at once, one run per alias,
/// cleared whenever the saved file changes.
@MainActor
@Observable
final class EffectiveConfigCache {
    static let maxConcurrent = 2

    private(set) var results: [String: EffectiveOptions] = [:]
    private(set) var failures: [String: String] = [:]
    @ObservationIgnored private let runner: any ProcessRunning
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var running = 0
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var generation = 0

    init(runner: any ProcessRunning) {
        self.runner = runner
    }

    private static func key(_ alias: String) -> String {
        String(String.UnicodeScalarView(alias.unicodeScalars.map { (65...90).contains($0.value) ? Unicode.Scalar($0.value + 32)! : $0 }))
    }

    func options(for alias: String) -> EffectiveOptions? { results[Self.key(alias)] }
    func failure(for alias: String) -> String? { failures[Self.key(alias)] }

    func load(_ alias: String, using builder: SSHCommandBuilder) async {
        let key = Self.key(alias)
        if results[key] != nil || failures[key] != nil { return }
        if let task = inFlight[key] { await task.value; return }
        let currentGeneration = generation
        let task = Task { [runner] in
            await self.acquire()
            defer { self.release() }
            let outcome: Result<ProcessResult, any Error>
            do {
                outcome = .success(try await runner.run(URL(filePath: "/usr/bin/ssh"),
                                                        arguments: builder.sshArguments(options: ["-G"], alias: alias),
                                                        environment: [:], timeout: .seconds(5)))
            } catch {
                outcome = .failure(error)
            }
            guard currentGeneration == self.generation else { return }
            switch outcome {
            case .success(let result) where result.exitCode == 0 && !result.timedOut:
                self.results[key] = EffectiveOptions(parsing: result.stdout)
            case .success(let result):
                self.failures[key] = result.timedOut ? "timed out" : ConnectionClassifier.firstLine(result.stderr)
            case .failure(let error):
                self.failures[key] = error.localizedDescription
            }
        }
        inFlight[key] = task
        await task.value
        if inFlight[key] == task { inFlight[key] = nil }
    }

    func clear() {
        generation += 1
        results = [:]
        failures = [:]
        inFlight = [:]
    }

    private func acquire() async {
        if running < Self.maxConcurrent { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
}
```

(A "timed out" failure is internal; the UI maps failures to a localized "could not read ssh -G" message plus the detail verbatim.)

`AppModel`: `let effectiveConfig: EffectiveConfigCache` created with `processRunner` in init; call `effectiveConfig.clear()` in `savedStateDidChange()` and in `switchConfig` (after replacing the store).

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/EffectiveConfigCacheTests` (3 times — concurrency), then `bash scripts/test-app.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat: cached ssh -G results with bounded concurrency"
```

---

### Task 7: Hızlı bağlanma — bölümler, akıllı arama, önizleme, ⌥↩ ve ⌘S

**Files:**
- Modify: `SSHConfigManager/Features/QuickConnect/QuickConnectModel.swift`, `QuickConnectView.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`, `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/QuickConnectModelTests.swift`

**Interfaces:**
- Consumes: Tasks 4–6 (`FuzzyMatcher`, `AppModel.favoriteAliases/recentAliases/toggleFavorite/memory`, `effectiveConfig`), Task 1 (`ConfigDocument.group(ofHostAt:)`), `app.savedConnectableHosts` (`SavedHost.entry`, `.isIncluded`), `app.store.savedDocument`, `commandBuilder.shellCommand(alias:)`.
- Produces: `QuickConnectEntry { alias, subtitle, isIncluded, group: String?, section: QuickConnectSection?, aliasOffsets: [Int], isFavorite: Bool }`; `enum QuickConnectSection { case favorites, recents, all }`; `QuickConnectModel.init(app:openMainWindow:copyToPasteboard:)`; `copySelectedCommand()`, `toggleFavoriteSelected()`, `previewText(for:) -> String?`, `requestPreview()`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `quick.section.favorites` | Favorites | Favoriler |
| `quick.section.recents` | Recent | Son |
| `quick.section.all` | All Hosts | Tüm Hostlar |
| `quick.preview.via %@` | via %@ | %@ üzerinden |
| `quick.preview.loading` | Reading the configuration… | Yapılandırma okunuyor… |
| `quick.hint.more` | ↩ Connect · ⌘↩ Test · ⌥↩ Copy command · ⌘S Favorite | ↩ Bağlan · ⌘↩ Test · ⌥↩ Komutu kopyala · ⌘S Favori |

(`quick.hint.more` replaces the existing `quick.hint`; remove the old key if it becomes unused.)

- [ ] **Step 1: Write the failing tests**

Append inside `QuickConnectModelTests` (keep existing tests passing; update any that assert the old filter semantics to the new search):

```swift
    @Test func emptyQueryShowsFavoritesThenRecentsThenTheRest() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\nHost b\nHost c\nHost d\n")
        app.toggleFavorite("c")
        app.connect(alias: "b")
        app.connect(alias: "c")
        let model = QuickConnectModel(app: app)
        #expect(model.entries.map(\.alias) == ["c", "b", "a", "d"])
        #expect(model.entries.map(\.section) == [.favorites, .recents, .all, .all])
        #expect(model.entries.first?.isFavorite == true)
    }

    @Test func searchRanksAndHighlights() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host db-prod\n  HostName 10.0.0.9\nHost prod-web-01\nHost prod\n")
        let model = QuickConnectModel(app: app)
        model.query = "prod"
        #expect(model.entries.map(\.alias) == ["prod", "prod-web-01", "db-prod"])
        #expect(model.entries.allSatisfy { $0.section == nil })
        model.query = "prd web"
        #expect(model.entries.map(\.alias) == ["prod-web-01"])
        #expect(model.entries.first?.aliasOffsets == [0, 1, 3, 5, 6, 7])
        model.query = "10.0.0"
        #expect(model.entries.map(\.alias) == ["db-prod"])
    }

    @Test func groupsAppearOnEntries() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "# group: Prod\nHost web\n")
        #expect(QuickConnectModel(app: app).entries.first?.group == "Prod")
    }

    @Test func copyAndFavoriteActOnTheSelection() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n")
        var copied: [String] = []
        let model = QuickConnectModel(app: app, copyToPasteboard: { copied.append($0) })
        model.copySelectedCommand()
        #expect(copied == ["ssh -- web"])
        model.toggleFavoriteSelected()
        #expect(app.favoriteAliases == ["web"])
    }

    @Test func previewUsesSshGOutput() async throws {
        let tmp = try TempDir()
        let runner = FixedRunner(result: ProcessResult(exitCode: 0, stdout: "user ubuntu\nhostname 10.0.1.12\nport 2222\nproxyjump bastion\n", stderr: "", timedOut: false))
        let app = makeTestModel(tmp, config: "Host web\n", runner: runner)
        let model = QuickConnectModel(app: app)
        let entry = try #require(model.selectedEntry)
        #expect(model.previewText(for: entry) == nil)
        await app.effectiveConfig.load("web", using: app.commandBuilder)
        #expect(model.previewText(for: entry) == "ubuntu@10.0.1.12:2222 · " + String(localized: "quick.preview.via \("bastion")"))
    }
```

(`shellCommand(alias:)` for the default config is `ssh -- web` — confirm with `SSHCommandBuilderTests` and use the real value.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/QuickConnectModelTests`
Expected: FAIL to build.

- [ ] **Step 3: Implement**

`QuickConnectModel`:

```swift
enum QuickConnectSection: Hashable, Sendable { case favorites, recents, all }

struct QuickConnectEntry: Identifiable, Hashable, Sendable {
    let alias: String
    let subtitle: String
    let isIncluded: Bool
    var group: String? = nil
    var section: QuickConnectSection? = nil
    var aliasOffsets: [Int] = []
    var isFavorite = false
    var id: String { alias }
}
```

Init gains `copyToPasteboard: @escaping @MainActor (String) -> Void = { NSPasteboard.general.clearContents(); NSPasteboard.general.setString($0, forType: .string) }` (import AppKit). `entries`:

```swift
    var entries: [QuickConnectEntry] {
        let saved = app.savedConnectableHosts
        let base: [QuickConnectEntry] = saved.map { host in
            QuickConnectEntry(
                alias: host.entry.alias,
                subtitle: SidebarBuilder.subtitle(for: host.entry),
                isIncluded: host.isIncluded,
                group: host.isIncluded ? nil : app.store.savedDocument.group(ofHostAt: host.entry.headerLine),
                isFavorite: app.memory.isFavorite(host.entry.alias))
        }
        let query = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sectioned(base) }
        let recents = app.recentAliases
        let scored: [(QuickConnectEntry, Int, Int)] = base.enumerated().compactMap { index, entry in
            let host = saved[index].entry
            let others = [host.value(for: "HostName"), host.value(for: "User"), entry.group].compactMap { $0 }
            guard let match = FuzzyMatcher.match(query: query, alias: entry.alias, others: others) else { return nil }
            var hit = entry
            hit.aliasOffsets = match.aliasOffsets
            let bonus = entry.isFavorite ? 2 : (recents.contains { HostMemory.same($0, entry.alias) } ? 1 : 0)
            return (hit, match.score * 10 + bonus, index)
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }.map(\.0)
    }

    private func sectioned(_ base: [QuickConnectEntry]) -> [QuickConnectEntry] {
        var used = Set<String>()
        var result: [QuickConnectEntry] = []
        func add(_ alias: String, _ section: QuickConnectSection) {
            guard let entry = base.first(where: { HostMemory.same($0.alias, alias) }),
                  used.insert(entry.alias.lowercased()).inserted else { return }
            var copy = entry
            copy.section = section
            result.append(copy)
        }
        app.favoriteAliases.forEach { add($0, .favorites) }
        app.recentAliases.forEach { add($0, .recents) }
        base.forEach { add($0.alias, .all) }
        return result
    }
```

Actions:

```swift
    func copySelectedCommand() {
        guard let entry = selectedEntry else { return }
        copyToPasteboard(app.commandBuilder.shellCommand(alias: entry.alias))
    }

    func toggleFavoriteSelected() {
        guard let entry = selectedEntry else { return }
        app.toggleFavorite(entry.alias)
    }

    /// `user@host:port · via hop`, or nil until ssh -G answered.
    func previewText(for entry: QuickConnectEntry) -> String? {
        guard let options = app.effectiveConfig.options(for: entry.alias), let host = options.first("hostname") else { return nil }
        var text = host
        if let user = options.first("user") { text = user + "@" + text }
        if let port = options.first("port"), port != "22" { text += ":" + port }
        if let hop = options.jumpHops.first {
            let name = hop.host
            text += " · " + String(localized: "quick.preview.via \(name)")
        }
        return text
    }

    @ObservationIgnored private var previewTask: Task<Void, Never>?

    /// Loads the selected host's ssh -G after a short pause; a new selection cancels it.
    func requestPreview() {
        previewTask?.cancel()
        guard let alias = selectedEntry?.alias else { return }
        let builder = app.commandBuilder
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            await self.app.effectiveConfig.load(alias, using: builder)
        }
    }
```

(`lowercased()` here is app code for a set key; it is fine but prefer `HostMemory.same`-consistent keys: use the alias ASCII-lowercased via the same helper the cache uses. Make the `key` helper of `EffectiveConfigCache` internal-static and reuse it.)

`QuickConnectView`:
- When `model.query` is empty, render section headers (`quick.section.*`) before the first entry of each section.
- Row: `Text(FuzzyMatcher.highlighted(entry.alias, offsets: entry.aliasOffsets))` instead of the plain alias; a small `star.fill` when `entry.isFavorite`; subtitle shows `group · subtitle` when a group exists.
- Under the list, a one-line preview of the selected entry: `model.previewText(for:)` or `quick.preview.loading` while it is being loaded (and nothing on failure).
- Keys: `.onKeyPress(.return, phases: .down)` checks modifiers — none: connect; `.command`: test; `.option`: `copySelectedCommand()` then dismiss. `.onKeyPress("s")` with `.command` → `toggleFavoriteSelected()`. Use `KeyPress.modifiers`.
- Call `model.requestPreview()` on appear and on `selectedIndex`/`query` change.
- Replace the hint text with `quick.hint.more`.

Checklist (append to `docs/design/manual-test-checklist.md` under a new "## v1.1 — Arayüz geliştirmeleri" section):

```markdown
- [ ] ⌥⌘S → arama yazmadan ↩: en son bağlanılan host'a bağlanıyor; boş aramada Favoriler / Son / Tüm Hostlar bölümleri.
- [ ] `prd web` gibi kısaltmalar doğru host'u ilk sırada buluyor; eşleşen harfler kalın.
- [ ] ⌥↩ komutu panoya kopyalıyor; ⌘S favoriye ekleyip çıkarıyor; satırda yıldız görünüyor.
- [ ] Seçili host'un altında `kullanıcı@adres:port · … üzerinden` önizlemesi kısa sürede beliriyor.
```

Add the catalog keys.

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/QuickConnectModelTests`, then `bash scripts/test-app.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat: quick connect sections, fuzzy search, preview and shortcuts"
```

---

### Task 8: Etkin ayarlar ve ProxyJump zinciri (detay)

**Files:**
- Create: `SSHConfigManager/Features/HostDetail/EffectiveSettingsModel.swift`, `EffectiveSettingsView.swift`, `ProxyChainModel.swift`, `ProxyChainView.swift`
- Modify: `SSHConfigManager/Features/HostList/DetailView.swift`, `SSHConfigManager/Shared/AppModel.swift` (`includeResolver` access), `Localizable.xcstrings`, `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/EffectiveSettingsModelTests.swift`, `ProxyChainModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`ConfigResolver.resolve`, `ResolvedConfig`, `OptionSource`), Task 3 (`EffectiveOptions`, `JumpHop`), Task 6 (`effectiveConfig`), `IncludeResolver.includedDocuments(for:)`, `app.savedAlias`, `connectionTests`, `ConnectionStatus`.
- Produces:
  - `struct EffectiveSettingRow: Identifiable, Equatable { key: String; values: [String]; source: EffectiveSettingSource; id: String }`
  - `enum EffectiveSettingSource: Equatable { case thisBlock, otherHost([String]), global, include(file: String, patterns: [String]), defaultValue, uncertain }`
  - `enum EffectiveSettingsBuilder { static let primaryKeys: [String]; static func rows(alias:options:resolved:home:showAll:) -> [EffectiveSettingRow] }`
  - `AppModel.resolvedConfig(forSavedAlias: String) -> ResolvedConfig?`
  - `struct ProxyChainNode: Identifiable, Equatable { id: Int; title: String; alias: String?; isCycle: Bool }`; `enum ProxyChainBuilder { static let maxDepth = 5; static func nodes(for alias: String, options: (String) -> EffectiveOptions?, isSavedAlias: (String) -> String?) -> [ProxyChainNode] }`
  - `@MainActor @Observable final class ProxyChainTest { states: [Int: ChainNodeState]; func run(nodes:app:) async }`, `enum ChainNodeState { case pending, testing, done(ConnectionStatus), skipped }`

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `effective.title` | Effective Settings | Etkin Ayarlar |
| `effective.showAll` | Show All | Tümünü Göster |
| `effective.unsaved` | Shown after the host is saved: ssh reads the saved file. | Host kaydedildikten sonra gösterilir: ssh kaydedilmiş dosyayı okur. |
| `effective.failed %@` | Could not read the effective settings: %@ | Etkin ayarlar okunamadı: %@ |
| `effective.source.thisBlock` | This host | Bu host |
| `effective.source.otherHost %@` | Host %@ | Host %@ |
| `effective.source.global` | Top of the file | Dosyanın başı |
| `effective.source.include %@` | Included: %@ | Dahil edilen: %@ |
| `effective.source.default` | Default | Varsayılan |
| `effective.source.uncertain` | Match block or default | Match bloğu ya da varsayılan |
| `chain.title` | Jump Chain | Atlama Zinciri |
| `chain.thisMac` | This Mac | Bu Mac |
| `chain.cycle` | (loop) | (döngü) |
| `chain.proxyCommand` | Uses ProxyCommand; the chain is not shown. | ProxyCommand kullanıyor; zincir gösterilmez. |
| `chain.test` | Test Chain | Zinciri Test Et |
| `chain.skipped` | Skipped | Atlandı |

- [ ] **Step 1: Write the failing tests**

`EffectiveSettingsModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct EffectiveSettingsModelTests {
    @Test func sourcesComeFromTheResolverAndValuesFromSshG() throws {
        let doc = ConfigDocument(parsing: "Host *\n  User star\nHost web\n  HostName Example.COM\n  Port 2222\n")
        let resolved = ConfigResolver.resolve(alias: "web", document: doc, targetHeader: 2, includes: { _ in [] })
        let options = EffectiveOptions(parsing: "user star\nhostname example.com\nport 2222\nforwardagent no\nidentityfile ~/.ssh/id_rsa\n")
        let rows = EffectiveSettingsBuilder.rows(alias: "web", options: options, resolved: resolved, home: URL(filePath: "/h"), showAll: false)
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
        #expect(byKey["user"]?.source == .otherHost(["*"]))
        #expect(byKey["hostname"]?.source == .thisBlock)                 // ssh -G lowercases; still the same value
        #expect(byKey["port"]?.source == .thisBlock)
        #expect(byKey["forwardagent"]?.source == .defaultValue)
        #expect(byKey["identityfile"]?.source == .defaultValue)
    }

    @Test func mismatchesWithAMatchBlockAreUncertain() {
        let doc = ConfigDocument(parsing: "Host web\n  Port 22\nMatch exec true\n  User m\n")
        let resolved = ConfigResolver.resolve(alias: "web", document: doc, targetHeader: 0, includes: { _ in [] })
        let options = EffectiveOptions(parsing: "port 2200\nuser m\n")
        let rows = EffectiveSettingsBuilder.rows(alias: "web", options: options, resolved: resolved, home: URL(filePath: "/h"), showAll: false)
        #expect(rows.first { $0.key == "port" }?.source == .uncertain)
        #expect(rows.first { $0.key == "user" }?.source == .uncertain)
    }

    @Test func identityFilesCompareAfterTildeExpansion() {
        let doc = ConfigDocument(parsing: "Host web\n  IdentityFile ~/.ssh/k\n")
        let resolved = ConfigResolver.resolve(alias: "web", document: doc, targetHeader: 0, includes: { _ in [] })
        let options = EffectiveOptions(parsing: "identityfile /h/.ssh/k\n")
        let row = EffectiveSettingsBuilder.rows(alias: "web", options: options, resolved: resolved, home: URL(filePath: "/h"), showAll: false).first { $0.key == "identityfile" }
        #expect(row?.source == .thisBlock)
    }

    @Test func showAllAddsTheRemainingKeysSorted() {
        let options = EffectiveOptions(parsing: "hostname h\nzz z\naa a\n")
        let rows = EffectiveSettingsBuilder.rows(alias: "w", options: options, resolved: ResolvedConfig(), home: URL(filePath: "/h"), showAll: true)
        #expect(rows.map(\.key).suffix(2) == ["aa", "zz"])
    }
}
```

`ProxyChainModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct ProxyChainModelTests {
    func options(_ map: [String: String]) -> (String) -> EffectiveOptions? {
        { alias in map[alias].map { EffectiveOptions(parsing: $0) } }
    }

    @Test func expandsSavedAliasesRecursively() {
        let nodes = ProxyChainBuilder.nodes(
            for: "db",
            options: options(["db": "hostname 10.0.0.5\nproxyjump bastion", "bastion": "hostname b.example.com\nproxyjump edge", "edge": "hostname e"]),
            isSavedAlias: { ["db", "bastion", "edge"].contains($0) ? $0 : nil })
        #expect(nodes.map(\.title) == ["edge", "bastion", "db"])
        #expect(nodes.map(\.alias) == ["edge", "bastion", "db"])
    }

    @Test func nonAliasHopsArePlainAndUntested() {
        let nodes = ProxyChainBuilder.nodes(for: "db", options: options(["db": "proxyjump admin@1.2.3.4:2200"]), isSavedAlias: { $0 == "db" ? $0 : nil })
        #expect(nodes.map(\.title) == ["admin@1.2.3.4:2200", "db"])
        #expect(nodes.first?.alias == nil)
    }

    @Test func cyclesAndDepthAreBounded() {
        let looped = ProxyChainBuilder.nodes(for: "a", options: options(["a": "proxyjump b", "b": "proxyjump a"]), isSavedAlias: { $0 })
        #expect(looped.contains { $0.isCycle })
        var deep: [String: String] = [:]
        for n in 0..<10 { deep["h\(n)"] = "proxyjump h\(n + 1)" }
        let bounded = ProxyChainBuilder.nodes(for: "h0", options: options(deep), isSavedAlias: { $0 })
        #expect(bounded.count <= ProxyChainBuilder.maxDepth + 1)
    }

    @Test func chainTestStopsAtTheFirstFailure() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host bastion\nHost db\n", runner: FixedRunner.invalid("Connection refused"))
        let nodes = [ProxyChainNode(id: 0, title: "bastion", alias: "bastion", isCycle: false),
                     ProxyChainNode(id: 1, title: "db", alias: "db", isCycle: false)]
        let test = ProxyChainTest()
        await test.run(nodes: nodes, app: app)
        #expect(test.states[0] == .done(.connectionRefused))
        #expect(test.states[1] == .skipped)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/EffectiveSettingsModelTests`
Expected: FAIL to build.

- [ ] **Step 3: Implement**

`EffectiveSettingsModel.swift`:

```swift
import Foundation
import SSHConfigKit

enum EffectiveSettingSource: Equatable {
    case thisBlock
    case otherHost([String])
    case global
    case include(file: String, patterns: [String])
    case defaultValue
    case uncertain
}

struct EffectiveSettingRow: Identifiable, Equatable {
    let key: String
    let values: [String]
    let source: EffectiveSettingSource
    var id: String { key }
}

/// Spec v1.1 §5: values from ssh -G (what ssh will use), sources from the resolver.
enum EffectiveSettingsBuilder {
    static let primaryKeys = [
        "hostname", "user", "port", "identityfile", "proxyjump", "proxycommand", "forwardagent", "identitiesonly",
        "localforward", "remoteforward", "dynamicforward", "serveraliveinterval", "stricthostkeychecking",
        "userknownhostsfile", "controlmaster", "controlpath",
    ]

    static func rows(alias: String, options: EffectiveOptions, resolved: ResolvedConfig, home: URL, showAll: Bool) -> [EffectiveSettingRow] {
        var keys = primaryKeys.filter { options.values[$0] != nil }
        if showAll {
            keys += options.values.keys.filter { !primaryKeys.contains($0) }.sorted()
        }
        return keys.map { key in
            let values = options.values[key] ?? []
            return EffectiveSettingRow(key: key, values: values, source: source(key: key, sshValues: values, resolved: resolved, home: home))
        }
    }

    private static func normalize(_ value: String, key: String, home: URL) -> String {
        var text = value
        if key == "identityfile" || key == "certificatefile" || key == "userknownhostsfile" {
            if text.hasPrefix("~/") { text = home.path + text.dropFirst(1) }
            text = URL(filePath: text).standardizedFileURL.path
        }
        // ssh -G lowercases some values (host names, yes/no): compare ASCII case-insensitively.
        return String(String.UnicodeScalarView(text.unicodeScalars.map { (65...90).contains($0.value) ? Unicode.Scalar($0.value + 32)! : $0 }))
    }

    private static func source(key: String, sshValues: [String], resolved: ResolvedConfig, home: URL) -> EffectiveSettingSource {
        guard let first = resolved.options[key]?.first else {
            return resolved.hasMatchBlocks ? .uncertain : .defaultValue
        }
        let sshFirst = sshValues.first.map { normalize($0, key: key, home: home) }
        guard sshFirst == normalize(first.value, key: key, home: home) else { return .uncertain }
        switch first.source {
        case .thisBlock: return .thisBlock
        case .otherHost(let patterns): return .otherHost(patterns)
        case .global: return .global
        case .include(let file, let patterns): return .include(file: file.lastPathComponent, patterns: patterns)
        }
    }
}
```

`AppModel`:

```swift
    /// Resolver result for a host of the saved file (Includes followed in place).
    func resolvedConfig(forSavedAlias alias: String) -> ResolvedConfig? {
        guard let saved = savedAlias(alias) else { return nil }
        let document = store.savedDocument
        let header = document.hosts.first { !$0.isPattern && $0.alias == saved }?.headerLine
        let resolver = IncludeResolver(homeDirectory: settings.homeDirectory)
        return ConfigResolver.resolve(alias: saved, document: document, targetHeader: header,
                                      includes: { resolver.includedDocuments(for: $0) })
    }
```

`ProxyChainModel.swift`:

```swift
import Foundation
import Observation
import SSHConfigKit

struct ProxyChainNode: Identifiable, Equatable {
    let id: Int
    let title: String
    /// A host of the saved file (testable), or nil for a plain host name.
    let alias: String?
    let isCycle: Bool
}

enum ProxyChainBuilder {
    static let maxDepth = 5

    /// Nodes from the first hop to the target (the target is last).
    static func nodes(for alias: String, options: (String) -> EffectiveOptions?, isSavedAlias: (String) -> String?) -> [ProxyChainNode] {
        var chain: [(title: String, alias: String?, isCycle: Bool)] = [(alias, isSavedAlias(alias), false)]
        var visited: Set<String> = [alias.lowercased()]
        var current = alias
        for _ in 0..<maxDepth {
            guard let hop = options(current)?.jumpHops.first else { break }
            let title = [hop.user.map { $0 + "@" }, hop.host, hop.port.map { ":\($0)" }].compactMap { $0 }.joined()
            guard let saved = isSavedAlias(hop.host), hop.user == nil, hop.port == nil else {
                chain.insert((title, nil, false), at: 0)
                break
            }
            let isCycle = !visited.insert(saved.lowercased()).inserted
            chain.insert((saved, saved, isCycle), at: 0)
            if isCycle { break }
            current = saved
        }
        return chain.enumerated().map { ProxyChainNode(id: $0.offset, title: $0.element.title, alias: $0.element.alias, isCycle: $0.element.isCycle) }
    }
}

enum ChainNodeState: Equatable {
    case pending, testing, done(ConnectionStatus), skipped
}

/// Tests the chain's saved hosts from the first hop; after a failure the rest are skipped.
@MainActor
@Observable
final class ProxyChainTest {
    private(set) var states: [Int: ChainNodeState] = [:]
    private(set) var isRunning = false

    func run(nodes: [ProxyChainNode], app: AppModel) async {
        isRunning = true
        defer { isRunning = false }
        states = [:]
        var failed = false
        for node in nodes {
            guard let alias = node.alias, !node.isCycle else { continue }
            if failed { states[node.id] = .skipped; continue }
            states[node.id] = .testing
            await app.connectionTests.test(alias, using: app.commandBuilder)
            let status = app.connectionTests.results[alias]?.status ?? .other
            states[node.id] = .done(status)
            if status != .reachable { failed = true }
        }
    }
}
```

(The chain only expands into hosts written as plain aliases; a hop with a user or port is shown as typed and not expanded, because it may mean a different connection than the alias.)

`EffectiveSettingsView` (detail, below `ConnectionBar` for `.host` and `.included` items):
- `DisclosureGroup(String(localized: "effective.title"))`, expanded state in `@State`.
- For an unsaved host: `Text(String(localized: "effective.unsaved"))`.
- Otherwise: `.task(id: alias) { await model.effectiveConfig.load(alias, using: model.commandBuilder) }`; on failure `effective.failed %@`; else a `Grid` of rows: key (monospaced, verbatim), values (verbatim, one per line), source label (localized from `EffectiveSettingSource`). A "Show All" toggle.
- Below it the chain (`ProxyChainView`): when `proxycommand` is set (and not `none`) show `chain.proxyCommand`; when the chain has more than the target, show `chain.thisMac → node → … → target` with each aliased node's `ConnectionStatusBadge` (or the `ProxyChainTest` state while running: spinner/skipped) and a `chain.test` button (disabled while running). Hop aliases' ssh -G are loaded through `effectiveConfig.load` in a `.task` so recursion can expand.

Add catalog keys and checklist lines:

```markdown
- [ ] Bir host'un detayında "Etkin Ayarlar" ssh -G değerlerini ve her birinin kaynağını (Bu host / Host * / Dosyanın başı / Dahil edilen / Varsayılan) gösteriyor; "Tümünü Göster" kalan ayarları açıyor.
- [ ] ProxyJump kullanan host'ta `Bu Mac → bastion → host` zinciri görünüyor; "Zinciri Test Et" sırayla test ediyor, başarısız halkadan sonrakiler "Atlandı".
```

- [ ] **Step 4: Run tests**

Run: the two suites, then `bash scripts/test-app.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat: effective settings with sources and the ProxyJump chain"
```

---

### Task 9: Kenar çubuğunda gruplar, favori yıldızı, uyarı rozetleri ve grup alanı

**Files:**
- Modify: `SSHConfigManager/Features/HostList/SidebarModel.swift`, `SidebarView.swift`, `HostCommands.swift`, `HostEditorView.swift`, `DetailView.swift`, `ConnectionBar.swift`
- Modify: `SSHConfigManager/Shared/AppModel.swift` (`setGroup`, `existingGroups`, `lintIssues(for:)`), `Messages.swift`, `Localizable.xcstrings`, `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/SidebarBuilderTests.swift`, `HostCommandsTests.swift`, `AppModelTests.swift`

**Interfaces:**
- Consumes: Task 1 (`group(ofHostAt:)`, `setGroup`), Task 3 (`HostLint`, `HostIssue`), Task 5 (`memory`, `toggleFavorite`), `KeyFileInspector`, `SidebarBuilder`.
- Produces: `SidebarSections.hostGroups: [SidebarGroup]` (`struct SidebarGroup: Equatable, Identifiable { name: String?; rows: [SidebarRow]; id }`) with `hosts` kept as the flattened list; `AppModel.setGroup(_ item: SidebarItem, to: String?)`, `existingGroups: [String]`, `lintIssues(for: SidebarItem) -> [HostIssue]`; `Messages.text(for: HostIssue)`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `sidebar.section.ungrouped` | Other Hosts | Diğer Hostlar |
| `editor.group` | Group | Grup |
| `editor.group.placeholder` | No group | Grup yok |
| `editor.group.apply` | Apply | Uygula |
| `favorite.add` | Add to Favorites | Favorilere Ekle |
| `favorite.remove` | Remove from Favorites | Favorilerden Çıkar |
| `issue.lint.missingIdentityFile %@` | IdentityFile not found: %@ | IdentityFile bulunamadı: %@ |
| `issue.lint.duplicateFirst %@` | “%@” also appears in later Host blocks; they only add settings this block does not set. | “%@” sonraki Host bloklarında da var; onlar yalnızca bu blokta olmayan ayarları ekler. |
| `issue.lint.duplicateLater %@` | An earlier Host block already defines “%@”; its values take precedence over this block. | “%@” daha önceki bir Host bloğunda zaten tanımlı; oradaki değerler bu bloğun önüne geçer. |
| `issue.lint.unencryptedKey %@` | Private key without a passphrase: %@ | Parolasız özel anahtar: %@ |

(If the existing "Hosts" section title key differs, keep the existing key for the ungrouped section only when there are no groups at all; otherwise use `sidebar.section.ungrouped`.)

- [ ] **Step 1: Write the failing tests**

Append to `SidebarBuilderTests`:

```swift
    @Test func hostsAreGroupedAlphabeticallyWithUngroupedLast() {
        let doc = ConfigDocument(parsing: "# group: Staging\nHost s1\n# group: Prod\nHost p1\nHost loose\n# group: Prod\nHost p2\nHost *\n")
        let sections = SidebarBuilder.sections(document: doc, included: [], search: "")
        #expect(sections.hostGroups.map(\.name) == ["Prod", "Staging", nil])
        #expect(sections.hostGroups.map { $0.rows.map(\.title) } == [["p1", "p2"], ["s1"], ["loose"]])
        #expect(sections.hosts.count == 4)
        #expect(sections.patterns.map(\.title) == ["*"])
    }

    @Test func noGroupsMeansOneUnnamedGroup() {
        let sections = SidebarBuilder.sections(document: ConfigDocument(parsing: "Host a\nHost b\n"), included: [], search: "")
        #expect(sections.hostGroups.map(\.name) == [nil])
    }
```

Append to `HostCommandsTests`:

```swift
    @Test func duplicatingKeepsTheGroup() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "# group: Prod\nHost web\n  User u\n")
        let item = try #require(try HostCommands.duplicate(.host(alias: "web", occurrence: 0), in: model.store))
        let entry = try #require(SidebarBuilder.hostEntry(for: item, in: model.store.document))
        #expect(model.store.document.group(ofHostAt: entry.headerLine) == "Prod")
    }
```

Append to `AppModelTests`:

```swift
    @Test func settingAGroupIsAnUnsavedEditOfOneLine() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  User u\nHost db\n")
        model.setGroup(.host(alias: "web", occurrence: 0), to: "Prod")
        #expect(model.store.document.render() == "# group: Prod\nHost web\n  User u\nHost db\n")
        #expect(model.existingGroups == ["Prod"])
        #expect(try tmp.read(".ssh/config") == "Host web\n  User u\nHost db\n")
    }

    @Test func lintIssuesAreReportedForTheDocumentBeingEdited() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host web\n  IdentityFile ~/.ssh/missing\nHost web\n")
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 0)).contains(.missingIdentityFile("~/.ssh/missing")))
        #expect(model.lintIssues(for: .host(alias: "web", occurrence: 1)) == [.duplicateAlias(alias: "web", isFirst: false)])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/SidebarBuilderTests`
Expected: FAIL to build.

- [ ] **Step 3: Implement**

`SidebarModel.swift`:

```swift
struct SidebarGroup: Equatable, Identifiable, Sendable {
    let name: String?
    var rows: [SidebarRow]
    var id: String { name ?? "\u{0}ungrouped" }
}

struct SidebarSections: Equatable, Sendable {
    var hostGroups: [SidebarGroup] = []
    var patterns: [SidebarRow] = []
    var included: [SidebarRow] = []
    var matches: [SidebarRow] = []
    var hosts: [SidebarRow] { hostGroups.flatMap(\.rows) }
}
```

In `sections(...)`, collect non-pattern rows with `document.group(ofHostAt: entry.headerLine)`; build groups: named groups sorted with `localizedStandardCompare`, rows in file order, then the ungrouped group (name nil) last; omit empty groups. Update any code that wrote `result.hosts.append` to the new structure.

`AppModel`:

```swift
    func setGroup(_ item: SidebarItem, to name: String?) {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return }
        do {
            try store.apply { try $0.setGroup(ofHostAt: entry.headerLine, to: name) }
        } catch {
            errorMessage = Messages.text(for: error)
        }
    }

    /// Group names used in the document, sorted for suggestions.
    var existingGroups: [String] {
        let names = Set(store.document.hosts.compactMap { store.document.group(ofHostAt: $0.headerLine) })
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @ObservationIgnored private var lintCache: (text: String, issues: [Int: [HostIssue]])?

    /// Lint of the document being edited (so fixes show at once); cached per document text.
    func lintIssues(for item: SidebarItem) -> [HostIssue] {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return [] }
        let text = store.document.render()
        if lintCache?.text != text {
            let lint = HostLint(
                home: settings.homeDirectory,
                fileExists: { FileManager.default.fileExists(atPath: $0.path) },
                encryption: { url in
                    (try? KeyFileInspector.readHead(of: url)).map(KeyFileInspector.encryption(ofPrivateKeyHead:)) ?? .unknown
                })
            let duplicates = HostLint.duplicateCounts(document: store.document, included: store.includedHosts)
            var seen = Set<String>()
            var issues: [Int: [HostIssue]] = [:]
            for host in store.document.hosts {
                let first = seen.insert(host.alias.lowercased()).inserted
                issues[host.headerLine] = lint.issues(for: host, duplicates: duplicates, isFirstOccurrence: first)
            }
            lintCache = (text, issues)
        }
        return lintCache?.issues[entry.headerLine] ?? []
    }
```

(Included hosts can only be "later" duplicates relative to the root file's first block; root blocks are checked against the counts including includes, so a root host that also appears in an include is flagged as first.)

`Messages.text(for issue: HostIssue)` → the `issue.lint.*` keys (copy the value to a local before interpolating).

`HostCommands.duplicate`: inside the same `store.apply` closure, after `duplicateHost`, `if let group = $0.group(ofHostAt: entry.headerLine) { try $0.setGroup(ofHostAt: header, to: group) }` — note the group line insertion shifts the new header by one: recompute the returned item from `SidebarBuilder.item(forHeader:)` using `header + 1` when a group line was inserted (the inserted line is directly above the new Host).

`SidebarView`:
- Replace the single hosts section with `ForEach(sections.hostGroups) { group in section(group.name ?? String(localized: "sidebar.section.ungrouped"), rows: group.rows, …) }`. When there is only the unnamed group, keep the original `sidebar.section.hosts` title.
- Row: a `star.fill` (yellow, `accessibilityLabel(favorite.remove)`) when `model.memory.isFavorite(alias)`; an `exclamationmark.triangle.fill` (orange) when `model.lintIssues(for: row.item)` is non-empty, `.help` listing `Messages.text(for:)` lines.
- Context menu: `favorite.add` / `favorite.remove` for rows with `connectableAlias(for:)`.

`ConnectionBar`: a star toggle button next to the status (only with an alias): `Image(systemName: isFavorite ? "star.fill" : "star")`, help `favorite.add`/`favorite.remove`.

`HostEditorView` (or `DetailView` above the form): a "Group" row — `TextField(String(localized: "editor.group"), text: $groupText, prompt: Text(String(localized: "editor.group.placeholder")))` with `.onSubmit { model.setGroup(item, to: groupText) }`, a suggestions `Menu` listing `model.existingGroups`, and an `editor.group.apply` button. `groupText` initializes from `store.document.group(ofHostAt:)`. Below the form fields, the host's lint issues as a list (orange icon + text).

Add catalog keys and checklist lines:

```markdown
- [ ] Grup atanan hostlar kenar çubuğunda grup başlıkları altında; grupsuzlar en altta "Diğer Hostlar". Dosyadaki değişiklik yalnızca `# group:` satırı (Kaydet farkında kontrol).
- [ ] Favori hostlarda yıldız; sağ tık ve detaydaki yıldızla ekleme/çıkarma.
- [ ] Var olmayan IdentityFile, yinelenen alias ya da parolasız anahtar kullanan hostta ⚠ ve açıklaması görünüyor; düzeltince hemen kayboluyor.
```

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh`.
Expected: PASS (update existing sidebar tests that read `sections.hosts` only if they break; `hosts` remains as a computed property).

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat: host groups, favorites and lint badges in the sidebar"
```

---

### Task 10: Host menüsü, durum özeti ve boş durum ekranı

**Files:**
- Create: `SSHConfigManager/App/HostCommandMenu.swift`, `SSHConfigManager/Features/HostList/StatusSummaryView.swift`, `SSHConfigManager/Features/HostList/OnboardingView.swift`
- Modify: `SSHConfigManager/App/SSHConfigManagerApp.swift`, `SSHConfigManager/Shared/AppModel.swift` (`statusFilter`, `pendingDelete`, `statusCounts`, `canAct`), `SidebarView.swift` (filter, delete dialog moved to model, `onDeleteCommand`), `ConnectionBar.swift` (⌘↩ moves to the menu), `MainWindow.swift`, `DetailView.swift`, `KeysModel.swift` (`pendingNewKey`), `KeysWindow.swift`, `Localizable.xcstrings`, `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/StatusSummaryTests.swift`, `AppModelTests.swift`

**Interfaces:**
- Consumes: Tasks 5 and 9 (`toggleFavorite`, `memory`), `HostCommands`, `connectionTests`, `connectableAliases`, `KeysModel`.
- Produces: `enum StatusCategory: CaseIterable { case ok, attention, failed; static func of(_: ConnectionStatus) -> StatusCategory }`; `AppModel.statusFilter: StatusCategory?`, `statusCounts: [StatusCategory: Int]`, `pendingDelete: SidebarItem?`, `requestDelete(_:)`, `copySSHCommand(_:)`; `KeysModel.pendingNewKey: Bool`; `HostCommandMenu: Commands`.

Kısayollar (spec v1.1 §4): Yeni Host ⌘N, Çoğalt ⌘D, Sil… (menü öğesi kısayolsuz; ⌫ ve ⌘⌫ kenar çubuğu odaktayken `onDeleteCommand` ile — metin alanında silmeyi çalmamak için), Test Et ⌘T, Bağlan ⌘↩ (ConnectionBar'daki kısayol kaldırılır, düğme kalır), Favori ⌘⇧F, `ssh` Komutunu Kopyala ⌘⇧C.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `menu.host` | Host | Host |
| `menu.host.new` | New Host | Yeni Host |
| `menu.host.duplicate` | Duplicate | Çoğalt |
| `menu.host.delete` | Delete… | Sil… |
| `menu.host.test` | Test | Test Et |
| `menu.host.connect` | Connect | Bağlan |
| `menu.host.favorite` | Toggle Favorite | Favori Yap / Kaldır |
| `menu.host.copyCommand` | Copy ssh Command | ssh Komutunu Kopyala |
| `status.summary.ok %@` | %@ reachable | %@ erişilebilir |
| `status.summary.attention %@` | %@ need attention | %@ dikkat istiyor |
| `status.summary.failed %@` | %@ failed | %@ başarısız |
| `status.filter %@` | Showing: %@ | Gösterilen: %@ |
| `status.filter.clear` | Show All | Tümünü Göster |
| `onboarding.title` | Let’s add your first server | İlk sunucunu ekleyelim |
| `onboarding.addHost` | Add your first host | İlk host'u ekle |
| `onboarding.createKey` | Create a key | Anahtar oluştur |
| `onboarding.uploadKey` | Upload the key to the server | Anahtarı sunucuya yükle |

- [ ] **Step 1: Write the failing tests**

`StatusSummaryTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct StatusSummaryTests {
    @Test func categoriesCoverEveryStatus() {
        #expect(StatusCategory.of(.reachable) == .ok)
        #expect(StatusCategory.of(.authenticationRequired) == .attention)
        #expect(StatusCategory.of(.unknownHostKey) == .attention)
        for status in [ConnectionStatus.hostKeyChanged, .timeout, .dnsFailure, .connectionRefused, .other] {
            #expect(StatusCategory.of(status) == .failed)
        }
    }

    @Test func countsOnlyConnectableHostsAndTheFilterNarrowsTheSidebar() async throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\nHost b\n", runner: FixedRunner.invalid("Connection refused"))
        await model.connectionTests.test("a", using: model.commandBuilder)
        #expect(model.statusCounts == [.failed: 1])
        model.statusFilter = .failed
        #expect(model.passesStatusFilter(.host(alias: "a", occurrence: 0)))
        #expect(!model.passesStatusFilter(.host(alias: "b", occurrence: 0)))
        try tmp.file(".ssh/config", "Host a\n  Port 2\n")
        model.store.load()                     // saved file changed: results and the filter are cleared
        #expect(model.statusFilter == nil)
    }

    @Test func deleteGoesThroughAConfirmation() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        model.requestDelete(.host(alias: "a", occurrence: 0))
        #expect(model.pendingDelete == .host(alias: "a", occurrence: 0))
        #expect(model.store.document.hosts.count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/StatusSummaryTests`
Expected: FAIL to build.

- [ ] **Step 3: Implement**

`AppModel`:

```swift
    var statusFilter: StatusCategory?
    var pendingDelete: SidebarItem?

    var statusCounts: [StatusCategory: Int] {
        var counts: [StatusCategory: Int] = [:]
        for alias in connectableAliases {
            if let status = connectionTests.results[alias]?.status { counts[StatusCategory.of(status), default: 0] += 1 }
        }
        return counts
    }

    func passesStatusFilter(_ item: SidebarItem) -> Bool {
        guard let filter = statusFilter else { return true }
        guard let alias = connectableAlias(for: item), let status = connectionTests.results[alias]?.status else { return false }
        return StatusCategory.of(status) == filter
    }

    func requestDelete(_ item: SidebarItem) {
        guard SidebarBuilder.hostEntry(for: item, in: store.document) != nil else { return }
        pendingDelete = item
    }

    func copySSHCommand(_ item: SidebarItem, copy: (String) -> Void) {
        if let command = HostCommands.sshCommand(for: item, document: store.document, builder: commandBuilder) { copy(command) }
    }
```

Clear `statusFilter = nil` in `savedStateDidChange()` and `switchConfig`.

`StatusCategory` (in `StatusSummaryView.swift`):

```swift
enum StatusCategory: CaseIterable, Hashable {
    case ok, attention, failed

    static func of(_ status: ConnectionStatus) -> StatusCategory {
        switch status {
        case .reachable: .ok
        case .authenticationRequired, .unknownHostKey: .attention
        case .hostKeyChanged, .timeout, .dnsFailure, .connectionRefused, .other: .failed
        }
    }
}
```

`StatusSummaryView`: a toolbar `ToolbarItem(placement: .status)` (next to the unsaved indicator) showing, when `statusCounts` is non-empty, three buttons (`checkmark.circle.fill` green / `exclamationmark.triangle.fill` orange / `xmark.octagon.fill` red) with counts; each sets `model.statusFilter` (tap again to clear); help texts from `status.summary.*` (count as `String`). `SidebarView` filters every host row with `model.passesStatusFilter`, and when a filter is active shows a first row `status.filter %@` with a `status.filter.clear` button.

`SidebarView`: move the delete confirmation to `model.pendingDelete` (title/message unchanged); context menu Delete calls `model.requestDelete`; add `.onDeleteCommand { if let item = model.selection { model.requestDelete(item) } }` on the `List`.

`HostCommandMenu.swift`:

```swift
import AppKit
import SwiftUI

/// "Host" menu (spec v1.1 §4). Acts only when the main window is key.
struct HostCommandMenu: Commands {
    let model: AppModel
    let openMainWindow: () -> Void

    private var mainWindowIsKey: Bool { NSApp.keyWindow?.identifier?.rawValue.hasPrefix("main") == true }

    var body: some Commands {
        CommandMenu(String(localized: "menu.host")) {
            Button(String(localized: "menu.host.new")) {
                openMainWindow()
                do { model.requestSelect(try HostCommands.addHost(to: model.store)) } catch { model.errorMessage = Messages.text(for: error) }
            }
            .keyboardShortcut("n")
            .disabled(model.store.loadState != .loaded)

            Button(String(localized: "menu.host.duplicate")) {
                guard mainWindowIsKey, let item = model.selection else { return }
                do { if let copy = try HostCommands.duplicate(item, in: model.store) { model.requestSelect(copy) } }
                catch { model.errorMessage = Messages.text(for: error) }
            }
            .keyboardShortcut("d")
            .disabled(!isEditableHost)

            Button(String(localized: "menu.host.delete")) {
                guard mainWindowIsKey, let item = model.selection else { return }
                model.requestDelete(item)
            }
            .disabled(!isEditableHost)

            Divider()

            Button(String(localized: "menu.host.connect")) {
                guard mainWindowIsKey, let alias = selectedAlias else { return }
                model.connect(alias: alias)
            }
            .keyboardShortcut(.return)
            .disabled(selectedAlias == nil)

            Button(String(localized: "menu.host.test")) {
                guard mainWindowIsKey, let alias = selectedAlias else { return }
                Task { await model.connectionTests.test(alias, using: model.commandBuilder) }
            }
            .keyboardShortcut("t")
            .disabled(selectedAlias == nil)

            Button(String(localized: "menu.host.favorite")) {
                guard mainWindowIsKey, let alias = selectedAlias else { return }
                model.toggleFavorite(alias)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(selectedAlias == nil)

            Button(String(localized: "menu.host.copyCommand")) {
                guard mainWindowIsKey, let item = model.selection else { return }
                model.copySSHCommand(item) { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(selectedAlias == nil)
        }
    }

    private var selectedAlias: String? { model.selection.flatMap(model.connectableAlias(for:)) }

    private var isEditableHost: Bool {
        guard case .host? = model.selection else { return false }
        return model.selection.flatMap { SidebarBuilder.hostEntry(for: $0, in: model.store.document) } != nil
    }
}
```

`SSHConfigManagerApp`: add `HostCommandMenu(model: appDelegate.model, openMainWindow: { appDelegate.openMainWindow?() })` to the main `Window`'s `.commands { … }` (next to the About `CommandGroup`). Remove `.keyboardShortcut(.return, modifiers: .command)` from `ConnectionBar`'s Connect button (the menu owns ⌘↩) and set `.help` to show "⌘↩".

`KeysModel`: `var pendingNewKey = false`. `KeysWindow`: `.onChange(of: keys.pendingNewKey, initial: true) { if keys.pendingNewKey { sheet = .new; keys.pendingNewKey = false } }`.

`OnboardingView` (shown by `DetailView` instead of the empty selection placeholder when `model.store.loadState == .loaded && model.store.document.hosts.allSatisfy(\.isPattern) && model.store.includedHosts.isEmpty`):
- Title `onboarding.title`; three numbered steps with buttons:
  1. `onboarding.addHost` → `model.requestSelect(try HostCommands.addHost(to: model.store))`.
  2. `onboarding.createKey` → `model.keys.pendingNewKey = true; openWindow(id: "keys")`.
  3. `onboarding.uploadKey` → `openWindow(id: "keys")`.

Add catalog keys and checklist lines:

```markdown
- [ ] Menü çubuğunda "Host" menüsü: ⌘N, ⌘D, Sil… (onaylı; ⌫ / ⌘⌫ yalnızca liste odaktayken), ⌘T, ⌘↩, ⌘⇧F, ⌘⇧C çalışıyor; metin alanında ⌘⌫ satır silmeye devam ediyor.
- [ ] "Tümünü test et" sonrası araç çubuğunda ✓/⚠/✕ sayıları; birine tıklayınca liste süzülüyor, "Tümünü Göster" ile kalkıyor.
- [ ] Boş config ile açılınca üç adımlı karşılama ekranı; "Anahtar oluştur" Anahtarlar penceresini Yeni Anahtar formuyla açıyor.
```

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/StatusSummaryTests`, then `bash scripts/test-app.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat: Host menu with shortcuts, status summary filter and onboarding"
```
