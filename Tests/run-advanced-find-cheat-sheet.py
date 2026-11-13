#!/usr/bin/env python3
"""The regular expression cheat sheet of the Advanced Find panel (Tests/AdvancedFindCheatSheet.m) and the engine's
table of differences from OgreKit, in all 12 languages. Nothing is displayed; the defaults stay in memory and the
pasteboards are unique.

--image DIR writes the sheet's pages (find, replace in either syntax, differences from OgreKit), light and dark, in
English, Japanese and German (--image-all-languages: in all 12).
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
IMAGE_LANGUAGES = ['en', 'ja', 'de']

MUTATIONS = {
    'the pages are not hidden': ('TSAdvancedFindCheatSheet.m',
        '        self.pages[i].hidden = (NSInteger)i != index;', '        self.pages[i].hidden = NO;'),
    'the tabs do nothing': ('TSAdvancedFindCheatSheet.m',
        '    [self selectPage:sender.selectedSegment];\n', ''),
    'the sheet is not measured again when shown': ('TSAdvancedFindCheatSheet.m',
        '    [super viewWillAppear];\n    [self fitToContent];', '    [super viewWillAppear];'),
    'the replacement page ignores the syntax': ('TSAdvancedFindCheatSheet.m',
        '    BOOL ogreKit = self.replacementSyntax == TSRegexReplacementSyntaxOgreKit;', '    BOOL ogreKit = NO;'),
    'an open sheet does not follow the setting': ('TSAdvancedFindPanelController+CheatSheet.m',
        '    sheet.replacementSyntax = self.findController.settings.replacementSyntax;\n', ''),
    'the sheet cannot be dragged off': ('TSAdvancedFindPanelController+CheatSheet.m',
        '    return popover == self.cheatSheetPopover;', '    return NO;'),
    'the pages do not allow for the overhang of the descriptions': ('TSAdvancedFindCheatSheet.m',
        'constraintLessThanOrEqualToAnchor:self.pageArea.trailingAnchor constant:-2]', 'constraintLessThanOrEqualToAnchor:self.pageArea.trailingAnchor constant:0]'),
    'the differences page has its own text for \\h': ('TSAdvancedFindCheatSheet.m',
        '        [messages addObject:entry.message];', '        [messages addObject:[entry.term isEqualToString:@"\\\\h"] ? @"a hexadecimal digit" : entry.message];'),
    'the table does not mark (?~…)': ('TSRegexOnigmoIncompatibility.m',
        '            TSEntry(Absent, @"(?~…)", YES,', '            TSEntry(Absent, @"(?~…)", NO,'),
    'the options row spreads out after the ?': ('TSAdvancedFindPanelController.m',
        '    [regex setHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];\n', ''),
    'the ? is not next to Regular expression': ('TSAdvancedFindPanelController.m',
        '    NSStackView *regex = [NSStackView stackViewWithViews:@[self.regexBox, self.cheatSheetButton]];',
        '    NSStackView *regex = [NSStackView stackViewWithViews:@[self.cheatSheetButton, self.regexBox]];'),
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
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.AdvancedFindCheatSheet</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    probe = app / 'Contents/MacOS/probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                    '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'), '-framework', 'Cocoa',
                    str(root / 'Tests/AdvancedFindCheatSheet.m'), *map(str, sorted(sources.glob('*.m'))), '-o', str(probe)], check=True)
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
    parser.add_argument('--image-all-languages', action='store_true', help='images in all 12 languages, not only English, Japanese and German')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-cheat-sheet-') as tmp:
        tmp = Path(tmp)
        probe = build(tmp, copy_sources(tmp))
        for language in LANGUAGES:
            images = args.image if args.image and (args.image_all_languages or language in IMAGE_LANGUAGES) else None
            for mode in ['table', 'sheet']:
                result = run(probe, mode, language, images if mode == 'sheet' else None)
                print(result.stdout + result.stderr, end='')
                if result.returncode:
                    sys.exit(f'FAIL: the {mode} in {language}')
        if args.image:
            print(f'images in {args.image}')
        if args.mutations:
            for name, (file, old, new) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-cheat-sheet-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    sources = copy_sources(mtmp)
                    text = (sources / file).read_text(encoding='utf-8')
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    (sources / file).write_text(text.replace(old, new), encoding='utf-8')
                    mprobe = build(mtmp, sources)
                    # English and German: German has the longest descriptions.
                    results = [run(mprobe, mode, language) for mode in ['table', 'sheet'] for language in ['en', 'de']]
                    if all(r.returncode == 0 for r in results):
                        sys.exit(f'FAIL: mutation {name!r} was not detected')
                    print(f'PASS: detected mutation {name!r}')
    print('PASS: Advanced Find cheat sheet')


if __name__ == '__main__':
    main()
