# ClipboardHistory — Tam Kod ve Mimari İnceleme

**İncelenen arşiv:** `ClipboardHistory-main.zip`  
**İnceleme tarihi:** 2026-08-10  
**Kapsam:** kaynak kod, testler, Xcode proje yapısı, plist/entitlement/config, Safari + Chromium uzantıları, native messaging/login item, release/quality scriptleri, dokümantasyon ve depolama/gizlilik veri akışları.

## Sonuç

[Kesin] Repo şu haliyle sözdizimsel ve organizasyonel açıdan güçlü, fakat **privacy-sensitive bir clipboard uygulaması için release-blocker sayılacak veri silme, anahtar rotasyonu, şifreleme migrasyonu ve hassas içerik görünürlüğü hataları var.** Özellikle `Clear History`, collection şifreleme anahtarı, backup retention ve fail-open storage yolları düzeltilmeden “tam güvenli silme / güvenli varsayılanlar” iddiası yapılmamalı.

[Kesin] Bu inceleme yalnızca yüzeysel grep değildir. Arşivde 340 Swift dosyası (~29 bin satır; üretim Swift’i ~17.5 bin satır), 52 Swift test dosyası, 5 JS, 16 zsh scripti, JSON/plist/entitlement dosyaları ve Xcode proje metadata’sı incelendi. 340 Swift dosyasının tamamı Linux Swift 6.2 parser’ından geçti; 5 JS dosyası `node --check` ile geçti; JSON/plist/entitlement dosyaları parse edildi; metin dosyalarında UTF-8/NUL/CRLF/trailing-whitespace/final-newline kontrolleri yapıldı.

[Kesin] Ortam Linux olduğu için AppKit/IOKit/CoreAudio/QuickLook/LocalAuthentication içeren gerçek macOS build, `xcodebuild test`, sanitizer, Instruments veya UI testi burada çalıştırılamadı. Dolayısıyla “proje gerçek Xcode build’inden geçti” iddiası bu incelemede yapılmıyor. Arşivde `.git` geçmişi de bulunmadığından tarihçe bazlı secret scan yeniden doğrulanamadı.

---

# Mimari özeti

Uygulama artık yalnızca clipboard history değil, daha geniş bir macOS utility suite:

- Clipboard capture, search, pin/snippet, collections, rich text, images/PDF/files, Quick Look, export/import.
- Privacy: excluded/allowed apps, secret detection, temporary sensitive content, AES-GCM encryption, Keychain master keys, application lock.
- Notes: ayrı key ve ayrı storage semantics.
- Audio mixer: CoreAudio process control, Safari extension, Chromium extension + native messaging bridge.
- Input tools: keyboard cleaning ve scroll reversal.
- System monitor: process/system metrics ve SMC temperature.
- Login item / menu bar shell.
- Release tooling: static quality, localization, coverage, sanitizer, mutation, arm64 artifact/signing checks.

[Kesin] Genel tasarımda iyi kararlar var: `StorageService` actor; SQLite WAL/FULLMUTEX; database transaction’ları; `ManagedFilename` ile asset filename doğrulaması; AES-GCM; history ve note key’lerinin ayrılması; archive size/count/path/integrity limitleri; strict Swift concurrency; test doubles/failure injection; fail-closed note storage; release statik gate’leri.

---

# Release blocker / yüksek önem

## 1. Clear History collection’ları silmeden history encryption key’i değiştiriyor

**Seviye:** CRITICAL / Release blocker  
**Güven:** [Kesin]

`ClipboardHistory/Services/Storage/StorageService.swift:391-405` içinde `clearAll()` yalnızca `ClipboardItems` tablosunu siliyor ve sonra `rotateEncryptionKeyAfterCompleteErasure()` çağırıyor. `ClipboardCollections` silinmiyor.

`StorageRecoveryAndEncryptionRotation.swift:5-14` history key’ini gerçekten değiştiriyor. Collection adları ise `StorageService.swift:109-135` içinde aynı history encryption service ile decrypt ediliyor.

Sonuç: Clear History öncesi oluşturulmuş collection adları eski anahtarla şifreli kalıyor; yeni key ile decrypt edilemiyor. Bir sonraki `loadHistory()` akışında `loadCollectionsThrowing()` hata verebilir.

`ClipboardHistoryViewModel.swift:173-189` herhangi bir storage hatasını “encryption key erişilemiyor” olarak ele alıyor, `isStorageAvailable=false` yapıp monitoring’i durduruyor. Dolayısıyla kullanıcı kendi Clear History işlemiyle sonraki açılışta storage’ı kilitleyebilir ve yanıltıcı Keychain mesajı görebilir.

**Düzeltme:** Clear History transaction’ına `DELETE FROM ClipboardCollections` eklenmeli veya collection kayıtları yeni key ile yeniden şifrelenmeli. “Clear all history” semantics’i açısından collection’ları silmek daha tutarlı. ViewModel `collections` da eşzamanlı temizlenmeli. Bunun için mutlaka regresyon testi eklenmeli.

---

## 2. Delete ve Clear History fail-open: UI’den silinen veri SQLite’ta kalabilir

**Seviye:** HIGH / Release blocker  
**Güven:** [Kesin]

