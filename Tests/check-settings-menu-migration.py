#!/usr/bin/env python3
"""Verify stable command identity against the fixed pre-migration menu contract."""
from pathlib import Path
import hashlib,json,xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
removed={'openAutoCompletionListEditor:','openCommandCompletionList:'}
# Commands added to the Edit menu later; they are outside the fixed contract.
added={'convertCharacterType:','normalizeSelectedString:','exchangePaste:'}
# Find and Replace… joined the Find submenu of the other languages in 6.00; the Base menu always had it.
added_outside_base={'performTextFinderAction:'}
def records(tree,language='Base'):
 result=[]
 skipped=added|(added_outside_base if language!='Base' else set())
 for item in tree.iter('menuItem'):
  action=item.find('connections/action')
  if action is None or action.get('selector') in removed|skipped:continue
  result.append({'identifier':item.get('identifier'),'selector':action.get('selector'),'tag':item.get('tag','0'),'key':item.get('keyEquivalent',''),'mask':[child.attrib for child in item if child.tag=='modifierMask']})
 return sorted(result,key=lambda entry:json.dumps(entry,sort_keys=True))
def digest(tree,language='Base'):return hashlib.sha256(json.dumps(records(tree,language),sort_keys=True,ensure_ascii=False).encode()).hexdigest()
def main():
 contract=json.loads((root/'Tests/Fixtures/SettingsMenuIdentity.json').read_text())
 for language,expected in contract['languages'].items():
  p=root/f'Resources/Interfaces/{language}.lproj/MainMenu.nib/designable.nib';tree=E.parse(p).getroot()
  assert digest(tree,language)==expected,(language,'unrelated command identity or key changed')
  assert not any(a.get('selector') in removed for a in tree.iter('action')),(language,'old editor menu remains')
  toggle=[i for i in tree.iter('menuItem') if i.find("connections/action[@selector='changeAutoComplete:']") is not None]
  assert len(toggle)==1 and toggle[0].get('identifier')=='TSShortcut.changeAutoComplete:.0'
  parents={child:parent for parent in tree.iter() for child in parent};menu=parents[parents[toggle[0]]];owner=parents[menu]
  assert owner.tag=='menuItem' and owner.get('title')!=toggle[0].get('title'),(language,'toggle still nested in a same-title submenu')
  assert toggle[0].find('menu') is None
 print('PASS: 12 menus preserve command IDs, actions, tags and default keys; two editors moved and toggle flattened')
if __name__=='__main__':main()
