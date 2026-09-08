#!/bin/bash
set -e

APP_NAME="SennheiserFreqManager"
APP_BUNDLE="$APP_NAME.app"

echo "Building $APP_NAME..."
swift build

echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp .build/arm64-apple-macosx/debug/$APP_NAME "$APP_BUNDLE/Contents/MacOS/"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SennheiserFreqManager</string>
    <key>CFBundleIdentifier</key>
    <string>com.andiabba.sennheiser-freq-manager</string>
    <key>CFBundleName</key>
    <string>Sennheiser Freq Manager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Sennheiser Freq Manager needs local network access to discover and control Sennheiser wireless transmitters.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_sennheiser._udp.</string>
        <string>_ewg4._udp.</string>
    </array>
</dict>
</plist>
PLIST

echo "Done. Run with: open $APP_BUNDLE"
