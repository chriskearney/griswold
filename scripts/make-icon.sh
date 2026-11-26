#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the app's own renderer.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swift build --package-path "$root" -c release --product Griswold
binary="$(swift build --package-path "$root" -c release --show-bin-path)/Griswold"
"$binary" --icon "$work/icon-1024.png"

iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$root/Resources/AppIcon.icns"
echo "Wrote $root/Resources/AppIcon.icns"
