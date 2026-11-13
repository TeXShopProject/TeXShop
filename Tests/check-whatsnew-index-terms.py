#!/usr/bin/env python3
"""Check that the English help index keeps every word of What's New that it indexed before.

The index keeps at most 2000 words of What's New. The newest release is at the top of the page, so
a word that a new release note adds pushes out a word of an older release, which can then no
longer be found in Help. Release notes therefore use words that the index already has.

If a release note needs a new word on purpose, rebuild the index, check which word was pushed out,
and update Tests/Fixtures/WhatsNewIndexTerms.txt with --update."""
from pathlib import Path
import argparse
import subprocess
import sys

MUTATIONS = {
    # A word is pushed out (nstextview and started were, #25 audit and the Advanced Find panel); the word must be in the fixture.
    'word-pushed-out': lambda terms: terms - {'advanced'},
    # A new word comes in.
    'word-added': lambda terms: terms | {'else'},
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--update', action='store_true', help='write the terms of the current index to the fixture')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
index = root / 'Resources/Interfaces/en.lproj/TeXShopHelp/TeXShopHelp.helpindex'
fixture = root / 'Tests/Fixtures/WhatsNewIndexTerms.txt'
PAGE = '/pgs/whatisnew.htm'

# hiutil -T lists the words of each page under the page's path.
listing = subprocess.check_output(['hiutil', '-I', 'lsm', '-T', '-f', str(index)], text=True)
page, terms = None, set()
for line in listing.splitlines():
    if line.startswith('/'):
        page = line.strip()
    elif page == PAGE and line.strip():
        terms.add(line.strip())
if args.mutation:
    mutated = MUTATIONS[args.mutation](terms)
    assert mutated != terms, f'the mutation {args.mutation} changes nothing'
    terms = mutated
if args.update:
    fixture.write_text(''.join(t + '\n' for t in sorted(terms)), encoding='utf-8')
    print(f'updated {fixture.name}: {len(terms)} words')
    sys.exit(0)

expected = set(fixture.read_text(encoding='utf-8').split('\n')) - {''}
lost, added = sorted(expected - terms), sorted(terms - expected)
failed = bool(lost or added)
if args.mutation:
    assert failed, 'mutation not detected: ' + args.mutation
    print(f'PASS: detected mutation {args.mutation}: lost {lost}, added {added}')
    sys.exit(0)
if failed:
    print(f'FAIL: the words of What\'s New in the English help index changed: lost {lost}, added {added}. '
          'Reword the release note with words the index already has and rebuild the index, '
          'or update the fixture with --update if the change is intended.')
    sys.exit(1)
print(f'PASS: the English help index keeps all {len(terms)} words of What\'s New')
