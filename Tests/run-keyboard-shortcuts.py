#!/usr/bin/env python3
"""Check shortcut storage/runtime menus and all localized nib command identities.
No TeXShop launch, real preference writes or input-source selection changes.
"""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
for path in sorted((root / 'Resources/Interfaces').glob('*/MainMenu.nib/designable.nib')):
    elements = ET.parse(path).getroot()
    commands = []
    for item in elements.iter('menuItem'):
        action = item.find('connections/action')
        if action is None or item.find('menu') is not None:
            continue
        ident = item.get('identifier', '')
        assert ident.startswith('TSShortcut.'), (path, item.attrib)
        commands.append(ident)
    assert len(commands) == len(set(commands)), (path, 'duplicate command IDs')
    for required in ['TSShortcut.doTypeset:.-1', 'TSShortcut.doTypeset:.-2',
                     'TSShortcut.doAlternateTypeset:.-2', 'TSShortcut.splitWindow:.0',
                     'TSShortcut.splitWindow:.vertical', 'TSShortcut.doNextBulletAndDelete:.0',
                     'TSShortcut.doPreviousBulletAndDelete:.0', 'TSShortcut.placeComment:.0']:
        assert required in commands, (path, required)
    if path.parts[-3] == 'fr.lproj':
        links = next(i for i in elements.iter('menuItem') if i.get('id') == '862')
        assert links.find('connections/action').get('selector') == 'toggleAutomaticLinkDetection:'
    print(f'PASS: {path.parts[-3]} {len(commands)} unique commands, including typesetting/alternates')

macro = (root / 'Sources/TSMacroMenuController.m').read_text(encoding='latin-1')
setup = macro[macro.index('- (void)setupMainMacroMenu'):macro.index('// reload')]
assert setup.index('beginMenuRebuild') < setup.index('listKeyEquivalents:') < setup.index('endMenuRebuild')
print('PASS: macro rebuild applies effective menu keys before collecting free keys')

# Guard the call sites as well as the standalone menu model. These checks do not
# replace the user's real-window checks for launch ordering and split orientation.
delegate = (root / 'Sources/TSAppDelegate.m').read_text(encoding='latin-1')
launch = delegate[delegate.index('- (void)applicationDidFinishLaunching:'):]
assert 'dispatch_async(dispatch_get_main_queue(), ^{\n        [[TSKeyboardShortcuts sharedController] installInMainMenu];' in launch
pdf = (root / 'Sources/MyPDFKitView.m').read_text(encoding='latin-1')
for tag in (1, 2):
    assert f'[TSKeyboardShortcuts event:theEvent matchesAction:@selector(performFindPanelAction:) tag:{tag}]' in pdf
document = (root / 'Sources/TSDocument.m').read_text(encoding='latin-1')
split = document[document.index('- (void) splitWindow:'):]
assert split.index('hasPrefix:@"TSShortcut.splitWindow:."') < split.index('[splitView setVertical:vertical]')
assert 'vertical = [[sender identifier] isEqualToString:@"TSShortcut.splitWindow:.vertical"]' in split
print('PASS: deferred launch installation, PDF search call sites and stable split orientation integration')

with tempfile.TemporaryDirectory(prefix='texshop-shortcuts-') as td:
    (Path(td) / 'MacroKeyProduction.inc').write_text(macro[macro.index('NSString *getKeyEquivalentFromString('):])
    binary = Path(td) / 'shortcuts'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'Carbon', '-I', td,
                    str(root / 'Tests/KeyboardShortcuts.m'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    paths = sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
    assert len(paths) == 36
    for path in paths:
        result = subprocess.run([str(binary), str(path), str(root / "Resources/TeXShop/Macros/Macros_Latex.plist")], capture_output=True, text=True)
        assert result.returncode == 0, (str(path), result.stdout, result.stderr)
    print('PASS: commands and bundled macro keys in all 36 compiled menu variants (12 languages)')
