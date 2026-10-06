#!/usr/bin/env bash
# Creates the Google Play upload key on this machine and stores it, with its
# password, as GitHub Actions secrets for .github/workflows/android.yml.
#
#   scripts/setup-android-signing.sh [owner/repo]
#
# Needs: keytool (any JDK), openssl, and the GitHub CLI logged in with admin
# rights on the repository (`gh auth login`).
#
# The key never leaves this machine except as an encrypted GitHub secret.
# Back up the output folder: every future Play update must be signed with the
# same upload key (Google can reset a lost one, but only via support).
set -euo pipefail

REPO="${1:-kapetaltd/background-remover}"
OUT_DIR="${CUTOUT_SIGNING_DIR:-$HOME/cutout-signing}"
ALIAS="upload"
KEYSTORE="$OUT_DIR/upload-keystore.jks"
CREDENTIALS="$OUT_DIR/credentials.txt"

for cmd in keytool openssl gh; do
  command -v "$cmd" >/dev/null || { echo "error: '$cmd' is not installed." >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "error: run 'gh auth login' first." >&2; exit 1; }

if [ -e "$KEYSTORE" ]; then
  echo "error: $KEYSTORE already exists. Refusing to replace an upload key." >&2
  echo "Move it away first if you really mean to create a new one." >&2
  exit 1
fi

umask 077
mkdir -p "$OUT_DIR"

# One random password for both store and key (PKCS12 requires they match).
CUTOUT_KEY_PASSWORD="$(openssl rand -base64 32 | tr -d '/+=\n' | cut -c1-32)"
export CUTOUT_KEY_PASSWORD

echo "Creating upload key in $KEYSTORE ..."
keytool -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 \
  -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass:env CUTOUT_KEY_PASSWORD -keypass:env CUTOUT_KEY_PASSWORD \
  -dname "CN=Cutout, O=Kapeta Ltd" >/dev/null

FINGERPRINT="$(keytool -list -v -keystore "$KEYSTORE" -alias "$ALIAS" \
  -storepass:env CUTOUT_KEY_PASSWORD | grep -m1 'SHA256:' | sed 's/^[[:space:]]*//')"

cat >"$CREDENTIALS" <<EOF
Cutout Play upload key ($(date -u +%Y-%m-%d))
keystore:  $KEYSTORE
alias:     $ALIAS
password:  $CUTOUT_KEY_PASSWORD   (store and key)
$FINGERPRINT
EOF

# Values go to gh on stdin, so they never appear in the process list.
set_secret() { printf '%s' "$2" | gh secret set "$1" --repo "$REPO" >/dev/null; echo "  set $1"; }

echo "Storing secrets in $REPO ..."
set_secret ANDROID_UPLOAD_KEYSTORE_BASE64 "$(openssl base64 -A -in "$KEYSTORE")"
set_secret ANDROID_UPLOAD_STORE_PASSWORD "$CUTOUT_KEY_PASSWORD"
set_secret ANDROID_UPLOAD_KEY_ALIAS "$ALIAS"
set_secret ANDROID_UPLOAD_KEY_PASSWORD "$CUTOUT_KEY_PASSWORD"

cat <<EOF

Done. The next push builds a Play-signed bundle.

Back up this folder somewhere safe (password manager, encrypted drive):
  $OUT_DIR
Upload key $FINGERPRINT
EOF
