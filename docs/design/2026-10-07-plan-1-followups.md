# Plan 1 (SSHConfigKit çekirdeği): Plan 2'ye devreden konular

Plan 1'in son incelemesinde ertelenen ve Plan 2 (uygulama arayüzü) yazılırken dikkate alınması gereken maddeler.

## Plan 2'de mutlaka ele alınacaklar

- **Host seçimi:** `HostEntry.id` satır numarasıdır ve üstte satır eklenince değişir. Listede seçim alias üzerinden tutulmalı, her `apply` sonrası yeniden bulunmalı.
- **Diff görünümü:** CRLF dosyalarda `DiffLine.text` sonunda `\r` taşır; görüntülerken atılmalı. `missingNewline == true` olan satırlar için "\ Dosya sonunda yeni satır yok" notu gösterilmeli.
- **"Tümünü test et" iptali:** `ConnectionTester.testAll` iptal edilince kalan aliasları kuyruğa almaya devam ediyor; iptal düğmesi eklenmeden önce `guard !Task.isCancelled` eklenmeli.
- **Dosya izleme:** `ConfigStore.isWatching == false` ise kullanıcıya bildirilmeli. `createFile()` sonrasında veya config yolu değiştiğinde izleyici yeniden başlatılmalı.
- **Önizleme verileri:** `HostEntry`, `MatchEntry`, `IncludedHost`, `DiffLine`, `DiffHunk` için public init yok; SwiftUI önizlemeleri için eklenmeli.
- **Terminal başlatıcılar:** Dosya seçiciden gelen config yolu kontrol karakteri içerebilir; terminale "yazılan" komutlarda reddedilmeli.
- **`ssh -G` yan etkileri:** Doğrulama sırasında config'teki `Match exec` komutları çalışır, `CanonicalizeHostname` DNS sorgusu yapabilir. Arayüzde not olarak belirtilmeli.
- **`apply` performansı:** Her düzenlemede `Include` dosyaları yeniden çözülüyor; form her tuş vuruşunda `apply` çağıracaksa yalnızca `Include` listesi değişince hesaplanmalı.
- **Büyük dosyalarda diff:** LCS tablosu boyut sınırsız (O(n·m)); BOM kaldırma + dosya sonuna ekleme gibi iki uçtaki değişikliklerde büyük dosyada bellek artar. Boyut sınırı ve "tüm dosya değişti" yedeği eklenmeli.

## Düşük öncelikli (ileride)

- Bağlantı sınıflandırması tüm stderr içinde alt dize arıyor; banner/uzak metin yanlış eşleşebilir. `detail` zararsız bir "Warning:" satırı olabilir.
- `~kullanıcı/` biçimindeki `Include` yolları genişletilmiyor.
- CRLF olup sonunda yeni satır olmayan dosyada dosya sonuna ekleme karışık satır sonu üretir.
- Tekrar eden anahtarların (ör. `IdentityFile`) sırası değiştirilince dosyadaki sıra değişmez (v1'de sıralama arayüzü yok).
- Kaydetmeden hemen önce parmak izi yeniden kontrol edilmiyor (küçük pencere; yedek mevcut). Üst dizin fsync edilmiyor.
- `ProcessRunner`: iptalde yalnızca SIGTERM; öldürülen sürecin torunları yetim kalabilir; zaman aşımında `exitCode` sinyal numarasıdır.
- `FileWatcher`: `onChange` içinde izleyicinin son referansı senkron bırakılırsa `deinit` kilitlenir (ConfigStore MainActor'a geçtiği için güvenli).
- Testler: `GatedRunner.waitUntilEntered()` zaman sınırı yok; birkaç testte pozitif kontrol eksik.
