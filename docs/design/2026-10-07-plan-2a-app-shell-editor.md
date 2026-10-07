# Plan 2a — Uygulama Kabuğu ve Düzenleyici: Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `SSHConfigKit` üzerine, config dosyasını görüntüleyen, form ile düzenleyen, diff onayı + `ssh -G` doğrulaması ile güvenle kaydeden, ayarları ve yedekleri yöneten, İngilizce/Türkçe yerelleştirilmiş native bir macOS 26 SwiftUI uygulaması.

**Architecture:** XcodeGen ile üretilen bir Xcode projesi (`project.yml` commit edilir, `.xcodeproj` edilmez); uygulama target'ı yerel `SSHConfigKit` paketine bağlıdır. Ekran mantığı test edilebilir `@MainActor @Observable` modellerde (`AppModel`, `HostEditorModel`, `SaveFlowModel`, `BackupsModel`) ve saf yardımcılarda (`SidebarBuilder`, `Messages`, `CodeHighlighter`, `DiffPresenter`, `BannerBuilder`) durur; SwiftUI view'ları ince tutulur ve otomatik UI testi yazılmaz (spec §11). Tüm kullanıcı metinleri `String(localized:)` + `Localizable.xcstrings` üzerinden gelir; testler kataloğun eksiksiz olduğunu denetler.

**Tech Stack:** Swift 6.4 (Xcode 26.6), SwiftUI, Observation, AppKit (NSAlert, NSWorkspace, NSPasteboard), XcodeGen 2.46, Swift Testing, String Catalog.

**Spec:** `docs/design/2026-10-07-ssh-config-manager-design.md` — bu plan §3.3 (ayarlar: config yolu, yedek sayısı), §4.6 (kaydetme akışının arayüzü), §4.8 (yedekler ekranı), §4.9 (dış değişiklik bandı), §5 (config dosyası seçimi), §6.1 (ana pencere), §6.1a (metin görünümleri), §6.5 (dil desteği), §10 (hata gösterimi) maddelerini uygular. Plan 1'den devreden maddeler: `docs/design/2026-10-07-plan-1-followups.md`.

### Yol haritası

| Plan | Kapsam | Durum |
|---|---|---|
| 1 — SSHConfigKit çekirdeği | Paket | ✅ tamamlandı |
| **2a — Uygulama kabuğu ve düzenleyici** | Bu doküman | — |
| 2b — Bağlanma | Terminal başlatıcıları (§9) + Ghostty/Warp denemesi (§12), bağlantı testi arayüzü (§6.4), menü çubuğu (§6.2), hızlı panel + ⌥⌘S (§6.3), girişte başlat, Otomasyon izni | 2a sonrası |
| 3 — Known Hosts | §7 | 2b sonrası |
| 4 — Anahtar yönetimi | §8 | 2b sonrası |
| 5 — Dağıtım | İmzalama, notarization, `.dmg` | En son |

## Global Constraints

- macOS 26.0 deployment target; Swift 6 dil modu (`SWIFT_VERSION = 6.0`), `SWIFT_STRICT_CONCURRENCY = complete`.
- App Sandbox **kapalı** (`com.apple.security.app-sandbox = false`). Hardened Runtime yalnızca Release'te açık (Debug'da kapalı; ad-hoc imzalı test paketi yüklenebilsin diye).
- Bundle ID: `tr.com.mess.SSHConfigManager`. Geliştirme dili `en`, yerelleştirmeler `en`, `tr`.
- Uygulama target'ında tek dış bağımlılık yerel `SSHConfigKit` paketidir (Plan 2b'ye kadar başka paket yok). `SSHConfigKit` bağımlılıksız kalır.
- **Kullanıcıya görünen her metin** `String(localized: "anahtar")` ile alınır ve `SSHConfigManager/Shared/Localization/Localizable.xcstrings` içinde hem `en` hem `tr` değeri `translated` durumundadır. `Text`, `Button`, `Label`, `Section`, `Toggle`, `TextField`, `Picker`, `Menu`, `LabeledContent` başlatıcılarına string **literal** verilmez (ssh anahtar kelimeleri gibi çevrilmeyecek metinler için `Text(verbatim:)` kullanılır). Yerelleştirilmiş metinlerdeki interpolasyonlar yalnızca düz tanımlayıcıdır (`\(name)`), sayı önce `String(...)`'e çevrilir. Bu kurallar Task 2'deki testlerle denetlenir.
- ssh direktif adları (`HostName`, `IdentityFile` …), ssh'in kendi hata metinleri ve komut metinleri çevrilmez (spec §6.5).
- Kullanıcı aramasında locale'e duyarlı `localizedStandardContains` kullanılır (spec §6.5); `SSHConfigKit` içinde locale API'leri yasak kalır.
- Testler gerçek `~/.ssh`, gerçek `~/Library/Application Support` veya gerçek `UserDefaults.standard` ile çalışmaz; ev dizini, yedek kökü ve `UserDefaults(suiteName:)` enjekte edilir. Test sırasında açılan uygulama da (test host) gerçek config'i yüklemez (Task 3).
- Paket testleri: `xcrun swift test --package-path Packages/SSHConfigKit`. Uygulama testleri: `scripts/test-app.sh` (XcodeGen ile projeyi üretir, `xcodebuild test` çalıştırır). Tek test: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/<SuiteAdı>`.

## Review Focus

1. **Formda alias yeniden adlandırılırken** seçim yeniden adlandırılan host'ta kalır, form odağı kaybolmaz, başka bir host'a atlamaz (Task 5 ve Task 9'da test/kontrol).
2. **Aynı alias'a sahip iki `Host` bloğu** listede ayrı satırlar olarak görünür ve ikincisini düzenlemek ikinci bloğu değiştirir (Task 4 ve Task 5'te test).
3. **Türkçe arayüz eksiksizdir**: kod içindeki her anahtarın kataloğunda `tr` çevirisi vardır, katalogda kullanılmayan anahtar yoktur, `tr.lproj` uygulama paketine derlenir (Task 2'de test; her görev kendi anahtarlarını ekler).
4. **Kaydedilmemiş değişiklikler asla sessizce kaybolmaz**: config dosyası değiştirilirken onay istenir; uygulamadan çıkarken Kaydet/Vazgeç/At seçenekleri sunulur (Task 3'te test, Task 9'da manuel kontrol).
5. **Forma yapıştırılan satır sonlu değer** (`x\nHost evil`) dosyaya yazılmaz; formda kontrol karakteri sorunu gösterilir (Task 5'te test).

---

## Dosya yapısı

```
project.yml                                  XcodeGen tanımı (commit edilir)
scripts/test-app.sh                          proje üret + xcodebuild test
SSHConfigManager/
├── Info.plist                               (XcodeGen üretir, commit edilir)
├── SSHConfigManager.entitlements
├── App/
│   ├── SSHConfigManagerApp.swift            @main, sahneler
│   └── AppDelegate.swift                    çıkışta kaydedilmemiş değişiklik koruması
├── Shared/
│   ├── Localization/Localizable.xcstrings
│   ├── Messages.swift                       hata/durum → yerelleştirilmiş metin
│   ├── AppSettings.swift                    UserDefaults ayarları
│   ├── AppModel.swift                       store yaşam döngüsü, seçim
│   ├── TestEnvironment.swift                test host algılama
│   └── Text/
│       ├── CodeHighlighter.swift            satır → renk rolleri
│       ├── DiffPresenter.swift              hunk → görüntü satırları
│       ├── CodeTextView.swift
│       └── DiffTextView.swift
└── Features/
    ├── HostList/
    │   ├── SidebarModel.swift               SidebarItem, SidebarBuilder
    │   ├── HostCommands.swift               ekle / çoğalt / sil / komut kopyala
    │   ├── HostEditorModel.swift
    │   ├── BannerBuilder.swift
    │   ├── SaveFlowModel.swift
    │   ├── MainWindow.swift                 NavigationSplitView + toolbar
    │   ├── SidebarView.swift
    │   ├── DetailView.swift                 host formu / dahil edilen / match
    │   ├── HostEditorView.swift
    │   ├── BannerStack.swift
    │   └── SaveSheet.swift
    └── Settings/
        ├── SettingsView.swift
        ├── BackupsModel.swift
        └── BackupsView.swift
SSHConfigManagerTests/
├── Support/TestSupport.swift                TempDir, FixedRunner, makeTestStore
└── <Birim>Tests.swift
```

---

### Task 1: SSHConfigKit hazırlığı (public init'ler, yedek sayısı, include tazeleme, büyük diff sınırı, izlemeyi yeniden başlatma)

**Files:**
- Modify: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/ConfigDocument+Read.swift`
- Modify: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/IncludeResolver.swift`
- Modify: `Packages/SSHConfigKit/Sources/SSHConfigKit/Config/LineDiff.swift`
- Modify: `Packages/SSHConfigKit/Sources/SSHConfigKit/Stores/ConfigStore.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/AppSupportAPITests.swift`

**Interfaces:**
- Consumes: mevcut paket (Plan 1).
- Produces:
  - `public init(line:key:value:)` → `HostDirective`; `public init(headerLine:patterns:directives:)` → `HostEntry`; `public init(headerLine:criteria:text:)` → `MatchEntry`; `public init(file:entry:)` → `IncludedHost`; `public init(kind:text:oldNumber:newNumber:missingNewline:)` → `DiffLine`; `public init(oldStart:oldCount:newStart:newCount:lines:)` → `DiffHunk`.
  - `ConfigStore.backupKeep: Int?` (salt okunur) ve `ConfigStore.setBackupKeep(_ keep: Int)`.
  - `ConfigStore.apply` `includedHosts`'u yalnızca `Include` yol listesi değiştiğinde yeniden hesaplar.
  - `ConfigStore.createFile()` izleme açıksa ve izleyici yoksa izlemeyi başlatır.
  - `LineDiff.maxTableCells = 4_000_000`; aşılırsa orta bölüm "hepsi silindi + hepsi eklendi" olarak üretilir.

- [ ] **Step 1: Başarısız testleri yaz**

`Packages/SSHConfigKit/Tests/SSHConfigKitTests/AppSupportAPITests.swift`:

```swift
import Foundation
import Testing
@testable import SSHConfigKit

@MainActor
struct AppSupportAPITests {
    private func store(_ tmp: TempDir, name: String = "config", watch: Bool = false, keep: Int = 10) -> ConfigStore {
        ConfigStore(
            fileURL: tmp.url.appending(path: name),
            writer: SafeFileWriter(backups: BackupManager(rootDirectory: tmp.url.appending(path: "Backups"), keep: keep)),
            includeResolver: IncludeResolver(homeDirectory: tmp.url),
            watchForChanges: watch)
    }

    @Test func publicInitializersBuildValues() {
        let entry = HostEntry(headerLine: 0, patterns: ["web"], directives: [HostDirective(line: 1, key: "User", value: "u")])
        #expect(entry.value(for: "user") == "u")
        #expect(MatchEntry(headerLine: 3, criteria: "all", text: "Match all").criteria == "all")
        #expect(IncludedHost(file: URL(filePath: "/x"), entry: entry).id == "/x#0")
        let line = DiffLine(kind: .added, text: "a", oldNumber: nil, newNumber: 1, missingNewline: false)
        #expect(DiffHunk(oldStart: 0, oldCount: 0, newStart: 1, newCount: 1, lines: [line]).header == "@@ -0,0 +1,1 @@")
    }

