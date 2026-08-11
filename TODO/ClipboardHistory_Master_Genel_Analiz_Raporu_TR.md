# ClipboardHistory — Master Genel Analiz, Risk ve Geliştirme Raporu

**Repository:** `BGirginn/ClipboardHistory`  
**İncelenen branch:** `main`  
**İncelenen commit:** `3c2a2f583cd3deb0b5009cf33c76cc8ef9a5c13b` (`3c2a2f5`)  
**İnceleme tarihi:** 2026-08-10  
**Durum:** Public Community beta (`v1.0.0-beta.2`), arm64, macOS 14.2+  
**Kapsam:** kaynak kodun tamamı, testler, Xcode proje metadata’sı, App/Shell, Clipboard, Notes, Input Tools, System Monitor, Audio Mixer, browser extension’ları, login item, storage, crypto, migrations, export/import, menu bar/panel katmanı, release/quality scriptleri, dokümantasyon ve kaynak bütünlüğü.

---

# 1. Yönetici özeti

[Kesin] Proje artık bir “clipboard history uygulaması” değil; **yerel çalışan, modüler bir macOS menu-bar utility hub**. Mevcut mimari; merkezi Control Center, bağımsız menu-bar modülleri, Clipboard, Notes, Input Tools, System Monitor ve Audio Mixer özelliklerini tek process/composition root altında yönetiyor.

[Kesin] Kod tabanının genel mühendislik seviyesi güçlü. Özellikle şu kararlar doğru:

- `AppModel` tek composition root.
- Feature’lar compile-time registry ile ayrıştırılmış.
- Clipboard storage katmanı actor üzerinden serialize ediliyor.
- SQLite WAL + transactional mutation kullanılıyor.
- History ve Notes ayrı Keychain anahtarlarına sahip.
- AES-GCM kullanılıyor ve gerekli key erişilemediğinde plaintext fallback yapılmıyor.
- Archive import/export doğrulama, staging, hash ve boyut/adet limitleri içeriyor.
- System Monitor aynı metriği her UI için ayrı ayrı okumuyor; merkezi demand-driven sampling kullanıyor.
- Menu-bar placement modeli “Control Center / standalone / ikisi birden” ürün vizyonunu gerçekten karşılıyor.
- Swift 6 concurrency, test doubles, failure injection, sanitizer/fuzz/mutation/performance yaklaşımı mevcut.
- Production Swift dosyaları için 500 satır ve tek top-level type gate’i bakım yapılabilirliği destekliyor.

[Kesin] Buna rağmen **stable/production release için hazır değil**. Sebep mimarinin zayıf olması değil; privacy-sensitive operasyonların birkaçında transaction/invariant sınırlarının yanlış kurulmuş olması. En ciddi alanlar:

1. `Clear History` + encryption-key rotation tutarlılığı.
2. Delete/Clear işlemlerinin storage başarısızlığında UI’de başarı gibi görünmesi.
3. Eski plaintext backup retention.
4. “All Items” encryption migration’ın fail-open davranabilmesi.
5. Sensitive content UI leak’i.
6. Secret detector kapsam boşlukları.
7. File metadata’nın encryption beklentisiyle uyuşmaması.
8. Storage quota temizliğinin yanlış byte muhasebesi.
9. Rich-text edit/paste veri tutarsızlığı.
10. Yeni Audio Mixer’daki gerçek CoreAudio scalar-property okuma yolunda yüksek olasılıklı ABI/storage hatası.

**Nihai karar:**  
[Kesin] **Rewrite gerekmiyor.** P0/P1 privacy-storage hataları düzeltilip gerçek Mac üzerinde regresyon/sanitizer/manual acceptance tamamlanmalı. Sonrasında mevcut mimari güvenle genişletilebilir.

---

# 2. İnceleme kapsamı ve doğrulanan kaynak bütünlüğü

## 2.1 Repo envanteri

[Kesin] İncelenen snapshot:

- **407 dosya**
- **57 klasör**
- yaklaşık **1.55 MB source/resources**
- **397 text dosyası / 38.717 satır**
- **340 Swift dosyası / yaklaşık 29 bin Swift satırı**
- production Swift: yaklaşık 17.5–17.7 bin satır
- 52 Swift test dosyası
- 1 Objective-C `.m`
- 2 C/Objective-C header
- 5 JavaScript
- 16 Zsh script
- 7 JSON
- Xcode `project.pbxproj`, scheme, plist, entitlements, xcstrings, YAML, Markdown ve asset’ler
- 10 PNG asset

## 2.2 Syntax / parse / byte-level sonuçları

[Kesin]

- 340/340 Swift dosyası Swift 6 parser’dan geçti.
- 5/5 JavaScript dosyası syntax kontrolünden geçti.
- JSON, plist, entitlements, xcstrings, Xcode scheme ve YAML parse edildi.
- Text dosyalarında bozuk UTF-8, NUL/control byte, BOM, CRLF, trailing whitespace ve missing final newline problemi bulunmadı.
- PNG asset bütünlüğü doğrulandı.
- Repo içinde `TODO`, `FIXME`, `HACK`, `XXX` işaretleri bulunmuyor.

## 2.3 Bu incelemenin sınırı

[Kesin] İnceleme ortamı Linux olduğu için aşağıdakiler burada gerçek runtime ile çalıştırılamadı:

- `xcodebuild`
- AppKit runtime
- CoreAudio process-tap runtime
- IOKit / SMC / HID runtime
- Accessibility event taps
- Safari Web Extension runtime
- LocalAuthentication
- Instruments / Energy Log / Leaks
- gerçek macOS UI automation

Bu nedenle kaynak düzeyinde kesin olan bulgular `[Kesin]`; yalnız macOS ABI/runtime davranışıyla son doğrulaması gerekenler `[Muhtemel]` olarak ayrılmıştır.

---

# 3. Ürün vizyonu ve mevcut konum

## 3.1 Ürün bugün ne?

Mevcut repository’nin fiili ürünü:

```text
ClipboardHistory
└── Native macOS Utility Hub
    ├── Control Center
    ├── Clipboard
    ├── Notes
    ├── Input Tools
    │   ├── Keyboard Cleaning
    │   └── Scroll Reverse
    ├── System Monitor
    ├── Audio Mixer
    ├── Menu Bar Customization
    └── Settings / Privacy / Security
```

## 3.2 Ana ürün prensibi

Kullanıcı bir feature için:

- yalnız Control Center’da gösterebilir,
- bağımsız menu-bar item olarak gösterebilir,
- her ikisinde gösterebilir,
- gizleyebilir.

Ana Control Center ikonu da bağımsız olarak açılıp kapatılabilir; sistem son erişilebilir giriş noktasını koruma mantığına sahip.

[Kesin] Bu ürün vizyonu mevcut `FeatureRegistry`, `FeaturePlacement`, `MenuBarConfiguration`, `ControlCenterModel` ve `MenuBarController` ile yalnız tasarım seviyesinde değil, implementasyon seviyesinde vardır.

## 3.3 Hedef vizyondan henüz eksik olan büyük parça

