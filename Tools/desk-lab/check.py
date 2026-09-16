#!/usr/bin/env python3
"""Check the lab's own judgement without guests: seeding and trace analysis.

A lab that mis-reads its traces would hide desk bugs, so its analysis is
tested the same way the rest of the repo is: headless and in seconds.
"""
import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import prepare as preparation
import sharing
import seed as seeder


def check(value: bool, message: str) -> None:
    if not value:
        raise SystemExit(f'FAIL: {message}')


def sample(at, kind, from_perch=False, key=None, x=10.0):
    return {'at': at, 'kind': kind, 'x': x, 'y': 10.0, 'key': key, 'flags': 0, 'fromPerch': from_perch}


# Two crossings, one in each direction, on guests whose clocks differ wildly.
plan = [{'index': 0, 'source': 'perch-a', 'target': 'perch-b', 'style': 'slow', 'sent': 1000.0, 'finished': 1000.5},
        {'index': 1, 'source': 'perch-b', 'target': 'perch-a', 'style': 'fast', 'sent': 1002.0, 'finished': 1002.2}]
offsets = {'perch-a': 900.0, 'perch-b': 500.0}   # wall = sample time + offset

clean = {'perch-a': [sample(102.15, 'mouseMoved', True)],    # wall 1002.15, its own crossing
         'perch-b': [sample(500.20, 'mouseMoved', True)]}    # wall 1000.20, its own crossing
result = sharing.analyse(plan, clean, offsets)
check(result['missed'] == [] and result['echoed'] == [] and result['stuck'] == [], f'clean run misjudged: {result}')
check(abs(result['latency_seconds']['worst'] - 0.2) < 0.01, f"latency wrong: {result['latency_seconds']}")

# Tagged input after a crossing's window closes is not an echo of it.
late = {'perch-a': [sample(103.0, 'mouseMoved', True)], 'perch-b': [sample(500.20, 'mouseMoved', True)]}
check(sharing.analyse([plan[0]], late, offsets)['echoed'] == [], 'input outside the crossing window counted as an echo')

# A crossing the other machine never saw is missed.
missed = {'perch-a': [sample(102.15, 'mouseMoved', True)], 'perch-b': []}
check(sharing.analyse(plan, missed, offsets)['missed'] == [0], 'a missed crossing was not caught')

# Perch-tagged input landing on the driving machine during its own crossing is an echo.
echo = {'perch-a': [sample(100.10, 'mouseMoved', True), sample(102.15, 'mouseMoved', True)],
        'perch-b': [sample(500.20, 'mouseMoved', True)]}
check(sharing.analyse(plan, echo, offsets)['echoed'] == [0], 'an echo back to the sender was not caught')

# A key that went down and never came up is stuck.
stuck = dict(clean); stuck['perch-a'] = clean['perch-a'] + [sample(102.30, 'keyDown', key=8)]
check(sharing.analyse(plan, stuck, offsets)['stuck'] == ['perch-a'], 'a stuck key was not caught')

# A crossing must arrive at the edge it entered, not somewhere else on the screen.
edges = [dict(plan[0], rightward=True, target_width=1600.0)]
near = {'perch-a': [], 'perch-b': [sample(500.20, 'mouseMoved', True, x=8.0)]}
far = {'perch-a': [], 'perch-b': [sample(500.20, 'mouseMoved', True, x=1200.0)]}
check(sharing.analyse(edges, near, offsets)['mislanded'] == [], 'a crossing that landed on the edge was called wrong')
check(sharing.analyse(edges, far, offsets)['mislanded'] == [0], 'a crossing that landed far from the edge was not caught')

# The recorder spells event kinds as Swift renders them, so the analysis must
# understand both that spelling and the plain names.
check(sharing.kind_of({'kind': 'CGEventType(rawValue: 10)'}) == 'keyDown', 'a raw-valued key event was not recognised')
check(sharing.kind_of({'kind': 'keyDown'}) == 'keyDown', 'a named key event was not recognised')
check(sharing.is_pointer({'kind': 'CGEventType(rawValue: 5)'}), 'raw-valued pointer motion was not recognised')
check(not sharing.is_pointer({'kind': 'CGEventType(rawValue: 12)'}), 'a modifier change was counted as pointer motion')
raw_stuck = {'perch-a': [sample(102.15, 'CGEventType(rawValue: 1)', True)]}
check(sharing.analyse([plan[0]], raw_stuck, offsets)['stuck'] == ['perch-a'], 'a raw-valued button left down was not caught')

# Typing must not pass on an empty capture, and must catch keys or modifiers left behind.
def guests(down, up, modifiers=False, held=False):
    return {'per_guest': {'perch-a': {'keyDown': down, 'keyUp': up, 'unbalanced': down - up,
                                      'ends_held': held, 'modifiers_left_on': modifiers}}}

check(sharing.judge_typing(guests(0, 0))[0] is False, 'typing passed although nothing was captured')
check(sharing.judge_typing(guests(40, 38))[0] is True, 'sampling loss was mistaken for a stuck key')
check(sharing.judge_typing(guests(40, 40, held=True))[0] is False, 'a key still down was not caught')
check(sharing.judge_typing(guests(40, 40, modifiers=True))[0] is False, 'a modifier left on was not caught')
check(sharing.judge_typing(guests(40, 40))[0] is True, 'a clean typing run was failed')

# Seeding produces a desk both guests can verify, and two distinct identities.
with tempfile.TemporaryDirectory(prefix='perch-desk-lab-') as directory:
    output = seeder.seed(Path(directory))
    files = {path.name for path in output.iterdir()}
    check({'desk-a.json', 'desk-b.json', 'identity-a.json', 'identity-b.json'} <= files, f'seeding is incomplete: {files}')
    check((output / 'identity-a.json').read_bytes() != (output / 'identity-b.json').read_bytes(), 'both guests got one identity')

    # A seeded pair must pin exactly the identities it installs. A desk that
    # pins anything else refuses every connection as a bad certificate, which
    # reads as a timeout on the other side and wastes a whole run.
    identities = {label: json.loads((output / f'identity-{label}.json').read_text()) for label in ('a', 'b')}
    check(identities['a']['id'] != identities['b']['id'], 'both guests were given the same identity id')
    for label in ('a', 'b'):
        pinned = {peer.get('certificate') for peer in
                  preparation.pinned_peers((output / f'desk-{label}.json').read_text())}
        missing = [name for name, identity in identities.items() if identity['certificate'] not in pinned]
        check(not missing, f'desk-{label} does not pin the identity of: {", ".join(missing)}')

print('PASS: lab analysis converts both guests to one clock and catches missed crossings, echoes and stuck keys; seeding writes a verifiable paired desk whose two sides pin each other; crossings are judged on where they land; typing passes only on captured keystrokes')
