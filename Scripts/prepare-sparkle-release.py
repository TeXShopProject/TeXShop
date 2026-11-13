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
FEED = 'https://texshop.app/appcast.xml'
# Builds offered only when Settings › Updates includes prereleases (TSSparklePrereleaseChannel).
PRERELEASE_CHANNEL = 'prerelease'
RELEASES = 'https://github.com/TeXShopProject/TeXShop/releases'
KEY = 'GItwOa4Q8LuY9zjGfp1n9vgprCsyiRrRqQVPq1feN/I='
ROOT = Path(__file__).resolve().parents[1]

def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()

def load_release_notes(version, directory):
    """Read finalized notes before accessing signing tools or creating artifacts."""
    notes = []
    for language, suffix in [('en', ''), ('ja', '-ja')]:
        path = directory / f'{version}{suffix}.md'
        if not path.is_file():
            raise ValueError(f'Missing {language} release notes: {path}')
        content = path.read_text(encoding='utf-8').strip()
        if not content.startswith(f'# TeXShop {version}\n'):
            raise ValueError(f'Release notes have the wrong version heading: {path}')
        if '<!-- release-status: draft -->' in content:
            raise ValueError(f'Finalize the draft release notes before packaging: {path}')
        notes.append((language, content))
    return notes


def append_release_notes(item, version, notes):
    # Markdown notes are supported by Sparkle 2.9+, including TeXShop 5.59.
    # Inline notes are covered by the existing whole-feed signature.
    for language, content in notes:
        ET.SubElement(item, 'description', {
            '{http://www.w3.org/XML/1998/namespace}lang': language,
            f'{{{SPARKLE}}}format': 'markdown',
        }).text = content
    ET.SubElement(item, f'{{{SPARKLE}}}fullReleaseNotesLink').text = (
        f'https://texshop.app/release-notes.html#v{version}')


def load_prerelease_notes(path):
    content = path.read_text(encoding='utf-8').strip()
    if not content:
        raise ValueError(f'Empty prerelease notes: {path}')
    return [('en', content)]


def is_prerelease_item(item):
    return item.findtext(f'{{{SPARKLE}}}channel') == PRERELEASE_CHANNEL


def prerelease_identity(info):
    """Return the release tag and archive name of a beta such as 5.60 beta-11 (5.60b11)."""
    beta = re.fullmatch(r'(\d+(?:\.\d+)+) beta-(\d+)', info['CFBundleShortVersionString'])
    if not beta or info['CFBundleVersion'] != f'{beta[1]}b{beta[2]}':
        raise ValueError('Expected a beta version such as 5.60 beta-11 with build version 5.60b11')
    return f'v.{beta[1]}-beta.{beta[2]}', f'TeXShop-{beta[1]}-beta-{beta[2]}.zip'


def retire_prereleases(channel, version, prerelease):
    """Only the newest beta stays in the feed, and a release retires its own betas."""
    for item in channel.findall('item'):
        short = item.findtext(f'{{{SPARKLE}}}shortVersionString') or ''
        if is_prerelease_item(item) and (prerelease or short.startswith(f'{version} beta-')):
            channel.remove(item)


def append_prerelease(item, notes, tag):
    ET.SubElement(item, f'{{{SPARKLE}}}channel').text = PRERELEASE_CHANNEL
    for language, content in notes:
        ET.SubElement(item, 'description', {
            '{http://www.w3.org/XML/1998/namespace}lang': language,
            f'{{{SPARKLE}}}format': 'markdown',
        }).text = content
    ET.SubElement(item, f'{{{SPARKLE}}}fullReleaseNotesLink').text = f'{RELEASES}/tag/{tag}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path, help='New staging directory')
    parser.add_argument('--tools', required=True, type=Path, help='Sparkle 2.10.1 bin directory')
    parser.add_argument('--replace-existing', action='store_true',
                        help='Replace the existing item for this build version in the staged feed')
    parser.add_argument('--prerelease', type=Path, metavar='NOTES',
                        help='Prepare a beta for the prerelease channel, with these Markdown notes')
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    if args.prerelease:
        try:
            tag, archive_name = prerelease_identity(info)
        except ValueError as error:
            raise SystemExit(str(error)) from error
    else:
        if not re.fullmatch(r'\d+(?:\.\d+)+', version):
            raise SystemExit('Expected a stable numeric release version')
        tag, archive_name = f'v.{version}', f'TeXShop-{version}.zip'
    try:
        notes = load_prerelease_notes(args.prerelease) if args.prerelease else load_release_notes(version, ROOT / 'Documentation/Releases')
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
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
    existing = [item for item in channel.findall('item')
                if item.findtext(f'{{{SPARKLE}}}version') == info['CFBundleVersion']]
    if existing and not args.replace_existing:
        raise SystemExit('This build version already exists in the feed')
    if args.replace_existing:
        if len(existing) != 1 or existing[0].findtext(f'{{{SPARKLE}}}shortVersionString') != version:
            raise SystemExit('Expected exactly one existing item for this release and build version')
        channel.remove(existing[0])
    retire_prereleases(channel, version, bool(args.prerelease))
    link = channel.find('link')
    if link is None:
        link = ET.SubElement(channel, 'link')
    link.text = FEED.rsplit('/', 1)[0] + '/'
    args.output.mkdir(parents=True, exist_ok=False)
    archive = args.output / archive_name
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    signature = run(args.tools / 'sign_update', '--account', 'TeXShopProject', '-p', archive)
    run(args.tools / 'sign_update', '--account', 'TeXShopProject', '--verify', archive, signature)
    item = ET.Element('item')
    for tag, value in [('title', f'TeXShop {version}'), ('pubDate', format_datetime(datetime.now(timezone.utc))),
                       (f'{{{SPARKLE}}}version', info['CFBundleVersion']),
                       (f'{{{SPARKLE}}}shortVersionString', version),
                       (f'{{{SPARKLE}}}minimumSystemVersion', info['LSMinimumSystemVersion'])]:
        ET.SubElement(item, tag).text = value
    if args.prerelease:
        append_prerelease(item, notes, tag)
    else:
        append_release_notes(item, version, notes)
    ET.SubElement(item, 'enclosure', {
        'url': f'{RELEASES}/download/{tag}/{archive.name}',
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