    @Test func setBackupKeepLimitsBackups() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = store(tmp)
        #expect(store.backupKeep == 10)
        store.setBackupKeep(2)
        #expect(store.backupKeep == 2)
        for port in ["1", "2", "3"] {
            try store.apply { doc in
                var draft = HostDraft(doc.hosts[0])
                draft.directives = [DraftDirective(key: "Port", value: port)]
                try doc.updateHost(at: 0, to: draft)
            }
            try await store.save()
        }
        let backups = try BackupManager(rootDirectory: tmp.url.appending(path: "Backups")).list(kind: "config")
        #expect(backups.count == 2)
    }

    @Test func setBackupKeepClampsToOne() throws {
        let tmp = try TempDir()
        let store = store(tmp)
        store.setBackupKeep(0)
        #expect(store.backupKeep == 1)
    }

    @Test func applyRecomputesIncludedHostsOnlyWhenIncludesChange() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Include extra\nHost a\n")
        let store = store(tmp)
        #expect(store.includedHosts.isEmpty)
        try tmp.file(".ssh/extra", "Host inc\n")

        try store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives = [DraftDirective(key: "Port", value: "22")]
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
        #expect(store.includedHosts.isEmpty)   // include list unchanged → not re-resolved

        try store.apply { $0 = ConfigDocument(parsing: "Include extra other\nHost a\n") }
        #expect(store.includedHosts.map(\.entry.alias) == ["inc"])
    }

    @Test func createFileStartsWatching() throws {
        let tmp = try TempDir()
        let store = store(tmp, name: "new/.ssh/config", watch: true)
        try store.createFile()
        #expect(store.isWatching)
    }

    @Test func hugeDiffFallsBackToReplaceAll() {
        let old = (0..<2100).map { "old \($0)" }.joined(separator: "\n") + "\n"
        let new = (0..<2100).map { "new \($0)" }.joined(separator: "\n") + "\n"
        let lines = LineDiff.lines(old: old, new: new)
        #expect(lines.count == 4200)
        #expect(lines.prefix(2100).allSatisfy { $0.kind == .removed })
        #expect(lines.suffix(2100).allSatisfy { $0.kind == .added })
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter AppSupportAPITests`
Expected: FAIL — derleme hatası (`'HostEntry' initializer is inaccessible due to 'internal' protection level` veya `value of type 'ConfigStore' has no member 'backupKeep'`).

- [ ] **Step 3: Uygulamayı yaz**

`ConfigDocument+Read.swift` içinde her tipe açık bir public init ekle (alanlar değişmez):

```swift
// HostDirective içine
public init(line: Int, key: String, value: String) {
    self.line = line
    self.key = key
    self.value = value
}

// HostEntry içine
public init(headerLine: Int, patterns: [String], directives: [HostDirective]) {
    self.headerLine = headerLine
    self.patterns = patterns
    self.directives = directives
}

// MatchEntry içine
public init(headerLine: Int, criteria: String, text: String) {
    self.headerLine = headerLine
    self.criteria = criteria
    self.text = text
}
```

`IncludeResolver.swift` içinde `IncludedHost`'a:

```swift
public init(file: URL, entry: HostEntry) {
    self.file = file
    self.entry = entry
}
```

`LineDiff.swift` içinde `DiffLine` ve `DiffHunk`'a:

```swift
// DiffLine içine
public init(kind: Kind, text: String, oldNumber: Int?, newNumber: Int?, missingNewline: Bool) {
    self.kind = kind
    self.text = text
    self.oldNumber = oldNumber
    self.newNumber = newNumber
    self.missingNewline = missingNewline
}

// DiffHunk içine
public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
    self.oldStart = oldStart
    self.oldCount = oldCount
    self.newStart = newStart
    self.newCount = newCount
    self.lines = lines
}
```

`LineDiff` enum'una sabiti ekle:

```swift
/// Above this many LCS cells the middle region is not aligned with a table; equal lines are
/// still matched greedily, everything else is emitted as "removed, then added".
public static let maxTableCells = 4_000_000
```

`lines(old:new:)` içinde DP tablosunu oluşturan blok (`var dp = Array(repeating: …)` ve onu dolduran iki `for` döngüsü) şununla değiştirilir:

```swift
let useTable = n * m <= maxTableCells
var dp: [[Int]] = []
if useTable {
    dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in stride(from: n - 1, through: 0, by: -1) {
        for j in stride(from: m - 1, through: 0, by: -1) {
            dp[i][j] = same(am[i], bm[j]) ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
        }
    }
}
```

ve `while i < n || j < m` döngüsündeki silme koşulu şuna dönüşür (tablo yoksa önce silinenler gelir; `dp` hiç indekslenmez):

```swift
} else if i < n && (j == m || !useTable || dp[i + 1][j] >= dp[i][j + 1]) {
```

`ConfigStore.swift` değişiklikleri:

```swift
// writer artık değiştirilebilir:
@ObservationIgnored private var writer: SafeFileWriter
// izleme tercihi saklanır:
@ObservationIgnored private let watchForChanges: Bool
```

`init` içinde `self.watchForChanges = watchForChanges` ata (mevcut `if watchForChanges { startWatching() }` aynen kalır).

```swift
/// Number of backups kept per save, or nil when the writer makes no backups.
public var backupKeep: Int? { writer.backups?.keep }

public func setBackupKeep(_ keep: Int) {
    guard var backups = writer.backups else { return }
    backups.keep = max(keep, 1)
    writer = SafeFileWriter(backups: backups)
}
```

`apply` gövdesini şu hale getir:

```swift
public func apply(_ edit: (inout ConfigDocument) throws -> Void) throws {
    guard loadState == .loaded else { throw ConfigStoreError.notEditable }
    var copy = document
    try edit(&copy)
    let includesChanged = copy.includes.map(\.paths) != document.includes.map(\.paths)
    document = copy
    if includesChanged {
        includedHosts = includeResolver.includedHosts(of: document, rootFile: fileURL)
    }
}
```

`createFile()` sonunda (`load()` çağrısından sonra):

```swift
if watchForChanges && !isWatching { startWatching() }
```

(`startWatching()` mevcut haliyle `isWatching`'i ayarlıyor olmalı; ayarlamıyorsa `isWatching = watcher != nil` satırını `startWatching()` sonuna ekle.)

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter AppSupportAPITests`
Expected: PASS. Ardından `xcrun swift test --package-path Packages/SSHConfigKit` — tüm paket yeşil, uyarı yok.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "feat(kit): uygulama için public init'ler, yedek sayısı, include tazeleme, büyük diff sınırı"
```

---

### Task 2: Xcode projesi (XcodeGen), uygulama iskeleti ve yerelleştirme altyapısı

**Files:**
- Create: `project.yml`
- Create: `scripts/test-app.sh`
- Modify: `.gitignore`
- Create: `SSHConfigManager/SSHConfigManager.entitlements` (XcodeGen üretir)
- Create: `SSHConfigManager/Info.plist` (XcodeGen üretir)
- Create: `SSHConfigManager/App/SSHConfigManagerApp.swift`
- Create: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Create: `SSHConfigManagerTests/Support/TestSupport.swift`
- Test: `SSHConfigManagerTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: —
- Produces: derlenebilir `SSHConfigManager.app`; test target `SSHConfigManagerTests` (Swift Testing); `scripts/test-app.sh`; `LocalizationCatalog` test yardımcıları; test destek tipleri `TempDir`, `FixedRunner`.

- [ ] **Step 1: XcodeGen'i kur**

```bash
brew install xcodegen
xcodegen --version
```
Expected: `Version: 2.46.0` (veya daha yeni).

- [ ] **Step 2: Proje tanımını ve betiği oluştur**

`project.yml`:

```yaml
name: SSHConfigManager
options:
  bundleIdPrefix: tr.com.mess
  deploymentTarget:
    macOS: "26.0"
  developmentLanguage: en
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MACOSX_DEPLOYMENT_TARGET: "26.0"
    LOCALIZATION_PREFERS_STRING_CATALOGS: YES
    SWIFT_EMIT_LOC_STRINGS: YES
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
packages:
  SSHConfigKit:
    path: Packages/SSHConfigKit
targets:
  SSHConfigManager:
    type: application
    platform: macOS
    sources:
      - path: SSHConfigManager
    dependencies:
      - package: SSHConfigKit
    info:
      path: SSHConfigManager/Info.plist
      properties:
        CFBundleDisplayName: SSH Config Manager
        CFBundleDevelopmentRegion: en
        CFBundleLocalizations: [en, tr]
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        LSApplicationCategoryType: public.app-category.developer-tools
        LSMinimumSystemVersion: "26.0"
    entitlements:
      path: SSHConfigManager/SSHConfigManager.entitlements
      properties:
        com.apple.security.app-sandbox: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: tr.com.mess.SSHConfigManager
        PRODUCT_NAME: SSH Config Manager
      configs:
        Debug:
          ENABLE_HARDENED_RUNTIME: NO
        Release:
          ENABLE_HARDENED_RUNTIME: YES
  SSHConfigManagerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: SSHConfigManagerTests
    dependencies:
      - target: SSHConfigManager
      - package: SSHConfigKit
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: tr.com.mess.SSHConfigManagerTests
schemes:
  SSHConfigManager:
    build:
      targets:
        SSHConfigManager: all
        SSHConfigManagerTests: [test]
    test:
      targets:
        - SSHConfigManagerTests
```

`scripts/test-app.sh`:

```bash
#!/bin/bash
# Generates the Xcode project from project.yml and runs the app's unit tests.
# Extra arguments are passed to xcodebuild (e.g. -only-testing:SSHConfigManagerTests/LocalizationTests).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --spec project.yml --quiet
xcodebuild test \
  -project SSHConfigManager.xcodeproj \
  -scheme SSHConfigManager \
  -destination 'platform=macOS,arch=arm64' \
  -quiet "$@"
```

```bash
chmod +x scripts/test-app.sh
```

`.gitignore` sonuna ekle:

```gitignore
# Generated by XcodeGen from project.yml
SSHConfigManager.xcodeproj/
```

- [ ] **Step 3: Test destek dosyasını ve başarısız yerelleştirme testlerini yaz**

`SSHConfigManagerTests/Support/TestSupport.swift`:

```swift
import Foundation
import SSHConfigKit

/// A unique temporary directory that is removed when the object is released.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SSHConfigManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ name: String, _ contents: String = "", permissions: Int = 0o600) throws -> URL {
        let target = url.appending(path: name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        return target
    }

    func read(_ name: String) throws -> String {
        String(decoding: try Data(contentsOf: url.appending(path: name)), as: UTF8.self)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// A ProcessRunning that returns a fixed result (lets tests control `ssh -G` validation).
struct FixedRunner: ProcessRunning {
    let result: ProcessResult

    static let valid = FixedRunner(result: ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false))
    static func invalid(_ message: String) -> FixedRunner {
        FixedRunner(result: ProcessResult(exitCode: 255, stdout: "", stderr: message, timedOut: false))
    }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        result
    }
}
```

`SSHConfigManagerTests/LocalizationTests.swift`:

```swift
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
```

> `@testable import SSH_Config_Manager`: ürün adı "SSH Config Manager" olduğu için modül adı `SSH_Config_Manager`'dır. Derleme farklı bir modül adı bildirirse (ör. `PRODUCT_MODULE_NAME`), testlerdeki import'u ona göre düzelt ve raporda belirt.

- [ ] **Step 4: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/LocalizationTests`
Expected: FAIL — `SSHConfigManager` kaynak klasörü / katalog henüz yok (XcodeGen veya derleme hatası).

- [ ] **Step 5: Uygulama iskeletini ve kataloğu yaz**

`SSHConfigManager/App/SSHConfigManagerApp.swift`:

```swift
import SwiftUI

@main
struct SSHConfigManagerApp: App {
    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            ContentUnavailableView(
                String(localized: "detail.empty.title"),
                systemImage: "server.rack",
                description: Text(String(localized: "detail.empty.message")))
                .frame(minWidth: 720, minHeight: 440)
        }
    }
}
```

`SSHConfigManager/Shared/Localization/Localizable.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "app.title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "SSH Config Manager" } },
        "tr" : { "stringUnit" : { "state" : "translated", "value" : "SSH Config Yöneticisi" } }
      }
    },
    "detail.empty.message" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Select a host from the list or add a new one." } },
        "tr" : { "stringUnit" : { "state" : "translated", "value" : "Listeden bir host seçin ya da yeni bir host ekleyin." } }
      }
    },
    "detail.empty.title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "No Host Selected" } },
        "tr" : { "stringUnit" : { "state" : "translated", "value" : "Host Seçilmedi" } }
      }
    }
  },
  "version" : "1.0"
}
```

**Katalog düzenleme kuralı (bu ve sonraki tüm görevler için):** Yeni anahtarlar `"strings"` nesnesine yukarıdaki biçimle (`extractionState: manual`, `en` + `tr`, ikisi de `translated`) eklenir. Sonraki görevlerde anahtarlar `anahtar | en | tr` tablosu olarak verilir; JSON'a birebir bu değerlerle dönüştürülür. Argümanlı anahtarlarda (`… %@`) değerlerde de `%@` bulunur.

Projeyi üret ve kaynak listesini kontrol et:

```bash
xcodegen generate --spec project.yml
git status --short
```
Expected: `SSHConfigManager/Info.plist` ve `SSHConfigManager/SSHConfigManager.entitlements` üretilmiş; `SSHConfigManager.xcodeproj/` git'te görünmüyor (ignore).

- [ ] **Step 6: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/LocalizationTests`
Expected: PASS (6 test). Ardından `scripts/test-app.sh` — tüm uygulama testleri yeşil, derleme uyarısı yok. Uygulamayı bir kez çalıştır: `open "$(xcodebuild -project SSHConfigManager.xcodeproj -scheme SSHConfigManager -showBuildSettings -quiet | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/SSH Config Manager.app"` → "No Host Selected" ekranlı bir pencere açılmalı; ardından uygulamayı kapat.

- [ ] **Step 7: Commit**

```bash
git add project.yml scripts/test-app.sh .gitignore SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): XcodeGen projesi, uygulama iskeleti ve yerelleştirme altyapısı"
```

---

### Task 3: Ayarlar (`AppSettings`) ve uygulama modeli (`AppModel`)

**Files:**
- Create: `SSHConfigManager/Shared/AppSettings.swift`
- Create: `SSHConfigManager/Shared/AppModel.swift`
- Create: `SSHConfigManager/Shared/TestEnvironment.swift`
- Create: `SSHConfigManager/Features/HostList/SidebarModel.swift` (yalnızca `SidebarItem`; geri kalanı Task 4)
- Modify: `SSHConfigManager/App/SSHConfigManagerApp.swift`
- Modify: `SSHConfigManagerTests/Support/TestSupport.swift`
- Test: `SSHConfigManagerTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ConfigStore`, `BackupManager`, `SafeFileWriter`, `IncludeResolver`, `SSHCommandBuilder`, `ConfigStore.setBackupKeep` (Task 1).
- Produces:
  - `@MainActor @Observable final class AppSettings` — `init(defaults: UserDefaults = .standard, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)`, `homeDirectory: URL`, `private(set) var configPath: String`, `private(set) var backupCount: Int`, `configURL: URL`, `func setConfigPath(_:)`, `func setBackupCount(_:)`, `func displayPath(for url: URL) -> String`, `static let defaultConfigPath = "~/.ssh/config"`, `static let backupCountRange = 1...50`, `static func expand(_ path: String, home: URL) -> URL`.
  - `enum SidebarItem: Hashable, Sendable { case host(alias: String, occurrence: Int), included(id: String), match(index: Int) }`
  - `@MainActor @Observable final class AppModel` — `typealias StoreFactory = @MainActor (URL, BackupManager) -> ConfigStore`; `init(settings:backupRoot:makeStore:)`; `settings`, `private(set) var store: ConfigStore`, `private(set) var backupManager: BackupManager`, `var selection: SidebarItem?`, `private(set) var editorToken: UUID`, `var searchText: String`, `var errorMessage: String?`, `commandBuilder: SSHCommandBuilder`, `func select(_ item: SidebarItem?)`, `func followRename(to item: SidebarItem)`, `func resetEditor()`, `enum SwitchResult { case switched, needsConfirmation, unchanged }`, `func switchConfig(to path: String, discardingUnsavedChanges: Bool = false) -> SwitchResult`, `func setBackupCount(_:)`, `static func liveStore(url:backups:) -> ConfigStore`.
  - `enum TestEnvironment { static var isRunningTests: Bool }`
  - Test yardımcısı: `@MainActor func makeTestModel(_ tmp: TempDir, config: String? = nil, runner: FixedRunner = .valid) -> AppModel`.

- [ ] **Step 1: Test yardımcısını ekle** (`TestSupport.swift` sonuna; dosyanın başına `@testable import SSH_Config_Manager` ekle)

```swift
/// An AppModel wired to a temporary home, temporary backups and fake ssh validation.
@MainActor
func makeTestModel(_ tmp: TempDir, config: String? = nil, runner: FixedRunner = .valid) -> AppModel {
    if let config { _ = try? tmp.file(".ssh/config", config) }
    let defaults = UserDefaults(suiteName: "SSHConfigManagerTests-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults, homeDirectory: tmp.url)
    return AppModel(settings: settings, backupRoot: tmp.url.appending(path: "Backups")) { url, backups in
        ConfigStore(
            fileURL: url,
            writer: SafeFileWriter(backups: backups),
            validator: ConfigValidator(runner: runner),
            includeResolver: IncludeResolver(homeDirectory: tmp.url),
            watchForChanges: false)
    }
}
```

- [ ] **Step 2: Başarısız testleri yaz**

`SSHConfigManagerTests/AppModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct AppModelTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)")!
    }

    @Test func settingsDefaultsAndPersistence() throws {
        let tmp = try TempDir()
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, homeDirectory: tmp.url)
        #expect(settings.configPath == "~/.ssh/config")
        #expect(settings.backupCount == 10)
        #expect(settings.configURL == tmp.url.appending(path: ".ssh/config"))

        settings.setConfigPath("~/dotfiles/ssh/config")
        settings.setBackupCount(99)
        let reloaded = AppSettings(defaults: defaults, homeDirectory: tmp.url)
        #expect(reloaded.configPath == "~/dotfiles/ssh/config")
        #expect(reloaded.backupCount == 50)
    }

    @Test func expandAndDisplayPaths() throws {
        let home = URL(filePath: "/Users/test")
        #expect(AppSettings.expand("~", home: home) == home)
        #expect(AppSettings.expand("~/a/b", home: home) == home.appending(path: "a/b"))
        #expect(AppSettings.expand("/etc/ssh/x", home: home) == URL(filePath: "/etc/ssh/x"))
        let settings = AppSettings(defaults: freshDefaults(), homeDirectory: home)
        #expect(settings.displayPath(for: home.appending(path: ".ssh/config")) == "~/.ssh/config")
        #expect(settings.displayPath(for: URL(filePath: "/opt/x")) == "/opt/x")
    }

    @Test func modelLoadsConfiguredFile() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        #expect(model.store.loadState == .loaded)
        #expect(model.store.document.hosts.map(\.alias) == ["a"])
        #expect(model.commandBuilder.usesDefaultConfig)
    }

    @Test func switchingConfigWithUnsavedChangesNeedsConfirmation() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        try tmp.file("other/config", "Host b\n")
        try model.store.apply { _ = try $0.addHost(HostDraft(patterns: ["new"])) }
        let original = model.store

        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path) == .needsConfirmation)
        #expect(model.store === original)
        #expect(model.settings.configPath == "~/.ssh/config")

        #expect(model.switchConfig(to: tmp.url.appending(path: "other/config").path, discardingUnsavedChanges: true) == .switched)
        #expect(model.store.document.hosts.map(\.alias) == ["b"])
        #expect(model.selection == nil)
        #expect(!model.commandBuilder.usesDefaultConfig)
    }

    @Test func switchingToTheSameFileIsUnchanged() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let original = model.store
        #expect(model.switchConfig(to: "~/.ssh/config") == .unchanged)
        #expect(model.store === original)
    }

    @Test func backupCountReachesStoreAndManager() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        model.setBackupCount(3)
        #expect(model.settings.backupCount == 3)
        #expect(model.backupManager.keep == 3)
        #expect(model.store.backupKeep == 3)
    }

    @Test func selectionTokens() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host a\n")
        let first = model.editorToken
        model.select(.host(alias: "a", occurrence: 0))
        let afterSelect = model.editorToken
        #expect(afterSelect != first)
        model.followRename(to: .host(alias: "b", occurrence: 0))
        #expect(model.selection == .host(alias: "b", occurrence: 0))
        #expect(model.editorToken == afterSelect)   // rename keeps the editor alive
        model.resetEditor()
        #expect(model.editorToken != afterSelect)
    }
}
```