`ClipboardHistoryMutationController.swift:137-166` item’ı önce memory/UI’dan kaldırıyor, sonra `storage.deleteItem` çağırıyor.

`StorageService.swift:319-335` `deleteItem` tüm storage hatalarını sadece loglayıp `Void` dönüyor. Kullanıcıya başarısızlık iletilmiyor ve memory rollback yapılmıyor.

Aynı model `clearHistoryNow()` için de var (`ClipboardHistoryMutationController.swift:388-405`): tüm in-memory state önce sıfırlanıyor, sonra `storage.clearAll()` çağrılıyor. `StorageService.clearAll()` hata durumunda sadece logluyor (`391-410`).

Sonuç: UI “silindi” görüntüsü verebilir ama DB satırı kalabilir; yeniden açılışta silinen içerik geri gelebilir. Privacy uygulamasında delete semantics için bu kabul edilemez.

**Düzeltme:** destructive storage API’leri `throws`/typed result dönmeli. Önce DB transaction tamamlanmalı, sonra UI state commit edilmeli; hata durumunda kullanıcı açıkça bilgilendirilmeli. Asset delete başarısızlıkları da raporlanmalı.

---

## 3. Clear History `Backups/` içindeki eski clipboard verisini silmiyor

**Seviye:** HIGH / Release blocker  
**Güven:** [Kesin]

`StorageService.clearAll()` sadece Images/Thumbnails/Payloads/.staging klasörlerini recreate ediyor; `Backups/` yok.

`StorageSchemaMigrationService.swift:208-234` legacy `history.json` dosyasını `Backups/history-before-sqlite-*.json` ve `history-migrated-*.json` şeklinde kopyalıyor/taşıyor. Legacy JSON doğrudan clipboard item text’i içerir; bu yedek plaintext olabilir.

Migration failure yolu da `history-migration-failed-*.json` bırakıyor (`237-243`). Corrupt SQLite recovery de backup üretir.

`StorageMaintenanceService.swift:104-110` storage metrics hesabına `Backups/` dahil değil. Yani UI storage kullanımı ve max-storage cleanup bunları görmüyor.

Sonuç: kullanıcı “Clear History” yaptıktan sonra eski clipboard metni backup’larda kalabilir. Bu özellikle clipboard manager’da privacy expectation ile çelişiyor.

**Düzeltme:** backup retention açıkça modellenmeli. En azından backup boyutları UI/storage metrics’e dahil edilmeli; Clear History için “backup’ları da sil” semantics’i tanımlanmalı veya backup’lar encrypted tutulmalı. Recovery rollback backup’ları da aynı politika altında ele alınmalı.

---

## 4. “Excluded clipboard content is never read or stored” garantisi teknik olarak doğru değil

**Seviye:** HIGH privacy  
**Güven:** [Kesin]

`ClipboardMonitor.swift:7` 500 ms polling yapıyor. Değişiklik algılandıktan sonra `NSWorkspace.shared.frontmostApplication` okunuyor (`53-67`) ve source app olarak bu bundle ID kabul ediliyor.

Bu, clipboard’ı **yazan uygulamayı** güvenilir biçimde belirlemiyor; yalnız poll anındaki frontmost app’i belirliyor. Kullanıcı excluded password manager’dan kopyalayıp 500 ms içinde başka uygulamaya geçerse içerik allowed app’e ait sanılarak okunabilir. Tersi de mümkün.

Settings UI `ClipboardSettingsPrivacyView.swift:99` ise “Excluded clipboard content is never read or stored.” diyor. Bu mevcut mekanizmanın garanti edemeyeceği kadar güçlü bir ifade.

Default excluded list 1Password, Bitwarden, Dashlane, LastPass ve Keychain Access içeriyor (`AppSettings.swift:255-262`), yani hata en hassas use-case’e temas ediyor.

**Düzeltme:** UI metnini “best effort” olarak düzelt. `org.nspasteboard.concealedtype/transienttype` gibi writer-set pasteboard markers daha güçlü privacy sinyali; source-app exclusion tek başına garanti diye sunulmamalı.

---

## 5. “All Items” encryption migration başarısız olsa bile ayar uygulanmış kabul ediliyor

**Seviye:** HIGH / Release blocker  
**Güven:** [Kesin]

`ClipboardHistoryPrivacyController.swift:141-149` içinde `appliedEncryptionMode = settings.encryptionMode` migrasyondan **önce** set ediliyor.

`StorageMaintenanceService.swift:5-30` `migrateEncryption` `Void` dönüyor. Asset rewrite false olursa sessizce `continue`; exception olursa sadece loglanıyor. UI’ye migration sonucu dönmüyor.

Sonuç: kullanıcı “All Items” seçer; bir asset veya DB write başarısız olur; UI hâlâ “All Items” gösterir fakat bazı eski item’lar eski encryption durumunda (varsayılanda sıradan item için plaintext) kalabilir. `appliedEncryptionMode` zaten güncellendiği için otomatik retry de tetiklenmez.

Ayrıca `ClipboardAssetStore.rewriteAssets` asset’leri tek tek yazar. Orta noktada hata olursa yeni-format kopyaların bir kısmı oluşmuş, DB row’u eski durumda kalmış olabilir.

