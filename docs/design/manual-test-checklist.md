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
- [ ] Yeni bir host eklenip kaydedilmez → kenar çubuğunda rozet/Bağlan yok, Bağlan ve Test Et pasif; menü çubuğu ve ⌥⌘S listesinde görünmez; Tümünü Test Et onu test etmez. Kaydedince bağlanılabilir.
- [ ] Kaydedilmiş bir host'un HostName'i değiştirilip kaydedilmez → bağlantı çubuğunda "Kaydedilmemiş değişiklikler var — Bağlan ve Test kaydedilmiş dosyayı kullanır." notu; Bağlan diskteki değerlerle bağlanır.
- [ ] Kaydet ve diskten yeniden yükleme sonrası test rozetleri temizlenir.
- [ ] Varsayılan kabuğu fish olan bir kullanıcıda Terminal ve iTerm2 ile bağlanılır → yalnızca `/…/sshcm-….sh` yolu yazılır, ssh açılır, betik dosyası silinmiş olur.
- [ ] Ayarlar'da yüklü olmayan terminal seçilemez (satır pasif).
- [ ] Seçili terminal kullanılamayıp Terminal'e düşülünce uyarının başlığı "Terminal'de Açıldı".
- [ ] Sistem dili Türkçe iken ilk bağlanmadaki Otomasyon izni penceresinin açıklaması Türkçe.
- [ ] Kaydedilmemiş değişiklik varken menü çubuğundan "Çık" → menü penceresi kapanır, kaydetme uyarısı önde açılır.

## Plan 3 — Known Hosts

Elle denemede gerçek `~/.ssh/known_hosts` kullanılmaz: `defaults write tr.com.mess.SSHConfigManager knownHostsPath /tmp/sshcm-manual/known_hosts` (bitince `defaults delete tr.com.mess.SSHConfigManager knownHostsPath`). Örnek dosya: birkaç düz kayıt, `ssh-keygen -H -f /tmp/sshcm-manual/known_hosts` ile hash'lenmiş bir kopya, bir `@cert-authority` satırı ve bir anlamsız satır.

- [ ] Ana penceredeki araç çubuğundan, menü çubuğunun alt kısmından ve Pencere menüsünden Known Hosts açılıyor; açıkken Dock ikonu görünüyor.
- [ ] Sütunlar: Host, Port, Anahtar Tipi, Parmak İzi, İşaret. Hash'li kayıt 🔒 "(hash'li kayıt)", anlamsız satır ⚠ ile görünüyor.
- [ ] Parmak izleri `ssh-keygen -lf /tmp/sshcm-manual/known_hosts` çıktısıyla aynı.
- [ ] Arama: düz kayıtta alt dize; `ornek.com` / `ornek.com:2222` yazınca hash'li kayıt bulunuyor.
- [ ] Çoklu seçim + Sil (ya da ⌫) → onay → silindi; Yedekler'de known_hosts yedeği var; diğer satırlar aynı (`diff` ile).
- [ ] Pencere açıkken dosyaya terminalden satır eklenince liste kendiliğinden yenileniyor.
- [ ] Dosya yokken pencere hata değil "Henüz known_hosts dosyası yok" gösteriyor.
- [ ] Koyu tema ve Türkçe arayüz.
- [ ] Ana pencerede bir host'a sağ tık → "known_hosts Kaydını Sil…" → `ssh -G` sonrası eşleşen kayıtlar (hash'li dahil, `*.…` desenleri hariç) listeleniyor; Sil → yedek alınmış, yalnızca o satırlar gitmiş.
- [ ] Test sonucu "Host anahtarı değişmiş" iken detaydaki "known_hosts Kaydını Sil…" aynı akışı açıyor; silindikten sonra rozet temizleniyor.
- [ ] Eşleşen kayıt yoksa denenen adlar (`host` / `[host]:port`) gösteriliyor.
- [ ] Yedekler: üstteki seçiciyle "known_hosts" seçilince known_hosts yedekleri listeleniyor; diff mevcut dosyaya göre; Geri Yükle onay istiyor ve dosyayı hemen yazıyor (önce mevcut dosyanın yedeği alınıyor).
- [ ] Ayarlar → known_hosts dosyası: Seç… ile başka dosya seçilince Known Hosts penceresi o dosyayı gösteriyor; "~/.ssh/known_hosts kullan" geri alıyor. Config dosyası seçimi hâlâ çalışıyor.
- [ ] Not: ssh bir host anahtarını tam silme anında eklerse (çok nadir) eklenen satır kaybolabilir; ssh bir sonraki bağlantıda yeniden sorar.
- [ ] Pencere açıkken başka bir terminalde `ssh-keygen -R <host> -f /tmp/sshcm-manual/known_hosts` çalıştırınca tablodaki seçim temizleniyor ve Sil yanlış satırı silmiyor.

