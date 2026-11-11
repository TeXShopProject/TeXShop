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
 assert 'dictionaryWithContentsOfFile' not in method
 program=(r/'Tests/LegacyMenuKeys.m').read_text().replace('// APPLICATION_ENTRY',method)
 test=Path(td)/'test.m';test.write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Wno-unused-parameter','-Werror',*include_args(r),'-I',str(r/'Tests'),'-framework','Cocoa',str(test),'-o',str(p)],check=True)
 subprocess.run([str(p),str(r/'Tests/Fixtures/LegacyKeyBindingTitles.json')],check=True)
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
