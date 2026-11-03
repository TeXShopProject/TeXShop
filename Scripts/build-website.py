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
for name in ('index.html', 'en.html', 'ja.html', 'release-notes.html', 'release-notes-ja.html', 'downloads.html', 'downloads-ja.html', 'all-releases.html', 'all-releases-ja.html', 'contact.html', 'contact-ja.html'):
    japanese = name in ('ja.html', 'release-notes-ja.html', 'downloads-ja.html', 'all-releases-ja.html', 'contact-ja.html')
    pending = ('GitHubリポジトリと不具合報告へのリンクは、公開時に掲載します。' if japanese else
               'The source repository and issue tracker will be linked here when published.')
    links = f'<span class="pending">{pending}</span>'
    if args.repository:
        url = 'https://github.com/' + html.escape(args.repository, quote=True)
        source, issues = ('ソースコード', '不具合報告') if japanese else ('Source code', 'Report an issue')
        github_icon = '<svg aria-hidden="true" focusable="false" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"/></svg>'
        links = f'<a href="{url}">{github_icon}{source}</a><a href="{url}/issues">{github_icon}{issues}</a>'
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
