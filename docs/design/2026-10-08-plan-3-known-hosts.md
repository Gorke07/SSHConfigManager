# Plan 3 — Known Hosts: Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** known_hosts dosyasını görüntüleyen, düz ve hash'li kayıtlarda arayan, seçilen kayıtları yedek alarak silen bir Known Hosts penceresi; ayrıca ana pencereden (sağ tık ve "Host anahtarı değişmiş" sonucu) bir host'un known_hosts kayıtlarını silme akışı.

**Architecture:** Ayrıştırma, eşleştirme ve parmak izi `SSHConfigKit` içinde saf ve test edilebilir parçalardır: `KnownHostsDocument` (kayıpsız, satır tabanlı), `HostMatcher` (ssh'in `host` / `[host]:port` biçimi, HMAC-SHA1 hash'li eşleşme), `Fingerprint` (`SHA256:…`), `HostResolver` (`ssh -G`). `KnownHostsStore` dosyayı yükler, izler ve silmeyi taslak olmadan hemen `SafeFileWriter` ile (yedek + atomik yazma) yapar; her yükleme bir `revision` artırır ve silme yalnızca kullanıcının gördüğü revizyona uygulanır, böylece dosya arada değiştiyse yanlış satır silinmez. Uygulamada `AppModel` tek bir `KnownHostsStore` tutar; pencere, ana pencere akışı ve Yedekler ekranı onu paylaşır.

**Tech Stack:** Swift 6.4 (Xcode 27.0), SwiftUI (`Window`, `Table`, `searchable`), CryptoKit (`HMAC<Insecure.SHA1>`, `SHA256`), Swift Testing, XcodeGen.

**Spec:** `docs/design/2026-10-07-ssh-config-manager-design.md` — §1.3 (Known Hosts kapsamı), §3.1–3.3 (birimler, `knownHostsPath` ayarı), §4.7–4.9 (`SafeFileWriter`, yedekler, dış değişiklik), §6.1 (araç çubuğu ve sağ tık "known_hosts kaydını sil…"), §6.2 (menü çubuğu alt kısmı), §6.4 (Host anahtarı değişmiş → "known_hosts kaydını sil…"), §7 (Known Hosts penceresi), §10 (anlaşılmayan satır, UTF-8 değil, dosya yok), §11 (known hosts testleri, `ssh-keygen -H` / `-lf` ile doğrulama, Türkçe locale). Devreden konular: `docs/design/2026-10-07-plan-2b-followups.md` — bu plan o listeyi kapatmaz; orada kalır.

## Global Constraints

- macOS 26.0; Swift 6 dil modu, `SWIFT_STRICT_CONCURRENCY = complete`. Toolchain: Xcode 27.0 (Swift 6.4).
- Yeni paket bağımlılığı yok. Paket yalnızca Foundation, CryptoKit, CoreServices kullanır.
- known_hosts satırları asla yeniden biçimlenmez: silme dışındaki her satır bayt düzeyinde aynı kalır (CRLF, sekme, yorum, anlaşılmayan satır, son satırda newline olmaması dahil).
- Silme: taslak ve "Kaydet" yok; onaydan sonra `BackupManager` + `SafeFileWriter` hemen çalışır. Geri alma Yedekler ekranından yapılır.
- Yedek türü (`backupKind`): varsayılan `~/.ssh/known_hosts` için `known_hosts`; başka bir yol için `known_hosts-` + yolun SHA256'sının ilk 12 onaltılık karakteri.
- ssh araçları sabit yoldan: `/usr/bin/ssh` (`-G`, 5 sn zaman aşımı). Testlerde `ssh-keygen` yalnızca geçici dizindeki dosyalar ve geçici anahtarlarla çalışır.
- ASCII dışı karakterlerde büyük/küçük harf için yerel ayara duyarlı API'ler kullanılmaz (paketteki `asciiLowercased`; `LocaleSafetyTests` yasak listesini denetler).
- **Testler gerçek `~/.ssh`'a, `~/Library`'ye veya `UserDefaults.standard`'a dokunmaz; gerçek terminal açmaz.** Test host'unda known_hosts yolu geçici ana dizindedir.
- Kullanıcıya görünen her metin `String(localized:)` + `Localizable.xcstrings` (en + tr, `translated`, `extractionState: manual`); ssh kelimeleri (`known_hosts`, `@cert-authority`, `@revoked`, anahtar tipleri, `SHA256:` parmak izleri) ve dosyadan gelen metin `Text(verbatim:)` ile çevrilmeden gösterilir. `scripts/check-localization.py` denetler.
- Paket testleri: `xcrun swift test --package-path Packages/SSHConfigKit`. Uygulama testleri: `bash scripts/test-app.sh` (yerelleştirme denetimi, denetleyicinin testleri, xcodegen, xcodebuild). Tek suite: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/<Suite>`. Test sayısı `-quiet` olmayan bir çalıştırmayla ya da xcresult'tan raporlanır.
- **Kullanıcı Ghostty içinde çalışıyor:** Ghostty, Terminal, iTerm2 ya da pencereleri asla kapatılmaz/öldürülmez (osascript/System Events dahil); sentetik tuş vuruşu gönderilmez; yalnızca kendi başlattığın süreçler PID ile sonlandırılır; macOS izin pencerelerine yanıt verilmez; uygulama elle açılmaz. Görsel doğrulama `docs/design/manual-test-checklist.md`'ye eklenir.

## Review Focus

1. **Seçim ile silme arasında dosya değişti (dış düzenleme, `ssh` yeni kayıt ekledi, izleyici yeniden yükledi)** — satır numaraları kaymış olabilir; silme reddedilir, liste yenilenir, yanlış satır asla silinmez (Task 3 ve Task 5'te test).
2. **Desenli düz kayıtlar (`*.example.com`, `!bad.example.com`) ve `@cert-authority` satırları** — "known_hosts kaydını sil…" akışında bir host adıyla eşleşmiş sayılmaz (geniş bir güveni sessizce silmez); pencerede görünür ve yalnızca açıkça seçilerek silinebilir (Task 2 ve Task 7'de test).
3. **CRLF, son satırda newline yok, BOM, yorum, sekme, anlaşılmayan satır** — gidiş-dönüş bayt düzeyinde aynı; bir satırı silmek diğerlerini değiştirmez; BOM'lu ilk satır ⚠ olarak görünür (Task 1'de test).
4. **Arama metni `Example.COM`, `example.com:22`, `example.com:2222`, `[example.com]:2222`, IPv6 (`::1`)** — hash'li kayıtlar ssh'in kuralıyla bulunur (port 22 ise yalın ad, değilse `[host]:port`; host ASCII küçük harf) (Task 2 ve Task 5'te test).
5. **known_hosts dosyası yok** — pencere hata değil "henüz kayıt yok" gösterir; Yedekler'den geri yükleme dosyayı 0600 izinle oluşturur (Task 3 ve Task 8'de test).

---

## Dosya yapısı

```
Packages/SSHConfigKit/Sources/SSHConfigKit/
├── KnownHosts/
│   ├── KnownHostEntry.swift            KnownHostMarker, KnownHostAddress, KnownHostName, KnownHostEntry
│   ├── KnownHostsDocument.swift        kayıpsız belge: satırlar, entries, render, remove(lines:)
│   ├── Fingerprint.swift               base64 anahtar → "SHA256:…"
│   └── HostMatcher.swift               lookupName, sorgu ayrıştırma, düz/hash'li eşleşme
├── SSH/HostResolver.swift              ssh -G → ResolvedHost (hostname, port, hostkeyalias)
└── Stores/KnownHostsStore.swift        yükle, izle, revision, remove(lines:ifRevision:), restore(text:)
Packages/SSHConfigKit/Tests/SSHConfigKitTests/
├── KnownHostsDocumentTests.swift
├── HostMatcherTests.swift              (+ ssh-keygen entegrasyon testleri)
├── HostResolverTests.swift
└── KnownHostsStoreTests.swift
SSHConfigManager/
├── App/SSHConfigManagerApp.swift       Window "knownHosts"
├── Shared/
│   ├── AppSettings.swift               knownHostsPath
│   ├── AppModel.swift                  knownHosts store, switchKnownHosts, hostKeyRemoval durumu
│   └── Messages.swift                  KnownHostsStoreError, HostResolverError metinleri
└── Features/
    ├── KnownHosts/
    │   ├── KnownHostsModel.swift       satırlar, arama, seçim, silme onayı
    │   ├── KnownHostsWindow.swift      Table + arama + silme
    │   ├── HostKeyRemoval.swift        AppModel uzantısı: ssh -G → eşleşen kayıtlar → sil
    │   └── HostKeyRemovalSheet.swift
    ├── HostList/MainWindow.swift       araç çubuğu "Known Hosts", sheet
    ├── HostList/SidebarView.swift      sağ tık "known_hosts kaydını sil…"
    ├── Connect/ConnectionBar.swift     hostKeyChanged → "known_hosts kaydını sil…"
    ├── Connect/ConnectionTestsModel.swift  dropResult(for:)
    ├── QuickConnect/QuickConnectView.swift + MenuBarContent.swift   alt kısımda "Known Hosts"
    └── Settings/ SettingsView.swift (known_hosts yolu), BackupsModel.swift + BackupsView.swift (tür seçimi)
SSHConfigManagerTests/  KnownHostsModelTests.swift, HostKeyRemovalTests.swift, AppModelTests.swift, BackupsModelTests.swift, Support/TestSupport.swift
```

## Test verileri (gerçek `ssh-keygen` çıktısı)

Plan yazılırken geçici bir dizinde üretildi; testlerde aynen kullanılır.

```
ED25519 açık anahtar (base64):  AAAAC3NzaC1lZDI1NTE5AAAAIPfUPYg1znbIXwm8qtmbk2fUgbpCS0X0aPBTqX90D7ND
  ssh-keygen -lf parmak izi:    SHA256:la2oUdtS09OZ69kPsktdpFX2ayEAR71pQfHiCfcmpwQ
ECDSA (nistp256) açık anahtar:  AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMZEF0uxfT/j/MUTD4m4qPdo0bZqQHln5x4cWOV5M4UIXrnccLQ7LCTyysxdMNqMwzrFAmCYRtST3B8qXQZPwx8=
  ssh-keygen -lf parmak izi:    SHA256:kmAs9qUu4Gav2S0iGxToGYV07zWdavw1l3vPHLV1Jdw
ssh-keygen -H çıktısı:
  example.com            → |1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 <ED25519>
  [git.example.com]:2222 → |1|2e88F0oZhjdk7AYBjB2yWxNkEpg=|+36JR+hdplXSdtbGuVpYTEQw0rw= ecdsa-sha2-nistp256 <ECDSA>
```

---

### Task 1: `KnownHostsDocument` — kayıpsız ayrıştırma ve silme

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts/KnownHostEntry.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts/KnownHostsDocument.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/KnownHostsDocumentTests.swift`

**Interfaces:**
- Consumes: yok.
- Produces:
  - `public enum KnownHostMarker: String, Equatable, Sendable { case certAuthority = "@cert-authority", revoked = "@revoked" }`
  - `public struct KnownHostAddress: Equatable, Sendable { host: String; port: Int; isPattern: Bool }`
  - `public enum KnownHostName: Equatable, Sendable { case plain(KnownHostAddress); case hashed(salt: Data, hash: Data) }`
  - `public struct KnownHostEntry: Equatable, Sendable, Identifiable { lineIndex: Int; marker: KnownHostMarker?; names: [KnownHostName]; keyType: String; keyBase64: String; comment: String?; id: Int; isHashed: Bool }`
  - `public enum KnownHostsLineKind: Equatable, Sendable { case blank, comment, entry(KnownHostEntry), unparsable }`
  - `public struct KnownHostsDocument: Sendable { struct Line { raw: String; kind: KnownHostsLineKind }; lines: [Line]; init(parsing:); static let empty; entries: [KnownHostEntry]; unparsableLines: [(index: Int, text: String)]; render() -> String; mutating remove(lines: Set<Int>); static func content(of raw: String) -> String }`

- [ ] **Step 1: Write the failing test**

