#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=26.0
cd "$(dirname "$0")"
python3 Tools/check-dialog-contract.py
APP="$PWD/build/Perch.app"
if [[ $# -gt 0 ]]; then
    if [[ $# -ne 2 || "$1" != "--output" || "$2" != *.app ]]; then
        echo "Usage: $0 [--output /path/to/Perch.app]" >&2
        exit 1
    fi
    APP="$2"
    [[ "$APP" == /* ]] || APP="$PWD/$APP"
fi
# Serialize builds so the persisted counter cannot be reused by concurrent runs.
mkdir -p build
if ! mkdir build/.build-lock 2>/dev/null; then
    echo "Another build is running (build/.build-lock exists)." >&2
    exit 1
fi
trap 'rmdir build/.build-lock' EXIT
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "CFBundleVersion must be an integer" >&2; exit 1; }
BUILD_NUMBER=$((10#$BUILD_NUMBER + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Info.plist
mkdir -p "$APP/Contents/MacOS"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror Sources/PerchEventLauncher.c -o "$APP/Contents/MacOS/PerchEventLauncher"
xcrun clang -std=c11 -O3 -Wall -Wextra -Werror -c Sources/EventParser.c -o build/EventParser.o
xcrun clang -std=c11 -O3 -Wall -Wextra -Werror -c Sources/DDCWire.c -o build/DDCWire.o
xcrun clang -fmodules -fmodules-cache-path="$PWD/build/ClangModuleCache" -O2 -DMAX_DISPLAYS=16 -I Vendor/m1ddc -I Sources Sources/PerchDisplay.m Sources/MonitorTransport.m Vendor/m1ddc/ioregistry.m build/DDCWire.o -framework CoreDisplay -framework IOKit -framework Foundation -framework CoreGraphics -o "$APP/Contents/MacOS/PerchDisplay"
xcrun swiftc -module-cache-path "$PWD/build/ModuleCache" -import-objc-header Sources/EventParser.h Sources/*.swift build/EventParser.o build/DDCWire.o -o "$APP/Contents/MacOS/Perch" -framework AppKit -framework IOKit -framework ServiceManagement -framework Carbon -framework CoreAudio -framework Security -O -whole-module-optimization
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Tools/install-event-collector.sh "$APP/Contents/Resources/install-event-collector.sh"
cp catalog/msi-input-profiles.json "$APP/Contents/Resources/msi-input-profiles.json"
cp catalog/agents.json "$APP/Contents/Resources/agents.json"
cp catalog/keyboard-profiles.json "$APP/Contents/Resources/keyboard-profiles.json"
cp catalog/lg-firmware-families.json "$APP/Contents/Resources/lg-firmware-families.json"
cp catalog/monitor-profiles.json "$APP/Contents/Resources/monitor-profiles.json"
cp catalog/ddccontrol-COPYING.txt "$APP/Contents/Resources/ddccontrol-COPYING.txt"
cp Vendor/m1ddc/LICENSE "$APP/Contents/Resources/m1ddc-LICENSE.txt"
codesign --force --sign "Perch Local Code Signing" --identifier local.scott.perch.event-launcher --timestamp=none "$APP/Contents/MacOS/PerchEventLauncher"
codesign --force --sign "Perch Local Code Signing" --timestamp=none "$APP/Contents/MacOS/PerchDisplay"
codesign --force --sign "Perch Local Code Signing" --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
