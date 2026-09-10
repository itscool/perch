#!/usr/bin/env python3
"""Exercise fresh/corrupt/offline dependency repair without keys or network."""
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tarfile
import tempfile
from unittest.mock import patch

def load(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

sparkle = load('sparkle_fixture', 'sparkle-dependency.py')
preflight = load('preflight_fixture', 'build-preflight.py')
real_run = subprocess.run
with tempfile.TemporaryDirectory(prefix='perch-dependency-tests-') as directory:
    root = Path(directory); content = root/'source'; content.mkdir()
    for name in ('Sparkle.framework/Sparkle', 'Sparkle.framework/Modules/module.modulemap', 'LICENSE', 'bin/sign_update'):
        file = content/name; file.parent.mkdir(parents=True, exist_ok=True); file.write_text('fixture '+name)
    packed = root/'fixture.tar'
    with tarfile.open(packed, 'w') as archive: archive.add(content, arcname='.')
    payload = packed.read_bytes(); sparkle.SHA256 = hashlib.sha256(payload).hexdigest()
    sparkle.ROOT = root/'cache'
    calls = []
    def download(command, **options):
        calls.append(command)
        if command[0] == '/usr/bin/curl':
            assert command[1] == '-q' and '--proto' in command and '=https' in command and '--insecure' not in command
            Path(command[command.index('--output')+1]).write_bytes(payload)
            return subprocess.CompletedProcess(command, 0)
        return real_run(command, **options)
    with patch.object(sparkle.subprocess, 'run', side_effect=download):
        destination = sparkle.dependency()
        assert (destination/'LICENSE').read_text() == 'fixture LICENSE'
        assert sum(c[0] == '/usr/bin/curl' for c in calls) == 1
        (destination/'LICENSE').write_text('edited cache')
        (destination/'unexpected-file').write_text('not in pinned archive')
        calls.clear(); sparkle.dependency()
        assert not any(c[0] == '/usr/bin/curl' for c in calls), 'Valid cache unnecessarily required a network connection'
        assert (destination/'LICENSE').read_text() == 'fixture LICENSE' and not (destination/'unexpected-file').exists()
        (destination/'Sparkle.framework/Sparkle').unlink(); sparkle.dependency()
        assert (destination/'Sparkle.framework/Sparkle').is_file(), 'Missing framework binary was not repaired'
        archive = sparkle.ROOT/f'Sparkle-{sparkle.VERSION}.tar.xz'
        archive.write_bytes(b'interrupted download'); calls.clear(); sparkle.dependency()
        assert sum(c[0] == '/usr/bin/curl' for c in calls) == 1 and sparkle.valid_archive(archive)
    def failed_download(command, **options):
        assert command[0] == '/usr/bin/curl', 'Unverified download reached extraction'
        Path(command[command.index('--output')+1]).write_bytes(b'partial response')
        raise subprocess.CalledProcessError(60, command)
    archive.write_bytes(b'bad old cache')
    with patch.object(sparkle.subprocess, 'run', side_effect=failed_download):
        try: sparkle.dependency()
        except SystemExit as error: assert 'macOS certificate trust' in str(error)
        else: raise AssertionError('TLS failure reported success')
    assert archive.read_bytes() == b'bad old cache' and (destination/'LICENSE').read_text() == 'fixture LICENSE'
    assert not list(sparkle.ROOT.glob('.sparkle-*')) or all(p.name == '.sparkle-lock' for p in sparkle.ROOT.glob('.sparkle-*'))
    def bad_checksum(command, **options):
        assert command[0] == '/usr/bin/curl', 'Checksum failure reached extraction'
        Path(command[command.index('--output')+1]).write_bytes(b'wrong payload')
        return subprocess.CompletedProcess(command, 0)
    with patch.object(sparkle.subprocess, 'run', side_effect=bad_checksum):
        try: sparkle.dependency()
        except SystemExit as error: assert 'checksum' in str(error)
        else: raise AssertionError('Checksum verification was bypassed')

    def environment_output(*command):
        if 'security' == command[0]: return '  1) '+('A'*40)+' "Fixture Local Signing"\n'
        if '--show-sdk-version' in command: return '26.0'
        if '--version' in command: return 'Apple Swift version 6.2'
        return '/fixture/clang'
    with patch.object(preflight.sys, 'platform', 'darwin'), patch.object(preflight.platform, 'machine', return_value='arm64'), patch.object(preflight.shutil, 'which', return_value='/fixture/tool'), patch.object(preflight, 'output', side_effect=environment_output):
        preflight.environment('Fixture Local Signing')
        preflight.environment('A'*40)
        preflight.environment(None)
        try: preflight.environment('Missing release key')
        except SystemExit as error: assert 'certificate/private key' in str(error)
        else: raise AssertionError('Missing signing identity advanced to dependency preparation')
        def old_sdk(*command): return '25.0' if '--show-sdk-version' in command else environment_output(*command)
        with patch.object(preflight, 'output', side_effect=old_sdk):
            try: preflight.environment('Fixture Local Signing')
            except SystemExit as error: assert 'SDK 26' in str(error)
            else: raise AssertionError('Old SDK accepted')
print('PASS: fresh download, offline cache, corrupt archive repair, edited framework repair, TLS interruption, checksum rejection, signing identity and SDK preflight; no network or key changes')
