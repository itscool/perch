#!/usr/bin/env python3
"""Build, notarize, package and publish a Perch release in explicit stages.

Signing keys stay in Keychain. Each notarization submission records its attempt and returned ID; ambiguous
failures require checking Apple history before another upload. Publication is an
explicit final command after notarization and package verification.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import shutil
import xml.etree.ElementTree as ET
import release_assets
import release_checksums

REPO = Path(__file__).resolve().parents[1]
CONFIG = json.loads((REPO/'Release/config.json').read_text())

def run(*args, capture=False, env=None):
    if capture:
        return subprocess.check_output(list(map(str, args)), cwd=REPO, env=env, text=True).strip()
    subprocess.run(list(map(str, args)), cwd=REPO, env=env, check=True)

def info(app):
    return plistlib.loads((app/'Contents/Info.plist').read_bytes())

def verify(app, notarized=False):
    run('codesign', '--verify', '--deep', '--strict', app)
    release_assets.check(app)
    details = subprocess.run(['codesign','-dvvv',str(app)], capture_output=True, text=True, check=True).stderr
    if ('TeamIdentifier='+CONFIG['teamID']) not in details or 'runtime' not in details or 'Timestamp=' not in details:
        raise SystemExit('Release needs the expected Developer ID team, hardened runtime and secure timestamp.')
    p = info(app)
    if p.get('SUFeedURL') != CONFIG['feedURL'] or p.get('SUPublicEDKey') != CONFIG['publicKey']:
        raise SystemExit('Release updater configuration does not match the production config.')
    if run('lipo', '-archs', app/'Contents/MacOS/Perch', capture=True) != 'arm64':
        raise SystemExit('This release pipeline currently supports Apple silicon only.')
    if notarized:
        run('xcrun','stapler','validate',app)
        run('spctl','--assess','--type','execute','--verbose=2',app)

def source_snapshot():
    paths = run('git','ls-files','--cached','--others','--exclude-standard','-z',capture=True).split('\0')
    return {name: hashlib.sha256((REPO/name).read_bytes()).hexdigest()
            for name in sorted(set(paths)) if name and (REPO/name).is_file() and
            (name.startswith(('Sources/','Vendor/','Resources/','Tools/','catalog/','Release/licenses/')) or
             name in ('build.sh','Info.plist','Release/config.json','Release/Perch.entitlements','Release/dependencies.json','Release/notes.md','SUPPORT.md','THIRD-PARTY-NOTICES.md'))}

def release_commit(root, ref):
    """Verify the original compiled source, even when release tooling advances."""
    commit = run('git','rev-parse','--verify',ref+'^{commit}',capture=True)
    snapshot = json.loads((root/'source-snapshot.json').read_text())
    names = run('git','ls-tree','-r','--name-only','-z',commit,capture=True).split('\0')
    names = [n for n in names if n and (n.startswith(('Sources/','Vendor/','Resources/','Tools/','catalog/','Release/licenses/')) or
        n in ('build.sh','Info.plist','Release/config.json','Release/Perch.entitlements','Release/dependencies.json','Release/notes.md','SUPPORT.md','THIRD-PARTY-NOTICES.md'))]
    if set(names) != set(snapshot):
        raise SystemExit('Release source file set does not match the requested commit.')
    for name in names:
        data = subprocess.check_output(['git','show',commit+':'+name],cwd=REPO)
        if hashlib.sha256(data).hexdigest() != snapshot[name]:
            raise SystemExit('Release source differs from requested commit: '+name)
    return commit

def verify_feed(root, version):
    feed = root/'appcast.xml'
    signer = REPO/'build/dependencies/sparkle-2.9.6/bin/sign_update'
    run(signer,'--account',CONFIG['sparkleAccount'],'--verify',feed)
    item = ET.parse(feed).getroot().find('channel/item')
    namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    if item is None or item.findtext(namespace+'shortVersionString') != version or item.findtext(namespace+'hardwareRequirements') != 'arm64':
        raise SystemExit('Appcast version or architecture is incorrect.')
    enclosure = item.find('enclosure')
    archive = root/('Perch-'+version+'.zip')
    expected = 'https://github.com/'+CONFIG['repository']+'/releases/download/v'+version+'/'+archive.name
    if enclosure is None or enclosure.get('url') != expected or enclosure.get('length') != str(archive.stat().st_size):
        raise SystemExit('Appcast archive URL or size is incorrect.')
    run('xcrun','swift','Tools/verify-update-signature.swift',CONFIG['publicKey'],archive,enclosure.get(namespace+'edSignature',''))

def submission(root, artifact, profile, label):
    record = root/(label+'-submission.json')
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    if record.exists():
        saved = json.loads(record.read_text())
        if saved.get('artifactSHA256') != digest: raise SystemExit('Submitted artifact changed; use a fresh release folder.')
        print('Existing submission: '+saved['id']); return
    attempt = root/(label+'-submission-attempt.json')
    if attempt.exists():
        raise SystemExit('Previous submission outcome is uncertain. Inspect notarytool history and recover its ID before retrying; see Release/README.md.')
    attempt.write_text(json.dumps({'artifactSHA256':digest,'artifact':artifact.name},indent=2)+'\n')
    result = run('xcrun','notarytool','submit',artifact,'--keychain-profile',profile,'--output-format','json',capture=True)
    value = json.loads(result); value['artifactSHA256'] = digest; record.write_text(json.dumps(value,indent=2)+'\n')
    print('Submitted '+label+': '+value['id'])

def accepted(root, profile, label):
    record = json.loads((root/(label+'-submission.json')).read_text())
    result = json.loads(run('xcrun','notarytool','info',record['id'],'--keychain-profile',profile,'--output-format','json',capture=True))
    (root/(label+'-notarization.json')).write_text(json.dumps(result,indent=2)+'\n')
    if result.get('status') != 'Accepted':
        raise SystemExit('Apple notarization status: '+result.get('status','unknown')+'. Retry this stage when accepted; inspect the saved submission if rejected.')

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('stage',choices=['build','submit-app','package','submit-dmg','finish','publish'])
p.add_argument('--output',type=Path,required=True)
p.add_argument('--profile',help='Existing notarytool Keychain profile; never a password')
p.add_argument('--notes',type=Path,default=REPO/'Release/notes.md')
p.add_argument('--source-ref',default='HEAD',help='Publication tag target; must match every file in the candidate source snapshot')
a=p.parse_args(); root=a.output.resolve(); app=root/'Perch.app'
if root == REPO/'build': p.error('Use a separate release output directory.')
if a.stage in ['submit-app','package','submit-dmg','finish'] and not a.profile: p.error('This stage requires --profile.')
root.mkdir(parents=True,exist_ok=True)
if a.stage == 'build':
    if app.exists(): p.error('Use a fresh output directory for a new build.')
    env=os.environ.copy();env.update(PERCH_RELEASE_BUILD='1',PERCH_SIGN_IDENTITY=CONFIG['identity'],PERCH_UPDATE_FEED_URL=CONFIG['feedURL'],PERCH_UPDATE_PUBLIC_KEY=CONFIG['publicKey'])
    before = source_snapshot(); before.pop('Info.plist',None)
    run('bash','build.sh','--output',app,env=env); verify(app)
    snapshot = source_snapshot(); after = dict(snapshot); after.pop('Info.plist',None)
    if before != after: p.error('Source changed during compilation; rebuild in a fresh folder.')
    (root/'source-snapshot.json').write_text(json.dumps(snapshot,indent=2)+'\n')
    print('Developer ID build ready. Next: submit-app --profile YOUR_PROFILE.'); sys.exit(0)
verify(app)
version=info(app)['CFBundleShortVersionString'];tag='v'+version
zip_path=root/('Perch-'+version+'.zip');dmg=root/('Perch-'+version+'.dmg')
if a.stage == 'submit-app':
    archive=root/'notarize-app.zip'
    if not archive.exists(): run('ditto','-c','-k','--sequesterRsrc','--keepParent',app,archive)
    submission(root,archive,a.profile,'app')
elif a.stage == 'package':
    accepted(root,a.profile,'app');run('xcrun','stapler','staple',app);verify(app,notarized=True)
    if not dmg.exists():
        import dmgbuild
        branding=root/'branding';run('xcrun','swift','Tools/render-branding.swift',branding)
        dmgbuild.build_dmg(str(dmg),'Perch '+version,settings={
            'format':'ULFO','filesystem':'APFS','files':[str(app)],'symlinks':{'Applications':'/Applications'},
            'background':str(branding/'installer.png'),'icon':str(branding/'Perch.icns'),
            'icon_locations':{'Perch.app':(185,240),'Applications':(535,240)},
            'window_rect':((160,120),(720,440)),'icon_size':112,'text_size':14,
            'show_status_bar':False,'show_tab_view':False,'show_toolbar':False,'show_pathbar':False,'show_sidebar':False,
            'default_view':'icon-view','include_icon_view_settings':True,'include_list_view_settings':False,
        })
    if not (root/'dmg-submission-attempt.json').exists():
        run('codesign','--force','--sign',CONFIG['identity'],'--timestamp',dmg)
    if not zip_path.exists():
        with tempfile.TemporaryDirectory(prefix='sparkle-',dir=root) as temporary:
            staging = Path(temporary)
            run('python3','Tools/prepare-update.py',app,'--output',staging,'--account',CONFIG['sparkleAccount'],'--notes',a.notes,'--download-url','https://github.com/'+CONFIG['repository']+'/releases/download/'+tag+'/'+zip_path.name)
            verify_feed(staging,version)
            shutil.move(str(staging/'appcast.xml'),root/'appcast.xml')
            shutil.move(str(staging/zip_path.name),zip_path)
    verify_feed(root,version)
    print('Notarized app, installer and signed Sparkle feed prepared. Next: submit-dmg.')
elif a.stage == 'submit-dmg':
    submission(root,dmg,a.profile,'dmg')
elif a.stage == 'finish':
    accepted(root,a.profile,'dmg');run('xcrun','stapler','staple',dmg)
    run('xcrun','stapler','validate',dmg);run('codesign','--verify',dmg);verify(app,notarized=True)
    run('hdiutil','verify',dmg);run('unzip','-tq',zip_path);verify_feed(root,version)
    hashes=release_checksums.write(root,version)
    release_checksums.verify(root,version,hashes)
    (root/'verified-release.json').write_text(json.dumps({'version':version,'artifacts':hashes,'notesSHA256':hashlib.sha256(a.notes.read_bytes()).hexdigest()},indent=2)+'\n')
    print('Verified release ready. Publication is the explicit final stage.')
elif a.stage == 'publish':
    if run('git','status','--porcelain',capture=True): p.error('Commit and push the reviewed release source before publishing.')
    target = release_commit(root,a.source_ref)
    receipt=json.loads((root/'verified-release.json').read_text())
    if receipt['notesSHA256'] != hashlib.sha256(a.notes.read_bytes()).hexdigest(): p.error('Release notes changed after verification.')
    if receipt['version'] != version: p.error('Release verification is for another version.')
    try: release_checksums.verify(root,version,receipt['artifacts'])
    except (ValueError,OSError) as error: p.error(str(error))
    release_assets.check(app,publication=True)
    verify(app,notarized=True)
    existing=subprocess.run(['gh','release','view',tag,'--repo',CONFIG['repository'],'--json','isDraft'],capture_output=True,text=True)
    if existing.returncode == 0:
        if not json.loads(existing.stdout)['isDraft']: p.error('This release is already public; published assets are immutable.')
        p.error('A draft already exists. Inspect it and resume explicitly without duplicate uploads.')
    run('gh','release','create',tag,dmg,zip_path,root/'appcast.xml',root/'SHA256SUMS','--repo',CONFIG['repository'],'--draft','--title','Perch '+version,'--notes-file',a.notes,'--target',target)
    # Draft upload completes before making any appcast reachable to users.
    run('gh','release','edit',tag,'--repo',CONFIG['repository'],'--draft=false','--latest')
    print('Published https://github.com/'+CONFIG['repository']+'/releases/tag/'+tag)
