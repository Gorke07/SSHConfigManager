# Plan 1 — SSHConfigKit Çekirdeği: Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SSH config dosyasını kayıpsız okuyup düzenleyen, doğrulayan, yedekleyip güvenli şekilde yazan ve bağlantı komutlarını/testlerini üreten, UI'dan bağımsız, tamamen test edilmiş `SSHConfigKit` Swift paketi.

**Architecture:** Satır tabanlı kayıpsız bir belge modeli (`ConfigDocument`) her satırın orijinal metnini saklar; düzenlemeler yalnızca dokunulan satırları yeniden üretir. Dosya G/Ç'si (`SafeFileWriter`, `BackupManager`, `FileWatcher`), süreç çalıştırma (`ProcessRunner`) ve ssh entegrasyonları (`ConfigValidator`, `ConnectionTester`, `SSHCommandBuilder`) ayrı, enjekte edilebilir birimlerdir. `ConfigStore` (`@MainActor @Observable`) bunları UI'ın kullanacağı tek bir duruma bağlar.

**Tech Stack:** Swift 6.2+ (Xcode 26.6 / Swift 6.3 kurulu), Swift Package Manager, Swift Testing, Foundation, CryptoKit, CoreServices (FSEvents), Synchronization (`Mutex`), Observation.

**Spec:** `docs/design/2026-10-07-ssh-config-manager-design.md` — bu plan §4 (parser ve güvenli düzenleme), §5 (dosya seçiminin store tarafı), §6.4 (bağlantı testi), §9.1 (komut), §10 ve §11'in paket kısmını uygular.

### Yol haritası (bu plan serisinin parçası)

| Plan | Kapsam | Durum |
|---|---|---|
| **1 — SSHConfigKit çekirdeği** | Bu doküman | — |
| 2 — Uygulama kabuğu ve arayüz | Xcode projesi (XcodeGen), ana pencere, diff onayı, terminal başlatıcıları + §12 denemeleri, menü çubuğu, hızlı panel + global kısayol, ayarlar, yedekler ekranı, String Catalog (en/tr) | Plan 1 bitince yazılacak |
| 3 — Known Hosts | Parser, `HostMatcher`, `Fingerprint`, pencere, test sonucu entegrasyonu | Plan 2 sonrası |
| 4 — Anahtar yönetimi | `KeyScanner`, `KeyManager`, askpass, pencere | Plan 2 sonrası |
| 5 — Dağıtım | İmzalama, notarization, `.dmg`, manuel test listesi | En son |

## Global Constraints

