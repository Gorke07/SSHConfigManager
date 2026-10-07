# Plan 5 — Son Rötuşlar ve Dağıtım: Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** v1'i dağıtıma hazır hale getirmek: önceki planlardan kalan öncelikli eksikler (dış değişiklikte kayıtlı host listesi, kaydedilmemiş host için açıklama, girişte açılışta yalnızca menü çubuğu, giriş öğesi onayı), `os.Logger` ile güvenli kayıt, "Hakkında" ekranında üçüncü parti lisans, ve imzalı/notarize edilmiş `.dmg` üreten sürüm betiği.

**Architecture:** Paket tarafında `ConfigStore` dış değişiklikte (kaydedilmemiş düzenleme varken) yalnızca "ssh'in okuduğu" görünümü (`savedDocument`, `savedIncludedHosts`) yeniler; çakışma tespiti için `diskText`/parmak izi değişmez. Uygulama tarafında giriş öğesi durumu `LoginItemControlling` üzerinden test edilebilir, girişte açılış Apple Event'inden anlaşılır. Kayıtlar `AppLog` (tek `Logger` alt sistemi) ile yazılır ve parola, anahtar, süreç argümanı/ortamı içermez. Sürüm betiği (`scripts/build-release.sh`) Release derler; `SIGN_IDENTITY` verilmezse ad-hoc imzalar, verilirse Developer ID + zaman damgası; `NOTARY_PROFILE` verilirse `.dmg`'yi notarize eder ve damgalar.

**Tech Stack:** Swift 6.4 (Xcode 27.0), SwiftUI (`CommandGroup`), AppKit (`orderFrontStandardAboutPanel`, `NSAppleEventManager`), ServiceManagement, `os.Logger`, `codesign`, `xcrun notarytool`, `xcrun stapler`, `hdiutil`, XcodeGen.

**Spec:** `docs/design/2026-10-07-ssh-config-manager-design.md` — §2 (dağıtım: Developer ID, notarize, Hardened Runtime, `.dmg`), §3.3 (girişte başlat), §6.1 (kapatınca menü çubuğunda devam), §6.6 (üçüncü parti lisanslar "Hakkında" ekranında), §10 (loglama: `os.Logger`, alt sistem bundle ID; parola/anahtar/argüman/ortam loglanmaz), §13 madde 10. Devreden konular: `docs/design/2026-10-07-plan-2b-followups.md` "Öncelikli" bölümü (4 madde) bu planın Task 2–4'üdür; Plan 4'ten devreden Anahtarlar penceresi bildirimleri Task 1'dir (`docs/design/2026-10-08-plan-4-followups.md`).

## Global Constraints

- macOS 26.0; Swift 6 dil modu, `SWIFT_STRICT_CONCURRENCY = complete`. Toolchain: Xcode 27.0 (Swift 6.4). Yeni bağımlılık yok.
- Bundle ID `tr.com.mess.SSHConfigManager`; sürüm `1.0.0` (build `1`).
- Release: Hardened Runtime açık; App Sandbox kapalı; `com.apple.security.automation.apple-events` yetkisi korunur.
- Sürüm betiği hiçbir sırrı depoya yazmaz: imza kimliği `SIGN_IDENTITY`, notarize profili `NOTARY_PROFILE` (`xcrun notarytool store-credentials` ile kullanıcının keychain'inde) ortam değişkenleriyle verilir. Çıktılar `build/` altına yazılır (git'e girmez).
- Loglama: `Logger(subsystem: "tr.com.mess.SSHConfigManager", category: …)`; dosya yolları ve ssh stderr `privacy: .private`; parola, anahtar içeriği, süreç argümanları/ortamı **hiç** loglanmaz.
- Kullanıcıya görünen her metin `String(localized:)` + `Localizable.xcstrings` (en + tr, `translated`); lisans metni çevrilmez (`verbatim`). `scripts/check-localization.py` denetler.
- **Testler gerçek `~/.ssh`'a, `~/Library`'ye, `UserDefaults.standard`'a, giriş öğelerine, agent'a, keychain'e dokunmaz.** Sürüm betiği testte yalnızca ad-hoc modda çalıştırılır; ajanlar notarize etmez, imza kimliği aramaz/oluşturmaz.
- **Kullanıcı Ghostty içinde çalışıyor:** Ghostty/Terminal/iTerm2 ya da pencereleri asla kapatılmaz/öldürülmez; sentetik tuş vuruşu yok; yalnızca kendi başlattığın süreçler PID ile sonlandırılır; izin pencerelerine yanıt verilmez; uygulama elle açılmaz (oluşturulan `.dmg` bağlanıp açılmaz, yalnızca `hdiutil verify`/`imageinfo` ile denetlenir).

