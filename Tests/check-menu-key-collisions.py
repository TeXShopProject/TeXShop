#!/usr/bin/env python3
"""No two items of one MainMenu nib share a key equivalent with the same modifiers, in all 12 languages.

Until 6.00, Edit › Marks › Next Mark and Window › Enter Full Screen both had Control-Command-F in every
language; the menu that AppKit searched first took the key. The check reads the designable.nib of each
language, as the nibs are compiled from them, and counts every item that is not disabled in the nib,
alternates included (an alternate differs from its item by its modifiers). An uppercase letter is the
letter with Shift, as AppKit reads it. The run also checks that it still finds the former Control-Command-F
collision when Next Mark is given that key again.
"""
from pathlib import Path
import collections
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']

# Collisions that are older than this check and wait for a decision. Each entry names the two commands by
# identifier; the check fails when one of them is gone, so that the entry is removed with the fix.
# Source › Font › Copy Style and Preview › Rotate Counterclockwise have Option-Command-C in every language
# (5.58 had them so); a source window has only Copy Style enabled, a Preview window only the rotation, and in a
# single window the Source menu, searched first, takes the key while the source has the focus.
PENDING = {(language, ('c', ('command', 'option'))): {'TSShortcut.copyFont:.0', 'TSShortcut.rotateCounterclockwise:.0'}
           for language in LANGUAGES}


def binding(item):
    key = item.get('keyEquivalent', '')
    mask = item.find('modifierMask')
    modifiers = {'command'} if mask is None else {name for name, value in mask.attrib.items() if value == 'YES'}
    if len(key) == 1 and key.lower() != key:
        key, modifiers = key.lower(), modifiers | {'shift'}
    return key, tuple(sorted(modifiers))


def collisions(text):
    seen = collections.defaultdict(list)
    for item in ET.fromstring(text).iter('menuItem'):
        if not item.get('keyEquivalent') or item.get('enabled') == 'NO':
            continue
        seen[binding(item)].append(item)
    return {key: items for key, items in seen.items() if len(items) > 1}


def describe(key, items):
    shown = '+'.join(key[1] + (key[0],))
    return f'{shown}: ' + ', '.join(f'{item.get("title")} ({item.get("identifier")})' for item in items)


def main():
    failures = []
    texts = {}
    for language in LANGUAGES:
        path = ROOT / f'Resources/Interfaces/{language}.lproj/MainMenu.nib/designable.nib'
        texts[language] = path.read_text(encoding='utf-8')
        found = collisions(texts[language])
        for key, items in sorted(found.items()):
            pending = PENDING.get((language, key))
            if pending is not None and {item.get('identifier') for item in items} == pending:
                continue
            failures.append(f'{language}: {describe(key, items)}')
        for (pending_language, key), identifiers in PENDING.items():
            if pending_language == language and (key not in found or {i.get('identifier') for i in found[key]} != identifiers):
                failures.append(f'{language}: the pending collision {key} is gone; remove it from PENDING')
        # The mark keys and Enter Full Screen as the nibs give them since 6.00.
        root = ET.fromstring(texts[language])
        keys = {item.get('identifier'): binding(item) for item in root.iter('menuItem') if item.get('identifier')}
        expected = {'TSShortcut.doNextBullet:.0': (']', ('command', 'control')),
                    'TSShortcut.doNextBulletAndDelete:.0': (']', ('command', 'control', 'option')),
                    'TSShortcut.doPreviousBullet:.0': ('[', ('command', 'control')),
                    'TSShortcut.doPreviousBulletAndDelete:.0': ('[', ('command', 'control', 'option')),
                    'TSShortcut.toggleFullScreen:.0': ('f', ('command', 'control'))}
        for identifier, key in expected.items():
            if keys.get(identifier) != key:
                failures.append(f'{language}: {identifier} has {keys.get(identifier)}, not {key}')
    # The check finds the collision that 6.00 removed: Next Mark with Control-Command-F again.
    old = 'keyEquivalent="]" id="881" identifier="TSShortcut.doNextBullet:.0"'
    assert texts['Base'].count(old) == 1, 'Next Mark in the Base menu'
    former = collisions(texts['Base'].replace(old, old.replace('"]"', '"f"')))
    assert any({i.get('identifier') for i in items} == {'TSShortcut.doNextBullet:.0', 'TSShortcut.toggleFullScreen:.0'}
               for items in former.values()), 'the former Control-Command-F collision is not found'
    if failures:
        print('\n'.join('FAIL: ' + failure for failure in failures))
        sys.exit(1)
    print(f'PASS: {len(LANGUAGES)} MainMenu nibs have no two items with the same key and modifiers '
          f'(pending: Option-Command-C); Next Mark Control-Command-] and Previous Mark Control-Command-[; '
          f'the former Control-Command-F collision is found')


if __name__ == '__main__':
    main()
