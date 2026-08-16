# ClipboardHistory Top Bar ve Settings Denetimi

**Tarih:** 2026-08-16

**İncelenen commit:** `ea7063366362bc0bc910e995c0ac83e2bccbf43c`

**Kapsam:** Control Center, bağımsız `NSStatusItem` öğeleri, metric status item'ları, sağ tık menüleri, popover/detachable panel, Settings yönlendirmesi ve feature-specific ayarlar.

**Durum:** Bu belge `ea7063366362bc0bc910e995c0ac83e2bccbf43c` tabanındaki bulguları korur. Beta.4 çalışma ağacında aşağıdaki maddeler giderildi veya daraltıldı; çözülmeyen maddeler takip listesi olarak geçerlidir.

### Bu çalışma ağacında kapananlar

- **TS-01:** Application Lock ürün kapsamından tamamen çıkarıldı; bulgu artık güncel davranışa uygulanmıyor.
- **TS-02:** Storage içindeki Clear History onayı aynı Settings yüzeyine taşındı ve modal etkileşim popover'ı kapatmıyor.
- **TS-04, TS-06, TS-08:** System Monitor ve Audio Settings gerçek controller'ları gözlemliyor; seçili ayar bölümü metinle görünüyor; Audio extension sonucu Settings içinde gösteriliyor.
- **TM-01:** Sağ tık kaynağı aktif anchor olarak korunuyor; ortak komutlar tıklanan status item altında açılıyor.
- **TM-02:** Separate metric modunda etkisiz sıra düğmeleri artık gösterilmiyor.
- **TM-03:** Metric seçimleri grup görünürlüğünden bağımsız; boş grup açıldığında CPU güvenli varsayılan olarak ekleniyor.
- **TM-04, TM-06:** Stil adları gerçek render davranışıyla eşleşiyor; birleşik icon modu simge taşıyor; metrik öğeleri monospaced digit ve sabit hesaplanan genişlik kullanıyor.
- **TS-03:** Bütün feature gear ve sağ tık Settings hedefleri ilgili üst seviye bölüme gidiyor.
- **TS-05:** App-wide General, Menu Bar, Clipboard, Notes, Input Tools, System Monitor ve Audio Mixer üst seviyede ayrıldı.
- Settings'in iki yatay rafı yalnız simge gösteriyor; adlar tooltip ve erişilebilirlik etiketi olarak korunuyor.
- Clipboard başlığında Private Mode ve geçmiş temizleme işlemleri doğrudan ikonlarla erişilebilir; retention cleanup, yaşa göre silme ve Clear All aynı güvenli controller akışlarını kullanıyor.
- CPU Usage içindeki çekirdek bazlı liste ve buna ait gereksiz per-core Mach örneklemesi ürün kapsamından çıkarıldı.

## Yönetici özeti

Mevcut `FeatureRegistry` / `MenuBarConfiguration` / paylaşılan controller mimarisi korunmaya değer. Sorun, bu mimarinin Settings'e tamamlanmamış bağlanması ve status-item presentation katmanında tıklama kaynağı, sıra ve görünür state'in kaybedilmesi.

Doğrulanan sonuç:

- 1 release-blocker güvenlik/interaction açığı
- 9 yüksek önemde işlevsel veya güvenilirlik hatası
- 12 orta önemde UI, lifecycle veya mimari kapsam açığı

En önemli kök nedenler:

1. Settings hâlâ `ClipboardHistoryViewModel` merkezli bir façade; diğer feature controller'ları tam olarak gözlemlenmiyor.
2. Settings route yalnız `.settings`; hangi modülden ve hangi bölüme girildiği taşınmıyor.
3. Sağ tık menüsü tıklanan `MenuBarItemID` bilgisini selector aksiyonlarına taşımıyor.
4. Metric configuration modeli sıra/stil seçimini saklıyor, fakat status-item renderer bu anlamların bir kısmını uygulamıyor.
5. Application Lock, Settings içindeki Clipboard/Notes interaction aksiyonlarında controller seviyesinde zorlanmıyor.

## Ayar sahipliği haritası

