# Arayüz Geliştirmeleri (v1.1) — Tasarım

Ana spec: `docs/design/2026-10-07-ssh-config-manager-design.md`. Bu doküman ona eklenir; çelişki yoksa ana spec'in kuralları (kayıpsız düzenleme, `ssh -G` doğrulaması, yerelleştirme, test yalıtımı, Türkçe I/İ kuralı) aynen geçerlidir.

## 1. Amaç

Günlük kullanımı hızlandırmak (son bağlanılanlar, favoriler, akıllı arama, kısayollar), config'i anlamayı kolaylaştırmak (etkin ayarlar ve kaynakları, ProxyJump zinciri, uyarılar) ve düzeni artırmak (gruplar, durum özeti, boş durum ekranı). Config dosyasına uygulamaya özgü veri yazılmaz; tek istisna, ssh'in yorum olarak yok saydığı `# group:` satırıdır (§9).

**Başarı kriterleri**
1. ⌥⌘S → (arama yazmadan) ↩ ile en son bağlanılan host'a bağlanılır.
2. `prd web` araması `prod-web-01`'i ilk sırada bulur.
3. Bir host'un her etkin ayarının nereden geldiği (bu blok, `Host *`, başka desen, Include, varsayılan) görülür.
4. Grup atamak ya da kaldırmak dosyada yalnızca ilgili yorum satırını değiştirir; diğer her bayt aynı kalır.

## 2. Son bağlanılanlar ve favoriler

