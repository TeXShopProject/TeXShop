#!/usr/bin/env python3
"""Check the macro editor's layout (the sidebar, the contents, the status band, the shortcut field and the placeholder
row), its keys and the renaming of items in its list against all localized macro-editor nibs without showing windows.
With a directory, writes the window's images there: as it opens, an item renamed, the contents focused, the shortcut
field waiting for keys, larger and smallest, light and dark."""
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
double=method(editor,'- (void)listDoubleClicked:(id)sender')
assert '[outlineView setDoubleAction: @selector(listDoubleClicked:)];' in editor and '[self doMacroTest:sender];' in double and 'isStandardItem' in double and 'expandItem:item' in double and 'collapseItem:item' in double, 'a double click tests a macro and opens or closes a submenu'
def write_outline(td,text):
    """The outline controller's editing of a name, and the list with its cells, as the harness includes them."""
    start='// The name typed when an item is renamed in the list.'
    (Path(td)/'MacroOutlineEditing.inc').write_text(text[text.index(start):text.index('// A name typed in the list is filtered')])
    (Path(td)/'MacroOutlineView.inc').write_text(text[text.index('@implementation NSOutlineView (MyExtensions)'):])
    # How ＋ and the menu add an item, a submenu or a separator after the selection, and select it.
    (Path(td)/'MacroOutlineAdding.inc').write_text(text[text.index('- (NSArray *)selectedNodes'):text.index('- (void)addNewDataArrayToSelection')])
STATES=('opened','renaming','contents','recording','resized','smallest')
with tempfile.TemporaryDirectory(prefix='texshop-macro-layout-') as td:
    mutation='--mutations' in sys.argv
    extra=write_sources(root,td,'MacroStatusLayout.inc')
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
            'the shortcut field takes typing keys': ('if (binding.key.length != 1 || ![TSShortcutStore isAllowedKey:binding.key modifiers:binding.modifiers]) return NO;', 'if (binding.key.length != 1) return NO;'),
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
            'the contents overlap the shortcut row': ('    CGFloat gap = MAX(8, NSMinY(contentsFrame) - NSMaxY([keyField frame]));', '    CGFloat gap = MIN(8, NSMinY(contentsFrame) - NSMaxY([keyField frame])) - 12;'),
        }
        # Mutations of the shortcut field and of the sidebar shared with the Multiple Replace window.
        file_cases={
            'TSMacroShortcutField.m': {
                'Escape does not end the waiting': ('    if (c == 27 && !flags) {\n        [self endRecording];\n        return YES;\n    }\n', ''),
                '⊗ shows without a shortcut': ('self.clearButton.hidden = !(self.enabled && self.shortcut.length > 0);', 'self.clearButton.hidden = !self.enabled;'),
            },
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
        }
        originals={name:Path(next(x for x in extra if x.endswith('/'+name))) for name in file_cases}
        for name,changed,(before,after) in [*((k,None,v) for k,v in cases.items()),*((f'{f}: {k}',f,v) for f,c in file_cases.items() for k,v in c.items()),*((f'TSMacroOutlineController.m: {k}','outline',v) for k,v in outline_cases.items())]:
            text=outline if changed=='outline' else originals[changed].read_text() if changed else body
            assert text.count(before)==1,name
            (Path(td)/'MacroStatusLayout.inc').write_text(body if changed else body.replace(before,after))
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
        (Path(td)/'MacroStatusLayout.inc').write_text(body); write_outline(td,outline)
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