| Alan | Gerçek state sahibi | Settings'teki mevcut erişim | Sorun |
|---|---|---|---|
| App görünümü / panel / Clipboard shortcut | `AppSettings` | `SettingsFeatureModel.settings` üzerinden | App-wide ve Clipboard seçenekleri aynı “General” içinde |
| Clipboard privacy/storage/advanced | `ClipboardHistoryViewModel` | Tam erişim | Settings façade'nin ana omurgası hâlâ Clipboard |
| Menu bar placement/metrics | `ControlCenterModel` | Customization ekranı + eksik System Monitor kopyası | İki farklı ve tutarsız UI |
| System Monitor | `SystemMetricsController` | `SettingsFeatureModel` içinden | Child controller değişimleri gözlemlenmiyor |
| Audio Mixer | `AudioMixerController` | `SettingsFeatureModel` içinden | Child controller değişimleri ve feedback görünmüyor |
| Scroll Reverse | `ScrollReversalController` + `AppSettings` | Feature ekranında | Settings bölümü ve doğru gear route'u yok |
| Keyboard Cleaning | `KeyboardCleaningController` | Feature ekranında | Settings bölümü ve doğru gear route'u yok |
| Notes | `NoteController` | Yok | Modül gear'ı Clipboard ağırlıklı General'a gidiyor |

## P0 — Release blocker

### TS-01 — Application Lock, Settings içindeki export/import/delete etkileşimlerini engellemiyor

**Tür:** Security / privacy / functional
**Etkilenen dosyalar:**

- `ClipboardHistory/Application/Shell/AppShellView.swift:124-128`
- `ClipboardHistory/Features/Settings/Views/ClipboardSettingsStorageView.swift:100-150`
- `ClipboardHistory/Features/Clipboard/ViewModels/ClipboardHistoryPrivacyController.swift:244-269`
- `ClipboardHistory/Features/Clipboard/ViewModels/ClipboardHistoryMutationController.swift:401-435`
- `docs/KNOWN_LIMITATIONS.md:7`

**Kök neden:** `.settings` route'u kilitliyken koşulsuz render ediliyor. Archive export/import ve Clear History controller girişlerinde `isLocked` guard'ı veya yeniden authentication yok. Application Lock dokümantasyonda Clipboard ve Notes aksiyonlarını engelleyen bir interaction boundary olarak tanımlanmasına rağmen Settings bu boundary'nin dışına çıkıyor.

**Yeniden üretim:**

1. Application Lock'u etkinleştirip uygulamayı kilitle.
2. Control Center içinden Settings'i aç.
3. Storage bölümüne git.
4. Unencrypted Export / Merge Import / Clear History aksiyonlarını dene.

**Etki:** Kilitli oturumda Clipboard ve şifresi storage katmanında çözülebilen Notes içeriği unencrypted archive'a çıkarılabilir; import ve silme etkileşimleri de başlatılabilir. Bu, UI lock sözleşmesini bozar.

**Çözüm yönü:** Sadece buton disable etmek yeterli değil. Export/import/clear controller boundary'sinde `isLocked` kontrolü ve gerektiğinde `AppLockService` ile authentication zorlanmalı. UI kilit state'ini açıkça göstermeli.

**Gerekli test:** Locked export/import/clear için controller-level negative-path testleri; UI testinde locked Settings aksiyonlarının unavailable/authenticated olması.

## P1 — Yüksek önem

### TS-02 — Settings'teki Clear History onayı yanlış ekrana bağlı

**Tür:** Functional / navigation
**Etkilenen dosyalar:**

- `ClipboardHistory/Features/Settings/Views/ClipboardSettingsStorageView.swift:100-107`
- `ClipboardHistory/Features/Clipboard/ViewModels/ClipboardHistoryMutationController.swift:401-409`
- `ClipboardHistory/Features/Clipboard/Views/Panel/ClipboardPanelView.swift:58-66`

**Kök neden:** Settings butonu `clearHistory()` çağrısıyla yalnız `isShowingClearConfirmation = true` yapıyor. `confirmationDialog` ise Settings ağacında değil `ClipboardPanelView` üzerinde.

**Kullanıcı davranışı:** Settings'te buton görünürde çalışmaz. Settings kapatılıp Clipboard ekranına dönüldüğünde onay diyaloğu gecikmeli ve bağlam dışı açılır.

**Çözüm yönü:** Confirmation'ı tetikleyen Storage UI'ına taşı veya app-level presentation state kullan. Confirmation sonrası tek yetkili async clear akışına gir.

**Gerekli test:** Settings Storage'dan Clear History tıklanınca aynı ekranda confirmation görünmesi; cancel/confirm ve sonraki navigation state'i.

### TS-03 — Feature gear düğmeleri doğru Settings bölümüne gitmiyor

**Tür:** Navigation / UX
**Etkilenen dosyalar:**

- `ClipboardHistory/Shared/Components/ModuleToolbar.swift:51-57`
- `ClipboardHistory/Application/Shell/AppModel.swift:144-150`
- `ClipboardHistory/Application/Shell/AppRouter.swift:48-57`
- `ClipboardHistory/Features/Settings/Views/ClipboardSettingsView.swift:9-17`

