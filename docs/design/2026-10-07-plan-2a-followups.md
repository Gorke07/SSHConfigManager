# Plan 2a (uygulama kabuğu ve düzenleyici): Plan 2b'ye devreden konular

## Plan 2b'nin ilk işi

- **Çıkış koruması uygulama açılışına bağlanmalı.** `AppDelegate.model` ve `openMainWindow` şu an yalnızca ana pencerenin `onAppear`'ında atanıyor. Uygulama yalnızca Ayarlar/Yedekler penceresiyle (veya 2b'de menü çubuğundan) açılırsa ⌘Q kaydedilmemiş değişiklikleri sormadan çıkar ve Dock'tan yeniden açma çalışmaz. Model ve pencere açma eylemi uygulama başlangıcında AppDelegate'e verilmeli.

## Plan 2b'de ele alınacaklar

- `scripts/check-localization.py` kapsamı genişletilmeli: `.help(`, `Window(`, `MenuBarExtra(`, `ContentUnavailableView(`, `confirmationDialog(`, `alert(`, `ProgressView(`, `Stepper(`, `NSAlert` metinleri; dosya başına tüm ihlaller raporlanmalı; yinelenen anahtarlar yakalanmalı.
- Dosya seçiciler (`SettingsView`, `HostEditorView`) klasör seçimine izin veriyor; `allowedContentTypes: [.data]` yapılmalı.
- Hatalar (yedekten geri yükleme, bant eylemleri) yalnızca ana penceredeki uyarıda gösteriliyor; pencere kapalıyken görünmez.
- Ayarlar'da config değiştirirken yalnızca "At / Vazgeç" var; spec §6.1 "Kaydet / Vazgeç / İptal" diyor.
- `SaveFlowModel` `probeAlias` geçmiyor; spec §4.6 düzenlenen host'un alias'ı ile doğrulama istiyor.
- Config dosyası yokken yedekten geri yükleme pasif.
- Formda bekleyen düzenleme varken Ekle/Çoğalt, onay iptal edilse bile host'u oluşturuyor.
- `CFBundleDisplayName` yerelleştirilmemiş (menü adı İngilizce kalıyor).
- Aynı tek değerli direktifin (ör. iki `User` satırı) yalnızca ilki gösteriliyor; ilk düzenlemede fazlası düşüyor (diff'te görünür).
- "Diğer Seçenekler"e form alanı olan bir anahtar (ör. `Port`) yazılırsa yinelenen direktif oluşuyor.
- Çakışma görünümünde okunamayan/UTF-8 olmayan disk "her şey eklendi" gibi görünüyor; "okunamadı" mesajı boş ayrıntıyla bitiyor.
- `backupKind` symlink çözmüyor: symlinkli `~/.ssh/config` için yedekler varsayılan klasör yerine özet adlı klasöre gidiyor.
- Plan 1 takipleri hâlâ açık olanlar: `ConnectionTester.testAll` iptal desteği, terminal başlatıcılarda kontrol karakterli config yolu.

## Düşük öncelikli

- Diff satır genişlikleri tembel yığında uzun satırlarda zıplayabilir; `DiffPresenter.rows` her çizimde yeniden hesaplanıyor; bant ikonları VoiceOver'dan gizlenmemiş.
- Silme onayı sessiz yeniden yüklemeden sonra kaymış bir satırı hedefleyebilir (aynı alias'lı hostlarda).
- Test boşlukları: arama sonrası occurrence kararlılığı, no-op kaydetme, `saveCancelled`, yedek dosyası varlığı, yerel ayara bağlı arama doğrulamaları.
- `scripts/test-app.sh` hedefi `arch=arm64` sabit; `TEST_HOST` ürün adını tekrarlıyor.

## Kullanıcının elle kontrol etmesi gerekenler

`docs/design/manual-test-checklist.md` — özellikle Ayarlar ve Yedekler pencereleri (otomatik ortamda görsel olarak doğrulanamadı), koyu tema, Türkçe arayüz.
