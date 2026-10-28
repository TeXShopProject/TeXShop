#!/usr/bin/env python3
# added by Terada: Build a static Pages artifact without publishing it.
import argparse
import html
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
shutil.copytree(root / 'website', args.output)
for name in ('index.html', 'en.html', 'ja.html', 'release-notes.html', 'release-notes-ja.html', 'downloads.html', 'downloads-ja.html'):
    japanese = name in ('ja.html', 'release-notes-ja.html', 'downloads-ja.html')
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
(args.output / '.nojekyll').touch()
print(args.output.resolve())
