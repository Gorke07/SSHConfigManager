# Plan 2b — Bağlanma: Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uygulamadan sunuculara bağlanmak: seçilen terminalde (Terminal, iTerm2, Ghostty) tek tıkla `ssh`, bağlantı testi ve sonuç rozetleri, menü çubuğu ve ⌥⌘S ile açılan hızlı bağlanma paneli, girişte başlatma.

**Architecture:** Terminal açma, test edilebilir saf parçalara (AppleScript metni, Ghostty argümanları, yedeğe düşme kararı) ve ince AppKit başlatıcılarına (`NSAppleScript`, `/usr/bin/open`) ayrılır; `AppModel.connect(alias:)` bunları birleştirir ve testlerde sahte başlatıcılarla çalışır (testler asla gerçek terminal açmaz). Bağlantı testleri `ConnectionTestsModel`'de, sonuçlar oturum boyunca bellekte tutulur. Menü çubuğu ve hızlı panel aynı `QuickConnectModel` + `QuickConnectView`'ı paylaşır. Model artık `AppDelegate`'e aittir; böylece uygulama yalnızca menü çubuğuyla açıldığında da çıkış koruması çalışır.

**Tech Stack:** Swift 6.4 (Xcode 27.0), SwiftUI (`MenuBarExtra`, `onKeyPress`), AppKit (`NSPanel`, `NSAppleScript`, `NSWorkspace`), ServiceManagement (`SMAppService`), `KeyboardShortcuts` (sindresorhus, MIT), Swift Testing, XcodeGen.

**Spec:** `docs/design/2026-10-07-ssh-config-manager-design.md` — §3.3 (terminal, girişte başlat, kısayol ayarları), §6.1 (Bağlan / Test et / Tümünü test et), §6.2 (menü çubuğu), §6.3 (hızlı panel + global kısayol), §6.4 (bağlantı testi sonuçları), §9 (terminal entegrasyonu; Ghostty doğrulandı, Warp v1'de yok), §10 (Otomasyon izni reddi). Devreden konular: `docs/design/2026-10-07-plan-2a-followups.md` (ilk madde bu planın Task 1'idir), `docs/design/2026-10-07-plan-1-followups.md` (`testAll` iptali, kontrol karakterli yol).

## Global Constraints

- macOS 26.0; Swift 6 dil modu, `SWIFT_STRICT_CONCURRENCY = complete`. Toolchain: Xcode 27.0 (Swift 6.4).
- Uygulama target'ının bağımlılıkları: yerel `SSHConfigKit` ve `KeyboardShortcuts` (https://github.com/sindresorhus/KeyboardShortcuts, `from: 2.0.0`). Başka paket yok.
- Desteklenen terminaller: Terminal (`com.apple.Terminal`), iTerm2 (`com.googlecode.iterm2`), Ghostty (`com.mitchellh.ghostty`). Warp yok.
- Terminal ve iTerm2 AppleScript ile açılır: `tell application id "<bundle id>"`; Ghostty `open -na Ghostty.app --args -e /usr/bin/ssh <argümanlar>` ile, argümanlar shell'den geçmeden. Komut metni yalnızca `SSHCommandBuilder.shellCommand(alias:)` / `sshArguments(alias:)` ile üretilir; kontrol karakteri içeren komutlar hiç başlatılmaz.
- Seçilen başlatıcı başarısız olursa (yüklü değil ya da hata) Terminal'e düşülür ve kullanıcıya söylenir; Otomasyon izni reddi ayrı bir uyarıyla ve Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon bağlantısıyla gösterilir.
- Bağlantı testi: en fazla 4 eşzamanlı; sonuçlar diske yazılmaz; config dosyası değişince temizlenir.
- **Testler asla gerçek terminal açmaz, gerçek `~/.ssh`'a, `~/Library`'ye veya `UserDefaults.standard`'a dokunmaz**; `makeTestModel` varsayılan olarak kaydeden (hiçbir şey açmayan) sahte başlatıcı kullanır. Test host'unda menü çubuğu öğesi, global kısayol ve panel kurulmaz.
- Kullanıcıya görünen her metin `String(localized:)` + `Localizable.xcstrings` (en + tr, `translated`); görünüm başlatıcılarına literal verilmez (`Text(verbatim:)` çevrilmeyen metinler için). Ürün adları (Terminal, iTerm2, Ghostty) ve ssh kelimeleri çevrilmez. `scripts/check-localization.py` bunları denetler.
- Paket testleri: `xcrun swift test --package-path Packages/SSHConfigKit`. Uygulama testleri: `scripts/test-app.sh` (önce yerelleştirme denetimi ve denetleyicinin kendi testleri, sonra xcodebuild). Tek suite: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/<Suite>`. Sayılar `-quiet` olmayan bir xcodebuild çalıştırmasıyla doğrulanır. İş bitince xcodebuild/uygulama süreci açık bırakılmaz.
- Elle denemelerde daima geçici config: `defaults write tr.com.mess.SSHConfigManager configPath /tmp/sshcm-manual/config`; bittiğinde `defaults delete tr.com.mess.SSHConfigManager configPath`. Gerçek `~/.ssh/config` kullanılmaz. Bağlanma denemeleri için config'te `Host demo` → `HostName 127.0.0.1`, `Port 1` (bağlantı reddedilir; zararsız) kullanılır.

## Review Focus

1. **Boşluk, tek/çift tırnak, `$()` veya ters bölü içeren alias ya da config yolu** — Terminal/iTerm2'ye giden AppleScript metninde ve Ghostty argümanlarında tek bir ssh argümanı olarak kalır, komut enjeksiyonu olmaz (Task 3'te test).
2. **Seçilen terminal yüklü değilse veya Otomasyon izni reddedilirse** — sessizce hiçbir şey olmaması yerine Terminal'e düşülür ve söylenir ya da izin adımı gösterilir (Task 3'te test, Task 5'te elle).
3. **"Tümünü test et" çalışırken yeniden başlatılır veya durdurulursa** — eski çalıştırmanın sonuçları yeni durumu ezmez, iptal edilen hostlar sahte "başarısız" sonuç almaz (Task 2 ve Task 4'te test).
4. **Uygulama ana pencere olmadan (menü çubuğundan) açıldığında** — ⌘Q kaydedilmemiş değişiklikleri sorar, Dock'tan ya da menüden ana pencere açılabilir (Task 1'de test/elle, Task 7'de elle).
5. **Hızlı bağlanma listesinde aynı alias'a sahip birden çok blok ve include edilen hostlar** — her alias bir kez görünür, include edilen hostlara da bağlanılabilir, desenler (`*`) listede yoktur (Task 7'de test).

---

## Dosya yapısı

```
project.yml                                         KeyboardShortcuts paketi, Otomasyon açıklaması ve yetkisi
scripts/check-localization.py                       kapsam genişletildi, --sources/--catalog argümanları
scripts/test_check_localization.py                  denetleyicinin kendi testleri (unittest)
scripts/test-app.sh                                 denetleyici testlerini de çalıştırır
SSHConfigManager/
├── App/
│   ├── SSHConfigManagerApp.swift                   sahneler: ana pencere, MenuBarExtra, Settings, Backups
│   ├── AppDelegate.swift                           modelin sahibi, çıkış koruması, aktivasyon politikası, kısayol, panel
│   └── MainWindowOpener.swift                      her sahneden ana pencereyi açma eylemini kaydeder
├── Shared/
│   ├── AppModel.swift                              connect, connectableAlias(es), connectionTests, başlatıcı enjeksiyonu
│   └── AppSettings.swift                           terminal seçimi; yolda kontrol karakteri yasağı
└── Features/
    ├── Connect/
    │   ├── TerminalChoice.swift                    Terminal / iTerm2 / Ghostty
    │   ├── TerminalLaunching.swift                 LaunchRequest, LaunchError, AppleScriptBuilder, GhosttyArguments
    │   ├── TerminalLaunchers.swift                 AppleScriptLauncher, GhosttyLauncher, LiveTerminals
    │   ├── Connector.swift                         seçili başlatıcı + Terminal'e düşme
    │   ├── ConnectionTestsModel.swift
    │   ├── ConnectionStatusStyle.swift             durum → simge/renk/metin
    │   ├── ConnectionBar.swift                     detay başlığı: rozet + Test et + Bağlan
    │   └── LoginItem.swift                         SMAppService sarmalayıcı
    └── QuickConnect/
        ├── QuickConnectModel.swift
        ├── QuickConnectView.swift
        ├── MenuBarContent.swift
        └── QuickConnectPanel.swift                 NSPanel + global kısayol
SSHConfigManagerTests/
├── Support/TestSupport.swift                       RecordingLauncher, DelayedRunner, makeTestModel(launcher:)
└── <Birim>Tests.swift
```

---

### Task 1: Uygulama yaşam döngüsü (model AppDelegate'te), yerelleştirme denetleyicisinin kapsamı, küçük düzeltmeler

**Files:**
- Modify: `SSHConfigManager/App/AppDelegate.swift`
- Modify: `SSHConfigManager/App/SSHConfigManagerApp.swift`
- Create: `SSHConfigManager/App/MainWindowOpener.swift`
- Modify: `SSHConfigManager/Features/HostList/MainWindow.swift` (artık `appDelegate.model` ataması yapmaz)
- Modify: `SSHConfigManager/Shared/AppSettings.swift`
- Modify: `SSHConfigManager/Features/Settings/SettingsView.swift`, `SSHConfigManager/Features/HostList/HostEditorView.swift` (`allowedContentTypes: [.data]`)
- Modify: `scripts/check-localization.py`, `scripts/test-app.sh`
- Create: `scripts/test_check_localization.py`
- Test: `SSHConfigManagerTests/AppModelTests.swift` (yeni test)

**Interfaces:**
- Consumes: `AppModel`, `AppSettings`, `TestEnvironment`.
- Produces:
  - `AppDelegate.model: AppModel` (artık optional değil; `AppDelegate.makeModel()` ile oluşturulur), `AppDelegate.openMainWindow: (() -> Void)?`.
  - `extension View { func registersMainWindowOpener(_ appDelegate: AppDelegate) -> some View }`.
  - `AppSettings.isValidConfigPath(_:)` kontrol karakterli yolları (U+0000–U+001F, U+007F) reddeder.
  - `scripts/check-localization.py [--sources DIR] [--catalog FILE]`.

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/AppModelTests.swift` sonuna:

