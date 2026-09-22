#!/bin/bash
set -e

echo "[BUILD] Compiling ClipSnippet..."
swiftc -O main.swift -o ClipSnippet

echo "[PACKAGE] Packaging ClipSnippet.app..."

# 1. Create directory structure
mkdir -p ClipSnippet.app/Contents/MacOS

# 2. Copy compiled binary
cp ClipSnippet ClipSnippet.app/Contents/MacOS/ClipSnippet

# 3. Create Info.plist
cat <<EOF > ClipSnippet.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClipSnippet</string>
    <key>CFBundleIdentifier</key>
    <string>com.metrobee.clipsnippet</string>
    <key>CFBundleName</key>
    <string>ClipSnippet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.5</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSContactsUsageDescription</key>
    <string>ClipSnippet vajab ligipääsu kontaktidele, et otsida ja kopeerida telefoninumbreid ning e-posti aadresse.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ClipSnippet vajab luba Finderi ja süsteemitoimingute juhtimiseks (nt prügikasti tühjendamine ja akende haldus).</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>ClipSnippet vajab õigusi süsteemikäskude täitmiseks.</string>
</dict>
</plist>
EOF

# 4. Sign the app bundle with stable designated requirement
codesign --force --deep --sign - --requirements '=designated => identifier "com.metrobee.clipsnippet"' ClipSnippet.app

# 5. Deploy to /Applications
rm -rf /Applications/ClipSnippet.app
cp -R ClipSnippet.app /Applications/ClipSnippet.app
codesign --force --deep --sign - --requirements '=designated => identifier "com.metrobee.clipsnippet"' /Applications/ClipSnippet.app

# 6. Create release zip
rm -f ClipSnippet.zip
zip -r -y -q ClipSnippet.zip ClipSnippet.app

# 7. The local ClipSnippet.app carries the same CFBundleIdentifier as the
#    /Applications copy. If Launch Services indexes both, `open` (used by
#    the LaunchAgent to start the app) can resolve to whichever one it
#    registered last, ignoring the literal path argument - so unregister
#    the local copy right after packaging to keep /Applications the only
#    resolvable target for com.metrobee.clipsnippet.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$(pwd)/ClipSnippet.app" 2>/dev/null || true
"$LSREGISTER" -f /Applications/ClipSnippet.app 2>/dev/null || true

echo "[SUCCESS] ClipSnippet.app packaged, deployed to /Applications, and signed successfully."
echo "[INFO] SHA256: $(shasum -a 256 ClipSnippet.zip | awk '{print $1}')"
