#!/usr/bin/env python3
"""Bundle/check reviewed release documents, catalog sources and license notices."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
INVENTORY = REPO/'Release/dependencies.json'
DOCUMENTS = {'SUPPORT.md':'SUPPORT.md', 'THIRD-PARTY-NOTICES.md':'THIRD-PARTY-NOTICES.md',
             'catalog/NOTICE.md':'catalog-NOTICE.md', 'Release/dependencies.json':'dependencies.json',
             'Release/notes.md':'release-notes.txt'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def sources():
    inventory = json.loads(INVENTORY.read_text())
    files = [f for component in inventory['components'] for f in component['files']] + inventory['catalogs']
    for entry in files:
        if digest(REPO/entry['source']) != entry['sha256']:
            raise SystemExit('Reviewed dependency/catalog changed: '+entry['source']+'. Update provenance and review before bundling.')
    return inventory, {**{f['source']:f['resource'] for f in files}, **DOCUMENTS}

def check_pins(inventory):
    pins = json.loads((REPO/'Vendor/PerchCertificates/Package.resolved').read_text())['pins']
    for pin in pins:
        component = next(c for c in inventory['components'] if c['name']==pin['identity'])
        if component['revision'] != pin['state']['revision'] or component['version'] != pin['state']['version']:
            raise SystemExit('Package pin differs from reviewed dependency: '+pin['identity'])
        checkout = REPO/'Vendor/PerchCertificates/.build/checkouts'/pin['identity']
        head = subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
        dirty = subprocess.check_output(['git','-C',str(checkout),'status','--porcelain'],text=True).strip()
        if head != component['revision'] or dirty: raise SystemExit('Dependency checkout changed: '+pin['identity'])
    boring = next(c for c in inventory['components'] if c['name']=='BoringSSL')
    if boring['revision'] not in (REPO/'Vendor/PerchCertificates/.build/checkouts/swift-crypto/Sources/CCryptoBoringSSL/hash.txt').read_text():
        raise SystemExit('BoringSSL revision differs from its reviewed license.')

def check(app, publication=False):
    inventory, files = sources()
    resources = app/'Contents/Resources'
    for source, destination in files.items():
        path = resources/destination
        if not path.is_file() or path.is_symlink() or digest(path) != digest(REPO/source):
            raise SystemExit('Release resource missing or changed: '+destination)
    if publication:
        issues = [x for x in inventory['publicationIssues'] if x['status'] != 'resolved']
        if issues: raise SystemExit('Dependency review still open: '+'; '.join(x['detail'] for x in issues))
    return len(files)

def install(app):
    inventory, files = sources(); check_pins(inventory)
    resources=app/'Contents/Resources';resources.mkdir(parents=True,exist_ok=True)
    for source,destination in files.items():
        # Upstream notices may be read-only. Replace a completed temporary file
        # instead of opening an existing destination (or following its symlink).
        with tempfile.NamedTemporaryFile(dir=resources,delete=False) as stream:
            temporary=Path(stream.name)
        try:
            shutil.copyfile(REPO/source,temporary);temporary.chmod(0o644)
            temporary.replace(resources/destination)
        finally:
            if temporary.exists(): temporary.unlink()
    return check(app)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['install','check'])
    parser.add_argument('--app',type=Path,required=True)
    parser.add_argument('--for-publication',action='store_true')
    args=parser.parse_args()
    if args.mode=='install' and args.for_publication: parser.error('Publication only checks existing signed resources.')
    count=install(args.app) if args.mode=='install' else check(args.app,args.for_publication)
    print(f'PASS: {count} reviewed release resources match; no publication performed')
