# CoreDeck Community beta distribution

The latest published Community release is CoreDeck v1.0.0-beta.7 build `10007`. The source prepares beta.8 build `10009`; GitHub and Homebrew remain on beta.7 until its release gates pass. Community artifacts are self-signed, are not Apple-notarized, and must not be described as Developer ID releases.

## Stable signing identity

The release uses one self-signed `CoreDeck Community Beta` code-signing certificate. No Apple account, Development Team, or provisioning profile is involved. The private key remains outside the repository in the maintainer's login Keychain; it must never be committed or uploaded.

```sh
scripts/create-community-signing-identity.sh
scripts/verify-community-signing.sh
```

Changing the signing identity changes the designated requirement and can strand access to encrypted Notes or the key needed for one-time migration of legacy encrypted Clipboard records. The first CoreDeck-signed upgrade must exercise the interactive old-Keychain-key read and verify Notes decryption before distribution; a denied read fails closed and leaves the old key intact. Export the identity from Keychain Access as an encrypted `.p12`, store it outside the repository, and never expose its password in shell arguments, logs, chat, or CI variables.

## Release artifacts

The following command reproduces the beta.8 Community artifacts from its exact clean release commit:

```sh
scripts/build-community-artifact.sh /private/tmp/CoreDeck-1.0.0-beta.8
```

The script requires `syft` and produces:

- `CoreDeck-1.0.0-beta.8-arm64.zip`
- `CoreDeck-1.0.0-beta.8-arm64.dmg`
- `CoreDeck-1.0.0-beta.8-arm64.spdx.json`
- `CoreDeck-Chromium-Audio-1.0.0-beta.8.zip`
- `source-commit.txt`
- `SHA256SUMS`
- `designated-requirement.txt`
- `signing-certificate-sha256.txt`

It verifies `CoreDeck.app` and its `CoreDeck` executable, the `com.brgirgin.CoreDeck` bundle identifier, the code signature and designated requirement, an empty main-app entitlement set, the Safari bridge entitlement, exact `arm64` architecture, minimum macOS 14.2, version `1.0.0-beta.8` build `10009`, embedded helper/extension/XPC presence, app/extension ZIP integrity, checksums, and SPDX metadata.

The Community beta retains normal quarantine behavior. If Gatekeeper blocks first launch, document Finder Control-click → Open or System Settings → Privacy & Security → Open Anyway. Never remove quarantine, run `xattr`, or suppress the warning in the Cask.

## GitHub Release

The tag and prerelease use the same clean commit. Release assets include the ZIP, DMG, checksum manifest, SPDX SBOM, designated requirement, and public signing-certificate fingerprint. The release notes identify validation gaps without claiming notarization or unsupported OS evidence.

The automatic GitHub Quality workflow is disabled for this beta at the maintainer's request. A release must not be described as CI-validated while it remains disabled.

## Homebrew Cask

The public tap is `BGirginn/homebrew-tap`; users address it as `BGirginn/tap`. The published `clipboardhistory` Cask installs beta.7. The beta.8 candidate Cask will install its artifact after publication:

```sh
brew tap BGirginn/tap
brew trust BGirginn/tap
brew install --cask clipboardhistory
```

Homebrew 6 requires explicit trust for this third-party tap. The `coredeck` Cask token is retained for upgrades. Handle a manually installed `/Applications/CoreDeck.app` separately and preserve the existing clipboard database and preferences.

`Casks/coredeck.rb` uses the GitHub Release ZIP and its exact SHA-256 with:

```ruby
depends_on arch: :arm64
depends_on macos: :sonoma
app "CoreDeck.app"
```

The Cask changes token from `clipboardhistory` to `coredeck` with a `cask_renames.json` mapping in the same tap, so existing Homebrew installations have an upgrade path. The source repository remains `BGirginn/CoreDeck`. Normal uninstall preserves both the legacy and new Application Support directories and preferences. The optional `--zap` path removes them only when the user explicitly asks for complete deletion.

For every Cask update, run style/audit, fetch the public URL, install into an isolated app directory, verify the running artifact metadata/signature/architecture, and perform normal uninstall. The ZIP fetched by Homebrew must match the checksum published in the GitHub Release.

## Future Developer ID release

Apple signing and Keychain rationale follows [TN3137](https://developer.apple.com/documentation/Technotes/tn3137-on-mac-keychains), [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), and [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html). A future Developer ID release must use Apple's supported [notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); it is a separate release model.
