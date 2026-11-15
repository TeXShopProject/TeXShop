#!/usr/bin/env python3
"""Character Info (Sources/Panels/TSGlyphPopoverController.m) in the twelve languages:
the name and table of one character from ICU, the code points of a character made of
several, the counts of several characters as the status bar counts them, their code points, readable colors in light and
dark appearance, whole text, and the size of the popover (Tests/GlyphPopover.m).
Nothing is shown on screen; it runs with a temporary HOME.

Block names in other languages are read from the Character Viewer of macOS (UnicodeBlocks_Title.loctable).
The names shown for every block of ICU, in every language, are checked against the table as this script reads
it, for the table of this Mac, for copies given with --tables, and for a missing, broken or incomplete table,
which give the English names.

  --images DIR      also write the popover of the English and Japanese cases, light and dark, as PNG files
  --tables FILE...  copies of UnicodeBlocks_Title.loctable of other versions of macOS to check as well
  --mutation NAME   check that the test fails with a known mistake in the product code"""
from pathlib import Path
import argparse
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
controller = source_file(root, 'TSGlyphPopoverController.m')

# Mistakes the test must catch: name, (old, new) in the controller.
MUTATIONS = {
    # The color the details had: a disabled control's text.
    'disabled-color': ('Label(category, font, NSColor.labelColor', 'Label(category, font, NSColor.disabledControlTextColor'),
    # The popover keeps a fixed width and cuts long names off.
    'no-wrap': ('BOOL wraps = (width > maxWidth);', 'BOOL wraps = NO;'),
    # The surrogate pair is no longer shown beside the code point.
    'no-surrogates': ('codePoint = [NSString stringWithFormat:@"%@ %@", codePoint, surrogates];', ';'),
    # A variation sequence is taken for a character of several code points.
    'no-variant': ('NSString *variant = (codePoints.count == 2) ? VariantDescription(codePoints[1].unsignedIntValue) : nil;', 'NSString *variant = nil;'),
    # The table stretches to the width of the name and leaves its leading edge.
    'table-stretch': ('    [grid setContentHuggingPriority:NSLayoutPriorityDefaultHigh + 1 forOrientation:NSLayoutConstraintOrientationHorizontal];\n', ''),
    # The code points of several characters break into lines inside a surrogate pair.
    'break-anywhere': ('    if (separator.location != NSNotFound && NSMaxRange(separator) > range.location)', '    if (NO)'),
    # Closing one code point closes them all.
    'close-all': ('        [self.openCodePoints removeObject:prefix];', '        [self.openCodePoints removeAllObjects];'),
    # The words counted by the spelling checker again, which finds none in "あああ".
    'spell-words': ('        words += TSStatusBarWordCount(text, range, nil);',
                    '        words += (NSUInteger)MAX(0, [NSSpellChecker.sharedSpellChecker countWordsInString:[text substringWithRange:range] language:nil]);'),
    # Lines counted by line feeds in the selection, as before.
    'newline-lines': ('    counts.selectedLines = TSStatusBarSelectedLineCount(text, ranges);',
                      '    counts.selectedLines = [selected componentsSeparatedByString:@"\\n"].count;'),
    # Only the first of several selected ranges is counted and shown.
    'first-range-only': ('    for (NSValue *value in ranges) {\n        NSRange range = value.rangeValue;\n        if (range.location > text.length',
                         '    for (NSValue *value in [ranges subarrayWithRange:NSMakeRange(0, MIN(1u, ranges.count))]) {\n        NSRange range = value.rangeValue;\n        if (range.location > text.length'),
    # The abbreviations of the Character Viewer's table are not spelled out: CJK Unified Ideographs Ext. B stays in English.
    'no-abbreviations': ('TSUnicodeBlockNames.m', '@[@"\\\\bext\\\\.", @"extension"], ', ''),
    # Portuguese of Portugal takes the Brazilian names.
    'portugal-as-brazil': ('TSUnicodeBlockNames.m', '@"pt-PT": @"pt_PT", ', '@"pt-PT": @"pt_BR", '),
    # The table is read again for every name.
    'read-every-time': ('TSUnicodeBlockNames.m', '    if (!CachedTranslations)\n', ''),
    # A click on a disclosure triangle does not open the code point.
    'no-open': ('        [self.openCodePoints addObject:prefix];', '        ;'),
}

