#!/usr/bin/env python3
"""Inventory UI construction sites and enforce shared interaction ownership.
This is a source coverage gate, not evidence that native clicks work.
New routes must be audited and recorded in dialog-routes.json and the UI ledger.
"""
import json, re, sys
from pathlib import Path
repo = Path(__file__).resolve().parents[1]
patterns = {
    'about-panel': r'\bNSApp\.orderFrontStandardAboutPanel\(',
    'alert': r'\bNSAlert\(', 'picker': r'\bNSOpenPanel\(',
    'panel': r'\b(?:NSPanel|SettingsPanel|CountdownPanel)\(', 'task-page': r'\bSettingsTaskPage\(title:',
    'page': r'(?:SettingsWindow\.shared|host)\.show\(',
    'menu-page': r'SettingsWindow\.shared\.list\(',
    'menu-entry': r'(?<!func )\bchooseSafetyAction\(title:',
}
found = {}
errors = []
for file in sorted((repo/'Sources').rglob('*.swift')):
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

# Page lifetime. A page object that shows itself must stay alive while its page
# is visible, or its weak button and refresh callbacks silently do nothing (the
# September 15 Setup & status regression). Pass owner: self, capture self
# strongly in leave/refresh/poll, or record why another owner holds it.
RETAINED_ELSEWHERE = {
    'SettingsWindow': 'the shared window itself',
    'PermissionSetup': 'AppDelegate.permissionSetup keeps it',
    'EventCollectorSetup': 'shared singleton',
    'PerchUpdater': 'shared singleton',
    'DeskConnectionLogPage': 'shows a plain view; no callback references the object',
}
def show_calls(text):
    lines = text.splitlines(keepends=True)
    kind = name = None
    offset = 0
    starts = []
    for line in lines:
        declaration = re.match(r'(?:(?:final|private|fileprivate|public|internal)\s+)*(class|struct|enum|extension)\s+(\w+)', line)
        if declaration: kind, name = declaration.groups()
        for match in re.finditer(r'(?:SettingsWindow\.shared|\bhost)\.show\(', line):
            if re.match(r'\s*func ', line): continue
            starts.append((offset + match.end(), kind, name))
        offset += len(line)
    for start, kind, name in starts:
        depth, index = 1, start
        while depth and index < len(text):
            depth += {'(': 1, ')': -1}.get(text[index], 0); index += 1
        yield kind, name, text[start:index], text.count('\n', 0, start) + 1
def unretained(text):
    return [(name, line) for kind, name, call, line in show_calls(text)
            if kind == 'class' and name not in RETAINED_ELSEWHERE and 'owner: self' not in call and '[self]' not in call]
fixture = 'final class FixturePage {\n    func show() {\n        SettingsWindow.shared.show(.init(title: "Fixture", detail: "", view: view, refresh: { [weak self] in self?.refresh() }))\n    }\n}\n'
assert unretained(fixture) == [('FixturePage', 3)], 'page lifetime scan no longer detects an unretained page'
assert not unretained(fixture.replace('[weak self] in self?.refresh() }', '[weak self] in self?.refresh() }, owner: self')), 'page lifetime scan rejects a retained page'
for file in sorted((repo/'Sources').rglob('*.swift')):
    for name, line in unretained(file.read_text()):
        errors.append(f'{file.name}:{line}: {name} shows a page without keeping itself alive; pass owner: self')

# Termination. A direct terminate called inside a main-queue block waits for
# replies that are themselves queued on the main queue (the September 15 Quit
# and Reset hang). Every terminate goes through AppTermination.request().
for file in sorted((repo/'Sources').rglob('*.swift')):
    if file.name == 'TerminationReply.swift': continue
    for number, line in enumerate(file.read_text().splitlines(), 1):
        if re.search(r'\b(?:NSApp|NSApplication\.shared)\.terminate\(', line):
            errors.append(f'{file.name}:{number}: NSApp.terminate outside AppTermination; call AppTermination.request()')

# Navigation targets. Setup stage ids passed as strings must name a setup-stage
# sidebar destination, or navigation silently does nothing; destination ids are
# unique; every sidebar page title is shown by some page.
routes = (repo/'Sources/Settings/SettingsNavigationRoutes.swift').read_text()
destinations = re.findall(r'item\("([a-z-]+)", "[^"]*", \[([^\]]*)\], #selector\(\w+\)((?:, depth: \d)?(?:, setupStage: true)?)\)', routes)
ids = [d[0] for d in destinations]
if len(destinations) < 20: errors.append('Could not read the Settings sidebar destinations')
if len(ids) != len(set(ids)): errors.append('Duplicate Settings sidebar destination id')
stages = {d[0] for d in destinations if 'setupStage: true' in d[2]}
sources_text = {file: file.read_text() for file in (repo/'Sources').rglob('*.swift')}
for file, text in sources_text.items():
    for stage in re.findall(r'(?:openSetupStage|navigateToSetupStage)\("([a-z-]+)"\)', text):
        if stage not in stages: errors.append(f'{file.name}: setup stage "{stage}" has no setup-stage destination; navigation would do nothing')
for identifier, titles, _ in destinations:
    for title in re.findall(r'"([^"]+)"', titles):
        if not any(f'"{title}"' in text for file, text in sources_text.items() if file.name != 'SettingsNavigationRoutes.swift'):
            errors.append(f'Sidebar destination "{identifier}" names page "{title}", which no page shows')
if errors:
    print('\n'.join(errors),file=sys.stderr); sys.exit(1)
print(f'PASS: {len(found)} UI construction sites inventoried; no unscoped modal control outside shared host; every self-shown page retained; setup stages and sidebar pages resolve')
