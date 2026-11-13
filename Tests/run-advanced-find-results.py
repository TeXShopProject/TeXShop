#!/usr/bin/env python3
"""The Find All list of the Advanced Find panel, stage 4 (Tests/AdvancedFindResults.m): the matches with their lines,
text and group colors, OgreKit's six edit cases and stale rows, typing in TeXShop's text, live update and its scope,
an 8 MB document, the list in the panel (growing, closing, jumping, quitting, closing the document), and the panel
with its list in all 12 languages. Nothing is displayed; the defaults stay in memory and the pasteboards are unique.

--image DIR writes the panel with its list, light and dark, in English and Japanese (--image-all-languages: in all 12).
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
NEW_FILES = ['TSAdvancedFindResults.h', 'TSAdvancedFindResults.m', 'TSAdvancedFindResultsView.h', 'TSAdvancedFindResultsView.m',
             'TSAdvancedFindPanelController+Results.m']
KEYS = ['FindAll', 'FindAllTip', 'Results.Close', 'Results.Count', 'Results.FindString', 'Results.Line', 'Results.LiveUpdate',
        'Results.CountStale', 'Results.Text']

MUTATIONS = {
    'the list does not follow edits': ('TSAdvancedFindResults.m',
        '    [self followEditFrom:edited.location to:(NSUInteger)((NSInteger)b2 - storage.changeInLength) newEnd:b2];\n', ''),
    'edits are taken after processing (the widened range)': ('TSAdvancedFindResults.m',
        'name:NSTextStorageWillProcessEditingNotification object:storage];', 'name:NSTextStorageDidProcessEditingNotification object:storage];'),
    'an edit inside a match leaves it fresh': ('TSAdvancedFindResults.m', '            item.stale = YES;\n', ''),
    'stale rows keep their colors': ('TSAdvancedFindResults.m', '    if (item.isStale) {\n        // An edit touched', '    if (NO) {\n        // An edit touched'),
    'groups are not colored': ('TSAdvancedFindResults.m', 'for (NSUInteger k = 1; k < item.foundRanges.count && groupColors.count > 0; k++)',
                               'for (NSUInteger k = 1; k < 1 && groupColors.count > 0; k++)'),
    'more text before the match': ('TSAdvancedFindResults.m', 'TSBeforeLength = 30,', 'TSBeforeLength = 40,'),
    'line numbers from zero': ('TSAdvancedFindResults.m', '    return low;\n}', '    return low - 1;\n}'),
    'CRLF counts as two lines': ('TSAdvancedFindResults.m', '[string getLineStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(index, 0)];',
                                 '[string getLineStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(index, 0)]; if (end > index + 1 && [string characterAtIndex:end - 1] == 10 && [string characterAtIndex:end - 2] == 13) end--;'),
    'the scope loses an edit at its start': ('TSAdvancedFindResults.m', 'if (!TSAdjustRange(&range, a, b, b2) && c <= a && b <= d)', 'if (NO && !TSAdjustRange(&range, a, b, b2))'),
    'live update searches without an edit': ('TSAdvancedFindResults.m', '    if (updatesLive && self.editedSinceSearch)', '    if (updatesLive)'),
    'an overtaken search is kept': ('TSAdvancedFindResults.m', '|| results.editCount != edits)', ')'),
    'Find All is not allowed in a read-only text view': ('TSAdvancedFindController.m',
        '        case TSAdvancedFindActionHighlight:\n        case TSAdvancedFindActionFindAll:\n', '        case TSAdvancedFindActionHighlight:\n'),
    'Find All highlights': ('TSAdvancedFindController.m', '    if (self.findAllHandler)\n        self.findAllHandler(results, textView);',
                            '    [TSAdvancedFindHighlights highlightsForTextStorage:storage].ranges = results.currentRanges;\n    if (self.findAllHandler)\n        self.findAllHandler(results, textView);'),
    'Find All lists nothing found': ('TSAdvancedFindController.m', '    if (items.count == 0) {\n        self.beepHandler();', '    if (NO) {\n        self.beepHandler();'),
    'Find All closes the panel when it is done': ('TSAdvancedFindPanelController+Actions.m', ' && action != TSAdvancedFindActionFindAll)', ')'),
    'the Find All button greys with Highlight All': ('TSAdvancedFindPanelController+Actions.m',
        'actions[] = {TSAdvancedFindActionFindAll,', 'actions[] = {TSAdvancedFindActionReplaceAll,'),
    'the fields take the list\'s room': ('TSAdvancedFindPanelController+Results.m', '        self.fieldHeightWhileListing.active = YES;\n', ''),
    'quitting keeps the list': ('TSAdvancedFindPanelController+Results.m', '    if (self.resultsView.hidden)\n        return;\n    [self.resultsView clear];',
                                '    return;\n    [self.resultsView clear];'),
    'closing any window closes the list': ('TSAdvancedFindResultsView.m', 'if (!closing || closing != (self.textView.window ?: self.documentWindow))', 'if (!closing)'),
    'closing the document leaves the list': ('TSAdvancedFindResultsView.m', 'if (!closing || closing != (self.textView.window ?: self.documentWindow))', 'if (YES)'),
    'a click on the selected row does not jump': ('TSAdvancedFindResultsView.m', '    table.action = @selector(rowClicked:);\n', ''),
    'Live Update is not kept': ('TSAdvancedFindResultsView.m', '    self.settings.updatesResultsLive = on;\n', ''),
    'the stale rows are not counted': ('TSAdvancedFindResultsView.m', '    NSString *message = stale > 0\n', '    NSString *message = NO\n'),
    'the count is as wide as its text': ('TSAdvancedFindResultsView.m', '        [self.liveUpdateBox.leadingAnchor constraintEqualToAnchor:self.countField.trailingAnchor constant:12],',
                                         '        [self.liveUpdateBox.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.countField.trailingAnchor constant:12],'),
    'the count line does not wrap': ('TSAdvancedFindResultsView.m', '    self.countField.maximumNumberOfLines = 2;\n', '    self.countField.maximumNumberOfLines = 1;\n'),
    'a row jumps without a text view': ('TSAdvancedFindResultsView.m', '    if (NSMaxRange(item.currentRange) > textView.string.length) {', '    if (NO) {'),
    'Remove Highlights is left out': ('TSAdvancedFindPanelController.m',
        '    [allMenu addItem:NSMenuItem.separatorItem];\n    [allMenu addItemWithTitle:TSLocalized(@"AdvancedFind.Unhighlight"', '    [allMenu addItemWithTitle:TSLocalized(@"AdvancedFind.Unhighlight"'),
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
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.AdvancedFindResults</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    globals_m = source_file(root, 'globals.m').read_text(encoding='latin1')
    keys = dict(re.findall(r'^NSString \*(\w+Key)\s*=\s*(@"[^"]*");', globals_m, re.M))
    marker_keys = '\n'.join(f'NSString *{k} = {keys[k]};' for k in [
        'showSpaceCharacterKey', 'showFullwidthSpaceCharacterKey', 'showTabCharacterKey', 'showNewLineCharacterKey',
        'SpaceCharacterKindKey', 'FullwidthSpaceCharacterKindKey', 'TabCharacterKindKey', 'NewLineCharacterKindKey'])
    (tmp / 'keys.m').write_text('#import <Cocoa/Cocoa.h>\n' + marker_keys + '\nNSColor *InvisibleColor;\nBOOL atLeastMonterey = YES, atLeastSonoma = YES;\n')
    probe = app / 'Contents/MacOS/probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                    '-Wno-deprecated-declarations', '-Wno-deprecated-implementations', '-Wnullability-completeness', '-Werror=nullability-completeness',
                    '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'), '-framework', 'Cocoa',
                    str(root / 'Tests/AdvancedFindResults.m'), str(tmp / 'keys.m'), *map(str, sorted(sources.glob('*.m'))),
                    '-o', str(probe)], check=True)
    return probe


def run(probe, mode, language='en', images=None):
    command = [str(probe), mode, *([str(images)] if images else []), '-AppleLanguages', f'({language})']
    return subprocess.run(command, capture_output=True, text=True, timeout=300)


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for path in [*(root / 'Sources/Find').glob('*.[mh]'), source_file(root, 'TSLayoutManager.m'), source_file(root, 'TSLayoutManager.h')]:
        shutil.copy(path, sources / path.name)
    return sources


def check_project():
    project = (root / 'TeXShop.xcodeproj/project.pbxproj').read_text()
    for name in NEW_FILES:
        quoted = f'"{name}"' if '+' in name else name
        if f'path = {quoted};' not in project or (name.endswith('.m') and f'/* {name} in Sources */,' not in project):
            sys.exit(f'FAIL: {name} is not in the application')
    for language in LANGUAGES:
        table = (root / 'Resources/Interfaces' / f'{language}.lproj/AdvancedFind.strings').read_text()
        missing = [k for k in KEYS if f'"AdvancedFind.{k}" = ' not in table]
        if missing:
            sys.exit(f'FAIL: {language} AdvancedFind.strings lacks {missing}')
    print('PASS: the list\'s files and its strings in all 12 languages are in the application')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--image-all-languages', action='store_true', help='images in all 12 languages, not only English and Japanese')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    check_project()
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-results-') as tmp:
        tmp = Path(tmp)
        probe = build(tmp, copy_sources(tmp))
        for mode in ['behavior', 'large']:
            result = run(probe, mode)
            print(result.stdout + result.stderr, end='')
            if result.returncode:
                sys.exit(f'FAIL: {mode}')
        for language in LANGUAGES:
            images = args.image if args.image and (args.image_all_languages or language in ('en', 'ja')) else None
            result = run(probe, 'layout', language, images)
            print(result.stdout + result.stderr, end='')
            if result.returncode:
                sys.exit(f'FAIL: the list in {language}')
        if args.image:
            print(f'images in {args.image}')
        if args.mutations:
            survivors = []
            for name, (file, old, new) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-results-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    sources = copy_sources(mtmp)
                    text = (sources / file).read_text()
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    (sources / file).write_text(text.replace(old, new))
                    mprobe = build(mtmp, sources)
                    results = [run(mprobe, 'behavior'), run(mprobe, 'large'), run(mprobe, 'layout'), run(mprobe, 'layout', 'de'), run(mprobe, 'layout', 'ja')]
                    if all(r.returncode == 0 for r in results):
                        print(f'FAIL: mutation {name!r} was not detected')
                        survivors.append(name)
                    else:
                        print(f'PASS: detected mutation {name!r}')
            if survivors:
                sys.exit(f'FAIL: {len(survivors)} of {len(MUTATIONS)} mutations were not detected')
            print(f'PASS: all {len(MUTATIONS)} mutations detected')
    print('PASS: Advanced Find panel stage 4, the Find All list')


if __name__ == '__main__':
    main()
