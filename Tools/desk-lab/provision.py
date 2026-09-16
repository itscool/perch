#!/usr/bin/env python3
"""Create, boot and report the two disposable lab guests. Never edits the base image."""
import argparse
import subprocess
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import lab


REPO = Path(__file__).resolve().parents[2]
BOOT_LOGS = REPO / 'work/desk-lab/boot'


def running(guest: str) -> bool:
    """A guest exists only while its run process does; tart list's state column
    reports stopped even while a healthy run is in progress."""
    found = subprocess.run(['/usr/bin/pgrep', '-f', f'tart run --no-graphics {guest}'],
                           capture_output=True, text=True)
    return bool(found.stdout.strip())


def create(guest: str, recreate: bool) -> None:
    if guest in lab.existing():
        if not recreate:
            return
        stop(guest)
        lab.tart('delete', guest, timeout=120)
    lab.tart('clone', lab.BASE_IMAGE, guest, timeout=1800)


def boot(guest: str) -> None:
    if running(guest):
        return
    BOOT_LOGS.mkdir(parents=True, exist_ok=True)
    log = BOOT_LOGS / f'{guest}.log'
    handle = open(log, 'ab')
    # Detached: the guest must outlive whichever shell started it, and its
    # output is kept so a failed boot is visible instead of silent.
    # Shared NAT isolates the guests from each other, so the desk can never
    # connect. Bridged networking puts both on the same network as this Mac.
    command = [str(lab.TART), 'run', '--no-graphics', guest]
    if lab.BRIDGE:
        command.insert(2, f'--net-bridged={lab.BRIDGE}')
    subprocess.Popen(command, stdout=handle, stderr=handle, stdin=subprocess.DEVNULL, start_new_session=True)
    time.sleep(3)


def boot_log(guest: str) -> str:
    log = BOOT_LOGS / f'{guest}.log'
    return log.read_text()[-400:] if log.exists() else '(no boot log)'


def stop(guest: str) -> None:
    try:
        lab.tart('stop', guest, timeout=120)
    except lab.LabError:
        pass
    subprocess.run(['/usr/bin/pkill', '-f', f'tart run --no-graphics {guest}'], capture_output=True)


def up(recreate: bool) -> dict[str, str]:
    for guest in lab.GUESTS:
        create(guest, recreate)
        boot(guest)
    try:
        addresses = lab.discover()
    except lab.LabError as error:
        raise lab.LabError(f'{error}; boot logs: ' + '; '.join(f'{g}: {boot_log(g)[-120:]}' for g in lab.GUESTS)) from error
    for guest, address in addresses.items():
        lab.install_key(address)
        print(f'{guest}: {address}')
    return addresses


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recreate', action='store_true', help='Delete and clone the guests again')
    parser.add_argument('--stop', action='store_true', help='Stop both guests and exit')
    arguments = parser.parse_args()
    if arguments.stop:
        for name in lab.GUESTS:
            stop(name)
        print('stopped', ', '.join(lab.GUESTS))
    else:
        up(arguments.recreate)
