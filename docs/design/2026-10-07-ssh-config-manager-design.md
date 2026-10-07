# SSH Config Manager — Tasarım Dokümanı

- **Tarih:** 2026-10-07
- **Durum:** Taslak (inceleme bekliyor)
- **Platform:** macOS 26+ (Swift / SwiftUI)

## 1. Amaç ve kapsam

### 1.1 Amaç

Şirket içinde kullanılacak native bir macOS uygulaması. Her kullanıcı kendi SSH config dosyasını, known_hosts dosyasını ve SSH anahtarlarını bir arayüz üzerinden yönetir ve sunuculara hızlıca bağlanır. İleride daha geniş dağıtım ihtimali var, ancak ilk hedef şirket içi kullanım.

### 1.2 Başarı kriterleri

1. Mevcut bir config dosyası uygulamada açılıp hiçbir şey değiştirilmeden kaydedildiğinde dosya **bayt bayt aynı** kalır.
2. Bir düzenleme sonrası dosyada **yalnızca düzenlenen satırlar** değişir. Yorumlar, boş satırlar, girinti, `Include` ve `Match` blokları korunur.
3. Kullanıcı global kısayol (⌥⌘S) veya menü çubuğu üzerinden birkaç tuşla bir sunucuya bağlanabilir.
4. Uygulama geçersiz bir config dosyası yazmaz. Her kayıt `ssh -G` ile doğrulanır ve öncesinde yedek alınır.

### 1.3 Kapsam (v1)

