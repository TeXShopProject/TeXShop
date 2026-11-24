#!/usr/bin/env python3
"""Write the menu titles of earlier versions that a KeyEquivalents.plist may still use.

A KeyEquivalents.plist (~/Library/TeXShop/Menus) names menus and items by position or by
title, as the menus were when it was written. Titles change (a translation follows Apple's
terms, a typo is fixed), and an entry with the former title then reaches no item. This script
compares the MainMenu of every language in the versions below with the MainMenu of now and
writes Sources/Shortcuts/TSLegacyMenuTitles.inc: each former title of an item that still
exists, with the item it names (its identifier), and each former title of a menu, with an
item in that menu. Items are matched by their command (action and tag), menus by the items
they hold. Removed items are left out on purpose: their former titles reach nothing.

  python3 Scripts/update-legacy-menu-titles.py          # rewrite the table
  python3 Scripts/update-legacy-menu-titles.py --check  # fail if the table is out of date
  python3 Scripts/update-legacy-menu-titles.py --cases FILE  # write every former path and its item (for the tests)
"""
from pathlib import Path
import argparse, json, re, subprocess, sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
# 5.59, the last version before Settings › Keyboard, and 6.00 RC2, the last release before the
# menus took Apple's terms in every language.
REVISIONS = ['v.5.59', 'v.6.00-rc.2']
TABLE = ROOT / 'Sources/Shortcuts/TSLegacyMenuTitles.inc'
HAND = ROOT / 'Sources/Shortcuts/TSLegacyMenuKeyEquivalents.inc'

CJK = '[　-ヿ㐀-鿿！-｠]'
MARKS = [' (Englisch)', '（英語）', ' (영문)', ' (en inglés)', ' (en anglais)', ' (in inglese)', ' (Engels)',
         ' (em inglês)', ' (în engleză)', '（英文）']


def comparable(title):
    """TSLegacyComparableTitle (TSLegacyMenuKeyEquivalents.inc), which this must follow."""
    for mark in MARKS:
        if title.endswith(mark):
            title = title[:-len(mark)]
            break
    title = re.sub('[  ]?(\\.\\.\\.|…)', '…', title)
    title = title.strip(' \n')
    title = re.sub(' {2,}', ' ', title)
    return re.sub(f'(?<={CJK}) (?=[A-Za-z0-9])|(?<=[A-Za-z0-9]) (?={CJK})', '', title)


FIND = {'showFindPanel:': 1, 'findNext:': 2, 'findPrevious:': 3, 'replaceAll:': 4, 'replace:': 5,
        'replaceAndFind:': 6, 'useSelectionForFind:': 7}


def identifier(item):
    """The identifier of now (nibs before 5.60 have none): TSShortcut.<action>.<tag>, as TSFindCommandID shares them."""
    if (item.get('identifier') or '').startswith('TSShortcut.'):
        return item.get('identifier')
    action = item.find('connections/action')
    if action is None:
        return None
    selector = action.get('selector')
    if selector == 'jumpToSelection:':
        return 'TSShortcut.centerSelectionInVisibleArea:.0'
    if selector in FIND:
        return f'TSShortcut.performFindPanelAction:.{FIND[selector]}'
    if selector == 'splitWindow:' and item.get('alternate') == 'YES':
        return 'TSShortcut.splitWindow:.vertical'
    return f"TSShortcut.{selector}.{item.get('tag') or 0}"


class Node:
    def __init__(self, title, parent):
        self.title, self.parent, self.ident, self.children = title, parent, None, []

    def leaves(self):
        out = []
        for child in self.children:
            out += child.leaves() if child.children else [child.ident] if child.ident else []
        return out

    def chain(self):
        nodes, node = [], self
        while node.parent is not None:
            nodes.append(node)
            node = node.parent
        return nodes[::-1]


