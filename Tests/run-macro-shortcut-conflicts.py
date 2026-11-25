#!/usr/bin/env python3
"""Exercise production macro save/validation methods with no visible UI or real preferences."""
from pathlib import Path
from shortcut_sources import production_source, companion_sources
import subprocess
import tempfile
import sys
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
editor = (root / 'Sources/Macros/TSMacroEditor.m').read_text()
menu = (root / 'Sources/Macros/TSMacroMenuController.m').read_text()
delegate = (root / 'Sources/App/TSAppDelegate.m').read_text()

def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]

# Compile the actual methods; unrelated document/AppleScript subsystems are omitted.
parts = {
    'MacroEditorProduction.inc': between(editor, '- (void)collectShortcutCandidates:', '// action for Cancel button')
        + between(editor, '- (void)setPendingShortcut:', '// Below the contents, as in the key binding list')
        + between(editor, '- (IBAction)nameFieldAction:', '// delegate method for contentTextView')
        + between(editor, '- (IBAction)textDidChange:', "// The nib's key field")
        + between(editor, '- (void)outlineViewSelectionChanged:', '// a method called on "Items changed"')
        + between(editor, '- (void)outlineViewItemsChanged:', '// interation bewteen outline')
        + between(editor, '- (void)writeMacrosBeforeTermination:', '// delegate method for window\n- (void) windowWillClose:')
        + between(editor, '- (BOOL)saveNodes:', '// action for "save selection'),
    'MacroMenuProduction.inc': between(menu, '- (void)setupMainMacroMenu', '// reload') + between(menu, '- (void)addItemsToMenu:', '// build a menu for popup')
        + between(menu, '- (void)listKeyEquivalents:', '\n@end'),
    'MacroKeyProduction.inc': menu[menu.index('NSString *getKeyEquivalentFromString('):],
    'TSAppDelegate.m': delegate,
}
def quit_gate_inc(delegate_text):
    start = delegate_text.index('- (NSApplicationTerminateReply)applicationShouldTerminate:')
    method = delegate_text[start:delegate_text.index('- (void)applicationWillTerminate:', start)]
    ask = 'if (![[TSMacroEditor sharedInstance] prepareMacrosBeforeTermination])\n        return NSTerminateCancel;'
    replace = 'if (![TSTeXRootReplaceGuard isApplying])'
    # The ask has to win before Replace All decides whether quitting waits.
    if ask in method and replace in method and method.index(ask) < method.index(replace):
        return 'static void CheckQuitGate(void) {\n    puts("PASS: quitting asks before the other termination checks");\n}\n'
    return ('static void CheckQuitGate(void) {\n'
            '    REQUIRE(0 && "applicationShouldTerminate asks, and cancelling that cancels quitting, before the other checks");\n'
            '}\n')
