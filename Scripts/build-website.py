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
links = '<span class="pending">The GitHub repository and issue tracker will be linked here when publication is ready.</span>'
if args.repository:
    url = 'https://github.com/' + html.escape(args.repository, quote=True)
    links = f'<a href="{url}">Source code ↗</a><a href="{url}/issues">Report an issue ↗</a>'
page = args.output / 'index.html'
page.write_text(page.read_text().replace('@@REPOSITORY_LINKS@@', links))
(args.output / '.nojekyll').touch()
print(args.output.resolve())
