#!/bin/sh
# added by Terada: Never start TeXShop or use its production preference domain.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d /tmp/TeXShop-DockLab.XXXXXX)
app="$build/DockLab.app"
domain="org.texshop.DockLab.$(basename "$build" | tr . -)"
cleanup() {
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" >/dev/null 2>&1 || true
    defaults delete "$domain" >/dev/null 2>&1 || true
    rm -rf "$build"
}
trap cleanup EXIT HUP INT TERM
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
<key>NSDockTilePlugIn</key><string>TeXShopDockIcon.docktileplugin</string>
</dict></plist>
PLIST
xcrun clang -fobjc-arc -fmodules -framework Cocoa "$root/Tests/DockIcons.m" "$root/Sources/TSDockIconController.m" -o "$app/Contents/MacOS/DockLab"
SRCROOT="$root" TARGET_BUILD_DIR="$build" CONTENTS_FOLDER_PATH=DockLab.app/Contents TARGET_TEMP_DIR="$build/intermediate" ARCHS="$(uname -m)" SDKROOT="$(xcrun --show-sdk-path)" MACOSX_DEPLOYMENT_TARGET=14.6 sh "$root/Scripts/build-dock-icon-plugin.sh"
codesign --force --sign - "$app/Contents/PlugIns/TeXShopDockIcon.docktileplugin"
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
