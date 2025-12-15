#!/bin/bash

set -e  # Exit on error

echo "📀 Creating DMG installer for Untold Engine Studio..."

# Configuration
APP_NAME="Untold Engine Studio"
DMG_NAME="UntoldEngineStudio"
APP_BUNDLE="$APP_NAME.app"
DMG_TEMP_DIR="dmg_temp"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Determine version (env -> release/* branch -> latest tag vX.Y.Z -> fallback)
detect_version() {
    if [ -n "${VERSION:-}" ]; then
        echo "$VERSION"; return
    fi
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$branch" == release/* ]]; then
        echo "${branch#release/}"; return
    fi
    tag=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")
    if [[ "$tag" == v* ]]; then
        echo "${tag#v}"; return
    fi
    echo "0.0.0-dev"
}
VERSION="$(detect_version)"

DMG_FILE="$DMG_NAME-$VERSION.dmg"

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: $APP_BUNDLE not found. Run ./create_app_bundle.sh first."
    exit 1
fi

# Clean previous DMG files
echo "🧹 Cleaning previous DMG files..."
rm -f "$DMG_FILE"
rm -rf "$DMG_TEMP_DIR"

# Create temporary directory for DMG contents
echo "📦 Creating DMG staging directory..."
mkdir -p "$DMG_TEMP_DIR"

# Copy app bundle to staging
echo "📋 Copying app bundle..."
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"

# Create symbolic link to Applications folder
echo "🔗 Creating Applications folder link..."
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# Create DMG
echo "💿 Creating DMG image..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP_DIR" \
    -ov -format UDZO \
    "$DMG_FILE"

# Clean up temp directory
echo "🧹 Cleaning up..."
rm -rf "$DMG_TEMP_DIR"

echo "✅ DMG created successfully: $DMG_FILE"
echo ""
echo "To test the DMG:"
echo "  open $DMG_FILE"
echo ""
echo "Users can drag '$APP_NAME.app' to the Applications folder to install."