**Düzeltme:** migration typed success/report dönmeli; tüm migration başarılı olmadan `appliedEncryptionMode` commit edilmemeli. Asset migration staging + verify + DB commit + old-file cleanup sırasıyla yapılmalı. Hata UI’ye gösterilmeli ve retry mümkün olmalı.

---

## 6. Sensitive item preview gizli ama aynı ekranda editor gerçek secret’ı gösteriyor

**Seviye:** HIGH privacy  
**Güven:** [Kesin]

`ClipboardDetailView.swift:93-105` sensitive item için “Sensitive Content / The preview is hidden.” gösteriyor.

Fakat body aynı anda `preview`, `editor`, `metadata` render ediyor (`41-45`). `editor` (`54-90`) gerçek `draftTitle`, `draftText`, tags alanlarını TextField olarak gösteriyor; state doğrudan gerçek item değerlerinden initialize ediliyor (`13-20`).

Ayrıca metadata içinde OCR ve QR text gerçek haliyle gösterilebiliyor (`145-150`).

Application lock panel seviyesinde doğru biçimde detail screen’i engelliyor; sorun **app unlocked iken sensitive item’ın “hidden preview” iddiasının editor tarafından delinmesi**.

**Düzeltme:** sensitive item için editor ve secret-derived metadata da redacted olmalı. Reveal gerekiyorsa explicit authenticated “Reveal” aksiyonu uygulanmalı.

---

## 7. Secret detector standart PKCS#8 private key’leri kaçırıyor

**Seviye:** HIGH privacy  
**Güven:** [Kesin]

`SecretDetectionService.swift:16` regex’i:

`-----BEGIN (OPENSSH|RSA|EC|DSA|PGP|PRIVATE) PRIVATE KEY-----`

Bu regex standart `-----BEGIN PRIVATE KEY-----` formatını eşleştirmez; `PRIVATE` alternatifi `BEGIN PRIVATE PRIVATE KEY` bekler. `-----BEGIN ENCRYPTED PRIVATE KEY-----` de kaçırılır.

Entropy fallback yalnız whitespace çıkarıldıktan sonra 20...512 karakter aralığında çalışıyor (`51-55`). Tipik PEM private key 512 karakteri aşabildiği için detector tamamen kaçırabilir.

Default `secretDetectionEnabled=true`, `sensitiveStoragePolicy=.neverSave`, encryption default `.sensitive` olduğundan kaçırılan key ordinary item olarak plaintext persist edilebilir.

Test `PrivacySecurityTests.swift:9-27` yalnız OPENSSH marker’ını kapsıyor; PKCS#8 testi yok.

**Düzeltme:** explicit `BEGIN PRIVATE KEY`, `BEGIN ENCRYPTED PRIVATE KEY` ve vendor-specific PEM varyantları test edilmeli. PEM header tespiti entropy sınırına bağlı olmamalı.

---

## 8. Encrypted file item’larda absolute paths ve bookmark blobs SQLite’ta şifresiz

**Seviye:** HIGH/MEDIUM privacy  
**Güven:** [Kesin]

`SQLiteClipboardRepository.swift:33-38` yalnız `textContent` için `item.isEncrypted` kontrolüyle encryption uyguluyor. `fileURLs` ve `fileBookmarks` doğrudan JSON encode edilip SQLite BLOB’a yazılıyor (`57-59`) ve doğrudan decode ediliyor (`151-160`).

Absolute path kullanıcı adı, proje/müşteri adı veya klasör organizasyonu gibi sensitive metadata taşıyabilir. Security-scoped bookmark blob da path/resource bilgisi taşıyabilir.

Threat model görünür metadata listesinde file path/bookmark açıkça belirtilmemiş.

**Düzeltme:** `isEncrypted` item’da fileURLs ve bookmarks serialized blob’u da encryption envelope içine alınmalı veya UI/dokümantasyonda bunların plaintext metadata olduğu açıkça yazılmalı.

---

## 9. Max-storage cleanup algoritması DB/text ağırlıklı durumda bütün unpinned item’ları silebilir

**Seviye:** HIGH data-loss / MEDIUM-HIGH correctness  
**Güven:** [Kesin]

`StorageMaintenanceService.swift:68-75` toplam storage cap aşılırsa `currentBytes` azaltmak için yalnız `associatedFileSize(for:item)` kullanıyor.

`StorageRecoveryAndEncryptionRotation.swift:43-57` bu fonksiyon yalnız image/thumbnail/payload dosyalarını sayıyor. SQLite row/text boyutu sıfır kabul ediliyor.

Ancak `storageMetrics()` toplamına SQLite database file dahil (`StorageMaintenanceService.swift:104-110`). DB/text yüzünden quota aşılmışsa her text item için `currentBytes -= 0`; loop quota altına asla düşmez ve bütün unpinned item’lar removal set’e eklenebilir.

Üstelik SQLite row delete database file’ı otomatik küçültmeyebileceğinden işlemden sonra fiziksel usage aynı kalabilir.

