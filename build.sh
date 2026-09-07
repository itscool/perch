#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=26.0
cd "$(dirname "$0")"
APP="$PWD/build/Perch.app"
mkdir -p "$APP/Contents/MacOS"
xcrun clang -std=c11 -O3 -Wall -Wextra -Werror -c Sources/EventParser.c -o build/EventParser.o
xcrun swiftc -module-cache-path "$PWD/build/ModuleCache" -import-objc-header Sources/EventParser.h Sources/*.swift build/EventParser.o -o "$APP/Contents/MacOS/Perch" -framework AppKit -framework IOKit -framework ServiceManagement -framework Carbon -framework CoreAudio -framework Security -O -whole-module-optimization
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Tools/install-event-collector.sh "$APP/Contents/Resources/install-event-collector.sh"
cp catalog/agents.json "$APP/Contents/Resources/agents.json"
cp catalog/keyboard-profiles.json "$APP/Contents/Resources/keyboard-profiles.json"
codesign --force --sign "Perch Local Code Signing" --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