## Review Focus

1. **Kaydedilmemiş düzenleme varken dosya dışarıdan değişir** — dışarıdan silinen host artık bağlanabilir görünmez; çakışma uyarısı ve "üzerine yazma" koruması aynen çalışır (Task 2'de test).
2. **Seçili host kaydedilmemiş (yeni ya da yeniden adlandırılmış)** — Bağlan/Test neden pasif açıklanır; desenlerde ve Match bloklarında not çıkmaz (Task 3'te test).
3. **Giriş öğesi Sistem Ayarları'nda onay bekliyor ya da kullanıcı orada kapatmış** — anahtar gerçek durumu gösterir, açıklama ve Sistem Ayarları kısayolu sunulur (Task 4'te test).
4. **Hata ayrıntısında yol ya da ssh stderr var** — loglarda `private` olarak işaretlenir; parola ve süreç argümanı hiçbir log çağrısına geçmez (Task 5'te test + kod incelemesi).
5. **İmza kimliği/notarize profili yok** — sürüm betiği yine çalışır (ad-hoc, notarize atlanır ve söylenir); varsa her adım doğrulanır, bir adım başarısız olursa betik sıfırdan farklı kodla durur (Task 6'da ad-hoc çalıştırma).

---

### Task 1: Anahtarlar penceresinde bildirimler (Plan 4'ten devreden)

**Files:**
- Modify: `SSHConfigManager/Features/Keys/KeysModel.swift`, `KeySheets.swift`, `KeysWindow.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Test: `SSHConfigManagerTests/KeysModelTests.swift`

**Interfaces:**
- Consumes: `KeysModel.upload(_:alias:)`, `generate(...)`, `AppModel.uploadKey`, `app.errorMessage` / `fallbackNotice` / `automationDenied`.
- Produces: `KeysModel.notice: String?` (window-level, survives a sheet closing), `KeysModel.noticeIsAutomationDenied: Bool`; `errorMessage` stays sheet-scoped (cleared by the sheets' `onDisappear`).

Bağlam: `docs/design/2026-10-08-plan-4-followups.md` "Plan 5'in ilk görevi". Bugün yedeğe düşme bildirimi `errorMessage`'a yazılıyor ve form kapanırken `.onDisappear` onu siliyor (hiç görünmüyor); "oluşturuldu ama atanmadı" durumunda form açık kalıyor ve yeniden Oluştur ikinci bir anahtar üretiyor; `upload` ana penceredeki ilgisiz uyarıları da siliyor.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `keys.notice.title` | Note | Bilgi |

- [ ] **Step 1: Write the failing tests**

Append inside `KeysModelTests` (adapt to the existing helpers there):

```swift
    @Test func fallbackNoticeSurvivesTheSheetAndAppAlertsAreRestored() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher, isTerminalInstalled: { $0 == .terminal })
        model.settings.setTerminal(.ghostty)                     // not installed → falls back to Terminal
        model.errorMessage = "unrelated main-window error"
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        await model.keys.refresh()
        let row = try #require(model.keys.rows.first)
        guard case .fellBack = model.keys.upload(row, alias: "web") else { Issue.record("expected fellBack"); return }
        model.keys.errorMessage = nil                             // what the sheet's onDisappear does
        #expect(model.keys.notice == model.fallbackNoticeText(for: .ghostty))
        #expect(model.errorMessage == "unrelated main-window error")
        #expect(model.fallbackNotice == nil)
    }

    @Test func automationDeniedBecomesAWindowNoticeWithTheSettingsButton() async throws {
        let tmp = try TempDir()
        let launcher = RecordingLauncher()
        launcher.error = .automationDenied
        let model = makeTestModel(tmp, config: "Host web\n", launcher: launcher)
        _ = await model.keys.generate(type: .ed25519, fileName: "k", comment: "c", passphrase: "", assignTo: nil)
        await model.keys.refresh()
        _ = model.keys.upload(try #require(model.keys.rows.first), alias: "web")
        #expect(model.keys.notice == String(localized: "connect.automationDenied.message"))
        #expect(model.keys.noticeIsAutomationDenied)
        #expect(model.automationDenied == false)
    }

```

Also update the existing "form became dirty during generation" test in `KeysModelTests`: it must now expect `generate` to return `true` (the sheet closes), `model.keys.notice` to start with `String(localized: "keys.error.createdNotAssigned \(path)")` for the created path, and its wait loop to stop after a 30 s `ContinuousClock` deadline with `Issue.record("key file never appeared")` instead of looping forever.

(If `AppModel` has no `fallbackNoticeText(for:)`, compare against `String(localized: "connect.fellBack \(TerminalChoice.ghostty.displayName)")`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/KeysModelTests`
Expected: FAIL to build — `no member 'notice'`.

- [ ] **Step 3: Implement**

`KeysModel`:

```swift
    /// Window-level message (not cleared when a sheet closes): fallback notices, Automation
    /// denial, "created but not assigned".
    var notice: String?
    var noticeIsAutomationDenied = false
```

`upload(_:alias:)` — snapshot `app.errorMessage`, `app.fallbackNotice`, `app.automationDenied` before calling `app.uploadKey`, map the outcome (`.launched`: nothing; `.fellBack`: `notice = app.fallbackNotice`; `.failed(.automationDenied)`: `notice = String(localized: "connect.automationDenied.message")`, `noticeIsAutomationDenied = true`; `.failed(.failed)`: `errorMessage = app.errorMessage` — shown inside the sheet), then **restore** the three snapshot values instead of setting them to nil.

`generate(...)` — when the key was created but the assignment threw, set `notice` (the existing createdNotAssigned text), not `errorMessage`, and return `true` so the sheet closes.

`UploadKeySheet` — close on `.launched`, `.fellBack` and `.failed(.automationDenied)`; stay open (inline `errorMessage`) on `.failed(.failed)`.

`KeysWindow` — a second alert, presented when `sheet == nil && keys.notice != nil`:

```swift
        .alert(
            String(localized: "keys.notice.title"),
            isPresented: Binding(get: { sheet == nil && keys.notice != nil },
                                 set: { if !$0 { keys.notice = nil; keys.noticeIsAutomationDenied = false } })
        ) {
            if keys.noticeIsAutomationDenied {
                Button(String(localized: "connect.automationDenied.open")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Button(String(localized: "action.close"), role: .cancel) {}
        } message: {
            Text(verbatim: keys.notice ?? "")
        }
```

Add the catalog key.

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh` — PASS; `pgrep -fl "ssh-agent -D -a /tmp/sshcm"` empty.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "fix: Keys window notices survive sheets; uploads leave main-window alerts alone"
```

---

### Task 2: Dış değişiklikte "ssh'in okuduğu" görünümü güncel tut

**Files:**
- Modify: `Packages/SSHConfigKit/Sources/SSHConfigKit/Stores/ConfigStore.swift`
- Test: `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `ConfigStore` (`fileDidChange()`, `savedDocument`, `savedIncludedHosts`, `diskText`, `onDiskStateChange`, `externalChangePending`), `IncludeResolver.includedHosts(of:rootFile:)`.
- Produces: `fileDidChange()` kaydedilmemiş düzenleme varken `savedDocument`/`savedIncludedHosts`'u yeni disk metninden yeniden üretir ve `onDiskStateChange` çağırır; `diskText`, `document`, parmak izi değişmez.

- [ ] **Step 1: Write the failing test**

Append inside `ConfigStoreTests`:

```swift
    @Test func externalChangeWithLocalEditsRefreshesWhatSshReads() async throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n  User u\nHost gone\n  User x\n")
        let store = makeStore(tmp)
        var notified = 0
        store.onDiskStateChange = { notified += 1 }
        try addPort(store)
        try tmp.file("config", "Host a\n  User u\nHost added\n  User y\n")

        store.fileDidChange()

        #expect(store.externalChangePending)
        #expect(store.savedDocument.hosts.map(\.alias) == ["a", "added"])
        #expect(notified == 1)
        // The edit and the conflict guard are untouched.
        #expect(store.document.hosts.map(\.alias) == ["a", "gone"])
        #expect(store.diskText == "Host a\n  User u\nHost gone\n  User x\n")
        await #expect(throws: ConfigStoreError.conflict) { try await store.save() }
        #expect(try tmp.read("config") == "Host a\n  User u\nHost added\n  User y\n")
    }

    @Test func externalChangeToInvalidUTF8KeepsTheOldSavedView() throws {
        let tmp = try TempDir()
        try tmp.file("config", "Host a\n")
        let store = makeStore(tmp)
        try addPort(store)
        try Data([0xFF, 0xFE]).write(to: tmp.url.appending(path: "config"))
        store.fileDidChange()
        #expect(store.externalChangePending)
        #expect(store.savedDocument.hosts.map(\.alias) == ["a"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter ConfigStoreTests`
Expected: FAIL — `savedDocument` still lists `gone`.

- [ ] **Step 3: Write minimal implementation**

In `ConfigStore.fileDidChange()`, replace the `if hasUnsavedChanges { externalChangePending = true }` branch with:

```swift
        if hasUnsavedChanges {
            externalChangePending = true
            refreshSavedView()
        } else {
            load()
        }
```

and add:

```swift
    /// The file changed under unsaved edits: keep `diskText` and the fingerprint (so Save still
    /// detects the conflict) but show what ssh now reads, so Connect/Test never offer removed hosts.
    private func refreshSavedView() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(validating: data, as: UTF8.self) else { return }
        savedDocument = ConfigDocument(parsing: text)
        savedIncludedHosts = includeResolver.includedHosts(of: savedDocument, rootFile: fileURL)
        onDiskStateChange?()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcrun swift test --package-path Packages/SSHConfigKit --filter ConfigStoreTests`, then the whole package, then `bash scripts/test-app.sh` (the app observes `onDiskStateChange`).
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/SSHConfigKit
git commit -m "fix(kit): external changes under unsaved edits refresh what ssh reads"
```

---

### Task 3: Kaydedilmemiş host için "Bağlanmak için kaydedin" açıklaması

**Files:**
- Modify: `SSHConfigManager/Shared/AppModel.swift`
- Modify: `SSHConfigManager/Features/Connect/ConnectionBar.swift`
- Modify: `SSHConfigManager/Features/HostList/DetailView.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Test: `SSHConfigManagerTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `AppModel.connectableAlias(for:)`, `savedAlias(_:)`, `SidebarBuilder.hostEntry(for:in:)`, `store.document`.
- Produces: `AppModel.isUnsavedHost(_ item: SidebarItem) -> Bool` (editable, non-pattern host whose alias is not in the saved file); `ConnectionBar(model:alias:showsSaveHint:)` (`showsSaveHint` default `false`).

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `connect.saveToConnect` | Save the file to connect to or test this host. | Bu host'a bağlanmak ya da test etmek için dosyayı kaydedin. |

- [ ] **Step 1: Write the failing test**

Append inside the `AppModelTests` suite:

```swift
    @Test func unsavedHostsAreRecognizedButPatternsAndSavedHostsAreNot() throws {
        let tmp = try TempDir()
        let model = makeTestModel(tmp, config: "Host saved\n  HostName 10.0.0.1\nHost *\n  User me\n")
        let added = try HostCommands.addHost(to: model.store)
        #expect(model.isUnsavedHost(added))
        #expect(!model.isUnsavedHost(.host(alias: "saved", occurrence: 0)))
        #expect(!model.isUnsavedHost(.host(alias: "*", occurrence: 0)))
        #expect(!model.isUnsavedHost(.match(index: 0)))
    }
```

(`SidebarItem.host(alias:occurrence:)` counts occurrences of the same alias from 0.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/AppModelTests`
Expected: FAIL to build — `no member 'isUnsavedHost'`.

- [ ] **Step 3: Write minimal implementation**

`AppModel.swift`:

```swift
    /// An editable, non-pattern host that is not in the saved file yet (new or renamed):
    /// Connect and Test are off until it is saved.
    func isUnsavedHost(_ item: SidebarItem) -> Bool {
        guard case .host = item,
              let entry = SidebarBuilder.hostEntry(for: item, in: store.document), !entry.isPattern else { return false }
        return savedAlias(entry.alias) == nil
    }
```

`ConnectionBar.swift` — add `var showsSaveHint = false` after `alias`, and in the `VStack` after `buttons`:

```swift
            if showsSaveHint {
                Text(String(localized: "connect.saveToConnect"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

`DetailView.swift` — the `.host` case: `ConnectionBar(model: model, alias: model.connectableAlias(for: item), showsSaveHint: model.isUnsavedHost(item))`.

Add the catalog key.

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat: explain why Connect is off for unsaved hosts"
```

---

### Task 4: Giriş öğesi onayı ve girişte yalnızca menü çubuğunda başlama

**Files:**
- Modify: `SSHConfigManager/Features/Connect/LoginItem.swift`
- Modify: `SSHConfigManager/Features/Settings/SettingsView.swift`
- Modify: `SSHConfigManager/App/AppDelegate.swift`
- Create: `SSHConfigManager/App/LaunchContext.swift`
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`, `docs/design/manual-test-checklist.md`
- Test: `SSHConfigManagerTests/LoginItemTests.swift`

**Interfaces:**
- Consumes: `LoginItemControlling`, `LoginItemToggle`, `MainAppLoginItem`.
- Produces: `LoginItemControlling.needsApproval: Bool`; `LoginItemToggle.needsApproval`, `LoginItemToggle.refresh()`; `enum LaunchContext { static func isLoginItemLaunch(propertyData: OSType?) -> Bool; static func currentLaunchIsLoginItem() -> Bool }`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `settings.launchAtLogin.needsApproval` | macOS needs your approval in System Settings → General → Login Items. | macOS'un Sistem Ayarları → Genel → Giriş Öğeleri'nde onayınız gerekiyor. |
| `settings.launchAtLogin.openSettings` | Open Login Items | Giriş Öğelerini Aç |

- [ ] **Step 1: Write the failing tests**

In `SSHConfigManagerTests/LoginItemTests.swift`, give `FakeLoginItem` `var needsApproval = false`, and add:

```swift
    @Test func approvalStateIsShownAndRefreshed() {
        let item = FakeLoginItem()
        let toggle = LoginItemToggle(item: item)
        #expect(!toggle.needsApproval)
        item.needsApproval = true
        item.isEnabled = false
        toggle.refresh()
        #expect(toggle.needsApproval && !toggle.isOn)
        item.needsApproval = false
        item.isEnabled = true          // the user approved in System Settings
        toggle.refresh()
        #expect(!toggle.needsApproval && toggle.isOn)
    }

    @Test func loginItemLaunchesAreRecognized() {
        #expect(LaunchContext.isLoginItemLaunch(propertyData: OSType(keyAELaunchedAsLogInItem)))
        #expect(!LaunchContext.isLoginItemLaunch(propertyData: nil))
        #expect(!LaunchContext.isLoginItemLaunch(propertyData: OSType(keyAELaunchedAsServiceItem)))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/LoginItemTests`
Expected: FAIL to build.

- [ ] **Step 3: Write minimal implementation**

`LoginItem.swift`:

```swift
@MainActor
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    /// Registered but waiting for the user's approval in System Settings → Login Items.
    var needsApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct MainAppLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    …
}
```

`LoginItemToggle`: `private(set) var needsApproval: Bool` (initialized from the item), set after every `set(_:)`, and:

```swift
    /// Re-reads the system state (the user may have changed it in System Settings).
    func refresh() {
        isOn = item.isEnabled
        needsApproval = item.needsApproval
    }
```

`SettingsView.swift` — under the launch-at-login toggle:

```swift
                if loginItem.needsApproval {
                    Text(String(localized: "settings.launchAtLogin.needsApproval")).font(.footnote).foregroundStyle(.secondary)
                    Button(String(localized: "settings.launchAtLogin.openSettings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
```

and on the `Form`: `.onAppear { loginItem.refresh() }` plus `.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }`.

`SSHConfigManager/App/LaunchContext.swift`:

```swift
import AppKit

/// Whether macOS started the app as a login item (spec §3.3: then it starts in the menu bar only).
enum LaunchContext {
    static func isLoginItemLaunch(propertyData: OSType?) -> Bool {
        propertyData == OSType(keyAELaunchedAsLogInItem)
    }

    /// Reads the launch Apple Event; call from `applicationWillFinishLaunching` / `DidFinishLaunching`.
    @MainActor
    static func currentLaunchIsLoginItem() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let data = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        return isLoginItemLaunch(propertyData: data)
    }
}
```

`AppDelegate.swift` — store `private var launchedAsLoginItem = false`; in `applicationWillFinishLaunching(_:)` (add it) set `launchedAsLoginItem = !TestEnvironment.isRunningTests && LaunchContext.currentLaunchIsLoginItem()`; at the end of `applicationDidFinishLaunching`:

```swift
        if launchedAsLoginItem {
            // Started at login: stay in the menu bar; the main window opens from there or the Dock.
            Task { @MainActor in
                for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true { window.close() }
                NSApp.setActivationPolicy(.accessory)
            }
        }
```

Add the catalog keys and append to `docs/design/manual-test-checklist.md`:

```markdown
## Plan 5 — Son rötuşlar

- [ ] Girişte açıl açıkken oturumu kapatıp açın: uygulama ana pencere açmadan yalnızca menü çubuğunda başlıyor; Dock'ta ikon yok.
- [ ] Girişte açıl'ı açınca macOS onay isterse Ayarlar'da açıklama ve "Giriş Öğelerini Aç" görünüyor; onayladıktan sonra Ayarlar'a dönünce anahtar açık.
- [ ] Sistem Ayarları → Giriş Öğeleri'nden kapatılınca Ayarlar'a dönüldüğünde anahtar kapalı görünüyor.
- [ ] Yeni bir host ekleyip kaydetmeden seçince Bağlan/Test pasif ve "Bu host'a bağlanmak ya da test etmek için dosyayı kaydedin" notu var.
- [ ] Kaydedilmemiş düzenleme varken config'ten bir host'u terminalden silin: o host artık menü çubuğu listesinde ve ⌥⌘S panelinde yok; "Dosya dışarıdan değişti" bandı görünüyor.
```

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests docs/design/manual-test-checklist.md
git commit -m "feat: login item approval state; start in the menu bar at login"
```

---

### Task 5: `os.Logger` ile güvenli kayıt ve "Hakkında" ekranı

**Files:**
- Create: `SSHConfigManager/Shared/AppLog.swift`
- Create: `SSHConfigManager/App/AboutPanel.swift`
- Modify: `SSHConfigManager/App/SSHConfigManagerApp.swift` (`.commands`)
- Modify: call sites that turn errors into user messages: `SSHConfigManager/Shared/AppModel.swift` (`launch` failures), `SSHConfigManager/Features/HostList/SaveFlowModel.swift` (save failures), `SSHConfigManager/App/AppDelegate.swift` (quit-save failure), `SSHConfigManager/Features/KnownHosts/KnownHostsModel.swift` + `HostKeyRemoval.swift` (deletion failures), `SSHConfigManager/Features/Keys/KeysModel.swift` (`perform` failures), `SSHConfigManager/Features/Settings/BackupsView.swift` (restore failures)
- Modify: `SSHConfigManager/Shared/Localization/Localizable.xcstrings`
- Test: `SSHConfigManagerTests/AboutPanelTests.swift`

**Interfaces:**
- Produces: `enum AppLog { static func error(_ category: AppLog.Category, _ error: any Error) ; enum Category: String { case save, connect, knownHosts, keys, backups } ; static func describe(_ error: any Error) -> (kind: String, detail: String) }`; `enum AboutPanel { static var credits: NSAttributedString; static func show() }`.

Katalog anahtarları:

| anahtar | en | tr |
|---|---|---|
| `about.menu` | About SSH Config Manager | SSH Config Manager Hakkında |
| `about.thirdParty` | Third-party software | Üçüncü parti yazılımlar |

- [ ] **Step 1: Write the failing test**

`SSHConfigManagerTests/AboutPanelTests.swift`:

```swift
import AppKit
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct AboutPanelTests {
    @Test func creditsListKeyboardShortcutsWithItsMITLicense() {
        let text = AboutPanel.credits.string
        #expect(text.contains(String(localized: "about.thirdParty")))
        #expect(text.contains("KeyboardShortcuts"))
        #expect(text.contains("MIT License"))
        #expect(text.contains("Copyright (c) Sindre Sorhus"))
    }

    @Test func logDescriptionsNameTheErrorKindWithoutItsPayloadInThePublicPart() {
        let described = AppLog.describe(KeyManagerError.failed("Load key \"/Users/x/.ssh/id\": bad"))
        #expect(described.kind == "KeyManagerError.failed")
        #expect(!described.kind.contains("/Users"))
        #expect(described.detail.contains("/Users/x/.ssh/id"))   // logged as .private only
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-app.sh -only-testing:SSHConfigManagerTests/AboutPanelTests`
Expected: FAIL to build.

- [ ] **Step 3: Write minimal implementation**

`SSHConfigManager/Shared/AppLog.swift`:

```swift
import Foundation
import os

/// One logging subsystem (spec §10). Only error kinds are public; details (paths, ssh stderr) are
/// private; passphrases, key contents and process arguments/environment are never passed here.
enum AppLog {
    enum Category: String {
        case save, connect, knownHosts, keys, backups
    }

    private static let subsystem = "tr.com.mess.SSHConfigManager"

    static func error(_ category: Category, _ error: any Error) {
        let (kind, detail) = describe(error)
        Logger(subsystem: subsystem, category: category.rawValue)
            .error("\(kind, privacy: .public): \(detail, privacy: .private)")
    }

    /// `Type.case` (public) and the full description (private).
    static func describe(_ error: any Error) -> (kind: String, detail: String) {
        let detail = String(describing: error)
        let caseName = detail.prefix { $0 != "(" }
        return ("\(type(of: error)).\(caseName)", detail)
    }
}
```

`SSHConfigManager/App/AboutPanel.swift`:

```swift
import AppKit

enum AboutPanel {
    static let keyboardShortcutsLicense = """
    MIT License

    Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    /// Spec §6.6: third-party licenses are listed in the About panel.
    static var credits: NSAttributedString {
        let result = NSMutableAttributedString()
        let heading = String(localized: "about.thirdParty")
        result.append(NSAttributedString(string: heading + "\n\n", attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)]))
        result.append(NSAttributedString(string: "KeyboardShortcuts\n", attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)]))
        result.append(NSAttributedString(string: keyboardShortcutsLicense, attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]))
        return result
    }

    @MainActor
    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
```

`SSHConfigManagerApp.swift` — on the main `Window` scene (or the `App` body's first scene):

```swift
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "about.menu")) { AboutPanel.show() }
            }
        }
```

At each listed call site, next to the existing `errorMessage = Messages.text(for: error)` (or equivalent), add `AppLog.error(.<category>, error)` with the category named in the Files list. For `AppModel.launch`, log only `.failed(.failed(...))` and `.automationDenied` outcomes by wrapping the `LaunchError` (`AppLog.error(.connect, error)`); never log the `LaunchRequest`.

Add the catalog keys.

- [ ] **Step 4: Run tests**

Run: `bash scripts/test-app.sh`, and `grep -rn "AppLog.error" SSHConfigManager | grep -i "passphrase\|request\|argument\|environment"` must print nothing.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SSHConfigManager SSHConfigManagerTests
git commit -m "feat: os.Logger error logging without secrets; About panel with third-party license"
```

---

### Task 6: Sürüm betiği (Release, imza, notarize, `.dmg`) ve sürüm 1.0.0

**Files:**
- Create: `scripts/build-release.sh`
- Create: `docs/design/release.md`
- Modify: `project.yml` (`CFBundleShortVersionString: "1.0.0"`)
- Modify: `.gitignore` (`build/`)

**Interfaces:**
- Produces: `scripts/build-release.sh` — ortam: `SIGN_IDENTITY` (boşsa ad-hoc `-`), `NOTARY_PROFILE` (boşsa notarize atlanır); çıktı: `build/SSH-Config-Manager-<version>.dmg`; doğrulama adımları başarısızsa sıfırdan farklı çıkış.

- [ ] **Step 1: Write the script**

`scripts/build-release.sh`:

```bash
#!/bin/bash
# Builds a Release app and a .dmg under build/.
#   SIGN_IDENTITY  "Developer ID Application: …" (default: ad-hoc "-", for local testing only)
#   NOTARY_PROFILE a `xcrun notarytool store-credentials` profile in your keychain (optional)
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:--}"
VERSION=$(sed -n 's/^ *CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)
BUILD=build
APP_NAME="SSH Config Manager"
DMG="$BUILD/SSH-Config-Manager-$VERSION.dmg"

rm -rf "$BUILD"
mkdir -p "$BUILD"
python3 scripts/check-localization.py
xcodegen generate --spec project.yml --quiet

SIGN_FLAGS=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES)
if [[ "$IDENTITY" != "-" ]]; then SIGN_FLAGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp"); fi

xcodebuild build \
  -project SSHConfigManager.xcodeproj \
  -scheme SSHConfigManager \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD/DerivedData" \
  -quiet "${SIGN_FLAGS[@]}"

APP="$BUILD/DerivedData/Build/Products/Release/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "com.apple.security.automation.apple-events"
codesign -d --verbose=2 "$APP" 2>&1 | grep -q "flags=.*runtime"

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

if [[ "$IDENTITY" == "-" ]]; then
  echo "Built $DMG with an ad-hoc signature (not for distribution: set SIGN_IDENTITY)."
  exit 0
fi

codesign --sign "$IDENTITY" --timestamp "$DMG"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
  echo "Signed but not notarized (set NOTARY_PROFILE to notarize)."
fi
echo "Built $DMG"
```

`chmod +x scripts/build-release.sh`. Add `build/` to `.gitignore`. Set `CFBundleShortVersionString: "1.0.0"` in `project.yml`.

- [ ] **Step 2: Write the release notes for the team**

`docs/design/release.md`:

```markdown
# Sürüm alma

## Bir kerelik hazırlık (sürümü alan kişi)

1. Apple Developer hesabında **Developer ID Application** sertifikası oluşturup bu Mac'in keychain'ine yükleyin. Kontrol: `security find-identity -v -p codesigning`.
2. Notarize için uygulamaya özel parola ya da App Store Connect API anahtarı ile bir profil kaydedin:
   `xcrun notarytool store-credentials sshcm-notary --apple-id <e-posta> --team-id <TEAMID>`
   (parola sorulur ve keychain'e kaydedilir; depoya hiçbir şey yazılmaz).

## Sürüm

```bash
SIGN_IDENTITY="Developer ID Application: <Ad> (<TEAMID>)" NOTARY_PROFILE=sshcm-notary scripts/build-release.sh
```

Çıktı: `build/SSH-Config-Manager-<sürüm>.dmg` (imzalı, notarize edilmiş, damgalı). `SIGN_IDENTITY` verilmezse ad-hoc imzalı bir yerel deneme kopyası üretilir; bu kopya başka Mac'lerde Gatekeeper'a takılır.

## Sürüm öncesi kontrol listesi

- [ ] `bash scripts/test-app.sh` ve `xcrun swift test --package-path Packages/SSHConfigKit` yeşil.
- [ ] `python3 scripts/check-localization.py`: eksik Türkçe çeviri yok.
- [ ] `docs/design/manual-test-checklist.md` baştan sona geçildi.
- [ ] `project.yml` sürümü güncellendi; `CFBundleVersion` artırıldı.
- [ ] `.dmg` temiz bir kullanıcı hesabında açılıp uygulama ilk açılışta Gatekeeper uyarısı vermeden çalışıyor.
```

- [ ] **Step 3: Run the script in ad-hoc mode**

Run: `bash scripts/build-release.sh` (no `SIGN_IDENTITY`, no `NOTARY_PROFILE`).
Expected: exit 0, prints "Built build/SSH-Config-Manager-1.0.0.dmg with an ad-hoc signature …"; `hdiutil imageinfo build/SSH-Config-Manager-1.0.0.dmg | head -3` works. Do **not** mount or open the dmg or the app.

Then `bash scripts/test-app.sh` — PASS (the version change must not break tests).

- [ ] **Step 4: Commit**

```bash
git add scripts/build-release.sh docs/design/release.md project.yml .gitignore
git commit -m "build: release script (Release, signing, notarization, dmg) and version 1.0.0"
```
