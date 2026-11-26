#!/usr/bin/env bash
# Packs Griswold.app into a disk image. Uses dmgbuild for the styled window
# when it is installed, and falls back to a plain image otherwise.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <app-path> <output.dmg>" >&2
  exit 64
fi
app_path="$1"
dmg_path="$2"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/griswold-dmg.XXXXXX")"
trap 'rm -rf "$work"' EXIT
rm -f "$dmg_path"

python="${DMGBUILD_PYTHON:-python3}"
if "$python" -c 'import dmgbuild' >/dev/null 2>&1; then
  tiffutil -cathidpicheck "$root/Resources/dmg-background.png" "$root/Resources/dmg-background@2x.png" \
    -out "$work/background.tiff" >/dev/null
  if "$python" -m dmgbuild -s "$root/scripts/dmg-settings.py" \
      -D app="$app_path" -D background="$work/background.tiff" "Griswold" "$dmg_path"; then
    echo "Built styled disk image: $dmg_path"
    exit 0
  fi
  echo "dmgbuild failed; falling back to a plain disk image" >&2
  rm -f "$dmg_path"
fi

ditto "$app_path" "$work/stage/Griswold.app"
ln -s /Applications "$work/stage/Applications"
hdiutil create -volname "Griswold" -srcfolder "$work/stage" -ov -format UDZO "$dmg_path"
echo "Built plain disk image: $dmg_path"
