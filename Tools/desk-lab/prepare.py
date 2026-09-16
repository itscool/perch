#!/usr/bin/env python3
"""Put Perch, a seeded desk and the input tool into each guest.

Nothing here touches the host: the app is copied in, permissions are granted
inside the guest, and lid protection is skipped (it needs real hardware).
"""
from __future__ import annotations
import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import lab
import seed as seeder

APP_ID = 'local.scott.perch'
IDENTITY_SERVICE = 'local.scott.perch.desk.identity'
DESK_PATH = 'Library/Application Support/Perch/Desk/desk.json'
SERVICES = ('kTCCServiceAccessibility', 'kTCCServiceListenEvent')
GUEST_TOOL = '/tmp/desk-lab-guest'
TEAM_ID = 'S42F8BV6J2'


def gui(address: str, command: str, check: bool = True) -> str:
    """Run a command inside the guest's logged-in session.

    macOS refuses every keychain item operation from an SSH session, and
    preference writes made over SSH can be missed by the session's cache, so
    identity and preference work runs where the user is actually logged in.
    """
    password = lab.quote(lab.GUEST_PASSWORD)
    return lab.run_in(address, f'echo {password} | sudo -S launchctl asuser $(id -u) '
                               f'sudo -u {lab.GUEST_USER} /bin/sh -lc {lab.quote(command)}', check=check)


def sip_disabled(address: str) -> bool:
    return 'disabled' in lab.run_in(address, 'csrutil status', check=False).lower()


def grant(address: str) -> str:
    """Grant Accessibility and Input Monitoring inside the guest.

    Only possible unattended when the guest has System Integrity Protection
    off, which lets us write its permission database directly. Otherwise the
    caller is told exactly what a person must click once per image.

    Perch is granted by bundle id; the lab's input tool is a bare binary, so it
    is granted by path. Without that second grant the recorder cannot open an
    event tap and the driver cannot post anything.
    """
    if not sip_disabled(address):
        return ('manual: in this guest open System Settings -> Privacy & Security and enable Perch under '
                'Accessibility and Input Monitoring (once per image, then snapshot the image)')
    database = '/Library/Application Support/com.apple.TCC/TCC.db'
    sudo = f'echo {lab.quote(lab.GUEST_PASSWORD)} | sudo -S'
    statements = []
    for service in SERVICES:
        for client, client_type in ((APP_ID, 0), (GUEST_TOOL, 1)):
            statements.append(
                f"INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, "
                f"auth_version, flags) VALUES ('{service}', '{client}', {client_type}, 2, 4, 1, 0);")
    write = ' '.join(statements)
    failure = lab.run_in(address, f'{sudo} sqlite3 {lab.quote(database)} {lab.quote(write)} 2>&1 || true', check=False)
    lab.run_in(address, f'{sudo} killall tccd 2>/dev/null || true', check=False)
    query = f"SELECT service || '=' || client || ':' || auth_value FROM access WHERE client IN ('{APP_ID}', '{GUEST_TOOL}');"
    granted = lab.run_in(address, f'{sudo} sqlite3 {lab.quote(database)} {lab.quote(query)} 2>&1 || true', check=False)
    lines = [line for line in granted.splitlines() if '=' in line]
    if not lines:
        return f'FAILED to grant (SIP is off but the write did not stick): {failure[:200]} {granted[:200]}'
    return 'granted in the guest permission database: ' + '; '.join(lines)


def install_app(address: str, app: Path) -> None:
    lab.run_in(address, 'rm -rf /tmp/Perch.app')
    lab.copy_to(address, app, '/tmp/Perch.app')
    lab.run_in(address, f'echo {lab.quote(lab.GUEST_PASSWORD)} | sudo -S rm -rf /Applications/Perch.app && '
                        f'echo {lab.quote(lab.GUEST_PASSWORD)} | sudo -S cp -R /tmp/Perch.app /Applications/Perch.app')


def install_tool(address: str, tool: Path) -> None:
    lab.copy_to(address, tool, '/tmp/desk-lab-guest')
    lab.run_in(address, 'chmod +x /tmp/desk-lab-guest')


def seed_guest(address: str, identity: Path, desk: Path) -> None:
    """Give the guest its desk identity and the desk both guests share."""
    password = lab.quote(lab.GUEST_PASSWORD)
    gui(address, f'security unlock-keychain -p {password} ~/Library/Keychains/login.keychain-db', check=False)
    payload = identity.read_text()
    gui(address, f'security delete-generic-password -s {IDENTITY_SERVICE} -a device 2>/dev/null; true', check=False)
    gui(address, f'security add-generic-password -U -A -s {IDENTITY_SERVICE} -a device -w {lab.quote(payload)}')
    stored = gui(address, f'security find-generic-password -s {IDENTITY_SERVICE} -a device -w | head -c 24', check=False)
    if not stored.strip():
        raise lab.LabError('the desk identity did not persist in the guest keychain')
    # Without a partition list naming Perch's signing team, reading the item
    # raises a keychain prompt inside the guest that nobody can click, and the
    # desk never starts.
    partitions = 'apple-tool:,apple:,teamid:' + TEAM_ID
    result = gui(address, f'security set-generic-password-partition-list -S {partitions} '
                          f'-s {IDENTITY_SERVICE} -a device -k {password} 2>&1; echo exit=$?', check=False)
    if 'exit=0' not in result:
        raise lab.LabError(f'could not set the keychain partition list: {result[:200]}')
    lab.run_in(address, f'mkdir -p ~/{lab.quote("Library/Application Support/Perch/Desk")}')
    lab.copy_to(address, desk, '/tmp/desk.json')
    lab.run_in(address, f'cp /tmp/desk.json ~/{lab.quote(DESK_PATH)}')
    gui(address, f'defaults write {APP_ID} desk.shareOnThisMac -bool true')


