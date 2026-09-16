#!/usr/bin/env python3
"""Run the Desk permutation matrix across two guests and collect the evidence.

Each permutation writes its own steps into one merged timeline, so a failure
names the step that broke instead of starting an investigation.
"""
from __future__ import annotations
import argparse
import base64
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import lab
import prepare as preparation
import provision
import relay as relaying
import sharing

REPO = Path(__file__).resolve().parents[2]
DESK_LOG = 'Library/Application Support/Perch/Desk/desk.connections.json'
PUBLISHED_DMG = 'https://github.com/itscool/perch/releases/download/v2.0.204/Perch-2.0.204.dmg'


class Timeline:
    def __init__(self, path: Path):
        self.path = path
        self.entries: list[dict] = []

    def add(self, permutation: str, event: str, detail: str = '', guest: str = '') -> None:
        self.entries.append({'at': time.time(), 'permutation': permutation, 'event': event,
                             'guest': guest, 'detail': detail})

    def write(self) -> None:
        self.path.write_text('\n'.join(
            f"{datetime.fromtimestamp(e['at']).strftime('%H:%M:%S.%f')[:-3]}  {e['permutation']:<22} "
            f"{e['event']:<26} {e['guest']:<8} {e['detail']}" for e in sorted(self.entries, key=lambda e: e['at'])) + '\n')


def perch_running(address: str) -> bool:
    return bool(lab.run_in(address, 'pgrep -x Perch || true', check=False))


def start_perch(address: str) -> None:
    # A menu bar app belongs to the guest's logged-in session. This is the same
    # elevated path preparation uses; plain "launchctl asuser" is not permitted
    # and silently leaves Perch unlaunched.
    preparation.gui(address, 'open -a /Applications/Perch.app', check=False)


def restore_dial_addresses(ctx, guest: str) -> None:
    """Put the seeded addresses back before Perch starts again.

    Perch replaces a saved peer address with the host it observes on the live
    connection. Through the relay that host is a loopback or the gateway, so a
    restarted Perch dials itself or a dead port and never re-links. Restoring
    what the seeder wrote keeps a restart permutation measuring the restart
    rather than this artefact. On a real network Perch alternates with
    discovery and recovers on its own, so this is only for relayed runs.
    """
    source = ctx['out'] / 'seed' / ('desk-a.json' if list(ctx['addresses']).index(guest) == 0 else 'desk-b.json')
    if not ctx.get('dial') or not source.exists():
        return
    wanted = json.loads(source.read_text()).get('addresses')
    if not wanted:
        return
    blob = base64.b64encode(json.dumps(wanted).encode()).decode()
    command = ('python3 -c "'
               'import base64,json,os;'
               "p=os.path.expanduser('~/Library/Application Support/Perch/Desk/desk.json');"
               'd=json.load(open(p));'
               f"d['addresses']=json.loads(base64.b64decode('{blob}'));"
               "json.dump(d,open(p,'w'))"
               '" 2>/dev/null')
    lab.run_in(ctx['addresses'][guest], command, check=False)
    ctx['timeline'].add('lab', 'dial-addresses-restored', guest=guest)


def restore_all_dial_addresses(ctx) -> None:
    """Restore both guests, not just the one being restarted.

    Only one side dials: the peer whose identity sorts first. Restoring the
    restarted guest alone still leaves the other holding a poisoned address,
    and if that one is the dialler the link never returns.
    """
    for guest in ctx['addresses']:
        restore_dial_addresses(ctx, guest)


def perch_ready(address: str, seconds: float = 120) -> bool:
    """Perch is running and its desk port is listening in this guest."""
    check = ('pgrep -x Perch >/dev/null && lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null '
             '| grep -q "Perch.*:53031" && echo ready || echo waiting')
    end = time.time() + seconds
    while time.time() < end:
        if lab.run_in(address, check, check=False, timeout=90).strip().endswith('ready'):
            return True
        time.sleep(4)
    return False


DESK_EVENTS = '~/Library/Application Support/Perch/Desk/desk.connections.json'


