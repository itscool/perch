#!/usr/bin/env python3
"""Apply public update configuration before the app is signed. No secrets here.

Every build gets the production feed and public key from Release/config.json,
so a Mac testing a local build is still offered the next release. Setting both
PERCH_UPDATE_FEED_URL and PERCH_UPDATE_PUBLIC_KEY points a build elsewhere,
for a fixture feed.
"""
import base64
import json
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
if not feed:
    config = json.loads((Path(__file__).resolve().parents[1]/'Release/config.json').read_text())
    feed, key = config['feedURL'], config['publicKey']
if feed:
    url = urlparse(feed)
    try: valid_key = len(base64.b64decode(key, validate=True)) == 32
    except ValueError: valid_key = False
    if url.scheme != 'https' or not url.hostname or url.username or url.password or not valid_key:
        raise SystemExit('Updates require an HTTPS feed and a base64 32-byte public Ed25519 key.')
    info = plistlib.loads(path.read_bytes())
    info.update(SUFeedURL=feed, SUPublicEDKey=key)
    path.write_bytes(plistlib.dumps(info, sort_keys=False))
