#!/usr/bin/env python3
"""Prepare a signed Sparkle archive/feed locally. Never upload or publish.

The input app must already have its final signature, feed URL and public key.
For subsequent releases pass the existing appcast to retain version history.
"""
import argparse
import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument('app', type=Path)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--download-url', required=True)
p.add_argument('--appcast', type=Path)
p.add_argument('--notes', type=Path, help='Plain-text release notes, authenticated inside the signed feed')
key = p.add_mutually_exclusive_group(required=True)
key.add_argument('--key-file', type=Path)
key.add_argument('--account')
p.add_argument('--fixture', action='store_true', help='Allow loopback HTTP for disposable test apps only')
a = p.parse_args()
repo = Path(__file__).resolve().parents[1]
info = plistlib.loads((a.app / 'Contents/Info.plist').read_bytes())
architectures = subprocess.check_output(['lipo', '-archs', str(a.app/'Contents/MacOS'/info['CFBundleExecutable'])], text=True).split()
if architectures != ['arm64']:
    p.error('This manifest format currently supports Perch’s arm64 build only; add per-architecture identities before publishing other architectures.')
url = urllib.parse.urlparse(a.download_url)
def allowed_url(value):
    return not value.username and not value.password and bool(value.hostname) and (value.scheme == 'https' or
        (a.fixture and value.scheme == 'http' and value.hostname in ('127.0.0.1', 'localhost') and info['CFBundleIdentifier'].startswith('local.perch.sparkle-fixture')))
if not allowed_url(url):
    p.error('Downloads require HTTPS (or an explicitly isolated loopback fixture).')
if not info.get('SUPublicEDKey') or not info.get('SUFeedURL') or not info.get('SURequireSignedFeed') or not info.get('SUVerifyUpdateBeforeExtraction'):
    p.error('The signed app must contain its feed URL, public key and required signature-verification settings.')
if not allowed_url(urllib.parse.urlparse(info['SUFeedURL'])):
    p.error('The signed app has an invalid feed URL.')
if info['CFBundleShortVersionString'].split('.')[-1] != info['CFBundleVersion']:
    p.error('The displayed three-part version must end in the build counter.')
a.output.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('dependency', repo / 'Tools/sparkle-dependency.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
sparkle = module.dependency()
signer = str(sparkle / 'bin/sign_update')
keyargs = ['-f', str(a.key_file.resolve())] if a.key_file else ['--account', a.account]
archive = a.output / f'Perch-{info["CFBundleShortVersionString"]}.zip'
if archive.exists():
    p.error('The versioned archive already exists; use a new output directory or build number.')
manifest = subprocess.check_output(['xcrun', 'swift', str(repo / 'Tools/update-identity.swift'), str(a.app.resolve())])
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(a.app.resolve()), str(archive)], check=True)
after = subprocess.check_output(['xcrun', 'swift', str(repo / 'Tools/update-identity.swift'), str(a.app.resolve())])
if after != manifest:
    raise SystemExit('The signed app changed while packaging. Rebuild from an immutable candidate in a fresh output directory.')
# A signing tool can print malformed secret input in an error. Capture its
# output and report a generic error on failure, never echo private key material.
def sign(path, print_signature=True):
    result = subprocess.run([signer, *keyargs, *(['-p'] if print_signature else []), str(path)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('Update signing failed. Check the selected key/account; no signer output was printed.')
    return result.stdout.strip()
with tempfile.TemporaryDirectory(prefix='perch-update-sign-') as temporary:
    payload = Path(temporary) / 'identity.json'; payload.write_bytes(manifest)
    identity_signature = sign(payload)
    subprocess.run(['xcrun', 'swift', str(repo / 'Tools/verify-update-signature.swift'), info['SUPublicEDKey'], str(payload), identity_signature], check=True)
archive_signature = sign(archive)
S = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
P = 'https://github.com/itscool/perch/xml-namespaces/update'
ET.register_namespace('sparkle', S); ET.register_namespace('perch', P)
if a.appcast:
    root = ET.fromstring(a.appcast.read_bytes())
    channel = root.find('channel')
    if channel is None: p.error('Existing appcast has no channel')
else:
    root = ET.Element('rss', {'version':'2.0'}); channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'Perch updates'
for item in channel.findall('item'):
    if item.findtext(f'{{{S}}}version') == info['CFBundleVersion']: p.error('Appcast already contains this build')
item = ET.Element('item'); channel.insert(1, item)
ET.SubElement(item, 'title').text = f'Perch {info["CFBundleShortVersionString"]}'
ET.SubElement(item, f'{{{S}}}version').text = info['CFBundleVersion']
ET.SubElement(item, f'{{{S}}}shortVersionString').text = info['CFBundleShortVersionString']
ET.SubElement(item, f'{{{S}}}minimumSystemVersion').text = info.get('LSMinimumSystemVersion', '26.0')
ET.SubElement(item, f'{{{S}}}hardwareRequirements').text = 'arm64'
if a.notes:
    ET.SubElement(item, 'description', {f'{{{S}}}format':'plain-text'}).text = a.notes.read_text()
ET.SubElement(item, f'{{{P}}}identity').text = base64.b64encode(manifest).decode()
ET.SubElement(item, f'{{{P}}}identitySignature').text = identity_signature
ET.SubElement(item, 'enclosure', {'url':a.download_url, 'length':str(archive.stat().st_size), 'type':'application/octet-stream', f'{{{S}}}edSignature':archive_signature})
feed = a.output / 'appcast.xml'
ET.indent(root); ET.ElementTree(root).write(feed, encoding='utf-8', xml_declaration=True)
sign(feed, False)
print(f'Prepared locally: {archive}\nSigned appcast: {feed}')
