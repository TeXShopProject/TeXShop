#!/usr/bin/env python3
"""Titles of 5.59 and 6.00 RC2 in a KeyEquivalents.plist still name their items in the compiled menu of every language.

Scripts/update-legacy-menu-titles.py lists every path of menu titles of those versions whose item still exists but
whose titles changed (Apple's terms, fixed typos, the ellipsis). For each, the former path is looked up level by level as
TSApplyLegacyMenuKeys does, in the compiled MainMenu of that language: it must name that item. The table it
writes must be up to date. Mutations: without the table, without the ellipsis rule, and without two rows of the table
(the Portuguese Fonte), the check must fail.
"""
from pathlib import Path
import json, shutil, subprocess, sys, tempfile
from source_tree import include_args

r = Path(__file__).resolve().parents[1]
PROBE = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#include "TSLegacyMenuKeyEquivalents.inc"
// The item a path of titles names, as TSApplyLegacyMenuKeys looks it up level by level, and the titles of its menus now.
static NSArray *Reach(NSMenu *main, NSArray<NSString *> *former)
{
    NSMenu *menu = main; NSMenuItem *item = nil;
    for (NSString *title in former) { if (menu == nil) return @[]; item = TSLegacyMenuItem(menu, title); if (item == nil) return @[]; menu = item.submenu; }
    NSMutableArray *path = [NSMutableArray array];
    for (NSMenuItem *x = item; x != nil; ) {
        [path insertObject:x.title atIndex:0];
        NSMenu *within = x.menu, *above = within.supermenu;
        x = above ? [above itemAtIndex:[above indexOfItemWithSubmenu:within]] : nil;
    }
    return @[@[item.identifier ?: @"", path]];
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    NSArray *cases = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
    NSDictionary *nibs = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:nil];
    NSMutableDictionary *menus = [NSMutableDictionary dictionary];
    NSUInteger checked = 0, failed = 0;
    for (NSDictionary *c in cases) {
        if ([c[@"taken"] boolValue]) continue;
        NSString *language = c[@"language"];
        NSMenu *main = menus[language];
        if (main == nil) {
            NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:nibs[language]] bundle:nil]; NSArray *objects = nil;
            if (![nib instantiateWithOwner:NSApp topLevelObjects:&objects]) { fprintf(stderr, "FAIL: %s: the menu loads\n", language.UTF8String); return 1; }
            for (id o in objects) if ([o isKindOfClass:NSMenu.class] && [o numberOfItems] > 5) main = o;
            menus[language] = main;
        }
        // Only the English menu had Find and Replace… before 6.00 (positions only; set as the application does).
        TSLegacyMenuHadFindAndReplace = [language isEqualToString:@"Base"] ? 1 : 0;
        // The lookup is checked rather than the key it gives: AppKit keeps Enter Full Screen from taking a key when its nib
        // has none (its own key is fn-F), so a key is no evidence there.
        NSArray *former = c[@"former"];
        NSArray *reached = Reach(main, former);
        checked++;
        // ibtool writes a no-break space in a title as a space; titles are compared as the lookup compares them.
        BOOL ok = reached.count == 1 && [reached[0][0] isEqualToString:c[@"identifier"]] && [reached[0][1] count] == [c[@"current"] count];
        for (NSUInteger k = 0; ok && k < [c[@"current"] count]; k++)
            ok = [TSLegacyComparableTitle(reached[0][1][k]) isEqualToString:TSLegacyComparableTitle(c[@"current"][k])];
        if (!ok) {
            failed++;
            if (failed <= 20) fprintf(stderr, "FAIL: %s (%s): %s reaches %s, not %s\n", language.UTF8String, [c[@"revision"] UTF8String],
                                      [former componentsJoinedByString:@" › "].UTF8String, reached.description.UTF8String,
                                      [c[@"current"] componentsJoinedByString:@" › "].UTF8String);
        }
    }
    printf("%lu former paths checked, %lu failed\n", (unsigned long)checked, (unsigned long)failed);
    return failed ? 1 : 0;
} }
'''


def run(td, sources, label):
    """Compile the probe with the .inc files in `sources` (patched copies for the mutations) and run it."""
    probe, program = Path(td) / f'probe-{label}', Path(td) / f'probe-{label}.m'
    program.write_text(PROBE)
    # The probe uses the lookup, not TSApplyLegacyMenuKeys, and a mutation may leave a function unused.
    unused = ['-Wno-unused-function']
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror', *unused, '-I', str(sources),
                    *include_args(r), '-I', str(r / 'Tests'), '-framework', 'Cocoa', str(program), '-o', str(probe)], check=True)
    return subprocess.run([str(probe), str(Path(td) / 'cases.json'), str(Path(td) / 'nibs.json')], capture_output=True, text=True)


with tempfile.TemporaryDirectory(prefix='texshop-legacy-titles-') as td:
    subprocess.run([sys.executable, str(r / 'Scripts/update-legacy-menu-titles.py'), '--check', '--cases', str(Path(td) / 'cases.json')], check=True)
    cases = json.loads((Path(td) / 'cases.json').read_text())
    # The renames this check is for are among the cases.
    def has(language, former, current):
        return any(c['language'] == language and former(c['former']) and current(c['current']) for c in cases)
    assert has('pt', lambda f: f[0] == 'Fonte', lambda c: c[0] == 'Código-fonte'), 'pt: the former Source menu Fonte'
    assert has('pt', lambda f: f[:2] == ['Fonte', 'Tipos'], lambda c: c[:2] == ['Código-fonte', 'Fonte']), 'pt: the former Font menu Tipos'
    assert has('de', lambda f: f[-1].endswith('...'), lambda c: c[-1].endswith(' …')), 'de: titles that ended in ...'
    assert sum(not c['taken'] for c in cases) > 1000, len(cases)
    nibs = {}
    for nib in sorted((r / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects.nib')):
        nibs[nib.parent.parent.name[:-6]] = str(nib)
    assert len(nibs) == 12, nibs
    (Path(td) / 'nibs.json').write_text(json.dumps(nibs))
    shortcuts = r / 'Sources/Shortcuts'
    result = run(td, shortcuts, 'now')
    # AppKit logs that the Function modifier of KeyEquivalents.plist keys is ignored; leave that out.
    print(result.stdout + ''.join(l for l in result.stderr.splitlines(True) if 'NSEventModifierFlagFunction' not in l), end='')
    if result.returncode:
        sys.exit('FAIL: former titles do not all reach their items')
    print('PASS: former menu titles of 5.59 and 6.00 RC2 reach the same items in 12 languages')
    if '--no-mutations' not in sys.argv:
        main_inc, table = 'TSLegacyMenuKeyEquivalents.inc', 'TSLegacyMenuTitles.inc'
        mutations = {
            'no-table': (main_inc, 'return TSLegacyRenamedItem(items, menu, key);', 'return nil;'),
            'no-ellipsis': (main_inc, 'title = [ellipsis stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@"\\u2026"];', '(void)ellipsis;'),
            'stale-table': (table, '        @[@"Fonte", @"TSShortcut.doCommentOrIndent:.1"],\n', ''),
        }
        for label, (name, old, new) in mutations.items():
            mutated = Path(td) / label
            mutated.mkdir()
            for f in (main_inc, table):
                shutil.copy2(shortcuts / f, mutated / f)
            text = (mutated / name).read_text(encoding='utf-8')
            assert text.count(old) == 1, (label, old)
            (mutated / name).write_text(text.replace(old, new), encoding='utf-8')
            result = run(td, mutated, label)
            assert result.returncode != 0, f'mutation {label} was not detected'
            print(f'PASS: mutation {label} detected ({result.stdout.strip().splitlines()[-1]})')
