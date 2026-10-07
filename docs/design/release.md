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
