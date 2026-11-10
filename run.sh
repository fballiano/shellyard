#!/bin/bash
# Builds Shellyard and starts it.
#
#   ./run.sh            build and start
#   ./run.sh --install  also copy the application to /Applications and
#                       link the `shellyard` command into /usr/local/bin
#
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null; then
    echo "XcodeGen is missing. Run: brew install xcodegen"
    exit 1
fi

echo "==> Making the Xcode project"
xcodegen generate >/dev/null

echo "==> Building"
xcodebuild -project Shellyard.xcodeproj -scheme Shellyard \
           -configuration Debug \
           -destination 'platform=macOS,arch=arm64' \
           -derivedDataPath build build \
    | grep -E "error:|warning:|BUILD" || true

APP="build/Build/Products/Debug/Shellyard.app"
if [ ! -d "$APP" ]; then
    echo "The build produced no application."
    exit 1
fi

if [ "${1:-}" = "--install" ]; then
    echo "==> Copying to /Applications"
    rm -rf "/Applications/Shellyard.app"
    cp -R "$APP" "/Applications/Shellyard.app"
    APP="/Applications/Shellyard.app"

    CLI="$APP/Contents/MacOS/shellyard-cli"
    LINK="/usr/local/bin/shellyard"
    if [ "$(readlink "$LINK" 2>/dev/null)" != "$CLI" ]; then
        echo "==> Linking $LINK (asks for your password)"
        sudo mkdir -p /usr/local/bin
        sudo ln -sf "$CLI" "$LINK"
    fi
fi

echo "==> Starting $APP"
# Quit an older copy first, so the new one is the one you see.
pkill -f "Shellyard.app/Contents/MacOS/Shellyard" 2>/dev/null || true
open "$APP"
