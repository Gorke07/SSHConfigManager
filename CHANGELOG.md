# Değişiklik Günlüğü

Bu projedeki önemli değişiklikler bu dosyada tutulur. Biçim [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/) yapısını izler, sürümler [Semantic Versioning](https://semver.org/lang/tr/) kurallarına uyar.

## [0.2.0] - 2026-10-12

### Yeni özellikler

- **Görünüm seçimi:** Ayarlar → Genel → Görünüm ile **Sistem**, **Açık** ve **Koyu** arasında seçim yapılabilir. Seçim, ilk pencere çizilmeden uygulanır; açılışta açık renk yanıp sönmez. Menü çubuğu penceresi, hızlı bağlan paneli, sayfalar ve uyarılar da seçimi izler.
- **Yumuşak koyu tema:** Koyu modda pencereler, standart koyu gri yerine hafif soğuk tonlu, açık bir grafit siyahı (`#212226`) kullanır. Formlar, listeler ve tablolar bu zemin üzerinde ayrışır. Açık modun görünümü değişmedi.
- **Dock'ta göster:** Ayarlar → Genel'deki bu seçenek kapatıldığında uygulama yalnızca menü çubuğunda çalışır ve pencere açıkken de Dock simgesi görünmez. Seçenek anında uygulanır.
- **Toolbar'da Ayarlar butonu:** Ana pencerenin toolbar'ında, Anahtarlar butonunun yanında dişli ikonlu bir Ayarlar butonu var (ipucu: ⌘,).
- **Parolasız anahtar ipucu:** Parolasız bir özel anahtar artık yalnızca editörün **Identity Files** bölümünde, ilgili satırda turuncu açık kilit ikonuyla gösterilir. İkonun üzerine gelince açıklama çıkar. Bu uyarı sidebar'dan ve detay başlığından kaldırıldı, böylece aynı anahtarı kullanan her host turuncu üçgenle işaretlenmiyor.

### Arayüz iyileştirmeleri

- **Ayarlar penceresi yenilendi:** Pencere daha geniş (640 pt) ve **Genel**, **Dosyalar**, **Yedekler** sekmelerine ayrıldı. Her sekme içeriği kadar yer kaplar; kaydırma çubuğu çıkmaz.
- **Liquid Glass:**
  - Bağlantı çubuğundaki Test, Bağlan ve favori butonları glass stilinde.
  - Bağlantı durumu, sonucun rengiyle tonlanmış bir glass kapsül içinde gösterilir.
  - Uyarı bannerları yüzen, tonlu glass kartlar olarak gösterilir.
  - Kısayolla açılan hızlı bağlan paneli Spotlight benzeri glass bir zemin kullanır.
  - İlk kullanım ekranı glass bir kart içinde.
- **Menü çubuğu hover:** Menü çubuğu penceresinin altındaki eylemler, üzerine gelince native menü öğeleri gibi accent renkte vurgulanır. Host satırlarına da hafif bir hover zemini eklendi.
- **Dosya bannerları:** Bulunamayan ya da okunamayan config bannerındaki **Seç…** butonu, Ayarlar'ı doğrudan **Dosyalar** sekmesinde açar.
- **Ana pencere boyutu:** Minimum yükseklik 480 pt'den 560 pt'ye çıktı; Etkin ayarlar açıkken en küçük pencerede bile içerik sığar.

### Performans

Büyük config dosyalarında (2.000 Host bloğu, 50.000 satırlık known_hosts, 200 anahtar) ölçülerek yapıldı.

- **Host aramaları önbellekte:** `ConfigDocument`, host listesini ve alias dizinini her belge sürümü için bir kez hesaplar. Daha önce sidebar'ın her satırı ve editörün her commit'i dosyanın tamamını yeniden tarıyordu. Durum filtresi açıkken sidebar 2-4 saniye donuyordu, artık donmuyor.
- **Daha az lint çalışması:**
  - Include dosyalarının tanımladığı host adları, her tuş vuruşunda diskten yeniden okunmak yerine önbellekten gelir.
  - Include direktiflerinin hangi bloğa ait olduğu ikili aramayla bulunur.
  - Anahtar listesi yenilendiğinde lint yalnızca bir anahtar dosyası gerçekten değiştiyse yeniden çalışır.
- **known_hosts arka planda yüklenir:**
  - Dosya artık açılışta ve her dış değişiklikte ana thread'i bloklamıyor.
  - Eski bir okuma daha yeni bir okumanın üzerine yazmaz.
  - ASCII satırlar bayt düzeyinde ayrıştırılır; büyük dosyalarda yaklaşık 2,5 kat daha hızlı.
- **Known Hosts penceresi:** Satırlar dosya sürümü başına bir kez oluşturulur ve sorgu başına bir kez filtrelenir. Arama ve seçim başına yaşanan 230-400 ms gecikme kalktı.
- **Hızlı bağlan:** Liste her tuş ya da ok tuşu için üç kez yerine bir kez hesaplanır. Host temel bilgileri, kaydedilmiş dosya, favoriler veya son bağlanılanlar değişene kadar önbellekte kalır.

### Hata düzeltmeleri

#### Veri bütünlüğü

- **Yorum çöpü birikmesi:** Editörde değerin içine ` #` yazılınca, her tuş vuruşunda config satırının sonuna önceki yorum yeniden ekleniyordu. Yorum başlatacak, tırnaksız bir `#` içeren değerler artık kaydı engelleyen bir uyarı gösteriyor. Değer değiştirilirken eski yorum da tekrar eklenmiyor.
- **Onaylanmamış değişikliklerin kaydı:** Kaydet sayfası açıkken başka bir pencereden yapılan bir değişiklik (anahtar atama, yedek geri yükleme, yeni host) kullanıcının görmediği halde dosyaya yazılabiliyordu. Belge değiştiyse Kaydet artık yeni diff'i yeniden gösteriyor.
- **Çakışmada üzerine yazma:** Çakışma sonrası "Üzerine yaz", doğrulama sürerken diske gelen daha yeni bir dış değişikliği sessizce silebiliyordu. Artık yalnızca kullanıcının incelediği disk sürümünün üzerine yazılıyor.
- **Hedefi olmayan symlink:** `~/.ssh/config` hedefi henüz var olmayan bir symlink ise (ör. dotfiles), "Dosya oluştur" ve zorla üzerine yazma işlemleri symlink'i normal bir dosyaya çeviriyordu. Artık symlink korunuyor ve hedef dosya oluşturuluyor; hedef klasör yoksa açık bir hata veriliyor.
- **Tırnaklı Host deseni:** `Host "my host"` gibi boşluk içeren bir desen, blokta başka bir alan düzenlenince `Host my host` olarak iki ayrı desene bölünüyordu. Artık tırnakları korunuyor.
- **CRLF dosyalar:** Sonunda satır sonu olmayan bir CRLF dosyasından son host silinince dosya tek başına bir `\r` ile bitiyordu. Düzeltildi.

#### Düzenleme ve kaydetme

- **Kaydedilemeyen config:** `Host a,b`, `Host -jump` veya `Host web$1` gibi geçerli bir ssh hedefi olmayan bir host seçiliyken dosya hiç kaydedilemiyordu. Doğrulama, bu durumda nötr bir yoklama host'una geçiyor; dosyadaki hatalar yine raporlanıyor.
- **Servis adıyla port:** `Port ssh` gibi geçerli servis adları artık kabul ediliyor. Daha önce bu host'taki her düzenleme engelleniyordu.

#### Arayüz

- **Beyaz ekran:** Etkin ayarlar açılınca sidebar ve detay içeriği tamamen kayboluyor, pencere beyaz kalıyordu. Liste artık sınırlı bir yükseklik içinde kayıyor, split view pencereden taşmıyor.
- **Eski form:** Ana pencere kapalıyken (yalnızca menü çubuğu) config dışarıdan değişirse, pencere yeniden açıldığında form eski değerleri gösteriyordu. Form artık yeniden yüklemede güncelleniyor.
- **Yedek geri yükleme:** Formu atmayı onaylamaya rağmen, uygulanmamış bir grup adı geri yüklenen belgeye eklenebiliyordu. Düzeltildi.
- **Anahtar sayfaları:**
  - Geç biten bir anahtar işlemi, sonradan açılmış başka bir sayfayı kapatabiliyordu. Her sayfa artık yalnızca kendini kapatıyor.
  - İptal, `ssh-keygen` veya `ssh-add` çalışırken devre dışı; çünkü bu işlemler iptal edilemiyor.

### Bilinen sınırlamalar

- Bir `Host` bloğunun içindeki Include (koşullu Include) ile gelen host'lar, ssh onları yalnızca o blokla eşleşen adlar için okusa da bağlanılabilir olarak listeleniyor.

## [0.1.0] - 2026-10-10

İlk sürüm.

- **Hızlı bağlanma:** ⌥⌘S paneli ve menü çubuğu; akıllı arama, favoriler, son bağlanılanlar, bağlanma önizlemesi. Terminal, iTerm2 ve Ghostty desteği.
- **Güvenli düzenleme:** Kayıpsız düzenleme, kaydetmeden önce diff önizlemesi, `ssh -G` doğrulaması, otomatik yedek ve atomik yazma.
- **Config'i anlama:** Etkin ayarlar ve kaynakları, ProxyJump zinciri, uyarı rozetleri, bağlantı testi.
- **Known Hosts:** Hash'li kayıtlarda arama; `ssh-keygen -R` ile aynı satırları silme.
- **Anahtarlar:** Listeleme, oluşturma, agent'a ekleme, sunucuya yükleme, parola değiştirme, çöp kutusuna taşıma.
- **Gruplar:** `# group:` yorumlarıyla host gruplama.
- İngilizce ve Türkçe arayüz.

[0.2.0]: https://github.com/messcenter/SSHConfigManager/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/messcenter/SSHConfigManager/releases/tag/v0.1.0
