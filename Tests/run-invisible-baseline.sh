#!/bin/bash
# added by Terada: Verify invisible-character rendering without launching TeXShop.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d /tmp/texshop-invisible.XXXXXX)"
trap 'rm -rf "$output"' EXIT
extra=()
if test -f "$root/Sources/TSATSTypesetter.m"; then extra+=("$root/Sources/TSATSTypesetter.m"); fi
xcrun clang -fobjc-arc -framework Cocoa -I "$root/Sources" "$root/Tests/InvisibleCharacterBaseline.m" "$root/Sources/TSLayoutManager.m" "${extra[@]}" -o "$output/test"
# 最低OS宣言によるNSString描画の互換動作にも影響されないことを確認する。
mkdir -p "$output/Probe.app/Contents/MacOS"
mv "$output/test" "$output/Probe.app/Contents/MacOS/Probe"
for minimum in 10.13.0 14.6; do
    cat > "$output/Probe.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Probe</string>
<key>CFBundleIdentifier</key><string>org.texshop.invisible-baseline-test</string>
<key>LSMinimumSystemVersion</key><string>$minimum</string>
</dict></plist>
EOF
    "$output/Probe.app/Contents/MacOS/Probe" "$output/$minimum.png"
done
cmp "$output/10.13.0.png.pixels" "$output/14.6.png.pixels"
cp "$output/14.6.png" "${1:?PNG出力パスを指定してください}"
echo 'PASS: 最低OS宣言を変更しても描画ピクセルは一致'
