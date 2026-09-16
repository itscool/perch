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


def drive_drag(address: str, start: tuple[float, float], end: tuple[float, float], steps: int, pause: float,
               held: bool, push: int) -> None:
    lab.run_in(address, f'/tmp/desk-lab-guest drive drag {start[0]:.0f} {start[1]:.0f} {end[0]:.0f} {end[1]:.0f} '
                        f'{steps} {pause} {"held" if held else "free"} {push}', timeout=120)


def probe_tracking(address: str, dx: float, dy: float) -> dict:
    """Does this guest's cursor still follow input posted on it?

    When focus moves to the other Mac, Perch captures local input rather than
    letting it through, so the cursor stops tracking. Reading that from outside
    the product is the only way this lab can tell "focus never transferred"
    from "focus transferred but motion was never delivered".
    """
    raw = lab.run_in(address, f'/tmp/desk-lab-guest track {dx:.0f} {dy:.0f}', check=False, timeout=60)
    start = raw.find('{')
    if start < 0:
        return {}
    try:
        return json.loads(raw[start:])
    except json.JSONDecodeError:
        return {}


def drive_crosshold(address: str, point: tuple[float, float], push: int, keycode: int, flags: int) -> None:
    """Cross while a chord is held down, to catch a modifier left behind."""
    lab.run_in(address, f'/tmp/desk-lab-guest drive crosshold {point[0]:.0f} {point[1]:.0f} {push} {keycode} {flags}',
               timeout=120)


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
    plan, tracking = [], []
    for index in range(rounds):
        source, target = (names[0], names[1]) if index % 2 == 0 else (names[1], names[0])
        style = ['slow', 'fast', 'diagonal', 'held'][index % 4]
        steps, pause = {'slow': (60, 0.01), 'fast': (4, 0.0), 'diagonal': (25, 0.004), 'held': (30, 0.006)}[style]
        # The first guest's screen sits left of the second on the desk canvas, so
        # it crosses off its right edge and the second crosses off its left.
        # Driving both to the right would push one of them off the far side of
        # the canvas, where no screen exists.
        rightward = source == names[0]
        start = (width[source] * 0.5, height[source] * 0.5)
        end = (width[source] - 1 if rightward else 0, height[source] * (0.5 if style != 'diagonal' else 0.15))
        # A plausible per-event mouse delta, repeated against the edge.
        sent = time.time()
        drive_drag(addresses[source], start, end, steps, pause, style == 'held', 12 if rightward else -12)
        # A crossing to the right must arrive near the target's left edge, and
        # one to the left near its right edge. Anything else means the pointer
        # did not land where the shared edge says it should.
        # Occasionally ask the driving guest whether its own cursor still follows
        # posted input. Sparse, and inward, so it neither perturbs the timing
        # nor pushes another edge.
        if index % 25 == 0:
            probe = probe_tracking(addresses[source], -40 if rightward else 40, 0)
            if probe:
                tracking.append({**probe, 'index': index, 'source': source})
        plan.append({'index': index, 'source': source, 'target': target, 'style': style,
                     'sent': sent, 'finished': time.time(), 'rightward': rightward,
                     'target_width': width[target], 'target_height': height[target]})
        time.sleep(0.4)
    for recorder in recorders.values():
        recorder.wait(timeout=duration + 60)
    traces = {name: read_trace(addresses[name], out / f'trace-{name}.jsonl') for name in names}
    summary = analyse(plan, traces, offsets)
    summary['cursor_probes'] = len(tracking)
    summary['cursor_stopped_following'] = len([probe for probe in tracking if not probe.get('followed', True)])
    return {'plan': plan, 'offsets': offsets, 'traces': {name: len(trace) for name, trace in traces.items()},
            'tracking': tracking, 'analysis': summary}


EVENT_NAMES = {1: 'leftMouseDown', 2: 'leftMouseUp', 3: 'rightMouseDown', 4: 'rightMouseUp',
               5: 'mouseMoved', 6: 'leftMouseDragged', 7: 'rightMouseDragged',
               10: 'keyDown', 11: 'keyUp', 12: 'flagsChanged'}

# A crossing is pointer motion arriving on the other Mac. Perch also injects
# modifier-state events to keep the two keyboards consistent, and counting
# those as an arrival would report a crossing that never happened.
POINTER_KINDS = {'mouseMoved', 'leftMouseDragged', 'rightMouseDragged', 'leftMouseDown', 'leftMouseUp'}


def kind_of(sample: dict) -> str:
    """The event's name, however the recorder spelled it.

    Swift renders a CGEventType as "CGEventType(rawValue: 10)", so comparing a
    sample against "keyDown" matches nothing and silently reports no keys and
    no stuck buttons. Normalise once, here, rather than at each comparison.
    """
    raw = str(sample.get('kind') or '')
    if raw.startswith('CGEventType(rawValue:'):
        digits = ''.join(character for character in raw if character.isdigit())
        if digits:
            return EVENT_NAMES.get(int(digits), raw)
    return raw


def is_pointer(sample: dict) -> bool:
    return kind_of(sample) in POINTER_KINDS


PRESSES = {'keyDown', 'leftMouseDown'}
RELEASES = {'keyUp', 'leftMouseUp'}


def ends_held(trace: list[dict]) -> bool:
    """Whether this machine finished with a key or button still pressed.

    Comparing press and release totals looks equivalent but is not: the event
    tap loses a fraction of events during fast bursts, while the fixed-interval
    pointer sampler loses none, so unequal totals are ordinary sampling loss
    rather than a stuck input. Something genuinely stuck leaves a press as the
    last thing that happened.
    """
    events = sorted((sample['at'], kind_of(sample)) for sample in trace
                    if kind_of(sample) in PRESSES | RELEASES)
    return bool(events) and events[-1][1] in PRESSES


