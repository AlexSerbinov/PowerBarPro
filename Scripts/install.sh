#!/bin/bash
set -e

# PowerBarPro Installation Script
# Installs to /Applications/PowerBarPro.app (separate from original PowerBar.app)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="PowerBarPro"
BINARY_NAME="PowerBarPro"
BUILD_PATH=".build/release/$BINARY_NAME"
INSTALL_PATH="/Applications/${APP_NAME}.app"
ICON_SOURCE="Resources/PowerBarPro.icns"
PLIST_SOURCE="Resources/Info.plist"

echo "Installing $APP_NAME..."

# Verify build exists
if [ ! -f "$BUILD_PATH" ]; then
    echo "Error: Executable not found at $BUILD_PATH"
    echo "  Run Scripts/build.sh first."
    exit 1
fi

# Remove previous installation
if [ -d "$INSTALL_PATH" ]; then
    echo "Removing previous installation..."
    rm -rf "$INSTALL_PATH"
fi

# Create app bundle structure
echo "Creating app bundle..."
mkdir -p "$INSTALL_PATH/Contents/MacOS"
mkdir -p "$INSTALL_PATH/Contents/Resources"

# Copy executable
echo "Copying executable..."
cp "$BUILD_PATH" "$INSTALL_PATH/Contents/MacOS/$BINARY_NAME"
chmod +x "$INSTALL_PATH/Contents/MacOS/$BINARY_NAME"

# Copy Info.plist
echo "Copying Info.plist..."
if [ -f "$PLIST_SOURCE" ]; then
    cp "$PLIST_SOURCE" "$INSTALL_PATH/Contents/Info.plist"
else
    echo "Error: Info.plist not found at $PLIST_SOURCE"
    exit 1
fi

# Copy icon from original powerBar project
echo "Copying app icon..."
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$INSTALL_PATH/Contents/Resources/PowerBar.icns"
    echo "Icon copied."
else
    echo "Warning: Icon not found at $ICON_SOURCE"
    echo "  The app will work but without a custom icon."
fi

# Code sign for Gatekeeper compatibility
echo "Code signing..."
codesign -f -s - "$INSTALL_PATH"

# Touch the app bundle to refresh Finder/LaunchServices icon cache
touch "$INSTALL_PATH"

echo ""
echo "$APP_NAME installed to $INSTALL_PATH"
echo ""
echo "Launch with:"
echo "  open $INSTALL_PATH"
