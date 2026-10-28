#!/usr/bin/env python3
"""Terada: prepare a signed update archive and feed locally; never publish."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)
FEED = 'https://texshopproject.github.io/TeXShop/appcast.xml'
KEY = 'GItwOa4Q8LuY9zjGfp1n9vgprCsyiRrRqQVPq1feN/I='
ROOT = Path(__file__).resolve().parents[1]

def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path, help='New staging directory')
    parser.add_argument('--tools', required=True, type=Path, help='Sparkle 2.10.1 bin directory')
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+(?:\.\d+)+', version):
        raise SystemExit('Expected a stable numeric release version')
    if info.get('SUFeedURL') != FEED or info.get('SUPublicEDKey') != KEY:
        raise SystemExit('Application has the wrong update feed or public key')
    if run(args.tools / 'generate_keys', '--account', 'TeXShopProject', '-p') != KEY:
        raise SystemExit('Keychain public key does not match the application')
    run('codesign', '--verify', '--deep', '--strict', app)
    run('spctl', '--assess', '--type', 'execute', app)
    run('xcrun', 'stapler', 'validate', app)
    tree = ET.parse(ROOT / 'website/appcast.xml')
    channel = tree.getroot().find('channel')
    if channel is None:
        raise SystemExit('Invalid appcast')
    if any(item.findtext(f'{{{SPARKLE}}}version') == info['CFBundleVersion'] for item in channel.findall('item')):
        raise SystemExit('This build version already exists in the feed')
    args.output.mkdir(parents=True, exist_ok=False)
    archive = args.output / f'TeXShop-{version}.zip'
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    signature = run(args.tools / 'sign_update', '--account', 'TeXShopProject', '-p', archive)
    run(args.tools / 'sign_update', '--account', 'TeXShopProject', '--verify', archive, signature)
    item = ET.Element('item')
    for tag, value in [('title', f'TeXShop {version}'), ('pubDate', format_datetime(datetime.now(timezone.utc))),
                       (f'{{{SPARKLE}}}version', info['CFBundleVersion']),
                       (f'{{{SPARKLE}}}shortVersionString', version),
                       (f'{{{SPARKLE}}}minimumSystemVersion', info['LSMinimumSystemVersion'])]:
        ET.SubElement(item, tag).text = value
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/TeXShopProject/TeXShop/releases/download/v{version}/{archive.name}',
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature})
    channel.insert(0, item)
    feed = args.output / 'appcast.xml'
    ET.indent(tree, space='  ')
    tree.write(feed, encoding='utf-8', xml_declaration=True)
    run(args.tools / 'sign_update', '--account', 'TeXShopProject', feed)
    run(args.tools / 'sign_update', '--account', 'TeXShopProject', '--verify', feed)
    print(f'Prepared {archive} and {feed}. Nothing was uploaded.')

if __name__ == '__main__':
    main()