- Host CRUD (listeleme, ekleme, düzenleme, silme, çoğaltma)
- Seçilebilir terminalde tek tıkla bağlanma
- Menü çubuğu erişimi ve global kısayolla açılan hızlı bağlanma paneli
- Güvenli düzenleme: kayıpsız parser, diff önizlemesi, doğrulama, yedekleme, atomik yazma
- Bağlantı testi
- Seçilebilir config dosyası yolu
- Known Hosts penceresi (görüntüleme, hash'li kayıtlarda arama, silme)
- Anahtar yönetimi (listeleme, oluşturma, agent'a ekleme, sunucuya yükleme, parola değiştirme, çöp kutusuna taşıma)
- Çoklu dil desteği: İngilizce (varsayılan, kaynak dil) ve Türkçe (bkz. §6.5)

### 1.4 Kapsam dışı (v1)

- Ekip içi paylaşım, senkronizasyon, merkezi yönetim. Her kullanıcı kendi dosyalarını yönetir.
- Host gruplama ve etiketleme
- Birden fazla config dosyası arasında geçiş (aynı anda tek aktif dosya)
- `Include` edilen dosyaları ve `Match` bloklarını düzenleme (bunlar salt okunur)
- SSH sertifikaları (`-cert.pub`)
- `ed25519-sk` / `ecdsa-sk` anahtar oluşturma (bu anahtarlar listelenir ama oluşturulamaz)
- Sandbox ve App Store dağıtımı
- Otomatik güncelleme (Sparkle)
- Otomatik UI testleri

## 2. Temel kararlar

| Karar | Seçim | Gerekçe |
|---|---|---|
| Teknoloji | Native Swift + SwiftUI | Liquid Glass, `MenuBarExtra`, native his. Ekipte yalnızca macOS kullanılıyor. |
| Minimum sürüm | macOS 26 | En güncel SwiftUI API'leri ve Liquid Glass. |
| Sandbox | **Kapalı** | `~/.ssh` dizinine doğrudan erişim, `ssh` süreçlerini çalıştırma ve terminalleri Apple Events ile kontrol etme gerekiyor. |
| Dağıtım | Developer ID ile imzalı, notarize edilmiş, Hardened Runtime, `.dmg` | Şirket içi dağıtım için uygun. Sandbox'a geçiş gerekirse yalnızca dosya erişim katmanı değişir. |
| Doğruluk kaynağı | Config dosyasının kendisi | Uygulama host verisini ayrıca saklamaz. Yalnızca ayarlar `UserDefaults` içinde tutulur. |
| Parser stratejisi | Satır tabanlı, kayıpsız | Bayt bayt aynı kalma garantisi bu sayede sağlanır. |
| Uygulama bağımlılıkları | `KeyboardShortcuts` (MIT), `STTextView` 2.x (**GPL v3 / ticari lisans**) | Yalnızca uygulama target'ında; `SSHConfigKit` paketi bağımlılıksız kalır. STTextView lisansı için bkz. §6.6. |

## 3. Mimari

### 3.1 Proje yapısı

```
SSHConfigManager/
├── SSHConfigManager.xcodeproj        (app target, macOS 26, sandbox kapalı)
├── SSHConfigManager/
│   ├── App/                          SwiftUI App: WindowGroup, Window(KnownHosts), Window(Keys),
│   │                                 MenuBarExtra, Settings; QuickConnectPanel (NSPanel)
│   └── Features/
│       ├── HostList/                 Ana pencere: liste, arama, detay formu, diff onay ekranı
│       ├── QuickConnect/             Menü çubuğu ve hızlı panelin ortak arama/bağlan view'ı
│       ├── KnownHosts/               Known Hosts penceresi
│       ├── Keys/                     Anahtarlar penceresi, yeni anahtar formu
│       └── Settings/                 Ayarlar ekranı, yedekler listesi
└── Packages/SSHConfigKit/            UI'dan bağımsız Swift paketi
    ├── Sources/SSHConfigKit/
    │   ├── Config/                   ConfigParser, ConfigDocument, Host görünüm modeli
    │   ├── KnownHosts/               KnownHostsParser, KnownHostsDocument, HostMatcher, Fingerprint
    │   ├── Keys/                     KeyScanner, KeyManager
    │   ├── IO/                       SafeFileWriter, BackupManager, FileWatcher
    │   ├── Process/                  ProcessRunner (timeout, stdout/stderr), AskPass
    │   ├── Launcher/                 TerminalLauncher protokolü + 4 uygulaması, SSHCommandBuilder
    │   ├── Probe/                    ConnectionTester, sonuç sınıflandırıcı
    │   └── Stores/                   ConfigStore, KnownHostsStore, KeyStore (@Observable)
    └── Tests/SSHConfigKitTests/      (+ Fixtures/)
```

### 3.2 Birimler

| Birim | Sorumluluk | Bağımlılık |
|---|---|---|
| `ConfigParser` | Metni `ConfigDocument` yapısına çevirir. Hiçbir zaman hata fırlatmaz. | Yok |
| `ConfigDocument` | Satır listesi; `hosts`, `addHost`, `updateHost`, `removeHost`, `duplicateHost`, `render()` | Yok |
| `KnownHostsParser` / `KnownHostsDocument` | Kayıpsız known_hosts modeli; `entries`, `remove(lines:)`, `render()` | Yok |
| `HostMatcher` | Düz ve hash'li (HMAC-SHA1) eşleşme, `[host]:port` normalizasyonu | CryptoKit |
| `Fingerprint` | Base64 public key → `SHA256:…` | CryptoKit |
| `SafeFileWriter` | Yedek → geçici dosya → `rename`; symlink takibi, izinlerin korunması, çakışma kontrolü | `BackupManager`, FileManager |
| `BackupManager` | Zaman damgalı yedekler, rotasyon, listeleme ve geri yükleme | FileManager |
| `FileWatcher` | Dosyanın dışarıdan değiştiğini bildirir | DispatchSource / FSEvents |
| `ProcessRunner` | Süreç çalıştırma, zaman aşımı, çıktı yakalama. Argüman listesi ve ortam değişkenlerini loglamaz. | Foundation `Process` |
| `SSHCommandBuilder` | `ssh [-F '<yol>'] -- '<alias>'` komutunu shell için güvenli şekilde üretir | Yok |
| `TerminalLauncher` | `launch(command:)`; Terminal, iTerm2, Ghostty ve Warp uygulamaları | NSAppleScript, `open` |
| `ConnectionTester` | `ssh -G` ile adres çözümleme ve BatchMode testi; sonucu sınıflandırır | `ProcessRunner` |
| `KeyScanner` | Anahtar çiftlerini bulur, meta verilerini çıkarır | FileManager, `ProcessRunner` |
| `KeyManager` | Anahtar oluşturma, parola değiştirme, agent'a ekleme, çöp kutusuna taşıma | `ProcessRunner`, `AskPass` |
| `ConfigStore` | Aktif config için `@Observable` durum: belge, kaydedilmemiş değişiklik, diff, kaydetme akışı, dış değişiklik takibi | Yukarıdakiler |
| `KnownHostsStore` / `KeyStore` | İlgili pencerelerin `@Observable` durumu | Yukarıdakiler |

Ana pencere, menü çubuğu ve hızlı panel aynı `ConfigStore` örneğini paylaşır.

### 3.3 Ayarlar (`UserDefaults`)

| Anahtar | Varsayılan |
|---|---|
| `configPath` | `~/.ssh/config` |
| `knownHostsPath` | `~/.ssh/known_hosts` |
| `terminal` | `terminal` (`iterm2` / `ghostty` / `warp`) |
| `backupCount` | 10 |
| `launchAtLogin` | `false` (`SMAppService`) |
| Global kısayol | ⌥⌘S (`KeyboardShortcuts` paketi kendi saklar) |

## 4. Config parser ve güvenli düzenleme

### 4.1 Veri modeli

```swift
enum LineKind {
    case blank
    case comment
    case directive(key: String, value: String)   // key büyük/küçük harf duyarsız karşılaştırılır
    case hostStart(patterns: [String])
    case matchStart(criteria: String)
    case include(paths: [String])
    case unknown                                  // anlaşılamayan satır: aynen korunur
}

struct Line { var raw: String; var kind: LineKind }

struct ConfigDocument {
    var lines: [Line]
    var lineEnding: LineEnding        // .lf | .crlf (dosyada ilk görülen)
    var hasTrailingNewline: Bool
    func render() -> String           // lines.map(\.raw).joined(lineEnding) (+ son newline)
}
```

**Kural:** Kullanıcı bir satıra dokunmadıkça o satırın `raw` değeri değişmez. `render()` her satır için yalnızca `raw` değerini kullanır.

### 4.2 Parse kuralları

- Anahtar ve değer ayrımı için hem `Key value` hem `Key=value` biçimi kabul edilir; `=` etrafındaki boşluklar da kabul edilir.
- Anahtar kelimeler büyük/küçük harf duyarsızdır. Karşılaştırma **ASCII büyük/küçük harf dönüşümüyle** ve locale'den bağımsız yapılır. Locale'e duyarlı API'ler (`localizedCaseInsensitiveCompare`, `lowercased(with:)` vb.) kullanılmaz; aksi halde Türkçe locale'de `Include`/`IdentityFile` gibi `I` içeren anahtarlar `ı` ile eşleşip tanınmaz (bkz. §6.5).
- Çift tırnaklı değerler tanınır. Satır başında `#` varsa satır yorumdur.
- İlk `Host` veya `Match` satırından önceki direktifler global bölüme aittir.
- Bir blok, bir sonraki `Host`/`Match` satırına ya da dosya sonuna kadar sürer.
- Parser hiçbir girdide hata fırlatmaz. Anlamadığı satırları `unknown` olarak işaretler.

### 4.3 Blok türleri

| Blok | Listede | Düzenleme | Bağlanma |
|---|---|---|---|
| `Host foo` | Hostlar | Evet | Evet |
| `Host foo bar` (birden fazla alias) | Hostlar (ilk alias + diğerleri) | Evet | İlk alias ile |
| Wildcard içeren (`*`, `?`, `!`) | Desenler | Evet | Hayır |
| `Match …` | Match 🔒 | Hayır (ham metin gösterilir) | Hayır |
| `Include` edilen dosyalardaki hostlar | Dahil edilen 🔒 | Hayır | Evet |

`Include` yolları ssh'in kuralına göre çözülür: göreli yollar her zaman `~/.ssh` dizinine göredir, `~` genişletilir, glob desenleri desteklenir. Dahil edilen dosyalarda tekrar `Include` varsa bunlar da en fazla 16 seviye derinliğe kadar takip edilir; döngüler tespit edilir.

### 4.4 Host görünüm modeli ve form

- Formda ayrı alan olarak gösterilenler: `HostName`, `User`, `Port`, `IdentityFile`, `ProxyJump`, `ForwardAgent`.
- Diğer tüm direktifler "Diğer seçenekler" kısmında anahtar–değer listesi olarak düzenlenir.
- Aynı anahtar birden fazla kez yer alıyorsa (örneğin birden fazla `IdentityFile`) form bu alanı liste olarak gösterir.
- **Doğrulama:**
  - Alias boş olamaz ve boşluk içeremez.
  - Alias başka bir düzenlenebilir hostla aynı olamaz.
  - `Port` 1–65535 aralığında olmalıdır.
  - `IdentityFile` yolu yoksa yalnızca uyarı gösterilir, kayıt engellenmez.

### 4.5 Düzenleme kuralları

| İşlem | Davranış |
|---|---|
| Alan değiştirme | Yalnızca o satırın `raw` değeri yeniden üretilir. Mevcut girinti ve ayırıcı (boşluk veya `=`) korunur. |
| Alan ekleme | Bloğun son direktifinin altına eklenir. Girinti komşu direktiften alınır, komşu yoksa 4 boşluk kullanılır. |
| Alan silme | Yalnızca o satır silinir. |
| Host ekleme | **İlk `Host *` veya `Match all` bloğunun önüne** eklenir; böyle bir blok yoksa dosyanın sonuna. Önüne bir boş satır konur. *Gerekçe:* ssh her ayar için ilk bulduğu değeri kullanır. |
| Host silme | `Host` satırından bloğun son satırına kadar silinir. Hemen üstündeki, araya boş satır girmeyen yorum satırları da silinir. Bloktan sonraki fazla boş satırlar tek satıra indirilir. |
| Alias değiştirme | `Host` satırındaki ilgili desen değiştirilir, satırdaki diğer desenler korunur. |
| Çoğaltma | Blok kopyalanır, alias `<alias>-copy` olur, kopya orijinal bloğun hemen altına eklenir. |
| Değer tırnaklama | Boşluk içeren değerler çift tırnakla yazılır. |

### 4.6 Kaydetme akışı

Düzenlemeler bellekteki belgeye uygulanır. Kaydet (`⌘S`) şu adımları sırayla çalıştırır:

1. **Diff:** Diskteki metin ile `render()` çıktısı arasında satır bazlı unified diff hesaplanır ve onay ekranında gösterilir.
2. **Doğrulama:** Yeni içerik geçici bir dosyaya (0600 izinle) yazılır ve `ssh -G -F <geçici> <alias>` çalıştırılır. Alias olarak düzenlenen host kullanılır, yoksa ilk host, o da yoksa `localhost`. Çıkış kodu sıfırdan farklıysa ssh'in hata mesajı gösterilir ve Kaydet butonu pasif olur. Geçici dosya ardından silinir.
3. **Çakışma kontrolü:** Diskteki dosyanın SHA256 hash'i, belge yüklendiği andaki hash ile karşılaştırılır. Farklıysa çakışma ekranı gösterilir (bkz. §10).
4. **Yedek:** `BackupManager` mevcut dosyayı yedekler.
5. **Atomik yazma:** `SafeFileWriter` dosyayı yazar.
6. Yeni hash kaydedilir, kaydedilmemiş değişiklik işareti temizlenir.

### 4.7 `SafeFileWriter`

- Hedef bir symlink ise **gerçek hedef dosyaya** yazılır; symlink korunur.
- Hedef dosyanın dizininde geçici bir dosya oluşturulur, içerik yazılıp `fsync` yapılır, ardından `rename(2)` ile hedefin yerine konur.
- Orijinal dosyanın izinleri korunur. Dosya yeni oluşturuluyorsa izin `0600` olur.
- Yazma işlemi config ve known_hosts için aynıdır.

### 4.8 Yedekleme

- Konum: `~/Library/Application Support/SSHConfigManager/Backups/<dosya-türü>/<YYYYMMDD-HHMMSS>-<dosya-adı>`
- Her dosya türü (config, known_hosts) için ayrı ayrı son N yedek tutulur. N varsayılan olarak 10'dur, ayarlardan değiştirilebilir.
- Ayarlardaki "Yedekler" ekranı yedekleri listeler, diff gösterir ve geri yükleme yapar. Geri yükleme de normal kaydetme akışından geçer, yani o sırada mevcut dosyanın da yedeği alınır.

### 4.9 Dış değişiklik takibi

`FileWatcher` aktif dosyayı izler. Dosya dışarıdan değiştiğinde:
- Kaydedilmemiş değişiklik yoksa belge sessizce yeniden yüklenir.
- Kaydedilmemiş değişiklik varsa bir uyarı bandı gösterilir: "Dosya dışarıdan değişti — Yeniden yükle / Farkı göster".

## 5. Config dosyası seçimi

- Ayarlar'daki "Config dosyası" alanı. Varsayılan `~/.ssh/config`; "Seç…" ile başka bir dosya seçilir.
- İlk açılışta seçili dosya yoksa kullanıcıya "Oluştur" (0600 izinle, `~/.ssh` dizini yoksa 0700 izinle oluşturulur) veya "Başka dosya seç" seçenekleri sunulur.
- Seçilen dosya varsayılandan farklıysa:
  - Tüm ssh çağrılarına (bağlanma, test, `ssh -G`, `ssh-copy-id`) `-F '<yol>'` eklenir.
  - Ayarlar'da şu not gösterilir: *"Terminalden doğrudan `ssh host` yazarsanız bu dosya kullanılmaz; uygulama `-F` ile bağlanır."*
- Ayar değiştiğinde `ConfigStore` yeni dosyayla yeniden oluşturulur. Kaydedilmemiş değişiklik varsa önce kullanıcıya sorulur.

## 6. Arayüz

### 6.1 Ana pencere

Yapı olarak `NavigationSplitView` kullanılır. Sol kenar çubuğunda arama alanı ve şu bölümler yer alır: **Hostlar**, **Desenler**, **Dahil edilen 🔒**, **Match 🔒**. Sağ tarafta detay formu bulunur.

```
┌─────────────────────┬──────────────────────────────────────────┐
│ 🔍 Ara…             │  web-prod                  ● Erişilebilir │
│ HOSTLAR             │  Alias        [web-prod          ]        │
│  ● web-prod         │  HostName     [10.0.1.12         ]        │
│  ○ staging          │  User / Port / IdentityFile / ProxyJump   │
│ DESENLER            │  ForwardAgent                              │
│    Host *           │  ▸ Diğer seçenekler (3)                    │
│ DAHİL EDİLEN 🔒     │                                            │
│ MATCH 🔒            │  [Test et]               [Bağlan ⌘↩]       │
└─────────────────────┴──────────────────────────────────────────┘
 Araç çubuğu: [+ Host] [Tümünü test et] [Known Hosts] [Anahtarlar]  ● Kaydedilmemiş  [Kaydet ⌘S]
```

- Arama alias, HostName ve User alanlarında yapılır.
- Sağ tık menüsü: Bağlan, Test et, `ssh alias` komutunu kopyala, Çoğalt, known_hosts kaydını sil…, Sil.
- Kaydedilmemiş değişiklik varken pencere kapatılırsa ya da dosya değiştirilirse kullanıcıya "Kaydet / Vazgeç / İptal" sorulur.
- Görsel tasarımda standart macOS 26 SwiftUI bileşenleri kullanılır; Liquid Glass bu bileşenlerde otomatik gelir. Özel glass efekti eklenmez.
- Ana pencere kapatıldığında uygulama menü çubuğunda çalışmaya devam eder. Dock ikonu yalnızca bir pencere açıkken görünür (activation policy `.regular` ↔ `.accessory`).

### 6.1a Metin görünümleri (STTextView)

`STTextView` (TextKit 2, `STTextViewSwiftUI` modülündeki `TextView`) şu üç yerde, **salt okunur** olarak kullanılır:

| Yer | İçerik | Özellikler |
|---|---|---|
| Kaydet → diff onay ekranı | Unified diff (`DiffHunk` listesi) | Satır numaraları (eski/yeni), eklenen satırlar yeşil, silinenler kırmızı arka plan, monospace |
| Match 🔒 ve Dahil edilen 🔒 detayı | Bloğun ham metni | Satır numaraları, ssh_config renklendirmesi |
| Yedekler ekranı | Seçilen yedek ile mevcut dosya arasındaki diff | Diff ekranıyla aynı görünüm |

- **Renklendirme:** ssh_config için hazır bir TreeSitter grameri kullanılmaz. `SSHConfigKit`'in `LineKind` sınıflandırması üzerinden basit bir renklendirici yazılır: yorum, anahtar kelime (`Host`/`Match`/`Include`), direktif adı, değer, ⚠ anlaşılmayan satır. Böylece ekranda gösterilen renk, parser'ın gerçekten ne anladığını yansıtır.
- **Düzenleme yok:** v1'de ham metin düzenleme yoktur; tüm düzenlemeler form üzerinden yapılır (kayıpsız düzenleme garantisi formun dokunduğu satırlarla sınırlıdır). STTextView'un düzenleme özellikleri kapalı tutulur (`isEditable = false`, seçme ve kopyalama açık).
- **Paylaşılan bileşen:** Üç ekran da tek bir `CodeTextView` (SwiftUI sarmalayıcı) ve tek bir `DiffTextView` kullanır; görünüm kodu tekrarlanmaz.

### 6.2 Menü çubuğu

- `MenuBarExtra`, `.window` stilinde. Açıldığında odak arama kutusundadır.
- `↑`/`↓` ile seçim yapılır, `↩` ile bağlanılır. Desenler ve Match blokları bu listede gösterilmez; dahil edilen dosyalardaki hostlar gösterilir.
- Alt kısımda: Ana pencereyi aç, Known Hosts, Anahtarlar, Ayarlar…, Çıkış.

### 6.3 Hızlı bağlanma paneli (global kısayol)

- Kısayol `KeyboardShortcuts` paketiyle (sindresorhus) kaydedilir. Varsayılan ⌥⌘S; Ayarlar'dan değiştirilebilir veya kapatılabilir. Paket Erişilebilirlik izni gerektirmez.
- Kısayol, ekranın ortasında Spotlight benzeri bir `NSPanel` açar: kenarlıksız, her pencerenin üstünde, odak kaybedince kapanan bir panel. *Gerekçe:* `MenuBarExtra` menüsünü koddan açmanın resmi bir API'si yok.
- Panel, menü çubuğu ile aynı SwiftUI view'ını kullanır. Tuşlar: `↩` bağlan, `⌘↩` test et, `esc` kapat.

### 6.4 Bağlantı testi

- `ConnectionTester` şu komutu çalıştırır: `ssh [-F] -T -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes -o ControlPath=none -- <alias> exit`. `-T` stdin terminal olmadığında ssh'in stderr'e yazdığı "Pseudo-terminal will not be allocated" uyarısını engeller; `ControlPath=none` mevcut bir multiplex bağlantısının testi yanıltmasını önler.
- Toplam süre sınırı 10 saniyedir.
- **Sınıflandırma:**

| Sonuç | Koşul |
|---|---|
| 🟢 Erişilebilir | Çıkış kodu 0 |
| 🟡 Kimlik doğrulama gerekli | `Permission denied`, `keyboard-interactive` veya benzeri |
| 🔴 Host anahtarı değişmiş | `REMOTE HOST IDENTIFICATION HAS CHANGED`. Yanında "known_hosts kaydını sil…" butonu gösterilir. |
| 🟡 Bilinmeyen host anahtarı | `Host key verification failed` (ilk bağlantı) |
| 🔴 Zaman aşımı | `Connection timed out` veya süre sınırı aşıldı |
| 🔴 DNS | `Could not resolve hostname` |
| 🔴 Bağlantı reddedildi | `Connection refused` |
| ⚪ Diğer | stderr'in ilk satırı gösterilir |

- "Tümünü test et" en fazla 4 testi aynı anda çalıştırır. Sonuçlar diske yazılmaz, yalnızca oturum boyunca tutulur.

### 6.5 Dil desteği

- **Diller:** İngilizce kaynak dil ve varsayılan; Türkçe ikinci dil. Bu dokümandaki arayüz metinleri Türkçe çevirilerdir; kodda kaynak metinler İngilizce yazılır.
- **Altyapı:** Xcode String Catalog (`Localizable.xcstrings`). SwiftUI `Text("…")` / `LocalizedStringKey` ve SwiftUI dışındaki kodda `String(localized:)` kullanılır. Kullanıcıya görünen hiçbir metin kodda sabit (çevrilemez) string olarak bırakılmaz.
- **`SSHConfigKit` paketi:** Pakette kullanıcıya görünen metin yoktur. Hatalar ve sonuçlar tipli değerler olarak döner (`ConnectionStatus`, `DraftIssue`, `ConfigStoreError` …); bunların çevirisi uygulama katmanındaki String Catalog'da yapılır. Böylece paket `swift test` ile, kaynak derleme gerektirmeden test edilir.
- **Dil seçimi:** Sistem dili takip edilir. Sistem dili Türkçe değilse uygulama İngilizce açılır. Uygulama içinde ayrı bir dil seçici yoktur. Kullanıcı macOS'un uygulama başına dil ayarını kullanabilir (Sistem Ayarları → Genel → Dil ve Bölge → Uygulamalar); Ayarlar ekranında bu ekrana bir kısayol bulunur.
- **Çoğul ifadeler:** "4 host", "3 kayıt seçili" gibi metinler String Catalog'un çoğul varyantlarıyla yazılır.
- **Tarih ve sayılar:** Yedek tarihleri ve sayılar `FormatStyle` ile kullanıcının locale'ine göre biçimlendirilir. Yedek **dosya adlarındaki** zaman damgası locale'den bağımsızdır (`YYYYMMDD-HHMMSS`).
- **Çevrilmeyenler:** ssh direktif adları (`HostName`, `IdentityFile` …), ssh/ssh-keygen'in ham hata çıktıları ve komut metinleri çevrilmez. Formdaki alan etiketleri direktif adının kendisidir; yanlarında çevrilmiş bir açıklama (tooltip) bulunur.
- **ssh çıktısının dili:** Bağlantı testi sınıflandırması ssh'in İngilizce stderr metinlerine dayanır. OpenSSH mesajlarını yerelleştirmez; yine de alt süreçler `LC_ALL=C` ile çalıştırılarak bu garanti altına alınır.
- **Türkçe I/İ tuzağı:** Parser ve `HostMatcher` gibi protokol/dosya formatı kodlarında locale'e duyarlı büyük/küçük harf işlemleri yasaktır (bkz. §4.2). Kullanıcıya yönelik arama (host listesi filtreleme) ise `localizedStandardContains` ile locale'e duyarlı yapılır.
- **Eksik çeviri kontrolü:** Derlemede String Catalog'daki "needs review"/eksik Türkçe çeviriler uyarı olarak görünür; sürüm öncesi kontrol listesinde sıfır eksik çeviri şartı vardır.

### 6.6 Üçüncü parti lisanslar

| Paket | Lisans | Etkisi |
|---|---|---|
| `KeyboardShortcuts` | MIT | Yok (lisans metni "Hakkında" ekranında listelenir). |
| `STTextView` | GPL v3 veya ticari lisans | Şirket içi kullanımda sorun yaratmaz. Uygulama şirket dışına **dağıtılırsa** iki yol vardır: uygulamanın kaynak kodunu GPL v3 ile yayımlamak ya da STTextView'un ticari lisansını almak. Dağıtım kararı (Plan 5) öncesinde bu seçim yapılmalıdır. |

## 7. Known Hosts penceresi

Ayrı bir `Window` sahnesi olarak açılır. Erişim yerleri: ana pencerenin araç çubuğu, menü çubuğu ve "Pencere" menüsü.

### 7.1 Model

- `KnownHostsDocument` satır tabanlı ve kayıpsızdır; config parser'ıyla aynı ilkeye dayanır.
- Her satırdan şunlar parse edilir:
  - İsteğe bağlı işaret: `@cert-authority` veya `@revoked`
  - Host listesi: virgülle ayrılmış; `[host]:port` biçimi olabilir; hash'li biçim `|1|salt|hash`
  - Anahtar tipi, base64 anahtar ve isteğe bağlı yorum
- Parse edilemeyen satırlar korunur ve ⚠ ile gösterilir.

### 7.2 Görünüm

Tablo sütunları: Host, Port, Anahtar tipi, Parmak izi (SHA256), İşaret. Hash'li kayıtlar 🔒 "(hash'li kayıt)" olarak görünür.

### 7.3 Arama

- Düz kayıtlarda alt dize araması yapılır.
- Arama metni tam bir host adı (veya `host:port`) gibi görünüyorsa, `HostMatcher` hash'li kayıtları HMAC-SHA1 ile kontrol eder ve eşleşenleri sonuçlara ekler. Bu, `ssh-keygen -F` komutunun davranışıyla aynıdır. Port 22 dışındaysa `[host]:port` biçimi kullanılır.

### 7.4 Silme

- Çoklu seçim yapılır, onay istenir; ardından `BackupManager` ve `SafeFileWriter` çalışır. Bu pencerede taslak ve "Kaydet" adımı yoktur.
- Geri alma, "Yedekler…" ekranından yapılır.

### 7.5 Diğer özelliklerle bağlantı

"known_hosts kaydını sil…" eylemi (sağ tık menüsünden ya da test sonucundan) şöyle çalışır:
1. `ssh -G <alias>` ile gerçek `hostname` ve `port` değerleri alınır.
2. Eşleşen kayıtlar (hash'liler dahil, ayrıca `HostKeyAlias` varsa o değerle) bir onay penceresinde listelenir.
3. Kullanıcı onaylarsa kayıtlar silinir.

## 8. Anahtar yönetimi

Ayrı bir `Window` sahnesi olarak açılır; erişim yerleri Known Hosts ile aynıdır.

### 8.1 Tarama

- `~/.ssh` dizini ve seçili config dosyasının dizini taranır.
- Özel anahtar şu iki koşulla tanınır: dosya `-----BEGIN … PRIVATE KEY-----` başlığıyla başlar **ve** yanında `<ad>.pub` dosyası vardır. Yalnızca `.pub` dosyası varsa da listelenir ve "Özel anahtar yok" olarak işaretlenir.
- Config'teki `IdentityFile` satırlarında geçen, bu dizinler dışındaki dosyalar da listeye eklenir.
- **Uygulama özel anahtar içeriğini okumaz.** Yalnızca ilk satır (başlık) okunur. Parola durumu için OpenSSH formatında başlıktan sonraki base64 bloktaki şifreleme alanı (`cipher` / `none`) kontrol edilir; PEM formatında `Proc-Type: 4,ENCRYPTED` satırına bakılır. Anahtar materyali ayrıştırılmaz ve saklanmaz.

### 8.2 Sütunlar

| Sütun | Kaynak |
|---|---|
| Ad | Dosya adı |
| Tip / bit | `ssh-keygen -lf <pub>` |
| Parmak izi | `.pub` → `Fingerprint` |
| Yorum | `.pub` içindeki üçüncü alan |
| Parola | Başlık kontrolü; parolasız anahtarlar ⚠ ile işaretlenir |
| Agent | `ssh-add -l` çıktısındaki parmak izleriyle karşılaştırılır |
| Kullanan | Config'te bu dosyaya `IdentityFile` ile referans veren hostlar (yollar normalize edilerek karşılaştırılır) |

### 8.3 İşlemler

| İşlem | Uygulama |
|---|---|
| Yeni anahtar | Form alanları: tip (ed25519 varsayılan, rsa 4096), dosya adı (varsayılan `id_ed25519`, çakışırsa `_2`, `_3` ekiyle), yorum (varsayılan `kullanıcı@makine`), parola ve tekrarı, isteğe bağlı "Bir hosta ata". Komut: `ssh-keygen -t <tip> [-b 4096] -C <yorum> -f <yol> -N <parola>`. Mevcut dosyanın üzerine asla yazılmaz. "Bir hosta ata" seçilirse ilgili hostun `IdentityFile` alanı bellekteki belgeye eklenir; kayıt normal Kaydet akışıyla yapılır. |
| Public key'i kopyala | `.pub` içeriği `NSPasteboard` ile panoya kopyalanır. |
| Agent'a ekle | `ssh-add --apple-use-keychain <key>`. Parola, uygulama paketindeki askpass yardımcısıyla iletilir: `SSH_ASKPASS=<helper>`, `SSH_ASKPASS_REQUIRE=force`; parola yalnızca alt süreç ortamında yer alır. |
| Sunucuya yükle… | Seçilen terminalde `ssh-copy-id -i '<key>.pub' [-F] -- '<alias>'` açılır (etkileşimli). |
| Parolayı değiştir | `ssh-keygen -p -f <yol> -P <eski> -N <yeni>`. |
| Çöp kutusuna taşı | `NSWorkspace.recycle` ile özel anahtar ve `.pub` birlikte taşınır. Anahtar herhangi bir hostta kullanılıyorsa uyarı gösterilir ve o hostlar listelenir. |

Host formundaki `IdentityFile` → "Seç…" butonu önce bilinen anahtarların listesini, ardından "Başka dosya…" seçeneğini gösterir.

### 8.4 Güvenlik ödünleri (kabul edildi)

- `-N`/`-P` parametreleri ve askpass ortam değişkeni, komut çalıştığı kısa süre boyunca aynı kullanıcının süreç listesinde görünebilir. ssh-keygen parolayı stdin'den kabul etmez. Alternatifi OpenSSH anahtar formatını ve bcrypt-pbkdf şifrelemesini uygulama içinde yazmaktır; bu hata riski yüksek bir iş olduğu için reddedildi.
- Parolalar hiçbir yerde saklanmaz ve loglanmaz. İşlem bittiğinde form durumu temizlenir.

## 9. Terminal entegrasyonu

### 9.1 Komut

`SSHCommandBuilder` şu komutu üretir: `ssh [-F '<config>'] -- '<alias>'`. Yalnızca güvenli karakterlerden (`A–Z a–z 0–9 _ @ % + = : , . / -`) oluşmayan her değer tek tırnakla korunur (`'` karakteri `'\''` olarak kaçırılır); alias her zaman `--` sonrasında yer aldığı için `-` ile başlayan bir alias seçenek olarak yorumlanamaz. Komut metni hiçbir durumda kullanıcı girdisinin olduğu gibi birleştirilmesiyle oluşturulmaz.

### 9.2 Başlatıcılar

| Terminal | Yöntem |
|---|---|
| Terminal.app | AppleScript: `tell application "Terminal" to do script "<komut>"` + `activate` |
| iTerm2 | AppleScript: `create window with default profile`, ardından `write text "<komut>"` (ssh kapanınca pencere açık kalır) |
| Ghostty | `open -na Ghostty --args -e <komut>`. **Doğrulanması gerekiyor** (§12). |
| Warp | Geçici launch configuration YAML dosyası (`~/.warp/launch_configurations/`) + `warp://launch/<ad>`. **Doğrulanması gerekiyor** (§12). |

- Ayarlar'da yalnızca yüklü terminaller seçilebilir. Kontrol `NSWorkspace.urlForApplication(withBundleIdentifier:)` ile yapılır.
- Seçilen başlatıcı başarısız olursa Terminal.app'e geri dönülür ve kullanıcıya bildirim gösterilir.
- Gerekenler: Hardened Runtime, `com.apple.security.automation.apple-events` entitlement'ı ve `NSAppleEventsUsageDescription`.
- Kullanılan araçlar sabit yollardan çalıştırılır: `/usr/bin/ssh`, `/usr/bin/ssh-keygen`, `/usr/bin/ssh-add`, `/usr/bin/ssh-copy-id`.

## 10. Hata yönetimi

| Durum | Davranış |
|---|---|
| Anlaşılmayan config veya known_hosts satırı | Parser hata vermez. Satır korunur, UI'da ⚠ ile gösterilir. |
| Dosya UTF-8 BOM ile başlıyor | OpenSSH böyle bir dosyayı okuyamaz. BOM sessizce silinmez; ilk satır ⚠ ile gösterilir ve uyarı bandında "BOM'u kaldır" eylemi sunulur. Kaldırılana kadar `ssh -G` doğrulaması kaydı engeller. |
| Dosya UTF-8 değil | Dosya salt okunur açılır, hiçbir zaman yeniden yazılmaz; uyarı bandında açıklama gösterilir. |
| Dosya yok veya okunamıyor | Uyarı bandı ve eylemler: "Oluştur", "Başka dosya seç", "İzinleri göster". |
| `ssh -G` doğrulaması başarısız | Diff ekranında stderr gösterilir, Kaydet pasif olur. |
| Kaydederken çakışma | Seçenekler: "Diskteki sürümü yükle (değişikliklerim gider)", "Üzerine yaz", "Farkı göster". |
| Yazma veya yedek hatası | İşlem iptal edilir, dosyaya dokunulmaz, hata mesajı gösterilir. Yedek alınamazsa yazma yapılmaz. |
| Otomasyon izni reddedildi | Açıklama ve `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation` adresini açan bir buton. |
| Süreç zaman aşımı | Bağlantı testi: 10 sn. ssh-keygen / ssh-add: 30 sn. `ssh -G`: 5 sn. Süre dolunca süreç sonlandırılır ve hata gösterilir. |
| ssh-keygen / ssh-add hatası | stderr kullanıcıya gösterilir (örneğin "yanlış parola"). |
| Loglama | `os.Logger` (subsystem: uygulamanın bundle ID'si). Parolalar, anahtar içerikleri ve süreç argümanları/ortam değişkenleri loglanmaz. |

## 11. Test stratejisi

Testler Swift Testing ile, `SSHConfigKit` paketi üzerinde yazılır.

- **Gidiş-dönüş testi (kritik):** `Fixtures/` altındaki config örnekleri kullanılır: tab ve boşluk karışımı, `=` ayırıcı, tırnaklı değerler, CRLF, dosya sonunda newline olmaması, yorumlar, `Match`, `Include`, Unicode, anlaşılmayan satırlar. Her örnek için `render(parse(x)) == x` olduğu bayt düzeyinde kontrol edilir. Rastgele satır karışımlarıyla ek bir test yapılır.
- **Düzenleme testleri:** Her işlemden sonra unified diff'in yalnızca beklenen satırları değiştirdiği kontrol edilir. `Host *` bloğundan önce ekleme, yorumlarla birlikte silme ve çoklu alias durumları ayrı test edilir.
- **Known hosts:** Gidiş-dönüş testi; test fixture'ı `ssh-keygen -H` ile üretilir ve hash'li eşleşme doğrulanır; `[host]:port` biçimi test edilir; `Fingerprint` çıktısının `ssh-keygen -lf` ile aynı olduğu kontrol edilir.
- **`SafeFileWriter` / `BackupManager`:** Geçici dizinde symlink takibi, izinlerin korunması, rotasyon, çakışma tespiti ve hata durumunda dosyaya dokunulmaması test edilir.
- **`SSHCommandBuilder`:** Tırnaklama için özel karakter, boşluk ve `'` içeren alias ve yollar test edilir.
- **`ConnectionTester`:** Sınıflandırma, gerçek ssh stderr çıktılarından alınmış fixture'larla test edilir.
- **Entegrasyon testleri (geçici dizinde):** `/usr/bin/ssh -G` ile doğrulama; `KeyManager` ile anahtar oluşturma ve parola değiştirme; `KeyScanner` ile oluşturulan anahtarın tespiti.
- **Türkçe locale testi:** Parser, `HostMatcher` ve `ConnectionTester` testleri ayrıca `tr_TR` locale'i ile çalıştırılır; `INCLUDE`, `IdentityFile`, `hostname` gibi `I`/`i` içeren anahtar kelimelerin doğru tanındığı kontrol edilir.
- **Çeviri tamlığı:** String Catalog'ları okuyup her anahtar için `tr` çevirisinin `translated` durumda olduğunu doğrulayan bir test.
- **Kural:** Hiçbir test gerçek `~/.ssh` dizinine veya kullanıcının agent'ına dokunmaz. Tüm yollar dışarıdan verilir; agent testleri ayrı bir `ssh-agent` örneği ile yapılır.
- **UI:** Otomatik test yazılmaz. SwiftUI preview'ları ve `docs/design/manual-test-checklist.md` dosyasındaki manuel test listesi kullanılır (planın bir parçası olarak yazılacak).

## 12. Açık riskler ve ilk denemeler

Uygulama planının ilk adımlarında kısa denemelerle doğrulanacaklar:

1. **Ghostty:** `open -na Ghostty --args -e …` komutunun güncel sürümde yeni pencerede komut çalıştırıp çalıştırmadığı.
2. **Warp:** Launch configuration + `warp://launch/` yönteminin komut çalıştırıp çalıştırmadığı. Çalışmıyorsa Warp v1'den çıkarılır.
3. **Askpass + `ssh-add --apple-use-keychain`:** Tty olmayan bir ortamda `SSH_ASKPASS_REQUIRE=force` ile çalıştığı.
4. **Activation policy geçişi:** `.regular` ↔ `.accessory` geçişinin macOS 26'da pencere odağını bozmadığı.

## 13. Uygulama sırası (plan için öneri)

1. `SSHConfigKit`: Config parser, belge, gidiş-dönüş ve düzenleme testleri
2. `SafeFileWriter`, `BackupManager`, `ConfigStore` + kaydetme akışı
3. Ana pencere (liste ve form) + diff onay ekranı
4. Terminal başlatıcılar + §12 denemeleri
5. Bağlantı testi
6. Menü çubuğu + hızlı bağlanma paneli + global kısayol
7. Ayarlar (config yolu, terminal, yedekler, girişte başlat)
8. Known Hosts
9. Anahtar yönetimi
10. İmzalama, notarization, `.dmg`

Dil desteği ayrı bir adım değildir: String Catalog'lar 1. ve 3. adımda kurulur, her adımda eklenen metinlerin İngilizce kaynağı ve Türkçe çevirisi aynı adımda yazılır.
