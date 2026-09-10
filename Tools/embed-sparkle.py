#!/usr/bin/env python3
"""Copy and sign Sparkle from the inside out, preserving its framework layout."""
import argparse
from pathlib import Path
import subprocess
import importlib.util

p = argparse.ArgumentParser()
p.add_argument('app', type=Path)
p.add_argument('--identity', default='Perch Local Code Signing')
p.add_argument('--release', action='store_true')
a = p.parse_args()
spec = importlib.util.spec_from_file_location('dependency', Path(__file__).with_name('sparkle-dependency.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = module.dependency()
framework = a.app / 'Contents/Frameworks/Sparkle.framework'
framework.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['ditto', str(source / 'Sparkle.framework'), str(framework)], check=True)
resources = a.app / 'Contents/Resources'
resources.mkdir(parents=True, exist_ok=True)
subprocess.run(['cp', str(source / 'LICENSE'), str(resources / 'Sparkle-LICENSE.txt')], check=True)
options = ['--options', 'runtime', '--timestamp'] if a.release else ['--timestamp=none']
# No --deep signing: nested bundles/executables are signed deliberately.
version = framework / 'Versions/B'
targets = [*sorted((version / 'XPCServices').glob('*.xpc')), version / 'Autoupdate', version / 'Updater.app', framework]
for target in targets:
    if not target.exists():
        raise SystemExit(f'Pinned Sparkle layout changed: {target}')
    subprocess.run(['codesign', '--force', '--sign', a.identity, *options, str(target)], check=True)
