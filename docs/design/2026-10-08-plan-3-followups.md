# Plan 3 (Known Hosts): sonraki planlara devreden konular

## Öncelikli

- **Tablo seçimi geri yazımı:** `KnownHostsModel.selection` ayarlayıcısı her yazmayı güncel revizyonla etiketliyor. SwiftUI Table bir yeniden yüklemeden sonra eski seçimi geri yazarsa seçim yeniden geçerli olabilir. Elle kontrol listesinde denetlenmeli (pencere açıkken başka bir terminalde `ssh-keygen -R` → seçim temizlenmeli); gerekirse ayarlayıcı yalnızca kullanıcının yaptığı değişikliği kabul etmeli.
- **Eşzamanlı ssh yazması (park edildi):** `SafeFileWriter` içerik kontrolü ile `rename` arasında ssh known_hosts'a satır eklerse o satır kaybolur; ssh bir sonraki bağlantıda yeniden sorar.

## Düşük öncelikli

- Silme onayındaki listede port ve parmak izi yok; aynı adlı iki kayıt (ör. iki hash'li kayıt) ayırt edilemiyor.
- Tüm seçili satırlar arama ile gizlenince Sil düğmesi etkin kalıyor (bir şey yapmıyor).
- `userknownhostsfile` yolları boşlukla bölünüyor ve symlink çözülmüyor; boşluklu/`%d` içeren yollarda gereksiz "ssh başka dosya okuyor" notu çıkabilir.
- Karışık (hash'li + düz) kayıtlar yalnızca "(hash'li kayıt)" olarak görünüyor; düz adları alt dize aramasında bulunmuyor.
- `ssh -G` iptal edilince süreç durdurulmuyor (en fazla 5 sn sürer).
- `[host]:22` kaydı `host` ile eşleşmiş sayılıyor (ssh-keygen -F'den daha hoşgörülü); `a:b:c` IPv6 sayılıyor.
- Not-UTF-8 durumunda dosya izleyicisi her değişiklikte yeniden okuyor; symlink hedefi başka dizine taşınırsa izleyici eski dizini izliyor.
- Onay başlığı kapanırken bir an eski metni gösterebiliyor; ⌫ kısayolu yükleme durumuna bakmıyor; ⚠ simgesinin erişilebilirlik etiketi yok.
- Test boşlukları: harici olarak oluşturulan dosyada restore çakışması, not-UTF-8'de restore reddi, `fileDidChange`, ikinci `requestHostKeyRemoval`, `dropResult` öncesi sonuç tohumlama, `@cert-authority` içeren uygulama fikstürü, Türkçe locale ayarlı eşleşme testi.

## Kullanıcının elle kontrol etmesi gerekenler

`docs/design/manual-test-checklist.md` — "Plan 3 — Known Hosts" bölümü.
