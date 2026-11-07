#!/bin/sh
# Never start TeXShop or use its production preference domain.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d /tmp/TeXShop-DockLab.XXXXXX)
app="$build/DockLab.app"
domain="org.texshop.DockLab.$(basename "$build" | tr . -)"
cleanup() {
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" >/dev/null 2>&1 || true
    rm -rf "$build"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R "$root/Resources/DockIcons" "$app/Contents/Resources/"
cp "$root/Artwork/TeXShop.icns" "$app/Contents/Resources/TeXShop.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$domain</string>
<key>CFBundleExecutable</key><string>DockLab</string>
<key>LSUIElement</key><true/>
<key>CFBundleName</key><string>DockLab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>TeXShop</string>
</dict></plist>
PLIST
python3 "$root/Tests/extract-dock-preferences.py" "$build/PreferenceCancel.h"
test_source="$root/Tests/DockIcons.m"
if [ "${1:-}" = --mutation-persistent-defaults ]; then
    python3 - "$test_source" "$build/DockIcons.m" <<'PYM'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
line='    method_setImplementation(class_getClassMethod(NSUserDefaults.class,@selector(standardUserDefaults)),(IMP)InMemoryStandardDefaults);'
assert s.count(line)==1
Path(sys.argv[2]).write_text(s.replace(line,''))
PYM
    test_source="$build/DockIcons.m"
fi
xcrun clang -I"$root/Tests" -I"$build" -fobjc-arc -fmodules -framework Cocoa "$test_source" "$root/Sources/TSDockIconController.m" -o "$app/Contents/MacOS/DockLab"
codesign --force --sign - "$app"
if [ "${1:-}" = --snapshot ]; then
    "$app/Contents/MacOS/DockLab" "$root/Resources/Interfaces/${2:-ja}.lproj/Preferences.nib" --snapshot "$3" -AppleLanguages "(${2:-ja})"
elif [ "${1:-}" = --preview ]; then
    echo "$app"
    "$app/Contents/MacOS/DockLab" "$root/Resources/Interfaces/${2:-ja}.lproj/Preferences.nib" --preview -AppleLanguages "(${2:-ja})"
else
    for language in "$root"/Resources/Interfaces/*.lproj; do
        [ -d "$language/Preferences.nib" ] || continue
        echo "Testing $(basename "$language")"
        "$app/Contents/MacOS/DockLab" "$language/Preferences.nib"
    done
fi
