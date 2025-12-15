#!/bin/bash

set -e  # Exit on error

echo "🔨 Building UntoldEditor app bundle..."

# Configuration
APP_NAME="Untold Engine Studio"
EXECUTABLE_NAME="UntoldEditor"
BUNDLE_ID="com.untoldengine.studio"
VERSION="0.2.0"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_BUNDLE="$APP_NAME.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNTOLD_ENGINE_ROOT="$SCRIPT_DIR/../UntoldEngine"
METALLIB_PATH="$UNTOLD_ENGINE_ROOT/Sources/UntoldEngine/UntoldEngineKernels/UntoldEngineKernels.metallib"

# Clean previous bundle
echo "🧹 Cleaning previous bundle..."
rm -rf "$APP_BUNDLE"

# Build the executable with Swift Package Manager
echo "🔧 Building executable..."
swift build --configuration release

# Create app bundle structure
echo "📦 Creating app bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the executable
echo "📋 Copying executable..."
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Copy Metal shaders
if [ -f "$METALLIB_PATH" ]; then
    echo "🎨 Copying Metal shaders..."
    cp "$METALLIB_PATH" "$APP_BUNDLE/Contents/Resources/"
else
    echo "⚠️  Warning: Metal shader library not found at $METALLIB_PATH"
fi

# Copy app icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    echo "🎨 Copying app icon..."
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Create Info.plist
echo "📝 Creating Info.plist..."

# Check if icon exists to conditionally add it
ICON_ENTRY=""
if [ -f "Resources/AppIcon.icns" ]; then
    ICON_ENTRY="    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
$(echo -e "$ICON_ENTRY")
</dict>
</plist>
EOF

# Make executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

echo "✅ App bundle created successfully at: $APP_BUNDLE"
echo ""
echo "To test the app, run:"
echo "  open $APP_BUNDLE"
echo ""
echo "Or double-click the app in Finder"
