#!/usr/bin/env python3
"""Compare resource-based search with independently collected localized controls."""
from pathlib import Path
import argparse,json,subprocess,tempfile
from pane_fixtures import bundles,sources
from encoding_menu_fixture import encoding_menu_fixture
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--app',type=Path);p.add_argument('--language');args=p.parse_args()
s=(r/'Sources/TSPreferences.m').read_text()
def method(name):
 start=s.index("\n"+name)+1;end=s.index('\n}',start)+2;return s[start:end]
methods='\n'.join(method(n) for n in ['- (void)setSettingsControl:','- (void)updateSettingsDependenciesFromDefaults:','- (void)updateSpellingControlsFromDefaults:','- (IBAction)texAwareSpellCheckPressed:','- (IBAction)legacySpellCheckPressed:', '- (IBAction)editKeyBindings:', '- (IBAction)displayCommentLines:', *['- (IBAction)'+name+':' for name in ['blockCursorPressed','colorMapChanged','sourceAndPreviewInSameWindowChanged','autoSaveEnabledPressed','syntaxColorPressed','makeatletterChanged','expl3SyntaxColorPressed','parensMatchPressed','spellCheckPressed','autoCompletePressed','bibDeskCompletePressed','selectActivatePressed','lineNumberButtonPressed','midEastButtonPressed','tagMenuButtonPressed','spellCorrectPressed','editorAddBracketsPressed','spellCheckCommandPressed','spellCheckParameterPressed','spellCheckCommentPressed']]])
g=(r/'Sources/globals.m').read_text(encoding='latin1');import re
names=sorted({'BlockCursorKey','PdfColorMapKey','SourceAndPreviewInSameWindowKey','AutoSaveEnabledKey'}|set(re.findall(r'\b[A-Za-z][A-Za-z0-9]*(?:Key|Notification)\b',methods))-{'NeedsForRecolorNotification'})
constants='BOOL editorCanAddBrackets;\n'+'\n'.join(re.search(r'^NSString \*'+k+r'\s*=.*?;',g,re.M)[0] for k in names if re.search(r'^NSString \*'+k+r'\s*=',g,re.M))
with tempfile.TemporaryDirectory(prefix='texshop-classification-') as temp:
 t=Path(temp);(t/'fixtures').mkdir()
 program=(r/'Tests/SettingsClassification.m').read_text().replace('#import <Cocoa/Cocoa.h>', '#import <Cocoa/Cocoa.h>\n#import \"TSSettingsSearch.h\"').replace('int main(int argc,char **argv)', encoding_menu_fixture(r)+(r/'Tests/SettingsSearchCoverage.inc').read_text()+'\nint main(int argc,char **argv)').replace(' NSMutableDictionary *after=[NSMutableDictionary dictionary];',' for(NSString *name in @[@"documentFontTextField",@"consoleFontTextField",@"DarkStyle",@"EditingStyle",@"LiteStyle"]) { NSView *value=[owner valueForKey:name]; Check(value!=nil && [value.accessibilityIdentifier isEqual:@"settings.user-data"],@"Dynamic values identified through actual preference outlets"); } NSPopUpButton *enc=[owner valueForKey:@"defaultEncodeMatrix"]; Check(enc!=nil,@"Encoding popup outlet"); [[[EncodingMenuFixture alloc] init] addEncodingsToMenu:Required(enc.menu) withTarget:nil action:NULL]; Check(enc.numberOfItems>=31,@"Actual encoding menu populated"); NSPopUpButton *dictionary=[owner valueForKey:@"dictionaryPopup"]; Check(dictionary!=nil,@"Dictionary popup outlet"); // DICTIONARY_POPULATION\n SearchCoverage(panes,bundle);return 0;\n NSMutableDictionary *after=[NSMutableDictionary dictionary];').replace('// CONSTANTS',constants).replace('// DEPENDENCIES',methods).replace('// DICTIONARY_POPULATION', re.search(r'\[dictionaryPopup addItemWithTitle:.*?;', s)[0].replace('dictionaryPopup','dictionary'))
 (t/'test.m').write_text(program)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Werror','-Wno-deprecated-declarations','-Wnullability-completeness','-Wnullable-to-nonnull-conversion','-Wunguarded-availability-new','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-I',str(r/'Tests'),'-framework','Cocoa',str(t/'test.m'),*map(str,sources(r)),str(r/'Sources/TSPreferences+Panes.m'),str(r/'Sources/TSSettingsCategory.m'),str(r/'Sources/TSSettingsSearch.m'),str(r/'Sources/TSDockIconController.m'),'-o',str(t/'probe')],check=True)
 from settings_contract import expand
 expected=expand(json.loads((r/'Tests/Fixtures/SettingsClassificationStrings.json').read_text()))
 for bundle in bundles(r,t/'fixtures',product=args.app,dock=True):
  lang=bundle.stem
  if args.language and lang!=args.language:continue
  loc=r/'Resources/Interfaces'/('en.lproj' if lang=='Base' else lang+'.lproj');f=loc/'Localizable.strings'
  actual=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(f)]))
  assert all(actual.get(k)==v for k,v in expected[lang].items()),lang
  # This named confirmation deliberately uses English fallback outside Japanese.
  for key,ja in [('Replace','置き換える'),('The theme “%@” already exists. Replace it?','テーマ「%@」はすでにあります。置き換えますか？')]:
   if lang=='ja':assert actual.get(key)==ja,(lang,key,actual.get(key))
   else:assert actual.get(key,key)==key,(lang,key)
  import shutil
  dest=bundle/'Contents/Resources'/('en.lproj' if lang=='Base' else lang+'.lproj');dest.mkdir(exist_ok=True);shutil.copy2(f,dest/'Localizable.strings')
  enc=(args.app/'Contents/Resources'/loc.name if args.app else loc)/'Encodings.strings'
  if not enc.exists(): enc=(args.app/'Contents/Resources/en.lproj' if args.app else r/'Resources/Interfaces/en.lproj')/'Encodings.strings'
  shutil.copy2(enc,dest/'Encodings.strings')
  if args.app:
   built=args.app/'Contents/Resources'/loc.name/'Localizable.strings';assert json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(built)]))==actual
  print('CHECK',lang,flush=True);subprocess.run([str(t/'probe'),str(bundle),str(r/'Tests/Fixtures/SettingsCategoryGroups.json')],check=True,timeout=90)
