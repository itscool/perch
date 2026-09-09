#!/usr/bin/env python3
"""Inventory UI construction sites and enforce shared interaction ownership.
This is a source coverage gate, not evidence that native clicks work.
New routes must be audited and recorded in dialog-routes.json and the UI ledger.
"""
import json, re, sys
from pathlib import Path
repo = Path(__file__).resolve().parents[1]
patterns = {
    'alert': r'\bNSAlert\(', 'picker': r'\bNSOpenPanel\(',
    'panel': r'\bNSPanel\(', 'task-page': r'\bSettingsTaskPage\(title:',
    'page': r'(?:SettingsWindow\.shared|host)\.show\(',
    'menu-page': r'SettingsWindow\.shared\.list\(',
    'menu-entry': r'(?<!func )\bchooseSafetyAction\(title:',
}
found = {}
errors = []
for file in sorted((repo/'Sources').glob('*.swift')):
    if file.name.endswith('Tests.swift'): continue
    function = 'declaration'; counts = {}
    for number, line in enumerate(file.read_text().splitlines(), 1):
        match = re.search(r'\bfunc\s+(\w+)',line)
        if match: function = match[1]
        if file.name != 'SettingsWindow.swift' and re.search(r'\b(?:NSApp|NSApplication\.shared)\.(?:stopModal|abortModal|runModal|beginModalSession)\(',line):
            errors.append(f'{file.name}:{number}: modal session control must stay in SettingsWindow')
        if file.name != 'SettingsWindow.swift' and re.search(r'(?:SettingsWindow\.shared|host)\.run\(',line):
            errors.append(f'{file.name}:{number}: app-owned alerts must use asynchronous present, not the fixture-only run adapter')
        for kind, pattern in patterns.items():
            if not re.search(pattern,line): continue
            scope = f'{file.name}:{function}:{kind}'
            counts[scope] = counts.get(scope,0)+1
            key = f'{scope}:{counts[scope]}'
            found[key] = {'file': file.name, 'line': number, 'kind': kind}
if '--inventory' in sys.argv:
    print(json.dumps(found,indent=2)); sys.exit(0)
known = json.loads((repo/'Tools/dialog-routes.json').read_text())
for key in sorted(set(found)-set(known)):
    errors.append('Unreviewed UI route: '+key)
for key in sorted(set(known)-set(found)):
    errors.append('Removed/renamed UI route needs ledger update: '+key)
for key, value in known.items():
    if not value.get('review') or not value.get('acceptance'):
        errors.append('Missing evidence boundary: '+key)
if errors:
    print('\n'.join(errors),file=sys.stderr); sys.exit(1)
print(f'PASS: {len(found)} UI construction sites inventoried; no unscoped modal control outside shared host')
