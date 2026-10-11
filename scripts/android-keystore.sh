#!/usr/bin/env bash
# Creates the Android upload key, which signs the release builds uploaded to
# Google Play (Play re-signs them with its own app signing key), and writes
# its settings to the git-ignored tabscan_app/android/key.properties, which
# the Gradle build reads. Run it once, by hand:
#
#   bash scripts/android-keystore.sh [keystore path]
#
# The keystore defaults to ~/.android-keys/tabscan-upload.jks, outside the
# repo; keep it and its password backed up (losing them means asking Google
# for an upload key reset). It asks for the password and the name on the
# certificate. If key.properties already points to a keystore, it only
# prints the key's fingerprints: the SHA-1 for Google's Android OAuth
# client, the SHA-256 for assetlinks.json.
set -euo pipefail

cd "$(dirname "$0")/../tabscan_app/android"
props=key.properties
alias=upload

fingerprints() {
  echo "Upload key fingerprints ($1):"
  KEYSTORE_PASSWORD="$2" keytool -list -v -keystore "$1" -alias "$alias" \
    -storepass:env KEYSTORE_PASSWORD | grep -E '^\s*SHA(1|256):'
}

# prop <name>: a value from key.properties (no escapes; the file is ours).
prop() { sed -n "s/^$1=//p" "$props"; }

if [[ -f "$props" ]]; then
  ks="$(prop storeFile)"
  if [[ ! -f "$ks" ]]; then
    echo "error: $props points to $ks, which doesn't exist" >&2
    exit 1
  fi
  fingerprints "$ks" "$(prop storePassword)"
  exit 0
fi

ks="${1:-$HOME/.android-keys/tabscan-upload.jks}"
if [[ -e "$ks" ]]; then
  echo "error: $ks exists already; pass another path, or write $props for it by hand" >&2
  exit 1
fi

read -rp "Name on the certificate (e.g. your name): " name
if [[ -z "$name" || "$name" =~ [,+=\<\>#\;\"\\] ]]; then
  echo "error: give a name without , + = < > # ; \" or \\" >&2
  exit 1
fi
read -rsp "Keystore password (6+ characters, no backslash): " password; echo
read -rsp "Again: " again; echo
if [[ "$password" != "$again" ]]; then
  echo "error: the passwords don't match" >&2
  exit 1
fi
if (( ${#password} < 6 )) || [[ "$password" == *\\* || "$password" =~ ^[[:space:]] ]]; then
  echo "error: 6 or more characters, no backslash, not starting with a space" >&2
  exit 1
fi

mkdir -p "$(dirname "$ks")"
chmod 700 "$(dirname "$ks")"
# PKCS12 keeps one password for the store and the key. Valid ~27 years
# (Play wants a key valid past 2033).
KEYSTORE_PASSWORD="$password" keytool -genkeypair -keystore "$ks" \
  -storetype PKCS12 -alias "$alias" -keyalg RSA -keysize 4096 \
  -validity 10000 -dname "CN=$name" -storepass:env KEYSTORE_PASSWORD
chmod 600 "$ks"

# The password is in the clear here, as Flutter's guide has it: the file is
# git-ignored and readable only by this user.
(
  umask 077
  cat >"$props" <<EOF
storeFile=$ks
storePassword=$password
keyAlias=$alias
keyPassword=$password
EOF
)
echo "Wrote tabscan_app/android/$props; release builds are now signed with $ks"
fingerprints "$ks" "$password"
