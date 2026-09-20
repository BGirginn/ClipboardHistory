# CoreDeck — Rakiplerle Kıyaslanabilir Utility Hub Roadmap’i

Revizyon: 2026-09-20. Başlangıç commit’i: `54abfa04f1b4c606a2faa5ba4a36219b18b286f7`.

Durum: GitHub pull ve plan revizyonu tamamlandı; aşağıdaki uygulama/kabul aşamaları tamamlanmadı. [Kaynak analiz](RELEASE_READINESS_PLAN_TR.md) R00–R12 bulgularını ve bu revizyonda gerçekten doğrulanan durumları içerir.

## 1. Sabit ürün kararları

CoreDeck; pano, notlar, drawer, sistem metrikleri, girdi araçları ve ses kontrolünü tutarlı, anlaşılır ve akıcı bir native macOS deneyiminde birleştirecek. Hedef kullanıcı, az ayarla günlük görevlerini tamamlamak isteyen Mac kullanıcısıdır; klavye ile hızlı kullanım da bütün temel akışlarda korunur.

- Community self-signed dağıtım korunur; Developer ID/notarization kapsam dışıdır.
- Yeni Quick Center/Settings düzeni ve tam drawer zorunludur. Wi-Fi, Bluetooth, Battery ve Sound ile Focus kabulü desteklenen OS matrisinde tamamlanmadan tam yayın yapılmaz.
- Kendi ikon drawer’ı ara teslimdir. Kararsız kimlikli veya korunan dış öğe zorlanmaz; desteklenmeme nedeni kullanıcıya gösterilir. Clock, Siri, Control Center ve gizlilik göstergelerini zorla gizleme hedeflenmez.
- Yerel/offline mimari, mevcut veri formatları ve imza kimliği korunur. Hesap, bulut, AI, mobil/Intel desteği veya rakiplerin tüm özelliklerinin birebir kopyası eklenmez.
- Görünen ad CoreDeck’tir. Eski teknik kimlikler uyumluluk sözleşmesidir; toplu string replacement ile değiştirilmez.
- GitHub deposunun yeniden adlandırılması varsayılmaz veya otomatik yapılmaz. Mevcut doğrulanmış depo `BGirginn/ClipboardHistory`, Cask token’ı `clipboardhistory` olarak kalır; gerçek bir depo taşıması ayrıca doğrulanmadan CoreDeck URL’si dağıtımda kullanılmaz.

## 2. Referanslar ve karşılaştırma yöntemi