- **Saklama:** `UserDefaults`, anahtar `hostMemory.<configKey>`; `configKey`, yedek türüyle aynı kuraldan türetilir (`config` ya da `config-<sha256 ilk 12>`). Değer: `{ "favorites": [alias], "recents": [alias] }`. Alias'lar dosyada yazıldığı biçimde saklanır; karşılaştırma tam eşitliktir (büyük/küçük harf duyarlı): ssh `Host` eşleştirmesi duyarlı olduğundan (§5) `Web` ve `web` ayrı hostlardır; ayrı favori/son kaydı tutulur ve hızlı bağlan ile bağlanma listelerinde ayrı görünür. Aynı alias'ın tekrarında ilk blok geçerlidir.
- **Son bağlanılanlar:** `connect` sonucu `.launched` ya da `.fellBack` olunca alias listenin başına alınır (tekrarı silinir), en fazla 5 tutulur. Test, ssh-copy-id ve başarısız bağlantı eklemez.
- **Favoriler:** Kenar çubuğu sağ tık menüsü ("Favorilere ekle/çıkar"), detay başlığındaki yıldız düğmesi ve panelde ⌘S kısayolu ile değiştirilir. Sıra eklenme sırasıdır.
- **Gösterim:** Menü çubuğu ve ⌥⌘S panelinde arama boşken bölümler: **Favoriler**, **Son**, **Tüm hostlar** (bir host yalnızca ilk uygun bölümde görünür). Arama varken bölüm yoktur, yalnızca sıralı sonuçlar. Kenar çubuğunda favori hostların yanında küçük bir yıldız gösterilir.
- **Eskiyen kayıtlar:** Kaydedilmiş dosyada (ssh'in okuduğu) artık olmayan alias'lar gösterilmez; listede kalır ama dosyaya geri eklenirse yeniden görünür. Kayıt büyümesin diye favoriler en fazla 50, son bağlanılanlar 5.

## 3. Akıllı arama (panel ve menü çubuğu)

- Sorgu boşluklarla kelimelere ayrılır; **her kelime** host'un alias'ında bulanık (harf sırası korunur) ya da HostName/User/grup adında alt dize olarak eşleşmelidir.
- Karşılaştırma `folding([.caseInsensitive, .diacriticInsensitive], locale: .current)` ile yapılır (kullanıcıya yönelik arama; ana spec §6.5).
- **Puan** (yüksekten düşüğe): alias tam eşleşme > alias baştan > alias kelime başlarından (`-`, `.`, `_`, rakam sınırları) > alias dağınık > yalnızca HostName/User/grup. Eşit puanda favori > son bağlanılan > dosya sırası.
- Alias'ta eşleşen karakterler kalın gösterilir (`AttributedString`).
- Ana penceredeki kenar çubuğu araması değişmez (alt dize).

## 4. Klavye kısayolları

- Uygulama menü çubuğuna **Host** menüsü (`CommandMenu`): Yeni Host ⌘N, Çoğalt ⌘D, Sil… ⌘⌫ (onay ister), Test Et ⌘T, Bağlan ⌘↩, Favori ⌘⇧F, `ssh` Komutunu Kopyala ⌘⇧C. Seçim uygun değilse (desen, Match, kaydedilmemiş host) ilgili öğe pasif.
- Panel / menü çubuğu: ↩ bağlan, ⌘↩ test, ⌥↩ komutu panoya kopyala, ⌘S favori, esc kapat.
- Kısayollar ana pencere odaktayken çalışır; metin alanı odaktayken ⌘⌫ metin silmeye kalır (yalnızca liste/odak dışındayken host siler).

## 5. Etkin ayarlar ve kaynakları

- **Değerler:** `ssh -G [-F] -- <alias>` çıktısı (5 sn sınır). Gösterilen anahtarlar: `hostname`, `user`, `port`, `identityfile`, `proxyjump`, `proxycommand`, `forwardagent`, `identitiesonly`, `localforward`, `remoteforward`, `dynamicforward`, `serveraliveinterval`, `stricthostkeychecking`, `userknownhostsfile`, `controlmaster`, `controlpath`; diğerleri "Tümünü göster" ile.
- **Kaynak:** Paket içinde `ConfigResolver`, kaydedilmiş belge + Include'larla ssh'in kuralını uygular: bloklar dosya sırasıyla taranır, `Host` desenleri (`*`, `?`, `!` olumsuzlama; boşlukla ayrılmış liste — `Host` satırında virgül ayırıcı değildir) alias'a **büyük/küçük harf duyarlı** eşleştirilir (OpenSSH 10.3 ile doğrulandı: `Host WEB` `ssh -G web`'e uygulanmaz), **her anahtar için ilk elde edilen değer kazanır** (çok değerli `IdentityFile`, `CertificateFile`, `LocalForward`, `RemoteForward`, `DynamicForward`, `SendEnv` birikir — yinelenen IdentityFile bir kez, `SendEnv -DESEN` öncekileri siler; `SetEnv` için ilk satır kazanır). Sonuç `[anahtar: (değer, kaynak)]`; kaynak `.thisBlock`, `.otherHost(desenler)`, `.include(dosya, desenler)`, `.unresolved`.
- **Match blokları** değerlendirilmez. ssh -G değeri, çözümleyicinin değeriyle uyuşmazsa (ya da çözümleyicide yoksa ve ssh'in varsayılanı değilse) kaynak "Match / belirsiz" gösterilir. Çözümleyicide yok ve ssh -G değeri yalnızca varsayılan ise "varsayılan".
- **Önbellek:** Tam alias başına (büyük/küçük harf duyarlı) ssh -G sonucu; kaydedilmiş dosya değişince (`onDiskStateChange`) ya da config değişince temizlenir. Aynı anda en fazla 2 ssh -G.
- **Kaydedilmemiş host:** Bölüm "Kaydedildikten sonra gösterilir" notu verir (ssh kaydedilmiş dosyayı okur).
- Detayda açılır-kapanır "Etkin ayarlar" bölümü; açık/kapalı durumu oturumluk.

## 6. Bağlanma önizlemesi (panel ve menü çubuğu)

- Seçili host için tek satır: `user@hostname:port` (port 22 ise yazılmaz) ve varsa ` · <ilk atlama> üzerinden`. §5'teki önbellekten okunur; yoksa arka planda ssh -G başlatılır (150 ms gecikmeyle, seçim değişirse iptal), gelene kadar `HostName` değeri ya da "…" gösterilir.

## 7. ProxyJump zinciri

- `proxyjump` değeri (virgüllü liste, `none` hariç) atlama noktalarına ayrılır; her atlama `[user@]host[:port]` biçimindedir. `host` kaydedilmiş config'te bir alias ise zincirde alias olarak gösterilir ve özyinelemeli olarak onun da ProxyJump'ı açılır (en fazla 5 seviye, döngü tespiti).
- Görünüm: detayda `Bu Mac → bastion → prod-db`. Alias olan her düğümde bağlantı testi rozeti; "Zinciri test et" düğmesi alias olan düğümleri baştan sona sırayla test eder (bir düğüm başarısızsa sonrakiler "atlandı").
- Alias olmayan atlama düz metin gösterilir, test edilmez. `proxycommand` varsa "ProxyCommand kullanılıyor" notu; zincir çizilmez.

## 8. Uyarı rozetleri

Paket içinde `HostLint` (dosya varlığı ve anahtar başı okuma enjekte edilir). Kontroller (kaydedilmemiş belge değil, **düzenlenen belge** üzerinde, böylece kullanıcı düzeltirken anında görür):
- **IdentityFile bulunamadı:** `KeyUsage.resolve` ile çözülen yol yoksa. Çözülemeyen (`%h` vb.) değerler uyarı vermez.
- **Yinelenen alias:** Düzenlenebilir hostlar ve Include edilenler arasında aynı alias birden fazla blokta. Tam eşleşen alias'larda ilk/sonraki sıralaması tam adlarla hesaplanır: ilk blok için "sonraki bloklarda da var; onlar yalnızca bu blokta olmayan ayarları ekler", sonrakiler için "daha önceki bir blokta tanımlı; oradaki değerler önceliklidir" iletisi çıkar (ssh her anahtarda ilk değeri alır). Kök dosyada bir `Include` satırı host bloğundan önceyse ve dahil edilen dosyalar aynı alias'ı (tam ad) tanımlıyorsa kök blok ilk sayılmaz. ssh Host desenlerini büyük/küçük harfe duyarlı eşleştirdiğinden (§5) yalnızca harf büyüklüğüyle ayrılan alias'lar (`Web`/`web`) için ayrı bir ileti vardır ("yalnızca büyük/küçük harfle ayrılıyor; ssh bunları farklı hostlar sayar"): bu, olası yazım hatası uyarısıdır ve bir öncelik sırası söylemez. Düzenleyicide yalnızca taslağın eklediği alias'lar denetlenir: tam eşleşen yeni alias engeller, harf farkıyla eşleşen engellemeyen uyarıdır; blokta zaten bulunan alias'lar (var olan kopyalar) düzenlemeyi engellemez.
- **Parolasız anahtar:** IdentityFile'ın başı `KeyFileInspector` ile parolasız özel anahtar ise.
Kenar çubuğunda ⚠ (ipucunda sorunlar), detayda sorun listesi. Desen bloklarında (kenar çubuğu "Desenler" bölümü dahil) yalnızca IdentityFile kontrolü; yinelenen alias uyarısı yoktur ve grup satırı gösterilmez.

## 9. Gruplama

- **Sözdizimi:** Bir `Host` satırının hemen üstündeki ardışık yorum bloğunda (araya boş satır girmeden) `# group: <ad>` satırı. Anahtar kelime ASCII büyük/küçük harf duyarsız; `#` ile `group` arasında boşluk isteğe bağlı; ad baştaki/sondaki boşluklardan arındırılır; boş ad = grup yok. Birden fazla varsa en yakın (Host'a en yakın) olan geçerlidir.
- **Okuma:** `HostEntry.group: String?` (parser değişmez; grup, bloğun önceki yorum satırlarından türetilir).
- **Yazma:** `ConfigDocument.setGroup(at header:, to name: String?)` — mevcut `# group:` satırını değiştirir/siler ya da Host satırının hemen üstüne yeni satır ekler (Host'un girinti stiline bakmadan sütun 0, dosyanın satır sonu stiliyle). Başka hiçbir satır değişmez. Ad kontrol karakteri içeremez.
- **Arayüz:** Host formunda "Grup" alanı (mevcut gruplar önerilir). Kenar çubuğunda düzenlenebilir hostlar grup adına göre bölümlere ayrılır (alfabetik, sonra "Grupsuz"); desenler, Include edilenler, Match bölümleri değişmez. Panelde grup adı ikincil metinde.
- Çoğaltma grubu korur (yorum bloğu kopyalanmaz; yalnızca `# group:` satırı yeniden yazılır).

## 10. Durum özeti

- Araç çubuğunda, en az bir test sonucu varken: `✓ 12  ⚠ 2  ✕ 1` (erişilebilir / kimlik doğrulama ya da bilinmeyen host anahtarı / diğer hatalar). Yalnızca şu an bağlanılabilir hostların sonuçları sayılır.
- Bir kategoriye tıklamak kenar çubuğunu o kategorideki hostlara süzer (`AppModel.statusFilter`); süzgeç açıkken kenar çubuğu başında "Süzgeç: … ✕" satırı. Config değişince ya da sonuçlar temizlenince süzgeç kalkar.

## 11. Boş durum ekranı

- Dosya yüklü ve bağlanılabilir/düzenlenebilir hiç host yokken detay alanında üç adımlı ekran: **İlk host'u ekle** (yeni host + form), **Anahtar oluştur** (Anahtarlar penceresini Yeni Anahtar formuyla açar), **Sunucuya yükle** (Anahtarlar penceresini açar). Dosya yokken mevcut "Oluştur / Başka dosya seç" bandı aynen kalır.

## 12. Test stratejisi

- Paket: `ConfigResolver` (desen eşleşmesi, olumsuzlama, ilk değer kazanır, çok değerli anahtarlar, Include, Türkçe locale), `HostLint`, grup okuma/yazma (gidiş-dönüş bayt eşitliği, CRLF, yalnızca ilgili satırın değiştiği diff), ProxyJump ayrıştırma, bulanık arama puanlaması.
- Uygulama: hafıza (son/favori, eskiyen alias, config başına ayrı), komut menüsü durumları (model düzeyinde), önizleme ve etkin ayarlar önbelleği (sahte runner), zincir testi sırası, durum özeti sayımı ve süzgeç.
- Arayüz görünümleri otomatik test edilmez; `manual-test-checklist.md`'ye "v1.1" bölümü eklenir.
- Testler gerçek `~/.ssh`, `~/Library`, `UserDefaults.standard`, agent, keychain, pano, çöp kutusuna dokunmaz; gerçek ssh çalıştırmaz (ssh -G sahte runner ile).