- [ ] **Step 3: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/AppModelTests`
Expected: FAIL — `cannot find 'AppSettings' in scope`.

- [ ] **Step 4: Uygulamayı yaz**

`SSHConfigManager/Shared/TestEnvironment.swift`:

```swift
import Foundation

enum TestEnvironment {
    /// True when the app process hosts unit tests; the app then never touches the real ~/.ssh.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
```

`SSHConfigManager/Features/HostList/SidebarModel.swift` (Task 4 bu dosyayı genişletir):

```swift
import Foundation

/// Stable identity of a sidebar row. Hosts are identified by alias + occurrence, not by line
/// number, so edits above a host do not change which row is selected.
enum SidebarItem: Hashable, Sendable {
    case host(alias: String, occurrence: Int)
    case included(id: String)
    case match(index: Int)
}
```

`SSHConfigManager/Shared/AppSettings.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let defaultConfigPath = "~/.ssh/config"
    static let defaultBackupCount = 10
    static let backupCountRange = 1...50

    private enum Keys {
        static let configPath = "configPath"
        static let backupCount = "backupCount"
    }

    @ObservationIgnored private let defaults: UserDefaults
    let homeDirectory: URL
    private(set) var configPath: String
    private(set) var backupCount: Int

    init(defaults: UserDefaults = .standard, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        configPath = defaults.string(forKey: Keys.configPath) ?? Self.defaultConfigPath
        backupCount = Self.clamp(defaults.object(forKey: Keys.backupCount) as? Int ?? Self.defaultBackupCount)
    }

    var configURL: URL { Self.expand(configPath, home: homeDirectory) }

    func setConfigPath(_ path: String) {
        configPath = path
        defaults.set(path, forKey: Keys.configPath)
    }

    func setBackupCount(_ count: Int) {
        backupCount = Self.clamp(count)
        defaults.set(backupCount, forKey: Keys.backupCount)
    }

    /// Shows paths under the home directory with a leading "~".
    func displayPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func expand(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))) }
        return URL(filePath: path)
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, backupCountRange.lowerBound), backupCountRange.upperBound)
    }
}
```

`SSHConfigManager/Shared/AppModel.swift`:

```swift
import Foundation
import Observation
import SSHConfigKit

@MainActor
@Observable
final class AppModel {
    typealias StoreFactory = @MainActor (URL, BackupManager) -> ConfigStore

    enum SwitchResult: Equatable { case switched, needsConfirmation, unchanged }

    let settings: AppSettings
    private(set) var store: ConfigStore
    private(set) var backupManager: BackupManager
    var selection: SidebarItem?
    /// Changes when the user picks another row (or the document is reloaded); the editor view
    /// is keyed by it so renaming a host in place does not rebuild the form.
    private(set) var editorToken = UUID()
    var searchText = ""
    var errorMessage: String?

    @ObservationIgnored private let makeStore: StoreFactory

    init(settings: AppSettings, backupRoot: URL = BackupManager.defaultRoot, makeStore: @escaping StoreFactory = AppModel.liveStore) {
        self.settings = settings
        let backups = BackupManager(rootDirectory: backupRoot, keep: settings.backupCount)
        self.backupManager = backups
        self.makeStore = makeStore
        self.store = makeStore(settings.configURL, backups)
    }

    static func liveStore(url: URL, backups: BackupManager) -> ConfigStore {
        ConfigStore(fileURL: url, writer: SafeFileWriter(backups: backups))
    }

    var commandBuilder: SSHCommandBuilder {
        SSHCommandBuilder(configFile: store.fileURL, homeDirectory: settings.homeDirectory)
    }

    func select(_ item: SidebarItem?) {
        selection = item
        editorToken = UUID()
    }

    /// Called by the editor after it renamed the selected host.
    func followRename(to item: SidebarItem) {
        selection = item
    }

    func resetEditor() {
        editorToken = UUID()
    }

    func switchConfig(to path: String, discardingUnsavedChanges: Bool = false) -> SwitchResult {
        let url = AppSettings.expand(path, home: settings.homeDirectory)
        if url.standardizedFileURL == store.fileURL.standardizedFileURL {
            settings.setConfigPath(path)
            return .unchanged
        }
        if store.hasUnsavedChanges && !discardingUnsavedChanges { return .needsConfirmation }
        settings.setConfigPath(path)
        store = makeStore(url, backupManager)
        select(nil)
        return .switched
    }

    func setBackupCount(_ count: Int) {
        settings.setBackupCount(count)
        backupManager.keep = settings.backupCount
        store.setBackupKeep(settings.backupCount)
    }
}
```

`SSHConfigManagerApp.swift` — modeli oluştur; test host'ta gerçek config'e dokunma:

```swift
import SwiftUI

@main
struct SSHConfigManagerApp: App {
    @State private var model: AppModel = SSHConfigManagerApp.makeModel()

    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            ContentUnavailableView(
                String(localized: "detail.empty.title"),
                systemImage: "server.rack",
                description: Text(String(localized: "detail.empty.message")))
                .frame(minWidth: 720, minHeight: 440)
        }
    }

    @MainActor
    private static func makeModel() -> AppModel {
        guard TestEnvironment.isRunningTests else { return AppModel(settings: AppSettings()) }
        // Unit tests are hosted by the app: use a throwaway home so the real ~/.ssh is never read.
        let home = FileManager.default.temporaryDirectory.appending(path: "SSHConfigManagerTestHost-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "SSHConfigManagerTestHost")!
        return AppModel(settings: AppSettings(defaults: defaults, homeDirectory: home),
                        backupRoot: home.appending(path: "Backups"))
    }
}
```

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/AppModelTests`
Expected: PASS. Ardından `scripts/test-app.sh` — tüm testler yeşil.

- [ ] **Step 6: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): AppSettings ve AppModel (config değiştirme, yedek sayısı, seçim)"
```

---

### Task 4: Kenar çubuğu modeli (`SidebarBuilder`)

**Files:**
- Modify: `SSHConfigManager/Features/HostList/SidebarModel.swift`
- Test: `SSHConfigManagerTests/SidebarBuilderTests.swift`

**Interfaces:**
- Consumes: `SidebarItem` (Task 3); `ConfigDocument`, `HostEntry`, `IncludedHost`, `MatchEntry`.
- Produces:
  - `struct SidebarRow: Identifiable, Hashable, Sendable { let item: SidebarItem; let title: String; let subtitle: String; var id: SidebarItem }`
  - `struct SidebarSections: Equatable, Sendable { var hosts, patterns, included, matches: [SidebarRow] }`
  - `enum SidebarBuilder` — `static func sections(document:included:search:) -> SidebarSections`, `static func hostEntry(for:in:) -> HostEntry?`, `static func item(forHeader:in:) -> SidebarItem?`, `static func includedHost(for:in:) -> IncludedHost?`, `static func matchEntry(for:in:) -> MatchEntry?`, `static func subtitle(for:) -> String`.

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/SidebarBuilderTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

struct SidebarBuilderTests {
    let doc = ConfigDocument(parsing: """
    Host web
      HostName 10.0.0.1
      User deploy
    Host web
      HostName 10.0.0.2
    Host db
      HostName db.İstanbul.example
      User Gökhan
    Host *.prod
      User ops
    Match host x
      Port 2200

    """)

    let included = [IncludedHost(
        file: URL(filePath: "/h/.ssh/config.d/work"),
        entry: HostEntry(headerLine: 0, patterns: ["vpn"], directives: [HostDirective(line: 1, key: "HostName", value: "vpn.example")]))]

    @Test func groupsRowsBySection() {
        let sections = SidebarBuilder.sections(document: doc, included: included, search: "")
        #expect(sections.hosts.map(\.item) == [
            .host(alias: "web", occurrence: 0), .host(alias: "web", occurrence: 1), .host(alias: "db", occurrence: 0),
        ])
        #expect(sections.patterns.map(\.title) == ["*.prod"])
        #expect(sections.included.map(\.item) == [.included(id: "/h/.ssh/config.d/work#0")])
        #expect(sections.included.first?.subtitle == "work")
        #expect(sections.matches.map(\.item) == [.match(index: 0)])
        #expect(sections.matches.first?.title == "Match host x")
    }

    @Test func subtitles() {
        let sections = SidebarBuilder.sections(document: doc, included: [], search: "")
        #expect(sections.hosts.map(\.subtitle) == ["deploy@10.0.0.1", "10.0.0.2", "Gökhan@db.İstanbul.example"])
    }

    @Test func duplicateAliasesResolveToTheirOwnBlocks() throws {
        let second = try #require(SidebarBuilder.hostEntry(for: .host(alias: "web", occurrence: 1), in: doc))
        #expect(second.value(for: "HostName") == "10.0.0.2")
        #expect(SidebarBuilder.item(forHeader: second.headerLine, in: doc) == .host(alias: "web", occurrence: 1))
        #expect(SidebarBuilder.hostEntry(for: .host(alias: "web", occurrence: 2), in: doc) == nil)
    }

    @Test(arguments: [
        ("deploy", ["web"]),
        ("10.0.0", ["web", "web"]),
        ("gokhan", ["db"]),          // diacritic-insensitive
        ("istanbul", ["db"]),        // case/diacritic-insensitive on İ
        ("WEB", ["web", "web"]),
        ("   ", ["web", "web", "db"]),
    ])
    func searchFiltersHosts(query: String, expected: [String]) {
        let sections = SidebarBuilder.sections(document: doc, included: [], search: query)
        #expect(sections.hosts.map(\.title) == expected)
    }

    @Test func searchAlsoFiltersPatternsIncludedAndMatches() {
        let sections = SidebarBuilder.sections(document: doc, included: included, search: "vpn")
        #expect(sections.hosts.isEmpty)
        #expect(sections.patterns.isEmpty)
        #expect(sections.included.count == 1)
        #expect(sections.matches.isEmpty)
    }

    @Test func lookupHelpers() {
        #expect(SidebarBuilder.includedHost(for: .included(id: "/h/.ssh/config.d/work#0"), in: included)?.entry.alias == "vpn")
        #expect(SidebarBuilder.matchEntry(for: .match(index: 0), in: doc)?.criteria == "host x")
        #expect(SidebarBuilder.matchEntry(for: .match(index: 5), in: doc) == nil)
        #expect(SidebarBuilder.hostEntry(for: .match(index: 0), in: doc) == nil)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/SidebarBuilderTests`
Expected: FAIL — `cannot find 'SidebarBuilder' in scope`.

- [ ] **Step 3: Uygulamayı yaz** (`SidebarModel.swift`'te `SidebarItem`'ın altına ekle; dosyanın başına `import SSHConfigKit` ekle)

```swift
struct SidebarRow: Identifiable, Hashable, Sendable {
    let item: SidebarItem
    let title: String
    let subtitle: String
    var id: SidebarItem { item }
}

struct SidebarSections: Equatable, Sendable {
    var hosts: [SidebarRow] = []
    var patterns: [SidebarRow] = []
    var included: [SidebarRow] = []
    var matches: [SidebarRow] = []
}

enum SidebarBuilder {
    static func sections(document: ConfigDocument, included: [IncludedHost], search: String) -> SidebarSections {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = SidebarSections()

        var seen: [String: Int] = [:]
        for entry in document.hosts {
            let occurrence = seen[entry.alias, default: 0]
            seen[entry.alias] = occurrence + 1
            guard matches(entry, query: query) else { continue }
            let row = SidebarRow(
                item: .host(alias: entry.alias, occurrence: occurrence),
                title: entry.patterns.joined(separator: " "),
                subtitle: subtitle(for: entry))
            if entry.isPattern {
                result.patterns.append(row)
            } else {
                result.hosts.append(row)
            }
        }

        for host in included where matches(host.entry, query: query) {
            result.included.append(SidebarRow(
                item: .included(id: host.id),
                title: host.entry.patterns.joined(separator: " "),
                subtitle: host.file.lastPathComponent))
        }

        for (index, match) in document.matches.enumerated()
        where query.isEmpty || match.criteria.localizedStandardContains(query) {
            // "Match" is an ssh keyword and is not translated.
            result.matches.append(SidebarRow(item: .match(index: index), title: "Match " + match.criteria, subtitle: ""))
        }
        return result
    }

    static func subtitle(for entry: HostEntry) -> String {
        let host = entry.value(for: "HostName") ?? ""
        if let user = entry.value(for: "User"), !user.isEmpty, !host.isEmpty { return "\(user)@\(host)" }
        return host
    }

    static func hostEntry(for item: SidebarItem, in document: ConfigDocument) -> HostEntry? {
        guard case .host(let alias, let occurrence) = item else { return nil }
        let candidates = document.hosts.filter { $0.alias == alias }
        return candidates.indices.contains(occurrence) ? candidates[occurrence] : nil
    }

    static func item(forHeader header: Int, in document: ConfigDocument) -> SidebarItem? {
        guard let entry = document.hostEntry(at: header) else { return nil }
        let occurrence = document.hosts.filter { $0.alias == entry.alias && $0.headerLine < header }.count
        return .host(alias: entry.alias, occurrence: occurrence)
    }

    static func includedHost(for item: SidebarItem, in included: [IncludedHost]) -> IncludedHost? {
        guard case .included(let id) = item else { return nil }
        return included.first { $0.id == id }
    }

    static func matchEntry(for item: SidebarItem, in document: ConfigDocument) -> MatchEntry? {
        guard case .match(let index) = item else { return nil }
        let matches = document.matches
        return matches.indices.contains(index) ? matches[index] : nil
    }

    private static func matches(_ entry: HostEntry, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = entry.patterns + [entry.value(for: "HostName"), entry.value(for: "User")].compactMap { $0 }
        return fields.contains { $0.localizedStandardContains(query) }
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/SidebarBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): kenar çubuğu modeli (bölümler, arama, alias+sıra kimliği)"
```

---

### Task 5: Host düzenleyici modeli ve host komutları

**Files:**
- Create: `SSHConfigManager/Features/HostList/HostEditorModel.swift`
- Create: `SSHConfigManager/Features/HostList/HostCommands.swift`
- Test: `SSHConfigManagerTests/HostEditorModelTests.swift`
- Test: `SSHConfigManagerTests/HostCommandsTests.swift`