**Düzeltme:** per-record logical DB estimate veya incremental delete+recalculate kullanılmalı. Büyük cleanup sonrası kontrollü VACUUM/auto-vacuum stratejisi değerlendirilmeli.

---

## 10. Rich-text edit sonrası “Original” paste eski içeriği yapıştırabilir

**Seviye:** HIGH functional/data-integrity  
**Güven:** [Kesin]

`ClipboardDetailView.swift:187-195` `.richText` için text editing’e izin veriyor.

`ClipboardHistoryMutationController.swift:293-299` editte yalnız `text`, `hash`, `fileSize` güncelleniyor. Eski `payloadFilename` ve içindeki RTF/HTML aynen kalıyor.

`ClipboardPasteboardWriter.swift:52-60` `.richText` restore sırasında text ile birlikte bu eski RTF/HTML payload’ı pasteboard’a yazıyor. Rich-aware hedef uygulama RTF/HTML’yi plain text’ten üstün tutarsa kullanıcı UI’da düzenlediği metin yerine **eski zengin metni** paste edebilir.

Ayrıca row hash yeni text’e, rich payload eski text’e karşılık gelerek internal data tutarsızlığı oluşur.

**Düzeltme:** richText edit edilince ya item `.text`’e downgrade edilip payload silinmeli ya da yeni RTF/HTML payload regenerate edilmeli.

---

# Orta önem

## 11. Live clipboard capture için explicit boyut/adet/pixel sınırı yok

**Seviye:** MEDIUM availability  
**Güven:** [Kesin kod davranışı], etkisi [Muhtemel]

`ClipboardMonitor.readSupportedContent()` PDF/image/RTF/HTML/string ve tüm pasteboard image item’larını app-level byte cap olmadan okuyor (`102-155`). Image processing decode/PNG normalize ve OCR yoluna girebiliyor.

Archive import’ta 512 MB / item-count limitleri mevcutken canlı clipboard için benzer sınırlar yok.

**Risk:** local aynı-user process büyük/many image/PDF/text clipboard yazarak memory/CPU/disk spike yaratabilir.

**Düzeltme:** per-event byte cap, text/RTF/HTML cap, image count, compressed bytes, pixel dimensions ve OCR threshold eklenmeli.

---

## 12. HTML sanitizer regex tabanlı ve aktif scheme/resource yollarını kapsamıyor

**Seviye:** MEDIUM  
**Güven:** [Kesin]

`HTMLSanitizer.swift:6-13` script/style/iframe/object/embed, inline `on*` ve http(s)// src/href’i kaldırıyor.

Fakat `javascript:`, `data:`, `file:`, `srcset`, CSS `url(...)`, SVG/xlink ve malformed HTML parser edge-case’leri kapsanmıyor.

Uygulamanın kendisi HTML’i WebView’de execute etmiyor; dolayısıyla bunu app içi RCE diye sınıflandırmıyorum. Fakat sanitized HTML tekrar clipboard’a verilerek downstream uygulama tarafından yorumlanabilir.

**Düzeltme:** regex blacklist yerine parser + explicit safe tag/attribute/scheme allowlist veya rich formatting subset’ine canonicalization.

---

## 13. Quick Look encrypted asset’i plaintext temp dosyasına çıkarıyor; crash orphan bırakabilir

**Seviye:** MEDIUM privacy  
**Güven:** [Kesin]

`QuickLookService.swift:65-101` encrypted image/PDF/rich payload’ı decrypt edip `temporaryDirectory/ClipboardHistoryPreview-UUID` içine plaintext yazıyor.

Cleanup next-show/close/panel-will-close sırasında var (`25-53`, `111-117`) fakat process crash/force-kill/power loss senaryosunda mevcut instance cleanup çalışmayabilir. Startup’ta `ClipboardHistoryPreview-*` sweep yok.

**Düzeltme:** startup orphan cleanup, restrictive permissions ve lifecycle cleanup. Dokümantasyonda encrypted-at-rest içeriğin Quick Look sırasında geçici plaintext materialization yaptığı belirtilmeli.

---

## 14. `idx_items_text` full text/BLOB index’i kullanılmıyor ve DB’yi şişirebilir

**Seviye:** MEDIUM performance/storage  
**Güven:** [Kesin]

`StorageSchemaMigrationService.swift:112` `textContent` üstünde SQLite index kuruyor. Storage query’lerinde textContent üzerinde WHERE/ORDER lookup yok; search UI in-memory.

Bu index uzun plaintext/ciphertext BLOB değerlerini ayrıca index pages’te tutarak database size ve write amplification yaratır. Encrypted content için lookup değeri sıfırdır.

Bu aynı zamanda #9 storage cap problemine katkıda bulunur.

**Düzeltme:** schema migration ile `DROP INDEX idx_items_text`.

---

## 15. Chromium-family browser tab namespace’i browser’lar arasında çakışıyor

**Seviye:** MEDIUM functional  
**Güven:** [Kesin]

`offscreen.js:31-34` Chrome/Brave/Edge/Arc için `source: "chromium"`, id=`chromium:${tabId}` gönderiyor. `browserName` yalnız display alanı.

