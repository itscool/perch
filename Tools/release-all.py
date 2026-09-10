#!/usr/bin/env python3
"""Build, notarize both artifacts, verify, and optionally publish a release.

Requires explicit notarization authorization. Reuse the same output directory to
resume. Never installs/restarts the live app. Credentials remain in Keychain.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]

def load_pipeline():
    scope = {'__file__':str(REPO/'Tools/release.py')}
    exec(compile((REPO/'Tools/release.py').read_text().split('\np = argparse.ArgumentParser')[0],
                 str(REPO/'Tools/release.py'),'exec'),scope)
    return scope

def run(*args, capture=False):
    result = subprocess.run(list(map(str,args)), cwd=REPO, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None

def wait_for_apple(root, profile, label, seconds):
    record = json.loads((root/(label+'-submission.json')).read_text())
    deadline = time.monotonic()+seconds
    previous = None
    while True:
        value = json.loads(run('xcrun','notarytool','info',record['id'],
            '--keychain-profile',profile,'--output-format','json',capture=True))
        (root/(label+'-notarization.json')).write_text(json.dumps(value,indent=2)+'\n')
        status = value.get('status','Unknown')
        if status != previous:
            print(label+': '+status+' ('+record['id']+')',flush=True)
            previous = status
        if status == 'Accepted': return
        if status != 'In Progress':
            raise SystemExit('Apple did not accept '+label+'. Inspect notarytool log for '+record['id']+'.')
        if time.monotonic() >= deadline:
            raise SystemExit('Apple is still processing. Rerun this same command to resume without resubmitting.')
        time.sleep(min(30, max(0,deadline-time.monotonic())))

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--profile',required=True,help='notarytool Keychain profile, normally Perch')
    p.add_argument('--publish',action='store_true',help='Push source and publish verified GitHub release/feed')
    p.add_argument('--source-ref',help='Resume a candidate from this exact source commit; default saved commit or HEAD')
    p.add_argument('--wait-seconds',type=int,default=3600,help='Maximum wait per Apple submission (default 3600); rerun safely on timeout')
    a = p.parse_args()
    if a.wait_seconds < 0: p.error('--wait-seconds must be nonnegative')
    root = a.output.resolve()
    if root == REPO/'build' or root == REPO: p.error('Use a separate release directory.')
    # Require the packaging interpreter before reserving a version/submitting.
    try: import dmgbuild
    except ImportError: p.error('Use a Python environment with Release/requirements.txt installed.')
    root.mkdir(parents=True,exist_ok=True)
    import fcntl
    with (root/'pipeline.lock').open('w') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: p.error('This release directory already has an active pipeline.')
        def stage(name):
            print('Release stage: '+name,flush=True)
            run(sys.executable,REPO/'Tools/release.py',name,'--output',root,
                '--profile',a.profile,'--source-ref',source_ref)
        source_file = root/'source-commit.txt'
        source_ref = a.source_ref or (source_file.read_text().strip() if source_file.exists() else 'HEAD')
        if run('git','status','--porcelain',capture=True):
            p.error('Commit reviewed changes first; release automation only commits its own version bump.')
        if not (root/'Perch.app').exists():
            if a.source_ref: p.error('--source-ref is for resuming an existing candidate; build from current checkout.')
            stage('build')
            changed = run('git','diff','--name-only',capture=True).splitlines()
            if changed != ['Info.plist'] or run('git','diff','--cached','--name-only',capture=True):
                p.error('Unexpected source changes during build. Inspect and commit before resuming.')
            run('git','add','Info.plist')
            run('git','commit','-m','Reserve Perch release version')
            source_ref = run('git','rev-parse','HEAD',capture=True)
        # Import only the shared definitions; the staged CLI is intentionally
        # separately executable for manual investigation and recovery.
        scope = load_pipeline()
        source_ref = scope['release_commit'](root,source_ref)
        source_file.write_text(source_ref+'\n')
        scope['verify'](root/'Perch.app')
        import release_assets
        if a.publish: release_assets.check(root/'Perch.app',publication=True)
        if not (root/'app-submission.json').exists(): stage('submit-app')
        wait_for_apple(root,a.profile,'app',a.wait_seconds)
        if not (root/'verified-release.json').exists():
            stage('package')
            if not (root/'dmg-submission.json').exists(): stage('submit-dmg')
            wait_for_apple(root,a.profile,'dmg',a.wait_seconds)
            stage('finish')
        else:
            # Recheck final bytes without resubmitting the now-stapled DMG.
            import release_checksums
            receipt=json.loads((root/'verified-release.json').read_text())
            version=scope['info'](root/'Perch.app')['CFBundleShortVersionString']
            if receipt['version'] != version: p.error('Verification receipt is for another version.')
            release_checksums.verify(root,version,receipt['artifacts'])
            scope['verify'](root/'Perch.app',notarized=True)
            scope['verify_feed'](root,version)
        if a.publish:
            run('git','push')
            stage('publish')
        else: print('Verified release ready. Add --publish to publish this same release.',flush=True)

if __name__ == '__main__': main()
