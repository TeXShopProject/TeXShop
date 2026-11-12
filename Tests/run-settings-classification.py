#!/usr/bin/env python3
"""Exercise final categories, original controls and dependencies without showing a window."""
from pathlib import Path
import argparse,json,subprocess,tempfile
from pane_fixtures import bundles,sources
from encoding_menu_fixture import encoding_menu_fixture
from source_tree import include_args, source_file
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--app',type=Path);p.add_argument('--language');p.add_argument('--snapshots',type=Path);p.add_argument('--search-coverage',action='store_true');p.add_argument('--mutations',action='store_true');p.add_argument('--search-catalog',type=Path);p.add_argument('--search-source',type=Path);args=p.parse_args()
with tempfile.TemporaryDirectory(prefix='texshop-classification-') as temp:
 t=Path(temp);(t/'fixtures').mkdir()
 program=(r/'Tests/SettingsClassification.m').read_text().replace('int main(int argc,char **argv)', encoding_menu_fixture(r)+'\nint main(int argc,char **argv)').replace('// SNAPSHOT_ENCODING', 'if(argc>3) { NSPopUpButton *encoding=[owner valueForKey:@"defaultEncodeMatrix"]; [[[EncodingMenuFixture alloc] init] addEncodingsToMenu:encoding.menu withTarget:nil action:NULL]; [encoding selectItemWithTag:NSUTF8StringEncoding]; }')
 if args.search_coverage:
  program=program.replace('#import <Cocoa/Cocoa.h>','#import <Cocoa/Cocoa.h>\n#import "TSSettingsSearch.h"')
  program=program.replace('int main(int argc,char **argv)',(r/'Tests/SettingsSearchCoverage.inc').read_text()+'\nint main(int argc,char **argv)')
  program=program.replace(' NSMutableDictionary *after=[NSMutableDictionary dictionary];',''' for(NSString *name in @[@"documentFontTextField",@"consoleFontTextField",@"DarkStyle",@"EditingStyle",@"LiteStyle"]) { NSView *value=[owner valueForKey:name]; Check(value!=nil && [value.accessibilityIdentifier isEqual:@"settings.user-data"],@"Dynamic values identified through actual preference outlets"); }
 NSPopUpButton *enc=[owner valueForKey:@"defaultEncodeMatrix"]; [[[EncodingMenuFixture alloc] init] addEncodingsToMenu:Required(enc.menu) withTarget:nil action:NULL]; Check(enc.numberOfItems>=31,@"Actual encoding menu populated");
 NSPopUpButton *dictionary=[owner valueForKey:@"dictionaryPopup"];[dictionary addItemWithTitle:[bundle localizedStringForKey:@"Automatic Language" value:nil table:@"Localizable"]];
 SearchCoverage(panes,bundle);return 0;
 NSMutableDictionary *after=[NSMutableDictionary dictionary];''')
 (t/'test.m').write_text(program)
 extra=[r/'Sources/Settings/TSPreferences.m',r/'Sources/Settings/TSPreferences-Color.m',r/'Sources/Editor/TSColorSupport.m',r/'Sources/Settings/TSThemeFileStore.m',r/'Sources/App/globals.m',r/'Sources/Settings/TSPreferenceInput.m',r/'Tests/PreferencesTestServices.m',*sorted((r/'Sources').rglob('TSSettings*.m'))]
 compile_command=['xcrun','clang','-fobjc-arc','-F',str(r/'Frameworks'),'-Wno-deprecated-declarations','-Wnullability-completeness','-Wnullable-to-nonnull-conversion','-Wunguarded-availability-new','-mmacosx-version-min=14.6',*include_args(r),'-I',str(r/'Tests'),'-framework','Cocoa',str(t/'test.m'),*map(str,sources(r)),str(r/'Sources/Settings/TSPreferences+Panes.m'),*map(str,extra),str(r/'Sources/App/TSDockIconController.m'),'-o',str(t/'probe')]
 if args.search_catalog or args.search_source:
  (t/'TSSettingsSearch.m').write_text((args.search_source or r/'Sources/Settings/TSSettingsSearch.m').read_text())
  (t/'TSSettingsSearchCatalog.inc').write_text((args.search_catalog or r/'Sources/Settings/TSSettingsSearchCatalog.inc').read_text())
  compile_command=[str(t/'TSSettingsSearch.m') if x==str(r/'Sources/Settings/TSSettingsSearch.m') else x for x in compile_command]
 subprocess.run(compile_command,check=True)
 from settings_contract import expand
 expected=expand(json.loads((r/'Tests/Fixtures/SettingsClassificationStrings.json').read_text()))
 for bundle in bundles(r,t/'fixtures',product=args.app,dock=True):
  lang=bundle.stem
  if args.language and lang!=args.language:continue
  loc=r/'Resources/Interfaces'/('en.lproj' if lang=='Base' else lang+'.lproj');f=loc/'Localizable.strings'
  actual=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(f)]))
  # Preview is a settings category label here, not the legacy menu lookup key.
  category_file=(args.app/'Contents/Resources' if args.app else r/'Resources/Interfaces')/(lang+'.lproj')/'SettingsCategories.strings'
  categories=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(category_file)]))
  assert categories['preview']==expected[lang]['Preview'],(lang,'Preview category')
  assert all(actual.get(k)==v for k,v in expected[lang].items() if k!='Preview'),lang
  # The named theme confirmation is translated in every language.
  for key,ja in [('Replace','置き換える'),('The theme “%@” already exists. Replace it?','テーマ「%@」はすでにあります。置き換えますか？')]:
   if lang=='ja':assert actual.get(key)==ja,(lang,key,actual.get(key))
   elif lang!='Base':assert actual.get(key) not in (None,key),(lang,key,'untranslated')
  import shutil
  dest=bundle/'Contents/Resources'/('en.lproj' if lang=='Base' else lang+'.lproj');dest.mkdir(exist_ok=True);shutil.copy2(f,dest/'Localizable.strings')
  if args.app:
   built=args.app/'Contents/Resources'/loc.name/'Localizable.strings';assert json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(built)]))==actual
  print('CHECK',lang,flush=True)
  encoding=r/'Resources/Interfaces'/loc.name/'Encodings.strings'
  if not encoding.exists(): encoding=r/'Resources/Interfaces/en.lproj/Encodings.strings'
  shutil.copy2(encoding,dest/'Encodings.strings')
  command=[str(t/'probe'),str(bundle),str(r/'Tests/Fixtures/SettingsCategoryGroups.json')]
  if args.snapshots:
   folder=args.snapshots/lang;folder.mkdir(parents=True,exist_ok=True);command.append(str(folder))
  subprocess.run(command,check=True,timeout=90)

  if args.mutations:
   cases=[
    ('cursor-RGB','TSPreferences.m','[((NSColorWell *)sender).color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]','((NSColorWell *)sender).color'),
    ('theme-RGB','TSColorSupport.m','[((NSColorWell *)theWell).color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]','((NSColorWell *)theWell).color'),
    ('unread-theme','TSPreferences-Color.m','[self setAllThemeEditingEnabled:(EditingColors != nil)];',';'),
    ('PDF-position','TSPreferences.m','[_pdfWindowPosMatrix selectCellWithTag:PdfWindowPosFixed];','[_sourceWindowPosMatrix selectCellWithTag:PdfWindowPosFixed];'),
    ('expl3-notification','TSPreferenceEffects.h','MakeatletterEnabledKey, expl3SyntaxColoringKey, ShowInvisibleCharactersEnabledKey','MakeatletterEnabledKey, ShowInvisibleCharactersEnabledKey'),
    ('invisible-notification','TSPreferenceEffects.h','expl3SyntaxColoringKey, ShowInvisibleCharactersEnabledKey, showSpaceCharacterKey','expl3SyntaxColoringKey, showSpaceCharacterKey'),
   ]
   for name,filename,old,new in cases:
    # Whole translation units, including their shared notification header.
    for copied in ['TSPreferences.m','TSPreferenceEffects.h']:(t/copied).write_text((source_file(r, copied)).read_text())
    original=(source_file(r, filename)).read_text();assert original.count(old)==1,(name,original.count(old));(t/filename).write_text(original.replace(old,new))
    cmd=[str(t/'TSPreferences.m') if x==str(r/'Sources/Settings/TSPreferences.m') else str(t/filename) if x==str(source_file(r, filename)) else x for x in compile_command]
    subprocess.run(cmd,check=True)
    result=subprocess.run(command,capture_output=True,text=True,timeout=90)
    failure={'cursor-RGB':'Cursor action stores converted RGB from its sender','theme-RGB':'Theme wells store converted RGBA','unread-theme':'Unreadable theme disables offscreen color wells','PDF-position':'Saving PDF position preserves source selection and value','expl3-notification':'Individual action sends exactly the approved runtime notification','invisible-notification':'Invisible-character default requests recoloring'}[name]
    assert result.returncode and 'FAIL: '+failure in result.stderr,(name,result.stdout,result.stderr)
    print('DETECTED',name,result.stderr[-1200:],flush=True)
   subprocess.run(compile_command,check=True);subprocess.run(command,check=True,timeout=90);print('NORMAL CONTROL',lang,flush=True)
