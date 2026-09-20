# CoreDeck — Yayın hazırlık analizi

Revizyon: 2026-09-19. İncelenen commit: `54abfa04f1b4c606a2faa5ba4a36219b18b286f7`.

Karar: Tam drawer içeren, günlük kullanıma uygun Community yayını için geliştirme ve kabul çalışması gerekiyor. Bu belge mevcut kaynağı ve eksikleri kaydeder; uygulama sırası ve ürün kabulü [roadmap](RELEASE_ROADMAP_TR.md) içindedir.

## 1. Güncel başlangıç ve kanıt sınırı

`git pull --ff-only origin main`, temiz çalışma ağacında `f8d4c6b` → `54abfa0` olarak tamamlandı. Gelen commit CoreDeck/beta.6 yeniden adlandırmasıdır; 55 dosya değişmiştir. Pull sonrası `main` ve `origin/main` eşleşmektedir. Bu iki plan belgesi pull sonrasında yeniden oluşturulmuştur; önceki konuşmada hazırlanan yerel planlar, drawer blueprint’i, prototip ve düzeltmeler çekilen kaynakta bulunmamaktadır.

| Doğrulanan durum | Kanıt ve anlamı |
|---|---|
| Ürün adı değişti | `CoreDeck.app`, `CoreDeck` executable; Community sürümü `1.0.0-beta.6`, build `10006`. Kaynak target/project/test adları hâlâ ClipboardHistory; bunlar yanlışlık olarak topluca yeniden adlandırılmamalı. |
| Uyumluluk kimlikleri korunuyor | `com.brgirgin.ClipboardHistory`, mevcut Application Support dizini, preferences, Notes Keychain hesabı, helper/browser kimlikleri ve `ClipboardHistory Community Beta` imzası korunuyor. Kaynakta korunmaları gerçek yükseltme kabulünün yerine geçmez. |
| Güncel commit için CI kanıtı yok | Commit mesajı `[skip ci]` içeriyor. GitHub Actions API, bu SHA için 0 koşu döndürdü. Önceki commit’in kırmızı CI sonucu yeni commit’in çalıştırılmış sonucu değildir. |
| Yayın ile belgeler uyuşmuyor | GitHub release listesi ve tap Cask hâlâ `v1.0.0-beta.4` gösteriyor. Beta.6 belgelerindeki yayımlanmış paket ifadeleri dağıtım kanıtı değildir. |
| Yeni depo URL’si doğrulanmadı | `gh repo view` mevcut depoyu `BGirginn/ClipboardHistory` olarak bildiriyor; `BGirginn/CoreDeck` API sorgusu mevcut erişimle 404 döndü. README/dağıtım bağlantıları yayımdan önce gerçek adresle eşleşmeli. |
| Önceki düzeltmeler kaynakta yok | `MenuBarController` içindeki nested closure hâlâ açık `self` kullanmıyor. Render testleri sabit 2× ekran varsayımını, metadata fixture’ı `lockFocus` bağımlılığını koruyor. |
| Yerel ortam kabul matrisinin yerine geçmez | macOS 27.0 beta; seçili developer directory Command Line Tools. Uygulama sırasında kurulu Xcode yolu yeniden doğrulanmalı ve komuta özel seçilmeli. |
| Bu revizyonda uygulama testleri çalıştırılmadı | Pull, kaynak/CI/release/Cask incelemesi ve plan revizyonu yapıldı. Önceki 324 test veya benchmark sonuçları bu kaynak için yeniden doğrulanmış sayılmadı. |

