#!/bin/bash
# Build the app icon: the PNG is drawn by scripts/make-icon.swift, then packed into the .icns the
# bundle carries. Regenerate after changing the drawing, and commit the result: the bundle needs the
# file, not the toolchain that made it.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/macos/Resources/Macmon.icns
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swift "$root/scripts/make-icon.swift" "$work/icon.png"

iconset=$work/Macmon.iconset
mkdir -p "$iconset"
for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$work/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
done
# The retina entries iconutil expects.
cp "$iconset/icon_32x32.png" "$iconset/icon_16x16@2x.png"
cp "$iconset/icon_64x64.png" "$iconset/icon_32x32@2x.png"
cp "$iconset/icon_256x256.png" "$iconset/icon_128x128@2x.png"
cp "$iconset/icon_512x512.png" "$iconset/icon_256x256@2x.png"
cp "$iconset/icon_1024x1024.png" "$iconset/icon_512x512@2x.png"

iconutil -c icns "$iconset" -o "$out"
echo "==> $out"
ls -lh "$out" | awk '{print "    " $5}'
