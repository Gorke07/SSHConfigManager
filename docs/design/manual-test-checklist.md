# Manuel Test Listesi

Her sürüm öncesi temiz bir test kullanıcısında veya `~/.ssh/config` yedeği alınmış bir makinede uygulanır.

## Plan 2a — Düzenleyici

- [ ] İlk açılış, `~/.ssh/config` yokken: "Config dosyası henüz yok" bandı → "Dosya Oluştur" → dosya 0600, `~/.ssh` 0700 oluşur; bant kaybolur.
- [ ] Mevcut config açılır; hostlar / desenler / dahil edilen 🔒 / Match 🔒 bölümleri doğru.
- [ ] Arama: alias, HostName ve User'da çalışır; Türkçe karakterlerde (ö, İ) aksansız arama sonuç verir.
- [ ] Bir host'un HostName'i değiştirilir → araç çubuğunda "Kaydedilmemiş değişiklikler" görünür.
- [ ] Alias yeniden adlandırılırken yazma kesilmez, odak kaybolmaz, seçim yeni adda kalır.
- [ ] Alias başka bir host'la aynı yapılınca form "başka bir host tarafından kullanılıyor" der ve dosya değişmez.
- [ ] Port alanına `abc` → hata; IdentityFile olarak var olmayan dosya → yalnızca uyarı.
- [ ] Bir değere satır sonlu metin yapıştırılır → kontrol karakteri hatası, belge değişmez.
- [ ] ⌘S → diff ekranı satır numaraları ve renklerle görünür; "ssh bu yapılandırmayı kabul ediyor"; Kaydet → dosya yazılır, yedek oluşur.
- [ ] Geçersiz bir seçenek (ör. Diğer Seçenekler'e `Bogus yes`) → diff ekranında ssh'in hata metni, Kaydet pasif.
- [ ] Uygulama açıkken dosya vim ile değiştirilir: düzenleme yoksa sessizce yeniden yüklenir; düzenleme varken bant çıkar, "Farkı Göster" ve "Yeniden Yükle" çalışır.
- [ ] Düzenleme varken başka bir editörde kaydedip ⌘S → çakışma ekranı; "Üzerine Yaz" ve "Diskteki Sürümü Yükle" beklendiği gibi.
- [ ] BOM'lu bir dosya: bant görünür, "BOM'u Kaldır" → kaydet → dosya BOM'suz.
- [ ] Sağ tık → Çoğalt (`web-copy`), SSH Komutunu Kopyala (`ssh -- web`), Sil (onaylı).
- [ ] Kaydedilmemiş değişiklikle ⌘Q: Kaydet / Vazgeç / Kaydetme seçenekleri; Vazgeç uygulamayı açık tutar. Kaydet başarısız olursa pencere yeniden açılır ve hata görünür.
- [ ] Pencereyi kapatmak uygulamayı kapatmaz (değişiklikler korunur); Dock simgesine tıklayınca pencere geri gelir.
- [ ] Formda hatalı bir alan varken (ör. Port `abc`) başka host seçmek / ⌘S / ⌘Q uyarı verir; alias'ı harf harf yeniden adlandırırken odak kaybolmaz; arama seçili host'u gizlese bile form kalır.
- [ ] Sistem dili Türkçe iken tüm metinler Türkçe; İngilizce iken İngilizce.
- [ ] Koyu temada diff renkleri ve bantlar okunaklı.
- [ ] Port `abc` iken pencere kapatılıp Dock'tan yeniden açılınca form `abc` ve hata satırıyla durur; ⌘Q → Kaydet çıkmaz, formdaki sorunu belirten uyarı gösterir; ⌘Q → Kaydetme çıkar.
