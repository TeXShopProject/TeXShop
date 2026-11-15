#!/usr/bin/env python3
"""Check the macro editor's layout (the sidebar, the contents, the status band and the placeholder row), its keys, the
renaming of items in its list and the recording of a shortcut in the list's own cell, with its warnings, against all
localized macro-editor nibs without showing windows. With a directory, writes the window's images there: as it opens,
an item renamed, the contents focused, a shortcut recorded in the list, a key refused there because another macro uses
it or because it cannot be a shortcut, a saved shortcut that is inactive selected, larger and smallest, light and
dark."""
from pathlib import Path
import os, subprocess, tempfile, sys
from source_tree import include_args
from macro_editor_sources import write_sources, layout_body, FRAMEWORKS
root=Path(__file__).resolve().parents[1]
body=layout_body(root)
# What the harness does not run: closing the window removes the key monitor, and the list draws its separators
# with TSMacroSeparatorImage, not the old groove image.
editor=(root/'Sources/Macros/TSMacroEditor.m').read_text()
closing=editor[editor.index('- (void) windowWillClose:'):]
closing=closing[:closing.index('\n}\n')]
assert '[self releaseWindowControls];' in closing, 'closing the editor lets go of the controls of its window and of its key monitor'
outline=(root/'Sources/Macros/TSMacroOutlineController.m').read_text()
assert 'setImage1: TSMacroSeparatorImage(' in outline and 'imageNamed: SEPARATOR_IMAGE' not in outline, 'separators are drawn as lines'
# Command-S saves the macros, and a double click runs a macro and opens or closes a submenu (the harness does not build these).
def method(text,signature):
    body=text[text.index(signature):]
    return body[:body.index('\n}\n')]
assert '[self savePressed:sender];' in method(editor,'- (IBAction)saveDocument:(id)sender'), 'Command-S saves'
# The list sends a click to listClicked: and a double click to listDoubleClicked: (the harness sends them as the list does).
assert '[outlineView setAction: @selector(listClicked:)];' in editor and '[outlineView setDoubleAction: @selector(listDoubleClicked:)];' in editor, 'the list sends its clicks to the editor'
# Another selection ends a recording before the fields take the new item, and changed items end it (the harness's
# stand-ins for the selection and the items do the same).
assert method(editor,'- (void)outlineViewSelectionChanged: (NSNotification *)note').split('\n')[2].strip()=='[self endShortcutRecordingUnlessSelected];', 'another selection ends a recording'
assert '[self endShortcutRecording];' in method(editor,'- (void)outlineViewItemsChanged: (NSNotification *)note'), 'changed items end a recording'
# The conflicts sheet's Return to Editing records the shortcut of the item it selects.
assert '[self beginRecordingShortcutForItem:node];' in method(editor,'- (BOOL)validateMacroShortcutsBeforeSaving'), 'Return to Editing records the shortcut'
assert 'TSMacroUseShortcutCell(outlineView);' in method(outline,'- (void)awakeFromNib'), 'the list shows its shortcuts in its own cells'
def write_editor(td,text):
    """The editor's layout, recording and message (MacroStatusLayout.inc) and its double click, as the harness includes them."""
    (Path(td)/'MacroStatusLayout.inc').write_text(text[text.index('- (void)installShortcutStatus'):text.index('- (void)updatePendingShortcutStatus')])
    (Path(td)/'MacroListDoubleClick.inc').write_text(method(text,'- (void)listDoubleClicked:(id)sender')+'\n}\n')
def write_outline(td,text):
    """The outline controller's cells and editing of a name, and the list with its cells, as the harness includes them."""
    start='// The name typed when an item is renamed in the list.'
    (Path(td)/'MacroOutlineEditing.inc').write_text(text[text.index(start):text.index('// A name typed in the list is filtered')])
    cells=text[text.index('- (id)outlineView:(NSOutlineView *)olv objectValueForTableColumn:'):text.index('// Optional method: needed to allow editing.')]
    display=text[text.index('- (void)outlineView: (NSOutlineView *)olv willDisplayCell:'):text.index('// ================================================================\n//  NSOutlineView data source methods. (dragging related)')]
    (Path(td)/'MacroOutlineCells.inc').write_text(cells+display)
    (Path(td)/'MacroOutlineView.inc').write_text(text[text.index('@implementation NSOutlineView (MyExtensions)'):])
    # How ＋ and the menu add an item, a submenu or a separator after the selection, and select it.
    (Path(td)/'MacroOutlineAdding.inc').write_text(text[text.index('- (NSArray *)selectedNodes'):text.index('- (void)addNewDataArrayToSelection')])