**Kök neden:** Bütün modüller parametresiz `openSettings()` çağırıyor. Router bölüm taşımıyor; Settings view her oluşturulduğunda `.general` ile başlıyor.

**Yeniden üretim:** System Monitor veya Audio Mixer ekranında gear'a bas. İlgili mevcut bölüm yerine Clipboard ağırlıklı General açılır. Notes, Keyboard Cleaning ve Scroll Reverse için gidilecek bir bölüm zaten yoktur.

**Çözüm yönü:** `SettingsRoute` veya `SettingsDestination(feature:section:)` ekle; `openSettings(_:)` çağrısını modül bazlı yap. Back dönüş noktası ile Settings hedefini ayrı state olarak tut.

**Gerekli test:** Her `UtilityFeatureID` için gear → beklenen Settings destination matrisi ve Back dönüşü.

### TS-04 — Settings, System Monitor ve Audio Mixer canlı state'ini gözlemlemiyor

**Tür:** Data flow / stale UI
**Etkilenen dosyalar:**

- `ClipboardHistory/Features/Settings/SettingsFeatureModel.swift:14-31`
- `ClipboardHistory/Features/Settings/Views/SystemMonitorSettingsView.swift:3-57`
- `ClipboardHistory/Features/Settings/Views/AudioMixerSettingsView.swift:3-51`

**Kök neden:** `SettingsFeatureModel` yalnız `clipboard.objectWillChange` yayınını forward ediyor. `controlCenter`, `systemMetrics` ve `audioMixer` child controller'ları için observation yok. İlgili view'lar da child controller'ı doğrudan `@ObservedObject` olarak tutmuyor.

**Etki:** System Monitor temperature/scope ve Audio permission state'i controller değişse bile Settings ekranında stale kalabilir. Metric toggle'larının source-of-truth ile görsel senkronu da garanti değildir.

**Çözüm yönü:** Feature-specific Settings view'larına gerçek controller'ı `@ObservedObject` olarak ver veya façade içinde bütün child `objectWillChange` yayınlarını güvenli biçimde birleştir. Tercih edilen yön, her ekranın yalnız kendi state sahibini gözlemlemesidir.

**Gerekli test:** Açık Settings ekranında yeni metric snapshot, network scope, audio permission ve browser-extension sonucu yayınlandığında UI state'in değişmesi.

### TM-01 — Sağ tık menüsünün ortak komutları tıklanan status item'a anchor olmuyor

**Tür:** Functional / popover placement
**Etkilenen dosyalar:**

- `ClipboardHistory/Services/Presentation/MenuBarController+Actions.swift:63-116`
- `ClipboardHistory/Services/Presentation/MenuBarController+Actions.swift:133-147`

**Kök neden:** `showStatusMenu(for:)` gerçek `itemID`'yi biliyor, fakat `Open Control Center`, `Open Settings`, `Customize Menu Bar` ve `Open System Monitor` selector'ları bu ID'yi taşımıyor; hepsi eski `activeAnchorID` ile açılıyor.

**Yeniden üretim:** Bir status item'dan panel aç, kapat; başka bir status item'a sağ tıkla ve Open Settings/Control Center seç. Popover önceki item altında açılabilir.

**Çözüm yönü:** Menü item'ına `MenuBarItemID` temsilini bağla ve her shared action'da tıklanan item'ı anchor olarak geçir.

**Gerekli test:** İki farklı status item ile right-click source → presented anchor matrisi. Mevcut testler yalnız router destination'ı assert ediyor.

### TM-02 — Separate metric sıralama düğmeleri menu bar sırasını değiştirmiyor

**Tür:** Functional / configuration
**Etkilenen dosyalar:**

- `ClipboardHistory/Application/Shell/ControlCenterModel.swift:105-113`
- `ClipboardHistory/Services/Presentation/MenuBarController+StatusItems.swift:5-17`
- `ClipboardHistory/Services/Presentation/MenuBarController+StatusItems.swift:31-43`

**Kök neden:** `moveMetric` array sırasını değiştiriyor. Renderer ise desired item'ları `Set<MenuBarItemID>` içine çeviriyor ve mevcut `NSStatusItem` kimliklerini koruyor; ayrı item'ların status bar order'ını uygulayan hiçbir adım yok.

**Etki:** Combined modda metin sırası değişir; separate modda UI'daki Move Up/Down komutu görünür sonucu olmayan bir ayardır.

