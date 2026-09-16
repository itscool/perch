#!/usr/bin/env python3
"""Relay each guest's desk port to the other through this Mac.

tart's shared networking isolates the guests from each other while both can
still reach the host. This forwards guest A's dial address to guest B's desk
port and the other way round, so a seeded desk link connects.

A relayed link is not the real path: it bypasses discovery, link-local
addressing and the multi-interface behaviour, so anything that depends on those
still needs real guest-to-guest networking.
"""
from __future__ import annotations
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import lab

DESK_PORT = 53031
# Ports opened on the host's guest-facing address, one per direction.
PORTS = {'perch-a': 53041, 'perch-b': 53042}


def gateway(address: str) -> str:
    """The host address this guest can reach, taken from the guest's route."""
    route = lab.run_in(address, "route -n get default | awk '/gateway/ {print $2}'", check=False, timeout=60)
    return route.strip() or '192.168.64.1'


def holders(host: str, port: int) -> list[int]:
    """Process ids listening on one of the lab's own relay ports."""
    listing = subprocess.run(['/usr/sbin/lsof', '-nP', f'-iTCP@{host}:{port}', '-sTCP:LISTEN', '-t'],
                             capture_output=True, text=True)
    return [int(line) for line in listing.stdout.split() if line.isdigit()]


def listening(host: str, port: int, seconds: float = 10) -> bool:
    end = time.time() + seconds
    while time.time() < end:
        if holders(host, port):
            return True
        time.sleep(0.5)
    return False


def release(host: str, port: int) -> None:
    """Clear a forward left behind by an earlier run.

    These ports belong to the lab, so anything still holding one is a leftover
    from a run that crashed before its teardown. Left in place it silently
    shadows the new forward.
    """
    for pid in holders(host, port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    end = time.time() + 10
    while time.time() < end and holders(host, port):
        time.sleep(0.3)


class Relay:
    """Host-side SSH forwards, one per guest, torn down on exit."""

    def __init__(self, addresses: dict[str, str]):
        self.addresses = addresses
        self.processes: list[subprocess.Popen] = []
        self.dial: dict[str, str] = {}

    def start(self) -> dict[str, str]:
        host = gateway(next(iter(self.addresses.values())))
        for name, address in self.addresses.items():
            # Anything arriving on the host at this port reaches this guest's desk.
            port = PORTS[name]
            release(host, port)
            command = ['/usr/bin/ssh', *lab.SSH_OPTIONS, '-N',
                       '-L', f'{host}:{port}:127.0.0.1:{DESK_PORT}', f'{lab.GUEST_USER}@{address}']
            self.processes.append(subprocess.Popen(command, stdout=subprocess.DEVNULL,
                                                   stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                                                   env=lab._environment(), start_new_session=True))
            if not listening(host, port, 20):
                raise RuntimeError(f'the relay port for {name} ({host}:{port}) never started listening; '
                                   'a run without it produces no sharing data')
        names = list(self.addresses)
        # Each guest dials the port that forwards to the other guest.
        self.dial = {names[0]: f'{host}:{PORTS[names[1]]}', names[1]: f'{host}:{PORTS[names[0]]}'}
        return self.dial

    def check(self) -> dict[str, str]:
        """Prove each guest can reach the port that leads to the other."""
        result = {}
        for name, address in self.addresses.items():
            target = self.dial[name]
            host, port = target.rsplit(':', 1)
            probe = (f"python3 -c \"import socket;s=socket.socket();s.settimeout(5);"
                     f"print('open' if s.connect_ex(('{host}',{port}))==0 else 'closed')\"")
            result[name] = lab.run_in(address, probe, check=False, timeout=60).strip()
        return result

    def stop(self) -> None:
        for process in self.processes:
            process.terminate()
        self.processes.clear()

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *_):
        self.stop()