def linked(address: str) -> bool:
    """This guest holds an authenticated desk link right now.

    Perch's own connection log is the authority: its newest entry says whether
    the last thing that happened was authentication or a failure. A socket
    check alone is not enough, because a relayed link is a loopback socket
    inside the guest and can be briefly absent between reconnects.
    """
    reader = (
        'python3 -c "'
        "import json,os;"
        "p=os.path.expanduser('~/Library/Application Support/Perch/Desk/desk.connections.json');"
        "d=json.load(open(p)) if os.path.exists(p) else [];"
        "e=sorted(d,key=lambda x:x.get('time',0));"
        "print('linked' if e and 'Authenticated' in (e[-1].get('detail') or '') else 'none')"
        '" 2>/dev/null'
    )
    if lab.run_in(address, reader, check=False, timeout=90).strip().endswith('linked'):
        return True
    socket_check = ('lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -i perch | grep -q ":530" '
                    '&& echo linked || echo none')
    return lab.run_in(address, socket_check, check=False, timeout=90).strip().endswith('linked')


def guest_evidence(ctx, guest: str, address: str, label: str) -> str:
    """Save why a guest was not ready and return a short reason."""
    logs = lab.run_in(address, '/usr/bin/log show --last 10m --style compact 2>/dev/null | grep -i perch | tail -40',
                      check=False, timeout=300)
    events = lab.run_in(address, 'tail -c 600 "$HOME/Library/Application Support/Perch/Desk/desk.connections.json" 2>/dev/null',
                        check=False, timeout=90)
    (ctx['out'] / f'not-ready-{label}-{guest}.txt').write_text(f'log:\n{logs}\n\nconnections:\n{events}\n')
    # Perch's own account of the last connection says more than any log line.
    detail = ''
    try:
        recorded = json.loads(events) if events.strip().startswith('[') else []
        if recorded:
            detail = str(recorded[-1].get('detail', ''))
    except json.JSONDecodeError:
        tail = events.rsplit('"detail":"', 1)
        detail = tail[1].split('"')[0] if len(tail) > 1 else ''
    if detail:
        return f'last desk event: {detail}'
    failure = next((line for line in logs.splitlines() if 'rror' in line or 'ailed' in line), '')
    if failure:
        return failure[:160]
    return 'no error in the captured log' if logs.strip() else 'no Perch log lines captured'


def require_ready(ctx, link: bool = False) -> str | None:
    """Every guest must be up before a permutation runs; loud failure if not."""
    for guest, address in ctx['addresses'].items():
        if not perch_ready(address):
            return f'{guest}: Perch never became ready ({guest_evidence(ctx, guest, address, "launch")})'
    if link:
        end = time.time() + 330
        while time.time() < end:
            if all(linked(address) for address in ctx['addresses'].values()):
                return None
            time.sleep(5)
        details = '; '.join(f'{guest}: {guest_evidence(ctx, guest, address, "link")}'
                            for guest, address in ctx['addresses'].items())
        return f'no authenticated desk link on both sides ({details})'
    return None


def quit_perch(address: str) -> None:
    lab.run_in(address, 'osascript -e \'tell application "Perch" to quit\' 2>/dev/null || pkill -x Perch || true', check=False)


def desk_events(address: str, into: Path) -> list[dict]:
    lab.copy_from(address, f'"$HOME/{DESK_LOG}"'.replace('"', ''), into)
    if not into.exists():
        return []
    try:
        return json.loads(into.read_text())
    except json.JSONDecodeError:
        return []


def wait_for(condition, seconds: float, interval: float = 2.0) -> bool:
    end = time.time() + seconds
    while time.time() < end:
        if condition():
            return True
        time.sleep(interval)
    return False


def connected(address: str, into: Path) -> bool:
    events = desk_events(address, into)
    recent = [e for e in events[-8:] if 'Connected' in str(e.get('detail', '')) or e.get('unexpected') is False]
    return bool(recent)


# Each permutation returns (passed, detail). Add one here and it runs.
def permutation_fresh(ctx) -> tuple[bool, str]:
    for guest, address in ctx['addresses'].items():
        start_perch(address)
        ctx['timeline'].add('fresh-start', 'perch-launched', guest=guest)
    problem = require_ready(ctx, link=True)
    return problem is None, 'both guests run Perch and hold an authenticated desk link' if problem is None else problem