- Paket: `Packages/SSHConfigKit`, `swift-tools-version: 6.2`, Swift 6 dil modu, `platforms: [.macOS(.v26)]`.
- Pakette üçüncü parti bağımlılık yok.
- Pakette kullanıcıya görünen metin yok; tüm sonuçlar tipli değerlerdir (çeviri Plan 2'de uygulama katmanında).
- ssh_config anahtar kelimeleri `asciiLowercased` ile karşılaştırılır. `localizedCaseInsensitiveCompare`, `caseInsensitiveCompare`, `lowercased(with:)`, `uppercased(with:)`, `localizedLowercase`, `localizedUppercase` paket kaynaklarında **yasak** (Task 3'te bir test bunu denetler).
- "Bayt bayt aynı" karşılaştırmaları her zaman `Array(a.utf8) == Array(b.utf8)` veya `a.utf8.elementsEqual(b.utf8)` ile yapılır; Swift `String ==` kanonik eşdeğerlik kullandığı için yeterli değildir.
- Metin çözme yalnızca `String(validating: data, as: UTF8.self)` ile yapılır. `String(data:encoding:)` BOM'u silebildiği için kullanılmaz.
- Harici araçlar sabit yoldan çağrılır: `/usr/bin/ssh`. Her alt sürece `LC_ALL=C` verilir.
- Yeni oluşturulan dosyalar `0600`, dizinler `0700` izinli olur.
- Testler gerçek `~/.ssh` dizinine dokunmaz; tüm yollar ve ev dizini enjekte edilir.
- Test komutu (paket kökünden): `swift test --package-path Packages/SSHConfigKit`.

## Review Focus

1. **UTF-8 BOM'lu config dosyası** → OpenSSH bu dosyayı reddeder (`Bad configuration option: \357\273\277host`). Uygulama ssh'in gördüğünü gösterir: BOM'u tespit eder, ilk satırı anlaşılmayan satır olarak işaretler, BOM'u izinsiz silmez; kayıt `ssh -G` doğrulamasında durur ve kullanıcı `removeByteOrderMark()` ile düzeltebilir (Task 2 ve Task 16'da test).
2. **CRLF veya karışık satır sonlu dosyada düzenleme** → dokunulmayan satırların satır sonları aynen kalır, yeni satırlar dosyanın satır sonunu kullanır (Task 2, 4, 5'te test).
3. **Boşluk, tek tırnak veya shell meta karakteri içeren alias/yol** → üretilen terminal komutu tek bir argüman olarak iletilir, komut enjeksiyonu olmaz (Task 12'de test).
4. **Config dosyası bir symlink (dotfiles)** → yazma hedef dosyaya yapılır, symlink symlink olarak kalır (Task 9'da test).
5. **Kaydedilmemiş değişiklik varken dosyanın başka bir editörle değişmesi** → sessizce üzerine yazılmaz; çakışma bildirilir, yalnızca açık onayla üzerine yazılır (Task 9 ve Task 16'da test).

---

## Dosya yapısı

```
Packages/SSHConfigKit/
├── Package.swift
├── Sources/SSHConfigKit/
│   ├── Config/
│   │   ├── ASCII.swift                 asciiLowercased (locale'den bağımsız)
│   │   ├── LineTokenizer.swift         Tek satırı kayıpsız parçalara ayırır
│   │   ├── ConfigLine.swift            LineKind + ConfigLine
│   │   ├── ConfigDocument.swift        Parse / render (BOM, CRLF, son newline)
│   │   ├── ConfigDocument+Read.swift   HostEntry, MatchEntry, IncludeDirective, blok sınırları
│   │   ├── ValueFormatter.swift        Tek değerli anahtarlar için tırnaklama
│   │   ├── HostDraft.swift             HostDraft, DraftDirective
│   │   ├── ConfigDocument+Edit.swift   updateHost / addHost / removeHost / duplicateHost
│   │   ├── HostDraftValidator.swift    DraftIssue + doğrulama
│   │   ├── LineDiff.swift              Satır diff'i + unified hunk'lar
│   │   └── IncludeResolver.swift       Include edilen dosyalardaki hostlar
│   ├── IO/
│   │   ├── FileFingerprint.swift
│   │   ├── BackupManager.swift
│   │   ├── SafeFileWriter.swift
│   │   └── FileWatcher.swift
│   ├── Process/
│   │   └── ProcessRunner.swift
│   ├── SSH/
│   │   ├── SSHCommandBuilder.swift
│   │   ├── ConfigValidator.swift
│   │   └── ConnectionTester.swift
│   └── Stores/
│       └── ConfigStore.swift
└── Tests/SSHConfigKitTests/
    ├── Support/TestSupport.swift       TempDir, SplitMix64, FakeRunner, TestClock
    └── <Birim>Tests.swift              her görev için bir dosya
```

---

### Task 1: Paket iskeleti ve satır tokenizer'ı

**Files:**
- Create: `.gitignore`
- Create: `Packages/SSHConfigKit/Package.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/ASCII.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/LineTokenizer.swift`
- Create: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/Support/TestSupport.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/LineTokenizerTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `extension StringProtocol { var asciiLowercased: String }` (internal)
  - `struct LineParts: Equatable, Sendable { var indent, key, separator, value, trailing: String; var raw: String }` (internal)
  - `enum LineTokenizer` (internal): `enum Classification { case blank, comment, keyed(LineParts), unknown; var parts: LineParts? }`, `static func classify(_ raw: String) -> Classification`, `static func arguments(of value: String) -> [String]`, `static func replacingValue(in parts: LineParts, with newValue: String) -> String`, `static func isSpace(_ c: Unicode.Scalar) -> Bool`
  - Test destek tipleri: `final class TempDir`, `struct SplitMix64: RandomNumberGenerator`

- [ ] **Step 1: İskeleti oluştur**

`.gitignore` (repo kökü):

```gitignore
.DS_Store
.build/
.swiftpm/
DerivedData/
xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
```

`Packages/SSHConfigKit/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SSHConfigKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SSHConfigKit", targets: ["SSHConfigKit"]),
    ],
    targets: [
        .target(name: "SSHConfigKit"),
        .testTarget(name: "SSHConfigKitTests", dependencies: ["SSHConfigKit"]),
    ]
)
```

`Packages/SSHConfigKit/Tests/SSHConfigKitTests/Support/TestSupport.swift`:

```swift
import Foundation

/// A unique temporary directory that is removed when the object is released.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SSHConfigKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Creates (or overwrites) a file inside the directory and returns its URL.
    @discardableResult
    func file(_ name: String, _ contents: String = "", permissions: Int = 0o600) throws -> URL {
        let target = url.appending(path: name)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        return target
    }

    func read(_ name: String) throws -> String {
        let data = try Data(contentsOf: url.appending(path: name))
        return String(decoding: data, as: UTF8.self)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Deterministic RNG for reproducible randomized tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 2: Başarısız testleri yaz**

`Packages/SSHConfigKit/Tests/SSHConfigKitTests/LineTokenizerTests.swift`:

```swift
import Testing
@testable import SSHConfigKit

struct LineTokenizerTests {
    @Test func blankAndCommentLines() {
        #expect(LineTokenizer.classify("") == .blank)
        #expect(LineTokenizer.classify(" \t ") == .blank)
        #expect(LineTokenizer.classify("\r") == .blank)
        #expect(LineTokenizer.classify("  # yorum") == .comment)
        #expect(LineTokenizer.classify("#Host x") == .comment)
    }

    @Test(arguments: [
        "Host web",
        "    HostName 10.0.0.1",
        "\tUser=deploy",
        "Port = 2222",
        "IdentityFile \"~/My Keys/id\"  # anahtar",
        "ProxyJump bastion\r",
        "Host",
        "Key  #c",
        "Host e\u{301}",
    ])
    func partsReassembleToRaw(raw: String) throws {
        let parts = try #require(LineTokenizer.classify(raw).parts)
        #expect(Array(parts.raw.utf8) == Array(raw.utf8))
    }

    @Test func splitsIntoIndentKeySeparatorValueTrailing() throws {
        let p = try #require(LineTokenizer.classify("  Port = 2222 # ssh\r").parts)
        #expect(p.indent == "  ")
        #expect(p.key == "Port")
        #expect(p.separator == " = ")
        #expect(p.value == "2222")
        #expect(p.trailing == " # ssh\r")
    }

    @Test func hashInsideTokenIsNotAComment() throws {
        let p = try #require(LineTokenizer.classify("Host foo#bar").parts)
        #expect(p.value == "foo#bar")
        #expect(p.trailing == "")
    }

    @Test func quotedValueMayContainHash() throws {
        let p = try #require(LineTokenizer.classify("IdentityFile \"~/a #b\" # c").parts)
        #expect(p.value == "\"~/a #b\"")
        #expect(p.trailing == " # c")
    }

    @Test(arguments: ["=foo", "Ho:st x", "-x y"])
    func unknownLines(raw: String) {
        #expect(LineTokenizer.classify(raw) == .unknown)
    }

    @Test func argumentsRespectQuotes() {
        #expect(LineTokenizer.arguments(of: "a  \"b c\" d") == ["a", "b c", "d"])
        #expect(LineTokenizer.arguments(of: "\"\"") == [""])
        #expect(LineTokenizer.arguments(of: "") == [])
    }

    @Test func replacingValueKeepsLayout() throws {
        let p1 = try #require(LineTokenizer.classify("\tHostName  old # prod\r").parts)
        #expect(LineTokenizer.replacingValue(in: p1, with: "new") == "\tHostName  new # prod\r")

        let p2 = try #require(LineTokenizer.classify("User=u").parts)
        #expect(LineTokenizer.replacingValue(in: p2, with: "v") == "User=v")

        let p3 = try #require(LineTokenizer.classify("Host").parts)
        #expect(LineTokenizer.replacingValue(in: p3, with: "a") == "Host a")

        let p4 = try #require(LineTokenizer.classify("Key  #c").parts)
        #expect(LineTokenizer.replacingValue(in: p4, with: "v") == "Key  v #c")
    }

    @Test func asciiLowercasedIgnoresLocale() {
        #expect("INCLUDE".asciiLowercased == "include")
        #expect("IdentityFile".asciiLowercased == "identityfile")
        #expect("İstanbul".asciiLowercased == "İstanbul")
    }
}
```

- [ ] **Step 3: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter LineTokenizerTests`
Expected: FAIL — derleme hatası, `cannot find 'LineTokenizer' in scope`.

- [ ] **Step 4: Uygulamayı yaz**

`Sources/SSHConfigKit/Config/ASCII.swift`:

```swift
extension StringProtocol {
    /// Lowercases ASCII A–Z only. ssh_config keywords are ASCII; locale-aware
    /// lowercasing would break under the Turkish locale (I → ı).
    var asciiLowercased: String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            if (65...90).contains(scalar.value), let lower = Unicode.Scalar(scalar.value + 32) {
                scalars.append(lower)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
```

`Sources/SSHConfigKit/Config/LineTokenizer.swift`:

```swift
/// Lossless pieces of a keyed config line: `indent + key + separator + value + trailing == raw`.
struct LineParts: Equatable, Sendable {
    var indent: String
    var key: String
    var separator: String
    var value: String
    /// Whitespace, trailing comment and a trailing "\r", if any.
    var trailing: String

    var raw: String { indent + key + separator + value + trailing }
}

enum LineTokenizer {
    enum Classification: Equatable, Sendable {
        case blank
        case comment
        case keyed(LineParts)
        case unknown

        var parts: LineParts? {
            if case .keyed(let parts) = self { return parts }
            return nil
        }
    }

    /// Works on Unicode scalars, never Characters: "\r\n" and combining marks
    /// form single Characters and would hide boundaries.
    static func classify(_ raw: String) -> Classification {
        let s = Array(raw.unicodeScalars)
        var end = s.count
        if end > 0 && s[end - 1] == "\r" { end -= 1 }

        var i = 0
        while i < end && isSpace(s[i]) { i += 1 }
        if i == end { return .blank }
        if s[i] == "#" { return .comment }

        let indentEnd = i
        while i < end && !isSpace(s[i]) && s[i] != "=" { i += 1 }
        let keyEnd = i
        guard keyEnd > indentEnd, s[indentEnd..<keyEnd].allSatisfy(isKeyScalar) else { return .unknown }

        while i < end && isSpace(s[i]) { i += 1 }
        if i < end && s[i] == "=" {
            i += 1
            while i < end && isSpace(s[i]) { i += 1 }
        }
        let valueStart = i

        var valueEnd = i
        var j = i
        var inQuote = false
        while j < end {
            if !inQuote && isSpace(s[j]) { j += 1; continue }
            if !inQuote && s[j] == "#" { break }
            while j < end && (inQuote || !isSpace(s[j])) {
                if s[j] == "\"" { inQuote.toggle() }
                j += 1
            }
            valueEnd = j
        }

        return .keyed(LineParts(
            indent: string(s[0..<indentEnd]),
            key: string(s[indentEnd..<keyEnd]),
            separator: string(s[keyEnd..<valueStart]),
            value: string(s[valueStart..<valueEnd]),
            trailing: string(s[valueEnd..<s.count])
        ))
    }

    /// Splits a value into arguments; double quotes group and are removed.
    static func arguments(of value: String) -> [String] {
        var args: [String] = []
        var current = String.UnicodeScalarView()
        var inQuote = false
        var hasToken = false
        for c in value.unicodeScalars {
            if c == "\"" {
                inQuote.toggle()
                hasToken = true
                continue
            }
            if !inQuote && isSpace(c) {
                if hasToken {
                    args.append(String(current))
                    current = String.UnicodeScalarView()
                    hasToken = false
                }
                continue
            }
            current.append(c)
            hasToken = true
        }
        if hasToken { args.append(String(current)) }
        return args
    }

    /// Rebuilds a line with a new value while keeping indent, separator, comment and line ending.
    static func replacingValue(in parts: LineParts, with newValue: String) -> String {
        let separator = parts.separator.isEmpty ? " " : parts.separator
        var trailing = parts.trailing
        if trailing.unicodeScalars.first == "#" { trailing = " " + trailing }
        return parts.indent + parts.key + separator + newValue + trailing
    }

    static func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" }

    private static func isKeyScalar(_ c: Unicode.Scalar) -> Bool {
        (65...90).contains(c.value) || (97...122).contains(c.value) || (48...57).contains(c.value)
    }

    private static func string(_ slice: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: slice)
        return String(view)
    }
}
```

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter LineTokenizerTests`
Expected: PASS (tüm testler).

- [ ] **Step 6: Commit**

```bash
git add .gitignore Packages/SSHConfigKit
git commit -m "feat(kit): paket iskeleti ve kayıpsız satır tokenizer'ı"
```

---

### Task 2: `ConfigLine` ve `ConfigDocument` — kayıpsız parse/render

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/ConfigLine.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/ConfigDocument.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConfigDocumentRoundTripTests.swift`

**Interfaces:**
- Consumes: `LineTokenizer.classify`, `LineTokenizer.arguments`, `asciiLowercased` (Task 1)
- Produces:
  - `public enum LineKind: Equatable, Sendable { case blank, comment, directive(key: String, value: String), hostStart(patterns: [String]), matchStart(criteria: String), include(paths: [String]), unknown }` + internal `var isHeader: Bool`
  - `public struct ConfigLine: Equatable, Sendable { public let raw: String; public let kind: LineKind; public init(raw: String) }` + internal `var parts: LineParts?`
  - `public struct ConfigDocument: Equatable, Sendable { public internal(set) var lines: [ConfigLine]; public internal(set) var hasTrailingNewline: Bool; public let usesCRLF: Bool; public var hasByteOrderMark: Bool; public static let empty; public init(parsing: String); public func render() -> String; public mutating func removeByteOrderMark() }` + internal `var lineEndingSuffix: String`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/ConfigDocumentRoundTripTests.swift`:

```swift
import Testing
@testable import SSHConfigKit

struct ConfigDocumentRoundTripTests {
    static let samples: [String] = [
        "",
        "\n",
        "\n\n",
        "Host a",
        "Host a\n",
        "Host a\n  HostName b\n",
        "# global\nUser me\n\nHost *\n    ServerAliveInterval 30\n",
        "Host web\r\n\tHostName 10.0.0.1\r\n",
        "Host a\r\n  User x\n  Port 22\r\n",
        "\u{FEFF}Host bom\n  HostName x\n",
        "Host=eq\n  User = me\n  Port=22\n",
        "Host \"quoted name\"\n  IdentityFile \"~/My Keys/id\" # yorum\n",
        "Match exec \"test -f /tmp/x\"\n  User y\n",
        "Include ~/.ssh/config.d/*\n",
        "Host ünicode-çğış\n  User Gökhan\n",
        "=garbage\n   \t  \nHo:st weird\n",
        "Host e\u{301}\n",
        "trailing spaces   \n\t\n",
        "\r\n\r\n",
    ]

    @Test(arguments: samples)
    func renderIsByteIdentical(text: String) {
        let doc = ConfigDocument(parsing: text)
        #expect(Array(doc.render().utf8) == Array(text.utf8))
    }

    @Test func randomMixesRoundTrip() {
        var rng = SplitMix64(seed: 42)
        let pool = [
            "Host a", "  HostName h", "\tUser=u", "# c", "", "   ", "Match all", "Include x/*",
            "=bad", "IdentityFile \"a b\" # k", "Port 22 #x", "\u{FEFF}Host bom", "Host e\u{301}",
        ]
        let endings = ["\n", "\r\n"]
        for _ in 0..<500 {
            let count = Int.random(in: 0...12, using: &rng)
            var text = ""
            for index in 0..<count {
                text += pool.randomElement(using: &rng)!
                if index < count - 1 || Bool.random(using: &rng) {
                    text += endings.randomElement(using: &rng)!
                }
            }
            let rendered = ConfigDocument(parsing: text).render()
            #expect(Array(rendered.utf8) == Array(text.utf8), "girdi: \(text.debugDescription)")
        }
    }

    @Test func lineKinds() {
        let doc = ConfigDocument(parsing: "# c\nUser me\n\nHOST web *.x\n  HostName h\nMatch host x\nInclude a \"b c\"\n=?\n")
        #expect(doc.lines.map(\.kind) == [
            .comment,
            .directive(key: "User", value: "me"),
            .blank,
            .hostStart(patterns: ["web", "*.x"]),
            .directive(key: "HostName", value: "h"),
            .matchStart(criteria: "host x"),
            .include(paths: ["a", "b c"]),
            .unknown,
        ])
    }

    @Test func byteOrderMarkIsKeptAndSeenAsSshSeesIt() {
        var doc = ConfigDocument(parsing: "\u{FEFF}Host bom\n")
        #expect(doc.hasByteOrderMark)
        // OpenSSH rejects "\u{FEFF}Host"; we show the line as not understood instead of hiding the problem.
        #expect(doc.lines.first?.kind == .unknown)

        doc.removeByteOrderMark()

        #expect(!doc.hasByteOrderMark)
        #expect(doc.lines.first?.kind == .hostStart(patterns: ["bom"]))
        #expect(Array(doc.render().utf8) == Array("Host bom\n".utf8))
    }

    @Test func detectsCRLFAndTrailingNewline() {
        #expect(ConfigDocument(parsing: "Host a\r\n").usesCRLF)
        #expect(!ConfigDocument(parsing: "Host a\n").usesCRLF)
        #expect(ConfigDocument(parsing: "Host a\n").hasTrailingNewline)
        #expect(!ConfigDocument(parsing: "Host a").hasTrailingNewline)
        #expect(ConfigDocument(parsing: "").lines.isEmpty)
        #expect(ConfigDocument(parsing: "Host a\r\n").lineEndingSuffix == "\r")
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ConfigDocumentRoundTripTests`
Expected: FAIL — `cannot find 'ConfigDocument' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/Config/ConfigLine.swift`:

```swift
public enum LineKind: Equatable, Sendable {
    case blank
    case comment
    /// `value` is the raw value text: quotes kept, trailing comment removed.
    case directive(key: String, value: String)
    case hostStart(patterns: [String])
    case matchStart(criteria: String)
    case include(paths: [String])
    /// A line we cannot interpret; it is preserved verbatim.
    case unknown

    var isHeader: Bool {
        switch self {
        case .hostStart, .matchStart: true
        default: false
        }
    }
}

public struct ConfigLine: Equatable, Sendable {
    /// Exact original text without the "\n" separator (may end with "\r").
    public let raw: String
    public let kind: LineKind

    public init(raw: String) {
        self.raw = raw
        switch LineTokenizer.classify(raw) {
        case .blank: kind = .blank
        case .comment: kind = .comment
        case .unknown: kind = .unknown
        case .keyed(let parts):
            switch parts.key.asciiLowercased {
            case "host": kind = .hostStart(patterns: LineTokenizer.arguments(of: parts.value))
            case "match": kind = .matchStart(criteria: parts.value)
            case "include": kind = .include(paths: LineTokenizer.arguments(of: parts.value))
            default: kind = .directive(key: parts.key, value: parts.value)
            }
        }
    }

    var parts: LineParts? { LineTokenizer.classify(raw).parts }
}
```

`Sources/SSHConfigKit/Config/ConfigDocument.swift`:

```swift
/// Line-based, lossless model of an ssh_config file. Untouched lines render
/// exactly as they were read.
public struct ConfigDocument: Equatable, Sendable {
    public internal(set) var lines: [ConfigLine]
    public internal(set) var hasTrailingNewline: Bool
    /// True when the first non-empty line ends with "\r"; new lines follow this convention.
    public let usesCRLF: Bool

    public static let empty = ConfigDocument(parsing: "")

    public init(parsing text: String) {
        // Split on the "\n" byte; "\r\n" is a single Character and must not be split by Character.
        // A UTF-8 BOM stays part of the first line, exactly as ssh reads it.
        var rawLines = text.utf8
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }

        if rawLines.count > 1, rawLines.last == "" {
            rawLines.removeLast()
            hasTrailingNewline = true
        } else {
            if rawLines == [""] { rawLines = [] }
            hasTrailingNewline = false
        }

        lines = rawLines.map(ConfigLine.init(raw:))
        usesCRLF = rawLines.first(where: { !$0.isEmpty })?.unicodeScalars.last == "\r"
    }

    public func render() -> String {
        var out = lines.map(\.raw).joined(separator: "\n")
        if hasTrailingNewline { out += "\n" }
        return out
    }

    /// OpenSSH cannot parse a file that starts with a UTF-8 BOM.
    public var hasByteOrderMark: Bool {
        lines.first?.raw.unicodeScalars.first == "\u{FEFF}"
    }

    public mutating func removeByteOrderMark() {
        guard hasByteOrderMark else { return }
        lines[0] = ConfigLine(raw: String(String.UnicodeScalarView(lines[0].raw.unicodeScalars.dropFirst())))
    }

    /// Appended to every newly created line ("\r" for CRLF files).
    var lineEndingSuffix: String { usesCRLF ? "\r" : "" }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ConfigDocumentRoundTripTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): kayıpsız ConfigDocument parse/render (BOM, CRLF, son newline)"
```

---

### Task 3: Okuma modeli — hostlar, desenler, Match, Include, blok sınırları

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/ValueFormatter.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/ConfigDocument+Read.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConfigDocumentReadTests.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/LocaleSafetyTests.swift`

**Interfaces:**
- Consumes: `ConfigDocument`, `ConfigLine`, `LineKind` (Task 2); `LineTokenizer.arguments`, `LineTokenizer.isSpace` (Task 1)
- Produces:
  - `public enum ValueFormatter { public static func display(key: String, rawValue: String) -> String; public static func encode(key: String, value: String) -> String }`
  - `public struct HostDirective: Equatable, Sendable { public let line: Int; public let key: String; public let value: String }`
  - `public struct HostEntry: Identifiable, Equatable, Sendable { public let headerLine: Int; public let patterns: [String]; public let directives: [HostDirective]; public var id: Int; public var alias: String; public var isPattern: Bool; public func values(for key: String) -> [String]; public func value(for key: String) -> String? }`
  - `public struct MatchEntry: Equatable, Sendable { public let headerLine: Int; public let criteria: String; public let text: String }`
  - `public struct IncludeDirective: Equatable, Sendable { public let line: Int; public let paths: [String] }`
  - `extension ConfigDocument`: `public var hosts: [HostEntry]`, `public func hostEntry(at header: Int) -> HostEntry?`, `public var matches: [MatchEntry]`, `public var includes: [IncludeDirective]`, `public var globalDirectives: [HostDirective]`; internal `var headerIndices: [Int]`, `func blockEnd(after header: Int) -> Int`, `func ownedEnd(of header: Int) -> Int`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/ConfigDocumentReadTests.swift`:

```swift
import Testing
@testable import SSHConfigKit

struct ConfigDocumentReadTests {
    let sample = """
    # global
    User me
    Include config.d/*

    # web sunucusu
    Host web web2
        HostName 10.0.0.1
        IdentityFile "~/My Keys/id"
        IdentityFile ~/.ssh/second

    HOST *.prod
      user deploy

    Match host x exec "true"
      Port 2200

    Host *
        ServerAliveInterval 30

    """

    @Test func parsesHostsWithDisplayValues() throws {
        let doc = ConfigDocument(parsing: sample)
        #expect(doc.hosts.map(\.patterns) == [["web", "web2"], ["*.prod"], ["*"]])
        let web = try #require(doc.hosts.first)
        #expect(web.alias == "web")
        #expect(web.headerLine == 5)
        #expect(!web.isPattern)
        #expect(web.value(for: "hostname") == "10.0.0.1")
        #expect(web.values(for: "IDENTITYFILE") == ["~/My Keys/id", "~/.ssh/second"])
        #expect(web.directives.map(\.line) == [6, 7, 8])
    }

    @Test func patternsAreFlagged() {
        let doc = ConfigDocument(parsing: "Host a\nHost *.x\nHost ?b\nHost !c d\nHost\n")
        #expect(doc.hosts.map(\.isPattern) == [false, true, true, true, true])
    }

    @Test func matchesIncludesAndGlobals() throws {
        let doc = ConfigDocument(parsing: sample)
        let match = try #require(doc.matches.first)
        #expect(match.criteria == "host x exec \"true\"")
        #expect(match.text == "Match host x exec \"true\"\n  Port 2200")
        #expect(doc.includes == [IncludeDirective(line: 2, paths: ["config.d/*"])])
        #expect(doc.globalDirectives.map(\.key) == ["User"])
    }

    @Test func uppercaseKeywordsAreRecognized() {
        let doc = ConfigDocument(parsing: "INCLUDE x\nHOST a\n  IDENTITYFILE k\n")
        #expect(doc.includes.count == 1)
        #expect(doc.hosts.first?.value(for: "IdentityFile") == "k")
    }

    @Test func blockBoundaries() {
        let doc = ConfigDocument(parsing: "Host a\n  X 1\n\n# b\nHost b\n  Y 2\n# trailing\n")
        #expect(doc.headerIndices == [0, 4])
        #expect(doc.blockEnd(after: 0) == 4)
        // The "# b" comment belongs to the next host, not to "a".
        #expect(doc.ownedEnd(of: 0) == 3)
        #expect(doc.ownedEnd(of: 4) == 7)
    }

    @Test func valueFormatter() {
        #expect(ValueFormatter.display(key: "IdentityFile", rawValue: "\"~/a b\"") == "~/a b")
        #expect(ValueFormatter.display(key: "LocalForward", rawValue: "8080 \"h:80\"") == "8080 \"h:80\"")
        #expect(ValueFormatter.encode(key: "identityfile", value: "~/a b") == "\"~/a b\"")
        #expect(ValueFormatter.encode(key: "IdentityFile", value: "~/ab") == "~/ab")
        #expect(ValueFormatter.encode(key: "LocalForward", value: "8080 h:80") == "8080 h:80")
    }
}
```

`Tests/SSHConfigKitTests/LocaleSafetyTests.swift`:

```swift
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
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter "ConfigDocumentReadTests|LocaleSafetyTests"`
Expected: FAIL — `value of type 'ConfigDocument' has no member 'hosts'`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/Config/ValueFormatter.swift`:

```swift
/// Converts between the raw text of a directive value and the form shown/edited in the UI.
/// Only keys that take exactly one argument are unquoted/quoted; multi-argument
/// values (LocalForward, SendEnv, ProxyCommand …) are shown and written verbatim.
public enum ValueFormatter {
    static let singleValueKeys: Set<String> = [
        "hostname", "user", "port", "identityfile", "certificatefile",
        "identityagent", "controlpath", "hostkeyalias", "proxyjump",
    ]

    public static func display(key: String, rawValue: String) -> String {
        guard singleValueKeys.contains(key.asciiLowercased) else { return rawValue }
        let args = LineTokenizer.arguments(of: rawValue)
        return args.count == 1 ? args[0] : rawValue
    }

    public static func encode(key: String, value: String) -> String {
        guard singleValueKeys.contains(key.asciiLowercased),
              value.unicodeScalars.contains(where: LineTokenizer.isSpace),
              value.unicodeScalars.first != "\""
        else { return value }
        return "\"" + value + "\""
    }
}
```

`Sources/SSHConfigKit/Config/ConfigDocument+Read.swift`:

```swift
public struct HostDirective: Equatable, Sendable {
    public let line: Int
    public let key: String
    /// Display value (see `ValueFormatter.display`).
    public let value: String
}

public struct HostEntry: Identifiable, Equatable, Sendable {
    /// Index of the `Host` line. Valid only for the document version it came from.
    public let headerLine: Int
    public let patterns: [String]
    public let directives: [HostDirective]

    public var id: Int { headerLine }
    public var alias: String { patterns.first ?? "" }

    /// Wildcard / negated / empty blocks cannot be connected to.
    public var isPattern: Bool {
        patterns.isEmpty || patterns.contains { $0.contains("*") || $0.contains("?") || $0.hasPrefix("!") }
    }

    public func values(for key: String) -> [String] {
        let wanted = key.asciiLowercased
        return directives.filter { $0.key.asciiLowercased == wanted }.map(\.value)
    }

    public func value(for key: String) -> String? { values(for: key).first }
}

public struct MatchEntry: Equatable, Sendable {
    public let headerLine: Int
    public let criteria: String
    /// Raw text of the block (header through its last owned non-blank line).
    public let text: String
}

public struct IncludeDirective: Equatable, Sendable {
    public let line: Int
    public let paths: [String]
}

extension ConfigDocument {
    var headerIndices: [Int] { lines.indices.filter { lines[$0].kind.isHeader } }

    /// Index of the next header after `header`, or `lines.count`.
    func blockEnd(after header: Int) -> Int {
        var i = header + 1
        while i < lines.count && !lines[i].kind.isHeader { i += 1 }
        return i
    }

    /// Like `blockEnd`, but comment lines glued to the next header belong to that header.
    func ownedEnd(of header: Int) -> Int {
        let end = blockEnd(after: header)
        guard end < lines.count else { return end }
        var e = end
        while e - 1 > header && lines[e - 1].kind == .comment { e -= 1 }
        return e
    }

    public func hostEntry(at header: Int) -> HostEntry? {
        guard lines.indices.contains(header), case .hostStart(let patterns) = lines[header].kind else {
            return nil
        }
        let end = blockEnd(after: header)
        return HostEntry(headerLine: header, patterns: patterns, directives: directives(in: (header + 1)..<end))
    }

    public var hosts: [HostEntry] { headerIndices.compactMap(hostEntry(at:)) }

    public var matches: [MatchEntry] {
        headerIndices.compactMap { header in
            guard case .matchStart(let criteria) = lines[header].kind else { return nil }
            var end = ownedEnd(of: header)
            while end - 1 > header && lines[end - 1].kind == .blank { end -= 1 }
            let text = lines[header..<end].map(\.raw).joined(separator: "\n")
            return MatchEntry(headerLine: header, criteria: criteria, text: text)
        }
    }

    public var includes: [IncludeDirective] {
        lines.indices.compactMap { i in
            guard case .include(let paths) = lines[i].kind else { return nil }
            return IncludeDirective(line: i, paths: paths)
        }
    }

    public var globalDirectives: [HostDirective] {
        directives(in: 0..<(headerIndices.first ?? lines.count))
    }

    private func directives(in range: Range<Int>) -> [HostDirective] {
        range.compactMap { i in
            guard case .directive(let key, let value) = lines[i].kind else { return nil }
            return HostDirective(line: i, key: key, value: ValueFormatter.display(key: key, rawValue: value))
        }
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter "ConfigDocumentReadTests|LocaleSafetyTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): host/match/include okuma modeli ve locale güvenliği testi"
```

---

### Task 4: Host güncelleme (`updateHost`)

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/HostDraft.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/ConfigDocument+Edit.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/UpdateHostTests.swift`

**Interfaces:**
- Consumes: `hostEntry(at:)`, `blockEnd(after:)`, `ConfigLine.parts`, `lineEndingSuffix`, `ValueFormatter.encode`, `LineTokenizer.replacingValue`
- Produces:
  - `public struct DraftDirective: Equatable, Sendable { public var key: String; public var value: String; public init(key:value:) }`
  - `public struct HostDraft: Equatable, Sendable { public var patterns: [String]; public var directives: [DraftDirective]; public init(patterns:directives:); public init(_ entry: HostEntry) }`
  - `public enum ConfigEditError: Error, Equatable, Sendable { case hostNotFound(Int) }`
  - `extension ConfigDocument { public mutating func updateHost(at header: Int, to draft: HostDraft) throws }`; internal `var directiveIndent: String`, `func makeDirectiveLine(indent: String, key: String, value: String) -> ConfigLine`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/UpdateHostTests.swift`:

```swift
import Testing
@testable import SSHConfigKit

struct UpdateHostTests {
    private func update(_ text: String, header: Int = 0, _ change: (inout HostDraft) -> Void) throws -> String {
        var doc = ConfigDocument(parsing: text)
        var draft = HostDraft(try #require(doc.hostEntry(at: header)))
        change(&draft)
        try doc.updateHost(at: header, to: draft)
        return doc.render()
    }

    private func set(_ draft: inout HostDraft, _ key: String, _ value: String) {
        let index = draft.directives.firstIndex { $0.key == key }!
        draft.directives[index].value = value
    }

    @Test func unchangedDraftIsByteIdentical() throws {
        let text = "Host a b # c\n\tHostName  h # x\n  IdentityFile \"~/a b\"\n  User=u\n"
        let out = try update(text) { _ in }
        #expect(Array(out.utf8) == Array(text.utf8))
    }

    @Test func changingValueKeepsIndentSeparatorAndComment() throws {
        let out = try update("Host web\n\tHostName  old.example # prod\n  User u\n") {
            set(&$0, "HostName", "new.example")
        }
        #expect(out == "Host web\n\tHostName  new.example # prod\n  User u\n")
    }

    @Test func equalsSeparatorIsKept() throws {
        let out = try update("Host a\n  User=u\n") { set(&$0, "User", "v") }
        #expect(out == "Host a\n  User=v\n")
    }

    @Test func addedDirectiveGoesAfterLastDirective() throws {
        let out = try update("Host a\n  User u\n\n# b\nHost b\n") {
            $0.directives.append(DraftDirective(key: "Port", value: "22"))
        }
        #expect(out == "Host a\n  User u\n  Port 22\n\n# b\nHost b\n")
    }

    @Test func addedDirectiveInEmptyBlockUsesDocumentIndent() throws {
        let out = try update("Host a\nHost b\n\tUser u\n") {
            $0.directives.append(DraftDirective(key: "User", value: "x"))
        }
        #expect(out == "Host a\n\tUser x\nHost b\n\tUser u\n")
    }

    @Test func removingDirectiveDeletesOnlyThatLine() throws {
        let out = try update("Host a\n  User u\n  Port 22\n  # keep\n") {
            $0.directives.removeAll { $0.key == "Port" }
        }
        #expect(out == "Host a\n  User u\n  # keep\n")
    }

    @Test func repeatedKeysArePairedInOrder() throws {
        let out = try update("Host a\n  IdentityFile k1\n  IdentityFile k2\n") {
            $0.directives.removeLast()
        }
        #expect(out == "Host a\n  IdentityFile k1\n")
    }

    @Test func renamingAliasKeepsOtherPatternsAndComment() throws {
        let out = try update("Host a a2 # c\n  User u\n") { $0.patterns[0] = "x" }
        #expect(out == "Host x a2 # c\n  User u\n")
    }

    @Test func valuesWithSpacesAreQuoted() throws {
        let out = try update("Host a\n  IdentityFile ~/k\n") { set(&$0, "IdentityFile", "~/My Keys/k") }
        #expect(out == "Host a\n  IdentityFile \"~/My Keys/k\"\n")
    }

    @Test func crlfDocumentGetsCRLFOnNewLines() throws {
        let out = try update("Host a\r\n  User u\r\n") {
            $0.directives.append(DraftDirective(key: "Port", value: "22"))
        }
        #expect(Array(out.utf8) == Array("Host a\r\n  User u\r\n  Port 22\r\n".utf8))
    }

    @Test func mixedLineEndingsOfUntouchedLinesSurvive() throws {
        let out = try update("Host a\r\n  User u\n  Port 1\r\n") { set(&$0, "Port", "2") }
        #expect(Array(out.utf8) == Array("Host a\r\n  User u\n  Port 2\r\n".utf8))
    }

    @Test func unknownHeaderThrows() {
        var doc = ConfigDocument(parsing: "User x\n")
        #expect(throws: ConfigEditError.hostNotFound(0)) {
            try doc.updateHost(at: 0, to: HostDraft(patterns: ["a"]))
        }
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter UpdateHostTests`
Expected: FAIL — `cannot find 'HostDraft' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/Config/HostDraft.swift`:

```swift
public struct DraftDirective: Equatable, Sendable {
    public var key: String
    /// Display form; quoting is applied on write by `ValueFormatter.encode`.
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// The desired state of a Host block, as edited in the UI.
public struct HostDraft: Equatable, Sendable {
    public var patterns: [String]
    public var directives: [DraftDirective]

    public init(patterns: [String], directives: [DraftDirective] = []) {
        self.patterns = patterns
        self.directives = directives
    }

    public init(_ entry: HostEntry) {
        patterns = entry.patterns
        directives = entry.directives.map { DraftDirective(key: $0.key, value: $0.value) }
    }
}
```

`Sources/SSHConfigKit/Config/ConfigDocument+Edit.swift`:

```swift
public enum ConfigEditError: Error, Equatable, Sendable {
    case hostNotFound(Int)
}

extension ConfigDocument {
    /// Indent of the first directive inside any Host block, else four spaces.
    var directiveIndent: String {
        for entry in hosts {
            for directive in entry.directives {
                if let indent = lines[directive.line].parts?.indent { return indent }
            }
        }
        return "    "
    }

    func makeDirectiveLine(indent: String, key: String, value: String) -> ConfigLine {
        ConfigLine(raw: indent + key + " " + ValueFormatter.encode(key: key, value: value) + lineEndingSuffix)
    }

    /// Applies `draft` to the Host block at `header`, touching only lines whose content changes.
    /// Existing directives are paired with draft directives by key, in order of appearance.
    public mutating func updateHost(at header: Int, to draft: HostDraft) throws {
        guard let entry = hostEntry(at: header) else { throw ConfigEditError.hostNotFound(header) }
        let end = blockEnd(after: header)

        var replacements: [Int: ConfigLine] = [:]
        var deletions = Set<Int>()
        var insertions: [DraftDirective] = []

        if draft.patterns != entry.patterns, let parts = lines[header].parts {
            replacements[header] = ConfigLine(
                raw: LineTokenizer.replacingValue(in: parts, with: draft.patterns.joined(separator: " ")))
        }

        var existingByKey: [String: [HostDirective]] = [:]
        for directive in entry.directives {
            existingByKey[directive.key.asciiLowercased, default: []].append(directive)
        }
        var used: [String: Int] = [:]
        for wanted in draft.directives {
            let key = wanted.key.asciiLowercased
            let n = used[key, default: 0]
            used[key] = n + 1
            if let existing = existingByKey[key], n < existing.count {
                let old = existing[n]
                if old.value != wanted.value, let parts = lines[old.line].parts {
                    let encoded = ValueFormatter.encode(key: old.key, value: wanted.value)
                    replacements[old.line] = ConfigLine(raw: LineTokenizer.replacingValue(in: parts, with: encoded))
                }
            } else {
                insertions.append(wanted)
            }
        }
        for (key, existing) in existingByKey {
            for old in existing.dropFirst(used[key, default: 0]) { deletions.insert(old.line) }
        }

        var block: [ConfigLine] = []
        var insertAt = 1
        for i in header..<end where !deletions.contains(i) {
            block.append(replacements[i] ?? lines[i])
            switch lines[i].kind {
            case .directive, .include, .hostStart: insertAt = block.count
            default: break
            }
        }

        let indent = entry.directives.lazy.compactMap { self.lines[$0.line].parts?.indent }.first ?? directiveIndent
        block.insert(
            contentsOf: insertions.map { makeDirectiveLine(indent: indent, key: $0.key, value: $0.value) },
            at: insertAt)
        lines.replaceSubrange(header..<end, with: block)
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter UpdateHostTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): yalnızca değişen satırlara dokunan updateHost"
```

---

### Task 5: Host ekleme, silme, çoğaltma

**Files:**
- Modify: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/ConfigDocument+Edit.swift` (dosya sonuna ekle)
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/AddRemoveHostTests.swift`

**Interfaces:**
- Consumes: Task 3 ve Task 4'teki her şey
- Produces:
  - `public mutating func addHost(_ draft: HostDraft) -> Int` (`@discardableResult`, yeni header indeksi)
  - `public mutating func removeHost(at header: Int) throws`
  - `public mutating func duplicateHost(at header: Int, newAlias: String) throws -> Int` (`@discardableResult`)

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/AddRemoveHostTests.swift`:

```swift
import Testing
@testable import SSHConfigKit

struct AddRemoveHostTests {
    let draft = HostDraft(patterns: ["new"], directives: [DraftDirective(key: "HostName", value: "n.example")])

    @Test func addInsertsBeforeHostStarWithItsComment() {
        var doc = ConfigDocument(parsing: "Host a\n  User u\n\n# defaults\nHost *\n  User d\n")
        let header = doc.addHost(draft)
        #expect(doc.render() == "Host a\n  User u\n\nHost new\n  HostName n.example\n\n# defaults\nHost *\n  User d\n")
        #expect(doc.hostEntry(at: header)?.alias == "new")
    }

    @Test func addInsertsBeforeMatchAll() {
        var doc = ConfigDocument(parsing: "Host a\n  User u\nMatch all\n  User d\n")
        doc.addHost(draft)
        #expect(doc.render() == "Host a\n  User u\n\nHost new\n  HostName n.example\n\nMatch all\n  User d\n")
    }

    @Test func addAppendsWhenThereIsNoCatchAll() {
        var doc = ConfigDocument(parsing: "Host a\n\tUser u")
        let header = doc.addHost(draft)
        #expect(doc.render() == "Host a\n\tUser u\n\nHost new\n\tHostName n.example\n")
        #expect(header == 3)
    }

    @Test func addToEmptyDocument() {
        var doc = ConfigDocument.empty
        #expect(doc.addHost(draft) == 0)
        #expect(doc.render() == "Host new\n    HostName n.example\n")
    }

    @Test func addUsesCRLF() {
        var doc = ConfigDocument(parsing: "Host a\r\n")
        doc.addHost(draft)
        #expect(Array(doc.render().utf8) == Array("Host a\r\n\r\nHost new\r\n    HostName n.example\r\n".utf8))
    }

    @Test func removeDeletesAttachedCommentAndKeepsNextHostsComment() throws {
        var doc = ConfigDocument(parsing: "# web\nHost web\n  HostName a\n\n# db\nHost db\n  HostName b\n")
        try doc.removeHost(at: 1)
        #expect(doc.render() == "# db\nHost db\n  HostName b\n")
    }

    @Test func removeLastHostTrimsTrailingBlankLines() throws {
        var doc = ConfigDocument(parsing: "Host a\n  X 1\n\nHost b\n  Y 2\n")
        try doc.removeHost(at: 3)
        #expect(doc.render() == "Host a\n  X 1\n")
    }

    @Test func removeMiddleHostCollapsesBlankLines() throws {
        var doc = ConfigDocument(parsing: "Host a\n\nHost b\n  Y 2\n\nHost c\n")
        try doc.removeHost(at: 2)
        #expect(doc.render() == "Host a\n\nHost c\n")
    }

    @Test func removeOnlyHostLeavesEmptyFile() throws {
        var doc = ConfigDocument(parsing: "Host a\n  X 1\n")
        try doc.removeHost(at: 0)
        #expect(doc.render() == "")
    }

    @Test func duplicateInsertsCopyAfterBlock() throws {
        var doc = ConfigDocument(parsing: "Host a # c\n  User u\n\nHost b\n")
        let header = try doc.duplicateHost(at: 0, newAlias: "a-copy")
        #expect(doc.render() == "Host a # c\n  User u\n\nHost a-copy # c\n  User u\n\nHost b\n")
        #expect(doc.hostEntry(at: header)?.alias == "a-copy")
    }

    @Test func removingUnknownHeaderThrows() {
        var doc = ConfigDocument(parsing: "Match all\n")
        #expect(throws: ConfigEditError.hostNotFound(0)) { try doc.removeHost(at: 0) }
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter AddRemoveHostTests`
Expected: FAIL — `value of type 'ConfigDocument' has no member 'addHost'`.

- [ ] **Step 3: Uygulamayı yaz** (`ConfigDocument+Edit.swift` sonuna)

```swift
extension ConfigDocument {
    /// `Host *` or `Match all`: ssh uses the first value it finds, so new hosts must come before these.
    private func isCatchAll(_ index: Int) -> Bool {
        switch lines[index].kind {
        case .hostStart(let patterns): patterns == ["*"]
        case .matchStart(let criteria): criteria.asciiLowercased == "all"
        default: false
        }
    }

    @discardableResult
    public mutating func addHost(_ draft: HostDraft) -> Int {
        let indent = directiveIndent
        let blank = ConfigLine(raw: lineEndingSuffix)
        var hostLines = [ConfigLine(raw: "Host " + draft.patterns.joined(separator: " ") + lineEndingSuffix)]
        hostLines += draft.directives.map { makeDirectiveLine(indent: indent, key: $0.key, value: $0.value) }

        if let catchAll = headerIndices.first(where: isCatchAll) {
            var position = catchAll
            while position > 0 && lines[position - 1].kind == .comment { position -= 1 }
            let lead = (position > 0 && lines[position - 1].kind != .blank) ? [blank] : []
            lines.insert(contentsOf: lead + hostLines + [blank], at: position)
            return position + lead.count
        }

        if let last = lines.last, last.kind != .blank { lines.append(blank) }
        let header = lines.count
        lines += hostLines
        hasTrailingNewline = true
        return header
    }

    public mutating func removeHost(at header: Int) throws {
        guard hostEntry(at: header) != nil else { throw ConfigEditError.hostNotFound(header) }
        var start = header
        while start > 0 && lines[start - 1].kind == .comment { start -= 1 }
        lines.removeSubrange(start..<ownedEnd(of: header))

        while start < lines.count, lines[start].kind == .blank, start == 0 || lines[start - 1].kind == .blank {
            lines.remove(at: start)
        }
        if start == lines.count {
            while lines.last?.kind == .blank { lines.removeLast() }
        }
        if lines.isEmpty { hasTrailingNewline = false }
    }

    @discardableResult
    public mutating func duplicateHost(at header: Int, newAlias: String) throws -> Int {
        guard hostEntry(at: header) != nil, let parts = lines[header].parts else {
            throw ConfigEditError.hostNotFound(header)
        }
        var end = ownedEnd(of: header)
        while end - 1 > header && lines[end - 1].kind == .blank { end -= 1 }

        var copy = Array(lines[header..<end])
        copy[0] = ConfigLine(raw: LineTokenizer.replacingValue(in: parts, with: newAlias))
        lines.insert(contentsOf: [ConfigLine(raw: lineEndingSuffix)] + copy, at: end)
        return end + 1
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter AddRemoveHostTests`
Expected: PASS.

- [ ] **Step 5: Tüm paket testlerini çalıştır**

Run: `swift test --package-path Packages/SSHConfigKit`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): host ekleme (Host * öncesine), silme ve çoğaltma"
```

---

### Task 6: Taslak doğrulama (`HostDraftValidator`)

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/HostDraftValidator.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/HostDraftValidatorTests.swift`

**Interfaces:**
- Consumes: `HostDraft`, `ConfigDocument.hosts`, `HostEntry.isPattern`
- Produces:
  - `public enum DraftIssue: Equatable, Sendable { case emptyAlias, aliasHasWhitespace, duplicateAlias(String), invalidPort(String), invalidDirectiveKey(String), forbiddenDirectiveKey(String), emptyDirectiveValue(String), identityFileMissing(String); public var isBlocking: Bool }`
  - `public struct HostDraftValidator: Sendable { public init(fileExists: @escaping @Sendable (String) -> Bool); public func issues(for draft: HostDraft, in document: ConfigDocument, editing header: Int?) -> [DraftIssue] }`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/HostDraftValidatorTests.swift`:

```swift
import Testing
@testable import SSHConfigKit

struct HostDraftValidatorTests {
    let doc = ConfigDocument(parsing: "Host web web2\n  User u\nHost *.prod\nHost db\n")
    let validator = HostDraftValidator(fileExists: { $0 == "~/.ssh/id_ok" })

    private func issues(_ draft: HostDraft, editing: Int? = nil) -> [DraftIssue] {
        validator.issues(for: draft, in: doc, editing: editing)
    }

    @Test func validDraftHasNoIssues() {
        let draft = HostDraft(patterns: ["new"], directives: [
            DraftDirective(key: "Port", value: "2222"),
            DraftDirective(key: "IdentityFile", value: "~/.ssh/id_ok"),
        ])
        #expect(issues(draft).isEmpty)
    }

    @Test func aliasRules() {
        #expect(issues(HostDraft(patterns: [])) == [.emptyAlias])
        #expect(issues(HostDraft(patterns: [""])) == [.emptyAlias])
        #expect(issues(HostDraft(patterns: ["a b"])) == [.aliasHasWhitespace])
        #expect(issues(HostDraft(patterns: ["WEB2"])) == [.duplicateAlias("WEB2")])
    }

    @Test func editingItselfIsNotADuplicate() {
        #expect(issues(HostDraft(patterns: ["web", "web2"]), editing: 0).isEmpty)
        #expect(issues(HostDraft(patterns: ["db"]), editing: 0) == [.duplicateAlias("db")])
    }

    @Test func wildcardPatternsNeverCountAsDuplicates() {
        #expect(issues(HostDraft(patterns: ["*.prod"])).isEmpty)
    }

    @Test(arguments: ["0", "65536", "abc", "22 23", ""])
    func invalidPorts(port: String) {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "port", value: port)]))
        #expect(found.contains(.invalidPort(port)))
    }

    @Test func directiveKeyRules() {
        let draft = HostDraft(patterns: ["n"], directives: [
            DraftDirective(key: "Bad Key", value: "x"),
            DraftDirective(key: "Host", value: "x"),
            DraftDirective(key: "INCLUDE", value: "x"),
            DraftDirective(key: "User", value: "  "),
        ])
        #expect(issues(draft) == [
            .invalidDirectiveKey("Bad Key"),
            .forbiddenDirectiveKey("Host"),
            .forbiddenDirectiveKey("INCLUDE"),
            .emptyDirectiveValue("User"),
        ])
    }

    @Test func missingIdentityFileIsANonBlockingWarning() {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "IdentityFile", value: "~/.ssh/nope")]))
        #expect(found == [.identityFileMissing("~/.ssh/nope")])
        #expect(found.allSatisfy { !$0.isBlocking })
    }

    @Test func identityFileWithTokensIsNotChecked() {
        let found = issues(HostDraft(patterns: ["n"], directives: [DraftDirective(key: "IdentityFile", value: "~/.ssh/%h")]))
        #expect(found.isEmpty)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter HostDraftValidatorTests`
Expected: FAIL — `cannot find 'HostDraftValidator' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/Config/HostDraftValidator.swift`:

```swift
public enum DraftIssue: Equatable, Sendable {
    case emptyAlias
    case aliasHasWhitespace
    case duplicateAlias(String)
    case invalidPort(String)
    case invalidDirectiveKey(String)
    case forbiddenDirectiveKey(String)
    case emptyDirectiveValue(String)
    case identityFileMissing(String)

    /// Blocking issues prevent applying the draft; warnings do not.
    public var isBlocking: Bool {
        if case .identityFileMissing = self { return false }
        return true
    }
}

public struct HostDraftValidator: Sendable {
    private let fileExists: @Sendable (String) -> Bool

    /// - Parameter fileExists: receives the IdentityFile value as typed (may start with "~").
    public init(fileExists: @escaping @Sendable (String) -> Bool) {
        self.fileExists = fileExists
    }

    public func issues(for draft: HostDraft, in document: ConfigDocument, editing header: Int?) -> [DraftIssue] {
        var issues: [DraftIssue] = []

        if draft.patterns.isEmpty || draft.patterns.contains(where: \.isEmpty) {
            issues.append(.emptyAlias)
        } else if draft.patterns.contains(where: { $0.unicodeScalars.contains(where: LineTokenizer.isSpace) }) {
            issues.append(.aliasHasWhitespace)
        } else {
            // ssh lowercases host names before matching, so duplicates are case-insensitive.
            let taken = Set(document.hosts
                .filter { $0.headerLine != header && !$0.isPattern }
                .flatMap(\.patterns)
                .map(\.asciiLowercased))
            for pattern in draft.patterns where !HostEntry(headerLine: 0, patterns: [pattern], directives: []).isPattern {
                if taken.contains(pattern.asciiLowercased) { issues.append(.duplicateAlias(pattern)) }
            }
        }

        for directive in draft.directives {
            let key = directive.key.asciiLowercased
            let isValidKey = !directive.key.isEmpty && directive.key.unicodeScalars.allSatisfy {
                (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value)
            }
            if !isValidKey {
                issues.append(.invalidDirectiveKey(directive.key))
                continue
            }
            if ["host", "match", "include"].contains(key) {
                issues.append(.forbiddenDirectiveKey(directive.key))
                continue
            }
            if key == "port" {
                let isValidPort = Int(directive.value).map { (1...65535).contains($0) } ?? false
                if !isValidPort { issues.append(.invalidPort(directive.value)) }
                continue
            }
            if directive.value.unicodeScalars.allSatisfy(LineTokenizer.isSpace) {
                issues.append(.emptyDirectiveValue(directive.key))
                continue
            }
            if key == "identityfile", !directive.value.contains("%"), !fileExists(directive.value) {
                issues.append(.identityFileMissing(directive.value))
            }
        }
        return issues
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter HostDraftValidatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): host taslağı doğrulaması"
```

---

### Task 7: Satır diff'i ve unified hunk'lar

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/LineDiff.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/LineDiffTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `public struct DiffLine: Equatable, Sendable { public enum Kind { case context, added, removed }; public let kind: Kind; public let text: String; public let oldNumber: Int?; public let newNumber: Int? }`
  - `public struct DiffHunk: Equatable, Sendable { public let oldStart, oldCount, newStart, newCount: Int; public let lines: [DiffLine]; public var header: String }`
  - `public enum LineDiff { public static func lines(old: String, new: String) -> [DiffLine]; public static func hunks(old: String, new: String, context: Int = 3) -> [DiffHunk] }`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/LineDiffTests.swift`:

```swift
import Testing
@testable import SSHConfigKit

struct LineDiffTests {
    let old = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"

    @Test func identicalTextsHaveNoHunks() {
        #expect(LineDiff.hunks(old: old, new: old).isEmpty)
    }

    @Test func singleChangeWithThreeLinesOfContext() throws {
        let new = old.replacingOccurrences(of: "line 5\n", with: "line five\n")
        let hunks = LineDiff.hunks(old: old, new: new)
        let hunk = try #require(hunks.first)
        #expect(hunks.count == 1)
        #expect(hunk.header == "@@ -2,7 +2,7 @@")
        #expect(hunk.lines.map(\.kind) == [.context, .context, .context, .removed, .added, .context, .context, .context])
        #expect(hunk.lines[3].text == "line 5")
        #expect(hunk.lines[4].text == "line five")
        #expect(hunk.lines[3].oldNumber == 5)
        #expect(hunk.lines[4].newNumber == 5)
    }

    @Test func insertionAtTop() throws {
        let hunk = try #require(LineDiff.hunks(old: "a\nb\n", new: "x\na\nb\n").first)
        #expect(hunk.header == "@@ -0,0 +1,3 @@" || hunk.header == "@@ -1,2 +1,3 @@")
        #expect(hunk.lines.filter { $0.kind == .added }.map(\.text) == ["x"])
    }

    @Test func distantChangesProduceTwoHunks() {
        let new = old
            .replacingOccurrences(of: "line 1\n", with: "LINE 1\n")
            .replacingOccurrences(of: "line 10\n", with: "LINE 10\n")
        #expect(LineDiff.hunks(old: old, new: new).count == 2)
    }

    @Test func nearbyChangesMergeIntoOneHunk() {
        let new = old
            .replacingOccurrences(of: "line 4\n", with: "x\n")
            .replacingOccurrences(of: "line 7\n", with: "y\n")
        #expect(LineDiff.hunks(old: old, new: new).count == 1)
    }

    @Test func lineEndingChangeIsVisible() {
        let diff = LineDiff.lines(old: "a\nb\n", new: "a\r\nb\n")
        #expect(diff.map(\.kind) == [.removed, .added, .context])
    }

    @Test func deletionOnly() {
        let diff = LineDiff.lines(old: "a\nb\nc\n", new: "a\nc\n")
        #expect(diff.map(\.kind) == [.context, .removed, .context])
        #expect(diff[1].oldNumber == 2)
        #expect(diff[1].newNumber == nil)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter LineDiffTests`
Expected: FAIL — `cannot find 'LineDiff' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/Config/LineDiff.swift`:

```swift
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, added, removed }
    public let kind: Kind
    public let text: String
    /// 1-based line numbers; nil when the line does not exist on that side.
    public let oldNumber: Int?
    public let newNumber: Int?
}

public struct DiffHunk: Equatable, Sendable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public var header: String { "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@" }
}

/// LCS-based line diff. Common prefix/suffix are trimmed first, so the quadratic
/// table only covers the edited region (edits in this app are local).
public enum LineDiff {
    public static func lines(old: String, new: String) -> [DiffLine] {
        let a = split(old)
        let b = split(new)

        var prefix = 0
        while prefix < a.count && prefix < b.count && same(a[prefix], b[prefix]) { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix && suffix < b.count - prefix
            && same(a[a.count - 1 - suffix], b[b.count - 1 - suffix]) { suffix += 1 }

        let am = Array(a[prefix..<(a.count - suffix)])
        let bm = Array(b[prefix..<(b.count - suffix)])
        let n = am.count
        let m = bm.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = same(am[i], bm[j]) ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        var result: [DiffLine] = []
        var oldNo = 1
        var newNo = 1
        func context(_ text: String) {
            result.append(DiffLine(kind: .context, text: text, oldNumber: oldNo, newNumber: newNo))
            oldNo += 1
            newNo += 1
        }

        for k in 0..<prefix { context(a[k]) }
        var i = 0
        var j = 0
        while i < n || j < m {
            if i < n && j < m && same(am[i], bm[j]) {
                context(am[i]); i += 1; j += 1
            } else if i < n && (j == m || dp[i + 1][j] >= dp[i][j + 1]) {
                result.append(DiffLine(kind: .removed, text: am[i], oldNumber: oldNo, newNumber: nil))
                oldNo += 1; i += 1
            } else {
                result.append(DiffLine(kind: .added, text: bm[j], oldNumber: nil, newNumber: newNo))
                newNo += 1; j += 1
            }
        }
        for k in (a.count - suffix)..<a.count { context(a[k]) }
        return result
    }

    public static func hunks(old: String, new: String, context: Int = 3) -> [DiffHunk] {
        let all = lines(old: old, new: new)
        let changed = all.indices.filter { all[$0].kind != .context }
        guard !changed.isEmpty else { return [] }

        var ranges: [ClosedRange<Int>] = []
        for index in changed {
            let lo = max(0, index - context)
            let hi = min(all.count - 1, index + context)
            if let last = ranges.last, lo <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, hi)
            } else {
                ranges.append(lo...hi)
            }
        }

        return ranges.map { range in
            let slice = Array(all[range])
            let before = all[..<range.lowerBound]
            let oldCount = slice.filter { $0.kind != .added }.count
            let newCount = slice.filter { $0.kind != .removed }.count
            let oldBefore = before.filter { $0.kind != .added }.count
            let newBefore = before.filter { $0.kind != .removed }.count
            return DiffHunk(
                oldStart: oldCount == 0 ? oldBefore : oldBefore + 1,
                oldCount: oldCount,
                newStart: newCount == 0 ? newBefore : newBefore + 1,
                newCount: newCount,
                lines: slice)
        }
    }

    private static func split(_ text: String) -> [String] {
        var parts = text.utf8
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    private static func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter LineDiffTests`
Expected: PASS. (`insertionAtTop` iki geçerli başlık biçimini kabul eder; uygulama `@@ -1,2 +1,3 @@` üretir.)

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): satır diff'i ve unified hunk'lar"
```

---

### Task 8: `FileFingerprint` ve `BackupManager`

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/IO/FileFingerprint.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/IO/BackupManager.swift`
- Modify: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/Support/TestSupport.swift` (sona `TestClock` ekle)
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/BackupManagerTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `public struct FileFingerprint: Equatable, Sendable { public let sha256: Data; public init(data: Data); public static func of(fileAt url: URL) throws -> FileFingerprint? }`
  - `public struct Backup: Equatable, Sendable { public let url: URL; public let date: Date; public let originalName: String }`
  - `public struct BackupManager: Sendable { public let rootDirectory: URL; public var keep: Int; public init(rootDirectory: URL, keep: Int = 10, now: @escaping @Sendable () -> Date = { Date() }); @discardableResult public func backup(fileAt url: URL, kind: String) throws -> URL; public func list(kind: String) throws -> [Backup]; public func prune(kind: String) throws; public func contents(of backup: Backup) throws -> String }`
  - `public static let defaultRoot: URL` (`~/Library/Application Support/SSHConfigManager/Backups`)

- [ ] **Step 1: Test saatini ekle** (`TestSupport.swift` sonuna)

```swift
import Synchronization

final class TestClock: Sendable {
    private let current: Mutex<Date>
    init(_ start: Date) { current = Mutex(start) }
    var now: Date { current.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 += seconds } }
}
```

- [ ] **Step 2: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/BackupManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct BackupManagerTests {
    let start = Date(timeIntervalSince1970: 1_791_000_000)

    private func permissions(_ url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
    }

    @Test func backupCopiesContentWithPrivatePermissions() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "Host a\n", permissions: 0o644)
        let clock = TestClock(start)
        let manager = BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), now: { clock.now })

        let backup = try manager.backup(fileAt: source, kind: "config")

        #expect(try String(contentsOf: backup, encoding: .utf8) == "Host a\n")
        #expect(try permissions(backup) == 0o600)
        #expect(try permissions(backup.deletingLastPathComponent()) == 0o700)
        #expect(backup.lastPathComponent.hasSuffix("-config"))
        #expect(backup.lastPathComponent.count == "yyyyMMdd-HHmmss-config".count)
    }

    @Test func listIsNewestFirstAndParsesDates() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "1")
        let clock = TestClock(start)
        let manager = BackupManager(rootDirectory: tmp.url, now: { clock.now })
        try manager.backup(fileAt: source, kind: "config")
        clock.advance(60)
        try Data("2".utf8).write(to: source)
        try manager.backup(fileAt: source, kind: "config")

        let list = try manager.list(kind: "config")
        #expect(list.count == 2)
        #expect(try manager.contents(of: list[0]) == "2")
        #expect(list[0].date == start.addingTimeInterval(60))
        #expect(list[1].originalName == "config")
    }

    @Test func sameSecondBackupsDoNotCollide() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "x")
        let fixed = start
        let manager = BackupManager(rootDirectory: tmp.url, now: { fixed })
        let first = try manager.backup(fileAt: source, kind: "config")
        let second = try manager.backup(fileAt: source, kind: "config")
        #expect(first != second)
        #expect(try manager.list(kind: "config").first?.url == second)
    }

    @Test func pruneKeepsNewestN() throws {
        let tmp = try TempDir()
        let source = try tmp.file("config", "x")
        let clock = TestClock(start)
        let manager = BackupManager(rootDirectory: tmp.url, keep: 3, now: { clock.now })
        for _ in 0..<5 {
            try manager.backup(fileAt: source, kind: "config")
            clock.advance(1)
        }
        let list = try manager.list(kind: "config")
        #expect(list.count == 3)
        #expect(list.first?.date == start.addingTimeInterval(4))
    }

    @Test func symlinkSourceBacksUpTargetContent() throws {
        let tmp = try TempDir()
        let target = try tmp.file("dotfiles/config", "real")
        let link = tmp.url.appending(path: "config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let backup = try BackupManager(rootDirectory: tmp.url.appending(path: "B")).backup(fileAt: link, kind: "config")
        let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
        #expect(attributes[.type] as? FileAttributeType == .typeRegular)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "real")
    }

    @Test func unrelatedFilesAreIgnored() throws {
        let tmp = try TempDir()
        try tmp.file("config/.DS_Store", "")
        try tmp.file("config/notes.txt", "")
        #expect(try BackupManager(rootDirectory: tmp.url).list(kind: "config").isEmpty)
    }

    @Test func fingerprint() throws {
        let tmp = try TempDir()
        let file = try tmp.file("f", "abc")
        #expect(try FileFingerprint.of(fileAt: file) == FileFingerprint(data: Data("abc".utf8)))
        #expect(try FileFingerprint.of(fileAt: tmp.url.appending(path: "missing")) == nil)
    }
}
```

- [ ] **Step 3: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter BackupManagerTests`
Expected: FAIL — `cannot find 'BackupManager' in scope`.

- [ ] **Step 4: Uygulamayı yaz**

`Sources/SSHConfigKit/IO/FileFingerprint.swift`:

```swift
import CryptoKit
import Foundation

public struct FileFingerprint: Equatable, Sendable {
    public let sha256: Data

    public init(data: Data) {
        sha256 = Data(SHA256.hash(data: data))
    }

    /// Returns nil when the file does not exist. Follows symlinks.
    public static func of(fileAt url: URL) throws -> FileFingerprint? {
        do {
            return FileFingerprint(data: try Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
```

`Sources/SSHConfigKit/IO/BackupManager.swift`:

```swift
import Foundation

public struct Backup: Equatable, Sendable {
    public let url: URL
    public let date: Date
    public let originalName: String
}

/// Keeps timestamped copies under `<root>/<kind>/yyyyMMdd-HHmmss[_n]-<name>`.
public struct BackupManager: Sendable {
    public static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/SSHConfigManager/Backups", directoryHint: .isDirectory)

    public let rootDirectory: URL
    public var keep: Int
    private let now: @Sendable () -> Date

    public init(rootDirectory: URL, keep: Int = 10, now: @escaping @Sendable () -> Date = { Date() }) {
        self.rootDirectory = rootDirectory
        self.keep = keep
        self.now = now
    }

    @discardableResult
    public func backup(fileAt url: URL, kind: String) throws -> URL {
        let fm = FileManager.default
        let directory = rootDirectory.appending(path: kind, directoryHint: .isDirectory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let stamp = Self.makeFormatter().string(from: now())
        let name = url.lastPathComponent
        var target = directory.appending(path: "\(stamp)-\(name)")
        var counter = 2
        while fm.fileExists(atPath: target.path) {
            target = directory.appending(path: "\(stamp)_\(counter)-\(name)")
            counter += 1
        }

        // Copy bytes (not the item): copyItem would copy a symlink as a symlink.
        let data = try Data(contentsOf: url)
        guard fm.createFile(atPath: target.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
        }
        try prune(kind: kind)
        return target
    }

    public func list(kind: String) throws -> [Backup] {
        let directory = rootDirectory.appending(path: kind, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .compactMap(Self.parse)
            .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    public func prune(kind: String) throws {
        for old in try list(kind: kind).dropFirst(max(keep, 1)) {
            try FileManager.default.removeItem(at: old.url)
        }
    }

    public func contents(of backup: Backup) throws -> String {
        let data = try Data(contentsOf: backup.url)
        guard let text = String(validating: data, as: UTF8.self) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    static func parse(_ url: URL) -> Backup? {
        let name = url.lastPathComponent
        guard name.count > 16, let date = makeFormatter().date(from: String(name.prefix(15))) else { return nil }
        var rest = name.dropFirst(15)
        if rest.hasPrefix("_") { rest = rest.drop(while: { $0 != "-" }) }
        guard rest.hasPrefix("-"), rest.count > 1 else { return nil }
        return Backup(url: url, date: date, originalName: String(rest.dropFirst()))
    }

    static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }
}
```

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter BackupManagerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): dosya parmak izi ve zaman damgalı yedekleme"
```

---

### Task 9: `SafeFileWriter` — çakışma kontrolü, yedek, atomik yazma

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/IO/SafeFileWriter.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/SafeFileWriterTests.swift`

**Interfaces:**
- Consumes: `FileFingerprint`, `BackupManager` (Task 8)
- Produces:
  - `public enum SafeFileWriterError: Error, Equatable, Sendable { case conflict, backupFailed(String), writeFailed(String) }`
  - `public struct SafeFileWriter: Sendable { public let backups: BackupManager?; public init(backups: BackupManager?); public func write(_ text: String, to url: URL, expected: FileFingerprint?, ignoreConflict: Bool = false, backupKind: String) throws }` (yalnızca `SafeFileWriterError` fırlatır)

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/SafeFileWriterTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct SafeFileWriterTests {
    private func permissions(_ url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
    }

    private func writer(_ tmp: TempDir) -> SafeFileWriter {
        SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups")))
    }

    @Test func createsNewFileWith0600() throws {
        let tmp = try TempDir()
        let url = tmp.url.appending(path: "config")
        try writer(tmp).write("Host a\n", to: url, expected: nil, backupKind: "config")
        #expect(try tmp.read("config") == "Host a\n")
        #expect(try permissions(url) == 0o600)
    }

    @Test func preservesExistingPermissionsAndBacksUpOldContent() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "old", permissions: 0o644)
        let w = writer(tmp)
        try w.write("new", to: url, expected: try FileFingerprint.of(fileAt: url), backupKind: "config")
        #expect(try tmp.read("config") == "new")
        #expect(try permissions(url) == 0o644)
        let backups = try #require(w.backups).list(kind: "config")
        #expect(backups.count == 1)
        #expect(try w.backups!.contents(of: backups[0]) == "old")
    }

    @Test func writesThroughSymlinkAndKeepsTheLink() throws {
        let tmp = try TempDir()
        let target = try tmp.file("dotfiles/ssh/config", "old")
        let link = tmp.url.appending(path: "config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try writer(tmp).write("new", to: link, expected: try FileFingerprint.of(fileAt: link), backupKind: "config")

        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try tmp.read("dotfiles/ssh/config") == "new")
    }

    @Test func externalChangeIsAConflict() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "v1")
        let loaded = try FileFingerprint.of(fileAt: url)
        try Data("v2 from vim".utf8).write(to: url)

        #expect(throws: SafeFileWriterError.conflict) {
            try writer(tmp).write("mine", to: url, expected: loaded, backupKind: "config")
        }
        #expect(try tmp.read("config") == "v2 from vim")
    }

    @Test func fileCreatedExternallyIsAConflict() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "appeared")
        #expect(throws: SafeFileWriterError.conflict) {
            try writer(tmp).write("mine", to: url, expected: nil, backupKind: "config")
        }
    }

    @Test func ignoreConflictOverwrites() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "theirs")
        try writer(tmp).write("mine", to: url, expected: nil, ignoreConflict: true, backupKind: "config")
        #expect(try tmp.read("config") == "mine")
    }

    @Test func backupFailureLeavesFileUntouched() throws {
        let tmp = try TempDir()
        let url = try tmp.file("config", "old")
        let blocker = try tmp.file("NotADirectory", "x")
        let w = SafeFileWriter(backups: BackupManager(rootDirectory: blocker))
        let expected = try FileFingerprint.of(fileAt: url)
        let error = #expect(throws: SafeFileWriterError.self) {
            try w.write("new", to: url, expected: expected, backupKind: "config")
        }
        guard case .backupFailed? = error else {
            Issue.record("backupFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try tmp.read("config") == "old")
    }

    @Test func writeFailureLeavesFileUntouchedAndNoTempFiles() throws {
        let tmp = try TempDir()
        let url = try tmp.file("ro/config", "old")
        let directory = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        let expected = try FileFingerprint.of(fileAt: url)
        let error = #expect(throws: SafeFileWriterError.self) {
            try SafeFileWriter(backups: nil).write("new", to: url, expected: expected, backupKind: "config")
        }
        guard case .writeFailed? = error else {
            Issue.record("writeFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try tmp.read("ro/config") == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["config"])
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter SafeFileWriterTests`
Expected: FAIL — `cannot find 'SafeFileWriter' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/IO/SafeFileWriter.swift`:

```swift
import Foundation

public enum SafeFileWriterError: Error, Equatable, Sendable {
    /// The file on disk no longer matches what was loaded.
    case conflict
    case backupFailed(String)
    case writeFailed(String)
}

/// Conflict check → backup → temp file in the same directory → fsync → rename(2).
/// Symlinks are resolved so the real file is replaced and the link is kept.
public struct SafeFileWriter: Sendable {
    public let backups: BackupManager?

    public init(backups: BackupManager?) {
        self.backups = backups
    }

    public func write(
        _ text: String,
        to url: URL,
        expected: FileFingerprint?,
        ignoreConflict: Bool = false,
        backupKind: String
    ) throws {
        let fm = FileManager.default
        let target = url.resolvingSymlinksInPath()

        if !ignoreConflict {
            let current: FileFingerprint?
            do { current = try FileFingerprint.of(fileAt: target) }
            catch { throw SafeFileWriterError.writeFailed(error.localizedDescription) }
            guard current == expected else { throw SafeFileWriterError.conflict }
        }

        let exists = fm.fileExists(atPath: target.path)
        if exists, let backups {
            do { try backups.backup(fileAt: target, kind: backupKind) }
            catch { throw SafeFileWriterError.backupFailed(error.localizedDescription) }
        }

        let permissions = exists
            ? ((try? fm.attributesOfItem(atPath: target.path)[.posixPermissions]) as? Int ?? 0o600)
            : 0o600
        let temp = target.deletingLastPathComponent()
            .appending(path: ".\(target.lastPathComponent).tmp-\(UUID().uuidString)")

        do {
            guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: permissions]) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temp.path])
            }
            let handle = try FileHandle(forWritingTo: temp)
            do {
                try handle.write(contentsOf: Data(text.utf8))
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            // createFile's mode is filtered by umask; set it explicitly.
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
            guard rename(temp.path, target.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw SafeFileWriterError.writeFailed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter SafeFileWriterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): çakışma kontrollü, yedekli, atomik SafeFileWriter"
```

---

### Task 10: `ProcessRunner`

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Process/ProcessRunner.swift`
- Modify: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/Support/TestSupport.swift` (sona `FakeRunner` ekle)
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ProcessRunnerTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `public struct ProcessResult: Equatable, Sendable { public let exitCode: Int32; public let stdout: String; public let stderr: String; public let timedOut: Bool; public init(...) }`
  - `public protocol ProcessRunning: Sendable { func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult }`
  - `public struct ProcessRunner: ProcessRunning { public init() }`
  - Test: `final class FakeRunner: ProcessRunning` (`calls`, `maxConcurrent`)

- [ ] **Step 1: `FakeRunner`'ı ekle** (`TestSupport.swift` sonuna; dosyanın başında `@testable import SSHConfigKit` satırını da ekle)

```swift
@testable import SSHConfigKit

final class FakeRunner: ProcessRunning {
    struct State {
        var calls: [[String]] = []
        var running = 0
        var maxRunning = 0
    }

    private let state = Mutex(State())
    private let respond: @Sendable ([String]) -> ProcessResult
    private let delay: Duration

    init(delay: Duration = .zero, respond: @escaping @Sendable ([String]) -> ProcessResult) {
        self.delay = delay
        self.respond = respond
    }

    var calls: [[String]] { state.withLock { $0.calls } }
    var maxConcurrent: Int { state.withLock { $0.maxRunning } }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        state.withLock {
            $0.calls.append(arguments)
            $0.running += 1
            $0.maxRunning = max($0.maxRunning, $0.running)
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        state.withLock { $0.running -= 1 }
        return respond(arguments)
    }
}
```

- [ ] **Step 2: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/ProcessRunnerTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct ProcessRunnerTests {
    let runner = ProcessRunner()

    @Test func capturesStdoutAndExitCode() async throws {
        let result = try await runner.run(URL(filePath: "/bin/echo"), arguments: ["hi"], environment: [:], timeout: .seconds(5))
        #expect(result == ProcessResult(exitCode: 0, stdout: "hi\n", stderr: "", timedOut: false))
    }

    @Test func capturesStderrAndNonZeroExit() async throws {
        let result = try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "echo err >&2; exit 3"], environment: [:], timeout: .seconds(5))
        #expect(result.exitCode == 3)
        #expect(result.stderr == "err\n")
    }

    @Test func timeoutTerminatesTheProcess() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await runner.run(URL(filePath: "/bin/sleep"), arguments: ["10"], environment: [:], timeout: .milliseconds(200))
        #expect(result.timedOut)
        #expect(clock.now - started < .seconds(3))
    }

    @Test func forcesCLocaleAndMergesEnvironment() async throws {
        let result = try await runner.run(URL(filePath: "/usr/bin/env"), arguments: [], environment: ["SSHCM_TEST": "1", "LC_ALL": "tr_TR.UTF-8"], timeout: .seconds(5))
        #expect(result.stdout.contains("LC_ALL=C\n"))
        #expect(result.stdout.contains("SSHCM_TEST=1\n"))
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let result = try await runner.run(URL(filePath: "/bin/sh"), arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' a"], environment: [:], timeout: .seconds(10))
        #expect(result.stdout.utf8.count == 300_000)
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            try await runner.run(URL(filePath: "/nonexistent/tool"), arguments: [], environment: [:], timeout: .seconds(1))
        }
    }

    @Test func stdinIsEmpty() async throws {
        let result = try await runner.run(URL(filePath: "/bin/cat"), arguments: [], environment: [:], timeout: .seconds(5))
        #expect(result.stdout.isEmpty)
        #expect(!result.timedOut)
    }
}
```

- [ ] **Step 3: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ProcessRunnerTests`
Expected: FAIL — `cannot find 'ProcessRunner' in scope`.

- [ ] **Step 4: Uygulamayı yaz**

`Sources/SSHConfigKit/Process/ProcessRunner.swift`:

```swift
import Foundation
import Synchronization

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult
}

/// Runs a process with stdin from /dev/null, `LC_ALL=C`, and a hard timeout
/// (SIGTERM, then SIGKILL after one second). Never logs arguments or environment:
/// they may contain passphrases.
public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env.merge(environment) { _, new in new }
        env["LC_ALL"] = "C"
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let box = Unchecked(process)
        let stdout = Buffer()
        let stderr = Buffer()
        let timedOut = Flag()
        let group = DispatchGroup()

        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            group.leave()
            throw error
        }

        // Drain both pipes concurrently so a full pipe buffer never blocks the child.
        for (pipe, buffer) in [(out, stdout), (err, stderr)] {
            group.enter()
            let reader = Unchecked(pipe.fileHandleForReading)
            DispatchQueue.global().async {
                buffer.set(reader.value.readDataToEndOfFile())
                group.leave()
            }
        }

        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            guard box.value.isRunning else { return }
            timedOut.set()
            box.value.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if box.value.isRunning { kill(box.value.processIdentifier, SIGKILL) }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { continuation.resume() }
        }

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout.string,
            stderr: stderr.string,
            timedOut: timedOut.isSet)
    }
}

/// `Mutex` is non-copyable and cannot be captured by escaping closures; wrap it in a class.
private final class Flag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
}

private final class Buffer: Sendable {
    private let data = Mutex(Data())
    func set(_ new: Data) { data.withLock { $0 = new } }
    var string: String { data.withLock { String(decoding: $0, as: UTF8.self) } }
}

/// Foundation's Process/FileHandle are thread-safe for the calls used here but not marked Sendable.
private final class Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
```

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ProcessRunnerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): zaman aşımlı, LC_ALL=C ProcessRunner"
```

---

### Task 11: `ConfigValidator` (`ssh -G`)

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/SSH/ConfigValidator.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConfigValidatorTests.swift`

**Interfaces:**
- Consumes: `ProcessRunning`, `ProcessRunner`, `ProcessResult` (Task 10)
- Produces:
  - `public enum ValidationOutcome: Equatable, Sendable { case valid, invalid(message: String), timedOut }`
  - `public struct ConfigValidator: Sendable { public init(runner: any ProcessRunning = ProcessRunner(), sshPath: URL = URL(filePath: "/usr/bin/ssh")); public func validate(_ text: String, probeAlias: String) async throws -> ValidationOutcome }`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/ConfigValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct ConfigValidatorTests {
    let validator = ConfigValidator()

    @Test func validConfigPasses() async throws {
        let outcome = try await validator.validate("Host a\n  HostName 10.0.0.1\n  Port 2222\n", probeAlias: "a")
        #expect(outcome == .valid)
    }

    @Test func emptyConfigPasses() async throws {
        #expect(try await validator.validate("", probeAlias: "localhost") == .valid)
    }

    @Test func unknownOptionFailsWithSshMessage() async throws {
        let outcome = try await validator.validate("Host a\n  Bogus yes\n", probeAlias: "a")
        guard case .invalid(let message) = outcome else {
            Issue.record("invalid bekleniyordu: \(outcome)")
            return
        }
        #expect(message.contains("Bad configuration option: bogus"))
    }

    @Test func badPortFails() async throws {
        let outcome = try await validator.validate("Host a\n  Port abc\n", probeAlias: "a")
        guard case .invalid(let message) = outcome else {
            Issue.record("invalid bekleniyordu: \(outcome)")
            return
        }
        #expect(message.contains("Bad port"))
    }

    @Test func passesConfigFileAndAliasAfterDoubleDash() async throws {
        let fake = FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        _ = try await ConfigValidator(runner: fake).validate("", probeAlias: "-oProxyCommand=x")
        let args = try #require(fake.calls.first)
        #expect(args.first == "-G")
        #expect(args[1] == "-F")
        #expect(Array(args.suffix(2)) == ["--", "-oProxyCommand=x"])
    }

    @Test func timeoutIsReported() async throws {
        let fake = FakeRunner { _ in ProcessResult(exitCode: 15, stdout: "", stderr: "", timedOut: true) }
        #expect(try await ConfigValidator(runner: fake).validate("", probeAlias: "a") == .timedOut)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ConfigValidatorTests`
Expected: FAIL — `cannot find 'ConfigValidator' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/SSH/ConfigValidator.swift`:

```swift
import Foundation

public enum ValidationOutcome: Equatable, Sendable {
    case valid
    /// `message` is ssh's own stderr (English, untranslated by design).
    case invalid(message: String)
    case timedOut
}

/// Validates config text by writing it to a private temp file and running `ssh -G -F <file> -- <alias>`.
/// With `-F`, ssh ignores the system-wide config, so only this text is checked.
/// Relative `Include` paths still resolve against `~/.ssh`, exactly as they will at runtime.
public struct ConfigValidator: Sendable {
    private let runner: any ProcessRunning
    private let sshPath: URL

    public init(runner: any ProcessRunning = ProcessRunner(), sshPath: URL = URL(filePath: "/usr/bin/ssh")) {
        self.runner = runner
        self.sshPath = sshPath
    }

    public func validate(_ text: String, probeAlias: String) async throws -> ValidationOutcome {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appending(path: "sshcm-validate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }

        let file = directory.appending(path: "config")
        guard fm.createFile(atPath: file.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }

        let result = try await runner.run(
            sshPath, arguments: ["-G", "-F", file.path, "--", probeAlias], environment: [:], timeout: .seconds(5))
        if result.timedOut { return .timedOut }
        if result.exitCode == 0 { return .valid }
        return .invalid(message: result.stderr
            .replacingOccurrences(of: file.path, with: "config")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ConfigValidatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): ssh -G ile config doğrulaması"
```

---

### Task 12: `SSHCommandBuilder`

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/SSH/SSHCommandBuilder.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/SSHCommandBuilderTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `public struct SSHCommandBuilder: Equatable, Sendable { public let configFile: URL; public let homeDirectory: URL; public init(configFile: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser); public var usesDefaultConfig: Bool; public var configArguments: [String]; public func sshArguments(options: [String] = [], alias: String) -> [String]; public func shellCommand(alias: String) -> String; public static func shellQuote(_ value: String) -> String }`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/SSHCommandBuilderTests.swift`:

```swift
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
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter SSHCommandBuilderTests`
Expected: FAIL — `cannot find 'SSHCommandBuilder' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/SSH/SSHCommandBuilder.swift`:

```swift
import Foundation

/// Builds ssh argument lists and shell command lines for the active config file.
/// A non-default config file is passed with `-F`; the alias always follows `--`.
public struct SSHCommandBuilder: Equatable, Sendable {
    public let configFile: URL
    public let homeDirectory: URL

    public init(configFile: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.configFile = configFile
        self.homeDirectory = homeDirectory
    }

    public var usesDefaultConfig: Bool {
        let defaultConfig = homeDirectory.appending(path: ".ssh/config")
        return configFile.resolvingSymlinksInPath().standardizedFileURL.path
            == defaultConfig.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public var configArguments: [String] {
        usesDefaultConfig ? [] : ["-F", configFile.path]
    }

    public func sshArguments(options: [String] = [], alias: String) -> [String] {
        configArguments + options + ["--", alias]
    }

    public func shellCommand(alias: String) -> String {
        (["ssh"] + sshArguments(alias: alias).map(Self.shellQuote)).joined(separator: " ")
    }

    private static let safeScalars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-".unicodeScalars)

    /// Leaves values made only of safe characters as-is; single-quotes everything else.
    public static func shellQuote(_ value: String) -> String {
        if !value.isEmpty && value.unicodeScalars.allSatisfy(safeScalars.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter SSHCommandBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): -F ve güvenli tırnaklamalı SSHCommandBuilder"
```

---

### Task 13: Bağlantı testi — sınıflandırıcı ve `ConnectionTester`

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/SSH/ConnectionTester.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConnectionTesterTests.swift`

**Interfaces:**
- Consumes: `ProcessRunning`, `ProcessRunner`, `ProcessResult` (Task 10); `SSHCommandBuilder` (Task 12)
- Produces:
  - `public enum ConnectionStatus: Equatable, Sendable { case reachable, authenticationRequired, hostKeyChanged, unknownHostKey, timeout, dnsFailure, connectionRefused, other }`
  - `public struct ConnectionTestResult: Equatable, Sendable { public let status: ConnectionStatus; public let detail: String }`
  - `public enum ConnectionClassifier { public static func classify(exitCode: Int32, stderr: String, timedOut: Bool) -> ConnectionStatus; public static func firstLine(_ text: String) -> String }`
  - `public struct ConnectionTester: Sendable { public static let options: [String]; public init(commandBuilder: SSHCommandBuilder, runner: any ProcessRunning = ProcessRunner(), sshPath: URL = URL(filePath: "/usr/bin/ssh")); public func test(alias: String) async -> ConnectionTestResult; public func testAll(_ aliases: [String], maxConcurrent: Int = 4, onResult: @escaping @Sendable (String, ConnectionTestResult) async -> Void) async }`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/ConnectionTesterTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct ConnectionTesterTests {
    static let changedKey = """
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    Host key verification failed.
    """

    @Test(arguments: [
        (Int32(0), "", false, ConnectionStatus.reachable),
        (255, changedKey, false, .hostKeyChanged),
        (255, "No ED25519 host key is known for x and you have requested strict checking.\r\nHost key verification failed.\r\n", false, .unknownHostKey),
        (255, "ssh: Could not resolve hostname nope.invalid: nodename nor servname provided, or not known\r\n", false, .dnsFailure),
        (255, "ssh: connect to host 127.0.0.1 port 1: Connection refused\r\n", false, .connectionRefused),
        (255, "ssh: connect to host 10.255.255.1 port 22: Operation timed out\r\n", false, .timeout),
        (255, "deploy@10.0.0.1: Permission denied (publickey,password).\r\n", false, .authenticationRequired),
        (255, "Received disconnect from 1.2.3.4 port 22:2: Too many authentication failures\r\n", false, .authenticationRequired),
        (255, "", true, .timeout),
        (1, "kex_exchange_identification: read: Connection reset by peer\r\n", false, .other),
    ])
    func classification(exitCode: Int32, stderr: String, timedOut: Bool, expected: ConnectionStatus) {
        #expect(ConnectionClassifier.classify(exitCode: exitCode, stderr: stderr, timedOut: timedOut) == expected)
    }

    @Test func firstLineSkipsBannersAndBlankLines() {
        #expect(ConnectionClassifier.firstLine("\r\n  \nssh: boom\r\nnext") == "ssh: boom")
        #expect(ConnectionClassifier.firstLine(Self.changedKey) == "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @")
    }

    @Test func testBuildsSafeArguments() async throws {
        let fake = FakeRunner { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/x/custom"), homeDirectory: URL(filePath: "/h"))
        let result = await ConnectionTester(commandBuilder: builder, runner: fake).test(alias: "web")
        #expect(result == ConnectionTestResult(status: .reachable, detail: ""))
        #expect(try #require(fake.calls.first) == ["-F", "/x/custom", "-T",
            "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=yes",
            "-o", "ControlPath=none", "--", "web", "exit"])
    }

    @Test func runnerErrorBecomesOther() async {
        let failing = FailingRunner()
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let result = await ConnectionTester(commandBuilder: builder, runner: failing).test(alias: "a")
        #expect(result.status == .other)
    }

    @Test func testAllLimitsConcurrencyAndReportsEveryAlias() async {
        let fake = FakeRunner(delay: .milliseconds(50)) { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let collected = Collected()
        let aliases = (1...10).map { "h\($0)" }
        await ConnectionTester(commandBuilder: builder, runner: fake).testAll(aliases, maxConcurrent: 4) { alias, _ in
            collected.add(alias)
        }
        #expect(fake.maxConcurrent <= 4)
        #expect(fake.maxConcurrent >= 2)
        #expect(collected.values.sorted() == aliases.sorted())
    }
}

private struct FailingRunner: ProcessRunning {
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        throw CocoaError(.fileNoSuchFile)
    }
}

private final class Collected: Sendable {
    private let storage = Mutex<[String]>([])
    func add(_ value: String) { storage.withLock { $0.append(value) } }
    var values: [String] { storage.withLock { $0 } }
}
```

Bu test dosyasının en üstüne `import Synchronization` ekle.

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ConnectionTesterTests`
Expected: FAIL — `cannot find 'ConnectionClassifier' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/SSH/ConnectionTester.swift`:

```swift
import Foundation

public enum ConnectionStatus: Equatable, Sendable {
    case reachable
    case authenticationRequired
    case hostKeyChanged
    case unknownHostKey
    case timeout
    case dnsFailure
    case connectionRefused
    /// See `ConnectionTestResult.detail` for ssh's message.
    case other
}

public struct ConnectionTestResult: Equatable, Sendable {
    public let status: ConnectionStatus
    /// First meaningful stderr line from ssh (untranslated).
    public let detail: String

    public init(status: ConnectionStatus, detail: String) {
        self.status = status
        self.detail = detail
    }
}

/// Classifies ssh output. Relies on OpenSSH's English messages; the runner forces `LC_ALL=C`.
public enum ConnectionClassifier {
    public static func classify(exitCode: Int32, stderr: String, timedOut: Bool) -> ConnectionStatus {
        if timedOut { return .timeout }
        if exitCode == 0 { return .reachable }
        let rules: [(String, ConnectionStatus)] = [
            ("REMOTE HOST IDENTIFICATION HAS CHANGED", .hostKeyChanged),
            ("Host key verification failed", .unknownHostKey),
            ("Could not resolve hostname", .dnsFailure),
            ("Connection refused", .connectionRefused),
            ("Operation timed out", .timeout),
            ("Connection timed out", .timeout),
            ("Permission denied", .authenticationRequired),
            ("Too many authentication failures", .authenticationRequired),
            ("keyboard-interactive", .authenticationRequired),
        ]
        return rules.first { stderr.contains($0.0) }?.1 ?? .other
    }

    /// First non-blank line that is not a row of "@" banner characters.
    public static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.allSatisfy { $0 == "@" } } ?? ""
    }
}

public struct ConnectionTester: Sendable {
    /// `-T` suppresses "Pseudo-terminal will not be allocated"; `ControlPath=none`
    /// keeps an existing multiplexed connection from masking the result.
    public static let options = [
        "-T",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "ControlPath=none",
    ]

    private let commandBuilder: SSHCommandBuilder
    private let runner: any ProcessRunning
    private let sshPath: URL

    public init(commandBuilder: SSHCommandBuilder, runner: any ProcessRunning = ProcessRunner(), sshPath: URL = URL(filePath: "/usr/bin/ssh")) {
        self.commandBuilder = commandBuilder
        self.runner = runner
        self.sshPath = sshPath
    }

    public func test(alias: String) async -> ConnectionTestResult {
        let arguments = commandBuilder.sshArguments(options: Self.options, alias: alias) + ["exit"]
        do {
            let result = try await runner.run(sshPath, arguments: arguments, environment: [:], timeout: .seconds(10))
            return ConnectionTestResult(
                status: ConnectionClassifier.classify(exitCode: result.exitCode, stderr: result.stderr, timedOut: result.timedOut),
                detail: ConnectionClassifier.firstLine(result.stderr))
        } catch {
            return ConnectionTestResult(status: .other, detail: error.localizedDescription)
        }
    }

    public func testAll(
        _ aliases: [String],
        maxConcurrent: Int = 4,
        onResult: @escaping @Sendable (String, ConnectionTestResult) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var pending = aliases.makeIterator()
            func startNext() {
                guard let alias = pending.next() else { return }
                group.addTask { await onResult(alias, await self.test(alias: alias)) }
            }
            for _ in 0..<max(maxConcurrent, 1) { startNext() }
            while await group.next() != nil { startNext() }
        }
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ConnectionTesterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): bağlantı testi ve ssh hata sınıflandırması"
```

---

### Task 14: `IncludeResolver`

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/IncludeResolver.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/IncludeResolverTests.swift`

**Interfaces:**
- Consumes: `ConfigDocument`, `ConfigDocument.includes`, `ConfigDocument.hosts`, `HostEntry`
- Produces:
  - `public struct IncludedHost: Identifiable, Equatable, Sendable { public let file: URL; public let entry: HostEntry; public var id: String }`
  - `public struct IncludeResolver: Sendable { public let homeDirectory: URL; public let maxDepth: Int; public var sshDirectory: URL; public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, maxDepth: Int = 16); public func includedHosts(of document: ConfigDocument, rootFile: URL?) -> [IncludedHost] }`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/IncludeResolverTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct IncludeResolverTests {
    @Test func relativeIncludesResolveAgainstDotSSHInGlobOrder() throws {
        let home = try TempDir()
        try home.file(".ssh/config.d/b.conf", "Host b\n")
        try home.file(".ssh/config.d/a.conf", "Host a\n  User u\n")
        let resolver = IncludeResolver(homeDirectory: home.url)
        let hosts = resolver.includedHosts(of: ConfigDocument(parsing: "Include config.d/*.conf\n"), rootFile: nil)
        #expect(hosts.map(\.entry.alias) == ["a", "b"])
        #expect(hosts.first?.entry.value(for: "User") == "u")
        #expect(hosts.first?.file.lastPathComponent == "a.conf")
    }

    @Test func tildeAndAbsolutePaths() throws {
        let home = try TempDir()
        let absolute = try home.file("elsewhere/x", "Host abs\n")
        try home.file("work/ssh", "Host tilde\n")
        let doc = ConfigDocument(parsing: "Include ~/work/ssh \(absolute.path)\n")
        let hosts = IncludeResolver(homeDirectory: home.url).includedHosts(of: doc, rootFile: nil)
        #expect(hosts.map(\.entry.alias) == ["tilde", "abs"])
    }

    @Test func nestedIncludesAndCyclesTerminate() throws {
        let home = try TempDir()
        try home.file(".ssh/one", "Host one\nInclude two\n")
        try home.file(".ssh/two", "Host two\nInclude one\n")
        let hosts = IncludeResolver(homeDirectory: home.url)
            .includedHosts(of: ConfigDocument(parsing: "Include one\n"), rootFile: nil)
        #expect(hosts.map(\.entry.alias) == ["one", "two"])
    }

    @Test func rootFileIsNotListedAgain() throws {
        let home = try TempDir()
        let root = try home.file(".ssh/config", "Host root\nInclude config\n")
        let doc = ConfigDocument(parsing: try home.read(".ssh/config"))
        #expect(IncludeResolver(homeDirectory: home.url).includedHosts(of: doc, rootFile: root).isEmpty)
    }

    @Test func depthLimitStopsRecursion() throws {
        let home = try TempDir()
        for i in 0..<5 { try home.file(".ssh/f\(i)", "Host h\(i)\nInclude f\(i + 1)\n") }
        let hosts = IncludeResolver(homeDirectory: home.url, maxDepth: 3)
            .includedHosts(of: ConfigDocument(parsing: "Include f0\n"), rootFile: nil)
        #expect(hosts.map(\.entry.alias) == ["h0", "h1", "h2"])
    }

    @Test func missingAndNonUTF8FilesAreSkipped() throws {
        let home = try TempDir()
        let bad = home.url.appending(path: ".ssh/bad")
        try FileManager.default.createDirectory(at: bad.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x48, 0x6F, 0x73, 0x74, 0x20, 0xFF, 0xFE]).write(to: bad)
        let hosts = IncludeResolver(homeDirectory: home.url)
            .includedHosts(of: ConfigDocument(parsing: "Include missing bad\n"), rootFile: nil)
        #expect(hosts.isEmpty)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter IncludeResolverTests`
Expected: FAIL — `cannot find 'IncludeResolver' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/Config/IncludeResolver.swift`:

```swift
import Foundation

public struct IncludedHost: Identifiable, Equatable, Sendable {
    public let file: URL
    public let entry: HostEntry
    public var id: String { "\(file.path)#\(entry.headerLine)" }
}

/// Follows `Include` directives the way ssh does: relative paths resolve against `~/.ssh`
/// (even when the root config lives elsewhere), `~` expands to home, globs are sorted.
public struct IncludeResolver: Sendable {
    public let homeDirectory: URL
    public let maxDepth: Int

    public var sshDirectory: URL { homeDirectory.appending(path: ".ssh", directoryHint: .isDirectory) }

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, maxDepth: Int = 16) {
        self.homeDirectory = homeDirectory
        self.maxDepth = maxDepth
    }

    public func includedHosts(of document: ConfigDocument, rootFile: URL?) -> [IncludedHost] {
        var visited = Set<String>()
        if let rootFile { visited.insert(rootFile.resolvingSymlinksInPath().path) }
        var result: [IncludedHost] = []
        collect(document, depth: 0, visited: &visited, into: &result)
        return result
    }

    private func collect(_ document: ConfigDocument, depth: Int, visited: inout Set<String>, into result: inout [IncludedHost]) {
        guard depth < maxDepth else { return }
        for include in document.includes {
            for pattern in include.paths {
                for file in expand(pattern) {
                    guard visited.insert(file.resolvingSymlinksInPath().path).inserted,
                          let data = try? Data(contentsOf: file),
                          let text = String(validating: data, as: UTF8.self)
                    else { continue }
                    let included = ConfigDocument(parsing: text)
                    result += included.hosts.map { IncludedHost(file: file, entry: $0) }
                    collect(included, depth: depth + 1, visited: &visited, into: &result)
                }
            }
        }
    }

    private func expand(_ pattern: String) -> [URL] {
        let path: String
        if pattern == "~" {
            path = homeDirectory.path
        } else if pattern.hasPrefix("~/") {
            path = homeDirectory.appending(path: String(pattern.dropFirst(2))).path
        } else if pattern.hasPrefix("/") {
            path = pattern
        } else {
            path = sshDirectory.appending(path: pattern).path
        }

        var matches = glob_t()
        defer { globfree(&matches) }
        guard glob(path, 0, nil, &matches) == 0 else { return [] }
        return (0..<Int(matches.gl_pathc)).compactMap { index in
            guard let cString = matches.gl_pathv[index] else { return nil }
            let url = URL(filePath: String(cString: cString))
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
            return url
        }
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter IncludeResolverTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): ssh kurallarıyla Include çözümleme"
```

---

### Task 15: `FileWatcher` (FSEvents)

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/IO/FileWatcher.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/FileWatcherTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `public final class FileWatcher: @unchecked Sendable { public init(directory: URL, latency: TimeInterval = 0.2, onChange: @escaping @Sendable () -> Void) }` — nesne yaşadığı sürece izler; `deinit` akışı durdurur.

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/FileWatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct FileWatcherTests {
    /// Waits up to `timeout` for the stream to yield once.
    private func firstEvent(_ stream: AsyncStream<Void>, timeout: Duration = .seconds(5)) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test func reportsInPlaceWrites() async throws {
        let tmp = try TempDir()
        let file = try tmp.file("config", "a")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let watcher = FileWatcher(directory: tmp.url.resolvingSymlinksInPath()) { continuation.yield() }
        try await Task.sleep(for: .milliseconds(300))

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("b".utf8))
        try handle.close()

        #expect(await firstEvent(stream))
        withExtendedLifetime(watcher) {}
    }

    @Test func reportsAtomicReplacement() async throws {
        let tmp = try TempDir()
        let file = try tmp.file("config", "a")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let watcher = FileWatcher(directory: tmp.url.resolvingSymlinksInPath()) { continuation.yield() }
        try await Task.sleep(for: .milliseconds(300))

        try Data("b".utf8).write(to: file, options: .atomic)

        #expect(await firstEvent(stream))
        withExtendedLifetime(watcher) {}
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter FileWatcherTests`
Expected: FAIL — `cannot find 'FileWatcher' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/IO/FileWatcher.swift`:

```swift
import CoreServices
import Foundation

/// Watches a directory with FSEvents (file-level events), so both in-place writes and
/// atomic rename-replacements of files inside it are reported. Callers filter by
/// comparing fingerprints; this class only says "something changed".
public final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "SSHConfigKit.FileWatcher")

    public init(directory: URL, latency: TimeInterval = 0.2, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            nil, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter FileWatcherTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): FSEvents tabanlı FileWatcher"
```

---

### Task 16: `ConfigStore`

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Stores/ConfigStore.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `ConfigDocument` ve düzenleme API'si (Task 2–5), `LineDiff` (Task 7), `FileFingerprint`, `BackupManager`, `SafeFileWriter` (Task 8–9), `ConfigValidator`, `ValidationOutcome` (Task 11), `IncludeResolver`, `IncludedHost` (Task 14), `FileWatcher` (Task 15)
- Produces:
  - `public enum ConfigLoadState: Equatable, Sendable { case loaded, missing, notUTF8, unreadable(String) }`
  - `public enum ConfigStoreError: Error, Equatable, Sendable { case notEditable, conflict, validationFailed(String), validationTimedOut, writeFailed(String) }`
  - `public struct SavePreparation: Equatable, Sendable { public let hunks: [DiffHunk]; public let validation: ValidationOutcome }`
  - `@MainActor @Observable public final class ConfigStore` — `fileURL`, `document`, `diskText`, `loadState`, `includedHosts`, `externalChangePending`, `hasUnsavedChanges`; `init(fileURL:writer:validator:includeResolver:watchForChanges:)`, `load()`, `createFile() throws`, `apply(_:) throws`, `discardChanges()`, `prepareSave(probeAlias:) async -> SavePreparation`, `save(overwritingExternalChanges:) async throws`, internal `fileDidChange()`

- [ ] **Step 1: Başarısız testleri yaz**

`Tests/SSHConfigKitTests/ConfigStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

@MainActor
struct ConfigStoreTests {
    private func makeStore(_ tmp: TempDir, name: String = "config", watch: Bool = false) -> ConfigStore {
        ConfigStore(
            fileURL: tmp.url.appending(path: name),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"))),
            includeResolver: IncludeResolver(homeDirectory: tmp.url),
            watchForChanges: watch)
    }

    private func addPort(_ store: ConfigStore) throws {
        try store.apply { doc in
            let entry = doc.hosts[0]
            var draft = HostDraft(entry)
            draft.directives.append(DraftDirective(key: "Port", value: "2222"))
            try doc.updateHost(at: entry.headerLine, to: draft)
        }
    }

    @Test func loadsExistingFile() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let store = makeStore(tmp)
        #expect(store.loadState == .loaded)
        #expect(store.document.hosts.map(\.alias) == ["a"])
        #expect(!store.hasUnsavedChanges)
    }

    @Test func missingFileCanBeCreated() throws {
        let tmp = try TempDir()
        let store = makeStore(tmp, name: "sub/.ssh/config")
        #expect(store.loadState == .missing)
        #expect(throws: ConfigStoreError.notEditable) { try store.apply { _ in } }

        try store.createFile()

        #expect(store.loadState == .loaded)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let dirAttributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.deletingLastPathComponent().path)
        #expect(dirAttributes[.posixPermissions] as? Int == 0o700)
    }

    @Test func nonUTF8FileIsReadOnly() async throws {
        let tmp = try TempDir()
        try Data([0x48, 0x6F, 0x73, 0x74, 0x20, 0xFF]).write(to: tmp.url.appending(path: "config"))
        let store = makeStore(tmp)
        #expect(store.loadState == .notUTF8)
        await #expect(throws: ConfigStoreError.notEditable) { try await store.save() }
        #expect(try Data(contentsOf: tmp.url.appending(path: "config")) == Data([0x48, 0x6F, 0x73, 0x74, 0x20, 0xFF]))
    }

    @Test func bomFileIsReportedNotSilentlyChangedAndCanBeFixed() async throws {
        let tmp = try TempDir()
        let original = "\u{FEFF}Host bom\r\n  HostName x\r\n"
        try tmp.file("config", original)
        let store = makeStore(tmp)
        #expect(store.loadState == .loaded)
        #expect(store.document.hasByteOrderMark)
        #expect(store.document.hosts.isEmpty)   // ssh does not see this Host line either

        let error = await #expect(throws: ConfigStoreError.self) { try await store.save() }
        guard case .validationFailed? = error else {
            Issue.record("validationFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(try Data(contentsOf: store.fileURL) == Data(original.utf8))

        try store.apply { $0.removeByteOrderMark() }
        try await store.save()
        #expect(try Data(contentsOf: store.fileURL) == Data("Host bom\r\n  HostName x\r\n".utf8))
        #expect(store.document.hosts.map(\.alias) == ["bom"])
    }

    @Test func editPrepareAndSave() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let store = makeStore(tmp)
        try addPort(store)
        #expect(store.hasUnsavedChanges)

        let preparation = await store.prepareSave()
        #expect(preparation.validation == .valid)
        #expect(preparation.hunks.count == 1)
        #expect(preparation.hunks[0].lines.filter { $0.kind == .added }.map(\.text) == ["  Port 2222"])

        try await store.save()
        #expect(!store.hasUnsavedChanges)
        #expect(try tmp.read("config") == "Host a\n  User u\n  Port 2222\n")
        #expect(try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "config").count == 1)
    }

    @Test func invalidConfigIsNotWritten() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives.append(DraftDirective(key: "Bogus", value: "yes"))
            try doc.updateHost(at: 0, to: draft)
        }
        let error = await #expect(throws: ConfigStoreError.self) { try await store.save() }
        guard case .validationFailed(let message)? = error else {
            Issue.record("validationFailed bekleniyordu: \(String(describing: error))")
            return
        }
        #expect(message.contains("Bad configuration option: bogus"))
        #expect(try tmp.read("config") == "Host a\n")
    }

    @Test func externalChangeWithoutLocalEditsReloads() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try tmp.file("config", "Host b\n")
        store.fileDidChange()
        #expect(store.document.hosts.map(\.alias) == ["b"])
        #expect(!store.externalChangePending)
    }

    @Test func externalChangeWithLocalEditsBecomesAConflict() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\n")
        let store = makeStore(tmp)
        try addPort(store)
        try tmp.file("config", "Host a\n  User changed-in-vim\n")

        store.fileDidChange()

        #expect(store.externalChangePending)
        #expect(store.hasUnsavedChanges)
        await #expect(throws: ConfigStoreError.conflict) { try await store.save() }
        #expect(try tmp.read("config") == "Host a\n  User changed-in-vim\n")

        try await store.save(overwritingExternalChanges: true)
        #expect(try tmp.read("config") == "Host a\n  User u\n  Port 2222\n")
        #expect(!store.externalChangePending)
    }

    @Test func ownSaveDoesNotTriggerReload() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try addPort(store)
        try await store.save()
        store.fileDidChange()
        #expect(!store.externalChangePending)
        #expect(!store.hasUnsavedChanges)
    }

    @Test func discardChangesRestoresDiskVersion() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try addPort(store)
        store.discardChanges()
        #expect(!store.hasUnsavedChanges)
    }

    @Test func includedHostsAreListed() throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/extra", "Host inc\n")
        try tmp.file("config", "Include extra\nHost a\n")
        #expect(makeStore(tmp).includedHosts.map(\.entry.alias) == ["inc"])
    }

    @Test func watcherReloadsAfterExternalEdit() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp, watch: true)
        try await Task.sleep(for: .milliseconds(300))
        try Data("Host z\n".utf8).write(to: store.fileURL, options: .atomic)

        var attempts = 0
        while store.document.hosts.first?.alias != "z" && attempts < 50 {
            try await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        #expect(store.document.hosts.first?.alias == "z")
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ConfigStoreTests`
Expected: FAIL — `cannot find 'ConfigStore' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`Sources/SSHConfigKit/Stores/ConfigStore.swift`:

```swift
import Foundation
import Observation

public enum ConfigLoadState: Equatable, Sendable {
    case loaded
    case missing
    /// Not valid UTF-8: shown as an error; never rewritten.
    case notUTF8
    case unreadable(String)
}

public enum ConfigStoreError: Error, Equatable, Sendable {
    case notEditable
    case conflict
    case validationFailed(String)
    case validationTimedOut
    case writeFailed(String)
}

public struct SavePreparation: Equatable, Sendable {
    public let hunks: [DiffHunk]
    public let validation: ValidationOutcome
}

/// Single source of UI state for the active config file. The file itself is the
/// source of truth; edits live in `document` until `save()`.
@MainActor
@Observable
public final class ConfigStore {
    public let fileURL: URL
    public private(set) var document: ConfigDocument = .empty
    public private(set) var diskText = ""
    public private(set) var loadState: ConfigLoadState = .missing
    public private(set) var includedHosts: [IncludedHost] = []
    public private(set) var externalChangePending = false

    @ObservationIgnored private var diskFingerprint: FileFingerprint?
    @ObservationIgnored private let writer: SafeFileWriter
    @ObservationIgnored private let validator: ConfigValidator
    @ObservationIgnored private let includeResolver: IncludeResolver
    @ObservationIgnored private var watcher: FileWatcher?

    public init(
        fileURL: URL,
        writer: SafeFileWriter = SafeFileWriter(backups: BackupManager(rootDirectory: BackupManager.defaultRoot)),
        validator: ConfigValidator = ConfigValidator(),
        includeResolver: IncludeResolver = IncludeResolver(),
        watchForChanges: Bool = true
    ) {
        self.fileURL = fileURL
        self.writer = writer
        self.validator = validator
        self.includeResolver = includeResolver
        load()
        if watchForChanges { startWatching() }
    }

    public var hasUnsavedChanges: Bool {
        !document.render().utf8.elementsEqual(diskText.utf8)
    }

    public func load() {
        externalChangePending = false
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            reset(state: .missing)
            return
        } catch {
            reset(state: .unreadable(error.localizedDescription))
            return
        }
        guard let text = String(validating: data, as: UTF8.self) else {
            reset(state: .notUTF8)
            return
        }
        document = ConfigDocument(parsing: text)
        diskText = text
        diskFingerprint = FileFingerprint(data: data)
        loadState = .loaded
        includedHosts = includeResolver.includedHosts(of: document, rootFile: fileURL)
    }

    public func createFile() throws {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if !fm.fileExists(atPath: fileURL.path) {
            guard fm.createFile(atPath: fileURL.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path])
            }
        }
        load()
    }

    /// Applies an edit atomically: if `edit` throws, `document` is unchanged.
    public func apply(_ edit: (inout ConfigDocument) throws -> Void) throws {
        guard loadState == .loaded else { throw ConfigStoreError.notEditable }
        var copy = document
        try edit(&copy)
        document = copy
    }

    public func discardChanges() {
        document = ConfigDocument(parsing: diskText)
    }

    public func prepareSave(probeAlias: String? = nil) async -> SavePreparation {
        let text = document.render()
        let hunks = LineDiff.hunks(old: diskText, new: text)
        return SavePreparation(hunks: hunks, validation: await validate(text, probeAlias: probeAlias))
    }

    /// Validates with `ssh -G`, then writes via `SafeFileWriter` (conflict check, backup, atomic rename).
    public func save(overwritingExternalChanges: Bool = false) async throws {
        guard loadState == .loaded else { throw ConfigStoreError.notEditable }
        let text = document.render()

        switch await validate(text, probeAlias: nil) {
        case .valid: break
        case .invalid(let message): throw ConfigStoreError.validationFailed(message)
        case .timedOut: throw ConfigStoreError.validationTimedOut
        }

        do {
            try writer.write(text, to: fileURL, expected: diskFingerprint,
                             ignoreConflict: overwritingExternalChanges, backupKind: "config")
        } catch SafeFileWriterError.conflict {
            externalChangePending = true
            throw ConfigStoreError.conflict
        } catch let error as SafeFileWriterError {
            throw ConfigStoreError.writeFailed(String(describing: error))
        }

        diskText = text
        diskFingerprint = FileFingerprint(data: Data(text.utf8))
        externalChangePending = false
        includedHosts = includeResolver.includedHosts(of: document, rootFile: fileURL)
    }

    func fileDidChange() {
        let current = try? FileFingerprint.of(fileAt: fileURL)
        guard current != diskFingerprint else { return }
        if hasUnsavedChanges {
            externalChangePending = true
        } else {
            load()
        }
    }

    private func validate(_ text: String, probeAlias: String?) async -> ValidationOutcome {
        let alias = probeAlias ?? document.hosts.first(where: { !$0.isPattern })?.alias ?? "localhost"
        do {
            return try await validator.validate(text, probeAlias: alias)
        } catch {
            return .invalid(message: error.localizedDescription)
        }
    }

    private func reset(state: ConfigLoadState) {
        document = .empty
        diskText = ""
        diskFingerprint = nil
        includedHosts = []
        loadState = state
    }

    private func startWatching() {
        let directory = fileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        let weakStore = WeakStore(self)   // store → watcher → closure must not retain the store
        watcher = FileWatcher(directory: directory) {
            Task { @MainActor in weakStore.value?.fileDidChange() }
        }
    }
}

private final class WeakStore: @unchecked Sendable {
    weak var value: ConfigStore?
    init(_ value: ConfigStore) { self.value = value }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `swift test --package-path Packages/SSHConfigKit --filter ConfigStoreTests`
Expected: PASS.

- [ ] **Step 5: Tüm paket testlerini çalıştır**

Run: `swift test --package-path Packages/SSHConfigKit`
Expected: PASS — tüm test dosyaları, uyarısız derleme (Swift 6 strict concurrency).

- [ ] **Step 6: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): ConfigStore — yükleme, düzenleme, doğrulama, güvenli kaydetme, dış değişiklik takibi"
```

---

## Plan 1 tamamlandığında

- `swift test --package-path Packages/SSHConfigKit` yeşil.
- Spec başarı kriteri 1, 2 ve 4 paket düzeyinde testlerle kanıtlanmış olur (bayt bayt gidiş-dönüş, yalnızca düzenlenen satırların değişmesi, `ssh -G` doğrulaması + yedek).
- Sıradaki adım: Plan 2 (uygulama kabuğu ve arayüz) bu paketin public API'sini kullanarak yazılır.