```swift
    @Test func configPathsWithControlCharactersAreInvalid() {
        #expect(!AppSettings.isValidConfigPath("/tmp/a\nb"))
        #expect(!AppSettings.isValidConfigPath("~/x\u{7F}"))
        #expect(!AppSettings.isValidConfigPath("/tmp/a\tb"))
        #expect(AppSettings.isValidConfigPath("/tmp/with space/config"))
    }
```

`scripts/test_check_localization.py`:

```python
"""Tests for check-localization.py (run: python3 -m unittest scripts/test_check_localization.py)."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check-localization.py"


def catalog(entries):
    return {
        "sourceLanguage": "en",
        "version": "1.0",
        "strings": {
            key: {
                "extractionState": "manual",
                "localizations": {
                    "en": {"stringUnit": {"state": "translated", "value": en}},
                    "tr": {"stringUnit": {"state": "translated", "value": tr}},
                },
            }
            for key, (en, tr) in entries.items()
        },
    }


class CheckLocalizationTests(unittest.TestCase):
    def run_check(self, swift: str, entries: dict) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            sources = Path(tmp) / "src"
            sources.mkdir()
            (sources / "View.swift").write_text(swift, encoding="utf-8")
            catalog_path = Path(tmp) / "Localizable.xcstrings"
            catalog_path.write_text(json.dumps(catalog(entries)), encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(SCRIPT), "--sources", str(sources), "--catalog", str(catalog_path)],
                capture_output=True, text=True)

    def test_clean_source_passes(self):
        result = self.run_check('let a = String(localized: "k.one \\(name)")', {"k.one %@": ("One %@", "Bir %@")})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_and_unused_keys_fail(self):
        result = self.run_check('let a = String(localized: "k.missing")', {"k.unused": ("U", "K")})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("k.missing", result.stderr)
        self.assertIn("k.unused", result.stderr)

    def test_untranslated_turkish_fails(self):
        result = self.run_check('let a = String(localized: "k")', {"k": ("K", "")})
        self.assertNotEqual(result.returncode, 0)

    def test_every_literal_is_reported_with_line_numbers(self):
        swift = "\n".join([
            'Text("a")',
            '.help("b")',
            'Window("c", id: "x")',
            'ContentUnavailableView("d", systemImage: "e")',
            '.confirmationDialog("f", isPresented: $p) {}',
            'ProgressView("g")',
            'MenuBarExtra("h", systemImage: "i") {}',
            'alert.messageText = "j"',
            'alert.addButton(withTitle: "k")',
            'Text(verbatim: "ok")',
        ])
        result = self.run_check(swift, {})
        self.assertNotEqual(result.returncode, 0)
        for line in range(1, 10):
            self.assertIn(f"View.swift:{line}", result.stderr)
        self.assertNotIn("View.swift:10", result.stderr)

    def test_complex_interpolation_fails(self):
        result = self.run_check('let a = String(localized: "k \\(a.b)")', {"k %@": ("K %@", "K %@")})
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `python3 -m unittest scripts/test_check_localization.py` → FAIL (`--sources` tanınmıyor, yeni kalıplar yakalanmıyor).
Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/AppModelTests` → FAIL (`configPathsWithControlCharactersAreInvalid`).

- [ ] **Step 3: Uygulamayı yaz**

`scripts/check-localization.py` — `main()` argümanları okur ve görünüm kalıplarını genişletir. Değişen kısımlar:

```python
import argparse

VIEW_LITERAL = re.compile(
    r'(\b(?:Text|Button|Label|Section|Toggle|TextField|Picker|Menu|LabeledContent|Window|MenuBarExtra'
    r'|ContentUnavailableView|ProgressView|Stepper)\(\s*"'
    r'|\.(?:help|navigationTitle|confirmationDialog|alert)\(\s*"'
    r'|\b(?:messageText|informativeText)\s*=\s*"'
    r'|addButton\(withTitle:\s*")'
)


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "SSHConfigManager")
    parser.add_argument("--catalog", type=Path, default=ROOT / "SSHConfigManager/Shared/Localization/Localizable.xcstrings")
    args = parser.parse_args()
    sources, catalog_path = args.sources, args.catalog
    # … aynı denetimler; CATALOG/SOURCES yerine catalog_path/sources kullanılır …
    # literal denetimi her eşleşmeyi satır numarasıyla raporlar:
    #     for match in VIEW_LITERAL.finditer(text):
    #         errors.append(f"{path.name}:{line_of(text, match.start())}: görünüm başlatıcısında string literal")
```

(`Text(verbatim: "…")` eşleşmez çünkü `(` sonrasında `"` değil `verbatim:` gelir.) Modül düzeyindeki `SOURCES`/`CATALOG` sabitleri kaldırılır; dosyanın geri kalan mantığı aynen kalır.

`scripts/test-app.sh` — denetleyiciden önce kendi testlerini çalıştırır:

```bash
python3 -m unittest scripts/test_check_localization.py
python3 scripts/check-localization.py
```

`AppSettings.isValidConfigPath`:

```swift
static func isValidConfigPath(_ path: String) -> Bool {
    guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return false }
    return path.hasPrefix("/") || path == "~" || path.hasPrefix("~/")
}
```

`SettingsView.swift` ve `HostEditorView.swift` dosya seçicileri: `allowedContentTypes: [.data]` (klasör seçilemez).

`SSHConfigManager/App/MainWindowOpener.swift`:

```swift
import AppKit
import SwiftUI

/// Every scene registers SwiftUI's `openWindow` with the AppDelegate, so the main window can be
/// reopened (Dock click, menu bar, failed quit-save) whichever scene the app launched with.
private struct MainWindowOpener: ViewModifier {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            appDelegate.openMainWindow = {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate()
            }
        }
    }
}

extension View {
    func registersMainWindowOpener(_ appDelegate: AppDelegate) -> some View {
        modifier(MainWindowOpener(appDelegate: appDelegate))
    }
}
```

`AppDelegate.swift` — modelin sahibi olur (`SSHConfigManagerApp.makeModel()` buraya taşınır):

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel = AppDelegate.makeModel()
    var openMainWindow: (() -> Void)?

    // applicationShouldTerminateAfterLastWindowClosed, applicationShouldHandleReopen ve
    // applicationShouldTerminate aynen kalır; yalnızca `guard let model` yerine `model` doğrudan kullanılır.

    static func makeModel() -> AppModel {
        guard TestEnvironment.isRunningTests else { return AppModel(settings: AppSettings()) }
        // Unit tests are hosted by the app: use a throwaway home so the real ~/.ssh is never read.
        let home = FileManager.default.temporaryDirectory.appending(path: "SSHConfigManagerTestHost-\(UUID().uuidString)")
        let suite = "SSHConfigManagerTestHost-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        UserDefaults().removePersistentDomain(forName: suite)
        return AppModel(settings: AppSettings(defaults: defaults, homeDirectory: home),
                        backupRoot: home.appending(path: "Backups"))
    }
}
```

`SSHConfigManagerApp.swift` — `@State model` kalkar; her sahne `appDelegate.model` kullanır ve açıcıyı kaydeder:

```swift
@main
struct SSHConfigManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(String(localized: "app.title"), id: "main") {
            MainWindow(model: appDelegate.model, appDelegate: appDelegate)
                .frame(minWidth: 760, minHeight: 480)
                .registersMainWindowOpener(appDelegate)
        }
        Settings {
            SettingsView(model: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
        }
        Window(String(localized: "settings.backups"), id: "backups") {
            BackupsView(model: appDelegate.model)
                .registersMainWindowOpener(appDelegate)
        }
    }
}
```

`MainWindow.swift` içinde `openMainWindow`/`appDelegate.model` atayan `onAppear` kodu kaldırılır (artık `registersMainWindowOpener` yapıyor). `MainWindow`'un `appDelegate` parametresi başka bir yerde kullanılmıyorsa kaldırılır.

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `python3 -m unittest scripts/test_check_localization.py` → PASS. Run: `scripts/test-app.sh` → PASS (denetleyici mevcut kaynaklarda temiz; yeni kalıplar bir ihlal bulursa onu `String(localized:)`'e çevir). Elle: geçici config ile uygulamayı aç; ana pencereyi kapat (⌘W); Dock simgesine tıkla → ana pencere açılır; bir host'un HostName'ini değiştir, ⌘W, ⌘Q → kaydetme uyarısı gelir; Vazgeç.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests scripts
git commit -m "feat(app): model AppDelegate'te, her sahneden ana pencere açıcı, denetleyici kapsamı"
```

---

### Task 2: SSHConfigKit — `testAll` iptali

**Files:**
- Modify: `Packages/SSHConfigKit/Sources/SSHConfigKit/SSH/ConnectionTester.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConnectionTesterTests.swift`

**Interfaces:**
- Consumes: `ConnectionTester.testAll(_:maxConcurrent:onResult:)`, test desteğinde `FakeRunner(delay:respond:)` ve `Collected` (bu test dosyasında tanımlı).
- Produces: iptal edildiğinde `testAll` yeni host başlatmaz ve iptal sonrası biten testler için `onResult` çağırmaz.

- [ ] **Step 1: Başarısız testi yaz** (`ConnectionTesterTests` içine)

```swift
    @Test func cancelledTestAllReportsNothingAndStopsQueueing() async {
        let fake = FakeRunner(delay: .milliseconds(300)) { _ in ProcessResult(exitCode: 0, stdout: "", stderr: "", timedOut: false) }
        let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
        let collected = Collected()
        let task = Task {
            await ConnectionTester(commandBuilder: builder, runner: fake).testAll((1...10).map { "h\($0)" }, maxConcurrent: 4) { alias, _ in
                collected.add(alias)
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        #expect(collected.values.isEmpty)
        #expect(fake.calls.count <= 4)
    }
```