def per_crossing(plan: list[dict], traces: dict[str, list[dict]], offsets: dict[str, float],
                 grace: float = 2.0, lead: float = 0.25) -> list[dict]:
    """Judge each crossing on its own, in one record per crossing.

    Traces carry each guest's own uptime clock, so every sample is converted
    with that guest's offset first. A guest is the receiver for half the
    crossings, so Perch-tagged input only counts as an echo when it lands on
    the driving machine during that crossing.
    """
    def tagged(name: str, window: tuple[float, float], pointer_only: bool = True) -> list[dict]:
        offset = offsets.get(name, 0.0)
        found = [dict(sample, at=sample['at'] + offset) for sample in traces.get(name, [])
                 if sample.get('fromPerch') and window[0] <= sample['at'] + offset <= window[1]
                 and (is_pointer(sample) or not pointer_only)]
        return sorted(found, key=lambda sample: sample['at'])

    records = []
    ordered_plan = sorted(plan, key=lambda step: step['sent'])
    for position, step in enumerate(ordered_plan):
        # Windows must not overlap: each guest receives during the next
        # crossing, and that must never be read as an echo of this one.
        following = ordered_plan[position + 1]['sent'] if position + 1 < len(ordered_plan) else float('inf')
        window = (step['sent'] - lead, min(step.get('finished', step['sent']) + grace, following))
        received = tagged(step['target'], window)
        landing = None
        if received and step.get('target_width'):
            # The entry edge is the far side from the direction of travel.
            expected = 0.0 if step.get('rightward') else float(step['target_width']) - 1
            arrival = received[0].get('x')
            if arrival is not None:
                landing = abs(float(arrival) - expected)
        records.append({'index': step['index'], 'style': step.get('style', ''),
                        'source': step['source'], 'target': step['target'],
                        'latency': (max(0.0, received[0]['at'] - step['sent']) if received else None),
                        'landing_error': landing,
                        'echoed': bool(tagged(step['source'], window))})
    return records


def analyse(plan: list[dict], traces: dict[str, list[dict]], offsets: dict[str, float],
            grace: float = 2.0, lead: float = 0.25) -> dict:
    """Summarise every crossing: what never arrived, what came back, what stuck."""
    records = per_crossing(plan, traces, offsets, grace, lead)
    missed = [r['index'] for r in records if r['latency'] is None]
    echoed = [r['index'] for r in records if r['echoed']]
    latencies = [r['latency'] for r in records if r['latency'] is not None]
    stuck = [name for name, trace in traces.items() if ends_held(trace)]
    # A quarter of the screen is generous; a correct entry clamps to the edge.
    mislanded = [r['index'] for r in records if r['landing_error'] is not None
                 and r['landing_error'] > 0.25 * max(1, max((s.get('target_width') or 0) for s in plan))]
    # Modifier-state injections are real shared input, but they are not
    # crossings. Report them separately so neither is mistaken for the other.
    other = {name: len([s for s in trace if s.get('fromPerch') and not is_pointer(s)])
             for name, trace in traces.items()}
    summary = {'crossings': len(plan), 'missed': missed, 'echoed': echoed, 'stuck': stuck,
               'mislanded': mislanded, 'injected_non_pointer': other}
    if latencies:
        ordered = sorted(latencies)
        summary['latency_seconds'] = {'median': statistics.median(ordered), 'worst': ordered[-1]}
    return summary


def judge_typing(result: dict) -> tuple[bool, str]:
    """Typing passes only on evidence.

    Counting unbalanced key events is satisfied by no events at all, so a run
    that captured nothing would report no stuck keys and mean nothing by it.
    Require keystrokes, then require them balanced and the modifiers released.
    """
    per_guest = result.get('per_guest', {})
    captured = sum(value.get('keyDown', 0) for value in per_guest.values())
    if not captured:
        return False, 'no keystrokes were captured, so nothing was tested'
    # Unequal totals are sampling loss; a key still down at the end is not.
    held = sorted(name for name, value in per_guest.items() if value.get('ends_held'))
    if held:
        return False, f'a key or button was still down on {", ".join(held)}'
    left_on = sorted(name for name, value in per_guest.items() if value.get('modifiers_left_on'))
    if left_on:
        return False, f'modifiers still held on {", ".join(left_on)}'
    return True, f'{captured} keystrokes, all released, no modifiers left on'


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
        # Switching needs a push against this guest's own edge, the same as a
        # crossing; a bare move to the edge produces no motion to act on. The
        # chord is held across the switch so a stuck modifier would show.
        rightward = source == names[0]
        width, height = screen(addresses[source])
        edge = (width - 1 if rightward else 0, height * 0.5)
        drive_crosshold(addresses[source], edge, 12 if rightward else -12, 8, command | shift)
        time.sleep(0.3)
    for recorder in recorders.values():
        recorder.wait(timeout=150)
    traces = {name: read_trace(addresses[name], out / f'typing-{name}.jsonl') for name in names}
    stuck = {}
    for name, trace in traces.items():
        downs = len([s for s in trace if kind_of(s) == 'keyDown'])
        ups = len([s for s in trace if kind_of(s) == 'keyUp'])
        flags = [s for s in trace if kind_of(s) == 'flagsChanged']
        stuck[name] = {'keyDown': downs, 'keyUp': ups, 'unbalanced': downs - ups,
                       'ends_held': ends_held(trace),
                       'modifiers_left_on': bool(flags and flags[-1].get('flags'))}
    return {'per_guest': stuck}
