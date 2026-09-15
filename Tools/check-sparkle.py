#!/usr/bin/env python3
"""Build disposable, locally signed old/new apps for real Sparkle UI acceptance.

Does not launch anything. Serve OUTPUT/feed on the printed loopback port, then
launch OUTPUT/installed/Perch.app via LaunchServices under AGENT MODE. Only the
fixture copy permits HTTP; Perch's production configuration requires HTTPS.
"""
import argparse
import importlib.util
from pathlib import Path
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import plistlib
import re
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--output', required=True, type=Path)
p.add_argument('--headless', action='store_true', help='Build a windowless scripted user driver; no launch')
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
source = (perch_source('PerchUpdater.swift')).read_text()
source = source.replace('url.scheme == "https"', '(url.scheme == "https" || (url.scheme == "http" && url.host == "127.0.0.1"))')
if a.headless: source = source.replace('SPUStandardUpdaterController', 'FixtureUpdaterController')
(root / 'PerchUpdater.swift').write_text(source)
fixture = (repo/'Tools/sparkle-fixture.swift').read_text()
if a.headless:
    start = fixture.index('        let window = NSWindow', fixture.index('    func showRecovery()'))
    end = fixture.index('\n    }\n    @objc func retryUpdate', start)
    fixture = fixture[:start] + '''        if fixtureScenario == "retry" {
            try? FileManager.default.removeItem(at: fixtureRoot.appendingPathComponent("fail-prepare"))
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in PerchUpdater.shared.retryInstallation() }
        } else { finishFixture("handoff-failed") }''' + fixture[end:]
    fixture += '\n' + (repo/'Tools/sparkle-headless-driver.swift').read_text()
policy = 'prohibited' if a.headless else 'regular'
(root / 'main.swift').write_text(fixture + f'\n_ = NSApplication.shared\nNSApp.setActivationPolicy(.{policy})\nlet delegate = AppDelegate()\nNSApp.delegate = delegate\nNSApp.run()\n')
binary = root / 'Fixture'
run('xcrun','swiftc',root/'main.swift',root/'PerchUpdater.swift',perch_source('UpdateIdentity.swift'),perch_source('LidRestartHandoff.swift'),perch_source('SecureFile.swift'),perch_source('SettingsLogView.swift'),perch_source('TerminationReply.swift'),perch_source('CodeIdentity.swift'),
    '-F',sparkle,'-framework','Sparkle','-framework','AppKit','-framework','Security', '-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks','-o',binary)
for build, directory in [('1','installed'),('2','candidate')]:
    app = root/directory/'Perch.app'; (app/'Contents/MacOS').mkdir(parents=True)
    run('cp',binary,app/'Contents/MacOS/Perch')
    info = {'CFBundleIdentifier':'local.perch.sparkle-fixture.'+root.name, 'CFBundleExecutable':'Perch','CFBundleName':'Perch Update Fixture',
            'CFBundlePackageType':'APPL','CFBundleVersion':build,'CFBundleShortVersionString':'1.2.'+build,'LSMinimumSystemVersion':'26.0',
            'PerchLidProtocolVersion':int(re.search(r'static let protocolVersion = (\d+)', (perch_source('LidRestartHandoff.swift')).read_text())[1]),
            'LSUIElement': a.headless,'SUFeedURL':f'http://127.0.0.1:{a.port}/appcast.xml','SUPublicEDKey':public,
            'SUEnableAutomaticChecks':True,'SUAllowsAutomaticUpdates':False,'SUAutomaticallyUpdate':False,
            'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,'FixtureRoot':str(root)}
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    run('python3',repo/'Tools/embed-sparkle.py',app)
    run('codesign','--force','--sign','Perch Local Code Signing','--timestamp=none',app)
    run('codesign','--verify','--deep','--strict',app)
run('python3',repo/'Tools/prepare-update.py',root/'candidate/Perch.app','--output',root/'feed','--download-url',f'http://127.0.0.1:{a.port}/Perch-1.2.2.zip','--key-file',root/'fixture-private.txt','--fixture')
print(f'Built fixture; no launch performed. Serve {root / "feed"} on 127.0.0.1:{a.port}.')
