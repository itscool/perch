#!/usr/bin/env python3
"""Shared helpers for the two-guest Desk lab: tart control and SSH to guests.

Never drives the host desktop. Every synthetic event happens inside a guest.
"""
from __future__ import annotations
import json
import os
import shlex
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TART = Path(os.environ.get('TART', Path.home() / '.local/bin/tart'))
BASE_IMAGE = 'ghcr.io/cirruslabs/macos-tahoe-base:latest'
GUESTS = ('perch-a', 'perch-b')
# Bridged networking; tart's shared NAT isolates guests from each other.
BRIDGE = os.environ.get('PERCH_LAB_BRIDGE', 'en0')
# The prebuilt image ships this account; it is a disposable lab guest.
GUEST_USER = os.environ.get('PERCH_LAB_USER', 'admin')
GUEST_PASSWORD = os.environ.get('PERCH_LAB_PASSWORD', 'admin')


class LabError(RuntimeError):
    pass


def tart(*arguments: str, timeout: float = 600, capture: bool = True) -> str:
    result = subprocess.run([str(TART), *arguments], capture_output=capture, text=True, timeout=timeout)
    if result.returncode != 0:
        raise LabError(f"tart {' '.join(arguments)} failed: {(result.stderr or '').strip()[:400]}")
    return (result.stdout or '').strip()


def existing() -> set[str]:
    names = set()
    for line in tart('list', '--format', 'json', timeout=60).splitlines():
        try:
            for entry in json.loads(line):
                names.add(entry.get('Name') or entry.get('name'))
        except json.JSONDecodeError:
            continue
    return {name for name in names if name}


def reachable(guest_ip: str) -> bool:
    """Whether this address answers SSH as a lab guest right now."""
    if not guest_ip:
        return False
    try:
        return run_in(guest_ip, 'echo ready', timeout=20) == 'ready'
    except Exception:
        return False


MARKER = '~/.perch-lab-guest'
NAT_SUBNET = '192.168.64'


def host_subnet() -> str:
    """The /24 the guests share with this Mac, whichever network they use."""
    override = os.environ.get('PERCH_LAB_SUBNET')
    if override:
        return override
    for interface in ('en0', 'en1', 'en2'):
        found = subprocess.run(['/usr/sbin/ipconfig', 'getifaddr', interface], capture_output=True, text=True)
        address = found.stdout.strip()
        if address:
            return address.rsplit('.', 1)[0]
    return NAT_SUBNET


def _normalise(mac: str) -> str:
    return ':'.join(part.zfill(2) for part in mac.lower().split(':')) if mac else ''


def arp_addresses() -> dict[str, str]:
    """Hardware address to network address, as this Mac currently sees them."""
    table = {}
    output = subprocess.run(['/usr/sbin/arp', '-an'], capture_output=True, text=True).stdout
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[1].startswith('(') and ':' in parts[3]:
            table[_normalise(parts[3])] = parts[1].strip('()')
    return table


def discover(deadline: float = 240) -> dict[str, str]:
    """Find the lab guests by asking them, not by asking tart.

    tart reports no address for a running guest and a previous boot's dead
    lease for another, and the live hardware addresses do not match the ones
    in its config, so neither is trusted. Instead every address on the shared
    virtual network is probed with the lab key; the guests that answer are
    labelled once and stamped, so the mapping stays stable across reboots.
    """
    end = time.time() + deadline
    while time.time() < end:
        alive: dict[str, str] = {}
        subnets = {host_subnet(), NAT_SUBNET}
        # A bridged guest takes whatever address the network's router hands
        # out, so the whole subnet is swept; addresses already answering ARP
        # are tried first because they are the ones that exist.
        subprocess.run(['/sbin/ping', '-c', '1', '-t', '1', '255.255.255.255'], capture_output=True)
        known = set(arp_addresses().values())
        candidates = [f'{subnet}.{host}' for subnet in subnets for host in range(2, 255)]
        candidates.sort(key=lambda address: (address not in known, address))
        with ThreadPoolExecutor(max_workers=64) as pool:
            probes = {pool.submit(_probe, address): address for address in candidates}
            for probe in as_completed(probes):
                label = probe.result()
                if label is not None:
                    alive[probes[probe]] = label
        if len(alive) >= len(GUESTS):
            addresses: dict[str, str] = {}
            unlabelled = []
            for address in sorted(alive, key=lambda value: int(value.split('.')[-1])):
                label = alive[address]
                if label in GUESTS and label not in addresses:
                    addresses[label] = address
                elif not label:
                    unlabelled.append(address)
            for label in GUESTS:
                if label not in addresses and unlabelled:
                    address = unlabelled.pop(0)
                    run_in(address, f'echo {label} > {MARKER}')
                    addresses[label] = address
            if len(addresses) == len(GUESTS):
                return addresses
        time.sleep(5)
    raise LabError(f'found {len(alive)} lab guests on {sorted(subnets)}; expected {len(GUESTS)}')


