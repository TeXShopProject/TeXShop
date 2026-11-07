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
    cases.update({'A conflictForKey counts macro items (macros block custom keys in the UI)': [('TSKeyboardShortcuts.m',
                                                                               'if (item == excluded || '
                                                                               'item.submenu || item.action '
                                                                               '== '
                                                                               'NSSelectorFromString(@"doMacro:") '
                                                                               '|| '
                                                                               '!item.keyEquivalent.length) '
                                                                               'return;',
                                                                               'if (item == excluded || '
                                                                               'item.submenu || '
                                                                               '!item.keyEquivalent.length) '
                                                                               'return;')],
 'B menuBindings includes installed macro items': [('TSKeyboardShortcuts.m',
                                                    'if (!item.submenu && item.action != '
                                                    'NSSelectorFromString(@"doMacro:") && '
                                                    'item.keyEquivalent.length)\n'
                                                    '            [result',
                                                    'if (!item.submenu && item.keyEquivalent.length)\n'
                                                    '            [result')],
 'C no clearing of command keys before applying (transient duplicates)': [('TSKeyboardShortcuts.m',
                                                                           '    for (TSShortcutCommand '
                                                                           '*command in self.commands) '
                                                                           'command.item.keyEquivalent = '
                                                                           '@"";\n'
                                                                           '    for (TSShortcutCommand '
                                                                           '*command in self.commands) {\n'
                                                                           '        if ([active',
                                                                           '    for (TSShortcutCommand '
                                                                           '*command in self.commands) {\n'
                                                                           '        if ([active')],
 'D refreshMenuAndMacros does not rebuild macros': [('TSKeyboardShortcuts.m',
                                                     '        [[NSNotificationCenter defaultCenter] '
                                                     'postNotificationName:TSRebuildMacrosNotification '
                                                     'object:self];\n',
                                                     '')],
 'E menuStructureChanged ignores reentrancy guards': [('TSKeyboardShortcuts.m',
                                                       'if (menu != NSApp.mainMenu || '
                                                       'self.menuRefreshPending || self.applyingMenus || '
                                                       'self.rebuildingMacros) return;',
                                                       'if (menu != NSApp.mainMenu || '
                                                       'self.menuRefreshPending) return;')],
 'F menu notifications not observed at all': [('TSKeyboardShortcuts.m',
                                               'for (NSNotificationName name in '
                                               '@[NSMenuDidAddItemNotification, '
                                               'NSMenuDidRemoveItemNotification])',
                                               'for (NSNotificationName name in @[])')],
 'G imported macros treated as unchanged': [('MacroEditorProduction.inc',
                                             'if (original && [original isEqual:binding]) continue;',
                                             'if (!original || [original isEqual:binding]) continue;')],
 'H monitor never removed': [('TSKeyboardShortcuts.m',
                              '@finally { [NSEvent removeMonitor:monitor]; }',
                              '@finally { }')],
 'I pending key not restored after preview': [('MacroEditorProduction.inc',
                                               '    [self refreshShortcutConflicts];\n'
                                               '    self.previousItem.key = saved;',
                                               '    [self refreshShortcutConflicts];')],
 'J accepted macro not recorded as owner (no tooltip for later duplicate)': [('MacroMenuProduction.inc',
                                                                              '                    '
                                                                              'self.keyOwners[binding] = @{',
                                                                              '                    if (NO) '
                                                                              'self.keyOwners[binding] = '
                                                                              '@{')],
 'K close sheet not ordered out before deferred save': [('MacroEditorProduction.inc',
                                                         '        [alert.window orderOut:nil];\n',
                                                         '')],
 'L attachedSheet guard removed in windowShouldClose': [('MacroEditorProduction.inc',
                                                         '    if ([window attachedSheet]) return NO;\n',
                                                         '')],
 'M macrosAffectedByRestoringAll empty': [('TSKeyboardShortcuts.m',
                                           '    for (TSShortcutCommand *command in self.commands)\n'
                                           '        [result addObjectsFromArray:[self '
                                           'macrosUsingKey:command.defaultKey '
                                           'modifiers:command.defaultModifiers]];',
                                           '')],
 'N applyCapturedShortcut skips macro confirmation': [('TSKeyboardShortcuts.m',
                                                       '    if (![self '
                                                       'confirmMacrosUsingKey:self.capturedKey '
                                                       'modifiers:self.capturedModifiers]) return;\n'
                                                       '    NSString *error = [self.store '
                                                       'setKey:self.capturedKey',
                                                       '    NSString *error = [self.store '
                                                       'setKey:self.capturedKey')],
 'O beginMenuRebuild does not reapply menu keys': [('TSKeyboardShortcuts.m',
                                                    '    self.rebuildingMacros = YES;\n'
                                                    '    [self.store refreshMenu];',
                                                    '    self.rebuildingMacros = YES;')],
 'P matchesItem compares raw strings without A-Z Shift folding': [('TSKeyboardShortcuts.m',
                                                                   'return '
                                                                   '[TSRecordedBinding(event, [event charactersByApplyingModifiers:0]) '
                                                                   'isEqual:TSBinding(item.keyEquivalent, '
                                                                   'item.keyEquivalentModifierMask)];',
                                                                   'return '
                                                                   '[TSShortcutCharacterForEvent(event) '
                                                                   'isEqual:item.keyEquivalent] && '
                                                                   '(event.modifierFlags & '
                                                                   'TSShortcutModifiers) == '
                                                                   '(item.keyEquivalentModifierMask & '
                                                                   'TSShortcutModifiers);')],
 'Q restoreAll does not rebuild macros': [('TSKeyboardShortcuts.m',
                                           '[self.store restoreAll]; [self refreshMenuAndMacros];',
                                           '[self.store restoreAll];')],
 'R removeShortcut does not rebuild macros': [('TSKeyboardShortcuts.m',
                                               '    [self showError:[self.store setKey:@"" modifiers:0 '
                                               'forCommand:command]];\n'
                                               '    [self refreshMenuAndMacros];',
                                               '    [self showError:[self.store setKey:@"" modifiers:0 '
                                               'forCommand:command]];')]})
    cases.update({
        'recording leaves redundant punctuation Shift': [(k, 'flags &= ~NSEventModifierFlagShift;', 'flags |= NSEventModifierFlagShift;')],
        'engine rebuild leaves settings list stale': [(k, '    if (self.isWindowLoaded) [self reloadCommands];\n    [[NSNotificationCenter', '    [[NSNotificationCenter')],
        'macro rebuild leaves guard set after exception': [(m, '    } @finally {\n        [[TSKeyboardShortcuts sharedController] endMenuRebuild];\n    }', '    } @catch (NSException *exception) { @throw; }\n    [[TSKeyboardShortcuts sharedController] endMenuRebuild];')],
        'validation changes rebuild all macros': [(k, '@[NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification]', '@[NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification, NSMenuDidChangeItemNotification]'), (k,'    if ([[self menuBindingSnapshot] isEqual:self.observedMenuBindings]) return;',''), (k,'if (![[self menuBindingSnapshot] isEqual:self.observedMenuBindings]) [self refreshMenuAndMacros];','[self refreshMenuAndMacros];')],
    })
    for name, changes in cases.items(): run_case(name, changes)
for lang in ('en', 'ja'):
    subprocess.run(['plutil', '-lint', str(root / f'Resources/Interfaces/{lang}.lproj/Localizable.strings')], check=True)
