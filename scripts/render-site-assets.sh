#!/usr/bin/env bash
# Renders every picture on the website with the app's own engine.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/site/assets"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

swift build --package-path "$root" -c release --product Griswold
bin="$(swift build --package-path "$root" -c release --show-bin-path)/Griswold"

jpeg() {  # jpeg <png> <jpg> <max-dimension>
  sips -s format jpeg -s formatOptions 84 -Z "$3" "$1" --out "$2" >/dev/null
}

# Link preview card and icons.
"$bin" --link-preview "$work/og.png" --scale 2
jpeg "$work/og.png" "$out/og.jpg" 2400
"$bin" --icon "$work/icon.png"
sips -z 512 512 "$work/icon.png" --out "$out/icon-512.png" >/dev/null
sips -z 180 180 "$work/icon.png" --out "$out/icon-180.png" >/dev/null
sips -z 64 64 "$work/icon.png" --out "$out/icon-64.png" >/dev/null

# Sprites for the live demo.
mkdir -p "$work/art"
"$bin" --dump-art "$work/art"
for name in sleigh reindeerStride reindeerGather squirrelStride squirrelGather sled; do
  cp "$work/art/$name.png" "$out/$name.png"
done

# The real interface, photographed from the running app. This opens the
# settings window and the popover on screen for a few seconds, so it only runs
# when asked for: scripts/render-site-assets.sh --ui
if [[ "${1:-}" == "--ui" ]]; then
  "$bin" --ui-shots "$work/ui"
  cp "$work/ui/ui-popover.png" "$work/ui/ui-settings-surprises.png" "$work/ui/ui-settings-snow.png" "$out/"
fi

shot() {  # shot <name> <snapshot args...>
  local name="$1"; shift
  "$bin" --snapshot "$work/$name.png" "$@"
  jpeg "$work/$name.png" "$out/$name.jpg" 1600
}

shot shot-piles     --seconds 150 --scale 3 --crop 96,128,640,400 --accumulation deep
shot shot-behind    --seconds 150 --scale 2 --layering behind --intensity 0.8 --crop 60,60,960,600
shot shot-squirrel  --seconds 120 --scale 3 --surprise squirrel --lead 1.3 --accumulation deep --crop 330,30,640,400
shot shot-sled      --seconds 120 --scale 3 --surprise sled --lead 0.5 --accumulation deep --crop 150,30,640,400
shot shot-griswold  --seconds 80  --scale 2 --surprise griswold --lead 3.95 --crop 0,0,960,600
shot shot-santa     --seconds 120 --scale 2 --surprise santa --lead 4.2 --crop 300,60,960,600
shot shot-frost     --seconds 60  --scale 2 --surprise frost --lead 22 --stroke 80,40,300,90,520,50,640,110 --crop 0,0,960,600
shot shot-presents  --seconds 120 --scale 2 --surprise presents --lead 7 --crop 90,40,960,600

strip() {  # strip <name> <height in points> <snapshot args...>
  local name="$1" height="$2"; shift 2
  "$bin" --snapshot "$work/$name.png" --seconds 40 --scale 2 --no-windows --no-menu-bar \
    --pattern steady --intensity 0.25 --top-only --crop "24,0,640,$height" "$@"
  jpeg "$work/$name.png" "$out/$name.jpg" 1280
}
strip lights-c9     62  --style c9 --palette classic
strip lights-icicle 100 --style icicle --palette icy
strip lights-star   62  --style star --palette gold

# The demo film (720p for the page) and the still shown before it plays.
"$bin" --demo-video "$out/demo.mp4" --fps 30 --scale 1 --bitrate 2600000 --poster "$work/demo-poster.png" 2>/dev/null
jpeg "$work/demo-poster.png" "$out/demo-poster.jpg" 1280

ls -la "$out"
