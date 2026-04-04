#!/bin/bash
set -e

# PowerBarPro Build Script

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "Building PowerBarPro..."

# Verify we are in the right directory
if [ ! -f "Package.swift" ]; then
    echo "Error: Package.swift not found. Expected project root at: $PROJECT_DIR"
    exit 1
fi

# Check macmon dependency
if ! command -v macmon &> /dev/null; then
    echo "Warning: macmon is not installed or not in PATH"
    echo "  Install: brew install macmon"
    echo "  Source:  https://github.com/vladkens/macmon"
    echo ""
fi

# Build in release mode
echo "Compiling in release mode..."
swift build -c release

# Verify output
BINARY=".build/release/PowerBarPro"
if [ -f "$BINARY" ]; then
    echo "Build successful: $BINARY"
else
    echo "Error: Build produced no output at $BINARY"
    exit 1
fi