[Kesin] Mevcut app **kendi** status item’larını yönetiyor. Ancak gelecekte planlanan:

- diğer uygulamaların menu-bar ikonlarını gizleme/gruplama,
- sistem menu-bar öğelerini mümkün olduğu ölçüde çatı altında toplama,
- Bartender/Ice benzeri yabancı status-item management,

henüz implement edilmiş değildir.

Bu özellik mevcut `MenuBarController` içine rastgele eklenmemeli; ayrı bir `ExternalMenuBarManagement` subsystem olarak tasarlanmalıdır.

---

# 4. Ana mimari ve çalışma mantığı

## 4.1 Composition root

```text
ClipboardHistoryAppDelegate
          │
          ▼
       AppModel
          │
 ┌────────┼────────┬──────────┬───────────┬────────────┐
 ▼        ▼        ▼          ▼           ▼            ▼
Clipboard Notes InputTools SystemMetrics AudioMixer ControlCenter
          │
          └──────────── shared services / settings / router
```

`AppModel` aşağıdaki shared model/controller’ları bir kez oluşturuyor:

- `ClipboardHistoryViewModel`
- `NoteController`
- `InputToolsController`
- `SystemMetricsController`
- `AudioMixerController`
- `ControlCenterModel`
- `SettingsFeatureModel`
- `AppRouter`
- `AppSettings`
- `AppLockService`

Bu yapı Control Center ve standalone panel’ların aynı state’i görmesi açısından doğru bir **Single Source of Truth** yaklaşımıdır.

## 4.2 Feature registry

Compile-time feature listesi:

```text
clipboard
notes
keyboardCleaning
scrollReverse
systemMonitor
audioMixer
```

Her feature:

- title,
- summary,
- SF Symbol,
- desteklenen click action,
- default click action

ile tanımlanır.

[Kesin] Runtime plugin sistemi yok; feature’lar first-party static modüller. Mevcut ürün ölçeğinde bu **doğru tercih**. Şimdilik plugin architecture eklemek gereksiz karmaşıklık yaratır.

## 4.3 Router

`AppRouter` aktif ekranı ve Settings dönüş noktasını yönetir. Normal Finder açılışı Control Center’a gider; clipboard shortcut doğrudan Clipboard’a yönlenir.

## 4.4 Menu bar

```text
MenuBarConfigurationStore
          │
          ▼
ControlCenterModel
          │
          ▼
MenuBarController
          │
 ┌────────┼────────────┐
 ▼        ▼            ▼
Control  Feature      Metric
Center   StatusItems  StatusItems
```

Status item lifecycle AppKit tarafında tutuluyor; UI state ve configuration SwiftUI/Combine tarafında.

## 4.5 Panel/presentation

Tek shared popover/panel mantığı ve outside-click coordination kullanılıyor. `PanelCloseCoordinator`, context menu tracking sırasında panelin yanlışlıkla kapanmasını engellemek için ayrı sınır oluşturuyor.

---

# 5. Clipboard modülü — çalışma mantığı

## 5.1 Capture flow

```text
NSPasteboard.changeCount
        │
        ▼
ClipboardMonitor
        │
        ├── transient/concealed/generated filter
        ├── source/exclusion best-effort check
        ├── pause/private/lock policy
        ▼
ClipboardHistoryCaptureController
        │
        ├── content analysis
        ├── secret detection
        ├── metadata
        ├── image/PDF/file/rich payload extraction
        ▼
StorageService
        │
        ├── SQLite metadata/text
        └── managed asset files
```

## 5.2 Paste/restore flow

Kullanıcı geçmişten öğe seçtiğinde:

1. `ClipboardPasteboardWriter` item representation’ını NSPasteboard’a yazar.
2. Direct paste istenirse Accessibility backend aktif uygulamaya Cmd+V benzeri paste uygular.
3. Restore/copy/paste paths pasteboard identity ile yeni clipboard içeriğinin yanlışlıkla silinmesini engellemeye çalışır.

## 5.3 Clipboard model decomposition

`ClipboardHistoryViewModel` facade olarak kalmış; sorumluluklar ayrı extension/controller dosyalarına bölünmüş:

- capture
- mutation
- privacy
- interaction
- presentation
- archive
- monitor delegate

[Kesin] Bu bölünme iyi; ViewModel’i tekrar tek dev sınıfa birleştirmek yanlış olur.

---

# 6. Storage ve encryption mimarisi

## 6.1 Storage

```text
StorageService (actor)
     │
     ├── SQLiteClipboardRepository
     ├── SQLiteNoteRepository
     ├── ClipboardAssetStore
     ├── StorageSchemaMigrationService
     ├── StorageMaintenanceService
     ├── StorageRecoveryImportService
     └── Encryption rotation/recovery facets
```

SQLite:

- WAL
- FULLMUTEX
- transaction boundaries
- schema migrations
- integrity/recovery paths

kullanıyor.

## 6.2 Encryption

- AES-GCM
- login Keychain-backed history key
- ayrı Notes key
- key failure’da plaintext fallback yok
- görünür/private metadata’nın bir bölümü encrypted BLOB olarak tutuluyor

[Kesin] History ve Notes anahtarlarının ayrılması doğru. Clear History’nin history key’ini rotate etmesi Notes’u bozmamalı.

## 6.3 Asset model

Images, thumbnails, rich payloads vb. Application Support altında managed dosyalara ayrılıyor. Path traversal’a karşı managed filename doğrulaması var.

---

# 7. Notes modülü

[Kesin] Notes ayrı domain olarak doğru ayrılmış.

Önemli doğru kararlar:

- ayrı encryption key,
- encrypted title/body,
- revision-aware save,
- serialized/debounced save,
- list/editor state’in merkezi controller’da olması,
- shutdown/navigation öncesi pending save flush.

Notes tarafı genel olarak Clipboard’a kıyasla daha temiz privacy invariant’lara sahip.

---

# 8. Input Tools

## 8.1 Shared Event Tap

Keyboard Cleaning ve Scroll Reverse ayrı ayrı event tap açmak yerine ortak `SystemInputEventTapCoordinator` kullanıyor.

Bu:

- daha az sistem kaynağı,
- permission lifecycle’ın tek yerde yönetilmesi,
- birbiriyle çakışan event tap riskinin düşürülmesi

açısından doğru.

## 8.2 Keyboard Cleaning

- keyboard/media event’lerini discard eder,
- mouse/scroll açık kalır,
- maksimum 60 saniye safety timeout,
- lock/sleep/termination paths stop eder.

## 8.3 Scroll Reverse

- line/pixel based deltas üzerinde çalışır,
- vertical/horizontal ayrı ayarlanabilir,
- permission yoksa native input bozulmaz.

[Kesin] Burada “fail-open” doğru davranıştır; input tool failure kullanıcının Mac’ini kilitlememeli.

---

# 9. System Monitor

## 9.1 Veri kaynakları

Mevcut provider aşağıdaki sınıfları bir snapshot’a birleştiriyor:

- Mach CPU ticks
- VM/memory statistics
- network counters
- IOKit storage counters
- Apple SMC / Apple Silicon HID temperature
- ProcessInfo thermal state

