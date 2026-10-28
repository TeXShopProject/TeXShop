#!/usr/bin/env python3
# added by Terada: Build a static Pages artifact without publishing it.
import argparse
import html
import hashlib
import json
from urllib.request import urlopen
from pathlib import Path
import re
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('--repository', default='', help='GitHub OWNER/REPOSITORY; omit for an unpublished preview')
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
if args.repository and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+', args.repository):
    parser.error('Expected a GitHub OWNER/REPOSITORY')
root = Path(__file__).resolve().parents[1]
if args.output.exists():
    parser.error('Output must be a new directory')
# added by Terada: Restore large historical files from our own release storage.
archive = root / 'website' / 'archive'
manifest = json.loads((archive / 'manifest.json').read_text())
for item in manifest['items']:
    if 'release_asset_url' not in item:
        continue
    local = archive / item['file']
    if not local.exists():
        local.parent.mkdir(parents=True, exist_ok=True)
        temporary = local.with_suffix(local.suffix + '.partial')
        try:
            with urlopen(item['release_asset_url'], timeout=60) as response, temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            with temporary.open('rb') as source:
                if hashlib.file_digest(source, 'sha256').hexdigest() != item['sha256']:
                    raise ValueError('Historical download checksum mismatch: ' + item['file'])
            temporary.replace(local)
        finally:
            temporary.unlink(missing_ok=True)
    with local.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != item['sha256']:
            raise ValueError('Historical download checksum mismatch: ' + item['file'])
shutil.copytree(root / 'website', args.output)
for name in ('index.html', 'en.html', 'ja.html', 'release-notes.html', 'release-notes-ja.html', 'downloads.html', 'downloads-ja.html', 'contact.html', 'contact-ja.html'):
    japanese = name in ('ja.html', 'release-notes-ja.html', 'downloads-ja.html', 'contact-ja.html')
    pending = ('GitHubリポジトリと不具合報告へのリンクは、公開時に掲載します。' if japanese else
               'The source repository and issue tracker will be linked here when published.')
    links = f'<span class="pending">{pending}</span>'
    if args.repository:
        url = 'https://github.com/' + html.escape(args.repository, quote=True)
        source, issues = ('ソースコード', '不具合報告') if japanese else ('Source code', 'Report an issue')
        links = f'<a href="{url}">{source}</a><a href="{url}/issues">{issues}</a>'
    page = args.output / name
    contact = ('https://github.com/' + html.escape(args.repository, quote=True)) if args.repository else '#development'
    page.write_text(page.read_text().replace('@@REPOSITORY_LINKS@@', links).replace('@@CONTACT_URL@@', contact))
# Added by Terada: use a new stylesheet URL whenever its contents change.
style_version = hashlib.sha256((args.output / 'style.css').read_bytes()).hexdigest()[:12]
for page in args.output.rglob('*.html'):
    source = page.read_text()
    source = re.sub(r'''(<link\b[^>]*\bhref=["'])((?:\.\./)?style\.css)(["'])''',
                    lambda match: match[1] + match[2] + '?v=' + style_version + match[3], source)
    page.write_text(source)
(args.output / '.nojekyll').touch()
print(args.output.resolve())
