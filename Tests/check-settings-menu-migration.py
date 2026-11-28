#!/usr/bin/env python3
"""Verify stable command identity against the fixed pre-migration menu contract."""
from pathlib import Path
import hashlib,json,xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
removed={'openAutoCompletionListEditor:','openCommandCompletionList:'}
# Window > Fullscreen (Old Method) left the menu in 6.00; Enter Full Screen is the macOS item. Help > Short Course
# Supplements --> Desktop left too: it copied the samples of the 4th edition next to the 5th edition of the Short Course.
# Help > TeXShop Feature Confusion left as well: its comparison of key bindings, macros and command completion is a section
# of the Command Completion page of TeXShop Help.
# Source > Font kept only Show Fonts, Bigger and Smaller in 6.00: Bold, Italic, Kern, Ligatures, Baseline, Copy Style and
# Paste Style change the style of rich text, and the source is plain text. Keys set for them earlier reach nothing.
# The contract keeps them as they were in every language (identifier, tag, key and modifiers).
def former_font_item(selector,tag='0',key='',mask=({'key':'keyEquivalentModifierMask'},)):
 return {'identifier':f'TSShortcut.{selector}.{tag}','selector':selector,'tag':tag,'key':key,'mask':list(mask)}
font_styles=[former_font_item('addFontTrait:','2'),former_font_item('addFontTrait:','1'),
             *[former_font_item(s) for s in ('useStandardKerning:','turnOffKerning:','tightenKerning:','loosenKerning:','useStandardLigatures:',
                                            'turnOffLigatures:','useAllLigatures:','unscript:','superscript:','subscript:')],
             former_font_item('raiseBaseline:',key='5',mask=()),former_font_item('lowerBaseline:',key='6',mask=()),
             former_font_item('copyFont:',key='c',mask=({'command':'YES','key':'keyEquivalentModifierMask','option':'YES'},)),
             former_font_item('pasteFont:',key='v',mask=({'command':'YES','key':'keyEquivalentModifierMask','option':'YES'},))]
retired={'fullscreen:','supplementsToDesktop:','displayTeXShopConfusion:'}
font_style_selectors={entry['selector'] for entry in font_styles}
# Commands added to the Edit menu later (Copy with Style in 6.00 beta 8), and Source > Show Status Bar and
# Source > Highlight Index Entries (6.00), and the symbol tables of George Grätzer's Short Course, which joined its
# Help submenu in 6.00, and Help > Command Completion Quick Start (6.00 RC4); they are outside the fixed contract.
added={'displayHG:','displayBinary:','displayMoreBinary:','displayNegatedBinary:','displayBinaryOperations:','displayArrows:','displayMiscSymbols:',
       'displayDelimiters:','displayOperators:','displayLargeOperators:','displayMathAccents:','displayMathSpacing:','displayEuropean:',
       'displayTextAccents:','displayTextSizes:','displayTextSymbols:','displayTextSpacing:','convertCharacterType:','normalizeSelectedString:','exchangePaste:','toggleStatusBar:','toggleIndexColor:',
       'copyWithLightTheme:','copyWithLightThemeAndBackground:','copyWithDarkTheme:','copyWithDarkThemeAndBackground:',
       'displayCommandCompletionQuickStart:'}
# Fit to Content Width (tag 6 of the magnifications) and the zooms to the content width joined Preview > Magnification in 6.00.
added_items={('zoomToContentWidth:','0'),('zoomToContent:','0'),('changePDFViewSize:','6')}
# Find and Replace… joined the Find submenu of the other languages in 6.00; the Base menu always had it.
added_outside_base={'performTextFinderAction:'}
# Change Encoding joined Edit > Transformations of the Base menu in 6.00; the other languages always had it.
added_to_base={'changeEncoding:'}
# Window > Enter Full Screen has no key in the nibs since 6.00: TeXShop gives it Globe-F at launch, which a nib cannot
# give, and Control-Command-F, which it shared with Next Mark, is Next Mark's alone. The contract keeps its former key.
globe={'toggleFullScreen:':('f',[{'key':'keyEquivalentModifierMask','control':'YES','command':'YES'}])}
# The Korean Show Annotation Toolbar and the Portuguese (Brazil) Check Grammar With Spelling had Command-V, the key
# of Paste, since 5.58 (check-menu-key-collisions.py). The Portuguese (Brazil) Indent and Unindent had Command-] and
# Command-[, which no other language gives them; 6.00 removed them so that the menu matches the Base one. Without
# these keys the items keep their place in the contract.
stale={('ko','displayChoicesPanel:','0'):'v',('pt','toggleGrammarChecking:','0'):'v',('pt','doCommentOrIndent:','3'):']',('pt','doCommentOrIndent:','4'):'['}
def records(tree,language='Base'):
 result=[]
 skipped=added|(added_outside_base if language!='Base' else added_to_base)
 for item in tree.iter('menuItem'):
  action=item.find('connections/action')
  if action is None or action.get('selector') in removed|retired|skipped|font_style_selectors or (action.get('selector'),item.get('tag','0')) in added_items:continue
  key=item.get('keyEquivalent','')
  mask=[child.attrib for child in item if child.tag=='modifierMask']
  if action.get('selector') in globe:
   assert key=='' and mask==[],(language,action.get('selector'),'key',key,mask)
   key,mask=globe[action.get('selector')]
  former=stale.get((language,action.get('selector'),item.get('tag','0')))
  if former is not None:
   assert key in ('',former),(language,action.get('selector'),'key',key)
   key,mask=former,[]
  result.append({'identifier':item.get('identifier'),'selector':action.get('selector'),'tag':item.get('tag','0'),'key':key,'mask':mask})
 result+=font_styles
 return sorted(result,key=lambda entry:json.dumps(entry,sort_keys=True))
