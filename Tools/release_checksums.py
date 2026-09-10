"""Final release checksums. Call write only after notarization/stapling completes."""
import hashlib
from pathlib import Path
import re

def names(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+',version): raise ValueError('Invalid release version')
    return [f'Perch-{version}.dmg',f'Perch-{version}.zip','appcast.xml']

def digest(path):
    if not path.is_file() or path.is_symlink(): raise ValueError('Artifact missing or not a regular file: '+str(path))
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''): value.update(block)
    return value.hexdigest()

def text(hashes,version):
    return ''.join(hashes[name]+'  '+name+'\n' for name in names(version))

def write(root,version):
    hashes={name:digest(root/name) for name in names(version)}
    temporary=root/'SHA256SUMS.tmp';temporary.write_text(text(hashes,version));temporary.replace(root/'SHA256SUMS')
    return hashes

def verify(root,version,hashes):
    if set(hashes) != set(names(version)): raise ValueError('Verification receipt has an incomplete or unexpected artifact list')
    for name in names(version):
        if digest(root/name) != hashes[name]: raise ValueError('Verified artifact changed: '+name)
    path=root/'SHA256SUMS'
    if path.is_symlink() or path.read_text() != text(hashes,version): raise ValueError('SHA256SUMS differs from the verified artifacts')