def permutation_restart(ctx) -> tuple[bool, str]:
    guest, address = list(ctx['addresses'].items())[1]
    quit_perch(address)
    ctx['timeline'].add('restart-peer', 'perch-quit', guest=guest)
    time.sleep(5)
    restore_all_dial_addresses(ctx)
    start_perch(address)
    ctx['timeline'].add('restart-peer', 'perch-relaunched', guest=guest)
    problem = require_ready(ctx, link=True)
    return problem is None, 'peer reconnected after a restart' if problem is None else problem


def permutation_network(ctx) -> tuple[bool, str]:
    guest, address = list(ctx['addresses'].items())[1]
    down = f'echo {lab.quote(lab.GUEST_PASSWORD)} | sudo -S ifconfig en0 down'
    up = f'echo {lab.quote(lab.GUEST_PASSWORD)} | sudo -S ifconfig en0 up'
    lab.run_in(address, down, check=False)
    ctx['timeline'].add('network-drop', 'interface-down', guest=guest)
    time.sleep(20)
    lab.run_in(address, up, check=False)
    ctx['timeline'].add('network-drop', 'interface-up', guest=guest)
    ok = wait_for(lambda: connected(address, ctx['out'] / f'network-{guest}.json'), 180)
    return ok, 'reconnected after the network returned' if ok else 'never reconnected after the network returned'


def permutation_version_skew(ctx) -> tuple[bool, str]:
    guest, address = list(ctx['addresses'].items())[1]
    quit_perch(address)
    lab.run_in(address, f'curl -sL -o /tmp/published.dmg {PUBLISHED_DMG}', timeout=900, check=False)
    mounted = lab.run_in(address, 'hdiutil attach -nobrowse -mountpoint /tmp/published /tmp/published.dmg >/dev/null 2>&1 && echo ok || echo no', check=False)
    if mounted != 'ok':
        return False, 'could not mount the published build in the guest'
    lab.run_in(address, f'echo {lab.quote(lab.GUEST_PASSWORD)} | sudo -S rm -rf /Applications/Perch.app && '
                        f'echo {lab.quote(lab.GUEST_PASSWORD)} | sudo -S cp -R /tmp/published/Perch.app /Applications/Perch.app', check=False)
    lab.run_in(address, 'hdiutil detach /tmp/published >/dev/null 2>&1 || true', check=False)
    start_perch(address)
    ctx['timeline'].add('version-skew', 'published-build-launched', guest=guest)
    def refused() -> bool:
        events = desk_events(address, ctx['out'] / f'skew-{guest}.json')
        return any('ncompatible' in str(event.get('detail', '')) for event in events[-12:])
    named = wait_for(refused, 120)
    preparation.install_app(address, ctx['app'])
    start_perch(address)
    ctx['timeline'].add('version-skew', 'build-under-test-restored', guest=guest)
    recovered = wait_for(lambda: connected(address, ctx['out'] / f'skew-recovered-{guest}.json'), 180)
    return named and recovered, ('refusal was named and the desk recovered once versions matched' if named and recovered
                                 else f'named refusal: {named}, recovered: {recovered}')


def permutation_sharing_toggle(ctx) -> tuple[bool, str]:
    guest, address = list(ctx['addresses'].items())[0]
    preparation.gui(address, f'defaults write {preparation.APP_ID} desk.shareOnThisMac -bool false', check=False)
    quit_perch(address); time.sleep(3); start_perch(address)
    ctx['timeline'].add('sharing-toggle', 'sharing-off', guest=guest)
    time.sleep(10)
    preparation.gui(address, f'defaults write {preparation.APP_ID} desk.shareOnThisMac -bool true', check=False)
    quit_perch(address); time.sleep(3)
    restore_all_dial_addresses(ctx)
    start_perch(address)
    ctx['timeline'].add('sharing-toggle', 'sharing-on', guest=guest)
    problem = require_ready(ctx, link=True)
    return problem is None, 'sharing turned off and on again' if problem is None else problem


