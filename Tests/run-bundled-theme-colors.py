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
   since then is updated, and nothing else; run after the first update on copies that 6.00 beta 1 put there: every
   color changed since beta 1 is updated, the expl3 colors (which 5.58 did not have) included. A color the user chose, a renamed copy, a theme of the user's own, a key
   the theme lacks and a theme reached through a symbolic link stay; the opacity stays; a second run changes nothing;
   a theme that cannot be read or written leaves the update to be done again; a theme that another TeXShop saves
   right after it is read keeps what was saved (its old colors are still updated).
3. The table of changes is complete: update 1 holds every color of a bundled theme that differs between 5.58 and
   6.00 beta 1, from its 5.58 value to its beta 1 value, and update 2 every color that differs between beta 1 and
   now, from its beta 1 value to its current value. The update runs at launch before the themes are read.
4. Every color drawn as text (the text, syntax, expl3 and XML colors, the console and the log) can be read on its
   background in every bundled theme (contrast at least 4.5), and the expl3 and XML colors also on the content of
   braces, the active line and the text found by SyncTeX (at least 3); comments are told from the text
   (color difference CIE76 at least 20); the matching braces are marked in a color that shows on the background (at
   least 3); copied images keep their text when their colors are mapped (the foreground of every bundled theme is
   opaque, and TeXShop draws a fully transparent foreground of an earlier copy opaque).

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
DOCCOLOR = 'Sources/Editor/TSDocument-Color.m'
BASE = 'db040b9b'  # the import of TeXShop 5.58
# The bundled themes each update of the table starts from: update 1 from 5.58, update 2 from 6.00 beta 1.
UPDATES = {1: BASE, 2: '8b9db011'}  # 8b9db011 is the tag v.6.00-beta.1
LAST = max(UPDATES)

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
    'the DarkTheme comment is left out of update 2': (SUPPORT, '    {2, @"DarkTheme", @"SyntaxComment",', '    {1, @"DarkTheme", @"SyntaxComment",'),
    'a transparent image foreground stays transparent': (DOCCOLOR, '        myColor = [myColor colorWithAlphaComponent:1];', ''),
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
    # Named by their folder under Resources, so that the reserve copies do not hide the bundled themes of the same name.
    return {f'{folder.relative_to(ROOT / "Resources")}/{p.stem}': plistlib.loads(p.read_bytes()) for folder in (THEMES, RESERVE) for p in sorted(folder.glob('*.plist'))}


