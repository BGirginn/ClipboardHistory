<p align="center">
  <img src="../ClipboardHistory/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" width="128" height="128" alt="ClipboardHistory uygulama ikonu">
</p>

<h1 align="center">ClipboardHistory</h1>

<p align="center">
  macOS menü çubuğu için özel ve yerel bir araç merkezi.
</p>

<p align="center">
  <a href="../README.md">English</a>
</p>

ClipboardHistory; Pano, Notlar, Giriş Araçları, Sistem Monitörü ve Ses Mikseri özelliklerini Mac'inizde yerel tutan modüler bir menü çubuğu araç merkezidir. Swift 6, SwiftUI ve AppKit ile yazılmıştır; telemetri, hesap sistemi, bulut servisi veya üçüncü taraf çalışma zamanı bağımlılığı kullanmaz.

## Güncel durum

- Güncel Community beta: [`v1.0.0-beta.2`](https://github.com/BGirginn/ClipboardHistory/releases/tag/v1.0.0-beta.2) (`1.0.0`, build `10002`)
- Desteklenen platform: macOS 14.2 veya sonrası kullanan Apple silicon (`arm64`) Mac
- `main` dalındaki kaynak kod public ve günceldir
- İmzalı ZIP, DMG, checksum, SPDX SBOM ve imza kanıtları GitHub prerelease'e eklenmiştir
- Homebrew Cask [`BGirginn/homebrew-tap`](https://github.com/BGirginn/homebrew-tap) üzerinden yayımlanmıştır
- Community yapısı self-signed'dır ve Apple tarafından notarize edilmemiştir

## Kurulum

Homebrew ile kurulum:

```sh
brew tap BGirginn/tap
brew trust BGirginn/tap
brew install --cask clipboardhistory
```

Homebrew 6, üçüncü taraf tap'ler için açık güven onayı ister. Cask kullanılmadan önce `/Applications/ClipboardHistory.app` elle kurulmuşsa ClipboardHistory'yi kapatıp mevcut uygulama paketini önce `/Applications` dışına taşıyın. Pano geçmişi Application Support altında ayrı saklandığı için bu geçişte silinmez.

Daha sonra güncellemek veya kaldırmak için:

```sh
brew update
brew upgrade --cask clipboardhistory
brew uninstall --cask clipboardhistory
```

Normal kaldırma işlemi pano geçmişini ve tercihleri korur. `brew uninstall --cask --zap clipboardhistory` komutu bu yerel kullanıcı verilerini de siler.

Community beta self-signed'dır ve notarize edilmemiştir. macOS ilk açılışı engellerse Finder'da Uygulamalar klasörünü açın, ClipboardHistory üzerinde Control-tıklayın, **Aç** seçeneğini seçip onaylayın. Aynı onay Sistem Ayarları → Gizlilik ve Güvenlik altında da verilebilir. Karantinayı `xattr` ile kaldırmayın.

ZIP ve DMG dosyaları [GitHub Release](https://github.com/BGirginn/ClipboardHistory/releases/tag/v1.0.0-beta.2) sayfasından da indirilebilir.

## Özellikler

- Metin, URL, e-posta, kaynak kod, zengin metin, görsel, PDF ve dosya/klasör geçmişi
- Tür/tarih/kaynak filtreleri, sıralama, koleksiyonlar, etiketler, sabitlenen öğeler ve parçacıklar
- Kopyalama, geri yükleme, etkin uygulamaya yapıştırma, farklı biçimde yapıştırma, Quick Look, sürükle-bırak ve toplu işlemler
- FIFO/LIFO Yapıştırma Yığını ve klavye odaklı gezinme
- Anında düzenleme, yerel arama ve otomatik kayıt sunan menü çubuğu notları
- 60 saniyelik güvenli Klavye Temizliği ile kademeli ve hassas kaydırma için ayrı dikey/yatay ayarlar sunan bağımsız Scroll Reverse modülleri
- Sistem, Açık ve Koyu görünüm seçenekleri
- Gizli Mod, geçici kayıt duraklatma ve uygulama hariç tutma
- Birleşik Kontrol Merkezi, her modül için isteğe bağlı ayrı menü çubuğu ikonu, ayarlanabilir sol tıklama eylemleri ve güvenli sağ tık menüleri
- CPU/çekirdek, RAM/bellek basıncı, CPU/SoC kalıp sıcaklığı, ağ ve aygıt bazlı disk etkinliği; birleşik veya ayrı menü çubuğu metrikleri
- macOS 14.2+ üzerinde uygulama bazlı 0–100 ses düzeyi, yetkilendirilmiş Chromium sekme yakalama ve doğrudan denetlenebilen Safari HTML medya sekmeleri
- Touch ID veya Mac oturum parolası kullanan isteğe bağlı uygulama kilidi
- Yerel gizli bilgi algılama ve hassas pano öğeleri için geçici tutma
- Açık yerel pano depolaması ve ayrı Keychain anahtarıyla AES-GCM şifreli Notlar
- Notları da içeren parola korumalı yerel arşiv dışa/içe aktarma
- Cihaz üzerinde Vision OCR, QR tanıma ve renk analizi
- İngilizce ve Türkçe yerelleştirme

## Gizlilik modeli

ClipboardHistory yalnızca `NSPasteboard` üzerinden sunulan pano değişikliklerini okur. Masaüstünü veya başka klasörleri izlemez ve pano içeriğini ağ üzerinden göndermez. Ses örnekleri, sistem metriği geçmişi, sekme başlıkları, URL'ler ve sekme kimlikleri kalıcı olarak saklanmaz.

Pano geçmişi yerel SQLite veritabanında şifrelenmeden saklanır. Not başlıkları ve gövdeleri macOS login Keychain'deki ayrı bir AES-GCM anahtarıyla korunur. İsteğe bağlı uygulama kilidi görüntüleme/etkileşim gizlilik katmanıdır; kilitliyken pano kaydı duraklatılır.

Tam sınırlar için [Gizlilik ve Tehdit Modeli](PRIVACY_AND_THREAT_MODEL.md) ile [Bilinen Sınırlar](KNOWN_LIMITATIONS.md) belgelerine bakın.

## Kaynak koddan derleme

Gereksinimler:

- Apple silicon Mac
- macOS 14.2 veya sonrası
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

ClipboardHistory menü çubuğu uygulaması olarak çalışır ve Dock'ta görünmez. Finder'dan açıldığında Kontrol Merkezi gösterilir. **Menü Çubuğunu Özelleştir** ekranından her modülü Kontrol Merkezi'ne, ayrı bir menü çubuğu ikonuna, ikisine birden veya gizli duruma alabilirsiniz; erişilebilir son ikon her zaman korunur. İkon yerleşiminden bağımsız olarak `Command-Shift-V` Panoyu doğrudan açar. Bundle içindeki yardımcı uygulama sayesinde girişte başlatma sessiz kalır.

Pano geçmişi ve yönetilen dosyalar şu konumda saklanır:

```text
~/Library/Application Support/ClipboardHistory/
```

Etkin uygulamaya doğrudan yapıştırma, Klavye Temizlik Modu ve Scroll Reverse macOS Erişilebilirlik izni ister. Pano kaydı, paneli açma, notlar ve global kısayol bu izni gerektirmez. İzin yoksa Scroll Reverse doğal kaydırmaya dokunmaz ve uygulama açılışında izin penceresini otomatik göstermez.

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

- [Mimari](ARCHITECTURE.md)
- [Testler](TESTING.md)
- [Performans](PERFORMANCE.md)
- [Dağıtım](DISTRIBUTION.md)
- [Değişiklik Günlüğü](CHANGELOG.md)
- [Güvenlik Politikası](../.github/SECURITY.md)
- [Katkıda Bulunma](../.github/CONTRIBUTING.md)

## Dağıtım

`v1.0.0-beta.2`, public GitHub prerelease ve `BGirginn/homebrew-tap` Cask'i üzerinden dağıtılır. İndirilen uygulama yalnız arm64'tür, self-signed'dır ve notarize edilmemiştir. Release checksum'ları, SPDX SBOM, designated requirement ve imza sertifikası parmak izi release'e eklenmiştir.

## Lisans

ClipboardHistory [MIT Lisansı](../LICENSE) ile sunulur.
