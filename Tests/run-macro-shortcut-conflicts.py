#!/usr/bin/env python3
"""Exercise production macro save/validation methods with no visible UI or real preferences."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
editor = (root / 'Sources/TSMacroEditor.m').read_text()
menu = (root / 'Sources/TSMacroMenuController.m').read_text()

def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

# Compile the actual methods; unrelated document/AppleScript subsystems are omitted.
parts = {
    'MacroEditorProduction.inc': between(editor, '- (void)collectShortcutCandidates:', '// action for Cancel button')
        + between(editor, '- (BOOL)windowShouldClose:', '// delegate method for window\n- (void) windowWillClose:')
        + between(editor, '- (BOOL)saveNodes:', '// action for "save selection'),
    'MacroMenuProduction.inc': between(menu, '- (void)setupMainMacroMenu', '// reload') + between(menu, '- (void)addItemsToMenu:', '// build a menu for popup')
        + between(menu, '- (void)listKeyEquivalents:', '\n@end'),
    'MacroKeyProduction.inc': menu[menu.index('NSString *getKeyEquivalentFromString('):],
}
def run_case(name, changes=()):
    sources = dict(parts)
    sources['TSKeyboardShortcuts.m'] = (root / 'Sources/TSKeyboardShortcuts.m').read_text()
    for filename, before, after in changes:
        assert sources[filename].count(before) == 1, (name, filename, before)
        sources[filename] = sources[filename].replace(before, after)
    with tempfile.TemporaryDirectory(prefix='texshop-macro-conflicts-') as td:
        for filename, value in sources.items():
            (Path(td) / filename).write_text(value)
        binary = Path(td) / 'conflicts'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wno-incomplete-implementation',
                        '-Wno-deprecated-declarations', '-Wno-nullability-completeness', '-framework', 'Cocoa', '-framework', 'Carbon',
                        '-I', td, '-I', str(root / 'Sources'),
                        str(root / 'Tests/MacroShortcutConflicts.m'),
                        str(root / 'Sources/TSMacroTreeNode.m'), '-o', str(binary)], check=True)
        result = subprocess.run([str(binary), td], capture_output=True, text=True, timeout=20)
        if changes:
            assert result.returncode != 0 and 'FAIL ' in result.stderr, (name, result.stdout, result.stderr)
            print('DETECTED:', name, result.stderr.strip().splitlines()[-1])
        else:
            print(result.stdout, end='')
            assert result.returncode == 0, result.stderr

run_case('baseline')
if '--mutations' in sys.argv:
    k='TSKeyboardShortcuts.m'; e='MacroEditorProduction.inc'; m='MacroMenuProduction.inc'
    cases = {
        'fold Shift-minus into equals': [(k, 'flags &= TSShortcutModifiers;', 'if ([key isEqual:@"-"] && (flags & NSEventModifierFlagShift)) { key=@"="; flags &= ~NSEventModifierFlagShift; } flags &= TSShortcutModifiers;')],
        'macros block custom menu keys': [(k, 'if (!item.submenu && item.action != NSSelectorFromString(@"doMacro:")) [planned', 'if (!item.submenu) [planned')],
        'do not clear installed macro keys before assignment': [(k, 'if (item.action == NSSelectorFromString(@"doMacro:")) item.keyEquivalent = @"";', 'if (NO) item.keyEquivalent = @"";')],
        'runtime menu comparison ignores uppercase Shift': [(m, 'NSDictionary *binding = [TSShortcutStore normalizedKey:entry[@"key"] modifiers:[entry[@"modifiers"] unsignedIntegerValue]];', 'NSDictionary *binding = @{@"key":[entry[@"key"] lowercaseString], @"modifiers":entry[@"modifiers"]};')],
        'allow later duplicate macro': [(m, 'if ([binding[@"key"] length]) [self.keyEquivalents addObject:binding];', 'if (NO) [self.keyEquivalents addObject:binding];')],
        'include services': [(k, 'if (item.submenu == NSApp.servicesMenu && item.submenu) continue;', 'if (NO) continue;'), (k, 'if (item.submenu && item.submenu != NSApp.servicesMenu) TSVisitMenu', 'if (item.submenu) TSVisitMenu')],
        'ignore changes that displace later macros': [(e, 'later < candidates.count', 'later < 0')],
        'warn on unchanged keys': [(e, 'if (original && [original isEqual:binding]) continue;', 'if (NO) continue;')],
        'ignore save cancellation': [(e, 'if (![self validateMacroShortcutsBeforeSaving]) return;', '[self validateMacroShortcutsBeforeSaving];')],
        'ignore field commit refusal': [(e, 'if (![window makeFirstResponder:window]) return;', '[window makeFirstResponder:window];')],
        'do not remove changed conflicts': [(e, 'setKey:@""', 'setKey:@"F"')],
        'ignore write failure': [(e, 'if (![self saveNodes: [outlineController rootOfTree] toFile: pathStr]) return;', '[self saveNodes: [outlineController rootOfTree] toFile: pathStr];')],
        'do not select conflicting macro': [(e, '[outlineView selectItems:@[node] byExtendingSelection:NO];', '[outlineView selectItems:@[] byExtendingSelection:NO];')],
        'no Escape handling': [(k, 'event.keyCode == 53', 'event.keyCode == 99')],
        'restore without macro confirmation': [(k, 'if (![self confirmMacrosUsingKey:command.defaultKey modifiers:command.defaultModifiers]) return;', 'if (NO) return;')],
        'save from sheet synchronously': [(e, 'dispatch_async(dispatch_get_main_queue(), ^{\n            if (response', '^{\n            if (response'), (e, 'else if (response == NSAlertSecondButtonReturn) [self cancelPressed:self];\n        });', 'else if (response == NSAlertSecondButtonReturn) [self cancelPressed:self];\n        }();')],
    }
    for name, changes in cases.items(): run_case(name, changes)
for lang in ('en', 'ja'):
    subprocess.run(['plutil', '-lint', str(root / f'Resources/Interfaces/{lang}.lproj/Localizable.strings')], check=True)
