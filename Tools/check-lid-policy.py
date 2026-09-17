#!/usr/bin/env python3
"""Fast headless lid-policy tests using production Swift and a virtual clock.

No AppKit, IOKit, Sparkle, signing credentials, helper or AGENT MODE required.
The first run compiles; unchanged reruns reuse the binary. No live power access.
"""
import argparse
import hashlib
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, help='Cache directory (default: build/lid-policy-tests)')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = (args.output or repo / 'build/lid-policy-tests').resolve()
output.mkdir(parents=True, exist_ok=True)
sources = [perch_source(name) for name in [
    'LidGuardPolicy.swift', 'LidGuardWatchdogState.swift', 'LidGuardEnforcer.swift',
    'LidRestartHandoff.swift', 'HotKeyLatch.swift', 'LidCountdown.swift', 'LidPolicyTests.swift', 'LidCountdownTests.swift',
]]
# Only the app's error container is supplied by the harness. Every policy,
# watchdog, restart and enforcement implementation is compiled unchanged.
sources.insert(0, perch_source('PerchError.swift'))
sources.insert(1, perch_source('MonotonicClock.swift'))
main = '''import Foundation
do { try runLidPolicyTests(); try runLidCountdownTests() }
catch { fputs("FAIL: \\(error.localizedDescription)\\n", stderr); exit(1) }
'''
# Resolved only to identify the toolchain in the cache key. The compile runs
# through xcrun so the SDK is set; invoking this path directly leaves
# Xcode's swiftc unable to load a standard library.
compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
version = subprocess.check_output([compiler, '--version'])
digest = hashlib.sha256(version + main.encode() + Path(__file__).read_bytes())
for source in sources:
    digest.update(source.name.encode() + source.read_bytes())
key = digest.hexdigest()
stamp, binary = output / 'source.sha256', output / 'lid-policy-tests'
if not binary.exists() or not stamp.exists() or stamp.read_text() != key:
    print('Compiling headless lid-policy tests…', flush=True)
    entry = output / 'main.swift'
    entry.write_text(main)
    subprocess.run(['xcrun', 'swiftc', '-O', '-whole-module-optimization',
                    *map(str, sources), str(entry), '-o', str(binary)], check=True)
    stamp.write_text(key)
started = time.perf_counter()
subprocess.run([str(binary)], check=True)
print(f'Policy test execution: {time.perf_counter() - started:.3f}s (compilation excluded)')
