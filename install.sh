#!/bin/bash
set -e

APP_NAME="Sennheiser Freq Manager"
BUNDLE_NAME="SennheiserFreqManager"
INSTALL_DIR="/Applications"
RFEXPLORER_DIR="$HOME/rfexplorer-detailed-scan"
RFEXPLORER_REPO="https://github.com/mkupferman/rfexplorer-detailed-scan.git"

echo "=== $APP_NAME Installer ==="
echo ""

# Check for Xcode command line tools
if ! xcode-select -p &>/dev/null; then
    echo "Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "Please re-run this script after installation completes."
    exit 1
fi

# Check for Homebrew
if ! command -v brew &>/dev/null; then
    echo "Error: Homebrew is required. Install from https://brew.sh"
    exit 1
fi

# Check for xcodegen
if ! command -v xcodegen &>/dev/null; then
    echo "Installing xcodegen..."
    brew install xcodegen
fi

# Check for python3
if ! command -v python3 &>/dev/null; then
    echo "Installing python3..."
    brew install python3
fi

# ── Build and install the app ──

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
    echo "Error: Build failed."
    exit 1
fi

echo ""
echo "Installing app to $INSTALL_DIR..."

if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

cp -R "$BUILD_APP" "$INSTALL_DIR/"
xattr -cr "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
rm -rf build

# ── Install RF Explorer scanner ──

echo ""
echo "Setting up RF Explorer scanner..."

if [ -d "$RFEXPLORER_DIR/.git" ]; then
    echo "RF Explorer repo already exists, updating..."
    cd "$RFEXPLORER_DIR"
    git pull --ff-only 2>/dev/null || true
else
    echo "Cloning RF Explorer scanner..."
    git clone "$RFEXPLORER_REPO" "$RFEXPLORER_DIR"
    cd "$RFEXPLORER_DIR"
fi

if [ ! -d "$RFEXPLORER_DIR/venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$RFEXPLORER_DIR/venv"
fi

echo "Installing Python dependencies..."
"$RFEXPLORER_DIR/venv/bin/pip" install --upgrade pip -q
"$RFEXPLORER_DIR/venv/bin/pip" install -e "$RFEXPLORER_DIR" -q

# Verify
if [ -x "$RFEXPLORER_DIR/venv/bin/rfexplorerDetailedScan" ]; then
    echo "RF Explorer scanner installed successfully."
else
    echo "Warning: RF Explorer scanner binary not found after install."
fi

echo ""
echo "=== Installation complete! ==="
echo ""
echo "  App:         $INSTALL_DIR/$APP_NAME.app"
echo "  RF Scanner:  $RFEXPLORER_DIR/venv/bin/rfexplorerDetailedScan"
echo ""
echo "Open with: open '$INSTALL_DIR/$APP_NAME.app'"
echo ""
echo "Note: On first launch, if macOS asks, right-click the app"
echo "and select 'Open' to bypass Gatekeeper."
