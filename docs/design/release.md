# Sürüm alma

## Gereksinimler

Xcode 27, `PATH` üzerinde `xcodegen` ve `python3`.

## Bir kerelik hazırlık (sürümü alan kişi)

1. Apple Developer hesabında **Developer ID Application** sertifikası oluşturup bu Mac'in keychain'ine yükleyin. Kontrol: `security find-identity -v -p codesigning`.
2. Notarize için uygulamaya özel parola ya da App Store Connect API anahtarı ile bir profil kaydedin:
   `xcrun notarytool store-credentials sshcm-notary --apple-id <e-posta> --team-id <TEAMID>`
   (parola sorulur ve keychain'e kaydedilir; depoya hiçbir şey yazılmaz).
   App Store Connect API anahtarı ile:
   `xcrun notarytool store-credentials sshcm-notary --key <AuthKey.p8> --key-id <KEYID> --issuer <ISSUER-UUID>`
3. Sparkle imza anahtarı: güncellemeler, uygulamadaki `SUPublicEDKey` ile eşleşen EdDSA özel anahtarıyla imzalanır. Anahtar login keychain'de `sshcm` hesabıyla durur. Sparkle araçları ilk derlemeden sonra `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/` altındadır.
   - Kontrol: `generate_keys --account sshcm -p` çıktısı `project.yml`'deki `SUPublicEDKey` ile aynı olmalı.
   - **Yedek:** `generate_keys --account sshcm -x <dosya>` ile dışa aktarıp güvenli bir yerde (parola yöneticisi) saklayın, sonra dosyayı silin. Anahtar kaybolursa mevcut kullanıcılara bir daha güncelleme gönderilemez.
   - Başka bir Mac'e taşıma: `generate_keys --account sshcm -f <dosya>`.

## Sürüm

```bash
SIGN_IDENTITY="Developer ID Application: <Ad> (<TEAMID>)" TEAM_ID=<TEAMID> NOTARY_PROFILE=sshcm-notary scripts/build-release.sh
```

Çıktı: `build/SSH-Config-Manager-<sürüm>.dmg` (imzalı, notarize edilmiş, damgalı) ve güncellenmiş `appcast.xml`. `SIGN_IDENTITY` verilmezse ad-hoc imzalı bir yerel deneme kopyası üretilir; bu kopya başka Mac'lerde Gatekeeper'a takılır.

- `TEAM_ID` verilirse `DEVELOPMENT_TEAM` olarak iletilir; `SIGN_IDENTITY` ile birlikte verilmezse betik uyarı yazar ve devam eder.
- Gerçek kimlikte betik, derlemeden sonra uygulamanın `Authority=Developer ID Application` ve `Timestamp=` içerdiğini doğrular; yoksa hata ile durur.
- Notarize sonucu "Accepted" değilse betik `xcrun notarytool log <id> --keychain-profile …` komutunu yazdırır ve 1 ile çıkar.
- **`build/` her çalıştırmada silinir.** Önceki sürümleri korumak için `.dmg` dosyasını başka bir yere kopyalayın.
- Damga (staple) `.dmg` dosyasına yapılır; içindeki uygulama ayrıca damgalanmaz, `.dmg`'nin bileti onu da kapsar.
- Sparkle'ın yardımcıları (`Autoupdate`, `Updater.app`) ad-hoc imzalı gelir; betik onları, framework'ü ve uygulamayı aynı kimlikle hardened runtime ve zaman damgasıyla yeniden imzalar. Uygulama sandbox dışında olduğu için Sparkle'ın XPC servisleri paketten çıkarılır.

## Otomatik güncelleme (Sparkle)

`NOTARY_PROFILE` verildiğinde betik, notarize edilen `.dmg` için `appcast.xml` dosyasına yeni bir kayıt ekler:

- Kayıt, `.dmg`'nin EdDSA imzasını ve indirme adresini (`…/releases/download/v<sürüm>/SSH-Config-Manager-<sürüm>.dmg`) içerir. Eski kayıtlar olduğu gibi kalır.
- **Sürüm notları** iki dildedir: `CHANGELOG.en.md` (İngilizce) ve `CHANGELOG.md` (Türkçe) dosyalarındaki `## [<sürüm>]` bölümlerinden alınır, başlıkları çıkarılır ve kayda Markdown olarak gömülür (`xml:lang="en"` ve `xml:lang="tr"`). Sparkle, kullanıcının sistem diline uyanı biçimli gösterir (başlıklar, kalın yazı, madde işaretleri); Türkçe dışındaki dillerde İngilizce not görünür. Türkçe not (`build/release-notes-tr.md`) GitHub Release notu olarak da kullanılır. İki dosyadan birinde bölüm yoksa betik derlemeye başlamadan durur. Dil ekleme `scripts/localize-appcast.py` ile yapılır.
- `appcast.xml` bu derleme numarasını zaten içeriyorsa betik derlemeye başlamadan durur: `CFBundleVersion` artırılmalı. Sparkle sürümleri `CFBundleVersion` ile karşılaştırır.

Betik sonunda yayımlama komutlarını yazdırır. Sıra önemlidir: önce GitHub Release (DMG yüklenir), sonra `appcast.xml` commit'lenip `main`'e push'lanır. Ters sırada kullanıcılar henüz var olmayan bir dosyayı indirmeye çalışır. Uygulama beslemeyi `https://raw.githubusercontent.com/messcenter/SSHConfigManager/main/appcast.xml` adresinden okur; GitHub'ın önbelleği yüzünden yeni kayıt birkaç dakika gecikebilir.

Bir sürümü geri çekmek için `appcast.xml`'den kaydını silip push'layın.

## Sürüm öncesi kontrol listesi

- [ ] `bash scripts/test-app.sh` ve `xcrun swift test --package-path Packages/SSHConfigKit` yeşil.
- [ ] `python3 scripts/check-localization.py`: eksik Türkçe çeviri yok.
- [ ] `docs/design/manual-test-checklist.md` baştan sona geçildi.
- [ ] `project.yml` sürümü güncellendi; `CFBundleVersion` artırıldı.
- [ ] `CHANGELOG.md` ve `CHANGELOG.en.md`'de `## [<sürüm>] - <tarih>` bölümü var (`[Yayımlanmamış]` / `[Unreleased]` yeniden adlandırılır, alttaki karşılaştırma bağlantıları güncellenir) ve iki dosya aynı değişiklikleri listeliyor; bu metinler kullanıcıların güncelleme penceresinde göreceği notlardır.
- [ ] Bir önceki sürüm kuruluyken **Güncellemeleri Denetle…** yeni sürümü notlarıyla gösteriyor ve kuruyor (yayımladıktan sonra).
- [ ] `.dmg` temiz bir kullanıcı hesabında açılıp uygulama ilk açılışta Gatekeeper uyarısı vermeden çalışıyor.