**Çözüm yönü:** Separate-mode order sözleşmesini açıkça tanımla. App-controlled ordering destekleniyorsa deterministik ve identity-safe bir reorder mekanizması kur; yalnız macOS kullanıcı sürüklemesi desteklenecekse Move düğmelerini separate modda gösterme ve bunu açıkça anlat.

**Gerekli test:** Model array'i değil gerçek status-item order adapter'ını assert eden test.

### TM-03 — Bütün metric'ler kapatılınca Customization ekranı kendi kendine kilitleniyor

**Tür:** Functional / recovery dead-end
**Etkilenen dosyalar:**

- `ClipboardHistory/Application/Shell/ControlCenterModel.swift:58-61`
- `ClipboardHistory/Application/Shell/ControlCenterModel.swift:81-95`
- `ClipboardHistory/Features/ControlCenter/MenuBarMetricsConfigurationCard.swift:13-56`

**Kök neden:** Son metric kapatılınca `isVisible = false` oluyor. Metric seçimleri yalnız `isVisible == true` iken render ediliyor. Metrics array boşken Show Live Metrics toggle'ını açmak da `isVisible = isVisible && !metrics.isEmpty` nedeniyle etkisiz.

**Etki:** Kullanıcı Customization ekranından yeniden metric seçemez. Yalnız ayrı System Monitor Settings ekranını keşfederse kurtulabilir.

**Çözüm yönü:** Metric seçimlerini visibility'den bağımsız göster. Show açılırken boş gruba güvenli default eklemek de ikincil seçenek olabilir.

**Gerekli test:** Bütün metric'leri kapat → aynı ekranda bir metric'i yeniden aç → group görünür yap akışı.

### TM-04 — Metric “Value Only” ve “Icon and Value” stilleri sözleşmesini karşılamıyor

**Tür:** Functional / visual semantics
**Etkilenen dosyalar:**

- `ClipboardHistory/Features/SystemMonitor/Models/MenuBarMetricStyle.swift:3-15`
- `ClipboardHistory/Services/Presentation/MenuBarController+StatusItems.swift:157-175`

**Kök neden:** Renderer yalnız `.compact` için value-only metin üretiyor. `.value` etikete rağmen `"Metric Value"` gösteriyor. `.iconAndValue`, yalnız tek metric olduğunda icon ekliyor; combined grupta `.value` ile aynı görünüyor.

**Etki:** Üç seçenekten ikisi isimleriyle uyuşmaz; bazı kombinasyonlar görsel olarak ayırt edilemez.

**Çözüm yönü:** Stil sözleşmesini netleştir ve exhaustive switch ile her case'i ayrı render et. Combined icon politikasını UI'da açıkça sınırla.

**Gerekli test:** Her style × single/combined matrisi için title/symbol snapshot testi.

### TA-01 — Yalnız browser tab'ları varken Mute All geri açılamıyor

**Tür:** Audio semantics / functional
**Etkilenen dosyalar:**

- `ClipboardHistory/Features/AudioMixer/AudioMixerController.swift:75-80`
- `ClipboardHistory/Features/AudioMixer/AudioMixerController.swift:232-252`

**Kök neden:** `isEverythingMuted`, en az bir output-producing application olmasını zorunlu tutuyor. Browser tab'ları mevcut ve app discovery boş olduğunda tab'ların hepsi muted olsa bile sonuç false.

**Yeniden üretim:** Yalnız controllable browser tab varken Mute All'a iki kez bas. İkinci basış Restore yoluna girmek yerine pre-mute gain'i sıfırla tekrar mute eder.

**Çözüm yönü:** Application ve browser domain'lerini ayrı değerlendir; en az bir controllable source varsa bütün mevcut source'ların muted olması restore state'i olmalı. Pre-mute state'i ikinci mute ile overwrite etme.

**Gerekli test:** browser-only, application-only, mixed, empty ve disconnected-source mute/restore matrisi.

### TP-01 — Settings'teki exclusion metni uygulanamayacak mutlak garanti veriyor

**Tür:** Privacy wording / trust
**Etkilenen dosyalar:**

- `ClipboardHistory/Features/Settings/Views/ClipboardSettingsPrivacyView.swift:99-101`
- `docs/ENGINEERING_INVARIANTS.md:50-57`

**Kök neden:** UI “Excluded clipboard content is never read or stored.” diyor. Source app, clipboard değişiminden sonra frontmost app üzerinden çıkarıldığı için “never read” kanıtlanamaz.

