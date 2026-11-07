#!/usr/bin/env python3
"""Check default restoration without showing windows or changing the active layout/settings."""
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parents[1]
production=(root/'Sources/TSKeyboardShortcuts.m').read_text()
paths=sorted((root/'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
assert len(paths)==36
with tempfile.TemporaryDirectory(prefix='texshop-shortcut-restore-') as td:
    binary=Path(td)/'restore'
    def compile_source(source):
        (Path(td)/'TSKeyboardShortcuts.m').write_text(source)
        subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-deprecated-declarations','-framework','Cocoa','-framework','Carbon','-I',td,'-I',str(root/'Sources'),str(root/'Tests/ShortcutRestoration.m'),'-o',str(binary)],check=True)
    compile_source(production)
    for path in paths:
        subprocess.run([str(binary),str(path)],check=True)
    if '--mutations' in sys.argv:
        cases={
            'treat every symbol as Shift-encoded': ('if (encodesShift) [bindings addObject:', 'if (YES) [bindings addObject:'),
            'omit alternate Shift spelling': ('if (encodesShift) [bindings addObject:TSBinding(key, flags ^ NSEventModifierFlagShift)];',''),
            'omit shifted layout character': ('[bindings addObject:TSBinding(shifted, flags & ~NSEventModifierFlagShift)];',''),
            'omit unshifted physical spelling': ('[bindings addObject:TSBinding(plain, flags | NSEventModifierFlagShift)];','(void)0;'),
            'restore store checks raw spelling only': ('[self conflictForRestoringCommand:command]','[self conflictForKey:command.defaultKey modifiers:command.defaultModifiers except:command.item restoring:command]'),
            'restore UI checks raw spelling only': ('[self.store conflictForRestoringCommand:command]','[self.store conflictForKey:command.defaultKey modifiers:command.defaultModifiers except:command.item restoring:command]'),
            'restoration conflicts with itself': ('except:command.item restoring:command];','except:nil restoring:command];'),
            'restoration expands letter keys': ('if (!TSRestorationSymbol(key)) return bindings.array;','if (!key.length) return bindings.array;'),
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
