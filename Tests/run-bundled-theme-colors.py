#!/usr/bin/env python3
"""The colors of the bundled themes can be read, and the copies that earlier users have get the new colors.

1. Every bundled theme (and the reserve copies of Lite and Dark): the content of braces, the active line and the text
   found by SyncTeX are painted behind the text, so the text and the colors of commands, comments, markers, brackets,
   index entries, footnotes and the brace highlight stay readable on them (contrast as WCAG measures it: the text at
   least min(4.5, 0.8 x its contrast on the background), each other color at least min(3, 0.5 x its contrast on the
   background)). Index entries and the XML colors are readable on the background (at least 3), and so are commands in
   a theme whose source window is opaque.
2. -[TSColorSupport updateBundledThemeColorsInDirectory:after:], compiled unchanged with TSThemeFileStore, run on
   copies of the themes that TeXShop 5.58 put in ~/Library/TeXShop/Themes: every color that the bundled themes changed
   since then is updated, and nothing else. A color the user chose, a renamed copy, a theme of the user's own, a key
   the theme lacks and a theme reached through a symbolic link stay; the opacity stays; a second run changes nothing;
   a theme that cannot be read or written leaves the update to be done again; a theme that another TeXShop saves
   right after it is read keeps what was saved (its old colors are still updated).
3. The table of changes is complete: it holds every color of a bundled theme that differs from 5.58, from its 5.58
   value to its current value. The update runs at launch before the themes are read.

No window is opened; the harness works in a temporary folder.

  --mutations  break one rule at a time and check that the test notices
"""
from pathlib import Path
import argparse, os, plistlib, shutil, subprocess, sys, tempfile
from source_tree import include_args

ROOT = Path(__file__).resolve().parents[1]
THEMES = ROOT / 'Resources/TeXShop/Themes'
RESERVE = ROOT / 'Resources/Themes'
SUPPORT = 'Sources/Editor/TSColorSupport.m'
DELEGATE = 'Sources/App/TSAppDelegate.m'
BASE = 'db040b9b'  # the import of TeXShop 5.58

MUTATIONS = {
    'a color the user chose is replaced': (SUPPORT, '        if (!unchanged)\n            continue;\n', ''),
    'the opacity is replaced': (SUPPORT, '        for (NSUInteger c = 0; c < 3; c++)\n            color[c] = @(change->to[c]);',
                                '        [color setArray:@[@(change->to[0]), @(change->to[1]), @(change->to[2]), @1]];'),
    'a failed write still counts as done': (SUPPORT, '    return written ? last : update;', '    return last;'),
    'an update is done again': (SUPPORT, '    NSInteger last = update;\n', '    NSInteger last = update;\n    update = 0;\n'),
    'the file is replaced without checking what is there': (SUPPORT, '            if (![[NSData dataWithContentsOfURL:fileURL] isEqualToData:data])\n                continue;\n', ''),
    'a theme that cannot be read counts as done': (SUPPORT, '            if (![colors isKindOfClass:NSMutableDictionary.class])\n                return;', '            if (![colors isKindOfClass:NSMutableDictionary.class]) {\n                done = YES;\n                return;\n            }'),
    'symbolic links are followed': (SUPPORT, '        NSURL *url = [store URLForTitle:theme];',
                                    '        NSURL *url = [store.directory URLByAppendingPathComponent:[theme stringByAppendingPathExtension:@"plist"]];'),
    'the LiteTheme content color is left out': (SUPPORT, '    {1, @"LiteTheme", @"EditorHighlightContent",', '    {0, @"LiteTheme", @"EditorHighlightContent",'),
    'the update runs after the themes are read': (DELEGATE,
        '    [[TSColorSupport sharedInstance] updateBundledThemeColors];\n    [[TSColorSupport sharedInstance]  initializeColors];\n',
        '    [[TSColorSupport sharedInstance]  initializeColors];\n    [[TSColorSupport sharedInstance] updateBundledThemeColors];\n'),
}

