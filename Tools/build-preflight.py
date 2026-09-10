#!/usr/bin/env python3
"""Read-only build prerequisites; dependency helpers perform bounded cache repair."""
import argparse
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]

def output(*command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip())
    return result.stdout.strip()

def environment(identity):
    errors = []
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        errors.append('Build on Apple silicon in a native arm64 Terminal (turn off Open using Rosetta for Terminal).')
    if sys.version_info < (3, 9):
        errors.append('Python 3.9 or newer is required. Select the Python supplied with current Apple developer tools or install a current Python 3.')
    for tool in ('xcrun', 'git', 'curl', 'tar', 'ditto', 'codesign', 'security'):
        if not shutil.which(tool): errors.append('Missing '+tool+'. Install/select current Apple developer tools.')
    if shutil.which('xcrun'):
        try:
            sdk = output('xcrun', '--sdk', 'macosx', '--show-sdk-version')
            if int(sdk.split('.')[0]) < 26:
                errors.append('macOS SDK 26 or newer is required (selected SDK: '+sdk+'). Install Xcode 26+ or matching Command Line Tools, then select it in Xcode Settings → Locations.')
            compiler = output('xcrun', 'swift', '--version')
            version = re.search(r'Swift version (\d+)\.(\d+)', compiler)
            if not version or tuple(map(int, version.groups())) < (6, 2):
                errors.append('Swift 6.2 or newer is required. Select the compiler from Xcode 26+ or matching Command Line Tools.')
            output('xcrun', '--find', 'clang')
        except (RuntimeError, subprocess.TimeoutExpired, ValueError) as error:
            errors.append('Apple developer tools are not ready: '+str(error)+'. Open Xcode to finish its setup/license, or install current Command Line Tools; check xcode-select -p.')
    if identity and shutil.which('security'):
        try:
            identities = re.findall(r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)"', output('security', 'find-identity', '-v', '-p', 'codesigning'), re.M)
            matches = [item for item in identities if identity.lower() == item[0].lower() or identity == item[1]]
            if len(matches) != 1:
                errors.append('Signing identity '+repr(identity)+' must match one usable certificate/private key. Use this Mac’s own local signing identity; release credentials do not need to be copied. Create/import a local identity in Keychain Access, or set PERCH_SIGN_IDENTITY to one listed by: security find-identity -v -p codesigning. For duplicate names, use the identity hash. See README.md → Build and run. No ad-hoc fallback is used.')
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            errors.append('Could not inspect signing identities: '+str(error)+'. Unlock the login Keychain and retry.')
    for name in ('Vendor/PerchCertificates/Package.swift', 'Vendor/PerchCertificates/Package.resolved', 'Vendor/m1ddc/ioregistry.m'):
        if not (REPO/name).is_file(): errors.append('Required source is missing: '+name+'. Restore it from this checkout; dependency versions will not be guessed.')
    if errors:
        raise SystemExit('Build prerequisites need attention:\n\n'+'\n\n'.join('- '+x for x in errors))
    print('Build prerequisites ready: Apple silicon, macOS SDK 26+, Swift 6.2+ and Python'+('; signing identity available.' if identity else '. Signing credentials are not needed for dependency preparation.'))

def resolved():
    import release_assets
    inventory, _ = release_assets.sources()
    release_assets.check_pins(inventory)
    print('Pinned dependencies and their license/provenance files verified.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', default='Perch Local Code Signing')
    parser.add_argument('--verify-resolved', action='store_true')
    parser.add_argument('--dependencies-only', action='store_true', help='Check tools without requiring a signing identity; no app is built')
    args = parser.parse_args()
    try:
        resolved() if args.verify_resolved else environment(None if args.dependencies_only else args.identity)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit('Dependency preflight failed: '+str(error)+'. Repair the reported prerequisite and rerun ./build.sh --check-dependencies.')