parser = argparse.ArgumentParser()
parser.add_argument('--images')
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--tables', nargs='*', default=[])
args = parser.parse_args()

languages = [p.stem for p in sorted(interfaces.glob('*.lproj')) if (p / 'Localizable.strings').exists()]
assert len(languages) == 12, languages
SYSTEM_TABLE = Path('/System/Library/Input Methods/CharacterPalette.app/Contents/Resources/UnicodeBlocks_Title.loctable')
# The language of the table for each folder of TeXShop: pt is Brazilian Portuguese.
TABLE_LANGUAGE = {'en': 'en', 'pt': 'pt_BR', 'pt-PT': 'pt_PT'}


def key(name):
    """The table's names abbreviate a few words ("CJK Unified Ideographs Ext. J", "Arabic Math Alphabetic Symbols")."""
    name = name.lower()
    for short, full in ((r'\bext\.', 'extension'), (r'\bsupp\.', 'supplement'), (r'\bdesc\.', 'description'), (r'\bmath\b', 'mathematical')):
        name = re.sub(short, full, name)
    return re.sub(r'[^a-z0-9]', '', name)


def in_table(table, language, name):
    try:
        names = plistlib.loads(Path(table).read_bytes()).get(TABLE_LANGUAGE.get(language, language), {})
    except Exception:
        return False
    return key(name) in {key(k) for k in names}


def expected_names(table, language, english):
    """What Character Info should show for the English block names, read from a table of the Character Viewer."""
    try:
        data = plistlib.loads(Path(table).read_bytes())
    except Exception:
        data = None
    names = data.get(TABLE_LANGUAGE.get(language, language)) if isinstance(data, dict) else None
    names = {key(k): v for k, v in names.items() if isinstance(k, str) and isinstance(v, str) and v} if isinstance(names, dict) else {}
    return {name: names.get(key(name), name) for name in english}

