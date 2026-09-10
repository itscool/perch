#!/usr/bin/env python3
"""Offline orchestration checks: no signing, network, Git mutations or UI."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('release_all',Path(__file__).with_name('release-all.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def rejects(action):
    try: action()
    except SystemExit: return
    raise AssertionError('Expected refusal')

with tempfile.TemporaryDirectory() as directory:
    root=Path(directory)
    (root/'app-submission.json').write_text(json.dumps({'id':'existing-app'}))
    statuses=iter(['In Progress','Accepted'])
    with patch.object(m,'run',side_effect=lambda *a,**k:json.dumps({'status':next(statuses)})), patch.object(m.time,'sleep'):
        m.wait_for_apple(root,'fixture','app',60)
    for status in ['In Progress','Invalid','Unknown']:
        with patch.object(m,'run',return_value=json.dumps({'status':status})):
            rejects(lambda:m.wait_for_apple(root,'fixture','app',0))

for resume in [False,True]:
    with tempfile.TemporaryDirectory() as directory:
        root=Path(directory);calls=[]
        if resume:
            (root/'Perch.app').mkdir()
            (root/'app-submission.json').write_text('{}')
            (root/'dmg-submission.json').write_text('{}')
        def fake_run(*args,**kwargs):
            args=tuple(map(str,args));calls.append(args)
            if args[:3] == ('git','status','--porcelain'): return ''
            if args[:3] == ('git','diff','--name-only'): return 'Info.plist'
            if args[:3] == ('git','diff','--cached'): return ''
            if args[:2] == ('git','rev-parse'): return 'fixture-commit'
            if len(args)>2 and args[1].endswith('/Tools/release.py'):
                stage=args[2]
                if stage=='build': (root/'Perch.app').mkdir()
                if stage=='submit-app': (root/'app-submission.json').write_text('{}')
                if stage=='submit-dmg': (root/'dmg-submission.json').write_text('{}')
            return ''
        scope={'release_commit':lambda *a:'fixture-commit','verify':lambda *a,**k:None}
        with patch.object(sys,'argv',['release-all.py','--output',str(root),'--profile','fixture','--publish']), \
             patch.dict(sys.modules,{'dmgbuild':object()}), \
             patch.object(m,'run',side_effect=fake_run),patch.object(m,'load_pipeline',return_value=scope), \
             patch.object(m,'wait_for_apple') as waiting,patch('release_assets.check'):
            m.main()
        stages=[a[2] for a in calls if len(a)>2 and a[1].endswith('/Tools/release.py')]
        expected=['package','finish','publish'] if resume else ['build','submit-app','package','submit-dmg','finish','publish']
        assert stages==expected,(stages,expected)
        assert waiting.call_count==2
        assert ('git','push') in calls
        assert (root/'source-commit.txt').read_text().strip()=='fixture-commit'
        if resume: assert not any(a[:2]==('git','commit') for a in calls)
print('PASS: pending/rejected/accepted polling, timeout, complete build-to-publish ordering, version-only commit, saved submissions reused on resume; no external effects')
