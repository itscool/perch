#!/usr/bin/env python3
"""Real TLS on loopback, temporary identities/storage, no Keychain or UI."""
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import argparse
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--endurance-seconds', type=int, default=0,
                    help='Additional 16-peer sustained input run (0 or 10–600 seconds)')
args = parser.parse_args()
if args.endurance_seconds != 0 and not 10 <= args.endurance_seconds <= 600:
    parser.error('Use 0 or 10–600 seconds')
lib = subprocess.check_output(['python3', str(repo/'Tools/certificate-dependency.py')], text=True).strip()
with tempfile.TemporaryDirectory(prefix='perch-network-check-') as folder:
    binary = Path(folder)/'check'
    sources = ['PerchError.swift', 'SecureFile.swift', 'Subprocess.swift', 'MainTimer.swift', 'DisplayIdentity.swift', 'KVMGroup.swift','KVMSync.swift','KVMPeerIdentity.swift','KVMPeerTransport.swift','KVMMembership.swift','KVMReconnectPolicy.swift','KVMDeskNode.swift','DeskDisplayWake.swift','KVMMonitorSwitch.swift','KVMInput.swift','KVMInputSession.swift']
    subprocess.run(['xcrun','swiftc','-warnings-as-errors',*(['-O', '-whole-module-optimization'] if args.endurance_seconds else []),'-I',lib+'/Modules','-L',lib,'-lPerchCertificates',*[str(perch_source(s)) for s in sources],str(repo/'Tools/check-desk-network.swift'),'-o',str(binary)],check=True)
    subprocess.run([str(binary), str(args.endurance_seconds)],check=True,
                   timeout=180 + args.endurance_seconds)