def permutation_return_to_local(ctx) -> tuple[bool, str]:
    problem = require_ready(ctx, link=True)
    if problem:
        return False, problem
    guest, address = list(ctx['addresses'].items())[1]
    # Ctrl-Opt-Esc is Perch's return-to-local shortcut; it must act locally only.
    trace = ctx['out'] / f'local-{guest}.jsonl'
    recorder = sharing.start_recorder(address, 20)
    time.sleep(2)
    lab.run_in(address, f'/tmp/desk-lab-guest drive type 53 {(1 << 18) | (1 << 19)} 1 0.02', check=False)
    ctx['timeline'].add('return-to-local', 'shortcut-pressed', guest=guest)
    recorder.wait(timeout=60)
    other = list(ctx['addresses'].items())[0]
    samples = sharing.read_trace(other[1], ctx['out'] / f'local-other-{other[0]}.jsonl')
    leaked = [s for s in samples if s.get('key') == 53 and s.get('fromPerch')]
    return not leaked, 'the return-to-local shortcut stayed on its own Mac' if not leaked else 'the shortcut reached the other Mac'


def permutation_sharing_crossings(ctx) -> tuple[bool, str]:
    problem = require_ready(ctx, link=True)
    if problem:
        return False, problem
    result = sharing.crossings(ctx['addresses'], ctx['out'], rounds=ctx['rounds'])
    ctx['results']['sharing'] = result
    analysis = result['analysis']
    ok = not analysis['missed'] and not analysis['echoed'] and not analysis['stuck']
    latency = analysis.get('latency_seconds')
    detail = (f"{analysis['crossings']} crossings, missed {len(analysis['missed'])}, echoed {len(analysis['echoed'])}, "
              f"stuck {analysis['stuck']}" + (f", median {latency['median']:.3f}s worst {latency['worst']:.3f}s" if latency else ''))
    return ok, detail


def permutation_sharing_typing(ctx) -> tuple[bool, str]:
    problem = require_ready(ctx, link=True)
    if problem:
        return False, problem
    result = sharing.typing(ctx['addresses'], ctx['out'])
    ctx['results']['typing'] = result
    unbalanced = {name: value['unbalanced'] for name, value in result['per_guest'].items() if value['unbalanced']}
    return not unbalanced, 'no stuck keys or modifiers' if not unbalanced else f'unbalanced key events: {unbalanced}'


MATRIX = [
    ('fresh-start', permutation_fresh),
    ('sharing-crossings', permutation_sharing_crossings),
    ('sharing-typing', permutation_sharing_typing),
    ('return-to-local', permutation_return_to_local),
    ('restart-peer', permutation_restart),
    ('network-drop', permutation_network),
    ('sharing-toggle', permutation_sharing_toggle),
    ('version-skew', permutation_version_skew),
]
# Honest about scope: these need the physical desk and are not attempted here.
NOT_COVERED = ['monitor input switching over DDC', 'clamshell, lid and battery behavior',
               'real keyboards and their firmware modes', 'pairing through the UI (the lab seeds a paired desk)',
               'conflicting simultaneous edits (needs UI automation)']
# Only meaningful over a real guest-to-guest network, never over the relay.
NEEDS_REAL_NETWORK = ['pairing through discovery', 'link-local addressing and interface selection',
                      'reconnect storms and backoff', 'version skew refusal over the network']
# Permutations that only mean something over a real guest-to-guest network.
NETWORK_ONLY = {'network-drop', 'version-skew'}
# Input sharing starts only for an active preset, and a preset becomes active
# only when a monitor's input is switched and observed over DDC: building the
# request refuses a screen with no control path, executing it performs a real
# DDC write, and the fallback compares observed input codes. These guests have
# a virtual display that answers none of that, so the pointer can never leave
# the driving guest. Driving crossings anyway reports a failure that says
# nothing about Perch.
NEEDS_MONITOR_CONTROL = {'sharing-crossings', 'sharing-typing', 'return-to-local'}
MONITOR_REASON = ('needs a monitor Perch can switch over DDC: input sharing starts only for an '
                  'active preset, and these guests have a virtual display')


