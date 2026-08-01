#!/bin/zsh
set -euo pipefail

identity='ClipboardHistory Community Beta'
matches=$(security find-identity -v -p codesigning | rg -F "\"$identity\"" || true)
count=$(wc -l <<<"$matches" | tr -d ' ')
if [[ -z "$matches" || "$count" -ne 1 ]]; then
  print -u2 "community signing gate: expected exactly one valid identity named $identity"
  exit 1
fi

certificate=$(mktemp /private/tmp/clipboardhistory-community-certificate.XXXXXX)
trap 'rm -f -- "$certificate"' EXIT
security find-certificate -c "$identity" -p >"$certificate"

openssl x509 -in "$certificate" -noout -checkend 2592000 >/dev/null || {
  print -u2 "community signing gate: certificate expires within 30 days"
  exit 1
}
openssl x509 -in "$certificate" -noout -text | rg -Fq 'Code Signing' || {
  print -u2 "community signing gate: certificate lacks the Code Signing extended key usage"
  exit 1
}
subject=$(openssl x509 -in "$certificate" -noout -subject -nameopt RFC2253 | sed 's/^subject= //')
issuer=$(openssl x509 -in "$certificate" -noout -issuer -nameopt RFC2253 | sed 's/^issuer= //')
if [[ "$subject" != "$issuer" ]]; then
  print -u2 "community signing gate: certificate is not self-signed"
  exit 1
fi
security verify-cert -c "$certificate" -p codeSign >/dev/null || {
  print -u2 "community signing gate: certificate is not trusted for code signing"
  exit 1
}

fingerprint=$(openssl x509 -in "$certificate" -noout -fingerprint -sha256 | cut -d= -f2)
print "community signing gate: one valid self-signed code-signing identity is installed"
print "community signing gate: SHA-256 $fingerprint"
