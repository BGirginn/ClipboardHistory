# ClipboardHistory

ClipboardHistory, Swift 6 ve SwiftUI/AppKit ile yazılmış yerel bir macOS pano yöneticisidir. Ağ bağlantısı, telemetri, hesap, bulut eşitleme veya üçüncü taraf çalışma zamanı bağımlılığı kullanmaz.

## Durum

Depo şu anda `v1.0.0-beta.1` öncesi geliştirme aşamasındadır. Yerel arm64 kanıtı 204 unit/integration/benchmark ve 7 yalıtılmış UI testini kapsar. Her üretim Swift dosyası ve uygulama toplamı `%100` satır kapsamındadır (11.880/11.880); Debug, Release ve CommunityRelease minimum macOS 14 isteyen yalnız arm64 yapılardır; ASan ve TSan 203 uygun testi ayrı ayrı geçirir; optimize p95 eşiği geçer ve 7 kritik mutasyonun tamamı öldürülür. Sabit self-signed Community kimliğiyle üretilen entitlement'sız `1.0.0 (10001)` artifact Apple hesabı/profile olmadan imza, designated requirement, mimari, checksum, DMG ve SPDX kontrollerini geçer. Xcode UI otomasyonu Debug uygulaması self-signed olduğunda başlatma el sıkışmasını tamamlayamadığı için temiz kullanıcıda manuel UI/Gatekeeper kanıtı; erişilebilirlik/görsel matris, sekiz saatlik soak/Instruments, macOS 14/15/26 ve şifreli imza anahtarı yedeği hâlâ zorunludur. Beta etiketi, GitHub Release'i ve Homebrew Cask yayımlanmamıştır.

## Başlıca özellikler

- Metin, RTF, temizlenmiş HTML, görsel grubu, PDF ve dosya/klasör geçmişi
- Panoya kopyalama, etkin uygulamaya doğrudan yapıştırma ve düz metin/RTF/temiz HTML olarak yapıştırma
- Renk algılama, cihaz üzerinde Vision OCR ve QR kod çözme
- Şifreli görünen adlar, etiketler, koleksiyonlar ve sabit parçacıklar
- FIFO/LIFO geçici Yapıştırma Yığını, çoklu seçim, toplu silme ve yaşa göre temizlik
- Kaynak uygulama, tür, tarih, koleksiyon, etiket ve tanınan metin alanlarında arama
- Geçici/gizli/otomatik UTI'ları ve isteğe bağlı Universal Clipboard/özel UTI'ları yok sayma
- Sistem/Açık/Koyu görünüm, özelleştirilebilir global kısayol, menü popover'ı ve ayrılabilir kenar paneli
- AES-GCM, Keychain anahtarı, varsayılan kapalı sistem kimlik doğrulamalı uygulama kilidi ve parola korumalı arşiv
- İngilizce ve Türkçe String Catalog

## Geliştirme

Yalnız Apple silicon arm64 ve macOS 14+ hedeflenir; Xcode 26.6 ile Swift 6 strict concurrency doğrulanır. İmzasız komut satırı derlemesi:

```sh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

Statik ve yerelleştirme kapısı:

```sh
scripts/verify-static-quality.sh
```

Test ve yayın ölçütleri için [beta hazırlık raporu](docs/BETA_READINESS_REPORT.md), [İngilizce README](README.md), [test matrisi](docs/TESTING.md), [gizlilik ve tehdit modeli](docs/PRIVACY_AND_THREAT_MODEL.md) ve [bilinen sınırlar](docs/KNOWN_LIMITATIONS.md) belgelerine bakın.