- [ ] **Step 2: Testin başarısız olduğunu doğrula**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter ConnectionTesterTests`
Expected: FAIL — iptal edilen testler `.other` sonucuyla raporlanıyor veya kuyruk devam ediyor.

- [ ] **Step 3: Uygulamayı yaz** (`testAll` gövdesi)

```swift
await withTaskGroup(of: Void.self) { group in
    var pending = aliases.makeIterator()
    func startNext() {
        guard !Task.isCancelled, let alias = pending.next() else { return }
        group.addTask {
            let result = await self.test(alias: alias)
            // A cancelled run must not report fake failures for hosts it never really tested.
            if !Task.isCancelled { await onResult(alias, result) }
        }
    }
    for _ in 0..<max(maxConcurrent, 1) { startNext() }
    while await group.next() != nil { startNext() }
}
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `xcrun swift test --package-path Packages/SSHConfigKit` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "fix(kit): iptal edilen testAll sahte sonuç bildirmesin ve kuyruğa almasın"
```

---

### Task 3: Terminal açma (AppleScript, Ghostty, Terminal'e düşme) ve `AppModel.connect`

**Files:**
- Create: `SSHConfigManager/Features/Connect/TerminalChoice.swift`
- Create: `SSHConfigManager/Features/Connect/TerminalLaunching.swift`
- Create: `SSHConfigManager/Features/Connect/TerminalLaunchers.swift`
- Create: `SSHConfigManager/Features/Connect/Connector.swift`
- Modify: `SSHConfigManager/Shared/AppSettings.swift` (terminal seçimi)
- Modify: `SSHConfigManager/Shared/AppModel.swift` (connect, connectableAlias, enjeksiyon)
- Modify: `project.yml` (Otomasyon açıklaması ve yetkisi)
- Modify: `SSHConfigManagerTests/Support/TestSupport.swift` (`RecordingLauncher`, `makeTestModel(… launcher:)`)
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Test: `SSHConfigManagerTests/TerminalLaunchingTests.swift`

**Interfaces:**
- Consumes: `SSHCommandBuilder.sshArguments(options:alias:)`, `shellCommand(alias:)`; `SidebarBuilder.hostEntry(for:in:)`, `SidebarBuilder.includedHost(for:in:)`.
- Produces:
  - `enum TerminalChoice: String, CaseIterable, Sendable { case terminal, iterm2, ghostty; var bundleIdentifier: String; var displayName: String }`
  - `struct LaunchRequest: Equatable, Sendable { let sshArguments: [String]; let shellCommand: String }`
  - `enum LaunchError: Error, Equatable { case automationDenied, failed(String) }`
  - `@MainActor protocol TerminalLaunching { func launch(_ request: LaunchRequest) throws }`
  - `enum AppleScriptBuilder { static func quoted(_:) -> String; static func terminal(command:) -> String; static func iTerm(command:) -> String }`
  - `enum GhosttyArguments { static func openArguments(for request: LaunchRequest) -> [String] }`
  - `struct AppleScriptLauncher: TerminalLaunching`, `struct GhosttyLauncher: TerminalLaunching`, `enum LiveTerminals { static func launcher(for:) -> any TerminalLaunching; static func isInstalled(_:) -> Bool }`
  - `@MainActor struct Connector { enum Outcome: Equatable { case launched(TerminalChoice), fellBack(from: TerminalChoice), failed(LaunchError) }; func connect(_:) -> Outcome }`
  - `AppSettings.terminal: TerminalChoice` + `setTerminal(_:)`.
  - `AppModel`: `init(…, processRunner:launcherFactory:isTerminalInstalled:)`, `var automationDenied: Bool`, `func connectableAlias(for item: SidebarItem) -> String?`, `var connectableAliases: [String]`, `@discardableResult func connect(alias: String) -> Connector.Outcome`, `func isTerminalInstalled(_:) -> Bool`.
  - Test: `final class RecordingLauncher: TerminalLaunching` (`requests`, `error`), `makeTestModel(_:config:runner:launcher:)`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `connect.failed %@` | Could not open the terminal: %@ | Terminal açılamadı: %@ |
| `connect.fellBack %@` | %@ could not be opened, so Terminal was used instead. | %@ açılamadığı için bunun yerine Terminal kullanıldı. |
| `connect.invalidCommand` | This host can't be opened because its connection command contains invalid characters. | Bu host açılamıyor çünkü bağlantı komutu geçersiz karakterler içeriyor. |

- [ ] **Step 1: Test desteğini genişlet** (`TestSupport.swift`)

```swift
/// Records launch requests instead of opening a terminal. Tests must never open real terminals.
@MainActor
final class RecordingLauncher: TerminalLaunching {
    private(set) var requests: [LaunchRequest] = []
    var error: LaunchError?

    func launch(_ request: LaunchRequest) throws {
        if let error { throw error }
        requests.append(request)
    }
}
```

`makeTestModel` imzası `launcher: RecordingLauncher = RecordingLauncher()` parametresi alır ve `AppModel`'e `processRunner: runner`, `launcherFactory: { _ in launcher }`, `isTerminalInstalled: { _ in true }` geçirir.

- [ ] **Step 2: Başarısız testleri yaz**

`SSHConfigManagerTests/TerminalLaunchingTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct TerminalLaunchingTests {
    @Test func appleScriptQuotingEscapesBackslashAndQuote() {
        #expect(AppleScriptBuilder.quoted(#"ssh -- 'a"b\c'"#) == #""ssh -- 'a\"b\\c'""#)
    }

    @Test func terminalAndITermScripts() {
        let terminal = AppleScriptBuilder.terminal(command: "ssh -- web")
        #expect(terminal.contains(#"tell application id "com.apple.Terminal""#))
        #expect(terminal.contains(#"do script "ssh -- web""#))
        let iterm = AppleScriptBuilder.iTerm(command: "ssh -- web")
        #expect(iterm.contains(#"tell application id "com.googlecode.iterm2""#))
        #expect(iterm.contains(#"write text "ssh -- web""#))
    }

    @Test func ghosttyArgumentsPassSshArgvWithoutAShell() {
        let request = LaunchRequest(sshArguments: ["-F", "/x y/config", "--", "a'b"], shellCommand: "unused")
        #expect(GhosttyArguments.openArguments(for: request) ==
            ["-na", "Ghostty.app", "--args", "-e", "/usr/bin/ssh", "-F", "/x y/config", "--", "a'b"])
    }

    @Test func dangerousAliasStaysOneArgumentInBothPaths() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host x\n", launcher: launcher)
        app.connect(alias: "$(touch /tmp/pwned) \"q\"")
        let request = try #require(launcher.requests.first)
        #expect(request.sshArguments.last == "$(touch /tmp/pwned) \"q\"")
        #expect(request.shellCommand == #"ssh -- '$(touch /tmp/pwned) "q"'"#)
        let script = AppleScriptBuilder.terminal(command: request.shellCommand)
        #expect(script.contains(#"do script "ssh -- '$(touch /tmp/pwned) \"q\"'""#))
    }

    @Test func connectorFallsBackToTerminal() {
        let ghostty = RecordingLauncher()
        ghostty.error = .failed("boom")
        let terminal = RecordingLauncher()
        let request = LaunchRequest(sshArguments: ["--", "a"], shellCommand: "ssh -- a")

        let failing = Connector(choice: .ghostty, isInstalled: { _ in true }, makeLauncher: { $0 == .ghostty ? ghostty : terminal })
        #expect(failing.connect(request) == .fellBack(from: .ghostty))
        #expect(terminal.requests == [request])

        let missing = Connector(choice: .iterm2, isInstalled: { $0 == .terminal }, makeLauncher: { _ in terminal })
        #expect(missing.connect(request) == .fellBack(from: .iterm2))

        let fine = Connector(choice: .terminal, isInstalled: { _ in true }, makeLauncher: { _ in terminal })
        #expect(fine.connect(request) == .launched(.terminal))
    }

    @Test func automationDeniedIsReportedNotHidden() {
        let iterm = RecordingLauncher()
        iterm.error = .automationDenied
        let terminal = RecordingLauncher()
        let request = LaunchRequest(sshArguments: ["--", "a"], shellCommand: "ssh -- a")
        let connector = Connector(choice: .iterm2, isInstalled: { _ in true }, makeLauncher: { $0 == .iterm2 ? iterm : terminal })
        #expect(connector.connect(request) == .failed(.automationDenied))
        #expect(terminal.requests.isEmpty)
    }

    @Test func terminalFailureWithoutFallback() {
        let terminal = RecordingLauncher()
        terminal.error = .failed("nope")
        let connector = Connector(choice: .terminal, isInstalled: { _ in true }, makeLauncher: { _ in terminal })
        #expect(connector.connect(LaunchRequest(sshArguments: [], shellCommand: "ssh")) == .failed(.failed("nope")))
    }

    @Test func modelConnectsResolvesAliasesAndReportsOutcomes() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host web w2\n  HostName h\nHost *.prod\n", launcher: launcher)
        #expect(app.connectableAlias(for: .host(alias: "web", occurrence: 0)) == "web")
        #expect(app.connectableAlias(for: .host(alias: "*.prod", occurrence: 0)) == nil)
        #expect(app.connectableAlias(for: .match(index: 0)) == nil)
        #expect(app.connectableAliases == ["web"])

        #expect(app.connect(alias: "web") == .launched(.terminal))
        #expect(launcher.requests.first?.shellCommand == "ssh -- web")
        #expect(app.errorMessage == nil)

        launcher.error = .automationDenied
        #expect(app.connect(alias: "web") == .failed(.automationDenied))
        #expect(app.automationDenied)
    }

    @Test func customConfigUsesDashF() throws {
        let tmp = try TempDir()
        try tmp.file("dot/config", "Host a\n")
        let launcher = RecordingLauncher()
        let app = makeTestModel(tmp, config: "Host z\n", launcher: launcher)
        #expect(app.switchConfig(to: tmp.url.appending(path: "dot/config").path) == .switched)
        app.connect(alias: "a")
        let request = try #require(launcher.requests.first)
        #expect(request.sshArguments.prefix(2) == ["-F", tmp.url.appending(path: "dot/config").path])
    }

    @Test func terminalSettingPersistsAndFallsBack() throws {
        let tmp = try TempDir()
        let settings = AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url)
        #expect(settings.terminal == .terminal)
        settings.setTerminal(.ghostty)
        #expect(AppSettings(defaults: UserDefaults(suiteName: tmp.defaultsSuiteName)!, homeDirectory: tmp.url).terminal == .ghostty)
        tmp.defaults.set("warp", forKey: "terminal")
        #expect(AppSettings(defaults: tmp.defaults, homeDirectory: tmp.url).terminal == .terminal)
    }
}
```

- [ ] **Step 3: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/TerminalLaunchingTests`
Expected: FAIL — `cannot find 'TerminalChoice' in scope`.

