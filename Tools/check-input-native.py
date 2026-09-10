#!/usr/bin/env python3
"""Native event values only; never posts input, opens windows or creates a tap."""
from pathlib import Path
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='perch-input-values-') as folder:
    executable = Path(folder) / 'check'
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors',
                    *[str(repo/'Sources'/name) for name in ['KVMGroup.swift', 'KVMInput.swift', 'KVMNativeEvent.swift']],
                    str(repo/'Tools/check-input-native.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