## Plan 4 — Anahtarlar

Elle denemede gerçek anahtarlarınıza dokunmamak için yeni anahtarları `deneme_` önekiyle oluşturun ve bitince çöp kutusundan silin. "Agent'a ekle" gerçek agent'ınızı ve (`--apple-use-keychain` ile) keychain'inizi kullanır; denedikten sonra `ssh-add -d ~/.ssh/deneme_…` ile çıkarın.

- [ ] Ana penceredeki araç çubuğundan, menü çubuğunun alt kısmından (Known Hosts ile Ayarlar arasında) ve Pencere menüsünden Anahtarlar açılıyor.
- [ ] Sütunlar: Ad, Tip (ör. ED25519 256), Parmak İzi (`ssh-keygen -lf` ile aynı), Yorum, Parola (parolasızlar ⚠), Agent (`ssh-add -l` ile aynı), Kullanan.
- [ ] Yeni Anahtar: varsayılan ad çakışınca `_2` öneriyor; parola tekrarı eşleşmezse ya da 1–4 karakterse Oluştur pasif; "Hosta ata" seçilince ana pencerede kaydedilmemiş değişiklik olarak `IdentityFile` ekleniyor, Kaydet ile yazılıyor.
- [ ] Public Key'i Kopyala: panoda tek satır `ssh-… … yorum`.
- [ ] Agent'a Ekle: parolalı anahtarda yanlış parola birkaç saniye içinde "Parola doğru değil" diyor; doğru parolada Agent sütunu "Yüklü" oluyor; keychain'e kaydedildiği için sonraki girişte parola sorulmuyor.
- [ ] Sunucuya Yükle: seçilen terminalde `ssh-copy-id -i … -- host` açılıyor (Ghostty/Terminal/iTerm2).
- [ ] Parolayı Değiştir: yanlış mevcut parola reddediliyor; boş yeni parola ile parola kaldırılıyor (Parola sütunu ⚠).
- [ ] Çöp Kutusuna Taşı: kullanan host varsa onay penceresinde listeleniyor; özel anahtar ve .pub birlikte çöp kutusunda.
- [ ] Agent çalışmıyorken (`SSH_AUTH_SOCK` geçersiz bir oturumda) Agent sütunu "?" gösteriyor ve uygulama donmuyor.
- [ ] Koyu tema ve Türkçe arayüz.
- [ ] Host formunda IdentityFile → "Seç…" önce bilinen özel anahtarları (`~/.ssh/…`), ardından "Başka Dosya…" seçeneğini gösteriyor; seçilen yol listeye bir kez ekleniyor.

## Plan 5 — Son rötuşlar

- [ ] Girişte açıl açıkken oturumu kapatıp açın: uygulama ana pencere açmadan yalnızca menü çubuğunda başlıyor; Dock'ta ikon yok.
- [ ] Girişte açıl'ı açınca macOS onay isterse Ayarlar'da açıklama ve "Giriş Öğelerini Aç" görünüyor; onayladıktan sonra Ayarlar'a dönünce anahtar açık.
- [ ] Sistem Ayarları → Giriş Öğeleri'nden kapatılınca Ayarlar'a dönüldüğünde anahtar kapalı görünüyor.
- [ ] Yeni bir host ekleyip kaydetmeden seçince Bağlan/Test pasif ve "Bu host'a bağlanmak ya da test etmek için dosyayı kaydedin" notu var.
- [ ] Kaydedilmemiş düzenleme varken config'ten bir host'u terminalden silin: o host artık menü çubuğu listesinde ve ⌥⌘S panelinde yok; "Dosya dışarıdan değişti" bandı görünüyor.
- [ ] Girişte açılışta ana pencere bir an görünüp kaybolmuyor ve birkaç saniye sonra geri gelmiyor; menü çubuğundan 'Ana pencereyi aç' ile normal açılıyor ve Dock ikonu görünüyor.

## v1.1 — Arayüz geliştirmeleri

