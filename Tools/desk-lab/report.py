#!/usr/bin/env python3
"""Break a finished run's crossings down by style and by direction.

The matrix reports one summary for all crossings. Slow drags, fast flicks,
diagonals and crossings made with the button held can fail in different ways,
and a switch can work in one direction and not the other, so this reads the
saved evidence back and groups the same per-crossing judgement.
"""
from __future__ import annotations
import json
import statistics
from collections import Counter
import sys
from pathlib import Path

import sharing


def find_crossings(blob) -> dict | None:
    """The crossings result, wherever the runner recorded it."""
    if isinstance(blob, dict):
        if 'plan' in blob and 'offsets' in blob:
            return blob
        for value in blob.values():
            found = find_crossings(value)
            if found:
                return found
    elif isinstance(blob, list):
        for value in blob:
            found = find_crossings(value)
            if found:
                return found
    return None


def read_trace(path: Path) -> list[dict]:
    if not path.exists():
        return []
    samples = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            try:
                samples.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return samples


def describe(records: list[dict], tolerance: float = 0.0) -> str:
    latencies = sorted(r['latency'] for r in records if r['latency'] is not None)
    missed = len([r for r in records if r['latency'] is None])
    echoed = len([r for r in records if r['echoed']])
    # A crossing that arrives far from the shared edge did not land where the
    # desk says it should, even though it arrived.
    mislanded = len([r for r in records if r.get('landing_error') is not None and tolerance and r['landing_error'] > tolerance])
    if not latencies:
        return f'{len(records):>4}  {missed:>6}  {echoed:>6}  {mislanded:>5}       -        -        -'
    worst = latencies[-1]
    p95 = latencies[min(len(latencies) - 1, int(len(latencies) * 0.95))]
    return (f'{len(records):>4}  {missed:>6}  {echoed:>6}  {mislanded:>5}  {statistics.median(latencies):>6.3f}s '
            f'{p95:>7.3f}s {worst:>7.3f}s')


def adapter_evidence(directory: Path) -> None:
    """What Perch actually asked the monitor adapter for.

    The lab seeds the adapter on a different input from the one the preset
    selects, so a genuine activation has to issue a switch. Its absence means
    the preset never became active, which is a seeding fault rather than
    anything about input sharing.
    """
    logs = sorted(directory.glob('display-adapter-*.log'))
    if not logs:
        return
    print('\nmonitor adapter calls')
    for log in logs:
        guest = log.stem.replace('display-adapter-', '')
        lines = [line for line in log.read_text().splitlines() if line.strip()]
        verbs = Counter(line.split()[1] for line in lines if len(line.split()) > 1)
        switches = [line for line in lines if ' switch ' in f' {line} ']
        print(f'  {guest}: {len(lines)} calls {dict(verbs)}')
        for line in switches[:3]:
            print(f'    switch: {line[:110]}')
        if not switches:
            print('    no switch was ever issued, so no preset was activated')
    for state in sorted(directory.glob('display-state-*.json')):
        guest = state.stem.replace('display-state-', '')
        print(f'  {guest} final input: {state.read_text().strip()[:120]}')


def focus_evidence(crossings: dict) -> None:
    """Whether the driving Mac stopped tracking its own posted input.

    When focus moves to the other Mac, Perch captures local input instead of
    letting it through, so the cursor stops following. That separates focus
    never transferring from focus transferring without motion being delivered.
    """
    probes = crossings.get('tracking') or []
    if not probes:
        return
    stopped = [probe for probe in probes if not probe.get('followed', True)]
    print(f'\ncursor probes: {len(probes)}, of which the cursor stopped following: {len(stopped)}')
    for probe in probes[:6]:
        state = 'stopped following' if not probe.get('followed', True) else 'still followed'
        print(f"  #{probe.get('index')} on {probe.get('source')}: {state}")


def main(directory: Path) -> int:
    source = directory / 'results.json'
    if not source.exists():
        print(f'no results in {directory}; the run did not finish')
        return 1
    results = json.loads(source.read_text())
    crossings = find_crossings(results)
    if not crossings:
        print(f'no crossing evidence in {directory}/results.json')
        return 1
    traces = {name: read_trace(directory / f'trace-{name}.jsonl')
              for name in {step['source'] for step in crossings['plan']}}
    records = sharing.per_crossing(crossings['plan'], traces, crossings['offsets'])

    widths = [step.get('target_width') or 0 for step in crossings['plan']]
    tolerance = 0.25 * max(widths) if widths else 0.0
    header = 'group                 count  missed   echo  wrong  median      p95    worst'
    print(header)
    print('-' * len(header))
    print(f'{"all":<20} {describe(records, tolerance)}')
    for style in ['slow', 'fast', 'diagonal', 'held']:
        chosen = [r for r in records if r['style'] == style]
        if chosen:
            print(f'{style:<20} {describe(chosen, tolerance)}')
    for source in sorted({r['source'] for r in records}):
        chosen = [r for r in records if r['source'] == source]
        print(f'{source + " drives":<20} {describe(chosen, tolerance)}')

    late = [r for r in records if r['latency'] is not None and r['latency'] > 0.5]
    if late:
        print(f'\nslowest switches: ' + ', '.join(
            f'#{r["index"]} {r["style"]} {r["latency"]:.3f}s'
            for r in sorted(late, key=lambda r: -r['latency'])[:10]))
    wrong = [r for r in records if r.get('landing_error') is not None and tolerance and r['landing_error'] > tolerance]
    if wrong:
        print('\nlanded away from the edge: ' + ', '.join(
            f'#{r["index"]} {r["style"]} {r["landing_error"]:.0f}pt' for r in sorted(wrong, key=lambda r: -r['landing_error'])[:10]))
    missing = [r['index'] for r in records if r['latency'] is None]
    if missing:
        print(f'\ncrossings that never arrived ({len(missing)}): '
              + ', '.join(str(i) for i in missing[:40]) + (' ...' if len(missing) > 40 else ''))
    focus_evidence(crossings)
    adapter_evidence(directory)
    return 0


if __name__ == '__main__':
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else '.')))