## 9.2 Demand-driven sampling

```text
Consumers
 ├── Detail view       1 s
 ├── Menu-bar metrics  2 s
 └── Control Center    5 s
          │
          ▼
SystemMetricsController
          │
          ▼
Single SystemMetricsProvider sample
```

[Kesin] Birden fazla consumer varsa ayrı timer/provider oluşturulmuyor. En hızlı aktif demand interval’ı seçiliyor.

Bu konuştuğumuz enerji-verimli mimarinin önemli bölümünü zaten karşılıyor.

## 9.3 History

- yalnız memory’de
- yaklaşık 15 dakikalık time-bounded history
- default maximum 900 sample
- SQLite’a persist edilmiyor

## 9.4 Güçlü taraf

[Kesin] System Monitor’ın temel problemi “aynı sensörü 5 kez okuma” değil. Bu zaten çözülmüş.

## 9.5 Geliştirme gereken taraf

Mevcut model sabit üç sampling tier kullanıyor. Gelecekte:

- battery-aware interval,
- app inactive/locked/screen asleep durumu,
- metric-specific cost,
- user-selected refresh rate,
- threshold alert,
- rendering coalescing,
- düşük güç modu,
- external power durumu

ile daha akıllı hale getirilebilir.

---

# 10. Audio Mixer

## 10.1 Application audio

macOS 14.2+ Core Audio process APIs üzerinden uygulamalar discover ediliyor. Gain 100’den düşük olduğunda private process-tap pipeline devreye giriyor; native audio path gereksiz yere sürekli tap’lenmiyor.

Bu performans açısından doğru tasarım.

## 10.2 Browser tabs

### Chromium

- bundled extension
- user action ile tab capture
- native messaging
- local bridge

### Safari

- Safari Web Extension
- doğrudan kontrol edilebilen HTML media element’leri
- DRM/WebAudio/protected page gibi alanlarda sınırlı

Browser tab state memory-only tutuluyor.

## 10.3 Audio tarafının olgunluk durumu

[Kesin] Audio Mixer yeni ve project risk profilini belirgin artırmış durumda. CoreAudio, browser extension, native messaging ve device switching gerçek donanım kabul testine ihtiyaç duyuyor.

---

# 11. Güçlü yönler

## 11.1 Mimari

**Güçlü:**

- composition root net,
- shared state duplication düşük,
- feature boundaries belirgin,
- storage actor isolation,
- system interfaces injectable,
- presentation/platform sınırları ayrılmış,
- first-party static module yaklaşımı sade.

## 11.2 Güvenlik

**Güçlü:**

- local-only tasarım,
- telemetry/account/cloud yok,
- AES-GCM,
- Keychain keys,
- plaintext fallback yok,
- Notes/history ayrı keys,
- archive authentication + hashes,
- path/count/size validation,
- App Lock security boundary olarak encryption’dan ayrı tanımlanmış.

## 11.3 Privacy

**Güçlü:**

- system metrics persist edilmiyor,
- audio samples persist edilmiyor,
- browser tab metadata memory-only,
- incognito default reject,
- clipboard transient/concealed marker’lara dikkat ediliyor,
- input content loglanmıyor.

## 11.4 Performans

**Güçlü:**

- System Metrics demand-driven,
- process audio pipeline yalnız gerektiğinde,
- SQLite batch/transaction yaklaşımı,
- 15 dakika bounded metric history,
- lazy SwiftUI stack kullanımları,
- published benchmark thresholds mevcut.

## 11.5 Test/quality yaklaşımı

**Güçlü:**

- unit/integration tests,
- UI tests,
- ASan,
- TSan,
- fuzz,
- mutation tests,
- performance benchmark,
- line coverage gate,
- source structure/static quality gate,
- arm64 verification,
- SBOM/signing/checksum tooling.

[Kesin] Bu kadar küçük bir public macOS utility repo için test/release disiplininin seviyesi ortalamanın üstünde.

---

# 12. P0 — Release blocker riskler

Aşağıdaki maddeler düzeltilmeden stable release önermiyorum.

## P0-1 — Clear History collection encryption invariant’ını bozuyor

**Seviye:** CRITICAL  
**Güven:** [Kesin]

`StorageService.clearAll()` clipboard item’larını temizledikten sonra history encryption key’ini rotate ediyor; collection kayıtları aynı şekilde ortadan kaldırılmıyor/yeniden şifrelenmiyor.

### Etki

Eski key ile encrypted collection name yeni key ile decrypt edilemez. Sonraki history load storage failure’a dönebilir.

### Risk

- kullanıcı kendi “Clear History” işlemiyle storage’ı kullanılamaz hale getirebilir,
- hata yanlış biçimde Keychain problemi gibi gösterilebilir,
- clipboard monitoring durabilir.

### Çözüm

En temiz semantics:

1. item’ları sil,
2. collection’ları sil,
3. managed clipboard assets/backups policy’ye göre temizle,
4. transaction başarılıysa key rotate et,
5. memory state’i commit et.

Mutlaka `clear -> reopen -> collections load` regresyon testi eklenmeli.

---

## P0-2 — Delete/Clear fail-open

**Seviye:** HIGH / Release blocker  
**Güven:** [Kesin]

UI state storage operation tamamlanmadan temizleniyor; bazı destructive storage metodları hatayı yalnız loglayıp `Void` döndürüyor.

### Etki

Kullanıcı item’ı silmiş görür; SQLite delete başarısız olmuş olabilir. Restart sonrası item geri gelebilir.

### Privacy etkisi

“Delete” privacy-sensitive bir operasyon olduğu için success görünümü yalnız storage commit sonrası verilmelidir.

### Çözüm

- destructive APIs `throws` veya typed result,
- DB commit first,
- UI state commit second,
- error banner/dialog,
- retry/rollback semantics.

---

## P0-3 — Clear History backup retention

**Seviye:** HIGH  
**Güven:** [Kesin]

Legacy/migration/recovery backup’ları `Backups/` altında kalabiliyor. Eski `history.json` plaintext clipboard içeriği barındırabilir.

### Etki

Kullanıcı “history temizlendi” zannederken geçmiş içerik backup dosyasında kalabilir.

### Çözüm seçenekleri

Tercihen:

- backup’ları encrypt et,
- retention policy tanımla,
- storage usage’a dahil et,
- Clear History ekranında semantics’i açık hale getir,
- full erase seçeneği backup’ları da silsin.

---

## P0-4 — “All Items” encryption migration fail-open

**Seviye:** HIGH  
**Güven:** [Kesin]

Yeni encryption mode state’i migration tamamlanmadan applied kabul ediliyor; migration’ın bazı failure path’leri yalnız loglanıyor.

### Etki

UI “All Items encrypted” gösterirken eski bazı öğeler plaintext kalabilir.

### Çözüm

Migration’ı state machine yap:

```text
requested
  ↓
migrating
  ↓
verify assets + DB
  ↓
commit mode
  ↓
completed
```

Failure’da `failed/retryable` state gösterilmeli.

---

## P0-5 — Sensitive item detail leak

