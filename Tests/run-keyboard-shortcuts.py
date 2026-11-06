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

macro = (root / 'Sources/TSMacroMenuController.m').read_text()
setup = macro[macro.index('- (void)setupMainMacroMenu'):macro.index('// reload')]
assert setup.index('beginMenuRebuild') < setup.index('listKeyEquivalents:') < setup.index('endMenuRebuild')
print('PASS: macro rebuild suspends overrides before collecting keys and reapplies them afterward')

with tempfile.TemporaryDirectory(prefix='texshop-shortcuts-') as td:
    binary = Path(td) / 'shortcuts'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'Carbon',
                    str(root / 'Tests/KeyboardShortcuts.m'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    paths = sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
    assert len(paths) == 36
    for path in paths:
        result = subprocess.run([str(binary), str(path)], capture_output=True, text=True)
        assert result.returncode == 0, (str(path), result.stdout, result.stderr)
    print('PASS: all eight formerly excluded commands in 36 compiled menu variants')
