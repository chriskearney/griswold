#!/usr/bin/env bash
# Builds Griswold.app (unsigned). Universal by default; pass --native for a
# quick build for this machine only.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <version> <build-number> <output-directory> [--native]" >&2
  exit 64
fi
version="$1"
build_number="$2"
output_directory="$3"
mode="${4:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must look like 1.2.3" >&2
  exit 64
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "build number must be a positive integer" >&2
  exit 64
fi

arch_flags=()
if [[ "$mode" != "--native" ]]; then
  arch_flags=(--arch arm64 --arch x86_64)
fi
swift build --package-path "$root" -c release --product Griswold ${arch_flags[@]+"${arch_flags[@]}"}
# Ask SwiftPM where it put the product: the path differs between toolchains.
binary="$(swift build --package-path "$root" -c release ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)/Griswold"
test -x "$binary"

app="$output_directory/Griswold.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Griswold"
strip -x "$app/Contents/MacOS/Griswold"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build_number/" \
  "$root/Resources/Info.plist" > "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
plutil -lint "$app/Contents/Info.plist" >/dev/null

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = "net.chonkbase.griswold"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$version"

architectures="$(lipo -archs "$app/Contents/MacOS/Griswold")"
if [[ "$mode" != "--native" ]]; then
  grep -qw arm64 <<<"$architectures"
  grep -qw x86_64 <<<"$architectures"
fi
echo "Built $app ($architectures)"
