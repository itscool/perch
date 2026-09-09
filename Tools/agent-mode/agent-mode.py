#!/usr/bin/env python3
"""Explicit desktop test-session indicator. Check immediately before every UI batch."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time
import uuid


def write(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex)
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def check(directory, state):
    token = state['token']
    if state['phase'] != 'active':
        raise RuntimeError('Agent mode is stopped. Do not interact with the UI.')
    if (directory / 'control-requested').exists():
        raise RuntimeError('USER REQUESTED CONTROL. Stop UI actions and acknowledge with stop.')
    if time.time() >= state['expires']:
        raise RuntimeError('Agent mode expired. Stop and announce a new session before restarting.')
    if (directory / 'ready').read_text() != token:
        raise RuntimeError('Banner has not acknowledged this session. Do not interact.')
    os.kill(state['pid'], 0)
    command = subprocess.check_output(['/bin/ps', '-p', str(state['pid']), '-o', 'command='], text=True)
    if token not in command or str(directory / 'Agent Mode.app/Contents/MacOS/agent-banner') not in command:
        raise RuntimeError('Banner process identity changed. Do not interact.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['start', 'check', 'status', 'stop'])
    parser.add_argument('--session', required=True, type=Path)
    args = parser.parse_args()
    directory = args.session.resolve()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Serialize start/check/stop so a late renewal cannot undo a stop.
    with (directory / 'session.lock').open('a') as session_lock:
        fcntl.flock(session_lock, fcntl.LOCK_EX)
        run_command(args.command, directory)


def run_command(command, directory):
    path = directory / 'session.json'
    if command == 'start':
        if path.exists() and json.loads(path.read_text())['phase'] == 'active':
            raise RuntimeError('A session already exists. Stop it explicitly before starting another.')
        source = Path(__file__).with_name('main.swift')
        bundle = directory / 'Agent Mode.app'
        binary = bundle / 'Contents/MacOS/agent-banner'
        binary.parent.mkdir(parents=True, exist_ok=True)
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(
            CFBundleIdentifier='local.perch.agent-mode-testing', CFBundleName='Agent Mode',
            CFBundleExecutable='agent-banner', CFBundlePackageType='APPL', LSUIElement=True)))
        if not binary.exists() or source.stat().st_mtime > binary.stat().st_mtime:
            subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary), '-framework', 'AppKit', '-warnings-as-errors'], check=True)
        for name in ['ready', 'control-requested']:
            (directory / name).unlink(missing_ok=True)
        state = dict(token=uuid.uuid4().hex, phase='active', expires=time.time() + 90)
        write(path, state)
        with (directory / 'banner.log').open('a') as log:
            process = subprocess.Popen([str(binary), str(directory), state['token']], stdout=log, stderr=log, start_new_session=True)
        state['pid'] = process.pid
        write(path, state)
        for _ in range(100):
            if (directory / 'ready').exists() or process.poll() is not None:
                break
            time.sleep(.1)
        try:
            check(directory, state)
        except Exception:
            state['phase'] = 'stopped'; write(path, state)
            raise
        print('AGENT MODE visible. Check before each UI batch; stop when finished.')
        return
    state = json.loads(path.read_text())
    if command == 'stop':
        state['phase'] = 'stopped'
        write(path, state)
        print('Agent mode ended. Do not perform further UI actions in this session.')
    elif command == 'check':
        check(directory, state)
        state['expires'] = time.time() + 90
        write(path, state)
        # Do not lose a request made during the heartbeat write.
        check(directory, state)
        print('AGENT MODE active; no control request. Lease renewed for 90 seconds.')
    else:
        check(directory, state)
        print('AGENT MODE active; no control request.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
