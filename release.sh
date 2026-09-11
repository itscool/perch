#!/bin/bash
# Prepare the release tools, then use the single resumable release pipeline.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 Tools/release-launcher.py "$@"
