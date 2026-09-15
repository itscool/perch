#!/bin/bash
# Type-check every Swift source and test with the app's build flags, without
# linking, bumping the version or taking the build lock. Use it for quick
# iteration; ./build.sh --no-bump remains the real verification.
set -euo pipefail
cd "$(dirname "$0")/.."
CERTIFICATES=$(python3 Tools/certificate-dependency.py)
SPARKLE=$(python3 Tools/sparkle-dependency.py)
mkdir -p build
xcrun swiftc -typecheck -I "$CERTIFICATES/Modules" -module-cache-path "$PWD/build/ModuleCache" \
    -import-objc-header Sources/Native/EventParser.h \
    $(/usr/bin/find Sources Tests -name '*.swift' | /usr/bin/sort) \
    -F "$SPARKLE" "$@"
echo "Type-check passed."