**Interfaces:**
- Consumes: `SidebarItem`, `SidebarBuilder` (Task 3–4); `ConfigStore.apply`, `HostDraft`, `DraftDirective`, `HostDraftValidator`, `DraftIssue`, `ConfigEditError`, `SSHCommandBuilder`.
- Produces:
  - `@MainActor @Observable final class HostEditorModel` — `static let fieldKeys = ["HostName", "User", "Port", "ProxyJump", "ForwardAgent"]`; `init?(item: SidebarItem, store: ConfigStore, homeDirectory: URL)`; `private(set) var item: SidebarItem`; `var aliasText: String`; `var fields: [String: String]`; `var identityFiles: [String]`; `var otherOptions: [DraftDirective]`; `private(set) var issues: [DraftIssue]`; `private(set) var editError: ConfigEditError?`; `var draft: HostDraft`; `var hasBlockingIssues: Bool`; `@discardableResult func commit() -> Bool`; `nonisolated static func identityFileExists(_ value: String, home: URL) -> Bool`.
  - `@MainActor enum HostCommands` — `static func uniqueAlias(_ base: String, in document: ConfigDocument) -> String`, `static func addHost(to store: ConfigStore) throws -> SidebarItem`, `static func duplicate(_ item: SidebarItem, in store: ConfigStore) throws -> SidebarItem?`, `static func delete(_ item: SidebarItem, in store: ConfigStore) throws`, `static func sshCommand(for item: SidebarItem, document: ConfigDocument, builder: SSHCommandBuilder) -> String?`.

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/HostEditorModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct HostEditorModelTests {
    private func model(_ tmp: TempDir, _ config: String) -> AppModel {
        makeTestModel(tmp, config: config)
    }

    @Test func populatesFieldsFromEntry() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web w2\n  hostname 10.0.0.1\n  User deploy\n  IdentityFile ~/.ssh/a\n  IdentityFile ~/.ssh/b\n  ServerAliveInterval 30\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        #expect(editor.aliasText == "web w2")
        #expect(editor.fields["HostName"] == "10.0.0.1")
        #expect(editor.fields["User"] == "deploy")
        #expect(editor.fields["Port"] == "")
        #expect(editor.identityFiles == ["~/.ssh/a", "~/.ssh/b"])
        #expect(editor.otherOptions == [DraftDirective(key: "ServerAliveInterval", value: "30")])
    }

    @Test func editingAFieldWritesOnlyThatLine() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n\thostname  old # prod\n  User deploy\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.fields["HostName"] = "new.example"
        #expect(editor.commit())
        #expect(app.store.document.render() == "Host web\n\thostname  new.example # prod\n  User deploy\n")
        #expect(app.store.hasUnsavedChanges)
    }

    @Test func renamingFollowsTheItem() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\nHost db\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.aliasText = "web-prod"
        #expect(editor.commit())
        #expect(editor.item == .host(alias: "web-prod", occurrence: 0))
        #expect(app.store.document.hosts.map(\.alias) == ["web-prod", "db"])
    }

    @Test func secondOfDuplicateAliasesIsEditedInPlace() throws {
        let tmp = try TempDir()
        let original = "Host web\n  HostName one\nHost web\n  HostName two\n"
        let app = model(tmp, original)
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 1), store: app.store, homeDirectory: tmp.url))
        #expect(editor.fields["HostName"] == "two")

        // While the alias is still duplicated, edits are blocked and nothing is written.
        editor.fields["HostName"] = "three"
        #expect(!editor.commit())
        #expect(editor.issues.contains(.duplicateAlias("web")))
        #expect(app.store.document.render() == original)

        // Renaming resolves it; only the second block changes.
        editor.aliasText = "web-2"
        #expect(editor.commit())
        #expect(app.store.document.render() == "Host web\n  HostName one\nHost web-2\n  HostName three\n")
        #expect(editor.item == .host(alias: "web-2", occurrence: 0))
    }

    @Test func blockingIssuesPreventWrites() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\nHost db\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))

        editor.fields["Port"] = "99999"
        #expect(!editor.commit())
        #expect(editor.issues == [.invalidPort("99999")])

        editor.fields["Port"] = ""
        editor.aliasText = "db"
        #expect(!editor.commit())
        #expect(editor.issues == [.duplicateAlias("db")])
        #expect(app.store.document.render() == "Host web\n  User u\nHost db\n")
    }

    @Test func pastedLineBreakIsBlocked() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  User u\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.fields["User"] = "x\nHost evil"
        #expect(!editor.commit())
        #expect(editor.issues.contains(.controlCharacter("User")))
        #expect(app.store.document.render() == "Host web\n  User u\n")
    }

    @Test func missingIdentityFileIsOnlyAWarning() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.identityFiles = ["~/.ssh/missing"]
        #expect(editor.commit())
        #expect(editor.issues == [.identityFileMissing("~/.ssh/missing")])
        #expect(app.store.document.render() == "Host web\n    IdentityFile ~/.ssh/missing\n")
    }

    @Test func otherOptionsAndEmptyRows() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  ServerAliveInterval 30\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        editor.otherOptions = [DraftDirective(key: "ServerAliveInterval", value: "60"), DraftDirective(key: "", value: "")]
        #expect(editor.commit())
        #expect(app.store.document.render() == "Host web\n  ServerAliveInterval 60\n")
    }

    @Test func forwardAgentEmptyMeansUnset() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Host web\n  ForwardAgent yes\n")
        let editor = try #require(HostEditorModel(item: .host(alias: "web", occurrence: 0), store: app.store, homeDirectory: tmp.url))
        #expect(editor.fields["ForwardAgent"] == "yes")
        editor.fields["ForwardAgent"] = ""
        #expect(editor.commit())
        #expect(app.store.document.render() == "Host web\n")
    }

    @Test func nonHostItemsHaveNoEditor() throws {
        let tmp = try TempDir()
        let app = model(tmp, "Match all\n")
        #expect(HostEditorModel(item: .match(index: 0), store: app.store, homeDirectory: tmp.url) == nil)
    }

    @Test func identityFileExistence() throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/id_ok", "")
        #expect(HostEditorModel.identityFileExists("~/.ssh/id_ok", home: tmp.url))
        #expect(!HostEditorModel.identityFileExists("~/.ssh/nope", home: tmp.url))
        #expect(HostEditorModel.identityFileExists(tmp.url.appending(path: ".ssh/id_ok").path, home: tmp.url))
        #expect(HostEditorModel.identityFileExists("relative/key", home: tmp.url))   // not checked
    }
}
```

`SSHConfigManagerTests/HostCommandsTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct HostCommandsTests {
    @Test func uniqueAliases() {
        let doc = ConfigDocument(parsing: "Host new-host\nHost new-host-2\nHost web\n")
        #expect(HostCommands.uniqueAlias("new-host", in: doc) == "new-host-3")
        #expect(HostCommands.uniqueAlias("other", in: doc) == "other")
        #expect(HostCommands.uniqueAlias("WEB", in: doc) == "WEB-2")   // ssh compares case-insensitively
    }

    @Test func addHostGoesBeforeHostStar() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n\nHost *\n  User d\n")
        let item = try HostCommands.addHost(to: app.store)
        #expect(item == .host(alias: "new-host", occurrence: 0))
        #expect(app.store.document.render() == "Host a\n\nHost new-host\n\nHost *\n  User d\n")
    }

    @Test func duplicateAndDelete() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n  User u\n")
        let copy = try #require(try HostCommands.duplicate(.host(alias: "web", occurrence: 0), in: app.store))
        #expect(copy == .host(alias: "web-copy", occurrence: 0))
        #expect(app.store.document.hosts.map(\.alias) == ["web", "web-copy"])

        try HostCommands.delete(.host(alias: "web", occurrence: 0), in: app.store)
        #expect(app.store.document.hosts.map(\.alias) == ["web-copy"])
        #expect(try HostCommands.duplicate(.match(index: 0), in: app.store) == nil)
    }

    @Test func sshCommandUsesBuilder() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host web\n")
        #expect(HostCommands.sshCommand(for: .host(alias: "web", occurrence: 0), document: app.store.document, builder: app.commandBuilder) == "ssh -- web")
        #expect(HostCommands.sshCommand(for: .match(index: 0), document: app.store.document, builder: app.commandBuilder) == nil)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/HostEditorModelTests -only-testing:SSHConfigManagerTests/HostCommandsTests`
Expected: FAIL — `cannot find 'HostEditorModel' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`SSHConfigManager/Features/HostList/HostEditorModel.swift`:

```swift
import Foundation
import Observation
import SSHConfigKit

/// Form state for one Host block. Every change is validated; drafts without blocking issues
/// are written into the store's in-memory document (the file itself changes only on Save).
@MainActor
@Observable
final class HostEditorModel {
    /// Directives with their own form field (IdentityFile is a list, everything else is "other options").
    static let fieldKeys = ["HostName", "User", "Port", "ProxyJump", "ForwardAgent"]

    let store: ConfigStore
    private(set) var item: SidebarItem
    var aliasText: String
    var fields: [String: String]
    var identityFiles: [String]
    var otherOptions: [DraftDirective]
    private(set) var issues: [DraftIssue] = []
    private(set) var editError: ConfigEditError?

    @ObservationIgnored private let validator: HostDraftValidator

    init?(item: SidebarItem, store: ConfigStore, homeDirectory: URL) {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return nil }
        self.store = store
        self.item = item
        aliasText = entry.patterns.joined(separator: " ")
        var fields: [String: String] = [:]
        for key in Self.fieldKeys { fields[key] = entry.value(for: key) ?? "" }
        self.fields = fields
        identityFiles = entry.values(for: "IdentityFile")
        let known = Set((Self.fieldKeys + ["IdentityFile"]).map { $0.lowercased() })
        otherOptions = entry.directives
            .filter { !known.contains($0.key.lowercased()) }
            .map { DraftDirective(key: $0.key, value: $0.value) }
        validator = HostDraftValidator(fileExists: { HostEditorModel.identityFileExists($0, home: homeDirectory) })
    }

    var draft: HostDraft {
        let patterns = aliasText.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var directives: [DraftDirective] = []
        for key in Self.fieldKeys {
            let value = (fields[key] ?? "").trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { directives.append(DraftDirective(key: key, value: value)) }
        }
        for file in identityFiles {
            let value = file.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { directives.append(DraftDirective(key: "IdentityFile", value: value)) }
        }
        for option in otherOptions where !(option.key.isEmpty && option.value.isEmpty) {
            directives.append(option)
        }
        return HostDraft(patterns: patterns, directives: directives)
    }

    var hasBlockingIssues: Bool { issues.contains(where: \.isBlocking) }

    /// Validates the draft and, when nothing blocks it, applies it to the document.
    /// Returns true when the document reflects the draft afterwards.
    @discardableResult
    func commit() -> Bool {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else {
            editError = .hostNotFound(-1)
            return false
        }
        let draft = self.draft
        issues = validator.issues(for: draft, in: store.document, editing: entry.headerLine)
        guard !hasBlockingIssues else { return false }
        do {
            try store.apply { try $0.updateHost(at: entry.headerLine, to: draft) }
            editError = nil
            if let renamed = SidebarBuilder.item(forHeader: entry.headerLine, in: store.document) {
                item = renamed
            }
            return true
        } catch let error as ConfigEditError {
            editError = error
            return false
        } catch {
            return false
        }
    }

    /// `~/…` and absolute paths are checked; relative paths and `%` tokens are not.
    nonisolated static func identityFileExists(_ value: String, home: URL) -> Bool {
        let path: String
        if value.hasPrefix("~/") {
            path = home.appending(path: String(value.dropFirst(2))).path
        } else if value.hasPrefix("/") {
            path = value
        } else {
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }
}
```

`SSHConfigManager/Features/HostList/HostCommands.swift`:

```swift
import Foundation
import SSHConfigKit

@MainActor
enum HostCommands {
    /// `base`, or `base-2`, `base-3` … — compared case-insensitively like ssh does.
    static func uniqueAlias(_ base: String, in document: ConfigDocument) -> String {
        let taken = Set(document.hosts.flatMap(\.patterns).map { $0.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var counter = 2
        while taken.contains("\(base)-\(counter)".lowercased()) { counter += 1 }
        return "\(base)-\(counter)"
    }

    static func addHost(to store: ConfigStore) throws -> SidebarItem {
        var header = 0
        let alias = uniqueAlias("new-host", in: store.document)
        try store.apply { header = try $0.addHost(HostDraft(patterns: [alias])) }
        return SidebarBuilder.item(forHeader: header, in: store.document) ?? .host(alias: alias, occurrence: 0)
    }

    static func duplicate(_ item: SidebarItem, in store: ConfigStore) throws -> SidebarItem? {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return nil }
        let alias = uniqueAlias(entry.alias + "-copy", in: store.document)
        var header = 0
        try store.apply { header = try $0.duplicateHost(at: entry.headerLine, newAlias: alias) }
        return SidebarBuilder.item(forHeader: header, in: store.document)
    }

    static func delete(_ item: SidebarItem, in store: ConfigStore) throws {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document) else { return }
        try store.apply { try $0.removeHost(at: entry.headerLine) }
    }