`Packages/SSHConfigKit/Tests/SSHConfigKitTests/KnownHostsDocumentTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct KnownHostsDocumentTests {
    static let ed = "AAAAC3NzaC1lZDI1NTE5AAAAIPfUPYg1znbIXwm8qtmbk2fUgbpCS0X0aPBTqX90D7ND"
    static let ec = "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMZEF0uxfT/j/MUTD4m4qPdo0bZqQHln5x4cWOV5M4UIXrnccLQ7LCTyysxdMNqMwzrFAmCYRtST3B8qXQZPwx8="

    static let mixed = """
    # comment line
    example.com,192.0.2.1 ssh-ed25519 \(ed) laptop key
    \t[git.example.com]:2222 ecdsa-sha2-nistp256 \(ec)

    |1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 \(ed)
    @cert-authority *.example.com ssh-ed25519 \(ed)
    @revoked bad.example.com ssh-ed25519 \(ed)
    this line is not understood
    """

    @Test(arguments: [
        mixed,
        mixed + "\n",
        mixed.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n",
        "",
        "\n\n",
        "\u{FEFF}example.com ssh-ed25519 \(ed)\n",
        "a ssh-ed25519 \(ed)\r\nb ssh-ed25519 \(ed)",
    ])
    func roundTripIsByteIdentical(_ text: String) {
        #expect(KnownHostsDocument(parsing: text).render().utf8.elementsEqual(text.utf8))
    }

    @Test func parsesEntries() throws {
        let doc = KnownHostsDocument(parsing: Self.mixed)
        let entries = doc.entries
        #expect(entries.count == 5)

        #expect(entries[0].lineIndex == 1)
        #expect(entries[0].names == [
            .plain(KnownHostAddress(host: "example.com", port: 22, isPattern: false)),
            .plain(KnownHostAddress(host: "192.0.2.1", port: 22, isPattern: false)),
        ])
        #expect(entries[0].keyType == "ssh-ed25519")
        #expect(entries[0].keyBase64 == Self.ed)
        #expect(entries[0].comment == "laptop key")
        #expect(entries[0].marker == nil)

        #expect(entries[1].names == [.plain(KnownHostAddress(host: "git.example.com", port: 2222, isPattern: false))])
        #expect(entries[1].comment == nil)

        #expect(entries[2].isHashed)
        let salt = try #require(Data(base64Encoded: "TcU4u9vtVk+qrVRu5kObX1YkHxo="))
        let hash = try #require(Data(base64Encoded: "Xvpl/HIOfbtSWof7EwQayR7aF/k="))
        #expect(entries[2].names == [.hashed(salt: salt, hash: hash)])

        #expect(entries[3].marker == .certAuthority)
        #expect(entries[3].names == [.plain(KnownHostAddress(host: "*.example.com", port: 22, isPattern: true))])
        #expect(entries[4].marker == .revoked)

        #expect(doc.unparsableLines.map(\.index) == [7])
        #expect(doc.unparsableLines.map(\.text) == ["this line is not understood"])
    }

    @Test(arguments: [
        "\u{FEFF}example.com ssh-ed25519 \(ed)",          // BOM: OpenSSH cannot read it
        "example.com ssh-ed25519",                          // no key
        "example.com ssh-ed25519 not*base64",               // key is not base64
        "@unknown example.com ssh-ed25519 \(ed)",           // unknown marker
        "|1|abc ssh-ed25519 \(ed)",                         // malformed hash
        "|1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k=,other ssh-ed25519 \(ed)",
        "a,,b ssh-ed25519 \(ed)",                           // empty name
        "[host]:notaport ssh-ed25519 \(ed)",
        "[host]:70000 ssh-ed25519 \(ed)",
        "[]:22 ssh-ed25519 \(ed)",
    ])
    func malformedLinesAreUnparsable(_ line: String) {
        let doc = KnownHostsDocument(parsing: line + "\n")
        #expect(doc.entries.isEmpty)
        #expect(doc.unparsableLines.map(\.index) == [0])
    }

    @Test func negatedAndWildcardNamesArePatterns() {
        let doc = KnownHostsDocument(parsing: "!bad.example.com,host?.example.com,good.example.com ssh-ed25519 \(Self.ed)\n")
        #expect(doc.entries.first?.names.map { name -> Bool in
            if case .plain(let address) = name { return address.isPattern }
            return false
        } == [true, true, false])
    }

    @Test func removingLinesKeepsEveryOtherByte() {
        let text = Self.mixed.replacingOccurrences(of: "\n", with: "\r\n")
        var doc = KnownHostsDocument(parsing: text)
        doc.remove(lines: [1, 7])
        var expected = text.components(separatedBy: "\r\n")
        expected.remove(at: 7)
        expected.remove(at: 1)
        // The old line 6 keeps its "\r\n" although it is now the last line.
        #expect(doc.render().utf8.elementsEqual((expected.joined(separator: "\r\n") + "\r\n").utf8))
        #expect(doc.entries.map(\.lineIndex) == [1, 3, 4, 5])
    }

    @Test func removingTheLastLineWithoutNewlineLeavesThePreviousTerminator() {
        var doc = KnownHostsDocument(parsing: "a ssh-ed25519 \(Self.ed)\nb ssh-ed25519 \(Self.ed)")
        doc.remove(lines: [1])
        #expect(doc.render() == "a ssh-ed25519 \(Self.ed)\n")
    }

    @Test func removingUnknownIndicesIsANoOp() {
        var doc = KnownHostsDocument(parsing: "a ssh-ed25519 \(Self.ed)\n")
        doc.remove(lines: [5, -1])
        #expect(doc.render() == "a ssh-ed25519 \(Self.ed)\n")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter KnownHostsDocumentTests`
Expected: FAIL — `cannot find 'KnownHostsDocument' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts/KnownHostEntry.swift`:

```swift
import Foundation

public enum KnownHostMarker: String, Equatable, Sendable {
    case certAuthority = "@cert-authority"
    case revoked = "@revoked"
}

/// A plain known_hosts name: `host` (port 22) or `[host]:port`.
public struct KnownHostAddress: Equatable, Sendable {
    public let host: String
    public let port: Int
    /// Wildcards (`*`, `?`) or negation (`!`): never treated as a match for a single host name.
    public let isPattern: Bool

    public init(host: String, port: Int, isPattern: Bool) {
        self.host = host
        self.port = port
        self.isPattern = isPattern
    }
}

public enum KnownHostName: Equatable, Sendable {
    case plain(KnownHostAddress)
    /// `|1|salt|hash`: HMAC-SHA1 of the lookup name, keyed with the salt.
    case hashed(salt: Data, hash: Data)
}

public struct KnownHostEntry: Equatable, Sendable, Identifiable {
    /// Index into `KnownHostsDocument.lines`; stable only for the document it came from.
    public let lineIndex: Int
    public let marker: KnownHostMarker?
    public let names: [KnownHostName]
    public let keyType: String
    public let keyBase64: String
    public let comment: String?

    public var id: Int { lineIndex }

    public var isHashed: Bool {
        names.contains { if case .hashed = $0 { true } else { false } }
    }

    public init(lineIndex: Int, marker: KnownHostMarker?, names: [KnownHostName], keyType: String, keyBase64: String, comment: String?) {
        self.lineIndex = lineIndex
        self.marker = marker
        self.names = names
        self.keyType = keyType
        self.keyBase64 = keyBase64
        self.comment = comment
    }
}
```

`Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts/KnownHostsDocument.swift`:

```swift
import Foundation

public enum KnownHostsLineKind: Equatable, Sendable {
    case blank
    case comment
    case entry(KnownHostEntry)
    /// Kept byte-for-byte and shown with ⚠.
    case unparsable
}

/// Line-based, lossless known_hosts model: `render()` returns the parsed text byte for byte.
public struct KnownHostsDocument: Sendable {
    public struct Line: Sendable {
        /// The line including its terminator ("\n" or "\r\n"; none for a last line without newline).
        public let raw: String
        public let kind: KnownHostsLineKind
    }

    public private(set) var lines: [Line]

    public static let empty = KnownHostsDocument(parsing: "")

    public init(parsing text: String) {
        var result: [Line] = []
        let bytes = Array(text.utf8)
        var start = 0
        var index = 0
        while start < bytes.count {
            var end = start
            while end < bytes.count && bytes[end] != 0x0A { end += 1 }
            let hasNewline = end < bytes.count
            let rawEnd = hasNewline ? end + 1 : end
            let raw = String(decoding: bytes[start..<rawEnd], as: UTF8.self)
            var contentEnd = end
            if contentEnd > start && bytes[contentEnd - 1] == 0x0D { contentEnd -= 1 }
            let content = String(decoding: bytes[start..<contentEnd], as: UTF8.self)
            result.append(Line(raw: raw, kind: Self.classify(content, lineIndex: index)))
            start = rawEnd
            index += 1
        }
        lines = result
    }

    public var entries: [KnownHostEntry] {
        lines.compactMap { if case .entry(let entry) = $0.kind { entry } else { nil } }
    }

    /// Unparsable lines with their index and text (without the terminator).
    public var unparsableLines: [(index: Int, text: String)] {
        lines.enumerated().compactMap { index, line in
            guard line.kind == .unparsable else { return nil }
            return (index, Self.content(of: line.raw))
        }
    }

    public func render() -> String {
        lines.map(\.raw).joined()
    }

    /// Removes the given line indices (unknown indices are ignored) and re-parses so entry
    /// line indices stay consistent. Other lines keep their exact bytes.
    public mutating func remove(lines indices: Set<Int>) {
        let kept = lines.enumerated().filter { !indices.contains($0.offset) }.map(\.element.raw)
        self = KnownHostsDocument(parsing: kept.joined())
    }

    /// A line's text without its terminator.
    public static func content(of raw: String) -> String {
        var text = Substring(raw)
        if text.hasSuffix("\n") { text = text.dropLast() }
        if text.hasSuffix("\r") { text = text.dropLast() }
        return String(text)
    }

    static func classify(_ content: String, lineIndex: Int) -> KnownHostsLineKind {
        if content.unicodeScalars.first == "\u{FEFF}" { return .unparsable }
        let tokens = content.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = tokens.first else { return .blank }
        if first.hasPrefix("#") { return .comment }

        var rest = tokens[...]
        var marker: KnownHostMarker?
        if first.hasPrefix("@") {
            guard let parsed = KnownHostMarker(rawValue: first) else { return .unparsable }
            marker = parsed
            rest = rest.dropFirst()
        }
        guard rest.count >= 3 else { return .unparsable }
        let hostField = rest[rest.startIndex]
        let keyType = rest[rest.startIndex + 1]
        let key = rest[rest.startIndex + 2]
        guard Data(base64Encoded: key) != nil, let names = parseNames(hostField) else { return .unparsable }
        let commentTokens = rest.dropFirst(3)
        return .entry(KnownHostEntry(
            lineIndex: lineIndex, marker: marker, names: names, keyType: keyType, keyBase64: key,
            comment: commentTokens.isEmpty ? nil : commentTokens.joined(separator: " ")))
    }

    static func parseNames(_ field: String) -> [KnownHostName]? {
        if field.hasPrefix("|") {
            // Hashed names are always alone on the line: |1|salt|hash
            let parts = field.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0].isEmpty, parts[1] == "1",
                  let salt = Data(base64Encoded: String(parts[2])), !salt.isEmpty,
                  let hash = Data(base64Encoded: String(parts[3])), !hash.isEmpty
            else { return nil }
            return [.hashed(salt: salt, hash: hash)]
        }
        var names: [KnownHostName] = []
        for part in field.split(separator: ",", omittingEmptySubsequences: false) {
            guard let address = parseAddress(String(part)) else { return nil }
            names.append(.plain(address))
        }
        return names
    }

    static func parseAddress(_ text: String) -> KnownHostAddress? {
        guard !text.isEmpty else { return nil }
        let isPattern = text.hasPrefix("!") || text.contains("*") || text.contains("?")
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            let host = String(text[text.index(after: text.startIndex)..<close])
            let after = text[text.index(after: close)...]
            guard !host.isEmpty, after.hasPrefix(":"),
                  let port = Int(after.dropFirst()), (1...65535).contains(port) else { return nil }
            return KnownHostAddress(host: host, port: port, isPattern: isPattern)
        }
        return KnownHostAddress(host: text, port: 22, isPattern: isPattern)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter KnownHostsDocumentTests`
Expected: PASS. Then the whole package: `xcrun swift test --package-path Packages/SSHConfigKit` — all pass (including `LocaleSafetyTests`).

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts Packages/SSHConfigKit/Tests/SSHConfigKitTests/KnownHostsDocumentTests.swift
git commit -m "feat(kit): lossless known_hosts document"
```

---

### Task 2: `Fingerprint` ve `HostMatcher`

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts/Fingerprint.swift`
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts/HostMatcher.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/HostMatcherTests.swift`

**Interfaces:**
- Consumes: Task 1 (`KnownHostName`, `KnownHostAddress`, `KnownHostEntry`, `KnownHostsDocument`); paketteki `asciiLowercased`.
- Produces:
  - `public enum Fingerprint { static func sha256(base64Key: String) -> String? }`
  - `public enum HostMatcher { static func lookupName(host: String, port: Int) -> String; static func lookupName(forQuery: String) -> String?; static func matches(_ name: KnownHostName, lookupName: String) -> Bool; static func entries(in: KnownHostsDocument, matchingAny: [String]) -> [KnownHostEntry] }`

- [ ] **Step 1: Write the failing test**

`Packages/SSHConfigKit/Tests/SSHConfigKitTests/HostMatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

