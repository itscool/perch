#!/usr/bin/env python3
"""Fetch the pinned upstream binary; never execute an unverified download."""
import hashlib
import fcntl
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

VERSION = '2.9.6'
SHA256 = '52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192'
ROOT = Path(__file__).resolve().parents[1] / 'build/dependencies'

def valid_archive(archive):
    return archive.is_file() and not archive.is_symlink() and archive.stat().st_size <= 40 * 1024 * 1024 and hashlib.sha256(archive.read_bytes()).hexdigest() == SHA256

def fetch(archive):
    # System curl uses macOS certificate handling, independent of Python's CA bundle.
    # Ignore user curl config; neither TLS validation nor the pinned digest is optional.
    url = f'https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/{archive.name}'
    with tempfile.NamedTemporaryFile(dir=archive.parent, prefix='.sparkle-', delete=False) as stream:
        temporary = Path(stream.name)
    try:
        subprocess.run(['/usr/bin/curl', '-q', '--fail', '--location', '--silent', '--show-error',
                        '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '15',
                        '--max-time', '120', '--retry', '2', '--retry-max-time', '60',
                        '--max-filesize', str(40 * 1024 * 1024), '--output', str(temporary), url], check=True)
        if not valid_archive(temporary):
            raise SystemExit('Downloaded Sparkle failed its pinned checksum. Nothing was extracted. Retry later; do not disable verification or change the pin to accept this download.')
        temporary.replace(archive)
    except subprocess.CalledProcessError as error:
        raise SystemExit(f'Sparkle download failed (curl {error.returncode}). Check network/proxy access to GitHub and macOS certificate trust, then rerun the build; it will retry automatically. Python certificate installation is not required.')
    finally:
        temporary.unlink(missing_ok=True)

def dependency():
    ROOT.mkdir(parents=True, exist_ok=True)
    with (ROOT / '.sparkle-lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        archive = ROOT / f'Sparkle-{VERSION}.tar.xz'
        if not valid_archive(archive):
            print('Repairing cached Sparkle download…' if archive.exists() else f'Downloading Sparkle {VERSION}…', file=sys.stderr)
            fetch(archive)
        destination = ROOT / f'sparkle-{VERSION}'
        # A fresh extraction also repairs missing/edited framework files and removes
        # unexpected extras. Only the verified, pinned archive is ever extracted.
        with tempfile.TemporaryDirectory(dir=ROOT, prefix='.sparkle-unpack-') as temporary:
            extracted = Path(temporary) / 'contents'; extracted.mkdir()
            subprocess.run(['/usr/bin/tar', '-xf', str(archive), '-C', str(extracted)], check=True)
            for name in ('Sparkle.framework/Sparkle', 'Sparkle.framework/Modules/module.modulemap', 'LICENSE', 'bin/sign_update'):
                if not (extracted/name).is_file(): raise SystemExit('Verified Sparkle archive has an unexpected layout: '+name)
            if destination.is_symlink() or destination.is_file(): destination.unlink()
            elif destination.exists(): shutil.rmtree(destination)
            extracted.rename(destination)
        return destination

if __name__ == '__main__':
    try:
        print(dependency())
    except (OSError, subprocess.SubprocessError) as error:
        raise SystemExit('Could not prepare Sparkle: '+str(error)+'. Check free space and permissions in build/dependencies, then rerun the build.')
