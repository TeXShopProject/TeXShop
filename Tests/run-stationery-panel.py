#!/usr/bin/env python3
"""File > New from Stationery, built offscreen in all twelve languages (see
StationeryPanel.m), with the stationery bundled with TeXShop and with a folder of
test files. No window is shown, no document is opened and nothing is opened in the
Finder; AppKit defaults stay in memory.

  --png DIR     also draw the panel in each language, light and dark, into DIR
  --mutations   check that the test fails when the panel loses what it checks"""
from pathlib import Path
import argparse, shutil, subprocess, sys, tempfile
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--png')
parser.add_argument('--mutations', action='store_true')
args = parser.parse_args()

tables = sorted((root / 'Resources/Interfaces').glob('*.lproj/Localizable.strings'))
tables.sort(key=lambda p: p.parent.stem != 'en')
assert len(tables) == 12, tables
main_menu = sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/designable.nib'))
assert len(main_menu) == 12, main_menu
for nib in main_menu:
    text = nib.read_text(encoding='utf-8')
    assert 'customClass="TSStationery"/>' in text and 'stationeryWindow' not in text, \
        f'{nib.relative_to(root)}: TSStationery builds its own panel; the nib keeps only the object the menu item targets'
    assert 'selector="newFromStationery:"' in text, f'{nib.relative_to(root)}: File > New from Stationery'


def run(source, tmp):
    binary = tmp / 'StationeryPanel'
    built = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz',
                            '-I', str(root / 'Tests'), *include_args(root), str(root / 'Tests/StationeryPanel.m'),
                            str(source), str(root / 'Sources/Windows/TSListBottomBar.m'), '-o', str(binary)], capture_output=True, text=True)
    if built.returncode:
        return 2, built.stderr[-3000:]
    work = tmp / 'work'
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(root / 'Resources/TeXShop/Stationery', work / 'Bundled')
    home = tmp / 'home'
    (home / 'Library/Preferences').mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(binary), str(work), args.png or '-', *(f'{t.parent.stem}={t}' for t in tables)],
                            capture_output=True, text=True, timeout=600,
                            env={'HOME': str(home), 'CFFIXED_USER_HOME': str(home), 'TMPDIR': str(tmp), 'PATH': '/usr/bin:/bin'})
    return result.returncode, result.stdout + (result.stderr[-3000:] if result.returncode and not result.stdout.strip() else '')


MUTATIONS = {
    'not read again when key': ('- (void)windowDidBecomeKey:(NSNotification *)notification\n{\n\t[self reloadStationery];', '- (void)windowDidBecomeKey:(NSNotification *)notification\n{\n'),
    'hidden files listed': ('[file hasPrefix:@"."] || ', ''),
    'Create always enabled': ('self.createButton.enabled = selected;', 'self.createButton.enabled = YES;'),
    'plus always enabled': ('self.listBar.addButton.enabled = [self frontDocument] != nil;', 'self.listBar.addButton.enabled = YES;'),
    'selection lost on reload': ('if (row != NSNotFound) [table selectRowIndexes', 'if (NO) [table selectRowIndexes'),
    'Return presses Create while editing': ('\tself.createButton.keyEquivalent = @"";\n', ''),
    'description not written': ('if (![self writeDescription:description forName:[self titleAtRow:row] error:&error]) {', 'if (NO) {'),
    'remove without asking': ('[alert beginSheetModalForWindow:self.stationeryWindow completionHandler:^(NSModalResponse response) {\n\t\tif (response == NSAlertFirstButtonReturn) [self trashStationeryFile:file];\n\t}];',
                              '[self trashStationeryFile:file];'),
    'replace without asking': ('if (existing.count && !replacing) {', 'if (NO) {'),
    'any name accepted': ('return name.length > 0 && ', 'return YES || name.length > 0 && '),
    'Space ignored': ('if (plain && [event.charactersIgnoringModifiers isEqualToString:@" "]) {', 'if (NO) {'),
    'Quick Look not following': ('if ([QLPreviewPanel sharedPreviewPanelExists] && [QLPreviewPanel sharedPreviewPanel].visible) [[QLPreviewPanel sharedPreviewPanel] reloadData];', ''),
    'Escape closes the panel under Quick Look': ('\tif ([self quickLookIsShowingStationery]) {\n\t\t[[QLPreviewPanel sharedPreviewPanel] orderOut:nil];\n\t\treturn;\n\t}\n', ''),
    'open stationery detached': ('\tif ([self documentIsOpenForURL:url]) {', '\tif (NO) {'),
    'open stationery missed': ('if ([document respondsToSelector:@selector(isSameFileAs:)] && [(TSDocument *)document isSameFileAs:url]) return YES;', ''),
    'copy without its description': ('\tif ([fileManager fileExistsAtPath:comment])\n\t\t[fileManager copyItemAtPath:comment', '\tif (NO)\n\t\t[fileManager copyItemAtPath:comment'),
    'copy over the first copy': ('for (NSUInteger number = 2; [self stationeryFilesNamed:name].count ||', 'for (NSUInteger number = 2; NO &&'),
    'folder not created': ('if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {',
                           'if (NO) {'),
}

source = root / 'Sources/App/TSStationery.m'
with tempfile.TemporaryDirectory(prefix='texshop-stationery-panel-', dir='/private/tmp') as tmp:
    tmp = Path(tmp)
    if args.png:
        Path(args.png).mkdir(parents=True, exist_ok=True)
    code, output = run(source, tmp)
    print(output, end='')
    if code or not args.mutations:
        sys.exit(code)
    args.png = None
    text = source.read_text(encoding='utf-8')
    survived = []
    for name, (old, new) in MUTATIONS.items():
        assert text.count(old) == 1, f'mutation {name!r} no longer applies'
        mutant = tmp / 'mutant' / name.replace(' ', '-') / 'TSStationery.m'
        mutant.parent.mkdir(parents=True)
        mutant.write_text(text.replace(old, new), encoding='utf-8')
        code, output = run(mutant, tmp / 'mutant' / name.replace(' ', '-'))
        # A failed check (1) or a crash of the check catches the mutation; 2 is a build failure.
        print(f'mutation {name}: {"NOT CAUGHT" if code == 0 else "did not build" if code == 2 else "caught"}')
        if code in (0, 2):
            survived.append(name)
    sys.exit(1 if survived else 0)