GitHub kanıtları: [kaynak commit](https://github.com/BGirginn/ClipboardHistory/commit/54abfa04f1b4c606a2faa5ba4a36219b18b286f7), [önceki CI koşusu](https://github.com/BGirginn/ClipboardHistory/actions/runs/34217955632), [release listesi](https://github.com/BGirginn/ClipboardHistory/releases), [tap Cask](https://github.com/BGirginn/homebrew-tap/blob/main/Casks/clipboardhistory.rb). Bu dış durumlar 16 Eylül gözlemidir; final adayda yeniden kontrol edilir.

## 2. Eksikler, çözümler ve kapanış koşulları

P0: veri güvenliği, doğru yayın kararı veya temel işlev için engel. P1: hedeflenen ürün kalitesi için yayın öncesi zorunlu. P2: final dağıtım işi. Önceki konuşmanın R00–R10 kimlikleri korunmuştur; CoreDeck geçişi R11, karşılaştırmalı ürün kabulü R12 olarak eklenmiştir.

| ID | Öncelik / eksik | Çözüm ve kapanış kanıtı |
|---|---|---|
| R00 | P0 — Toolchain/test taşınabilirliği ve kırmızı eski CI | Nested closure’ın açık `self` erişimini düzelt; eski macOS 14 derleme hatasını aynı toolchain’de sınayarak kapat. Render fixture’larını ekran ölçeğinden bağımsız üret; piksel doğruluğu kontrollerini koru. Diğer test ve performans başarısızlıklarını raw sonuçlardan ayrı sınıflandır. Güncel adayın zorunlu CI işleri başarılı olmalı. |
| R01 | P0 — Tek adaya bağlı tam kanıt eksik | Commit, kaynak durumu, OS/Xcode, donanım, build türü ve artifact SHA-256 ile test sonuçlarını bağla. Son tam unit/UI koşusunu sakla; eski tarihlerdeki parçalı başarıları birleştirerek final başarı iddia etme. |
| R02 | P0 — Coverage dosya yokluğunu sessiz geçiyor | `verify-coverage.sh` içindeki `missing → continue` ayrımını kaynak/build envanteriyle doğrula. Yalnız yürütülebilir bölgesi olmadığı kanıtlanan dosya muaf olabilir. Eksik instrument edilmiş dosya kontrolü düşürmeli; toplam ≥%95, her yürütülebilir kaynak >0, <%80 dosyalar raporlu olmalı. |
| R03 | P0 — Soak sözleşmesi eksik denetleniyor | Mevcut betik final/initial RSS ve SQLite bütünlüğüyle sınırlı. CPU/RSS bütçesi, hang kontrolü ve süreç–bundle–DB eşleşmesini ekle. <%10 ile ≤%10 farkını sözleşmedeki <%10 lehine düzelt. İzole kullanıcı ve sentetik veri; eşik aşımı, hang ve yanlış DB negatif testleri zorunlu. |
| R04 | P0 — Native adapter ve veri kabulü eksik | CoreAudio, Accessibility, browser, sensör, paste, deletion/migration ve shutdown sınırlarını gerçek adapter kabulüyle tamamla. İzin kaybı, cihaz kaybı, yanlış hedef, rollback ve restart yollarını test et. Stub başarısı bu maddeyi kapatmaz. |
| R05 | P1 — CI kapsamı ve artifact saklama eksik | Browser/otomasyon testleri ve tam Git geçmişiyle güvenlik taramasını CI’ya ekle. Unit/UI özetleri, birleşik report/archive ve release raw sonuçlarını sakla. Her zorunlu dosyanın varlığını ayrı kontrol et; yalnız upload adımının başarılı olması yeterli değil. |
| R06 | P1 — Benchmark/sanitizer hatası teşhis kanıtını kaybediyor | EXIT temizliği build verisini temizlesin; başarısız raw sonucu/logu korusun. Benchmark başarısız olsa da mevcut ölçümleri JSON olarak dışa aktar. Eksik/bozuk metrik ve hata sonucu kontrolü düşürmeli. Kalıcı release kanıtı geçici build temizliğinin dışında tutulmalı. |
| R07 | P1 — Native akıcılık ve kaynak sahipliği ölçülmedi | Release baseline → Instruments ile darboğaz → dar düzeltme → aynı senaryoda tekrar ölçüm. Panel/Drawer first-frame, missed frames, 100 döngü ve idle/soak eşiklerini geç. Native animasyonu koru; tüketici başına timer/producer oluşturma. |
| R08 | P1 — Tam UX/erişilebilirlik matrisi eksik | Bütün modüllerde yükleniyor/boş/hazır/hata/izin durumları, retry, odak, IME, TR/EN, VoiceOver, ekran/Space tercihleri ve tam final UI koşusu kayıtlı olmalı. |
| R09 | P1 — Tam özellik ve Community kabulü | Dağıtım kararı kesin: mevcut self-signed Community. Audio Mixer’ın gerçek ses/browser kabulü tamamlanmadan varsayılan görünürlüğünü genişletme. Tam harici drawer zorunlu; yalnız kendi ikonlarımızın çalışması final kabul değil. |
| R10 | P2 — Final paket/upgrade/dağıtım kanıtı | Kesin temiz adaydan belgelenmiş builder ile paketle. ZIP/DMG/extension, imza, entitlements, minimum OS, SHA-256, SPDX ve Cask aynı artifact’e bağlansın. Yayın yetkisi ardından public indirme ve normal uninstall veri koruması doğrulansın. |
| R11 | P0 — CoreDeck geçişinin uçtan uca kabulü yok | Görünen adı yeni tut; kimlik/veri/imza sınırlarını koru. Eski beta’dan upgrade, çift uygulama, login helper, TCC izinleri, Notes erişimi, browser manifests, arşiv import ve Cask geçişini sınayarak doğrula. `InfoPlist.xcstrings` EN/TR izin metinlerini de derle ve imzalı artifact’te kontrol et. Gerçek GitHub/Cask adresleri ile sürüm iddiaları uyuşmalı. |
| R12 | P1 — Rakiplerle karşılaştırmalı günlük kullanım kabulü yok | Roadmap’teki 10 kullanıcı görevini aynı fixture ve ortamda kıyasla. İlk kullanım/izin akışlarını tekrar kullanımından ayır; başarı, eylem sayısı, süre ve hata sonrası toparlanmayı kaydet. Ürün iddiaları yalnız ölçülen sonuçlara dayansın. |

## 3. Korunacak ürün sınırları

- Ürün CoreDeck; Clipboard History modül adıdır. Mevcut `ClipboardHistory.xcodeproj`, scheme, test host ve kalıcı kimlikleri yeniden adlandırmak bu planın amacı değildir.
- Clipboard yerel ve şifresiz; Notes AES-GCM ile şifrelidir. Rakip kıyası nedeniyle mevcut güvenlik garantisinden daha güçlü bir iddia kurulmaz. Depolama/şifreleme formatı değişmez.
- Community self-signed ve notarized değildir. Kalite kapılarının geçmesi bu imza niteliğini değiştirmez; quarantine atlatılmaz.
- Destek sınırı arm64 macOS 14.2+/15/26; beta OS ayrıca güvenli uyumsuzluk için sınanır. Intel, bulut, hesap, AI ve mobil destek bu yayının kapsamına alınmaz.
- Paylaşılan feature controller’ları, MainActor AppKit sahipliği, kararlı status item kimliği ve tek metric producer korunur.
- Normal kaldırma veriyi korur. Gerçek kullanıcı verisi test fixture’ı yapılmaz; hata durumunda geri dönüş ve kurtarma korunur.

## 4. Uygulama ve kanıt yönetimi

Önce dar regresyon testi, sonra ilgili geniş kapılar çalıştırılır. Swift testleri `scripts/run-development-tests.sh`, coverage `scripts/run-coverage-suite.sh`, yerel release kapıları `scripts/release-gate.sh` üzerinden yürütülür. `release-gate.sh` coverage raporu argümanı ve temiz aday ister; UI/native/OS/soak/dağıtım kabulünü tek başına tamamlamaz. Başarısızlık kanıtı başarıdan önce kaydedilir; test veya eşik düşürülerek yeşil sonuç üretilmez.

Kanıtlar dört sınıfta tutulur: mevcut adayda çalıştırıldı/geçti; tarihli eski kanıt; çalıştırılmadı/ortam yok; başarısız/engelli. Uygulama sırasında her R-ID için sorumlu, çözüm, test çıktısı ve kalan sınır roadmap’te güncellenir. Bu revizyon geçmiş release belgelerini değiştirmez.

Başvuru: [Testing](TESTING.md), [Distribution](DISTRIBUTION.md), [Known Limitations](KNOWN_LIMITATIONS.md), [Privacy](PRIVACY_AND_THREAT_MODEL.md), [Engineering Invariants](ENGINEERING_INVARIANTS.md), [Performance](PERFORMANCE.md), [Architecture](ARCHITECTURE.md), [beta.6 değişiklikleri](RELEASE_NOTES_1.0.0-beta.6.md).

## 5. 16–19 Eylül uygulama kaydı

Bu kayıt `54abfa0` üzerindeki **commit edilmemiş** çalışma ağacına aittir; temiz kaynak veya kesin Community paketi kabulü değildir. Yerel ortam: Mac16,13, macOS 27.0 beta, Xcode 27.0 (27A5237l), arm64. Kanıt dosyaları yerel `.build/DevelopmentTests` ve `.build/ReleaseEvidence` altındadır; yayımlanabilir adaya devredilmez.

| Kapı | Sonuç ve tekrar üretim | Kalan iş / sahibi |
|---|---|---|
| M0 unit ve ekran ölçeği | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer scripts/run-development-tests.sh` ile 324/324 unit ve 324/324 kimlik kontrolü geçti. Panel kapanma saati ve sabit piksel fixture’ları kapsamda. | macOS 14/15/26 CI derleme ve UI koşusu; geliştirici + test sorumlusu. |
| M1 statik/browser/güvenlik | `scripts/verify-static-quality.sh`, `scripts/verify-release-security.sh`, Node browser 2/2, Python betik regresyonları 6/6, coverage shell negatif testleri geçti. Eksik export, eksik merge artifact’i, başarısız run logu ve eksik/eşik üstü/yetersiz örnekli performans JSON’u negatif senaryoları da geçti. | CI’nın güncel commit’te çalışması; geliştirici. |
| M1 coverage | 67 rapor dışı, gövdesi olmayan bildirim/protokol/sabit kaynağı SHA-256 ile denetimli envantere alındı; envanter dışı dosya ve değişmiş içerik negatif testte başarısız oluyor. 19 Eylül temiz koşusu 324/324 unit ve 17/17 UI ile geçti; birleşik üretim coverage %95,153 ve her yürütülebilir kaynak >0. Önceki başarısız raw sonuçlar da korundu. | Güncel commit CI koşusu ve kesin adayda yeniden çalışma; geliştirici + test sorumlusu. |
| M6 performans dilimi | `scripts/verify-performance.sh` optimize Release üzerinde beş ısınma + 100 ölçümle geçti: yazma 31,695; okuma 17,276; model 73,897; filtre 9,300; layout 17,464 ms p95. | Final kesin paket, ilk görünür frame, idle, 100 döngü, sekiz saat soak ve OS matrisi ayrıca gerekir; geliştirici + test sorumlusu. |
| M2 keşif denemesi | `Experiments/DrawerFeasibility/Probe.swift` yalnız okuma ile macOS 27 beta’da `ControlCenter` ve `SystemUIServer` için `AXExtrasMenuBar=-25212` gördü; aynı `MenuBarAgent` sürecinde Wi-Fi, Bluetooth, Battery, Sound ve Focus için birbirinden ayrı `com.apple.menuextra.*` AX kimliklerini buldu. Wi-Fi’nin görünen etiketi literal `Wi-Fi` içermediğinden ilk etiket tabanlı keşif onu kaçırmıştı. | Kimliklerin restart/OS kararlılığı ile macOS 14.2+/15/26 üzerinde alan boşaltan taşıma, native aktivasyon ve restore; geliştirici + fiziksel test sorumlusu. |

Tam drawer **kanıtlanmadı**; M2 ve ardından M3–M7 açık. Bu kayıt hiçbir modülü veya kabul eşiğini kapsam dışına çıkarmaz. [Apple NSStatusBar API’si](https://developer.apple.com/documentation/appkit/nsstatusbar), uygulamanın oluşturduğu `NSStatusItem` nesnelerini yönetir; dış öğe için eşdeğer genel bir sahiplik API’si bu araştırmada saptanmadı. Bu API sınırından, üçüncü taraf/system item taşımasının güvenli olduğu sonucu çıkarılamaz.

17 Eylül ortam değişikliği: `/Applications/Xcode-beta.app` artık bulunmadı; `xcode-select` yalnız `/Library/Developer/CommandLineTools` gösteriyor ve `xcresulttool` yok. Bu yüzden UI sonucunun assertion/attachment ayrıntısı çıkarılamadı, yeni Xcode build/test/analyzer/sanitizer koşusu başlatılamadı. Xcode 27.0 ile 16 Eylül’de tamamlanmış sonuçlar yukarıda tarihleriyle korunur; toolchain yeniden erişilebilir olduğunda başarısız UI sonucu incelenip kapı yeniden çalıştırılır. Bu engel uygulama testini başarılı saymaz.

17 Eylül uzak durum kontrolü: `git ls-remote origin main` yine `54abfa0` gösterdi; `gh release list` son yayımlanan sürümü `v1.0.0-beta.4`, tap Cask dosyası da `1.0.0-beta.4` olarak doğruladı. Bu SHA için `gh run list --commit` boş sonuç verdi. Yerel kirli ağaç uzakta veya Cask’te değildir.

17 Eylül Xcode tekrar kontrolü: `/Applications/Xcode.app` kuruldu ve seçili developer directory bu uygulamanın `Contents/Developer` dizinine döndü. Xcode 27.0 (27A266a), Swift 6.4 ve macOS 27.0 SDK görüldü. Önceki UI sonucunda ilk Notes yazma adımı XCTest olay sentezi zaman aşımıyla düşmüştü. Metin alanına doğrudan gönderilen UI olaylarıyla dar Notes testi 1/1 geçti. Yeni tam UI koşusu 15/16 geçti, 0 test atlandı; Notes testi bu kez uygulama dışındaki macOS “Allow accessory to connect?” USB izin penceresi testin önüne çıktığı için düştü. Ham sonuç `FullUIXcode27-20260917.xcresult` ve hata ekranı `NotesFullUIFailureXcode27` altında korundu. Bu dış pencere kapatılıp tam UI ve birleşik coverage yeniden geçmeden R01/R02 kapanmaz.

Aynı Xcode’da `scripts/run-development-tests.sh` 324/324 unit ve 324/324 kimlik kontrolünü, `scripts/verify-static-quality.sh` statik/yerelleştirme kontrolünü, `scripts/verify-arm64-builds.sh` Debug/Release/CommunityRelease arm64 ve gömülü bileşen kontrollerini, CI ile aynı `xcodebuild ... analyze` komutu analyzer kontrolünü, ayrı ASan/TSan koşuları 323/323 testi, `scripts/verify-release-security.sh` güvenlik kontrolünü ve kritik mutation kapısı 6/6 öldürülen değişikliği geçti. Optimize Release benchmark’ı 100 ölçümle p95 yazma 39,920; okuma 19,129; model 80,576; filtre 9,512; layout 20,640 ms ölçtü ve bütçeyi geçti. Unit sonucu `FullUnitXcode27-20260917.xcresult`; sanitizer ve performans ham sonuçları `.build/ReleaseEvidence` altında saklandı. Bunlar macOS 14/15/26 çalışma zamanı veya imzalı Community aday kabulü değildir.

System Monitor kart/grafik akışı için genişletme kontrolü tam satır tıklanabilen, genişleme durumu erişilebilirlik değerinde görülen bir butona çevrildi. Dar UI akışı ve zengin sensör fixture’ıyla kartların render testi geçti. `FullCoverage-20260917-SystemMonitor` koşusunda 324/324 unit, 16/17 UI geçti; başarısız test Private Mode işlevine ulaşmadan popover açılışında durdu. Bu testin ekran kaydı, Minecraft’ın tam ekran penceresinin test sırasında önde olduğunu gösteriyor. Başarısız koşunun ham kapsamı **yalnız tanısal** olarak birleştirildi: üretim satırlarının %95,16’sı ve her yürütülebilir Swift kaynak dosyasında en az bir satır çalıştı. Tam UI 17/17 olmadan coverage kapısı kabul edilmiş sayılmaz; testler boş masaüstünde yeniden çalıştırılmalıdır.

19 Eylül temiz masaüstü tekrarı `CLIPBOARD_HISTORY_RETAIN_RAW_RESULTS=1 scripts/run-coverage-suite.sh .build/ReleaseEvidence/FullCoverage-20260919` komutuyla aynı commit edilmemiş kaynakta tamamlandı. Unit envanteri **324/324**, UI envanteri **17/17** geçti; atlanan veya başarısız test yok. Birleşik üretim coverage oranı **%95,153** oldu ve her yürütülebilir üretim Swift kaynağında çalıştırılmış satır doğrulandı. `Unit.xcresult`, `UI.xcresult`, iki özet, birleşik report/archive, loglar ve commit/çalışma ağacı/Xcode/OS bilgisini içeren `Environment.json` aynı evidence dizininde korundu. Böylece önceki Notes, USB izin penceresi ve tam ekran uygulama müdahalesiyle başarısız olan koşuların ardından R02’nin yerel tam-koşu kabulü geçti; güncel commit CI koşusu ve kesin imzalı aday kanıtı R01/R05/M6 kapsamında hâlâ açıktır.

19 Eylül M2 macOS 27 beta denemesinde beş zorunlu `MenuBarAgent` öğesinin kararlı AX kimlikleri, boyut/konumları ve `AXShowMenu` action’ları tekrar bulundu. `AXPosition` hiçbirinde yazılabilir değildi; ayrı test host’u bu nedenle Command-drag olaylarını kullandı. Wi-Fi, Bluetooth, Battery, Sound ve Focus için taşıma gözlenen stable-ID sırası ile doğrulandı ve aynı işlemde başlangıç sırası/konumu geri yüklendi. Her öğenin native Control Center penceresi açılıp Escape sonrası kapandı. Wi-Fi `moved` journal’ı bırakıldıktan sonra `MenuBarAgent` PID 663’ten 8880’e yeniden başladı; yeni süreçte journal recovery eski sırayı doğrulayarak tamamladı. Aynı başlıklı iki `NSStatusItem` üreten tek process fixture’ı iki farklı accessibility identifier ile ayrıldı. Raw discovery/activation logları, atomik movement journal’ları, restart kaydı, ortam manifesti ve checksum’lar `.build/ReleaseEvidence/DrawerFeasibility-20260919` altındadır. Bu, yalnız macOS 27 beta kanıtıdır; 14.2+/15/26, izin revoke ve başka manager çakışması hâlâ açıktır.

## 6. 20 Eylül kendi drawer ara teslimi

Kaynak hâlâ `54abfa0` üzerinde commit edilmemiş çalışma ağacıdır. Bu bölüm, önceki 324/17 test ve %95,153 coverage kaydından **sonraki** değişiklikleri izler; önceki sonuç bu kaynağın kabulü değildir. Ortam macOS 27.0 beta (26A428), Xcode 27.0 (27A266a), arm64’tür.

- Kendi modüllerimiz için ayrı drawer status item’ı, ortak controller’ları kullanan yatay görünüm, açma ve menü çubuğuna geri alma uygulandı. System Monitor drawer’a alındığında üst çubuk metrikleri ve buna ait demand kapanır; sırası, formatı ve birleşik/ayrı tercihi korunur. Bu ara teslim; ayrı ayrı metrik ikonlarının drawer düzenlemesini veya harici ikon desteğini tamamlamaz.
- Drawer ve Quick Center karşılıklı dışlanır. Native animasyon korunur; drawer’ın hosting controller’ı tekrar kullanılır ve uygulamanın görünüm tercihini izler. Testte 100 aç/kapat sırasında hosting controller kimliği korundu; bu test tam fiziksel kaynak-sayacı/scroll performans kabulünün yerine geçmez.
- Sürüm 6 → 7 yükseltmesinin birleşik metrik tercihini yanlışlıkla sıfırlaması ve drawer’daki bir modülün yeniden sabitlenememesi regresyon testlerinde önce başarısız oldu, düzeltmeden sonra geçti. Drawer görünürlük seçeneğini kapatmak önceki hidden/whenActive/always tercihini korur; açık “Restore to Menu Bar” eylemi hidden öğeyi görünür yapar.
- Kendi feature yerleşimleri mevcut sürümlü menü çubuğu ayarlarıyla saklanır. Harici drawer için planlanan ayrı sürümlü domain/journal/adaptör üretimde henüz yoktur. M2 kanıtı tamamlanmadan dış ikon entegrasyonu kabul edilmez.
- Test çalıştırıcısı sıfır test, atlanmış/başarısız/beklenen hatalı veya eksik sonuçları reddeder. Kaynak manifesti her dosyanın SHA-256 değerini tutar; aynı commit’teki farklı kirli içerikler ayırt edilir. arm64 derleme logları ve sonuçları başarısızlıkta da korunup CI artifact’ine eklenir.

| Kart / R-ID | Sorumlu | Bağımlılık | Çıktı ve kabul testi | Kanıt | Durum |
|---|---|---|---|---|---|
| M4.1 / R04,R07,R08 | Geliştirici/ajan | M2/M3 tam kabulü açık | Kendi drawer’ı, sürüm 6 metrik migration regresyonu, hidden/conditional tercih korunması, System Monitor restore, sunum kimliği ve 100 döngü | `.build/ReleaseEvidence/OwnDrawer-20260920`: BeforeFix, Configuration (21/21), MenuBar (16/16) log/xcresult; Environment.json | Doğrulanıyor |
| M1.4 / R01,R02,R05,R06 | Geliştirici/ajan | M0/M1 | Eksik test özeti ve derleme kanıtı negatif senaryoları; kaynak hash’i değişiklik kontrolü | `Tests/Scripts/test_development_test_summary.sh`, `test_arm64_failure_artifacts.sh`; Python 8/8, browser 2/2, coverage/merge/performance negatif kontrolleri, statik ve güvenlik geçti | Doğrulanıyor |
| M2.1 / R04,R09 | Geliştirici + fiziksel test sorumlusu | M1 | Beş öğede alan boşaltma, hedef native panel doğrulaması, güvenli restore/recovery; 14.2/15/26 izin ve çakışma matrisi | Önceki beta OS swap deneyi yalnız sıralamayı kanıtlar. `Experiments/DrawerFeasibility/README.md` eksik yetenekleri açıklar | Engelli |

`FullCoverage-20260920-OwnDrawer` koşusunda **331/331 unit** geçti. UI ilk Settings testinde `settings.subsection.inputKeyboardCleaning` satırına erişim assertion’ına ulaştıktan sonra XCTest hata symbolication’ında takıldı; süreç örnekleri `OwnDrawer-20260920/UIRunnerSample.txt` ve `UIHostSample.txt` altında korundu. Uygulamanın ana iş parçacığı normal AppKit olay döngüsündeydi. Takılan test koşusu kesildi; UI xcresult bunu `Testing was canceled` olarak kaydetti. Bu başarısız koşu coverage kabulü değildir; nedenin dar testte yeniden incelenmesi ve tam koşunun geçmesi gerekir.

Yayın kararı **hazır değil**: M2’nin alan boşaltan tam harici drawer zinciri, desteklenen fiziksel OS matrisi, M3 veri/hata enjeksiyonu kabulü, M4’ün kalan UX akışları, M5 üretim entegrasyonu, M6 kullanıcı/performans/soak kabulü ve M7 kesin paket/kurulum-yükseltme provası açıktır. Bu kayıt bunları yalnız belge veya mock ile tamamlandı saymaz.


## 7. 20 Eylül son doğrulama ve kurtarma güvenliği

Bu kayıt aynı `54abfa0` üzerindeki kirli çalışma ağacına aittir. Kanıtlar tek bir final aday kabulü olarak birleştirilmez. Dosya hash manifestleri koşular arasındaki değişiklikleri ayırt eder.

| Kontrol | Gözlenen sonuç | Kanıt ve sınır |
|---|---|---|
| Son tam unit | **331/331 geçti**, her test kimliği doğrulandı; runtime warning listesi boş. | `FullCoverage-20260920-DrawerFinal/Unit.xcresult`, `UnitSummary.json`. Üretim ve unit kaynakları bu koşudan sonra değiştirilmedi; sonraki değişiklikler deney, otomasyon ve belgededir. |
| UI hata incelemesi | `VerifiedDrawer` koşusu 15/18 geçti; kalan üç hata kaydırma yardımcısının yanlış yönü/yetersiz görünürlük denetimiydi. Yardımcı iki yönü ve kontrolün çerçeve içine girmesini denetleyecek şekilde düzeltildi. Drawer taşı/geri al ve Settings erişim dar testleri ayrı ayrı 1/1 geçti. | `OwnDrawer-20260920/DrawerUI-Retry.log`, `SettingsUI-Retry.log`; önceki başarısız `FullCoverage-20260920-VerifiedDrawer/UI.xcresult` korundu. |
| Son tam UI ve coverage | **Engelli:** UI runner hiçbir uygulama testini başlatamadan `Authentication canceled. Canceled by user.` hatası verdi. Unit başarısı tam coverage kabulü değildir. | `FullCoverage-20260920-DrawerFinal/UI.xcresult`, `UISummary.json`, `UI.log`. macOS doğrulaması tamamlanarak 18 UI testinin ve birleşik coverage kapısının yeniden geçmesi gerekir. |
| Test kaynak sahipliği | PasteStack fixture'ı DB açıkken klasörünü silmeyi bıraktı; shutdown tamamlanması ve izole defaults temizliği teardown'da doğrulanıyor. Sabit yield döngüsü yerine yayınlanan sonuca bağlı beklenti kullanılıyor. | Dar PasteStack 2/2 ve yukarıdaki 331/331 tam unit geçti. |
| Önceki 20 Eylül geniş kapılar | arm64 Debug/Release/CommunityRelease, analyzer, ASan 330/330, TSan 330/330 ve 6/6 kritik mutation geçti. Release p95: yazma 32,207; okuma 17,380; model 73,719; filtre 9,126; layout 16,921 ms. | `arm64-builds.ayNBX3`, `analyzer.YcHkpY`, `sanitizers.amwrkD`, `mutations.uiZm5E`, `performance.gUynR2`. Bunlar son preset/fixture düzeltmesinden öncedir; kesin adayın kanıtı değildir. |
| Güncel otomasyon | Statik/yerelleştirme, güvenlik, browser **2/2**, Python **11/11**, bütün shell negatif regresyonları ve YAML/shell sözdizimi kontrolleri geçti. | `.build/ReleaseEvidence/DrawerRecovery-20260920` altındaki loglar. CI'ya gönderilmedi. |

XCTest'in önceki hata raporlama takılması, Desktop altındaki derleme nesnelerine erişirken TCC engeline girmesiyle eşleşti. Coverage, sanitizer, performance ve mutation geçici derleme dizinleri `/private/tmp` altına taşındı; kalıcı kanıt dizini ayrı kaldı. Test host'una Desktop izni verilmedi. macOS kimlik doğrulaması iptali ise ayrı ve hâlâ açık bir ortam engelidir.

Minimal/Balanced preset'leri artık drawer ikonunu da açıkça kapatır; iki ikonlu varsayılan düzen kendisini yanlışlıkla Minimal olarak tanımlamaz. Bu davranış son 331/331 unit koşusundadır.

Harici hareket deneyi güvenliği:

- Aynı kullanıcıdaki deney süreçleri tek OS kilidiyle sıraya alınır; mevcut journal üzerine yeni deney yazılmaz. Başka menü yöneticilerinin eşzamanlı müdahalesi ayrıca fiziksel kabul gerektirir.
- Kurtarma; sürüm/OS, benzersiz ve izin verilen kimlikler, komşuluk, bütün sıra ve geometriyi denetler. Sadece başlangıç düzeni veya tam beklenen takas kabul edilir. Ekran/öğe değişimi ve ilgisiz yeniden sıralama giriş göndermeden durur.
- Taşıma sonrası `moved` kaydı yazılmadan çökme, diskte `prepared` bırakabilir. Bu durumda yalnız gözlenen tam takas geri alınabilir; kısmi veya belirsiz hareket otomatik tekrarlanmaz.
- Journal okuyucu symlink, normal dosya olmayan yol, boş/1 MiB üstü dosya ve bozuk JSON'u reddeder. Mouse-up dahil bütün sürükleme olayları mouse-down öncesi ayrılır; sürükleme sırasında izin yeniden kontrol edilir. OS izin iptalinde mouse-up'ı reddedebileceğinden fiziksel kontrol kaybı kabulü açık kalır.
- **38 sentetik kontrol** ve Swift 6 warnings-as-errors derlemesi geçti; ani süreç çıkışı sonrası OS kilidinin serbest kalması da sınandı. Bu oturumda gerçek sistem ikonlarına input gönderilmedi. Deneyler üretim target'ına dahil edilmedi.

| Kart / R-ID | Sorumlu | Bağımlılık | Çıktı / kabul testi | Kanıt | Durum |
|---|---|---|---|---|---|
| M1.5 / R01,R05,R06 | Geliştirici/ajan | M1 | Başarısız sonuçta özet/raw log saklama; bozuk bundle export hatasını görünür tutma | `test_coverage_failure_artifacts.sh`, `DrawerRecovery-20260920/script-regressions.log` | Tamamlandı |
| M2.2 / R04,R09 | Geliştirici/ajan + fiziksel test sorumlusu | M2.1 | Journal doğrulaması, çökme durumu ve çakışma kilidi; native restore ayrıca zorunlu | `MovementJournal.swift`, `MovementJournalLock.swift`, 38 sentetik kontrol; native tekrar yapılmadı | Doğrulanıyor |
| M1.6 / R01,R02 | Geliştirici/ajan + test sorumlusu | macOS test kimlik doğrulaması | Güncel 331 unit + 18 UI ve birleşik ≥%95 coverage | Son unit başarılı; UI başlangıcı iptal edildi | Engelli |

Son karar **yayına hazır değil**. Tam harici drawer üretim adaptörü ve alan boşaltma davranışı tamamlanmadı; desteklenen OS/izin/çakışma matrisi, kalan M3–M5 ürün kapsamı, kullanıcı kabulü, sekiz saat soak ve aynı imzalı paket üzerinde kurulum/yükseltme provası hâlâ zorunludur.

## 8. 21 Eylül beta.6 yayın kapsamı ve güncel karar

Yayın sahibi 21 Eylül 2026'da fiziksel OS matrisi, beş kullanıcılı görev kabulü, sekiz saatlik soak ve ayrı imza kabulünü beta.6 yayın kapısından açıkça çıkardı. Bu karar geçmiş sonuçları başarılıya çevirmiyor; beta.6'nın **prerelease** kapsamını daraltıyor. Desteklenen macOS sürümlerinde alan boşaltma ve güvenli restore davranışı fiziksel olarak kanıtlanmadığı için harici sistem/üçüncü taraf menü çubuğu yönetimi bu sürümde etkinleştirilmedi ve tam drawer desteği iddia edilmiyor. Kendi CoreDeck modüllerinin drawer yerleşimi kullanılabilir durumdadır.

Güncel kirli kaynak manifestinde otomatik kabul sonuçları:

- Unit test envanteri **346/346 geçti**; atlanan veya eksik kimlik yok.
- Browser native-messaging testleri **2/2**, kanıt/otomasyon Python testleri **14/14** ve drawer hareket-journal sentetik kontrolleri **38/38** geçti.
- Statik kalite/yerelleştirme, release güvenliği, analyzer, Debug/Release/CommunityRelease arm64 derlemeleri, ayrı ASan/TSan, kritik mutation **6/6** ve optimize Release performans bütçeleri geçti.
- Son UI koşusu test başlamadan macOS'un kilitli oturum kimlik doğrulamasında `Authentication canceled` ile durdu; **0 UI testi** çalıştı. Bu koşu başarılı sayılmadı.
- Unit-only üretim coverage oranı **%93,729** oldu. Her yürütülebilir üretim Swift kaynağı için çalıştırılmış satır veya içerik hash'ine bağlı denetimli bildirim/protokol muafiyeti vardı; UI çalışmadığı için birleşik **%95** kapısı yerelde yeniden doğrulanamadı.
- Fiziksel macOS 14.2/15/26 matrisi, gerçek izin ret/revoke matrisi, beş kullanıcı çalışması ve sekiz saat soak yayın sahibinin kararıyla beta.6 için **çalıştırılmadı**.

Beta.6 yayın kararı: açık veri kaybı, yanlış hedefe işlem veya kontrol kaybı kusuru bulunmayan; kendi modül drawer'ı, Quick Center, Quick Note ve tek sidebar Settings penceresini içeren Community **prerelease** yayımlanabilir. Bu karar yalnız beta.6'nın belgelenmiş dar kapsamı içindir. Harici drawer adaptörü etkinleştirilmeden, CI sonuçları ve yayımlanan ZIP/Cask checksum eşliği ayrıca doğrulanacaktır.
