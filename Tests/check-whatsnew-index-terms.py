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
    # A word is pushed out (nstextview, started and tasks were, #25 audit, the Advanced Find panel, #38 and the version number 6.00; synchronization, think and track for the Find submenu of the Advanced Find panel; rescan for the Dracula theme; synchronization and track for TransparentTheme and SolarizedLite; formula, synchronization, telling, think and track for the names of languages and of the reporter of #42; 72 and 78 for the annotation buttons and the English Change Encoding item; sort and suddenly for MakeIndex and MetaPost under Related Tools; mathjax for the #38 link of the spelling item, accepted because the issue number has to stay; edu, https and uoregon left with the links to the former web site, and github, mathjax and movies came in with #43; brackets and input for the fix of the bracket highlight, which pushed out mathjax and static; auto, rotate and scale for Auto Rotate and Scale to Fit of the printing item, which pushed out 03, breaking and structures of older versions' notes; delete, export, import and rename for the list of themes in Settings, which pushed out bib, org, tug and uti of older versions' notes; 60 for the #60 link of the split Preview item, accepted because the issue number has to stay, which pushed out 61 of the 4.61 notes; 08 and rich for Copy with Style, which names copying in rich text as TeXShop 4.08 to 5.00 did, worded so at the user's request, which pushed out incompetently and sonoma of older versions' notes; 61 for the #61 link of the Return key in the drawer, accepted because the issue number has to stay, which pushed out relevant of older versions' notes; 66 for the #66 link of the first split of MultiPage display, accepted because the issue number has to stay, which pushed out transparency of older versions' notes; fullscreen for the removed item Fullscreen (Old Method), named as users know it, which pushed out spots of older versions' notes; 68 for the #68 link of quitting while the message that TeXShop is up to date is shown, accepted because the issue number has to stay, which pushed out obtain of older versions' notes; 69, seiji and zenitani for the #69 link and the name of the one who suggested the link in About TeXShop, accepted because the issue number and the name have to stay, which pushed out abouttypst, download and scheerder of older versions' notes; escape for -shell-escape in the note on how the default commands write TeX options, accepted because the name of the option has to stay, which pushed out jeroen of older versions' notes; what's for the title of the page, which the page structure of the help shows as its heading, which pushed out letting of older versions' notes; korean for the note that the Korean help is now in Korean, accepted because the name of the language has to stay, which pushed out cleanup of older versions' notes; 70 for the #70 link of opening a closed Preview window again at the same place, accepted because the issue number has to stay, which pushed out accomplish of older versions' notes; 71 for the #71 link of the Preview coming back as it was the next time TeXShop starts, accepted because the issue number has to stay, which pushed out destroyed of older versions' notes); the word must be in the fixture.
    'word-pushed-out': lambda terms: terms - {'advanced'},
    # A new word comes in; a word no release note uses, since common words such as else are already in the index.
    'word-added': lambda terms: terms | {'xyzzy'},
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