**Seviye:** HIGH privacy  
**Güven:** [Kesin]

Sensitive item preview gizleniyor ancak detail/editor yüzeyi gerçek text/title/tag/OCR/QR içeriğini gösterebiliyor.

### Etki

“Sensitive Content / preview hidden” davranışı kullanıcı beklentisini karşılamıyor.

### Çözüm

Sensitive state için detail editor ayrı policy’den geçmeli:

- default redacted,
- explicit “Reveal” action,
- App Lock/unlock policy,
- reveal timeout,
- OCR/QR metadata da aynı policy.

---

## P0-6 — Secret detector PKCS#8 private key boşluğu

**Seviye:** HIGH  
**Güven:** [Kesin]

Standart:

- `BEGIN PRIVATE KEY`
- `BEGIN ENCRYPTED PRIVATE KEY`

formatları mevcut detector kapsamından kaçabiliyor.

### Etki

Private key sıradan clipboard item olarak kalıcı yazılabilir.

### Çözüm

PEM family detection genişletilmeli; fixtures/test corpus:

- PKCS#1 RSA
- PKCS#8
- encrypted PKCS#8
- EC private key
- OpenSSH
- PGP private blocks

ile tamamlanmalı.

---

## P0-7 — Encrypted file item metadata plaintext kalıyor

**Seviye:** HIGH privacy expectation  
**Güven:** [Kesin]

Absolute paths ve bookmark BLOB’ları DB’de encryption mode’dan bağımsız görünür metadata bırakabiliyor.

### Etki

İçerik encrypted olsa dahi:

```text
/Users/.../Project-X/Client-Y/...
```

gibi path bilgisi hassas olabilir.

### Çözüm

- path/bookmark için protected metadata envelope,
- searchable/public metadata ile private metadata ayrımı,
- threat model/UI açıklamasını gerçek davranışla eşleştirme.

---

## P0-8 — Storage quota delete muhasebesi

**Seviye:** HIGH data-loss  
**Güven:** [Kesin]

Storage usage DB boyutunu sayarken cleanup item başına DB/text byte azalmasını doğru modellemiyor.

### Etki

Quota SQLite/text nedeniyle aşıldığında gereğinden çok — potansiyel olarak bütün unpinned history — silme listesine girebilir.

### Çözüm

Quota modelini iki aşamalı yap:

1. asset reclaim tahmini,
2. row/text DB reclaim tahmini veya batch delete + yeniden ölçüm.

Blind decrement yerine gerçek storage re-measure kullanılmalı.

---

## P0-9 — Rich-text edit/original paste stale payload

**Seviye:** HIGH data correctness  
**Güven:** [Kesin]

Rich-text item’ın görünen text’i edit edildiğinde eski RTF/HTML payload kalabiliyor. “Paste as Original” eski payload’ı yazabilir.

### Etki

Kullanıcı düzenlediği yeni text yerine eski içerik yapıştırabilir.

### Çözüm

Edit semantics net olmalı:

- rich payload invalidate,
- veya payload regenerate,
- veya item plain text’e downgrade.

Original representation’ın stale olmasına izin verilmemeli.

---

## P0-10 — CoreAudio generic scalar storage bug riski

**Seviye:** HIGH audio runtime  
**Güven:** [Muhtemel – yüksek]

`CoreAudioProcessDiscovery.scalarProperty<Value>` içinde CoreAudio `Value` boyutu kadar veri yazarken hedef storage `Optional<Value>` olarak oluşturuluyor.

### Neden riskli?

`Optional<T>` bellek temsili `T` ile her durumda aynı olmak zorunda değildir. C API yalnız `MemoryLayout<Value>.size` byte yazarken Optional discriminator/tag eski `nil` durumunda kalabilir.

### Olası etki

- PID discovery başarısız,
- `isRunningOutput` yanlış,
- audio app listesi boş/yanlış,
- fiziksel runtime’da unit testlerin yakalamadığı sorun.

### Çözüm

```swift
var value = Value.initializedZeroValue
```

gibi gerçek `Value` storage kullanılmalı veya her scalar type için typed helper yazılmalı.

Son doğrulama gerçek macOS CoreAudio runtime testidir.

---

# 13. P1 — Yüksek/orta riskli düzeltmeler

## P1-1 — Excluded application guarantee gerçekte best-effort

**Güven:** [Kesin]

Clipboard source attribution poll anındaki `frontmostApplication` üzerinden yapılıyor. Bu, clipboard’ı gerçekten yazan process’in güvenilir kimliği değildir.

### Risk

Password manager’dan copy → hızlı app switch senaryosunda exclusion atlanabilir.

### Yapılması gereken

- UI’daki “never read or stored” iddiasını kaldır,
- transient/concealed marker’ları önceliklendir,
- app exclusion’ı “best effort” olarak tanımla,
- secret detector ikinci savunma hattı olsun.

---

## P1-2 — Live capture payload limitleri

Clipboard’a çok büyük image/PDF/RTF/file listesi konması memory/disk baskısı yaratabilir.

### TODO

- max text bytes,
- max image pixel count,
- max decoded image memory,
- max PDF bytes/pages gerekirse,
- max file URL count,
- max rich-text payload,
- user-facing rejection reason.

---

## P1-3 — HTML sanitizer regex tabanlı

Regex temelli sanitization aktif scheme/resource varyasyonlarını kaçırabilir.

### Çözüm

HTML execute edilmese bile:

- URL scheme allowlist,
- DOM/NSAttributedString safe parsing boundary,
- `javascript:`, `data:`, remote resource behavior,
- malicious fixture fuzz tests

ile güçlendirilmeli.

---

## P1-4 — Quick Look plaintext temporary file

Encrypted asset Quick Look için plaintext temp materialize ediliyor.

### Risk

Crash/kill sonrası orphan temp dosya kalabilir.

### Çözüm

- dedicated temp root,
- restrictive permissions,
- startup orphan cleanup,
- lifecycle token,
- shorter exposure window.

---

## P1-5 — SQLite `textContent` index

Tam text/BLOB üzerinde kullanılmayan index DB boyutunu ve write cost’u artırabilir.

### TODO

`EXPLAIN QUERY PLAN` ile gerçekten kullanılıp kullanılmadığını ölç; gereksizse migration ile kaldır.

---

## P1-6 — Chromium browser tab namespace collision

Birden fazla Chromium-family browser aynı tab id alanını paylaşabilir.

### Çözüm

Identity:

```text
browserBundleID + profile/session + tabID
```

veya bridge-specific unique ID olmalı.

---

## P1-7 — Browser bridge sender authentication

DistributedNotificationCenter/local IPC mesajında sender’ın yalnız schema doğrulaması yeterli değil.

### Çözüm

- capability/token veya process identity doğrulaması,
- bounded message size,
- allowlisted message types,
- replay/state validation.

---

## P1-8 — Safari mixer webpage state mutation

Safari gain/mute kontrolü sayfadaki media element’in kendi volume/mute state’ini değiştirip sonra restore etmeye çalışıyor.

### Risk