**Çözüm yönü:** Metni best-effort attribution sınırına indir; concealed/transient pasteboard marker'larının daha güçlü olduğu durumu açıkla. Davranışı değiştirmeden yalnız claim'i düzeltmek gereklidir.

**Gerekli test:** Metin anahtarının izin verilen daraltılmış wording ile eşleşmesi; source-attribution edge-case testleri.

## P2 — Orta önem

### TS-05 — Settings bilgi mimarisi hâlâ Clipboard tabanlı — Çözüldü

**Tür:** Product architecture / UX
**Etkilenen dosyalar:**

- `ClipboardHistory/Models/ClipboardSettingsSection.swift:3-35`
- `ClipboardHistory/Features/Settings/SettingsFeatureModel.swift:5-40`
- `ClipboardHistory/Features/Settings/Views/ClipboardSettingsGeneralView.swift:14-106`
- `ClipboardHistory/Features/Settings/Views/ClipboardSettingsAdvancedView.swift:12-109`

**Kök neden:** Root tipler ve façade Clipboard'dan büyütülmüş. Yedi bölümün General/Privacy/Security/Storage/Advanced olan beşi ağırlıklı olarak Clipboard; Notes ve Input Tools yok, Menu Bar ayrı ekrana kaçıyor, System/Audio sonradan eklenmiş child controller referansları.

**Görünür sonuçlar:**

- “Global Shortcut” gerçekte Clipboard'ı açıyor ama app-wide gibi adlandırılıyor.
- “General” içinde app appearance/panel/startup ile history/filter/sort birbirine karışıyor.
- Generic “Storage” içindeki archive Clipboard ve Notes içeriyor, Clear History ise yalnız Clipboard semantics'i taşıyor.
- Notes/Input Tools gear'ları kendilerine ait hiçbir ayar gösteremiyor.

**Uygulanan çözüm:** App-wide General ile Menu Bar ayrıldı; Clipboard, Notes, Input Tools, System Monitor ve Audio Mixer kendi controller'larını gözlemleyen bölümlere taşındı. İkinci yatay raf yalnız seçili sahibin alt sayfalarını gösteriyor; Clipboard'ın Privacy/Security/Storage kapsamı Clipboard altında kalıyor, Notes ve Input Tools dişlileri kendi ayarlarına yönleniyor.

### TS-06 — Settings section picker yalnız ikon gösteriyor; görünür bölüm adı yok — Çözüldü

**Tür:** Discoverability / accessibility-adjacent UI
**Etkilenen dosyalar:**

- `ClipboardHistory/Features/Settings/Views/AppSettingsHeaderView.swift`
- `ClipboardHistory/Features/Settings/Views/SettingsNavigationShelf.swift`
- `ClipboardHistory/Features/Settings/Views/SettingsShelfButton.swift`

**Kök neden:** Yedi segmented item yalnız `Image` içeriyor; görünür etiket, tooltip veya seçili bölüm başlığı yok. VoiceOver label'ları var, fakat görsel kullanıcı ikon anlamını tahmin etmek zorunda.

**Uygulanan çözüm:** Çekmece tipi Picker'lar kaldırıldı. Üst yatay raf app-wide ve feature sahiplerini, alt yatay raf seçili sahibin alt bölümlerini yalnız ikon taşıyan butonlarla sunuyor; adlar tooltip ve erişilebilirlik etiketlerinde kalıyor. Raflar dar popover genişliğinde yatay kayıyor, seçili öğeyi merkeze getiriyor ve Reduce Motion ayarına uyuyor. Clipboard'ın General/Privacy/Security/Storage/Advanced seçimi artık üçüncü bir gezinme katmanı oluşturmuyor.

### TS-07 — Detachable panel her feature'da “Clipboard History” başlığını taşıyor

**Tür:** Stale branding / window UI
**Etkilenen dosya:** `ClipboardHistory/Services/Presentation/MenuBarControllerDependencies.swift:47-62`

**Kök neden:** Panel başlığı creation anında sabit atanıyor ve router destination değişiminde güncellenmiyor.

**Etki:** Notes, System Monitor, Audio Mixer, Menu Bar Customization ve Settings açıkken pencere başlığı yanlış.

**Çözüm yönü:** App adı veya aktif feature başlığına bağlı dinamik window title kullan.

### TS-08 — Audio Settings aksiyon sonucu kullanıcıya gösterilmiyor

**Tür:** Feedback / error visibility
**Etkilenen dosyalar:**

- `ClipboardHistory/Features/Settings/Views/AudioMixerSettingsView.swift:16-35`
- `ClipboardHistory/Features/AudioMixer/AudioMixerController.swift:265-280`
- `ClipboardHistory/Features/AudioMixer/Views/AudioMixerView.swift:54-62`

