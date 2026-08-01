# Community beta distribution

Distribution remains disabled until every row in [TESTING.md](TESTING.md) passes for the exact commit. Do not create `v1.0.0-beta.1`, a GitHub Release, or a Cask from a merely successful build.

## Stable signing identity

Create one self-signed `ClipboardHistory Community Beta` code-signing certificate, retain its encrypted backup outside the repository, and use that same identity for every update. No Apple account, Development Team, or provisioning profile is involved. Never commit or upload the private key. Every runnable configuration has the same empty entitlement file and login-Keychain service; changing the designated requirement can strand access to the existing key.

```sh
scripts/create-community-signing-identity.sh
scripts/verify-community-signing.sh
```

After creation, export exactly this identity from Keychain Access as an encrypted `.p12` and store the backup outside the repository. Do not send its password through shell arguments, chat, logs, or CI variables.

Build artifacts only after local release gates pass:

```sh
scripts/release-gate.sh /private/tmp/ClipboardHistoryCombined.xcresult
scripts/build-community-artifact.sh /private/tmp/ClipboardHistory-1.0.0-beta.1
```

The artifact script requires `syft` and creates the arm64-only app, `ClipboardHistory-1.0.0-beta.1-arm64.zip`, matching DMG, SHA-256 manifest, SPDX SBOM, designated requirement, and public certificate fingerprint. It verifies that `lipo -archs` is exactly `arm64`, the minimum OS is macOS 14, and the embedded version is `1.0.0` build `10001` with beta label `1.0.0-beta.1`.

The Community beta is self-signed and not notarized. Test the exact downloaded, quarantined artifact in a clean account/VM. Document macOS System Settings > Privacy & Security > Open Anyway with the expected certificate fingerprint. Never remove quarantine, run `xattr`, or hide Gatekeeper warnings in an installer or Cask.

## GitHub Release and Homebrew

Release notes must link the test/coverage/security/accessibility/performance evidence and publish the checksum, SBOM, fingerprint, and known limitations. Only then create and push the annotated tag.

After the immutable GitHub Release URL exists, add `Casks/clipboardhistory.rb` to `BGirginn/homebrew-tap` with the real ZIP SHA-256, `app "ClipboardHistory.app"`, `depends_on arch: :arm64`, and `depends_on macos: :sonoma`. Normal uninstall must preserve Application Support and preferences. A separately documented `zap` stanza may remove history, preferences, and caches only when the user explicitly requests `--zap`.

Run `brew audit --cask --strict`, install, upgrade, uninstall, reinstall, and a clean-user launch from the Cask. Record the running PID's exact executable, bundle/build versions, signature/designated requirement, login-Keychain read, and SQLite `PRAGMA integrity_check`. The ZIP downloaded by Homebrew must match the GitHub checksum byte-for-byte.

Apple signing/Keychain rationale follows [TN3137](https://developer.apple.com/documentation/Technotes/tn3137-on-mac-keychains), [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), and [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html). A future Developer ID release must use Apple's supported [notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); it is a separate release model.
