#!/usr/bin/env bash
# Creates a local self-signed code-signing identity for Camera Extension testing.
#
# The identity lives only in this Mac's login keychain. Re-running is safe: if the
# identity already exists it is reused, which is important because TCC/sysextd
# remember the certificate's Common Name.
set -euo pipefail

CN="${ANDROLAUNCH_SIGNING_CN:-AndroLaunch Local Dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$CN\""; then
  echo "signing identity already present: $CN"
  exit 0
fi

WORK="$(mktemp -d /tmp/androlaunch-signing.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS="androlaunch-local"

cat > "$WORK/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $CN

[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
CNF

openssl req -new -x509 -days 3650 -nodes \
  -config "$WORK/openssl.cnf" \
  -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" >/dev/null 2>&1

openssl pkcs12 -export -legacy \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$CN" -out "$WORK/identity.p12" -passout "pass:$PASS" >/dev/null 2>&1

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Trust the local root for code signing. This is a user trust setting; it may
# prompt once for the login keychain password.
security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$WORK/cert.pem" >/dev/null 2>&1 || true

echo "created local signing identity: $CN"
security find-identity -v -p codesigning | grep -F "\"$CN\"" || {
  echo "error: identity was imported but is not usable for code signing" >&2
  exit 1
}