def _probe(address: str) -> str | None:
    """Return the guest's label, '' when it has none yet, or None if it is not a guest."""
    try:
        answer = run_in(address, f'cat {MARKER} 2>/dev/null || echo UNLABELLED', timeout=12)
    except Exception:
        return None
    return '' if answer.strip() == 'UNLABELLED' else answer.strip()


def ip(guest: str, deadline: float = 240) -> str:
    return discover(deadline)[guest]


def _askpass() -> Path:
    """OpenSSH reads the guest password from this helper, so no prompt appears.

    The guests are disposable lab machines from a public base image; the
    password is that image's documented default, not a secret.
    """
    script = Path.home() / '.cache/perch-desk-lab/askpass.sh'
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text(f'#!/bin/sh\necho {shlex.quote(GUEST_PASSWORD)}\n')
    script.chmod(0o700)
    return script


def _environment() -> dict[str, str]:
    environment = dict(os.environ)
    environment['SSH_ASKPASS'] = str(_askpass())
    environment['SSH_ASKPASS_REQUIRE'] = 'force'
    environment['DISPLAY'] = environment.get('DISPLAY', ':0')
    return environment


def lab_key() -> Path:
    """A key for the lab guests only; the host's own ~/.ssh is left alone."""
    key = Path.home() / '.cache/perch-desk-lab/id_ed25519'
    if not key.exists():
        key.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'perch-desk-lab',
                        '-f', str(key)], check=True, capture_output=True)
    return key


SSH_OPTIONS = ['-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
               '-o', 'LogLevel=ERROR', '-o', 'ConnectTimeout=10', '-o', 'NumberOfPasswordPrompts=1',
               '-o', 'PreferredAuthentications=publickey,password,keyboard-interactive',
               '-i', str(lab_key())]


def ssh_command(guest_ip: str, command: str) -> list[str]:
    return ['/usr/bin/ssh', *SSH_OPTIONS, f'{GUEST_USER}@{guest_ip}', command]


def run_in(guest_ip: str, command: str, timeout: float = 120, check: bool = True) -> str:
    """Run a shell command inside a guest over SSH."""
    result = subprocess.run(ssh_command(guest_ip, command), capture_output=True, text=True,
                            timeout=timeout, env=_environment(), stdin=subprocess.DEVNULL)
    if check and result.returncode != 0:
        raise LabError(f'guest command failed ({result.returncode}): {command[:120]}\n{(result.stderr or "").strip()[:400]}')
    return (result.stdout or '').strip()


def copy_to(guest_ip: str, source: Path, destination: str, timeout: float = 1800) -> None:
    subprocess.run(['/usr/bin/scp', '-r', *SSH_OPTIONS, str(source), f'{GUEST_USER}@{guest_ip}:{destination}'],
                   check=True, capture_output=True, text=True, timeout=timeout,
                   env=_environment(), stdin=subprocess.DEVNULL)


def install_key(guest_ip: str) -> bool:
    """Put the lab's public key in the guest so later calls need no password."""
    public = Path(str(lab_key()) + '.pub').read_text().strip()
    run_in(guest_ip, f'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
                     f'grep -qxF {quote(public)} ~/.ssh/authorized_keys 2>/dev/null || '
                     f'echo {quote(public)} >> ~/.ssh/authorized_keys')
    return True


def copy_from(guest_ip: str, source: str, destination: Path, timeout: float = 300) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(['/usr/bin/scp', '-r', *SSH_OPTIONS, f'{GUEST_USER}@{guest_ip}:{source}', str(destination)],
                            capture_output=True, text=True, timeout=timeout,
                            env=_environment(), stdin=subprocess.DEVNULL)
    return result.returncode == 0


def wait_for_ssh(guest_ip: str, deadline: float = 300) -> None:
    end = time.time() + deadline
    while time.time() < end:
        try:
            run_in(guest_ip, 'echo ready', timeout=20)
            return
        except Exception:
            time.sleep(5)
    raise LabError(f'{guest_ip} never accepted SSH')


def quote(value: str) -> str:
    return shlex.quote(value)


_toolchain: dict | None = None


def toolchain_env() -> dict:
    """An environment whose Swift compiler actually runs.

    A freshly installed Xcode with an unaccepted licence makes every xcrun call
    fail, including the ones this lab makes to build its guest tool and seeder.
    The Command Line Tools keep working, so fall back to them rather than have
    the lab accept a licence on the user's behalf.
    """
    global _toolchain
    if _toolchain is None:
        probe = subprocess.run(['xcrun', '--find', 'swiftc'], capture_output=True, text=True)
        _toolchain = dict(os.environ)
        if probe.returncode != 0:
            _toolchain['DEVELOPER_DIR'] = '/Library/Developer/CommandLineTools'
    return _toolchain
