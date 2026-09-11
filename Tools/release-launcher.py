#!/usr/bin/env python3
"""Bootstrap release tooling; release-all.py remains the only stage orchestrator."""
import argparse
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
ENVIRONMENT = REPO / 'build/release-tools'
REQUIREMENTS = REPO / 'Release/requirements.txt'


def usable_python(path):
    try:
        return subprocess.run([str(path), '-c', 'import sys; sys.exit(sys.version_info < (3, 10))'],
                              capture_output=True, timeout=15).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def prepare_tools():
    python = ENVIRONMENT / 'bin/python3'
    ENVIRONMENT.parent.mkdir(parents=True, exist_ok=True)
    with (ENVIRONMENT.parent / '.release-tools.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('Another release command is preparing the tools. Retry when it finishes.')
        if not usable_python(python):
            explicit = os.environ.get('PERCH_RELEASE_PYTHON')
            candidates = [explicit] if explicit else [sys.executable] + [
                shutil.which(name) for name in ('python3', 'python3.14', 'python3.13', 'python3.12', 'python3.11', 'python3.10')
            ] + ['/opt/homebrew/bin/python3', '/usr/local/bin/python3']
            source = next((path for path in candidates if path and usable_python(path)), None)
            if source is None:
                raise SystemExit('Release packaging needs Python 3.10+. Install a current Python, or set PERCH_RELEASE_PYTHON to its executable, then rerun this command. No release was started.')
            print('Preparing the release Python environment…', flush=True)
            subprocess.run([str(source), '-m', 'venv', str(ENVIRONMENT)], check=True)
        # Validate imports, pinned top-level versions and transitive dependencies on reuse.
        # A failed or incomplete pip install is retried on the next invocation.
        probe = '''import importlib.metadata as metadata
import dmgbuild
from pathlib import Path
import sys
for line in Path(sys.argv[1]).read_text().splitlines():
    if not line.strip() or line.lstrip().startswith('#'): continue
    name, version = line.strip().split('==', 1)
    assert metadata.version(name) == version
'''
        ready = subprocess.run([str(python), '-c', probe, str(REQUIREMENTS)], capture_output=True).returncode == 0
        if ready:
            ready = subprocess.run([str(python), '-m', 'pip', 'check'], capture_output=True).returncode == 0
        if not ready:
            print('Installing or repairing pinned release tools…', flush=True)
            subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check', '-r', str(REQUIREMENTS)], check=True)
            subprocess.run([str(python), '-c', probe, str(REQUIREMENTS)], check=True)
            subprocess.run([str(python), '-m', 'pip', 'check'], check=True)
    return python


def main():
    parser = argparse.ArgumentParser(prog='./release.sh', description='Build, sign, notarize the app and DMG, verify, and optionally publish. Requires explicit notarization authorization. Does not install or restart Perch.', epilog='Use a fresh output folder for a new release; repeat the same command/folder to resume. Python tooling is prepared automatically. Signing keys and the Perch notarization profile stay in Keychain.')
    parser.add_argument('--output', type=Path, help='Release folder (required unless --prepare-tools); reused on retry')
    parser.add_argument('--profile', default='Perch', help='notarytool Keychain profile (default: Perch)')
    parser.add_argument('--publish', action='store_true', help='Also push source and publish the verified GitHub release and Sparkle feed')
    parser.add_argument('--source-ref', help='Resume an existing candidate from this exact source commit')
    parser.add_argument('--wait-seconds', type=int, default=3600, help='Wait limit per Apple submission (default: 3600)')
    parser.add_argument('--prepare-tools', action='store_true', help='Only prepare/repair Python packaging tools; no signing, notarization or publishing')
    args = parser.parse_args()
    if args.prepare_tools:
        if args.output or args.publish or args.source_ref:
            parser.error('--prepare-tools cannot be combined with a release output, publication or source ref')
    elif args.output is None:
        parser.error('Choose --output for this release, or --prepare-tools to prepare tooling only')
    if args.wait_seconds < 0:
        parser.error('--wait-seconds must be nonnegative')
    python = prepare_tools()
    if args.prepare_tools:
        print('Release tools ready. No release started.')
        return
    command = [str(python), str(REPO / 'Tools/release-all.py'), '--output', str(args.output.resolve()),
               '--profile', args.profile, '--wait-seconds', str(args.wait_seconds)]
    if args.publish:
        command.append('--publish')
    if args.source_ref:
        command += ['--source-ref', args.source_ref]
    raise SystemExit(subprocess.run(command, cwd=REPO).returncode)


if __name__ == '__main__':
    try:
        main()
    except (OSError, subprocess.SubprocessError) as error:
        raise SystemExit('Release command failed: ' + str(error) + '. Fix the reported error and rerun with the same output folder.')
