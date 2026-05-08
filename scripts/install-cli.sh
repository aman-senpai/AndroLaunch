#!/bin/bash
# AndroLaunch CLI Install Script
# Builds and installs the AndroLaunch CLI tool to /usr/local/bin

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$SCRIPT_DIR/../cli"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="androlaunch"

echo "🔨 Building AndroLaunch CLI..."

cd "$CLI_DIR"

# Build in release mode
swift build -c release --disable-sandbox

# Check if build succeeded
if [ ! -f ".build/release/$BINARY_NAME" ]; then
    echo "❌ Build failed! Binary not found."
    exit 1
fi

echo "✅ Build successful!"

# Install binary
echo "📦 Installing to $INSTALL_DIR/$BINARY_NAME..."
sudo cp ".build/release/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo ""
echo "✅ AndroLaunch CLI installed successfully!"
echo ""
echo "Run 'androlaunch --help' to get started."
echo ""
echo "Quick start:"
echo "  androlaunch devices              # List connected devices"
echo "  androlaunch apps                 # List installed apps"
echo "  androlaunch mirror               # Mirror device screen"
echo "  androlaunch wifi on              # Enable Wi-Fi"
echo "  androlaunch shell \"ls /sdcard\"  # Run shell command"
