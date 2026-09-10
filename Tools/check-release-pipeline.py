#!/usr/bin/env python3
"""Exercise release failure/retry gates with disposable artifacts and no upload."""
from pathlib import Path
import json
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
namespace = {'__file__':str(repo/'Tools/release.py')}
exec(compile((repo/'Tools/release.py').read_text().split('\np = argparse.ArgumentParser')[0], str(repo/'Tools/release.py'), 'exec'), namespace)
with tempfile.TemporaryDirectory(prefix='perch-release-check-') as temporary:
    root = Path(temporary); artifact = root/'candidate.zip'; artifact.write_bytes(b'fixture')
    calls = []
    def submit(*args, **kwargs):
        calls.append(args)
        return json.dumps({'id':'fixture-submission','status':'In Progress'})
    namespace['run'] = submit
    namespace['submission'](root,artifact,'fixture-profile','app')
    namespace['submission'](root,artifact,'fixture-profile','app')
    assert len(calls) == 1, 'Retry resubmitted a recorded archive'
    artifact.write_bytes(b'changed')
    try: namespace['submission'](root,artifact,'fixture-profile','app')
    except SystemExit: pass
    else: raise AssertionError('Changed archive reused an existing submission')
    def uncertain(*args, **kwargs):
        calls.append(args)
        raise subprocess.CalledProcessError(1,args)
    namespace['run'] = uncertain
    try: namespace['submission'](root,artifact,'fixture-profile','dmg')
    except subprocess.CalledProcessError: pass
    else: raise AssertionError('Unknown submission did not fail')
    count = len(calls)
    try: namespace['submission'](root,artifact,'fixture-profile','dmg')
    except SystemExit: pass
    else: raise AssertionError('Unknown submission allowed blind resubmission')
    assert len(calls) == count
    namespace['run'] = lambda *args, **kwargs: json.dumps({'status':'In Progress'})
    try: namespace['accepted'](root,'fixture-profile','app')
    except SystemExit: pass
    else: raise AssertionError('Pending notarization advanced to packaging')
    namespace['run'] = lambda *args, **kwargs: json.dumps({'status':'Invalid'})
    try: namespace['accepted'](root,'fixture-profile','app')
    except SystemExit: pass
    else: raise AssertionError('Rejected notarization advanced to packaging')
    namespace['run'] = lambda *args, **kwargs: json.dumps({'status':'Accepted'})
    namespace['accepted'](root,'fixture-profile','app')
print('PASS: immutable submissions, recorded retry, uncertain upload recovery, pending/rejected/accepted notarization gates; no network or credentials used')
