<p align="center">
  <img src="ClipboardHistory/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" width="128" height="128" alt="ClipboardHistory uygulama ikonu">
</p>

<h1 align="center">ClipboardHistory</h1>

<p align="center">
  macOS menü çubuğu için özel ve yerel bir pano yöneticisi.
</p>

<p align="center">
  <a href="README.md">English</a>
</p>

ClipboardHistory, aranabilir pano geçmişini yalnızca Mac'inizde tutar. Swift 6, SwiftUI ve AppKit ile yazılmıştır; ağ bağlantısı, telemetri, hesap sistemi, bulut servisi veya üçüncü taraf çalışma zamanı bağımlılığı kullanmaz.

## Güncel durum

- Güncel Community beta: [`v1.0.0-beta.1`](https://github.com/BGirginn/ClipboardHistory/releases/tag/v1.0.0-beta.1) (`1.0.0`, build `10001`)
- Desteklenen platform: macOS 14 Sonoma veya sonrası kullanan Apple silicon (`arm64`) Mac
- `main` dalındaki kaynak kod public ve günceldir
- İmzalı ZIP, DMG, checksum, SPDX SBOM ve imza kanıtları GitHub prerelease'e eklenmiştir
- Homebrew Cask [`BGirginn/homebrew-tap`](https://github.com/BGirginn/homebrew-tap) üzerinden yayımlanmıştır
- Community yapısı self-signed'dır ve Apple tarafından notarize edilmemiştir

## Kurulum

Homebrew ile kurulum:

```sh
brew tap BGirginn/tap
brew install --cask clipboardhistory
```

Daha sonra güncellemek veya kaldırmak için:

```sh
brew update
brew upgrade --cask clipboardhistory
brew uninstall --cask clipboardhistory
```

Normal kaldırma işlemi pano geçmişini ve tercihleri korur. `brew uninstall --cask --zap clipboardhistory` komutu bu yerel kullanıcı verilerini de siler.

Community beta self-signed'dır ve notarize edilmemiştir. macOS ilk açılışı engellerse Finder'da Uygulamalar klasörünü açın, ClipboardHistory üzerinde Control-tıklayın, **Aç** seçeneğini seçip onaylayın. Aynı onay Sistem Ayarları → Gizlilik ve Güvenlik altında da verilebilir. Karantinayı `xattr` ile kaldırmayın.

ZIP ve DMG dosyaları [GitHub Release](https://github.com/BGirginn/ClipboardHistory/releases/tag/v1.0.0-beta.1) sayfasından da indirilebilir.

## Özellikler

- Metin, URL, e-posta, kaynak kod, zengin metin, görsel, PDF ve dosya/klasör geçmişi
- Arama, tür/tarih/kaynak filtreleri, sıralama, koleksiyonlar, etiketler, sabitlenen öğeler ve parçacıklar
- Kopyalama, geri yükleme, etkin uygulamaya yapıştırma, farklı biçimde yapıştırma, Quick Look, sürükle-bırak ve toplu işlemler
- FIFO/LIFO Yapıştırma Yığını ve klavye odaklı gezinme
- Sistem, Açık ve Koyu görünüm seçenekleri
- Private Mode, geçici kayıt duraklatma, uygulama hariç tutma ve Sonraki Kopyalamayı Yoksay seçimi
- Touch ID veya Mac oturum parolası kullanan isteğe bağlı uygulama kilidi
- Yerel gizli bilgi algılama ve hassas pano öğeleri için geçici tutma
- Keychain anahtarlı AES-GCM geçmiş şifrelemesi ve plaintext'e düşmeyen hata davranışı
- Parola korumalı yerel arşiv dışa/içe aktarma
- Cihaz üzerinde Vision OCR, QR tanıma ve renk analizi
- İngilizce ve Türkçe yerelleştirme

## Gizlilik modeli

ClipboardHistory yalnızca `NSPasteboard` üzerinden sunulan pano değişikliklerini okur. Masaüstünü veya başka klasörleri izlemez ve pano içeriğini ağ üzerinden göndermez.

Geçmiş yerel SQLite veritabanında saklanır. Şifreleme anahtarları macOS login Keychain'de tutulur; Keychain hatalarında işlem kapalı ve güvenli biçimde başarısız olur. İsteğe bağlı uygulama kilidi görüntüleme/etkileşim gizlilik katmanıdır ve varsayılan olarak kapalıdır.

Tam sınırlar için [Gizlilik ve Tehdit Modeli](docs/PRIVACY_AND_THREAT_MODEL.md) ile [Bilinen Sınırlar](docs/KNOWN_LIMITATIONS.md) belgelerine bakın.

## Kaynak koddan derleme

Gereksinimler:

- Apple silicon Mac
- macOS 14 veya sonrası
- Swift 6 destekli Xcode

Depoyu klonlayıp yerel self-signed Community kimliğini oluşturun. Bunun için ücretli Apple Developer hesabı gerekmez:

```sh
git clone https://github.com/BGirginn/ClipboardHistory.git
cd ClipboardHistory
scripts/create-community-signing-identity.sh
scripts/verify-community-signing.sh
```

Community yapılandırmasını derleyip açın:

```sh
xcodebuild \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration CommunityRelease \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build/LocalRelease \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='ClipboardHistory Community Beta' \
  build

open .build/LocalRelease/Build/Products/CommunityRelease/ClipboardHistory.app
```

Sertifikanın private key'i kullanıcının login Keychain'inde kalır ve repoya kesinlikle eklenmemelidir.

## Kullanım

ClipboardHistory menü çubuğu uygulaması olarak çalışır ve Dock'ta görünmez. Paneli açmak için pano ikonuna tıklayın veya `Command-Shift-V` tuşlarına basın.

Pano geçmişi ve yönetilen dosyalar şu konumda saklanır:

```text
~/Library/Application Support/ClipboardHistory/
```

Etkin uygulamaya doğrudan yapıştırma işlemi macOS Erişilebilirlik izni ister. Pano kaydı, paneli açma ve global kısayol bu izni gerektirmez.

## Geliştirme

İmzasız derleme kontrolü:

```sh
xcodebuild \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Proje belgeleri:

- [Mimari](docs/ARCHITECTURE.md)
- [Testler](docs/TESTING.md)
- [Performans](docs/PERFORMANCE.md)
- [Dağıtım](docs/DISTRIBUTION.md)
- [Güvenlik Politikası](SECURITY.md)
- [Katkıda Bulunma](CONTRIBUTING.md)

## Dağıtım

`v1.0.0-beta.1`, public GitHub prerelease ve `BGirginn/homebrew-tap` Cask'i üzerinden dağıtılır. İndirilen uygulama yalnız arm64'tür, self-signed'dır ve notarize edilmemiştir. Release checksum'ları, SPDX SBOM, designated requirement ve imza sertifikası parmak izi release'e eklenmiştir.

## Lisans

ClipboardHistory [MIT Lisansı](LICENSE) ile sunulur.