def digest(tree,language='Base'):return hashlib.sha256(json.dumps(records(tree,language),sort_keys=True,ensure_ascii=False).encode()).hexdigest()
def main():
 contract=json.loads((root/'Tests/Fixtures/SettingsMenuIdentity.json').read_text())
 for language,expected in contract['languages'].items():
  p=root/f'Resources/Interfaces/{language}.lproj/MainMenu.nib/designable.nib';tree=E.parse(p).getroot()
  assert digest(tree,language)==expected,(language,'unrelated command identity or key changed')
  encoding=[i for i in tree.iter('menuItem') if i.find("connections/action[@selector='changeEncoding:']") is not None]
  assert len(encoding)==1 and encoding[0].get('identifier')=='TSShortcut.changeEncoding:.0',(language,'one Change Encoding item')
  assert not encoding[0].get('keyEquivalent'),(language,'Change Encoding has no default key')
  siblings=[item for item in tree.iter('items') if encoding[0] in list(item)][0]
  assert list(siblings)[0] is encoding[0] and siblings.find("menuItem/connections/action[@selector='uppercaseWord:']") is not None,(language,'Change Encoding opens Edit > Transformations')
  assert not any(a.get('selector') in removed for a in tree.iter('action')),(language,'old editor menu remains')
  assert not any(a.get('selector') in retired|font_style_selectors for a in tree.iter('action')),(language,'Fullscreen (Old Method), Short Course Supplements, TeXShop Feature Confusion or a font style item remains')
  fonts=[m for m in tree.iter('menu') if m.get('systemMenu')=='font']
  assert len(fonts)==1 and [(i.find('connections/action').get('selector'),i.get('tag','0')) if i.find('connections/action') is not None else i.get('isSeparatorItem')
                            for i in fonts[0].find('items')]==[('orderFrontFontPanel:','0'),'YES',('modifyFont:','3'),('modifyFont:','4')],(language,'Source > Font has Show Fonts, Bigger and Smaller')
  if language!='de':
   indents={i.get('tag'):i.get('keyEquivalent','') for i in tree.iter('menuItem') if i.find("connections/action[@selector='doCommentOrIndent:']") is not None}
   assert indents=={'1':'{','2':'}','3':'','4':''},(language,'Comment, Uncomment, Indent and Unindent keys as in the Base menu',indents)
  grammar=[i for i in tree.iter('menuItem') if i.find("connections/action[@selector='toggleGrammarChecking:']") is not None]
  assert len(grammar)==1 and not grammar[0].get('keyEquivalent'),(language,'Check Grammar With Spelling has no key')
  toggle=[i for i in tree.iter('menuItem') if i.find("connections/action[@selector='changeAutoComplete:']") is not None]
  assert len(toggle)==1 and toggle[0].get('identifier')=='TSShortcut.changeAutoComplete:.0'
  parents={child:parent for parent in tree.iter() for child in parent};menu=parents[parents[toggle[0]]];owner=parents[menu]
  assert owner.tag=='menuItem' and owner.get('title')!=toggle[0].get('title'),(language,'toggle still nested in a same-title submenu')
  assert toggle[0].find('menu') is None
 print('PASS: 12 menus preserve command IDs, actions, tags and default keys; two editors moved and toggle flattened; Source > Font has Show Fonts, Bigger and Smaller only')
if __name__=='__main__':main()
