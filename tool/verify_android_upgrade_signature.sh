#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  printf '%s\n' 'usage: verify_android_upgrade_signature.sh OLD_APK KEYSTORE ALIAS' >&2
  exit 64
fi

if [ -z "${ELEPHANT_KEYSTORE_PASSWORD:-}" ] || [ -z "${ELEPHANT_KEY_PASSWORD:-}" ]; then
  printf '%s\n' 'ELEPHANT_KEYSTORE_PASSWORD and ELEPHANT_KEY_PASSWORD are required' >&2
  exit 64
fi

apksigner_bin="${ELEPHANT_APKSIGNER_BIN:-apksigner}"
old_apk="$1"
keystore="$2"
alias_name="$3"
temp_dir="$(mktemp -d)"
trap '/bin/rm -rf "$temp_dir"' EXIT HUP INT TERM
signed_apk="$temp_dir/signed.apk"

old_digest="$($apksigner_bin verify --print-certs "$old_apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)"
$apksigner_bin sign \
  --ks "$keystore" \
  --ks-key-alias "$alias_name" \
  --ks-pass env:ELEPHANT_KEYSTORE_PASSWORD \
  --key-pass env:ELEPHANT_KEY_PASSWORD \
  --out "$signed_apk" \
  "$old_apk"
new_digest="$($apksigner_bin verify --print-certs "$signed_apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)"

if [ -z "$old_digest" ] || [ "$old_digest" != "$new_digest" ]; then
  printf '%s\n' 'Android upgrade signature mismatch' >&2
  exit 1
fi

printf 'Android upgrade signature verified: %s\n' "$old_digest"