- [ ] ⌥⌘S → arama yazmadan ↩: en son bağlanılan host'a bağlanıyor; boş aramada Favoriler / Son / Tüm Hostlar bölümleri.
- [ ] `prd web` gibi kısaltmalar doğru host'u ilk sırada buluyor; eşleşen harfler kalın.
- [ ] ⌥↩ komutu panoya kopyalıyor; ⌘S favoriye ekleyip çıkarıyor; satırda yıldız görünüyor.
- [ ] Seçili host'un altında `kullanıcı@adres:port · … üzerinden` önizlemesi kısa sürede beliriyor.
- [ ] Bir host'un detayında "Etkin Ayarlar" ssh -G değerlerini ve her birinin kaynağını (Bu host / Host * / Dosyanın başı / Dahil edilen / Varsayılan) gösteriyor; "Tümünü Göster" kalan ayarları açıyor.
- [ ] ProxyJump kullanan host'ta `Bu Mac → bastion → host` zinciri görünüyor; "Zinciri Test Et" sırayla test ediyor, başarısız halkadan sonrakiler "Atlandı".
- [ ] Grup atanan hostlar kenar çubuğunda grup başlıkları altında; grupsuzlar en altta "Diğer Hostlar". Dosyadaki değişiklik yalnızca `# group:` satırı (Kaydet farkında kontrol).
- [ ] Favori hostlarda yıldız; sağ tık ve detaydaki yıldızla ekleme/çıkarma.
- [ ] Var olmayan IdentityFile, yinelenen alias ya da parolasız anahtar kullanan hostta ⚠ ve açıklaması görünüyor; düzeltince hemen kayboluyor.
- [ ] Menü çubuğunda "Host" menüsü: ⌘N, ⌘D, Sil… (onaylı; ⌫ / ⌘⌫ yalnızca liste odaktayken), ⌘T, ⌘↩, ⌘⇧F, ⌘⇧C çalışıyor; metin alanında ⌘⌫ satır silmeye devam ediyor.
- [ ] Hızlı Bağlan paneli açıkken ⌘↩ (test), ⌥↩ (kopyala), ⌘S (favori) menüye takılmadan panelde çalışıyor; Anahtarlar penceresinde Host menüsü öğeleri pasif.
- [ ] "Tümünü test et" sonrası araç çubuğunda ✓/⚠/✕ sayıları; birine tıklayınca liste süzülüyor, "Tümünü Göster" ile kalkıyor.
- [ ] Boş config ile açılınca üç adımlı karşılama ekranı; "Anahtar oluştur" Anahtarlar penceresini Yeni Anahtar formuyla açıyor.

## Plan 8 — Fark ve arayüz rötuşları

- [ ] Çok uzun satırlı (200+ karakter) bir diff kaydırılırken tüm satırların eklenen/silinen arka planı aynı sağ kenarda bitiyor, satır genişlikleri aşağı kaydırınca zıplamıyor.
- [ ] Yedekler penceresinde bir yedek seçiliyken pencere yeniden boyutlandırılınca / başka yedek seçilip dönülünce diff takılmadan görünüyor.
- [ ] VoiceOver: bant (banner) simgeleri ayrıca okunmuyor, yalnızca mesaj ve düğmeler okunuyor.
- [ ] Kenar çubuğunda desen / Match gibi bağlanamayan bir satıra sağ tık: menü ayırıcıyla başlamıyor.
- [ ] Bağlantı çubuğundaki rozetin üstüne gelince çıkan ipucu yalnızca durumu gösteriyor (ayrıntı yanındaki metinde, tekrar yok); kenar çubuğundaki rozetin ipucu ayrıntıyı içermeye devam ediyor.
- [ ] Ayarlar → Bağlantı: kısayol kaydedici, "Girişte aç" anahtarının onay/hata metinlerinin altında.
- [ ] Ghostty seçiliyken Bağlan, Ghostty'yi paket kimliğiyle (`open -n -b com.mitchellh.ghostty --args …`) yeni örnek olarak açıyor ve ssh çalışıyor; "Anahtarı sunucuya yükle" da pencereyi tuş basışına kadar açık tutuyor.
- [ ] Terminal/iTerm2 ile Bağlan'a arka arkaya iki kez hızlı basınca tek pencere açılıyor; ilk Otomasyon izni istemi sırasında uygulama arayüzü donmuyor; Bağlan düğmesi bu sırada pasif. İzni reddet, Sistem Ayarları'nda onayla, tekrar Bağlan: hem Terminal hem iTerm2 için çalışıyor (izin istemi uzun beklerse -1712 zaman aşımı: iTerm2 Terminal'e düşüyor).
- [ ] ⌥⌘S paneli başka bir uygulamanın üstünde açılınca o uygulama ön planda kalıyor (ana pencere öne gelmiyor), arama alanına yazılabiliyor ve ↩ ile bağlanılabiliyor.
- [ ] Girişte açılışta (menü çubuğu modu) ilk 3 saniye içinde menü çubuğundan 'Ana pencereyi aç' ya da Dock'tan açılan pencere kapanmıyor; SwiftUI'nin kendi açtığı pencere hâlâ kapanıyor.
- [ ] Menü çubuğu penceresi ya da Hızlı Bağlan paneli açıkken Dock ikonu görünmüyor; yalnızca ana/Ayarlar/Yedekler penceresi açıkken görünüyor.