- [ ] **Step 4: Uygulamayı yaz**

`SSHConfigManager/Features/Connect/TerminalChoice.swift`:

```swift
enum TerminalChoice: String, CaseIterable, Sendable {
    case terminal, iterm2, ghostty

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm2: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }

    /// Product names are not translated.
    var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm2: "iTerm2"
        case .ghostty: "Ghostty"
        }
    }
}
```

`SSHConfigManager/Features/Connect/TerminalLaunching.swift`:

```swift
struct LaunchRequest: Equatable, Sendable {
    /// ssh argv after the program name (Ghostty passes these without a shell).
    let sshArguments: [String]
    /// Shell-quoted command line (Terminal / iTerm2 type it into a shell).
    let shellCommand: String
}

enum LaunchError: Error, Equatable {
    /// macOS refused to let this app control the terminal (Apple Events, error -1743).
    case automationDenied
    case failed(String)
}

@MainActor
protocol TerminalLaunching {
    func launch(_ request: LaunchRequest) throws
}

enum AppleScriptBuilder {
    /// An AppleScript string literal; only backslash and double quote need escaping.
    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func terminal(command: String) -> String {
        """
        tell application id "com.apple.Terminal"
            activate
            do script \(quoted(command))
        end tell
        """
    }

    static func iTerm(command: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow to write text \(quoted(command))
        end tell
        """
    }
}

enum GhosttyArguments {
    /// `open -na Ghostty.app --args -e /usr/bin/ssh …` (verified with Ghostty 1.2.2; `-n` opens a new instance).
    static func openArguments(for request: LaunchRequest) -> [String] {
        ["-na", "Ghostty.app", "--args", "-e", "/usr/bin/ssh"] + request.sshArguments
    }
}
```

`SSHConfigManager/Features/Connect/TerminalLaunchers.swift`:

```swift
import AppKit

struct AppleScriptLauncher: TerminalLaunching {
    let makeSource: (String) -> String

    func launch(_ request: LaunchRequest) throws {
        guard let script = NSAppleScript(source: makeSource(request.shellCommand)) else {
            throw LaunchError.failed("AppleScript")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            if number == -1743 { throw LaunchError.automationDenied }
            throw LaunchError.failed(error[NSAppleScript.errorMessage] as? String ?? String(describing: number))
        }
    }
}

struct GhosttyLauncher: TerminalLaunching {
    func launch(_ request: LaunchRequest) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = GhosttyArguments.openArguments(for: request)
        do {
            try process.run()
        } catch {
            throw LaunchError.failed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LaunchError.failed("open \(process.terminationStatus)") }
    }
}

@MainActor
enum LiveTerminals {
    static func launcher(for choice: TerminalChoice) -> any TerminalLaunching {
        switch choice {
        case .terminal: AppleScriptLauncher(makeSource: AppleScriptBuilder.terminal(command:))
        case .iterm2: AppleScriptLauncher(makeSource: AppleScriptBuilder.iTerm(command:))
        case .ghostty: GhosttyLauncher()
        }
    }

    static func isInstalled(_ choice: TerminalChoice) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.bundleIdentifier) != nil
    }
}
```

`SSHConfigManager/Features/Connect/Connector.swift`:

```swift
/// Launches the chosen terminal; falls back to Terminal when it is missing or fails,
/// but never hides a permission problem (the user must grant Automation access).
@MainActor
struct Connector {
    enum Outcome: Equatable {
        case launched(TerminalChoice)
        case fellBack(from: TerminalChoice)
        case failed(LaunchError)
    }

    let choice: TerminalChoice
    let isInstalled: (TerminalChoice) -> Bool
    let makeLauncher: (TerminalChoice) -> any TerminalLaunching

    func connect(_ request: LaunchRequest) -> Outcome {
        if choice != .terminal && !isInstalled(choice) {
            return fallBack(request)
        }
        do {
            try makeLauncher(choice).launch(request)
            return .launched(choice)
        } catch LaunchError.automationDenied {
            return .failed(.automationDenied)
        } catch {
            if choice == .terminal { return .failed(error as? LaunchError ?? .failed(error.localizedDescription)) }
            return fallBack(request)
        }
    }

    private func fallBack(_ request: LaunchRequest) -> Outcome {
        do {
            try makeLauncher(.terminal).launch(request)
            return .fellBack(from: choice)
        } catch {
            return .failed(error as? LaunchError ?? .failed(error.localizedDescription))
        }
    }
}
```

`AppSettings` — `terminal`:

```swift
private(set) var terminal: TerminalChoice   // init: TerminalChoice(rawValue: defaults.string(forKey: "terminal") ?? "") ?? .terminal

func setTerminal(_ choice: TerminalChoice) {
    terminal = choice
    defaults.set(choice.rawValue, forKey: "terminal")
}
```