def difference(a, b):
    """CIE76 color difference of two sRGB colors."""
    def lab(c):
        f = lambda x: x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
        r, g, b = (f(v) for v in c[:3])
        x, y, z = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047, 0.2126 * r + 0.7152 * g + 0.0722 * b, (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        g2 = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
        return 116 * g2(y) - 16, 500 * (g2(x) - g2(y)), 200 * (g2(y) - g2(z))
    return sum((p - q) ** 2 for p, q in zip(lab(a), lab(b))) ** 0.5


def source_problems(text):
    problems = []
    if '        myColor = [myColor colorWithAlphaComponent:1];' not in text[DOCCOLOR] or 'myColor.alphaComponent == 0' not in text[DOCCOLOR]:
        problems.append('a fully transparent image foreground is not drawn opaque')
    return problems


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
            # The expl3 and XML colors are drawn on these too (the active line, for instance).
            for key in ['explFunction', 'explIntenseFunction', 'explIntenseVariable', 'explVariable', 'explmsg',
                        'explmykey', 'explmykeyArgument', 'XMLComment', 'XMLParameter', 'XMLSpecial', 'XMLTag', 'XMLValue']:
                if key in theme and contrast(theme[key], theme[painted]) < 3:
                    problems.append(f'{name}: {key} on {painted}')
        opaque = theme.get('SourceAlpha', [0, 0, 0, 1])[3] >= 1
        for key in ['SyntaxIndex', 'XMLComment', 'XMLTag', 'XMLSpecial', 'XMLParameter', 'XMLValue'] + (['SyntaxCommand'] if opaque else []):
            if key in theme and contrast(theme[key], background) < 3:
                problems.append(f'{name}: {key} on the background')
        # Every color drawn as text is readable on its background (contrast at least 4.5).
        for key in ['EditorText', 'SyntaxCommand', 'SyntaxComment', 'SyntaxIndex', 'SyntaxMarker', 'SyntaxMarkerParen',
                    'SyntaxMarkerCurly', 'SyntaxMarkerSquare', 'FootnoteColor', 'explFunction', 'explIntenseFunction',
                    'explIntenseVariable', 'explVariable', 'explmsg', 'explmykey', 'explmykeyArgument',
                    'XMLComment', 'XMLParameter', 'XMLSpecial', 'XMLTag', 'XMLValue']:
            if key in theme and contrast(theme[key], background) < 4.5:
                problems.append(f'{name}: {key} on the background')
        for key, under in (('ConsoleText', 'ConsoleBackground'), ('LogText', 'LogBackground')):
            if key in theme and under in theme and contrast(theme[key], theme[under]) < 4.5:
                problems.append(f'{name}: {key} on {under}')
        comment = theme.get('SyntaxComment')
        if comment and difference(comment, text) < 20:
            problems.append(f'{name}: SyntaxComment too close to the text')
        if 'EditorHighlightBraces' in theme and contrast(theme['EditorHighlightBraces'], background) < 3:
            problems.append(f'{name}: EditorHighlightBraces on the background')
        if 'ImageForeground' in theme and theme['ImageForeground'][3] < 1:
            problems.append(f'{name}: ImageForeground is not opaque')
    return problems


def old_theme(name, base=BASE):
    result = subprocess.run(['git', 'show', f'{base}:Resources/TeXShop/Themes/{name}.plist'], cwd=ROOT, capture_output=True)
    return plistlib.loads(result.stdout) if result.returncode == 0 else None


def changed_colors(base=BASE, target=None):
    """Every color of a bundled theme that differs between base and target (now when None), keyed by (theme, key): (old, new)."""
    changes = {}
    for path in sorted(THEMES.glob('*.plist')):
        old = old_theme(path.stem, base)
        new = plistlib.loads(path.read_bytes()) if target is None else old_theme(path.stem, target)
        if old is None or new is None:
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
                    str(tmp / 'src' / SUPPORT), str(ROOT / 'Sources/App/TSLibraryRepair.m'), str(ROOT / 'Sources/Settings/TSThemeFileStore.m'), str(ROOT / 'Sources/App/globals.m'),
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
        if run(probe, folder, 0) != LAST:
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
        if run(probe, folder, LAST) != LAST or {p.name: p.read_bytes() for p in folder.iterdir()} != before:
            problems.append('a second run changes the themes')

        # Themes as 6.00 beta 1 left them, after update 1: every color changed since beta 1 is updated, the expl3
        # colors included, and nothing else.
        betas = {p.stem: old_theme(p.stem, UPDATES[2]) for p in sorted(THEMES.glob('*.plist'))}
        betas = {k: v for k, v in betas.items() if v is not None}
        since = changed_colors(UPDATES[2])
        folder = tmp / 'beta'
        folder.mkdir()
        for theme, colors in betas.items():
            (folder / f'{theme}.plist').write_bytes(plistlib.dumps(colors))
        if run(probe, folder, 1) != LAST:
            problems.append('the update after beta 1 is not reported as done')
        for theme, old in betas.items():
            now = plistlib.loads((folder / f'{theme}.plist').read_bytes())
            for key in set(old) | set(now):
                expected = since[(theme, key)][1] if (theme, key) in since else old.get(key)
                value = now.get(key)
                if isinstance(expected, list):
                    if not isinstance(value, list) or not close(value, expected) or value[3:] != old[key][3:]:
                        problems.append(f'beta 1 {theme} {key} is {value}, not {expected}')
                elif value != expected:
                    problems.append(f'beta 1 {theme} {key} changed')

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
        if run(probe, folder, 0, concurrent=tmp / 'theirs.plist') != LAST:
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
        if run(probe, folder, 0) != LAST or not close(plistlib.loads((folder / 'LiteTheme.plist').read_bytes())['EditorHighlightContent'], changes[('LiteTheme', 'EditorHighlightContent')][1]):
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
    """Each update holds every color that changed between its release and the next one (or now), with those values."""
    import re
    source = text[SUPPORT]
    rows = re.findall(r'\{(\d+), @"([^"]+)", @"([^"]+)", \{([^}]*)\}, \{([^}]*)\}\}', source)
    problems = []
    for update, base in UPDATES.items():
        table = {(theme, key): ([float(x) for x in old.split(',')], [float(x) for x in new.split(',')])
                 for n, theme, key, old, new in rows if int(n) == update}
        changes = changed_colors(base, UPDATES.get(update + 1))
        for (theme, key), (old, new) in changes.items():
            if (theme, key) not in table:
                problems.append(f'update {update}: {theme} {key} is not in the table')
            elif any(abs(a - b) > 1e-6 for a, b in zip(table[(theme, key)][0], old[:3])) or any(abs(a - b) > 1e-6 for a, b in zip(table[(theme, key)][1], new[:3])):
                problems.append(f'update {update}: {theme} {key} has other values in the table')
        for entry in table:
            if entry not in changes:
                problems.append(f'update {update}: {entry} is in the table but did not change')
    if any(int(n) not in UPDATES for n, *_ in rows):
        problems.append('the table has an update that the test does not know')
    return problems


def check(text):
    return readability_problems(bundled()) + source_problems(text) + table_problems(text) + update_problems(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    text = {path: (ROOT / path).read_text(encoding='latin1') for path in (SUPPORT, DELEGATE, DOCCOLOR)}
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
