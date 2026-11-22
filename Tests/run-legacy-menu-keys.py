#!/usr/bin/env python3
"""Exercise the legacy menu compatibility path in memory without loading user files."""
from pathlib import Path
import subprocess,tempfile
from source_tree import include_args
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-legacy-menu-') as td:
 p=Path(td)/'probe'
 source=(r/'Sources/App/TSAppDelegate.m').read_text(encoding='latin1');start=source.index('- (void)finishMenuKeyEquivalentsConfigure\n');method=source[start:source.index('\n}',start)+2]
 method=method.replace('[NSDictionary dictionaryWithContentsOfFile:path]','FixtureEntries(path)')
 # The restoring of a missing file is left out: it would reach the real ~/Library/TeXShop (run-library-repair.py covers it).
 repair='    TSLibraryRestoreMissingFile(path, TSLibraryBundledPath(@"Menus/KeyEquivalents.plist"), TSLibraryDictionaryCheck());\n'
 assert method.count(repair)==1
 method=method.replace(repair,'')
 assert 'dictionaryWithContentsOfFile' not in method
 program=(r/'Tests/LegacyMenuKeys.m').read_text().replace('// APPLICATION_ENTRY',method)
 test=Path(td)/'test.m';test.write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Wno-unused-parameter','-Werror',*include_args(r),'-I',str(r/'Tests'),'-framework','Cocoa',str(test),'-o',str(p)],check=True)
 # The Edit menu of 5.58 (db040b9b), as the actions at its positions, beside the compiled menu of now.
 import json,xml.etree.ElementTree as ET0
 # The title of Fullscreen (Old Method) in each language of 6.00 beta 8 (tag v.6.00-beta.8).
 BETA8_FULLSCREEN={'Base':'Fullscreen (Old Method)','de':'Vollbild','es':'Pantalla completa','fr':'Plein écran','it':'Schermo Intero','ja':'フルスクリーン表示',
  'ko':'전체 화면 (옛날방식)','nl':'Fullscreen','pt-PT':'Fullscreen','pt':'Tela cheia','ro':'Fullscreen','zh_CN':'全屏幕'}
 edits={}
 for nib in sorted((r/'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects.nib')):
  language=nib.parent.parent.name[:-6]
  xml=subprocess.check_output(['git','show',f'db040b9b:Resources/Interfaces/{language}.lproj/MainMenu.nib/designable.nib'],cwd=r)
  root=ET0.fromstring(xml);actions=None
  for menu in root.iter('menu'):
   items=menu.find('items')
   if items is not None and any(a.get('selector')=='undo:' for a in items.iter('action')) and menu.find("items/menuItem/connections/action[@selector='undo:']") is not None:
    actions=[]
    for item in items:
     sub=item.find('menu/items/menuItem/connections/action');own=item.find('connections/action')
     actions.append(sub.get('selector') if sub is not None else own.get('selector') if own is not None else '')
  assert actions,language;edits[language]={'nib':str(nib),'actions':actions}
  # The Window menu of 5.58, whose third item was Fullscreen (Old Method), removed in 6.00.
  window=[m for m in root.iter('menu') if m.find("items/menuItem/connections/action[@selector='toggleFullScreen:']") is not None]
  assert len(window)==1,language
  edits[language]['window']=[(i.find('connections/action').get('selector') if i.find('connections/action') is not None else '') for i in window[0].find('items')]
  assert 'fullscreen:' in edits[language]['window'],language
  # The name Fullscreen (Old Method) had in this language in 5.58, which a KeyEquivalents.plist may still use.
  former=[i.get('title') for i in root.iter('menuItem') if i.find("connections/action[@selector='fullscreen:']") is not None]
  assert len(former)==1,language;edits[language]['fullscreen']=former[0]
  # Its name in 6.00 beta 8, the last version that had it (written here: TetsuTeXShop has no tags of TeXShop).
  edits[language]['fullscreen600b8']=BETA8_FULLSCREEN[language]
 # The Help menu of 5.58 and of 6.00 beta 9 (6b0e2342): the names of George Grätzer's Short Course, its symbol tables and
 # TeXShop Feature Confusion, which a KeyEquivalents.plist may use, and the actions at the positions of 5.58.
 for language in edits:
  former={}
  for commit in ('db040b9b','6b0e2342'):
   root=ET0.fromstring(subprocess.check_output(['git','show',f'{commit}:Resources/Interfaces/{language}.lproj/MainMenu.nib/designable.nib'],cwd=r))
   for item in root.iter('menuItem'):
    own=item.find('connections/action')
    if own is not None and own.get('selector') in ('displayShortCourse:','displayTables:','displayTeXShopConfusion:'):
     former.setdefault(own.get('selector'),[])
     if item.get('title') not in former[own.get('selector')]:former[own.get('selector')].append(item.get('title'))
   if commit=='db040b9b':
    help=[m for m in root.iter('menu') if m.find("items/menuItem/connections/action[@selector='displayManual:']") is not None]
    assert len(help)==1,language
    edits[language]['helpactions']=[(i.find('connections/action').get('selector') if i.find('connections/action') is not None else '') for i in help[0].find('items')]
  assert all(len(former.get(s,[]))>=1 for s in ('displayShortCourse:','displayTables:','displayTeXShopConfusion:')),(language,former)
  edits[language]['helpformer']=former
 assert len(edits)==12
 (Path(td)/'edits.json').write_text(json.dumps(edits))
 subprocess.run([str(p),str(r/'Tests/Fixtures/LegacyKeyBindingTitles.json'),str(Path(td)/'edits.json')],check=True)
# The compatibility for the Open Style File move assumes, in every language, that the item
# follows Open in the File menu and that Show Help for Package is still in the Help menu.
import xml.etree.ElementTree as ET
for nib in sorted((r/'Resources/Interfaces').glob('*.lproj/MainMenu.nib/designable.nib')):
 root=ET.parse(nib).getroot();parent={c:p for p in root.iter() for c in p}
 def item(identifier):
  found=[e for e in root.iter('menuItem') if e.get('identifier')==identifier];assert len(found)==1,(nib,identifier);return found[0]
 style,opened,package=item('TSShortcut.displayStyleFile:.0'),item('TSShortcut.openDocument:.0'),item('TSShortcut.displayHelpForPackage:.0')
 siblings=[e for e in parent[style] if e.tag=='menuItem']
 assert parent[style] is parent[opened] and siblings.index(style)==siblings.index(opened)+1,(nib,'Open Style File follows Open')
 assert parent[package] is not parent[style],(nib,'Show Help for Package stays in another menu')
print('PASS: 12 MainMenu files keep Open Style File after Open and Show Help for Package in Help')
# Positions saved for Source › Command Completion reach Add to Command Completion List
# because the command took the submenu's place, right after Key Bindings.
for nib in sorted((r/'Resources/Interfaces').glob('*.lproj/MainMenu.nib/designable.nib')):
 root=ET.parse(nib).getroot();parent={c:p for p in root.iter() for c in p}
 found=[e for e in root.iter('menuItem') if e.get('identifier')=='TSShortcut.registerForCommandCompletion:.0'];assert len(found)==1,nib
 completion=found[0];siblings=[e for e in parent[completion] if e.tag=='menuItem']
 assert completion.find('menu') is None and siblings[siblings.index(completion)-1].get('identifier')=='TSShortcut.changeAutoComplete:.0',(nib,'Add to Command Completion List follows Key Bindings')
print('PASS: 12 MainMenu files have Add to Command Completion List in place of the Command Completion submenu')
