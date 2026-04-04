#!/bin/bash
set -e

# PowerBarPro Full Rebuild & Restart Script

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="PowerBarPro"
INSTALL_PATH="/Applications/${APP_NAME}.app"

echo "PowerBarPro - Full Rebuild & Restart"
echo "-------------------------------------"

# Step 1: Kill existing processes
echo "Stopping existing $APP_NAME processes..."
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1

# Step 2: Remove from Applications
if [ -d "$INSTALL_PATH" ]; then
    echo "Removing $INSTALL_PATH..."
    rm -rf "$INSTALL_PATH"
fi

# Step 3: Clean build directory
echo "Cleaning build artifacts..."
rm -rf .build

# Step 4: Build
echo ""
"$SCRIPT_DIR/build.sh"

# Step 5: Install
echo ""
"$SCRIPT_DIR/install.sh"

# Step 6: Launch
echo ""
echo "Launching $APP_NAME..."
open "$INSTALL_PATH"

# Step 7: Verify
sleep 2
if pgrep -f "$APP_NAME" > /dev/null; then
    echo "$APP_NAME is running."
else
    echo "Warning: $APP_NAME may not have started. Check Console.app for errors."
fi

echo ""
echo "Rebuild and restart complete."
