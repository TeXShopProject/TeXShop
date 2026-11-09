#!/usr/bin/env python3
"""Exercise production shortcut settings with memory defaults and unordered windows."""
from pathlib import Path
from shortcut_sources import production_source, companion_sources
import subprocess,tempfile,json,sys,re
r=Path(__file__).resolve().parents[1]
expected_failures={'search-both-shift': '[TSShortcutSearch matchesKey:@"x" modifiers:(macroFlags.unsignedIntegerValue^S) store:coordinator.store macros:shiftMacros].count==0', 'raw-macro-shift': 'winners==1 && [actual isEqual:c[@"winner"]] && macroIndex==macros.count', 'hidden-menu': '[TSShortcutSearch matchesKey:@"h" modifiers:C store:hiddenStore macros:@[]].count==0', 'empty-initial-list': 'translated.searchEvent==nil && translated.table.numberOfRows==(NSInteger)translated.store.settingsSearchCommandNames.count', 'modifier-only-event': 'Modifier-only events must not reach character translation'}
with tempfile.TemporaryDirectory(prefix='texshop-shortcut-pane-') as td:
 p=Path(td)
 (p/'TSKeyboardShortcuts.m').write_text(production_source(r))
 translations={f.parent.name:json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(f)])) for f in (r/'Resources/Interfaces').glob('*.lproj/Localizable.strings')}
 (p/'translations.json').write_text(json.dumps(translations))
 subprocess.run(['xcrun','ibtool','--compile',str(p/'SettingsWindow.nib'),str(r/'Resources/SettingsWindow.xib')],check=True)
 command=['xcrun','clang','-fobjc-arc','-Wno-deprecated-declarations','-Wno-nullability-completeness','-mmacosx-version-min=14.6','-I',str(p),'-I',str(r/'Tests'),'-I',str(r/'Sources'),'-framework','Cocoa','-framework','Carbon',str(r/'Tests/ShortcutPane.m'),*[str(f) for f in sorted((r/'Sources').glob('TSSettings*.m'))],*companion_sources(r),str(r/'Sources/TSPreferenceProfile.m'),str(r/'Sources/globals.m'),str(r/'Sources/TSMacroTreeNode.m'),'-o',str(p/'test')]
 def run():
  subprocess.run(command,check=True)
  return subprocess.run([str(p/'test'),str(p/'SettingsWindow.nib'),str(p/'translations.json')],capture_output=True,text=True,timeout=60)
 result=run();print(result.stdout,flush=True);assert result.returncode==0,result.stderr
 original=production_source(r)
 # Mandatory raw-macro Shift mutation: never use AppKit synthetic JIS dispatch as an oracle.
 mutations=[('search-both-shift','TSShortcutBinding *binding = TSBinding(key, flags);\n    [macros enumerateObjectsUsingBlock:', 'TSShortcutBinding *binding = TSBinding(key, flags & ~NSEventModifierFlagShift);\n    [macros enumerateObjectsUsingBlock:'),('raw-macro-shift','TSBinding(macro.key, macro.modifiers) isEqual:binding','TSBinding(macro.key, macro.modifiers & ~NSEventModifierFlagShift) isEqual:binding')]
 if '--mutations' in sys.argv:
  mutations += [('hidden-menu','if (match.menuItem.hidden && !match.menuItem.allowsKeyEquivalentWhenHidden) continue;',';'),('empty-initial-list','self.searchingByKey && self.searchEvent != nil ? (NSInteger)self.searchMatches.count','self.searchingByKey ? (NSInteger)self.searchMatches.count'),('modifier-only-event','if (event.type != NSEventTypeKeyDown) { return YES; }',';')]
 for name,old,new in mutations:
  assert original.count(old)==1,(name,original.count(old));changed=original.replace(old,new)
  if name=='search-both-shift':changed=changed.replace('TSBinding(macro.key, macro.modifiers) isEqual:binding','TSBinding(macro.key, macro.modifiers & ~NSEventModifierFlagShift) isEqual:binding')
  (p/'TSKeyboardShortcuts.m').write_text(changed);result=run()
  assert result.returncode and re.search(r'FAIL(?: \d+)?: '+re.escape(expected_failures[name]),result.stderr),(name,result.stderr);print('DETECTED',name,result.stderr.strip(),flush=True)
 (p/'TSKeyboardShortcuts.m').write_text(original);result=run();assert result.returncode==0,result.stderr;print('NORMAL CONTROL',result.stdout,flush=True)
