#!/bin/bash
# added by Terada: Verify invisible-character rendering without launching TeXShop.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d /tmp/texshop-invisible.XXXXXX)"
trap 'rm -rf "$output"' EXIT
# Use the real preference key definitions rather than aliases in the fixture.
python3 - "$root" "$output" <<'KEYS'
from pathlib import Path
import re, sys
source = (Path(sys.argv[1]) / 'Sources/globals.m').read_text(encoding='latin1')
keys = re.findall(r'^NSString \*(?:show(?:Space|FullwidthSpace|Tab|NewLine)CharacterKey|(?:Space|FullwidthSpace|Tab|NewLine)CharacterKindKey)\s*=.*?;', source, re.M)
assert len(keys) == 8
(Path(sys.argv[2]) / 'MarkerKeys.h').write_text('\n'.join(keys))
KEYS
set -- "${1:?Specify an output PNG path}"
xcrun clang -fobjc-arc -framework Cocoa -I "$root/Sources" -I "$output" "$root/Tests/InvisibleCharacterBaseline.m" "$root/Sources/TSLayoutManager.m" -o "$output/test"
# Verify independence from NSString drawing compatibility tied to the minimum OS declaration.
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
