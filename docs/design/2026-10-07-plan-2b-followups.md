# Plan 2b (bağlanma): sonraki planlara devreden konular

## Öncelikli

- **Girişte menü çubuğunda başlama:** Girişte açıl etkinken uygulama ana pencereyi açıyor; spec'e göre yalnızca menü çubuğunda başlamalı.
- **Dış değişiklik beklerken kayıtlı host listesi eskiyor:** Kaydedilmemiş düzenleme varken dosya dışarıdan değişirse `ConfigStore.fileDidChange` yalnızca `externalChangePending` ayarlıyor; `savedDocument` eski kalıyor. Dışarıdan silinen bir host bağlanabilir görünür. Yeni disk metni `savedDocument`'e işlenmeli ve `onDiskStateChange` tetiklenmeli.
- **Kaydedilmemiş yeni host:** Bağlan düğmesi açıklamasız pasif. `store.hasUnsavedChanges` iken "Bağlanmak için kaydedin" notu gösterilmeli.
- **`.requiresApproval`:** Giriş öğesi Sistem Ayarları'nda onay beklerken anahtar sessizce kapanıyor; ipucu gösterilmeli. Anahtar ayarlar açılınca yenilenmeli.

## Düşük öncelikli

- `ConnectionTestsModel.test` kayıtlı dosyayı kendisi kontrol etmiyor (çağıranlar ediyor); model düzeyinde ikinci koruma eklenebilir.
- `record()` `runAliases`'tan alias'ı çıkarmıyor; Test All bittikten sonra aynı host'un tekli testinin göstergesi erken kaybolabilir.
- Kontrol karakteri filtresi C1 ve U+2028/2029'u kapsamıyor (sh/AppleScript için ayırıcı değiller).
- `NSAppleScript` ve `open` ana iş parçacığını bloke ediyor (ilk TCC isteği sırasında dahil).
- Ghostty paket kimliğiyle denetleniyor ama adla açılıyor; başlatıcı hata ayrıntıları kısmen yerelleştirilmemiş.
- Çok alias'lı `Host` satırlarında yalnızca ilk alias bağlanabilir; sonuçlar büyük/küçük harfe duyarlı tutuluyor.
- Geçici betik: AppleScript başarılı olup kabuk betiği hiç çalıştırmazsa `$TMPDIR`'de 0700 bir betik kalır. `write` döngüsünde `EINTR` yeniden denenmiyor.
- Menü çubuğu penceresi dışlaması `NSPanel`/sınıf adına dayanıyor; `styleMask.contains(.titled)`, `level == .normal` kontrolleri eklenebilir.
- Kenar çubuğu bağlam menüsü bağlanamayan satırlarda ayırıcıyla başlıyor; ConnectionBar'daki Test, Test All sırasında pasif değil (zararsız); rozet ayrıntısı `.help`'te tekrar ediliyor.
- Ayarlar'da kısayol kaydedici, giriş anahtarı ile onun hata metni arasında duruyor.
- Hızlı bağlanma paneli: `NSApp.activate()` `.nonactivatingPanel`'i kısmen boşa çıkarıyor; belge yorumu "borderless" diyor; kullanılmayan `model`/`openSettings` parametreleri; `selectedEntry` her satırda yeniden hesaplanıyor.
- Yerelleştirme denetleyicisi yorum/dize içlerini de eşliyor; `.accessibilityLabel`, `Link`, `NSMenuItem` kapsanmıyor.
- Testler: `testAll` iptal testi yoğun zamanlamada boşuna geçebilir; `singleTestCannotRemoveATestAllEntry` ~50 ms pay; `.testing` stili için test yok.

## Kullanıcının elle kontrol etmesi gerekenler

`docs/design/manual-test-checklist.md` — "Plan 2b" bölümleri. Özellikle:

- Terminal, iTerm2 ve Ghostty ile bağlanma (fish/zsh/tcsh kabuğunda geçici betik çalışıyor ve kendini siliyor mu).
- Otomasyon izni reddedilince uyarı ve "Gizlilik Ayarlarını Aç".
- Menü çubuğu listesi, ↩/⌘↩, ikinci açılışta arama sıfırlanıyor mu.
- ⌥⌘S paneli ve kısayol kaydedici.
- Dock ikonu: ana pencere kapanırken Ayarlar açık kalsın; menü çubuğundan Ayarlar açılsın.
- Girişte açıl anahtarı.
