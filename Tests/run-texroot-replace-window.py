#!/usr/bin/env python3
"""Replace All of the window "Find in TeX Sources" (Tests/TeXRootReplaceWindow.m, Issue #45 spec §2.5, §2.9): check 1
and the confirmation sheet, check 2, the backup, the files on the disk, the open documents a part at a time with one
Undo, stopping, the report and its buttons, the controls while it runs, and the guard TSDocument asks. Nothing is
displayed; the defaults stay in memory.

The main thread: Replace All in a 10 MB open document with about 78,000 matches, stopping it half way, and a 2 MB
insertion, without the main thread stopping for 100 ms or more (spec §2.9).
Every language: the strings of the sheets and the status are found, with the numbers put in (plurals by .stringsdict).
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
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
    'Return presses Replace': ('TSTeXRootSearchWindowController+Replace.m', '    cancel.keyEquivalent = @"\\r";\n', ''),
    'Replace is not marked destructive': ('TSTeXRootSearchWindowController+Replace.m', '    replace.hasDestructiveAction = YES;\n', ''),
    'check 1 is skipped': ('TSTeXRootSearchWindowController+Replace.m', '            if (changed.count) {\n                [controller showChangedFiles:changed];', '            if (NO) {\n                [controller showChangedFiles:changed];'),
    'check 2 is skipped': ('TSTeXRootReplaceRun.m', '            if (changed.count) {\n                self.report.changedFiles = changed;', '            if (NO) {\n                self.report.changedFiles = changed;'),
    'a file added is not seen': ('TSTeXRootReplaceRun.m', '            [changed addObject:file.relativePath];\n    return changed.array;', '            ;\n    return changed.array;'),
    'an edited open document is not seen': ('TSTeXRootReplaceRun.m', 'same = file.isOpen && [file.text isEqualToString:then.text];', 'same = file.isOpen;'),
    'the open documents stay editable': ('TSTeXRootReplaceRun.m', '                    view.editable = NO;\n                    [self.lockedViews addObject:view];', '                    [self.lockedViews addObject:view];'),
    'Stop does not take back': ('TSTeXRootDocumentApplier.m', '    if (self.stopRequested && !self.takingBack) {', '    if (NO) {'),
    'no Undo is registered': ('TSTeXRootDocumentApplier.m', '    TSRegisterChanges(undo, view, back, self.replacements, self.actionName);\n', ''),
    'a change by something else is not seen': ('TSTeXRootDocumentApplier.m', '    if (self.changedUnexpectedly || !view || !storage || view.textStorage != storage) {', '    if (!view || !storage || view.textStorage != storage) {'),
    'the guard is not told': ('TSTeXRootDocumentApplier.m', '    [TSTeXRootReplaceGuard addApplier:self];\n', ''),
    'the report is not shown': ('TSTeXRootSearchWindowController+Replace.m', '                [controller showReport:report title:report.allApplied ? message : nil];\n', '                ;\n'),
    'no backup': ('TSTeXRootSearchWindowController+Replace.m', '    if (self.backupBox.state == NSControlStateValueOn)\n        run.backupFolder', '    if (NO)\n        run.backupFolder'),
    'the items off are forgotten': ('TSTeXRootSearchWindowController+Replace.m', '            rangesOff[path] = [TSTeXRootReplaceMapping ranges:off afterReplacements:record.file.replacements];\n', ''),
    'Escape in check 1 is ignored': ('TSTeXRootSearchWindowController+Replace.m', '    TSReplaceRequest++;\n    self.replacing = NO;', '    self.replacing = NO;'),
    'the controls stay enabled': ('TSTeXRootSearchWindowController+Replace.m', '    BOOL free = !self.replacing && self.model != nil;', '    BOOL free = self.model != nil;'),
    'the window closes meanwhile': ('TSTeXRootSearchWindowController.m', '    if (!self.replacing)\n        return YES;\n    NSBeep();', '    return YES;\n    NSBeep();'),
    'a failed file does not stop the rest': ('TSTeXRootReplaceRun.m', '                failed = YES;\n                break;', '                failed = YES;'),
    'the original text is not offered': ('TSTeXRootSearchWindowController+Replace.m', '    if (partlyFiles.count && self.openTextHandler) {', '    if (NO) {'),
    'parts of any size': ('TSTeXRootDocumentApplier.m', '    _maximumReplacements = 1000;\n    _maximumCharacters = 50000;', '    _maximumReplacements = 100000000;\n    _maximumCharacters = 100000000;', 'main-thread'),
    'a long string in one insert': ('TSTeXRootDocumentApplier.m', '        if (take > self.maximumCharacters) {', '        if (NO) {', 'main-thread'),
    'Quit is answered between two documents': ('TSTeXRootDocumentApplier.m', '+ (void)runWaitingBlocks\n{\n    if (TSAppliers.count || TSRunning || !TSWaitingForNotApplying.count)\n        return;\n    dispatch_async(dispatch_get_main_queue(), ^{\n        if (TSAppliers.count || TSRunning)\n            return; // waits for the next end\n        NSArray<dispatch_block_t> *waiting = TSWaitingForNotApplying;\n        TSWaitingForNotApplying = nil;\n        for (dispatch_block_t block in waiting)\n            block();\n    });\n}\n\n', '+ (void)runWaitingBlocks\n{\n    if (TSAppliers.count || !TSWaitingForNotApplying.count)\n        return;\n    NSArray<dispatch_block_t> *waiting = TSWaitingForNotApplying;\n    TSWaitingForNotApplying = nil;\n    dispatch_async(dispatch_get_main_queue(), ^{\n        for (dispatch_block_t block in waiting)\n            block();\n    });\n}\n\n'),
    'Stop in check 2 does not cancel the collection': ('TSTeXRootReplaceRun.m', '        [collector cancel];\n        [self markRestFrom:0 reason:TSTeXRootReplaceReasonStopped];', '        [self markRestFrom:0 reason:TSTeXRootReplaceReasonStopped];'),
    'Stop in check 1 does not cancel the collection': ('TSTeXRootSearchWindowController+Replace.m', '    [self.checkCollector cancel];\n', ''),
    'Stop in check 2 waits for it': ('TSTeXRootReplaceRun.m', '    TSTeXRootProjectCollector *collector = self.checkCollector;\n    if (collector) {', '    TSTeXRootProjectCollector *collector = self.checkCollector;\n    if (NO) {'),
    'a backup in UTF-8 is not told when all is replaced': ('TSTeXRootSearchWindowController+Replace.m', '            if (!report.allApplied || report.backupNotes.count)', '            if (!report.allApplied)'),
    "the confirmation says the panel's Replace": ('TSTeXRootSearchWindowController+Replace.m', 'TSLocalized(@"TeXRootSearch.Confirm.Replace", @"Replace")', 'TSLocalized(@"AdvancedFind.Replace", @"Replace")', 'language'),
    'every file is guarded from typesetting': ('TSTeXRootDocumentApplier.m', '    return [TSProjectPaths containsObject:(NSString *_Nonnull)path];', '    return YES;'),
    'the backup is made on the main thread': ('TSTeXRootReplaceRun.m', '    dispatch_async(self.queue, ^{\n        NSError *error = nil;', '    ((void (^)(dispatch_queue_t, dispatch_block_t))^(dispatch_queue_t q, dispatch_block_t b) { b(); })(self.queue, ^{\n        NSError *error = nil;'),
    'a document made read-only is replaced in': ('TSTeXRootReplaceRun.m', '        if (!main.isEditable)\n            [self.notEditable addObject:', '        if (NO)\n            [self.notEditable addObject:'),
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
        for table in ['AdvancedFind.strings', 'AdvancedFindEngine.strings', 'MultipleReplaceSamples.strings', 'AdvancedFind.stringsdict']:
            if (root / 'Resources/Interfaces' / f'{language}.lproj' / table).exists():
                shutil.copy(root / 'Resources/Interfaces' / f'{language}.lproj' / table, resources / f'{language}.lproj' / table)
    localizations = ''.join(f'<string>{l}</string>' for l in LANGUAGES)
    (app / 'Contents/Info.plist').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.TeXRootReplaceWindow</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    probe = app / 'Contents/MacOS/probe'
    compiled = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                               '-Wno-deprecated-declarations', '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'),
                               '-framework', 'Cocoa', str(root / 'Tests/TeXRootReplaceWindow.m'), *map(str, sorted(sources.glob('*.m'))),
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
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='texshop-texroot-replace-window-') as tmp:
        tmp = Path(tmp)
        probe, errors = build(tmp, copy_sources(tmp))
        if not probe:
            print(errors)
            return 1
        failed = False
        for mode, languages in [('behavior', ['en']), ('main-thread', ['en']), ('language', LANGUAGES)]:
            for language in languages:
                result = run(probe, mode, language)
                out = '\n'.join(line for line in (result.stdout + result.stderr).splitlines() if 'sandbox_extension' not in line)
                print(out)
                failed |= result.returncode != 0
        if failed:
            print('FAIL: Replace All in the TeX sources of a root')
            return 1
        if args.mutations:
            survived = []
            for name, (file, old, new, *modes) in MUTATIONS.items():
                with tempfile.TemporaryDirectory(prefix='texshop-texroot-replace-window-mutation-') as mtmp:
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
                    caught = any(run(mprobe, mode, 'ja' if mode == 'language' else 'en').returncode != 0 for mode in (modes or ['behavior']))
                    print(f"{'caught' if caught else 'SURVIVED'}: {name}")
                    if not caught:
                        survived.append(name)
            if survived:
                print(f'{len(survived)} mutations survived')
                return 1
            print(f'PASS: all {len(MUTATIONS)} mutations caught')
        print('PASS: Replace All in the TeX sources of a root')
    return 0


if __name__ == '__main__':
    sys.exit(main())
