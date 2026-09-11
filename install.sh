#!/bin/bash
set -e

APP_NAME="Sennheiser Freq Manager"
BUNDLE_NAME="SennheiserFreqManager"
INSTALL_DIR="/Applications"

echo "=== $APP_NAME Installer ==="
echo ""

# Check for Xcode command line tools
if ! xcode-select -p &>/dev/null; then
    echo "Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "Please re-run this script after installation completes."
    exit 1
fi

# Check for xcodegen
if ! command -v xcodegen &>/dev/null; then
    echo "xcodegen not found. Installing via Homebrew..."
    if ! command -v brew &>/dev/null; then
        echo "Error: Homebrew is required. Install from https://brew.sh"
        exit 1
    fi
    brew install xcodegen
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Generating Xcode project..."
xcodegen generate

echo "Building Release..."
xcodebuild -project "$BUNDLE_NAME.xcodeproj" \
    -scheme "$BUNDLE_NAME" \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    clean build 2>&1 | tail -5

BUILD_APP="build/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$BUILD_APP" ]; then
    echo "Error: Build failed. App not found at $BUILD_APP"
    exit 1
fi

echo ""
echo "Installing to $INSTALL_DIR..."

# Remove old version if exists
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "Removing previous version..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

cp -R "$BUILD_APP" "$INSTALL_DIR/"

# Remove quarantine attribute so Gatekeeper doesn't block it
xattr -cr "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

# Clean up build directory
rm -rf build

echo ""
echo "=== Installed successfully! ==="
echo "You can find '$APP_NAME' in $INSTALL_DIR"
echo "or open it with: open '$INSTALL_DIR/$APP_NAME.app'"
echo ""
echo "Note: On first launch, if macOS still asks, right-click the app"
echo "and select 'Open' to bypass Gatekeeper."