| Alan | Referans ürün | Karşılaştırılan görev/kalite |
|---|---|---|
| Pano | [Paste](https://pasteapp.io/help/search-and-filters), [Maccy](https://maccy.app/) | Bulma, filtreleme, sabitleme, klavyeyle seçim ve doğru hedefe yapıştırma |
| Drawer | [Ice](https://icemenubar.app/) | Yerleşim, sürükleme, gizli öğeye erişim ve eski konuma güvenli dönüş |
| Sistem izleme | [iStat Menus](https://bjango.com/mac/istatmenus/) | Okunabilir metrikler, doğru birimler ve ayrıntıya erişim |
| Ses | [SoundSource](https://rogueamoeba.com/soundsource/) | Uygulama bazında anlaşılır gain/mute, kararlı kontrol ve cihaz değişimi |
| Birleşik deneyim | [Raycast](https://www.raycast.com/core-features/clipboard-history) | Hızlı erişim, tutarlı klavye davranışı ve gezinme yükü |

Resmî sayfalar özellik/akış referansıdır; rakip performansına dair ölçüm sayılmaz. Karşılaştırmalar aynı Mac, OS, ekran ayarı ve sentetik içerikle yapılır; kullanılan ürün sürümü, ayarlar ve adımlar kaydedilir. Hedef uygulama ve erişilebilirlik izinleri eşdeğer tutulur; rakipler ölçüm sırasında aynı anda arka planda çalıştırılmaz.

İlk kurulum/izin maliyeti ile tekrar kullanım ayrı kaydedilir. Her ortak görevde başarı, kullanıcı eylemi sayısı, süre ve hata sonrası toparlanma ölçülür. Bir tıklama, bir kısayol veya kesintisiz bir metin girişi bir eylemdir. Aynı görev tekrar kullanımda referansın en kısa desteklenen akışından birden fazla ek eylem gerektiriyorsa yeniden tasarlanır. Referans ürünün desteklemediği görev doğrudan ürün kabulüyle değerlendirilir; başarısız kıyas olarak işaretlenmez.

## 3. Uygulama aşamaları

| ID / bağlı bulgular | İş ve teslim çıktısı | Geçiş koşulu |
|---|---|---|
| **M0 — Güncel başlangıç** / R00, R01, R11 | Güncel CI/test hatalarını sınıflandır; closure ve ekran ölçeği regresyonlarını düzelt. CoreDeck görünen/teknik kimlik envanterini çıkar. Eski yerel düzeltmeleri yeniden inceleyerek uygula. | Derleme/test çalıştırma engelleri giderilmiş; diğer başarısızlıkların tekrar üretimi, sorumlusu ve kapanacağı aşama belli; eski kaynak kanıtı yeni aday diye kullanılmıyor. |
| **M1 — Güvenilir ölçüm ve kanıt** / R02, R03, R05, R06 | Coverage eksik-dosya ayrımı, soak CPU/RSS/hang/DB kontrolü, CI browser/güvenlik kontrolleri, başarısız raw sonuçlar ve kalıcı ölçüm JSON’u. | Eksik/bozuk kanıt, eşik aşımı ve yanlış DB negatif testleri kontrolü düşürüyor; commit/ortam bilgisi saklanıyor; geçici build temizliği release kanıtını silmiyor. |
| **M2 — Harici drawer fizibilitesi** / R04, R09 | Ayrı test host’unda sistem/üçüncü taraf keşfi, kararlı kimlik, taşıma, alan boşaltma, tıklama ve restore. İzin iptali, yeniden başlama, çökme ve başka manager çakışması. | Beş zorunlu sistem öğesi macOS 14.2+/15/26 kabulünü geçiyor; aynı uygulamanın iki kararlı ikonu ayrılıyor; yanlış eşleme yok. Başarısızlıkta geniş UI/harici entegrasyon ve tam yayın bekler. |
| **M3 — Veri ve yaşam döngüsü** / R04, R11 | Clear, retention/quota, migration/import/export, Notes/Keychain, pending capture, shutdown/reopen; eski beta’dan CoreDeck’e sentetik veri geçişi. | Hata enjeksiyonunda disk/RAM tutarlı; veri/taslak kaybı ve yanlış başarı yok. Marka değişimi yeni boş veri alanı veya erişilemeyen Notes üretmiyor. |
| **M4 — Birleşik UX ve kendi drawer’ı** / R07, R08, R12 | Kompakt Quick Center, Quick Note, bağlamsal Clipboard, sidebar Settings; izin rehberliği; ayrı drawer ikonu/paneli ve Top Bar/Drawer düzenleyicisi. | 380×500 varsayılan Quick Center’da temel araçlar kaydırmadan erişilebilir; tek pencere/controller; seçim, arama ve taslak korunuyor; kendi ikonları ek izin olmadan yönetiliyor. |
| **M5 — Harici drawer entegrasyonu** / R04, R09 | Doğrulanmış adapter, atomik journal, native activation oturumu, restore/recovery, izin/çakışma durumları ve capability UI. | İmzalı adayda move/click/restore/restart geçiyor. Restore hatası otomatik yönetimi durduruyor; retry görünür; temel modüller çalışmaya devam ediyor. |
| **M6 — Bütünleşik kabul ve adayın sabitlenmesi** / R01, R04, R07, R08, R09, R12 | Kullanıcı oturumları, gerçek adaptörler, OS/ekran matrisi, Instruments, 100 döngü ve sekiz saat soak. Darboğazları gider; kaynak sabitlenince kesin Community imzalı adayı üretip kabulü bu pakette tekrarla. | Bütün otomatik/fiziksel kapılar ve Bölüm 5 bütçeleri geçti; açık P0/P1 yok. Kabul edilen paketin hash’i, kaynak commit’i ve ortamı kayıtlı. |
| **M7 — Dağıtım provası ve yayın** / R10, R11 | M6’da kabul edilmiş aynı adayda temiz kurulum, beta.4 yükseltme, kaldırma/kurtarma; ZIP/DMG/extension, checksum/SBOM ve belgeler. | Notes/Clipboard verisi korunmuş; paket kabul edilen uygulamayla aynı. Açık yayın talimatından sonra indirilen GitHub paketi ve Cask kurulumu doğrulanmış. |

Bağımlılık: **M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7**. Kıyaslama görevleri ve baseline M0/M1’de hazırlanır; ürün kabulü M6’da kapanır. M6’da bütün P0/P1 koşulları ve kesin imzalı aday kabulü kapanmalıdır. Sonradan yeniden derleme, yeniden imzalama veya uygulama içeriğini değiştirme yeni aday oluşturur; önceki artifact kabulü devralınmaz. M7’de bulunan hata ilgili aşamayı yeniden açar.

### CoreDeck geçişinin zorunlu alt işleri

- `CoreDeck.app`/executable adı; bundle ID, test host, helper/XPC/Safari kimlikleri, Keychain ve veri dizini için beklenen eşlemeyi sabitle.
- Eski managed Cask upgrade ve unmanaged manuel kurulum akışlarını ayrı sına; iki çalışan kopya, çift login item veya eski helper yolu bırakılmasın. Kullanıcıya ait unmanaged kopya otomatik silinmesin.
- Notes erişimi, geçmiş/preferences, mevcut archive import, Chromium native host ve Safari köprüsünü imzalı yeni uygulamada doğrula.
- TCC izinlerinin korunacağını varsayma; izin korunması, yeniden izin gereksinimi, ret ve revoke akışlarını test et.
- `InfoPlist.xcstrings` dahil EN/TR görünen ad ve izin metinlerini derle; eski teknik kimlikleri kullanıcı metinlerinden ayır.
- Beta.6/build 10006 mevcut kaynağın baseline’ıdır. Daha sonraki tam drawer adayına yeni ve monoton build/sürüm ver; beta.6 tarihli yeniden adlandırma notlarını gelecekteki doğrulamalarla geriye dönük yeniden yazma.

## 4. Mimari ve UX sözleşmesi

- Mevcut ortak feature controller’ları korunur. `MenuBarController` kendi status item’larının sahibi kalır; harici keşif/taşıma/tıklama/görüntüleme ayrı enjekte edilen adapter protokollerindedir. Sürüme duyarlı çağrılar bu sınırda kalır.
- Kalıcı drawer kimliği kaynak + kararlı semantic identifier’dır. PID, window ID, ekran koordinatı veya değişken başlık kullanılmaz; güvenilir kimlik yoksa işlem kapalıdır.
- Drawer ayarları ayrı sürümlü yapı ve atomik pending-operation journal’ı kullanır. Önce snapshot ve original komşu anchor’ları kaydet, taşı, yeni snapshot ile doğrula, sonra tercih commit et. Hata → restore → doğrulama; restore da başarısızsa otomatik reconcile durur ve recovery görünür olur.
- Başlangıç kendi ikonlarımızla çalışır. Harici yönetim açık kullanıcı eylemiyle etkinleşir. Gerekli ekran/Accessibility izinleri açıklanır; izin reddi temel modülleri kapatmaz. Başka menu bar manager varsa harici yönetim askıya alınır.
- Ana ikon Quick Center, ayrı sabit drawer ikonu yatay shelf açar; drawer ikonu kendi içine taşınamaz. Hover açmaz. Quick Center/drawer karşılıklı dışlanır; native menü/editor/modal odağı Escape ve outside-click kapanmasından önce gelir.
- Dış ikona tıklama, güncel keşif sonrası button/modifier bilgisini korur. Geçici taşıma native menü kapanana kadar geri alınmaz; timeout, uyku, permission revoke ve shutdown cancel/restore yolunu kullanır.
- Quick Note mevcut taslağı paylaşır; başarısız save taslağı korur. Settings tek yeniden kullanılan sidebar penceresinde doğru bölüme gider. Clipboard arama/selection/scroll/paste stack düzeni içerik alanını gereksiz küçültmez.
- Her modülde yükleniyor, boş, hazır, izin gerekli, desteklenmiyor ve hata durumları ayrılır. Hata görünür retry/kurtarma yolu sunar; yanlış başarı ve belirsiz çalışmayan kontrol olmaz.
- Tek metric producer ve mevcut demand modeli korunur. Drawer kapandığında ona ait capture/cache/metric demand durur. Tek lifecycle scope task/observer/timer sahipliğini toplar; native animasyon korunur.

## 5. Kabul matrisi ve bütçeler

### Günlük kullanım görevleri

Beş deneme kullanıcısı aşağıdaki on görevi sentetik veriyle yardım almadan dener. Görev adımları sırasında moderatör ipucu verilmez; ilk kurulum ayrı kaydedilir. Kullanıcılar mevcut yetkiyle erişilebilen test katılımcıları olmalı; bu belge dış kişilere mesaj gönderme yetkisi değildir.

| ID | Görev | Beklenen sonuç |
|---|---|---|
| U01 | İlk pano kaydını yeniden kullan | Kopyalanan içerik bulunur, doğru hedefe aktarılır; temel kayıt için gereksiz izin istenmez. |
| U02 | Geçmişte arama ve filtreleme | Doğru sonuç bulunur; klavye ile seçilir; aktif filtre anlaşılır ve temizlenebilir. |
| U03 | Düz metin yapıştır | Biçim kaldırılır; hedef korunur; stale rich payload geri gelmez. |
| U04 | Sık kullanılan içeriği sabitle ve bul | Sabitleme anlaşılır; korunmuş öğe beklenmedik eviction ile kaybolmaz. |
| U05 | Quick Note oluştur ve kaydet | Editör odaklanır; pending/saved/failed ayrılır; başarı yalnız kayıt tamamlanınca görünür. |
| U06 | Taslağa yeniden ulaş | Pencere/panel geçişinde taslak ve seçim korunur; yeniden açılışta kaydedilen içerik doğru gelir. |
| U07 | Keyboard Cleaning başlat ve durdur | Start/Stop anlaşılır; mouse ile durdurulabilir; izin hatası normal girdiyi bozmaz. |
| U08 | Sistem durumunu oku | CPU/RAM/sıcaklık okunur; loading, gerçek sıfır ve unavailable karışmaz. |
| U09 | Bir uygulamanın sesini değiştir | Doğru uygulama etkilenir; slider sıçramaz; hata/cihaz kaybında native ses geri gelir. |
| U10 | Drawer’a taşı, aç ve geri al | Doğru ikon taşınır, doğru native UI açılır; konum geri yüklenir. |

Geçiş: 50 görev denemesinde en az 45 başarı ve her görevde en az 4/5 başarı. Veri kaybı, yanlış hedefe işlem veya girdi/ses kontrolünü kaybetme tek vakada dahi yayını durdurur. Müşteri araştırması yerine geçen istatistiksel bir iddia kurulmaz; bu sınırlı bir kullanım kabul testidir.

### Performans

| Ölçüm | Zorunlu eşik |
|---|---|
| 5.000 öğe yazma / okuma | p95 ≤100 / ≤50 ms |
| Model load / filtre / ilk layout | p95 ≤100 / ≤50 / ≤50 ms |
| Quick Center ve drawer ilk görünür frame | p95 ≤120 ms; gerçek uygulamada |
| Cache hit harici activation başlangıcı | p95 ≤50 ms; native menünün açılma süresi ayrıca ölçülür |
| Boşta uygulama | Medyan CPU <%1; kararlı RSS <75 MB |
| Drawer kapalı, harici yönetim açık | Ek medyan CPU ≤0,2 yüzde puanı; sürekli ekran yakalama yok |
| İkon cache | En fazla 64 görsel veya 8 MiB; ilk dolan sınır uygulanır |
| 100 aç/kapat | Status item, observer, timer, task ve event tap sayıları başlangıca döner |
| Sekiz saat soak | RSS büyümesi <%10; crash/hang yok; SQLite integrity_check=ok |
| 60 Hz shelf scroll/customization drag | Missed-frame <%1 |

Release/CommunityRelease kullanılır. Kısa işlemler beş ısınma sonrası en az 100 örnekle ölçülür; soğuk açılış ayrı raporlanır. Boşta ölçüm iki dakika sakinleşme ardından on dakika örneklenir. Soak büyümesi ilk ve son on dakikanın medyan RSS değerleriyle hesaplanır. Fixture ve işlem sınırları M1’de sabitlenir; sonuca göre değiştirilmez. Test host layout süresi gerçek frame süresinin yerine geçmez. Aktif ses/OCR yükü boşta bütçesiyle karıştırılmaz; donanım ve fixture kaydedilir. Bu sayılar ürün hedefidir, rakiplerde ölçülmüş değerler değildir.

### Teknik ve platform kabulü

Tam unit/UI, browser, statik kalite/yerelleştirme, security, analyzer, Debug/Release/CommunityRelease arm64, ayrı ASan/TSan, kritik mutation ve coverage çalışır. Coverage ≥%95; her yürütülebilir üretim kaynağı >0. Test atlayarak veya eşikleri gevşeterek kabul oluşturulmaz.

Gerçek adapter senaryoları: izin ret/revoke, uyku/uyanma, event-tap/pipeline kaybı, çok process/çok browser, cihaz değiştirme, incognito/DRM sınırları, sensör yokluğu, silme/rollback/migration ve yükseltmede Keychain. OS matrisi arm64 macOS 14.2 alt sınırı, 15 ve 26; geliştirici beta’da güvenli uyumsuzluk ayrıca sınanır.

Görsel matris: TR/EN, Türkçe i/ı/İ/I ve IME, undo/redo, VoiceOver/klavye odağı, light/dark, yüksek kontrast, Reduce Motion/Transparency, %200 ölçek, küçük ekran/notch, çoklu ekran, Spaces, full-screen, auto-hide.

## 6. Takip, yetki ve yayın kararı

Durumlar: `Bekliyor` → `Çalışılıyor` → `Doğrulanıyor` → `Tamamlandı`; somut engelde `Engelli`. Kanıtı olmayan iş tamamlandı olmaz. Alt işler `M0.1` gibi kimlik alır; bağlı R-ID, sorumlu, bağımlılık, çıktı, kabul testi, kanıt ve durum alanlarını taşır. Bölüm 3’teki çıktı/kabul hücresi aşağıdaki aynı ID’nin iş kartının parçasıdır.

| ID | Sorumlu | Bağımlılık | Durum | Kanıt |
|---|---|---|---|---|
| M0 | Uygulayıcı geliştirici/ajan | Pull ve başlangıç incelemesi | Çalışılıyor | Son üretim/test kaynağında 331/331 unit ve kimlik envanteri geçti. Tam UI koşusu Xcode kimlik doğrulaması iptal edildiği için başlatılamadı. macOS 14/15/26 çalışma zamanı ve güncel CI matrisi açık. [Güncel çalışma kaydı](RELEASE_READINESS_PLAN_TR.md#7-20-eylül-son-doğrulama-ve-kurtarma-güvenliği) |
| M1 | Uygulayıcı geliştirici/ajan | M0 | Doğrulanıyor | Kaynak hash denetimi, başarısız log/özet saklama ve negatif senaryolar geçti; 11/11 Python, 2/2 browser ve tüm shell regresyonları başarılı. Önceki %95,153 coverage drawer öncesi tarihsel kanıttır. Son UI başlatma engeli nedeniyle güncel tam coverage kabulü ve CI koşusu açık. [Çalışma kaydı](RELEASE_READINESS_PLAN_TR.md#7-20-eylül-son-doğrulama-ve-kurtarma-güvenliği) |
| M2 | Geliştirici + maintainer/test sorumlusu | M1 | Engelli | macOS 27 beta’da beş zorunlu öğe discovery, native activation ve move/restore testini geçti; MenuBarAgent restart journal recovery ve aynı process içindeki iki eş başlıklı ikonun stable-ID ayrımı doğrulandı. 20 Eylül kurtarma korumaları 38 sentetik kontrolü geçti; bunlar native kabul değildir. Gerçek alan boşaltma ve açılan native panelin hedef kimliği doğrulanmadı. 14.2+/15/26 fiziksel matrisi, izin revoke ve başka manager çakışması da bekliyor. [Çalışma kaydı](RELEASE_READINESS_PLAN_TR.md#5-1619-eylül-uygulama-kaydı) |
| M3 | Uygulayıcı geliştirici/ajan | M2 | Bekliyor | Henüz üretilmedi |
| M4 | Uygulayıcı geliştirici/ajan | M3; tam M2 kabulü | Çalışılıyor | Kendi modüllerimizin drawer’ı ara teslim olarak uygulandı; ortak controller, tekrar kullanılan popover, taşı/geri al ve System Monitor tercihlerinin korunması test edildi. M2/M3 kapanmadı; Quick Center/Quick Note/sidebar Settings ve tam M4 kabulü açık. [20 Eylül kaydı](RELEASE_READINESS_PLAN_TR.md#6-20-eylül-kendi-drawer-ara-teslimi) |
| M5 | Geliştirici + maintainer/test sorumlusu | M4; M2 kabulü | Bekliyor | Henüz üretilmedi |
| M6 | Geliştirici + maintainer/test sorumlusu | M5 | Bekliyor | Henüz üretilmedi |
| M7 | Yayın sahibi + maintainer/test sorumlusu | M6; dağıtım için açık talimat | Bekliyor | Henüz üretilmedi |

Pull talimatı yerine getirilmiştir. Bu revizyon commit, push, tag, depo yeniden adlandırma veya yayın yetkisi değildir. Mevcut kullanıcı çalışmaları korunur; imza/özel anahtar/parola evidence’e girmez. Community imzası veya şifresiz Clipboard deposu rakiplerle güvenlik eşdeğerliği olarak sunulmaz.

İki sonuç ayrı izlenir: **Yayına hazır**, tam drawer dahil bütün kapıların, kesin imzalı adayın ve dağıtım provasının başarılı olmasıdır. **Yayın tamamlandı**, ayrıca açık yayın talimatı sonrasında indirilen GitHub/Cask artifact'inin doğrulanmasıdır. Planın yazılması veya beta.6 adı bu koşulları kapatmaz.

## 7. Beta.6 için onaylanan yayın kesiti

21 Eylül 2026 yayın talimatı, beta.6 için fiziksel OS matrisi, beş kullanıcılı kabul, sekiz saat soak ve ayrı imza kabulini zorunlu kapılardan çıkardı. M2'nin harici sistem/üçüncü taraf ikon taşıma adaptörü desteklenen OS matrisinde doğrulanmadığından beta.6'ya dahil edilmedi. Bu nedenle M2 ve M5 tam ürün roadmap'inde açık kalır; beta.6 yalnız kendi CoreDeck modüllerinin drawer'ını sunar ve tam harici drawer desteği iddia etmez.

Beta.6 yayın kesitinin tamamlanma sırası:

1. 346 unit test, browser, otomasyon, journal, statik kalite, güvenlik, analyzer, üç arm64 yapılandırma, sanitizer, mutation ve Release performans sonuçlarını kaynak commit'ine bağla.
2. Kilitli macOS oturumunda test başlamadan iptal edilen UI koşusunu ve buna bağlı yerel %95 coverage eksiğini yayın notlarında/kanıtta açık tut; sonucu başarı olarak işaretleme.
3. Temiz commit'ten Community artifact setini üret; ZIP, DMG, Chromium paketi, SPDX SBOM, checksum ve imza kanıtını aynı kaynak SHA'sına bağla.
4. GitHub prerelease'i yayımla, ZIP'i yeniden indir ve SHA-256 eşliğini doğrula.
5. `BGirginn/homebrew-tap` Cask'ini aynı ZIP URL ve hash'iyle güncelle; canlı Cask fetch'ini doğrula.

Bu kesit tamamlandığında **beta.6 prerelease yayımlandı** denebilir. Fiziksel kabulden feragat, tam drawer roadmap'ini veya sonraki stable sürüm kapılarını tamamlanmış saymaz.