**Kök neden:** Controller `extensionMessage` üretiyor. Audio Mixer feature ekranı bunu alert ile gösteriyor, Settings ekranı göstermiyor; ayrıca TS-04 nedeniyle değişimi gözlemlemiyor.

**Etki:** Prepare Extension / Safari Settings başarı veya hata sonucu Settings'te sessiz kalır.

### TM-05 — Gerçek fallback anchor seçiliyor ama `activeAnchorID` güncellenmiyor

**Tür:** State consistency / multi-item placement
**Etkilenen dosyalar:**

- `ClipboardHistory/Services/Presentation/MenuBarController.swift:237-255`
- `ClipboardHistory/Services/Presentation/MenuBarController+StatusItems.swift:44-50`

**Kök neden:** Control Center item gizliyken `showControlCenter()` hâlâ `.controlCenter` active ID'sini atar; renderer başka bir button'a fallback eder fakat state'i gerçek anchor'a düzeltmez. Active anchor kaldırıldığında da `Dictionary.keys.first` ile deterministik olmayan seçim yapılır.

**Etki:** Reopen, reanchor, detachable screen seçimi ve ortak right-click action'ları yanlış/random item veya ana ekrana bağlanabilir.

**Çözüm yönü:** Anchor resolution tek fonksiyonda deterministik olsun ve resolved ID + view birlikte dönsün.

### TM-06 — Metric metni proportional digit nedeniyle menu bar genişliğini oynatıyor

**Tür:** Visual stability / performance
**Etkilenen dosya:** `ClipboardHistory/Services/Presentation/MenuBarController+StatusItems.swift:190-212`

**Kök neden:** Numeric title doğrudan `NSStatusBarButton.title` olarak atanıyor; monospaced-digit attributed title/font uygulanmıyor. Variable-length item her değer değişiminde farklı genişliğe kayabilir.

**Etki:** CPU/rate değerleri değişirken komşu menu bar öğeleri yatay olarak titreşebilir. Proje performans planı numeric topbar için monospaced digit öngörüyor.

**Çözüm yönü:** Native menü-bar görünümünü bozmadan monospaced-digit feature'lı system font ile attributed title kullan ve width jitter'ı ölç.

### TM-07 — Control Center, System Monitor kartı gizliyken de metric sampling başlatıyor

**Tür:** Battery / unnecessary producer demand
**Etkilenen dosya:** `ClipboardHistory/Features/ControlCenter/ControlCenterView.swift:52-61`

**Kök neden:** Audio demand card visibility ile koşullu; System Metrics demand ise Control Center açıldığında her zaman active.

**Etki:** Kullanıcı System Monitor'u Control Center'dan gizlemiş olsa bile popover açıkken 5 saniyelik sampling sürer.

**Çözüm yönü:** `.controlCenter` demand'ını gerçekten görünür System Monitor consumer'ına bağla.

### TM-08 — Outside-click event monitor'ları ilk açılıştan sonra sürekli bağlı kalıyor

**Tür:** Lifecycle / wakeup overhead
**Etkilenen dosyalar:**

- `ClipboardHistory/Services/Presentation/MenuBarController.swift:301-304`
- `ClipboardHistory/Services/Presentation/PanelCloseCoordinator.swift:39-100`

**Kök neden:** Coordinator `popoverWillShow` içinde start ediliyor; `popoverDidClose` içinde stop edilmiyor. Yalnız controller shutdown'da kaldırılıyor.

**Etki:** Popover kapalıyken de global/local mouse monitor callback'leri uygulama ömrü boyunca event alır ve guard'dan döner.

**Çözüm yönü:** Popover lifecycle ile monitor lifecycle'ını eşle; detachable panel davranışını ayrı tanımla. Instruments/Energy Log ile wakeup farkını ölç.

### TA-02 — Audio status icon browser-tab değişimlerini dinlemiyor

**Tür:** Stale top-bar state
**Etkilenen dosyalar:**

- `ClipboardHistory/Services/Presentation/MenuBarController.swift:134-135`
- `ClipboardHistory/Services/Presentation/MenuBarController+StatusItems.swift:130-135`

**Kök neden:** MenuBarController yalnız `$applications` publisher'ına abone. `isEverythingMuted` browser tabs'e de bağlı olmasına rağmen `$browserTabs` değişimi status icon update'i tetiklemiyor.

**Etki:** Browser mute/restore veya bridge state değişiminden sonra Audio Mixer icon'u eski kalabilir.