with tempfile.TemporaryDirectory(prefix='texshop-glyph-popover-') as tmp:
    tmp = Path(tmp)
    sources = {'TSGlyphPopoverController.m': controller.read_text(), 'TSUnicodeBlockNames.m': source_file(root, 'TSUnicodeBlockNames.m').read_text()}
    if args.mutation:
        mutation = MUTATIONS[args.mutation]
        name, old, new = mutation if len(mutation) == 3 else ('TSGlyphPopoverController.m', *mutation)
        assert sources[name].count(old) == 1, args.mutation
        sources[name] = sources[name].replace(old, new)
    for name, source in sources.items():
        (tmp / name).write_text(source)
    binary = tmp / 'GlyphPopover'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-licucore',
                    '-I', str(root / 'Tests'), *include_args(root), str(root / 'Tests/GlyphPopover.m'), str(tmp / 'TSGlyphPopoverController.m'),
                    str(tmp / 'TSUnicodeBlockNames.m'), str(source_file(root, 'TSStatusBarCounting.m')), str(source_file(root, 'NSString-Extras.m')), '-o', str(binary)], check=True)
    home = tmp / 'home'
    (home / 'Library/Preferences').mkdir(parents=True)
    env = {**os.environ, 'HOME': str(home), 'CFFIXED_USER_HOME': str(home)}

    # The block names, for every block of ICU, every language and every table.
    broken = tmp / 'broken'
    broken.mkdir()
    (broken / 'garbage.loctable').write_bytes(b'\x00\x01 not a property list')
    (broken / 'array.loctable').write_bytes(plistlib.dumps(['en', 'ja'], fmt=plistlib.FMT_BINARY))
    (broken / 'values.loctable').write_bytes(plistlib.dumps({'ja': {'Basic Latin': 3, 'Hiragana': ''}, 'de': ['Basic Latin'], 'en': 'x'}, fmt=plistlib.FMT_BINARY))
    tables = ([SYSTEM_TABLE] if SYSTEM_TABLE.exists() else []) + [Path(p) for p in args.tables]
    others = [broken / 'garbage.loctable', broken / 'array.loctable', broken / 'values.loctable', tmp / 'missing.loctable']
    block_failures = 0

    def dump(table, language):
        out = subprocess.run([str(binary), '--dump-blocks', str(table), language], capture_output=True, text=True, timeout=120, env=env)
        if out.returncode:
            return None
        return json.loads(out.stdout)

    english = dump(tmp / 'missing.loctable', 'en') or {}
    if len(english) < 300 or any(k != v for k, v in english.items()):
        print(f'FAIL: without a table every block is shown by its English name ({len(english)} blocks)')
        block_failures += 1
    for table in tables + others:
        for language in languages:
            shown = dump(table, language)
            want = expected_names(table, language, english)
            if shown != want:
                bad = [n for n in want if (shown or {}).get(n) != want[n]]
                print(f'FAIL: {table.name} {language}: {len(bad)} block names differ, such as {bad[:3]}' if shown is not None else f'FAIL: {table.name} {language}: crashed')
                block_failures += 1
        if table in tables:
            for language in ('ja', 'de', 'pt', 'pt-PT', 'ro', 'zh_CN'):
                want = expected_names(table, language, english)
                print(f'blocks: {table} {language}: {sum(want[n] != n for n in want)} of {len(want)} blocks named otherwise than in English, '
                      f'{sum(in_table(table, language, n) for n in want)} found in the table')
    # The table is read once: names are still found after the file is gone.
    if SYSTEM_TABLE.exists():
        copy = tmp / 'once.loctable'
        copy.write_bytes(SYSTEM_TABLE.read_bytes())
        out = subprocess.run([str(binary), '--read-once', str(copy)], capture_output=True, text=True, timeout=120, env=env)
        if out.returncode or out.stdout.strip() != 'read once':
            print(f'FAIL: the table is read once: {out.stdout.strip()} {out.stderr[-300:]}')
            block_failures += 1
    # The check after an update of macOS (Scripts/check-unicode-block-titles.py): 0 for a good table, 1 for a table
    # that is missing, broken, without a language of TeXShop, or with names of another kind or none in a language.
    if SYSTEM_TABLE.exists():
        good = plistlib.loads(SYSTEM_TABLE.read_bytes())
        def variant(name, change):
            table = json.loads(json.dumps(good))
            change(table)
            (broken / name).write_bytes(plistlib.dumps(table, fmt=plistlib.FMT_BINARY))
            return broken / name
        checker_cases = [(SYSTEM_TABLE, 0), (tmp / 'missing.loctable', 1), (broken / 'garbage.loctable', 1), (broken / 'array.loctable', 1),
                         (broken / 'values.loctable', 1),
                         (variant('bad-value.loctable', lambda t: t.update(ja={k: {'new_format': v} for k, v in t['ja'].items()})), 1),
                         (variant('empty-japanese.loctable', lambda t: t.update(ja={})), 1),
                         (variant('no-romanian.loctable', lambda t: t.pop('ro')), 1),
                         (variant('one-empty-name.loctable', lambda t: t['de'].update({'Basic Latin': ' '})), 1),
                         (variant('unknown-name.loctable', lambda t: t['ja'].update({'Klingon Ext. Z': 'クリンゴン'})), 1)]
        for table, status in checker_cases:
            out = subprocess.run([sys.executable, str(root / 'Scripts/check-unicode-block-titles.py'), str(table)], capture_output=True, text=True, timeout=300)
            if out.returncode != status:
                print(f'FAIL: check-unicode-block-titles.py {table.name} ends with {out.returncode}, not {status}: {out.stdout[-400:]}')
                block_failures += 1
    if block_failures:
        print(f'FAIL: {block_failures} block name checks')

    # The popover in each language, with the names this Mac's table gives.
    entries = []
    for language in languages:
        names = tmp / f'blocks-{language}.json'
        names.write_text(json.dumps(expected_names(SYSTEM_TABLE, language, english), ensure_ascii=False))
        entries.append(f'{language}|{interfaces / (language + ".lproj") / "Localizable.strings"}|{names}')
    extra = []
    if args.images:
        Path(args.images).mkdir(parents=True, exist_ok=True)
        extra = ['--images', str(Path(args.images).resolve())]
    result = subprocess.run([str(binary), *extra, *entries], capture_output=True, text=True, timeout=900, env=env)
    if block_failures and not result.returncode:
        result.returncode = 1
    print(result.stdout[-20000:], end='')
    if result.returncode and not result.stdout.strip():
        print(result.stderr[-3000:], file=sys.stderr)
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: the mutation {args.mutation} was not detected')
        print(f'PASS: the mutation {args.mutation} is detected')
        sys.exit(0)
    sys.exit(result.returncode)