def run_case(name, changes=()):
    sources = dict(parts)
    sources['TSKeyboardShortcuts.m'] = production_source(root)
    for filename, before, after in changes:
        assert sources[filename].count(before) == 1, (name, filename, before)
        sources[filename] = sources[filename].replace(before, after)
    with tempfile.TemporaryDirectory(prefix='texshop-macro-conflicts-') as td:
        for filename, value in sources.items():
            (Path(td) / filename).write_text(value)
        (Path(td) / 'QuitGate.inc').write_text(quit_gate_inc(sources['TSAppDelegate.m']))
        binary = Path(td) / 'conflicts'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wno-incomplete-implementation',
                        '-Wno-deprecated-declarations', '-Wno-nullability-completeness', '-framework', 'Cocoa', '-framework', 'Carbon',
                        '-I', td, *include_args(root),
                        str(root / 'Tests/MacroShortcutConflicts.m'),
                        str(root / 'Sources/Macros/TSMacroTreeNode.m'), *companion_sources(root), '-o', str(binary)], check=True)
        result = subprocess.run([str(binary), td], capture_output=True, text=True, timeout=40)
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
        'ignore Shift on both comparison sides': [(k, 'return [[TSShortcutBinding alloc] initWithKey:key modifiers:flags];', 'return [[TSShortcutBinding alloc] initWithKey:key modifiers:flags & ~NSEventModifierFlagShift];')],
        'fold Shift-minus into equals': [(k, 'flags &= TSShortcutModifiers;', 'if ([key isEqual:@"-"] && (flags & NSEventModifierFlagShift)) { key=@"="; flags &= ~NSEventModifierFlagShift; } flags &= TSShortcutModifiers;')],
        'macros block custom menu keys': [(k, 'if (item.submenu || item.action == TSMacroAction() || [commandItems objectForKey:item]) return;', 'if (item.submenu || [commandItems objectForKey:item]) return;')],
        'do not clear installed macro keys before assignment': [(k, 'if (item.action == TSMacroAction()) item.keyEquivalent = @"";', 'if (NO) item.keyEquivalent = @"";')],
        'runtime menu comparison ignores uppercase Shift': [(m, 'NSDictionary *binding = [TSShortcutStore normalizedKey:entry[@"key"] modifiers:[entry[@"modifiers"] unsignedIntegerValue]];', 'NSDictionary *binding = @{@"key":[entry[@"key"] lowercaseString], @"modifiers":entry[@"modifiers"]};'),
            (k, '[result addObject:@{@"path":path, @"key":binding.key, @"modifiers":@(binding.modifiers), @"macro":@NO}];', '[result addObject:@{@"path":path, @"key":item.keyEquivalent, @"modifiers":@(item.keyEquivalentModifierMask), @"macro":@NO}];')],
        'allow later duplicate macro': [(m, 'if ([binding[@"key"] length]) [self.keyEquivalents addObject:binding];', 'if (NO) [self.keyEquivalents addObject:binding];')],
        'include services': [(k, 'if (item.submenu == NSApp.servicesMenu && item.submenu) continue;', 'if (NO) continue;'), (k, 'if (item.submenu && item.submenu != NSApp.servicesMenu) TSVisitMenu', 'if (item.submenu) TSVisitMenu')],
        'ignore changes that displace later macros': [(e, 'later < candidates.count', 'later < 0')],
        'warn on unchanged keys': [(e, 'if (original && [original isEqual:binding]) continue;', 'if (NO) continue;')],
        'ignore save cancellation': [(e, 'if (![self validateMacroShortcutsBeforeSaving]) {\n\t\t\treviewPending = YES;\n\t\t\treturn NO;\n\t\t}', '[self validateMacroShortcutsBeforeSaving];')],
        'ignore field commit refusal': [(e, 'if (![window makeFirstResponder:window]) return;', '[window makeFirstResponder:window];')],
        'do not remove changed conflicts': [(e, '    if (response == NSAlertThirdButtonReturn) {\n        for (NSDictionary *conflict in changed) [nodes[[conflict[@"index"] unsignedIntegerValue]] setKey:@""];\n', '    if (response == NSAlertThirdButtonReturn) {\n        for (NSDictionary *conflict in changed) [nodes[[conflict[@"index"] unsignedIntegerValue]] setKey:@"F"];\n')],
        'ignore write failure': [(e, 'if (![self saveNodes: [outlineController rootOfTree] toFile: pathStr]) return NO;', '[self saveNodes: [outlineController rootOfTree] toFile: pathStr];')],
        'do not select conflicting macro': [(e, '[outlineView selectItems:@[node] byExtendingSelection:NO];', '[outlineView selectItems:@[] byExtendingSelection:NO];')],
        'no Escape handling': [(k, 'event.keyCode == kVK_Escape', 'event.keyCode == 99')],
        'restore ignores macro confirmation refusal': [(k, 'if (strongSelf == nil || !accepted) { return; }', 'if (strongSelf == nil) { return; }')],
        'save closes the editor': [(e, '[self autosaveMacroEdits]; // stay open\n', '[self autosaveMacroEdits]; [window close]; // stay open\n')],
        'conflictForKey counts macro items (macros block custom keys in the UI)': [(k, 'if (item == excluded || item.submenu != nil || item.action == TSMacroAction() || item.keyEquivalent.length == 0) { return; }', 'if (item == excluded || item.submenu != nil || item.keyEquivalent.length == 0) { return; }')],
        'menuBindings includes installed macro items': [(k, 'if (item.hidden && !item.allowsKeyEquivalentWhenHidden) return;\n        if (item.submenu || item.action == TSMacroAction() || !item.keyEquivalent.length) return;', 'if (item.hidden && !item.allowsKeyEquivalentWhenHidden) return;\n        if (item.submenu || !item.keyEquivalent.length) return;')],
        'no clearing of command keys before applying (transient duplicates)': [(k, '    for (TSShortcutCommand *command in changing) command.item.keyEquivalent = @"";\n', '')],
        'refreshMenuAndMacros does not rebuild macros': [(k, '        [[NSNotificationCenter defaultCenter] postNotificationName:TSRebuildMacrosNotification object:self];\n', '')],
        'menuStructureChanged ignores reentrancy guards': [(k, 'if (menu != NSApp.mainMenu || self.menuRefreshPending || self.applyingMenus || self.rebuildingMacros) return;', 'if (menu != NSApp.mainMenu || self.menuRefreshPending) return;')],
        'menu notifications not observed at all': [(k, 'for (NSNotificationName name in @[NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification])', 'for (NSNotificationName name in @[])')],
        'imported macros treated as unchanged': [(e, 'if (original && [original isEqual:binding]) continue;', 'if (!original || [original isEqual:binding]) continue;')],
        'monitor never removed': [(k, '@finally { [NSEvent removeMonitor:monitor]; }', '@finally { }')],
        'pending key not restored after preview': [(e, '    [self refreshShortcutConflicts];\n    self.previousItem.key = saved;', '    [self refreshShortcutConflicts];')],
        'accepted macro not recorded as owner (no tooltip for later duplicate)': [(m, '                    self.keyOwners[binding] = @{', '                    if (NO) self.keyOwners[binding] = @{')],
        'hidden Show All Tabs copy takes the command': [(k, '        if (item.action == NSSelectorFromString(@"toggleTabOverview:") && item.hidden && !item.allowsKeyEquivalentWhenHidden) {\n', '        if (NO) {\n')],
        'close ignores a refused save': [(e, 'if (![self autosaveMacroEdits]) return NO;\n', '[self autosaveMacroEdits];\n')],
        'attachedSheet guard removed in windowShouldClose': [(e, '    if (sender == self) return YES;\n    if ([window attachedSheet]) return NO;\n', '    if (sender == self) return YES;\n')],
        'macrosAffectedByRestoringAll empty': [(k, '                [result addObjectsFromArray:[self macrosUsingKey:binding.key modifiers:binding.modifiers]];', '                ;')],
        'applyCapturedShortcut ignores macro confirmation refusal': [(k, '        if (!accepted || strongSelf.layoutChanges != changes) { [strongSelf endRecording]; return; }\n        NSString *error = [strongSelf conflictForCapturedShortcut];', '        NSString *error = [strongSelf conflictForCapturedShortcut];')],
        'beginMenuRebuild does not reapply menu keys': [(k, '    self.rebuildingMacros = YES;\n    [self.store refreshMenu];', '    self.rebuildingMacros = YES;')],
        'matchesItem compares raw strings without A-Z Shift folding': [(k, 'return [TSEventBindings(event, [event charactersByApplyingModifiers:0]) containsObject:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask)];', 'return [TSShortcutCharacterForEvent(event) isEqual:item.keyEquivalent] && (event.modifierFlags & TSShortcutModifiers) == (item.keyEquivalentModifierMask & TSShortcutModifiers);')],
        'restoreAll does not rebuild macros': [(k, '    [self.store restoreAll]; [self refreshMenuAndMacros];\n}', '    [self.store restoreAll];\n}')],
        'removeShortcut does not rebuild macros': [(k, '    [self showError:[self.store setKey:@"" modifiers:0 forCommand:command]];\n    [self refreshMenuAndMacros];', '    [self showError:[self.store setKey:@"" modifiers:0 forCommand:command]];')],
        'recording leaves redundant punctuation Shift': [(k, 'flags &= ~NSEventModifierFlagShift;', 'flags |= NSEventModifierFlagShift;')],
        'engine rebuild leaves settings list stale': [(k, 'if (self.isViewLoaded) { [self reloadCommands]; }', 'if (NO) { [self reloadCommands]; }')],
        'macro rebuild leaves guard set after exception': [(m, '    } @finally {\n        [[TSKeyboardShortcuts sharedController] endMenuRebuild];\n    }', '    } @catch (NSException *exception) { @throw; }\n    [[TSKeyboardShortcuts sharedController] endMenuRebuild];')],
        'validation changes rebuild all macros': [(k, '@[NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification]', '@[NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification, NSMenuDidChangeItemNotification]'), (k, '    if ([[self menuBindingSnapshot] isEqual:self.observedMenuBindings]) return;', ''), (k, 'if (![[self menuBindingSnapshot] isEqual:self.observedMenuBindings]) [self refreshMenuAndMacros];', '[self refreshMenuAndMacros];')],
        'strip Shift from non-ASCII letters': [(k, '![[NSCharacterSet letterCharacterSet] characterIsMember:[key characterAtIndex:0]])\n        flags &= ~NSEventModifierFlagShift;', 'YES)\n        flags &= ~NSEventModifierFlagShift;')],
        'snapshot ignores modifiers': [(k, '@(item.keyEquivalentModifierMask), (action ? NSStringFromSelector', '@0, (action ? NSStringFromSelector')],
        'snapshot ignores key equivalents': [(k, '[bindings addObject:@[[NSValue valueWithNonretainedObject:item], item.keyEquivalent,', '[bindings addObject:@[[NSValue valueWithNonretainedObject:item], @"",')],
        'ignore items whose keys AppKit hides': [(k, 'if (!item.submenu && !item.separatorItem && item.action != TSMacroAction())', 'if (!item.submenu && !item.separatorItem && item.action != TSMacroAction() && (item.keyEquivalent.length || [item.identifier hasPrefix:@"TSShortcut."]))')],
        'PDF drops legacy shifted punctuation': [(k, 'return [TSEventBindings(event, [event charactersByApplyingModifiers:0]) containsObject:', 'return [TSRecordedBinding(event, [event charactersByApplyingModifiers:0]) isEqual:')],
        'keys saved before lose Command': [('MacroKeyProduction.inc', 'NSUInteger mask = [modifiersStr rangeOfString: TSMacroNoCommandKey].location == NSNotFound ? NSEventModifierFlagCommand : 0;', 'NSUInteger mask = 0;')],
        'a shortcut without Command is saved with Command': [('MacroKeyProduction.inc', '\tif (!(modifiers & NSEventModifierFlagCommand))\n\t\t[string appendFormat: @"+%@", TSMacroNoCommandKey];\n', '')],
        'the pending shortcut is not previewed': [(e, '    self.previousItem.key = self.pendingShortcutKey ?: @"";', '    ;')],
        'macro files give Tab and Escape to macros': [(m, 'if (keyEquiv.length && ![TSShortcutStore isAllowedKey:keyEquiv modifiers:modifier]) {', 'if (NO) {')],
        'refused macro keys count as ordinary keys': [(k, '        if (![TSShortcutStore isAllowedKey:binding.key modifiers:binding.modifiers]) {\n            [result addObject:@{@"index":@(index), @"refused":@YES}];', '        if (NO) {\n            [result addObject:@{@"index":@(index), @"refused":@YES}];')],
        'refused keys explained as a conflict': [(k, '    if ([conflict[@"refused"] boolValue])\n        return', '    if (NO)\n        return')],
        'saving reports refused keys as conflicts': [(e, '        if ([conflict[@"refused"] boolValue]) continue;\n', '')],
        'leave Shift for dead keys': [(k, 'key.length == 1 &&\n        ![key isEqual:unshifted]', 'key.length == 1 && unshifted.length == 1 &&\n        ![key isEqual:unshifted]')],
        'hidden Show All Tabs copy is not a command': [(k, '    if (![seen containsObject:@"TSShortcut.toggleTabOverview:.0"] && hiddenTabCopies.count)\n        addCommand(hiddenTabCopies[0], hiddenTabPaths[0]);\n', '')],
        'system commands can be removed': [(k, '            if (!command.managedBySystem) [removable setObject:command.commandID forKey:command.item];', '            if (YES) [removable setObject:command.commandID forKey:command.item];')],
        'Cancel confirms removing a shortcut': [(e, '    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];\n    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];', '    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];\n    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];')],
        'clearing a menu shortcut does not refresh': [(e, '    NSString *error = command ? [store setKey:@"" modifiers:0 forCommand:command] : NSLocalizedString(@"This command is no longer available.", @"");\n    [[TSKeyboardShortcuts sharedController] refreshMenuAndMacros];\n', '    NSString *error = command ? [store setKey:@"" modifiers:0 forCommand:command] : NSLocalizedString(@"This command is no longer available.", @"");\n')],
        'recording still offers Remove': [(e, '    if (self.recordingItem || message.length == 0 || !self.previousItem) return nil;', '    if (message.length == 0 || !self.previousItem) return nil;')],
        'any status text offers Remove': [(e, '    if (!reason.length || ![message isEqualToString:reason]) return nil;', '    if (!reason.length) return nil;')],
        'yielding defaults stay reserved': [(k, '        NSString *commandID = entry[@"commandID"];\n        if (commandID && [TSYieldingDefaultCommands() containsObject:commandID] && !self.overrides[commandID]) continue;\n', '')],
        'removing a menu shortcut leaves the macro unsaved': [(e, '    // The menu key is gone. Write the macro, and ask again only if another conflict remains.\n    reviewPending = NO;\n    [self autosaveMacroEdits];', '    // The menu key is gone. Write the macro, and ask again only if another conflict remains.\n    [self autosaveMacroEdits];')],
        'a failed automatic save asks again': [(e, '\t\tif (coalesceWriteAlerts && reportedWriteFailure) return NO;\n', '')],
        'sent back to editing asks on the next automatic save': [(e, '\t\tif (pending.count) return NO;\n', '')],
        'closing does not ask again': [(e, '    [self reflectChangesInEditor:YES];\n    reviewPending = NO;\n    reportedWriteFailure = NO;\n    if (![self autosaveMacroEdits]) return NO;\n', '    [self reflectChangesInEditor:YES];\n    reportedWriteFailure = NO;\n    if (![self autosaveMacroEdits]) return NO;\n')],
        'Save Anyway does not remember the key': [(e, '\t\t[self rememberOriginalShortcutKeys];\n', '')],
        'close never finishes': [(e, '- (BOOL)windowShouldClose:(id)sender\n{\n    if (sender == self) return YES;\n', '- (BOOL)windowShouldClose:(id)sender\n{\n    return NO;\n    if (sender == self) return YES;\n')],
        'quit does not ask again after Return to Editing': [(e, '    if (!dataTouched) return YES;\n    reviewPending = NO;\n    reportedWriteFailure = NO;\n    return [self autosaveMacroEdits];\n', '    if (!dataTouched) return YES;\n    reportedWriteFailure = NO;\n    return [self autosaveMacroEdits];\n')],
        'closing stays quiet after a write failure': [(e, '    [self reflectChangesInEditor:YES];\n    reviewPending = NO;\n    reportedWriteFailure = NO;\n    if (![self autosaveMacroEdits]) return NO;\n', '    [self reflectChangesInEditor:YES];\n    reviewPending = NO;\n    if (![self autosaveMacroEdits]) return NO;\n')],
        'a successful save leaves the next failure quiet': [(e, '\t\tdataTouched = NO;\n\t\tsaved = YES;\n\t\treportedWriteFailure = NO;\n', '\t\tdataTouched = NO;\n\t\tsaved = YES;\n')],
        'quit notification keeps a displaced key': [(e, '    for (NSDictionary *conflict in changed) {\n        [nodes[[conflict[@"index"] unsignedIntegerValue]] setKey:@""];\n    }\n', '')],
        'applicationShouldTerminate does not ask': [('TSAppDelegate.m', '    if (![[TSMacroEditor sharedInstance] prepareMacrosBeforeTermination])\n        return NSTerminateCancel;\n', '')],
        'pending shortcut is not saved': [(e, '    [self updatePendingShortcutStatus];\n    [self reflectChangesInEditor:YES];\n    [self autosaveMacroEdits];\n', '    [self updatePendingShortcutStatus];\n    [self reflectChangesInEditor:YES];\n')],
        'name edit is not saved': [(e, '\tnameTouched = YES;\n\t[self reflectChangesInEditor: YES];\n\t[self autosaveMacroEdits];\n', '\tnameTouched = YES;\n\t[self reflectChangesInEditor: YES];\n')],
        'content edit is not saved': [(e, '\t\tcontentTouched = NO;\n\t}\n\t[self autosaveMacroEdits];\n', '\t\tcontentTouched = NO;\n\t}\n')],
        'selection change is not saved': [(e, '\t[self endShortcutRecordingUnlessSelected];\n\t[self reflectChangesInEditor: NO];\n\t[self autosaveMacroEdits];\n', '\t[self endShortcutRecordingUnlessSelected];\n\t[self reflectChangesInEditor: NO];\n')],
        'list change is not saved': [(e, '    [self refreshShortcutConflicts];\n\t[self autosaveMacroEdits];\n', '    [self refreshShortcutConflicts];\n')],
    }
    for name, changes in cases.items():
        if "--shift-only" not in sys.argv or name=="ignore Shift on both comparison sides": run_case(name, changes)
for lang in ('en', 'ja'):
    subprocess.run(['plutil', '-lint', str(root / f'Resources/Interfaces/{lang}.lproj/Localizable.strings')], check=True)
