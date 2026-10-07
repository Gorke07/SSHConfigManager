# Plan 4 (Anahtar yönetimi): sonraki planlara devreden konular

## Plan 5'in ilk görevi

- **Yedeğe düşme bildirimi kayboluyor:** "Sunucuya Yükle" seçilen terminal yerine Terminal'de açılırsa bildirim `keys.errorMessage`'a yazılıyor, ancak form `.onDisappear` ile bu mesajı silip kapanıyor; bildirim hiç görünmüyor. Silme yalnızca İptal'de yapılmalı.
- **Oluşturuldu ama atanmadı:** Form açık kalıyor (karar: kapanmalı ve mesaj Anahtarlar penceresinde gösterilmeli); yeniden Oluştur ikinci bir anahtar üretiyor.
- **Yükleme sonrası temizlik:** `KeysModel.upload` ana penceredeki ilgisiz uyarıları da temizleyebiliyor; önceki değerler saklanıp geri konmalı. Otomasyon reddinde "Gizlilik Ayarlarını Aç" düğmesi Anahtarlar penceresinde yok.
- **Test:** "oluşturma sırasında form kirlendi" testi ssh-keygen başarısız olursa sonsuz döngüye girebilir; süre sınırı eklenmeli ya da belirlenimci bir sahte runner kullanılmalı.

## Düşük öncelikli

- `.pub`-yalnız üzerine yazma yarışı (ssh-keygen yalnızca özel anahtarı sorar); pencere çok dar.
- `AskPass.make` `setAttributes` hata verirse dizini bırakıyor (içinde sır yok).
- Parolasız şifreli anahtarda `nil` parola → "yanlış parola"; ayrı bir "parola gerekli" durumu olabilir.
- `TestAgent` soket oluşmazsa hata fırlatmıyor.
- Host formundaki anahtar menüsü yalnızca liste boşken yeniliyor; dışarıdan eklenen anahtar Anahtarlar penceresi yenilenene kadar görünmüyor.
- `IdentityFile` yinelenme kontrolü dize eşitliğiyle; `~/…` ile mutlak yol eşleşmiyor.
- PEM `Proc-Type` kontrolü yalnızca `ENCRYPTED` alt dizesine bakıyor; `PublicKeyInfo` tip doğrulamıyor; yorumdaki çoklu boşluk tek boşluğa iniyor.
- Okunamayan özel anahtar yalnızca-.pub olarak görünüyor; tarama dosya G/Ç'sini async bağlamda senkron yapıyor.
- `-F`/`..` yol çözümlemesi sözcüksel; APFS büyük/küçük harf duyarsızlığı karşılaştırmada dikkate alınmıyor.

## Kullanıcının elle kontrol etmesi gerekenler

`docs/design/manual-test-checklist.md` — "Plan 4 — Anahtarlar" bölümü (özellikle `--apple-use-keychain` ile agent'a ekleme ve Ghostty'de ssh-copy-id penceresinin açık kalması).