**Çözüm yönü:** Render edilen state'in bütün gerçek dependency publisher'larını birleştir veya controller'da ayrı presentation-state publisher üret.

### TM-09 — System Monitor için anlamsız duplicate kontroller gösteriliyor

**Tür:** UI clutter / duplicate action
**Etkilenen dosyalar:**

- `ClipboardHistory/Application/Shell/FeatureRegistry.swift:51-57`
- `ClipboardHistory/Features/ControlCenter/MenuBarFeatureConfigurationCard.swift:18-23`
- `ClipboardHistory/Services/Presentation/MenuBarController+Actions.swift:72-90`

**Kök neden:** System Monitor yalnız `.open` destekliyor; buna rağmen tek seçenekli Left Click picker gösteriliyor ve right-click menüde hem Open Module hem Open System Monitor ekleniyor.

**Çözüm yönü:** Picker'ı yalnız birden çok click action varsa göster. Quick-action satırını yalnız non-open action varsa ekle.

### TM-10 — Bozuk preference içindeki duplicate feature ID uygulamayı açılışta düşürebilir

**Tür:** Resilience / configuration
**Etkilenen dosya:** `ClipboardHistory/Application/Shell/MenuBarConfigurationStore.swift:29-50`

**Kök neden:** `Dictionary(uniqueKeysWithValues:)`, decode edilmiş `features` içinde duplicate ID varsa precondition failure üretir. Decode başarısızlığı defaults'a düşüyor, fakat semantik olarak geçerli JSON içindeki duplicate ID bu guard'ı geçer.

**Çözüm yönü:** Duplicate'ları deterministik first/last-wins politikasıyla normalize et, diagnostic kaydet ve erişilebilir default status item invariant'ını uygula.

**Gerekli test:** Duplicate/unknown/missing feature içeren semantik olarak bozuk configuration corpus'u.

### TS-09 — İlgisiz app/input ayarı değişiklikleri Clipboard refresh zincirine giriyor

**Tür:** Cross-feature coupling / unnecessary work
**Etkilenen dosyalar:**

- `ClipboardHistory/Features/Clipboard/ViewModels/ClipboardHistoryCaptureController.swift:13-20`
- `ClipboardHistory/Features/Clipboard/ViewModels/ClipboardHistoryPrivacyController.swift:137-163`
- `ClipboardHistory/Features/Settings/ViewModels/AppSettings.swift:5-43`

**Kök neden:** Tek `AppSettings.objectWillChange` sink'i appearance, panel edge veya scroll reversal dahil her değişiklikte Clipboard `settingsDidChange()` çağırıyor; bu da list filtering, pasteboard type ve lock configuration işini yeniden yapıyor.

**Etki:** Settings'in Clipboard'dan büyümüş olması runtime coupling'e dönüşüyor. Şu an maintenance snapshot guard'ı ağır cleanup'ı sınırlıyor, fakat ilgisiz refresh ve notification zinciri devam ediyor.

**Çözüm yönü:** App-wide, Clipboard ve Input Tools preferences yayınlarını alan bazlı ayır veya typed preference snapshot diff uygula.

## Test kapsamı boşlukları

Mevcut testlerin güçlü tarafı configuration persistence, status-item kimliğinin korunması, temel route'lar ve rendering smoke kapsamıdır. Aşağıdaki davranışlar doğrulanmıyor:

1. Right-click'i açan gerçek status item ile popover anchor eşitliği.
2. Separate metric order'ın gerçek status bar order'a uygulanması.
3. Empty metric group'tan aynı Customization UI içinde kurtulma.
4. Metric style × combined/separate render matrisi.
5. Browser-only Audio Mixer mute/restore.
6. Browser tab publisher değişiminde status icon güncellemesi.
7. Açık Settings'te live System/Audio child-controller update'i.
8. Her feature gear'ının doğru Settings bölümüne gitmesi.
9. Settings Storage Clear History confirmation'ın aynı ekranda görünmesi.
10. Locked Settings export/import/delete negative path'leri.
11. Corrupt/duplicate menu-bar configuration normalization.
12. VoiceOver, keyboard focus, 200% scaling, notch ve multi-display fiziksel kabulü.

## Önerilen uygulama sırası

