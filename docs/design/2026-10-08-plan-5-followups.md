# Plan 5 (son rötuşlar ve dağıtım): kalanlar

Bu listedeki açık maddeler Plan 8'de kapatıldı (`2026-10-10-plan-8-old-followups.md`; madde madde durum: `2026-10-10-plan-8-triage.md`). Yalnızca elle doğrulanması gerekenler kaldı.

## Sürüm öncesi elle doğrulanmalı

- **Girişte yalnızca menü çubuğu (P5-1):** `SMAppService` ile başlatmada `kAEOpenApplication` + `keyAELaunchedAsLogInItem` algılaması macOS 26'da gerçek bir oturum açışıyla doğrulanmalı.
- **İmzalı sürüm (P5-2):** `SIGN_IDENTITY` / `NOTARY_PROFILE` dalları (reddedilince `notarytool log` dahil) hiç çalıştırılmadı; ilk gerçek sürüm deneme sayılmalı (`release.md`).
- `manual-test-checklist.md` "Plan 5" bölümü ve `release.md` sürüm kontrol listesi.
