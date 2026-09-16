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


def describe(records: list[dict]) -> str:
    latencies = sorted(r['latency'] for r in records if r['latency'] is not None)
    missed = len([r for r in records if r['latency'] is None])
    echoed = len([r for r in records if r['echoed']])
    if not latencies:
        return f'{len(records):>4}  {missed:>6}  {echoed:>6}       -        -        -'
    worst = latencies[-1]
    p95 = latencies[min(len(latencies) - 1, int(len(latencies) * 0.95))]
    return (f'{len(records):>4}  {missed:>6}  {echoed:>6}  {statistics.median(latencies):>6.3f}s '
            f'{p95:>7.3f}s {worst:>7.3f}s')


def main(directory: Path) -> int:
    results = json.loads((directory / 'results.json').read_text())
    crossings = find_crossings(results)
    if not crossings:
        print(f'no crossing evidence in {directory}/results.json')
        return 1
    traces = {name: read_trace(directory / f'trace-{name}.jsonl')
              for name in {step['source'] for step in crossings['plan']}}
    records = sharing.per_crossing(crossings['plan'], traces, crossings['offsets'])

    header = 'group                 count  missed   echo  median      p95    worst'
    print(header)
    print('-' * len(header))
    print(f'{"all":<20} {describe(records)}')
    for style in ['slow', 'fast', 'diagonal', 'held']:
        chosen = [r for r in records if r['style'] == style]
        if chosen:
            print(f'{style:<20} {describe(chosen)}')
    for source in sorted({r['source'] for r in records}):
        chosen = [r for r in records if r['source'] == source]
        print(f'{source + " drives":<20} {describe(chosen)}')

    late = [r for r in records if r['latency'] is not None and r['latency'] > 0.5]
    if late:
        print(f'\nslowest switches: ' + ', '.join(
            f'#{r["index"]} {r["style"]} {r["latency"]:.3f}s'
            for r in sorted(late, key=lambda r: -r['latency'])[:10]))
    missing = [r['index'] for r in records if r['latency'] is None]
    if missing:
        print(f'\ncrossings that never arrived ({len(missing)}): '
              + ', '.join(str(i) for i in missing[:40]) + (' ...' if len(missing) > 40 else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else '.')))
