#!/usr/bin/env python3
"""Apply public update configuration before the app is signed. No secrets here."""
import base64
import os
from pathlib import Path
import plistlib
import sys
from urllib.parse import urlparse

path = Path(sys.argv[1]) / 'Contents/Info.plist'
feed = os.environ.get('PERCH_UPDATE_FEED_URL')
key = os.environ.get('PERCH_UPDATE_PUBLIC_KEY')
if bool(feed) != bool(key):
    raise SystemExit('Set both PERCH_UPDATE_FEED_URL and PERCH_UPDATE_PUBLIC_KEY, or neither.')
if feed:
    url = urlparse(feed)
    try: valid_key = len(base64.b64decode(key, validate=True)) == 32
    except ValueError: valid_key = False
    if url.scheme != 'https' or not url.hostname or url.username or url.password or not valid_key:
        raise SystemExit('Updates require an HTTPS feed and a base64 32-byte public Ed25519 key.')
    info = plistlib.loads(path.read_bytes())
    info.update(SUFeedURL=feed, SUPublicEDKey=key)
    path.write_bytes(plistlib.dumps(info, sort_keys=False))
