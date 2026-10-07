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
- [ ] Ayarlar (⌘,) → "Seç…" ile `~/dotfiles/ssh/config` seçilir → liste o dosyadan yüklenir, `-F` notu görünür; "~/.ssh/config Kullan" geri döndürür.
- [ ] Kaydedilmemiş değişiklik varken config dosyası değiştirilmeye çalışılınca "atılsın mı?" onayı çıkar; vazgeçilirse hiçbir şey değişmez.
- [ ] Yedek sayısı 2 yapılır, üç farklı kayıt yapılır → Yedekler penceresinde 2 yedek.
- [ ] Yedekler penceresinde bir yedek seçilir → mevcut dosyadan yedeğe diff; "Düzenleyiciye Yükle" → kaydedilmemiş değişiklik olur, ⌘S ile normal kaydetme akışı.
- [ ] Kaydedilmemiş değişiklik veya formda hatalı alan varken "Düzenleyiciye Yükle" önce "değiştirilsin mi?" onayı ister; başka config dosyasına geçince Yedekler penceresi o dosyanın yedeklerini gösterir.
- [ ] "Dil Ayarlarını Aç…" Sistem Ayarları'nın Dil ve Bölge sayfasını açar.
- [ ] Dış değişiklik bandında "Yeniden Yükle", kaydedilmemiş değişiklik veya formda bekleyen düzenleme varken önce "atılsın mı?" onayı ister; değişiklik yoksa doğrudan yeniden yükler.

## Plan 2b — Bağlanma

- [ ] `demo` host'u (127.0.0.1, Port 1) seçili → ⌘↩ → Terminal'de `ssh -- demo` açılır ve "Connection refused" ile biter.
- [ ] İlk bağlanmada macOS Otomasyon izni ister; "İzin Verme" seçilirse uygulama "Terminali Kontrol Etmek İçin İzin Gerekiyor" uyarısını ve "Gizlilik Ayarlarını Aç" düğmesini gösterir.
- [ ] Ayarlar'da iTerm2 ve Ghostty seçilip ayrı ayrı bağlanılır; yüklü olmayan bir terminal seçiliyse Terminal kullanılır ve bu söylenir.
- [ ] Test Et → rozet "Bağlantı reddedildi" ve ssh'in mesajı; Tümünü Test Et → tüm hostlarda rozet; Testi Durdur yarıda keser.
- [ ] Sağ tık → Bağlan / Test Et, dahil edilen (🔒) hostlarda da çalışır.
- [ ] Ayarlar → Girişte Aç açılır; oturumu kapatıp açınca uygulama menü çubuğunda başlar; kapatılınca başlamaz.
- [ ] Menü çubuğundaki ikon → arama kutusu odaklı açılır; yaz → ↑↓ → ↩ ile bağlanır ve pencere kapanır; ⌘↩ seçili host'u test eder (rozet); esc kapatır.
- [ ] Dahil edilen hostlar 🔒 ile listede; desenler (`*`) yok; aynı alias bir kez.
- [ ] Ana pencere kapatılınca Dock simgesi kaybolur, menü çubuğu kalır; "SSH Config Yöneticisini Aç" pencereyi ve Dock simgesini geri getirir.
- [ ] Menüden "Çık" kaydedilmemiş değişiklik varken kaydetme uyarısını gösterir.
- [ ] Herhangi bir uygulamadayken ⌥⌘S → ekranın ortasında hızlı bağlanma paneli, arama kutusu odaklı; ↩ bağlar ve panel kapanır; esc ve başka yere tıklamak paneli kapatır; ⌥⌘S ikinci kez basınca kapanır.
- [ ] Ayarlar'da kısayol değiştirilir (ör. ⌃⌥Space) → yeni kısayol çalışır, eskisi çalışmaz; kaydedici temizlenirse kısayol devre dışı kalır.

### Plan 2b — Son inceleme düzeltmeleri

- [ ] Ayarlar açıkken ana pencere kapatılır → Dock simgesi kalır; Ayarlar da kapatılınca kaybolur.
- [ ] Ana pencere kapalıyken menü çubuğundan Ayarlar açılır → Dock simgesi görünür.
- [ ] Menü çubuğu listesi iki kez açılır → ikincisinde arama sıfırlanmış ve arama kutusu odaklı.