Page script aynı state’i değiştirirse kullanıcı state’i üzerine yazılabilir.

### Çözüm

Ownership/version token; yalnız app’in yaptığı mutation restore edilmeli.

---

## P1-9 — Recovery rollback failure swallow

Recovery import başarısız olduğunda rollback move da başarısız olabilir; ikinci failure bazı yollarda swallow ediliyor.

### Risk

UI “previous database unchanged” diyebilir fakat filesystem tam restore olmamış olabilir.

### Çözüm

Recovery result:

```text
success
failedAndRolledBack
failedRollbackIncomplete
```

şeklinde açık olmalı.

---

## P1-10 — “Inactivity lock” gerçek input inactivity değil

Mevcut semantics app interaction/activity’yi user inactivity olarak yorumlayabiliyor.

### Çözüm

Ya isim değiştir:

- “Lock after app inactivity”

ya da gerçekten CGEvent/source/System idle time ile kullanıcı inactivity ölç.

---

## P1-11 — Encryption asset migration staging tam transactional değil

Asset rewrite orta noktada fail ederse mixed filesystem state doğabilir.

### Çözüm

```text
new encrypted assets -> staging
verify
DB transaction
atomic swap
remove old assets
```

---

## P1-12 — Merge import collection mutation order

Collection state item importundan önce kalıcı mutate olabiliyor.

### Risk

Item import fail ederken collection side effect kalabilir.

### Çözüm

Import plan önce memory’de oluşturulmalı, transaction içinde tek commit yapılmalı.

---

## P1-13 — Rejected import orphan asset

Materialized asset item daha sonra rejected olursa dosya orphan kalabilir.

### Çözüm

Import staging root + accepted-manifest finalize; rejected asset finalize edilmemeli.

---

## P1-14 — Rich-text capture payload failure semantics

Payload storage başarısız olsa bile item `.richText` kalabiliyor.

### Çözüm

Payload yoksa content type plain text’e downgrade edilmeli veya item reject edilmeli.

---

## P1-15 — Legacy JSON migration sensitive guard bypass

Legacy history migration güncel sensitive-storage policy’nin tüm korumalarını uygulamayabilir.

### Çözüm

Migration path’leri current normalization/privacy pipeline ile aynı invariant’ları paylaşmalı.

---

# 14. P2 — Hardening / bakım / düşük önem

## P2-1 — PBKDF2 embedded NUL

Password C-string tabanlı aktarılıyorsa embedded `\0` password truncate edebilir.

**Çözüm:** explicit bytes + length API.

## P2-2 — Generic randomData zero-count

`baseAddress!` gibi varsayım zero-count generic çağrıda güvenli değil.

**Çözüm:** `count == 0` early return veya optional pointer handling.

## P2-3 — Static quality gate ordinary force unwrap kapsamı

Mevcut gate bazı force unwrap pattern’larını kaçırabilir.

**Çözüm:** SwiftSyntax tabanlı AST lint veya SwiftLint custom rule.

## P2-4 — Encrypted image Reveal in Finder UX

Finder’da kullanıcı gerçek görsel yerine `.enc` managed blob görebilir.

**Çözüm:** “Reveal encrypted storage file” olarak adlandır veya temp decrypted export gerektiriyorsa explicit action yap.

## P2-5 — Her settings mutation ağır maintenance chain

Bazı unrelated setting değişikliklerinde privacy/storage maintenance yeniden tetiklenebilir.

**Çözüm:** settings diff’i alan bazlı yap; yalnız ilgili maintenance çalışsın.

## P2-6 — Audio gain restore error swallow

Subsequent gain restore hataları log seviyesinde kaybolabiliyor.

**Çözüm:** user-visible degraded state + retry.

## P2-7 — Xcode legacy file reference metadata

File-system-synchronized groups’a geçilmesine rağmen project metadata’da eski reference/buildfile kayıtları kalmış.

**Çözüm:** Xcode project cleanup; target membership ve duplicate build input kontrolü.

## P2-8 — Localization stale helper entries

String Catalog ile yardımcı localization data arasında stale/extra entry olabilir.

**Çözüm:** tek source of truth ve CI diff gate.

## P2-9 — Beta readiness dokümanı beta.1’de kalmış

README/release state beta.2 iken `BETA_READINESS_REPORT.md` hâlâ beta.1 candidate/evidence anlatıyor.

**Çözüm:** release evidence dokümanlarını immutable versioned yap veya beta.2 report ekle.

## P2-10 — Threat model archive-encryption ifadesi

Bazı dokümantasyon ifadeleri archive protection semantics’ini gereğinden geniş anlatıyor.

**Çözüm:** exact encrypted/not-encrypted metadata sınırını tabloyla yaz.

---

# 15. Performans ve pil raporu

## 15.1 Bugünkü güçlü durum

[Kesin] Proje performans tarafında plansız değil:

- System Monitor demand-driven.
- No consumer → sampling task yok.
- Detail/MenuBar/ControlCenter farklı cadence.
- Metric history bounded.
- Audio tap yalnız <100% gain ihtiyacında.
- Background metric persistence yok.
- published optimized benchmark mevcut.
- short idle smoke ölçümünde dokümante edilen CPU/RSS sonuçları iyi.

## 15.2 En önemli eksik: bütün app için ortak Resource Lifecycle policy

Her feature kendi lifecycle’ını iyi yönetmeye çalışıyor ancak bunu ürün çapında formalize eden tek bir `ResourcePolicy/ModuleLifecycleCoordinator` henüz yok.

### Önerilen katman

```text
ModuleLifecycleCoordinator
    │
    ├── appVisible
    ├── controlCenterVisible
    ├── standaloneItemVisible
    ├── screenLocked
    ├── displayAsleep
    ├── battery / AC
    ├── lowPowerMode
    └── featureEnabled
           │
           ▼
   desired resource mode
      stopped / idle / live
```

Bu özellikle System Monitor, Audio Mixer ve gelecekte External Menu Bar Manager için faydalı olur.

## 15.3 Sampling için önerilen ileri model

Mevcut sabit:

```text
Detail        1 s
MenuBar       2 s
ControlCenter 5 s
```

iyi başlangıçtır.

Gelecekte:

```text
samplingInterval = f(
  fastestVisibleConsumer,
  metricCost,
  batteryState,
  lowPowerMode,
  thermalState,
  userPreference
)
```

olabilir.

### Ancak önemli sınır

[Kesin] “Zero polling” hedefi gerçekçi değildir. CPU/network/disk/temperature ve `NSPasteboard.changeCount` gibi alanlarda uygun interval ile polling normaldir. Hedef **minimum wake-up ve duplicate read** olmalıdır.

## 15.4 UI rendering

Topbar için planlanan numeric-only model performans açısından doğru:

- `.monospacedDigit()`
- yalnız text/SF Symbol
- metric değişmediyse status item redraw yok
- format template bir kez tokenize edilir
- her tick regex parse edilmez

## 15.5 Ölçülmesi gereken budget

Stable release öncesi feature başına enerji budget önerisi:

