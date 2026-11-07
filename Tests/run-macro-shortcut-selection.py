#!/usr/bin/env python3
"""Compile the production provider and editor entry without opening an editor."""
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[1]
menu=(r/'Sources/TSMacroMenuController.m').read_text()
editor=(r/'Sources/TSMacroEditor.m').read_text()
def method(s,start,end):return s[s.index(start):s.index(end,s.index(start))]
parts={
 'MacroProviderFunction.inc':method(menu,'static void TSCollectShortcutEntries','@implementation TSMacroMenuController'),
 'MacroProviderMethod.inc':method(menu,'- (NSArray<TSShortcutMacro *> *)shortcutEntries','+ (id)sharedInstance'),
 'MacroKeyProduction.inc':menu[menu.index('NSString *getKeyEquivalentFromString('):],
 'MacroSelectionEntry.inc':method(editor,'- (void)openMacroEditorSelectingMacroAtIndexPath:','- (IBAction)openMacroEditor:')}
with tempfile.TemporaryDirectory(prefix='texshop-macro-selection-') as td:
 p=Path(td)
 for name,s in parts.items():(p/name).write_text(s)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-incomplete-implementation','-Wno-deprecated-declarations','-Wno-nullability-completeness','-I',str(p),'-I',str(r/'Sources'),'-framework','Cocoa','-framework','Carbon',str(r/'Tests/MacroShortcutSelection.m'),str(r/'Sources/TSMacroTreeNode.m'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True,timeout=20)
