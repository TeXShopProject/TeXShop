#!/usr/bin/env python3
"""Check that Window > Fullscreen (Old Method) says it is the old method in every language.

TeXShop's own full screen (TSDocument -fullscreen:) is not the full screen of macOS (View > Enter Full Screen).
Its menu item names it as the old method in the MainMenu nib of every language, in the editable nib and in each
compiled variant, with Apple's term for full screen in that language. The compiled variants are loaded with AppKit
(NSNib, no window shown), and the item is found by its identifier and its action.
--mutation old-name puts back the earlier Japanese name in the editable nib, compiled-old-name reads the earlier
Japanese name from one compiled variant. The check must then fail.
"""
import argparse
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

NAMES = {
    'Base': 'Fullscreen (Old Method)',
    'de': 'Vollbild (alte Methode)',
    'es': 'Pantalla completa (método antiguo)',
    'fr': 'Plein écran (ancienne méthode)',
    'it': 'A tutto schermo (vecchio metodo)',
    'ja': 'フルスクリーン（旧方式）',
    'ko': '전체 화면 (옛날방식)',
    'nl': 'Schermvullend (oude methode)',
    'pt': 'Tela Cheia (método antigo)',
    'pt-PT': 'Ecrã completo (método antigo)',
    'ro': 'Pe tot ecranul (metoda veche)',
    'zh_CN': '全屏幕（旧方法）',
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['old-name', 'compiled-old-name'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
found = {}
try:
    for nib in sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib')):
        language = nib.parent.name.removesuffix('.lproj')
        text = (nib / 'designable.nib').read_text(encoding='utf-8')
        titles = re.findall(r'<menuItem title="([^"]*)" [^>]*identifier="TSShortcut\.fullscreen:\.0"', text)
        assert len(titles) == 1, f'{language}: the Fullscreen (Old Method) item is not found once'
        title = titles[0].replace('&amp;', '&')
        if args.mutation == 'old-name' and language == 'ja':
            title = 'フルスクリーン表示'
        assert title == NAMES.get(language), f'{language}: the item is named {title!r}, not {NAMES.get(language)!r}'
        found[language] = title
    # Each compiled variant, loaded as the app loads it: the item with the identifier, its title and action.
    program = r'''
#import <Cocoa/Cocoa.h>
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (int i = 1; i < argc; i++) {
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[i])] bundle:nil];
        NSArray *objects = nil;
        NSMutableArray *items = [NSMutableArray array];
        if ([nib instantiateWithOwner:NSApp topLevelObjects:&objects])
            for (id o in objects) if ([o isKindOfClass:NSMenu.class])
                for (NSMenuItem *top in [o itemArray]) for (NSMenuItem *item in top.submenu.itemArray)
                    if ([item.identifier isEqual:@"TSShortcut.fullscreen:.0"])
                        [items addObject:@{@"title": item.title, @"action": NSStringFromSelector(item.action) ?: @""}];
        result[@(argv[i])] = items;
    }
    puts([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:result options:0 error:nil] encoding:NSUTF8StringEncoding].UTF8String);
} return 0; }
'''
    compiled = sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
    assert len(compiled) >= 12, 'compiled MainMenu nibs not found'
    with tempfile.TemporaryDirectory(prefix='texshop-old-fullscreen-') as directory:
        temp = Path(directory)
        (temp / 'probe.m').write_text(program)
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', str(temp / 'probe.m'), '-o', str(temp / 'probe')], check=True)
        home = temp / 'home'
        (home / 'Library' / 'Preferences').mkdir(parents=True)
        environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temp))
        loaded = json.loads(subprocess.run([str(temp / 'probe'), *map(str, compiled)], env=environment, check=True,
                                           capture_output=True, text=True).stdout)
    for path in compiled:
        language = path.parent.parent.name.removesuffix('.lproj')
        items = loaded[str(path)]
        if args.mutation == 'compiled-old-name' and language == 'ja' and path.name == 'keyedobjects.nib':
            items = [dict(items[0], title='フルスクリーン表示')] if items else items
        assert len(items) == 1, f'{path.relative_to(root)}: Fullscreen (Old Method) is not found once'
        assert items[0]['action'] == 'fullscreen:', f'{path.relative_to(root)}: the item does not send fullscreen:'
        assert items[0]['title'] == NAMES[language], \
            f'{path.relative_to(root)}: the compiled item is named {items[0]["title"]!r}, not {NAMES[language]!r}; run Tests/compile-interface.py MainMenu'
    assert set(found) == set(NAMES), f'languages differ: {sorted(set(found) ^ set(NAMES))}'
except AssertionError as error:
    if args.mutation:
        print(f'PASS: detected mutation {args.mutation}: {error}')
        raise SystemExit(0)
    raise
if args.mutation:
    raise SystemExit(f'mutation {args.mutation} was not detected')
print(f'PASS: Fullscreen (Old Method) is named as the old method in all {len(found)} MainMenu nibs and in their {len(compiled)} compiled variants')
