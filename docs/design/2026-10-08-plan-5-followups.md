# Plan 5 (son rötuşlar ve dağıtım): sonraki sürüme devreden konular

## Sürüm öncesi elle doğrulanmalı

- **Girişte yalnızca menü çubuğu:** Algılama artık `applicationDidFinishLaunching`'de (`kAEOpenApplication` + `keyAELaunchedAsLogInItem`). `SMAppService` ile başlatılan uygulamaların bu Apple Event verisini taşıdığı macOS 26'da gerçek bir oturum açışıyla doğrulanmalı (kontrol listesi "Plan 5" satırları). Ana pencere giriş sırasında anahtar pencere olmadan oluşursa ya da 3 saniyeden geç anahtar olursa açık kalabilir; o durumda pencereleri anahtar olmalarını beklemeden bir sonraki run-loop turunda ve kısa bir gecikmeyle bir kez daha kapatmak gerekir.
- **İmzalı sürüm:** `SIGN_IDENTITY` / `NOTARY_PROFILE` dalları hiç çalıştırılmadı (bu Mac'te Developer ID yok). İlk gerçek sürüm deneme sayılmalı (`docs/design/release.md`).

## Düşük öncelikli

- Notarize reddedilirse betik `notarytool log` komutunu yalnızca yazdırıyor; `id` varsa doğrudan çalıştırabilir.
- Girişte açılıştan sonraki 3 saniye içinde kullanıcı ana pencereyi açarsa koruma onu kapatır.
- Bazı hata yolları hâlâ loglanmıyor (Host ekleme, Ayarlar'da dosya içe aktarma).
- Keys penceresi: `createdButNotAssigned` yalnızca testlerde okunuyor; test adı eski.
- `isUnsavedHost` testleri yeniden adlandırma, büyük/küçük harf ve `.included` durumlarını kapsamıyor.

## Kullanıcının elle kontrol etmesi gerekenler

`docs/design/manual-test-checklist.md` — "Plan 5 — Son rötuşlar" bölümü ve `docs/design/release.md` sürüm kontrol listesi.