- idle, hiçbir metric görünmüyor
- clipboard capture only
- combined metric status item
- 7 independent metric items
- Audio Mixer idle
- Audio Mixer 1 active pipeline
- browser tab control
- Scroll Reverse active
- Keyboard Cleaning active
- Control Center open

Her senaryo için:

- average CPU
- wakeups/sec
- Energy Impact
- RSS
- dirty memory
- I/O bytes
- timer count

kaydedilmeli.

---

# 16. Güvenlik ve privacy risk modeli

## 16.1 Güven sınırı

App’in korumaya çalıştığı:

- persisted clipboard history,
- persisted notes,
- managed payloads,
- local archive,
- UI visibility.

Koruyamayacağı:

- live system clipboard’ı başka privileged process’in okuması,
- compromised logged-in account,
- APFS snapshot/SSD physical erase,
- source file silinmesi,
- heuristic detector’ın %100 başarısı.

Bu boundary dokümantasyonda genel olarak doğru tanımlanmış.

## 16.2 En önemli privacy prensibi

Privacy UI metni implementasyon guarantee’sinden daha güçlü olmamalı.

Özellikle şu ifadeler audit edilmeli:

- “never read”
- “never stored”
- “all items encrypted”
- “history cleared”
- “previous database unchanged”

Bu tip absolute claim’ler ancak invariant test’i varsa kullanılmalı.

## 16.3 Encryption semantics

Settings ekranında kullanıcıya üç ayrı kavram açık ayrılmalı:

1. **at-rest encryption**
2. **application lock**
3. **sensitive-item temporary handling**

Bunlar birbirinin yerine geçmez.

---

# 17. Menu Bar / Control Center değerlendirmesi

## 17.1 Mevcut model güçlü

`MenuBarConfiguration`:

- versioned,
- Control Center visibility,
- feature placement,
- click actions,
- system metric group

tutuyor.

Bu gelecekte migration açısından doğru.

## 17.2 Korunması gereken karar

Status item’ları her value update’inde destroy/recreate etmemek; persistent status item’ın text/image content’ini update etmek gerekir.

Lifecycle recreate yalnız configuration topology değiştiğinde yapılmalı.

## 17.3 Gelecek numeric metrics customization

Önerilen model:

```text
MenuBarMetricWidgetConfiguration
├── enabled
├── metric IDs
├── order
├── formatTemplate
├── symbolMode
├── precision
├── unitStyle
├── thresholds
├── colorPolicy
└── refreshPolicy
```

Format template örneği:

```text
{cpu}% · {temp:0}°C
RAM {memory}%
↓{net.down} ↑{net.up}
```

Template setting değiştiğinde tokenize/compile edilmeli; sample tick’inde yalnız lightweight render yapılmalı.

## 17.4 Notch/overflow

Apple’ın başka menu-bar item’ları için resmi bir “overflow management API” vermemesi nedeniyle iki ayrı ürün katmanı düşünülmeli:

### Katman A — tamamen güvenilir

Kendi feature/metric status item’larımızı:

- combine,
- hide,
- prioritize,
- group,
- compact

etmek.

### Katman B — best-effort / permission dependent

External menu-bar management.

Bu özellik başarısız olduğunda uygulamanın kendi utility hub fonksiyonları etkilenmemeli.

---

# 18. External Menu Bar Manager — gelecek subsystem önerisi

Bu gelecekte eklenirse ayrı module boundary:

```text
ExternalMenuBarManager
├── MenuBarItemDiscovery
├── AXPermissionController
├── ExternalItemIdentityStore
├── VisibilityPolicy
├── ProxyActionController
├── RuleEngine
└── Recovery/FailSafe
```

## Gereken güvenlik prensipleri

- Accessibility izni yalnız feature açılırken istenmeli.
- App açılışında gereksiz permission prompt yok.
- Uygulama crash olduğunda yabancı ikonlar kalıcı olarak erişilemez hale gelmemeli.
- “Restore all menu bar items” emergency action olmalı.
- macOS update sonrası private/undocumented davranış kırılırsa fail-safe disable.
- Apple sistem item’ları için destek matrisi açıkça tutulmalı.

## Mimari kural

Bu sistem `MenuBarController` ile aynı class’a konmamalı. Kendi app status item lifecycle’ı ile external AX manipulation ayrı risk domain’leridir.

---

# 19. Test ve kalite değerlendirmesi

## 19.1 Güçlü taraf

Repository dokümantasyonuna göre mevcut quality matrix:

- unit/integration,
- UI automation,
- fuzz,
- coverage,
- performance,
- ASan,
- TSan,
- mutation,
- architecture/static checks,
- signing/artifact checks

içeriyor.

## 19.2 Kritik gözlem

[Kesin] **100% line coverage davranışsal correctness garantisi değildir.** Bulunan P0 hataların bir bölümü kodun test edilmiş satırlarında bulunmasına rağmen invariant’ın kendisi test edilmediği için kaçmıştır.

### Eksik invariant testleri

Mutlaka eklenmesi gerekenler:

- Clear History → reopen → no decrypt error.
- Clear History → collections semantics.
- Clear History → backup policy.
- delete failure → UI item hâlâ görünür.
- clear failure → UI state rollback.
- All Items encryption partial asset failure → mode commit edilmez.
- PKCS#8 detector fixtures.
- rich-text edit → original paste consistency.
- quota DB-heavy history.
- Quick Look crash/startup orphan cleanup.
- recovery rollback second failure.
- import rejection → no orphan asset.
- CoreAudio scalar property gerçek C API integration test.
- multiple Chromium browser namespace.

## 19.3 Release validation eksikleri

Mevcut docs da kabul ediyor:

- macOS 14/15 exact matrix tam değil,
- multi-display/manual UI matrix eksik,
- VoiceOver/high contrast/reduced motion/transparency eksik,
- Instruments eksik,
- eight-hour soak eksik,
- real physical audio/device switching acceptance eksik,
- sensor value ikinci güvenilir tool ile cross-check eksik.

Stable `1.0.0` için bunlar kapatılmalı.

---

# 20. Dokümantasyon değerlendirmesi

## İyi

- Architecture açık.
- Threat model var.
- Known limitations dürüst.
- Testing/performance thresholds yazılı.
- Distribution/signing akışı açıklanmış.
- İngilizce/Türkçe README var.

## Eksik

- Beta readiness beta.1’de kalmış, current beta beta.2.
- Bazı privacy ifadeleri implementasyondan güçlü.
- Feature-specific privacy tables daha açık olabilir.
- External Menu Bar Manager henüz plan dokümanında formal subsystem değil.
- System Monitor refresh/power policy ürün requirement olarak yazılı değil.

---

# 21. Teknik borç değerlendirmesi

[Kesin] Teknik borç “spaghetti architecture” türünde değil. Daha çok dört kategoride:

### 1. Privacy invariant debt

Delete, clear, encryption migration, backup retention.

### 2. Platform integration debt

CoreAudio, Safari/Chromium, SMC/HID, Accessibility gerçek hardware acceptance.

### 3. Release evidence debt

Beta.2 exact matrix, Instruments, soak, OS matrix.

### 4. Product evolution debt