`BrowserAudioBridge.swift:74-79` state’i source anahtarına göre replace ediyor. İki Chromium-family browser aynı anda extension çalıştırırsa ikisi aynı `chromium` namespace’ine yazıyor; heartbeat’ler birbirini overwrite edebilir. Tab ID’ler browser-local olduğu için aynı numeric ID de çakışabilir.

**Düzeltme:** source/id içine browser flavor ve mümkünse profile/install identity dahil edilmeli: `chromium:brave:<tabId>` gibi.

**Not:** `offscreen.js` içindeki `nativePort` gerçekten `let` olarak tanımlı. Ön inceleme sırasında görülen “const reassignment” şüphesi yanlış olduğu için bu raporda hata olarak yer almıyor.

---

## 16. Browser bridge DistributedNotificationCenter üzerinde sender authentication yapmıyor

**Seviye:** MEDIUM local integrity  
**Güven:** [Kesin kod davranışı], saldırı etkisi [Muhtemel]

`BrowserAudioBridge.swift:25-46` `object:nil` ile global named distributed notification dinliyor ve requestID + payload decode edildiyse kabul ediyor.

NativeMessagingHost Chromium origin’ini kontrol ediyor, fakat DNC katmanının kendisi sender identity doğrulamıyor. Aynı kullanıcı oturumundaki başka process aynı notification namespace’ine message inject edebilir veya response spoof etmeyi deneyebilir.

Bu doğrudan clipboard history okumaya yol açmıyor; browser mixer state/control integrity problemi.

**Düzeltme:** XPC + audit token/code-sign validation tercih edilmeli veya per-install/ephemeral authenticated IPC token kullanılmalı.

---

## 17. Safari mixer webpage’nin kendi volume/mute state’ini tahrip ediyor

**Seviye:** MEDIUM functional  
**Güven:** [Kesin]

`ClipboardHistorySafariExtension/Resources/content.js:1-14` tab volume’u yalnız ilk media elementinden raporluyor.

`17-24` mixer komutunda sayfadaki **tüm** audio/video elementlerine aynı `.volume` değeri yazıyor ve `media.muted = volume === 0` yapıyor.

Bu, site/user tarafından farklı volume verilen elementleri eşitler. Mixer 0’dan tekrar >0’a alınca önceden intentional muted olan elementleri de unmute eder.

`MutationObserver` tüm document subtree değişikliklerinde `querySelectorAll("audio,video")` çalıştırıyor (`27`); DOM-heavy sayfalarda gereksiz yük oluşturması [Muhtemel].

**Düzeltme:** Safari API izin veriyorsa ayrı gain layer; değilse original per-element mute/volume state preserve/restore ve observer debounce/throttle.

---

## 18. Recovery import rollback ikinci kez hata verirse swallow ediliyor ama UI “previous DB değişmedi” diyor

**Seviye:** MEDIUM-HIGH recovery correctness  
**Güven:** [Kesin]

`StorageRecoveryImportService.swift:85-96` mevcut destination’ı backup’a taşıyor; staging→destination move hata verirse backup→destination restore `try?` ile yapılıyor.

Rollback restore da hata verirse bu ikinci hata kayboluyor. Destination eksik kalabilir ve eski data sadece rollback backup’ta olabilir.

`ClipboardHistoryArchiveController.swift:97-100` ise her failure’da “Recovery failed without replacing the previous database” mesajı gösteriyor; rollback failure durumunda bu doğru olmayabilir.

**Düzeltme:** rollback failure ayrı typed catastrophic error olmalı; backup URL kullanıcıya güvenli şekilde bildirilmeli; UI “old DB intact” garantisini yalnız restore başarıyla doğrulanınca vermeli.

---

## 19. Application “inactivity” lock gerçek user inactivity’yi takip etmiyor

**Seviye:** MEDIUM UX/security semantics  
**Güven:** [Kesin]

`AppLockService.recordActivity()` timer’ı resetliyor (`72-75`). Production call-site aramasında yalnız `MenuBarController.swift:233,276,304` bulundu; bunlar panel/popover presentation yolları.

Keyboard/mouse interaction, note editing, selection, settings interaction vb. timer resetlemiyor.

Sonuç: “After 5 Minutes” gibi seçenek, app aktif şekilde kullanılırken bile panel açıldıktan 5 dakika sonra lock edebilir. Buna “inactivity” demek semantik olarak yanlış.

**Düzeltme:** app-local user input event stream veya merkezi interaction publisher ile meaningful activity’de `recordActivity()` çağır.

---

## 20. Encryption asset migration transactional staging yapmıyor

**Seviye:** MEDIUM state consistency  
**Güven:** [Kesin]

`ClipboardAssetStore.rewriteAssets()` image/thumbnail/payload’ı tek tek target encryption formatında store ediyor. Sonraki asset başarısız olursa önceki target kopyalar kalıyor; DB row `isEncrypted` hâlâ eski durumda olabilir.

Başarılı DB commit’ten sonra old-format fiziksel dosyalar siliniyor; fakat partial failure cleanup yok.

Bu #5 ile birleşince UI-state, DB-state ve disk-state üçlüsü ayrışabiliyor.

**Düzeltme:** item bazında staging directory, bütün asset verify, transaction, atomic promote, rollback cleanup.

