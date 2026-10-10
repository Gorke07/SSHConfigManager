# Plan 6 (arayüz iyileştirmeleri v1.1): sonraki sürüme devreden konular

Plan 7 (`docs/design/2026-10-10-plan-7-followups.md`) bu listedeki maddelerin çoğunu kapattı: alias kimliği artık ssh gibi büyük/küçük harf duyarlı ve tam eşleşmeli; `SendEnv` token'ları ve `-DESEN` kaldırma; Include içindeki hedef blok; ssh ile uyumlu port ayrıştırma; FIFO'da bloklanmayan anahtar okuma; favori/son listelerinin normalleştirilmesi ve görünür favori sınırı; arama katmanlarının çakışmaması ve deterministik performans testi; normalleştirilmiş değerlerin doğru kaynağı; zincirde "Atlandı" durumu; Include dosyası içeriğine göre yenileme; eksik önbellek testleri; uygulanmamış grup taslağının bekleyen düzenleme sayılması ve kaydetmede uygulanması; uyarı hesabının önbelleğe alınması (anahtar değişikliklerinde yenilenir); silme sonrası seçim; Include başına yinelenen alias ifadesi; boş araç çubuğu öğesi.

## Bilinen kısıtlar

- **Etkin ayarlar kaynağı:** Çok değerli anahtarlarda (`IdentityFile` vb.) kaynak etiketi yalnızca ilk değerin bloğunu gösterir.
- **Hedef blok:** Aynı alias hem kök dosyada hem de ondan önce gelen bir Include'da tanımlıysa "Bu host" etiketi kök bloğa verilir (kullanıcının gördüğü ve düzenlediği blok); dahil edilen bloğun satırları "Dahil edilen" olarak görünür, değerler doğrudur.
- **Yinelenen alias ifadesi:** `Match all` dışındaki `Match` bloklarının içindeki Include'lar hesaba katılmaz (koşula bağlı).
- **Çözümleyici:** `SendEnv` içindeki ters eğik çizgi kaçışları yorumlanmaz.
- **Port ayrıştırma:** Servis adları `getservbyname` ile çözülür (iş parçacığı güvenli değil; ayrıştırma ana aktörde yapılıyor).
- **ssh -G önbelleği:** Geçici hatalar (zaman aşımı/başlatma) yapılandırma değişene kadar önbellekte kalır (bilinçli).

## Sürüm öncesi elle doğrulanmalı

- **Komutlar:** Host menüsü komutlarının devre dışı durumu, seçim/belge değişince canlı güncelleniyor mu (Commands gözlemi).
- **⌘⌫:** Kenar çubuğunda `onDeleteCommand` ile host silme gerçek uygulamada çalışıyor mu.
- **Hızlı Bağlan:** Arama alanı odaktayken ⌥↩ ve ⌘S `onKeyPress`'e ulaşıyor mu (panel ve menü çubuğu).
- **Araç çubuğu:** Durum özeti öğesinin sonradan eklenmesi düzeni bozmuyor mu.
- **Grup taslağı:** Uygulanmamış ya da uygulanamayan grup metniyle çıkışta/kaydetmede davranış.

## Kullanıcının elle kontrol etmesi gerekenler

`docs/design/manual-test-checklist.md` — v1.1 maddeleri.