struct HostMatcherTests {
    static let ed = KnownHostsDocumentTests.ed
    static let ec = KnownHostsDocumentTests.ec
    static let hashedExample = "|1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 \(ed)"
    static let hashedGit = "|1|2e88F0oZhjdk7AYBjB2yWxNkEpg=|+36JR+hdplXSdtbGuVpYTEQw0rw= ecdsa-sha2-nistp256 \(ec)"

    @Test func fingerprintsMatchSshKeygen() {
        #expect(Fingerprint.sha256(base64Key: Self.ed) == "SHA256:la2oUdtS09OZ69kPsktdpFX2ayEAR71pQfHiCfcmpwQ")
        #expect(Fingerprint.sha256(base64Key: Self.ec) == "SHA256:kmAs9qUu4Gav2S0iGxToGYV07zWdavw1l3vPHLV1Jdw")
        #expect(Fingerprint.sha256(base64Key: "not base64!") == nil)
    }

    @Test func lookupNameUsesSshForm() {
        #expect(HostMatcher.lookupName(host: "Example.COM", port: 22) == "example.com")
        #expect(HostMatcher.lookupName(host: "git.example.com", port: 2222) == "[git.example.com]:2222")
    }

    @Test(arguments: [
        ("example.com", "example.com"),
        ("Example.COM", "example.com"),
        ("example.com:22", "example.com"),
        ("example.com:2222", "[example.com]:2222"),
        ("[example.com]:2222", "[example.com]:2222"),
        ("[example.com]:22", "example.com"),
        ("192.0.2.1", "192.0.2.1"),
        ("::1", "::1"),
        ("  example.com  ", "example.com"),
    ])
    func queriesThatLookLikeHosts(_ query: String, _ expected: String) {
        #expect(HostMatcher.lookupName(forQuery: query) == expected)
    }

    @Test(arguments: ["", "two words", "*.example.com", "example.com:abc", "[example.com", "a/b", "SHA256:abc", "..."])
    func queriesThatDoNotLookLikeHosts(_ query: String) {
        #expect(HostMatcher.lookupName(forQuery: query) == nil)
    }

    @Test func hashedNamesMatchLikeSshKeygenF() {
        let doc = KnownHostsDocument(parsing: Self.hashedExample + "\n" + Self.hashedGit + "\n")
        #expect(HostMatcher.entries(in: doc, matchingAny: ["example.com"]).map(\.lineIndex) == [0])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["[git.example.com]:2222"]).map(\.lineIndex) == [1])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["git.example.com"]).isEmpty)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["example.org"]).isEmpty)
    }

    @Test func plainNamesMatchCaseInsensitivelyButPatternsNever() {
        let doc = KnownHostsDocument(parsing: """
        Example.com ssh-ed25519 \(Self.ed)
        *.example.com ssh-ed25519 \(Self.ed)
        !example.com ssh-ed25519 \(Self.ed)
        [example.com]:2222 ssh-ed25519 \(Self.ed)
        @cert-authority example.com ssh-ed25519 \(Self.ed)

        """)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["example.com"]).map(\.lineIndex) == [0])
        #expect(HostMatcher.entries(in: doc, matchingAny: ["[example.com]:2222"]).map(\.lineIndex) == [3])
    }

    @Test func turkishLocaleDoesNotChangeMatching() {
        // "I" must lowercase to "i" (not "ı") whatever the user's locale is.
        #expect(HostMatcher.lookupName(host: "GITHUB.COM", port: 22) == "github.com")
        #expect(HostMatcher.lookupName(forQuery: "INFO.EXAMPLE.COM") == "info.example.com")
    }

    // MARK: - Against the real ssh-keygen, in a temporary directory only.

    @Test func agreesWithSshKeygenOnFreshKeys() async throws {
        let tmp = try TempDir()
        let runner = ProcessRunner()
        let keygen = URL(filePath: "/usr/bin/ssh-keygen")
        let key = tmp.url.appending(path: "k")
        let generated = try await runner.run(keygen, arguments: ["-q", "-t", "ed25519", "-N", "", "-C", "t", "-f", key.path],
                                             environment: [:], timeout: .seconds(30))
        #expect(generated.exitCode == 0)
        let pub = try tmp.read("k.pub").split(separator: " ")
        let type = String(pub[0]), blob = String(pub[1])

        let listed = try await runner.run(keygen, arguments: ["-lf", key.path + ".pub"], environment: [:], timeout: .seconds(30))
        #expect(listed.stdout.split(separator: " ")[1] == Fingerprint.sha256(base64Key: blob).map(Substring.init))

        let hosts = try tmp.file("known_hosts", "host-a.example.com \(type) \(blob)\n[host-b.example.com]:2200 \(type) \(blob)\n")
        let hashed = try await runner.run(keygen, arguments: ["-H", "-f", hosts.path], environment: [:], timeout: .seconds(30))
        #expect(hashed.exitCode == 0)
        let doc = KnownHostsDocument(parsing: try tmp.read("known_hosts"))
        #expect(doc.entries.allSatisfy(\.isHashed))
        #expect(HostMatcher.entries(in: doc, matchingAny: ["host-a.example.com"]).count == 1)
        #expect(HostMatcher.entries(in: doc, matchingAny: [HostMatcher.lookupName(host: "host-b.example.com", port: 2200)]).count == 1)
        #expect(HostMatcher.entries(in: doc, matchingAny: ["host-c.example.com"]).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter HostMatcherTests`
Expected: FAIL — `cannot find 'Fingerprint' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts/Fingerprint.swift`:

```swift
import CryptoKit
import Foundation

public enum Fingerprint {
    /// `ssh-keygen -lf` style: "SHA256:" + unpadded base64 of SHA-256 over the key blob.
    public static func sha256(base64Key: String) -> String? {
        guard let blob = Data(base64Encoded: base64Key) else { return nil }
        var digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        while digest.hasSuffix("=") { digest.removeLast() }
        return "SHA256:" + digest
    }
}
```

`Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts/HostMatcher.swift`:

```swift
import CryptoKit
import Foundation

/// Finds known_hosts entries for one host, the way `ssh-keygen -F` does.
public enum HostMatcher {
    /// ssh's lookup form: `host` for port 22, `[host]:port` otherwise; the host is ASCII-lowercased.
    public static func lookupName(host: String, port: Int) -> String {
        let lower = host.asciiLowercased
        return port == 22 ? lower : "[\(lower)]:\(port)"
    }

    private static let hostScalars = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:".unicodeScalars)

    /// Parses a search query that looks like one host (`host`, `host:port`, `[host]:port`, IPv6);
    /// returns nil for anything else (spaces, wildcards, slashes, …).
    public static func lookupName(forQuery query: String) -> String? {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("[") {
            guard let address = KnownHostsDocument.parseAddress(text), !address.isPattern,
                  isHost(address.host) else { return nil }
            return lookupName(host: address.host, port: address.port)
        }
        guard isHost(text) else { return nil }
        let colons = text.filter { $0 == ":" }.count
        if colons == 1, let colon = text.firstIndex(of: ":") {
            let host = String(text[..<colon])
            guard isHost(host), !host.contains(":"),
                  let port = Int(text[text.index(after: colon)...]), (1...65535).contains(port) else { return nil }
            return lookupName(host: host, port: port)
        }
        return lookupName(host: text, port: 22)   // plain host or IPv6 literal
    }

    private static func isHost(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy(hostScalars.contains)
            && text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    public static func matches(_ name: KnownHostName, lookupName: String) -> Bool {
        switch name {
        case .plain(let address):
            // Patterns are never a match for one host: deleting them would drop wider trust.
            guard !address.isPattern else { return false }
            return Self.lookupName(host: address.host, port: address.port) == lookupName.asciiLowercased
        case .hashed(let salt, let hash):
            let code = HMAC<Insecure.SHA1>.authenticationCode(for: Data(lookupName.utf8), using: SymmetricKey(data: salt))
            return Data(code) == hash
        }
    }

    /// Entries (no markers: `@cert-authority` / `@revoked` lines are not host keys) with a name
    /// matching any of `lookupNames`.
    public static func entries(in document: KnownHostsDocument, matchingAny lookupNames: [String]) -> [KnownHostEntry] {
        document.entries.filter { entry in
            entry.marker == nil && entry.names.contains { name in lookupNames.contains { matches(name, lookupName: $0) } }
        }
    }
}
```

Note: `"SHA256:abc"` returns nil — it has one colon but `abc` is not a port. `"..."` returns nil because a host needs at least one letter or digit.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter HostMatcherTests`
Expected: PASS. Then the whole package passes.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit/Sources/SSHConfigKit/KnownHosts Packages/SSHConfigKit/Tests/SSHConfigKitTests/HostMatcherTests.swift
git commit -m "feat(kit): known_hosts fingerprints and host matching (plain and hashed)"
```

---

### Task 3: `KnownHostsStore` — yükleme, izleme, revizyonlu silme, geri yükleme

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/Stores/KnownHostsStore.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/KnownHostsStoreTests.swift`

**Interfaces:**
- Consumes: Task 1; mevcut `SafeFileWriter`, `SafeFileWriterError`, `BackupManager`, `FileFingerprint`, `FileWatcher`, `ConfigLoadState`.
- Produces:
  - `public enum KnownHostsStoreError: Error, Equatable, Sendable { case notEditable, staleSelection, conflict, writeFailed(SafeFileWriterError) }`
  - `@MainActor @Observable public final class KnownHostsStore { fileURL; backupKind; document; loadState; revision: Int; isWatching; init(fileURL:writer:watchForChanges:backupKind:); load(); remove(lines: Set<Int>, ifRevision: Int) throws; restore(text: String) throws; backupKeep: Int?; setBackupKeep(_:) }`

- [ ] **Step 1: Write the failing test**

`Packages/SSHConfigKit/Tests/SSHConfigKitTests/KnownHostsStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

@MainActor
struct KnownHostsStoreTests {
    static let ed = KnownHostsDocumentTests.ed
    static let text = "a.example.com ssh-ed25519 \(ed)\r\n# note\r\nb.example.com ssh-ed25519 \(ed)\r\nc.example.com ssh-ed25519 \(ed)"

    func makeStore(_ tmp: TempDir, contents: String? = text) throws -> KnownHostsStore {
        if let contents { try tmp.file("known_hosts", contents, permissions: 0o644) }
        return KnownHostsStore(
            fileURL: tmp.url.appending(path: "known_hosts"),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"))),
            watchForChanges: false)
    }

    @Test func loadsTheFile() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        #expect(store.loadState == .loaded)
        #expect(store.document.entries.count == 3)
        #expect(store.backupKind == "known_hosts")
    }

    @Test func missingFileIsAnEmptyListNotAnError() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp, contents: nil)
        #expect(store.loadState == .missing)
        #expect(store.document.entries.isEmpty)
    }

    @Test func notUTF8IsNeverEditable() throws {
        let tmp = try TempDir()
        try Data([0xFF, 0xFE, 0x00]).write(to: tmp.url.appending(path: "known_hosts"))
        let store = try makeStore(tmp, contents: nil)
        #expect(store.loadState == .notUTF8)
        #expect(throws: KnownHostsStoreError.notEditable) { try store.remove(lines: [0], ifRevision: store.revision) }
    }

    @Test func removeWritesImmediatelyKeepsOtherBytesPermissionsAndBacksUp() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        try store.remove(lines: [2], ifRevision: store.revision)
        let expected = "a.example.com ssh-ed25519 \(Self.ed)\r\n# note\r\nc.example.com ssh-ed25519 \(Self.ed)"
        #expect(try tmp.read("known_hosts") == expected)
        #expect(store.document.render() == expected)
        let mode = try FileManager.default.attributesOfItem(atPath: tmp.url.appending(path: "known_hosts").path)[.posixPermissions] as? Int
        #expect(mode == 0o644)
        let backups = try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "known_hosts")
        #expect(backups.count == 1)
        #expect(try String(contentsOf: backups[0].url, encoding: .utf8) == Self.text)
    }

    @Test func removingWithAnOldRevisionIsRefused() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        let seen = store.revision
        store.load()   // e.g. the watcher reloaded after `ssh` appended a key
        #expect(throws: KnownHostsStoreError.staleSelection) { try store.remove(lines: [0], ifRevision: seen) }
        #expect(try tmp.read("known_hosts") == Self.text)
    }

    @Test func externalChangeBeforeRemoveIsAConflictAndReloads() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        let seen = store.revision
        try tmp.file("known_hosts", "new.example.com ssh-ed25519 \(Self.ed)\n" + Self.text)
        #expect(throws: KnownHostsStoreError.conflict) { try store.remove(lines: [0], ifRevision: seen) }
        #expect(try tmp.read("known_hosts").hasPrefix("new.example.com"))
        #expect(store.revision != seen)
        #expect(store.document.entries.first?.names == [.plain(KnownHostAddress(host: "new.example.com", port: 22, isPattern: false))])
    }

    @Test func restoreCreatesAMissingFileWith0600() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp, contents: nil)
        try store.restore(text: "a.example.com ssh-ed25519 \(Self.ed)\n")
        #expect(store.loadState == .loaded)
        #expect(store.document.entries.count == 1)
        let mode = try FileManager.default.attributesOfItem(atPath: tmp.url.appending(path: "known_hosts").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func restoreBacksUpTheCurrentFile() throws {
        let tmp = try TempDir()
        let store = try makeStore(tmp)
        try store.restore(text: "")
        #expect(try tmp.read("known_hosts") == "")
        #expect(try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "known_hosts").count == 1)
    }

    @Test func symlinkedFileIsReplacedThroughTheLink() throws {
        let tmp = try TempDir()
        let real = try tmp.file("real/known_hosts", Self.text)
        try FileManager.default.createSymbolicLink(at: tmp.url.appending(path: "known_hosts"), withDestinationURL: real)
        let store = KnownHostsStore(fileURL: tmp.url.appending(path: "known_hosts"), writer: SafeFileWriter(backups: nil), watchForChanges: false)
        try store.remove(lines: [0], ifRevision: store.revision)
        #expect(try tmp.read("real/known_hosts").hasPrefix("# note"))
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: tmp.url.appending(path: "known_hosts").path)
        #expect(link == real.path)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter KnownHostsStoreTests`
Expected: FAIL — `cannot find 'KnownHostsStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Packages/SSHConfigKit/Sources/SSHConfigKit/Stores/KnownHostsStore.swift`:

```swift
import Foundation
import Observation

public enum KnownHostsStoreError: Error, Equatable, Sendable {
    /// Not loaded (unreadable or not UTF-8): never rewritten.
    case notEditable
    /// The document changed since the user selected rows; nothing was written.
    case staleSelection
    /// The file changed on disk since it was loaded; it was reloaded and nothing was written.
    case conflict
    case writeFailed(SafeFileWriterError)
}

/// The known_hosts file. No drafts: removals and restores are written immediately
/// (conflict check → backup → atomic rename) and reloaded.
@MainActor
@Observable
public final class KnownHostsStore {
    public let fileURL: URL
    public let backupKind: String
    public private(set) var document: KnownHostsDocument = .empty
    public private(set) var loadState: ConfigLoadState = .missing
    /// Incremented on every load and write; selections are only valid for the revision they were made in.
    public private(set) var revision = 0
    public private(set) var isWatching = false

    @ObservationIgnored private var writer: SafeFileWriter
    @ObservationIgnored private var diskFingerprint: FileFingerprint?
    @ObservationIgnored private var watcher: FileWatcher?

    public init(
        fileURL: URL,
        writer: SafeFileWriter = SafeFileWriter(backups: BackupManager(rootDirectory: BackupManager.defaultRoot)),
        watchForChanges: Bool = true,
        backupKind: String = "known_hosts"
    ) {
        self.fileURL = fileURL
        self.writer = writer
        self.backupKind = backupKind
        load()
        if watchForChanges { startWatching() }
    }

    public var backupKeep: Int? { writer.backups?.keep }

    public func setBackupKeep(_ keep: Int) {
        guard var backups = writer.backups else { return }
        backups.keep = max(keep, 1)
        writer = SafeFileWriter(backups: backups)
    }

    public func load() {
        revision += 1
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            reset(.missing)
            return
        } catch {
            reset(.unreadable(error.localizedDescription))
            return
        }
        guard let text = String(validating: data, as: UTF8.self) else {
            reset(.notUTF8)
            return
        }
        document = KnownHostsDocument(parsing: text)
        diskFingerprint = FileFingerprint(data: data)
        loadState = .loaded
    }

    /// Removes lines of the document the user saw (`revision`). Refuses if it changed meanwhile.
    public func remove(lines: Set<Int>, ifRevision expected: Int) throws {
        guard loadState == .loaded else { throw KnownHostsStoreError.notEditable }
        guard expected == revision else { throw KnownHostsStoreError.staleSelection }
        var updated = document
        updated.remove(lines: lines)
        try write(updated.render())
    }

    /// Replaces the file with `text` (a backup's contents). Creates it (0600) when missing.
    public func restore(text: String) throws {
        guard loadState == .loaded || loadState == .missing else { throw KnownHostsStoreError.notEditable }
        try write(text)
    }

    private func write(_ text: String) throws {
        do {
            try writer.write(text, to: fileURL, expected: diskFingerprint, backupKind: backupKind)
        } catch SafeFileWriterError.conflict {
            load()
            throw KnownHostsStoreError.conflict
        } catch let error as SafeFileWriterError {
            throw KnownHostsStoreError.writeFailed(error)
        }
        load()
    }

    func fileDidChange() {
        let current = try? FileFingerprint.of(fileAt: fileURL)
        guard current != diskFingerprint else { return }
        load()
    }

    private func reset(_ state: ConfigLoadState) {
        document = .empty
        diskFingerprint = nil
        loadState = state
    }

    private func startWatching() {
        let directory = fileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        let weakStore = WeakKnownHostsStore(self)
        watcher = FileWatcher(directory: directory) {
            Task { @MainActor in weakStore.value?.fileDidChange() }
        }
        isWatching = watcher != nil
    }
}

private final class WeakKnownHostsStore: @unchecked Sendable {
    weak var value: KnownHostsStore?
    init(_ value: KnownHostsStore) { self.value = value }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter KnownHostsStoreTests`
Expected: PASS. Then the whole package passes.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit/Sources/SSHConfigKit/Stores/KnownHostsStore.swift Packages/SSHConfigKit/Tests/SSHConfigKitTests/KnownHostsStoreTests.swift
git commit -m "feat(kit): KnownHostsStore with revision-checked removal and restore"
```

---

### Task 4: `HostResolver` — `ssh -G` ile gerçek host adı, port ve HostKeyAlias

**Files:**
- Create: `Packages/SSHConfigKit/Sources/SSHConfigKit/SSH/HostResolver.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/HostResolverTests.swift`

**Interfaces:**
- Consumes: `SSHCommandBuilder.sshArguments(options:alias:)`, `ProcessRunning`, Task 2 `HostMatcher.lookupName(host:port:)`.
- Produces:
  - `public struct ResolvedHost: Equatable, Sendable { hostname: String; port: Int; hostKeyAlias: String?; lookupNames: [String] }`
  - `public enum HostResolverError: Error, Equatable, Sendable { case failed(String), timedOut, unparsable }`
  - `public struct HostResolver: Sendable { init(commandBuilder:runner:sshPath:); func resolve(alias: String) async throws -> ResolvedHost; static func parse(_ output: String) -> ResolvedHost? }`

- [ ] **Step 1: Write the failing test**

`Packages/SSHConfigKit/Tests/SSHConfigKitTests/HostResolverTests.swift`:

```swift
import Foundation
import Synchronization
import Testing
@testable import SSHConfigKit

/// Records the last arguments and returns a fixed result.
final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    let result: ProcessResult
    private let lock = Mutex<[String]>([])
    var lastArguments: [String] { lock.withLock { $0 } }
    init(_ result: ProcessResult) { self.result = result }
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        lock.withLock { $0 = arguments }
        return result
    }
}