Menu-bar manager, richer metric configuration, lifecycle/power coordinator.

---

# 22. Ne yeniden yazılmamalı?

Aşağıdaki yapıları sırf “daha modern olsun” diye değiştirmeyi önermiyorum:

- `StorageService` actor → korunmalı.
- SQLite → CoreData/SwiftData’ya geçirmenin somut getirisi yok.
- `AppModel` composition root → korunmalı.
- Compile-time `FeatureRegistry` → mevcut ölçek için korunmalı.
- SystemMetrics demand model → genişletilmeli, atılmamalı.
- shared Input Event Tap → korunmalı.
- AES-GCM + separate keys → korunmalı.
- static feature ownership → şimdilik runtime plugin’e çevrilmemeli.
- Clipboard `changeCount` polling → “polling kötü” gerekçesiyle kaldırılmamalı.

---

# 23. Yeniden tasarlanması gereken sınırlar

## 23.1 Destructive storage contract

Bugünkü:

```text
UI mutate
→ storage attempt
→ log error
```

Hedef:

```text
User intent
→ storage transaction
→ verified success
→ state commit
→ UI success
```

## 23.2 Privacy operation state machine

Encryption/clear/import gibi işlemler boolean setting olarak değil operation state olarak düşünülmeli.

```text
idle
requested
running
verifying
completed
failed(retryable/nonretryable)
```

## 23.3 Resource lifecycle

Heavy service’ler ortak policy’den desired mode almalı.

## 23.4 Platform adapters

CoreAudio/IOKit/Accessibility boundaries için gerçek integration smoke test target’ları eklenmeli.

---

# 24. Öncelikli TODO master list

## Phase 0 — Release safety / hemen

- [ ] Clear History collection/key rotation invariant düzelt.
- [ ] Delete/Clear storage API’lerini throwing/typed yap.
- [ ] UI destructive mutation’ı storage commit sonrasına taşı.
- [ ] Backup retention ve full-clear semantics belirle.
- [ ] All Items encryption migration state machine yap.
- [ ] Sensitive detail editor redaction/reveal policy düzelt.
- [ ] PKCS#8 ve PEM secret detection genişlet.
- [ ] File path/bookmark private metadata encryption kararı ver.
- [ ] Storage quota reclaim algoritmasını düzelt.
- [ ] Rich-text edit/original representation invariant düzelt.
- [ ] CoreAudio scalar property storage implementasyonunu düzelt ve Mac üzerinde test et.

## Phase 1 — Data integrity / privacy hardening

- [ ] Live capture byte/pixel/count limitleri.
- [ ] HTML sanitization allowlist/hardening.
- [ ] Quick Look temp plaintext lifecycle.
- [ ] Encryption asset migration atomic staging.
- [ ] Import transaction/staging cleanup.
- [ ] Recovery rollback status model.
- [ ] Legacy migration sensitive policy parity.
- [ ] SQLite index audit.
- [ ] Browser namespace ve IPC sender hardening.
- [ ] Safari media ownership-aware restore.

## Phase 2 — Performance / power

- [ ] ModuleLifecycleCoordinator tasarla.
- [ ] screen lock/sleep lifecycle ile heavy provider stop.
- [ ] Low Power Mode detection.
- [ ] battery/AC-aware sampling policy.
- [ ] metric-specific cost budgeting.
- [ ] status item update coalescing.
- [ ] Instruments Energy/Time Profiler baseline.
- [ ] 8-hour soak.
- [ ] combined vs independent metric energy benchmark.

## Phase 3 — System Monitor UX

- [ ] Numeric widget configuration model.
- [ ] Metric order.
- [ ] precision/unit settings.
- [ ] combined/independent custom layouts.
- [ ] format template parser/tokenizer.
- [ ] threshold/color policy.
- [ ] refresh interval user option with safe bounds.
- [ ] optional battery metric.
- [ ] per-metric visibility.
- [ ] live preview.

## Phase 4 — Menu Bar Manager

- [ ] Public/private API feasibility spike.
- [ ] AX permission boundary.
- [ ] external item identity strategy.
- [ ] hide/show fail-safe.
- [ ] restore-all emergency action.
- [ ] system items support matrix.
- [ ] custom grouping/rules.
- [ ] notch/overflow UX.
- [ ] macOS-version compatibility tests.

## Phase 5 — Stable release validation

- [ ] macOS 14 clean machine.
- [ ] macOS 15 clean machine.
- [ ] macOS 26 clean machine.
- [ ] M-series device cross-check.
- [ ] real CoreAudio multiple-app test.
- [ ] output device switch test.
- [ ] Safari/Chrome/Brave/Edge/Arc browser matrix.
- [ ] Accessibility revoke/regrant test.
- [ ] VoiceOver.
- [ ] High Contrast.
- [ ] Reduce Motion/Transparency.
- [ ] 200% scaling.
- [ ] small/notched display.
- [ ] multiple displays.
- [ ] 8-hour soak.
- [ ] Leaks / Allocations / Energy / Concurrency Instruments.
- [ ] exact stable-release SBOM/signing/checksum evidence.
- [ ] update `BETA_READINESS_REPORT` / create stable readiness report.

---

# 25. Risk matrisi

| ID | Alan | Risk | Olasılık | Etki | Öncelik |
|---|---|---|---|---|---|
| R1 | Clear/key rotation | Storage decrypt failure | Yüksek | Kritik | P0 |
| R2 | Delete/Clear | Verinin gerçekte silinmemesi | Orta | Kritik | P0 |
| R3 | Backups | Silinen clipboard’ın plaintext kalması | Yüksek | Yüksek | P0 |
| R4 | Encryption migration | UI encrypted, disk partial plaintext | Orta | Kritik | P0 |
| R5 | Sensitive UI | Secret’ın detail ekranında görünmesi | Yüksek | Yüksek | P0 |
| R6 | Secret detector | Private key persist edilmesi | Orta | Yüksek | P0 |
| R7 | File metadata | Sensitive path leak | Yüksek | Orta/Yüksek | P0 |
| R8 | Quota | Gereksiz toplu history kaybı | Orta | Yüksek | P0 |
| R9 | Rich text | Eski içeriğin paste edilmesi | Orta | Yüksek | P0 |
| R10 | CoreAudio | App discovery/audio mixer bozulması | Orta-Yüksek | Yüksek | P0/P1 |
| R11 | Exclusion | Password-manager copy’nin yakalanması | Düşük-Orta | Yüksek | P1 |
| R12 | Large paste | Memory/disk pressure | Orta | Orta/Yüksek | P1 |
| R13 | Quick Look temp | Plaintext orphan | Düşük-Orta | Orta | P1 |
| R14 | Browser IPC | Spoofed/local malformed command | Düşük-Orta | Orta | P1 |
| R15 | Recovery | Incomplete rollback | Düşük | Yüksek | P1 |
| R16 | Import | Orphan/mixed state | Orta | Orta | P1 |
| R17 | Power | Feature growth ile wake-up artışı | Orta | Orta | P2 |
| R18 | External menu manager | OS update ile private behavior break | Yüksek | Orta/Yüksek | Future |
| R19 | Release matrix | Beta testlerinin gerçek cihazı temsil etmemesi | Orta | Yüksek | P1 |

