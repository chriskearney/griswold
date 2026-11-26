#!/usr/bin/env bash
# Signs Griswold.app with a Developer ID, packs it into a disk image, and has
# Apple notarize and staple it. Set MAC_SIGNING_IDENTITY=- for a local ad hoc
# build that skips notarization.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <app-path> <version> <output-directory>" >&2
  exit 64
fi
app_path="$1"
version="$2"
output_directory="$3"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keychain_path="${MAC_KEYCHAIN_PATH:-}"
identity="${MAC_SIGNING_IDENTITY:-}"

if [[ -z "$identity" ]]; then
  echo "MAC_SIGNING_IDENTITY is required (use - for ad hoc)" >&2
  exit 1
fi
adhoc=false
if [[ "$identity" == "-" ]]; then adhoc=true; fi
if ! $adhoc; then
  for variable in APP_STORE_CONNECT_API_KEY_PATH APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID; do
    if [[ -z "${!variable:-}" ]]; then
      echo "required notarization variable is missing: $variable" >&2
      exit 1
    fi
  done
  test -f "$APP_STORE_CONNECT_API_KEY_PATH"
fi
test -d "$app_path"
mkdir -p "$output_directory"

# Griswold is a single executable. Refuse to ship nested code that this script
# would not sign correctly.
if find "$app_path/Contents" -mindepth 1 \( -name '*.framework' -o -name '*.xpc' -o -name '*.dylib' -o -name '*.bundle' \) -print -quit | grep -q .; then
  echo "unexpected nested code found; extend the signing steps first" >&2
  exit 1
fi

codesign_args=(--force --options runtime --sign "$identity")
if ! $adhoc; then codesign_args+=(--timestamp); fi
if [[ -n "$keychain_path" ]]; then codesign_args+=(--keychain "$keychain_path"); fi

xattr -cr "$app_path"
codesign "${codesign_args[@]}" "$app_path"
codesign --verify --strict=all --verbose=2 "$app_path"

details="$(codesign -dvv "$app_path" 2>&1)"
grep -q 'flags=.*runtime' <<<"$details"
if ! $adhoc; then
  authority="$(awk -F= '/^Authority=/ {print $2; exit}' <<<"$details")"
  if [[ "$authority" != "Developer ID Application:"* ]]; then
    echo "unexpected signing authority: ${authority:-none}" >&2
    exit 1
  fi
fi

dmg_path="$output_directory/Griswold-${version}.dmg"
"$root/scripts/make-dmg.sh" "$app_path" "$dmg_path"
hdiutil verify "$dmg_path" >/dev/null

if $adhoc; then
  shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
  echo "Ad hoc signed (not notarized): $dmg_path"
  exit 0
fi

dmg_codesign_args=(--force --timestamp --sign "$identity")
if [[ -n "$keychain_path" ]]; then dmg_codesign_args+=(--keychain "$keychain_path"); fi
codesign "${dmg_codesign_args[@]}" "$dmg_path"
codesign --verify --verbose=2 "$dmg_path"

notary_args=(--key "$APP_STORE_CONNECT_API_KEY_PATH" --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID")
submission_json="$output_directory/notary-submit.json"
xcrun notarytool submit "$dmg_path" "${notary_args[@]}" --wait --output-format json > "$submission_json"

field() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$submission_json" "$1"
}
if [[ "$(field status)" != "Accepted" ]]; then
  submission_id="$(field id)"
  echo "notarization failed for submission ${submission_id:-unknown}" >&2
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" "${notary_args[@]}" || true
  fi
  exit 1
fi

xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
echo "Signed, notarized, and stapled: $dmg_path"
