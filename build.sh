#!/bin/bash
set -euo pipefail
export MACOSX_DEPLOYMENT_TARGET=26.0
cd "$(dirname "$0")"
usage() {
    cat <<'HELP'
Usage: ./build.sh [--output /path/to/Perch.app | --check-dependencies]
       ./build.sh --help

With no options, prepare dependencies and build build/Perch.app.

Options:
  --output PATH          Build a separate candidate at PATH (must end in .app).
  --check-dependencies   Prepare/repair dependencies, then stop. No app build,
                         version change, or signing credentials required.
  -h, --help             Show this help without checking or downloading anything.

Every build automatically checks tools and repairs pinned dependency caches.
The first run needs GitHub access to download missing dependencies.
Requires Apple silicon, macOS SDK 26+, Swift 6.2+, and Python 3.9+.

Local signing:
  Uses this Mac's own "Perch Local Code Signing" identity by default.
  Select another with PERCH_SIGN_IDENTITY='identity name or hash'.
  An app build needs a usable signing certificate and private key.

Release signing and notarization use the separate Tools/release.py pipeline
on the release Mac. See README.md and Release/README.md for setup.
Building does not launch or install Perch.
HELP
}
if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
    usage
    exit 0
fi
APP="$PWD/build/Perch.app"
CHECK_DEPENDENCIES=0
if [[ $# -gt 0 ]]; then
    if [[ $# -eq 1 && "$1" == "--check-dependencies" ]]; then
        CHECK_DEPENDENCIES=1
    elif [[ $# -eq 2 && "$1" == "--output" && "$2" == *.app ]]; then
        APP="$2"
        [[ "$APP" == /* ]] || APP="$PWD/$APP"
    else
        echo "Invalid build options. Run $0 --help for usage." >&2
        exit 1
    fi
fi
SIGN_IDENTITY="${PERCH_SIGN_IDENTITY:-Perch Local Code Signing}"
SIGN_OPTIONS=(--timestamp=none)
SPARKLE_COMMAND=(python3 Tools/embed-sparkle.py)
if [[ "${PERCH_RELEASE_BUILD:-0}" == 1 ]]; then
    [[ "$CHECK_DEPENDENCIES" == 1 || ( $# -eq 2 && "$APP" != "$PWD/build/Perch.app" ) ]] || { echo 'Release builds require a separate --output app.' >&2; exit 1; }
    [[ "$SIGN_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Release builds require Developer ID Application.' >&2; exit 1; }
    [[ -n "${PERCH_UPDATE_FEED_URL:-}" && -n "${PERCH_UPDATE_PUBLIC_KEY:-}" ]] || { echo 'Release builds require production update configuration.' >&2; exit 1; }
    SIGN_OPTIONS=(--options runtime --timestamp)
    SPARKLE_COMMAND+=(--release)
fi
APP_SIGN_OPTIONS=("${SIGN_OPTIONS[@]}")
if [[ "${PERCH_RELEASE_BUILD:-0}" == 1 ]]; then
    APP_SIGN_OPTIONS+=(--entitlements Release/Perch.entitlements)
fi
# Bootstrap without invoking a missing developer-tools Python shim.
[[ "$(uname -s)" == Darwin ]] || { echo 'Perch builds require macOS on Apple silicon.' >&2; exit 1; }
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    echo 'Apple developer tools are missing. Install Xcode 26+ or current Command Line Tools (xcode-select --install), then rerun this build.' >&2
    exit 1
fi
command -v python3 >/dev/null || { echo 'Python 3.9+ is required. Install current Apple developer tools or Python 3, then retry.' >&2; exit 1; }
if [[ "$CHECK_DEPENDENCIES" == 1 ]]; then
    python3 Tools/build-preflight.py --dependencies-only
else
    python3 Tools/build-preflight.py --identity "$SIGN_IDENTITY"
fi
python3 Tools/check-dialog-contract.py
# Serialize builds so the persisted counter cannot be reused by concurrent runs.
mkdir -p build
if ! mkdir build/.build-lock 2>/dev/null; then
    echo "Another build is running (build/.build-lock exists)." >&2
    exit 1
fi
STAGING=""
cleanup() {
    if [[ -n "$STAGING" ]]; then rm -rf "$STAGING"; fi
    rmdir build/.build-lock
}
trap cleanup EXIT
# Fetch/repair pinned dependency caches before reserving a version or touching the app.
echo 'Preparing build dependencies (the first run downloads Sparkle and pinned Swift packages)…'
SPARKLE=$(python3 Tools/sparkle-dependency.py)
CERTIFICATES=$(python3 Tools/certificate-dependency.py)
python3 Tools/build-preflight.py --verify-resolved
if [[ "$CHECK_DEPENDENCIES" == 1 ]]; then
    echo 'Dependencies ready. Run ./build.sh to build Perch.'
    exit 0
fi
# A failed compile/embed/sign must not leave a launchable-looking partial app,
# or overwrite the last working build. Stage beside the destination for rename.
OUTPUT_APP="$APP"
mkdir -p "$(dirname "$OUTPUT_APP")"
STAGING=$(mktemp -d "$(dirname "$OUTPUT_APP")/.perch-build.XXXXXX")
APP="$STAGING/$(basename "$OUTPUT_APP")"
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "CFBundleVersion must be an integer" >&2; exit 1; }
BUILD_NUMBER=$((10#$BUILD_NUMBER + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Info.plist
RELEASE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist | cut -d. -f1-2)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION.$BUILD_NUMBER" Info.plist
mkdir -p "$APP/Contents/MacOS"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror Sources/PerchEventLauncher.c -o "$APP/Contents/MacOS/PerchEventLauncher"
xcrun clang -std=c11 -O3 -Wall -Wextra -Werror -c Sources/EventParser.c -o build/EventParser.o
xcrun clang -std=c11 -O3 -Wall -Wextra -Werror -c Sources/DDCWire.c -o build/DDCWire.o
xcrun clang -fmodules -fmodules-cache-path="$PWD/build/ClangModuleCache" -O2 -DMAX_DISPLAYS=16 -I Vendor/m1ddc -I Sources Sources/PerchDisplay.m Sources/MonitorTransport.m Vendor/m1ddc/ioregistry.m build/DDCWire.o -framework CoreDisplay -framework IOKit -framework Foundation -framework CoreGraphics -o "$APP/Contents/MacOS/PerchDisplay"
xcrun swiftc -I "$CERTIFICATES/Modules" -L "$CERTIFICATES" -lPerchCertificates -module-cache-path "$PWD/build/ModuleCache" -import-objc-header Sources/EventParser.h Sources/*.swift build/EventParser.o build/DDCWire.o -o "$APP/Contents/MacOS/Perch" -framework AppKit -framework IOKit -framework ServiceManagement -framework Carbon -framework CoreAudio -framework Security -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -O -whole-module-optimization
xcrun swift Tools/render-branding.swift "$PWD/build/branding"
mkdir -p "$APP/Contents/Resources"
cp build/branding/Perch.icns "$APP/Contents/Resources/Perch.icns"
cp Info.plist "$APP/Contents/Info.plist"
python3 Tools/configure-updates.py "$APP"
mkdir -p "$APP/Contents/Resources"
cp Tools/install-event-collector.sh "$APP/Contents/Resources/install-event-collector.sh"
cp catalog/msi-input-profiles.json "$APP/Contents/Resources/msi-input-profiles.json"
cp catalog/agents.json "$APP/Contents/Resources/agents.json"
cp catalog/keyboard-profiles.json "$APP/Contents/Resources/keyboard-profiles.json"
cp catalog/lg-firmware-families.json "$APP/Contents/Resources/lg-firmware-families.json"
cp catalog/monitor-profiles.json "$APP/Contents/Resources/monitor-profiles.json"
cp catalog/ddccontrol-COPYING.txt "$APP/Contents/Resources/ddccontrol-COPYING.txt"
cp Vendor/m1ddc/LICENSE "$APP/Contents/Resources/m1ddc-LICENSE.txt"
for DEPENDENCY in swift-certificates swift-asn1 swift-crypto; do
    cp "Vendor/PerchCertificates/.build/checkouts/$DEPENDENCY/LICENSE.txt" "$APP/Contents/Resources/$DEPENDENCY-LICENSE.txt"
    cp "Vendor/PerchCertificates/.build/checkouts/$DEPENDENCY/NOTICE.txt" "$APP/Contents/Resources/$DEPENDENCY-NOTICE.txt"
done
"${SPARKLE_COMMAND[@]}" "$APP" --identity "$SIGN_IDENTITY"
python3 Tools/release_assets.py install --app "$APP"
codesign --force --sign "$SIGN_IDENTITY" --identifier local.scott.perch.event-launcher "${SIGN_OPTIONS[@]}" "$APP/Contents/MacOS/PerchEventLauncher"
codesign --force --sign "$SIGN_IDENTITY" "${SIGN_OPTIONS[@]}" "$APP/Contents/MacOS/PerchDisplay"
codesign --force --sign "$SIGN_IDENTITY" "${APP_SIGN_OPTIONS[@]}" "$APP"
python3 Tools/app_bundle.py "$APP" --destination "$OUTPUT_APP"
echo "Built $OUTPUT_APP"
