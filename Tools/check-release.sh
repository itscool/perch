#!/bin/bash
# Run as the logged-in user. No sudo, privacy resets, or real panic action.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Perch.app"
BIN="$APP/Contents/MacOS/Perch"
codesign --verify --strict "$APP"
"$BIN" --self-test
"$BIN" --settings-self-test
if [[ "${1:-}" == "--cpu" ]]; then "$BIN" --cpu-benchmark; fi
echo 'PASS: Perch release checks'