1. **Lock boundary ve Clear History presentation:** TS-01, TS-02.
2. **Settings route ve state sahipliği:** TS-03, TS-04, TS-05, TS-08.
3. **Metric configuration doğruluğu:** TM-02, TM-03, TM-04, TM-05.
4. **Anchor ve status presentation:** TM-01, TM-06, TA-02.
5. **Audio semantics:** TA-01 ve browser/runtime acceptance.
6. **Lifecycle/performance:** TM-07, TM-08, TS-09; ardından Instruments/Energy Log.
7. **UI polish ve resilience:** TS-06, TS-07, TM-09, TM-10, TP-01.

## Korunması gereken doğru kararlar

- Status item topology değişmediğinde mevcut `NSStatusItem` kimlikleri korunuyor.
- System Monitor tek merkezi producer ve demand modelini kullanıyor; yeni timer-per-widget eklenmemeli.
- Feature, Control Center ve standalone placement birbirinden bağımsız modellenmiş.
- Popover native animasyonu korunuyor ve content önceden hazırlanıyor.
- Reduce Motion ve Reduce Transparency ortam ayarları ana shell/settings geçişlerinde dikkate alınıyor.
- String Catalog'daki mevcut 530 anahtarın Türkçe translation state'i dolu.

## SwiftUI düzeltme eskizleri

Bu örnekler nihai patch değil; ilgili UI sorunlarının önerilen state/data-flow yönünü gösterir.

### `AppSettingsHeaderView.swift`

Uygulanan iki raflı yapı üst seviyede `AppSettingsSection`, alt seviyede seçili sahibin `AppSettingsSubsection` değerlerini görünür metin ve SF Symbol içeren yatay butonlar olarak sunuyor. Dar popover genişliğinde her raf bağımsız kaydırılıyor; seçili durum yalnız renkle değil dolgu ve VoiceOver `isSelected` trait'iyle de belirtiliyor.

### `SystemMonitorSettingsView.swift`

**Önce — child controller gözlemlenmeden façade içinden okunuyor:**

```swift
@ObservedObject var viewModel: SettingsFeatureModel

Text(viewModel.systemMetrics.snapshot.primaryTemperature?.formatted() ?? "Unavailable")
```

**Sonra — ekran gerçek state sahibini gözlemliyor:**

```swift
@ObservedObject var controller: SystemMetricsController
@ObservedObject var menuBar: ControlCenterModel

Text(controller.snapshot.primaryTemperature?.formatted() ?? "Unavailable")
```

### `MenuBarMetricsConfigurationCard.swift`

**Önce — group gizlenince metric recovery kontrolleri de kayboluyor:**

```swift
if model.configuration.metricGroup.isVisible {
    ForEach(MenuBarMetricID.allCases) { metric in
        Toggle(metric.title, isOn: metricBinding(metric))
    }
}
```

**Sonra — seçim visibility'den bağımsız kalıyor:**

```swift
if model.configuration.metricGroup.isVisible {
    metricPresentationControls
}

ForEach(MenuBarMetricID.allCases) { metric in
    Toggle(metric.title, isOn: metricBinding(metric))
}
```

### `AudioMixerSettingsView.swift`

**Önce — controller feedback'i gözlemlenmiyor ve gösterilmiyor:**

```swift
@ObservedObject var viewModel: SettingsFeatureModel
```

**Sonra — Audio state doğrudan gözlemlenip sonuç görünür yapılıyor:**

```swift
@ObservedObject var controller: AudioMixerController

.alert(
    "Browser Extension",
    isPresented: Binding(
        get: { controller.extensionMessage != nil },
        set: { if !$0 { controller.extensionMessage = nil } }
    )
) { } message: {
    Text(controller.extensionMessage ?? "")
}
```

## Bu denetimde yapılan doğrulamalar ve sınırlar

- `git status`: başlangıçta temiz ve `main...origin/main` eşitti.
- Xcode 27.0 (`27A5237l`) ile `scripts/run-development-tests.sh`: 292/292 birim testi geçti.
- Gerçek status item kullanan `ClipboardHistoryUITests`: 10/10 geçti.
- UI testleri her açılışta popover merkezini ana status-item merkeziyle ve popover üst kenarını ikonun alt kenarıyla karşılaştırıyor.
- `MenuBarControllerTests`: 6/6 geçti; anchor view/rect/edge ve gecikmeli reanchor retry yolu kapsandı.
- `scripts/verify-static-quality.sh` geçti.
- `scripts/verify-localizations.sh` geçti; İngilizce kaynak ve Türkçe çeviriler eksiksiz.
- Canlı Accessibility ölçümünde ana ikon `x=1410...1434`, popover `x=1219...1625`; iki merkezin de `x=1422` olduğu doğrulandı.
- Notch ve ikinci fiziksel ekran üzerinde manuel doğrulama yapılmadı.