def collect(ctx) -> None:
    for guest, address in ctx['addresses'].items():
        desk_events(address, ctx['out'] / f'desk-connections-{guest}.json')
        logs = lab.run_in(address, '/usr/bin/log show --last 30m --style compact 2>/dev/null | grep -i perch | tail -2000',
                          check=False, timeout=600)
        (ctx['out'] / f'unified-log-{guest}.txt').write_text(logs or '(no Perch log lines captured)\n')
        crashes = lab.run_in(address, 'ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i perch | head -5',
                             check=False, timeout=90)
        if crashes.strip():
            (ctx['out'] / f'crashes-{guest}.txt').write_text(crashes)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=REPO / 'build/Perch.app')
    parser.add_argument('--rounds', type=int, default=60, help='Pointer crossings to drive')
    parser.add_argument('--only', help='Run one permutation by name')
    parser.add_argument('--recreate', action='store_true', help='Rebuild the guests first')
    parser.add_argument('--skip-prepare', action='store_true')
    parser.add_argument('--relay', action='store_true',
                        help='Connect the desk through this Mac because the guests cannot reach each other')
    arguments = parser.parse_args()
    out = REPO / 'work/desk-lab' / datetime.now().strftime('%Y%m%d-%H%M%S')
    out.mkdir(parents=True, exist_ok=True)
    timeline = Timeline(out / 'timeline.txt')
    addresses = provision.up(arguments.recreate)
    ctx = {'addresses': addresses, 'out': out, 'timeline': timeline, 'app': arguments.app,
           'rounds': arguments.rounds, 'results': {}, 'relayed': arguments.relay}
    relay = None
    dial = None
    if arguments.relay:
        # A relayed link bypasses discovery and the real multi-interface path.
        relay = relaying.Relay(addresses)
        dial_map = relay.start()
        names = list(addresses)
        dial = (dial_map[names[0]], dial_map[names[1]])
        reachable = relay.check()
        timeline.add('relay', 'started', f'{dial_map} reachable={reachable}')
        print(f'RELAYED LINK through this Mac: {dial_map}; guest reachability {reachable}')
        # Perch overwrites saved peer addresses with what it observes, which
        # through the relay is a loopback or the host gateway. Keep the real
        # relay addresses so a restart dials the peer and not itself.
        ctx['dial'] = dial_map
        if any(state != 'open' for state in reachable.values()):
            print('FAIL  relay: a guest cannot reach its relay port')
            relay.stop()
            return 1
    if not arguments.skip_prepare:
        report = preparation.prepare(addresses, arguments.app, out, dial=dial)
        (out / 'guests.json').write_text(json.dumps(report, indent=2))
        for guest, value in report.items():
            timeline.add('prepare', 'guest-ready', value['permissions'][:60], guest=guest)
    summary = []
    for name, runner in MATRIX:
        if arguments.only and arguments.only != name:
            continue
        if name in NEEDS_MONITOR_CONTROL:
            timeline.add(name, 'skipped', MONITOR_REASON)
            summary.append((name, None, f'skipped: {MONITOR_REASON}'))
            print(f'SKIP  {name}: {MONITOR_REASON}')
            continue
        if ctx['relayed'] and name in NETWORK_ONLY:
            timeline.add(name, 'skipped', 'needs real guest-to-guest networking')
            summary.append((name, None, 'skipped: needs real guest-to-guest networking'))
            print(f'SKIP  {name}: needs real guest-to-guest networking')
            continue
        timeline.add(name, 'started')
        try:
            passed, detail = runner(ctx)
        except Exception as error:  # a broken permutation must not hide the rest
            passed, detail = False, f'{type(error).__name__}: {error}'
        timeline.add(name, 'passed' if passed else 'FAILED', detail)
        summary.append((name, passed, detail))
        print(f"{'PASS' if passed else 'FAIL'}  {name}: {detail}")
    collect(ctx)
    if relay is not None:
        relay.stop()
        timeline.add('relay', 'stopped')
    timeline.write()
    (out / 'results.json').write_text(json.dumps(
        {'summary': [{'permutation': n, 'passed': p, 'skipped': p is None, 'detail': d} for n, p, d in summary],
         'sharing': ctx['results'], 'not_covered': NOT_COVERED,
         'relayed': ctx['relayed'], 'needs_real_network': NEEDS_REAL_NETWORK if ctx['relayed'] else [],
         'needs_monitor_control': sorted(NEEDS_MONITOR_CONTROL), 'monitor_reason': MONITOR_REASON}, indent=2))
    print('\nNot covered here (needs the physical desk):')
    for item in NOT_COVERED:
        print(' -', item)
    if ctx['relayed']:
        print('\nRan over a RELAYED link through this Mac, so these still need real guest-to-guest networking:')
        for item in NEEDS_REAL_NETWORK:
            print(' -', item)
    print('evidence:', out)
    return 0 if all(passed for _, passed, _ in summary if passed is not None) else 1


if __name__ == '__main__':
    raise SystemExit(main())
