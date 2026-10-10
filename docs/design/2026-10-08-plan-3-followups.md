# Plan 3 (Known Hosts): kalanlar

Bu listedeki açık maddeler Plan 8'de kapatıldı (`2026-10-10-plan-8-old-followups.md`; madde madde durum: `2026-10-10-plan-8-triage.md`). Yalnızca elle doğrulanması gerekenler kaldı.

## Elle doğrulanmalı

- Tablo seçimi: pencere açıkken başka bir terminalde `ssh-keygen -R` çalıştırınca seçim temizleniyor mu (P3-1).
- `manual-test-checklist.md` "Plan 3 — Known Hosts" bölümü.

## Park edilen

- Eşzamanlı ssh yazması: `SafeFileWriter` kontrolü ile `rename` arasında ssh known_hosts'a satır eklerse o satır kaybolur; ssh bir sonraki bağlantıda yeniden sorar.