struct HostResolverTests {
    static let output = """
    user me
    hostname example.com
    port 2222
    hostkeyalias myalias
    userknownhostsfile /h/.ssh/known_hosts /h/.ssh/known_hosts2

    """

    @Test func parsesHostnamePortAndAlias() {
        let host = HostResolver.parse(Self.output)
        #expect(host == ResolvedHost(hostname: "example.com", port: 2222, hostKeyAlias: "myalias"))
        #expect(host?.lookupNames == ["myalias", "[example.com]:2222"])
    }

    @Test func withoutAliasOnlyTheHostName() {
        let host = HostResolver.parse("hostname 10.0.0.1\nport 22\n")
        #expect(host?.lookupNames == ["10.0.0.1"])
    }

    @Test func missingHostnameOrBadPortIsUnparsable() {
        #expect(HostResolver.parse("port 22\n") == nil)
        #expect(HostResolver.parse("hostname a\nport x\n") == nil)
    }

    @Test func runsSshGWithTheConfigAndTheAliasAfterDoubleDash() async throws {
        let runner = RecordingRunner(ProcessResult(exitCode: 0, stdout: Self.output, stderr: "", timedOut: false))
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/tmp/other/config"), homeDirectory: URL(filePath: "/h"))
        let host = try await HostResolver(commandBuilder: builder, runner: runner).resolve(alias: "-oProxyCommand=x")
        #expect(host.hostname == "example.com")
        #expect(runner.lastArguments == ["-F", "/tmp/other/config", "-G", "--", "-oProxyCommand=x"])
    }

    @Test func failureAndTimeoutAreReported() async {
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let failing = RecordingRunner(ProcessResult(exitCode: 255, stdout: "", stderr: "Bad configuration option\n", timedOut: false))
        await #expect(throws: HostResolverError.failed("Bad configuration option")) {
            try await HostResolver(commandBuilder: builder, runner: failing).resolve(alias: "a")
        }
        let slow = RecordingRunner(ProcessResult(exitCode: 15, stdout: "", stderr: "", timedOut: true))
        await #expect(throws: HostResolverError.timedOut) {
            try await HostResolver(commandBuilder: builder, runner: slow).resolve(alias: "a")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter HostResolverTests`
Expected: FAIL — `cannot find 'HostResolver' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Packages/SSHConfigKit/Sources/SSHConfigKit/SSH/HostResolver.swift`:

```swift
import Foundation

public struct ResolvedHost: Equatable, Sendable {
    public let hostname: String
    public let port: Int
    public let hostKeyAlias: String?

    public init(hostname: String, port: Int, hostKeyAlias: String?) {
        self.hostname = hostname
        self.port = port
        self.hostKeyAlias = hostKeyAlias
    }

    /// Names to look up in known_hosts: the HostKeyAlias as written (ssh uses it instead of the
    /// host name, without a port) and the host name in ssh's `host` / `[host]:port` form.
    public var lookupNames: [String] {
        var names: [String] = []
        if let hostKeyAlias { names.append(hostKeyAlias) }
        names.append(HostMatcher.lookupName(host: hostname, port: port))
        return names
    }
}

public enum HostResolverError: Error, Equatable, Sendable {
    /// ssh's first stderr line (English, untranslated by design).
    case failed(String)
    case timedOut
    case unparsable
}

/// Asks `ssh -G` which host name, port and HostKeyAlias an alias really uses.
public struct HostResolver: Sendable {
    private let commandBuilder: SSHCommandBuilder
    private let runner: any ProcessRunning
    private let sshPath: URL

    public init(commandBuilder: SSHCommandBuilder, runner: any ProcessRunning = ProcessRunner(), sshPath: URL = URL(filePath: "/usr/bin/ssh")) {
        self.commandBuilder = commandBuilder
        self.runner = runner
        self.sshPath = sshPath
    }

    public func resolve(alias: String) async throws -> ResolvedHost {
        let arguments = commandBuilder.sshArguments(options: ["-G"], alias: alias)
        let result: ProcessResult
        do {
            result = try await runner.run(sshPath, arguments: arguments, environment: [:], timeout: .seconds(5))
        } catch {
            throw HostResolverError.failed(error.localizedDescription)
        }
        if result.timedOut { throw HostResolverError.timedOut }
        guard result.exitCode == 0 else { throw HostResolverError.failed(ConnectionClassifier.firstLine(result.stderr)) }
        guard let host = Self.parse(result.stdout) else { throw HostResolverError.unparsable }
        return host
    }