    static func sshCommand(for item: SidebarItem, document: ConfigDocument, builder: SSHCommandBuilder) -> String? {
        guard let entry = SidebarBuilder.hostEntry(for: item, in: document), !entry.isPattern else { return nil }
        return builder.shellCommand(alias: entry.alias)
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/HostEditorModelTests -only-testing:SSHConfigManagerTests/HostCommandsTests`
Expected: PASS. (Bir beklenen render metni farklı çıkarsa — ör. yeni satırın girintisi — beklentiyi değiştirmeden önce farkı raporla; girinti kuralı Plan 1 Task 4'te tanımlıdır.)

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): host düzenleyici modeli ve host komutları"
```

---

### Task 6: Mesajlar (hata ve durumların yerelleştirilmiş metinleri)

**Files:**
- Create: `SSHConfigManager/Shared/Messages.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Test: `SSHConfigManagerTests/MessagesTests.swift`

**Interfaces:**
- Consumes: `DraftIssue`, `ConfigEditError`, `ConfigStoreError`, `SafeFileWriterError`, `ConfigLoadState`, `ValidationOutcome`.
- Produces: `enum Messages` — `static func text(for issue: DraftIssue) -> String`, `text(for error: ConfigEditError) -> String`, `text(for error: ConfigStoreError) -> String`, `text(for state: ConfigLoadState) -> String?` (`.loaded` → nil), `text(for outcome: ValidationOutcome) -> String`, `text(for error: any Error) -> String`.

Katalog anahtarları (Task 2'deki kurala göre ekle):

| anahtar | en | tr |
|---|---|---|
| `issue.controlCharacter %@` | “%@” contains a line break or control character. | “%@” satır sonu veya kontrol karakteri içeriyor. |
| `issue.emptyAlias` | The alias cannot be empty. | Alias boş olamaz. |
| `issue.aliasHasWhitespace` | The alias cannot contain spaces. | Alias boşluk içeremez. |
| `issue.duplicateAlias %@` | Another host already uses “%@”. | “%@” başka bir host tarafından kullanılıyor. |
| `issue.invalidPort %@` | “%@” is not a valid port (1–65535). | “%@” geçerli bir port değil (1–65535). |
| `issue.invalidDirectiveKey %@` | “%@” is not a valid option name. | “%@” geçerli bir seçenek adı değil. |
| `issue.forbiddenDirectiveKey %@` | “%@” cannot be added as an option here. | “%@” burada seçenek olarak eklenemez. |
| `issue.emptyDirectiveValue %@` | “%@” needs a value. | “%@” için bir değer gerekli. |
| `issue.identityFileMissing %@` | Key file not found: %@ | Anahtar dosyası bulunamadı: %@ |
| `edit.hostNotFound` | This host no longer exists in the file. | Bu host artık dosyada yok. |
| `edit.controlCharacter` | Values cannot contain line breaks or control characters. | Değerler satır sonu veya kontrol karakteri içeremez. |
| `edit.invalidAlias %@` | “%@” is not a valid alias. | “%@” geçerli bir alias değil. |
| `store.notEditable` | The file can't be edited in its current state. | Dosya şu anki durumunda düzenlenemez. |
| `store.conflict` | The file was changed by another program. | Dosya başka bir program tarafından değiştirildi. |
| `store.validationFailed %@` | ssh rejected the configuration:\n%@ | ssh yapılandırmayı reddetti:\n%@ |
| `store.validationTimedOut` | Validation with ssh timed out. | ssh ile doğrulama zaman aşımına uğradı. |
| `store.backupFailed %@` | The backup could not be created, so nothing was written: %@ | Yedek oluşturulamadığı için hiçbir şey yazılmadı: %@ |
| `store.writeFailed %@` | The file could not be written: %@ | Dosya yazılamadı: %@ |
| `store.saveCancelled` | Saving was cancelled because the file was reloaded. | Dosya yeniden yüklendiği için kaydetme iptal edildi. |
| `store.saveInProgress` | A save is already in progress. | Zaten bir kaydetme işlemi sürüyor. |
| `store.validatorUnavailable %@` | ssh could not be run to validate the file: %@ | Dosyayı doğrulamak için ssh çalıştırılamadı: %@ |
| `load.missing` | The config file does not exist yet. | Config dosyası henüz yok. |
| `load.notUTF8` | The file is not valid UTF-8. It is shown read-only and will never be rewritten. | Dosya geçerli UTF-8 değil. Salt okunur gösteriliyor ve asla yeniden yazılmayacak. |
| `load.unreadable %@` | The file could not be read: %@ | Dosya okunamadı: %@ |
| `validation.valid` | ssh accepts this configuration. | ssh bu yapılandırmayı kabul ediyor. |
| `error.generic %@` | Unexpected error: %@ | Beklenmeyen hata: %@ |

(JSON'da `\n` kaçış dizisi olarak yazılır.)

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/MessagesTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

/// Tests run in the development language (English); Turkish completeness is covered by LocalizationTests.
struct MessagesTests {
    static let issues: [DraftIssue] = [
        .controlCharacter("User"), .emptyAlias, .aliasHasWhitespace, .duplicateAlias("web"),
        .invalidPort("99999"), .invalidDirectiveKey("Bad Key"), .forbiddenDirectiveKey("Host"),
        .emptyDirectiveValue("User"), .identityFileMissing("~/.ssh/x"),
    ]

    static let storeErrors: [ConfigStoreError] = [
        .notEditable, .conflict, .validationFailed("line 2: Bad configuration option: bogus"),
        .validationTimedOut, .writeFailed(.backupFailed("disk full")), .writeFailed(.writeFailed("EACCES")),
        .writeFailed(.conflict), .saveCancelled, .saveInProgress, .validatorUnavailable("no ssh"),
    ]

    @Test(arguments: issues)
    func everyIssueHasText(issue: DraftIssue) {
        let text = Messages.text(for: issue)
        #expect(!text.isEmpty)
        #expect(!text.hasPrefix("issue."), "anahtar katalogda bulunamadı: \(text)")
    }

    @Test(arguments: storeErrors)
    func everyStoreErrorHasText(error: ConfigStoreError) {
        let text = Messages.text(for: error)
        #expect(!text.isEmpty)
        #expect(!text.hasPrefix("store."))
    }

    @Test func payloadsAreIncluded() {
        #expect(Messages.text(for: DraftIssue.duplicateAlias("web")).contains("web"))
        #expect(Messages.text(for: ConfigStoreError.validationFailed("Bad port 'abc'")).contains("Bad port 'abc'"))
        #expect(Messages.text(for: ConfigStoreError.writeFailed(.backupFailed("disk full"))).contains("disk full"))
        #expect(Messages.text(for: ConfigEditError.invalidAlias("a b")).contains("a b"))
    }

    @Test func backupAndWriteFailuresAreDistinct() {
        let backup = Messages.text(for: ConfigStoreError.writeFailed(.backupFailed("x")))
        let write = Messages.text(for: ConfigStoreError.writeFailed(.writeFailed("x")))
        #expect(backup != write)
    }

    @Test func loadStatesAndOutcomes() {
        #expect(Messages.text(for: ConfigLoadState.loaded) == nil)
        #expect(Messages.text(for: ConfigLoadState.missing) != nil)
        #expect(Messages.text(for: ConfigLoadState.notUTF8) != nil)
        #expect(Messages.text(for: ConfigLoadState.unreadable("EPERM"))?.contains("EPERM") == true)
        #expect(Messages.text(for: ValidationOutcome.valid) != Messages.text(for: ValidationOutcome.timedOut))
        #expect(Messages.text(for: ValidationOutcome.invalid(message: "boom")).contains("boom"))
        #expect(Messages.text(for: ValidationOutcome.validatorUnavailable("nope")).contains("nope"))
    }

    @Test func editErrors() {
        for error: ConfigEditError in [.hostNotFound(0), .controlCharacter, .invalidDirectiveKey("a b"), .forbiddenDirectiveKey("Host"), .invalidAlias("x y")] {
            let text = Messages.text(for: error)
            #expect(!text.isEmpty && !text.hasPrefix("edit.") && !text.hasPrefix("issue."))
        }
    }

    @Test func genericErrorsRouteToSpecificTexts() {
        #expect(Messages.text(for: ConfigStoreError.conflict as any Error) == Messages.text(for: ConfigStoreError.conflict))
        struct Other: Error {}
        #expect(!Messages.text(for: Other() as any Error).isEmpty)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/MessagesTests`
Expected: FAIL — `cannot find 'Messages' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`SSHConfigManager/Shared/Messages.swift`:

```swift
import Foundation
import SSHConfigKit

/// Turns the package's typed results into localized, user-facing text.
enum Messages {
    static func text(for issue: DraftIssue) -> String {
        switch issue {
        case .controlCharacter(let field): String(localized: "issue.controlCharacter \(field)")
        case .emptyAlias: String(localized: "issue.emptyAlias")
        case .aliasHasWhitespace: String(localized: "issue.aliasHasWhitespace")
        case .duplicateAlias(let alias): String(localized: "issue.duplicateAlias \(alias)")
        case .invalidPort(let port): String(localized: "issue.invalidPort \(port)")
        case .invalidDirectiveKey(let key): String(localized: "issue.invalidDirectiveKey \(key)")
        case .forbiddenDirectiveKey(let key): String(localized: "issue.forbiddenDirectiveKey \(key)")
        case .emptyDirectiveValue(let key): String(localized: "issue.emptyDirectiveValue \(key)")
        case .identityFileMissing(let path): String(localized: "issue.identityFileMissing \(path)")
        }
    }

    static func text(for error: ConfigEditError) -> String {
        switch error {
        case .hostNotFound: String(localized: "edit.hostNotFound")
        case .controlCharacter: String(localized: "edit.controlCharacter")
        case .invalidDirectiveKey(let key): text(for: DraftIssue.invalidDirectiveKey(key))
        case .forbiddenDirectiveKey(let key): text(for: DraftIssue.forbiddenDirectiveKey(key))
        case .invalidAlias(let alias): String(localized: "edit.invalidAlias \(alias)")
        }
    }

    static func text(for error: ConfigStoreError) -> String {
        switch error {
        case .notEditable: String(localized: "store.notEditable")
        case .conflict, .writeFailed(.conflict): String(localized: "store.conflict")
        case .validationFailed(let message): String(localized: "store.validationFailed \(message)")
        case .validationTimedOut: String(localized: "store.validationTimedOut")
        case .writeFailed(.backupFailed(let detail)): String(localized: "store.backupFailed \(detail)")
        case .writeFailed(.writeFailed(let detail)): String(localized: "store.writeFailed \(detail)")
        case .saveCancelled: String(localized: "store.saveCancelled")
        case .saveInProgress: String(localized: "store.saveInProgress")
        case .validatorUnavailable(let detail): String(localized: "store.validatorUnavailable \(detail)")
        }
    }

    static func text(for state: ConfigLoadState) -> String? {
        switch state {
        case .loaded: nil
        case .missing: String(localized: "load.missing")
        case .notUTF8: String(localized: "load.notUTF8")
        case .unreadable(let detail): String(localized: "load.unreadable \(detail)")
        }
    }

    static func text(for outcome: ValidationOutcome) -> String {
        switch outcome {
        case .valid: String(localized: "validation.valid")
        case .invalid(let message): text(for: ConfigStoreError.validationFailed(message))
        case .timedOut: text(for: ConfigStoreError.validationTimedOut)
        case .validatorUnavailable(let detail): text(for: ConfigStoreError.validatorUnavailable(detail))
        }
    }

    static func text(for error: any Error) -> String {
        if let error = error as? ConfigStoreError { return text(for: error) }
        if let error = error as? ConfigEditError { return text(for: error) }
        let detail = error.localizedDescription
        return String(localized: "error.generic \(detail)")
    }
}
```

> `SafeFileWriterError` yeni bir case kazanırsa `switch` derleme hatası verir; bu bilinçlidir.

Kataloğa yukarıdaki tablodaki 26 anahtarı ekle.

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/MessagesTests -only-testing:SSHConfigManagerTests/LocalizationTests`
Expected: PASS (katalog ↔ kaynak tutarlılığı dahil).

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): hata ve durum mesajları (en/tr)"
```

---

### Task 7: Metin görünümleri (`CodeHighlighter`, `DiffPresenter`, `CodeTextView`, `DiffTextView`)

**Files:**
- Create: `SSHConfigManager/Shared/Text/CodeHighlighter.swift`
- Create: `SSHConfigManager/Shared/Text/DiffPresenter.swift`
- Create: `SSHConfigManager/Shared/Text/CodeTextView.swift`
- Create: `SSHConfigManager/Shared/Text/DiffTextView.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Test: `SSHConfigManagerTests/TextPresentationTests.swift`

**Interfaces:**
- Consumes: `ConfigLine`, `LineKind`, `DiffHunk`, `DiffLine`.
- Produces:
  - `enum HighlightRole: Equatable { case comment, keyword, key, value, unknown, plain }`, `struct HighlightSpan: Equatable { let text: String; let role: HighlightRole }`, `enum CodeHighlighter { static func spans(for line: ConfigLine) -> [HighlightSpan] }` (satır sonundaki `\r` atılır).
  - `struct DiffRow: Identifiable, Equatable { enum Kind { case header, context, added, removed, noNewline }; let id: Int; let kind: Kind; let oldNumber: Int?; let newNumber: Int?; let text: String; let accessibilityLabel: String }`, `enum DiffPresenter { static func rows(for hunks: [DiffHunk]) -> [DiffRow]; static func unifiedText(for hunks: [DiffHunk]) -> String }`.
  - `struct CodeTextView: View { init(lines: [ConfigLine]) }`, `struct DiffTextView: View { init(hunks: [DiffHunk]) }`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `diff.noNewline` | No newline at end of file | Dosya sonunda yeni satır yok |
| `diff.a11y.added %@ %@` | Line %@, added: %@ | Satır %@, eklendi: %@ |
| `diff.a11y.removed %@ %@` | Line %@, removed: %@ | Satır %@, silindi: %@ |
| `diff.a11y.context %@ %@` | Line %@: %@ | Satır %@: %@ |
| `text.copyAll` | Copy All | Tümünü Kopyala |
| `diff.empty` | No changes. | Değişiklik yok. |

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/TextPresentationTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

struct TextPresentationTests {
    @Test func highlightsDirective() {
        let spans = CodeHighlighter.spans(for: ConfigLine(raw: "  HostName = 10.0.0.1 # prod\r"))
        #expect(spans == [
            HighlightSpan(text: "  ", role: .plain),
            HighlightSpan(text: "HostName", role: .key),
            HighlightSpan(text: " = 10.0.0.1 # prod", role: .value),
        ])
    }

    @Test func highlightsKeywordsCommentsAndUnknown() {
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "Host web *.x")).map(\.role) == [.keyword, .value])
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "match host x")).first?.role == .keyword)
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "Include a/*")).first?.role == .keyword)
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "  # note")) == [HighlightSpan(text: "  # note", role: .comment)])
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "=bad")) == [HighlightSpan(text: "=bad", role: .unknown)])
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "\u{FEFF}Host bom")).first?.role == .unknown)
        #expect(CodeHighlighter.spans(for: ConfigLine(raw: "")) == [])
    }

    @Test func diffRowsStripCarriageReturnsAndMarkMissingNewline() throws {
        let hunks = LineDiff.hunks(old: "Host a\r\n  User u", new: "Host a\r\n  User v\n")
        let rows = DiffPresenter.rows(for: hunks)
        #expect(rows.first?.kind == .header)
        #expect(rows.first?.text == "@@ -1,2 +1,2 @@")
        #expect(rows.contains { $0.kind == .context && $0.text == "Host a" })
        let removedIndex = try #require(rows.firstIndex { $0.kind == .removed })
        #expect(rows[removedIndex].text == "  User u")
        #expect(rows[removedIndex + 1].kind == .noNewline)
        #expect(rows.contains { $0.kind == .added && $0.text == "  User v" && $0.newNumber == 2 })
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func accessibilityLabelsMentionLineAndText() {
        let rows = DiffPresenter.rows(for: LineDiff.hunks(old: "a\n", new: "b\n"))
        let added = rows.first { $0.kind == .added }
        #expect(added?.accessibilityLabel.contains("1") == true)
        #expect(added?.accessibilityLabel.contains("b") == true)
    }

    @Test func unifiedTextForCopying() {
        let hunks = LineDiff.hunks(old: "a\nb", new: "a\nc\n")
        #expect(DiffPresenter.unifiedText(for: hunks) == "@@ -1,2 +1,2 @@\n a\n-b\n\\ No newline at end of file\n+c\n")
        #expect(DiffPresenter.unifiedText(for: []) == "")
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/TextPresentationTests`
Expected: FAIL — `cannot find 'CodeHighlighter' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`SSHConfigManager/Shared/Text/CodeHighlighter.swift`:

```swift
import SSHConfigKit

enum HighlightRole: Equatable, Sendable { case comment, keyword, key, value, unknown, plain }

struct HighlightSpan: Equatable, Sendable {
    let text: String
    let role: HighlightRole
}

/// Colors follow the parser's own classification, so what is shown is what was understood.
enum CodeHighlighter {
    static func spans(for line: ConfigLine) -> [HighlightSpan] {
        var raw = line.raw
        if raw.unicodeScalars.last == "\r" { raw = String(raw.unicodeScalars.dropLast()) }
        guard !raw.isEmpty else { return [] }

        switch line.kind {
        case .blank:
            return [HighlightSpan(text: raw, role: .plain)]
        case .comment:
            return [HighlightSpan(text: raw, role: .comment)]
        case .unknown:
            return [HighlightSpan(text: raw, role: .unknown)]
        case .hostStart, .matchStart, .include:
            return split(raw, keyRole: .keyword)
        case .directive:
            return split(raw, keyRole: .key)
        }
    }

    /// indent (plain) + first token (keyRole) + rest (value)
    private static func split(_ raw: String, keyRole: HighlightRole) -> [HighlightSpan] {
        let scalars = Array(raw.unicodeScalars)
        var i = 0
        while i < scalars.count && (scalars[i] == " " || scalars[i] == "\t") { i += 1 }
        let indentEnd = i
        while i < scalars.count && scalars[i] != " " && scalars[i] != "\t" && scalars[i] != "=" { i += 1 }
        let keyEnd = i

        var spans: [HighlightSpan] = []
        if indentEnd > 0 { spans.append(HighlightSpan(text: string(scalars[0..<indentEnd]), role: .plain)) }
        spans.append(HighlightSpan(text: string(scalars[indentEnd..<keyEnd]), role: keyRole))
        if keyEnd < scalars.count { spans.append(HighlightSpan(text: string(scalars[keyEnd...]), role: .value)) }
        return spans
    }

    private static func string(_ slice: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: slice)
        return String(view)
    }
}
```

`SSHConfigManager/Shared/Text/DiffPresenter.swift`:

```swift
import SSHConfigKit

struct DiffRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case header, context, added, removed, noNewline }
    let id: Int
    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
    let accessibilityLabel: String
}

enum DiffPresenter {
    static func rows(for hunks: [DiffHunk]) -> [DiffRow] {
        var rows: [DiffRow] = []
        func append(_ kind: DiffRow.Kind, _ old: Int?, _ new: Int?, _ text: String, _ label: String) {
            rows.append(DiffRow(id: rows.count, kind: kind, oldNumber: old, newNumber: new, text: text, accessibilityLabel: label))
        }
        for hunk in hunks {
            append(.header, nil, nil, hunk.header, hunk.header)
            for line in hunk.lines {
                let text = stripCR(line.text)
                switch line.kind {
                case .context:
                    let number = String(line.newNumber ?? 0)
                    append(.context, line.oldNumber, line.newNumber, text, String(localized: "diff.a11y.context \(number) \(text)"))
                case .added:
                    let number = String(line.newNumber ?? 0)
                    append(.added, nil, line.newNumber, text, String(localized: "diff.a11y.added \(number) \(text)"))
                case .removed:
                    let number = String(line.oldNumber ?? 0)
                    append(.removed, line.oldNumber, nil, text, String(localized: "diff.a11y.removed \(number) \(text)"))
                }
                if line.missingNewline {
                    let note = String(localized: "diff.noNewline")
                    append(.noNewline, nil, nil, note, note)
                }
            }
        }
        return rows
    }

    /// Standard unified diff (not localized) for the "Copy All" button.
    static func unifiedText(for hunks: [DiffHunk]) -> String {
        var out = ""
        for hunk in hunks {
            out += hunk.header + "\n"
            for line in hunk.lines {
                let prefix = switch line.kind {
                case .context: " "
                case .added: "+"
                case .removed: "-"
                }
                out += prefix + stripCR(line.text) + "\n"
                if line.missingNewline { out += "\\ No newline at end of file\n" }
            }
        }
        return out
    }

    private static func stripCR(_ text: String) -> String {
        text.unicodeScalars.last == "\r" ? String(text.unicodeScalars.dropLast()) : text
    }
}
```

`SSHConfigManager/Shared/Text/CodeTextView.swift`:

```swift
import AppKit
import SSHConfigKit
import SwiftUI

/// Read-only, line-numbered, highlighted view of config lines.
struct CodeTextView: View {
    let lines: [ConfigLine]

    init(lines: [ConfigLine]) {
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "text.copyAll")) {
                    let text = lines.map(\.raw).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.borderless)
            }
            .padding(6)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(verbatim: String(index + 1))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 32, alignment: .trailing)
                            Text(Self.attributed(CodeHighlighter.spans(for: line)))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    static func attributed(_ spans: [HighlightSpan]) -> AttributedString {
        var result = AttributedString()
        for span in spans {
            var part = AttributedString(span.text)
            switch span.role {
            case .comment: part.foregroundColor = .secondary
            case .keyword: part.foregroundColor = .accentColor
            case .key: part.font = .system(.body, design: .monospaced).weight(.semibold)
            case .unknown: part.foregroundColor = .orange
            case .value, .plain: break
            }
            result += part
        }
        return result
    }
}
```

`SSHConfigManager/Shared/Text/DiffTextView.swift`:

```swift
import AppKit
import SSHConfigKit
import SwiftUI

/// Read-only unified diff with old/new line numbers and added/removed backgrounds.
struct DiffTextView: View {
    let hunks: [DiffHunk]

    init(hunks: [DiffHunk]) {
        self.hunks = hunks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "text.copyAll")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DiffPresenter.unifiedText(for: hunks), forType: .string)
                }
                .buttonStyle(.borderless)
                .disabled(hunks.isEmpty)
            }
            .padding(6)
            if hunks.isEmpty {
                Text(String(localized: "diff.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(DiffPresenter.rows(for: hunks)) { row in
                            DiffRowView(row: row)
                        }
                    }
                }
            }
        }
    }
}

private struct DiffRowView: View {
    let row: DiffRow

    var body: some View {
        HStack(spacing: 8) {
            number(row.oldNumber)
            number(row.newNumber)
            Text(verbatim: marker)
                .foregroundStyle(.secondary)
            Text(verbatim: row.text)
                .italic(row.kind == .noNewline)
                .foregroundStyle(row.kind == .header || row.kind == .noNewline ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal, 8)
        .background(background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var marker: String {
        switch row.kind {
        case .added: "+"
        case .removed: "-"
        case .context: " "
        case .header, .noNewline: ""
        }
    }

    private var background: Color {
        switch row.kind {
        case .added: .green.opacity(0.15)
        case .removed: .red.opacity(0.15)
        case .header: .secondary.opacity(0.08)
        case .context, .noNewline: .clear
        }
    }

    private func number(_ value: Int?) -> some View {
        Text(verbatim: value.map(String.init) ?? "")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 32, alignment: .trailing)
    }
}
```

Kataloğa yukarıdaki 6 anahtarı ekle.

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/TextPresentationTests -only-testing:SSHConfigManagerTests/LocalizationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): renkli kod ve diff görünümleri"
```

---

### Task 8: Kaydetme akışı modeli ve bant modeli

**Files:**
- Create: `SSHConfigManager/Features/HostList/SaveFlowModel.swift`
- Create: `SSHConfigManager/Features/HostList/BannerBuilder.swift`
- Test: `SSHConfigManagerTests/SaveFlowModelTests.swift`
- Test: `SSHConfigManagerTests/BannerBuilderTests.swift`

**Interfaces:**
- Consumes: `ConfigStore` (`prepareSave`, `save`, `discardChanges`, `hasUnsavedChanges`, `loadState`, `externalChangePending`, `isWatching`, `document.hasByteOrderMark`, `fileURL`, `diskText`), `LineDiff`, `Messages` (Task 6).
- Produces:
  - `@MainActor @Observable final class SaveFlowModel: Identifiable` — `enum Phase: Equatable { case preparing, review(SavePreparation), saving, conflict, failed(String), done }`; `let id = UUID()`; `private(set) var phase: Phase`; `init(store: ConfigStore)`; `var canConfirm: Bool`; `func prepare() async`; `func confirm() async`; `func overwrite() async`; `func loadDiskVersion()`; `func conflictHunks() -> [DiffHunk]`; `static func diskVersusMemory(_ store: ConfigStore) -> [DiffHunk]`.
  - `enum Banner: Hashable, Identifiable { case missingFile, notUTF8, unreadable(String), byteOrderMark, externalChange, notWatching; var id: Self }`, `@MainActor enum BannerBuilder { static func banners(for store: ConfigStore) -> [Banner] }`.

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/SaveFlowModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct SaveFlowModelTests {
    private func addPort(_ app: AppModel) throws {
        try app.store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives.append(DraftDirective(key: "Port", value: "2222"))
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
    }

    @Test func reviewThenSave() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        let flow = SaveFlowModel(store: app.store)
        #expect(flow.phase == .preparing)

        await flow.prepare()
        guard case .review(let preparation) = flow.phase else { Issue.record("review bekleniyordu"); return }
        #expect(preparation.validation == .valid)
        #expect(preparation.hunks.count == 1)
        #expect(flow.canConfirm)

        await flow.confirm()
        #expect(flow.phase == .done)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n  Port 2222\n")
    }

    @Test func invalidConfigCannotBeConfirmed() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n", runner: .invalid("line 2: Bad configuration option: bogus"))
        try addPort(app)
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        #expect(!flow.canConfirm)
        await flow.confirm()   // ignored while not confirmable
        #expect(try tmp.read(".ssh/config") == "Host a\n")
    }

    @Test func conflictOffersOverwriteOrDiskVersion() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        #expect(flow.phase == .conflict)
        #expect(!flow.conflictHunks().isEmpty)

        await flow.overwrite()
        #expect(flow.phase == .done)
        #expect(try tmp.read(".ssh/config") == "Host a\n  User u\n  Port 2222\n")
    }

    @Test func loadDiskVersionDiscardsMine() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n  User u\n")
        try addPort(app)
        try tmp.file(".ssh/config", "Host a\n  User vim\n")
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        flow.loadDiskVersion()
        #expect(flow.phase == .done)
        #expect(app.store.document.render() == "Host a\n  User vim\n")
        #expect(!app.store.hasUnsavedChanges)
    }

    @Test func failuresBecomeMessages() async throws {
        let tmp = try TempDir()
        try tmp.file("Backups", "not a directory")   // backup root is a file → backup fails
        let app = makeTestModel(tmp, config: "Host a\n")
        try addPort(app)
        let flow = SaveFlowModel(store: app.store)
        await flow.prepare()
        await flow.confirm()
        guard case .failed(let message) = flow.phase else { Issue.record("failed bekleniyordu: \(flow.phase)"); return }
        let template = Messages.text(for: ConfigStoreError.writeFailed(.backupFailed("§")))
        let fixedPart = try #require(template.components(separatedBy: "§").first)
        #expect(!fixedPart.isEmpty)
        #expect(message.hasPrefix(fixedPart))
        #expect(try tmp.read(".ssh/config") == "Host a\n")
    }
}
```

`SSHConfigManagerTests/BannerBuilderTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct BannerBuilderTests {
    @Test func missingFile() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp)
        #expect(BannerBuilder.banners(for: app.store) == [.missingFile, .notWatching])
    }

    @Test func notUTF8() throws {
        let tmp = try TempDir()
        try FileManager.default.createDirectory(at: tmp.url.appending(path: ".ssh"), withIntermediateDirectories: true)
        try Data([0x48, 0xFF]).write(to: tmp.url.appending(path: ".ssh/config"))
        let app = makeTestModel(tmp)
        #expect(BannerBuilder.banners(for: app.store).first == .notUTF8)
    }

    @Test func byteOrderMark() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "\u{FEFF}Host a\n")
        #expect(BannerBuilder.banners(for: app.store) == [.byteOrderMark, .notWatching])
    }

    @Test func externalChangeAppearsWithUnsavedEdits() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try app.store.apply { _ = try $0.addHost(HostDraft(patterns: ["b"])) }
        try tmp.file(".ssh/config", "Host z\n")
        // Simulate the watcher callback the same way ConfigStore does internally: a conflicting save.
        do { try await app.store.save() } catch {}
        #expect(BannerBuilder.banners(for: app.store).contains(.externalChange))
    }

    @Test func cleanLoadedFileWithWatcherHasNoBanners() throws {
        let tmp = try TempDir()
        try tmp.file(".ssh/config", "Host a\n")
        let defaults = UserDefaults(suiteName: "BannerBuilderTests-\(UUID().uuidString)")!
        let app = AppModel(settings: AppSettings(defaults: defaults, homeDirectory: tmp.url),
                           backupRoot: tmp.url.appending(path: "Backups")) { url, backups in
            ConfigStore(fileURL: url, writer: SafeFileWriter(backups: backups),
                        validator: ConfigValidator(runner: FixedRunner.valid),
                        includeResolver: IncludeResolver(homeDirectory: tmp.url), watchForChanges: true)
        }
        #expect(BannerBuilder.banners(for: app.store).isEmpty)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/SaveFlowModelTests -only-testing:SSHConfigManagerTests/BannerBuilderTests`
Expected: FAIL — `cannot find 'SaveFlowModel' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`SSHConfigManager/Features/HostList/SaveFlowModel.swift`:

```swift
import Foundation
import Observation
import SSHConfigKit

/// Drives the Save sheet: diff + `ssh -G` review, then save, with conflict resolution.
@MainActor
@Observable
final class SaveFlowModel: Identifiable {
    enum Phase: Equatable {
        case preparing
        case review(SavePreparation)
        case saving
        case conflict
        case failed(String)
        case done
    }

    let id = UUID()
    let store: ConfigStore
    private(set) var phase: Phase = .preparing

    init(store: ConfigStore) {
        self.store = store
    }

    var canConfirm: Bool {
        if case .review(let preparation) = phase { return preparation.validation == .valid }
        return false
    }

    func prepare() async {
        phase = .preparing
        phase = .review(await store.prepareSave())
    }

    func confirm() async {
        guard canConfirm else { return }
        await save(overwriting: false)
    }

    func overwrite() async {
        guard phase == .conflict else { return }
        await save(overwriting: true)
    }

    /// Discards the in-memory edits and loads what is on disk now.
    func loadDiskVersion() {
        store.discardChanges()
        phase = .done
    }

    /// Disk version (old) → my version (new), for the conflict view.
    func conflictHunks() -> [DiffHunk] {
        Self.diskVersusMemory(store)
    }

    static func diskVersusMemory(_ store: ConfigStore) -> [DiffHunk] {
        let disk = (try? Data(contentsOf: store.fileURL)).flatMap { String(validating: $0, as: UTF8.self) } ?? ""
        return LineDiff.hunks(old: disk, new: store.document.render())
    }

    private func save(overwriting: Bool) async {
        phase = .saving
        do {
            try await store.save(overwritingExternalChanges: overwriting)
            phase = .done
        } catch ConfigStoreError.conflict {
            phase = .conflict
        } catch {
            phase = .failed(Messages.text(for: error))
        }
    }
}
```

`SSHConfigManager/Features/HostList/BannerBuilder.swift`:

```swift
import SSHConfigKit

enum Banner: Hashable, Identifiable, Sendable {
    case missingFile
    case notUTF8
    case unreadable(String)
    case byteOrderMark
    case externalChange
    case notWatching

    var id: Self { self }
}

@MainActor
enum BannerBuilder {
    /// Most important first: load problems, then BOM, then external changes, then watcher status.
    static func banners(for store: ConfigStore) -> [Banner] {
        var banners: [Banner] = []
        switch store.loadState {
        case .missing: banners.append(.missingFile)
        case .notUTF8: banners.append(.notUTF8)
        case .unreadable(let detail): banners.append(.unreadable(detail))
        case .loaded:
            if store.document.hasByteOrderMark { banners.append(.byteOrderMark) }
        }
        if store.externalChangePending { banners.append(.externalChange) }
        if !store.isWatching { banners.append(.notWatching) }
        return banners
    }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/SaveFlowModelTests -only-testing:SSHConfigManagerTests/BannerBuilderTests`
Expected: PASS. (`notUTF8` testinde ikinci bant `.notWatching`'tir; `first` kontrol edilir.)

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): kaydetme akışı ve uyarı bandı modelleri"
```

---

### Task 9: Ana pencere (kenar çubuğu, form, bantlar, kaydetme sayfası, çıkış koruması)

**Files:**
- Create: `SSHConfigManager/App/AppDelegate.swift`
- Create: `SSHConfigManager/Features/HostList/MainWindow.swift`
- Create: `SSHConfigManager/Features/HostList/SidebarView.swift`
- Create: `SSHConfigManager/Features/HostList/DetailView.swift`
- Create: `SSHConfigManager/Features/HostList/HostEditorView.swift`
- Create: `SSHConfigManager/Features/HostList/BannerStack.swift`
- Create: `SSHConfigManager/Features/HostList/SaveSheet.swift`
- Modify: `SSHConfigManager/App/SSHConfigManagerApp.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Create: `docs/design/manual-test-checklist.md`

**Interfaces:**
- Consumes: `AppModel`, `SidebarBuilder`, `HostEditorModel`, `HostCommands`, `SaveFlowModel`, `BannerBuilder`, `Messages`, `CodeTextView`, `DiffTextView`.
- Produces: çalışan ana pencere. Bu görev yalnızca view kodu ve uygulama yaşam döngüsü içerir; otomatik UI testi yoktur (spec §11). Doğrulama: tüm testler yeşil (özellikle `LocalizationTests`) + manuel kontrol listesi.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `sidebar.search.prompt` | Search hosts | Host ara |
| `sidebar.section.hosts` | Hosts | Hostlar |
| `sidebar.section.patterns` | Patterns | Desenler |
| `sidebar.section.included` | Included | Dahil Edilen |
| `sidebar.section.match` | Match | Match |
| `toolbar.addHost` | Add Host | Host Ekle |
| `toolbar.unsaved` | Unsaved changes | Kaydedilmemiş değişiklikler |
| `action.save` | Save | Kaydet |
| `action.cancel` | Cancel | Vazgeç |
| `action.close` | Close | Kapat |
| `action.delete` | Delete | Sil |
| `action.duplicate` | Duplicate | Çoğalt |
| `action.copySSHCommand` | Copy SSH Command | SSH Komutunu Kopyala |
| `action.choose` | Choose… | Seç… |
| `action.discardAndQuit` | Don't Save | Kaydetme |
| `delete.confirm.title %@` | Delete “%@”? | “%@” silinsin mi? |
| `delete.confirm.message` | The host is removed from the file when you save. | Host, kaydettiğinizde dosyadan kaldırılır. |
| `quit.unsaved.title` | Do you want to save your changes? | Değişiklikleri kaydetmek istiyor musunuz? |
| `quit.unsaved.message` | Your changes will be lost if you don't save them. | Kaydetmezseniz değişiklikleriniz kaybolur. |
| `editor.alias` | Alias | Alias |
| `editor.section.connection` | Connection | Bağlantı |
| `editor.identityFiles` | Identity Files | Anahtar Dosyaları |
| `editor.identityFiles.add` | Add Key File | Anahtar Dosyası Ekle |
| `editor.otherOptions` | Other Options | Diğer Seçenekler |
| `editor.otherOptions.add` | Add Option | Seçenek Ekle |
| `editor.otherOptions.key` | Option | Seçenek |
| `editor.otherOptions.value` | Value | Değer |
| `editor.remove` | Remove | Kaldır |
| `editor.forwardAgent.unset` | Not set | Ayarlanmamış |
| `editor.issues` | Problems | Sorunlar |
| `help.HostName` | Real host name or IP address to connect to. | Bağlanılacak gerçek sunucu adı veya IP adresi. |
| `help.User` | User name on the server. | Sunucudaki kullanıcı adı. |
| `help.Port` | SSH port (default 22). | SSH portu (varsayılan 22). |
| `help.ProxyJump` | Jump host(s) to connect through. | Üzerinden bağlanılacak ara sunucu(lar). |
| `help.ForwardAgent` | Forward the local ssh-agent to the server. | Yerel ssh-agent'ı sunucuya ilet. |
| `included.readOnly %@` | Defined in %@ — read-only. | %@ dosyasında tanımlı — salt okunur. |
| `match.readOnly` | Match blocks are shown read-only. | Match blokları salt okunur gösterilir. |
| `banner.missing.create` | Create File | Dosya Oluştur |
| `banner.missing.choose` | Choose Another File… | Başka Dosya Seç… |
| `banner.bom` | This file starts with a byte order mark (BOM), which ssh cannot read. | Bu dosya ssh'in okuyamadığı bir bayt sıra işaretiyle (BOM) başlıyor. |
| `banner.bom.remove` | Remove BOM | BOM'u Kaldır |
| `banner.external.reload` | Reload | Yeniden Yükle |
| `banner.external.showDiff` | Show Difference | Farkı Göster |
| `banner.notWatching` | Changes made by other programs are not being detected. | Diğer programların yaptığı değişiklikler algılanmıyor. |
| `save.title` | Review Changes | Değişiklikleri İncele |
| `save.validating` | Validating with ssh… | ssh ile doğrulanıyor… |
| `save.saving` | Saving… | Kaydediliyor… |
| `save.failed.title` | Could Not Save | Kaydedilemedi |
| `conflict.title` | The File Changed on Disk | Dosya Diskte Değişti |
| `conflict.message` | Another program changed the file after it was opened. Choose which version to keep. | Dosya açıldıktan sonra başka bir program tarafından değiştirildi. Hangi sürümün kalacağını seçin. |
| `conflict.loadDisk` | Load Disk Version (Discard Mine) | Diskteki Sürümü Yükle (Benimkileri At) |
| `conflict.overwrite` | Overwrite | Üzerine Yaz |
| `error.title` | Something Went Wrong | Bir Sorun Oluştu |

- [ ] **Step 1: Uygulama yaşam döngüsü — `AppDelegate` ve sahneler**

`SSHConfigManager/App/AppDelegate.swift`:

```swift
import AppKit

/// Quitting (or closing the last window) with unsaved edits asks Save / Cancel / Don't Save.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.store.hasUnsavedChanges else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "quit.unsaved.title")
        alert.informativeText = String(localized: "quit.unsaved.message")
        alert.addButton(withTitle: String(localized: "action.save"))
        alert.addButton(withTitle: String(localized: "action.cancel"))
        alert.addButton(withTitle: String(localized: "action.discardAndQuit"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                do {
                    try await model.store.save()
                    sender.reply(toApplicationShouldTerminate: true)
                } catch {
                    model.errorMessage = Messages.text(for: error)
                    sender.reply(toApplicationShouldTerminate: false)
                }
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
```

`SSHConfigManagerApp.swift` — `body`'yi ana pencereyle değiştir (`makeModel()` aynen kalır):

```swift
@main
struct SSHConfigManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel = SSHConfigManagerApp.makeModel()

    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            MainWindow(model: model)
                .frame(minWidth: 760, minHeight: 480)
                .onAppear { appDelegate.model = model }
        }
    }

    // makeModel() Task 3'teki gibi
}
```

- [ ] **Step 2: Ana pencere, kenar çubuğu, detay**

`SSHConfigManager/Features/HostList/MainWindow.swift`:

```swift
import AppKit
import SSHConfigKit
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel
    @State private var saveFlow: SaveFlowModel?
    @State private var showExternalDiff = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                BannerStack(model: model, showExternalDiff: $showExternalDiff)
                DetailView(model: model)
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: String(localized: "sidebar.search.prompt"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    do { model.select(try HostCommands.addHost(to: model.store)) }
                    catch { model.errorMessage = Messages.text(for: error) }
                } label: {
                    Label(String(localized: "toolbar.addHost"), systemImage: "plus")
                }
                .disabled(model.store.loadState != .loaded)
            }
            ToolbarItem(placement: .status) {
                if model.store.hasUnsavedChanges {
                    Label(String(localized: "toolbar.unsaved"), systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    saveFlow = SaveFlowModel(store: model.store)
                } label: {
                    Label(String(localized: "action.save"), systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.store.hasUnsavedChanges || model.store.isSaving)
            }
        }
        .sheet(item: $saveFlow) { flow in
            SaveSheet(flow: flow) { reloaded in
                if reloaded { model.resetEditor() }
                saveFlow = nil
            }
        }
        .sheet(isPresented: $showExternalDiff) {
            ExternalDiffSheet(store: model.store) { showExternalDiff = false }
        }
        .alert(
            String(localized: "error.title"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "action.close")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Disk (old) → mine (new) for the "file changed elsewhere" banner.
private struct ExternalDiffSheet: View {
    let store: ConfigStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "conflict.title")).font(.headline)
            DiffTextView(hunks: SaveFlowModel.diskVersusMemory(store))
                .frame(minWidth: 640, minHeight: 360)
            HStack {
                Spacer()
                Button(String(localized: "action.close"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
```

`SSHConfigManager/Features/HostList/SidebarView.swift`:

```swift
import AppKit
import SSHConfigKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var pendingDelete: SidebarItem?

    var body: some View {
        let sections = SidebarBuilder.sections(
            document: model.store.document, included: model.store.includedHosts, search: model.searchText)
        List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
            section(String(localized: "sidebar.section.hosts"), rows: sections.hosts, icon: "server.rack", editable: true)
            section(String(localized: "sidebar.section.patterns"), rows: sections.patterns, icon: "asterisk", editable: true)
            section(String(localized: "sidebar.section.included"), rows: sections.included, icon: "lock", editable: false)
            section(String(localized: "sidebar.section.match"), rows: sections.matches, icon: "lock", editable: false)
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button(String(localized: "action.delete"), role: .destructive) {
                guard let item = pendingDelete else { return }
                do {
                    try HostCommands.delete(item, in: model.store)
                    if model.selection == item { model.select(nil) }
                } catch {
                    model.errorMessage = Messages.text(for: error)
                }
                pendingDelete = nil
            }
        } message: {
            Text(String(localized: "delete.confirm.message"))
        }
    }

    private var deleteTitle: String {
        guard case .host(let alias, _)? = pendingDelete else { return "" }
        return String(localized: "delete.confirm.title \(alias)")
    }

    @ViewBuilder
    private func section(_ title: String, rows: [SidebarRow], icon: String, editable: Bool) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(row.title, systemImage: icon)
                        if !row.subtitle.isEmpty {
                            Text(verbatim: row.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 24)
                        }
                    }
                    .tag(row.item)
                    .contextMenu { if editable { menu(for: row.item) } }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for item: SidebarItem) -> some View {
        Button(String(localized: "action.duplicate")) {
            do {
                if let copy = try HostCommands.duplicate(item, in: model.store) { model.select(copy) }
            } catch {
                model.errorMessage = Messages.text(for: error)
            }
        }
        if let command = HostCommands.sshCommand(for: item, document: model.store.document, builder: model.commandBuilder) {
            Button(String(localized: "action.copySSHCommand")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
        }
        Divider()
        Button(String(localized: "action.delete"), role: .destructive) { pendingDelete = item }
    }
}
```

> `Label(row.title, systemImage:)` bir `String` değişkeni alır (literal değil) — host adları çevrilmez.

`SSHConfigManager/Features/HostList/DetailView.swift`:

```swift
import SSHConfigKit
import SwiftUI

struct DetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let item = model.selection {
            content(for: item)
        } else {
            empty
        }
    }

    @ViewBuilder
    private func content(for item: SidebarItem) -> some View {
        switch item {
        case .host:
            HostEditorContainer(model: model)
                .id(model.editorToken)
        case .included:
            if let host = SidebarBuilder.includedHost(for: item, in: model.store.includedHosts) {
                IncludedHostView(host: host, displayPath: model.settings.displayPath(for: host.file))
            } else {
                empty
            }
        case .match:
            if let match = SidebarBuilder.matchEntry(for: item, in: model.store.document) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "match.readOnly"), systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .padding([.top, .horizontal])
                    CodeTextView(lines: match.text.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { ConfigLine(raw: String($0)) })
                }
            } else {
                empty
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView(
            String(localized: "detail.empty.title"),
            systemImage: "server.rack",
            description: Text(String(localized: "detail.empty.message")))
    }
}