STATES=('opened','renaming','contents','recording','refused','invalid','conflict','resized','smallest')
with tempfile.TemporaryDirectory(prefix='texshop-macro-layout-') as td:
    mutation='--mutations' in sys.argv
    extra=write_sources(root,td,'MacroStatusLayout.inc')
    write_editor(td,editor)
    write_outline(td,outline)
    binary=Path(td)/'layout'
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-Wno-deprecated-declarations','-Wno-nullability-completeness',*FRAMEWORKS,'-I',td,'-I',str(root/'Tests'),*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),*extra,'-o',str(binary)],check=True)
    for path in sorted((root/'Resources/Interfaces').glob('*.lproj/MacroEditor.nib/keyedobjects*.nib')):
        # The language's own strings, as the application shows them (Base is English).
        lproj=path.parts[-3]
        strings=root/'Resources/Interfaces'/('en.lproj' if lproj=='Base.lproj' else lproj)/'Localizable.strings'
        env=dict(os.environ,TS_STRINGS=str(strings)) if strings.exists() else dict(os.environ)
        subprocess.run([str(binary),str(path)],check=True,env=env)
        # With a directory, the images of every nib go there (TS_RENDER_DIR), each drawn in a run of its own.
        if len(sys.argv)>1 and sys.argv[1]!='--mutations':
            for state in STATES:
                for mode in ('light','dark'):
                    subprocess.run([str(binary),str(path)],check=True,stdout=subprocess.DEVNULL,
                                   env=dict(env,TS_RENDER_DIR=str(Path(sys.argv[1]).resolve()),TS_RENDER_ONLY=f'{state}-{mode}'))
    if mutation:
        cases={
            'grow window above its saved top edge': ('windowFrame.origin.y -= minimum.height - NSHeight(windowFrame);', ''),
            'frame growth on reopening': ('    if (self.shortcutStatus) return;', '    if (self.shortcutStatus) return; NSRect f=[window frame]; f.size.height+=60; [window setFrame:f display:NO];'),
            'editors extend beyond window': ('frame.origin.y += height; frame.size.height -= height;', 'frame.origin.y += height;'),
            'controls overlap status band': ('} else if (NSMinY(frame) < editorBottom) frame.origin.y += height;', '}'),
            'minimum height excludes status band': ('minimum.height += height;', ''),
            'restored small window stays too small': ('if (NSHeight(windowFrame) < minimum.height)', 'if (NO)'),
            'the list keeps its headings': ('    rows.headerView = nil;\n', ''),
            'the names take a fixed width': ('    rows.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;', '    rows.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;'),
            'the first row is higher than the sets\'': ('    list.contentInsets = NSEdgeInsetsMake(5, 0, 0, 0);\n', ''),
            'the fields keep the nib\'s margin from the list': ('    CGFloat shift = NSMinX([nameField frame]) - TSDialogMargin;', '    CGFloat shift = NSMinX([nameField frame]) - 2 * TSDialogMargin;'),
            'the buttons do not hold the narrowest window': ('                            TSDialogButtonsWidth(@[saveButton, cancelButton], @[testButton]));', '                            0);'),
            'a reopened window keeps the closed one\'s sidebar': ('    self.sidebar = nil; self.listBar = nil; self.editorView = nil;\n', ''),
            'Return in the contents saves': ('    [editor sendEvent:event];\n    return nil;\n', '    return event;\n'),
            'Escape does not cancel': ('    cancelButton.keyEquivalent = @"\\033";\n', ''),
            'Save is not the default button': ('    saveButton.keyEquivalent = @"\\r";\n', ''),
            'zh_CN.lproj: a font the nib names stays': ('        if (font == nil || [font.fontName hasPrefix:@"."]) continue;', '        continue;'),
            'the buttons keep the nib\'s height': ('        frame.size.height = button.fittingSize.height;\n', ''),
            'the window loses its minimum height': ('    editor.minSize = NSMakeSize(TSListSidebarMinimumWidth + split.splitView.dividerThickness + narrowest, minimumHeight);', '    editor.minSize = NSMakeSize(TSListSidebarMinimumWidth + split.splitView.dividerThickness + narrowest, 0);'),
            'typing keys become shortcuts': ('    if (binding.key.length != 1 || ![TSShortcutStore isAllowedKey:binding.key modifiers:binding.modifiers]) {', '    if (binding.key.length != 1) {'),
            'Return in the list does not rename': ('        if (![self beginRenamingSelectedItem]) NSBeep();\n        return nil;\n', '        return event;\n'),
            'Escape while renaming closes the window': ('        if (escape) [outlineView abortEditing];\n', '        if (escape) return event;\n'),
            'Escape in the list cancels': ('        if (escape) return nil;\n', '        if (escape) return event;\n'),
            'a separator is renamed': ('![item isKindOfClass:TSMacroTreeNode.class] || item.isSeparator) return NO;', '![item isKindOfClass:TSMacroTreeNode.class]) return NO;'),
            'the contents keep a margin from the sidebar': ('        contents.frame = NSMakeRect(0, NSMaxY(line), width, NSHeight(main.bounds) - NSMaxY(line));', '        contents.frame = NSMakeRect(TSDialogMargin, NSMaxY(line), width - TSDialogMargin, NSHeight(main.bounds) - NSMaxY(line));'),
            'the contents stop below the title bar': ('        contents.frame = NSMakeRect(0, NSMaxY(line), width, NSHeight(main.bounds) - NSMaxY(line));', '        contents.frame = NSMakeRect(0, NSMaxY(line), width, NSHeight(main.bounds) - NSMaxY(line) - 20);'),
            'the name\'s label stays': ('            view.hidden = YES;\n        }\n', '        }\n'),
            'the smallest window keeps the name field\'s height': ('    CGFloat minimumHeight = editor.minSize.height - MAX(0, taller);', '    CGFloat minimumHeight = editor.minSize.height;'),
            'a new item is not named at once': ('    TSSendButtonAction(newItemButton);\n    [self beginRenamingSelectedItem];\n', '    TSSendButtonAction(newItemButton);\n'),
            'a key after a second click still renames': ('    [self cancelPendingListRename];\n    if (event.modifierFlags', '    if (event.modifierFlags'),
            'closing keeps a pending renaming': ('    [self cancelPendingListRename];\n    [self stopKeyMonitor];', '    [self stopKeyMonitor];'),
            'the contents stop above the shortcut\'s rows': ('    if (NSMinY(frame) > bottom) { frame.size.height += NSMinY(frame) - bottom; frame.origin.y = bottom; }\n', ''),
            # Recording a shortcut in the list.
            'a click on an item not selected records': ('    if (row < 0 || row != rows.rowSelectedAtMouseDown || [rows clickedColumn]', '    if (row < 0 || [rows clickedColumn]'),
            'a click on a name records': ('    if (row < 0 || row != rows.rowSelectedAtMouseDown || [rows clickedColumn] != [rows columnWithIdentifier:@"Key"]) return;', '    if (row < 0 || row != rows.rowSelectedAtMouseDown) return;'),
            'a double click on a name records': ('\tif ([item isStandardItem] && [outlineView clickedColumn] == [outlineView columnWithIdentifier:@"Key"]) {', '\tif ([item isStandardItem]) {'),
            'a double click on a shortcut tests': ('\tif ([item isStandardItem] && [outlineView clickedColumn] == [outlineView columnWithIdentifier:@"Key"]) {', '\tif (NO) {'),
            'keys go to the menus and the buttons while recording': ('    if (self.recordingItem && responder == self.recordingCell.recorder) {\n        [self handleShortcutRecordingEvent:event];\n        return nil;\n    }\n', ''),
            'Escape while recording cancels the window': ('    if (!flags && (c == 27 || c == \'\\r\' || c == 3)) { [self endShortcutRecording]; return; }', '    if (!flags && (c == \'\\r\' || c == 3)) { [self endShortcutRecording]; return; }'),
            'a key another command uses ends the recording': ('        self.refusedShortcut = getMenuItemString(shortcut);\n        [self showShortcutRecordingError:conflict];\n        return NO;', '        [self endShortcutRecording];\n        return NO;'),
            'the keys of other macros are taken': ('            if (path && nodes[index] != self.recordingItem && [TSBinding(', '            if (NO && [TSBinding('),
            'the keys of menu commands are taken': ('            if (!match.menuItem.hidden || match.menuItem.allowsKeyEquivalentWhenHidden) [users addObject:match.path];', '            ;'),
            'the keys of hidden menu commands are refused': ('            if (!match.menuItem.hidden || match.menuItem.allowsKeyEquivalentWhenHidden) [users addObject:match.path];', '            [users addObject:match.path];'),
            'the refusal is not below the contents': ('    NSString *message = self.recordingItem ? self.recordingError : nil;', '    NSString *message = nil;'),
            'the refused cell has no triangle': ('    self.recordingCell.warning.hidden = self.recordingError == nil;', '    self.recordingCell.warning.hidden = YES;'),
            'the message has no triangle': ('    self.shortcutStatusMark.hidden = message.length == 0;', '    self.shortcutStatusMark.hidden = YES;'),
            'a refused key is not shown in the field': ('    self.recordingCell.recorder.shortcut = self.refusedShortcut ?: getMenuItemString(current);', '    self.recordingCell.recorder.shortcut = getMenuItemString(current);'),
            'a key that cannot be one is not shown in the field': ('        self.refusedShortcut = binding.key.length ? TSShortcutDisplayKey(binding.key, binding.modifiers) : nil;', '        self.refusedShortcut = nil;'),
            'a submenu records': ('    if (![item isKindOfClass:TSMacroTreeNode.class] || !item.isStandardItem || recorder == nil', '    if (![item isKindOfClass:TSMacroTreeNode.class] || recorder == nil'),
            'the field stays after a click elsewhere': ('            if (strongSelf != nil && strongSelf.recordingItem != item) [strongSelf removeShortcutRecorderOfItem:item];', '            (void)strongSelf;'),
            'closing keeps recording': ('    [self stopKeyMonitor];\n    [self endShortcutRecording];\n', '    [self stopKeyMonitor];\n'),
        }
        # Mutations of the sidebar shared with the Multiple Replace window.
        file_cases={
            'TSListBottomBar.m': {
                'the sidebar stops above the bottom edge': ('        [bar.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],', '        [bar.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-20],'),
                'the window\'s contents stay below the title bar': ('        window.styleMask |= NSWindowStyleMaskFullSizeContentView;', '        (void)0;'),
            },
        }
        # Mutations of the list: the outline controller's editing of a name and the list's cells (TSMacroOutlineController.m).
        outline_cases={
            'a click after the name renames': ('\treturn point.x <= NSMinX(frame) + MIN(NSWidth(frame), name + 4) + 2;', '\treturn YES;'),
            'a name of spaces replaces the old one': ('\tif ([name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) return;\n', ''),
            'the renamed name takes the whole column': ('\ttextFrame.size.width = MIN(NSWidth(textFrame), TSNameEditingWidth(self.stringValue, self.font));\n\t[super selectWithFrame:', '\t[super selectWithFrame:'),
            'the renamed name\'s field does not grow': ('\tclip.frame = frame;\n', ''),
            'a pending renaming is not cancelled': ('\t[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(renameAfterClick) object:nil];\n\tself.pendingRename = nil;\n', '\t[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(renameAfterClick) object:@0];\n'),
            'another selection keeps a pending renaming': ('\t[self cancelPendingRename];\n\t[super selectRowIndexes:', '\t[super selectRowIndexes:'),
            'a double click keeps a pending renaming': ('\t[self cancelPendingRename];\n\tNSPoint point', '\tNSPoint point'),
            'a double click edits the name': ('\treturn [[TSMacroEditor sharedInstance] isRenaming] && ', '\treturn YES && '),
            # The list's part in recording a shortcut, and the triangle of an inactive one.
            'the cell under the field shows the shortcut': ('\t\tobjectValue = item == [[TSMacroEditor sharedInstance] recordingItem] ? @"" : ', '\t\tobjectValue = '),
            'an inactive shortcut has no triangle': ('\t\t\t((TSMacroShortcutCell *)cell).showsWarning = conflict != nil && item != [[TSMacroEditor sharedInstance] recordingItem];', '\t\t\t((TSMacroShortcutCell *)cell).showsWarning = NO;'),
            'the field is only as wide as the shortcut\'s cell': ('\tCGFloat width = MAX(NSWidth(cell), MIN(self.recordingWidth, NSMaxX(cell) - leading));', '\tCGFloat width = NSWidth(cell);'),
            'the field stays where the row was when the list is resized': ('\t[super tile];\n\t[self placeRecordingView];\n}\n\n- (void)setFrameSize:(NSSize)size\n{\n\t[super setFrameSize:size];\n\t[self placeRecordingView];\n}', '\t[super tile];\n}\n\n- (void)setFrameSize:(NSSize)size\n{\n\t[super setFrameSize:size];\n}'),
            'the row selected when the mouse went down is not kept': ('\tself.rowSelectedAtMouseDown = modifiers == 0 && self.numberOfSelectedRows == 1 ? self.selectedRow : -1;\n', ''),
            'VoiceOver presses a submenu\'s shortcut': ('\tif (selector == @selector(accessibilityPerformPress)) return [self.representedObject isKindOfClass:TSMacroTreeNode.class] && [self.representedObject isStandardItem];', '\tif (selector == @selector(accessibilityPerformPress)) return YES;'),
        }
        originals={name:Path(next(x for x in extra if x.endswith('/'+name))) for name in file_cases}
        for name,changed,(before,after) in [*((k,None,v) for k,v in cases.items()),*((f'{f}: {k}',f,v) for f,c in file_cases.items() for k,v in c.items()),*((f'TSMacroOutlineController.m: {k}','outline',v) for k,v in outline_cases.items())]:
            text=outline if changed=='outline' else originals[changed].read_text() if changed else editor
            assert text.count(before)==1,name
            write_editor(td,editor if changed else editor.replace(before,after))
            write_outline(td,text.replace(before,after) if changed=='outline' else outline)
            sources=list(extra)
            if changed and changed!='outline':
                mutated=Path(td)/changed
                mutated.write_text(text.replace(before,after))
                sources=[str(mutated) if x.endswith('/'+changed) else x for x in extra]
            subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-Wno-deprecated-declarations','-Wno-nullability-completeness',*FRAMEWORKS,'-I',td,'-I',str(root/'Tests'),*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),*sources,'-o',str(binary)],check=True)
            # A mutation named after a localization runs on that nib.
            lproj=name.split(':')[0] if name.split(':')[0].endswith('.lproj') else 'Base.lproj'
            # The nib AppKit reads: keyedobjects-101300.nib where there is one.
            nibs=root/'Resources/Interfaces'/lproj/'MacroEditor.nib'
            nib=nibs/'keyedobjects-101300.nib' if (nibs/'keyedobjects-101300.nib').exists() else nibs/'keyedobjects.nib'
            result=subprocess.run([str(binary),str(nib)],capture_output=True,text=True)
            assert result.returncode and 'FAIL ' in result.stderr,(name,result.stderr)
            print('DETECTED:',name,result.stderr.strip())

        # Removing the Portuguese minimum size must fail the old-small-frame restoration case.
        write_editor(td,editor); write_outline(td,outline)
        subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-Wno-deprecated-declarations','-Wno-nullability-completeness',*FRAMEWORKS,'-I',td,'-I',str(root/'Tests'),*include_args(root),str(root/'Tests/MacroShortcutLayout.m'),*extra,'-o',str(binary)],check=True)
        nibSource=(root/'Resources/Interfaces/pt.lproj/MacroEditor.nib/designable.nib').read_text()
        minimum='<string key="NSMinSize">{270, 272}</string>'
        assert nibSource.count(minimum)==1
        altered=Path(td)/'MacroEditor.xib'; altered.write_text(nibSource.replace(minimum,''))
        nib=Path(td)/'MacroEditor.nib'
        subprocess.run(['xcrun','ibtool','--compile',str(nib),str(altered)],check=True,capture_output=True)
        result=subprocess.run([str(binary),str(nib/'keyedobjects.nib')],capture_output=True,text=True)
        assert result.returncode and 'FAIL ' in result.stderr,result.stderr
        print('DETECTED: Portuguese window has no usable minimum size',result.stderr.strip())