    /// `ssh -G` prints one lowercase option name and its value per line.
    public static func parse(_ output: String) -> ResolvedHost? {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            if values[key] == nil { values[key] = String(parts[1]) }
        }
        guard let hostname = values["hostname"], !hostname.isEmpty,
              let port = Int(values["port"] ?? "22"), (1...65535).contains(port) else { return nil }
        let alias = values["hostkeyalias"].flatMap { $0.isEmpty || $0 == "none" ? nil : $0 }
        return ResolvedHost(hostname: hostname, port: port, hostKeyAlias: alias)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter HostResolverTests`
Expected: PASS. Then the whole package passes.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit/Sources/SSHConfigKit/SSH/HostResolver.swift Packages/SSHConfigKit/Tests/SSHConfigKitTests/HostResolverTests.swift
git commit -m "feat(kit): resolve hostname, port and HostKeyAlias with ssh -G"
```

---

### Task 5: Uygulama modeli — `knownHostsPath`, `AppModel.knownHosts`, `KnownHostsModel`

**Files:**
- Modify: `SSHConfigManager/Shared/AppSettings.swift`
- Modify: `SSHConfigManager/Shared/AppModel.swift`
- Modify: `SSHConfigManager/Shared/Messages.swift`
- Create: `SSHConfigManager/Features/KnownHosts/KnownHostsModel.swift`
- Modify: `SSHConfigManagerTests/Support/TestSupport.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Test: `SSHConfigManagerTests/KnownHostsModelTests.swift`, `SSHConfigManagerTests/AppModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 (`KnownHostsStore`, `KnownHostsDocument`, `HostMatcher`, `Fingerprint`, `KnownHostsStoreError`).
- Produces:
  - `AppSettings.defaultKnownHostsPath = "~/.ssh/known_hosts"`, `knownHostsPath: String`, `knownHostsURL: URL`, `setKnownHostsPath(_:)`
  - `AppModel.knownHosts: KnownHostsStore`, `AppModel.switchKnownHosts(to: String) -> Bool`, `static AppModel.knownHostsBackupKind(for: URL, home: URL) -> String`, init parameter `makeKnownHostsStore: KnownHostsStoreFactory` (after `makeStore`)
  - `struct KnownHostRow: Identifiable, Equatable { id: Int; hosts: String; ports: String; keyType: String; fingerprint: String; marker: String; comment: String; isHashed: Bool; isUnparsable: Bool }`
  - `@MainActor @Observable final class KnownHostsModel { init(app:); app; searchText; selection: Set<Int>; errorMessage: String?; pendingRemoval: [KnownHostRow]?; rows: [KnownHostRow]; requestRemoveSelection(); confirmRemoval(); cancelRemoval() }`
  - `Messages.text(for: KnownHostsStoreError)`, `Messages.knownHostsLoadText(for: ConfigLoadState) -> String?`

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `knownHosts.hashed` | (hashed entry) | (hash'li kayıt) |
| `knownHosts.missing` | There is no known_hosts file yet. ssh creates it the first time you connect to a host. | Henüz known_hosts dosyası yok. ssh ilk bağlantıda oluşturur. |
| `knownHosts.notUTF8` | The known_hosts file is not valid UTF-8, so it is shown read-only and never rewritten. | known_hosts dosyası geçerli UTF-8 değil; salt okunur gösterilir ve hiçbir zaman yeniden yazılmaz. |
| `knownHosts.unreadable %@` | The known_hosts file could not be read: %@ | known_hosts dosyası okunamadı: %@ |
| `knownHosts.staleSelection` | The known_hosts file changed. The list was refreshed; select the entries again. | known_hosts dosyası değişti. Liste yenilendi; kayıtları yeniden seçin. |
| `knownHosts.conflict` | The known_hosts file was changed by another program. It was reloaded and nothing was deleted. | known_hosts dosyası başka bir program tarafından değiştirildi. Yeniden yüklendi ve hiçbir şey silinmedi. |
| `knownHosts.notEditable` | This known_hosts file cannot be changed. | Bu known_hosts dosyası değiştirilemez. |

- [ ] **Step 1: Write the failing tests**

`SSHConfigManagerTests/KnownHostsModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct KnownHostsModelTests {
    static let ed = "AAAAC3NzaC1lZDI1NTE5AAAAIPfUPYg1znbIXwm8qtmbk2fUgbpCS0X0aPBTqX90D7ND"
    static let ec = "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMZEF0uxfT/j/MUTD4m4qPdo0bZqQHln5x4cWOV5M4UIXrnccLQ7LCTyysxdMNqMwzrFAmCYRtST3B8qXQZPwx8="
    static let file = """
    web.example.com,192.0.2.10 ssh-ed25519 \(ed) deploy
    [db.example.com]:2222 ecdsa-sha2-nistp256 \(ec)
    |1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 \(ed)
    @cert-authority *.corp.example ssh-ed25519 \(ed)
    garbage

    """

    func make(_ tmp: TempDir) -> KnownHostsModel {
        _ = try? tmp.file(".ssh/known_hosts", Self.file)
        return KnownHostsModel(app: makeTestModel(tmp))
    }

    @Test func rowsShowEveryEntryAndUnparsableLine() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        #expect(model.rows.map(\.id) == [0, 1, 2, 3, 4])
        #expect(model.rows[0].hosts == "web.example.com, 192.0.2.10")
        #expect(model.rows[0].ports == "22")
        #expect(model.rows[0].fingerprint == "SHA256:la2oUdtS09OZ69kPsktdpFX2ayEAR71pQfHiCfcmpwQ")
        #expect(model.rows[0].comment == "deploy")
        #expect(model.rows[1].hosts == "db.example.com")
        #expect(model.rows[1].ports == "2222")
        #expect(model.rows[2].isHashed)
        #expect(model.rows[2].hosts == String(localized: "knownHosts.hashed"))
        #expect(model.rows[3].marker == "@cert-authority")
        #expect(model.rows[4].isUnparsable)
        #expect(model.rows[4].hosts == "garbage")
    }

    @Test func plainSearchIsASubstringMatch() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.searchText = "WEB."
        #expect(model.rows.map(\.id) == [0])
        model.searchText = "corp"
        #expect(model.rows.map(\.id) == [3])
        model.searchText = "192.0.2"
        #expect(model.rows.map(\.id) == [0])
        model.searchText = "SHA256:kmAs9"
        #expect(model.rows.map(\.id) == [1])
    }

    @Test func aHostLikeQueryAlsoFindsHashedEntries() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.searchText = "Example.COM"
        #expect(model.rows.map(\.id) == [0, 1, 2, 3])   // plain substring hits + the hashed "example.com"
        model.searchText = "example.com:22"
        #expect(model.rows.map(\.id) == [2])
        model.searchText = "example.com:2222"
        #expect(model.rows.isEmpty)
    }

    @Test func removalAsksThenDeletesTheSelectedLines() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [0, 4]
        model.requestRemoveSelection()
        #expect(model.pendingRemoval?.map(\.id) == [0, 4])
        model.confirmRemoval()
        #expect(model.pendingRemoval == nil)
        #expect(model.selection.isEmpty)
        let text = try tmp.read(".ssh/known_hosts")
        #expect(!text.contains("web.example.com"))
        #expect(!text.contains("garbage"))
        #expect(text.contains("db.example.com"))
        #expect(model.errorMessage == nil)
    }

    @Test func aReloadBetweenRequestAndConfirmDeletesNothing() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [0]
        model.requestRemoveSelection()
        try tmp.file(".ssh/known_hosts", "new.example.com ssh-ed25519 \(Self.ed)\n" + Self.file)
        model.app.knownHosts.load()   // what the file watcher does
        model.confirmRemoval()
        #expect(try tmp.read(".ssh/known_hosts").hasPrefix("new.example.com"))
        #expect(try tmp.read(".ssh/known_hosts").contains("web.example.com"))
        #expect(model.errorMessage == String(localized: "knownHosts.staleSelection"))
    }

    @Test func cancelKeepsTheFile() throws {
        let tmp = try TempDir()
        let model = make(tmp)
        model.selection = [1]
        model.requestRemoveSelection()
        model.cancelRemoval()
        #expect(model.pendingRemoval == nil)
        #expect(try tmp.read(".ssh/known_hosts") == Self.file)
    }
}
```

Append to `SSHConfigManagerTests/AppModelTests.swift` (inside the existing suite type):

```swift
    @Test func knownHostsDefaultsToTheHomeFileAndItsBackupKind() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp)
        #expect(model.knownHosts.fileURL.standardizedFileURL == tmp.url.appending(path: ".ssh/known_hosts").standardizedFileURL)
        #expect(model.knownHosts.backupKind == "known_hosts")
        let other = AppModel.knownHostsBackupKind(for: URL(filePath: "/tmp/other_known_hosts"), home: tmp.url)
        #expect(other.hasPrefix("known_hosts-") && other.count == "known_hosts-".count + 12)
    }

    @Test func switchingKnownHostsPersistsAndReplacesTheStore() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp)
        try tmp.file("other/known_hosts", "a.example.com ssh-ed25519 \(KnownHostsModelTests.ed)\n")
        #expect(model.switchKnownHosts(to: tmp.url.appending(path: "other/known_hosts").path))
        #expect(model.knownHosts.document.entries.count == 1)
        #expect(model.settings.knownHostsPath == tmp.url.appending(path: "other/known_hosts").path)
        #expect(!model.switchKnownHosts(to: "relative/path"))
    }

    @Test func backupCountAlsoAppliesToKnownHosts() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp)
        model.setBackupCount(3)
        #expect(model.knownHosts.backupKeep == 3)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/KnownHostsModelTests`
Expected: FAIL to build — `cannot find 'KnownHostsModel' in scope`.

- [ ] **Step 3: Write minimal implementation**

`SSHConfigManager/Shared/AppSettings.swift` — add next to the config path (same validation rules as the config path):

```swift
    static let defaultKnownHostsPath = "~/.ssh/known_hosts"
```

In `Keys`: `static let knownHostsPath = "knownHostsPath"`. Property and initialization:

```swift
    private(set) var knownHostsPath: String
```

```swift
        let storedKnownHosts = defaults.string(forKey: Keys.knownHostsPath)
        knownHostsPath = storedKnownHosts.flatMap { Self.isValidConfigPath($0) ? $0 : nil } ?? Self.defaultKnownHostsPath
```

```swift
    var knownHostsURL: URL { Self.expand(knownHostsPath, home: homeDirectory) }

    func setKnownHostsPath(_ path: String) {
        knownHostsPath = path
        defaults.set(path, forKey: Keys.knownHostsPath)
    }
```

`SSHConfigManager/Shared/AppModel.swift`:

```swift
    typealias KnownHostsStoreFactory = @MainActor (URL, BackupManager, String) -> KnownHostsStore

    private(set) var knownHosts: KnownHostsStore
    @ObservationIgnored private let makeKnownHostsStore: KnownHostsStoreFactory
```

Init gets a new last parameter `makeKnownHostsStore: @escaping KnownHostsStoreFactory = AppModel.liveKnownHostsStore` (after `makeStore`) and, after `self.store = …`:

```swift
        self.makeKnownHostsStore = makeKnownHostsStore
        self.knownHosts = makeKnownHostsStore(
            settings.knownHostsURL, backups, Self.knownHostsBackupKind(for: settings.knownHostsURL, home: settings.homeDirectory))
```

(Assign `makeKnownHostsStore` and `knownHosts` before `observeSavedState()`; all stored properties must be set before any method call.)

```swift
    static func liveKnownHostsStore(url: URL, backups: BackupManager, backupKind: String) -> KnownHostsStore {
        KnownHostsStore(fileURL: url, writer: SafeFileWriter(backups: backups), backupKind: backupKind)
    }

    /// "known_hosts" for ~/.ssh/known_hosts; otherwise a stable per-path kind.
    static func knownHostsBackupKind(for url: URL, home: URL) -> String {
        backupKind(for: url, defaultPath: home.appending(path: ".ssh/known_hosts"), prefix: "known_hosts")
    }

    private static func backupKind(for url: URL, defaultPath: URL, prefix: String) -> String {
        let path = url.standardizedFileURL.path
        if path == defaultPath.standardizedFileURL.path { return prefix }
        let digest = SHA256.hash(data: Data(path.utf8))
        return prefix + "-" + digest.map { String(format: "%02x", $0) }.joined().prefix(12)
    }

    /// Opens another known_hosts file. There are no drafts, so nothing needs confirming.
    @discardableResult
    func switchKnownHosts(to path: String) -> Bool {
        guard AppSettings.isValidConfigPath(path) else { return false }
        settings.setKnownHostsPath(path)
        let url = settings.knownHostsURL
        knownHosts = makeKnownHostsStore(url, backupManager, Self.knownHostsBackupKind(for: url, home: settings.homeDirectory))
        return true
    }
```

Rewrite the existing `backupKind(for:home:)` to call the shared helper (its results must not change):

```swift
    static func backupKind(for url: URL, home: URL) -> String {
        backupKind(for: url, defaultPath: home.appending(path: ".ssh/config"), prefix: "config")
    }
```

In `setBackupCount(_:)` add `knownHosts.setBackupKeep(settings.backupCount)`.

`SSHConfigManagerTests/Support/TestSupport.swift` — `makeTestModel` passes both store factories by label (no trailing closure any more):

```swift
@MainActor
func makeTestModel(_ tmp: TempDir, config: String? = nil, runner: FixedRunner = .valid,
                   launcher: RecordingLauncher = RecordingLauncher(),
                   isTerminalInstalled: @escaping @MainActor (TerminalChoice) -> Bool = { _ in true }) -> AppModel {
    if let config { _ = try? tmp.file(".ssh/config", config) }
    let settings = AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url)
    return AppModel(
        settings: settings, backupRoot: tmp.url.appending(path: "Backups"),
        processRunner: runner,
        launcherFactory: { _ in launcher },
        isTerminalInstalled: isTerminalInstalled,
        makeStore: { url, backups, kind in
            ConfigStore(
                fileURL: url,
                writer: SafeFileWriter(backups: backups),
                validator: ConfigValidator(runner: runner),
                includeResolver: IncludeResolver(homeDirectory: tmp.url),
                watchForChanges: false,
                backupKind: kind)
        },
        makeKnownHostsStore: { url, backups, kind in
            KnownHostsStore(fileURL: url, writer: SafeFileWriter(backups: backups), watchForChanges: false, backupKind: kind)
        })
}
```

`SSHConfigManager/Shared/Messages.swift`:

```swift
    static func text(for error: KnownHostsStoreError) -> String {
        switch error {
        case .notEditable: String(localized: "knownHosts.notEditable")
        case .staleSelection: String(localized: "knownHosts.staleSelection")
        case .conflict, .writeFailed(.conflict): String(localized: "knownHosts.conflict")
        case .writeFailed(.backupFailed(let detail)): String(localized: "store.backupFailed \(detail)")
        case .writeFailed(.writeFailed(let detail)): String(localized: "store.writeFailed \(detail)")
        }
    }

    /// known_hosts load states: a missing file is normal (ssh creates it), not an error.
    static func knownHostsLoadText(for state: ConfigLoadState) -> String? {
        switch state {
        case .loaded: nil
        case .missing: String(localized: "knownHosts.missing")
        case .notUTF8: String(localized: "knownHosts.notUTF8")
        case .unreadable(let detail): String(localized: "knownHosts.unreadable \(detail)")
        }
    }
```

and in `text(for error: any Error)` add `if let error = error as? KnownHostsStoreError { return text(for: error) }`.

`SSHConfigManager/Features/KnownHosts/KnownHostsModel.swift`:

```swift
import Foundation
import Observation
import SSHConfigKit

/// One table row: an entry or an unparsable line of the known_hosts file.
struct KnownHostRow: Identifiable, Equatable {
    /// Line index in the document it was built from.
    let id: Int
    let hosts: String
    let ports: String
    let keyType: String
    let fingerprint: String
    let marker: String
    let comment: String
    let isHashed: Bool
    let isUnparsable: Bool
    /// Hashed names, for host-like queries.
    let hashedNames: [KnownHostName]
}

@MainActor
@Observable
final class KnownHostsModel {
    let app: AppModel
    var searchText = ""
    var selection: Set<Int> = []
    var errorMessage: String?
    /// Rows waiting for the user to confirm deletion, and the store revision they belong to.
    private(set) var pendingRemoval: [KnownHostRow]?
    @ObservationIgnored private var pendingRevision = 0

    init(app: AppModel) {
        self.app = app
    }

    var allRows: [KnownHostRow] {
        let document = app.knownHosts.document
        return document.lines.enumerated().compactMap { index, line in
            switch line.kind {
            case .entry(let entry): Self.row(for: entry)
            case .unparsable:
                KnownHostRow(id: index, hosts: KnownHostsDocument.content(of: line.raw), ports: "", keyType: "",
                             fingerprint: "", marker: "", comment: "", isHashed: false, isUnparsable: true, hashedNames: [])
            case .blank, .comment: nil
            }
        }
    }

    var rows: [KnownHostRow] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allRows }
        let needle = query.lowercased()
        let lookup = HostMatcher.lookupName(forQuery: query)
        return allRows.filter { row in
            if row.isHashed {
                guard let lookup else { return false }
                return row.hashedNames.contains { HostMatcher.matches($0, lookupName: lookup) }
            }
            return [row.hosts, row.keyType, row.fingerprint, row.comment, row.marker]
                .contains { $0.lowercased().contains(needle) }
        }
    }

    func requestRemoveSelection() {
        let chosen = allRows.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        pendingRevision = app.knownHosts.revision
        pendingRemoval = chosen
    }

    func confirmRemoval() {
        guard let rows = pendingRemoval else { return }
        pendingRemoval = nil
        do {
            try app.knownHosts.remove(lines: Set(rows.map(\.id)), ifRevision: pendingRevision)
            errorMessage = nil
        } catch {
            errorMessage = Messages.text(for: error)
        }
        selection = []
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    private static func row(for entry: KnownHostEntry) -> KnownHostRow {
        var hosts: [String] = []
        var ports: [Int] = []
        var hashed: [KnownHostName] = []
        for name in entry.names {
            switch name {
            case .plain(let address):
                hosts.append(address.host)
                if !ports.contains(address.port) { ports.append(address.port) }
            case .hashed:
                hashed.append(name)
            }
        }
        let isHashed = !hashed.isEmpty
        return KnownHostRow(
            id: entry.lineIndex,
            hosts: isHashed ? String(localized: "knownHosts.hashed") : hosts.joined(separator: ", "),
            ports: ports.sorted().map(String.init).joined(separator: ", "),
            keyType: entry.keyType,
            fingerprint: Fingerprint.sha256(base64Key: entry.keyBase64) ?? "",
            marker: entry.marker?.rawValue ?? "",
            comment: entry.comment ?? "",
            isHashed: isHashed,
            isUnparsable: false,
            hashedNames: hashed)
    }
}
```

Add the catalog keys from the table above.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/KnownHostsModelTests`, then `bash scripts/test-app.sh`.
Expected: PASS, localization check passes.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat: known_hosts store in the app model and the Known Hosts list model"
```

---

### Task 6: Known Hosts penceresi ve erişim yerleri

**Files:**
- Create: `SSHConfigManager/Features/KnownHosts/KnownHostsWindow.swift`
- Modify: `SSHConfigManager/App/SSHConfigManagerApp.swift`
- Modify: `SSHConfigManager/Features/HostList/MainWindow.swift`
- Modify: `SSHConfigManager/Features/QuickConnect/QuickConnectView.swift`
- Modify: `SSHConfigManager/Features/QuickConnect/MenuBarContent.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Modify: `docs/design/manual-test-checklist.md`

**Interfaces:**
- Consumes: Task 5 `KnownHostsModel`, `KnownHostRow`, `Messages.knownHostsLoadText(for:)`.
- Produces: `struct KnownHostsWindow: View { init(app: AppModel) }`; scene `Window(id: "knownHosts")`; `QuickConnectView(… openKnownHosts: (() -> Void)? = nil)`. AppKit/SwiftUI görünümü otomatik test edilmez; doğrulama derleme + tam test çalıştırması + elle kontrol.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `knownHosts.title` | Known Hosts | Known Hosts |
| `knownHosts.column.host` | Host | Host |
| `knownHosts.column.port` | Port | Port |
| `knownHosts.column.type` | Key Type | Anahtar Tipi |
| `knownHosts.column.fingerprint` | Fingerprint (SHA256) | Parmak İzi (SHA256) |
| `knownHosts.column.marker` | Marker | İşaret |
| `knownHosts.search.prompt` | Search hosts, or type a host name to find hashed entries | Host ara ya da hash'li kayıtları bulmak için host adı yaz |
| `knownHosts.delete` | Delete | Sil |
| `knownHosts.delete.confirm.title %lld` | Delete %lld known_hosts entries? | %lld known_hosts kaydı silinsin mi? |
| `knownHosts.delete.confirm.message` | A backup is made first. You can restore it from Backups. | Önce yedek alınır. Yedekler ekranından geri yükleyebilirsiniz. |
| `knownHosts.empty` | No entries | Kayıt yok |
| `knownHosts.unparsable.help` | This line is not understood. It is kept as it is. | Bu satır anlaşılamadı. Olduğu gibi korunur. |
| `toolbar.knownHosts` | Known Hosts | Known Hosts |
| `quick.knownHosts` | Known Hosts | Known Hosts |

(`knownHosts.delete.confirm.title %lld`: catalog'da çoğul biçim gerekmez; `%lld` sayı olarak yazılır.)

- [ ] **Step 1: Write the window**

`SSHConfigManager/Features/KnownHosts/KnownHostsWindow.swift`:

```swift
import SSHConfigKit
import SwiftUI

struct KnownHostsWindow: View {
    @State private var model: KnownHostsModel

    init(app: AppModel) {
        _model = State(initialValue: KnownHostsModel(app: app))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = Messages.knownHostsLoadText(for: model.app.knownHosts.loadState) {
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary)
            }
            Table(model.rows, selection: $model.selection) {
                TableColumn(String(localized: "knownHosts.column.host")) { row in
                    HStack(spacing: 4) {
                        if row.isUnparsable {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help(String(localized: "knownHosts.unparsable.help"))
                        }
                        if row.isHashed { Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityHidden(true) }
                        Text(verbatim: row.hosts).lineLimit(1).textSelection(.enabled)
                    }
                }
                TableColumn(String(localized: "knownHosts.column.port")) { row in Text(verbatim: row.ports) }
                    .width(min: 50, ideal: 60)
                TableColumn(String(localized: "knownHosts.column.type")) { row in Text(verbatim: row.keyType) }
                TableColumn(String(localized: "knownHosts.column.fingerprint")) { row in
                    Text(verbatim: row.fingerprint).font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
                }
                .width(min: 200, ideal: 330)
                TableColumn(String(localized: "knownHosts.column.marker")) { row in Text(verbatim: row.marker) }
                    .width(min: 60, ideal: 110)
            }
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView(String(localized: "knownHosts.empty"), systemImage: "checkmark.shield")
                }
            }
            .onDeleteCommand { model.requestRemoveSelection() }
        }
        .searchable(text: $model.searchText, prompt: String(localized: "knownHosts.search.prompt"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    model.requestRemoveSelection()
                } label: {
                    Label(String(localized: "knownHosts.delete"), systemImage: "trash")
                }
                .disabled(model.selection.isEmpty || model.app.knownHosts.loadState != .loaded)
            }
        }
        .confirmationDialog(
            String(localized: "knownHosts.delete.confirm.title \(model.pendingRemoval?.count ?? 0)"),
            isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.cancelRemoval() } })
        ) {
            Button(String(localized: "knownHosts.delete"), role: .destructive) { model.confirmRemoval() }
        } message: {
            Text(String(localized: "knownHosts.delete.confirm.message"))
        }
        .alert(
            String(localized: "error.title"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "action.close")) { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        .frame(minWidth: 820, minHeight: 420)
    }
}
```

(`error.title` and `action.close` already exist in the catalog; check with `grep -c '"error.title"' SSHConfigManager/Shared/Localization/Localizable.xcstrings` and use the existing key names if they differ.)

- [ ] **Step 2: Add the scene and the entry points**

`SSHConfigManager/App/SSHConfigManagerApp.swift`, after the backups `Window`:

```swift
        Window(String(localized: "knownHosts.title"), id: "knownHosts") {
            KnownHostsWindow(app: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
        }
```

`MainWindow.swift`: add `@Environment(\.openWindow) private var openWindow` and a toolbar item before Save:

```swift
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "knownHosts")
                } label: {
                    Label(String(localized: "toolbar.knownHosts"), systemImage: "checkmark.shield")
                }
            }