def build_guest_tool(output: Path) -> Path:
    tool = output / 'desk-lab-guest'
    subprocess.run(['xcrun', 'swiftc', '-O', str(Path(__file__).with_name('guest') / 'main.swift'), '-o', str(tool)],
                   check=True, env=lab.toolchain_env())
    return tool


def pinned_peers(desk: str) -> list[dict]:
    """The peer cards a desk pins, read from its signed membership payload."""
    archive = json.loads(desk)
    payload = archive.get('membership', {}).get('payload', '')
    if not payload:
        raise lab.LabError('a seeded desk carries no membership payload')
    return json.loads(base64.b64decode(payload)).get('peers', [])


def guest_identity(address: str) -> dict:
    """The desk identity this guest would actually present."""
    stored = gui(address, f'security find-generic-password -s {IDENTITY_SERVICE} -a device -w', check=False)
    stored = stored.strip()
    if not stored.startswith('{'):
        raise lab.LabError(f'no desk identity in the keychain of {address}: {stored[:120]}')
    return json.loads(stored)


def verify_pairing(addresses: dict[str, str]) -> None:
    """Every guest must present the identity its peer pins.

    A guest that reverted to base-image state, or was seeded while Perch was
    still running, presents a certificate the other side has never seen. The
    transport reports that as "misc. bad certificate" on one side and a plain
    timeout on the other, which is slow to recognise and wastes a whole run.
    """
    identities = {guest: guest_identity(address) for guest, address in addresses.items()}
    desks = {guest: lab.run_in(address, f'cat ~/{lab.quote(DESK_PATH)}')
             for guest, address in addresses.items()}
    for guest, identity in identities.items():
        for holder, desk in desks.items():
            pinned = {peer.get('certificate') for peer in pinned_peers(desk)}
            if identity.get('certificate') not in pinned:
                raise lab.LabError(
                    f"{holder}'s desk does not pin the identity {guest} presents "
                    f"(identity {identity.get('id')}); the pair is half-seeded and "
                    'every connection would be refused as a bad certificate')
    if len({identity.get('id') for identity in identities.values()}) != len(identities):
        raise lab.LabError('both guests carry the same desk identity')


def prepare(addresses: dict[str, str], app: Path, output: Path,
            dial: tuple[str, str] | None = None) -> dict[str, dict]:
    """Install and seed both guests. `dial` gives each guest the address it
    should use to reach the other, for the relayed link used when the guests
    cannot reach each other directly."""
    seeds = seeder.seed(output / 'seed', names=tuple(addresses), dial=dial)
    tool = build_guest_tool(output)
    report = {}
    for index, (guest, address) in enumerate(addresses.items()):
        label = 'a' if index == 0 else 'b'
        # The base image gives both guests the same name; Perch shows computer
        # names and discovery uses them, so make them distinct.
        sudo = f'echo {lab.quote(lab.GUEST_PASSWORD)} | sudo -S'
        for key in ('ComputerName', 'LocalHostName', 'HostName'):
            lab.run_in(address, f'{sudo} scutil --set {key} {guest}', check=False)
        # A running Perch holds its identity and pairing in memory. Reseeding
        # underneath it leaves each side presenting a certificate the other's
        # membership does not know, which shows up as "misc. bad certificate"
        # and an unpaired computer. Stop it; the matrix starts it when ready.
        lab.run_in(address, 'pkill -x Perch || true', check=False)
        install_app(address, app)
        install_tool(address, tool)
        seed_guest(address, seeds / f'identity-{label}.json', seeds / f'desk-{label}.json')
        report[guest] = {
            'address': address,
            'sip': lab.run_in(address, 'csrutil status', check=False),
            'permissions': grant(address),
            'screen': lab.run_in(address, '/tmp/desk-lab-guest screen', check=False),
        }
    # Both guests are seeded together, so prove the pair matches before any
    # permutation spends time on a link that can only be refused.
    verify_pairing(addresses)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path(__file__).resolve().parents[2] / 'build/Perch.app')
    parser.add_argument('--output', type=Path, required=True)
    arguments = parser.parse_args()
    import provision
    print(json.dumps(prepare(provision.up(False), arguments.app, arguments.output), indent=2))