---

# 26. Stable 1.0 kabul kriterleri

Aşağıdakiler sağlanmadan “stable” demem:

## Data integrity

- [ ] destructive actions fail-closed / user-visible failure.
- [ ] Clear History sonrası restart temiz.
- [ ] Encryption migration partial failure testli.
- [ ] import/recovery atomicity testli.

## Privacy

- [ ] sensitive item hiçbir UI surface’ta implicit reveal olmuyor.
- [ ] secret detector PEM seti geniş.
- [ ] backup semantics kullanıcıya açık.
- [ ] privacy claim’ler implementation ile birebir.

## Performance

- [ ] idle < hedef budget.
- [ ] menu-bar metrics energy budget.
- [ ] 8h soak.
- [ ] no unbounded memory/history/cache.

## Platform

- [ ] macOS 14/15/26 acceptance.
- [ ] Accessibility paths.
- [ ] CoreAudio real app/device switch.
- [ ] SMC/HID sensor cross-validation.

## UX/accessibility

- [ ] notched/small display.
- [ ] multiple display.
- [ ] VoiceOver/focus.
- [ ] contrast/reduce motion/transparency.
- [ ] Turkish/English full pass.

## Distribution

- [ ] exact release artifact evidence.
- [ ] SBOM/checksum.
- [ ] reproducible documented signing.
- [ ] readiness report exact version.

---

# 27. Mimari kalite değerlendirmesi

Bu puanlar mutlak ölçüm değil, karar vermeyi kolaylaştıran `[Tahmin]` değerlendirmedir.

| Alan | Değerlendirme | Not |
|---|---:|---|
| Mimari ayrışma | 8.5/10 | Feature/service sınırları güçlü |
| Maintainability | 8.5/10 | Dosya boyutu/type gates ve DI iyi |
| Concurrency | 8/10 | Actor/MainActor kullanımı iyi; platform callback’leri izlenmeli |
| Storage design | 8/10 | Temel iyi; destructive invariants P0 |
| Security design | 8.5/10 | AES-GCM/Keychain/threat model güçlü |
| Privacy correctness | 6/10 | Clear/exclusion/sensitive UI/migration sorunları nedeniyle |
| Performance architecture | 8/10 | Demand sampling ve conditional audio güçlü |
| Energy optimization | 7/10 | İyi temel; global lifecycle/battery-aware policy eksik |
| Test engineering | 8.5/10 | Çok kapsamlı; invariant gap’leri var |
| Release readiness | 5.5/10 | Beta için uygun, stable için P0 + real-device evidence eksik |
| Product extensibility | 8/10 | Static modules kolay büyür; external menu manager ayrı subsystem olmalı |

---

# 28. Projenin en güçlü 10 kararı

1. `AppModel` composition root.
2. Shared feature controller state.
3. `StorageService` actor.
4. SQLite WAL/transaction yaklaşımı.
5. History/Notes separate Keychain keys.
6. Fail-closed crypto davranışı.
7. Archive staging + integrity validation.
8. Shared event tap for Input Tools.
9. System Monitor demand-driven single sampling.
10. Test/release gate kültürü.

---

# 29. Projenin şu anki en zayıf 10 noktası

1. Destructive storage API contract.
2. Clear History + key rotation invariant.
3. Backup privacy semantics.
4. Encryption migration commit semantics.
5. Sensitive content UI policy’nin yüzeyler arasında tutarsızlığı.
6. Secret detector false-negative riskleri.
7. Storage quota reclaim modelinin yanlış abstraction’ı.
8. New Audio Mixer gerçek platform integration coverage.
9. Exact beta.2/stable release evidence senkronizasyonu.
10. Feature büyüdükçe global power lifecycle policy’nin olmaması.

---

# 30. Önerilen hedef mimari

Mevcut yapıyı bozmadan:

```text
                        AppModel
                           │
       ┌───────────────────┼─────────────────────┐
       │                   │                     │
 FeatureRegistry     AppResourcePolicy      AppRouter
       │                   │
       │          ModuleLifecycleCoordinator
       │                   │
       ▼                   ▼
 Feature Models      Heavy Service Demands
       │           ┌───────┼──────────────┐
       │           ▼       ▼              ▼
       │       Clipboard SystemMetrics AudioMixer
       │                  │
       │          SamplingCoordinator
       │                  │
       │          MetricSnapshotStore
       │                  │
       ▼                  ▼
Control Center <---- Shared State ----> Menu Bar
                                     ├── modules
                                     ├── metric widgets
                                     └── future ExternalMenuBarManager
```

Storage tarafı:

```text
User destructive action
        │
        ▼
StorageOperationCoordinator
        │
        ├── begin
        ├── DB transaction
        ├── asset staging/finalize
        ├── verify invariants
        └── commit
             │
             ▼
        UI state update
```

---

# 31. Son karar

[Kesin] **Projenin temeli güçlü ve ölçeklenebilir.** Mevcut repo bir öğrenci/MVP kod tabanı seviyesinden daha ileri; native macOS platform sınırlarına, storage/crypto’ya, browser bridge’lerine ve release engineering’e ciddi biçimde girmiş durumda.

[Kesin] En büyük hata, “yeterince modüler değil” veya “performans mimarisi yok” değildir. Asıl problem **privacy-critical state transitions’ın birkaç yerde transactional olarak tamamlanmadan kullanıcıya başarı gibi yansıtılmasıdır.** Bu nedenle ilk geliştirme sprint’i yeni özellik eklemek yerine P0 invariant düzeltmelerine ayrılmalıdır.

[Kesin] P0 maddeleri kapandıktan sonra öncelik sırası:

1. privacy/data-integrity hardening,
2. CoreAudio ve platform acceptance,
3. global CPU/battery lifecycle policy,
4. System Monitor numeric customization,
5. external Menu Bar Manager,
6. stable release matrix

olmalıdır.

[Kesin] **Mevcut mimari korunmalı; kontrollü evrim yapılmalı, büyük rewrite yapılmamalı.**

---

# 32. Karar özeti — tek sayfalık liste

## Hemen düzelt

- Clear/key rotation
- delete/clear fail-open
- backups
- encryption migration
- sensitive UI
- PKCS#8
- file private metadata
- quota cleanup
- rich-text stale payload
- CoreAudio scalar read

## Sonra güçlendir

- payload limits
- HTML sanitizer
- Quick Look temp cleanup
- import/recovery atomicity
- browser IPC/identity
- real inactivity semantics
- SQLite indexes

## Performans

- mevcut SystemMetrics demand modelini koru
- global lifecycle coordinator ekle
- battery/Low Power Mode awareness
- redraw/update coalescing
- Instruments + soak

## Ürün

- numeric customizable metrics
- format template
- thresholds/colors
- combined/independent layouts
- external menu-bar manager ayrı subsystem

## Stable release

- macOS matrix
- real audio/device tests
- sensor cross-check
- accessibility/visual matrix
- exact versioned readiness evidence

