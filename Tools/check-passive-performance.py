#!/usr/bin/env python3
"""Sample existing Perch processes; never launch Perch or change its settings."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--seconds', type=int, default=120)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
if not 10 <= a.seconds <= 600: p.error('Use 10–600 seconds')
repo = Path(__file__).resolve().parents[1]
rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True).splitlines()
pids = {}
for row in rows:
    fields = row.strip().split(None, 1)
    if len(fields) != 2: continue
    pid, command = fields
    if command == '/Applications/Perch.app/Contents/MacOS/Perch': role = 'app'
    elif command.endswith('/Perch/Safety/Perch Helper.app/Contents/MacOS/Perch'): role = 'user-helper'
    elif command == '/Library/PrivilegedHelperTools/Perch Lid Helper.app/Contents/MacOS/Perch': role = 'lid-helper'
    elif command == '/usr/bin/eslogger': role = 'collector'
    else: continue
    pids[pid] = role
if 'app' not in pids.values(): raise SystemExit('Running installed Perch not found; nothing launched')
with tempfile.TemporaryDirectory(prefix='perch-passive-perf-') as directory:
    probe = Path(directory)/'counters'
    subprocess.run(['xcrun', 'clang', '-O2', str(repo/'Tools/perf-counters.c'), '-o', str(probe)], check=True)
    start = time.monotonic(); samples = []
    while True:
        samples.append({'seconds': time.monotonic()-start,
                        'processes': json.loads(subprocess.check_output([str(probe), *pids], text=True))})
        if time.monotonic()-start >= a.seconds: break
        time.sleep(min(5, a.seconds-(time.monotonic()-start)))
result = {'seconds': round(samples[-1]['seconds'], 2), 'scope': 'Existing processes under the user’s current workload; no input/menu activity induced. On-disk version does not identify a running older process.', 'processes': {}}
for pid, role in pids.items():
    values = [s['processes'][pid] for s in samples]
    if any(v is None for v in values):
        result['processes'][pid] = {'role': role, 'status': 'Counters inaccessible or process exited; not counted as zero'}
        continue
    first, last = values[0], values[-1]
    if any(v['birth'] != first['birth'] for v in values):
        result['processes'][pid] = {'role': role, 'status': 'PID lifetime changed; no combined result'}
        continue
    result['processes'][pid] = {'role': role, 'cpuPercent': round(100*(last['cpu']-first['cpu'])/result['seconds'], 3),
        'footprintMiBStart': round(first['footprint']/2**20, 3), 'footprintMiBEnd': round(last['footprint']/2**20, 3),
        'footprintMiBPeakSample': round(max(v['footprint'] for v in values)/2**20, 3),
        'interruptWakeupsPerSecond': round((last['interruptWakeups']-first['interruptWakeups'])/result['seconds'], 3),
        'bytesWritten': last['bytesWritten']-first['bytesWritten']}
measured = [v['cpuPercent'] for v in result['processes'].values() if 'cpuPercent' in v]
result['measuredCPUPercentTotal'] = round(sum(measured), 3) if measured else None
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps({'summary': result, 'samples': samples}, indent=2)+'\n')
print(json.dumps(result, indent=2))
