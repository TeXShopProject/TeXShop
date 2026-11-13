#!/usr/bin/env python3
"""Multiple replacement (Tests/MultipleReplace.m): the library of sets in its folder, applying a set as one undo,
the rule table, the window, the Find menu's items, and the window in all 12 languages. Nothing is displayed; the
defaults stay in memory, the pasteboards are unique and the sets go into temporary folders.

--image DIR writes the window, an empty window and a set's options, light and dark, in English and Japanese
(--image-all-languages: in all 12).
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']

MUTATIONS = {
    'rules run on the original text': ('TSRegexMultipleReplace.m', '            current = next;', '            (void)next;'),
    'the whole text is replaced': ('TSAdvancedFindController+MultipleReplace.m',
        '    TSChangedRange(old, result.string, &oldRange, &newRange);\n',
        '    oldRange = NSMakeRange(0, old.length); newRange = NSMakeRange(0, result.string.length);\n'),
    'a replacement is not registered for undo': ('TSAdvancedFindController+MultipleReplace.m',
        '    if (![textView shouldChangeTextInRange:oldRange replacementString:replacement])\n        return;\n', ''),
    'a read-only text view is replaced': ('TSAdvancedFindController+MultipleReplace.m',
        '    if (![self validateAction:TSAdvancedFindActionReplaceAll forTextView:textView]) {', '    if (NO) {'),
    'a rename overwrites another set': ('TSMultipleReplaceLibrary.m', '    if (!sameFile && [NSFileManager', '    if (NO && [NSFileManager'),
    'bad names are saved': ('TSMultipleReplaceLibrary.m', '    if (![TSMultipleReplaceLibrary isValidName:name]) {\n        if (error)\n            *error = TSLibraryError(@"MultipleReplace.BadName"',
        '    if (NO) {\n        if (error)\n            *error = TSLibraryError(@"MultipleReplace.BadName"'),
    'other files are listed as sets': ('TSMultipleReplaceLibrary.m', '        if ([file.pathExtension isEqualToString:TSMultipleReplaceLibrary.fileExtension])\n', ''),
    'a dropped row is not moved back by the rows above it': ('TSMultipleReplaceRuleTable.m',
        '(NSUInteger)row - [indexes countOfIndexesInRange:NSMakeRange(0, (NSUInteger)row)];', 'MIN((NSUInteger)row, rules.count - indexes.count);'),
    'problems are not marked': ('TSMultipleReplaceRuleTable.m', '    NSError *problem = self.problems[@(row)];', '    NSError *problem = nil;'),
    'the menu is added twice': ('TSMultipleReplaceMenu.m', '        if ([item.identifier isEqualToString:TSShowMultipleReplaceIdentifier])\n            return;\n', ''),
    'the sets menu ignores a read-only target': ('TSMultipleReplaceMenu.m',
        '        return target && [self.findController validateAction:TSAdvancedFindActionReplaceAll forTextView:(NSTextView *_Nonnull)target];',
        '        return target != nil;'),
    'Replace All ignores a read-only target': ('TSMultipleReplaceWindowController.m',
        '        BOOL enabled = target ? [controller validateAction:actions[index] forTextView:target] : YES;', '        BOOL enabled = YES;'),
    'the set options take the panel\'s rule': ('TSMultipleReplaceWindowController.m',
        'initWithStyle:TSAdvancedFindOptionsFormStyleSet', 'initWithStyle:TSAdvancedFindOptionsFormStylePanel'),
}


def build(tmp, sources):
    """A small application bundle, so the strings tables are found as in TeXShop.app."""
    app = tmp / 'Probe.app'
    resources = app / 'Contents/Resources'
    (app / 'Contents/MacOS').mkdir(parents=True)
    for language in LANGUAGES:
        (resources / f'{language}.lproj').mkdir(parents=True)
        for table in ['AdvancedFind.strings', 'AdvancedFindEngine.strings']:
            shutil.copy(root / 'Resources/Interfaces' / f'{language}.lproj' / table, resources / f'{language}.lproj' / table)
    localizations = ''.join(f'<string>{l}</string>' for l in LANGUAGES)
    (app / 'Contents/Info.plist').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.MultipleReplace</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    probe = app / 'Contents/MacOS/probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                    '-Wno-deprecated-declarations', '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'),
                    '-framework', 'Cocoa', str(root / 'Tests/MultipleReplace.m'), *map(str, sorted(sources.glob('*.m'))),
                    '-o', str(probe)], check=True)
    return probe


def run(probe, mode, language='en', images=None):
    command = [str(probe), mode, *([str(images)] if images else []), '-AppleLanguages', f'({language})']
    return subprocess.run(command, capture_output=True, text=True, timeout=120)


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for path in (root / 'Sources/Find').glob('*.[mh]'):
        shutil.copy(path, sources / path.name)
    return sources


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--image-all-languages', action='store_true')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='texshop-multiple-replace-') as tmp:
        tmp = Path(tmp)
        probe = build(tmp, copy_sources(tmp))
        result = run(probe, 'behavior')
        print(result.stdout + result.stderr, end='')
        if result.returncode:
            sys.exit('FAIL: multiple replacement')
        for language in LANGUAGES:
            images = args.image if args.image and (args.image_all_languages or language in ('en', 'ja')) else None
            result = run(probe, 'layout', language, images)
            print(result.stdout + result.stderr, end='')
            if result.returncode:
                sys.exit(f'FAIL: the window in {language}')
        if args.image:
            print(f'images in {args.image}')
        if args.mutations:
            for name, (file, old, new) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-multiple-replace-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    sources = copy_sources(mtmp)
                    text = (sources / file).read_text()
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    (sources / file).write_text(text.replace(old, new))
                    mprobe = build(mtmp, sources)
                    results = [run(mprobe, 'behavior'), run(mprobe, 'layout')]
                    if all(r.returncode == 0 for r in results):
                        sys.exit(f'FAIL: mutation {name!r} was not detected')
                    print(f'PASS: detected mutation {name!r}')
    print('PASS: multiple replacement')


if __name__ == '__main__':
    main()