```

`QuickConnectView.swift`: new stored property and init parameter `openKnownHosts: (() -> Void)? = nil` (last, so `QuickConnectPanelController` keeps compiling unchanged). In the footer, between "open main window" and "settings":

```swift
                    if let openKnownHosts {
                        footerButton(String(localized: "quick.knownHosts")) { openKnownHosts(); dismiss() }
                    }
```

`MenuBarContent.swift`: add `@Environment(\.openWindow) private var openWindow` and pass

```swift
            openKnownHosts: {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "knownHosts")
                NSApp.activate()
            }
```

Add the catalog keys from the table above.

- [ ] **Step 3: Add the manual checklist section**

Append to `docs/design/manual-test-checklist.md`:

```markdown
## Plan 3 — Known Hosts

Elle denemede gerçek `~/.ssh/known_hosts` kullanılmaz: `defaults write tr.com.mess.SSHConfigManager knownHostsPath /tmp/sshcm-manual/known_hosts` (bitince `defaults delete tr.com.mess.SSHConfigManager knownHostsPath`). Örnek dosya: birkaç düz kayıt, `ssh-keygen -H -f /tmp/sshcm-manual/known_hosts` ile hash'lenmiş bir kopya, bir `@cert-authority` satırı ve bir anlamsız satır.

