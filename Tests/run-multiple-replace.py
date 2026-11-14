#!/usr/bin/env python3
"""Multiple replacement (Tests/MultipleReplace.m): the library of sets in its folder, applying a set as one undo,
the rule table, the window, the Find menu's items, and the window in all 12 languages. Nothing is displayed; the
defaults stay in memory, the pasteboards are unique and the sets go into temporary folders.

--image DIR writes the window, a set without rules, a window without sets, the window with the bundled samples and
a set's options, light and dark, in English, German and Japanese (--image-all-languages: in all 12).
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys
import tempfile
from source_tree import include_args, advanced_find_syntax_sources

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
    'decomposed file names are listed as they are': ('TSMultipleReplaceLibrary.m', 'lastPathComponent.precomposedStringWithCanonicalMapping ?: @""]', 'lastPathComponent ?: @""]'),
    'other files are listed as sets': ('TSMultipleReplaceLibrary.m', '        if ([file.pathExtension isEqualToString:TSMultipleReplaceLibrary.fileExtension])\n            // The file system', '            // The file system'),
    'a dropped row is not moved back by the rows above it': ('TSMultipleReplaceRuleTable.m',
        '(NSUInteger)row - [indexes countOfIndexesInRange:NSMakeRange(0, (NSUInteger)row)];', 'MIN((NSUInteger)row, rules.count - indexes.count);'),
    'problems are not marked': ('TSMultipleReplaceRuleTable.m', '    NSError *problem = self.problems[@(row)];', '    NSError *problem = nil;'),
    'OgreKit\'s Find submenu is not found': ('TSMultipleReplaceMenu.m', '            || item.action == NSSelectorFromString(@"showFindPanel:"))', ')'),
    'the fallback name is not localized': ('TSMultipleReplaceLibrary.m', 'localizedStringForKey:@"MultipleReplace.Imported" value:@"Imported"', 'localizedStringForKey:@"MultipleReplace.Imported.Missing" value:@"MultipleReplace.Imported"'),
    'sets are saved as .cotrpl': ('TSMultipleReplaceLibrary.m', 'TSMultipleReplaceFileExtension = @"json";', 'TSMultipleReplaceFileExtension = @"cotrpl";'),
    '.cotrpl is read as tab-separated text': ('TSMultipleReplaceLibrary.m', ' || [extension isEqualToString:TSCotEditorFileExtension])', ')'),
    'the menu is added twice': ('TSMultipleReplaceMenu.m', '        if ([item.identifier isEqualToString:TSShowMultipleReplaceIdentifier])\n            return;\n', ''),
    'the sets menu ignores a read-only target': ('TSMultipleReplaceMenu.m',
        '        return target && [self.findController validateAction:TSAdvancedFindActionReplaceAll forTextView:(NSTextView *_Nonnull)target];',
        '        return target != nil;'),
    'Replace All ignores a read-only target': ('TSMultipleReplaceWindowController.m',
        '        BOOL enabled = target ? [controller validateAction:actions[index] forTextView:target] : controller.runningTask == nil;', '        BOOL enabled = YES;'),
    'the set options can be opened without a set': ('TSMultipleReplaceWindowController.m', '    self.optionsButton.enabled = set;', '    self.optionsButton.enabled = YES;'),
    'the set options need a rule': ('TSMultipleReplaceWindowController.m', '    self.optionsButton.enabled = set;', '    self.optionsButton.enabled = set && self.ruleTable.set.rules.count > 0;'),
    'minus of the rules ignores the selection': ('TSMultipleReplaceWindowController.m',
        '[self.ruleButtons setEnabled:set && self.ruleTable.tableView.selectedRowIndexes.count > 0 forSegment:1];', '[self.ruleButtons setEnabled:set forSegment:1];'),
    'the regular expression column is .*': ('TSMultipleReplaceRuleTable.m', 'title:@"RE"', 'title:@".*"'),
    'the set names fill their rows': ('TSMultipleReplaceWindowController.m',
        '    NSTableCellView *cell = [TSMultipleReplaceRuleTable cellWithControl:field];\n    cell.textField = nil;', '    NSView *cell = field;'),
    'the cells sit at the top of the row': ('TSMultipleReplaceRuleTable.m',
        '[control.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]', '[control.topAnchor constraintEqualToAnchor:cell.topAnchor]'),
    'the names keep a new column\'s width': ('TSMultipleReplaceWindowController.m', '    column.width = NSWidth(self.setTable.frame);\n', ''),
    'the sidebar starts narrower than the samples\' names': ('TSMultipleReplaceWindowController.m', 'static const CGFloat TSSidebarWidth = 240;', 'static const CGFloat TSSidebarWidth = 180;'),
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
        for table in ['AdvancedFind.strings', 'AdvancedFindEngine.strings', 'MultipleReplaceSamples.strings']:
            shutil.copy(root / 'Resources/Interfaces' / f'{language}.lproj' / table, resources / f'{language}.lproj' / table)
    shutil.copytree(root / 'Resources/MultipleReplaceSamples', resources / 'MultipleReplaceSamples')
    localizations = ''.join(f'<string>{l}</string>' for l in LANGUAGES)
    (app / 'Contents/Info.plist').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.texshop.test.MultipleReplace</string>
<key>CFBundleExecutable</key><string>probe</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array>{localizations}</array></dict></plist>''')
    probe = app / 'Contents/MacOS/probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-mmacosx-version-min=14.6', '-Wall', '-Wno-unused-parameter',
                    '-Wno-deprecated-declarations', '-I', str(sources), *include_args(root), '-I', str(root / 'Tests'),
                    '-framework', 'Cocoa', str(root / 'Tests/MultipleReplace.m'), *map(str, sorted(sources.glob('*.m'))), *map(str, advanced_find_syntax_sources(root)),
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


def check_launch_order(delegate, shortcuts):
    """The items join the Find submenu on the main queue after the launch notification, where OgreKit replaces the
    submenu, and before the shortcuts are read from the menu, which is queued after them."""
    start = delegate.index('- (void)applicationDidFinishLaunching:')
    body = delegate[start:delegate.index('\n}\n', start)]
    install = body.find('[TSMultipleReplaceMenu installInMainMenu:')
    queued = body.rfind('dispatch_async(dispatch_get_main_queue()', 0, install) if install >= 0 else -1
    reading = body.find('startAfterLaunchWithConfiguration:')
    method = shortcuts[shortcuts.index('- (void)startAfterLaunchWithConfiguration:'):]
    method = method[:method.index('\n}\n')]
    return 0 <= queued < install < reading and 'dispatch_async(dispatch_get_main_queue()' in method


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    parser.add_argument('--image-all-languages', action='store_true')
    parser.add_argument('--mutations', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='texshop-multiple-replace-') as tmp:
        tmp = Path(tmp)
        delegate = (root / 'Sources/App/TSAppDelegate.m').read_text(encoding='latin1')
        shortcuts = (root / 'Sources/Shortcuts/TSKeyboardShortcuts.m').read_text(encoding='latin1')
        if not check_launch_order(delegate, shortcuts):
            sys.exit('FAIL: the Multiple Replace items join the Find submenu after OgreKit and before the shortcuts are read')
        moved = delegate.replace('    dispatch_async(dispatch_get_main_queue(), ^{\n        NSString *directory', '    if (1) {\n        NSString *directory', 1)
        if moved == delegate or check_launch_order(moved, shortcuts):
            sys.exit('FAIL: the launch order check does not notice an install that is not queued')
        print('PASS: launch order (after OgreKit, before the shortcuts are read)')
        # The help button opens this anchor of the English help (the other help books take it as they describe the window).
        help_page = (root / 'Resources/Interfaces/en.lproj/TeXShopHelp/pgs/basic_edittricks.htm').read_text(encoding='latin1')
        window_source = (root / 'Sources/Find/TSMultipleReplaceWindowController.m').read_text()
        if '+ (NSString *)helpAnchor { return @"multiplereplace"; }' not in window_source or '<a name="multiplereplace"></a>' not in help_page:
            sys.exit('FAIL: the help button\'s anchor is in the English help')
        print('PASS: the help anchor of Multiple Replace')
        probe = build(tmp, copy_sources(tmp))
        result = run(probe, 'behavior')
        print(result.stdout + result.stderr, end='')
        if result.returncode:
            sys.exit('FAIL: multiple replacement')
        for language in LANGUAGES:
            images = args.image if args.image and (args.image_all_languages or language in ('en', 'de', 'ja')) else None
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
