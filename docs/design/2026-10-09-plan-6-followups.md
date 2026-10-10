# Plan 6 (arayüz iyileştirmeleri v1.1): sonraki sürüme devreden konular

## Bilinen kısıtlar

- **`savedAlias` eşlemesi:** Kaydedilmiş dosyadaki alias'a eşleme Unicode/büyük-küçük harf duyarsız yapılıyor; ssh `Host` eşleştirmesi ise büyük/küçük harf duyarlı. `Web` ile `web` ayrı hostlarsa yanlış blok seçilebilir (önceden vardı, bu sürümde değiştirilmedi).
- **Etkin ayarlar kaynağı:** ssh -G'nin normalleştirdiği değerler (Match bloğu yokken) "belirsiz" etiketi alabiliyor; Include edilen hostların kendi satırları "Dahil" etiketi taşıyor; düz atlamalar (ProxyJump) "atlanan" işareti almıyor; yalnızca Include dosyası değişince çözümlenen kaynaklar yenilenmiyor.
- **Çözümleyici:** `SendEnv` çok argümanlı satırlar token başına bölünmüyor; atlanan Include içindeki `Match` ve dahil edilen hostların `.thisBlock` durumu ele alınmıyor; `SendEnv -DESEN` testi anlamsız geçiyor.
- **Port ayrıştırma:** `Int("+22")` kabul ediliyor.
- **Arama:** Çok kelimeli puanlama toplamsal; dağınık eşleşme tabanı 200+ boşlukta diğer alanlar katmanıyla eşitlenebilir; 500 ms duvar saati sınaması yüklü CI'da kararsız olabilir.
- **Favoriler:** 51. favori sessizce atılıyor ve gizli favoriler üst sınıra sayılıyor; yüklemede normalleştirme yok; ASCII dışı büyük/küçük harf yinelemeleri dedupe edilmiyor; sınır/bozuk veri/`fellBack`/`uploadKey`/yazılmış harf biçimi testleri eksik.
- **ssh -G önbelleği:** `clear` sonrası bekleyenler (stale waiters) ssh çalıştırabilir (acquire sonrası nesil koruması eklenmeli); geçici hatalar (zaman aşımı/başlatma) temizlenene kadar önbellekte kalır; boş hata iletisi; `peak == 2`, clear-sonra-yükle ve `switchConfig` temizleme testleri eksik.
- **Grup alanı:** Uygulanmamış grup metni `hasPendingFormEdits`'e dahil değil; detaydaki uyarı hesabı her `body`'de tam geçiş yapıyor (belgeye göre önbelleğe alınabilir); IdentityFile okuması FIFO'da bloklanabilir (önceden var olan yardımcı).
- **Silme:** Önceki bir tekrar silinince seçim indeksi kayıyor (önceden vardı).
- **Küçük:** `connectionTests` doc yorumu yanlış yerde; araç çubuğunda boş `HStack` (görsel).

## Sürüm öncesi elle doğrulanmalı

- **Komutlar:** Host menüsü komutlarının devre dışı durumu, seçim/belge değişince canlı güncelleniyor mu (Commands gözlemi).
- **⌘⌫:** Kenar çubuğunda `onDeleteCommand` ile host silme gerçek uygulamada çalışıyor mu.
- **Hızlı Bağlan:** Arama alanı alan düzenleyicisi odaktayken ⌥↩ ve ⌘S `onKeyPress`'e ulaşıyor mu (panel ve menü çubuğu).
- **Araç çubuğu:** Boş `HStack`'in görsel etkisi.

## Kullanıcının elle kontrol etmesi gerekenler

`docs/design/manual-test-checklist.md` — v1.1 maddeleri.