(`Keys` enum'una `static let terminal = "terminal"` eklenir.)

`AppModel` — yeni alanlar, init parametreleri ve yöntemler:

```swift
@ObservationIgnored let processRunner: any ProcessRunning
@ObservationIgnored private let launcherFactory: @MainActor (TerminalChoice) -> any TerminalLaunching
@ObservationIgnored private let terminalInstalled: @MainActor (TerminalChoice) -> Bool
/// Set when macOS denied Automation access; the main window explains how to allow it.
var automationDenied = false

init(settings: AppSettings,
     backupRoot: URL = BackupManager.defaultRoot,
     processRunner: any ProcessRunning = ProcessRunner(),
     launcherFactory: @escaping @MainActor (TerminalChoice) -> any TerminalLaunching = LiveTerminals.launcher(for:),
     isTerminalInstalled: @escaping @MainActor (TerminalChoice) -> Bool = LiveTerminals.isInstalled,
     makeStore: @escaping StoreFactory = AppModel.liveStore) { … mevcut gövde + üç yeni alanın ataması … }

func isTerminalInstalled(_ choice: TerminalChoice) -> Bool { terminalInstalled(choice) }

/// The alias to connect to for a sidebar item (nil for patterns, Match blocks and missing hosts).
func connectableAlias(for item: SidebarItem) -> String? {
    switch item {
    case .host:
        guard let entry = SidebarBuilder.hostEntry(for: item, in: store.document), !entry.isPattern else { return nil }
        return entry.alias
    case .included:
        guard let host = SidebarBuilder.includedHost(for: item, in: store.includedHosts), !host.entry.isPattern else { return nil }
        return host.entry.alias
    case .match:
        return nil
    }
}

/// Every connectable alias once (case-insensitive, like ssh), file hosts first, then included ones.
var connectableAliases: [String] {
    var seen = Set<String>()
    let candidates = store.document.hosts.filter { !$0.isPattern }.map(\.alias)
        + store.includedHosts.filter { !$0.entry.isPattern }.map(\.entry.alias)
    return candidates.filter { seen.insert($0.lowercased()).inserted }
}

@discardableResult
func connect(alias: String) -> Connector.Outcome {
    let builder = commandBuilder
    let request = LaunchRequest(sshArguments: builder.sshArguments(alias: alias), shellCommand: builder.shellCommand(alias: alias))
    guard !request.shellCommand.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
        errorMessage = String(localized: "connect.invalidCommand")
        return .failed(.failed("control character"))
    }
    let outcome = Connector(choice: settings.terminal, isInstalled: terminalInstalled, makeLauncher: launcherFactory).connect(request)
    switch outcome {
    case .launched:
        break
    case .fellBack(let from):
        let name = from.displayName
        errorMessage = String(localized: "connect.fellBack \(name)")
    case .failed(.automationDenied):
        automationDenied = true
    case .failed(.failed(let detail)):
        errorMessage = String(localized: "connect.failed \(detail)")
    }
    return outcome
}
```

`project.yml` — uygulama target'ı:

```yaml
    info:
      properties:
        # … mevcutlar …
        NSAppleEventsUsageDescription: SSH Config Manager opens your terminal and runs ssh for the host you choose.
    entitlements:
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.automation.apple-events: true
```

Kataloğa yukarıdaki 3 anahtarı ekle.

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/TerminalLaunchingTests` → PASS; ardından tam `scripts/test-app.sh` → PASS, uyarı yok.

- [ ] **Step 6: Commit**

```bash
git add project.yml SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): Terminal, iTerm2 ve Ghostty ile bağlanma, Terminal'e düşme"
```

---

### Task 4: Bağlantı testi modeli ve durum görünümü

**Files:**
- Create: `SSHConfigManager/Features/Connect/ConnectionTestsModel.swift`
- Create: `SSHConfigManager/Features/Connect/ConnectionStatusStyle.swift`
- Modify: `SSHConfigManager/Shared/AppModel.swift` (`connectionTests`, config değişince temizleme)
- Modify: `SSHConfigManagerTests/Support/TestSupport.swift` (`DelayedRunner`)
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Test: `SSHConfigManagerTests/ConnectionTestsModelTests.swift`

**Interfaces:**
- Consumes: `ConnectionTester(commandBuilder:runner:)`, `.test(alias:)`, `.testAll(_:maxConcurrent:onResult:)` (Task 2: iptal güvenli), `ConnectionStatus`, `ConnectionTestResult`, `AppModel.processRunner`, `AppModel.commandBuilder`.
- Produces:
  - `@MainActor @Observable final class ConnectionTestsModel` — `init(runner:)`, `private(set) var results: [String: ConnectionTestResult]`, `private(set) var running: Set<String>`, `private(set) var isTestingAll: Bool`, `func test(_ alias: String, using: SSHCommandBuilder) async`, `func testAll(_ aliases: [String], using: SSHCommandBuilder)`, `func cancelAll()`, `func clear()`, `func waitUntilIdle() async`.
  - `struct ConnectionStatusStyle { let symbol: String; let tint: Color; let title: String; static func style(for: ConnectionStatus) -> Self; static var testing: Self }`
  - `AppModel.connectionTests: ConnectionTestsModel` (switchConfig `.switched` → `clear()`).
  - Test: `struct DelayedRunner: ProcessRunning { let delay: Duration; let result: ProcessResult }`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `status.reachable` | Reachable | Erişilebilir |
| `status.authenticationRequired` | Authentication required | Kimlik doğrulama gerekli |
| `status.hostKeyChanged` | Host key changed | Host anahtarı değişmiş |
| `status.unknownHostKey` | Unknown host key | Bilinmeyen host anahtarı |
| `status.timeout` | Timed out | Zaman aşımı |
| `status.dnsFailure` | Host name not found | Sunucu adı bulunamadı |
| `status.connectionRefused` | Connection refused | Bağlantı reddedildi |
| `status.other` | Connection failed | Bağlantı başarısız |
| `status.testing` | Testing… | Test ediliyor… |

- [ ] **Step 1: Test desteği** (`TestSupport.swift`)

```swift
/// A ProcessRunning that waits before answering (cancellable), for concurrency tests.
struct DelayedRunner: ProcessRunning {
    let delay: Duration
    let result: ProcessResult

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessResult {
        try await Task.sleep(for: delay)
        return result
    }
}
```

- [ ] **Step 2: Başarısız testleri yaz**

`SSHConfigManagerTests/ConnectionTestsModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct ConnectionTestsModelTests {
    let builder = SSHCommandBuilder(configFile: URL(filePath: "/h/.ssh/config"), homeDirectory: URL(filePath: "/h"))
    let refused = ProcessResult(exitCode: 255, stdout: "", stderr: "ssh: connect to host h port 1: Connection refused\r\n", timedOut: false)

    @Test func singleTestRecordsResult() async {
        let model = ConnectionTestsModel(runner: FixedRunner(result: refused))
        await model.test("web", using: builder)
        #expect(model.results["web"]?.status == .connectionRefused)
        #expect(model.results["web"]?.detail.contains("Connection refused") == true)
        #expect(model.running.isEmpty)
    }

    @Test func testAllRecordsEveryAlias() async {
        let model = ConnectionTestsModel(runner: FixedRunner.valid)
        model.testAll(["a", "b", "c"], using: builder)
        #expect(model.isTestingAll)
        await model.waitUntilIdle()
        #expect(Set(model.results.keys) == ["a", "b", "c"])
        #expect(model.results.values.allSatisfy { $0.status == .reachable })
        #expect(!model.isTestingAll)
        #expect(model.running.isEmpty)
    }

    @Test func cancelLeavesNoFakeResults() async {
        let model = ConnectionTestsModel(runner: DelayedRunner(delay: .milliseconds(400), result: refused))
        model.testAll(["a", "b"], using: builder)
        try? await Task.sleep(for: .milliseconds(50))
        model.cancelAll()
        await model.waitUntilIdle()
        #expect(model.results.isEmpty)
        #expect(!model.isTestingAll)
        #expect(model.running.isEmpty)
    }

    @Test func restartingDoesNotLetTheOldRunClobberTheNewOne() async {
        let model = ConnectionTestsModel(runner: DelayedRunner(delay: .milliseconds(200), result: refused))
        model.testAll(["old"], using: builder)
        model.testAll(["new"], using: builder)
        await model.waitUntilIdle()
        #expect(model.results["old"] == nil)
        #expect(model.results["new"]?.status == .connectionRefused)
        #expect(!model.isTestingAll)
    }

    @Test func switchingConfigClearsResults() async throws {
        let tmp = try TempDir()
        try tmp.file("other/config", "Host b\n")
        let app = makeTestModel(tmp, config: "Host a\n")
        await app.connectionTests.test("a", using: app.commandBuilder)
        #expect(!app.connectionTests.results.isEmpty)
        #expect(app.switchConfig(to: tmp.url.appending(path: "other/config").path) == .switched)
        #expect(app.connectionTests.results.isEmpty)
    }

    @Test(arguments: [
        ConnectionStatus.reachable, .authenticationRequired, .hostKeyChanged, .unknownHostKey,
        .timeout, .dnsFailure, .connectionRefused, .other,
    ])
    func everyStatusHasAStyle(status: ConnectionStatus) {
        let style = ConnectionStatusStyle.style(for: status)
        #expect(!style.symbol.isEmpty)
        #expect(!style.title.isEmpty && !style.title.hasPrefix("status."))
    }
}
```

- [ ] **Step 3: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/ConnectionTestsModelTests`
Expected: FAIL — `cannot find 'ConnectionTestsModel' in scope`.

- [ ] **Step 4: Uygulamayı yaz**

`SSHConfigManager/Features/Connect/ConnectionTestsModel.swift`:

```swift
import Foundation
import Observation
import SSHConfigKit

/// Connection test results for the session (never written to disk).
@MainActor
@Observable
final class ConnectionTestsModel {
    private(set) var results: [String: ConnectionTestResult] = [:]
    private(set) var running: Set<String> = []
    private(set) var isTestingAll = false

    @ObservationIgnored private let runner: any ProcessRunning
    @ObservationIgnored private var allTask: Task<Void, Never>?
    @ObservationIgnored private var currentRun: UUID?

    init(runner: any ProcessRunning) {
        self.runner = runner
    }

    func test(_ alias: String, using builder: SSHCommandBuilder) async {
        running.insert(alias)
        let result = await ConnectionTester(commandBuilder: builder, runner: runner).test(alias: alias)
        results[alias] = result
        running.remove(alias)
    }

    /// Tests up to 4 hosts at a time. Starting again cancels the previous run; a stale run never
    /// writes results or clears the new run's state.
    func testAll(_ aliases: [String], using builder: SSHCommandBuilder) {
        cancelAll()
        let run = UUID()
        currentRun = run
        isTestingAll = true
        running.formUnion(aliases)
        let tester = ConnectionTester(commandBuilder: builder, runner: runner)
        allTask = Task { @MainActor [self] in
            await tester.testAll(aliases, maxConcurrent: 4) { alias, result in
                await self.record(alias, result, run: run)
            }
            if currentRun == run { finish() }
        }
    }

    func cancelAll() {
        allTask?.cancel()
        allTask = nil
        currentRun = nil
        finish()
    }

    func clear() {
        cancelAll()
        results = [:]
    }

    /// For tests: waits until the current "test all" run (if any) has finished.
    func waitUntilIdle() async {
        await allTask?.value
    }

    private func record(_ alias: String, _ result: ConnectionTestResult, run: UUID) {
        guard currentRun == run else { return }
        results[alias] = result
        running.remove(alias)
    }

    private func finish() {
        isTestingAll = false
        running.removeAll()
    }
}
```

> Not: `cancelAll()` `allTask`'ı nil yaptığı için iptal testindeki `waitUntilIdle()` hemen döner; iptal edilen görevden sonradan gelen sonuçlar `currentRun` kontrolüyle yok sayılır. Yeniden başlatma testinde ilk görev iptal edilir ve yeni görev beklenir.

`SSHConfigManager/Features/Connect/ConnectionStatusStyle.swift`:

```swift
import SSHConfigKit
import SwiftUI

struct ConnectionStatusStyle {
    let symbol: String
    let tint: Color
    let title: String

    static func style(for status: ConnectionStatus) -> ConnectionStatusStyle {
        switch status {
        case .reachable: .init(symbol: "checkmark.circle.fill", tint: .green, title: String(localized: "status.reachable"))
        case .authenticationRequired: .init(symbol: "key.fill", tint: .yellow, title: String(localized: "status.authenticationRequired"))
        case .hostKeyChanged: .init(symbol: "exclamationmark.shield.fill", tint: .red, title: String(localized: "status.hostKeyChanged"))
        case .unknownHostKey: .init(symbol: "questionmark.circle.fill", tint: .yellow, title: String(localized: "status.unknownHostKey"))
        case .timeout: .init(symbol: "clock.badge.xmark", tint: .red, title: String(localized: "status.timeout"))
        case .dnsFailure: .init(symbol: "network.slash", tint: .red, title: String(localized: "status.dnsFailure"))
        case .connectionRefused: .init(symbol: "xmark.octagon.fill", tint: .red, title: String(localized: "status.connectionRefused"))
        case .other: .init(symbol: "exclamationmark.circle.fill", tint: .secondary, title: String(localized: "status.other"))
        }
    }

    static var testing: ConnectionStatusStyle {
        .init(symbol: "ellipsis.circle", tint: .secondary, title: String(localized: "status.testing"))
    }
}
```

`AppModel`: `let connectionTests: ConnectionTestsModel` alanı init'te `ConnectionTestsModel(runner: processRunner)` ile oluşturulur; `switchConfig`'in `.switched` dalında `connectionTests.clear()` çağrılır.

Kataloğa 9 anahtarı ekle.