---

## 21. Normal Merge Import collection’ları item importundan önce kalıcı olarak mutate ediyor

**Seviye:** LOW-MEDIUM transaction semantics  
**Güven:** [Kesin]

`ExportImportService.swift:124` archive collection’larını batch upsert ediyor; ardından item’ları tek tek import/reject ediyor (`130-150`).

Bütün item’lar reject olsa bile collection değişiklikleri kalabilir. Normal merge partial-success modeli olabilir; fakat dokümantasyondaki genel “atomic staging” dili bu davranışla ayrıştırılmalı.

**Düzeltme:** Merge = partial semantics açıkça belgelenmeli veya collection+item import staging/transaction içine alınmalı.

---

## 22. Normal import rejected item sonrası orphan asset bırakabilir

**Seviye:** LOW-MEDIUM storage correctness  
**Güven:** [Kesin]

`ExportImportService.materialize()` asset’leri sırayla `storage.storeImage/storePayload` ile kalıcı storage’a yazıyor (`410-443`). Sonraki bir asset missing/fail olursa önce yazılan asset’ler rollback edilmiyor.

Outer loop yalnız `rejected += 1` yapıyor (`148-150`). Daha sonraki `loadHistory()` orphan cleanup yapabilir fakat immediate leak/storage amplification mümkündür.

**Düzeltme:** item materialization sırasında created filenames takip edilip failure’da cleanup edilmeli veya staging kullanılmalı.

---

## 23. Rich-text capture payload storage başarısız olsa da item `.richText` oluyor

**Seviye:** LOW-MEDIUM functional  
**Güven:** [Kesin]

`ClipboardHistoryCaptureController.swift:86-95` rich payload encode ediyor, `storage.storePayload` sonucu `nil` olabilir; buna rağmen `itemType = .richText` unconditionally set ediliyor.

`ClipboardItem.isStructurallyValid` richText için yalnız `text != nil` şartı koyduğu için bu kayıt valid kalır. Restore tarafı payload bulamazsa plain text fallback yapar. Yani item UI’da rich text olarak görünüp formatını kaybetmiş olabilir.

**Düzeltme:** `payloadFilename != nil` ise `.richText`; aksi halde `.text` fallback ve subtype plain.

---

## 24. Legacy JSON migration sensitive fail-closed guard’ını bypass ediyor

**Seviye:** MEDIUM migration privacy  
**Güven:** kod yolu [Kesin], gerçek legacy veri kombinasyonu [Muhtemel]

Public `upsertThrowing` `isSensitive && !isEncrypted` item’ı reddediyor (`StorageService.swift:240-243`).

Fakat `StorageSchemaMigrationService.swift:213-220` legacy `[ClipboardItem]` decode edip low-level `insertOrReplace(item)` doğrudan çağırıyor. Bu low-level fonksiyonda sensitive guard yok.

Legacy JSON’da `isSensitive=true, isEncrypted=false` oluşabiliyorsa plaintext sensitive item migrate edilir.

**Düzeltme:** legacy item migration’dan önce normalization/validation; sensitive ise force-encrypt veya fail closed.

---

# Düşük önem / hardening / bakım

## 25. Password archive PBKDF2 embedded NUL’da password’u truncate ediyor

**Seviye:** LOW hardening  
**Güven:** [Kesin]

`SystemPasswordArchiveCryptoBackend.swift:22-29` `password.withCString` + `strlen(passwordBytes)` kullanıyor. Swift String U+0000 içerebilir; `abc\0def` ve `abc` aynı PBKDF2 password byte length’i kullanır.

SecureField ile pratik kullanıcı girişinde NUL olasılığı düşük olduğu için exploitation likelihood düşük.

**Düzeltme:** `Data(password.utf8)` ve explicit byte count kullan.

---

## 26. `randomData(count:)` generic zero-count durumunda `baseAddress!` güvenli değil

**Seviye:** LOW  
**Güven:** [Kesin]

`SystemPasswordArchiveCryptoBackend.swift:7-11` `buffer.baseAddress!` kullanıyor. Mevcut call-site salt için >0 count kullandığından bug bugün tetiklenmiyor; fakat generic API zero count alırsa force unwrap riski var.

**Düzeltme:** zero-count özel durum veya optional pointer safe handling.

---

## 27. Static quality gate ordinary force unwrap’ları yakalamıyor

**Seviye:** LOW tooling  
**Güven:** [Kesin]

`scripts/verify-static-quality.sh` `try!`, `as!`, `fatalError`, `preconditionFailure`, print/NSLog vb. arıyor fakat generic `!` unwrap için AST-aware check yok.

Production’da en az `SystemPasswordArchiveCryptoBackend.swift:10 baseAddress!` ve `ControlCenterModel.swift:31 .first{...}!` gibi örnekler var. Bazıları invariant nedeniyle kontrollü olsa da gate “unsafe construct” kapsamını tam sağlamıyor.

**Düzeltme:** regex yerine SwiftSyntax/SwiftLint/SwiftFormat lint veya compiler/analyzer tabanlı rule.

---

## 28. Encrypted image için “Reveal in Finder” gerçek görsel yerine `.enc` blob’u gösterebilir