PROBE = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TSColorSupport.h"
// TS_CONCURRENT_SAVE: right after the first read of LiteTheme.plist, another TeXShop saves that file with these bytes.
static IMP originalRead;
static BOOL saved;
static id readThenSave(id self, SEL _cmd, NSURL *url) {
    id data = ((id (*)(id, SEL, NSURL *))originalRead)(self, _cmd, url);
    const char *path = getenv("TS_CONCURRENT_SAVE");
    if (path && !saved && [url.lastPathComponent isEqualToString:@"LiteTheme.plist"]) {
        saved = YES;
        [[NSData dataWithContentsOfFile:@(path)] writeToURL:url options:0 error:NULL];
    }
    return data;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Method m = class_getClassMethod(NSData.class, @selector(dataWithContentsOfURL:));
        originalRead = method_setImplementation(m, (IMP)readThenSave);
        NSURL *directory = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        printf("%ld\n", (long)[[TSColorSupport sharedInstance] updateBundledThemeColorsInDirectory:directory after:atol(argv[2])]);
    }
    return 0;
}
'''


def luminance(rgb):
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb[:3]]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(a, b):
    lighter, darker = sorted([luminance(a), luminance(b)], reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def bundled():
    return {f'{folder.name}/{p.stem}': plistlib.loads(p.read_bytes()) for folder in (THEMES, RESERVE) for p in sorted(folder.glob('*.plist'))}


def readability_problems(themes):
    shown = ['SyntaxCommand', 'SyntaxComment', 'SyntaxMarker', 'SyntaxMarkerParen', 'SyntaxMarkerCurly', 'SyntaxMarkerSquare',
             'SyntaxIndex', 'FootnoteColor', 'EditorHighlightBraces']
    problems = []
    for name, theme in themes.items():
        background, text = theme['EditorBackground'], theme['EditorText']
        for painted in ('EditorHighlightContent', 'EntryColor', 'EditorReverseSync'):
            if painted not in theme:
                continue
            if contrast(text, theme[painted]) < min(4.5, 0.8 * contrast(text, background)):
                problems.append(f'{name}: text on {painted}')
            for key in shown:
                color = theme.get(key) or theme.get('SyntaxMarker')
                if color and contrast(color, theme[painted]) < min(3, 0.5 * contrast(color, background)):
                    problems.append(f'{name}: {key} on {painted}')
        opaque = theme.get('SourceAlpha', [0, 0, 0, 1])[3] >= 1
        for key in ['SyntaxIndex', 'XMLComment', 'XMLTag', 'XMLSpecial', 'XMLParameter', 'XMLValue'] + (['SyntaxCommand'] if opaque else []):
            if key in theme and contrast(theme[key], background) < 3:
                problems.append(f'{name}: {key} on the background')
    return problems


def old_theme(name):
    result = subprocess.run(['git', 'show', f'{BASE}:Resources/TeXShop/Themes/{name}.plist'], cwd=ROOT, capture_output=True)
    return plistlib.loads(result.stdout) if result.returncode == 0 else None


def changed_colors():
    """Every color of a bundled theme that differs from 5.58, keyed by (theme, key): (old, new)."""
    changes = {}
    for path in sorted(THEMES.glob('*.plist')):
        old, new = old_theme(path.stem), plistlib.loads(path.read_bytes())
        if old is None:
            continue
        for key, value in new.items():
            if isinstance(old.get(key), list) and any(abs(a - b) > 1e-9 for a, b in zip(old[key][:3], value[:3])):
                changes[(path.stem, key)] = (old[key], value)
    return changes


def build(text, tmp):
    for path, source in text.items():
        target = tmp / 'src' / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source, encoding='latin1')
    (tmp / 'probe.m').write_text(PROBE)
    includes = [arg for arg in include_args(ROOT)]
    includes = ['-I', str((tmp / 'src' / SUPPORT).parent)] + includes
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', *includes, str(tmp / 'probe.m'),
                    str(tmp / 'src' / SUPPORT), str(ROOT / 'Sources/Settings/TSThemeFileStore.m'), str(ROOT / 'Sources/App/globals.m'),
                    '-o', str(tmp / 'probe')], check=True)
    return tmp / 'probe'


def run(probe, folder, after, concurrent=None):
    env = dict(os.environ, **({'TS_CONCURRENT_SAVE': str(concurrent)} if concurrent else {}))
    out = subprocess.run([str(probe), str(folder), str(after)], capture_output=True, text=True, check=True, env=env)
    return int(out.stdout.strip())


def update_problems(text):
    problems = []
    delegate = text[DELEGATE]
    update, initialize = delegate.find('[[TSColorSupport sharedInstance] updateBundledThemeColors];'), delegate.find('[[TSColorSupport sharedInstance]  initializeColors];')
    if update < 0 or initialize < 0 or update > initialize:
        problems.append('the update does not run at launch before the themes are read')
    with tempfile.TemporaryDirectory(prefix='texshop-bundled-theme-colors-') as name:
        tmp = Path(name)
        probe = build(text, tmp)
        changes = changed_colors()
        olds = {p.stem: old_theme(p.stem) for p in sorted(THEMES.glob('*.plist'))}
        olds = {k: v for k, v in olds.items() if v is not None}

        def fresh(folder):
            folder.mkdir()
            for theme, colors in olds.items():
                (folder / f'{theme}.plist').write_bytes(plistlib.dumps(colors))
            return folder

        def close(a, b):
            return all(abs(x - y) < 1e-6 for x, y in zip(a[:3], b[:3]))

        # Themes as 5.58 left them: every changed color is updated and nothing else.
        folder = fresh(tmp / 'plain')
        if run(probe, folder, 0) != 1:
            problems.append('the update is not reported as done')
        for theme, old in olds.items():
            now = plistlib.loads((folder / f'{theme}.plist').read_bytes())
            for key in set(old) | set(now):
                expected = changes[(theme, key)][1] if (theme, key) in changes else old.get(key)
                value = now.get(key)
                if isinstance(expected, list):
                    if not isinstance(value, list) or not close(value, expected) or value[3:] != old[key][3:]:
                        problems.append(f'{theme} {key} is {value}, not {expected}')
                elif value != expected:
                    problems.append(f'{theme} {key} changed')
        # After the update, the user goes back to an old color; the next launch leaves it.
        lite = plistlib.loads((folder / 'LiteTheme.plist').read_bytes())
        lite['EditorHighlightContent'] = olds['LiteTheme']['EditorHighlightContent']
        (folder / 'LiteTheme.plist').write_bytes(plistlib.dumps(lite))
        before = {p.name: p.read_bytes() for p in folder.iterdir()}
        if run(probe, folder, 1) != 1 or {p.name: p.read_bytes() for p in folder.iterdir()} != before:
            problems.append('a second run changes the themes')

        # The user's own choices.
        folder = fresh(tmp / 'user')
        lite = dict(olds['LiteTheme'])
        lite['EditorHighlightContent'] = [0.9, 0.2, 0.2, 1]           # a color the user chose
        lite['EntryColor'] = olds['LiteTheme']['EntryColor'][:3] + [0.5]
        lite['SyntaxIndex'] = olds['LiteTheme']['SyntaxIndex'][:3] + [0.4]  # the bundled color with an opacity of its own
        del lite['XMLParameter']                                          # a key the theme lacks
        (folder / 'LiteTheme.plist').write_bytes(plistlib.dumps(lite, fmt=plistlib.FMT_BINARY))
        shutil.copy(folder / 'LiteTheme.plist', folder / 'My Lite.plist')
        own = tmp / 'own.plist'
        own.write_bytes(plistlib.dumps(olds['DarkTheme']))
        (folder / 'DarkTheme.plist').unlink()
        os.symlink(own, folder / 'DarkTheme.plist')
        mine = (folder / 'My Lite.plist').read_bytes()
        run(probe, folder, 0)
        now = plistlib.loads((folder / 'LiteTheme.plist').read_bytes())
        if now['EditorHighlightContent'] != [0.9, 0.2, 0.2, 1]:
            problems.append('a color the user chose is replaced')
        if not close(now['SyntaxIndex'], changes[('LiteTheme', 'SyntaxIndex')][1]) or now['SyntaxIndex'][3] != 0.4:
            problems.append('the bundled color with its own opacity is not updated, or loses the opacity')
        if 'XMLParameter' in now:
            problems.append('a key the theme lacks is added')
        if not close(now['XMLValue'], changes[('LiteTheme', 'XMLValue')][1]):
            problems.append('a binary theme is not updated')
        if (folder / 'My Lite.plist').read_bytes() != mine:
            problems.append('a renamed copy is changed')
        if own.read_bytes() != plistlib.dumps(olds['DarkTheme']) or not (folder / 'DarkTheme.plist').is_symlink():
            problems.append('a theme reached through a symbolic link is changed')

        # Another TeXShop saves LiteTheme right after it is read: what it saved stays, and the old colors in it are updated.
        folder = fresh(tmp / 'concurrent')
        theirs = dict(olds['LiteTheme'])
        theirs['SyntaxIndex'] = [0.1, 0.2, 0.3, 1]
        theirs['EditorBackground'] = [0.25, 0.35, 0.45, 1]
        theirs['Title'] = 'Saved meanwhile'
        (tmp / 'theirs.plist').write_bytes(plistlib.dumps(theirs))
        if run(probe, folder, 0, concurrent=tmp / 'theirs.plist') != 1:
            problems.append('the update with a save meanwhile is not reported as done')
        now = plistlib.loads((folder / 'LiteTheme.plist').read_bytes())
        if now['SyntaxIndex'] != [0.1, 0.2, 0.3, 1] or now['EditorBackground'] != [0.25, 0.35, 0.45, 1] or now['Title'] != 'Saved meanwhile':
            problems.append('a theme saved meanwhile by another TeXShop is overwritten')
        if not close(now['EditorHighlightContent'], changes[('LiteTheme', 'EditorHighlightContent')][1]):
            problems.append('the old colors of a theme saved meanwhile are not updated')

        # A theme that is there but cannot be read: the update is left to be done, and done once it can be read.
        folder = fresh(tmp / 'unreadable')
        os.chmod(folder / 'LiteTheme.plist', 0)
        try:
            if run(probe, folder, 0) != 0:
                problems.append('an update with a theme that could not be read is reported as done')
        finally:
            os.chmod(folder / 'LiteTheme.plist', 0o644)
        if run(probe, folder, 0) != 1 or not close(plistlib.loads((folder / 'LiteTheme.plist').read_bytes())['EditorHighlightContent'], changes[('LiteTheme', 'EditorHighlightContent')][1]):
            problems.append('a theme that can be read again is not updated')

        # A folder that cannot be written: nothing is lost, and the update is left to be done.
        folder = fresh(tmp / 'locked')
        os.chmod(folder, 0o555)
        try:
            if run(probe, folder, 0) != 0:
                problems.append('an update that could not be written is reported as done')
        finally:
            os.chmod(folder, 0o755)
    return problems


def table_problems(text):
    """Every color that changed since 5.58 is in the table, from its 5.58 value to its current value."""
    import re
    source = text[SUPPORT]
    rows = re.findall(r'\{(\d+), @"([^"]+)", @"([^"]+)", \{([^}]*)\}, \{([^}]*)\}\}', source)
    table = {(theme, key): ([float(x) for x in old.split(',')], [float(x) for x in new.split(',')]) for _, theme, key, old, new in rows}
    problems = []
    changes = changed_colors()
    for (theme, key), (old, new) in changes.items():
        if (theme, key) not in table:
            problems.append(f'{theme} {key} is not in the table')
        elif any(abs(a - b) > 1e-6 for a, b in zip(table[(theme, key)][0], old[:3])) or any(abs(a - b) > 1e-6 for a, b in zip(table[(theme, key)][1], new[:3])):
            problems.append(f'{theme} {key} has other values in the table')
    for entry in table:
        if entry not in changes:
            problems.append(f'{entry} is in the table but did not change')
    return problems


def check(text):
    return readability_problems(bundled()) + table_problems(text) + update_problems(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    text = {path: (ROOT / path).read_text(encoding='latin1') for path in (SUPPORT, DELEGATE)}
    problems = check(text)
    if problems:
        sys.exit('FAIL: ' + '\n      '.join(problems))
    print('PASS: the bundled themes can be read, and the themes of earlier users get the new colors where they kept the old ones')
    if args.mutations:
        for name, (path, old, new) in MUTATIONS.items():
            assert text[path].count(old) == 1, name
            mutated = dict(text, **{path: text[path].replace(old, new)})
            if not check(mutated):
                sys.exit(f'FAIL: mutation not detected: {name}')
            print(f'PASS: mutation detected: {name}')


if __name__ == '__main__':
    main()
