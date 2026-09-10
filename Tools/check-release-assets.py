#!/usr/bin/env python3
"""Check notice packaging, publication review and checksum tamper detection offline."""
from pathlib import Path
import tempfile
from unittest.mock import patch
import release_assets as assets
import release_checksums as checksums

def rejects(action):
    try: action()
    except (SystemExit,ValueError,OSError): return
    raise AssertionError('Invalid release input was accepted')

with tempfile.TemporaryDirectory(prefix='perch-release-assets-') as directory:
    root=Path(directory);app=root/'Perch.app'
    count=assets.install(app);assert assets.check(app)==count
    target=app/'Contents/Resources/BoringSSL-LICENSE.txt';original=target.read_bytes()
    target.chmod(0o444);assert assets.install(app)==count
    assert target.read_bytes()==original
    target.write_text('truncated license');rejects(lambda:assets.check(app))
    target.unlink();rejects(lambda:assets.check(app));target.write_bytes(original)
    inventory,files=assets.sources()
    with patch.object(assets,'sources',return_value=({**inventory,'publicationIssues':[{'status':'open','detail':'fixture unresolved data origin'}]},files)):
        rejects(lambda:assets.check(app,publication=True))
    with patch.object(assets,'sources',return_value=({**inventory,'publicationIssues':[]},files)):
        assert assets.check(app,publication=True)==count
    version='1.2.999'
    for name in checksums.names(version): (root/name).write_bytes(('fixture '+name).encode())
    hashes=checksums.write(root,version);checksums.verify(root,version,hashes)
    manifest=(root/'SHA256SUMS').read_text();assert len(manifest.splitlines())==3
    (root/'SHA256SUMS').write_text(manifest.replace(hashes['appcast.xml'],'0'*64))
    rejects(lambda:checksums.verify(root,version,hashes));(root/'SHA256SUMS').write_text(manifest)
    rejects(lambda:checksums.verify(root,version,{'appcast.xml':hashes['appcast.xml']}))
    (root/'appcast.xml').write_bytes(b'changed after verification');rejects(lambda:checksums.verify(root,version,hashes))
    (root/'appcast.xml').unlink();(root/'appcast.xml').symlink_to(root/'Perch-1.2.999.zip');rejects(lambda:checksums.write(root,version))
print(f'PASS: {count} packaged resources; missing/changed licenses, unresolved review, altered manifest/artifact, incomplete receipt and symlink rejection; no network, signing or publication')
