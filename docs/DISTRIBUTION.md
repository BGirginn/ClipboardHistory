# Community beta distribution

`v1.0.0-beta.3` is a public Community prerelease for Apple silicon Macs running macOS 14.2 or later. Distribution is complete only when the GitHub artifacts and matching Homebrew Cask are both available. Community artifacts are self-signed, are not Apple-notarized, and must not be described as production or Developer ID releases.

## Stable signing identity

The release uses one self-signed `ClipboardHistory Community Beta` code-signing certificate. No Apple account, Development Team, or provisioning profile is involved. The private key remains outside the repository in the maintainer's login Keychain; it must never be committed or uploaded.

```sh
scripts/create-community-signing-identity.sh
scripts/verify-community-signing.sh
```

Changing the signing identity changes the designated requirement and can strand access to encrypted Notes or the key needed for one-time migration of legacy encrypted Clipboard records. Export the identity from Keychain Access as an encrypted `.p12`, store it outside the repository, and never expose its password in shell arguments, logs, chat, or CI variables.

## Release artifacts

Build from the exact clean release commit:

```sh
scripts/build-community-artifact.sh /private/tmp/ClipboardHistory-1.0.0-beta.3
```

The script requires `syft` and produces:

- `ClipboardHistory-1.0.0-beta.3-arm64.zip`
- `ClipboardHistory-1.0.0-beta.3-arm64.dmg`
- `ClipboardHistory-1.0.0-beta.3-arm64.spdx.json`
- `SHA256SUMS`
- `designated-requirement.txt`
- `signing-certificate-sha256.txt`

It verifies the code signature and designated requirement, an empty final entitlement set, exact `arm64` architecture, minimum macOS 14.2, version `1.0.0` build `10003`, DMG and ZIP integrity, checksums, and SPDX metadata.

The Community beta retains normal quarantine behavior. If Gatekeeper blocks first launch, document Finder Control-click → Open or System Settings → Privacy & Security → Open Anyway. Never remove quarantine, run `xattr`, or suppress the warning in the Cask.

## GitHub Release

The tag and prerelease are published from the same clean commit. Release assets include the ZIP, DMG, checksum manifest, SPDX SBOM, designated requirement, and public signing-certificate fingerprint. The release notes link the known validation gaps rather than claiming notarization or unsupported OS evidence.

## Homebrew Cask

The public tap is `BGirginn/homebrew-tap`; users address it as `BGirginn/tap`:

```sh
brew tap BGirginn/tap
brew trust BGirginn/tap
brew install --cask clipboardhistory
```

Homebrew 6 requires explicit trust for this third-party tap. A manually installed `/Applications/ClipboardHistory.app` must be quit and moved aside before the first Cask install; Homebrew intentionally refuses to overwrite an unmanaged application bundle. This does not remove the separately stored clipboard database or preferences.

`Casks/clipboardhistory.rb` uses the GitHub Release ZIP and its exact SHA-256 with:

```ruby
depends_on arch: :arm64
depends_on macos: :sonoma
app "ClipboardHistory.app"
```

Normal uninstall preserves Application Support and preferences. The optional `--zap` path removes them only when the user explicitly asks for complete deletion.

For every Cask update, run style/audit, fetch the public URL, install into an isolated app directory, verify the running artifact metadata/signature/architecture, and perform normal uninstall. The ZIP fetched by Homebrew must match the checksum published in the GitHub Release.

## Future Developer ID release

Apple signing and Keychain rationale follows [TN3137](https://developer.apple.com/documentation/Technotes/tn3137-on-mac-keychains), [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), and [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html). A future Developer ID release must use Apple's supported [notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); it is a separate release model.
