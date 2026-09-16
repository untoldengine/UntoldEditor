#!/bin/bash

set -e  # Exit on error

# Optional Flags:
#   --sign : Code sign the app bundle with a Developer ID Application identity
#            (required before the app can be notarized or run cleanly on other Macs).
#            Override the identity with the SIGNING_IDENTITY env var.
SIGN_APP="false"
[[ "${1:-}" == "--sign" ]] && SIGN_APP="true"

echo "🔨 Building UntoldEditor app bundle..."

# Configuration
APP_NAME="Untold Engine Studio"
EXECUTABLE_NAME="UntoldEditor"
BUNDLE_ID="com.untoldengine.studio"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: UNTOLD ENGINE STUDIOS LLC (PXXZLXYJ26)}"

# Determine version (env -> release/* branch -> latest tag vX.Y.Z -> fallback)
detect_version() {
    if [ -n "${VERSION:-}" ]; then
        echo "$VERSION"; return
    fi
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$branch" == release/* ]]; then
        echo "${branch#release/}"; return
    fi
    tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [[ "$tag" == v* ]]; then
        echo "${tag#v}"; return
    fi
    echo "0.0.0-dev"
}
VERSION="$(detect_version)"
APP_BUNDLE="$APP_NAME.app"

# Clean previous bundle
echo "🧹 Cleaning previous bundle..."
rm -rf "$APP_BUNDLE"

# Build the executable with Swift Package Manager
echo "🔧 Building executable..."
swift build --configuration release -Xswiftc -DENGINE_STATS_ENABLED

# Ask SwiftPM where it actually put the build products rather than hardcoding a path — the
# default build system backend (and its output layout, e.g. .build/<triple>/release vs.
# .build/out/Products/Release) can change between toolchain versions.
BUILD_DIR="$(swift build --configuration release -Xswiftc -DENGINE_STATS_ENABLED --show-bin-path)"

# Create app bundle structure
echo "📦 Creating app bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the executable
echo "📋 Copying executable..."
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Flatten each target's SPM resource bundle (shaders/HDR skies/light icons for UntoldEngine,
# demo scene/asset pack thumbnails for UntoldEditor) into Contents/Resources. Both targets look
# these up via Bundle.main first (falling back to Bundle.module only on platforms/targets that
# still ship the resource bundle as-is), so placing the files directly in Contents/Resources
# lets Bundle.main find them by name. Copying a whole .bundle folder to the app root instead
# would make codesign refuse to seal the app ("unsealed contents present in the bundle root"),
# which is fatal for notarization.
flatten_resource_bundle() {
    local bundle_path="$1"
    local label="$2"
    if [ -d "$bundle_path" ]; then
        echo "📦 Copying $label resources..."
        # SwiftPM resource bundles are flat (files directly at the bundle root) under the
        # legacy "native" build system, but the "swiftbuild" backend wraps them in a full
        # Contents/Resources bundle structure (with its own Contents/Info.plist) for code
        # signing. Flatten from whichever layout the active build system actually produced.
        local resource_root="$bundle_path"
        if [ -d "$bundle_path/Contents/Resources" ]; then
            resource_root="$bundle_path/Contents/Resources"
        fi
        # Fail loudly on a filename collision with resources already flattened in from an
        # earlier call, rather than silently overwriting one target's resource with another's.
        while IFS= read -r -d '' src_file; do
            rel_path="${src_file#"$resource_root"/}"
            dest_file="$APP_BUNDLE/Contents/Resources/$rel_path"
            if [ -e "$dest_file" ]; then
                echo "❌ Error: $label resource '$rel_path' collides with a resource already copied into Contents/Resources." >&2
                exit 1
            fi
        done < <(find "$resource_root" -type f -print0)
        cp -R "$resource_root"/. "$APP_BUNDLE/Contents/Resources/"
    else
        echo "⚠️  Warning: $label resource bundle not found at $bundle_path — run 'swift build' first"
    fi
}
flatten_resource_bundle "$BUILD_DIR/UntoldEngine_UntoldEngine.bundle" "UntoldEngine"
flatten_resource_bundle "$BUILD_DIR/UntoldEditor_UntoldEditor.bundle" "UntoldEditor"

# Copy app icon if it exists
if [ -f "Resources/AppIcon.icns" ]; then
    echo "🎨 Copying app icon..."
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy exporter scripts. SPM only checks the dependency out under .build/checkouts/ for a
# git-URL dependency; while Package.swift points at a local path (e.g. during engine+editor
# co-development), fall back to that sibling checkout directly.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_SRC=".build/checkouts/UntoldEngine/scripts"
if [ ! -d "$SCRIPTS_SRC" ]; then
    SCRIPTS_SRC="$SCRIPT_DIR/../UntoldEngine/scripts"
fi
if [ -d "$SCRIPTS_SRC" ]; then
    echo "📜 Copying exporter scripts..."
    mkdir -p "$APP_BUNDLE/Contents/Resources/scripts"
    cp "$SCRIPTS_SRC/export-untold" "$APP_BUNDLE/Contents/Resources/scripts/"
    cp "$SCRIPTS_SRC/export-untold-tiles" "$APP_BUNDLE/Contents/Resources/scripts/"
    cp "$SCRIPTS_SRC/untoldexporter.py" "$APP_BUNDLE/Contents/Resources/scripts/"
    cp "$SCRIPTS_SRC/tilestreamingpartition.py" "$APP_BUNDLE/Contents/Resources/scripts/"
    cp "$SCRIPTS_SRC/untoldexplorer.py" "$APP_BUNDLE/Contents/Resources/scripts/"
    cp "$SCRIPTS_SRC/texbake.py" "$APP_BUNDLE/Contents/Resources/scripts/"
    chmod +x "$APP_BUNDLE/Contents/Resources/scripts/export-untold"
    chmod +x "$APP_BUNDLE/Contents/Resources/scripts/export-untold-tiles"
else
    echo "⚠️  Warning: Exporter scripts not found at $SCRIPTS_SRC — run 'swift build' first to populate checkouts"
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

# Optionally code sign with a Developer ID Application identity. Required for the app to
# run on other Macs without a Gatekeeper "damaged" error, and before it can be notarized.
if [[ "${SIGN_APP}" == "true" ]]; then
    security find-identity -v -p codesigning | grep -qF "${SIGNING_IDENTITY}" || {
        echo "❌ Error: Signing identity not found in keychain: ${SIGNING_IDENTITY}" >&2
        echo "Run 'security find-identity -v -p codesigning' to see available identities." >&2
        exit 1
    }
    echo "🔏 Code signing app bundle with: ${SIGNING_IDENTITY}..."
    codesign --force --deep --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    echo "✅ App bundle signed."
fi

echo "✅ App bundle created successfully at: $APP_BUNDLE"
echo ""
echo "To test the app, run:"
echo "  open $APP_BUNDLE"
echo ""
echo "Or double-click the app in Finder"