/// Owns the editor model for the current selection; rebuilt only when `editorToken` changes.
private struct HostEditorContainer: View {
    @Bindable var model: AppModel
    @State private var editor: HostEditorModel?

    var body: some View {
        Group {
            if let editor {
                HostEditorView(editor: editor, homeDirectory: model.settings.homeDirectory)
                    .onChange(of: editor.item) { _, newItem in model.followRename(to: newItem) }
            } else {
                ContentUnavailableView(String(localized: "edit.hostNotFound"), systemImage: "questionmark")
            }
        }
        .onAppear {
            if editor == nil, let item = model.selection {
                editor = HostEditorModel(item: item, store: model.store, homeDirectory: model.settings.homeDirectory)
            }
        }
    }
}

private struct IncludedHostView: View {
    let host: IncludedHost
    let displayPath: String

    var body: some View {
        Form {
            Section {
                Label(String(localized: "included.readOnly \(displayPath)"), systemImage: "lock")
                    .foregroundStyle(.secondary)
                LabeledContent(String(localized: "editor.alias")) { Text(verbatim: host.entry.patterns.joined(separator: " ")) }
                ForEach(Array(host.entry.directives.enumerated()), id: \.offset) { _, directive in
                    LabeledContent(directive.key) { Text(verbatim: directive.value).textSelection(.enabled) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: Host formu**

`SSHConfigManager/Features/HostList/HostEditorView.swift`:

```swift
import SSHConfigKit
import SwiftUI

struct HostEditorView: View {
    @Bindable var editor: HostEditorModel
    let homeDirectory: URL
    @State private var importingIdentity = false

    var body: some View {
        Form {
            Section(String(localized: "editor.section.connection")) {
                TextField(String(localized: "editor.alias"), text: $editor.aliasText)
                field("HostName", help: String(localized: "help.HostName"))
                field("User", help: String(localized: "help.User"))
                field("Port", help: String(localized: "help.Port"))
                field("ProxyJump", help: String(localized: "help.ProxyJump"))
                Picker(selection: binding("ForwardAgent")) {
                    Text(String(localized: "editor.forwardAgent.unset")).tag("")
                    Text(verbatim: "yes").tag("yes")
                    Text(verbatim: "no").tag("no")
                } label: {
                    Text(verbatim: "ForwardAgent")
                }
                .help(String(localized: "help.ForwardAgent"))
            }

            Section(String(localized: "editor.identityFiles")) {
                ForEach(editor.identityFiles.indices, id: \.self) { index in
                    HStack {
                        TextField(String(localized: "editor.identityFiles"), text: $editor.identityFiles[index])
                            .labelsHidden()
                        Button(String(localized: "editor.remove"), systemImage: "minus.circle") {
                            editor.identityFiles.remove(at: index)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button(String(localized: "editor.identityFiles.add")) { editor.identityFiles.append("") }
                    Button(String(localized: "action.choose")) { importingIdentity = true }
                }
            }

            Section(String(localized: "editor.otherOptions")) {
                ForEach(editor.otherOptions.indices, id: \.self) { index in
                    HStack {
                        TextField(String(localized: "editor.otherOptions.key"), text: $editor.otherOptions[index].key)
                        TextField(String(localized: "editor.otherOptions.value"), text: $editor.otherOptions[index].value)
                        Button(String(localized: "editor.remove"), systemImage: "minus.circle") {
                            editor.otherOptions.remove(at: index)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                Button(String(localized: "editor.otherOptions.add")) {
                    editor.otherOptions.append(DraftDirective(key: "", value: ""))
                }
            }

            if !editor.issues.isEmpty || editor.editError != nil {
                Section(String(localized: "editor.issues")) {
                    ForEach(Array(editor.issues.enumerated()), id: \.offset) { _, issue in
                        Label(Messages.text(for: issue), systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.isBlocking ? .red : .orange)
                    }
                    if let error = editor.editError {
                        Label(Messages.text(for: error), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: editor.draft) { editor.commit() }
        .fileImporter(isPresented: $importingIdentity, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                let path = url.standardizedFileURL.path
                let home = homeDirectory.standardizedFileURL.path
                editor.identityFiles.append(path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
            }
        }
    }

    private func field(_ key: String, help: String) -> some View {
        TextField(key, text: binding(key))
            .help(help)
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { editor.fields[key] ?? "" }, set: { editor.fields[key] = $0 })
    }
}
```

> `Text(verbatim: "yes")`, `TextField(key, …)` ve `Text(verbatim: "ForwardAgent")`: ssh değerleri ve direktif adları çevrilmez (spec §6.5); `Text(verbatim:)` biçimi `viewInitializersNeverTakeStringLiterals` testinin dışında kalır.

- [ ] **Step 4: Bantlar ve kaydetme sayfası**

`SSHConfigManager/Features/HostList/BannerStack.swift`:

```swift
import SSHConfigKit
import SwiftUI

struct BannerStack: View {
    @Bindable var model: AppModel
    @Binding var showExternalDiff: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let banners = BannerBuilder.banners(for: model.store)
        if !banners.isEmpty {
            VStack(spacing: 0) {
                ForEach(banners) { banner in
                    row(for: banner)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func row(for banner: Banner) -> some View {
        switch banner {
        case .missingFile:
            BannerRow(icon: "doc.badge.plus", tint: .yellow, message: Messages.text(for: ConfigLoadState.missing) ?? "") {
                Button(String(localized: "banner.missing.create")) {
                    do { try model.store.createFile() } catch { model.errorMessage = Messages.text(for: error) }
                }
                Button(String(localized: "banner.missing.choose")) { openSettings() }
            }
        case .notUTF8:
            BannerRow(icon: "exclamationmark.triangle", tint: .red, message: Messages.text(for: ConfigLoadState.notUTF8) ?? "") {
                EmptyView()
            }
        case .unreadable(let detail):
            BannerRow(icon: "exclamationmark.triangle", tint: .red, message: Messages.text(for: ConfigLoadState.unreadable(detail)) ?? "") {
                Button(String(localized: "banner.missing.choose")) { openSettings() }
            }
        case .byteOrderMark:
            BannerRow(icon: "exclamationmark.triangle", tint: .orange, message: String(localized: "banner.bom")) {
                Button(String(localized: "banner.bom.remove")) {
                    do { try model.store.apply { $0.removeByteOrderMark() } } catch { model.errorMessage = Messages.text(for: error) }
                }
            }
        case .externalChange:
            BannerRow(icon: "arrow.triangle.2.circlepath", tint: .orange, message: Messages.text(for: ConfigStoreError.conflict)) {
                Button(String(localized: "banner.external.reload")) {
                    model.store.discardChanges()
                    model.resetEditor()
                }
                Button(String(localized: "banner.external.showDiff")) { showExternalDiff = true }
            }
        case .notWatching:
            BannerRow(icon: "eye.slash", tint: .secondary, message: String(localized: "banner.notWatching")) {
                EmptyView()
            }
        }
    }
}

private struct BannerRow<Actions: View>: View {
    let icon: String
    let tint: Color
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
    }
}
```

`SSHConfigManager/Features/HostList/SaveSheet.swift`:

```swift
import SSHConfigKit
import SwiftUI

/// Review → save, or resolve a conflict. `finish(true)` means the document was reloaded from disk.
struct SaveSheet: View {
    @Bindable var flow: SaveFlowModel
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch flow.phase {
            case .preparing:
                ProgressView(String(localized: "save.validating"))
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .review(let preparation):
                Text(String(localized: "save.title")).font(.headline)
                DiffTextView(hunks: preparation.hunks).frame(minWidth: 640, minHeight: 320)
                validation(preparation.validation)
                HStack {
                    Spacer()
                    Button(String(localized: "action.cancel")) { finish(false) }
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "action.save")) { Task { await flow.confirm() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!flow.canConfirm)
                }
            case .saving:
                ProgressView(String(localized: "save.saving"))
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .conflict:
                Text(String(localized: "conflict.title")).font(.headline)
                Text(String(localized: "conflict.message"))
                DiffTextView(hunks: flow.conflictHunks()).frame(minWidth: 640, minHeight: 280)
                HStack {
                    Button(String(localized: "conflict.loadDisk"), role: .destructive) {
                        flow.loadDiskVersion()
                        finish(true)
                    }
                    Spacer()
                    Button(String(localized: "action.cancel")) { finish(false) }
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "conflict.overwrite")) { Task { await flow.overwrite() } }
                }
            case .failed(let message):
                Text(String(localized: "save.failed.title")).font(.headline)
                Text(message).textSelection(.enabled)
                HStack {
                    Spacer()
                    Button(String(localized: "action.close")) { finish(false) }
                        .keyboardShortcut(.defaultAction)
                }
            case .done:
                Color.clear.frame(width: 1, height: 1)
                    .onAppear { finish(false) }
            }
        }
        .padding()
        .task { if flow.phase == .preparing { await flow.prepare() } }
    }

    @ViewBuilder
    private func validation(_ outcome: ValidationOutcome) -> some View {
        let valid = outcome == .valid
        Label(Messages.text(for: outcome), systemImage: valid ? "checkmark.seal.fill" : "xmark.octagon.fill")
            .foregroundStyle(valid ? .green : .red)
            .font(valid ? .body : .system(.body, design: .monospaced))
            .textSelection(.enabled)
    }
}
```

Kataloğa yukarıdaki tablodaki anahtarları ekle.

- [ ] **Step 5: Manuel test listesini başlat**

`docs/design/manual-test-checklist.md`:

```markdown
# Manuel Test Listesi

Her sürüm öncesi temiz bir test kullanıcısında veya `~/.ssh/config` yedeği alınmış bir makinede uygulanır.

## Plan 2a — Düzenleyici

- [ ] İlk açılış, `~/.ssh/config` yokken: "Config dosyası henüz yok" bandı → "Dosya Oluştur" → dosya 0600, `~/.ssh` 0700 oluşur; bant kaybolur.
- [ ] Mevcut config açılır; hostlar / desenler / dahil edilen 🔒 / Match 🔒 bölümleri doğru.
- [ ] Arama: alias, HostName ve User'da çalışır; Türkçe karakterlerde (ö, İ) aksansız arama sonuç verir.
- [ ] Bir host'un HostName'i değiştirilir → araç çubuğunda "Kaydedilmemiş değişiklikler" görünür.
- [ ] Alias yeniden adlandırılırken yazma kesilmez, odak kaybolmaz, seçim yeni adda kalır.
- [ ] Alias başka bir host'la aynı yapılınca form "başka bir host tarafından kullanılıyor" der ve dosya değişmez.
- [ ] Port alanına `abc` → hata; IdentityFile olarak var olmayan dosya → yalnızca uyarı.
- [ ] Bir değere satır sonlu metin yapıştırılır → kontrol karakteri hatası, belge değişmez.
- [ ] ⌘S → diff ekranı satır numaraları ve renklerle görünür; "ssh bu yapılandırmayı kabul ediyor"; Kaydet → dosya yazılır, yedek oluşur.
- [ ] Geçersiz bir seçenek (ör. Diğer Seçenekler'e `Bogus yes`) → diff ekranında ssh'in hata metni, Kaydet pasif.
- [ ] Uygulama açıkken dosya vim ile değiştirilir: düzenleme yoksa sessizce yeniden yüklenir; düzenleme varken bant çıkar, "Farkı Göster" ve "Yeniden Yükle" çalışır.
- [ ] Düzenleme varken başka bir editörde kaydedip ⌘S → çakışma ekranı; "Üzerine Yaz" ve "Diskteki Sürümü Yükle" beklendiği gibi.
- [ ] BOM'lu bir dosya: bant görünür, "BOM'u Kaldır" → kaydet → dosya BOM'suz.
- [ ] Sağ tık → Çoğalt (`web-copy`), SSH Komutunu Kopyala (`ssh -- web`), Sil (onaylı).
- [ ] Kaydedilmemiş değişiklikle ⌘Q: Kaydet / Vazgeç / Kaydetme seçenekleri; Vazgeç uygulamayı açık tutar.
- [ ] Sistem dili Türkçe iken tüm metinler Türkçe; İngilizce iken İngilizce.
- [ ] Koyu temada diff renkleri ve bantlar okunaklı.
```

- [ ] **Step 6: Derle ve tüm testleri çalıştır**

Run: `scripts/test-app.sh`
Expected: PASS — tüm testler (özellikle `LocalizationTests`: kaynaktaki her anahtar katalogda, katalogda kullanılmayan anahtar yok, görünüm başlatıcılarında literal yok), derleme uyarısı yok.

Uygulamayı geçici bir test config'iyle çalıştır (gerçek config'e dokunmadan): Ayarlar henüz yok, bu yüzden geçici olarak `defaults write tr.com.mess.SSHConfigManager configPath /tmp/sshcm-manual/config` ile yolu ayarla, `mkdir -p /tmp/sshcm-manual && printf 'Host demo\n  HostName 127.0.0.1\n' > /tmp/sshcm-manual/config && chmod 600 /tmp/sshcm-manual/config`, uygulamayı aç ve manuel listenin ilk altı maddesini uygula; sonra `defaults delete tr.com.mess.SSHConfigManager configPath`. Gözlemleri raporuna yaz.

- [ ] **Step 7: Commit**

```bash
git add SSHConfigManager docs/design/manual-test-checklist.md
git commit -m "feat(app): ana pencere, host formu, uyarı bantları, kaydetme sayfası, çıkış koruması"
```

---

### Task 10: Ayarlar ve yedekler

**Files:**
- Create: `SSHConfigManager/Features/Settings/BackupsModel.swift`
- Create: `SSHConfigManager/Features/Settings/BackupsView.swift`
- Create: `SSHConfigManager/Features/Settings/SettingsView.swift`
- Modify: `SSHConfigManager/App/SSHConfigManagerApp.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Modify: `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/BackupsModelTests.swift`

**Interfaces:**
- Consumes: `AppModel` (`switchConfig`, `setBackupCount`, `backupManager`, `store`, `settings`, `resetEditor`), `BackupManager.list/contents`, `Backup`, `LineDiff`, `Messages`, `DiffTextView`.
- Produces: `@MainActor @Observable final class BackupsModel` — `init(model: AppModel)`, `private(set) var backups: [Backup]`, `var selectedURL: URL?`, `private(set) var errorMessage: String?`, `func refresh()`, `var selected: Backup?`, `func hunks(for backup: Backup) -> [DiffHunk]`, `func restore(_ backup: Backup) throws`; `SettingsView(model:)`; `BackupsView(model:)`; `Settings` sahnesi ve `Window(id: "backups")`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `settings.configFile` | Config File | Config Dosyası |
| `settings.configFile.useDefault` | Use ~/.ssh/config | ~/.ssh/config Kullan |
| `settings.configFile.customNote` | Typing “ssh host” in a terminal does not use this file; the app connects with -F. | Terminalde doğrudan “ssh host” yazarsanız bu dosya kullanılmaz; uygulama -F ile bağlanır. |
| `settings.backups` | Backups | Yedekler |
| `settings.backups.count %@` | Backups to keep: %@ | Saklanacak yedek sayısı: %@ |
| `settings.backups.show` | Show Backups… | Yedekleri Göster… |
| `settings.language` | Language | Dil |
| `settings.language.note` | The app follows the system language. You can choose a different language for this app in System Settings. | Uygulama sistem dilini kullanır. Bu uygulama için farklı bir dili Sistem Ayarları'ndan seçebilirsiniz. |
| `settings.language.open` | Open Language Settings… | Dil Ayarlarını Aç… |
| `settings.switch.title` | Discard unsaved changes? | Kaydedilmemiş değişiklikler atılsın mı? |
| `settings.switch.discard` | Discard and Switch | At ve Değiştir |
| `backups.empty` | No backups yet. | Henüz yedek yok. |
| `backups.restore` | Load into Editor | Düzenleyiciye Yükle |
| `backups.restore.note` | The backup is loaded as unsaved changes; review and save to apply it. | Yedek kaydedilmemiş değişiklik olarak yüklenir; uygulamak için inceleyip kaydedin. |
| `backups.diffCaption` | Changes from the current file to this backup | Mevcut dosyadan bu yedeğe değişiklikler |

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/BackupsModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct BackupsModelTests {
    private func saveEdit(_ app: AppModel, port: String) async throws {
        try app.store.apply { doc in
            var draft = HostDraft(doc.hosts[0])
            draft.directives = [DraftDirective(key: "Port", value: port)]
            try doc.updateHost(at: doc.hosts[0].headerLine, to: draft)
        }
        try await app.store.save()
    }

    @Test func listsBackupsNewestFirst() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        try await saveEdit(app, port: "2")
        let backups = BackupsModel(model: app)
        #expect(backups.backups.count == 2)
        #expect(try app.backupManager.contents(of: backups.backups[0]) == "Host a\n    Port 1\n")
        #expect(backups.selected == nil)
        backups.selectedURL = backups.backups[1].url
        #expect(backups.selected?.url == backups.backups[1].url)
    }

    @Test func hunksCompareCurrentDocumentToBackup() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        let hunks = backups.hunks(for: backup)
        #expect(hunks.flatMap(\.lines).contains { $0.kind == .removed && $0.text == "    Port 1" })
    }

    @Test func restoreLoadsBackupAsUnsavedChanges() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        try await saveEdit(app, port: "1")
        let backups = BackupsModel(model: app)
        let backup = try #require(backups.backups.first)
        try backups.restore(backup)
        #expect(app.store.document.render() == "Host a\n")
        #expect(app.store.hasUnsavedChanges)
        #expect(try tmp.read(".ssh/config") == "Host a\n    Port 1\n")   // disk untouched until Save
    }

    @Test func emptyWhenNoBackups() throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host a\n")
        let backups = BackupsModel(model: app)
        #expect(backups.backups.isEmpty)
        #expect(backups.errorMessage == nil)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/BackupsModelTests`
Expected: FAIL — `cannot find 'BackupsModel' in scope`.

- [ ] **Step 3: Uygulamayı yaz**

`SSHConfigManager/Features/Settings/BackupsModel.swift`:

```swift
import Foundation
import Observation
import SSHConfigKit

@MainActor
@Observable
final class BackupsModel {
    let model: AppModel
    private(set) var backups: [Backup] = []
    var selectedURL: URL?
    private(set) var errorMessage: String?

    init(model: AppModel) {
        self.model = model
        refresh()
    }

    var selected: Backup? { backups.first { $0.url == selectedURL } }

    func refresh() {
        do {
            backups = try model.backupManager.list(kind: "config")
            errorMessage = nil
        } catch {
            backups = []
            errorMessage = Messages.text(for: error)
        }
        if let selectedURL, !backups.contains(where: { $0.url == selectedURL }) { self.selectedURL = nil }
    }

    /// Current document (old) → backup (new): what restoring would change.
    func hunks(for backup: Backup) -> [DiffHunk] {
        let contents = (try? model.backupManager.contents(of: backup)) ?? ""
        return LineDiff.hunks(old: model.store.document.render(), new: contents)
    }

    /// Loads the backup into the editor; the normal Save flow (diff, ssh -G, backup) writes it.
    func restore(_ backup: Backup) throws {
        let contents = try model.backupManager.contents(of: backup)
        try model.store.apply { $0 = ConfigDocument(parsing: contents) }
        model.resetEditor()
    }
}
```

`SSHConfigManager/Features/Settings/BackupsView.swift`:

```swift
import SSHConfigKit
import SwiftUI

struct BackupsView: View {
    @State private var backups: BackupsModel

    init(model: AppModel) {
        _backups = State(initialValue: BackupsModel(model: model))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $backups.selectedURL) {
                ForEach(backups.backups, id: \.url) { backup in
                    Text(backup.date.formatted(date: .abbreviated, time: .standard)).tag(backup.url)
                }
            }
            .overlay {
                if backups.backups.isEmpty {
                    ContentUnavailableView(String(localized: "backups.empty"), systemImage: "clock.arrow.circlepath")
                }
            }
        } detail: {
            if let backup = backups.selected {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "backups.diffCaption")).font(.headline)
                    DiffTextView(hunks: backups.hunks(for: backup))
                    HStack {
                        Text(String(localized: "backups.restore.note")).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "backups.restore")) {
                            do { try backups.restore(backup) } catch { backups.model.errorMessage = Messages.text(for: error) }
                        }
                        .disabled(backups.model.store.loadState != .loaded)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView(String(localized: "settings.backups"), systemImage: "clock.arrow.circlepath")
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .onAppear { backups.refresh() }
    }
}
```

`SSHConfigManager/Features/Settings/SettingsView.swift`:

```swift
import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var importing = false
    @State private var pendingPath: String?

    var body: some View {
        Form {
            Section(String(localized: "settings.configFile")) {
                LabeledContent(String(localized: "settings.configFile")) {
                    Text(verbatim: model.settings.configPath).textSelection(.enabled)
                }
                HStack {
                    Button(String(localized: "action.choose")) { importing = true }
                    Button(String(localized: "settings.configFile.useDefault")) { requestSwitch(AppSettings.defaultConfigPath) }
                        .disabled(model.commandBuilder.usesDefaultConfig)
                }
                if !model.commandBuilder.usesDefaultConfig {
                    Text(String(localized: "settings.configFile.customNote"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "settings.backups")) {
                let count = String(model.settings.backupCount)
                Stepper(
                    value: Binding(get: { model.settings.backupCount }, set: { model.setBackupCount($0) }),
                    in: AppSettings.backupCountRange
                ) {
                    Text(String(localized: "settings.backups.count \(count)"))
                }
                Button(String(localized: "settings.backups.show")) { openWindow(id: "backups") }
            }

            Section(String(localized: "settings.language")) {
                Text(String(localized: "settings.language.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(String(localized: "settings.language.open")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { requestSwitch(model.settings.displayPath(for: url)) }
        }
        .confirmationDialog(
            String(localized: "settings.switch.title"),
            isPresented: Binding(get: { pendingPath != nil }, set: { if !$0 { pendingPath = nil } })
        ) {
            Button(String(localized: "settings.switch.discard"), role: .destructive) {
                if let path = pendingPath { _ = model.switchConfig(to: path, discardingUnsavedChanges: true) }
                pendingPath = nil
            }
        }
    }

    private func requestSwitch(_ path: String) {
        if model.switchConfig(to: path) == .needsConfirmation { pendingPath = path }
    }
}
```

`SSHConfigManagerApp.swift` sahnelerine ekle (ana `Window`'dan sonra):

```swift
        Settings {
            SettingsView(model: model)
        }
        Window(String(localized: "settings.backups"), id: "backups") {
            BackupsView(model: model)
        }
```

Kataloğa tablodaki anahtarları ekle. `docs/design/manual-test-checklist.md` "Plan 2a" bölümüne ekle:

```markdown
- [ ] Ayarlar (⌘,) → "Seç…" ile `~/dotfiles/ssh/config` seçilir → liste o dosyadan yüklenir, `-F` notu görünür; "~/.ssh/config Kullan" geri döndürür.
- [ ] Kaydedilmemiş değişiklik varken config dosyası değiştirilmeye çalışılınca "atılsın mı?" onayı çıkar; vazgeçilirse hiçbir şey değişmez.
- [ ] Yedek sayısı 2 yapılır, üç farklı kayıt yapılır → Yedekler penceresinde 2 yedek.
- [ ] Yedekler penceresinde bir yedek seçilir → mevcut dosyadan yedeğe diff; "Düzenleyiciye Yükle" → kaydedilmemiş değişiklik olur, ⌘S ile normal kaydetme akışı.
- [ ] "Dil Ayarlarını Aç…" Sistem Ayarları'nın Dil ve Bölge sayfasını açar.
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh`
Expected: PASS — tüm testler, uyarı yok.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat(app): ayarlar ve yedekler penceresi"
```

---

## Plan 2a tamamlandığında

- `xcrun swift test --package-path Packages/SSHConfigKit` ve `scripts/test-app.sh` yeşil.
- Uygulama config dosyasını açar, form ile düzenler, diff + `ssh -G` onayıyla kaydeder, yedekleri gösterir/geri yükler, config yolunu değiştirir; arayüz İngilizce ve Türkçe.
- Sıradaki adım: Ghostty/Warp denemesi (spec §12) ve ardından Plan 2b (bağlanma, menü çubuğu, hızlı panel).
