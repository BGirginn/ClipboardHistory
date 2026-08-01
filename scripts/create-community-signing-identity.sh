#!/bin/zsh
set -euo pipefail

identity='ClipboardHistory Community Beta'
if security find-identity -v -p codesigning | rg -Fq "\"$identity\""; then
  print "community identity: already installed"
  exit 0
fi

login_keychain=$(
  security default-keychain -d user \
    | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//'
)
if [[ -z "$login_keychain" || ! -f "$login_keychain" ]]; then
  print -u2 "community identity: the default user Keychain could not be resolved"
  exit 1
fi

temporary_directory=$(mktemp -d /private/tmp/clipboardhistory-signing.XXXXXX)
certificate="$temporary_directory/certificate.pem"
private_key="$temporary_directory/signing-key.pem"
cleanup() {
  rm -f -- "$certificate" "$private_key"
  rmdir "$temporary_directory" 2>/dev/null || true
}
trap cleanup EXIT
umask 077

openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout "$private_key" \
  -out "$certificate" \
  -subj '/CN=ClipboardHistory Community Beta/O=ClipboardHistory Community Beta' \
  -addext 'basicConstraints=critical,CA:FALSE' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=codeSigning' \
  >/dev/null 2>&1

security import "$certificate" -k "$login_keychain" >/dev/null
security import "$private_key" -k "$login_keychain" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >/dev/null
security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$login_keychain" \
  "$certificate"

if ! security find-identity -v -p codesigning | rg -Fq "\"$identity\""; then
  print -u2 "community identity: imported certificate is not a valid code-signing identity"
  exit 1
fi

fingerprint=$(openssl x509 -in "$certificate" -noout -fingerprint -sha256 | cut -d= -f2)
print "community identity: installed and trusted for code signing"
print "community identity: SHA-256 $fingerprint"
print "community identity: export the identity from Keychain Access as an encrypted .p12 and keep it outside the repository"
