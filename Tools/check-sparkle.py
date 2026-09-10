#!/usr/bin/env python3
"""Build disposable, locally signed old/new apps for real Sparkle UI acceptance.

Does not launch anything. Serve OUTPUT/feed on the printed loopback port, then
launch OUTPUT/installed/Perch.app via LaunchServices under AGENT MODE. Only the
fixture copy permits HTTP; Perch's production configuration requires HTTPS.
"""
import argparse
import importlib.util
from pathlib import Path
import plistlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--output', required=True, type=Path)
p.add_argument('--port', default=18783, type=int)
a = p.parse_args()
repo = Path(__file__).resolve().parents[1]
root = a.output.resolve(); root.mkdir(parents=True, exist_ok=True)
if (root / 'installed').exists(): p.error('Use a fresh fixture directory')
def run(*args): subprocess.run(list(map(str,args)), check=True)
spec = importlib.util.spec_from_file_location('dependency', repo / 'Tools/sparkle-dependency.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
sparkle = module.dependency()
generator = root / 'generate.swift'
generator.write_text('''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try key.rawRepresentation.base64EncodedString().write(to: url, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
print(key.publicKey.rawRepresentation.base64EncodedString())
''')
public = subprocess.check_output(['xcrun','swift',str(generator),str(root/'fixture-private.txt')], text=True).strip()
source = (repo / 'Sources/PerchUpdater.swift').read_text()
source = source.replace('url.scheme == "https"', '(url.scheme == "https" || (url.scheme == "http" && url.host == "127.0.0.1"))')
(root / 'PerchUpdater.swift').write_text(source)
(root / 'main.swift').write_text((repo/'Tools/sparkle-fixture.swift').read_text() + '\n_ = NSApplication.shared\nNSApp.setActivationPolicy(.regular)\nlet delegate = AppDelegate()\nNSApp.delegate = delegate\nNSApp.run()\n')
binary = root / 'Fixture'
run('xcrun','swiftc',root/'main.swift',root/'PerchUpdater.swift',repo/'Sources/UpdateIdentity.swift',repo/'Sources/LidRestartHandoff.swift',
    '-F',sparkle,'-framework','Sparkle','-framework','AppKit','-framework','Security', '-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks','-o',binary)
for build, directory in [('1','installed'),('2','candidate')]:
    app = root/directory/'Perch.app'; (app/'Contents/MacOS').mkdir(parents=True)
    run('cp',binary,app/'Contents/MacOS/Perch')
    info = {'CFBundleIdentifier':'local.perch.sparkle-fixture.'+root.name, 'CFBundleExecutable':'Perch','CFBundleName':'Perch Update Fixture',
            'CFBundlePackageType':'APPL','CFBundleVersion':build,'CFBundleShortVersionString':'1.2.'+build,'LSMinimumSystemVersion':'26.0',
            'PerchLidProtocolVersion':2,'SUFeedURL':f'http://127.0.0.1:{a.port}/appcast.xml','SUPublicEDKey':public,
            'SUEnableAutomaticChecks':False,'SUAllowsAutomaticUpdates':False,'SUAutomaticallyUpdate':False,
            'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,'FixtureRoot':str(root)}
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    run('python3',repo/'Tools/embed-sparkle.py',app)
    run('codesign','--force','--sign','Perch Local Code Signing','--timestamp=none',app)
    run('codesign','--verify','--deep','--strict',app)
run('python3',repo/'Tools/prepare-update.py',root/'candidate/Perch.app','--output',root/'feed','--download-url',f'http://127.0.0.1:{a.port}/Perch-1.2.2.zip','--key-file',root/'fixture-private.txt','--fixture')
print(f'Built fixture; no launch performed. Serve {root / "feed"} on 127.0.0.1:{a.port}.')