- [ ] Ana penceredeki araç çubuğundan, menü çubuğunun alt kısmından ve Pencere menüsünden Known Hosts açılıyor; açıkken Dock ikonu görünüyor.
- [ ] Sütunlar: Host, Port, Anahtar Tipi, Parmak İzi, İşaret. Hash'li kayıt 🔒 "(hash'li kayıt)", anlamsız satır ⚠ ile görünüyor.
- [ ] Parmak izleri `ssh-keygen -lf /tmp/sshcm-manual/known_hosts` çıktısıyla aynı.
- [ ] Arama: düz kayıtta alt dize; `ornek.com` / `ornek.com:2222` yazınca hash'li kayıt bulunuyor.
- [ ] Çoklu seçim + Sil (ya da ⌫) → onay → silindi; Yedekler'de known_hosts yedeği var; diğer satırlar aynı (`diff` ile).
- [ ] Pencere açıkken dosyaya terminalden satır eklenince liste kendiliğinden yenileniyor.
- [ ] Dosya yokken pencere hata değil "Henüz known_hosts dosyası yok" gösteriyor.
- [ ] Koyu tema ve Türkçe arayüz.
```

- [ ] **Step 4: Build and run all tests**

Run: `bash scripts/test-app.sh`
Expected: PASS, no warnings, localization check passes.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager docs/design/manual-test-checklist.md
git commit -m "feat: Known Hosts window with search and deletion"
```

---

### Task 7: Ana pencereden "known_hosts kaydını sil…"

**Files:**
- Create: `SSHConfigManager/Features/KnownHosts/HostKeyRemoval.swift`
- Create: `SSHConfigManager/Features/KnownHosts/HostKeyRemovalSheet.swift`
- Modify: `SSHConfigManager/Shared/AppModel.swift` (stored state only)
- Modify: `SSHConfigManager/Features/Connect/ConnectionTestsModel.swift` (`dropResult(for:)`)
- Modify: `SSHConfigManager/Features/HostList/SidebarView.swift`, `SSHConfigManager/Features/Connect/ConnectionBar.swift`, `SSHConfigManager/Features/HostList/MainWindow.swift`
- Modify: `SSHConfigManager/Shared/Messages.swift`, `SSHConfigManager/Shared/Localization/Localizable.xcstrings`, `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/HostKeyRemovalTests.swift`

**Interfaces:**
- Consumes: Task 4 `HostResolver`, `ResolvedHost`, `HostResolverError`; Task 2 `HostMatcher.entries(in:matchingAny:)`; Task 3 `KnownHostsStore.remove(lines:ifRevision:)`; Task 5 `KnownHostRow` is not used here (rows are built from entries).
- Produces:
  - `struct HostKeyRemoval: Equatable, Identifiable { enum Phase: Equatable { case resolving, confirm([KnownHostEntry]), nothingFound([String]), failed(String) }; id: UUID; alias: String; phase: Phase; revision: Int }`
  - `AppModel.hostKeyRemoval: HostKeyRemoval?`; `func requestHostKeyRemoval(alias: String) async`; `func confirmHostKeyRemoval()`; `func cancelHostKeyRemoval()`
  - `ConnectionTestsModel.dropResult(for alias: String)`
  - `Messages.text(for: HostResolverError)`

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `action.removeKnownHost` | Delete known_hosts Entry… | known_hosts Kaydını Sil… |
| `hostKeyRemoval.title %@` | known_hosts entries for “%@” | “%@” için known_hosts kayıtları |
| `hostKeyRemoval.resolving` | Asking ssh which host name and port this host uses… | ssh'e bu host'un hangi ad ve portu kullandığı soruluyor… |
| `hostKeyRemoval.confirm.message` | These entries will be deleted. A backup is made first. | Bu kayıtlar silinecek. Önce yedek alınır. |
| `hostKeyRemoval.nothingFound %@` | No known_hosts entry matches %@. | %@ ile eşleşen known_hosts kaydı yok. |
| `hostKeyRemoval.resolveFailed %@` | ssh could not resolve this host: %@ | ssh bu host'u çözümleyemedi: %@ |
| `hostKeyRemoval.resolveTimedOut` | ssh -G did not answer within 5 seconds. | ssh -G 5 saniye içinde yanıt vermedi. |
| `hostKeyRemoval.resolveUnparsable` | ssh -G returned output that could not be read. | ssh -G okunamayan bir çıktı verdi. |

- [ ] **Step 1: Write the failing test**

`SSHConfigManagerTests/HostKeyRemovalTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct HostKeyRemovalTests {
    static let ed = KnownHostsModelTests.ed
    static let config = "Host web\n  HostName web.example.com\n"
    static let knownHosts = """
    web.example.com ssh-ed25519 \(ed)
    |1|TcU4u9vtVk+qrVRu5kObX1YkHxo=|Xvpl/HIOfbtSWof7EwQayR7aF/k= ssh-ed25519 \(ed)
    *.example.com ssh-ed25519 \(ed)
    other.example.com ssh-ed25519 \(ed)

    """

    /// `ssh -G` output for the alias (FixedRunner also answers validation; exit 0 = valid).
    func make(_ tmp: TempDir, sshG: String) -> AppModel {
        _ = try? tmp.file(".ssh/known_hosts", Self.knownHosts)
        let runner = FixedRunner(result: ProcessResult(exitCode: 0, stdout: sshG, stderr: "", timedOut: false))
        return makeTestModel(tmp, config: Self.config, runner: runner)
    }

    @Test func findsPlainAndHashedEntriesButNotPatterns() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
        await model.requestHostKeyRemoval(alias: "web")
        guard case .confirm(let entries) = model.hostKeyRemoval?.phase else {
            Issue.record("expected confirm, got \(String(describing: model.hostKeyRemoval))"); return
        }
        #expect(entries.map(\.lineIndex) == [0])
        // The hashed line is for "example.com", not "web.example.com"; the pattern never matches.
    }

    @Test func hostKeyAliasIsAlsoLookedUp() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\nhostkeyalias example.com\n")
        await model.requestHostKeyRemoval(alias: "web")
        guard case .confirm(let entries) = model.hostKeyRemoval?.phase else { Issue.record("expected confirm"); return }
        #expect(entries.map(\.lineIndex) == [0, 1])
    }

    @Test func confirmingDeletesOnlyThoseLinesAndForgetsTheTestResult() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
        await model.requestHostKeyRemoval(alias: "web")
        model.confirmHostKeyRemoval()
        #expect(model.hostKeyRemoval == nil)
        let text = try tmp.read(".ssh/known_hosts")
        #expect(!text.contains("web.example.com ssh-ed25519"))
        #expect(text.contains("*.example.com"))
        #expect(text.contains("other.example.com"))
        #expect(model.connectionTests.results["web"] == nil)
    }

    @Test func nothingFoundListsTheNamesThatWereTried() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname 10.9.9.9\nport 2200\n")
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.phase == .nothingFound(["[10.9.9.9]:2200"]))
    }

    @Test func resolveFailureIsShown() async throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/known_hosts", Self.knownHosts)
        let runner = FixedRunner(result: ProcessResult(exitCode: 255, stdout: "", stderr: "Bad configuration option: foo\n", timedOut: false))
        let model = makeTestModel(tmp, config: Self.config, runner: runner)
        await model.requestHostKeyRemoval(alias: "web")
        #expect(model.hostKeyRemoval?.phase == .failed(String(localized: "hostKeyRemoval.resolveFailed \("Bad configuration option: foo")")))
    }

    @Test func aChangeOfTheFileWhileConfirmingDeletesNothing() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname web.example.com\nport 22\n")
        await model.requestHostKeyRemoval(alias: "web")
        try tmp.file(".ssh/known_hosts", "new.example.com ssh-ed25519 \(Self.ed)\n" + Self.knownHosts)
        model.knownHosts.load()
        model.confirmHostKeyRemoval()
        #expect(try tmp.read(".ssh/known_hosts").contains("web.example.com ssh-ed25519"))
        #expect(model.errorMessage == String(localized: "knownHosts.staleSelection"))
    }

    @Test func unsavedAliasesAreRefused() async throws {
        let tmp = try TempDir()
        let model = make(tmp, sshG: "hostname x\nport 22\n")
        await model.requestHostKeyRemoval(alias: "not-in-file")
        #expect(model.hostKeyRemoval == nil)
        #expect(model.errorMessage == String(localized: "connect.notSaved"))
    }

    @Test func cancellingWhileResolvingDropsTheLateAnswer() async throws {
        let tmp = try TempDir()
        _ = try tmp.file(".ssh/known_hosts", Self.knownHosts)
        let model = makeTestModel(tmp, config: Self.config)   // FixedRunner.valid: empty stdout → unparsable
        let task = Task { await model.requestHostKeyRemoval(alias: "web") }
        model.cancelHostKeyRemoval()
        await task.value
        // Either it never started or its answer was dropped; nothing is shown after cancel.
        #expect(model.hostKeyRemoval == nil || model.hostKeyRemoval?.phase != .resolving)
    }
}
```

Note on the last test: the request starts synchronously up to the first `await`, so with `Task {}` scheduling the cancel may run first or second; both orders must leave no stale "resolving" sheet. Replace it with a deterministic version if the implementer adds a delayed runner: `makeTestModel` accepts only `FixedRunner`, so keep this ordering-agnostic assertion.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/HostKeyRemovalTests`
Expected: FAIL to build — `value of type 'AppModel' has no member 'requestHostKeyRemoval'`.

- [ ] **Step 3: Write minimal implementation**

`AppModel.swift` — stored state (an extension cannot add stored properties):

```swift
    /// The "Delete known_hosts entry…" flow for one alias; drives `HostKeyRemovalSheet`.
    var hostKeyRemoval: HostKeyRemoval?
```

`ConnectionTestsModel.swift`:

```swift
    /// Forgets one alias's last result (e.g. after its known_hosts entry was deleted).
    func dropResult(for alias: String) {
        results.removeValue(forKey: alias)
    }
```

`SSHConfigManager/Features/KnownHosts/HostKeyRemoval.swift`:

```swift
import Foundation
import SSHConfigKit

struct HostKeyRemoval: Equatable, Identifiable {
    enum Phase: Equatable {
        case resolving
        case confirm([KnownHostEntry])
        /// The lookup names that were tried.
        case nothingFound([String])
        case failed(String)
    }

    let id = UUID()
    let alias: String
    var phase: Phase
    /// Store revision the matched entries belong to.
    var revision = 0
}

extension AppModel {
    /// ssh -G → real host name, port and HostKeyAlias → matching entries (hashed included, patterns
    /// and marker lines never) → confirmation.
    func requestHostKeyRemoval(alias requested: String) async {
        guard let alias = savedAlias(requested) else {
            errorMessage = String(localized: "connect.notSaved")
            return
        }
        let request = HostKeyRemoval(alias: alias, phase: .resolving)
        hostKeyRemoval = request
        let resolver = HostResolver(commandBuilder: commandBuilder, runner: processRunner)
        let phase: HostKeyRemoval.Phase
        var revision = 0
        do {
            let host = try await resolver.resolve(alias: alias)
            revision = knownHosts.revision
            let entries = HostMatcher.entries(in: knownHosts.document, matchingAny: host.lookupNames)
            phase = entries.isEmpty ? .nothingFound(host.lookupNames) : .confirm(entries)
        } catch let error as HostResolverError {
            phase = .failed(Messages.text(for: error))
        } catch {
            phase = .failed(Messages.text(for: error))
        }
        // Cancelled or replaced while ssh -G was running: drop the late answer.
        guard hostKeyRemoval?.id == request.id else { return }
        hostKeyRemoval?.phase = phase
        hostKeyRemoval?.revision = revision
    }

