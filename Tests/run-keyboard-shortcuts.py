#!/usr/bin/env python3
"""Check shortcut storage/runtime menus and all localized nib command identities.
No TeXShop launch, real preference writes or input-source selection changes.
"""
from pathlib import Path
from shortcut_sources import production_source
import subprocess
import tempfile
import sys
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
assert 'startAfterLaunchWithConfiguration:' in launch
subprocess.run([sys.executable,str(root/'Tests/run-shortcut-launch.py'),'--mutations'],check=True)
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
    production=production_source(root)
    (Path(td)/'TSKeyboardShortcuts.m').write_text(production)
    binary = Path(td) / 'shortcuts'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'Carbon', '-I', td, '-I',str(root/'Sources'),
                    str(root / 'Tests/KeyboardShortcuts.m'), str(root/'Sources/TSPrefPaneLayout.m'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    paths = sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
    assert len(paths) == 36
    for path in paths:
        result = subprocess.run([str(binary), str(path), str(root / "Resources/TeXShop/Macros/Macros_Latex.plist")], capture_output=True, text=True)
        assert result.returncode == 0, (str(path), result.stdout, result.stderr)
    print('PASS: commands and bundled macro keys in all 36 compiled menu variants (12 languages)')
    if '--mutations' in sys.argv:
        cases={
            'report the edited command as its own conflict': (
                'except:self.editingCommand.item restoring:nil];', 'except:nil restoring:nil];'),
            'show only the last conflicting command': (
                '[conflicts.array componentsJoinedByString:@"\\n"]', 'conflicts.lastObject'),
            'ignore captured spellings when checking conflicts': (
                'NSArray<TSShortcutBinding *> *bindings = self.capturedBindings ?: @[TSBinding(self.capturedKey, self.capturedModifiers)];',
                'NSArray<TSShortcutBinding *> *bindings = @[TSBinding(self.capturedKey, self.capturedModifiers)];'),
            'discard unshifted physical spelling': (
                '[bindings addObject:TSBinding(unshifted, event.modifierFlags)];', '(void)0;'),
            'discard shifted character spelling': (
                '[bindings addObject:TSBinding(key, event.modifierFlags)];', '(void)0;'),
            'do not retain captured event spellings': (
                'self.capturedBindings = TSEventBindings(event, [event charactersByApplyingModifiers:0]);',
                'self.capturedBindings = @[TSRecordedBinding(event, [event charactersByApplyingModifiers:0])];'),
            'apply shortcut without checking event spellings': (
                'NSString *conflict = [self conflictForCapturedShortcut];',
                'NSString *conflict = [self.store conflictForKey:self.capturedKey modifiers:self.capturedModifiers except:self.editingCommand.item restoring:nil];'),
        }
        for name,(before,after) in cases.items():
            assert production.count(before)==1,(name,before)
            (Path(td)/'TSKeyboardShortcuts.m').write_text(production.replace(before,after))
            subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-nullability-completeness','-framework','Cocoa','-framework','Carbon','-I',td,'-I',str(root/'Sources'),str(root/'Tests/KeyboardShortcuts.m'),str(root/'Sources/TSPrefPaneLayout.m'),'-o',str(binary)],check=True)
            detected=False
            for path in paths:
                result=subprocess.run([str(binary),str(path),str(root/'Resources/TeXShop/Macros/Macros_Latex.plist')],capture_output=True,text=True)
                if result.returncode:
                    assert 'FAIL ' in result.stderr,(name,result.stderr)
                    print('DETECTED:',name,path.parts[-3],result.stderr.strip())
                    detected=True
                    break
            assert detected,name
