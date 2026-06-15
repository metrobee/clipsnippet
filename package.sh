#!/bin/bash
set -e

echo "📦 Packaging ClipSnippet.app..."

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
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
EOF
# 4. Sign the app bundle ad-hoc to satisfy macOS security requirements
codesign --force --deep --sign - ClipSnippet.app

echo "✅ ClipSnippet.app packaged and signed successfully!"