    func confirmHostKeyRemoval() {
        guard let removal = hostKeyRemoval, case .confirm(let entries) = removal.phase else { return }
        hostKeyRemoval = nil
        do {
            try knownHosts.remove(lines: Set(entries.map(\.lineIndex)), ifRevision: removal.revision)
            connectionTests.dropResult(for: removal.alias)
        } catch {
            errorMessage = Messages.text(for: error)
        }
    }

    func cancelHostKeyRemoval() {
        hostKeyRemoval = nil
    }
}
```

`Messages.swift`:

```swift
    static func text(for error: HostResolverError) -> String {
        switch error {
        case .failed(let detail): String(localized: "hostKeyRemoval.resolveFailed \(detail)")
        case .timedOut: String(localized: "hostKeyRemoval.resolveTimedOut")
        case .unparsable: String(localized: "hostKeyRemoval.resolveUnparsable")
        }
    }
```

and in `text(for error: any Error)`: `if let error = error as? HostResolverError { return text(for: error) }`.

`SSHConfigManager/Features/KnownHosts/HostKeyRemovalSheet.swift`:

```swift
import SSHConfigKit
import SwiftUI

struct HostKeyRemovalSheet: View {
    let model: AppModel
    let removal: HostKeyRemoval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "hostKeyRemoval.title \(removal.alias)")).font(.headline)
            switch removal.phase {
            case .resolving:
                HStack { ProgressView().controlSize(.small); Text(String(localized: "hostKeyRemoval.resolving")) }
            case .confirm(let entries):
                Text(String(localized: "hostKeyRemoval.confirm.message")).foregroundStyle(.secondary)
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: Self.names(of: entry)).fontWeight(.medium)
                        Text(verbatim: "\(entry.keyType)  \(Fingerprint.sha256(base64Key: entry.keyBase64) ?? "")")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 120)
            case .nothingFound(let names):
                let joined = names.joined(separator: ", ")
                Text(String(localized: "hostKeyRemoval.nothingFound \(joined)"))
            case .failed(let message):
                Text(verbatim: message).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "action.cancel"), role: .cancel) { model.cancelHostKeyRemoval() }
                    .keyboardShortcut(.cancelAction)
                if case .confirm = removal.phase {
                    Button(String(localized: "knownHosts.delete"), role: .destructive) { model.confirmHostKeyRemoval() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private static func names(of entry: KnownHostEntry) -> String {
        entry.names.map { name in
            switch name {
            case .plain(let address): address.port == 22 ? address.host : "[\(address.host)]:\(address.port)"
            case .hashed: String(localized: "knownHosts.hashed")
            }
        }.joined(separator: ", ")
    }
}
```

(`action.cancel` must exist in the catalog; if the existing key has another name, use that one — check with `grep '"action\.' SSHConfigManager/Shared/Localization/Localizable.xcstrings`.)

`MainWindow.swift` — present it:

```swift
        .sheet(item: Binding(get: { model.hostKeyRemoval }, set: { if $0 == nil { model.cancelHostKeyRemoval() } })) { removal in
            HostKeyRemovalSheet(model: model, removal: removal)
        }
```

`SidebarView.swift` — in `connectItems(for:)`, after Test:

```swift
            Button(String(localized: "action.removeKnownHost")) {
                Task { await model.requestHostKeyRemoval(alias: alias) }
            }
```

`ConnectionBar.swift` — in `buttons`, inside the `if let alias { … }` block, after the detail text:

```swift
                if model.connectionTests.results[alias]?.status == .hostKeyChanged {
                    Button(String(localized: "action.removeKnownHost")) {
                        Task { await model.requestHostKeyRemoval(alias: alias) }
                    }
                }
```

Add the catalog keys. Append to the Plan 3 section of `docs/design/manual-test-checklist.md`:

```markdown
- [ ] Ana pencerede bir host'a sağ tık → "known_hosts Kaydını Sil…" → `ssh -G` sonrası eşleşen kayıtlar (hash'li dahil, `*.…` desenleri hariç) listeleniyor; Sil → yedek alınmış, yalnızca o satırlar gitmiş.
- [ ] Test sonucu "Host anahtarı değişmiş" iken detaydaki "known_hosts Kaydını Sil…" aynı akışı açıyor; silindikten sonra rozet temizleniyor.
- [ ] Eşleşen kayıt yoksa denenen adlar (`host` / `[host]:port`) gösteriliyor.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/HostKeyRemovalTests`, then `bash scripts/test-app.sh`.
Expected: PASS, localization check passes.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat: delete a host's known_hosts entries from the main window"
```

---

### Task 8: Yedekler'de known_hosts ve Ayarlar'da known_hosts yolu

**Files:**
- Modify: `SSHConfigManager/Features/Settings/BackupsModel.swift`
- Modify: `SSHConfigManager/Features/Settings/BackupsView.swift`
- Modify: `SSHConfigManager/Features/Settings/SettingsView.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Modify: `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/BackupsModelTests.swift`

**Interfaces:**
- Consumes: Task 3 `KnownHostsStore.restore(text:)`, `backupKind`; Task 5 `AppModel.knownHosts`, `switchKnownHosts(to:)`, `AppSettings.knownHostsPath`, `defaultKnownHostsPath`.
- Produces: `enum BackupFileKind: CaseIterable { case config, knownHosts }`; `BackupsModel.fileKind: BackupFileKind` (setting it refreshes); `BackupsModel.restore(_:)` writes known_hosts immediately.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `backups.kind.config` | SSH config | SSH config |
| `backups.kind.knownHosts` | known_hosts | known_hosts |
| `backups.restore.knownHosts.title` | Replace the known_hosts file with this backup? | known_hosts dosyası bu yedekle değiştirilsin mi? |
| `backups.restore.knownHosts.message` | The file is written now. The current file is backed up first. | Dosya hemen yazılır. Mevcut dosyanın önce yedeği alınır. |
| `settings.knownHostsFile` | known_hosts file | known_hosts dosyası |
| `settings.knownHostsFile.useDefault` | Use ~/.ssh/known_hosts | ~/.ssh/known_hosts kullan |
| `settings.knownHostsFile.customNote` | ssh itself still reads ~/.ssh/known_hosts unless your config sets UserKnownHostsFile. | ssh, config'inizde UserKnownHostsFile ayarlı değilse yine ~/.ssh/known_hosts okur. |

- [ ] **Step 1: Write the failing tests**

Append to `SSHConfigManagerTests/BackupsModelTests.swift` (inside the existing suite type):

```swift
    @Test func knownHostsBackupsAreListedSeparatelyAndRestoredImmediately() throws {
        let tmp = try TempDir()
        let ed = KnownHostsModelTests.ed
        _ = try tmp.file(".ssh/known_hosts", "a.example.com ssh-ed25519 \(ed)\nb.example.com ssh-ed25519 \(ed)\n")
        let model = makeTestModel(tmp, config: "Host x\n")
        try model.knownHosts.remove(lines: [0], ifRevision: model.knownHosts.revision)   // makes one backup

        let backups = BackupsModel(model: model)
        #expect(backups.fileKind == .config)
        #expect(backups.backups.isEmpty)
        backups.fileKind = .knownHosts
        #expect(backups.backups.count == 1)

        let backup = try #require(backups.backups.first)
        #expect(!backups.hunks(for: backup).isEmpty)
        try backups.restore(backup)
        #expect(try tmp.read(".ssh/known_hosts") == "a.example.com ssh-ed25519 \(ed)\nb.example.com ssh-ed25519 \(ed)\n")
        backups.refresh()
        #expect(backups.backups.count == 2)   // restoring backed up the current file first
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/BackupsModelTests`
Expected: FAIL to build — `value of type 'BackupsModel' has no member 'fileKind'`.

- [ ] **Step 3: Write minimal implementation**

`BackupsModel.swift`:

```swift
enum BackupFileKind: CaseIterable {
    case config, knownHosts
}
```

In the class:

```swift
    var fileKind: BackupFileKind = .config {
        didSet { if oldValue != fileKind { selectedURL = nil; refresh() } }
    }

    private var backupKind: String {
        switch fileKind {
        case .config: model.store.backupKind
        case .knownHosts: model.knownHosts.backupKind
        }
    }

    private var currentText: String {
        switch fileKind {
        case .config: model.store.document.render()
        case .knownHosts: model.knownHosts.document.render()
        }
    }
```

`refresh()` lists `backupKind` instead of `model.store.backupKind`; `hunks(for:)` uses `currentText` as `old`. `restore(_:)`:

```swift
    /// Config: loads the backup into the editor (the Save flow writes it).
    /// known_hosts: no drafts, so it is written now (the current file is backed up first).
    func restore(_ backup: Backup) throws {
        let contents = try model.backupManager.contents(of: backup)
        switch fileKind {
        case .config:
            try model.store.apply { $0 = ConfigDocument(parsing: contents) }
            model.resetEditor()
        case .knownHosts:
            try model.knownHosts.restore(text: contents)
            refresh()
        }
    }
```

`BackupsView.swift`:
- At the top of the sidebar list add a segmented `Picker` bound to `$backups.fileKind`, with `Text(String(localized: "backups.kind.config")).tag(BackupFileKind.config)` and `Text(String(localized: "backups.kind.knownHosts")).tag(BackupFileKind.knownHosts)`, `.pickerStyle(.segmented)`, `.labelsHidden()`, padded.
- The restore button: for `.knownHosts` always asks first with `backups.restore.knownHosts.title` / `.message` (a second `confirmationDialog` driven by `@State private var confirmingKnownHostsRestore: Backup?`); for `.config` the existing behavior is unchanged. The `.disabled` condition for known_hosts is `backups.model.knownHosts.loadState != .loaded && backups.model.knownHosts.loadState != .missing`.
- Add `.onChange(of: backups.model.knownHosts.revision) { backups.refresh() }`.

`SettingsView.swift` — one file importer for both paths (two `.fileImporter`s on one view do not both work):

```swift
    private enum ImportTarget { case config, knownHosts }
    @State private var importTarget: ImportTarget?
```

Replace `@State private var importing` and its uses: the config "Choose…" button sets `importTarget = .config`; the importer becomes

```swift
        .fileImporter(
            isPresented: Binding(get: { importTarget != nil }, set: { if !$0 { importTarget = nil } }),
            allowedContentTypes: [.data]
        ) { result in
            guard case .success(let url) = result, let target = importTarget else { return }
            let path = model.settings.displayPath(for: url)
            switch target {
            case .config: requestSwitch(path)
            case .knownHosts: model.switchKnownHosts(to: path)
            }
        }
```

(`importTarget` is still set inside the completion: SwiftUI calls the completion before the binding's setter. If the implementer finds the opposite order on macOS 26, capture the target in a separate `@State private var lastImportTarget` set when the button is pressed, and read that instead.)

New section after the config section:

```swift
            Section(String(localized: "settings.knownHostsFile")) {
                LabeledContent(String(localized: "settings.knownHostsFile")) {
                    Text(verbatim: model.settings.knownHostsPath).textSelection(.enabled)
                }
                HStack {
                    Button(String(localized: "action.choose")) { importTarget = .knownHosts }
                    Button(String(localized: "settings.knownHostsFile.useDefault")) {
                        model.switchKnownHosts(to: AppSettings.defaultKnownHostsPath)
                    }
                    .disabled(model.settings.knownHostsPath == AppSettings.defaultKnownHostsPath)
                }
                if model.settings.knownHostsPath != AppSettings.defaultKnownHostsPath {
                    Text(String(localized: "settings.knownHostsFile.customNote"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
```

Add the catalog keys. Append to the Plan 3 section of `docs/design/manual-test-checklist.md`:

```markdown
- [ ] Yedekler: üstteki seçiciyle "known_hosts" seçilince known_hosts yedekleri listeleniyor; diff mevcut dosyaya göre; Geri Yükle onay istiyor ve dosyayı hemen yazıyor (önce mevcut dosyanın yedeği alınıyor).
- [ ] Ayarlar → known_hosts dosyası: Seç… ile başka dosya seçilince Known Hosts penceresi o dosyayı gösteriyor; "~/.ssh/known_hosts kullan" geri alıyor. Config dosyası seçimi hâlâ çalışıyor.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/BackupsModelTests`, then `bash scripts/test-app.sh`, then `xcrun swift test --package-path Packages/SSHConfigKit`.
Expected: all PASS, localization check passes, no warnings.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat: known_hosts backups and known_hosts path in settings"
```
