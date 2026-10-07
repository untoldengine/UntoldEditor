#!/bin/bash
# Wraps the editor that `swift build` made in a development app bundle and registers it with
# LaunchServices, so that it runs as an app the system knows: the device picker of the Apple
# Vision Pro preview asks LaunchServices for the app behind the request and refuses a bare
# executable. The settings and the window state are the packaged app's (same identifier).
#
# The executable is copied (LaunchServices wants the running file inside the bundle); the resource
# bundles, the exporter scripts and the build products are linked, and the editor finds its
# Component SDK through the BuildProducts link. Run it again after a build, or use --run.
#
#   scripts/dev-app.sh [debug|release]        makes (or refreshes) the bundle and prints its path
#   scripts/dev-app.sh --run [debug|release]  builds, makes it and starts it, output in this terminal
set -euo pipefail
cd "$(dirname "$0")/.."

RUN=0
CONFIG=debug
for arg in "$@"; do
    case "$arg" in
        --run) RUN=1 ;;
        debug | release) CONFIG="$arg" ;;
        *) echo "usage: scripts/dev-app.sh [--run] [debug|release]" >&2; exit 2 ;;
    esac
done

if [ "$RUN" = 1 ]; then
    swift build -c "$CONFIG"
fi
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
if [ ! -x "$BIN_DIR/UntoldEditor" ]; then
    echo "No $CONFIG build in $BIN_DIR: run 'swift build -c $CONFIG' first." >&2
    exit 1
fi

APP="$BIN_DIR/Untold Engine Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
rm -f "$APP/Contents/MacOS/UntoldEditor"
cp "$BIN_DIR/UntoldEditor" "$APP/Contents/MacOS/UntoldEditor"
cp Sources/UntoldEditor/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" > /dev/null
fi
# The resource bundles of the engine and the editor, as the build folder has them (for the
# `Bundle.module` accessors), and their files flattened into Resources as the packaged app has
# them (for the lookups through `Bundle.main`); the build products for the Component SDK; the
# exporter scripts.
for bundle in "$BIN_DIR"/*.bundle; do
    ln -sfn "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
    resource_root="$bundle"
    if [ -d "$bundle/Contents/Resources" ]; then
        resource_root="$bundle/Contents/Resources"
    fi
    for entry in "$resource_root"/*; do
        [ -e "$entry" ] || continue
        target="$APP/Contents/Resources/$(basename "$entry")"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
            echo "warning: $(basename "$entry") of $(basename "$bundle") is left out: a file of that name is in the bundle already" >&2
            continue
        fi
        ln -sfn "$entry" "$target"
    done
done
ln -sfn "$BIN_DIR" "$APP/Contents/Resources/BuildProducts"
SCRIPTS=.build/checkouts/UntoldEngine/scripts
if [ ! -d "$SCRIPTS" ]; then
    SCRIPTS=../UntoldEngine/scripts
fi
if [ -d "$SCRIPTS" ]; then
    ln -sfn "$(cd "$SCRIPTS" && pwd)" "$APP/Contents/Resources/scripts"
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "$APP"
if [ "$RUN" = 1 ]; then
    exec "$APP/Contents/MacOS/UntoldEditor"
fi
