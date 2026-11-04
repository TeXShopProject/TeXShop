#!/bin/sh
# added by Terada: Build the experimental non-App-Store Dock plug-in.
set -eu
plugin="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/PlugIns/TeXShopDockIcon.docktileplugin"
stage="$TARGET_TEMP_DIR/TeXShopDockIcon.docktileplugin"
mkdir -p "$stage/Contents/MacOS"
set --
for arch in $ARCHS; do set -- "$@" -arch "$arch"; done
xcrun clang "$@" -isysroot "$SDKROOT" -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
  -fobjc-arc -fmodules -bundle -framework Cocoa \
  "$SRCROOT/Sources/DockIconPlugin/TSDockIconPlugin.m" -o "$stage/Contents/MacOS/TeXShopDockIcon"
cat > "$stage/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TeXShopDockIcon</string>
<key>CFBundleIdentifier</key><string>org.texshop.TeXShop.DockIcon</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSPrincipalClass</key><string>TSDockIconPlugin</string>
</dict></plist>
PLIST
mkdir -p "$(dirname "$plugin")"
ditto "$stage" "$plugin"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$plugin"
fi
