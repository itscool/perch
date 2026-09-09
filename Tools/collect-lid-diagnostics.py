#!/usr/bin/env python3
"""Collect bounded, read-only sleep evidence; never enable, disable or request sleep."""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import plistlib
import re
import subprocess


def command(arguments):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=20)
        if result.returncode:
            return {'error': result.stderr.strip()[:1000], 'exit_code': result.returncode}
        return result.stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        return {'error': str(error)}


def bundle_version(path):
    try:
        info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
        return {'version': info.get('CFBundleShortVersionString'), 'build': info.get('CFBundleVersion')}
    except (OSError, ValueError) as error:
        return {'error': str(error)}


def sleep_events(text, start, end):
    if not isinstance(text, str):
        return text
    kept = []
    for line in text.splitlines():
        match = re.match(r'^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [+-]\d{4})\s+(Sleep|Wake|DarkWake)\s', line)
        if match:
            when = datetime.strptime(match[1], '%Y-%m-%d %H:%M:%S %z')
            if start <= when <= end:
                kept.append(line.strip()[:1500])
    return kept[-1024:]


def clamshell_events(text):
    if not isinstance(text, str):
        return text
    # Keep only powerd's clamshell messages, not the log command's headings.
    lines = [line.strip() for line in text.splitlines()
             if re.match(r'^\d{4}-\d\d-\d\d ', line) and 'powerd[' in line
             and 'clamshell' in line.lower()]
    return {'entries': [line[:1500] for line in lines[-1024:]],
            'truncated': len(lines) > 1024 or any(len(line) > 1500 for line in lines)}


def collect(app, hours):
    now = datetime.now(timezone.utc)
    start = now - timedelta(hours=hours)
    epoch = datetime(2001, 1, 1, tzinfo=timezone.utc)
    try:
        path = Path('/var/db/local.scott.perch.lid-activity/events.json')
        if path.stat().st_size > 4 * 1024 * 1024:
            raise ValueError('Lid history exceeds its expected 4 MiB bound')
        entries = json.loads(path.read_text())
        events = []
        for event in entries:
            when = epoch + timedelta(seconds=event['date'])
            if start <= when <= now:
                events.append({'time': when.astimezone().isoformat(),
                               'source': event['source'][:40], 'message': event['message'][:512]})
        events = sorted(events, key=lambda event: event['time'])[-1024:]
    except (OSError, ValueError, TypeError, KeyError, OverflowError) as error:
        events = {'error': str(error)}
    registry = command(['/usr/sbin/ioreg', '-r', '-k', 'AppleClamshellState', '-d', '4'])
    if isinstance(registry, str):
        registry = [line.strip() for line in registry.splitlines()
                    if re.search(r'"AppleClamshell(State|CausesSleep)"\s*=', line)]
    versions = {'app': bundle_version(app),
                'input_and_safety_helper': bundle_version(Path.home() / 'Library/Application Support/Perch/Safety/Perch Helper.app'),
                'lid_helper': bundle_version(Path('/Library/PrivilegedHelperTools/Perch Lid Helper.app'))}
    return {
        'captured_at': now.astimezone().isoformat(), 'hours': hours,
        'evidence_limits': [
            'Read-only snapshot. No power, hardware, permission or helper changes were made.',
            'Bundle versions describe files on disk, not proof of the running process version.',
            'AppleClamshellCausesSleep is cached; it cannot verify continued lid-sleep prevention.',
            'Missing sleep entries are not proof that sleep did not occur. Helper gaps are not reconstructed.',
            'powerd clamshell messages explain observed OS decisions; missing or redacted messages do not establish effective protection.',
        ],
        'os': command(['/usr/bin/sw_vers']),
        'hardware_model': command(['/usr/sbin/sysctl', '-n', 'hw.model']),
        'bundle_versions': versions,
        'current_power': command(['/usr/bin/pmset', '-g', 'batt']),
        'clamshell_properties': registry,
        'perch_lid_events': events,
        'macos_sleep_events': sleep_events(command(['/usr/bin/pmset', '-g', 'log']), start, now),
        'macos_clamshell_events': clamshell_events(command([
            '/usr/bin/log', 'show', '--start', start.astimezone().strftime('%Y-%m-%d %H:%M:%S'),
            '--end', now.astimezone().strftime('%Y-%m-%d %H:%M:%S'), '--style', 'compact',
            '--predicate', 'process == "powerd" AND eventMessage CONTAINS[c] "clamshell"',
        ])),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path, help='Installed Perch.app path')
    parser.add_argument('--output', required=True, type=Path, help='New JSON report file; never overwrites an existing file')
    parser.add_argument('--hours', type=int, choices=range(1, 25), default=24)
    args = parser.parse_args()
    report = collect(args.app.resolve(), args.hours)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as file:
        json.dump(report, file, indent=2)
        file.write('\n')
    print(f'Read-only report saved: {args.output.resolve()}')