- [ ] **Step 5: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/ConnectionTestsModelTests` → PASS (3 kez çalıştır; zamanlamaya bağlı testler kararlı olmalı). Ardından tam `scripts/test-app.sh`.

- [ ] **Step 6: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat(app): bağlantı testi modeli ve durum görünümü"
```

---

### Task 5: Ana pencerede bağlanma ve test (detay çubuğu, sağ tık, Tümünü test et, izin uyarısı)

**Files:**
- Create: `SSHConfigManager/Features/Connect/ConnectionBar.swift`
- Modify: `SSHConfigManager/Features/HostList/DetailView.swift` (host ve dahil edilen görünümlerin üstüne `ConnectionBar`)
- Modify: `SSHConfigManager/Features/HostList/SidebarView.swift` (durum rozeti, Bağlan / Test et menüsü — dahil edilen satırlar dahil)
- Modify: `SSHConfigManager/Features/HostList/MainWindow.swift` (Tümünü test et / Testi durdur; Otomasyon izni uyarısı)
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Modify: `docs/design/manual-test-checklist.md`

**Interfaces:**
- Consumes: `AppModel.connect(alias:)`, `connectableAlias(for:)`, `connectableAliases`, `automationDenied`, `connectionTests`, `commandBuilder`; `ConnectionStatusStyle`.
- Produces: `struct ConnectionBar: View { init(model: AppModel, alias: String?) }` ve `struct ConnectionStatusBadge: View { init(model: ConnectionTestsModel, alias: String, showsTitle: Bool) }`. Otomatik UI testi yoktur (spec §11); doğrulama tam test çalıştırması + elle kontrol.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `action.connect` | Connect | Bağlan |
| `action.test` | Test | Test Et |
| `toolbar.testAll` | Test All | Tümünü Test Et |
| `toolbar.stopTesting` | Stop Testing | Testi Durdur |
| `connect.automationDenied.title` | Permission Needed to Control the Terminal | Terminali Kontrol Etmek İçin İzin Gerekiyor |
| `connect.automationDenied.message` | Allow SSH Config Manager under Privacy & Security → Automation, then try again. | Gizlilik ve Güvenlik → Otomasyon altında SSH Config Manager'a izin verin ve tekrar deneyin. |
| `connect.automationDenied.open` | Open Privacy Settings | Gizlilik Ayarlarını Aç |

- [ ] **Step 1: Görünümleri yaz**

`SSHConfigManager/Features/Connect/ConnectionBar.swift`:

```swift
import SSHConfigKit
import SwiftUI

/// Status badge for one alias: spinner while testing, then the last result.
struct ConnectionStatusBadge: View {
    let model: ConnectionTestsModel
    let alias: String
    let showsTitle: Bool

    var body: some View {
        if model.running.contains(alias) {
            badge(ConnectionStatusStyle.testing, detail: nil)
        } else if let result = model.results[alias] {
            badge(ConnectionStatusStyle.style(for: result.status), detail: result.detail)
        }
    }

    private func badge(_ style: ConnectionStatusStyle, detail: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: style.symbol).foregroundStyle(style.tint)
            if showsTitle { Text(style.title) }
        }
        .help(detail.map { style.title + "\n" + $0 } ?? style.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.title)
    }
}

/// Above the host form: status, Test and Connect (⌘↩). Patterns and Match blocks pass `alias: nil`.
struct ConnectionBar: View {
    let model: AppModel
    let alias: String?

    var body: some View {
        HStack {
            if let alias {
                ConnectionStatusBadge(model: model.connectionTests, alias: alias, showsTitle: true)
                if let detail = model.connectionTests.results[alias]?.detail, !detail.isEmpty {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
            }
            Spacer()
            Button(String(localized: "action.test")) {
                guard let alias else { return }
                Task { await model.connectionTests.test(alias, using: model.commandBuilder) }
            }
            .disabled(alias == nil || model.connectionTests.running.contains(alias ?? ""))
            Button(String(localized: "action.connect")) {
                if let alias { model.connect(alias: alias) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(alias == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

`DetailView.swift` — `content(for:)` içinde host ve dahil edilen içerikler bir `VStack(spacing: 0)` ile sarılır: üstte `ConnectionBar(model: model, alias: model.connectableAlias(for: item))`, altında `Divider()` ve mevcut içerik. Match için çubuk yoktur.

`SidebarView.swift`:
- Her satırın başlığının sağına, `model.connectableAlias(for: row.item)` nil değilse `ConnectionStatusBadge(model: model.connectionTests, alias: alias, showsTitle: false)`.
- Bağlam menüsü: düzenlenebilir satırlar için mevcut menünün en üstüne, dahil edilen satırlar için tek başına şu iki öğe (alias varsa):

```swift
Button(String(localized: "action.connect")) { model.connect(alias: alias) }
Button(String(localized: "action.test")) {
    Task { await model.connectionTests.test(alias, using: model.commandBuilder) }
}
```

`MainWindow.swift`:
- Araç çubuğuna (Kaydet'ten önce):

```swift
ToolbarItem(placement: .primaryAction) {
    if model.connectionTests.isTestingAll {
        Button {
            model.connectionTests.cancelAll()
        } label: {
            Label(String(localized: "toolbar.stopTesting"), systemImage: "stop.circle")
        }
    } else {
        Button {
            model.connectionTests.testAll(model.connectableAliases, using: model.commandBuilder)
        } label: {
            Label(String(localized: "toolbar.testAll"), systemImage: "bolt.horizontal.circle")
        }
        .disabled(model.connectableAliases.isEmpty)
    }
}
```

- Otomasyon izni uyarısı:

```swift
.alert(String(localized: "connect.automationDenied.title"), isPresented: $model.automationDenied) {
    Button(String(localized: "connect.automationDenied.open")) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
    Button(String(localized: "action.close"), role: .cancel) {}
} message: {
    Text(String(localized: "connect.automationDenied.message"))
}
```

Kataloğa 7 anahtarı ekle. `docs/design/manual-test-checklist.md`'ye "Plan 2b — Bağlanma" bölümü ekle:

```markdown
## Plan 2b — Bağlanma

- [ ] `demo` host'u (127.0.0.1, Port 1) seçili → ⌘↩ → Terminal'de `ssh -- demo` açılır ve "Connection refused" ile biter.
- [ ] İlk bağlanmada macOS Otomasyon izni ister; "İzin Verme" seçilirse uygulama "Terminali Kontrol Etmek İçin İzin Gerekiyor" uyarısını ve "Gizlilik Ayarlarını Aç" düğmesini gösterir.
- [ ] Ayarlar'da iTerm2 ve Ghostty seçilip ayrı ayrı bağlanılır; yüklü olmayan bir terminal seçiliyse Terminal kullanılır ve bu söylenir.
- [ ] Test Et → rozet "Bağlantı reddedildi" ve ssh'in mesajı; Tümünü Test Et → tüm hostlarda rozet; Testi Durdur yarıda keser.
- [ ] Sağ tık → Bağlan / Test Et, dahil edilen (🔒) hostlarda da çalışır.
```

- [ ] **Step 2: Derle ve tüm testleri çalıştır**

Run: `scripts/test-app.sh` → PASS (yerelleştirme denetimi dahil), uyarı yok.

- [ ] **Step 3: Elle kontrol**

Geçici config (`Host demo`, `HostName 127.0.0.1`, `Port 1`) ile yeni listeyi uygula. Otomasyon izni penceresi açılırsa kullanıcıya bırak (izni sen verme/reddetme); gözlemleri rapora yaz. Bittiğinde açılan Terminal pencerelerini kapat ve defaults anahtarını sil.

- [ ] **Step 4: Commit**

```bash
git add SSHConfigManager docs/design/manual-test-checklist.md
git commit -m "feat(app): ana pencerede bağlan, test et ve tümünü test et"
```

---

### Task 6: Ayarlar — terminal seçimi ve girişte açılma

**Files:**
- Create: `SSHConfigManager/Features/Connect/LoginItem.swift`
- Modify: `SSHConfigManager/Features/Settings/SettingsView.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Modify: `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/LoginItemTests.swift`

**Interfaces:**
- Consumes: `AppSettings.terminal/setTerminal`, `AppModel.isTerminalInstalled(_:)`, `TerminalChoice`.
- Produces: `@MainActor protocol LoginItemControlling { var isEnabled: Bool { get }; func setEnabled(_ enabled: Bool) throws }`, `struct MainAppLoginItem: LoginItemControlling`, `@MainActor @Observable final class LoginItemToggle { init(item:); private(set) var isOn: Bool; private(set) var errorMessage: String?; func set(_ on: Bool) }`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `settings.connection` | Connection | Bağlantı |
| `settings.terminal` | Terminal | Terminal |
| `settings.terminal.notInstalled %@` | %@ (not installed) | %@ (yüklü değil) |
| `settings.launchAtLogin` | Open at Login | Girişte Aç |
| `settings.launchAtLogin.failed %@` | Could not change the login item: %@ | Giriş öğesi değiştirilemedi: %@ |

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/LoginItemTests.swift`:

```swift
import Testing
@testable import SSH_Config_Manager

@MainActor
private final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
    var failure: Error?
    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
struct LoginItemTests {
    @Test func togglingUpdatesState() {
        let item = FakeLoginItem()
        let toggle = LoginItemToggle(item: item)
        #expect(!toggle.isOn)
        toggle.set(true)
        #expect(toggle.isOn && item.isEnabled)
        #expect(toggle.errorMessage == nil)
    }

