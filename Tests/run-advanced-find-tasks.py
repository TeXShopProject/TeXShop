#!/usr/bin/env python3
"""The long actions of the Advanced Find panel (Tests/AdvancedFindTasks.m): Replace All, Find All and Multiple Replace in
the background on a 10 MB document, the text views locked and unlocked, Cancel within a second, the progress and its
messages, a text changed meanwhile, Find All in a read-only text view receiving output, the cache of matches (typing,
undo, another document, colors, options, line ending), the panel's and the multiple replacement window's buttons, and
the progress sheet in all 12 languages. Nothing is displayed; the defaults stay in memory and the pasteboards are unique.

--image DIR writes the progress sheet, light and dark, in English and Japanese (--image-all-languages: in all 12).
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file, advanced_find_syntax_sources

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
NEW_FILES = ['TSAdvancedFindTask.h', 'TSAdvancedFindTask.m', 'TSAdvancedFindProgressSheet.h', 'TSAdvancedFindProgressSheet.m',
             'TSAdvancedFindMatchCache.h', 'TSAdvancedFindMatchCache.m', 'TSAdvancedFindController+Tasks.m', 'TSAdvancedFindController+Private.h']
KEYS = ['AdvancedFind.Cancel', 'AdvancedFind.Cancelling', 'AdvancedFind.Cancelled', 'AdvancedFind.TextChanged', 'AdvancedFind.Searching',
        'AdvancedFind.SearchingCount', 'MultipleReplace.RuleProgress']

MUTATIONS = {
    'the views are not locked': ('TSAdvancedFindTask.m', '            if (view.isEditable) {\n                view.editable = NO;', '            if (NO) {\n                view.editable = NO;'),
    'the views are not unlocked': ('TSAdvancedFindTask.m', '        view.editable = YES;\n', ''),
    'Cancel is not passed to the engine': ('TSAdvancedFindTask.m', '    return ^BOOL { return weakSelf.isCancelled; };', '    return ^BOOL { return NO; };'),
    'a cancelled result is applied': ('TSAdvancedFindTask.m', 'completion(self.isCancelled ? nil : result, self.isCancelled);', 'completion(result, NO);'),
    'edits meanwhile are not recorded': ('TSAdvancedFindTask.m', '    [self.edits addObject:', '    if (NO) [self.edits addObject:'),
    'a text changed meanwhile is replaced': ('TSAdvancedFindController.m', '} else if (!followsEdits && storage && [TSAdvancedFindMatchCache cacheForTextStorage:storage].version != version) {',
                                             '} else if (NO) {'),
    'Find All throws away a list found while output came in': ('TSAdvancedFindController.m',
        '    [self runTaskNamed:title inTextView:textView work:work followsEdits:YES completion:completion];', '    [self runTaskNamed:title inTextView:textView work:work followsEdits:NO completion:completion];'),
    'the list does not follow the changes made meanwhile': ('TSAdvancedFindController+Tasks.m', '        [results followEdits:edits];\n', ''),
    'other actions run during a task': ('TSAdvancedFindController.m', '    if (self.runningTask) // one task at a time', '    if (NO) // one task at a time'),
    'the find field searches during a task': ('TSAdvancedFindController.m', 'if (self.settings.findString.length == 0 || self.runningTask)', 'if (self.settings.findString.length == 0)'),
    'the panel\'s buttons do not hear of the task': ('TSAdvancedFindPanelController.m',
        '    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:TSAdvancedFindTaskDidChangeNotification object:findController];\n', ''),
    'the window\'s buttons ignore the task': ('TSMultipleReplaceWindowController.m',
        '    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:TSAdvancedFindTaskDidChangeNotification object:findController];\n', ''),
    'Highlight of a set runs during a task': ('TSAdvancedFindController+MultipleReplace.m',
        '    if (![self validateAction:TSAdvancedFindActionHighlight forTextView:textView]) { // another task runs', '    if (NO) { // another task runs'),
    'Replace All shows no progress': ('TSAdvancedFindController+Tasks.m', '            task.progress = fraction;\n            task.message = [NSString localizedStringWithFormat:format, (unsigned long)count];\n        }];\n    } completion:^(TSRegexReplaceAllResult',
                                      '        }];\n    } completion:^(TSRegexReplaceAllResult'),
    'the bar fills for each rule': ('TSAdvancedFindController+MultipleReplace.m', 'task.progress = ruleCount > 0 ? MIN(1.0, (ruleIndex + fraction) / ruleCount) : 1.0;', 'task.progress = fraction;'),
    'the cache is kept after an edit': ('TSAdvancedFindMatchCache.m', '    self.version++;\n    [self.keys removeAllObjects];\n    [self.entries removeAllObjects];\n', '    self.version++;\n'),
    'the cache is cleared by colors': ('TSAdvancedFindMatchCache.m', '    if (!(storage.editedMask & NSTextStorageEditedCharacters))\n        return; // a color', '    if (NO)\n        return; // a color'),
    'the cache ignores the options': ('TSAdvancedFindController.m', '@"%lu\\x1f%@\\x1f%@", (unsigned long)find.pattern.options,', '@"%lu\\x1f%@\\x1f%@", (unsigned long)0,'),
    'the cache ignores the line ending': ('TSAdvancedFindController.m', 'find.lineEnding ?: @"", find.pattern.findString];', '@"", find.pattern.findString];'),
    'no cache': ('TSAdvancedFindController.m', '    NSArray<NSValue *> *matches = [cache matchesForKey:key];\n', '    NSArray<NSValue *> *matches = nil; (void)cache;\n'),
    'Escape does not cancel': ('TSAdvancedFindProgressSheet.m', '    _cancelButton.keyEquivalent = @"\\e";\n', ''),
    'Cancel is left of the bar': ('TSAdvancedFindProgressSheet.m', '    NSStackView *bar = [NSStackView stackViewWithViews:@[_progressBar, _cancelButton]];',
                                  '    NSStackView *bar = [NSStackView stackViewWithViews:@[_cancelButton, _progressBar]];'),
    'no sheet is called for': ('TSAdvancedFindTask.m', '        task.sheetWasDue = YES;\n', ''),
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
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.AdvancedFindTasks</string>
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
                    str(root / 'Tests/AdvancedFindTasks.m'), str(tmp / 'keys.m'), *map(str, sorted(sources.glob('*.m'))), *map(str, advanced_find_syntax_sources(root)),
                    '-o', str(probe)], check=True)
    return probe


def run(probe, mode, language='en', images=None):
    command = [str(probe), mode, *([str(images)] if images else []), '-AppleLanguages', f'({language})']
    return subprocess.run(command, capture_output=True, text=True, timeout=900)


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
        missing = [k for k in KEYS if f'"{k}" = ' not in table]
        if missing:
            sys.exit(f'FAIL: {language} AdvancedFind.strings lacks {missing}')
    print('PASS: the files of the tasks and their strings in all 12 languages are in the application')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--image-all-languages', action='store_true', help='images in all 12 languages, not only English and Japanese')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    check_project()
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-tasks-') as tmp:
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
                sys.exit(f'FAIL: the sheet in {language}')
        if args.image:
            print(f'images in {args.image}')
        if args.mutations:
            survivors = []
            for name, (file, old, new) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-tasks-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    sources = copy_sources(mtmp)
                    text = (sources / file).read_text()
                    if text.count(old) != 1:
                        sys.exit(f'FAIL: mutation {name!r} does not apply')
                    (sources / file).write_text(text.replace(old, new))
                    mprobe = build(mtmp, sources)
                    results = [run(mprobe, 'behavior'), run(mprobe, 'large'), run(mprobe, 'layout')]
                    if all(r.returncode == 0 for r in results):
                        print(f'FAIL: mutation {name!r} was not detected')
                        survivors.append(name)
                    else:
                        print(f'PASS: detected mutation {name!r}')
            if survivors:
                sys.exit(f'FAIL: {len(survivors)} of {len(MUTATIONS)} mutations were not detected')
            print(f'PASS: all {len(MUTATIONS)} mutations detected')
    print('PASS: the long actions of the Advanced Find panel')


if __name__ == '__main__':
    main()