**Seviye:** LOW UX  
**Güven:** [Kesin]

`ClipboardHistoryPrivacyController.swift` storage `imageURL(... isEncrypted:)` yolunu Finder’a verir. Encrypted asset fiziksel olarak `.enc` dosyasıdır.

Kullanıcı bunu source/reveal anlamında bekliyorsa viewable image yerine internal ciphertext storage file görür.

**Düzeltme:** encrypted item’da “Reveal encrypted storage file” olarak etiketle veya action’ı kaldır; gerçek içerik için explicit Export kullan.

---

## 29. Her settings mutation ağır clipboard maintenance zincirini yeniden tetikliyor

**Seviye:** LOW performance/architecture  
**Güven:** [Kesin]

`ClipboardHistoryCaptureController.swift:13-19` bütün `settings.objectWillChange` event’lerini tek sink’te `settingsDidChange()` çağrısına çeviriyor.

`ClipboardHistoryPrivacyController.swift:128-155` bunun sonucunda ignored types, lock config, thumbnail cache, encryption mode check, history limit enforcement ve retention cleanup zincirini çalıştırıyor.

Unrelated UI/system setting değişiklikleri bile storage maintenance başlatabilir.

**Düzeltme:** settings snapshot diff veya feature-specific publishers/debounce.

---

## 30. Audio mixer sonraki gain restore hatalarını sessizce yutuyor

**Seviye:** MEDIUM functional  
**Güven:** [Kesin]

`AudioMixerController.swift:225-239`: ilk restore `setVolume()` ile normal error handling yoluna giriyor. Daha sonraki refresh’lerde `try? engine.setGain` kullanılıyor (`228-232`).

Pipeline/process object değişimi sonrası gain reapply başarısız olursa UI stored volume göstermeye devam edip gerçek output 100% kalabilir; kullanıcı hata görmez.

**Düzeltme:** refresh restore’da da unified error state + retry/reconciliation.

---

## 31. Xcode project’te legacy file reference/buildfile metadata kalmış

**Seviye:** LOW maintenance  
**Güven:** [Kesin]

`project.pbxproj` başında eski `ClipboardHistoryApp.swift`, root `ClipboardItem.swift` gibi PBXFileReference/PBXBuildFile kayıtları var. Mevcut proje file-system-synchronized root groups kullanıyor ve PBXSourcesBuildPhase listeleri boş (`551-587`), bu nedenle bu kayıtları doğrudan active compilation bug olarak sınıflandırmıyorum.

**Düzeltme:** pbxproj’yi Xcode üzerinden temizlemek merge noise ve ileride yanlış referans riskini azaltır.

---

## 32. Lokalizasyon helper JSON’da stale/extra entry’ler var

**Seviye:** LOW maintenance  
**Güven:** [Kesin]

`Localizable.xcstrings` 503 source key içerirken `scripts/tr-localizations.json` 534 entry içeriyor; 31 entry artık source catalog’da kullanılmıyor. Mevcut localization gate missing translation ve checked-in catalog staleness’ını yakalıyor, helper JSON’daki extra key’leri fail etmiyor.

**Düzeltme:** unused helper translations için reverse-diff gate ekle veya generation source-of-truth’u sadeleştir.

---

## 33. Beta readiness raporu güncel release metadata’sıyla senkron değil

**Seviye:** LOW docs/release process  
**Güven:** [Kesin]

README/CHANGELOG/release tooling `v1.0.0-beta.2`, version `1.0.0`, build `10002` gösterirken `docs/BETA_READINESS_REPORT.md` hâlâ beta.1/build10001 evidence raporu.

Bu tek başına product bug değil; release evidence dokümanının hangi build’e ait olduğunu doğru isimlendirmek gerekir.

**Düzeltme:** beta.1 raporunu historical olarak rename et veya beta.2 için yeni readiness evidence üret.

---

## 34. Threat model archive encryption ifadesi fazla genel

**Seviye:** LOW documentation security accuracy  
**Güven:** [Kesin]

Export modes arasında metadata-only/full-unencrypted/encrypted var; import raw JSON archive’ı da kabul ediyor. Buna karşı threat model’de archive güvenliği “authenticated encryption” diye genel ifade edilmiş.

Plain export SHA-256 manifest integrity taşır fakat keyed/authenticated değildir; archive içeriğini değiştirebilen biri checksum manifest’ini de değiştirebilir.

**Düzeltme:** “password-protected archives use authenticated AES-GCM; unencrypted exports are not authenticated” şeklinde açık ayrım.

---

# Test ve kalite değerlendirmesi

[Kesin] Test yapısı sıradan bir hobby repo seviyesinin üstünde: 51 unit + 1 UI Swift test dosyası; failure injector’lar; storage rollback tests; crypto tamper tests; deterministic fuzz; performance benchmark; recovery import; accessibility/paste; menu/panel; audio; input tools; notes; archive tests mevcut.

[Kesin] Buna rağmen bulunan kritik hatalar **coverage miktarı ile invariant coverage farkını** gösteriyor. Özellikle şu testler eksik:

1. `clearAll` + mevcut collection + key rotation → restart/load collections.
2. `deleteItem` veya `clearAll` DB failure → UI state rollback / user-visible error.
3. Clear History sonrası `Backups/` privacy policy.
4. “All Items” migration mid-asset/mid-DB failure → applied mode değişmemeli.
5. Sensitive item detail editor redaction.
6. `BEGIN PRIVATE KEY` ve `BEGIN ENCRYPTED PRIVATE KEY` detector cases.
7. Storage cap yalnız text/DB ile aşılmış senaryo → bütün history silinmemeli.
8. Rich-text edit → original paste edited content ile tutarlı.
9. Multi-Chromium browser source/id namespace collision.
10. Recovery import rollback’un kendisi fail ederse UI/error semantics.
11. App lock continuous interaction ile inactivity timer reset.
12. Legacy migration sensitive-unencrypted guard.

[Kesin] `scripts/verify-static-quality.sh` iyi bir minimum gate: network primitives/literal HTTP, force cast/try, crash primitives, print/log hygiene, file-size/type count ve localization checks var. Fakat regex tabanlı olduğu için semantic invariant/security/data-flow hatalarını yakalayamaz; bu auditteki kritik bulguların çoğu bu sınıfta.

---

# Güvenlik ve privacy açısından iyi olan kısımlar

[Kesin] AES-GCM kullanımı, Keychain fallback key üretmemesi, note key’inin history key’inden ayrılması, password archive PBKDF2 rounds validation, archive path validation, max archive size/item count, manifest/hash checks, `ManagedFilename`, storage staging, encrypted protected metadata ve concealed/transient pasteboard type ignore yaklaşımı doğru yönde.

[Kesin] Main app entitlement dosyası boş, Safari extension sandboxed. Main app’in unsandboxed olması otomatik vulnerability değildir; Accessibility/CoreAudio/input/system utility fonksiyonlarının gerektirdiği capability modeliyle uyumlu olabilir. Bunun bedeli, app içindeki storage/path/IPC güvenliğinin daha önemli hale gelmesidir.

[Kesin] Production Swift kaynaklarında `try!`, `as!`, `fatalError`, `print/NSLog` tipi kolay riskler görünmedi. Strict concurrency `complete`, Swift 6 ve hardened runtime build settings mevcut.

---

# Release için düzeltme sırası

1. **Clear History + collection key rotation (#1).**
2. **Delete/Clear fail-open semantics (#2).**
3. **Backups privacy / Clear History semantics (#3).**
4. **Encryption migration fail-open + asset staging (#5/#20).**
5. **Sensitive detail redaction (#6).**
6. **PKCS#8 detector (#7).**
7. **Encrypted file URL/bookmark metadata (#8).**
8. **Storage quota over-deletion (#9).**
9. **Rich-text stale payload (#10).**
10. Recovery rollback correctness, live content limits, HTML sanitizer ve browser/audio issues.
11. Low-level tooling/docs/maintenance temizliği.

[Kesin] İlk 8-9 madde düzeltilmeden “stable privacy-safe release” demem. Beta etiketi altında bile #1/#2/#3/#5/#6 özellikle çözülmeli; bunlar yalnız kozmetik veya edge-case değil, uygulamanın temel “clipboard verisini güvenli sakla/sil” sözleşmesine temas ediyor.

---

# İnceleme sırasında doğrulanan ama hata olmayan noktalar

- Chromium `offscreen.js` satır 2: `let nativePort = null`; reassignment geçerlidir. `const` hatası yok.
- `unsafeBitCast(-1, sqlite3_destructor_type.self)` SQLite `SQLITE_TRANSIENT` kullanım pattern’idir; tek başına vulnerability olarak işaretlenmedi.
- QuickLook delegate IUO’ları Apple Objective-C API imzalarından kaynaklanıyor; generic unsafe unwrap listesine dahil edilmedi.
- Xcode PBXSourcesBuildPhase’lerin boş olması file-system-synchronized groups kullanılan proje yapısında tek başına build bug diye işaretlenmedi.
- Main app’in sandboxed olmaması tek başına hata olarak işaretlenmedi.

---

# Nihai değerlendirme

**Kod organizasyonu / mimari:** güçlü  
**Test altyapısı:** güçlü ama önemli invariant boşlukları var  
**Storage transaction semantics:** kritik düzeltme gerekiyor  
**Encryption implementation primitives:** iyi; migration/key lifecycle semantics sorunlu  
**Privacy UX doğruluğu:** bazı iddialar mevcut implementasyondan daha güçlü  
**Clipboard correctness:** rich-text ve exclusion edge-case’leri düzeltilmeli  
**Browser/audio entegrasyonu:** çalışabilir tasarım, namespace/state semantics hardening gerekiyor  
**Release engineering:** güçlü beta tooling, evidence/docs senkronizasyonu iyileştirilmeli

**Karar:** [Kesin] Kod tabanı çöpe atılacak veya yeniden yazılacak durumda değil. Tersine temel mimari iyi. Fakat şu anki haliyle kritik storage/privacy invariant’ları yüzünden “release-ready” diye işaretlemem. En doğru yaklaşım mevcut mimariyi koruyup yukarıdaki blocker’ları hedefli patch + regression test ile kapatmak.