def load(language, revision):
    path = f'Resources/Interfaces/{language}.lproj/MainMenu.nib/designable.nib'
    if revision:
        try:
            xml = subprocess.check_output(['git', 'show', f'{revision}:{path}'], cwd=ROOT, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            return None
    else:
        xml = (ROOT / path).read_bytes()
    mains = [m for m in ET.fromstring(xml).iter('menu') if m.get('systemMenu') == 'main']
    assert len(mains) == 1, (language, revision)
    top = Node('', None)

    def walk(menu, node):
        for item in menu.findall('items/menuItem'):
            if item.get('isSeparatorItem') == 'YES':
                continue
            child = Node(item.get('title') or '', node)
            node.children.append(child)
            submenu = item.find('menu')
            if submenu is not None:
                walk(submenu, child)
            else:
                child.ident = identifier(item)
    walk(mains[0], top)
    return top


def same_menu(old, new, existing):
    """A menu of then is the menu of now with the same title, or the one that holds most of its items that still exist."""
    if comparable(old.title) == comparable(new.title):
        return True
    then, now = set(old.leaves()) & existing, set(new.leaves())
    return bool(then) and len(then & now) >= max(1, len(then) // 2)


def by_title(menu, key):
    """The title lookup of TSLegacyMenuItem before any table: the exact title, then the comparable one."""
    for child in menu.children:
        if child.title == key:
            return child
    if comparable(key):
        for child in menu.children:
            if comparable(child.title) == comparable(key):
                return child
    return None


def hand_titles():
    """Former titles that TSLegacyFormerTitleIdentifier and the Toggle On/Off and Add Word lists already handle."""
    text = HAND.read_text(encoding='utf-8')
    return {comparable(t) for t in re.findall(r'@"((?:[^"\\]|\\.)*)"', text) if not t.startswith('TSShortcut.')}


def analyse():
    languages = sorted(p.name[:-6] for p in (ROOT / 'Resources/Interfaces').glob('*.lproj')
                       if (p / 'MainMenu.nib/designable.nib').exists())
    handled = hand_titles()
    items, menus, cases, problems = {}, {}, [], []
    for language in languages:
        now = load(language, None)
        found = {}

        def index(node):
            for child in node.children:
                if child.children:
                    index(child)
                elif child.ident:
                    found.setdefault(child.ident, []).append(child)
        index(now)
        for revision in REVISIONS:
            then = load(language, revision)
            assert then is not None, (language, revision)

            def visit(node):
                for child in node.children:
                    if child.children:
                        visit(child)
                        continue
                    # KeyEquivalents.plist reaches three levels: a menu, an item, and an item of its submenu.
                    if not child.ident or child.ident not in found or len(child.chain()) > 3:
                        continue
                    if any(not comparable(a.title) for a in child.chain()):
                        continue  # a title of spaces alone names no item
                    old = child.chain()
                    for target in found[child.ident]:
                        new = target.chain()
                        if len(new) != len(old) or not all(same_menu(a, b, set(found)) for a, b in zip(old[:-1], new[:-1])):
                            continue  # moved to another menu: positions and titles of then are handled elsewhere
                        if all(a.title == b.title for a, b in zip(old, new)):
                            continue
                        case = {'language': language, 'revision': revision, 'former': [a.title for a in old],
                                'current': [b.title for b in new], 'identifier': child.ident, 'taken': False}
                        menu = now
                        for a, b in zip(old, new):
                            got = by_title(menu, a.title)
                            if got is not b:
                                if got is not None:
                                    # A title of then that another item has now: the item of now keeps it.
                                    case['taken'] = True
                                    problems.append(f'{language} {revision}: {" › ".join(case["former"])}: "{a.title}" is now the title of another item')
                                    break
                                if comparable(a.title) in handled:
                                    pass  # TSLegacyFormerTitleIdentifier
                                elif b.children:
                                    # One item per menu of now names it: the first one seen in it.
                                    seen = menus.setdefault(comparable(a.title), {})
                                    if not any(i in b.leaves() for i in seen):
                                        seen[child.ident] = True
                                else:
                                    items.setdefault(comparable(a.title), []).append(b.ident)
                            menu = b
                        cases.append(case)
            visit(then)
    def unique(values):
        out = []
        for v in values:
            if v not in out:
                out.append(v)
        return out
    items = {k: unique(v) for k, v in sorted(items.items())}
    menus = {k: unique(v) for k, v in sorted(menus.items())}
    return items, menus, cases, sorted(set(problems))


def c_string(s):
    return '@"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def render(items, menus):
    lines = ['// SPDX-License-Identifier: GPL-2.0-or-later',
             '// Written by Scripts/update-legacy-menu-titles.py from the MainMenu of every language in ' + ' and '.join(REVISIONS) + '.',
             '// Do not edit; run the script after a menu title changes.',
             '// Each entry: a former title (as TSLegacyComparableTitle compares it), then the items it named.',
             '// Item titles name the item with that identifier; menu titles name the menu that holds an item with that identifier.',
             'static NSArray<NSArray<NSString *> *> *TSLegacyFormerItemTitles(void)', '{', '    return @[']
    lines += [f'        @[{c_string(k)}, {", ".join(c_string(i) for i in v)}],' for k, v in items.items()]
    lines += ['    ];', '}', 'static NSArray<NSArray<NSString *> *> *TSLegacyFormerMenuTitles(void)', '{', '    return @[']
    lines += [f'        @[{c_string(k)}, {", ".join(c_string(i) for i in v)}],' for k, v in menus.items()]
    lines += ['    ];', '}', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--cases')
    args = parser.parse_args()
    items, menus, cases, problems = analyse()
    text = render(items, menus)
    if args.cases:
        Path(args.cases).write_text(json.dumps(cases, ensure_ascii=False))
    for p in problems:
        print('note:', p)
    if args.check:
        if not TABLE.exists() or TABLE.read_text(encoding='utf-8') != text:
            sys.exit(f'{TABLE.relative_to(ROOT)} is out of date: run Scripts/update-legacy-menu-titles.py')
        print(f'{TABLE.relative_to(ROOT)} is up to date: {len(items)} item titles, {len(menus)} menu titles, {len(cases)} former paths')
        return
    if not args.cases:
        TABLE.write_text(text, encoding='utf-8')
        print(f'wrote {TABLE.relative_to(ROOT)}: {len(items)} item titles, {len(menus)} menu titles, {len(cases)} former paths')


if __name__ == '__main__':
    main()
