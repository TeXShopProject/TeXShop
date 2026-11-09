#!/usr/bin/env python3
"""Check default restoration without showing windows or changing the active layout/settings."""
from pathlib import Path
from shortcut_sources import production_source, companion_sources
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
production=production_source(root)
paths=sorted((root/'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
assert len(paths)==36
with tempfile.TemporaryDirectory(prefix='texshop-shortcut-restore-') as td:
    binary=Path(td)/'restore'
    def compile_source(source):
        (Path(td)/'TSKeyboardShortcuts.m').write_text(source)
        subprocess.run(['xcrun','clang','-O2','-fobjc-arc','-Wno-deprecated-declarations','-framework','Cocoa','-framework','Carbon','-I',td,'-I',str(root/'Sources'),str(root/'Tests/ShortcutRestoration.m'),*companion_sources(root),'-o',str(binary)],check=True)
    compile_source(production)
    for path in paths:
        subprocess.run([str(binary),str(path)],check=True)
    if '--mutations' in sys.argv:
        cases={
            'compare aliases against untouched defaults': ('self.overrides[other.commandID] && other.item.keyEquivalent.length &&\n            [TSBinding(other.item.keyEquivalent, other.item.keyEquivalentModifierMask) isEqual:self.overrides[other.commandID]]', 'other.item.keyEquivalent.length'),
            'compare rejected overrides as live custom keys': (' &&\n            [TSBinding(other.item.keyEquivalent, other.item.keyEquivalentModifierMask) isEqual:self.overrides[other.commandID]]', ''),
            'omit raw check for anonymous menu items': ('if (rawConflict) return rawConflict;', '(void)rawConflict;'),
            'omit all alternate restoration spellings': ('if (!data || !TSRestorationSymbol(key)) return bindings.array;', 'return bindings.array;'),
            'ignore symbols on number keys': ('if ([TSShortcutStore isAllowedKey:recorded[@"key"]', 'if (TSRestorationSymbol(plain) && [TSShortcutStore isAllowedKey:recorded[@"key"]'),
            'ignore Command modifier layer': ('TSRestorationCharacters(data, code, modifiers, keyboardType)', 'TSRestorationCharacters(data, code, modifiers & NSEventModifierFlagShift, keyboardType)'),
            'restore store checks raw spelling only': ('[self conflictForRestoringCommand:command]','[self conflictForKey:command.defaultKey modifiers:command.defaultModifiers except:command.item restoring:command]'),
            'restore UI checks raw spelling only': ('[self.store conflictForRestoringCommand:command]','[self.store conflictForKey:command.defaultKey modifiers:command.defaultModifiers except:command.item restoring:command]'),
            'restoration conflicts with itself': ('except:command.item restoring:command];','except:nil restoring:command];'),
            'restoration aliases conflict with own override': ('other.item != command.item && self.overrides[other.commandID]', 'self.overrides[other.commandID]'),
            'restoration omits key codes 64 and above': ('for (UInt16 code = 0; code < 128; code++)', 'for (UInt16 code = 0; code < 64; code++)'),
        }
        for name,(before,after) in cases.items():
            assert production.count(before)==1,(name,before)
            compile_source(production.replace(before,after))
            detected=False
            for path in paths:
                result=subprocess.run([str(binary),str(path)],capture_output=True,text=True)
                if result.returncode:
                    assert 'FAIL ' in result.stderr,(name,result.stderr)
                    print('DETECTED:',name,result.stderr.strip());detected=True;break
            assert detected,name
