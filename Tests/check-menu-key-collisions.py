#!/usr/bin/env python3
"""No two items of one MainMenu nib share a key equivalent with the same modifiers, in all 12 languages.

Until 6.00, Edit › Marks › Next Mark and Window › Enter Full Screen both had Control-Command-F in every
language; the menu that AppKit searched first took the key. Since 6.00 Next Mark has it alone: the nibs give
Enter Full Screen no key, and TeXShop gives it Globe-F at launch (TSGiveFullScreenGlobeKey; a nib cannot, and a
nib key would make AppKit add a hidden copy of the item with that key). The check reads the designable.nib of each
language, as the nibs are compiled from them, and counts every item that is not disabled in the nib,
alternates included (an alternate differs from its item by its modifiers). An uppercase letter is the
letter with Shift, as AppKit reads it. The run also checks that it still finds the former Control-Command-F
collision when Enter Full Screen is given that key again.
"""
from pathlib import Path
import collections
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']

# Collisions that are older than this check and wait for a decision. Each entry names the two commands by
# identifier; the check fails when one of them is gone, so that the entry is removed with the fix.
# (Source › Font › Copy Style shared Option-Command-C with Preview › Rotate Counterclockwise until 6.00, which removed
# the rich-text items of Source › Font.)
PENDING = {}


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
        # The mark keys as in 5.58, and Enter Full Screen without a key (no function="YES" either: ibtool drops it,
        # and the item would answer to a bare F).
        root = ET.fromstring(texts[language])
        rotate = [item.get('identifier') for item in root.iter('menuItem') if binding(item) == ('c', ('command', 'option'))]
        if rotate != ['TSShortcut.rotateCounterclockwise:.0']:
            failures.append(f'{language}: Option-Command-C belongs to {rotate}, not Rotate Counterclockwise alone')
        keys = {item.get('identifier'): binding(item) for item in root.iter('menuItem') if item.get('identifier')}
        expected = {'TSShortcut.doNextBullet:.0': ('f', ('command', 'control')),
                    'TSShortcut.doNextBulletAndDelete:.0': ('f', ('command', 'control', 'option')),
                    'TSShortcut.doPreviousBullet:.0': ('g', ('command', 'control')),
                    'TSShortcut.doPreviousBulletAndDelete:.0': ('g', ('command', 'control', 'option'))}
        for identifier, key in expected.items():
            if keys.get(identifier) != key:
                failures.append(f'{language}: {identifier} has {keys.get(identifier)}, not {key}')
        full = [item for item in root.iter('menuItem') if item.find("connections/action[@selector='toggleFullScreen:']") is not None]
        if len(full) != 1 or full[0].get('keyEquivalent') is not None or full[0].find('modifierMask') is not None:
            failures.append(f'{language}: Enter Full Screen has a key or modifiers in the nib')
        control_command_f = [item.get('identifier') for item in root.iter('menuItem')
                             if item.get('keyEquivalent') and binding(item) == ('f', ('command', 'control'))]
        if control_command_f != ['TSShortcut.doNextBullet:.0']:
            failures.append(f'{language}: Control-Command-F belongs to {control_command_f}, not Next Mark alone')
        if 'function="YES"' in texts[language]:
            failures.append(f'{language}: an item has the Globe (fn) modifier in the nib')
    # The check finds the collision that 6.00 removed: Enter Full Screen with Control-Command-F again.
    old = '<menuItem title="Enter Full Screen" id="1181" identifier="TSShortcut.toggleFullScreen:.0">'
    assert texts['Base'].count(old) == 1, 'Enter Full Screen in the Base menu'
    former = collisions(texts['Base'].replace(old, old.replace(' id=', ' keyEquivalent="f" id=') +
                                              '<modifierMask key="keyEquivalentModifierMask" control="YES" command="YES"/>'))
    assert any({i.get('identifier') for i in items} == {'TSShortcut.doNextBullet:.0', 'TSShortcut.toggleFullScreen:.0'}
               for items in former.values()), 'the former Control-Command-F collision is not found'
    if failures:
        print('\n'.join('FAIL: ' + failure for failure in failures))
        sys.exit(1)
    print(f'PASS: {len(LANGUAGES)} MainMenu nibs have no two items with the same key and modifiers '
          f'(Option-Command-C is Rotate Counterclockwise alone); Next Mark Control-Command-F alone and Previous Mark Control-Command-G; '
          f'Enter Full Screen without a key in the nibs; '
          f'the former Control-Command-F collision is found')


if __name__ == '__main__':
    main()