    @Test func failureKeepsRealStateAndExplains() {
        struct Boom: Error {}
        let item = FakeLoginItem()
        item.failure = Boom()
        let toggle = LoginItemToggle(item: item)
        toggle.set(true)
        #expect(!toggle.isOn)
        #expect(toggle.errorMessage?.isEmpty == false)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/LoginItemTests` → FAIL (`cannot find 'LoginItemToggle'`).

- [ ] **Step 3: Uygulamayı yaz**

`SSHConfigManager/Features/Connect/LoginItem.swift`:

```swift
import Observation
import ServiceManagement

@MainActor
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct MainAppLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// Reflects the system's real login-item state; a failed change keeps the old state and explains why.
@MainActor
@Observable
final class LoginItemToggle {
    private(set) var isOn: Bool
    private(set) var errorMessage: String?
    @ObservationIgnored private let item: any LoginItemControlling

    init(item: any LoginItemControlling) {
        self.item = item
        isOn = item.isEnabled
    }

    func set(_ on: Bool) {
        do {
            try item.setEnabled(on)
            errorMessage = nil
        } catch {
            let detail = error.localizedDescription
            errorMessage = String(localized: "settings.launchAtLogin.failed \(detail)")
        }
        isOn = item.isEnabled
    }
}
```

`SettingsView.swift` — yeni bölüm (dosya bölümünden sonra); `@State private var loginItem = LoginItemToggle(item: MainAppLoginItem())`:

```swift
Section(String(localized: "settings.connection")) {
    Picker(String(localized: "settings.terminal"), selection: Binding(
        get: { model.settings.terminal },
        set: { model.settings.setTerminal($0) }
    )) {
        ForEach(TerminalChoice.allCases, id: \.self) { choice in
            let name = choice.displayName
            Text(verbatim: model.isTerminalInstalled(choice) ? name : String(localized: "settings.terminal.notInstalled \(name)"))
                .tag(choice)
        }
    }
    Toggle(String(localized: "settings.launchAtLogin"), isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
    if let message = loginItem.errorMessage {
        Text(message).font(.footnote).foregroundStyle(.red)
    }
}
```

Kataloğa 5 anahtarı ekle; manuel listeye ekle: "Ayarlar → Girişte Aç açılır; oturumu kapatıp açınca uygulama menü çubuğunda başlar; kapatılınca başlamaz."

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh` → PASS. Elle: Ayarlar'da terminal listesinde yüklü olmayanların "(yüklü değil)" etiketi; Girişte Aç düğmesini aç-kapat (System Settings → General → Login Items'ta görünür); sonra kapalı bırak.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat(app): ayarlarda terminal seçimi ve girişte açılma"
```

---

### Task 7: Hızlı bağlanma modeli, menü çubuğu ve aktivasyon politikası

**Files:**
- Create: `SSHConfigManager/Features/QuickConnect/QuickConnectModel.swift`
- Create: `SSHConfigManager/Features/QuickConnect/QuickConnectView.swift`
- Create: `SSHConfigManager/Features/QuickConnect/MenuBarContent.swift`
- Modify: `SSHConfigManager/App/AppDelegate.swift` (`quickConnect`, aktivasyon politikası gözlemcisi)
- Modify: `SSHConfigManager/App/SSHConfigManagerApp.swift` (`MenuBarExtra`)
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Modify: `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/QuickConnectModelTests.swift`

**Interfaces:**
- Consumes: `AppModel.connect(alias:)`, `AppModel.connectionTests`, `AppModel.store` (`document.hosts`, `includedHosts`), `SidebarBuilder.subtitle(for:)`, `ConnectionStatusBadge`, `AppDelegate.openMainWindow`, `registersMainWindowOpener`.
- Produces:
  - `struct QuickConnectEntry: Identifiable, Hashable, Sendable { let alias: String; let subtitle: String; let isIncluded: Bool; var id: String }`
  - `@MainActor @Observable final class QuickConnectModel` — `init(app:)`, `var query`, `var selectedIndex`, `private(set) var focusToken`, `var entries: [QuickConnectEntry]`, `var selectedEntry: QuickConnectEntry?`, `func move(by:)`, `func select(_:)`, `@discardableResult func connectSelected() -> Bool`, `func testSelected()`, `func prepareForDisplay()`.
  - `struct QuickConnectView: View { init(model:showsFooter:dismiss:openMainWindow:openSettings:) }`
  - `AppDelegate.quickConnect: QuickConnectModel` (lazy).

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `quick.search.prompt` | Connect to… | Bağlan… |
| `quick.empty` | No matching hosts. | Eşleşen host yok. |
| `quick.hint` | ↩ connect · ⌘↩ test · esc close | ↩ bağlan · ⌘↩ test et · esc kapat |
| `quick.openMainWindow` | Open SSH Config Manager | SSH Config Yöneticisini Aç |
| `quick.settings` | Settings… | Ayarlar… |
| `quick.quit` | Quit | Çık |

- [ ] **Step 1: Başarısız testleri yaz**

`SSHConfigManagerTests/QuickConnectModelTests.swift`:

```swift
import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct QuickConnectModelTests {
    private func model(_ tmp: TempDir, launcher: RecordingLauncher = RecordingLauncher()) throws -> QuickConnectModel {
        try tmp.file(".ssh/work", "Host vpn\n  HostName vpn.example\nHost web\n")
        let app = makeTestModel(tmp, config: """
        Include work
        Host web
          HostName 10.0.0.1
          User deploy
        Host web
          HostName 10.0.0.2
        Host db db2
          HostName db.İstanbul.example
        Host *.prod
          User ops

        """, launcher: launcher)
        return QuickConnectModel(app: app)
    }

    @Test func entriesAreUniqueConnectableAliases() throws {
        let tmp = try TempDir()
        let quick = try model(tmp)
        #expect(quick.entries.map(\.alias) == ["web", "db", "vpn"])
        #expect(quick.entries.map(\.isIncluded) == [false, false, true])
        #expect(quick.entries.first?.subtitle == "deploy@10.0.0.1")
    }

    @Test func searchFiltersAndResetsSelection() throws {
        let tmp = try TempDir()
        let quick = try model(tmp)
        quick.selectedIndex = 2
        quick.query = "istanbul"
        #expect(quick.entries.map(\.alias) == ["db"])
        #expect(quick.selectedEntry?.alias == "db")
        quick.query = "zzz"
        #expect(quick.entries.isEmpty)
        #expect(quick.selectedEntry == nil)
        #expect(!quick.connectSelected())
    }

    @Test func movingWrapsAround() throws {
        let tmp = try TempDir()
        let quick = try model(tmp)
        quick.move(by: -1)
        #expect(quick.selectedEntry?.alias == "vpn")
        quick.move(by: 1)
        #expect(quick.selectedEntry?.alias == "web")
    }

    @Test func connectingUsesTheSelectedAlias() throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let quick = try model(tmp, launcher: launcher)
        quick.move(by: 2)
        #expect(quick.connectSelected())
        #expect(launcher.requests.first?.sshArguments.last == "vpn")
    }

    @Test func prepareForDisplayClearsQueryAndBumpsFocus() throws {
        let tmp = try TempDir()
        let quick = try model(tmp)
        quick.query = "x"
        quick.selectedIndex = 1
        let token = quick.focusToken
        quick.prepareForDisplay()
        #expect(quick.query.isEmpty && quick.selectedIndex == 0)
        #expect(quick.focusToken != token)
    }
}
```

- [ ] **Step 2: Testlerin başarısız olduğunu doğrula**

Run: `scripts/test-app.sh -only-testing:SSHConfigManagerTests/QuickConnectModelTests` → FAIL (`cannot find 'QuickConnectModel'`).

- [ ] **Step 3: Uygulamayı yaz**

`SSHConfigManager/Features/QuickConnect/QuickConnectModel.swift`:

```swift
import Foundation
import Observation
import SSHConfigKit

struct QuickConnectEntry: Identifiable, Hashable, Sendable {
    let alias: String
    let subtitle: String
    let isIncluded: Bool
    var id: String { alias }
}

/// Shared by the menu bar window and the floating panel.
@MainActor
@Observable
final class QuickConnectModel {
    let app: AppModel
    var query = "" {
        didSet { if query != oldValue { selectedIndex = 0 } }
    }
    var selectedIndex = 0
    /// Changes every time the UI is shown, so the view can focus the search field again.
    private(set) var focusToken = UUID()

    init(app: AppModel) {
        self.app = app
    }

    var entries: [QuickConnectEntry] {
        var seen = Set<String>()
        var result: [QuickConnectEntry] = []
        for entry in app.store.document.hosts where !entry.isPattern && seen.insert(entry.alias.lowercased()).inserted {
            result.append(QuickConnectEntry(alias: entry.alias, subtitle: SidebarBuilder.subtitle(for: entry), isIncluded: false))
        }
        for host in app.store.includedHosts where !host.entry.isPattern && seen.insert(host.entry.alias.lowercased()).inserted {
            result.append(QuickConnectEntry(alias: host.entry.alias, subtitle: SidebarBuilder.subtitle(for: host.entry), isIncluded: true))
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }
        return result.filter { $0.alias.localizedStandardContains(trimmed) || $0.subtitle.localizedStandardContains(trimmed) }
    }

    var selectedEntry: QuickConnectEntry? {
        let list = entries
        guard !list.isEmpty else { return nil }
        return list[min(max(selectedIndex, 0), list.count - 1)]
    }

    func move(by delta: Int) {
        let count = entries.count
        guard count > 0 else { selectedIndex = 0; return }
        let current = min(max(selectedIndex, 0), count - 1)
        selectedIndex = ((current + delta) % count + count) % count
    }

    func select(_ entry: QuickConnectEntry) {
        if let index = entries.firstIndex(of: entry) { selectedIndex = index }
    }

    @discardableResult
    func connectSelected() -> Bool {
        guard let entry = selectedEntry else { return false }
        app.connect(alias: entry.alias)
        return true
    }

    func testSelected() {
        guard let entry = selectedEntry else { return }
        let builder = app.commandBuilder
        Task { await app.connectionTests.test(entry.alias, using: builder) }
    }

    func prepareForDisplay() {
        query = ""
        selectedIndex = 0
        focusToken = UUID()
    }
}
```

> `@Observable` sınıflarda `didSet` desteklenir; desteklenmezse `query`'yi `private(set)` yapıp `setQuery(_:)` yöntemiyle aynı davranışı sağla ve raporda belirt.

`SSHConfigManager/Features/QuickConnect/QuickConnectView.swift`:

```swift
import AppKit
import SwiftUI

struct QuickConnectView: View {
    @Bindable var model: QuickConnectModel
    let showsFooter: Bool
    let dismiss: () -> Void
    let openMainWindow: () -> Void
    let openSettings: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(String(localized: "quick.search.prompt"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($searchFocused)
                .onKeyPress(.upArrow) { model.move(by: -1); return .handled }
                .onKeyPress(.downArrow) { model.move(by: 1); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.command) {
                        model.testSelected()
                    } else if model.connectSelected() {
                        dismiss()
                    }
                    return .handled
                }
            Divider()
            if model.entries.isEmpty {
                Text(String(localized: "quick.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.entries) { entry in
                                row(entry).id(entry.id)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: model.selectedIndex) {
                        if let id = model.selectedEntry?.id { proxy.scrollTo(id) }
                    }
                }
            }
            Divider()
            Text(String(localized: "quick.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            if showsFooter {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    footerButton(String(localized: "quick.openMainWindow")) { openMainWindow(); dismiss() }
                    footerButton(String(localized: "quick.settings")) { openSettings(); dismiss() }
                    footerButton(String(localized: "quick.quit")) { NSApp.terminate(nil) }
                }
                .padding(6)
            }
        }
        .frame(width: 420)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    private func row(_ entry: QuickConnectEntry) -> some View {
        let selected = model.selectedEntry == entry
        return HStack(spacing: 8) {
            ConnectionStatusBadge(model: model.app.connectionTests, alias: entry.alias, showsTitle: false)
                .frame(width: 16)
            Text(verbatim: entry.alias).fontWeight(.medium)
            if entry.isIncluded { Image(systemName: "lock").foregroundStyle(.secondary).accessibilityHidden(true) }
            Spacer()
            Text(verbatim: entry.subtitle).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.select(entry)
            if model.connectSelected() { dismiss() }
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }
}
```

`SSHConfigManager/Features/QuickConnect/MenuBarContent.swift`:

```swift
import SwiftUI

struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        QuickConnectView(
            model: appDelegate.quickConnect,
            showsFooter: true,
            dismiss: { dismiss() },
            openMainWindow: { appDelegate.openMainWindow?() },
            openSettings: { openSettings(); NSApp.activate() })
            .onAppear { appDelegate.quickConnect.prepareForDisplay() }
    }
}
```

`AppDelegate.swift` — eklemeler:

```swift
private(set) lazy var quickConnect = QuickConnectModel(app: model)

func applicationDidFinishLaunching(_ notification: Notification) {
    guard !TestEnvironment.isRunningTests else { return }
    // The Dock icon is shown only while the main window is open (spec §6.2).
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
        let isMain = (note.object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") ?? false
        guard isMain else { return }
        MainActor.assumeIsolated { NSApp.setActivationPolicy(.accessory) }
    }
    NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
        let isMain = (note.object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") ?? false
        guard isMain else { return }
        MainActor.assumeIsolated { NSApp.setActivationPolicy(.regular) }
    }
}
```

`SSHConfigManagerApp.swift` — sahnelere `MenuBarExtra` eklenir (etiket görünümü uygulama açılır açılmaz var olduğu için açıcıyı da kaydeder):

```swift
MenuBarExtra {
    MenuBarContent(appDelegate: appDelegate)
} label: {
    Image(systemName: "terminal")
        .accessibilityLabel(String(localized: "app.title"))
        .registersMainWindowOpener(appDelegate)
}
.menuBarExtraStyle(.window)
```

Kataloğa 6 anahtarı ekle. Manuel listeye ekle:

```markdown
- [ ] Menü çubuğundaki ikon → arama kutusu odaklı açılır; yaz → ↑↓ → ↩ ile bağlanır ve pencere kapanır; ⌘↩ seçili host'u test eder (rozet); esc kapatır.
- [ ] Dahil edilen hostlar 🔒 ile listede; desenler (`*`) yok; aynı alias bir kez.
- [ ] Ana pencere kapatılınca Dock simgesi kaybolur, menü çubuğu kalır; "SSH Config Yöneticisini Aç" pencereyi ve Dock simgesini geri getirir.
- [ ] Menüden "Çık" kaydedilmemiş değişiklik varken kaydetme uyarısını gösterir.
```

- [ ] **Step 4: Testlerin geçtiğini doğrula**

Run: `scripts/test-app.sh` → PASS. Elle: yukarıdaki dört madde (geçici config ile).

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat(app): menü çubuğundan hızlı bağlanma ve Dock simgesi yönetimi"
```

---

### Task 8: Global kısayol (⌥⌘S) ve yüzen hızlı bağlanma paneli

**Files:**
- Modify: `project.yml` (`KeyboardShortcuts` paketi)
- Create: `SSHConfigManager/Features/QuickConnect/QuickConnectPanel.swift`
- Modify: `SSHConfigManager/App/AppDelegate.swift` (paneli ve kısayolu kurar)
- Modify: `SSHConfigManager/Features/Settings/SettingsView.swift` (kısayol kaydedici)
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Modify: `docs/design/manual-test-checklist.md`

**Interfaces:**
- Consumes: `QuickConnectModel`, `QuickConnectView`, `AppDelegate.openMainWindow`.
- Produces: `extension KeyboardShortcuts.Name { static let quickConnect }` (varsayılan ⌥⌘S), `@MainActor final class QuickConnectPanelController: NSObject, NSWindowDelegate { init(model:openMainWindow:openSettings:); func toggle(); func show(); func close() }`. AppKit paneli otomatik test edilmez; doğrulama derleme + elle.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `settings.shortcut` | Quick connect shortcut | Hızlı bağlanma kısayolu |

- [ ] **Step 1: Paketi ekle**

`project.yml`:

```yaml
packages:
  SSHConfigKit:
    path: Packages/SSHConfigKit
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 2.0.0
```

ve uygulama target'ının `dependencies` listesine `- package: KeyboardShortcuts`. `xcodegen generate` + bir derleme ile paketin çözümlendiğini doğrula (ağ erişimi gerekir).

- [ ] **Step 2: Paneli yaz**

`SSHConfigManager/Features/QuickConnect/QuickConnectPanel.swift`:

```swift
import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let quickConnect = Self("quickConnect", default: .init(.s, modifiers: [.option, .command]))
}

/// A borderless panel that can take keyboard focus.
final class QuickConnectPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Spotlight-like floating panel opened by the global shortcut (spec §6.3). Closes on Esc,
/// after connecting, and when it loses focus.
@MainActor
final class QuickConnectPanelController: NSObject, NSWindowDelegate {
    private let panel: QuickConnectPanel
    private let model: QuickConnectModel

