#!/usr/bin/env python3
"""Exercise keyboard and mouse sharing between the two guests, hard.

Every synthetic event is posted inside the guest that currently has control.
The other guest records what arrives, so a crossing is judged by what the
receiving machine actually saw, not by what Perch claims.
"""
from __future__ import annotations
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import lab

TRACE = '/tmp/desk-lab-trace.jsonl'


def start_recorder(address: str, seconds: float) -> subprocess.Popen:
    lab.run_in(address, f'rm -f {TRACE}', check=False)
    return subprocess.Popen(lab.ssh_command(address, f'/tmp/desk-lab-guest record {seconds} {TRACE}'),
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def read_trace(address: str, into: Path) -> list[dict]:
    lab.copy_from(address, TRACE, into)
    if not into.exists():
        return []
    samples = []
    for line in into.read_text().splitlines():
        try:
            samples.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return samples


def clock_offset(address: str) -> float:
    """Wall clock minus this guest's uptime clock, so traces can be compared."""
    raw = json.loads(lab.run_in(address, '/tmp/desk-lab-guest clock'))
    return raw['wall'] - raw['uptime']


def screen(address: str) -> tuple[float, float]:
    raw = json.loads(lab.run_in(address, '/tmp/desk-lab-guest screen'))
    return raw['width'], raw['height']


def drive_move(address: str, x: float, y: float) -> None:
    lab.run_in(address, f'/tmp/desk-lab-guest drive move {x:.0f} {y:.0f}', timeout=30)


def drive_drag(address: str, start: tuple[float, float], end: tuple[float, float], steps: int, pause: float, held: bool) -> None:
    lab.run_in(address, f'/tmp/desk-lab-guest drive drag {start[0]:.0f} {start[1]:.0f} {end[0]:.0f} {end[1]:.0f} '
                        f'{steps} {pause} {"held" if held else "free"}', timeout=120)


def drive_type(address: str, keycodes: list[int], flags: int, repeats: int, pause: float) -> None:
    codes = ','.join(str(code) for code in keycodes)
    lab.run_in(address, f'/tmp/desk-lab-guest drive type {codes} {flags} {repeats} {pause}', timeout=120)


def crossings(addresses: dict[str, str], out: Path, rounds: int = 60) -> dict:
    """Push the pointer across the shared edge again and again, slow and fast.

    Each crossing is driven on one guest; the other guest must start receiving
    Perch-tagged pointer events inside that crossing's own window. The gap
    between driving and the first received event is the switch latency.
    """
    names = list(addresses)
    offsets = {name: clock_offset(addresses[name]) for name in names}
    width = {name: screen(addresses[name])[0] for name in names}
    height = {name: screen(addresses[name])[1] for name in names}
    duration = rounds * 2.5 + 30
    recorders = {name: start_recorder(addresses[name], duration) for name in names}
    time.sleep(3)
    plan = []
    for index in range(rounds):
        source, target = (names[0], names[1]) if index % 2 == 0 else (names[1], names[0])
        style = ['slow', 'fast', 'diagonal', 'held'][index % 4]
        steps, pause = {'slow': (60, 0.01), 'fast': (4, 0.0), 'diagonal': (25, 0.004), 'held': (30, 0.006)}[style]
        start = (width[source] * 0.5, height[source] * 0.5)
        end = (width[source] - 1, height[source] * (0.5 if style != 'diagonal' else 0.15))
        sent = time.time()
        drive_drag(addresses[source], start, end, steps, pause, style == 'held')
        plan.append({'index': index, 'source': source, 'target': target, 'style': style,
                     'sent': sent, 'finished': time.time()})
        time.sleep(0.4)
    for recorder in recorders.values():
        recorder.wait(timeout=duration + 60)
    traces = {name: read_trace(addresses[name], out / f'trace-{name}.jsonl') for name in names}
    return {'plan': plan, 'offsets': offsets, 'traces': {name: len(trace) for name, trace in traces.items()},
            'analysis': analyse(plan, traces, offsets)}


def per_crossing(plan: list[dict], traces: dict[str, list[dict]], offsets: dict[str, float],
                 grace: float = 2.0, lead: float = 0.25) -> list[dict]:
    """Judge each crossing on its own, in one record per crossing.

    Traces carry each guest's own uptime clock, so every sample is converted
    with that guest's offset first. A guest is the receiver for half the
    crossings, so Perch-tagged input only counts as an echo when it lands on
    the driving machine during that crossing.
    """
    def tagged(name: str, window: tuple[float, float]) -> list[float]:
        offset = offsets.get(name, 0.0)
        return sorted(sample['at'] + offset for sample in traces.get(name, [])
                      if sample.get('fromPerch') and window[0] <= sample['at'] + offset <= window[1])

    records = []
    ordered_plan = sorted(plan, key=lambda step: step['sent'])
    for position, step in enumerate(ordered_plan):
        # Windows must not overlap: each guest receives during the next
        # crossing, and that must never be read as an echo of this one.
        following = ordered_plan[position + 1]['sent'] if position + 1 < len(ordered_plan) else float('inf')
        window = (step['sent'] - lead, min(step.get('finished', step['sent']) + grace, following))
        received = tagged(step['target'], window)
        records.append({'index': step['index'], 'style': step.get('style', ''),
                        'source': step['source'], 'target': step['target'],
                        'latency': (max(0.0, received[0] - step['sent']) if received else None),
                        'echoed': bool(tagged(step['source'], window))})
    return records


def analyse(plan: list[dict], traces: dict[str, list[dict]], offsets: dict[str, float],
            grace: float = 2.0, lead: float = 0.25) -> dict:
    """Summarise every crossing: what never arrived, what came back, what stuck."""
    records = per_crossing(plan, traces, offsets, grace, lead)
    missed = [r['index'] for r in records if r['latency'] is None]
    echoed = [r['index'] for r in records if r['echoed']]
    latencies = [r['latency'] for r in records if r['latency'] is not None]
    stuck = []
    for name, trace in traces.items():
        downs = len([s for s in trace if s['kind'] in ('keyDown', 'leftMouseDown')])
        ups = len([s for s in trace if s['kind'] in ('keyUp', 'leftMouseUp')])
        if downs > ups:
            stuck.append(name)
    summary = {'crossings': len(plan), 'missed': missed, 'echoed': echoed, 'stuck': stuck}
    if latencies:
        ordered = sorted(latencies)
        summary['latency_seconds'] = {'median': statistics.median(ordered), 'worst': ordered[-1]}
    return summary


def typing(addresses: dict[str, str], out: Path) -> dict:
    """Type through switches: bursts, modifier chords, repeats, mid-chord moves."""
    names = list(addresses)
    recorders = {name: start_recorder(addresses[name], 90) for name in names}
    time.sleep(3)
    shift, command, option = 1 << 17, 1 << 20, 1 << 19
    for index, source in enumerate(names * 3):
        drive_type(addresses[source], [0, 1, 2, 3], 0, 4, 0.01)              # plain burst
        drive_type(addresses[source], [8], command | shift, 2, 0.02)          # chord
        drive_type(addresses[source], [6], option, 6, 0.005)                  # repeats
        width, height = screen(addresses[source])
        drive_move(addresses[source], width - 1, height * 0.5)                # switch mid-sequence
        time.sleep(0.3)
    for recorder in recorders.values():
        recorder.wait(timeout=150)
    traces = {name: read_trace(addresses[name], out / f'typing-{name}.jsonl') for name in names}
    stuck = {}
    for name, trace in traces.items():
        downs = len([s for s in trace if s['kind'] == 'keyDown'])
        ups = len([s for s in trace if s['kind'] == 'keyUp'])
        flags = [s for s in trace if s['kind'] == 'flagsChanged']
        stuck[name] = {'keyDown': downs, 'keyUp': ups, 'unbalanced': downs - ups,
                       'modifiers_left_on': bool(flags and flags[-1].get('flags')) }
    return {'per_guest': stuck}
