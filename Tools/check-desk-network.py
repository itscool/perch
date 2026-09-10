#!/usr/bin/env python3
"""Real TLS on loopback, temporary identities/storage, no Keychain or UI."""
from pathlib import Path
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[1]
lib = subprocess.check_output(['python3', str(repo/'Tools/certificate-dependency.py')], text=True).strip()
with tempfile.TemporaryDirectory(prefix='perch-network-check-') as folder:
    binary = Path(folder)/'check'
    sources = ['KVMGroup.swift','KVMSync.swift','KVMPeerIdentity.swift','KVMPeerTransport.swift','KVMMembership.swift','KVMDeskNode.swift','KVMMonitorSwitch.swift']
    subprocess.run(['xcrun','swiftc','-warnings-as-errors','-I',lib+'/Modules','-L',lib,'-lPerchCertificates',*[str(repo/'Sources'/s) for s in sources],str(repo/'Tools/check-desk-network.swift'),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