    init(model: QuickConnectModel, openMainWindow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        panel = QuickConnectPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            panel.standardWindowButton($0)?.isHidden = true
        }
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickConnectView(
            model: model,
            showsFooter: false,
            dismiss: { [weak self] in self?.close() },
            openMainWindow: openMainWindow,
            openSettings: openSettings))
    }

    func toggle() {
        panel.isVisible ? close() : show()
    }

    func show() {
        model.prepareForDisplay()
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
```

`AppDelegate.swift` — `var panelController: QuickConnectPanelController?`; `applicationDidFinishLaunching` içinde (test host'ta kurulmaz; mevcut `guard`'dan sonra):

```swift
panelController = QuickConnectPanelController(
    model: quickConnect,
    openMainWindow: { [weak self] in self?.openMainWindow?() },
    openSettings: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) })
KeyboardShortcuts.onKeyUp(for: .quickConnect) { [weak self] in
    MainActor.assumeIsolated { self?.panelController?.toggle() }
}
```

> `KeyboardShortcuts.onKeyUp` kapanışı zaten ana aktörde çağrılıyorsa `MainActor.assumeIsolated` gereksiz olabilir; derleyici ne isterse onu kullan. Ayarlar penceresini açmak için `showSettingsWindow:` seçicisi macOS 14+'ta çalışır; çalışmazsa paneli kapatıp `openMainWindow` ile yetin ve raporda belirt.

`SettingsView.swift` — "Bağlantı" bölümüne (`import KeyboardShortcuts`):

```swift
KeyboardShortcuts.Recorder(String(localized: "settings.shortcut"), name: .quickConnect)
```

Kataloğa anahtarı ekle; manuel listeye ekle:

```markdown
- [ ] Herhangi bir uygulamadayken ⌥⌘S → ekranın ortasında hızlı bağlanma paneli, arama kutusu odaklı; ↩ bağlar ve panel kapanır; esc ve başka yere tıklamak paneli kapatır; ⌥⌘S ikinci kez basınca kapanır.
- [ ] Ayarlar'da kısayol değiştirilir (ör. ⌃⌥Space) → yeni kısayol çalışır, eskisi çalışmaz; kaydedici temizlenirse kısayol devre dışı kalır.
```

- [ ] **Step 3: Derle, test et, elle kontrol**

Run: `scripts/test-app.sh` → PASS, uyarı yok. Elle: yukarıdaki iki madde (geçici config). Bitince defaults anahtarını sil; Ayarlar'da kısayolu varsayılana (⌥⌘S) geri al.

- [ ] **Step 4: Commit**

```bash
git add project.yml SSHConfigManager docs/design/manual-test-checklist.md
git commit -m "feat(app): global kısayol ile hızlı bağlanma paneli"
```

---

## Plan 2b tamamlandığında

- `xcrun swift test --package-path Packages/SSHConfigKit` ve `scripts/test-app.sh` yeşil.
- Uygulamadan Terminal, iTerm2 veya Ghostty ile bağlanılır; hostlar tek tek veya toplu test edilir; menü çubuğu ve ⌥⌘S paneliyle birkaç tuşla bağlanılır; ana pencere kapatılınca uygulama menü çubuğunda kalır; girişte açılabilir.
- Sıradaki: Plan 3 (Known Hosts) ve Plan 4 (Anahtar yönetimi).
