#!/usr/bin/env python3
"""The window of the TeX sources of a root (Tests/TeXRootSearchWindow.m, Issue #45 spec §2.7): the model of the
window (collecting, generations and the pause, results dropped when late, stopping, files and items on and off, open
documents and their edits, the limit, a multiple replacement set), the window itself (modes, the strings shared with
the panel, the status, Replace All, the question mark, the files not read, Escape), the tree and the list (three
states, checks, highlights, Space and Return, what VoiceOver reads), the entry rules and the items of the panel and of
the Multiple Replace window. Nothing is displayed; the defaults stay in memory.

Every language: the strings are found and the line that says what is searched is never cut.
The main thread: a 10 MB open document with 100,000 matches is listed, searched again and an item turned off without
the main thread stopping for 100 ms or more (spec §2.9).

--image DIR writes the window in its three modes and the question mark's popover, light and dark, in English and
Japanese. --mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parent))
from source_tree import include_args, advanced_find_syntax_sources

root = Path(__file__).resolve().parents[1]
LANGUAGES = ['en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
DOCUMENT = ['TSTeXRootProject.m', 'TSRootFileResolver.m', 'TSSourceMagicComments.m']

MUTATIONS = {
    'a change does not move the generation': ('TSTeXRootSearchModel.m', '    [self userChanged];\n    self.generation++;\n    [self.excludedItems removeAllObjects];',
                                              '    [self userChanged];\n    [self.excludedItems removeAllObjects];'),
    'a late result is taken': ('TSTeXRootSearchModel.m', 'return model && model.token == token && !token.cancelled;', 'return model != nil;'),
    'the pause is skipped': ('TSTeXRootSearchModel.m', '    self.environment.performAfterDelay(self.pause, ^{', '    ((void (^)(NSTimeInterval, dispatch_block_t))^(NSTimeInterval d, dispatch_block_t b) { b(); })(self.pause, ^{'),
    'a file turned on searches every file': ('TSTeXRootSearchModel.m', '    if (included) {\n        [self computeFiles:changedFiles];', '    if (included) {\n        [self computeFiles:nil];'),
    'items stay off after new conditions': ('TSTeXRootSearchModel.m', '    self.generation++;\n    [self.excludedItems removeAllObjects];', '    self.generation++;'),
    'an edit searches every file': ('TSTeXRootSearchModel.m', '        BOOL full = model.fullSearchPending || model.reachedLimit;', '        BOOL full = YES;'),
    'stopping keeps the list': ('TSTeXRootSearchModel.m', '    self.requestNumber++;\n    [self.fileResults removeAllObjects];\n    self.reachedLimit = NO;\n    self.stopped = YES;',
                                '    self.requestNumber++;\n    self.reachedLimit = NO;\n    self.stopped = YES;'),
    'Replace All with the limit reached': ('TSTeXRootSearchModel.m', '        && !self.reachedLimit && !self.stopped', '        && !self.stopped'),
    'search-only items can be replaced': ('TSTeXRootSearchModel.m', '    if (self.mode == TSTeXRootSearchModeFind || file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone)\n        return NO;',
                                          '    if (self.mode == TSTeXRootSearchModeFind)\n        return NO;'),
    'the panel\'s strings do not reach the window': ('TSTeXRootSearchWindowController.m', '    self.model.findString = settings.findString;\n', ''),
    'a mixed folder turns off': ('TSTeXRootSearchFileTree.m', '    [self setNodes:@[node] on:[self stateOfNode:node] != NSControlStateValueOn];\n}\n\n- (NSControlStateValue)stateOfRow',
                                 '    [self setNodes:@[node] on:[self stateOfNode:node] == NSControlStateValueOff];\n}\n\n- (NSControlStateValue)stateOfRow'),
    'the match is not marked': ('TSTeXRootSearchResultsList.m', '[shown addAttribute:NSBackgroundColorAttributeName value:(NSColor *_Nonnull)color range:highlight];',
                                '[shown addAttribute:NSBackgroundColorAttributeName value:(NSColor *_Nonnull)color range:NSMakeRange(0, 0)];'),
    'Escape does not stop': ('TSTeXRootSearchWindowController.m', '    if (self.model.activity != TSTeXRootSearchActivityIdle)\n        [self.model stop];\n}', '}'),
    'the %SourceDoc sentence always': ('TSTeXRootSearchWindowController.m', '    if (self.mentionsSourceDoc)\n        rule =', '    if (YES)\n        rule ='),
    'Return does not press Replace All ▾': ('TSMultipleReplaceWindowController.m', '        [self sendAction:self.action to:self.target];\n        return YES;', '        return NO;'),
    'a document closed since collecting is kept': ('TSTeXRootSearchModel.m', '    if (self.project && ![self collectedDocumentsStand]) {', '    if (NO) {'),
    'choosing an item reads on the main thread': ('TSTeXRootEntryRules.m', '    dispatch_async(self.queue, ^{\n        NSURL *root = nil;', '    dispatch_async(dispatch_get_main_queue(), ^{\n        NSURL *root = nil;'),
    'a long item hides how many lines it has more': ('TSTeXRootSearchResultsList.m', 'NSString *rest = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.MoreLines", @"⋯ %lu more lines"), (unsigned long)more];', 'NSString *rest = @"⋯";'),
    'the whole change is cut too': ('TSTeXRootSearchResultsList.m', 'NSMutableAttributedString *whole = [[NSMutableAttributedString alloc] initWithString:text attributes:base];',
                                    'NSMutableAttributedString *whole = [[NSMutableAttributedString alloc] initWithString:[text substringToIndex:MIN(text.length, (NSUInteger)60)] attributes:base];'),
    '21 lines are cut': ('TSTeXRootSearchResultsList.m', '    if (more >= 2) {', '    if (more >= 1) {'),
    'the collector is prepared on the main thread': ('TSTeXRootSearchModel.m', '    dispatch_async(self.queue, ^{\n        if (prepare)\n            prepare(collector);', '    if (prepare)\n        prepare(collector);\n    dispatch_async(self.queue, ^{', 'main-thread'),
    'the whole change is laid out all at once': ('TSTeXRootSearchResultsList.m', 'view.layoutManager.allowsNonContiguousLayout = YES;', 'view.layoutManager.allowsNonContiguousLayout = NO;', 'main-thread'),
    '.TEX counts as .tex': ('TSTeXRootEntryRules.m', 'return [url.pathExtension isEqualToString:@"tex"];', 'return [url.pathExtension.lowercaseString isEqualToString:@"tex"];'),
}


def copy_sources(tmp):
    sources = tmp / 'sources'
    sources.mkdir()
    for path in [*(root / 'Sources/Find').glob('*.[mh]'), *(root / 'Sources/Find/TeXRoot').glob('*.[mh]'),
                 *(root / 'Sources/Windows').glob('TSListBottomBar.[mh]')]:
        if path.name.startswith('TSTeXRootSearchEntry'):
            continue  # needs TSDocument; its rules are TSTeXRootEntryRules
        shutil.copy(path, sources / path.name)
    for name in DOCUMENT:
        shutil.copy(root / 'Sources/Document' / name, sources / name)
    return sources


def build(tmp, sources):
    app = tmp / 'Probe.app'
    resources = app / 'Contents/Resources'
    (app / 'Contents/MacOS').mkdir(parents=True)
    for language in LANGUAGES:
        (resources / f'{language}.lproj').mkdir(parents=True)
        for table in ['AdvancedFind.strings', 'AdvancedFindEngine.strings', 'MultipleReplaceSamples.strings']:
            shutil.copy(root / 'Resources/Interfaces' / f'{language}.lproj' / table, resources / f'{language}.lproj' / table)
    localizations = ''.join(f'<string>{l}</string>' for l in LANGUAGES)
    (app / 'Contents/Info.plist').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.TeXRootSearchWindow</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    probe = app / 'Contents/MacOS/probe'
    compiled = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                               '-Wno-deprecated-declarations', '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'),
                               '-framework', 'Cocoa', str(root / 'Tests/TeXRootSearchWindow.m'), *map(str, sorted(sources.glob('*.m'))),
                               *(str(path) for path in advanced_find_syntax_sources(root) if not (sources / path.name).exists()),
                               '-o', str(probe)], capture_output=True, text=True)
    if compiled.returncode:
        return None, compiled.stderr
    return probe, ''


def run(probe, mode, language='en', images=None):
    command = [str(probe), mode, *([str(images)] if images else []), '-AppleLanguages', f'({language})']
    return subprocess.run(command, capture_output=True, text=True, timeout=600)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='texshop-texroot-window-') as tmp:
        tmp = Path(tmp)
        probe, errors = build(tmp, copy_sources(tmp))
        if not probe:
            print(errors)
            return 1
        failed = False
        for mode, languages in [('behavior', ['en']), ('main-thread', ['en']), ('language', LANGUAGES)]:
            for language in languages:
                images = args.image if args.image and mode == 'behavior' else None
                result = run(probe, mode, language, images)
                out = '\n'.join(line for line in (result.stdout + result.stderr).splitlines() if 'sandbox_extension' not in line)
                print(out)
                failed |= result.returncode != 0
        if args.image:
            for language in ['ja']:
                result = run(probe, 'behavior', language, args.image)
                print('\n'.join(line for line in (result.stdout + result.stderr).splitlines() if 'sandbox_extension' not in line and 'FAIL' not in line))
            print(f'images in {args.image}')
        if failed:
            print('FAIL: the window of the TeX sources of a root')
            return 1
        if args.mutations:
            survived = []
            for name, (file, old, new, *modes) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-texroot-window-mutation-') as mtmp:
                    mtmp = Path(mtmp)
                    sources = copy_sources(mtmp)
                    text = (sources / file).read_text(encoding='utf-8')
                    if text.count(old) != 1:
                        print(f'mutation {name!r}: the text to break is found {text.count(old)} times')
                        return 1
                    (sources / file).write_text(text.replace(old, new), encoding='utf-8')
                    mprobe, errors = build(mtmp, sources)
                    if not mprobe:
                        print(f'mutation {name!r} does not compile:\n{errors}')
                        return 1
                    caught = any(run(mprobe, mode).returncode != 0 for mode in (modes or ['behavior']))
                    print(f"{'caught' if caught else 'SURVIVED'}: {name}")
                    if not caught:
                        survived.append(name)
            if survived:
                print(f'{len(survived)} mutations survived')
                return 1
            print(f'PASS: all {len(MUTATIONS)} mutations caught')
        print('PASS: the window of the TeX sources of a root')
    return 0


if __name__ == '__main__':
    sys.exit(main())
